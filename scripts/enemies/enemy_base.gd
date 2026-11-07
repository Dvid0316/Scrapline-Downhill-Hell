class_name EnemyBase
extends Damageable
## Base class for enemy vehicles and drones.
##
## Enemies are [Damageable]s, so scoring, explosions, popups and hit markers
## work for them exactly like for range targets. On top of that they move,
## shoot at the train, and get pooled by the [WaveDirector] (spawned and
## despawned, never freed during a run).
##
## Movement happens in the TRACK FRAME, relative to the train:
##   rel_offset  metres along the route from the train's front (+ = ahead)
##   lateral     metres sideways from the track centreline (+ = right)
##   height      metres above the track (drones) or 0 (ground vehicles)
## Because positions are relative to the train, enemies keep pace with it
## automatically, follow curves, and come along when the route loops.
##
## Expected children (all optional except Body):
##   Intact (Node3D)  visuals while alive
##   Wreck  (Node3D)  visuals after destruction
##   Body   (CollisionObject3D on the ENEMIES layer)  hit box
##   Muzzle (Marker3D)  where its rounds come from
##   Gun    (Node3D)  turned to face the train
##
## Enemy fire is hitscan like the player's, but only against WORLD | TRAIN,
## and it reports every round to the "enemy_fire_listeners" group so the
## presentation layer can draw tracers and play sounds.

signal despawned(enemy: EnemyBase)

const FIRE_LISTENER_GROUP := &"enemy_fire_listeners"
const FLASH_MATERIAL := preload("res://materials/fx_damage_flash.tres")
const SCORCH_MATERIAL := preload("res://materials/fx_scorched.tres")

@export var kind: StringName = &"enemy"

@export_group("Gun")
@export var armed: bool = true
@export_range(0.5, 30.0) var fire_rate: float = 7.0  ## rounds per second inside a burst
@export_range(1, 30) var burst_rounds: int = 5
## Seconds between bursts (random in range).
@export var burst_pause: Vector2 = Vector2(1.6, 2.6)
@export var round_damage: float = 3.0
@export_range(0.0, 15.0) var spread_degrees: float = 2.5
@export var fire_range: float = 70.0
@export_range(1, 10) var tracer_every: int = 2

@export_group("Feel")
@export var flash_time: float = 0.06
## Seconds the wreck stays in the world before it's recycled.
@export var wreck_time: float = 3.0

# Set by the WaveDirector on spawn.
var train: TrainController
var route: RailRoute
var terrain: TerrainBuilder
var hull: TrainHull

## True from spawn until despawn (including the wreck phase).
var active: bool = false

var rel_offset: float = 0.0
var lateral: float = 0.0
var height: float = 0.0

## Stats (for tests/debug).
var shots_fired: int = 0
var shots_hit_train: int = 0

var rng := RandomNumberGenerator.new()

var _intact: Node3D
var _wreck: Node3D
var _body: CollisionObject3D
var _muzzle: Node3D
var _gun: Node3D
var _meshes: Array[GeometryInstance3D] = []
var _body_layer: int = 0
var _base_health: float = 0.0
var _flash_left: float = 0.0
var _wreck_left: float = 0.0
var _burst_left: int = 0
var _shot_cd: float = 0.0
var _burst_cd: float = 0.0
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	super._ready()
	_base_health = max_health
	_intact = get_node_or_null(^"Intact")
	_wreck = get_node_or_null(^"Wreck")
	_body = get_node_or_null(^"Body")
	_muzzle = find_child("Muzzle", true, false) as Node3D
	_gun = find_child("Gun", true, false) as Node3D
	if _intact:
		for n in _intact.find_children("*", "GeometryInstance3D", true, false):
			_meshes.append(n)
	if _body:
		_body_layer = _body.collision_layer
	_query.collision_mask = PhysicsLayers.ENEMY_SHOT_MASK
	_query.collide_with_areas = false
	_set_inactive()


# ------------------------------------------------------------------ lifecycle

## Put this enemy into play. [param health_mult] scales toughness for later waves.
func spawn(p_train: TrainController, p_route: RailRoute, p_terrain: TerrainBuilder,
		p_hull: TrainHull, seed_value: int, health_mult: float = 1.0) -> void:
	train = p_train
	route = p_route
	terrain = p_terrain
	hull = p_hull
	rng.seed = seed_value
	max_health = _base_health * health_mult
	reset()  # health, is_destroyed, visuals (via _on_reset)
	active = true
	visible = true
	if _body:
		_body.collision_layer = _body_layer
	shots_fired = 0
	shots_hit_train = 0
	_burst_left = 0
	_shot_cd = 0.0
	_burst_cd = rng.randf_range(burst_pause.x, burst_pause.y) * 0.7
	_on_spawn()
	_place(0.0)
	set_physics_process(true)


## Remove from play and hand back to the pool.
func despawn() -> void:
	if not active:
		return
	_set_inactive()
	despawned.emit(self)


func _set_inactive() -> void:
	active = false
	is_destroyed = true  # so area damage, aim helpers and weapons ignore it
	visible = false
	if _body:
		_body.collision_layer = 0
	set_physics_process(false)
	set_process(false)


func _physics_process(delta: float) -> void:
	if not active:
		return
	if is_destroyed:
		_wreck_left -= delta
		_wreck_update(delta)
		if _wreck_left <= 0.0:
			despawn()
		return
	_think(delta)
	if not active or is_destroyed:
		return  # _think may detonate/despawn
	_place(delta)
	if armed:
		_update_gun(delta)


# ------------------------------------------------------------------ overrides

## Pick the spawn position and initial AI state.
func _on_spawn() -> void:
	pass


