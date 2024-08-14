extends "res://addons/SphynxMotionBlurToolkit/BaseClasses/enhanced_compositor_effect.gd"
class_name DebugCompositorEffect

@export var overlay_stage : ShaderStageResource = preload("res://addons/SphynxMotionBlurToolkit/Debug/debug_overlay_shader_stage.tres"):
	set(value):
		unsubscribe_shader_stage(overlay_stage)
		overlay_stage = value
		subscirbe_shader_stage(value)

## wether to display debug views for velocity and depth 
## buffers
@export var draw_debug : bool = false

## currently 0 - 1, flip between velocity buffers
## and depth buffers debug views
@export var debug_page : int = 0

var past_color : StringName = "past_color"

var freeze : bool = false

func _init():
	set_deferred("context", "MotionBlur")
	set_deferred("debug", true)
	super()

func _render_callback_2(render_size : Vector2i, render_scene_buffers : RenderSceneBuffersRD, render_scene_data : RenderSceneDataRD):
	ensure_texture(past_color, render_scene_buffers)
	ensure_texture(debug_1, render_scene_buffers)
	ensure_texture(debug_2, render_scene_buffers)
	ensure_texture(debug_3, render_scene_buffers)
	ensure_texture(debug_4, render_scene_buffers)
	ensure_texture(debug_5, render_scene_buffers)
	ensure_texture(debug_6, render_scene_buffers)
	ensure_texture(debug_7, render_scene_buffers)
	ensure_texture(debug_8, render_scene_buffers)
	
	rd.draw_command_begin_label("Debug", Color(1.0, 1.0, 1.0, 1.0))
	
	if Input.is_action_just_pressed("freeze"):
		freeze = !freeze
	
	if Input.is_action_just_pressed("Z"):
		draw_debug = !draw_debug
	
	if Input.is_action_just_pressed("C"):
		debug_page = 1 if debug_page == 0 else 0
	
	var push_constant: PackedFloat32Array = [
		0,
		0,
		0, 
		0, 
	]
	var int_push_constant : PackedInt32Array = [
		freeze,
		draw_debug,
		debug_page,
		0
	]
	var byte_array = push_constant.to_byte_array()
	byte_array.append_array(int_push_constant.to_byte_array())
	
	var view_count = render_scene_buffers.get_view_count()
	for view in range(view_count):
		var color_image := render_scene_buffers.get_color_layer(view)
		var past_color_image := render_scene_buffers.get_texture_slice(context, past_color, view, 0, 1, 1)
		var debug_1_image := render_scene_buffers.get_texture_slice(context, debug_1, view, 0, 1, 1)
		var debug_2_image := render_scene_buffers.get_texture_slice(context, debug_2, view, 0, 1, 1)
		var debug_3_image := render_scene_buffers.get_texture_slice(context, debug_3, view, 0, 1, 1)
		var debug_4_image := render_scene_buffers.get_texture_slice(context, debug_4, view, 0, 1, 1)
		var debug_5_image := render_scene_buffers.get_texture_slice(context, debug_5, view, 0, 1, 1)
		var debug_6_image := render_scene_buffers.get_texture_slice(context, debug_6, view, 0, 1, 1)
		var debug_7_image := render_scene_buffers.get_texture_slice(context, debug_7, view, 0, 1, 1)
		var debug_8_image := render_scene_buffers.get_texture_slice(context, debug_8, view, 0, 1, 1)
		
		var x_groups := floori((render_size.x - 1) / 16 + 1)
		var y_groups := floori((render_size.y - 1) / 16 + 1)
		
		dispatch_stage(overlay_stage, 
		[
			get_image_uniform(past_color_image, 0),
			get_image_uniform(color_image, 1),
			get_sampler_uniform(color_image, 2),
			get_sampler_uniform(debug_1_image, 3),
			get_sampler_uniform(debug_2_image, 4),
			get_sampler_uniform(debug_3_image, 5),
			get_sampler_uniform(debug_4_image, 6),
			get_sampler_uniform(debug_5_image, 7),
			get_sampler_uniform(debug_6_image, 8),
			get_sampler_uniform(debug_7_image, 9),
			get_sampler_uniform(debug_8_image, 10),
		],
		byte_array,
		Vector3i(x_groups, y_groups, 1), 
		"Debug Overlay", 
		view)
	
	rd.draw_command_end_label()
