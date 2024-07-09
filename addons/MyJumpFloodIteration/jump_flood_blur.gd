extends CompositorEffect
class_name MotionBlurSphynxJumpFlood

@export_group("Motion Blur", "motion_blur_")
# diminishing returns over 16
@export_range(4, 64) var motion_blur_samples: int = 8
# you really don't want this over 0.5, but you can if you want to try
@export_range(0, 0.5, 0.001, "or_greater") var motion_blur_intensity: float = 1
@export_range(0, 1) var motion_blur_center_fade: float = 0.0


@export var blur_shader_file : RDShaderFile = preload("res://addons/MyJumpFloodIteration/jump_flood_blur.glsl"):
	set(value):
		blur_shader_file = value
		_init()

@export var overlay_shader_file : RDShaderFile = preload("res://addons/MyJumpFloodIteration/jump_flood_overlay.glsl"):
	set(value):
		overlay_shader_file = value
		_init()

@export var construction_pass : RDShaderFile = preload("res://addons/MyJumpFloodIteration/jfp_backtracking_experimental.glsl"):
	set(value):
		construction_pass = value
		_init()

## the portion of speed that is allowed for side bleed of velocities 
## during the jfa dilation passes and before backtracking. Getting this a higher value
## would make it so that meshes at movement blur more reliably, but also bleed 
## further perpendicularly to their velocity, thus wash elemets behind them out.
@export var perpen_error_threshold : float = 0.3

## an initial step size that can increase the dilation radius proportionally, at the 
## sacrifice of some quality in the final resolution of the dilation.[br][br]
## the formula for the maximum radius of the dilation (in pixels) is: pow(2, JFA_pass_count) * sample_step_multiplier
@export var sample_step_multiplier : float = 8

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
## the formula for the maximum radius of the dilation (in pixels) is: pow(2, JFA_pass_count) * sample_step_multiplier
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

var rd: RenderingDevice

var linear_sampler: RID

var construct_shader : RID
var construct_pipeline : RID

var motion_blur_shader: RID
var motion_blur_pipeline: RID

var overlay_shader: RID
var overlay_pipeline: RID

var context: StringName = "MotionBlur"
var texture: StringName = "texture"

var buffer_a : StringName = "buffer_a"
var buffer_b : StringName = "buffer_b"

var past_color : StringName = "past_color"

var velocity_3D : StringName = "velocity_3D"
var velocity_curl : StringName = "velocity_curl"

var draw_debug : float = 0

var freeze : bool = false

func _init():
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = true
	RenderingServer.call_on_render_thread(_initialize_compute)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if linear_sampler.is_valid():
			rd.free_rid(linear_sampler)
		if motion_blur_shader.is_valid():
			rd.free_rid(motion_blur_shader)
		if overlay_shader.is_valid():
			rd.free_rid(overlay_shader)

func _initialize_compute():
	rd = RenderingServer.get_rendering_device()
	if !rd:
		return

	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	linear_sampler = rd.sampler_create(sampler_state)

	var construct_shader_spirv : RDShaderSPIRV = construction_pass.get_spirv()
	construct_shader = rd.shader_create_from_spirv(construct_shader_spirv)
	construct_pipeline = rd.compute_pipeline_create(construct_shader)

	var shader_spirv: RDShaderSPIRV = blur_shader_file.get_spirv()
	motion_blur_shader = rd.shader_create_from_spirv(shader_spirv)
	motion_blur_pipeline = rd.compute_pipeline_create(motion_blur_shader)

	var overlay_shader_spirv: RDShaderSPIRV = overlay_shader_file.get_spirv()
	overlay_shader = rd.shader_create_from_spirv(overlay_shader_spirv)
	overlay_pipeline = rd.compute_pipeline_create(overlay_shader)

func get_image_uniform(image: RID, binding: int) -> RDUniform:
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(image)
	return uniform

func get_sampler_uniform(image: RID, binding: int) -> RDUniform:
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = binding
	uniform.add_id(linear_sampler)
	uniform.add_id(image)
	return uniform

var temp_motion_blur_intensity : float

var previous_time : float = 0

