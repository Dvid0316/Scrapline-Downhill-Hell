class_name RailRoute
extends Path3D
## The single source of truth for where the railway goes.
##
## The route is authored as a short list of control points. Smooth Bezier
## handles are generated automatically (Catmull-Rom style), so tweaking the
## route is just editing positions in the inspector. Everything else — rails,
## terrain, prop placement, the train, the camera — reads from this curve.
##
## Convention: the train travels in the direction of increasing curve offset.
## Overall travel direction is roughly world -Z (Godot's "forward").

## Control points in this node's local space (metres). Y is elevation.
## Keep successive points descending for a downhill run.
@export var control_points: PackedVector3Array = PackedVector3Array([
	Vector3(0, 70, 60),
	Vector3(0, 70, 0),
	Vector3(0, 69, -60),
	Vector3(15, 66, -130),
	Vector3(45, 61, -200),
	Vector3(60, 56, -270),
	Vector3(50, 50, -340),
	Vector3(20, 44, -410),
	Vector3(0, 39, -480),
	Vector3(-10, 34, -550),
	Vector3(5, 28, -620),
	Vector3(35, 22, -690),
	Vector3(55, 16, -760),
	Vector3(60, 11, -830),
	Vector3(55, 7, -900),
	Vector3(50, 6, -960),
])

## Bezier handle length as a fraction of the neighbour span. ~0.16 = Catmull-Rom.
@export_range(0.05, 0.4) var handle_scale: float = 0.17

## Distance between baked curve samples (metres). Smaller = smoother but slower.
@export_range(0.25, 4.0) var bake_resolution: float = 1.0


func _enter_tree() -> void:
	# Built in _enter_tree (not _ready) so sibling nodes can read the curve in
	# their own _ready regardless of their order in the scene tree.
	if curve == null or curve.point_count != control_points.size():
		rebuild()


func rebuild() -> void:
	var c := Curve3D.new()
	c.bake_interval = bake_resolution
	var n := control_points.size()
	for i in n:
		var p: Vector3 = control_points[i]
		var prev: Vector3 = control_points[maxi(i - 1, 0)]
		var next: Vector3 = control_points[mini(i + 1, n - 1)]
		var handle := (next - prev) * handle_scale
		c.add_point(p, -handle, handle)
	curve = c


func get_length() -> float:
	return curve.get_baked_length()


## World-space position on the track centreline at [param offset] metres.
func sample_world(offset: float) -> Vector3:
	var d := clampf(offset, 0.0, get_length())
	return to_global(curve.sample_baked(d, true))


## World-space unit tangent (direction of travel) at [param offset].
func tangent_world(offset: float, span: float = 1.0) -> Vector3:
	var a := sample_world(offset - span)
	var b := sample_world(offset + span)
	var t := b - a
	if t.length_squared() < 0.000001:
		return Vector3.FORWARD
	return t.normalized()


## Gradient in percent at [param offset] (negative = downhill).
func grade_percent(offset: float) -> float:
	var a := sample_world(offset - 5.0)
	var b := sample_world(offset + 5.0)
	var run := Vector2(b.x - a.x, b.z - a.z).length()
	if run < 0.001:
		return 0.0
	return (b.y - a.y) / run * 100.0
