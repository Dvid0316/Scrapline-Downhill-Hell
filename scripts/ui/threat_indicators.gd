class_name ThreatIndicators
extends Control
## Draws where enemies are:
##   - off-screen enemies: a red arrow on the screen edge pointing at them
##   - kamikazes that are arming or diving: a pulsing red bracket, on screen
##     or off (bigger arrow), so the one about to hit you stands out
##   - heavily damaged ground vehicles: nothing extra (the scorch shows it)

@export var camera: Camera3D
@export var director: WaveDirector
@export var edge_margin: float = 34.0
@export var arrow_size: float = 13.0
@export var color: Color = Color(1.0, 0.25, 0.18, 0.85)
@export var danger_color: Color = Color(1.0, 0.1, 0.05, 1.0)

var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if camera == null or director == null:
		return
	var rect := get_viewport_rect()
	var centre := rect.size * 0.5
	var inner := rect.grow(-edge_margin)
	for e in director.get_alive():
		if not e.active or e.is_destroyed:
			continue
		var p := e.get_effect_origin()
		var danger: bool = e.has_method(&"is_threatening") and e.is_threatening()
		var col := danger_color if danger else color
		var behind := camera.is_position_behind(p)
		var s := camera.unproject_position(p)
		if behind:
			s = centre + (centre - s) * 1000.0  # mirror, push far off-screen
		if not behind and inner.has_point(s):
			if danger:
				_draw_bracket(s, col)
			continue
		var dir := (s - centre)
		if dir.length_squared() < 1.0:
			dir = Vector2.DOWN
		var pos := _edge_point(centre, dir.normalized(), inner)
		var size := arrow_size * (1.5 if danger else 1.0)
		if danger:
			size *= 1.0 + 0.2 * sin(_t * 18.0)
		_draw_arrow(pos, dir.normalized(), size, col)


func _edge_point(centre: Vector2, dir: Vector2, inner: Rect2) -> Vector2:
	var half := inner.size * 0.5
	var tx := INF if absf(dir.x) < 0.0001 else half.x / absf(dir.x)
	var ty := INF if absf(dir.y) < 0.0001 else half.y / absf(dir.y)
	return centre + dir * minf(tx, ty)


func _draw_arrow(pos: Vector2, dir: Vector2, size: float, col: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var tip := pos + dir * size
	var pts := PackedVector2Array([tip, pos - dir * size * 0.6 + side * size * 0.8, pos - dir * size * 0.6 - side * size * 0.8])
	draw_colored_polygon(pts, col)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.6), 1.5, true)


func _draw_bracket(s: Vector2, col: Color) -> void:
	var r := 26.0 + 5.0 * sin(_t * 16.0)
	var l := r * 0.45
	var w := 3.0
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var c := s + corner * r
		draw_line(c, c - Vector2(corner.x, 0) * l, col, w)
		draw_line(c, c - Vector2(0, corner.y) * l, col, w)
