extends Compositor
class_name MotionBlurCompositor

@export_group("Motion Blur")
# diminishing returns over 16
@export_range(4, 64) var samples: int = 16 :
	set(value):
		for effect in compositor_effects:
			effect.set("samples", value)
		samples = value
# you really don't want this over 0.5, but you can if you want to try
@export_range(0, 0.5, 0.001, "or_greater") var intensity: float = 1 :
	set(value):
		for effect in compositor_effects:
			effect.set("intensity", value)
		intensity = value
@export_range(0, 1) var center_fade: float = 0.0 :
	set(value):
		for effect in compositor_effects:
			effect.set("center_fade", value)
		center_fade = value

## wether this motion blur stays the same intensity below
## target_constant_framerate
@export var framerate_independent : bool = true :
	set(value):
		for effect in compositor_effects:
			effect.set("framerate_independent", value)
		framerate_independent = value

## Description: Removes clamping on motion blur scale to allow framerate independent motion
## blur to scale longer than realistically possible when render framerate is higher
## than target framerate.[br][br]
## [color=yellow]Warning:[/color] Turning this on would allow over-blurring of pixels, which 
## produces inaccurate results, and would likely cause nausea in players over
## long exposure durations, use with caution and out of artistic intent
@export var uncapped_independence : bool = false :
	set(value):
		for effect in compositor_effects:
			effect.set("uncapped_independence", value)
		uncapped_independence = value

## if framerate_independent is enabled, the blur would simulate 
## sutter speeds at that framerate, and up.
@export var target_constant_framerate : float = 30 :
	set(value):
		for effect in compositor_effects:
			effect.set("target_constant_framerate", value)
		target_constant_framerate = value
