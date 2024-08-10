#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38

layout(set = 0, binding = 0) uniform sampler2D tile_max_sampler;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D buffer_a;
layout(rgba16f, set = 0, binding = 2) uniform writeonly image2D buffer_b;
layout(set = 0, binding = 3) uniform sampler2D buffer_a_sampler;
layout(set = 0, binding = 4) uniform sampler2D buffer_b_sampler;

layout(push_constant, std430) uniform Params 
{
	int iteration_index;
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

//vec4 get_value(bool a, ivec2 uvi)
//{
//	if(a)
//	{
//		return imageLoad(buffer_a, uvi);
//	}
//	else
//	{
//		return imageLoad(buffer_b, uvi);
//	}
//}

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

void sample_fitness(vec2 uv_offset, vec4 uv_sample, vec2 render_size, inout vec4 current_sample_fitness)
{
	vec2 sample_velocity = -uv_sample.xy;

	// if velocity is 0, we never reach it (steps never smaller than 1)
	if (dot(sample_velocity, sample_velocity) <= FLT_MIN || uv_sample.w == 0)
	{
		current_sample_fitness = vec4(FLT_MAX, FLT_MAX, FLT_MAX, -1);
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
	current_sample_fitness = vec4(absolute_velocity_space_distance, velocity_space_distance, uv_sample.w + uv_sample.z * velocity_space_distance, within_velocity_range * within_perpen_error_range);
}

float is_sample_better(vec4 a, vec4 b)
{
	// see explanation at end of code
	return mix(1. - step(b.x * a.w, a.x * b.w), step(b.z, a.z), step(0.5, b.w) * step(0.5, a.w));//1. - step(a.x * a.w, b.x * b.w);//(a.x > b.x) ? 1 : 0;//1. - step(b.x * a.w, a.x * b.w);//
}

void main() 
{
	ivec2 render_size = ivec2(textureSize(tile_max_sampler, 0));
	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);
	if ((uvi.x >= render_size.x) || (uvi.y >= render_size.y)) 
	{
		return;
	}

	// must be on pixel center for whole values
	vec2 uvn = (vec2(uvi) + vec2(0.5)) / render_size;

	vec2 uv_step = vec2(round(params.step_size)) / render_size;

	vec4 best_sample_fitness = vec4(FLT_MAX, FLT_MAX, FLT_MAX, 0);
	
	vec2 chosen_uv = uvn;

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

		if(params.iteration_index > 0)
		{		
			check_uv = get_value(!set_a, check_uv).xy;

			step_offset = check_uv - uvn;
		}

		uv_sample = textureLod(tile_max_sampler, check_uv, 0.0);
		
		sample_fitness(step_offset, uv_sample, render_size, current_sample_fitness);

		if (is_sample_better(current_sample_fitness, best_sample_fitness) > 0.5)
		{
			best_sample_fitness = current_sample_fitness;
			chosen_uv = check_uv;
		}
	}

	set_value(set_a, uvi, vec4(chosen_uv, 0, 0));
}	
//
//	if((a.w == b.w) && (a.w == 1))
//	{
//		return a.z < b.z ? 0. : 1.;
//	}
//
//	return a.x * b.w < b.x * a.w ? 1. : 0.;