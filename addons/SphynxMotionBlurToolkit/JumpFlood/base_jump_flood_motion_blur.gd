extends "res://addons/SphynxMotionBlurToolkit/BaseClasses/mb_compositor_effect.gd"

@export_group("Shader Parameters")
## the portion of speed that is allowed for side bleed of velocities 
## during the jfa dilation passes and before backtracking. Getting this a higher value
## would make it so that meshes at movement blur more reliably, but also bleed 
## further perpendicularly to their velocity, thus wash elemets behind them out.
@export var perpen_error_threshold : float = 0.5

## an initial step size that can increase the dilation radius proportionally, at the 
## sacrifice of some quality in the final resolution of the dilation.[br][br]
## the formula for the maximum radius of the dilation (in pixels) is: pow(2 + step_exponent_modifier, JFA_pass_count) * sample_step_multiplier
@export var sample_step_multiplier : int = 16

## by default, the jump flood makes samples along distances that start
## at 2 to the power of the pass count you want to perform, which is also 
## the dilation radius you desire. You can change it to values higher than 
## 2 with this variable, and reach higher dilation radius at the sacrifice of
## some accuracy in the dilation.
## the formula for the maximum radius of the dilation (in pixels) is: pow(2 + step_exponent_modifier, JFA_pass_count) * sample_step_multiplier
@export var step_exponent_modifier : float = 1

## the number of passes performed by the jump flood algorithm based dilation, 
## each pass added doubles the maximum radius of dilation available.[br][br]
## the formula for the maximum radius of the dilation (in pixels) is: pow(2 + step_exponent_modifier, JFA_pass_count) * sample_step_multiplier
@export var JFA_pass_count : int = 3
