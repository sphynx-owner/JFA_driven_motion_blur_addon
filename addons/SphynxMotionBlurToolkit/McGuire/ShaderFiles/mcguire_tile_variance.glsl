#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38

layout(set = 0, binding = 0) uniform sampler2D tile_max;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D tile_variance;

layout(push_constant, std430) uniform Params 
{	
	float nan5;
	float nan6;
	float nan7;
	float nan8;
	int nan1;
	int nan2;
	int nan3;
	int nan4;
} params;

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;


void main() 
{
	ivec2 render_size = ivec2(textureSize(tile_max, 0));
	ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);
	if ((uvi.x >= render_size.x) || (uvi.y >= render_size.y)) 
	{
		return;
	}

	vec2 uvn = (vec2(uvi) + vec2(0.5)) / render_size;

	float variance = 0;

	vec2 current_velocity = abs(normalize(textureLod(tile_max, uvn, 0.0).xy));

	float tile_count = 0;

	for(int i = -1; i < 2; i++)
	{
		for(int j = -1; j < 2; j++)
		{
			vec2 current_offset = vec2(1) / vec2(render_size) * vec2(i, j);
			vec2 current_uv = uvn + current_offset;
			if(current_uv.x < 0 || current_uv.x > 1 || current_uv.y < 0 || current_uv.y > 1)
			{
				continue;
			}
			if(i == j && i == 0)
			{
				continue;
			}
			
			tile_count += 1;

			vec2 current_neighbor_velocity = abs(normalize(textureLod(tile_max, current_uv, 0.0).xy));

			variance += dot(current_velocity, current_neighbor_velocity);
		}
	}

	variance /= tile_count;

	imageStore(tile_variance, uvi, vec4(1 - variance));
}