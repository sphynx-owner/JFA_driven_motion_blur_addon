extends MotionBlurCompositorEffect
class_name SphynxOldJumpFloodMotionBlur

@export_group("Motion Blur", "motion_blur_")
# diminishing returns over 16
@export_range(4, 64) var motion_blur_samples: int = 8
# you really don't want this over 0.5, but you can if you want to try
@export_range(0, 0.5, 0.001, "or_greater") var motion_blur_intensity: float = 1
@export_range(0, 1) var motion_blur_center_fade: float = 0.0

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

## the portion of speed that is allowed for side bleed of velocities 
## during the jfa dilation passes and before backtracking. Getting this a higher value
## would make it so that meshes at movement blur more reliably, but also bleed 
## further perpendicularly to their velocity, thus wash elemets behind them out.
@export var perpen_error_threshold : float = 0.5

## an initial step size that can increase the dilation radius proportionally, at the 
## sacrifice of some quality in the final resolution of the dilation.[br][br]
## the formula for the maximum radius of the dilation (in pixels) is: pow(2 + step_exponent_modifier, JFA_pass_count) * sample_step_multiplier
@export var sample_step_multiplier : float = 16

## by default, the jump flood makes samples along distances that start
## at 2 to the power of the pass count you want to perform, which is also 
## the dilation radius you desire. You can change it to values higher than 
## 2 with this variable, and reach higher dilation radius at the sacrifice of
## some accuracy in the dilation.
## the formula for the maximum radius of the dilation (in pixels) is: pow(2 + step_exponent_modifier, JFA_pass_count) * sample_step_multiplier
@export var step_exponent_modifier : float = 1

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

var texture: StringName = "texture"

var buffer_a : StringName = "buffer_a"
var buffer_b : StringName = "buffer_b"

var custom_velocity : StringName = "custom_velocity"

@export var debug_1 : String = "debug_1"
@export var debug_2 : String = "debug_2"
@export var debug_3 : String = "debug_3"
@export var debug_4 : String = "debug_4"
@export var debug_5 : String = "debug_5"
@export var debug_6 : String = "debug_6"
@export var debug_7 : String = "debug_7"
@export var debug_8 : String = "debug_8"

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
	

	ensure_texture(texture, render_scene_buffers)
	ensure_texture(buffer_a, render_scene_buffers)#, RenderingDevice.DATA_FORMAT_R16G16_SFLOAT)
	ensure_texture(buffer_b, render_scene_buffers)#, RenderingDevice.DATA_FORMAT_R16G16_SFLOAT)
	ensure_texture(custom_velocity, render_scene_buffers)
	
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
		var texture_image := render_scene_buffers.get_texture_slice(context, texture, view, 0, 1, 1)
		var buffer_a_image := render_scene_buffers.get_texture_slice(context, buffer_a, view, 0, 1, 1)
		var buffer_b_image := render_scene_buffers.get_texture_slice(context, buffer_b, view, 0, 1, 1)
		var custom_velocity_image := render_scene_buffers.get_texture_slice(context, custom_velocity, view, 0, 1, 1)
		var debug_1_image := render_scene_buffers.get_texture_slice(context, debug_1, view, 0, 1, 1)
		var debug_2_image := render_scene_buffers.get_texture_slice(context, debug_2, view, 0, 1, 1)
		var debug_3_image := render_scene_buffers.get_texture_slice(context, debug_3, view, 0, 1, 1)
		var debug_4_image := render_scene_buffers.get_texture_slice(context, debug_4, view, 0, 1, 1)
		var debug_5_image := render_scene_buffers.get_texture_slice(context, debug_5, view, 0, 1, 1)
		var debug_6_image := render_scene_buffers.get_texture_slice(context, debug_6, view, 0, 1, 1)
		var debug_7_image := render_scene_buffers.get_texture_slice(context, debug_7, view, 0, 1, 1)
		var debug_8_image := render_scene_buffers.get_texture_slice(context, debug_8, view, 0, 1, 1)
		
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
				temp_motion_blur_intensity,
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
			get_image_uniform(debug_1_image, 5),
			get_image_uniform(debug_2_image, 6),
			get_image_uniform(debug_3_image, 7),
			get_image_uniform(debug_4_image, 8),
			get_image_uniform(debug_5_image, 9),
			get_image_uniform(debug_6_image, 10),
			get_image_uniform(debug_7_image, 11),
			get_image_uniform(debug_8_image, 12),
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
