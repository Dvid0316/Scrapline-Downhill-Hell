class_name CombatAudio
extends Node3D
## Combat sound playback with capped overlap.
##
## Volume: each category plays on its own bus (Weapons / Impacts / Explosions,
## see default_bus_layout.tres and the Audio panel in the editor), and also
## has a per-sound volume export here.
##
## Overlap control:
##  - the gun is one non-positional player with limited polyphony and slight
##    random pitch, so 11 rounds per second never stack into a wall of noise
##  - impacts use a small round-robin pool of 3D players plus a minimum
##    interval between impact sounds

@export_group("Streams")
@export var gun_stream: AudioStream = preload("res://audio/sfx/mg_shot.wav")
@export var metal_impact_stream: AudioStream = preload("res://audio/sfx/impact_metal.wav")
@export var dirt_impact_stream: AudioStream = preload("res://audio/sfx/impact_dirt.wav")
@export var wood_impact_stream: AudioStream = preload("res://audio/sfx/impact_wood.wav")
@export var explosion_stream: AudioStream = preload("res://audio/sfx/explosion.wav")
@export var break_stream: AudioStream = preload("res://audio/sfx/crate_break.wav")
@export var cannon_stream: AudioStream = preload("res://audio/sfx/cannon_shot.wav")
@export var enemy_gun_stream: AudioStream = preload("res://audio/sfx/enemy_shot.wav")
@export var wave_horn_stream: AudioStream = preload("res://audio/sfx/wave_horn.wav")
@export var wave_clear_stream: AudioStream = preload("res://audio/sfx/wave_clear.wav")
@export var warning_stream: AudioStream = preload("res://audio/sfx/kamikaze_beep.wav")
@export var zap_stream: AudioStream = preload("res://audio/sfx/tesla_zap.wav")
@export var rocket_stream: AudioStream = preload("res://audio/sfx/rocket_launch.wav")
@export var upgrade_stream: AudioStream = preload("res://audio/sfx/upgrade_pick.wav")

@export_group("Volume (dB)")
@export_range(-40.0, 12.0) var gun_volume_db: float = -5.0
@export_range(-40.0, 12.0) var impact_volume_db: float = -11.0
@export_range(-40.0, 12.0) var explosion_volume_db: float = -2.0
@export_range(-40.0, 12.0) var enemy_gun_volume_db: float = -8.0
@export_range(-40.0, 12.0) var cannon_volume_db: float = -3.0
@export_range(-40.0, 12.0) var cue_volume_db: float = -6.0

@export_group("Limits")
@export_range(1, 8) var gun_polyphony: int = 3
@export_range(1, 16) var impact_voices: int = 5
## Minimum seconds between impact sounds (rapid fire would otherwise spam).
@export var impact_min_interval: float = 0.07
@export_range(1, 8) var explosion_voices: int = 4
@export_range(1, 12) var enemy_gun_voices: int = 4
## Minimum seconds between enemy gunshots (several enemies firing at once).
@export var enemy_gun_min_interval: float = 0.035

var _gun: AudioStreamPlayer
var _impacts: Array[AudioStreamPlayer3D] = []
var _impact_next := 0
var _blasts: Array[AudioStreamPlayer3D] = []
var _blast_next := 0
var _last_impact_time := -1.0
var _enemy_guns: Array[AudioStreamPlayer3D] = []
var _enemy_gun_next := 0
var _last_enemy_gun_time := -1.0
var _cue: AudioStreamPlayer
var _cannon: AudioStreamPlayer
var _warning: AudioStreamPlayer3D
var _zap: AudioStreamPlayer3D
var _rockets: Array[AudioStreamPlayer3D] = []
var _rocket_next := 0
## Requests per category (for tests/debug). Counted even when muted.
var requested := {&"shot": 0, &"impact": 0, &"explosion": 0, &"enemy_shot": 0, &"cue": 0, &"warning": 0, &"cannon": 0, &"zap": 0, &"rocket": 0}
## Headless runs (CI/tests) have a dummy audio driver that never mixes, so
## playbacks would pile up unreleased. Count the requests but don't play.
var _silent := false
var _metal: AudioStreamRandomizer
var _dirt: AudioStreamRandomizer
var _wood: AudioStreamRandomizer


