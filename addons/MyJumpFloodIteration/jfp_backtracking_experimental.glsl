#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38
#define DBL_MAX 1.7976931348623158e+308
#define DBL_MIN 2.2250738585072014e-308

layout(set = 0, binding = 0) uniform sampler2D depth_sampler;
layout(set = 0, binding = 1) uniform sampler2D velocity_sampler;
layout(rgba16f, set = 0, binding = 2) uniform image2D buffer_a;
layout(rgba16f, set = 0, binding = 3) uniform image2D buffer_b;

layout(push_constant, std430) uniform Params 
{
	int iteration_index;
	int last_iteration_index;
	int nan1;
	int nan2;	
	float perpen_error_thresh;
	float sample_step_multiplier;
	float motion_blur_intensity;
	float velocity_match_threshold;
	float parallel_sensitivity;
	float perpendicular_sensitivity;
	float depth_match_threshold;
	float nan4;
} params;

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

const int kernel_size = 9;//8;//

const vec2 check_step_kernel[kernel_size] = {
	vec2(0, 0),
	vec2(1, 1),
	vec2(0, 1),
	vec2(-1, 1),
	vec2(1, 0),
	vec2(1, -1),
	vec2(-1, 0),
	vec2(-1, -1),
	vec2(0, -1),
};

// near plane distance
float npd = 0.05;

vec4 get_value(bool a, ivec2 uvi, ivec2 render_size)
{
	if ((uvi.x >= render_size.x) || (uvi.x < 0)  || (uvi.y >= render_size.y) || (uvi.y < 0)) 
	{
		return vec4(-1, -1, 0, 1);
	}

	if(a)
	{
		return imageLoad(buffer_a, uvi);
	}

	return imageLoad(buffer_b, uvi);
}

void set_value(bool a, ivec2 uvi, vec4 value, ivec2 render_size)
{
	if ((uvi.x >= render_size.x) || (uvi.x < 0)  || (uvi.y >= render_size.y) || (uvi.y < 0)) 
	{
		return;
	}
	if(a)
	{
		imageStore(buffer_a, uvi, value);
		return;
	}

	imageStore(buffer_b, uvi, value);
}

// Motion similarity 
// ----------------------------------------------------------
float get_motion_difference(vec2 V, vec2 V2, float parallel_sensitivity, float perpendicular_sensitivity)
{
	vec2 VO = V - V2;
	double parallel = abs(dot(VO, V) / max(DBL_MIN, dot(V, V)));
	vec2 perpen_V = vec2(V.y, -V.x);
	double perpendicular = abs(dot(VO, perpen_V) / max(DBL_MIN, dot(V, V)));
	float difference = float(parallel) * parallel_sensitivity + float(perpendicular) * perpendicular_sensitivity;
	return clamp(difference, 0, 1);
}
// ----------------------------------------------------------

vec4 sample_fitness(vec2 uv_offset, vec4 uv_sample)
{
	vec2 sample_velocity = -uv_sample.xy;
	
	if (dot(sample_velocity, sample_velocity) <= FLT_MIN)
	{
		return vec4(FLT_MAX, FLT_MAX, FLT_MAX, 0);
	}

//	if(dot(uv_offset, uv_offset) <= FLT_MIN)
//	{
//		uv_offset = normalize(sample_velocity) * FLT_MIN;
//	}

	double velocity_space_distance = dot(sample_velocity, uv_offset) / max(FLT_MIN, dot(sample_velocity, sample_velocity));

	double mid_point = params.motion_blur_intensity / 2;

	double absolute_velocity_space_distance = abs(velocity_space_distance - mid_point);

	double within_velocity_range = step(absolute_velocity_space_distance, mid_point);
	
	vec2 perpen_offset = vec2(uv_offset.y, -uv_offset.x);

	double side_offset = abs(dot(perpen_offset, sample_velocity)) / max(FLT_MIN, dot(sample_velocity, sample_velocity));
	
	double within_perpen_error_range = step(side_offset, params.perpen_error_thresh * params.motion_blur_intensity);

	return vec4(absolute_velocity_space_distance, velocity_space_distance, uv_sample.z, within_velocity_range * within_perpen_error_range);
}

bool is_sample_better(vec4 a, vec4 b)
{
	if((a.w == b.w) && (a.w == 1))
	{
		return a.z < b.z;
	}

	float nearer = a.z > b.z ? 1 : 0;

	return a.x * b.w * nearer < b.x * a.w;
}

