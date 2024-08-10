extends MotionBlurCompositorEffect
class_name SphynxSimpleJumpFloodMotionBlur

@export_group("Motion Blur", "motion_blur_")
# diminishing returns over 16
@export_range(4, 64) var motion_blur_samples: int = 16
# you really don't want this over 0.5, but you can if you want to try
@export_range(0, 0.5, 0.001, "or_greater") var motion_blur_intensity: float = 1
@export_range(0, 1) var motion_blur_center_fade: float = 0.0

@export var tile_max_x_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/jump_flood_tile_max_x_stage.tres"):
	set(value):
		unsubscribe_shader_stage(tile_max_x_stage)
		tile_max_x_stage = value
		subscirbe_shader_stage(value)

@export var tile_max_y_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/jump_flood_tile_max_y_stage.tres"):
	set(value):
		unsubscribe_shader_stage(tile_max_y_stage)
		tile_max_y_stage = value
		subscirbe_shader_stage(value)

@export var construct_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/jf_simple_stage.tres"):
	set(value):
		unsubscribe_shader_stage(construct_stage)
		construct_stage = value
		subscirbe_shader_stage(value)

@export var neighbor_max_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/jump_flood_neighbor_max_stage.tres"):
	set(value):
		unsubscribe_shader_stage(neighbor_max_stage)
		neighbor_max_stage = value
		subscirbe_shader_stage(value)

@export var blur_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/simple_jf_blur_stage.tres"):
	set(value):
		unsubscribe_shader_stage(blur_stage)
		blur_stage = value
		subscirbe_shader_stage(value)

@export var overlay_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/jump_flood_overlay_stage.tres"):
	set(value):
		unsubscribe_shader_stage(overlay_stage)
		overlay_stage = value
		subscirbe_shader_stage(value)

## the portion of speed that is allowed for side bleed of velocities 
## during the jfa dilation passes and before backtracking. Getting this a higher value
## would make it so that meshes at movement blur more reliably, but also bleed 
## further perpendicularly to their velocity, thus wash elemets behind them out.
@export var perpen_error_threshold : float = 0.5

## an initial step size that can increase the dilation radius proportionally, at the 
## sacrifice of some quality in the final resolution of the dilation.[br][br]
## the formula for the maximum radius of the dilation (in pixels) is: pow(2 + step_exponent_modifier, JFA_pass_count) * sample_step_multiplier
@export var sample_step_multiplier : int = 16

## by default, the jump flood makes samples along distances that start
## at 2 to the power of the pass count you want to perform, which is also 
## the dilation radius you desire. You can change it to values higher than 
## 2 with this variable, and reach higher dilation radius at the sacrifice of
## some accuracy in the dilation.
## the formula for the maximum radius of the dilation (in pixels) is: pow(2 + step_exponent_modifier, JFA_pass_count) * sample_step_multiplier
@export var step_exponent_modifier : float = 1

## the number of passes performed by the jump flood algorithm based dilation, 
## each pass added doubles the maximum radius of dilation available.[br][br]
## the formula for the maximum radius of the dilation (in pixels) is: pow(2 + step_exponent_modifier, JFA_pass_count) * sample_step_multiplier
@export var JFA_pass_count : int = 3

## wether this motion blur stays the same intensity below
## target_constant_framerate
@export var framerate_independent : bool = true

## Description: Removes clamping on motion blur scale to allow framerate independent motion
## blur to scale longer than realistically possible when render framerate is higher
## than target framerate.[br][br]
## [color=yellow]Warning:[/color] Turning this on would allow over-blurring of pixels, which 
## produces inaccurate results, and would likely cause nausea in players over
## long exposure durations, use with caution and out of artistic intent
@export var uncapped_independence : bool = false

## if framerate_independent is enabled, the blur would simulate 
## sutter speeds at that framerate, and up.
@export var target_constant_framerate : float = 30

var tile_max_x : StringName = "tile_max_x"

var tile_max : StringName = "tile_max"

var neighbor_max : StringName = "neighbor_max"

var output_color : StringName = "output_color"

var buffer_a : StringName = "buffer_a"
var buffer_b : StringName = "buffer_b"

var custom_velocity : StringName = "custom_velocity"

var debug_1 : String = "debug_1"
var debug_2 : String = "debug_2"
var debug_3 : String = "debug_3"
var debug_4 : String = "debug_4"
var debug_5 : String = "debug_5"
var debug_6 : String = "debug_6"
var debug_7 : String = "debug_7"
var debug_8 : String = "debug_8"

var temp_motion_blur_intensity : float

var previous_time : float = 0

