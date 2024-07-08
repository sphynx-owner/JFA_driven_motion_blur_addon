#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38
#define DBL_MAX 1.7976931348623158e+308
#define DBL_MIN 2.2250738585072014e-308

layout(set = 0, binding = 0) uniform sampler2D color_sampler;
layout(set = 0, binding = 1) uniform sampler2D depth_sampler;
layout(set = 0, binding = 2) uniform sampler2D vector_sampler;
layout(rgba16f, set = 0, binding = 3) uniform readonly image2D velocity_map;
layout(rgba16f, set = 0, binding = 4) uniform image2D output_image;
layout(rgba16f, set = 0, binding = 5) uniform image2D past_color_image;

layout(push_constant, std430) uniform Params 
{
	float motion_blur_samples;
	float motion_blur_intensity;
	float motion_blur_center_fade;
	float debug;
	float freeze;
	float frame;
	float last_iteration_index;
	float sample_step_multiplier;
} params;

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
// velocity similarity divisors
float vsim_parallel = 20;
float vsim_perpendicular = 20;

// for velocity similarity check
float depth_bias = 0.1;

// sample weight threshold
float sw_threshold = 0.1;

// near plane distance
float npd = 0.05;

// SOFT_Z_EXTENT
float sze = 0.1;

// Helper functions
// --------------------------------------------
vec2 get_depth_difference_at_derivative(vec2 uv, vec2 step_size)
{
	float base = textureLod(depth_sampler, uv, 0.0).x;
	float x = textureLod(depth_sampler, uv + vec2(0, step_size.x), 0.0).x;
	float y = textureLod(depth_sampler, uv + vec2(step_size.y, 0), 0.0).x;
	return vec2(x - base, y - base);
}

// from https://www.shadertoy.com/view/ftKfzc
float interleaved_gradient_noise(vec2 uv, int FrameId){
	uv += float(FrameId)  * (vec2(47, 17) * 0.695);

    vec3 magic = vec3( 0.06711056, 0.00583715, 52.9829189 );

    return fract(magic.z * fract(dot(uv, magic.xy)));
}

float get_velocity_convergence(vec2 uv, vec2 step_size)
{
	vec2 base = textureLod(vector_sampler, uv, 0.0).xy;
	vec2 x = textureLod(vector_sampler, uv + vec2(0, step_size.x), 0.0).xy;
	vec2 y = textureLod(vector_sampler, uv + vec2(step_size.y, 0), 0.0).xy;

	return (dot(vec2(0, 1), vec2(x - base)) + dot(vec2(1, 0), vec2(y - base)));
}

vec3 get_ndc_velocity(vec2 uv, vec2 render_size, float depth)
{
	float ndc_velocity_z = get_velocity_convergence(uv, vec2(1) / render_size) / depth;

	vec2 ndc_velocity_xy = textureLod(vector_sampler, uv, 0.0).xy;
	
	return vec3(ndc_velocity_xy, ndc_velocity_z);
}

vec3 get_world_velocity(vec2 uv, vec2 render_size, float depth)
{
	return get_ndc_velocity(uv, render_size, depth) / depth;
}
	

vec3 get_velocity_curl_vector(vec2 uv, vec2 render_size)
{
	float depth = textureLod(depth_sampler, uv, 0.0).x;

	vec2 step_size = vec2(1) / render_size;
	vec3 base = get_world_velocity(uv, render_size, depth);
	vec3 x = get_world_velocity(uv + vec2(step_size.x, 0), render_size, depth);
	vec3 y = get_world_velocity(uv + vec2(0, step_size.y), render_size, depth);

	vec2 depth_derivative = get_depth_difference_at_derivative(uv, step_size) / depth;

	vec3 x_vector = normalize(vec3(step_size.x, 0, 0));
	vec3 y_vector = normalize(vec3(0, step_size.y,  0));

	vec3 cross_x = cross((x - base) / vec3(step_size, 0), x_vector);
	vec3 cross_y = cross((y - base) / vec3(step_size, 0), y_vector);

	return cross_x + cross_y;
}

float get_velocity_curl(vec2 uv, vec2 render_size)
{
	vec2 step_size = vec2(1) / render_size;
	vec2 base = textureLod(vector_sampler, uv, 0.0).xy;
	vec2 x = textureLod(vector_sampler, uv + vec2(0, step_size.x), 0.0).xy;
	vec2 y = textureLod(vector_sampler, uv + vec2(step_size.y, 0), 0.0).xy;

	return (cross(vec3(0, 1, 0), vec3(x - base, 0) / vec3(step_size, 0)) + cross(vec3(1, 0, 0), vec3(y - base, 0) / vec3(step_size, 0))).z;
}
// -------------------------------------------------------

// McGuire's functions https://docs.google.com/document/d/1IIlAKTj-O01hcXEdGxTErQbCHO9iBmRx6oFUy_Jm0fI/edit
// ----------------------------------------------------------
float soft_depth_compare(float depth_X, float depth_Y)
{
	return clamp(1 - (depth_X - depth_Y) / sze, 0, 1);
}

float cone(vec2 X, vec2 Y, vec2 v)
{
	return clamp(1 - length(X - Y) / length(v), 0, 1);
}

