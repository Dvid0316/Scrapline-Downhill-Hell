class_name TrackBuilder
extends Node3D
## Generates the visible railway (ballast bed, sleepers, two rails) along a
## [RailRoute]. Purely visual — no gameplay logic lives here.
##
## Vertical layout relative to the route centreline (y = 0):
##   ballast top ~0.05, sleepers 0.00–0.18, rails 0.18–0.33 (rail top).
## The train's ride height must match [member rail_top].

@export var route: RailRoute
@export var rail_material: Material
@export var sleeper_material: Material
@export var ballast_material: Material

@export_group("Dimensions")
## Distance between rail centres (standard gauge ≈ 1.435 m inner faces).
@export var rail_spacing: float = 1.5
@export var sleeper_interval: float = 0.65
@export var sleeper_size: Vector3 = Vector3(2.6, 0.18, 0.26)
## Length of each extruded segment (metres).
@export var segment_length: float = 1.0

const RAIL_BASE := 0.18
var rail_top: float:
	get:
		return RAIL_BASE + 0.15

# Rail cross-section (x right, y up), counter-clockwise, rough flat-bottom rail.
const RAIL_PROFILE := [
	Vector2(-0.075, 0.0), Vector2(0.075, 0.0), Vector2(0.075, 0.025),
	Vector2(0.02, 0.045), Vector2(0.02, 0.105), Vector2(0.038, 0.115),
	Vector2(0.038, 0.15), Vector2(-0.038, 0.15), Vector2(-0.038, 0.115),
	Vector2(-0.02, 0.105), Vector2(-0.02, 0.045), Vector2(-0.075, 0.025),
]
# Ballast bed cross-section, counter-clockwise.
const BALLAST_PROFILE := [
	Vector2(-2.6, -0.9), Vector2(2.6, -0.9), Vector2(1.7, 0.05), Vector2(-1.7, 0.05),
]


func _ready() -> void:
	if route == null:
		push_error("TrackBuilder: no route assigned")
		return
	build()


func build() -> void:
	for child in get_children():
		child.queue_free()
	var frames := _compute_frames()
	_add_mesh("Ballast", _extrude(BALLAST_PROFILE, 0.0, 0.0, frames), ballast_material)
	_add_mesh("RailLeft", _extrude(RAIL_PROFILE, -rail_spacing * 0.5, RAIL_BASE, frames), rail_material)
	_add_mesh("RailRight", _extrude(RAIL_PROFILE, rail_spacing * 0.5, RAIL_BASE, frames), rail_material)
	_build_sleepers()


## A frame = [origin, right, up] in this node's local space, sampled along the route.
func _compute_frames() -> Array:
	var frames: Array = []
	var length := route.get_length()
	var steps := maxi(int(ceil(length / segment_length)), 1)
	for i in steps + 1:
		var d := length * float(i) / float(steps)
		frames.append(_frame_at(d))
	return frames


func _frame_at(d: float) -> Array:
	var origin := to_local(route.sample_world(d))
	var forward := route.tangent_world(d, 0.5)
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	# Directions are unaffected by translation; assume no rotation on this node.
	return [origin, right, up]


func _extrude(profile: Array, x_offset: float, y_offset: float, frames: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pc := profile.size()
	var dist_along := 0.0
	for f in range(frames.size() - 1):
		var fa: Array = frames[f]
		var fb: Array = frames[f + 1]
		var seg := (fb[0] as Vector3).distance_to(fa[0])
		for e in pc:
			var p0: Vector2 = profile[e]
			var p1: Vector2 = profile[(e + 1) % pc]
			var edge := p1 - p0
			# Outward normal of a CCW profile edge.
			var n2 := Vector2(edge.y, -edge.x).normalized()
			var a0 := _place(fa, p0, x_offset, y_offset)
			var a1 := _place(fa, p1, x_offset, y_offset)
			var b0 := _place(fb, p0, x_offset, y_offset)
			var b1 := _place(fb, p1, x_offset, y_offset)
			var na: Vector3 = (fa[1] as Vector3) * n2.x + (fa[2] as Vector3) * n2.y
			var nb: Vector3 = (fb[1] as Vector3) * n2.x + (fb[2] as Vector3) * n2.y
			var u0 := dist_along * 0.25
			var u1 := (dist_along + seg) * 0.25
			# Godot front faces are clockwise: (a0, a1, b1) and (a0, b1, b0).
			_vert(st, a0, na, Vector2(p0.x + p0.y, u0))
			_vert(st, a1, na, Vector2(p1.x + p1.y, u0))
			_vert(st, b1, nb, Vector2(p1.x + p1.y, u1))
			_vert(st, a0, na, Vector2(p0.x + p0.y, u0))
			_vert(st, b1, nb, Vector2(p1.x + p1.y, u1))
			_vert(st, b0, nb, Vector2(p0.x + p0.y, u1))
		dist_along += seg
	st.generate_tangents()
	return st.commit()


func _place(frame: Array, p: Vector2, x_offset: float, y_offset: float) -> Vector3:
	return (frame[0] as Vector3) + (frame[1] as Vector3) * (p.x + x_offset) + (frame[2] as Vector3) * (p.y + y_offset)


func _vert(st: SurfaceTool, pos: Vector3, normal: Vector3, uv: Vector2) -> void:
	st.set_normal(normal)
	st.set_uv(uv)
	st.add_vertex(pos)


func _add_mesh(node_name: String, mesh: Mesh, material: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material
	add_child(mi)


func _build_sleepers() -> void:
	var length := route.get_length()
	var count := int(length / sleeper_interval)
	var box := BoxMesh.new()
	box.size = sleeper_size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = count
	for i in count:
		var fr := _frame_at((float(i) + 0.5) * sleeper_interval)
		var right: Vector3 = fr[1]
		var up: Vector3 = fr[2]
		var basis := Basis(right, up, right.cross(up))
		var origin: Vector3 = (fr[0] as Vector3) + up * (sleeper_size.y * 0.5)
		mm.set_instance_transform(i, Transform3D(basis, origin))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Sleepers"
	mmi.multimesh = mm
	mmi.material_override = sleeper_material
	add_child(mmi)
