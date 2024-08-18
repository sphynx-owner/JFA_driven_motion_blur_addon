#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38
#define M_PI 3.1415926535897932384626433832795

layout(set = 0, binding = 0) uniform sampler2D color_sampler;
layout(set = 0, binding = 1) uniform sampler2D depth_sampler;
layout(set = 0, binding = 2) uniform sampler2D velocity_sampler;
layout(set = 0, binding = 3) uniform sampler2D velocity_map;
layout(rgba16f, set = 0, binding = 4) uniform writeonly image2D output_image;
layout(set = 0, binding = 5) uniform sampler2D tile_max;

layout(push_constant, std430) uniform Params 
{
	float motion_blur_samples;
	float motion_blur_intensity;
	float motion_blur_center_fade;
	float frame;
	float last_iteration_index;
	float sample_step_multiplier;
	float step_exponent_modifier;
	float max_dilation_radius;
	int nan0;
	int nan1;
	int nan2;
	int nan3;
} params;

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// McGuire's functions https://docs.google.com/document/d/1IIlAKTj-O01hcXEdGxTErQbCHO9iBmRx6oFUy_Jm0fI/edit
// ----------------------------------------------------------
float soft_depth_compare(float depth_X, float depth_Y, float sze)
{
	return clamp(1 - (depth_X - depth_Y) / sze, 0, 1);
}

float cone(float T, float v)
{
	return clamp(1 - T / v, 0, 1);
}

float cylinder(float T, float v)
{
	return 1.0 - smoothstep(0.95 * v, 1.05 * v, T);
}
// ----------------------------------------------------------

// Guertin's functions https://research.nvidia.com/sites/default/files/pubs/2013-11_A-Fast-and/Guertin2013MotionBlur-small.pdf
// ----------------------------------------------------------
float z_compare(float a, float b, float sze)
{
	return clamp(1. - sze * (a - b), 0, 1);
}
// ----------------------------------------------------------

// from https://www.shadertoy.com/view/ftKfzc
// ----------------------------------------------------------
float interleaved_gradient_noise(vec2 uv){
	uv += float(params.frame)  * (vec2(47, 17) * 0.695);

    vec3 magic = vec3( 0.06711056, 0.00583715, 52.9829189 );

    return fract(magic.z * fract(dot(uv, magic.xy)));
}
// ----------------------------------------------------------

// from https://github.com/bradparks/KinoMotion__unity_motion_blur/tree/master
// ----------------------------------------------------------
vec2 safenorm(vec2 v)
{
	float l = max(length(v), 1e-6);
	return v / l * int(l >= 0.5);
}

