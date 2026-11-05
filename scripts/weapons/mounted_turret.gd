class_name MountedTurret
extends Node3D
## Heavy MG turret: rotating base (Yaw), elevating gun (Pitch), recoiling
## barrel assembly (Recoil), and muzzle (Muzzle + MuzzleFlash).
##
## The turret only aims and animates. It doesn't fire. Give it a world-space
## [member aim_point] and it slews toward it at the configured speeds. Because
## it's parented to the railcar, it stays attached as the train moves.
##
## "Don't aim through the train": over the front arc (where the locomotive
## sits), depression is limited to [member front_arc_min_pitch]. Player
## shots also ignore the TRAIN physics layer completely.

@export_group("Traverse")
@export_range(10.0, 1080.0) var yaw_speed_degrees: float = 300.0
@export_range(10.0, 720.0) var pitch_speed_degrees: float = 160.0
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

var aim_point: Vector3
var has_aim: bool = false

@onready var _yaw: Node3D = $Yaw
@onready var _pitch: Node3D = $Yaw/Pitch
@onready var _recoil: Node3D = $Yaw/Pitch/Recoil
@onready var _muzzle: Marker3D = $Yaw/Pitch/Recoil/Muzzle
@onready var _flash: Node3D = $Yaw/Pitch/Recoil/MuzzleFlash
@onready var _flash_light: OmniLight3D = $Yaw/Pitch/Recoil/MuzzleFlash/FlashLight

var _flash_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_flash.visible = false
	_flash_light.light_energy = 0.0


func aim_at(world_point: Vector3) -> void:
	aim_point = world_point
	has_aim = true


func _process(delta: float) -> void:
	if has_aim:
		var goal := _desired_angles(aim_point)
		_yaw.rotation.y = _rotate_toward_angle(_yaw.rotation.y, goal.x, deg_to_rad(yaw_speed_degrees) * delta)
		_pitch.rotation.x = move_toward(_pitch.rotation.x, goal.y, deg_to_rad(pitch_speed_degrees) * delta)
	# Recoil spring back.
	_recoil.position.z = move_toward(_recoil.position.z, 0.0, recoil_return_speed * recoil_distance * delta * 4.0)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.visible = false
			_flash_light.light_energy = 0.0


## Instantly face the current aim point (tests, respawn).
func snap_to_aim() -> void:
	if not has_aim:
		return
	var goal := _desired_angles(aim_point)
	_yaw.rotation.y = goal.x
	_pitch.rotation.x = goal.y


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


func _rotate_toward_angle(from: float, to: float, max_step: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	return from + clampf(diff, -max_step, max_step)


func get_muzzle_transform() -> Transform3D:
	return _muzzle.global_transform


## World direction the barrel is actually pointing (shots go this way).
func get_barrel_direction() -> Vector3:
	return -_muzzle.global_transform.basis.z.normalized()


## Angle (degrees) between where the barrel points and the aim point.
func get_aim_error_degrees() -> float:
	if not has_aim:
		return 180.0
	var to_aim := (aim_point - _muzzle.global_position).normalized()
	return rad_to_deg(get_barrel_direction().angle_to(to_aim))


## Visual reaction to one shot: muzzle flash + barrel kick.
func play_fire_fx() -> void:
	_recoil.position.z = recoil_distance
	_flash.visible = true
	_flash.rotation.z = _rng.randf() * TAU
	var s := _rng.randf_range(0.8, 1.25)
	_flash.scale = Vector3(s, s, _rng.randf_range(0.8, 1.4))
	_flash_light.light_energy = flash_light_energy
	_flash_left = flash_duration
