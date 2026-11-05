class_name TargetCourse
extends Node3D
## Places a shooting range of destructible targets along the route.
##
## Every [member cluster_spacing] metres a small themed cluster is placed on
## one side of the track, so there's always something coming up while the
## train rolls. Clusters vary distance and elevation: steel plates high on the
## mountain side, depots down in the valley, barrels near bunkers for chain
## reactions. Placement is deterministic for a given [member random_seed].
##
## Targets are never freed. [method reset_all] restores them for a new run.

@export var route: RailRoute
@export var terrain: TerrainBuilder

@export_group("Target scenes")
@export var plate_scene: PackedScene
@export var bunker_scene: PackedScene
@export var barrel_scene: PackedScene
@export var crate_scene: PackedScene
@export var generator_scene: PackedScene

@export_group("Layout")
@export var first_cluster: float = 95.0
@export var cluster_spacing: float = 72.0
@export var end_margin: float = 40.0
@export var min_track_clearance: float = 7.0
@export var random_seed: int = 1337

var targets: Array[Damageable] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if route == null or terrain == null:
		push_error("TargetCourse: route/terrain missing")
		return
	build()


func build() -> void:
	_rng.seed = random_seed
	var length := route.get_length()
	var d := first_cluster
	var i := 0
	while d < length - end_margin:
		var kind := i % 4
		match kind:
			0: _barrel_yard(d + _rng.randf_range(-8, 8))
			1: _ridge_plates(d + _rng.randf_range(-8, 8))
			2: _bunker_post(d + _rng.randf_range(-8, 8))
			3: _valley_depot(d + _rng.randf_range(-8, 8))
		d += cluster_spacing
		i += 1


func reset_all() -> void:
	for t in targets:
		t.reset()


func alive_count() -> int:
	var n := 0
	for t in targets:
		if not t.is_destroyed:
			n += 1
	return n


# --------------------------------------------------------------- cluster themes

## Barrels packed together with crates and a plate: shoot one, watch the chain.
func _barrel_yard(off: float) -> void:
	var side := _side()
	var c := Vector2(_rng.randf_range(11, 16) * side, 0)
	for k in 4:
		_place(barrel_scene, off, c + Vector2(_rng.randf_range(-2.6, 2.6), _rng.randf_range(-2.6, 2.6)))
	_place(crate_scene, off, c + Vector2(3.0 * side, 2.5))
	_place(crate_scene, off, c + Vector2(3.2 * side, -1.0))
	_place(plate_scene, off, c + Vector2(-1.0 * side, -5.0))


## Steel plates up the mountain (left side, higher elevation).
func _ridge_plates(off: float) -> void:
	for k in 3:
		var lat := -_rng.randf_range(16, 30)
		_place(plate_scene, off + k * 7.0 - 7.0, Vector2(lat, 0))
	_place(crate_scene, off + 4.0, Vector2(-_rng.randf_range(11, 14), 0))


## A bunker with barrels stacked beside it.
func _bunker_post(off: float) -> void:
	var side := _side()
	var c := Vector2(_rng.randf_range(16, 22) * side, 0)
	_place(bunker_scene, off, c)
	_place(barrel_scene, off, c + Vector2(-4.0 * side, 2.0))
	_place(barrel_scene, off, c + Vector2(-4.2 * side, 3.5))
	_place(plate_scene, off, c + Vector2(-2.0 * side, -7.0))


## Generator + crates + a barrel down on the valley side (right, lower).
func _valley_depot(off: float) -> void:
	var c := Vector2(_rng.randf_range(17, 24), 0)
	_place(generator_scene, off, c)
	_place(crate_scene, off, c + Vector2(-2.5, 3.0))
	_place(crate_scene, off, c + Vector2(-2.0, 4.4))
	_place(barrel_scene, off, c + Vector2(2.8, -2.6))


# --------------------------------------------------------------- placement

func _side() -> int:
	return -1 if _rng.randf() < 0.5 else 1


## [param local]: x = lateral metres (negative = left), y = metres along track.
func _place(scene: PackedScene, off: float, local: Vector2) -> Damageable:
	if scene == null:
		return null
	var o := clampf(off + local.y, 0.0, route.get_length())
	var centre := route.sample_world(o)
	var t := route.tangent_world(o)
	var fwd := Vector3(t.x, 0.0, t.z).normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var pos := centre + right * local.x
	var rel := terrain.track_relation(pos.x, pos.z)
	if absf(rel.x) < min_track_clearance:
		return null
	pos.y = terrain.sample_height(pos.x, pos.z)
	var inst := scene.instantiate() as Damageable
	add_child(inst)
	# Face the track (-Z toward the nearest rail point), small random yaw.
	var to_track := centre - pos
	to_track.y = 0.0
	var yaw := atan2(-to_track.x, -to_track.z) + _rng.randf_range(-0.25, 0.25)
	inst.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	targets.append(inst)
	return inst
