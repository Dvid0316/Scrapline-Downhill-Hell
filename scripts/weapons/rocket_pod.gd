class_name RocketPod
extends Node3D
## Upgrade weapon: a four-tube launcher on the gun car's rear deck. Every
## [member interval] seconds it fires a volley of homing rockets, one per
## enemy (nearest first). They pop out of the tubes, curl round onto their
## target and burst with splash damage. Fully automatic.
##
## Level 0 = not owned (hidden, idle). The UpgradeManager sets [member level].

signal rocket_fired(origin: Vector3)
signal rocket_burst(point: Vector3, radius: float)

@export var director: WaveDirector
@export var reach: float = 150.0
@export var damage: float = 60.0
@export var splash_radius: float = 4.5
@export var top_speed: float = 75.0
@export var life: float = 5.0
@export var fuse_radius: float = 2.2

var level: int = 0: set = set_level
var interval: float = 3.5
var volley: int = 2
var fired: int = 0

var _cd: float = 1.0
var _queue: Array[EnemyBase] = []
var _queue_cd: float = 0.0
var _tube: int = 0
var _rockets: Array[Dictionary] = []
var _query := PhysicsRayQueryParameters3D.new()
static var _pod_mesh: ArrayMesh
static var _rocket_mesh: ArrayMesh

const DARK := preload("res://materials/armor_dark.tres")
const PLATE := preload("res://materials/armor_plate.tres")
const STEEL := preload("res://materials/steel_worn.tres")
const HAZARD := preload("res://materials/hazard_yellow.tres")
const RED := preload("res://materials/barrel_red.tres")
const TILT := 40.0  ## launcher elevation, degrees
const TUBES := [Vector2(-0.2, 0.17), Vector2(0.2, 0.17), Vector2(-0.2, -0.17), Vector2(0.2, -0.17)]


func _ready() -> void:
	if _pod_mesh == null:
		_pod_mesh = _build_pod()
		_rocket_mesh = _build_rocket()
	var m := MeshInstance3D.new()
	m.name = "Launcher"
	m.mesh = _pod_mesh
	add_child(m)
	_query.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.ENEMIES
	set_level(level)


func set_level(v: int) -> void:
	level = v
	volley = v + 1
	interval = maxf(3.5 - 0.5 * (v - 1), 2.0)
	visible = v > 0
	set_physics_process(v > 0 or not _rockets.is_empty())


## Clear rockets in flight (new run).
func reset() -> void:
	for r in _rockets:
		(r.node as Node3D).queue_free()
	_rockets.clear()
	_queue.clear()
	_cd = 1.0


func _physics_process(delta: float) -> void:
	_fly(delta)
	if level <= 0:
		if _rockets.is_empty():
			set_physics_process(false)
		return
	_cd -= delta
	if _cd <= 0.0 and _queue.is_empty():
		_queue = _pick_targets()
		_cd = interval if not _queue.is_empty() else 0.3
	_queue_cd -= delta
	if not _queue.is_empty() and _queue_cd <= 0.0:
		var t: EnemyBase = _queue.pop_front()
		if t.active and not t.is_destroyed:
			launch(t)
		_queue_cd = 0.14


func _pick_targets() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	if director == null:
		return out
	var cands: Array = []
	for e: EnemyBase in director.get_alive():
		if e.active and not e.is_destroyed:
			var d := e.get_effect_origin().distance_to(global_position)
			if d < reach:
				cands.append([d, e])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(volley, cands.size()):
		out.append(cands[i][1])
	# Fewer enemies than rockets: the rest double up on the nearest.
	var i := 0
	while not out.is_empty() and out.size() < volley and i < volley:
		out.append(out[i % out.size()])
		i += 1
	return out


## Fire one rocket at [param target] right now.
func launch(target: EnemyBase) -> void:
	var tube: Vector2 = TUBES[_tube % TUBES.size()]
	_tube += 1
	var aim := Basis(Vector3.RIGHT, deg_to_rad(TILT))
	var origin := global_transform * (Vector3(0, 0.55, 0) + aim * Vector3(tube.x, tube.y, -0.5))
	var dir := (global_transform.basis * (aim * Vector3.FORWARD)).normalized()
	var node := Node3D.new()
	node.top_level = true
	add_child(node)
	node.global_position = origin
	var body := MeshInstance3D.new()
	body.mesh = _rocket_mesh
	node.add_child(body)
	var trail := PuffFx.make("Trail", PuffFx.ramp([
		[0.0, Color(1.0, 0.85, 0.5, 0.9)], [0.12, Color(0.85, 0.82, 0.78, 0.0)], [1.0, Color(0.6, 0.6, 0.62, 0.0)]]),
		40, 0.7, Vector2(0.28, 0.5))
	trail.direction = Vector3.ZERO
	trail.spread = 180.0
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.8
	trail.gravity = Vector3(0, 0.6, 0)
	trail.position = Vector3(0, 0, 0.4)
	node.add_child(trail)
	trail.emitting = true
	_rockets.append({"node": node, "trail": trail, "vel": dir * 16.0, "target": target,
		"aim": target.get_effect_origin(), "age": 0.0})
	node.look_at(origin + dir, Vector3.UP)
	fired += 1
	set_physics_process(true)
	rocket_fired.emit(origin)


