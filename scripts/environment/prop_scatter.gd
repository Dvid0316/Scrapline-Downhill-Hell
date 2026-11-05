class_name PropScatter
extends Node3D
## Places copies of reusable prop scenes along a [RailRoute], sitting on the
## [TerrainBuilder] ground. Deterministic for a given [member random_seed].
##
## Use one PropScatter node per "layer" (rocks, cliffs, industrial, signals…).

@export var route: RailRoute
@export var terrain: TerrainBuilder
@export var props: Array[PackedScene] = []

@export_group("Placement")
## Number of props to try to place. Ignored when [member interval] > 0.
@export var count: int = 30
## When > 0, place one prop every [member interval] metres instead of randomly.
@export var interval: float = 0.0
## -1 = left of travel only, 1 = right only, 0 = both sides.
@export_range(-1, 1) var side: int = 0
@export var min_lateral: float = 10.0
@export var max_lateral: float = 40.0
## Skip the first/last metres of the route.
@export var start_margin: float = 15.0
@export var end_margin: float = 15.0
## Reject spots that come closer than this to ANY part of the track.
@export var min_track_clearance: float = 0.0

@export_group("Variation")
@export var align_to_track: bool = true
@export_range(0.0, 180.0) var random_yaw_degrees: float = 0.0
@export var scale_range: Vector2 = Vector2(1.0, 1.0)
@export var non_uniform_scale: float = 0.0
## Push props down into the ground (metres) to hide floating edges.
@export var sink: float = 0.0
@export var random_seed: int = 1


func _ready() -> void:
	if route == null or props.is_empty():
		push_error("PropScatter '%s': route or props missing" % name)
		return
	scatter()


func scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var length := route.get_length()
	var usable := length - start_margin - end_margin
	if usable <= 0.0:
		return
	var offsets: Array[float] = []
	if interval > 0.0:
		var d := start_margin
		while d <= length - end_margin:
			offsets.append(d)
			d += interval
	else:
		for i in count:
			offsets.append(start_margin + rng.randf() * usable)

	for off in offsets:
		var lateral := rng.randf_range(min_lateral, max_lateral)
		var s := side
		if s == 0:
			s = -1 if rng.randf() < 0.5 else 1
		lateral *= float(s)
		var centre := route.sample_world(off)
		var t := route.tangent_world(off)
		var flat_t := Vector3(t.x, 0.0, t.z).normalized()
		var right := Vector3(-flat_t.z, 0.0, flat_t.x)
		var pos := centre + right * lateral
		if terrain != null:
			if min_track_clearance > 0.0:
				var rel := terrain.track_relation(pos.x, pos.z)
				if absf(rel.x) < min_track_clearance:
					continue
			pos.y = terrain.sample_height(pos.x, pos.z) - sink
		var scene: PackedScene = props[rng.randi() % props.size()]
		var inst := scene.instantiate() as Node3D
		if inst == null:
			continue
		add_child(inst)
		var yaw := 0.0
		if align_to_track:
			yaw = atan2(-flat_t.x, -flat_t.z)
		yaw += deg_to_rad(rng.randf_range(-random_yaw_degrees, random_yaw_degrees))
		var sc := rng.randf_range(scale_range.x, scale_range.y)
		var sv := Vector3(sc, sc, sc)
		if non_uniform_scale > 0.0:
			sv *= Vector3(
				1.0 + rng.randf_range(-non_uniform_scale, non_uniform_scale),
				1.0 + rng.randf_range(-non_uniform_scale, non_uniform_scale),
				1.0 + rng.randf_range(-non_uniform_scale, non_uniform_scale))
		var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(sv)
		inst.global_transform = Transform3D(basis, pos)
