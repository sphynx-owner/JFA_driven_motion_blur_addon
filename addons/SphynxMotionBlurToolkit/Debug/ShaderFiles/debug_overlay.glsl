#[compute]
#version 450

#define FLT_MAX 3.402823466e+38
#define FLT_MIN 1.175494351e-38
#define DBL_MAX 1.7976931348623158e+308
#define DBL_MIN 2.2250738585072014e-308

layout(rgba16f, set = 0, binding = 0) uniform image2D past_color_image;
layout(rgba16f, set = 0, binding = 1) uniform image2D output_color_image;
layout(set = 0, binding = 2) uniform sampler2D color_sampler;

layout(push_constant, std430) uniform Params 
{
	float nan_fl_1;
	float nan_fl_2;
	float nan_fl_3;
	float nan_fl_4;
	int freeze;
	int draw_debug;
	int debug_page;
	int nan3;
} params;

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;


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
		imageStore(output_color_image, uvi, imageLoad(past_color_image, uvi));
		return;
	}
	// must be on pixel center for whole values (tested)
	vec2 uvn = vec2(uvi + vec2(0.5)) / render_size;

	vec4 source = textureLod(color_sampler, uvn, 0.0);

	if (params.draw_debug == 0) 
	{
		imageStore(output_color_image, uvi, source);
		imageStore(past_color_image, uvi, source);
		return;
	}

	vec4 tl_col;

	vec4 tr_col;

	vec4 bl_col;

	vec4 br_col;

#ifdef DEBUG
	if(params.debug_page == 0)
	{
		tl_col = imageLoad(debug_1_image, uvi);
		tr_col = imageLoad(debug_2_image, uvi);
		bl_col = imageLoad(debug_3_image, uvi);
		br_col = imageLoad(debug_4_image, uvi);
	}
	if(params.debug_page == 1)
	{
		tl_col = imageLoad(debug_5_image, uvi);
		tr_col = imageLoad(debug_6_image, uvi);
		bl_col = imageLoad(debug_7_image, uvi);
		br_col = imageLoad(debug_8_image, uvi);
	}
#endif

	imageStore(output_color_image, uvi / 2, tl_col);
	imageStore(output_color_image, uvi / 2 + ivec2(vec2(0.5, 0.5) * render_size), br_col);
	imageStore(output_color_image, uvi / 2 + ivec2(vec2(0.0, 0.5) * render_size), bl_col);
	imageStore(output_color_image, uvi / 2 + ivec2(vec2(0.5, 0.0) * render_size), tr_col);
	imageStore(past_color_image, uvi / 2, tl_col);
	imageStore(past_color_image, uvi / 2 + ivec2(vec2(0.5, 0.5) * render_size), br_col);
	imageStore(past_color_image, uvi / 2 + ivec2(vec2(0.0, 0.5) * render_size), bl_col);
	imageStore(past_color_image, uvi / 2 + ivec2(vec2(0.5, 0.0) * render_size), tr_col);
}