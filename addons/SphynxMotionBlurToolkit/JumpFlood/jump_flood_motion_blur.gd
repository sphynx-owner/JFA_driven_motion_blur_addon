extends "res://addons/SphynxMotionBlurToolkit/JumpFlood/base_jump_flood_motion_blur.gd"
class_name SphynxOldJumpFloodMotionBlur

@export_group("Shader Stages")
@export var blur_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/jump_flood_blur_stage.tres"):
	set(value):
		unsubscribe_shader_stage(blur_stage)
		blur_stage = value
		subscirbe_shader_stage(value)

@export var overlay_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/jump_flood_overlay_stage.tres"):
	set(value):
		unsubscribe_shader_stage(overlay_stage)
		overlay_stage = value
		subscirbe_shader_stage(value)

@export var construct_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/jump_flood_construction_stage.tres"):
	set(value):
		unsubscribe_shader_stage(construct_stage)
		construct_stage = value
		subscirbe_shader_stage(value)

## how many steps along a range of 2 velocities from the 
## dilation target velocity space do we go along to find a better fitting velocity sample
## higher samples meaning higher detail getting captured and blurred
@export var backtracking_sample_count : int = 8

## how sensitive the backtracking for velocities be
@export var backtracking_velocity_match_threshold : float = 0.9

## how sensitively the backtracking should treat velocities that are a different
## length along that velocity
@export var backtracking_velocity_match_parallel_sensitivity : float = 1

## how sensitively the backtracking should treat velcoities that have perpendicular
## offset to that velocity
@export var backtracking_velcoity_match_perpendicular_sensitivity : float = 0.05

## how closely does the depth of the backtracked sample has to match the original sample to be
## considered (in NDC space)
@export var backtracbing_depth_match_threshold : float = 0.001

var texture: StringName = "texture"

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
	

	ensure_texture(texture, render_scene_buffers)
	ensure_texture(buffer_a, render_scene_buffers)#, RenderingDevice.DATA_FORMAT_R16G16_SFLOAT)
	ensure_texture(buffer_b, render_scene_buffers)#, RenderingDevice.DATA_FORMAT_R16G16_SFLOAT)
	ensure_texture(custom_velocity, render_scene_buffers)
	
	rd.draw_command_begin_label("Motion Blur", Color(1.0, 1.0, 1.0, 1.0))
	
	var last_iteration_index : int = JFA_pass_count - 1;
	
	var max_dilation_radius : float = pow(2 + step_exponent_modifier, last_iteration_index) * sample_step_multiplier / intensity;
	
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
		var texture_image := render_scene_buffers.get_texture_slice(context, texture, view, 0, 1, 1)
		var buffer_a_image := render_scene_buffers.get_texture_slice(context, buffer_a, view, 0, 1, 1)
		var buffer_b_image := render_scene_buffers.get_texture_slice(context, buffer_b, view, 0, 1, 1)
		var custom_velocity_image := render_scene_buffers.get_texture_slice(context, custom_velocity, view, 0, 1, 1)
		
		rd.draw_command_begin_label("Construct blur " + str(view), Color(1.0, 1.0, 1.0, 1.0))
		
		var tex_uniform_set
		var compute_list
		
		var x_groups := floori((render_size.x - 1) / 16 + 1)
		var y_groups := floori((render_size.y - 1) / 16 + 1)
		
		tex_uniform_set = UniformSetCacheRD.get_cache(construct_stage.shader, 0, [
			get_sampler_uniform(depth_image, 0, false),
			get_sampler_uniform(custom_velocity_image, 1, false),
			get_image_uniform(buffer_a_image, 2),
			get_image_uniform(buffer_b_image, 3),
			get_sampler_uniform(buffer_a_image, 4, false),
			get_sampler_uniform(buffer_b_image, 5, false)
		])
		
		compute_list = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, construct_stage.pipeline)
		rd.compute_list_bind_uniform_set(compute_list, tex_uniform_set, 0)
		
		for i in JFA_pass_count:
			var jf_push_constants : PackedInt32Array = [
				i,
				last_iteration_index,
				backtracking_sample_count,
				16
			]
			
			var step_size : float = round(pow(2 + step_exponent_modifier, last_iteration_index - i)) * sample_step_multiplier;
			
			var jf_float_push_constants_test : PackedFloat32Array = [
				perpen_error_threshold,
				sample_step_multiplier,
				temp_intensity,
				backtracking_velocity_match_threshold,
				backtracking_velocity_match_parallel_sensitivity,
				backtracking_velcoity_match_perpendicular_sensitivity,
				backtracbing_depth_match_threshold,
				step_exponent_modifier,
				step_size,
				max_dilation_radius,
				0,
				0
			]
			
			var jf_byte_array = jf_push_constants.to_byte_array()
			jf_byte_array.append_array(jf_float_push_constants_test.to_byte_array())
			
			rd.compute_list_set_push_constant(compute_list, jf_byte_array, jf_byte_array.size())
			rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		
		rd.compute_list_end()
		
		rd.draw_command_end_label()
		
		dispatch_stage(blur_stage, 
		[
			get_sampler_uniform(color_image, 0, false),
			get_sampler_uniform(depth_image, 1, false),
			get_sampler_uniform(custom_velocity_image, 2, false),
			get_sampler_uniform(buffer_b_image if last_iteration_index % 2 else buffer_a_image, 3, false),
			get_image_uniform(texture_image, 4),
		],
		byte_array,
		Vector3i(x_groups, y_groups, 1), 
		"Compute Blur", 
		view)
		
		dispatch_stage(overlay_stage, 
		[
			get_sampler_uniform(texture_image, 0),
			get_image_uniform(color_image, 1)
		],
		[],
		Vector3i(x_groups, y_groups, 1), 
		"Overlay Result", 
		view)
	
	rd.draw_command_end_label()
