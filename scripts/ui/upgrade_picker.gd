class_name UpgradePicker
extends CanvasLayer
## The between-wave upgrade cards. Big, bright and readable: each card has
## a coloured category strip, a name, level pips, one plain sentence and its
## key. Click a card or press 1 / 2 / 3.

signal chosen(index: int)

const CARD_SIZE := Vector2(300, 330)

var _root: Control
var _title: Label
var _sub: Label
var _row: HBoxContainer
var _cards: Array[Button] = []
var _open := false


func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	_sub = _label(22, Color(1.0, 0.7, 0.25))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_sub)
	_title = _label(46, Color.WHITE)
	_title.text = "CHOOSE AN UPGRADE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	col.add_child(gap)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override(&"separation", 26)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_row)
	var hint := _label(18, Color(0.85, 0.85, 0.85))
	hint.text = "Click a card, or press 1 / 2 / 3"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(gap.duplicate())
	col.add_child(hint)
	visible = false


func is_open() -> bool:
	return _open


func open(wave: int, cards: Array[Dictionary]) -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_sub.text = "WAVE %d CLEARED" % wave if wave > 0 else "UPGRADE"
	for i in cards.size():
		var b := _make_card(i, cards[i])
		_row.add_child(b)
		_cards.append(b)
	visible = true
	_open = true
	# Cards pop up one after another.
	for i in _cards.size():
		var b := _cards[i]
		b.modulate.a = 0.0
		b.scale = Vector2(0.85, 0.85)
		var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.08 * i)
		tw.tween_property(b, "modulate:a", 1.0, 0.18)
		tw.parallel().tween_property(b, "scale", Vector2.ONE, 0.3)


func close() -> void:
	visible = false
	_open = false


func get_card_count() -> int:
	return _cards.size()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		var i := -1
		match k:
			KEY_1, KEY_KP_1: i = 0
			KEY_2, KEY_KP_2: i = 1
			KEY_3, KEY_KP_3: i = 2
			KEY_4, KEY_KP_4: i = 3
		if i >= 0 and i < _cards.size():
			get_viewport().set_input_as_handled()
			chosen.emit(i)


func _make_card(i: int, d: Dictionary) -> Button:
	var color: Color = d["color"]
	var b := Button.new()
	b.name = "Card%d" % i
	b.custom_minimum_size = CARD_SIZE
	b.pivot_offset = CARD_SIZE * 0.5
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override(&"normal", _card_style(color, false))
	b.add_theme_stylebox_override(&"hover", _card_style(color, true))
	b.add_theme_stylebox_override(&"pressed", _card_style(color, true))
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	b.pressed.connect(func() -> void: chosen.emit(i))
	b.mouse_entered.connect(func() -> void:
		create_tween().tween_property(b, "scale", Vector2(1.05, 1.05), 0.08))
	b.mouse_exited.connect(func() -> void:
		create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18
	box.offset_right = -18
	box.offset_top = 0
	box.offset_bottom = -16
	box.add_theme_constant_override(&"separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	# Category strip across the top.
	var strip := PanelContainer.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = color
	ss.corner_radius_top_left = 8
	ss.corner_radius_top_right = 8
	ss.content_margin_top = 6
	ss.content_margin_bottom = 6
	strip.add_theme_stylebox_override(&"panel", ss)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := _label(17, Color(0.05, 0.05, 0.07), false)
	tag.text = d["tag"]
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strip.add_child(tag)
	var strip_wrap := MarginContainer.new()
	strip_wrap.add_theme_constant_override(&"margin_left", -18)
	strip_wrap.add_theme_constant_override(&"margin_right", -18)
	strip_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_wrap.add_child(strip)
	box.add_child(strip_wrap)

	var title := _label(30, Color.WHITE)
	title.text = d["title"]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	box.add_child(_pips(d["level"], d["max"], color))
	var text := _label(20, Color(0.9, 0.9, 0.9), false)
	text.text = d["text"]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	var key := _label(20, color)
	key.text = "[ %d ]" % (i + 1)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(key)
	return b


## Level pips: filled up to the level this card gives. Repeatable cards
## (huge max) show a single "again" pip instead.
func _pips(level: int, max_level: int, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if max_level > 10:
		var l := _label(17, Color(0.75, 0.75, 0.75), false)
		l.text = "Can pick again"
		row.add_child(l)
		return row
	for i in max_level:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(26, 10)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(3)
		if i < level - 1:
			st.bg_color = color.darkened(0.25)      # already owned
		elif i == level - 1:
			st.bg_color = Color.WHITE               # what this card adds
		else:
			st.bg_color = Color(1, 1, 1, 0.12)
		p.add_theme_stylebox_override(&"panel", st)
		row.add_child(p)
	if level > 1:
		var l := _label(17, Color(0.8, 0.8, 0.8), false)
		l.text = " Lv %d" % level
		row.add_child(l)
	return row


func _card_style(color: Color, hot: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.09, 0.11, 0.96) if not hot else Color(0.15, 0.15, 0.18, 0.98)
	s.border_color = color if not hot else color.lightened(0.45)
	s.set_border_width_all(4 if not hot else 6)
	s.set_corner_radius_all(12)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 10
	if hot:
		s.shadow_color = Color(color, 0.45)
		s.shadow_size = 18
	return s


func _label(size: int, col: Color, outline: bool = true) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", col)
	if outline:
		l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override(&"outline_size", maxi(size / 6, 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