vec4 get_backtracked_sample(vec2 uvn, vec2 chosen_uv, vec2 chosen_velocity, vec4 best_sample_fitness, vec2 render_size)
{
	//return vec4(chosen_uv, best_sample_fitness.x, 0);// comment this to enable backtracking
	
	int step_count = 16;

	float smallest_step = 1 / max(render_size.x, render_size.y);

	float max_dilation_radius = pow(2, params.last_iteration_index) * params.sample_step_multiplier * smallest_step / (length(chosen_velocity) * params.motion_blur_intensity);

	float general_velocity_multiplier = min(best_sample_fitness.y, max_dilation_radius);

	vec2 best_uv = chosen_uv;

	float best_velocity_match_threshold = params.velocity_match_threshold;

	int initial_steps_to_compare = 2;

	int steps_to_compare = initial_steps_to_compare;

	for(int i = -step_count; i < step_count + 1; i++)
	{
		float velocity_multiplier = general_velocity_multiplier * (1 + float(i) /  float(step_count));

		if(velocity_multiplier > params.motion_blur_intensity + 0.2 || velocity_multiplier < FLT_MIN)
		{
			continue;
		}

		vec2 new_sample = round((uvn - chosen_velocity * velocity_multiplier) * render_size) / render_size;

		if((new_sample.x < 0.) || (new_sample.x > 1.) || (new_sample.y < 0.) || (new_sample.y > 1.))
		{
			continue;
		}

		vec2 velocity_test = textureLod(velocity_sampler, new_sample, 0.0).xy;
		
		float depth_test = textureLod(depth_sampler, new_sample, 0.0).x;

		float velocity_match = get_motion_difference(chosen_velocity, velocity_test, params.parallel_sensitivity, params.perpendicular_sensitivity);

		if((abs(depth_test - npd / best_sample_fitness.z) < params.depth_match_threshold) && (velocity_match <= best_velocity_match_threshold))
		{
			best_uv = new_sample;
			if(steps_to_compare == 0)
			{
				chosen_uv = best_uv;
				best_velocity_match_threshold = velocity_match;
				return vec4(chosen_uv, 0, 0);
			}
			steps_to_compare--;
		}
		else if(initial_steps_to_compare > steps_to_compare)
		{
			chosen_uv = best_uv;
			return vec4(chosen_uv, 0, 0);
		}
	}
	
	return vec4(uvn, best_sample_fitness.x, 1);
}

void main() 
{
	ivec2 render_size = ivec2(textureSize(velocity_sampler, 0));
	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);
	if ((uvi.x >= render_size.x) || (uvi.y >= render_size.y)) 
	{
		return;
	}
	vec2 uvn = (vec2(uvi)) / render_size;

	int iteration_index = params.iteration_index;

	float step_size = round(pow(2, params.last_iteration_index - iteration_index));

	vec2 uv_step = vec2(step_size) * params.sample_step_multiplier / render_size;

	vec4 best_sample_fitness = vec4(FLT_MAX, FLT_MAX, FLT_MAX, 0);
	
	vec2 chosen_uv = uvn;
	
	vec2 chosen_velocity = vec2(0);

	bool set_a = !bool(step(0.5, float(iteration_index % 2)));

	for(int i = 0; i < kernel_size; i++)
	{
		if((true || params.iteration_index == 0) && i == 0)
		{
			continue;
		}

		vec2 step_offset = check_step_kernel[i] * uv_step;
		vec2 check_uv = uvn + step_offset;
			
		if((check_uv.x < 0.) || (check_uv.x > 1.) || (check_uv.y < 0.) || (check_uv.y > 1.))
		{
			continue;
		}

		if(iteration_index > 0)
		{
			ivec2 check_uv2 = ivec2(check_uv * render_size);
		
			vec4 buffer_load = get_value(!set_a, check_uv2, render_size);

			check_uv = buffer_load.xy;

			step_offset = check_uv - uvn;
		}

		vec4 uv_sample = vec4(textureLod(velocity_sampler, check_uv, 0.0).xy, npd / textureLod(depth_sampler, check_uv, 0.0).x, 0);
			
		vec4 current_sample_fitness = sample_fitness(step_offset, uv_sample);
			
		if (is_sample_better(current_sample_fitness, best_sample_fitness))
		{
			best_sample_fitness = current_sample_fitness;
			chosen_uv = check_uv;
			chosen_velocity = uv_sample.xy;
		}
	}
	
	if(iteration_index < params.last_iteration_index)
	{
		set_value(set_a, uvi, vec4(chosen_uv, best_sample_fitness.x, best_sample_fitness.w), render_size);
		return;
	}

	float depth = npd / textureLod(depth_sampler, uvn, 0.0).x;

	if(best_sample_fitness.w == 0 || depth < best_sample_fitness.z)
	{
		set_value(set_a, uvi, vec4(uvn, best_sample_fitness.x, 0), render_size);
		return;
	}

	vec4 backtracked_sample = get_backtracked_sample(uvn, chosen_uv, chosen_velocity, best_sample_fitness, render_size);
	
	set_value(set_a, uvi, backtracked_sample, render_size);
	
	return;
}	