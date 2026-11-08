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
@export_range(1.0, 16.0) var cell_size: float = 3.0

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

@export_group("Rollercoaster ground")
## On the coaster section the ground follows the valleys instead of the
## track, so crests stand on trestles and dips cut into the hills.
@export var coaster_ground: bool = true
## Window (metres either side) for the valley envelope.
@export var envelope_window: float = 45.0
## Smoothing window for the ground line.
@export var ground_smoothing: float = 35.0
## The track never stands more than this far above the ground.
@export var max_lift: float = 26.0
## Up to this height the track runs on an earth embankment; higher = trestle.
@export var embankment_max: float = 5.0

@export_group("Pre-plunge tunnel")
## The final route tunnel is tied to these control points, so it follows route edits.
@export_range(0, 60, 1) var tunnel_start_point: int = 32
@export_range(0, 60, 1) var tunnel_end_point: int = 35
@export var tunnel_half_width: float = 6.5
@export var tunnel_cut_depth: float = 3.0

## Build a static collider (WORLD layer) so shots and the aim ray hit the ground.
@export var generate_collision: bool = true

@export_group("Colours")
@export var gravel_color: Color = Color(0.2, 0.19, 0.18)
@export var dirt_color: Color = Color(0.36, 0.31, 0.24)
@export var scrub_color: Color = Color(0.27, 0.29, 0.19)
@export var rock_color: Color = Color(0.4, 0.38, 0.36)

var _noise: FastNoiseLite
var _detail: FastNoiseLite
var _mean_y: float = 0.0
# Built height grid (world space), so sample_height() matches the mesh exactly.
var _grid: PackedFloat32Array
var _grid_nx: int = 0
var _grid_nz: int = 0
var _grid_min: Vector2
var _grid_dist: PackedFloat32Array
# Ground line under the route (world y), sampled every GROUND_STEP metres.
const GROUND_STEP := 2.0
var _ground: PackedFloat32Array
var _tunnel_start_offset: float = 0.0
var _tunnel_end_offset: float = 0.0


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
	_build_ground_line()
	_update_tunnel_offsets()


func _update_tunnel_offsets() -> void:
	_tunnel_start_offset = 0.0
	_tunnel_end_offset = 0.0
	if route.control_points.is_empty():
		return
	var first := clampi(tunnel_start_point, 0, route.control_points.size() - 1)
	var last := clampi(tunnel_end_point, first, route.control_points.size() - 1)
	_tunnel_start_offset = route.curve.get_closest_offset(route.control_points[first])
	_tunnel_end_offset = route.curve.get_closest_offset(route.control_points[last])


## Ground elevation under the track: equal to the track on the gentle part;
## on the coaster, a smoothed lower envelope of the track (the valleys).
func _build_ground_line() -> void:
	var length := route.get_length()
	var n := int(ceil(length / GROUND_STEP)) + 1
	var track := PackedFloat32Array()
	track.resize(n)
	for i in n:
		track[i] = route.sample_world(i * GROUND_STEP).y
	_ground = track.duplicate()
	if not coaster_ground or not route.has_method(&"get_coaster_start"):
		return
	var w := int(envelope_window / GROUND_STEP)
	var env := PackedFloat32Array()
	env.resize(n)
	for i in n:
		var m := INF
		for k in range(maxi(i - w, 0), mini(i + w, n - 1) + 1):
			m = minf(m, track[k])
		env[i] = maxf(m, track[i] - max_lift)
	var sw := int(ground_smoothing / GROUND_STEP)
	for pass_i in 2:
		var sm := PackedFloat32Array()
		sm.resize(n)
		for i in n:
			var sum := 0.0
			var cnt := 0
			for k in range(maxi(i - sw, 0), mini(i + sw, n - 1) + 1):
				sum += env[k]
				cnt += 1
			sm[i] = sum / cnt
		env = sm
	var start: float = route.get_coaster_start()
	for i in n:
		var f := smoothstep(start - 20.0, start + 60.0, i * GROUND_STEP)
		_ground[i] = lerpf(track[i], minf(env[i], track[i] + 2.0), f)


## Ground elevation under the route at [param offset].
func ground_at(offset: float) -> float:
	if _ground.is_empty():
		return route.sample_world(offset).y
	var f := clampf(offset / GROUND_STEP, 0.0, _ground.size() - 1.001)
	var i := int(f)
	return lerpf(_ground[i], _ground[i + 1], f - i)


## How far the track stands above its ground at [param offset] (negative = cutting).
func track_lift(offset: float) -> float:
	return route.sample_world(offset).y - ground_at(offset)


