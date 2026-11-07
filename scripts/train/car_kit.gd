class_name CarKit
extends RefCounted
## Tiny procedural modelling kit for rail vehicles.
##
## Collects flat-shaded geometry per material (chamfered boxes, extruded
## armour profiles, cylinders, rivets, any primitive Mesh) and commits it as
## ONE ArrayMesh with a surface per material, so a detailed car is still only
## a handful of draw calls. No UVs: the stylized surface shader is object-space
## triplanar.
##
## Coordinates follow the car convention: front is -Z, y = 0 at rail top.

var _tools := {}   # Material -> SurfaceTool
var _order: Array[Material] = []


func _st(mat: Material) -> SurfaceTool:
	if not _tools.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[mat] = st
		_order.append(mat)
	return _tools[mat]


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for mat in _order:
		var st: SurfaceTool = _tools[mat]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


## Convex polygon, flat shaded. Winding is fixed automatically so the face
## points away from [param inside] (a point inside the solid).
func poly(mat: Material, pts: PackedVector3Array, inside: Vector3) -> void:
	if pts.size() < 3:
		return
	var n := (pts[2] - pts[0]).cross(pts[1] - pts[0])
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	if n.dot(c - inside) < 0.0:
		pts.reverse()
		n = -n
	n = n.normalized()
	var st := _st(mat)
	for i in range(1, pts.size() - 1):
		for p: Vector3 in [pts[0], pts[i], pts[i + 1]]:
			st.set_normal(n)
			st.add_vertex(p)


func _poly_x(mat: Material, pts: Array, inside: Vector3, xf: Transform3D) -> void:
	var out := PackedVector3Array()
	for p: Vector3 in pts:
		out.append(xf * p)
	poly(mat, out, xf * inside)


## Box with chamfered edges (catches light and outlines, unlike a raw cube).
## [param xf] places the box centre; size is the full extent.
func box(mat: Material, size: Vector3, xf: Transform3D, bevel: float = 0.06) -> void:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	if b <= 0.001:
		_plain_box(mat, h, xf)
		return
	# Three points per corner, one on each face plane.
	var P := func(sx: int, sy: int, sz: int, axis: int) -> Vector3:
		var v := Vector3(sx * (h.x - b), sy * (h.y - b), sz * (h.z - b))
		v[axis] = [sx, sy, sz][axis] * h[axis]
		return v
	var c := Vector3.ZERO
	# Faces
	for axis in 3:
		for s in [-1, 1]:
			var pts := []
			for u in [-1, 1]:
				for v in ([-1, 1] if u == -1 else [1, -1]):
					var sg := [0, 0, 0]
					sg[axis] = s
					sg[(axis + 1) % 3] = u
					sg[(axis + 2) % 3] = v
					pts.append(P.call(sg[0], sg[1], sg[2], axis))
			_poly_x(mat, pts, c, xf)
	# Edge bevels: for each pair of axes (a, b2) and signs, along the third.
	for a in 3:
		var a2 := (a + 1) % 3
		var along := (a + 2) % 3
		for sa in [-1, 1]:
			for sb in [-1, 1]:
				var pts := []
				for t in [-1, 1]:
					var sg := [0, 0, 0]
					sg[a] = sa
					sg[a2] = sb
					sg[along] = t
					pts.append(P.call(sg[0], sg[1], sg[2], a))
				for t in [1, -1]:
					var sg := [0, 0, 0]
					sg[a] = sa
					sg[a2] = sb
					sg[along] = t
					pts.append(P.call(sg[0], sg[1], sg[2], a2))
				_poly_x(mat, pts, c, xf)
	# Corner triangles
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				_poly_x(mat, [P.call(sx, sy, sz, 0), P.call(sx, sy, sz, 1), P.call(sx, sy, sz, 2)], c, xf)


func _plain_box(mat: Material, h: Vector3, xf: Transform3D) -> void:
	for axis in 3:
		for s in [-1, 1]:
			var pts := []
			for k in [[-1, -1], [-1, 1], [1, 1], [1, -1]]:
				var v := Vector3.ZERO
				v[axis] = s * h[axis]
				v[(axis + 1) % 3] = k[0] * h[(axis + 1) % 3]
				v[(axis + 2) % 3] = k[1] * h[(axis + 2) % 3]
				pts.append(v)
			_poly_x(mat, pts, Vector3.ZERO, xf)


## Convenience: box at a position with optional rotation in degrees.
func boxp(mat: Material, size: Vector3, pos: Vector3, rot_deg := Vector3.ZERO, bevel: float = 0.06) -> void:
	box(mat, size, Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos), bevel)