func _fly(delta: float) -> void:
	if _rockets.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for i in range(_rockets.size() - 1, -1, -1):
		var r: Dictionary = _rockets[i]
		var node: Node3D = r.node
		var t: EnemyBase = r.target
		if is_instance_valid(t) and t.active and not t.is_destroyed:
			r.aim = t.get_effect_origin()
		r.age += delta
		var pos := node.global_position
		var vel: Vector3 = r.vel
		var to: Vector3 = r.aim - pos
		# Turn harder the longer it flies, so it always lands.
		var turn := clampf(r.age * 9.0, 2.0, 14.0)
		var dir := vel.normalized().slerp(to.normalized(), minf(turn * delta, 1.0))
		var spd := minf(vel.length() + 70.0 * delta, top_speed)
		vel = dir * spd
		r.vel = vel
		var next := pos + vel * delta
		var burst := Vector3.INF
		if r.age > 0.12:
			_query.from = pos
			_query.to = next
			var hit := space.intersect_ray(_query)
			if not hit.is_empty():
				burst = hit.position
		if burst == Vector3.INF:
			# Proximity fuse along the whole step, not just its end: at 75 m/s
			# a rocket moves over a metre per frame.
			var close := Geometry3D.get_closest_point_to_segment(r.aim, pos, next)
			if close.distance_to(r.aim) < fuse_radius:
				burst = close
		if burst == Vector3.INF and r.age > life:
			burst = next
		if burst != Vector3.INF:
			_burst(burst)
			node.queue_free()
			_rockets.remove_at(i)
			continue
		node.global_position = next
		if vel.length_squared() > 0.01:
			node.look_at(next + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.RIGHT)


func _burst(point: Vector3) -> void:
	if is_inside_tree():
		Damageable.damage_area(get_tree(), point, splash_radius, damage, self)
	rocket_burst.emit(point, splash_radius)


static func _build_pod() -> ArrayMesh:
	var k := CarKit.new()
	# Swivel base on the deck.
	k.cylp(DARK, 0.42, 0.14, Vector3(0, 0.07, 0), Vector3.ZERO, 10)
	k.boxp(STEEL, Vector3(0.22, 0.42, 0.22), Vector3(0, 0.3, 0), Vector3.ZERO, 0.03)
	# Tube box, tilted up.
	var aim := Basis(Vector3.RIGHT, deg_to_rad(TILT))
	var c := Vector3(0, 0.55, 0)
	k.box(PLATE, Vector3(0.72, 0.6, 1.1), Transform3D(aim, c), 0.06)
	k.box(HAZARD, Vector3(0.74, 0.1, 0.4), Transform3D(aim, c + aim * Vector3(0, 0.0, 0.3)), 0.0)
	for t: Vector2 in TUBES:
		var p := c + aim * Vector3(t.x, t.y, -0.56)
		k.cyl(DARK, 0.13, 0.13, 0.06, Transform3D(aim * Basis(Vector3.RIGHT, PI / 2.0), p), 10)
		k.cyl(RED, 0.07, 0.07, 0.07, Transform3D(aim * Basis(Vector3.RIGHT, PI / 2.0), p + aim * Vector3(0, 0, 0.02)), 8)
	return k.commit()


static func _build_rocket() -> ArrayMesh:
	var k := CarKit.new()
	var along := Basis(Vector3.RIGHT, PI / 2.0)  # cylinder Y -> Z
	k.cyl(STEEL, 0.09, 0.09, 0.7, Transform3D(along, Vector3.ZERO), 8)
	k.cyl(RED, 0.0, 0.09, 0.26, Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0, -0.48)), 8)
	for a in 4:
		var b := Basis(Vector3.FORWARD, a * PI / 2.0)
		k.box(DARK, Vector3(0.02, 0.32, 0.2), Transform3D(b, b * Vector3(0, 0.12, 0.28)), 0.0)
	return k.commit()
