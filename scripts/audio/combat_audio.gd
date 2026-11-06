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

@export_group("Volume (dB)")
@export_range(-40.0, 12.0) var gun_volume_db: float = -5.0
@export_range(-40.0, 12.0) var impact_volume_db: float = -11.0
@export_range(-40.0, 12.0) var explosion_volume_db: float = -2.0

@export_group("Limits")
@export_range(1, 8) var gun_polyphony: int = 3
@export_range(1, 16) var impact_voices: int = 5
## Minimum seconds between impact sounds (rapid fire would otherwise spam).
@export var impact_min_interval: float = 0.07
@export_range(1, 8) var explosion_voices: int = 3

var _gun: AudioStreamPlayer
var _impacts: Array[AudioStreamPlayer3D] = []
var _impact_next := 0
var _blasts: Array[AudioStreamPlayer3D] = []
var _blast_next := 0
var _last_impact_time := -1.0
## Requests per category (for tests/debug). Counted even when muted.
var requested := {&"shot": 0, &"impact": 0, &"explosion": 0}
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
