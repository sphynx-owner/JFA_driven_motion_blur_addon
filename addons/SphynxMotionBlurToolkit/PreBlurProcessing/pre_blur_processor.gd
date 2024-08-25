extends "res://addons/SphynxMotionBlurToolkit/BaseClasses/mb_compositor_effect.gd"
class_name PreBlurProcessor

@export_group("Shader Stages")
@export var pre_blur_processor_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/PreBlurProcessing/pre_blur_processing_stage.tres"):
	set(value):
		unsubscribe_shader_stage(pre_blur_processor_stage)
		pre_blur_processor_stage = value
		subscirbe_shader_stage(value)

@export_group("Blur Components")
@export var camera_rotation_component : BlurVelocityComponentResource = preload("res://addons/SphynxMotionBlurToolkit/PreBlurProcessing/default_camera_rotation_component.tres")
@export var camera_movement_component : BlurVelocityComponentResource = preload("res://addons/SphynxMotionBlurToolkit/PreBlurProcessing/default_camera_movement_component.tres")
@export var object_movement_component : BlurVelocityComponentResource = preload("res://addons/SphynxMotionBlurToolkit/PreBlurProcessing/default_object_movement_component.tres")

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
		temp_intensity,
		0,
	]
	
	var int_pre_blur_push_constants : PackedInt32Array = [
	]
	
	var byte_array = float_pre_blur_push_constants.to_byte_array()
	byte_array.append_array(int_pre_blur_push_constants.to_byte_array())
	
	var view_count = render_scene_buffers.get_view_count()
	
	for view in range(view_count):
		var depth_image := render_scene_buffers.get_depth_layer(view)
		var velocity_image := render_scene_buffers.get_velocity_layer(view)
		var custom_velocity_image := render_scene_buffers.get_texture_slice(context, custom_velocity, view, 0, 1, 1)
		var scene_data_buffer : RID = render_scene_data.get_uniform_buffer()
		var scene_data_buffer_uniform := RDUniform.new()
		scene_data_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		scene_data_buffer_uniform.binding = 5
		scene_data_buffer_uniform.add_id(scene_data_buffer)
		
		var x_groups := floori((render_size.x - 1) / 16 + 1)
		var y_groups := floori((render_size.y - 1) / 16 + 1)
		
		dispatch_stage(pre_blur_processor_stage, 
		[
			get_sampler_uniform(depth_image, 0, false),
			get_sampler_uniform(velocity_image, 1, false),
			get_image_uniform(custom_velocity_image, 2),
			scene_data_buffer_uniform
		],
		byte_array,
		Vector3i(x_groups, y_groups, 1), 
		"Process Velocity Buffer", 
		view)
	
	rd.draw_command_end_label()
