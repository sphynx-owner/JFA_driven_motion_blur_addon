#[compute]
#version 450

layout(set = 0, binding = 0) uniform sampler2D velocity_sampler;
layout(set = 0, binding = 1) uniform sampler2D color_sampler;
layout(rgba16f, set = 0, binding = 2) uniform image2D past_velocity;
layout(rgba16f, set = 0, binding = 3) uniform image2D past_color;

// Guertin's functions https://research.nvidia.com/sites/default/files/pubs/2013-11_A-Fast-and/Guertin2013MotionBlur-small.pdf
// ----------------------------------------------------------
float z_compare(float a, float b, float sze)
{
	return clamp(1. - sze * (a - b), 0, 1);
}
// ----------------------------------------------------------

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

void main() 
{
	ivec2 render_size = ivec2(textureSize(velocity_sampler, 0));
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	if ((uv.x >= render_size.x) || (uv.y >= render_size.y)) 
	{
		return;
	}
	
	vec2 x = (vec2(uv) + 0.5) / render_size;

	vec4 past_vx = textureLod(velocity_sampler, x, 0.0);

	vec4 past_vx_vx = textureLod(velocity_sampler, x + past_vx.xy, 0.0);

	vec4 past_col_vx = textureLod(color_sampler, x + past_vx.xy, 0.0);

	vec4 past_col_x = textureLod(color_sampler, x, 0.0);

	float alpha = 1 - z_compare(-past_vx.w, -past_vx_vx.w, 20000);

	vec4 final_past_col = mix(past_col_vx, past_col_x, alpha); 
	
	vec4 final_past_vx = mix(vec4(past_vx_vx.xyz, past_vx.w), past_vx, alpha);

	imageStore(past_color, uv, final_past_col);
	imageStore(past_velocity, uv, final_past_vx);
}
