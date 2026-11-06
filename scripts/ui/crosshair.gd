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
## Barrel reticle: a ring where the gun actually points.
@export var gun_ring_radius: float = 15.0
@export var gun_ring_color: Color = Color(1.0, 0.72, 0.25, 0.85)
## Within this many pixels of the cursor, the ring reads as "on target".
@export var on_target_pixels: float = 10.0

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
	var g: Variant = gun_provider.call() if gun_provider.is_valid() else null
	if g != null:
		var gp: Vector2 = g
		var on := gp.distance_to(c) < on_target_pixels
		var ring_col := gun_ring_color
		if on:
			ring_col.a = 0.45
		else:
			# Faint line from gun to cursor shows which way it's swinging.
			draw_line(gp, c, Color(ring_col, 0.25), 1.0)
		draw_arc(gp + Vector2(1, 1), gun_ring_radius, 0.0, TAU, 40, shadow, thickness + 1.0)
		draw_arc(gp, gun_ring_radius, 0.0, TAU, 40, ring_col, thickness)
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
## Returns the barrel reticle's screen position, or null to hide it.
var gun_provider: Callable


func get_aim_position() -> Vector2:
	if aim_provider.is_valid():
		return aim_provider.call()
	return get_local_mouse_position()
