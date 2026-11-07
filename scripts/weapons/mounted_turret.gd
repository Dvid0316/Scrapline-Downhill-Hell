class_name MountedTurret
extends Node3D
## Heavy MG turret: rotating base (Yaw), elevating gun (Pitch), recoiling
## barrel assembly (Recoil), and muzzle (Muzzle + MuzzleFlash).
## A heavy cannon rides on the same elevating mount (CannonRecoil,
## CannonMuzzle, CannonFlash), so both guns aim together. Weapons pick
## which barrel they fire from by slot: &"mg" or &"cannon".
##
## The turret only aims and animates. It doesn't fire. Give it a world-space
## [member aim_point] and it slews toward it at the configured speeds. Because
## it's parented to the railcar, it stays attached as the train moves.
##
## "Don't aim through the train": over the front arc (where the locomotive
## sits), depression is limited to [member front_arc_min_pitch]. Player
## shots also ignore the TRAIN physics layer completely.

@export_group("Traverse")
## Top traverse speeds. The turret accelerates up to these and eases in as it
## nears the aim point, so it feels like a heavy gun being swung, not a cursor.
@export_range(10.0, 1080.0) var yaw_speed_degrees: float = 160.0
@export_range(10.0, 720.0) var pitch_speed_degrees: float = 90.0
## How quickly the turret gets up to speed (degrees/s²). Lower = heavier.
@export_range(50.0, 5000.0) var yaw_accel_degrees: float = 900.0
@export_range(50.0, 5000.0) var pitch_accel_degrees: float = 700.0
## Easing near the target: wanted speed = remaining angle × this (1/s).
## Higher = snappier stop, lower = softer settle.
@export_range(1.0, 40.0) var settle_rate: float = 9.0
@export_range(-45.0, 0.0) var min_pitch: float = -22.0
@export_range(0.0, 85.0) var max_pitch: float = 60.0
## Half-angle of the forward cone where the locomotive blocks low shots.
@export_range(0.0, 90.0) var front_arc_degrees: float = 28.0
@export_range(-20.0, 10.0) var front_arc_min_pitch: float = -2.0

@export_group("Feel")
@export var recoil_distance: float = 0.12
@export var recoil_return_speed: float = 18.0
@export var flash_duration: float = 0.045
@export var flash_light_energy: float = 6.0
@export var cannon_recoil_distance: float = 0.45
@export var cannon_recoil_return_speed: float = 3.5
@export var cannon_flash_duration: float = 0.08
@export var cannon_flash_light_energy: float = 14.0

var aim_point: Vector3
var has_aim: bool = false

@onready var _yaw: Node3D = $Yaw
@onready var _pitch: Node3D = $Yaw/Pitch
@onready var _recoil: Node3D = $Yaw/Pitch/Recoil
@onready var _muzzle: Marker3D = $Yaw/Pitch/Recoil/Muzzle
@onready var _flash: Node3D = $Yaw/Pitch/Recoil/MuzzleFlash
@onready var _flash_light: OmniLight3D = $Yaw/Pitch/Recoil/MuzzleFlash/FlashLight
@onready var _c_recoil: Node3D = get_node_or_null(^"Yaw/Pitch/CannonRecoil")
@onready var _c_muzzle: Marker3D = get_node_or_null(^"Yaw/Pitch/CannonRecoil/CannonMuzzle")
@onready var _c_flash: Node3D = get_node_or_null(^"Yaw/Pitch/CannonRecoil/CannonFlash")
@onready var _c_flash_light: OmniLight3D = get_node_or_null(^"Yaw/Pitch/CannonRecoil/CannonFlash/FlashLight")
var _c_flash_left: float = 0.0

var _yaw_vel: float = 0.0
var _pitch_vel: float = 0.0
## Previous goal angles, to estimate how fast the aim point is moving
## (feed-forward: steady tracking doesn't lag behind, big swings still ease).
var _last_goal: Vector2
var _has_last_goal := false
var _flash_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_flash.visible = false
	_flash_light.light_energy = 0.0
	if _c_flash:
		_c_flash.visible = false
		_c_flash_light.light_energy = 0.0


func aim_at(world_point: Vector3) -> void:
	aim_point = world_point
	has_aim = true


