class_name RockMeshes
extends RefCounted
## Procedural low-poly rocks: a subdivided icosahedron with jittered,
## noise-displaced vertices and flat shading, so boulders read as chunky
## faceted stones in the stylized look. Meshes are built once and cached.
##
## Vertex colour red = ambient occlusion (darker toward the base), used by
## the stylized rock shader.

const BOULDER_VARIANTS := 6
const SPIRE_VARIANTS := 4

static var _boulders: Array[ArrayMesh] = []
static var _spires: Array[ArrayMesh] = []
static var _puff: ArrayMesh


static func boulder(index: int) -> ArrayMesh:
	if _boulders.is_empty():
		for i in BOULDER_VARIANTS:
			_boulders.append(_build(1000 + i * 17, Vector3(1.0, 0.72, 0.9), 0.0, 1))
	return _boulders[posmod(index, BOULDER_VARIANTS)]


## Lumpy, centred, flat-shaded ball for stylized smoke/fire puffs (white vertex colour).
static func puff() -> ArrayMesh:
	if _puff == null:
		var noise := FastNoiseLite.new()
		noise.seed = 77
		noise.frequency = 1.1
		var data := _icosphere(1)
		var verts: PackedVector3Array = data[0]
		var faces: PackedInt32Array = data[1]
		for i in verts.size():
			verts[i] *= 1.0 + noise.get_noise_3dv(verts[i] * 1.5) * 0.3
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for f in range(0, faces.size(), 3):
			var a := verts[faces[f]]
			var b := verts[faces[f + 1]]
			var c := verts[faces[f + 2]]
			var n := (c - a).cross(b - a).normalized()
			for v: Vector3 in [a, b, c]:
				st.set_color(Color.WHITE)
				st.set_normal(n)
				st.add_vertex(v)
		_puff = st.commit()
	return _puff


static func spire(index: int) -> ArrayMesh:
	if _spires.is_empty():
		for i in SPIRE_VARIANTS:
			_spires.append(_build(5000 + i * 31, Vector3(0.75, 2.6, 0.7), 0.45, 1))
	return _spires[posmod(index, SPIRE_VARIANTS)]


## [param squash] scales the unit sphere; [param taper] narrows the top.
static func _build(seed_value: int, squash: Vector3, taper: float, subdivisions: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.9
	noise.fractal_octaves = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var data := _icosphere(subdivisions)
	var verts: PackedVector3Array = data[0]
	var faces: PackedInt32Array = data[1]
	# Displace each shared vertex once (keeps the surface closed).
	for i in verts.size():
		var p: Vector3 = verts[i]
		var r := 1.0 + noise.get_noise_3dv(p * 1.3) * 0.38 + rng.randf_range(-0.07, 0.07)
		p *= r
		p *= squash
		if taper > 0.0:
			var t := clampf((p.y / squash.y + 1.0) * 0.5, 0.0, 1.0)
			var k := 1.0 - taper * t
			p.x *= k
			p.z *= k
		# Flat-ish base so it sits on the ground.
		p.y = maxf(p.y, -squash.y * 0.55)
		verts[i] = p
	var lo := INF
	var hi := -INF
	for p in verts:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in range(0, faces.size(), 3):
		var a := verts[faces[f]]
		var b := verts[faces[f + 1]]
		var c := verts[faces[f + 2]]
		var n := (c - a).cross(b - a).normalized()  # outward for clockwise faces
		for p: Vector3 in [a, b, c]:
			var ao := lerpf(0.45, 1.0, clampf((p.y - lo) / maxf(hi - lo, 0.01) * 1.6, 0.0, 1.0))
			st.set_color(Color(ao, 0, 0))
			st.set_normal(n)
			st.add_vertex(p - Vector3(0, lo, 0))  # base at y = 0
	return st.commit()


static func _icosphere(subdivisions: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for s in subdivisions:
		var cache := {}
		var nf := PackedInt32Array()
		for f in range(0, faces.size(), 3):
			var a := faces[f]
			var b := faces[f + 1]
			var c := faces[f + 2]
			var ab := _mid(verts, cache, a, b)
			var bc := _mid(verts, cache, b, c)
			var ca := _mid(verts, cache, c, a)
			nf.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		faces = nf
	# Godot front faces are clockwise: flip winding.
	for f in range(0, faces.size(), 3):
		var tmp := faces[f + 1]
		faces[f + 1] = faces[f + 2]
		faces[f + 2] = tmp
	return [verts, faces]


static func _mid(verts: PackedVector3Array, cache: Dictionary, a: int, b: int) -> int:
	var key := mini(a, b) * 100000 + maxi(a, b)
	if cache.has(key):
		return cache[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	cache[key] = verts.size() - 1
	return verts.size() - 1
