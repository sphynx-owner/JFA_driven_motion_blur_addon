extends CompositorEffect
class_name EnhancedCompositorEffect

var rd: RenderingDevice

var linear_sampler: RID

var nearest_sampler : RID

var context: StringName = "PostProcess"

var all_shader_stages : Dictionary

func _init():
	RenderingServer.call_on_render_thread(_initialize_compute)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if !rd:
			return
		if linear_sampler.is_valid():
			rd.free_rid(linear_sampler)
		if nearest_sampler.is_valid():
			rd.free_rid(nearest_sampler)
		for shader_stage in all_shader_stages.keys():
			if shader_stage.pipeline.is_valid():
				rd.free_rid(shader_stage.pipeline)
			if shader_stage.shader.is_valid():
				rd.free_rid(shader_stage.shader)

func subscirbe_shader_stage(shader_stage : ShaderStageResource):
	if all_shader_stages.has(shader_stage):
		return
	
	all_shader_stages[shader_stage] = 1
	
	if rd:
		generate_shader_stage(shader_stage)

func unsubscribe_shader_stage(shader_stage : ShaderStageResource):
	if all_shader_stages.has(shader_stage):
		all_shader_stages.erase(shader_stage)
		if !rd:
			return
		
		if shader_stage.shader.is_valid():
			rd.free_rid(shader_stage.shader)
		if shader_stage.pipeline.is_valid():
			rd.free_rid(shader_stage.pipeline)

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
	
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	
	nearest_sampler = rd.sampler_create(sampler_state)
	
	for shader_stage in all_shader_stages.keys():
		generate_shader_stage(shader_stage)

func generate_shader_stage(shader_stage : ShaderStageResource):
	var shader_spirv : RDShaderSPIRV = shader_stage.shader_file.get_spirv()
	shader_stage.shader = rd.shader_create_from_spirv(shader_spirv)
	shader_stage.pipeline = rd.compute_pipeline_create(shader_stage.shader)

func _render_callback(p_effect_callback_type, p_render_data):
	if !rd:
		return
	
	var render_scene_buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
	var render_scene_data: RenderSceneDataRD = p_render_data.get_render_scene_data()
	if !render_scene_buffers or !render_scene_data:
		return
	
	var render_size: Vector2i = render_scene_buffers.get_internal_size()
	
	if render_size.x == 0 or render_size.y == 0:
		return
		
	
	_render_callback_2(render_size, render_scene_buffers, render_scene_data)

func _render_callback_2(render_size : Vector2i, render_scene_buffers : RenderSceneBuffersRD, render_scene_data : RenderSceneDataRD):
	pass

func ensure_texture(texture_name : StringName, render_scene_buffers : RenderSceneBuffersRD, texture_format : RenderingDevice.DataFormat = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, render_size_multiplier : Vector2 = Vector2(1, 1)):
	var render_size : Vector2i = Vector2(render_scene_buffers.get_internal_size()) * render_size_multiplier
	
	if render_scene_buffers.has_texture(context, texture_name):
		var tf: RDTextureFormat = render_scene_buffers.get_texture_format(context, texture_name)
		if tf.width != render_size.x or tf.height != render_size.y:
			render_scene_buffers.clear_context(context)

	if !render_scene_buffers.has_texture(context, texture_name):
		var usage_bits: int = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		render_scene_buffers.create_texture(context, texture_name, texture_format, usage_bits, RenderingDevice.TEXTURE_SAMPLES_1, render_size, 1, 1, true)

func get_image_uniform(image: RID, binding: int) -> RDUniform:
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(image)
	return uniform

func get_sampler_uniform(image: RID, binding: int, linear : bool = true) -> RDUniform:
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = binding
	uniform.add_id(linear_sampler if linear else nearest_sampler)
	uniform.add_id(image)
	return uniform

func dispatch_stage(stage : ShaderStageResource, uniforms : Array[RDUniform], push_constants : PackedByteArray, dispatch_size : Vector3i, label : String = "DefaultLabel", view : int = 0, color : Color = Color(1, 1, 1, 1)):
	rd.draw_command_begin_label(label + " " + str(view), color)
	
	var tex_uniform_set = UniformSetCacheRD.get_cache(stage.shader, 0, uniforms)
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, stage.pipeline)
	rd.compute_list_bind_uniform_set(compute_list, tex_uniform_set, 0)
	
	if !push_constants.is_empty():
		rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
		
	rd.compute_list_dispatch(compute_list, dispatch_size.x, dispatch_size.y, dispatch_size.z)
	
	rd.compute_list_end()
	
	rd.draw_command_end_label()