func _process(delta: float) -> void:
	if has_aim:
		var goal := _desired_angles(aim_point)
		var goal_rate := Vector2.ZERO
		if _has_last_goal and delta > 0.0:
			goal_rate = Vector2(wrapf(goal.x - _last_goal.x, -PI, PI), goal.y - _last_goal.y) / delta
		_last_goal = goal
		_has_last_goal = true
		var yaw_diff := wrapf(goal.x - _yaw.rotation.y, -PI, PI)
		_yaw_vel = _drive(_yaw_vel, yaw_diff, goal_rate.x, yaw_speed_degrees, yaw_accel_degrees, delta)
		_yaw.rotation.y = wrapf(_yaw.rotation.y + _yaw_vel * delta, -PI, PI)
		var pitch_diff := goal.y - _pitch.rotation.x
		_pitch_vel = _drive(_pitch_vel, pitch_diff, goal_rate.y, pitch_speed_degrees, pitch_accel_degrees, delta)
		_pitch.rotation.x += _pitch_vel * delta
	# Recoil spring back.
	_recoil.position.z = move_toward(_recoil.position.z, 0.0, recoil_return_speed * recoil_distance * delta * 4.0)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.visible = false
			_flash_light.light_energy = 0.0
	if _c_recoil:
		_c_recoil.position.z = move_toward(_c_recoil.position.z, 0.0, cannon_recoil_return_speed * cannon_recoil_distance * delta)
	if _c_flash_left > 0.0:
		_c_flash_left -= delta
		if _c_flash_left <= 0.0:
			_c_flash.visible = false
			_c_flash_light.light_energy = 0.0


## Instantly face the current aim point (tests, respawn).
func snap_to_aim() -> void:
	if not has_aim:
		return
	var goal := _desired_angles(aim_point)
	_yaw.rotation.y = goal.x
	_pitch.rotation.x = goal.y
	_yaw_vel = 0.0
	_pitch_vel = 0.0
	_last_goal = goal
	_has_last_goal = true


## (yaw, pitch) in radians needed to point the barrel at [param world_point],
## after limits are applied.
func _desired_angles(world_point: Vector3) -> Vector2:
	var local := global_transform.affine_inverse() * world_point
	var yaw := atan2(-local.x, -local.z)
	# Pitch measured from the elevation pivot.
	var pivot := _pitch.position
	var horizontal := Vector2(local.x, local.z).length() - absf(pivot.z)
	var pitch := atan2(local.y - pivot.y, maxf(horizontal, 0.1))
	var lo := deg_to_rad(min_pitch)
	if absf(yaw) < deg_to_rad(front_arc_degrees):
		lo = maxf(lo, deg_to_rad(front_arc_min_pitch))
	pitch = clampf(pitch, lo, deg_to_rad(max_pitch))
	return Vector2(yaw, pitch)


## One axis of traverse. Wanted speed = how fast the goal is moving
## (feed-forward) + remaining × settle_rate (eases in), capped at max speed.
## The actual speed can only change by accel × delta per frame, which is the
## "weight". Goal rate is clamped so a sudden mouse flick doesn't count as
## steady motion.
func _drive(vel: float, remaining: float, goal_rate: float, max_deg: float, accel_deg: float, delta: float) -> float:
	var max_rad := deg_to_rad(max_deg)
	var ff := clampf(goal_rate, -max_rad * 0.75, max_rad * 0.75)
	var want := clampf(ff + remaining * settle_rate, -max_rad, max_rad)
	return move_toward(vel, want, deg_to_rad(accel_deg) * delta)


func get_muzzle_transform(slot: StringName = &"mg") -> Transform3D:
	return _muzzle_for(slot).global_transform


## World direction the barrel is actually pointing (shots go this way).
func get_barrel_direction(slot: StringName = &"mg") -> Vector3:
	return -_muzzle_for(slot).global_transform.basis.z.normalized()


func has_cannon() -> bool:
	return _c_muzzle != null


func _muzzle_for(slot: StringName) -> Marker3D:
	return _c_muzzle if slot == &"cannon" and _c_muzzle else _muzzle


## Angle (degrees) between where the barrel points and the aim point.
func get_aim_error_degrees() -> float:
	if not has_aim:
		return 180.0
	var to_aim := (aim_point - _muzzle.global_position).normalized()
	return rad_to_deg(get_barrel_direction().angle_to(to_aim))


## Visual reaction to one shot: muzzle flash + barrel kick.
func play_fire_fx(slot: StringName = &"mg") -> void:
	if slot == &"cannon" and _c_recoil:
		_c_recoil.position.z = cannon_recoil_distance
		_c_flash.visible = true
		_c_flash.rotation.z = _rng.randf() * TAU
		var cs := _rng.randf_range(0.9, 1.2)
		_c_flash.scale = Vector3(cs, cs, cs)
		_c_flash_light.light_energy = cannon_flash_light_energy
		_c_flash_left = cannon_flash_duration
		return
	_recoil.position.z = recoil_distance
	_flash.visible = true
	_flash.rotation.z = _rng.randf() * TAU
	var s := _rng.randf_range(0.8, 1.25)
	_flash.scale = Vector3(s, s, _rng.randf_range(0.8, 1.4))
	_flash_light.light_energy = flash_light_energy
	_flash_left = flash_duration
