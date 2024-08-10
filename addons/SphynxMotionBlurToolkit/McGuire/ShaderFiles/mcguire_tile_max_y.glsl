#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38

layout(set = 0, binding = 0) uniform sampler2D tile_max_x;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D tile_max;

layout(push_constant, std430) uniform Params 
{	
	float nan5;
	float nan6;
	float nan7;
	float nan8;
	int tile_size;
	int nan2;
	int nan3;
	int nan4;
} params;

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;


void main() 
{
	ivec2 render_size = ivec2(textureSize(tile_max_x, 0));
	ivec2 output_size = imageSize(tile_max);
	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);
	ivec2 global_uvi = uvi * ivec2(1, params.tile_size);
	if ((uvi.x >= output_size.x) || (uvi.y >= output_size.y)) 
	{
		return;
	}

	vec2 uvn = (vec2(global_uvi) + vec2(0.5)) / render_size;

	vec2 max_velocity = vec2(0);

	float max_velocity_length = 0;

	for(int i = 0; i < params.tile_size; i++)
	{
		vec2 current_uv = uvn + vec2(0, float(i) / render_size.y);
		vec2 velocity_sample = textureLod(tile_max_x, current_uv, 0.0).xy;
		float current_velocity_length = dot(velocity_sample, velocity_sample);
		if(current_velocity_length > max_velocity_length)
		{
			max_velocity_length = current_velocity_length;
			max_velocity = velocity_sample;
		}
	}
	imageStore(tile_max, uvi, vec4(max_velocity, 0, 1));
}