#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38

layout(set = 0, binding = 0) uniform sampler2D color_sampler;
layout(set = 0, binding = 1) uniform sampler2D depth_sampler;
layout(set = 0, binding = 2) uniform sampler2D velocity_sampler;
layout(set = 0, binding = 3) uniform sampler2D neighbor_max;
layout(set = 0, binding = 4) uniform sampler2D tile_variance;
layout(rgba16f, set = 0, binding = 5) uniform writeonly image2D output_color;
layout(rgba16f, set = 0, binding = 6) uniform image2D debug_1_image;
layout(rgba16f, set = 0, binding = 7) uniform image2D debug_2_image;

layout(push_constant, std430) uniform Params 
{	
	float minimum_user_threshold;
	float importance_bias;
	float maximum_jitter_value;
	float nan8;
	int tile_size;
	int sample_count;
	int frame;
	int nan4;
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
	return clamp(1 - abs(T) / v, 0, 1);
}

float cylinder(float T, float v)
{
	return 1.0 - smoothstep(0.95 * v, 1.05 * v, abs(T));
}
// ----------------------------------------------------------

// Guertin's functions https://research.nvidia.com/sites/default/files/pubs/2013-11_A-Fast-and/Guertin2013MotionBlur-small.pdf
// ----------------------------------------------------------
float z_compare(float a, float b)
{
	return clamp(1. - (a - b) / min(a, b), 0, 1);
}
// ----------------------------------------------------------

// from https://www.shadertoy.com/view/ftKfzc
// ----------------------------------------------------------
float interleaved_gradient_noise(vec2 uv, int FrameId){
	uv += float(FrameId)  * (vec2(47, 17) * 0.695);

    vec3 magic = vec3( 0.06711056, 0.00583715, 52.9829189 );

    return fract(magic.z * fract(dot(uv, magic.xy)));
}
// ----------------------------------------------------------

vec2 sample_random_offset(vec2 uv, float j)
{
	return vec2(0);
}

void main() 
{
	ivec2 render_size = ivec2(textureSize(color_sampler, 0));
	ivec2 tile_render_size = ivec2(textureSize(neighbor_max, 0));
	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);
	if ((uvi.x >= render_size.x) || (uvi.y >= render_size.y)) 
	{
		return;
	}

	vec2 x = (vec2(uvi) + vec2(0.5)) / vec2(render_size);
	
	float j = interleaved_gradient_noise(uvi, params.frame) * 2. - 1.;

	vec2 vn = textureLod(neighbor_max, x, 0.0).xy * render_size / 2;

	float vn_length = max(0.5, length(vn));

	vec4 base_color = textureLod(color_sampler, x, 0.0);

	if(vn_length <= 0.5)
	{
		imageStore(output_color, uvi, base_color);
		imageStore(debug_1_image, uvi, base_color);
		imageStore(debug_2_image, uvi, vec4(vn / render_size * 2, 0, 1));
		return;
	}

	vec2 wn = normalize(vn);

	vec2 vx = textureLod(velocity_sampler, x, 0.0).xy * render_size / 2;

	float vx_length = max(0.5, length(vx));

	vec2 wp = vec2(-wn.y, wn.x);

	if(dot(wp, vx) < 0)
	{
		wp = -wp;
	}

	vec2 wc = normalize(mix(wp, normalize(vx), (vx_length - 0.5) / params.minimum_user_threshold));

	float zx = -0.05 / textureLod(depth_sampler, x, 0.0).x;
	
	float weight = params.sample_count / (params.importance_bias * vx_length);

	vec4 sum = base_color * weight;

	for(int i = 0; i < params.sample_count; i++)
	{
		float t = mix(-1.0, 1.0, (i + j * params.maximum_jitter_value + 1.0) / (params.sample_count + 1.0));
		
		vec2 d = ((i % 2) > 0) ? vx : vn;

		float T = t * vn_length;

		vec2 y = x + t * d / render_size;

		vec2 vy = textureLod(velocity_sampler, y, 0.0).xy * render_size / 2;

		float vy_length = max(0.5, length(vy));

		float zy = -0.05 / textureLod(depth_sampler, y, 0.0).x;

		float f = z_compare(zx, zy);
		float b = z_compare(zy, zx);
	
		float wa = dot(wc, d);
		float wb = dot(normalize(vy), d);

		float ay = f * cone(T, 1. / vy_length) * max(FLT_MIN, abs(wb))
		+ b * cone(T, 1. / vx_length) * max(FLT_MIN, abs(wa)) 
		+ cylinder(T, min(vx_length, vy_length)) * 2 * max(FLT_MIN, max(abs(wa), abs(wb)));

		weight += abs(ay);
		sum += ay * textureLod(color_sampler, y, 0.0);
	}

	sum /= weight;

	imageStore(output_color, uvi, sum);
	imageStore(debug_1_image, uvi, sum);
	imageStore(debug_2_image, uvi, vec4(vn / render_size * 2, 0, 1));
}