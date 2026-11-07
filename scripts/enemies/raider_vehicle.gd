class_name RaiderVehicle
extends EnemyBase
## Ground raider (buggy or gun truck). Spawns behind the train on the
## shoulder, races up alongside it, then holds an "attack slot" beside the
## train and fires bursts from its pintle gun. Every few seconds it picks a
## new slot, so it surges forward and drops back instead of sitting still.
##
## It drives on the terrain surface (height comes from TerrainBuilder) and
## tilts with the ground. Wheels named "Wheel*" spin with its road speed.

@export_group("Driving")
## Distance from the track centreline it drives at (metres, either side).
@export var lane: Vector2 = Vector2(8.5, 11.0)
## Where it spawns, in metres behind the train front.
@export var spawn_behind: Vector2 = Vector2(55.0, 75.0)
## Attack slots, in metres relative to the train front (train spans 0 to about -32).
@export var hold_range: Vector2 = Vector2(-28.0, 22.0)
## Top speed relative to the train while repositioning (m/s).
@export var approach_speed: float = 11.0
@export var approach_accel: float = 7.0
@export var retarget_time: Vector2 = Vector2(3.5, 6.5)
## Side-to-side weave while holding a slot (metres).
@export var weave: float = 0.7
@export var wheel_radius: float = 0.5
## Starts shooting once within this many metres of its slot.
@export var fire_window: float = 18.0

var side: int = 1
var _slot: float = 0.0
var _lane_goal: float = 9.0
var _retarget: float = 0.0
var _rel_vel: float = 0.0
var _t: float = 0.0
var _wheels: Array[Node3D] = []
var _wheel_angle: float = 0.0
var _smoothed_basis := Basis.IDENTITY
var _wreck_velocity := Vector3.ZERO


func _ready() -> void:
	super._ready()
	for n in find_children("Wheel*", "Node3D", true, false):
		_wheels.append(n)


func _on_spawn() -> void:
	side = -1 if rng.randf() < 0.5 else 1
	_lane_goal = rng.randf_range(lane.x, lane.y)
	lateral = side * _lane_goal
	rel_offset = -rng.randf_range(spawn_behind.x, spawn_behind.y)
	height = 0.0
	_rel_vel = approach_speed * 0.5
	_t = rng.randf() * 10.0
	_pick_slot()
	_smoothed_basis = Basis.IDENTITY
	_place(0.0)
	_smoothed_basis = global_basis


func _pick_slot() -> void:
	_slot = rng.randf_range(hold_range.x, hold_range.y)
	_retarget = rng.randf_range(retarget_time.x, retarget_time.y)
	if rng.randf() < 0.25:
		_lane_goal = rng.randf_range(lane.x, lane.y)


func _think(delta: float) -> void:
	_t += delta
	_retarget -= delta
	if _retarget <= 0.0:
		_pick_slot()
	var want := clampf((_slot - rel_offset) * 0.7, -approach_speed, approach_speed)
	_rel_vel = move_toward(_rel_vel, want, approach_accel * delta)
	rel_offset += _rel_vel * delta
	var goal := side * (_lane_goal + sin(_t * 1.3) * weave)
	lateral = move_toward(lateral, goal, 2.5 * delta)


func _place(delta: float) -> void:
	var p := frame_point(rel_offset, lateral, 0.0)
	p.y = terrain.sample_height(p.x, p.z) if terrain else p.y
	var fwd := frame_forward(rel_offset)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	# Ground normal from four height samples around the vehicle.
	var normal := Vector3.UP
	if terrain:
		var hf := terrain.sample_height(p.x + fwd.x * 1.4, p.z + fwd.z * 1.4)
		var hb := terrain.sample_height(p.x - fwd.x * 1.4, p.z - fwd.z * 1.4)
		var hr := terrain.sample_height(p.x + right.x * 1.0, p.z + right.z * 1.0)
		var hl := terrain.sample_height(p.x - right.x * 1.0, p.z - right.z * 1.0)
		var along := fwd * 2.8 + Vector3.UP * (hf - hb)
		var across := right * 2.0 + Vector3.UP * (hr - hl)
		normal = across.cross(along).normalized()
		if normal.y < 0.0:
			normal = -normal
	# Steer: nose turns slightly toward where it's heading sideways.
	var world_speed := maxf((train.speed if train else 0.0) + _rel_vel, 1.0)
	var lat_speed := (side * (_lane_goal) - lateral)
	var heading := (fwd * world_speed + right * clampf(lat_speed, -2.0, 2.0)).normalized()
	var z := -(heading - normal * heading.dot(normal)).normalized()
	var x := normal.cross(z).normalized()
	var target_basis := Basis(x, normal, z).orthonormalized()
	var k := 1.0 if delta <= 0.0 else 1.0 - exp(-10.0 * delta)
	_smoothed_basis = _smoothed_basis.slerp(target_basis, k).orthonormalized()
	# Suspension bob.
	var bob := sin(_t * 9.0) * 0.03 + sin(_t * 13.7) * 0.02
	global_transform = Transform3D(_smoothed_basis, p + normal * bob)
	_wheel_angle -= world_speed / maxf(wheel_radius, 0.1) * delta
	for w in _wheels:
		w.rotation.x = _wheel_angle


func _wants_to_fire() -> bool:
	return absf(_slot - rel_offset) < fire_window


## Wreck: coasts to a stop in the world (no longer keeps pace with the train).
func _on_wrecked() -> void:
	var fwd := frame_forward(rel_offset)
	_wreck_velocity = fwd * ((train.speed if train else 0.0) + _rel_vel)


func _wreck_update(delta: float) -> void:
	_wreck_velocity = _wreck_velocity.move_toward(Vector3.ZERO, 14.0 * delta)
	var p := global_position + _wreck_velocity * delta
	if terrain:
		p.y = terrain.sample_height(p.x, p.z)
	global_position = p
