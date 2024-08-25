extends "res://addons/SphynxMotionBlurToolkit/BaseClasses/enhanced_compositor_effect.gd"

# diminishing returns over 16
var samples: int = 16
# you really don't want this over 0.5, but you can if you want to try
var intensity: float = 1
var center_fade: float = 0.0

## wether this motion blur stays the same intensity below
## target_constant_framerate
var framerate_independent : bool = true

## Description: Removes clamping on motion blur scale to allow framerate independent motion
## blur to scale longer than realistically possible when render framerate is higher
## than target framerate.[br][br]
## [color=yellow]Warning:[/color] Turning this on would allow over-blurring of pixels, which 
## produces inaccurate results, and would likely cause nausea in players over
## long exposure durations, use with caution and out of artistic intent
var uncapped_independence : bool = false

## if framerate_independent is enabled, the blur would simulate 
## sutter speeds at that framerate, and up.
var target_constant_framerate : float = 30

func _init():
	needs_motion_vectors = true
	set_deferred("context", "MotionBlur")
	super()
