extends MeshInstance3D
class_name RadialBlurMesh

@export var target_node : Node3D

## the rotation vector the current mesh blur's around
## locally
@export_enum("x", "y", "z") var local_rotation_axis : int 

@export var negate_local_rotation_axis : bool = false

## the rotation vector that the target mesh spins along locally
@export_enum("x", "y", "z") var target_local_rotation_axis : int

@export var negate_target_local_rotation_axis : bool = false

## At what speed does the mesh become visible and start blurring
@export var speed_visibility_threshold : float = 0.2

## make mesh visible for debugging
@export var show_debug : bool = false

@onready var local_rotation_vector : Vector3 = Vector3(1 if local_rotation_axis == 0 else 0, 1 if local_rotation_axis == 1 else 0, 1 if local_rotation_axis == 2 else 0) * (1 if !negate_local_rotation_axis else -1)

@onready var target_local_rotation_vector : Vector3 = Vector3(1 if target_local_rotation_axis == 0 else 0, 1 if target_local_rotation_axis == 1 else 0, 1 if target_local_rotation_axis == 2 else 0) * (1 if !negate_target_local_rotation_axis else -1)

var mesh_last_rotation : float = 0;

var previous_mesh_basis : Basis = Basis()

var mesh_has_rotation_signal : bool = false

var signal_rotation_velocity : float = 0

var debug_toggle : float = 0

var axis_offset : float 

var shape_radius : float = 0

var shape_depth : float = 0

var shape_axis_offset : float = 0

func _ready():
	get_surface_override_material(0).set_shader_parameter("debug_color", Color(0, 0, 0, 0) if !show_debug else Color(1, 0, 0, 0))
	
	previous_mesh_basis = target_node.global_basis
	
	var target_rotation_vector : Vector3 = previous_mesh_basis.orthonormalized() * target_local_rotation_vector
	
	axis_offset = target_rotation_vector.dot(global_position - target_node.global_position)
	
	var mesh_aabb : AABB = mesh.get_aabb()
	
	var extent : Vector3 = mesh_aabb.size * global_basis.get_scale()
	
	var all_axis : Array[float] = [extent.x, extent.y, extent.z]
	
	var center : Vector3 = mesh_aabb.get_center() * global_basis.get_scale()
	
	var all_centers : Array[float] = [center.x, center.y, center.z]
	
	shape_depth = all_axis[local_rotation_axis]
	
	shape_axis_offset = all_centers[local_rotation_axis] * (1 if !negate_local_rotation_axis else -1)
	
	shape_radius = 0
	
	for i in all_axis.size():
		if i == local_rotation_axis:
			continue
		shape_radius = max(shape_radius, all_axis[i] / 2)
	
	#print(name, "has the shape depth of ", shape_depth, ", radius of ", shape_radius, " and axis offset of ", shape_axis_offset)
	
	if target_node.has_signal("rotation_velocity_signal"):
		mesh_has_rotation_signal = true
		target_node.rotation_velocity_signal.connect(on_rotation_velocity_signal)
	
	deferred_update_cylinder_data.call_deferred()

func on_rotation_velocity_signal(velocity : float):
	signal_rotation_velocity = velocity

func deferred_update_cylinder_data():
	get_surface_override_material(0).set_shader_parameter("shape_depth", shape_depth)
	get_surface_override_material(0).set_shader_parameter("shape_radius", shape_radius)
	get_surface_override_material(0).set_shader_parameter("shape_axis_offset", shape_axis_offset)
	get_surface_override_material(0).set_shader_parameter("local_rotation_axis", local_rotation_vector)

func _process(delta: float) -> void:
	var target_transform : Transform3D = target_node.global_transform
	
	var target_rotation_vector : Vector3 = target_transform.orthonormalized().basis * target_local_rotation_vector
	
	var current_mesh_basis : Basis = target_transform.basis
	
	var difference_quat : Quaternion = Quaternion(current_mesh_basis.get_rotation_quaternion() * previous_mesh_basis.get_rotation_quaternion().inverse())
	
	var centered_angle : float = difference_quat.get_angle() - PI
	
	var angle = (PI - abs(centered_angle)) * abs(target_rotation_vector.dot(difference_quat.get_axis()))
	
	if mesh_has_rotation_signal:
		angle = signal_rotation_velocity
	
	visible = abs(angle) > speed_visibility_threshold
	
	get_surface_override_material(0).set_shader_parameter("rotation_speed", clamp(angle, -TAU, TAU))
	
	previous_mesh_basis = current_mesh_basis
	
	global_position = target_transform.origin + target_rotation_vector * axis_offset
	
	var alignment_quaternion : Quaternion = Quaternion(global_basis.orthonormalized() * local_rotation_vector, target_rotation_vector)
	
	global_basis = Basis(alignment_quaternion) * global_basis;