func _render_callback_2(render_size : Vector2i, render_scene_buffers : RenderSceneBuffersRD, render_scene_data : RenderSceneDataRD):
	var time : float = float(Time.get_ticks_msec()) / 1000
	
	var delta_time : float = time - previous_time
	
	previous_time = time
	
	temp_motion_blur_intensity = motion_blur_intensity
	
	if framerate_independent:
		var capped_frame_time : float = 1 / target_constant_framerate
		
		if !uncapped_independence:
			capped_frame_time = min(capped_frame_time, delta_time)
		
		temp_motion_blur_intensity = motion_blur_intensity * capped_frame_time / delta_time
	
	ensure_texture(custom_velocity, render_scene_buffers)
	ensure_texture(tile_max_x, render_scene_buffers, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Vector2(1. / sample_step_multiplier, 1.))
	ensure_texture(tile_max, render_scene_buffers, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Vector2(1. / sample_step_multiplier, 1. / sample_step_multiplier))
	ensure_texture(buffer_a, render_scene_buffers, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Vector2(1. / sample_step_multiplier, 1. / sample_step_multiplier))
	ensure_texture(buffer_b, render_scene_buffers, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Vector2(1. / sample_step_multiplier, 1. / sample_step_multiplier))
	ensure_texture(neighbor_max, render_scene_buffers, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Vector2(1. / sample_step_multiplier, 1. / sample_step_multiplier))
	ensure_texture(output_color, render_scene_buffers)
	ensure_texture(debug_1, render_scene_buffers)
	ensure_texture(debug_2, render_scene_buffers)
	ensure_texture(debug_3, render_scene_buffers)
	ensure_texture(debug_4, render_scene_buffers)
	ensure_texture(debug_5, render_scene_buffers)
	ensure_texture(debug_6, render_scene_buffers)
	ensure_texture(debug_7, render_scene_buffers)
	ensure_texture(debug_8, render_scene_buffers)
	
	rd.draw_command_begin_label("Motion Blur", Color(1.0, 1.0, 1.0, 1.0))
	
	var last_iteration_index : int = JFA_pass_count - 1;
	
	var max_dilation_radius : float = pow(2 + step_exponent_modifier, last_iteration_index) * sample_step_multiplier / motion_blur_intensity;
	
	var tile_max_x_push_constants: PackedFloat32Array = [
		0,
		0,
		0,
		0
	]
	var int_tile_max_x_push_constants : PackedInt32Array = [
		sample_step_multiplier,
		0,
		0,
		0
	]
	var tile_max_x_push_constants_byte_array = tile_max_x_push_constants.to_byte_array()
	tile_max_x_push_constants_byte_array.append_array(int_tile_max_x_push_constants.to_byte_array())
	
	var tile_max_y_push_constants: PackedFloat32Array = [
		0,
		0,
		0,
		0
	]
	var int_tile_max_y_push_constants : PackedInt32Array = [
		sample_step_multiplier,
		0,
		0,
		0
	]
	var tile_max_y_push_constants_byte_array = tile_max_y_push_constants.to_byte_array()
	tile_max_y_push_constants_byte_array.append_array(int_tile_max_y_push_constants.to_byte_array())
	var neighbor_max_push_constants: PackedFloat32Array = [
		0,
		0,
		0,
		0
	]
	var int_neighbor_max_push_constants : PackedInt32Array = [
		0,
		0,
		0,
		0
	]
	var neighbor_max_push_constants_byte_array = neighbor_max_push_constants.to_byte_array()
	neighbor_max_push_constants_byte_array.append_array(int_neighbor_max_push_constants.to_byte_array())
	
	var push_constant: PackedFloat32Array = [
		motion_blur_samples, 
		temp_motion_blur_intensity,
		motion_blur_center_fade,
		Engine.get_frames_drawn() % 8, 
		last_iteration_index, 
		sample_step_multiplier,
		step_exponent_modifier,
		max_dilation_radius,
	]
	var int_push_constant : PackedInt32Array = [
		0,
		0,
		0,
		0
	]
	var byte_array = push_constant.to_byte_array()
	byte_array.append_array(int_push_constant.to_byte_array())
	
	var view_count = render_scene_buffers.get_view_count()
	for view in range(view_count):
		var color_image := render_scene_buffers.get_color_layer(view)
		var depth_image := render_scene_buffers.get_depth_layer(view)
		var output_color_image := render_scene_buffers.get_texture_slice(context, output_color, view, 0, 1, 1)
		var buffer_a_image := render_scene_buffers.get_texture_slice(context, buffer_a, view, 0, 1, 1)
		var buffer_b_image := render_scene_buffers.get_texture_slice(context, buffer_b, view, 0, 1, 1)
		var custom_velocity_image := render_scene_buffers.get_texture_slice(context, custom_velocity, view, 0, 1, 1)
		var tile_max_x_image := render_scene_buffers.get_texture_slice(context, tile_max_x, view, 0, 1, 1)
		var tile_max_image := render_scene_buffers.get_texture_slice(context, tile_max, view, 0, 1, 1)
		var neighbor_max_image := render_scene_buffers.get_texture_slice(context, neighbor_max, view, 0, 1, 1)
		var debug_1_image := render_scene_buffers.get_texture_slice(context, debug_1, view, 0, 1, 1)
		var debug_2_image := render_scene_buffers.get_texture_slice(context, debug_2, view, 0, 1, 1)
		var debug_3_image := render_scene_buffers.get_texture_slice(context, debug_3, view, 0, 1, 1)
		var debug_4_image := render_scene_buffers.get_texture_slice(context, debug_4, view, 0, 1, 1)
		var debug_5_image := render_scene_buffers.get_texture_slice(context, debug_5, view, 0, 1, 1)
		var debug_6_image := render_scene_buffers.get_texture_slice(context, debug_6, view, 0, 1, 1)
		var debug_7_image := render_scene_buffers.get_texture_slice(context, debug_7, view, 0, 1, 1)
		var debug_8_image := render_scene_buffers.get_texture_slice(context, debug_8, view, 0, 1, 1)
		
		var x_groups := floori((render_size.x / sample_step_multiplier - 1) / 16 + 1)
		var y_groups := floori((render_size.y - 1) / 16 + 1)
		
		dispatch_stage(tile_max_x_stage, 
		[
			get_sampler_uniform(custom_velocity_image, 0, false),
			get_sampler_uniform(depth_image, 1, false),
			get_image_uniform(tile_max_x_image, 2)
		],
		tile_max_x_push_constants_byte_array,
		Vector3i(x_groups, y_groups, 1), 
		"TileMaxX", 
		view)
		
		x_groups = floori((render_size.x / sample_step_multiplier - 1) / 16 + 1)
		y_groups = floori((render_size.y / sample_step_multiplier - 1) / 16 + 1)
		
		dispatch_stage(tile_max_y_stage, 
		[
			get_sampler_uniform(tile_max_x_image, 0, false),
			get_image_uniform(tile_max_image, 1)
		],
		tile_max_y_push_constants_byte_array,
		Vector3i(x_groups, y_groups, 1), 
		"TileMaxY", 
		view)
		
		for i in JFA_pass_count:
			var jf_push_constants : PackedInt32Array = [
				i,
				last_iteration_index,
				0,
				16
			]
			
			var step_size : float = round(pow(2 + step_exponent_modifier, last_iteration_index - i));
			
			var jf_float_push_constants_test : PackedFloat32Array = [
				perpen_error_threshold,
				sample_step_multiplier,
				temp_motion_blur_intensity,
				0,
				0,
				0,
				0,
				step_exponent_modifier,
				step_size,
				max_dilation_radius,
				0,
				0
			]
			
			var jf_byte_array = jf_push_constants.to_byte_array()
			jf_byte_array.append_array(jf_float_push_constants_test.to_byte_array())
			
			dispatch_stage(construct_stage, 
			[
				get_sampler_uniform(tile_max_image, 0, false),
				get_image_uniform(buffer_a_image, 1),
				get_image_uniform(buffer_b_image, 2),
				get_sampler_uniform(buffer_a_image, 3, false),
				get_sampler_uniform(buffer_b_image, 4, false)
			],
			jf_byte_array,
			Vector3i(x_groups, y_groups, 1), 
			"Construct Blur", 
			view)
		
		
		
		rd.draw_command_end_label()
		
		dispatch_stage(neighbor_max_stage, 
		[
			get_sampler_uniform(tile_max_image, 0, false),
			get_sampler_uniform(buffer_b_image if last_iteration_index % 2 else buffer_a_image, 1, false),
			get_image_uniform(neighbor_max_image, 2)
		],
		neighbor_max_push_constants_byte_array,
		Vector3i(x_groups, y_groups, 1), 
		"NeighborMax", 
		view)
		
		x_groups = floori((render_size.x - 1) / 16 + 1)
		y_groups = floori((render_size.y - 1) / 16 + 1)
		
		dispatch_stage(blur_stage, 
		[
			get_sampler_uniform(color_image, 0, false),
			get_sampler_uniform(depth_image, 1, false),
			get_sampler_uniform(custom_velocity_image, 2, false),
			get_sampler_uniform(neighbor_max_image, 3, false),
			get_image_uniform(output_color_image, 4),
			get_image_uniform(debug_1_image, 5),
			get_image_uniform(debug_2_image, 6),
			get_image_uniform(debug_3_image, 7),
			get_image_uniform(debug_4_image, 8),
			get_image_uniform(debug_5_image, 9),
			get_image_uniform(debug_6_image, 10),
			get_image_uniform(debug_7_image, 11),
			get_image_uniform(debug_8_image, 12),
			get_sampler_uniform(tile_max_image, 13, false)
		],
		byte_array,
		Vector3i(x_groups, y_groups, 1), 
		"Compute Blur", 
		view)
		
		dispatch_stage(overlay_stage, 
		[
			get_sampler_uniform(output_color_image, 0),
			get_image_uniform(color_image, 1)
		],
		[],
		Vector3i(x_groups, y_groups, 1), 
		"Overlay Result", 
		view)
	
	rd.draw_command_end_label()