## Prism: a convex 2D profile in the XY plane extruded along Z from z0 to z1.
## [param taper0]/[param taper1] scale the profile at each end (about x = 0,
## y = profile bottom) for sloped noses.
func extrude(mat: Material, profile: PackedVector2Array, z0: float, z1: float,
		xf := Transform3D.IDENTITY, taper0 := Vector2.ONE, taper1 := Vector2.ONE) -> void:
	var lo := INF
	var c2 := Vector2.ZERO
	for p in profile:
		lo = minf(lo, p.y)
		c2 += p
	c2 /= profile.size()
	var ring := func(z: float, t: Vector2) -> Array:
		var r := []
		for p in profile:
			r.append(Vector3(p.x * t.x, lo + (p.y - lo) * t.y, z))
		return r
	var a: Array = ring.call(z0, taper0)
	var b: Array = ring.call(z1, taper1)
	var inside := Vector3(0.0, lo + (c2.y - lo) * (taper0.y + taper1.y) * 0.5, (z0 + z1) * 0.5)
	inside.x = c2.x
	_poly_x(mat, a, inside, xf)
	_poly_x(mat, b, inside, xf)
	var n := profile.size()
	for i in n:
		var j := (i + 1) % n
		_poly_x(mat, [a[i], a[j], b[j], b[i]], inside, xf)


## Cylinder along local Y (rotate with [param xf]). Flat-shaded sides.
func cyl(mat: Material, r_top: float, r_bot: float, height: float, xf: Transform3D, segs: int = 12, caps: bool = true) -> void:
	var h := height * 0.5
	var top := []
	var bot := []
	for i in segs:
		var a := TAU * (float(i) + 0.5) / segs
		var d := Vector3(cos(a), 0.0, sin(a))
		top.append(d * r_top + Vector3(0, h, 0))
		bot.append(d * r_bot - Vector3(0, h, 0))
	var c := Vector3.ZERO
	for i in segs:
		var j := (i + 1) % segs
		_poly_x(mat, [top[i], top[j], bot[j], bot[i]], c, xf)
	if caps:
		_poly_x(mat, top, c, xf)
		_poly_x(mat, bot, c, xf)


func cylp(mat: Material, r: float, height: float, pos: Vector3, rot_deg := Vector3.ZERO, segs: int = 12) -> void:
	cyl(mat, r, r, height, Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), pos), segs)


## Rivet heads: small flat-topped studs on a surface facing [param normal].
func rivets(mat: Material, points: PackedVector3Array, normal: Vector3, size: float = 0.05) -> void:
	var y := normal.normalized()
	var x := (Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).cross(y).normalized()
	var z := x.cross(y)
	var basis := Basis(x, y, z)
	size *= 0.75
	for p in points:
		cyl(mat, size * 0.6, size, size * 0.7, Transform3D(basis, p + y * size * 0.3), 6)


## Evenly spaced points from a to b (inclusive).
static func line(a: Vector3, b: Vector3, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in count:
		out.append(a.lerp(b, float(i) / maxf(count - 1, 1)))
	return out


## Diagonal hazard stripes on a flat panel: alternating materials, as slanted
## parallelograms on the plane x = const (side panels) facing +/-X.
func hazard_band(mat_a: Material, mat_b: Material, center: Vector3, width: float, height: float,
		face_x: float, stripes: int = 8) -> void:
	var w := width / stripes
	var skew := height * 0.6
	for i in stripes:
		var z0 := center.z - width * 0.5 + i * w
		var mat := mat_a if i % 2 == 0 else mat_b
		var pts := PackedVector3Array([
			Vector3(center.x, center.y - height * 0.5, z0),
			Vector3(center.x, center.y - height * 0.5, z0 + w),
			Vector3(center.x, center.y + height * 0.5, minf(z0 + w + skew, center.z + width * 0.5)),
			Vector3(center.x, center.y + height * 0.5, minf(z0 + skew, center.z + width * 0.5))])
		poly(mat, pts, center - Vector3(face_x, 0, 0))


## Append any primitive mesh (e.g. a SphereMesh) transformed.
func mesh(mat: Material, m: Mesh, xf: Transform3D) -> void:
	var arr := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var st := _st(mat)
	var nb := xf.basis.inverse().transposed()
	if idx.is_empty():
		for i in verts.size():
			st.set_normal((nb * norms[i]).normalized())
			st.add_vertex(xf * verts[i])
	else:
		for i in idx:
			st.set_normal((nb * norms[i]).normalized())
			st.add_vertex(xf * verts[i])
