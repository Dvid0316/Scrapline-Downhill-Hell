class_name Crosshair
extends Control
## Drawn crosshair that follows the aim point, plus a hit-marker "X" that
## flashes on hits (white) and kills (orange, bigger).

@export var color: Color = Color(1.0, 1.0, 0.95, 0.9)
@export var hit_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var kill_color: Color = Color(1.0, 0.55, 0.15, 1.0)
@export var gap: float = 7.0
@export var arm: float = 11.0
@export var thickness: float = 2.0
@export var marker_time: float = 0.12

var _marker_left: float = 0.0
var _marker_kill: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_hit(killed: bool) -> void:
	# A kill marker isn't overwritten by ordinary hits in the same window.
	if killed or not (_marker_kill and _marker_left > 0.0):
		_marker_kill = killed
		_marker_left = marker_time * (2.0 if killed else 1.0)


func _process(delta: float) -> void:
	if _marker_left > 0.0:
		_marker_left -= delta
	queue_redraw()


func _draw() -> void:
	var c := get_aim_position()
	var shadow := Color(0, 0, 0, 0.5)
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var a := c + dir * gap
		var b := c + dir * (gap + arm)
		draw_line(a + Vector2(1, 1), b + Vector2(1, 1), shadow, thickness + 1.0)
		draw_line(a, b, color, thickness)
	draw_circle(c, 1.5, color)
	if _marker_left > 0.0:
		var col := kill_color if _marker_kill else hit_color
		var s := 1.4 if _marker_kill else 1.0
		var inner := 6.0 * s
		var outer := 14.0 * s
		for d: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			var n := d.normalized()
			draw_line(c + n * inner, c + n * outer, col, thickness + 1.0)


## Overridden by CombatHud via [member aim_provider].
var aim_provider: Callable


func get_aim_position() -> Vector2:
	if aim_provider.is_valid():
		return aim_provider.call()
	return get_local_mouse_position()