vec2 jitter_tile(vec2 uvi)
{
	float rx, ry;
	float angle = interleaved_gradient_noise(uvi + vec2(2, 0)) * M_PI * 2;
	rx = cos(angle);
	ry = sin(angle);
	return vec2(rx, ry) / textureSize(tile_max, 0) / 4;
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

	vec2 x = (vec2(uvi) + vec2(0.5)) / vec2(render_size);

	vec2 velocity_map_sample = textureLod(velocity_map, x + jitter_tile(uvi), 0.0).xy;

	vec3 vnz = textureLod(tile_max, velocity_map_sample, 0.0).xyz * vec3(render_size, 1);
	
	float vn_length = max(0.5, length(vnz.xy));

	float multiplier = clamp(vn_length, 0, min(params.max_dilation_radius, vn_length * params.motion_blur_intensity)) / max(FLT_MIN, vn_length);

	vnz.xyz *= multiplier;

	vn_length *= multiplier;

	vec2 vn = vnz.xy;
	
	vec4 col_x = textureLod(color_sampler, x, 0.0);
		
	vec2 wn = safenorm(vn);

	vec4 vxz = textureLod(velocity_sampler, x, 0.0) * vec4(render_size, 1, 1);
	
	float vx_length = max(0.5, length(vxz.xy));
	
	multiplier = clamp(vx_length, 0, min(params.max_dilation_radius, vn_length * params.motion_blur_intensity)) / max(FLT_MIN, vx_length);
	
	vxz.xyz *= multiplier;

	vx_length *= multiplier;
	
	vec2 vx = vxz.xy;
	
	if(vn_length <= 0.5)
	{
		imageStore(output_image, uvi, col_x);

#ifdef DEBUG
		imageStore(debug_1_image, uvi, col_x);
		imageStore(debug_2_image, uvi, abs(vec4(vn / render_size * 10, vnz.z * 100, 1)));
		imageStore(debug_3_image, uvi, abs(vec4(velocity_map_sample - x, 0, 1)));
		imageStore(debug_4_image, uvi, abs(vec4(vx / render_size * 10, vxz.z * 100, 1)));
		imageStore(debug_5_image, uvi, col_x);
#endif
		
		return;
	}

	float velocity_match = pow(clamp(dot(vx, vn) / dot(vn, vn), 0, 1), 0.5);

	vn = mix(vn, vx, velocity_match);

	vnz = mix(vnz, vxz.xyz, velocity_match);
	
	float zx = vxz.w;
	
	vec2 wx = safenorm(vx);

	float weight = 0;

	vec4 sum = col_x * weight;

	float total_back_weight = 1e-10;

	vec4 back_sum = col_x * total_back_weight;
	
	float j = interleaved_gradient_noise(uvi) - 0.5;

	int back_amount = 0;

	int nai_back_i = 1;

	for(int i = 0; i < params.motion_blur_samples; i++)
	{
		float nai_t = mix(0., -1., (i + j + 1.0) / (params.motion_blur_samples + 1.0));

		float nai_T = abs(nai_t * vx_length);

		vec2 nai_y = x + (vx / render_size) * nai_t;

		float nai_zy = textureLod(depth_sampler, nai_y, 0.0).x - vxz.z * nai_t;
		
		float nai_b = z_compare(-zx, -nai_zy, 20000);
		
		float nai_f = z_compare(-nai_zy, -zx, 20000);

		vec4 nai_vy = textureLod(velocity_sampler, nai_y, 0.0) * vec4(render_size, 1, 1);
		
		float nai_vy_length = max(0.5, length(nai_vy.xy));
		
		float nai_ay = nai_b;

		float nai_wb = abs(max(0, dot(nai_vy.xy / nai_vy_length, wx)));

		float nai_ay_f = nai_f * step(nai_T, nai_vy_length * nai_wb);

		if(nai_y.x < 0 || nai_y.x > 1 || nai_y.y < 0 || nai_y.y > 1 || nai_ay + nai_ay_f <= 1e-5)
		{
			nai_t = mix(0., 1., (nai_back_i + j + 1.0) / (params.motion_blur_samples + 1.0));
			
			nai_T = abs(nai_t * vx_length);
			
			nai_y = x + (vx / render_size) * nai_t;

			nai_zy = textureLod(depth_sampler, nai_y, 0.0).x - vxz.z * nai_t;
		
			nai_b = z_compare(-zx, -nai_zy, 20000);
			
			nai_f = z_compare(-nai_zy, -zx, 20000);

			nai_vy = textureLod(velocity_sampler, nai_y, 0.0) * vec4(render_size, 1, 1);
		
			nai_vy_length = max(0.5, length(nai_vy.xy));
			
			nai_ay = nai_b;
			
			nai_wb = abs(max(0, dot(nai_vy.xy / nai_vy_length, wx)));

			nai_ay_f = nai_f * step(nai_T, nai_vy_length * nai_wb);
			
			nai_back_i++;
		}
		
		vec4 nai_col_y = textureLod(color_sampler, nai_y, 0.0);

		total_back_weight += nai_ay;

		back_sum += nai_col_y * nai_ay;
				
		float t = mix(0., -1., (i - back_amount + j + 1.0) / (params.motion_blur_samples + 1.0));

		float T = abs(t * vn_length);

		vec2 y = x + (vn / render_size) * t;
		
		if(y.x < 0 || y.x > 1 || y.y < 0 || y.y > 1)
		{
			continue;
//			vn = -vn;
//			vnz = -vnz;
//			wn = -wn;
//			back_amount = i;
		}

		vec4 vy = textureLod(velocity_sampler, y, 0.0) * vec4(render_size, 1, 1);

		float vy_length = max(0.5, length(vy.xy));

		float zy = vy.w - vnz.z * t;

		float f = z_compare(-zy, -zx, 20000);

		float wa = abs(max(0, dot(vy.xy / vy_length, wn)));

		float ay_trail = f * step(T, vy_length * wa);

		vec4 col_y = textureLod(color_sampler, y, 0.0);
		
		vec2 back_y = x + (vn / render_size) * -t;

		vec4 back_vy = textureLod(velocity_sampler, back_y, 0.0) * vec4(render_size, 1, 1);

		float back_vy_length = max(0.5, length(back_vy.xy));

		float back_zy = back_vy.w - vnz.z * -t;

		float back_wa = abs(max(0, dot(back_vy.xy / back_vy_length, -wn)));

		float back_f = z_compare(-back_zy, -zx, 20000);

		float back_ay_trail = back_f * step(T, back_vy_length * back_wa);

		vec4 back_col_y = textureLod(color_sampler, back_y, 0.0);

		weight += back_ay_trail + (back_ay_trail > 0 ? 0 : ay_trail);

		sum += back_col_y * back_ay_trail + (back_ay_trail > 0 ? vec4(0) : col_y * ay_trail);
		

	}

	back_sum *= (params.motion_blur_samples - weight) / total_back_weight;

	sum /= params.motion_blur_samples;

	back_sum /= params.motion_blur_samples;
	
	imageStore(output_image, uvi, sum + back_sum);
	
#ifdef DEBUG
	imageStore(debug_1_image, uvi, sum + back_sum);
	imageStore(debug_2_image, uvi, abs(vec4(vn / render_size * 10, vnz.z * 100, 1)));
	imageStore(debug_3_image, uvi, abs(vec4(velocity_map_sample - x, 0, 1)));
	imageStore(debug_4_image, uvi, abs(vec4(vx / render_size * 10, vxz.z * 100, 1)));
	imageStore(debug_5_image, uvi, col_x);
#endif
}