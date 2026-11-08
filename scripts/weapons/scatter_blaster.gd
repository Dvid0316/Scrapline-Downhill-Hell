class_name ScatterBlaster
extends Node3D
## Close-range turret upgrade: a burst shotgun on the rear deck.
## It blasts a tight spread of pellets at the closest enemies in front.

@export var director: WaveDirector
@export var reach: float = 22.0
@export var damage: float = 12.0
@export var pellets: int = 7
@export var spread_degrees: float = 18.0

var level: int = 0: set = set_level
var interval: float = 1.8

var _cd: float = 0.4
var _mesh: MeshInstance3D


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.5, 0.7)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_mesh.position = Vector3(0.0, 0.3, 0.0)
	add_child(_mesh)
	set_level(level)


func set_level(v: int) -> void:
	level = v
	interval = maxf(1.8 - 0.2 * (v - 1), 0.8)
	visible = v > 0
	set_physics_process(v > 0)


func _physics_process(delta: float) -> void:
	_cd -= delta
	if _cd <= 0.0:
		if _fire():
			_cd = interval
		else:
			_cd = 0.15


func _fire() -> bool:
	if director == null or level <= 0:
		return false
	var best: EnemyBase = null
	var best_d := INF
	for e: EnemyBase in director.get_alive():
		if not e.active or e.is_destroyed:
			continue
		var d := e.get_effect_origin().distance_to(global_position)
		if d < reach and d < best_d:
			best_d = d
			best = e
	if best == null:
		return false
	var origin := global_position + Vector3.UP * 1.2
	var centre := best.get_effect_origin()
	for i in range(pellets + level):
		var dir := (centre - origin).normalized()
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
		var right := dir.cross(up).normalized()
		up = right.cross(dir).normalized()
		var a := randf() * TAU
		var r := tan(deg_to_rad(spread_degrees)) * randf()
		var spread_dir := (dir + right * cos(a) * r + up * sin(a) * r).normalized()
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.new())
		if hit.is_empty():
			continue
		var target := Damageable.find_in(hit.collider as Node)
		if target != null:
			target.apply_damage(damage, hit.position, hit.normal, self)
	_mesh.rotation = Vector3(0.0, _mesh.rotation.y + 0.25, 0.0)
	return true
