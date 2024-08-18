#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38

layout(set = 0, binding = 0) uniform sampler2D tile_max_sampler;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D buffer_a;
layout(rgba16f, set = 0, binding = 2) uniform writeonly image2D buffer_b;
layout(set = 0, binding = 3) uniform sampler2D buffer_a_sampler;
layout(set = 0, binding = 4) uniform sampler2D buffer_b_sampler;

layout(set = 0, binding = 5, std430) restrict buffer MyDataBuffer {
    int iteration_index;
}
iteration_data;

layout(push_constant, std430) uniform Params 
{
	int nan0;//iteration_index;
	int last_iteration_index;
	int nan1;
	int nan2;	
	float perpen_error_thresh;
	float sample_step_multiplier;
	float motion_blur_intensity;
	float nan_fl_5;
	float nan_fl_4;
	float nan_fl_3;
	float nan_fl_6;
	float step_exponent_modifier;
	float nan_fl_0;//step_size;
	float max_dilation_radius;
	float nan_fl_1;
	float nan_fl_2;
} params;

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

const int kernel_size = 8;

const vec2 check_step_kernel[kernel_size] = {
	vec2(-1, 0),
	vec2(1, 0),
	vec2(0, -1),
	vec2(0, 1),
	vec2(-1, 1),
	vec2(1, -1),
	vec2(1, 1),
	vec2(-1, -1),
};

vec2 get_value(bool a, vec2 uv)
{
	if(a)
	{
		return textureLod(buffer_a_sampler, uv, 0.0).xy;
	}
	else
	{
		return textureLod(buffer_b_sampler, uv, 0.0).xy;
	}
}

void set_value(bool a, ivec2 uvi, vec4 value)
{
	if(a)
	{
		imageStore(buffer_a, uvi, value);
	}
	else
	{
		imageStore(buffer_b, uvi, value);
	}
}

void sample_fitness(vec2 uv_offset, vec4 uv_sample, vec2 render_size, inout vec4 current_sample_fitness)
{
	vec2 sample_velocity = -uv_sample.xy;

//	if (dot(sample_velocity, sample_velocity) <= FLT_MIN || uv_sample.w == 0)
//	{
//		current_sample_fitness = vec4(10, 10, 0, 0);
//		return;
//	}

	float velocity_space_distance = dot(sample_velocity, uv_offset) / dot(sample_velocity, sample_velocity);

	float mid_point = params.motion_blur_intensity / 2 + 1e-5;

	float absolute_velocity_space_distance = abs(velocity_space_distance - mid_point);

	float within_velocity_range = step(absolute_velocity_space_distance, mid_point);

	float side_offset = abs(dot(vec2(uv_offset.y, -uv_offset.x), sample_velocity)) / dot(sample_velocity, sample_velocity);

	float within_perpen_error_range = step(side_offset, params.perpen_error_thresh * params.motion_blur_intensity);

	current_sample_fitness = vec4(/*max(absolute_velocity_space_distance, side_offset)*/absolute_velocity_space_distance, velocity_space_distance, uv_sample.w + uv_sample.z * velocity_space_distance, within_velocity_range * within_perpen_error_range);
}

//float is_sample_better(vec4 a, vec4 b)
//{
//	return 1. - step(b.x * a.w, a.x * b.w);//mix(1. - step(b.x * a.w, a.x * b.w), step(b.z, a.z), step(0.5, b.w) * step(0.5, a.w));
//}

//vec4 backtrack_sample(vec2 chosen_uv, vec4 best_sample_fitness)
//{
//	vec4 velocity = textureLod(tile_max_sampler, chosen_uv, 0.0);
//	
//	vec2 uv_candidate = chosen_uv + velocity.xy;
//
//	vec4 velocity_candidate = textureLod(tile_max_sampler, uv_candidate, 0.0);
//
//	if((dot(velocity, velocity_candidate) / dot(velocity, velocity)) > 0.5 && velocity_candidate.w > 0)
//	{
//		return vec4(uv_candidate, 0, 0);
//	}
//	else
//	{
//		return vec4(chosen_uv, 0, 0);
//	}
//}

void main() 
{
	ivec2 render_size = ivec2(textureSize(tile_max_sampler, 0));
	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);
	if ((uvi.x >= render_size.x) || (uvi.y >= render_size.y)) 
	{
		return;
	}

	vec2 uvn = (vec2(uvi) + vec2(0.5)) / render_size;

	vec2 step_size = vec2(round(pow(2 + params.step_exponent_modifier, params.last_iteration_index - iteration_data.iteration_index)));

	vec2 uv_step = vec2(round(step_size)) / render_size;

	vec4 best_sample_fitness = vec4(10, 10, 0, 0);
	
	vec2 chosen_uv = uvn;

	bool set_a = !bool(step(0.5, float(iteration_data.iteration_index % 2)));

	iteration_data.iteration_index += 1;

	vec2 step_offset;

	vec2 check_uv;

	vec4 uv_sample;

	vec4 current_sample_fitness;

	for(int i = 0; i < kernel_size; i++)
	{
		step_offset = check_step_kernel[i] * uv_step;
		check_uv = uvn + step_offset;
			
		if(any(notEqual(check_uv, clamp(check_uv, vec2(0.0), vec2(1.0)))))
		{
			continue;
		}

//		if(iteration_data.iteration_index > 0)
//		{		
			check_uv = get_value(!set_a, check_uv).xy;

			step_offset = check_uv - uvn;
//		}

		uv_sample = textureLod(tile_max_sampler, check_uv, 0.0);
		
		sample_fitness(step_offset, uv_sample, render_size, current_sample_fitness);

		float sample_better = 1. - step(current_sample_fitness.z * current_sample_fitness.w, best_sample_fitness.z * best_sample_fitness.w);
		best_sample_fitness = mix(best_sample_fitness, current_sample_fitness, sample_better);
		chosen_uv = mix(chosen_uv, check_uv, sample_better);
	}

//	if(params.iteration_index < params.last_iteration_index)
//	{
//		set_value(set_a, uvi, vec4(chosen_uv, 0, 0));
//		return;
//	}
//	
//	float depth = textureLod(tile_max_sampler, uvn, 0.0).w;
//
//	if(params.iteration_index == params.last_iteration_index && (best_sample_fitness.w < 0.5 || depth > best_sample_fitness.z))
//	{
//		set_value(set_a, uvi, vec4(uvn, 0, 0));
//		return;
//	}

	set_value(set_a, uvi, vec4(chosen_uv, 0, 0));
	
//	vec4 backtracked_sample = backtrack_sample(chosen_uv, best_sample_fitness);
//
//	set_value(set_a, uvi, backtracked_sample);
}