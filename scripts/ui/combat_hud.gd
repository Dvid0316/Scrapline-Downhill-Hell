class_name CombatHud
extends CanvasLayer
## Combat HUD, built in code so the layout lives in one readable place:
##   - crosshair + hit marker, and "+100 BUNKER" popups over kills
##   - score panel (top right)
##   - wave panel (top left): wave number, hostiles left, next-wave countdown
##   - hull bar (bottom centre), with a red screen-edge flash when hit
##   - off-screen threat arrows and kamikaze warnings ([ThreatIndicators])
##   - wave banners and the game-over panel

@export var camera: Camera3D
@export var score: ScoreTracker
@export var weapon: HitscanWeapon
@export var turret_input: TurretInput
@export var hull: TrainHull
@export var director: WaveDirector
@export_range(2, 16) var popup_pool: int = 8
@export var popup_time: float = 1.1

var crosshair: Crosshair
var _score_label: Label
var _detail_label: Label
var _popups: Array[Label] = []
var _popup_world: PackedVector3Array
var _popup_age: PackedFloat32Array
var _popup_next := 0
var _total_targets := 0

var threats: ThreatIndicators
var _wave_label: Label
var _wave_detail: Label
var _hull_bar: ProgressBar
var _hull_fill: StyleBoxFlat
var _hull_label: Label
var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _damage_flash: float = 0.0
var _banner: Label
var _banner_sub: Label
var _banner_age: float = 99.0
var _game_over: PanelContainer
var _game_over_stats: Label

