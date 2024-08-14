extends MeshInstance3D
class_name LinearMotionBlurMesh

@export var target_node : Node3D

## the rotation vector the current mesh blur's around
## locally
@export_enum("x", "y", "z") var local_stretch_axis : int 

@export var negate_local_stretch_axis : bool = false

@onready var local_stretch_vector : Vector3 = Vector3(1 if local_stretch_axis == 0 else 0, 1 if local_stretch_axis == 1 else 0, 1 if local_stretch_axis == 2 else 0) * (1 if !negate_local_stretch_axis else -1)

## At what speed does the mesh become visible and start blurring
@export var speed_visibility_threshold : float = 0.2

## make mesh visible for debugging
@export var show_debug : bool = false

var previous_mesh_transform : Transform3D = Transform3D()

var shape_depth : float = 0

func _ready():
	get_surface_override_material(0).set_shader_parameter("debug_color", Color(0, 0, 0, 0) if !show_debug else Color(1, 0, 0, 0))
	
	var mesh_aabb : AABB = mesh.get_aabb()
	
	var extent : Vector3 = mesh_aabb.size * global_basis.get_scale()
	
	var center : Vector3 = mesh_aabb.get_center() * global_basis.get_scale()
	
	var all_axis : Array[float] = [extent.x, extent.y, extent.z]
	
	shape_depth = all_axis[local_stretch_axis]
	
	previous_mesh_transform = target_node.global_transform
	
	deferred_update_cylinder_data.call_deferred()

func deferred_update_cylinder_data():
	get_surface_override_material(0).set_shader_parameter("local_stretch_axis", local_stretch_vector)

func _process(delta: float) -> void:
	var target_transform : Transform3D = target_node.global_transform
	
	var offset : Vector3 = target_transform.origin - previous_mesh_transform.origin
	
	var distance : float = (offset).length()
	
	visible = distance > speed_visibility_threshold
	
	get_surface_override_material(0).set_shader_parameter("movement_speed", distance / (distance + shape_depth))
	
	global_position = target_transform.origin - offset / 2
	
	previous_mesh_transform = target_transform
	
	var alignment_quaternion : Quaternion = Quaternion(global_basis.orthonormalized() * local_stretch_vector, offset.normalized())
	
	global_basis = Basis(alignment_quaternion) * global_basis;
	
	scale = scale * (Vector3(1, 1, 1) - local_stretch_vector) + local_stretch_vector * (distance + shape_depth)
