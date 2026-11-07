class_name FollowCamera
extends Camera3D
## Angled-overhead chase camera for the train.
##
## The camera aims at a "focus" point placed [member look_ahead] metres ahead
## of the train's centre ON THE TRACK, so the upcoming track stays in view.
## It sits behind and above that focus at [member distance] metres along a
## line tilted down by [member pitch_degrees]. Yaw follows the track heading
## (sampled ahead, so curves are anticipated) with its own smoothing.
##
## Derived: camera height above focus = distance × sin(pitch).
## No shake is applied anywhere.

@export var train: TrainController

@export_group("Framing")
## Downward tilt in degrees. Locked design: 45–60.
@export_range(30.0, 75.0, 0.5) var pitch_degrees: float = 48.0
## Metres from focus point to camera.
@export_range(10.0, 120.0, 0.5) var distance: float = 50.0
## Metres ahead of the train centre to aim at (shows more upcoming track).
@export_range(0.0, 60.0, 0.5) var look_ahead: float = 4.0
## Aim this high above the track (train body ~2.5 m).
@export var aim_height: float = 2.0
## Rotate the view around the train. 0 = directly behind.
@export_range(-180.0, 180.0) var yaw_offset_degrees: float = 0.0
## How far ahead to sample the track for heading. Larger = earlier turn-in.
@export_range(1.0, 80.0) var heading_sample_distance: float = 30.0

@export_group("Smoothing")
## Higher = tighter follow. 0 disables smoothing (rigid).
@export_range(0.0, 20.0) var position_smoothing: float = 5.0
@export_range(0.0, 20.0) var yaw_smoothing: float = 2.0

@export_group("Shake")
## Master switch / strength for impact shake (explosions only; never from firing).
@export var shake_enabled: bool = true
## Maximum lens offset in metres at full trauma. Keep small.
@export_range(0.0, 3.0) var max_shake_offset: float = 0.45
## Trauma lost per second.
@export_range(0.1, 10.0) var shake_decay: float = 2.2

@export_group("Limits")
@export var min_pitch: float = 45.0
@export var max_pitch: float = 60.0
@export var min_distance: float = 18.0
@export var max_distance: float = 90.0

var _focus: Vector3
var _yaw: float = 0.0
var _initialised := false
var _defaults := {}
var _trauma: float = 0.0
var _shake_time: float = 0.0


func _ready() -> void:
	process_priority = 10
	add_to_group(&"camera_shake")
	_defaults = {
		"pitch_degrees": pitch_degrees, "distance": distance,
		"look_ahead": look_ahead, "yaw_offset_degrees": yaw_offset_degrees,
	}
	if train == null:
		push_error("FollowCamera: no train assigned")
		return
	train.run_restarted.connect(snap)
	train.route_looped.connect(snap)
	snap()


## Jump straight to the target framing (used on start and restart).
func snap() -> void:
	if train == null or train.route == null:
		return
	_focus = _target_focus()
	_yaw = _target_yaw()
	_initialised = true
	_apply()


func _process(delta: float) -> void:
	# process_priority is raised in _ready so this runs after the train moves.
	if train == null or not _initialised:
		return
	var pk := _smooth_factor(position_smoothing, delta)
	var yk := _smooth_factor(yaw_smoothing, delta)
	_focus = _focus.lerp(_target_focus(), pk)
	_yaw = lerp_angle(_yaw, _target_yaw(), yk)
	_apply()
	_update_shake(delta)


## Add screen shake (0..1). Shake moves the lens sideways via h/v_offset, so
## framing, follow target and aim maths are unaffected.
func add_trauma(amount: float) -> void:
	if shake_enabled:
		_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _update_shake(delta: float) -> void:
	if _trauma <= 0.0:
		h_offset = 0.0
		v_offset = 0.0
		return
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)
	_shake_time += delta * 30.0
	var k := _trauma * _trauma * max_shake_offset
	h_offset = sin(_shake_time * 1.7) * cos(_shake_time * 0.9) * k
	v_offset = sin(_shake_time * 2.3 + 1.3) * k


func _smooth_factor(rate: float, delta: float) -> float:
	# Frame-rate independent exponential smoothing.
	return 1.0 if rate <= 0.0 else 1.0 - exp(-rate * delta)


func _target_focus() -> Vector3:
	var d := train.get_centre_distance() + look_ahead
	return train.route.sample_world(d) + Vector3.UP * aim_height


func _target_yaw() -> float:
	var c := train.get_centre_distance()
	var a := train.route.sample_world(c)
	var b := train.route.sample_world(c + heading_sample_distance)
	var dir := b - a
	return atan2(-dir.x, -dir.z) + deg_to_rad(yaw_offset_degrees)


func _apply() -> void:
	pitch_degrees = clampf(pitch_degrees, min_pitch, max_pitch)
	distance = clampf(distance, min_distance, max_distance)
	var pitch := deg_to_rad(pitch_degrees)
	# Behind = local +Z in heading space; up by sin(pitch).
	var local_offset := Vector3(0.0, sin(pitch), cos(pitch)) * distance
	var offset := Basis(Vector3.UP, _yaw) * local_offset
	global_position = _focus + offset
	look_at(_focus, Vector3.UP)


func get_height() -> float:
	return distance * sin(deg_to_rad(pitch_degrees))


## Restore the framing values the scene started with.
func reset_framing() -> void:
	for key in _defaults:
		set(key, _defaults[key])
	snap()
