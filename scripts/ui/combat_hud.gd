class_name CombatHud
extends CanvasLayer
## Minimal combat HUD: crosshair + hit marker, score panel (top-right), and
## short "+100 BUNKER" popups that float above destroyed targets.
## Built in code so the layout lives in one readable place.

@export var camera: Camera3D
@export var score: ScoreTracker
@export var weapon: HitscanWeapon
@export var turret_input: TurretInput
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
	if score:
		score.score_changed.connect(_on_score_changed)
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


func _process(delta: float) -> void:
	_refresh()
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
	_detail_label.text = "DESTROYED %d / %d\nHITS %d   ACC %d%%" % [kills, _total_targets, hits, int(acc)]


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