func _render_callback(p_effect_callback_type, p_render_data):
	var time : float = float(Time.get_ticks_msec()) / 1000
	
	var delta_time : float = time - previous_time
	
	previous_time = time
	
	temp_motion_blur_intensity = motion_blur_intensity
	
	if framerate_independent:
		var capped_frame_time : float = 1 / target_constant_framerate
		
		if !uncapped_independence:
			capped_frame_time = min(capped_frame_time, delta_time)
		
		temp_motion_blur_intensity = motion_blur_intensity * capped_frame_time / delta_time
	
	if rd and p_effect_callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		var render_scene_buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
		var render_scene_data: RenderSceneDataRD = p_render_data.get_render_scene_data()
		if render_scene_buffers and render_scene_data:
			var render_size: Vector2 = render_scene_buffers.get_internal_size()
			if render_size.x == 0.0 or render_size.y == 0.0:
				return
			
			ensure_texture(texture, render_scene_buffers)
			ensure_texture(buffer_a, render_scene_buffers)
			ensure_texture(buffer_b, render_scene_buffers)
			ensure_texture(past_color, render_scene_buffers)

			rd.draw_command_begin_label("Motion Blur", Color(1.0, 1.0, 1.0, 1.0))
			
			var last_iteration_index : int = JFA_pass_count - 1;
			
			var push_constant: PackedFloat32Array = [
				motion_blur_samples, temp_motion_blur_intensity,
				motion_blur_center_fade, draw_debug,
				freeze, 
				Engine.get_frames_drawn() % 8, 
				last_iteration_index, 
				sample_step_multiplier
			]

			var view_count = render_scene_buffers.get_view_count()
			for view in range(view_count):
				var color_image := render_scene_buffers.get_color_layer(view)
				var depth_image := render_scene_buffers.get_depth_layer(view)
				var velocity_image := render_scene_buffers.get_velocity_layer(view)
				var texture_image := render_scene_buffers.get_texture_slice(context, texture, view, 0, 1, 1)
				var buffer_a_image := render_scene_buffers.get_texture_slice(context, buffer_a, view, 0, 1, 1)
				var buffer_b_image := render_scene_buffers.get_texture_slice(context, buffer_b, view, 0, 1, 1)
				var past_color_image := render_scene_buffers.get_texture_slice(context, past_color, view, 0, 1, 1)
				rd.draw_command_begin_label("Construct blur " + str(view), Color(1.0, 1.0, 1.0, 1.0))
				
				var tex_uniform_set
				var compute_list
				
				var x_groups := floori((render_size.x - 1) / 8 + 1)
				var y_groups := floori((render_size.y - 1) / 8 + 1)
				
				tex_uniform_set = UniformSetCacheRD.get_cache(construct_shader, 0, [
					get_sampler_uniform(depth_image, 0),
					get_sampler_uniform(velocity_image, 1),
					get_image_uniform(buffer_a_image, 2),
					get_image_uniform(buffer_b_image, 3),
				])
				
				compute_list = rd.compute_list_begin()
				rd.compute_list_bind_compute_pipeline(compute_list, construct_pipeline)
				rd.compute_list_bind_uniform_set(compute_list, tex_uniform_set, 0)
				
				for i in JFA_pass_count:
					var jf_push_constants : PackedInt32Array = [
						i,
						last_iteration_index,
						backtracking_sample_count,
						16
					]
					
					var jf_float_push_constants_test : PackedFloat32Array = [
						perpen_error_threshold,
						sample_step_multiplier,
						temp_motion_blur_intensity,
						backtracking_velocity_match_threshold,
						backtracking_velocity_match_parallel_sensitivity,
						backtracking_velcoity_match_perpendicular_sensitivity,
						backtracbing_depth_match_threshold,
						0
					]
					
					var jf_byte_array = jf_push_constants.to_byte_array()
					jf_byte_array.append_array(jf_float_push_constants_test.to_byte_array())
					
					rd.compute_list_set_push_constant(compute_list, jf_byte_array, jf_byte_array.size())
					rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
				
				rd.compute_list_end()
				
				rd.draw_command_end_label()
				
				rd.draw_command_begin_label("Compute blur " + str(view), Color(1.0, 1.0, 1.0, 1.0))

				tex_uniform_set = UniformSetCacheRD.get_cache(motion_blur_shader, 0, [
					get_sampler_uniform(color_image, 0),
					get_sampler_uniform(depth_image, 1),
					get_sampler_uniform(velocity_image, 2),
					get_image_uniform(buffer_b_image if last_iteration_index % 2 else buffer_a_image, 3),
					get_image_uniform(texture_image, 4),
					get_image_uniform(past_color_image, 5),
				])

				compute_list = rd.compute_list_begin()
				rd.compute_list_bind_compute_pipeline(compute_list, motion_blur_pipeline)
				rd.compute_list_bind_uniform_set(compute_list, tex_uniform_set, 0)
				rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
				rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
				rd.compute_list_end()
				rd.draw_command_end_label()

				rd.draw_command_begin_label("Overlay result " + str(view), Color(1.0, 1.0, 1.0, 1.0))

				tex_uniform_set = UniformSetCacheRD.get_cache(overlay_shader, 0, [
					get_sampler_uniform(texture_image, 0),
					get_image_uniform(color_image, 1),
				])

				compute_list = rd.compute_list_begin()
				rd.compute_list_bind_compute_pipeline(compute_list, overlay_pipeline)
				rd.compute_list_bind_uniform_set(compute_list, tex_uniform_set, 0)
				rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
				rd.compute_list_end()
				rd.draw_command_end_label()

			rd.draw_command_end_label()


func ensure_texture(texture_name : StringName, render_scene_buffers : RenderSceneBuffersRD, high_accuracy : bool = false, render_size_multiplier : Vector2 = Vector2(1, 1)):
	var render_size : Vector2 = Vector2(render_scene_buffers.get_internal_size()) * render_size_multiplier
	
	if render_scene_buffers.has_texture(context, texture_name):
		var tf: RDTextureFormat = render_scene_buffers.get_texture_format(context, texture_name)
		if tf.width != render_size.x or tf.height != render_size.y:
			render_scene_buffers.clear_context(context)

	if !render_scene_buffers.has_texture(context, texture_name):
		var usage_bits: int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		var texture_format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT if high_accuracy else RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		render_scene_buffers.create_texture(context, texture_name, texture_format, usage_bits, RenderingDevice.TEXTURE_SAMPLES_1, render_size, 1, 1, true)
