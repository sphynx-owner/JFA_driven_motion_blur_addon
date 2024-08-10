extends EnhancedCompositorEffect
class_name MotionBlurCompositorEffect

func _init():
	set_deferred("context", "MotionBlur")
	super()

func _get_max_dilation_range() -> float:
	return 0
