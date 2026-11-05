class_name CombatFeedback
extends Node
## Glue between gameplay events and presentation. It's the only place that
## knows about weapon + effects + audio + HUD + camera together.
##
##   weapon.shot_fired   → turret recoil/flash, tracer, gun sound
##   weapon.shot_impact  → sparks/dust, impact sound, hit marker
##   target destroyed    → explosion/debris, sound, popup, small camera shake
##
## The weapon never touches the camera. Shake comes only from destructions.

@export var weapon: HitscanWeapon
@export var turret: MountedTurret
@export var effects: EffectsManager
@export var audio: CombatAudio
@export var hud: CombatHud
@export var camera: FollowCamera

@export_group("Camera shake")
## Trauma added per destruction, times the target's explosion_scale.
@export_range(0.0, 1.0) var shake_per_destruction: float = 0.18
## Explosions further than this from the camera don't shake.
@export var shake_max_distance: float = 120.0


func _ready() -> void:
	add_to_group(Damageable.LISTENER_GROUP)
	if weapon:
		weapon.shot_fired.connect(_on_shot_fired)
		weapon.shot_impact.connect(_on_shot_impact)


func _on_shot_fired(origin: Vector3, _dir: Vector3, end_point: Vector3, is_tracer: bool) -> void:
	if turret:
		turret.play_fire_fx()
	if audio:
		audio.play_shot()
	if effects and is_tracer:
		effects.spawn_tracer(origin, end_point)


func _on_shot_impact(point: Vector3, normal: Vector3, surface: StringName, target: Node, killed: bool) -> void:
	if effects:
		effects.spawn_impact(point, normal, surface)
	if audio:
		audio.play_impact(point, surface)
	if hud and target != null:
		hud.show_hit_marker(killed)


func on_target_destroyed(target: Node, _source: Node) -> void:
	var t := target as Damageable
	if t == null:
		return
	var origin: Vector3 = t.get_effect_origin() if t.has_method(&"get_effect_origin") else t.global_position
	var fireball := t.destroy_effect == &"explosion"
	if effects:
		effects.spawn_explosion(origin, t.explosion_scale, fireball)
	if audio:
		audio.play_explosion(origin, fireball)
	if hud:
		hud.show_popup("+%d  %s" % [t.points, t.display_name], origin + Vector3.UP * 1.5)
	if camera and fireball:
		var dist := camera.global_position.distance_to(origin)
		var k := clampf(1.0 - dist / shake_max_distance, 0.0, 1.0)
		camera.add_trauma(shake_per_destruction * t.explosion_scale * k)