const BANNER_TIME := 2.6
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = smoothstep(0.72, 1.0, max(d.x, d.y));
	COLOR = vec4(0.9, 0.06, 0.02, edge * strength * 0.75);
}
"""


func _ready() -> void:
	layer = 5
	crosshair = Crosshair.new()
	crosshair.name = "Crosshair"
	crosshair.aim_provider = _aim_position
	crosshair.gun_provider = _gun_position
	add_child(crosshair)

	var panel := PanelContainer.new()
	panel.name = "ScorePanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.06, 0.72)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -16
	panel.offset_top = 16
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	_score_label = _make_label(34, Color(1.0, 0.85, 0.35))
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_score_label)
	_detail_label = _make_label(16, Color(0.85, 0.83, 0.78))
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_detail_label)

	_popup_world.resize(popup_pool)
	_popup_age.resize(popup_pool)
	for i in popup_pool:
		var l := _make_label(24, Color(1.0, 0.75, 0.3))
		l.visible = false
		l.add_theme_constant_override(&"outline_size", 6)
		l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
		add_child(l)
		_popups.append(l)
		_popup_age[i] = 99.0
	_build_wave_panel()
	_build_hull_bar()
	_build_banner()
	_build_game_over()
	_vignette = ColorRect.new()
	_vignette.name = "DamageVignette"
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = sh
	_vignette.material = _vignette_mat
	_vignette.visible = false
	add_child(_vignette)
	move_child(_vignette, 0)
	threats = ThreatIndicators.new()
	threats.name = "Threats"
	threats.camera = camera
	threats.director = director
	add_child(threats)
	move_child(threats, 1)

	if score:
		score.score_changed.connect(_on_score_changed)
	if hull:
		hull.hull_changed.connect(_on_hull_changed)
		_on_hull_changed(hull.hull, hull.max_hull)
	_refresh()


func set_total_targets(n: int) -> void:
	_total_targets = n
	_refresh()


func show_hit_marker(killed: bool) -> void:
	crosshair.show_hit(killed)


func show_popup(text: String, world_pos: Vector3) -> void:
	var i := _popup_next
	_popup_next = (_popup_next + 1) % popup_pool
	_popups[i].text = text
	_popup_world[i] = world_pos
	_popup_age[i] = 0.0
	_popups[i].visible = true


## Red flash at the screen edges; bigger hits flash harder.
func flash_damage(amount: float) -> void:
	_damage_flash = clampf(maxf(_damage_flash, 0.25 + amount / 40.0), 0.0, 1.0)


func show_banner(title: String, subtitle: String = "") -> void:
	_banner.text = title
	_banner_sub.text = subtitle
	_banner_age = 0.0


func show_game_over(wave: int, final_score: int, kills: int) -> void:
	_game_over_stats.text = "Made it to wave %d\nScore %d   ·   %d enemies destroyed" % [wave, final_score, kills]
	_game_over.visible = true
	_banner_age = 99.0


func hide_game_over() -> void:
	_game_over.visible = false
	_banner_age = 99.0
	_damage_flash = 0.0


func is_game_over_visible() -> bool:
	return _game_over.visible


func _process(delta: float) -> void:
	_refresh()
	_update_effects(delta)
	for i in popup_pool:
		if _popup_age[i] >= popup_time:
			continue
		_popup_age[i] += delta
		var l := _popups[i]
		var t := _popup_age[i] / popup_time
		if t >= 1.0 or camera == null or camera.is_position_behind(_popup_world[i]):
			l.visible = false
			continue
		var p := camera.unproject_position(_popup_world[i])
		l.position = p - l.size * 0.5 + Vector2(0, -50.0 * t)
		l.modulate.a = 1.0 - t * t
		var s := 1.0 + 0.25 * maxf(0.0, 1.0 - t * 6.0)
		l.scale = Vector2(s, s)


func _on_score_changed(_score: int, _destroyed: int) -> void:
	_refresh()


func _refresh() -> void:
	if _score_label == null:
		return
	var sc := score.score if score else 0
	var kills := score.destroyed if score else 0
	_score_label.text = "%d" % sc
	var hits := weapon.shots_hit if weapon else 0
	var shots := weapon.shots_fired if weapon else 0
	var acc := (100.0 * hits / shots) if shots > 0 else 0.0
	var enemy_kills := score.enemy_kills if score else 0
	_detail_label.text = "ENEMIES %d   TARGETS %d / %d\nHITS %d   ACC %d%%" % [
		enemy_kills, kills - enemy_kills, _total_targets, hits, int(acc)]
	_refresh_wave()


func _refresh_wave() -> void:
	if _wave_label == null:
		return
	if director == null or not director.enabled:
		_wave_label.text = "NO ENEMIES"
		_wave_detail.text = "free-fire range"
		return
	match director.state:
		WaveDirector.State.SPAWNING:
			_wave_label.text = "WAVE %d" % director.wave
			_wave_detail.text = "%d hostile%s left" % [director.get_remaining(), "" if director.get_remaining() == 1 else "s"]
		WaveDirector.State.BREATHER:
			_wave_label.text = "WAVE %d" % (director.wave + 1)
			_wave_detail.text = "incoming in %d" % ceili(maxf(director.breather_left, 0.0))
		WaveDirector.State.STOPPED:
			_wave_label.text = "WAVE %d" % director.wave
			_wave_detail.text = "train wrecked"
		_:
			_wave_label.text = ""
			_wave_detail.text = ""


func _on_hull_changed(value: float, max_value: float) -> void:
	if _hull_bar == null:
		return
	_hull_bar.max_value = max_value
	_hull_bar.value = value
	var r := value / max_value if max_value > 0.0 else 0.0
	_hull_label.text = "HULL  %d%%" % int(ceil(r * 100.0))
	var good := Color(0.55, 0.8, 0.35)
	var mid := Color(0.95, 0.72, 0.2)
	var bad := Color(0.95, 0.2, 0.12)
	_hull_fill.bg_color = bad.lerp(mid, r * 2.0) if r < 0.5 else mid.lerp(good, (r - 0.5) * 2.0)


func _update_effects(delta: float) -> void:
	# Damage vignette fades out; a low hull keeps a faint pulse.
	_damage_flash = maxf(_damage_flash - delta * 2.2, 0.0)
	var low := 0.0
	if hull and not hull.is_wrecked and hull.get_ratio() < 0.25:
		low = 0.18 + 0.1 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
	var strength := maxf(_damage_flash, low)
	_vignette.visible = strength > 0.01
	_vignette_mat.set_shader_parameter(&"strength", strength)
	# Banner: pop in, hold, fade.
	if _banner_age < BANNER_TIME:
		_banner_age += delta
		var t := _banner_age / BANNER_TIME
		var a := clampf(_banner_age / 0.15, 0.0, 1.0) * clampf((1.0 - t) / 0.25, 0.0, 1.0)
		_banner.modulate.a = a
		_banner_sub.modulate.a = a
		var sc := 1.0 + 0.3 * maxf(0.0, 1.0 - _banner_age / 0.2)
		_banner.scale = Vector2(sc, sc)
		_banner.visible = true
		_banner_sub.visible = true
	else:
		_banner.visible = false
		_banner_sub.visible = false


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.06, 0.72)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	return style


func _build_wave_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "WavePanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(&"panel", _panel_style())
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -110
	panel.offset_right = 110
	panel.offset_top = 16
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	_wave_label = _make_label(30, Color(1.0, 0.45, 0.32))
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_wave_label)
	_wave_detail = _make_label(16, Color(0.85, 0.83, 0.78))
	_wave_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_wave_detail)


func _build_hull_bar() -> void:
	var box := VBoxContainer.new()
	box.name = "HullBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_left = -220
	box.offset_right = 220
	box.offset_bottom = -22
	add_child(box)
	_hull_label = _make_label(16, Color(0.9, 0.88, 0.82))
	_hull_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hull_label.add_theme_constant_override(&"outline_size", 5)
	_hull_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	box.add_child(_hull_label)
	_hull_bar = ProgressBar.new()
	_hull_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hull_bar.show_percentage = false
	_hull_bar.custom_minimum_size = Vector2(440, 16)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.06, 0.75)
	bg.set_corner_radius_all(4)
	bg.border_color = Color(0, 0, 0, 0.8)
	bg.set_border_width_all(2)
	_hull_fill = StyleBoxFlat.new()
	_hull_fill.bg_color = Color(0.55, 0.8, 0.35)
	_hull_fill.set_corner_radius_all(3)
	_hull_bar.add_theme_stylebox_override(&"background", bg)
	_hull_bar.add_theme_stylebox_override(&"fill", _hull_fill)
	_hull_bar.max_value = 1.0
	_hull_bar.value = 1.0
	box.add_child(_hull_bar)
	_hull_label.text = "HULL  100%"


func _build_banner() -> void:
	_banner = _make_label(64, Color(1.0, 0.82, 0.35))
	_banner.name = "Banner"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override(&"outline_size", 10)
	_banner.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_left = -500
	_banner.offset_right = 500
	_banner.offset_top = 170
	_banner.pivot_offset = Vector2(500, 40)
	_banner.visible = false
	add_child(_banner)
	_banner_sub = _make_label(24, Color(0.95, 0.92, 0.85))
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.add_theme_constant_override(&"outline_size", 6)
	_banner_sub.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_banner_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner_sub.offset_left = -500
	_banner_sub.offset_right = 500
	_banner_sub.offset_top = 256
	_banner_sub.visible = false
	add_child(_banner_sub)


func _build_game_over() -> void:
	_game_over = PanelContainer.new()
	_game_over.name = "GameOver"
	_game_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _panel_style()
	style.bg_color = Color(0.04, 0.03, 0.03, 0.85)
	style.set_content_margin_all(28)
	style.border_color = Color(0.8, 0.2, 0.12, 0.9)
	style.set_border_width_all(2)
	_game_over.add_theme_stylebox_override(&"panel", style)
	_game_over.set_anchors_preset(Control.PRESET_CENTER)
	_game_over.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_game_over.grow_vertical = Control.GROW_DIRECTION_BOTH
	_game_over.visible = false
	add_child(_game_over)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 12)
	_game_over.add_child(box)
	var title := _make_label(56, Color(1.0, 0.35, 0.22))
	title.text = "TRAIN WRECKED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_game_over_stats = _make_label(24, Color(0.92, 0.9, 0.85))
	_game_over_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_game_over_stats)
	var hint := _make_label(22, Color(1.0, 0.82, 0.35))
	hint.text = "Press  R  to roll out again"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _aim_position() -> Vector2:
	if turret_input:
		return turret_input.aim_screen_position
	return crosshair.get_local_mouse_position()


func _gun_position() -> Variant:
	if turret_input and turret_input.gun_point_visible:
		return turret_input.gun_screen_position
	return null


func _make_label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", col)
	return l
