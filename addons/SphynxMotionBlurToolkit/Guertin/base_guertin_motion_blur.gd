extends "res://addons/SphynxMotionBlurToolkit/BaseClasses/mb_compositor_effect.gd"

@export_group("Shader Parameters")
@export var tile_size : int = 40

@export var linear_falloff_slope : float = 1

@export var importance_bias : float = 40

@export var maximum_jitter_value : float = 0.95

@export var minimum_user_threshold : float = 1.5
