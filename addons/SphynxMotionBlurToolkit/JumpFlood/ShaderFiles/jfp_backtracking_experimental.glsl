#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38

layout(set = 0, binding = 0) uniform sampler2D depth_sampler;
layout(set = 0, binding = 1) uniform sampler2D velocity_sampler;
layout(rgba16f, set = 0, binding = 2) uniform writeonly image2D buffer_a;
layout(rgba16f, set = 0, binding = 3) uniform writeonly image2D buffer_b;
layout(set = 0, binding = 4) uniform sampler2D buffer_a_sampler;
layout(set = 0, binding = 5) uniform sampler2D buffer_b_sampler;

layout(push_constant, std430) uniform Params 
{
	int iteration_index;
	int last_iteration_index;
	int backtracking_sample_count;
	int nan2;	
	float perpen_error_thresh;
	float sample_step_multiplier;
	float motion_blur_intensity;
	float velocity_match_threshold;
	float parallel_sensitivity;
	float perpendicular_sensitivity;
	float depth_match_threshold;
	float step_exponent_modifier;
	float step_size;
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

void get_value(bool a,inout vec2 uv)
{
	if(a)
	{
		uv = textureLod(buffer_a_sampler, uv, 0.0).xy;
	}
	else
	{
		uv = textureLod(buffer_b_sampler, uv, 0.0).xy;
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

// Motion similarity 
// ----------------------------------------------------------
float get_motion_difference(vec2 V, vec2 V2)
{
	return clamp(dot(V - V2, V) / dot(V, V), 0, 1);
//	vec2 VO = V - V2;
//	float parallel = dot(VO, V) / dot(V, V);
//	return clamp(parallel, 0, 1);
}
// ----------------------------------------------------------

void sample_fitness(vec2 uv_offset, vec4 uv_sample, vec2 render_size, inout vec4 curren_sample_fitness)
{
	vec2 sample_velocity = -uv_sample.xy;

	// if velocity is 0, we never reach it (steps never smaller than 1)
	if (dot(sample_velocity, sample_velocity) <= FLT_MIN || uv_sample.w == 0)
	{
		curren_sample_fitness = vec4(FLT_MAX, FLT_MAX, FLT_MAX, 0);
		return;
	}

	// velocity space distance (projected pixel offset onto velocity vector)
	float velocity_space_distance = dot(sample_velocity, uv_offset) / dot(sample_velocity, sample_velocity);
	// the velcity space distance to gravitate the JFA to (found more relieable than doing a 0 - 1 range)
	float mid_point = params.motion_blur_intensity / 2;
	// centralize the velocity space distance around that mid point
	float absolute_velocity_space_distance = abs(velocity_space_distance - mid_point);
	// if that distance is half the original, its within range (we centered around a mid point)
	float within_velocity_range = step(absolute_velocity_space_distance, mid_point);
	// perpendicular offset
	float side_offset = abs(dot(vec2(uv_offset.y, -uv_offset.x), sample_velocity)) / dot(sample_velocity, sample_velocity);
	// arbitrary perpendicular limit (lower means tighter dilation, but less reliable)
	float within_perpen_error_range = step(side_offset, params.perpen_error_thresh * params.motion_blur_intensity);
	// store relevant data for use in conditions
	curren_sample_fitness = vec4(absolute_velocity_space_distance, velocity_space_distance, uv_sample.w + uv_sample.z * velocity_space_distance, within_velocity_range * within_perpen_error_range);
}

float is_sample_better(vec4 a, vec4 b)
{
	// see explanation at end of code
	return mix(1. - step(b.x * a.w, a.x * b.w), step(b.z, a.z), step(0.5, b.w) * step(0.5, a.w));
}

// dilation validation and better sample selection
vec4 get_backtracked_sample(vec2 uvn, vec2 chosen_uv, vec3 chosen_velocity, vec4 best_sample_fitness, vec2 render_size)
{
	//return vec4(chosen_uv, best_sample_fitness.z, best_sample_fitness.w);// comment this to enable backtracking

	float smallest_step = 1 / max(render_size.x, render_size.y);
	// choose maximum range to check along (matches with implementation in blur stage)
	float general_velocity_multiplier = min(best_sample_fitness.y, params.max_dilation_radius * smallest_step / (length(chosen_velocity) * params.motion_blur_intensity));

	vec2 best_uv = chosen_uv;

	float best_multiplier = best_sample_fitness.y;

	float best_depth = best_sample_fitness.z;

	// set temp variable to keet track of better matches
	float smallest_velocity_difference = 0.99;//params.velocity_match_threshold;
	// minimum amount of valid velocities to compare before decision
	int initial_steps_to_compare = 2;

	int steps_to_compare = initial_steps_to_compare;

	float velocity_multiplier;

	vec2 check_uv;

	vec3 velocity_test;

	float depth_test;

	float velocity_difference;

	float current_depth;

	for(int i = -params.backtracking_sample_count; i < params.backtracking_sample_count + 1; i++)
	{
		velocity_multiplier = general_velocity_multiplier * (1 + float(i) /  float(params.backtracking_sample_count));

		if(velocity_multiplier > params.motion_blur_intensity || velocity_multiplier < 0)
		{
			continue;
		}

		check_uv = uvn - chosen_velocity.xy * velocity_multiplier;

		if(any(notEqual(check_uv, clamp(check_uv, vec2(0.0), vec2(1.0)))))
		{
			continue;
		}
		// get potential velocity and depth matches
		velocity_test = textureLod(velocity_sampler, check_uv, 0.0).xyz;
		
		depth_test = textureLod(depth_sampler, check_uv, 0.0).x;

		velocity_difference = get_motion_difference(chosen_velocity.xy, velocity_test.xy);
		
		current_depth = depth_test + chosen_velocity.z * velocity_multiplier;
		
		// if checked sample matches depth and velocity, it is valid for backtracking
		if((abs(current_depth - best_sample_fitness.z) < 0.002) && (velocity_difference <= smallest_velocity_difference))
		{
			best_uv = check_uv;
			best_multiplier = velocity_multiplier;
			best_depth = current_depth;
			if(steps_to_compare == 0)
			{
				return vec4(best_uv, best_depth, 0);
			}
			steps_to_compare--;
		}
		// if a sample was found and we lost footing after, go with that found sample right away
		else if(initial_steps_to_compare > steps_to_compare)
		{
			return vec4(best_uv, best_depth, 0);
		}
	}

	return vec4(uvn, best_sample_fitness.z, 1);
}

void main() 
{
	ivec2 render_size = ivec2(textureSize(velocity_sampler, 0));
	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);
	if ((uvi.x >= render_size.x) || (uvi.y >= render_size.y)) 
	{
		return;
	}

	// must be on pixel center for whole values
	vec2 uvn = (vec2(uvi) + vec2(0.5)) / render_size;

	vec2 uv_step = vec2(round(params.step_size)) / render_size;

	vec4 best_sample_fitness = vec4(FLT_MAX, FLT_MAX, FLT_MAX, 0.);
	
	vec2 chosen_uv = uvn;
	
	vec3 chosen_velocity = vec3(0.);

	bool set_a = !bool(step(0.5, float(params.iteration_index % 2)));

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

		if(params.iteration_index > 0.)
		{		
			get_value(!set_a, check_uv);

			step_offset = check_uv - uvn;
		}

		uv_sample = vec4(textureLod(velocity_sampler, check_uv, 0.0).xyz, textureLod(depth_sampler, check_uv, 0.0).x);
		
		sample_fitness(step_offset, uv_sample, render_size, current_sample_fitness);

		if (mix(1. - step(best_sample_fitness.x * current_sample_fitness.w, current_sample_fitness.x * best_sample_fitness.w), step(best_sample_fitness.z, current_sample_fitness.z), step(0.5, best_sample_fitness.w) * step(0.5, current_sample_fitness.w)) > 0.5)//is_sample_better(current_sample_fitness, best_sample_fitness) > 0.5)
		{
			best_sample_fitness = current_sample_fitness;
			chosen_uv = check_uv;
			chosen_velocity = uv_sample.xyz;
		}
	}
	
	if(params.iteration_index < params.last_iteration_index)
	{
		set_value(set_a, uvi, vec4(chosen_uv, 0, 0));
		return;
	}

	float depth = textureLod(depth_sampler, uvn, 0.0).x;

	// best_sample_fitness.z contains the depth of the texture + offset of velocity z
	vec4 backtracked_sample = get_backtracked_sample(uvn, chosen_uv, chosen_velocity, best_sample_fitness, render_size);
	
	if(best_sample_fitness.w == 0 || depth > backtracked_sample.z)
	{
		set_value(set_a, uvi, vec4(uvn, 0, 0));
		return;
	}
	
	set_value(set_a, uvi, backtracked_sample);
	
	return;
}	
//
//	if((a.w == b.w) && (a.w == 1))
//	{
//		return a.z < b.z ? 0. : 1.;
//	}
//
//	return a.x * b.w < b.x * a.w ? 1. : 0.;