func _ready() -> void:
	add_to_group(&"audio_shutdown")
	_silent = DisplayServer.get_name() == "headless"
	_gun = AudioStreamPlayer.new()
	_gun.name = "Gun"
	_gun.stream = _randomized(gun_stream, 1.07, 1.5)
	_gun.max_polyphony = gun_polyphony
	_gun.volume_db = gun_volume_db
	_gun.bus = _bus_or_master(&"Weapons")
	add_child(_gun)
	_metal = _randomized(metal_impact_stream, 1.2, 3.0)
	_dirt = _randomized(dirt_impact_stream, 1.12, 2.0)
	_wood = _randomized(wood_impact_stream, 1.12, 2.0)
	for i in impact_voices:
		_impacts.append(_make_3d("Impact%d" % i, &"Impacts", impact_volume_db, 25.0))
	for i in explosion_voices:
		_blasts.append(_make_3d("Blast%d" % i, &"Explosions", explosion_volume_db, 60.0))
	var enemy_gun := _randomized(enemy_gun_stream, 1.12, 2.0)
	for i in enemy_gun_voices:
		var p := _make_3d("EnemyGun%d" % i, &"Weapons", enemy_gun_volume_db, 30.0)
		p.stream = enemy_gun
		_enemy_guns.append(p)
	_cannon = AudioStreamPlayer.new()
	_cannon.name = "Cannon"
	_cannon.stream = _randomized(cannon_stream, 1.06, 1.5)
	_cannon.max_polyphony = 2
	_cannon.volume_db = cannon_volume_db
	_cannon.bus = _bus_or_master(&"Weapons")
	add_child(_cannon)
	_cue = AudioStreamPlayer.new()
	_cue.name = "Cue"
	_cue.volume_db = cue_volume_db
	_cue.max_polyphony = 2
	add_child(_cue)
	_warning = _make_3d("Warning", &"Weapons", cue_volume_db, 40.0)
	_warning.stream = warning_stream
	_zap = _make_3d("Zap", &"Weapons", cue_volume_db, 40.0)
	_zap.stream = _randomized(zap_stream, 1.15, 2.0)
	_zap.max_polyphony = 2
	for i in 2:
		var r := _make_3d("Rocket%d" % i, &"Weapons", cannon_volume_db - 2.0, 40.0)
		r.stream = _randomized(rocket_stream, 1.1, 1.5)
		_rockets.append(r)


## Stop everything on shutdown/scene change so no playbacks outlive the scene
## (otherwise Godot reports leaked AudioStreamPlayback objects at exit).
func _exit_tree() -> void:
	stop_all()


func stop_all() -> void:
	if _gun:
		_gun.stop()
	for p in _impacts:
		p.stop()
	for p in _blasts:
		p.stop()
	for p in _enemy_guns:
		p.stop()
	if _cue:
		_cue.stop()
	if _cannon:
		_cannon.stop()
	if _warning:
		_warning.stop()
	if _zap:
		_zap.stop()
	for p in _rockets:
		p.stop()


func play_shot() -> void:
	requested[&"shot"] += 1
	if _silent:
		return
	_gun.volume_db = gun_volume_db
	_gun.play()


func play_impact(point: Vector3, surface: StringName) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_impact_time < impact_min_interval:
		return
	_last_impact_time = now
	requested[&"impact"] += 1
	if _silent:
		return
	var p := _impacts[_impact_next]
	_impact_next = (_impact_next + 1) % _impacts.size()
	match surface:
		&"metal":
			p.stream = _metal
		&"wood":
			p.stream = _wood
		_:
			p.stream = _dirt
	p.volume_db = impact_volume_db
	p.global_position = point
	p.play()


func play_explosion(point: Vector3, big: bool = true) -> void:
	requested[&"explosion"] += 1
	if _silent:
		return
	var p := _blasts[_blast_next]
	_blast_next = (_blast_next + 1) % _blasts.size()
	p.stream = explosion_stream if big else break_stream
	p.volume_db = explosion_volume_db
	p.pitch_scale = randf_range(0.9, 1.08)
	p.global_position = point
	p.play()


func play_cannon() -> void:
	requested[&"cannon"] += 1
	if _silent:
		return
	_cannon.volume_db = cannon_volume_db
	_cannon.play()


## Enemy gunfire, positional and rate-limited.
func play_enemy_shot(point: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_enemy_gun_time < enemy_gun_min_interval:
		return
	_last_enemy_gun_time = now
	requested[&"enemy_shot"] += 1
	if _silent:
		return
	var p := _enemy_guns[_enemy_gun_next]
	_enemy_gun_next = (_enemy_gun_next + 1) % _enemy_guns.size()
	p.volume_db = enemy_gun_volume_db
	p.global_position = point
	p.play()


## Non-positional cue: &"wave_start", &"wave_clear" or &"upgrade".
func play_cue(cue: StringName) -> void:
	requested[&"cue"] += 1
	if _silent:
		return
	match cue:
		&"wave_start": _cue.stream = wave_horn_stream
		&"upgrade": _cue.stream = upgrade_stream
		_: _cue.stream = wave_clear_stream
	_cue.volume_db = cue_volume_db
	_cue.play()


## Tesla coil arc.
func play_zap(point: Vector3) -> void:
	requested[&"zap"] += 1
	if _silent:
		return
	_zap.global_position = point
	_zap.play()


## Rocket pod launch.
func play_rocket(point: Vector3) -> void:
	requested[&"rocket"] += 1
	if _silent:
		return
	var p := _rockets[_rocket_next]
	_rocket_next = (_rocket_next + 1) % _rockets.size()
	p.global_position = point
	p.play()


## Kamikaze arming beep at its position.
func play_warning(point: Vector3) -> void:
	requested[&"warning"] += 1
	if _silent:
		return
	_warning.global_position = point
	_warning.play()


func _make_3d(n: String, bus: StringName, vol: float, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = n
	p.top_level = true
	p.unit_size = unit
	p.max_distance = 400.0
	p.volume_db = vol
	p.bus = _bus_or_master(bus)
	add_child(p)
	return p


func _randomized(stream: AudioStream, pitch: float, vol: float) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	r.add_stream(-1, stream)
	r.random_pitch = pitch
	r.random_volume_offset_db = vol
	return r


func _bus_or_master(bus: StringName) -> StringName:
	return bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"
