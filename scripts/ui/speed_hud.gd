class_name SpeedHud
extends Control
## Speed feedback: a chunky speedometer (bottom left) and speed lines that
## streak in from the screen edges as the train gets fast. Colour shifts
## from white to orange to red, and the readout shakes when you're flying.

@export var train: TrainController
## Speed lines start at this speed (m/s) and are full strength at [member lines_full].
@export var lines_start: float = 30.0
@export var lines_full: float = 65.0
## Gauge full scale (km/h).
@export var gauge_max_kmh: float = 300.0

const LINES_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
uniform float aspect = 1.78;
float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
void fragment() {
	vec2 p = UV - 0.5;
	p.x *= aspect;
	float r = length(p);
	float ang = atan(p.y, p.x) / 6.28318 + 0.5;
	float n = 110.0;
	float seg = floor(ang * n);
	float h = hash(seg);
	float a = fract(ang * n);
	float thin = 1.0 - smoothstep(0.0, 0.22, abs(a - 0.5));
	float band = fract(r * 1.2 - TIME * (1.6 + h * 1.8) + h * 9.0);
	float streak = smoothstep(0.55, 0.95, band) * step(0.55, hash(seg + 3.1));
	float edge = smoothstep(0.28, 0.75, r);
	COLOR = vec4(1.0, 1.0, 1.0, streak * thin * edge * strength * 0.55);
}
"""

var _lines: ColorRect
var _lines_mat: ShaderMaterial
var _t: float = 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lines = ColorRect.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lines_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = LINES_SHADER
	_lines_mat.shader = sh
	_lines.material = _lines_mat
	add_child(_lines)
	_font = ThemeDB.fallback_font


## 0..1 how "fast" it feels (drives lines, colour, camera FOV).
func get_rush() -> float:
	if train == null:
		return 0.0
	return clampf((train.speed - lines_start) / (lines_full - lines_start), 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	var rush := get_rush()
	_lines_mat.set_shader_parameter(&"strength", rush)
	var vs := get_viewport_rect().size
	_lines_mat.set_shader_parameter(&"aspect", vs.x / maxf(vs.y, 1.0))
	queue_redraw()


func _draw() -> void:
	if train == null:
		return
	var kmh := train.speed * 3.6
	var rush := get_rush()
	var vs := get_viewport_rect().size
	var c := Vector2(110.0, vs.y - 95.0)
	var shake := Vector2(sin(_t * 53.0), cos(_t * 47.0)) * 2.5 * rush * rush
	c += shake
	var col := Color.WHITE.lerp(Color(1.0, 0.6, 0.1), clampf(rush * 1.6, 0.0, 1.0))
	col = col.lerp(Color(1.0, 0.15, 0.1), clampf(rush * 2.0 - 1.0, 0.0, 1.0))
	# Gauge arc: 220° sweep, background + fill.
	var r := 70.0
	var a0 := deg_to_rad(160.0)
	var sweep := deg_to_rad(220.0)
	var f := clampf(kmh / gauge_max_kmh, 0.0, 1.0)
	draw_arc(c, r, a0, a0 + sweep, 48, Color(0, 0, 0, 0.55), 16.0, true)
	draw_arc(c, r, a0, a0 + sweep * f, 48, col, 10.0, true)
	# Driver's set speed: a tick on the gauge.
	var ta := a0 + sweep * clampf(train.target_speed * 3.6 / gauge_max_kmh, 0.0, 1.0)
	var td := Vector2(cos(ta), sin(ta))
	draw_line(c + td * (r - 12.0), c + td * (r + 12.0), Color(0, 0, 0, 0.9), 6.0)
	draw_line(c + td * (r - 10.0), c + td * (r + 10.0), Color(0.4, 0.9, 1.0), 3.0)
	# Big number with an outline.
	var txt := "%d" % roundi(kmh)
	var size := 46
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := c + Vector2(-w * 0.5, 14.0)
	draw_string_outline(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(0, 0, 0, 0.9))
	draw_string(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	var unit := "KM/H"
	var uw := _font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string_outline(_font, c + Vector2(-uw * 0.5, 36.0), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color(0, 0, 0, 0.9))
	draw_string(_font, c + Vector2(-uw * 0.5, 36.0), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.85, 0.85))
	# Grade indicator: arrow up/down with percent, so you see the hill coming.
	var g := train.get_current_grade()
	if absf(g) > 3.0:
		var gt := ("▲ %d%%" if g > 0.0 else "▼ %d%%") % absi(roundi(g))
		var gc := Color(0.5, 0.85, 1.0) if g > 0.0 else Color(1.0, 0.75, 0.3)
		draw_string_outline(_font, c + Vector2(-30.0, 62.0), gt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 5, Color(0, 0, 0, 0.9))
		draw_string(_font, c + Vector2(-30.0, 62.0), gt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, gc)