func is_trestle(offset: float) -> bool:
	return track_lift(offset) > embankment_max


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


## Ground height at world XZ. After build() this reads the generated grid
## with the same triangle split as the mesh, so props sit exactly on the
## visible surface. Before build (or outside the grid) it uses the analytic shape.
func sample_height(x: float, z: float) -> float:
	if _grid_nx > 1:
		var gx := (x - _grid_min.x) / cell_size
		var gz := (z - _grid_min.y) / cell_size
		var i := int(floor(gx))
		var j := int(floor(gz))
		if i >= 0 and j >= 0 and i < _grid_nx - 1 and j < _grid_nz - 1:
			var u := gx - i
			var v := gz - j
			var a := _grid[j * _grid_nx + i]
			var b := _grid[j * _grid_nx + i + 1]
			var c := _grid[(j + 1) * _grid_nx + i]
			var d := _grid[(j + 1) * _grid_nx + i + 1]
			# Mesh triangles are (a, b, d) and (a, d, c).
			if u >= v:
				return a + (b - a) * u + (d - b) * v
			return a + (c - a) * v + (d - c) * u
	return analytic_height(x, z)


## Distance to the track centreline at world XZ, from the built grid
## (nearest cell; cheap enough for scattering thousands of plants).
func sample_track_distance(x: float, z: float) -> float:
	if _grid_nx > 1:
		var i := clampi(int(round((x - _grid_min.x) / cell_size)), 0, _grid_nx - 1)
		var j := clampi(int(round((z - _grid_min.y) / cell_size)), 0, _grid_nz - 1)
		return _grid_dist[j * _grid_nx + i]
	return absf(track_relation(x, z).x)


## Ground normal at world XZ from the height grid.
func sample_normal(x: float, z: float) -> Vector3:
	var e := cell_size
	var hl := sample_height(x - e, z)
	var hr := sample_height(x + e, z)
	var hd := sample_height(x, z - e)
	var hu := sample_height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


## World XZ rectangle covered by the terrain grid.
func get_bounds() -> Rect2:
	return Rect2(_grid_min, Vector2((_grid_nx - 1) * cell_size, (_grid_nz - 1) * cell_size))


func analytic_height(x: float, z: float) -> float:
	var rel := track_relation(x, z)
	return _height_from_relation(x, z, rel)


func _height_from_relation(x: float, z: float, rel: Vector3) -> float:
	var d := absf(rel.x)
	var bed := rel.y - 0.35
	var ground := ground_at(rel.z) - 0.35
	var lift := bed - ground
	var base := bed
	if lift > embankment_max:
		# Trestle: natural ground everywhere, the track flies over it.
		base = ground
	elif absf(lift) > 0.05:
		# Embankment (lift > 0) or cutting (lift < 0): slope from the bed out
		# to the natural ground.
		var reach := bed_half_width + 1.0 + absf(lift) * (2.2 if lift > 0.0 else 1.4)
		base = lerpf(bed, ground, smoothstep(bed_half_width, reach, d))
	if d <= bed_half_width:
		return _apply_tunnel_cut(base, rel)
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
	return _apply_tunnel_cut(h, rel)


## Excavate a rounded corridor through the terrain before the final plunge.
func _apply_tunnel_cut(height: float, rel: Vector3) -> float:
	if _tunnel_end_offset <= _tunnel_start_offset:
		return height
	var along := smoothstep(_tunnel_start_offset - 5.0, _tunnel_start_offset + 5.0, rel.z)
	along *= 1.0 - smoothstep(_tunnel_end_offset - 5.0, _tunnel_end_offset + 5.0, rel.z)
	var across := 1.0 - smoothstep(tunnel_half_width, tunnel_half_width + 3.0, absf(rel.x))
	return lerpf(height, rel.y - tunnel_cut_depth, along * across)


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
	var sides := PackedByteArray()
	sides.resize(nx * nz)
	var flying := PackedByteArray()
	flying.resize(nx * nz)
	for j in nz:
		for i in nx:
			var x := min_v.x + i * cell_size
			var z := min_v.y + j * cell_size
			var rel := track_relation(x, z)
			heights[j * nx + i] = _height_from_relation(x, z, rel)
			dists[j * nx + i] = absf(rel.x)
			sides[j * nx + i] = 1 if rel.x < 0.0 else 0
			flying[j * nx + i] = 1 if is_trestle(rel.z) else 0

	_grid = heights
	_grid_dist = dists
	_grid_nx = nx
	_grid_nz = nz
	_grid_min = min_v

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
			st.set_color(_color_for(normal, dists[idx] + (40.0 if flying[idx] == 1 else 0.0), x, z, sides[idx] == 1))
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
	if generate_collision:
		var body := StaticBody3D.new()
		body.name = "TerrainBody"
		body.collision_layer = PhysicsLayers.WORLD
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mi.mesh.create_trimesh_shape()
		body.add_child(shape)
		mi.add_child(body)
	_build_tunnel_interior()


