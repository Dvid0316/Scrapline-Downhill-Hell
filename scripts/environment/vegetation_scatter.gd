class_name VegetationScatter
extends Node3D
## Stylized vegetation over the whole terrain, drawn with MultiMeshes:
## low-poly pines in forest clumps, round bushes, and grass tufts.
## Meshes are built in code (vertex-coloured, flat-shaded) and sway in the
## wind via shaders/stylized_foliage.gdshader. No collision: plants never
## block shots.
##
## Placement is deterministic (fixed seed) and keeps clear of the track and
## the play area right beside it, where targets and enemies live.

const SHADER := preload("res://shaders/stylized_foliage.gdshader")

@export var terrain: TerrainBuilder

@export_group("Counts")
@export var tree_attempts: int = 9000
@export var bush_attempts: int = 5000
@export var grass_attempts: int = 110000

@export_group("Clearance from the track (m)")
@export var tree_min_distance: float = 30.0
@export var bush_min_distance: float = 9.0
@export var grass_min_distance: float = 5.5

@export var random_seed: int = 77

var tree_count: int = 0
var bush_count: int = 0
var grass_count: int = 0

var _noise := FastNoiseLite.new()


func _ready() -> void:
	if terrain == null:
		push_error("VegetationScatter: terrain missing")
		return
	_noise.seed = random_seed
	_noise.frequency = 0.012
	build()


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var bounds := terrain.get_bounds().grow(-6.0)
	var trees: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var grass: Array[Transform3D] = []
	for i in tree_attempts:
		var p := _random_point(rng, bounds)
		var forest := _noise.get_noise_2d(p.x, p.y)
		if forest < 0.05 + rng.randf() * 0.25:
			continue
		var t: Variant = _ground(p, tree_min_distance, 0.62)
		if t == null:
			continue
		var s := rng.randf_range(0.8, 1.45)
		trees.append(_xf(t, rng, Vector3(s, s * rng.randf_range(0.9, 1.25), s), 0.3))
	for i in bush_attempts:
		var p := _random_point(rng, bounds)
		if _noise.get_noise_2d(p.x + 300.0, p.y) < -0.25 + rng.randf() * 0.2:
			continue
		var t: Variant = _ground(p, bush_min_distance, 0.65)
		if t == null:
			continue
		var s := rng.randf_range(0.7, 1.6)
		bushes.append(_xf(t, rng, Vector3(s, s * rng.randf_range(0.6, 0.9), s), -0.15))
	for i in grass_attempts:
		var p := _random_point(rng, bounds)
		var t: Variant = _ground(p, grass_min_distance, 0.8)
		if t == null:
			continue
		var s := rng.randf_range(0.9, 1.7)
		grass.append(_xf(t, rng, Vector3(s, s * rng.randf_range(0.8, 1.3), s), -0.05))
	tree_count = trees.size()
	bush_count = bushes.size()
	grass_count = grass.size()
	_add_multimesh("Trees", _pine_mesh(), trees, 0.35, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_add_multimesh("Bushes", _bush_mesh(), bushes, 0.15, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_add_multimesh("Grass", _grass_mesh(), grass, 0.6, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, false)


func _random_point(rng: RandomNumberGenerator, b: Rect2) -> Vector2:
	return Vector2(rng.randf_range(b.position.x, b.end.x), rng.randf_range(b.position.y, b.end.y))


## Ground position at XZ, or null if too close to the track or too steep.
func _ground(p: Vector2, min_dist: float, min_up: float) -> Variant:
	if terrain.sample_track_distance(p.x, p.y) < min_dist:
		return null
	if terrain.sample_normal(p.x, p.y).y < min_up:
		return null
	return Vector3(p.x, terrain.sample_height(p.x, p.y), p.y)


func _xf(pos: Vector3, rng: RandomNumberGenerator, sc: Vector3, sink: float) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(sc)
	return Transform3D(basis, pos + Vector3.DOWN * sink)


func _add_multimesh(n: String, mesh: Mesh, xforms: Array[Transform3D], sway: float, shadows: int, outline: bool = true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"sway", sway)
	mat.set_shader_parameter(&"no_outline", not outline)
	mmi.material_override = mat
	mmi.cast_shadow = shadows
	add_child(mmi)


# ------------------------------------------------------------------ meshes

## Low-poly pine: hex trunk + three stacked 7-sided cones, flat shaded.
func _pine_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark := Color(0.36, 0.22, 0.12, 0.0)
	_cone(st, 0.0, 1.6, 0.28, 0.2, 6, bark, bark)
	var tiers := [[1.2, 3.4, 2.3], [2.9, 3.0, 1.75], [4.4, 2.6, 1.15]]
	for k in tiers.size():
		var tier: Array = tiers[k]
		var base := Color(0.07, 0.24, 0.10, 0.25 + k * 0.25)
		var tip := Color(0.22, 0.52, 0.16, 0.5 + k * 0.25)
		_cone(st, tier[0], tier[1], tier[2], 0.0, 7, base, tip)
	return st.commit()


## Bush: chunky low-poly blob.
func _bush_mesh() -> ArrayMesh:
	var src := RockMeshes.boulder(3)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		var v := verts[i]
		var h := clampf(v.y / 1.4, 0.0, 1.0)
		var c := Color(0.06, 0.2, 0.05).lerp(Color(0.22, 0.44, 0.1), h)
		c.a = h * 0.6
		st.set_color(c)
		st.set_normal(norms[i])
		st.add_vertex(v * Vector3(0.9, 0.75, 0.9))
	return st.commit()


## Grass tuft: six thin blades fanning out, bright tips that sway.
func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 6:
		var a := k * TAU / 6.0 + 0.3 * (k % 2)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.07
		var h := 0.55 + 0.25 * (k % 3)
		var tip := dir * 0.28 + Vector3.UP * h
		var n := Vector3.UP
		st.set_normal(n)
		st.set_color(Color(0.2, 0.42, 0.08, 0.0))
		st.add_vertex(-side)
		st.set_normal(n)
		st.set_color(Color(0.2, 0.42, 0.08, 0.0))
		st.add_vertex(side)
		st.set_normal(n)
		st.set_color(Color(0.62, 0.8, 0.25, 1.0))
		st.add_vertex(tip)
	return st.commit()


## Flat-shaded cone/frustum from y0 up by height, with a colour gradient.
func _cone(st: SurfaceTool, y0: float, height: float, r0: float, r1: float, sides: int, c0: Color, c1: Color) -> void:
	for i in sides:
		var a0 := i * TAU / sides
		var a1 := (i + 1) * TAU / sides
		var b0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var b1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var t0 := Vector3(cos(a0) * r1, y0 + height, sin(a0) * r1)
		var t1 := Vector3(cos(a1) * r1, y0 + height, sin(a1) * r1)
		var n := (t0 - b0).cross(b1 - b0).normalized()
		if n.dot(Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))) < 0.0:
			n = -n
		# Side quad (two triangles, clockwise from outside).
		_tri(st, b0, t0, b1, n, c0, c1, c0)
		if r1 > 0.0:
			_tri(st, b1, t0, t1, n, c0, c1, c1)
		# Underside so tiers don't look hollow from below.
		var dn := Vector3.DOWN
		_tri(st, Vector3(0, y0, 0), b1, b0, dn, c0.darkened(0.4), c0.darkened(0.4), c0.darkened(0.4))


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	for pair: Array in [[a, ca], [b, cb], [c, cc]]:
		st.set_normal(n)
		st.set_color(pair[1])
		st.add_vertex(pair[0])
