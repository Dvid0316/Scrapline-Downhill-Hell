class_name Crosshair
extends Control
## Drawn crosshair that follows the aim point, plus a hit-marker "X" that
## flashes on hits (white) and kills (orange, bigger).
##
## Every stroke has a solid black outline so it reads on any background
## (sunny dirt, grass, sky, smoke). `C` cycles the colour; the choice is
## saved to user://settings.cfg.

const PRESETS: Array[Color] = [
	Color(1.0, 0.2, 0.8),    # hot pink: nothing in the world is this colour
	Color(0.25, 1.0, 0.2),   # neon green
	Color(0.2, 0.95, 1.0),   # cyan
	Color(1.0, 0.95, 0.1),   # yellow
	Color(1.0, 1.0, 1.0),    # white
]
const SETTINGS_PATH := "user://settings.cfg"

@export var color: Color = PRESETS[0]
@export var outline_color: Color = Color(0, 0, 0, 0.95)
## Extra pixels of black around every stroke.
@export var outline: float = 3.0
@export var hit_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var kill_color: Color = Color(1.0, 0.55, 0.15, 1.0)
@export var gap: float = 10.0
@export var arm: float = 24.0
@export var thickness: float = 4.0
@export var marker_time: float = 0.12
## Barrel reticle: a ring where the gun actually points.
@export var gun_ring_radius: float = 22.0
@export var gun_ring_color: Color = Color(1.0, 0.72, 0.25, 1.0)
## Within this many pixels of the cursor, the ring reads as "on target".
@export var on_target_pixels: float = 10.0
@export var cannon_color: Color = Color(1.0, 0.45, 0.2, 1.0)

var _marker_left: float = 0.0
var _marker_kill: bool = false
var preset_index: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		set_preset(int(cfg.get_value("crosshair", "preset", 0)), false)
	else:
		set_preset(0, false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"cycle_crosshair"):
		set_preset(preset_index + 1)


func set_preset(i: int, save: bool = true) -> void:
	preset_index = posmod(i, PRESETS.size())
	color = PRESETS[preset_index]
	# Rings follow the chosen colour so they never blend in where it doesn't.
	gun_ring_color = color.lerp(Color.WHITE, 0.45)
	cannon_color = color
	if save:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("crosshair", "preset", preset_index)
		cfg.save(SETTINGS_PATH)


## Line with a solid outline (outline drawn first, slightly longer).
func _oline(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var d := (b - a).normalized() * outline
	draw_line(a - d, b + d, outline_color, w + outline * 2.0)
	draw_line(a, b, col, w)


func _oarc(c: Vector2, radius: float, from: float, to: float, col: Color, w: float) -> void:
	draw_arc(c, radius, from, to, 48, outline_color, w + outline * 2.0, true)
	draw_arc(c, radius, from, to, 48, col, w, true)


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
	var shadow := outline_color
	for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_oline(c + dir * gap, c + dir * (gap + arm), color, thickness)
	draw_circle(c, 3.0 + outline, outline_color)
	draw_circle(c, 3.0, color)
	var g: Variant = gun_provider.call() if gun_provider.is_valid() else null
	if g != null:
		var gp: Vector2 = g
		var on := gp.distance_to(c) < on_target_pixels
		var ring_col := gun_ring_color
		if on:
			ring_col.a = 0.45
		else:
			# Faint line from gun to cursor shows which way it's swinging.
			draw_line(gp, c, Color(ring_col, 0.4), 1.5)
		_oarc(gp, gun_ring_radius, 0.0, TAU, ring_col, thickness - 0.5)
	_draw_cannon_ring(c, shadow)
	if _marker_left > 0.0:
		var col := kill_color if _marker_kill else hit_color
		var s := 1.4 if _marker_kill else 1.0
		var inner := 6.0 * s
		var outer := 14.0 * s
		for d: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			var n := d.normalized()
			_oline(c + n * inner, c + n * outer, col, thickness + 1.0)


## Cannon reload: an arc around the crosshair fills clockwise while it
## reloads, then shows a faint full ring with a brighter tick when loaded.
func _draw_cannon_ring(c: Vector2, _shadow: Color) -> void:
	var r: Variant = cannon_provider.call() if cannon_provider.is_valid() else null
	if r == null:
		return
	var ratio: float = r
	var radius := gap + arm + 10.0
	var start := -PI * 0.5
	if ratio >= 1.0:
		draw_arc(c, radius, 0.0, TAU, 48, Color(outline_color, 0.5), 2.0 + outline, true)
		draw_arc(c, radius, 0.0, TAU, 48, Color(cannon_color, 0.5), 2.0, true)
		for k in 4:
			var a := start + k * PI * 0.5
			var d := Vector2(cos(a), sin(a))
			_oline(c + d * (radius - 5.0), c + d * (radius + 5.0), cannon_color, 3.0)
	else:
		_oarc(c, radius, start, start + TAU * ratio, cannon_color, 3.0)


## Overridden by CombatHud via [member aim_provider].
var aim_provider: Callable
## Returns the barrel reticle's screen position, or null to hide it.
var gun_provider: Callable
## Returns the cannon's ready ratio (0 = just fired, 1 = loaded), or null.
var cannon_provider: Callable


func get_aim_position() -> Vector2:
	if aim_provider.is_valid():
		return aim_provider.call()
	return get_local_mouse_position()