## AI: update rel_offset / lateral / height (and anything else) for this frame.
func _think(_delta: float) -> void:
	pass


## Turn the track-frame position into a world transform.
func _place(_delta: float) -> void:
	global_position = frame_point(rel_offset, lateral, height)


## Whether the AI currently wants to shoot (in position, not fleeing, etc.).
func _wants_to_fire() -> bool:
	return true


## Called every physics frame while wrecked (falling drones, smoking hulks).
func _wreck_update(_delta: float) -> void:
	pass


func _on_wrecked() -> void:
	pass


# ------------------------------------------------------------------ track frame

## World position for a track-frame coordinate.
func frame_point(rel: float, lat: float, up: float) -> Vector3:
	var off := train.head_distance + rel
	var c := route.sample_world_extended(off)
	return c + frame_right(rel) * lat + Vector3.UP * up


## Flat (horizontal) direction of travel at a track-frame offset.
func frame_forward(rel: float) -> Vector3:
	var l := route.get_length()
	var t := route.tangent_world(clampf(train.head_distance + rel, 1.0, l - 1.0), 2.0)
	var f := Vector3(t.x, 0.0, t.z)
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


func frame_right(rel: float) -> Vector3:
	var f := frame_forward(rel)
	return Vector3(-f.z, 0.0, f.x)


## Route offset (relative to the train front) of the armored railcar's centre.
func core_rel_offset() -> float:
	if train == null or train.cars.is_empty():
		return -16.0
	var last: TrainCar = train.cars[train.cars.size() - 1]
	return -(train.get_consist_length() - last.car_length * 0.5)


# ------------------------------------------------------------------ gun

func _update_gun(delta: float) -> void:
	if hull == null or hull.is_wrecked:
		_burst_left = 0
		return
	if _gun:
		_aim_gun_visual()
	if _burst_left > 0:
		_shot_cd -= delta
		var guard := 0
		while _shot_cd <= 0.0 and _burst_left > 0 and guard < 4:
			fire_round()
			_burst_left -= 1
			_shot_cd += 1.0 / fire_rate
			guard += 1
		if _burst_left == 0:
			_burst_cd = rng.randf_range(burst_pause.x, burst_pause.y)
		return
	_burst_cd -= delta
	if _burst_cd <= 0.0 and in_range() and _wants_to_fire():
		_burst_left = burst_rounds
		_shot_cd = 0.0


func in_range() -> bool:
	return hull != null and get_muzzle_position().distance_to(hull.get_core_point()) <= fire_range


func get_muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position + Vector3.UP


## Fire one round at the train. Returns true if it hit the hull.
func fire_round() -> bool:
	if hull == null or not is_inside_tree():
		return false
	var origin := get_muzzle_position()
	var aim := hull.get_aim_point(rng)
	var dir := _apply_spread((aim - origin).normalized())
	var reach := fire_range * 1.6
	_query.from = origin
	_query.to = origin + dir * reach
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	var end := _query.to
	var normal := -dir
	var hit_train := false
	if not hit.is_empty():
		end = hit.position
		normal = hit.normal
		var col := hit.collider as CollisionObject3D
		hit_train = col != null and (col.collision_layer & PhysicsLayers.TRAIN) != 0
	shots_fired += 1
	if hit_train:
		shots_hit_train += 1
		hull.apply_hit(round_damage, end)
	var tracer := (shots_fired % tracer_every) == 0
	get_tree().call_group(FIRE_LISTENER_GROUP, &"on_enemy_shot", self, origin, end, normal, hit_train, tracer)
	return hit_train


func _aim_gun_visual() -> void:
	var target := hull.get_core_point()
	var from := _gun.global_position
	var to := target - from
	if to.length_squared() < 1.0:
		return
	var up := global_basis.y if absf(to.normalized().dot(global_basis.y)) < 0.98 else Vector3.FORWARD
	_gun.global_basis = Basis.looking_at(to.normalized(), up)


func _apply_spread(dir: Vector3) -> Vector3:
	if spread_degrees <= 0.0:
		return dir
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	up = right.cross(dir).normalized()
	var r := tan(deg_to_rad(spread_degrees)) * sqrt(rng.randf())
	var a := rng.randf() * TAU
	return (dir + right * cos(a) * r + up * sin(a) * r).normalized()


# ------------------------------------------------------------------ damage visuals

func _on_damaged(_amount: float, _hit_point: Vector3, _hit_normal: Vector3) -> void:
	_flash_left = flash_time
	_set_overlay(FLASH_MATERIAL)
	set_process(true)


func _process(delta: float) -> void:
	_flash_left -= delta
	if _flash_left <= 0.0:
		_set_overlay(SCORCH_MATERIAL if (is_destroyed or get_health_ratio() < 0.5) else null)
		set_process(false)


func _on_destroyed(_source: Node) -> void:
	_burst_left = 0
	_flash_left = 0.0
	set_process(false)
	if _body:
		_body.collision_layer = 0
	if _wreck:
		_wreck.visible = true
		if _intact:
			_intact.visible = false
	else:
		_set_overlay(SCORCH_MATERIAL)
	_wreck_left = wreck_time
	_on_wrecked()


func _on_reset() -> void:
	_flash_left = 0.0
	_set_overlay(null)
	if _intact:
		_intact.visible = true
	if _wreck:
		_wreck.visible = false


func _set_overlay(mat: Material) -> void:
	for m in _meshes:
		m.material_overlay = mat


## World-space centre of the hit box (where effects spawn and aim helpers point).
func get_effect_origin() -> Vector3:
	if _body:
		for c in _body.get_children():
			if c is CollisionShape3D:
				return (c as Node3D).global_position
	return global_position + Vector3.UP
