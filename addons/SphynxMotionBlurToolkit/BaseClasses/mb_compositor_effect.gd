extends "res://addons/SphynxMotionBlurToolkit/BaseClasses/enhanced_compositor_effect.gd"

@export_group("Motion Blur")
# diminishing returns over 16
@export_range(4, 64) var samples: int = 16
# you really don't want this over 0.5, but you can if you want to try
@export_range(0, 0.5, 0.001, "or_greater") var intensity: float = 1
@export_range(0, 1) var center_fade: float = 0.0

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

func _init():
	set_deferred("context", "MotionBlur")
	super()

func _get_max_dilation_range() -> float:
	return 0
