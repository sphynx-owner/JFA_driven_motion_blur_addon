#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38
#define DBL_MAX 1.7976931348623158e+308
#define DBL_MIN 2.2250738585072014e-308

layout(set = 0, binding = 0) uniform sampler2D color_sampler;
layout(set = 0, binding = 1) uniform sampler2D depth_sampler;
layout(set = 0, binding = 2) uniform sampler2D vector_sampler;
layout(set = 0, binding = 3) uniform sampler2D velocity_map;
layout(rgba16f, set = 0, binding = 4) uniform writeonly image2D output_image;
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
	float step_exponent_modifier;
	float max_dilation_radius;
	float nan_fl_3;
	float nan_fl_4;
	int debug_page;
	int nan1;
	int nan2;
	int nan3;
} params;

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// near plane distance
float npd = 0.05;

// SOFT_Z_EXTENT
float sze = 0.1;

// Helper functions
// --------------------------------------------
// from https://www.shadertoy.com/view/ftKfzc
float interleaved_gradient_noise(vec2 uv, int FrameId){
	uv += float(FrameId)  * (vec2(47, 17) * 0.695);

    vec3 magic = vec3( 0.06711056, 0.00583715, 52.9829189 );

    return fract(magic.z * fract(dot(uv, magic.xy)));
}
float get_motion_difference(vec2 V, vec2 V2, float power)
{
	vec2 VO = V - V2;
	float difference = dot(VO, V) / max(FLT_MIN, dot(V, V));
	return pow(clamp(difference, 0, 1), power);
}
// McGuire's function https://docs.google.com/document/d/1IIlAKTj-O01hcXEdGxTErQbCHO9iBmRx6oFUy_Jm0fI/edit
float soft_depth_compare(float depth_X, float depth_Y)
{
	return clamp(1 - (depth_X - depth_Y) / sze, 0, 1);
}
// -------------------------------------------------------

void main() 
{
	ivec2 render_size = ivec2(textureSize(color_sampler, 0));
	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);
	if ((uvi.x >= render_size.x) || (uvi.y >= render_size.y)) 
	{
		return;
	}
	// show past image for freeze frame
	if(params.freeze > 0)
	{
		imageStore(output_image, uvi, imageLoad(past_color_image, uvi));
		return;
	}
	// must be on pixel center for whole values (tested)
	vec2 uvn = vec2(uvi + vec2(0.5)) / render_size;

	vec4 base_color = textureLod(color_sampler, uvn, 0.0);
	// get dominant velocity data
	vec4 velocity_map_sample = textureLod(velocity_map, uvn, 0.0);

	vec3 dominant_velocity = -textureLod(vector_sampler, velocity_map_sample.xy, 0.0).xyz;

	vec3 naive_velocity = -textureLod(vector_sampler, uvn, 0.0).xyz;
	// if velocity is 0 and we dont show debug, return right away.
	if ((dot(dominant_velocity, dominant_velocity) == 0 || params.motion_blur_intensity == 0) && params.debug == 0)
	{
		imageStore(output_image, uvi, base_color);
		imageStore(past_color_image, uvi, base_color);
		return;
	}
	// offset along velocity to blend between sample steps
	float noise_offset = interleaved_gradient_noise(uvi, int(params.frame)) - 1;
	// scale of step
	float velocity_step_coef = min(params.motion_blur_intensity, params.max_dilation_radius / max(render_size.x, render_size.y) / (length(dominant_velocity) * params.motion_blur_intensity)) / max(1.0, params.motion_blur_samples - 1.0);

	vec3 step_sample = dominant_velocity * velocity_step_coef;

	vec3 naive_step_sample = naive_velocity * velocity_step_coef;

	vec4 velocity_map_step_sample = vec4(0);

	//float d = 1.0 - min(1.0, 2.0 * distance(uvn, vec2(0.5)));
	//sample_step *= 1.0 - d * params.fade_padding.x;

	float total_weight = 1;
	
	vec3 dominant_offset = step_sample * noise_offset;
	
	vec3 naive_offset = naive_step_sample * noise_offset;

	vec4 col = base_color * total_weight;

	float naive_depth = textureLod(depth_sampler, uvn, 0.0).x;

	for (int i = 1; i < params.motion_blur_samples; i++) 
	{
		dominant_offset += step_sample;

		naive_offset += naive_step_sample;

		vec2 dominant_uvo = uvn + dominant_offset.xy;

		vec2 naive_uvo = uvn + naive_offset.xy;

		if (any(notEqual(dominant_uvo, clamp(dominant_uvo, vec2(0.0), vec2(1.0))))) 
		{
			break;
		}
		
		velocity_map_step_sample = textureLod(velocity_map, dominant_uvo, 0.0);

		vec3 current_dominant_velocity = -textureLod(vector_sampler, velocity_map_step_sample.xy, 0.0).xyz;

		float current_naive_depth = textureLod(depth_sampler, dominant_uvo, 0.0).x;
		// is current velocity different than dilated velocity
		float motion_difference = get_motion_difference(dominant_velocity.xy, current_dominant_velocity.xy, 0.1);
		// is current depth closer than origin of dilation (object in the foreground)
		float foreground = step(naive_depth + dominant_offset.z, current_naive_depth - 0.0001);
		// if we are sampling a foreground object and its velocity is different, discard this sample (prevent ghosting)
		float sample_weight = 1 - (foreground * motion_difference);

		float dominant_naive_mix = 1. - step(0.9, motion_difference);

		vec2 sample_uv = mix(naive_uvo, dominant_uvo, dominant_naive_mix);

		total_weight += sample_weight;

		col += textureLod(color_sampler, sample_uv, 0.0) * sample_weight;
	}

	col /= total_weight;

	if (params.debug == 0) 
	{
		imageStore(output_image, uvi, col);
		imageStore(past_color_image, uvi, col);
		return;
	}

	vec4 tl_col;

	vec4 tr_col;

	vec4 bl_col;

	vec4 br_col;
	
	if(params.debug_page == 0)
	{
		tl_col = vec4((textureLod(vector_sampler, uvn, 0.0).xyz) * vec3(10, 10, 10000), 1);
		tr_col = vec4(abs(dominant_velocity.xy) * 10, 0, 1);
		bl_col = vec4(abs(velocity_map_sample.xyw - vec3(uvn, 0)) * vec3(10, 10, 1), 1);
		br_col = col;
	}
	if(params.debug_page == 1)
	{
		tl_col = vec4(naive_depth * 10);
		tr_col = textureLod(color_sampler, velocity_map_sample.xy, 0.0);//
		//bl_col = vec4(dominant_depth * 10);
		br_col = col;
	}
	
	imageStore(output_image, uvi / 2, tl_col);
	imageStore(output_image, uvi / 2 + ivec2(vec2(0.5, 0.5) * render_size), br_col);
	imageStore(output_image, uvi / 2 + ivec2(vec2(0.0, 0.5) * render_size), bl_col);
	imageStore(output_image, uvi / 2 + ivec2(vec2(0.5, 0.0) * render_size), tr_col);
	imageStore(past_color_image, uvi / 2, tl_col);
	imageStore(past_color_image, uvi / 2 + ivec2(vec2(0.5, 0.5) * render_size), br_col);
	imageStore(past_color_image, uvi / 2 + ivec2(vec2(0.0, 0.5) * render_size), bl_col);
	imageStore(past_color_image, uvi / 2 + ivec2(vec2(0.5, 0.0) * render_size), tr_col);
}