## Create a dark rock-lined arch, repeated structural ribs, and warm guide lights.
func _build_tunnel_interior() -> void:
	if _tunnel_end_offset <= _tunnel_start_offset:
		return
	var lining := StandardMaterial3D.new()
	lining.albedo_color = Color(0.105, 0.095, 0.085)
	lining.roughness = 0.95
	lining.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rib_material := StandardMaterial3D.new()
	rib_material.albedo_color = Color(0.24, 0.20, 0.16)
	rib_material.roughness = 0.85
	rib_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var start := maxf(_tunnel_start_offset - 2.0, 0.0)
	var end := minf(_tunnel_end_offset + 2.0, route.get_length())
	var shell := MeshInstance3D.new()
	shell.name = "TunnelInterior"
	shell.mesh = _make_tunnel_arch_mesh(start, end, 2.0)
	shell.material_override = lining
	add_child(shell)

	var rib_offset := start
	while rib_offset <= end:
		var rib := MeshInstance3D.new()
		rib.name = "TunnelRib"
		rib.mesh = _make_tunnel_arch_mesh(maxf(rib_offset - 0.22, start), minf(rib_offset + 0.22, end), 0.44)
		rib.material_override = rib_material
		add_child(rib)
		rib_offset += 8.0

	# Portal ribs frame both openings, even when the regular rib spacing misses them.
	for portal_offset in [start, end]:
		var portal := MeshInstance3D.new()
		portal.name = "TunnelPortalFrame"
		portal.mesh = _make_tunnel_arch_mesh(maxf(portal_offset - 0.32, start), minf(portal_offset + 0.32, end), 0.64)
		portal.material_override = rib_material
		add_child(portal)

	var light_offset := start + 10.0
	while light_offset < end:
		var lamp := OmniLight3D.new()
		lamp.name = "TunnelLamp"
		lamp.light_color = Color(1.0, 0.58, 0.28)
		lamp.light_energy = 2.0
		lamp.omni_range = 18.0
		lamp.position = to_local(route.sample_world(light_offset) + Vector3.UP * 6.2)
		add_child(lamp)
		light_offset += 24.0


func _make_tunnel_arch_mesh(start: float, end: float, step: float) -> ArrayMesh:
	var profile := PackedVector2Array()
	var radius := tunnel_half_width - 0.2
	profile.append(Vector2(-radius, -tunnel_cut_depth + 0.2))
	for i in 13:
		var angle := PI - float(i) / 12.0 * PI
		profile.append(Vector2(cos(angle) * radius, 3.0 + sin(angle) * radius))
	profile.append(Vector2(radius, -tunnel_cut_depth + 0.2))

	var length := maxf(end - start, 0.05)
	var slice_count := maxi(int(ceil(length / maxf(step, 0.1))) + 1, 2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in slice_count:
		var offset := lerpf(start, end, float(i) / float(slice_count - 1))
		var centre := route.sample_world(offset)
		var tangent := route.tangent_world(offset)
		var flat_tangent := Vector3(tangent.x, 0.0, tangent.z).normalized()
		var right := Vector3(-flat_tangent.z, 0.0, flat_tangent.x)
		for point in profile:
			var world_point := centre + right * point.x + Vector3.UP * point.y
			st.add_vertex(to_local(world_point))
	for i in slice_count - 1:
		for j in profile.size() - 1:
			var a := i * profile.size() + j
			var b := a + 1
			var c := a + profile.size()
			var d := c + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(d)
			st.add_index(a)
			st.add_index(d)
			st.add_index(b)
		st.generate_normals()
	return st.commit()


## Vertex colour = blend masks for the terrain shader:
## r = gravel (next to the track), g = shoulder dirt, b = mountain side.
func _color_for(_normal: Vector3, dist: float, x: float, z: float, mountain: bool) -> Color:
	var gravel := 1.0 - smoothstep(bed_half_width + 0.5, bed_half_width + 3.0, dist)
	var wobble := _detail.get_noise_2d(x * 0.15, z * 0.15) * 2.5
	var shoulder := 1.0 - smoothstep(bed_half_width + 4.0, bed_half_width + shoulder_width + 2.0 + wobble, dist)
	return Color(gravel, shoulder, 1.0 if mountain else 0.0)
