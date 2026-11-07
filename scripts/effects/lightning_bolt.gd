class_name LightningBolt
extends MeshInstance3D
## A crackling electric arc along a chain of points (Tesla coil zaps).
##
## Each frame it re-jags the path and rebuilds two camera-facing ribbons, a
## wide soft glow and a hot thin core, in additive blend, then fades out.
## One ImmediateMesh, no textures. Lives in world space (top_level).

@export var duration: float = 0.22
@export var jag: float = 0.55
@export var core_width: float = 0.24
@export var glow_width: float = 1.1
@export var color := Color(0.3, 0.75, 1.0)

var _points := PackedVector3Array()
var _age: float = 99.0
var _im := ImmediateMesh.new()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	material_override = m
	visible = false
	set_process(false)


## Arc through [param points] (coil top, first target, chained targets...).
func strike(points: PackedVector3Array) -> void:
	_points = points
	_age = 0.0
	global_transform = Transform3D.IDENTITY  # points are world space
	visible = true
	set_process(true)
	_rebuild()


func is_active() -> bool:
	return _age < duration


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		visible = false
		_im.clear_surfaces()
		set_process(false)
		return
	_rebuild()


func _rebuild() -> void:
	_im.clear_surfaces()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or _points.size() < 2:
		return
	var fade := 1.0 - _age / duration
	var flicker := 0.7 + 0.3 * _rng.randf()
	var path := PackedVector3Array()
	for i in _points.size() - 1:
		var a := _points[i]
		var b := _points[i + 1]
		var segs := clampi(int(a.distance_to(b) / 1.6), 3, 24)
		for s in segs:
			var t := float(s) / segs
			var p := a.lerp(b, t)
			if s > 0:
				p += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * jag * sin(t * PI) * 1.4
			path.append(p)
	path.append(_points[_points.size() - 1])
	var eye := cam.global_position
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_ribbon(path, eye, glow_width, Color(color, 0.5 * fade * flicker))
	_ribbon(path, eye, core_width, Color(color.lerp(Color.WHITE, 0.7), fade * flicker))
	_im.surface_end()


func _ribbon(path: PackedVector3Array, eye: Vector3, width: float, c: Color) -> void:
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var side := (b - a).cross(eye - a).normalized() * width * 0.5
		var quad := [a - side, a + side, b + side, a - side, b + side, b - side]
		for v: Vector3 in quad:
			_im.surface_set_color(c)
			_im.surface_add_vertex(v)