float cylinder(vec2 X, vec2 Y, vec2 v)
{
	return 1.0 + smoothstep(0.95 * length(v), 1.05 * length(v), length(X - Y));
}
// ----------------------------------------------------------

// Motion similarity 
// ----------------------------------------------------------
float get_motion_difference(vec2 V, vec2 V2, float power)
{
	vec2 VO = V - V2;
	float difference = dot(VO, V) / max(FLT_MIN, dot(V, V));
	return pow(clamp(difference, 0, 1), power);
}
// ----------------------------------------------------------

void main() 
{
	ivec2 render_size = ivec2(textureSize(color_sampler, 0));
	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);
	if ((uvi.x >= render_size.x) || (uvi.y >= render_size.y)) 
	{
		return;
	}
	
	if(params.freeze > 0)
	{
		imageStore(output_image, uvi, imageLoad(past_color_image, uvi));
		return;
	}

	vec2 uvn = vec2(uvi) / render_size;

	int iteration_count = int(params.motion_blur_samples);

	vec4 base = textureLod(color_sampler, uvn, 0.0);

	vec4 result_constructed_color = vec4(0);

	vec4 velocity_map_sample = imageLoad(velocity_map, uvi);
	
	vec3 velocity = -textureLod(vector_sampler, velocity_map_sample.xy, 0.0).xyz;

	vec3 naive_velocity = -textureLod(vector_sampler, uvn, 0.0).xyz;

	float max_dialtion_radius = pow(2, params.last_iteration_index) * params.sample_step_multiplier / max(render_size.x, render_size.y);

	if ((dot(velocity, velocity) == 0 || params.motion_blur_intensity == 0) && params.debug == 0) //(uvn.y > 0.5)//
	{
		imageStore(output_image, uvi, base);
		imageStore(past_color_image, uvi, base);
		return;
	}
	
	float noise_offset = (interleaved_gradient_noise(uvi, int(params.frame)) - 1);

	float velocity_step_coef = min(params.motion_blur_intensity, max_dialtion_radius / (length(velocity) * params.motion_blur_intensity)) / max(1.0, params.motion_blur_samples - 1.0);

	vec3 sample_step = velocity * velocity_step_coef;

	vec4 velocity_map_sample_step = vec4(0);

	//float d = 1.0 - min(1.0, 2.0 * distance(uvn, vec2(0.5)));
	//sample_step *= 1.0 - d * params.fade_padding.x;

	float total_weight = 1;// max(0.0001, length(naive_velocity));
	
	vec2 offset = vec2(sample_step * noise_offset);
	
	vec4 col = base * total_weight;

	float depth = max(FLT_MIN, textureLod(depth_sampler, velocity_map_sample.xy, 0.0).x);

	float naive_depth = max(FLT_MIN, textureLod(depth_sampler, uvn, 0.0).x);

	for (int i = 1; i < iteration_count; i++) 
	{
		offset += sample_step.xy;// * interleaved_gradient_noise(uvi, int(params.frame) + i);

		vec2 uvo = uvn + offset;

		if (any(notEqual(uvo, clamp(uvo, vec2(0.0), vec2(1.0))))) 
		{
			break;
		}
		
		velocity_map_sample_step = imageLoad(velocity_map, ivec2(uvo * render_size));

		vec3 current_velocity = -textureLod(vector_sampler, velocity_map_sample_step.xy, 0.0).xyz;

		float current_depth = max(FLT_MIN, textureLod(depth_sampler, velocity_map_sample_step.xy, 0.0).x);

		float sample_weight = 1;

		float motion_difference = get_motion_difference(velocity.xy, current_velocity.xy, 0.1);

		float foreground = soft_depth_compare(npd / current_depth, npd / depth);

		sample_weight *= 1 - (foreground * motion_difference);

		total_weight += sample_weight;

		col += textureLod(color_sampler, uvo, 0.0) * sample_weight;
	}

	col /= total_weight;

	if (params.debug == 0) 
	{
		imageStore(output_image, uvi, col);
		imageStore(past_color_image, uvi, col);
		return;
	}

	vec4 tl_col = vec4(abs(textureLod(vector_sampler, uvn, 0.0).xy) * 10, 0, 1);

	vec4 tr_col = vec4(abs(velocity.xy) * 10, 0, 1);

	vec4 bl_col = vec4(abs(velocity_map_sample.xyw - vec3(uvn, 0)) * vec3(10, 10, 1), 1);

	vec4 br_col = col;
	
	//imageStore(past_color_image, uvi, imageLoad(output_image, uvi));
	
	imageStore(output_image, uvi / 2, tl_col);
	imageStore(output_image, uvi / 2 + ivec2(vec2(0.5, 0.5) * render_size), br_col);
	imageStore(output_image, uvi / 2 + ivec2(vec2(0.0, 0.5) * render_size), bl_col);
	imageStore(output_image, uvi / 2 + ivec2(vec2(0.5, 0.0) * render_size), tr_col);
	imageStore(past_color_image, uvi / 2, tl_col);
	imageStore(past_color_image, uvi / 2 + ivec2(vec2(0.5, 0.5) * render_size), br_col);
	imageStore(past_color_image, uvi / 2 + ivec2(vec2(0.0, 0.5) * render_size), bl_col);
	imageStore(past_color_image, uvi / 2 + ivec2(vec2(0.5, 0.0) * render_size), tr_col);
}