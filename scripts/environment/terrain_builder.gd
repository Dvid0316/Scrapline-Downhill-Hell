class_name TerrainBuilder
extends Node3D
## Procedural mountain-descent terrain shaped around a [RailRoute].
##
## Shape, by horizontal distance from the track:
##   - a flat bed under the ballast,
##   - a bumpy shoulder,
##   - then the LEFT side rises into a mountain wall and the RIGHT side drops
##     into a valley, so the line runs along a ledge.
## [method sample_height] is analytic, so props can be placed on the
## ground without physics raycasts.
##
## Assumes this node and the route share the same (unrotated) space.

@export var route: RailRoute
@export var material: Material

@export_group("Grid")
@export var margin: float = 140.0
@export_range(1.0, 16.0) var cell_size: float = 4.0

@export_group("Shape")
@export var bed_half_width: float = 3.2
@export var shoulder_width: float = 9.0
@export var wall_start: float = 13.0
@export var mountain_width: float = 55.0
@export var mountain_height: float = 60.0
@export var valley_width: float = 70.0
@export var valley_depth: float = 45.0
@export var noise_amplitude: float = 9.0
@export var noise_seed: int = 7

@export_group("Colours")
@export var gravel_color: Color = Color(0.2, 0.19, 0.18)
@export var dirt_color: Color = Color(0.36, 0.31, 0.24)
@export var scrub_color: Color = Color(0.27, 0.29, 0.19)
@export var rock_color: Color = Color(0.4, 0.38, 0.36)

var _noise: FastNoiseLite
var _detail: FastNoiseLite
var _mean_y: float = 0.0


func _ready() -> void:
	if route == null:
		push_error("TerrainBuilder: no route assigned")
		return
	_setup()
	build()


func _setup() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.012
	_noise.fractal_octaves = 4
	_detail = FastNoiseLite.new()
	_detail.seed = noise_seed + 101
	_detail.frequency = 0.08
	var a := route.sample_world(0.0)
	var b := route.sample_world(route.get_length())
	_mean_y = (a.y + b.y) * 0.5


## Relation of a world XZ point to the track: x = signed lateral distance
## (negative = left of travel), y = track elevation, z = route offset.
func track_relation(x: float, z: float) -> Vector3:
	if _noise == null:
		_setup()
	var c3 := route.curve
	var local_guess := route.to_local(Vector3(x, _mean_y, z))
	var off := c3.get_closest_offset(local_guess)
	var c := route.sample_world(off)
	# Second pass using the found height: removes bias from the big elevation change.
	off = c3.get_closest_offset(route.to_local(Vector3(x, c.y, z)))
	c = route.sample_world(off)
	var t := route.tangent_world(off)
	var right := Vector3(-t.z, 0.0, t.x).normalized()
	var delta := Vector3(x - c.x, 0.0, z - c.z)
	var side := signf(delta.dot(right))
	if side == 0.0:
		side = 1.0
	return Vector3(delta.length() * side, c.y, off)


func sample_height(x: float, z: float) -> float:
	var rel := track_relation(x, z)
	return _height_from_relation(x, z, rel)


func _height_from_relation(x: float, z: float, rel: Vector3) -> float:
	var d := absf(rel.x)
	var base := rel.y - 0.35
	if d <= bed_half_width:
		return base
	var s := smoothstep(bed_half_width, bed_half_width + shoulder_width, d)
	var h := base + s * (0.4 + _detail.get_noise_2d(x, z) * 0.9)
	var n := _noise.get_noise_2d(x, z)
	if rel.x < 0.0:
		# Mountain side: steep rise with craggy noise.
		var w := smoothstep(wall_start, wall_start + mountain_width, d)
		h += mountain_height * pow(w, 0.7) + (n * noise_amplitude * 1.6 + absf(_detail.get_noise_2d(x * 0.5, z * 0.5)) * 4.0) * w
	else:
		# Valley side: falls away from the ledge.
		var w := smoothstep(wall_start, wall_start + valley_width, d)
		h -= valley_depth * w
		h += n * noise_amplitude * w
	return h


func build() -> void:
	for child in get_children():
		child.queue_free()
	# Bounding box of the route in XZ.
	var length := route.get_length()
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	var d := 0.0
	while d <= length:
		var p := route.sample_world(d)
		min_v = Vector2(minf(min_v.x, p.x), minf(min_v.y, p.z))
		max_v = Vector2(maxf(max_v.x, p.x), maxf(max_v.y, p.z))
		d += 10.0
	min_v -= Vector2(margin, margin)
	max_v += Vector2(margin, margin)
	var nx := int(ceil((max_v.x - min_v.x) / cell_size)) + 1
	var nz := int(ceil((max_v.y - min_v.y) / cell_size)) + 1

	var heights := PackedFloat32Array()
	heights.resize(nx * nz)
	var dists := PackedFloat32Array()
	dists.resize(nx * nz)
	for j in nz:
		for i in nx:
			var x := min_v.x + i * cell_size
			var z := min_v.y + j * cell_size
			var rel := track_relation(x, z)
			heights[j * nx + i] = _height_from_relation(x, z, rel)
			dists[j * nx + i] = absf(rel.x)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nz:
		for i in nx:
			var idx := j * nx + i
			var hl := heights[j * nx + maxi(i - 1, 0)]
			var hr := heights[j * nx + mini(i + 1, nx - 1)]
			var hd := heights[maxi(j - 1, 0) * nx + i]
			var hu := heights[mini(j + 1, nz - 1) * nx + i]
			var normal := Vector3(hl - hr, 2.0 * cell_size, hd - hu).normalized()
			var x := min_v.x + i * cell_size
			var z := min_v.y + j * cell_size
			st.set_normal(normal)
			st.set_color(_color_for(normal, dists[idx], x, z))
			st.set_uv(Vector2(x, z) * 0.05)
			st.add_vertex(to_local(Vector3(x, heights[idx], z)))
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			var b := a + 1
			var c := a + nx
			var dd := c + 1
			# Clockwise when viewed from above.
			st.add_index(a)
			st.add_index(b)
			st.add_index(dd)
			st.add_index(a)
			st.add_index(dd)
			st.add_index(c)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = st.commit()
	mi.material_override = material
	add_child(mi)


func _color_for(normal: Vector3, dist: float, x: float, z: float) -> Color:
	var steep := clampf((1.0 - normal.y) * 3.0, 0.0, 1.0)
	var patch := _detail.get_noise_2d(x * 0.3, z * 0.3) * 0.5 + 0.5
	var ground := dirt_color.lerp(scrub_color, patch)
	var col := ground.lerp(rock_color, steep)
	var near := 1.0 - smoothstep(bed_half_width, bed_half_width + 4.0, dist)
	return col.lerp(gravel_color, near)
