#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38
#define M_PI 3.1415926535897932384626433832795

layout(set = 0, binding = 0) uniform sampler2D color_sampler;
layout(set = 0, binding = 1) uniform sampler2D depth_sampler;
layout(set = 0, binding = 2) uniform sampler2D vector_sampler;
layout(set = 0, binding = 3) uniform sampler2D velocity_map;
layout(rgba16f, set = 0, binding = 4) uniform writeonly image2D output_image;
layout(rgba16f, set = 0, binding = 5) uniform writeonly image2D debug_1_image;
layout(rgba16f, set = 0, binding = 6) uniform writeonly image2D debug_2_image;
layout(rgba16f, set = 0, binding = 7) uniform writeonly image2D debug_3_image;
layout(rgba16f, set = 0, binding = 8) uniform writeonly image2D debug_4_image;
layout(rgba16f, set = 0, binding = 9) uniform writeonly image2D debug_5_image;
layout(rgba16f, set = 0, binding = 10) uniform writeonly image2D debug_6_image;
layout(rgba16f, set = 0, binding = 11) uniform writeonly image2D debug_7_image;
layout(rgba16f, set = 0, binding = 12) uniform writeonly image2D debug_8_image;
layout(set = 0, binding = 13) uniform sampler2D tile_max;

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
	return clamp(1. - sze * (a - b) / min(a, b), 0, 1);
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
	return v / l * int(1 >= 0.5);
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

float get_motion_difference(vec2 V, vec2 V2, float power)
{
	vec2 VO = V - V2;
	float difference = dot(VO, V) / max(FLT_MIN, dot(V, V));
	return pow(clamp(difference, 0, 1), power);
}

vec2 sample_random_offset(vec2 uv, float j)
{
	return vec2(0);
}

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

	vec3 vnz = textureLod(tile_max, velocity_map_sample, 0.0).xyz * vec3(render_size, 1);// * 2;

	vec2 vn = vnz.xy;

	float vn_length = max(0.5, length(vn));
	
	vec2 wn = safenorm(vn);

	vec4 col_x = textureLod(color_sampler, x, 0.0);

	vec3 vxz = textureLod(vector_sampler, x, 0.0).xyz * vec3(render_size, 1);// * 2;
	
	vec2 vx = vxz.xy;

	if(vn_length <= 0.5)
	{
		imageStore(output_image, uvi, col_x);	
		imageStore(debug_1_image, uvi, col_x);
		imageStore(debug_2_image, uvi, abs(vec4(vn / render_size * 10, vnz.z * 100, 1)));
		imageStore(debug_3_image, uvi, abs(vec4(velocity_map_sample - x, 0, 1)));
		imageStore(debug_4_image, uvi, abs(vec4(vx / render_size * 10, vxz.z * 100, 1)));
		imageStore(debug_5_image, uvi, 10 * abs(textureLod(tile_max, x, 0.0)));
		imageStore(debug_6_image, uvi, 10 * abs(textureLod(tile_max, textureLod(velocity_map, x, 0.0).xy, 0.0)));
		imageStore(debug_7_image, uvi, 10 * abs(textureLod(velocity_map, x, 0.0)));
		imageStore(debug_8_image, uvi, abs(textureLod(velocity_map, x, 0.0) / 10));
		return;
	}

	float zx = -0.05 / max(FLT_MIN, textureLod(depth_sampler, x, 0.0).x);

	float vx_length = max(0.5, length(vx));
	
	vec2 wx = safenorm(vx);
	
	vec2 wp = vec2(-wn.y, wn.x);
	
	if(dot(wp, vx) < 0)
	{
		wp = -wp;
	}

	vec2 wc = safenorm(mix(wp, wx, clamp((vx_length - 0.5) / 1.5, 0, 1)));

	float weight = 1;//params.motion_blur_samples / (100 * vx_length);

	vec4 sum = col_x * weight;

	float j = interleaved_gradient_noise(uvi) - 0.5;

	int vnvx = 2;//int(vn_length / (10 + vx_length)) + 2;

	for(int i = 0; i < params.motion_blur_samples; i++)
	{
		if(i == (params.motion_blur_samples - 1) / 2)
		{
			continue;
		}
		float t = mix(-1., 0.0, (i + j + 1.0) / (params.motion_blur_samples + 1.0));
		
		float T = abs(t * vn_length);

		float Tx = abs((t + 0.5) * vn_length);
		
		bool sample_main_v = !(((i - 1) % vnvx) == 0);

		vec2 d = vn;//sample_main_v ? vn : vx;

		float dz = vnz.z;//sample_main_v ? vnz.z : vxz.z;

		vec2 wd = safenorm(d);

		vec2 y = x + (d / render_size) * t;

		vec2 vy = textureLod(vector_sampler, y, 0.0).xy * render_size;// * 2;

		float vy_length = max(0.5, length(vy));

		float zy = -0.05 / max(FLT_MIN, textureLod(depth_sampler, y, 0.0).x - dz * t);

		float f = z_compare(zy, zx, 15);
		float b = z_compare(zx, zy, 15);

		float wa = abs(max(0, dot(vy / vy_length, wd)));

		float wb = abs((dot(wc, wd)));

		float cone_x = cone(T, vx_length); // how much of the velocity reaches the current position
		
		float cone_y = cone(T, vy_length); // how much of the velocity reaches the current position

		float ay = clamp(max(step(FLT_MIN, f * wa * cone_y), step(FLT_MIN, b * wb * cone_x)), 0, 1);// * wb;// + cylinder(T, vy_length) * cylinder(T, vx_length) * 2;//cylinder(T, min(vy_length, vx_length)) * 2. * max(wa, wb);//

		vec4 col_y = textureLod(color_sampler, y, 0.0);

		vec4 final_color = mix(col_x, col_y, ay);

		float final_weight = mix(1, 1, ay);

		weight += final_weight;//ay;
		sum += final_color * final_weight;// * ay;
	}

	sum /= weight;
	
	imageStore(output_image, uvi, sum);
	
	imageStore(debug_1_image, uvi, sum);
	imageStore(debug_2_image, uvi, abs(vec4(vn / render_size * 10, vnz.z * 100, 1)));
	imageStore(debug_3_image, uvi, abs(vec4(velocity_map_sample - x, 0, 1)));
	imageStore(debug_4_image, uvi, abs(vec4(vx / render_size * 10, vxz.z * 100, 1)));
	imageStore(debug_5_image, uvi, 10 * abs(textureLod(tile_max, x, 0.0)));
	imageStore(debug_6_image, uvi, 10 * abs(textureLod(tile_max, textureLod(velocity_map, x, 0.0).xy, 0.0)));
	imageStore(debug_7_image, uvi, 10 * abs(textureLod(velocity_map, x, 0.0)));
	imageStore(debug_8_image, uvi, abs(textureLod(velocity_map, x, 0.0) / 10));
}