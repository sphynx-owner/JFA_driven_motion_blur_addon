extends CompositorEffect
class_name PreBlurProcessor

@export var pre_blur_processor_shader_file : RDShaderFile = preload("res://addons/PreBlurProcessing/pre_blur_processor.glsl"):
	set(value):
		pre_blur_processor_shader_file = value
		_init()

@export var camera_rotation_component : BlurVelocityComponentResource = BlurVelocityComponentResource.new()
@export var camera_movement_component : BlurVelocityComponentResource = BlurVelocityComponentResource.new()
@export var object_movement_component : BlurVelocityComponentResource = BlurVelocityComponentResource.new()

var context: StringName = "MotionBlur"

var rd: RenderingDevice

var linear_sampler: RID

var construct_shader : RID
var construct_pipeline : RID

var pre_blur_processor_shader: RID
var pre_blur_processor_pipeline: RID

var custom_velocity : StringName = "custom_velocity"

func _init():
	needs_motion_vectors = true
	RenderingServer.call_on_render_thread(_initialize_compute)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if linear_sampler.is_valid():
			rd.free_rid(linear_sampler)
		if pre_blur_processor_shader.is_valid():
			rd.free_rid(pre_blur_processor_shader)

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

	var shader_spirv: RDShaderSPIRV = pre_blur_processor_shader_file.get_spirv()
	pre_blur_processor_shader = rd.shader_create_from_spirv(shader_spirv)
	pre_blur_processor_pipeline = rd.compute_pipeline_create(pre_blur_processor_shader)

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

func _render_callback(p_effect_callback_type, p_render_data : RenderData):
	if rd:
		var render_scene_buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
		var render_scene_data: RenderSceneDataRD = p_render_data.get_render_scene_data()
		if render_scene_buffers and render_scene_data:
			var render_size: Vector2 = render_scene_buffers.get_internal_size()
			if render_size.x == 0.0 or render_size.y == 0.0:
				return
			
			ensure_texture(custom_velocity, render_scene_buffers)
			
			rd.draw_command_begin_label("Pre Blur Processing", Color(1.0, 1.0, 1.0, 1.0))
			
			var float_pre_blur_push_constants: PackedFloat32Array = [
				camera_rotation_component.multiplier,
				camera_movement_component.multiplier,
				object_movement_component.multiplier,
				camera_rotation_component.lower_threshold,
				camera_movement_component.lower_threshold,
				object_movement_component.lower_threshold,
				camera_rotation_component.upper_threshold,
				camera_movement_component.upper_threshold,
				object_movement_component.upper_threshold,
				1 if true else 0,
				0,
				0,
			]
			
			var int_pre_blur_push_constants : PackedInt32Array = [
			]
			
			var byte_array = float_pre_blur_push_constants.to_byte_array()
			byte_array.append_array(int_pre_blur_push_constants.to_byte_array())
			
			var view_count = render_scene_buffers.get_view_count()
			for view in range(view_count):
				var color_image := render_scene_buffers.get_color_layer(view)
				var depth_image := render_scene_buffers.get_depth_layer(view)
				var velocity_image := render_scene_buffers.get_velocity_layer(view)
				var custom_velocity_image := render_scene_buffers.get_texture_slice(context, custom_velocity, view, 0, 1, 1)
				var scene_data_buffer : RID = render_scene_data.get_uniform_buffer()
				var scene_data_buffer_uniform := RDUniform.new()
				scene_data_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
				scene_data_buffer_uniform.binding = 5
				scene_data_buffer_uniform.add_id(scene_data_buffer)
				
				var tex_uniform_set
				var compute_list
				
				var x_groups := floori((render_size.x - 1) / 16 + 1)
				var y_groups := floori((render_size.y - 1) / 16 + 1)
				
				rd.draw_command_begin_label("Process Velocity Buffer " + str(view), Color(1.0, 1.0, 1.0, 1.0))

				tex_uniform_set = UniformSetCacheRD.get_cache(pre_blur_processor_shader, 0, [
					get_sampler_uniform(color_image, 0),
					get_sampler_uniform(depth_image, 1),
					get_sampler_uniform(velocity_image, 2),
					get_image_uniform(custom_velocity_image, 3),
					get_image_uniform(color_image, 4),
					scene_data_buffer_uniform,
				])

				compute_list = rd.compute_list_begin()
				rd.compute_list_bind_compute_pipeline(compute_list, pre_blur_processor_pipeline)
				rd.compute_list_bind_uniform_set(compute_list, tex_uniform_set, 0)
				rd.compute_list_set_push_constant(compute_list, byte_array, byte_array.size())
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
