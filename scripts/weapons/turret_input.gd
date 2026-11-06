class_name TurretInput
extends Node
## Player control of the turret: the mouse position becomes a camera ray, then
## a 3D aim point. Holding the "fire" action pulls the trigger.
##
## The aim ray hits terrain and targets but ignores the train, so aiming
## "past" the train works. Any elevation works because the aim point is a real
## 3D hit, not a ground plane. When the ray hits nothing (sky), it aims at a
## point [member fallback_distance] along the ray.
##
## The cursor is hidden and confined while playing (the HUD draws a crosshair).
## Esc frees it; clicking back into the window re-captures it.

@export var camera: Camera3D
@export var turret: MountedTurret
@export var weapon: HitscanWeapon
@export var fallback_distance: float = 200.0
@export var confine_cursor: bool = true

## Dev/demo helpers (set from the command line, never in normal play).
var debug_auto_fire: bool = false
var debug_auto_aim: bool = false

## Screen position currently aimed at (viewport coordinates).
var aim_screen_position: Vector2
var aim_world_point: Vector3
## Where the barrel actually points right now (what a shot would hit).
## The HUD draws a second reticle here; it lags the cursor while the
## turret swings, and the two merge once the gun is on target.
var gun_world_point: Vector3
var gun_screen_position: Vector2
var gun_point_visible: bool = false

var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_query.collision_mask = PhysicsLayers.PLAYER_SHOT_MASK
	# Cursor is confined on window focus / first click, not here: grabbing the
	# pointer before the window has focus fails on Wayland ("NO GRAB").


func _physics_process(_delta: float) -> void:
	if camera == null or turret == null:
		return
	if debug_auto_aim:
		var t: Variant = _pick_demo_target()
		if t != null:
			aim_world_point = t
			aim_screen_position = camera.unproject_position(t)
			turret.aim_at(t)
	else:
		aim_screen_position = camera.get_viewport().get_mouse_position()
		aim_world_point = screen_to_aim_point(aim_screen_position)
		turret.aim_at(aim_world_point)
	_update_gun_point()
	if weapon:
		weapon.trigger_held = debug_auto_fire or Input.is_action_pressed(&"fire")


func _update_gun_point() -> void:
	var origin := turret.get_muzzle_transform().origin
	var dir := turret.get_barrel_direction()
	var reach := weapon.max_range if weapon else 320.0
	_query.from = origin
	_query.to = origin + dir * reach
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(_query)
	gun_world_point = _query.to if hit.is_empty() else hit.position
	gun_point_visible = not camera.is_position_behind(gun_world_point)
	if gun_point_visible:
		gun_screen_position = camera.unproject_position(gun_world_point)


## Viewport position → world aim point (terrain/targets; train ignored).
func screen_to_aim_point(screen_pos: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	_query.from = origin
	_query.to = origin + dir * 2000.0
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		return origin + dir * fallback_distance
	return hit.position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		_capture_cursor()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and weapon:
		weapon.trigger_held = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_capture_cursor.call_deferred()


func _capture_cursor() -> void:
	if not confine_cursor or DisplayServer.get_name() == "headless":
		return
	if not get_window().has_focus():
		return
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN


## Demo only: the nearest live target ahead of the train, for screenshots and benchmarks.
func _pick_demo_target() -> Variant:
	var best: Variant = null
	var best_d := 85.0
	var cam_fwd := -camera.global_transform.basis.z
	for n in get_tree().get_nodes_in_group(Damageable.GROUP):
		var d := n as Damageable
		if d == null or d.is_destroyed:
			continue
		var p: Vector3 = d.get_effect_origin() if d.has_method(&"get_effect_origin") else d.global_position + Vector3.UP
		var dist := p.distance_to(turret.global_position)
		if dist < best_d and (p - camera.global_position).dot(cam_fwd) > 0.0:
			best_d = dist
			best = p
	return best
