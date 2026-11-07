class_name ProcRock
extends Node3D
## A procedural rock prop (see [RockMeshes]). Picks a mesh variant in
## spawn order, so scatters stay deterministic without per-instance seeds.

const MATERIAL := preload("res://materials/rock_stylized.tres")

enum Kind { BOULDER, SPIRES }

@export var kind: Kind = Kind.BOULDER

static var _counter: int = 0


func _ready() -> void:
	_counter += 1
	match kind:
		Kind.BOULDER:
			_add(RockMeshes.boulder(_counter), Vector3.ZERO, 0.0, Vector3(1.2, 1.2, 1.2))
			if _counter % 3 == 0:
				_add(RockMeshes.boulder(_counter + 2), Vector3(1.1, 0.0, 0.6), 1.3, Vector3(0.55, 0.5, 0.55))
		Kind.SPIRES:
			_add(RockMeshes.spire(_counter), Vector3.ZERO, 0.0, Vector3(2.4, 3.6, 2.4))
			_add(RockMeshes.spire(_counter + 1), Vector3(2.6, 0.0, 1.2), 0.8, Vector3(1.6, 2.2, 1.6))
			_add(RockMeshes.boulder(_counter), Vector3(-2.0, 0.0, -1.4), 2.0, Vector3(1.4, 1.2, 1.4))


func _add(mesh: Mesh, pos: Vector3, yaw: float, sc: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MATERIAL
	mi.position = pos
	mi.rotation.y = yaw
	mi.scale = sc
	add_child(mi)
