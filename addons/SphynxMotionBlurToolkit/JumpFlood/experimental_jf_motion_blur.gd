extends "res://addons/SphynxMotionBlurToolkit/JumpFlood/base_jump_flood_motion_blur.gd"
class_name ExperimentalJumpFloodMotionBlur

@export_group("Shader Stages")
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

@export var blur_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/experimental_jump_flood_blur_stage.tres"):
	set(value):
		unsubscribe_shader_stage(blur_stage)
		blur_stage = value
		subscirbe_shader_stage(value)

@export var cache_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/jump_flood_cache_stage.tres"):
	set(value):
		unsubscribe_shader_stage(cache_stage)
		cache_stage = value
		subscirbe_shader_stage(value)

@export var overlay_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/jump_flood_overlay_stage.tres"):
	set(value):
		unsubscribe_shader_stage(overlay_stage)
		overlay_stage = value
		subscirbe_shader_stage(value)

var tile_max_x : StringName = "tile_max_x"

var tile_max : StringName = "tile_max"

var neighbor_max : StringName = "neighbor_max"

var output_color : StringName = "output_color"

var past_color : StringName = "past_color_cache"

var past_velocity : StringName = "past_velocity_cache"

var buffer_a : StringName = "buffer_a"
var buffer_b : StringName = "buffer_b"

var custom_velocity : StringName = "custom_velocity"

var temp_intensity : float

var previous_time : float = 0

func _render_callback_2(render_size : Vector2i, render_scene_buffers : RenderSceneBuffersRD, render_scene_data : RenderSceneDataRD):
	var time : float = float(Time.get_ticks_msec()) / 1000
	
	var delta_time : float = time - previous_time
	
	previous_time = time
	
	temp_intensity = intensity
	
	if framerate_independent:
		var capped_frame_time : float = 1 / target_constant_framerate
		
		if !uncapped_independence:
			capped_frame_time = min(capped_frame_time, delta_time)
		
		temp_intensity = intensity * capped_frame_time / delta_time
	
	ensure_texture(custom_velocity, render_scene_buffers)
	ensure_texture(tile_max_x, render_scene_buffers, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Vector2(1. / sample_step_multiplier, 1.))
	ensure_texture(tile_max, render_scene_buffers, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Vector2(1. / sample_step_multiplier, 1. / sample_step_multiplier))
	ensure_texture(buffer_a, render_scene_buffers, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Vector2(1. / sample_step_multiplier, 1. / sample_step_multiplier))
	ensure_texture(buffer_b, render_scene_buffers, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Vector2(1. / sample_step_multiplier, 1. / sample_step_multiplier))
	ensure_texture(neighbor_max, render_scene_buffers, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, Vector2(1. / sample_step_multiplier, 1. / sample_step_multiplier))
	ensure_texture(output_color, render_scene_buffers)
	ensure_texture(past_color, render_scene_buffers)
	ensure_texture(past_velocity, render_scene_buffers)
	
	rd.draw_command_begin_label("Motion Blur", Color(1.0, 1.0, 1.0, 1.0))
	
	var last_iteration_index : int = JFA_pass_count - 1;
	
	var max_dilation_radius : float = pow(2 + step_exponent_modifier, last_iteration_index) * sample_step_multiplier / intensity;
	
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
		samples, 
		temp_intensity,
		center_fade,
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
		var past_color_image := render_scene_buffers.get_texture_slice(context, past_color, view, 0, 1, 1)
		var past_velocity_image := render_scene_buffers.get_texture_slice(context, past_velocity, view, 0, 1, 1)
		var buffer_a_image := render_scene_buffers.get_texture_slice(context, buffer_a, view, 0, 1, 1)
		var buffer_b_image := render_scene_buffers.get_texture_slice(context, buffer_b, view, 0, 1, 1)
		var custom_velocity_image := render_scene_buffers.get_texture_slice(context, custom_velocity, view, 0, 1, 1)
		var tile_max_x_image := render_scene_buffers.get_texture_slice(context, tile_max_x, view, 0, 1, 1)
		var tile_max_image := render_scene_buffers.get_texture_slice(context, tile_max, view, 0, 1, 1)
		var neighbor_max_image := render_scene_buffers.get_texture_slice(context, neighbor_max, view, 0, 1, 1)
		
		var x_groups := floori((render_size.x / sample_step_multiplier - 1) / 16 + 1)
		var y_groups := floori((render_size.y - 1) / 16 + 1)
		
		dispatch_stage(tile_max_x_stage, 
		[
			get_sampler_uniform(custom_velocity_image, 0, false),
			get_image_uniform(tile_max_x_image, 1)
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
			
			var jf_float_push_constants_test : PackedFloat32Array = [
				perpen_error_threshold,
				sample_step_multiplier,
				temp_intensity,
				0,
				0,
				0,
				0,
				step_exponent_modifier,
				0,
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
				get_sampler_uniform(buffer_b_image, 4, false),
			],
			jf_byte_array,
			Vector3i(x_groups, y_groups, 1), 
			"Construct Blur", 
			view)
		
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
			get_sampler_uniform(tile_max_image, 5, false),
			get_sampler_uniform(past_color_image, 6, false),
			get_sampler_uniform(past_velocity_image, 7, false)
		],
		byte_array,
		Vector3i(x_groups, y_groups, 1), 
		"Compute Blur", 
		view)
		
		dispatch_stage(cache_stage, 
		[
			get_sampler_uniform(custom_velocity_image, 0),
			get_sampler_uniform(color_image, 1),
			get_image_uniform(past_velocity_image, 2),
			get_image_uniform(past_color_image, 3),
		],
		[],
		Vector3i(x_groups, y_groups, 1), 
		"Past Color Copy", 
		view)
		
		dispatch_stage(overlay_stage, 
		[
			get_sampler_uniform(output_color_image, 0),
			get_image_uniform(color_image, 1),
		],
		[],
		Vector3i(x_groups, y_groups, 1), 
		"Overlay Result", 
		view)
	
	rd.draw_command_end_label()
