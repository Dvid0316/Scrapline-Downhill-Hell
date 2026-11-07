class_name CombatFeedback
extends Node
## Glue between gameplay events and presentation. It's the only place that
## knows about weapon + effects + audio + HUD + camera together.
##
##   weapon.shot_fired      → turret recoil/flash, tracer, gun sound
##   weapon.shot_impact     → sparks/dust, impact sound, hit marker
##   target destroyed       → explosion/debris, sound, popup, small camera shake
##   enemy shot (M3)        → red tracer, enemy gun sound, sparks on the train
##   train hit (M3)         → HUD damage flash, tiny shake on big hits
##   kamikaze arming/blast  → warning beep / big explosion + shake
##   waves (M3)             → horn, chime, HUD banners
##   train wrecked (M3)     → a string of explosions along the train
##
## The weapon never touches the camera. Shake comes only from explosions.

@export var weapon: HitscanWeapon
@export var cannon: HitscanWeapon
@export var turret: MountedTurret
@export var effects: EffectsManager
@export var audio: CombatAudio
@export var hud: CombatHud
@export var camera: FollowCamera
@export var hull: TrainHull
@export var director: WaveDirector

@export_group("Camera shake")
## Trauma added per destruction, times the target's explosion_scale.
@export_range(0.0, 1.0) var shake_per_destruction: float = 0.18
## Explosions further than this from the camera don't shake.
@export var shake_max_distance: float = 120.0
## Trauma when a kamikaze reaches the train.
@export_range(0.0, 1.0) var shake_kamikaze_hit: float = 0.55

var _wreck_explosions_left: int = 0
var _wreck_timer: float = 0.0


func _ready() -> void:
	add_to_group(Damageable.LISTENER_GROUP)
	add_to_group(EnemyBase.FIRE_LISTENER_GROUP)
	if weapon:
		weapon.shot_fired.connect(_on_shot_fired)
		weapon.shot_impact.connect(_on_shot_impact)
	if cannon:
		cannon.shot_fired.connect(_on_cannon_fired)
		cannon.shot_impact.connect(_on_cannon_impact)
		cannon.splashed.connect(_on_cannon_splash)
	if hull:
		hull.hit_taken.connect(_on_hull_hit)
		hull.wrecked.connect(_on_train_wrecked)
	if director:
		director.wave_started.connect(_on_wave_started)
		director.wave_cleared.connect(_on_wave_cleared)
	set_process(false)


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
	if fireball:
		_shake_at(origin, shake_per_destruction * t.explosion_scale)


# ------------------------------------------------------------------ cannon (M4)

func _on_cannon_fired(origin: Vector3, _dir: Vector3, end_point: Vector3, _is_tracer: bool) -> void:
	if turret:
		turret.play_fire_fx(&"cannon")
	if audio:
		audio.play_cannon()
	if effects:
		effects.spawn_tracer(origin, end_point, false, true)


func _on_cannon_impact(_point: Vector3, _normal: Vector3, _surface: StringName, target: Node, killed: bool) -> void:
	if hud and target != null:
		hud.show_hit_marker(killed)


## Every shell bursts where it lands (the splash damage itself is in HitscanWeapon).
func _on_cannon_splash(point: Vector3, radius: float) -> void:
	if effects:
		effects.spawn_explosion(point, radius / 5.0, true)
	if audio:
		audio.play_explosion(point, true)


# ------------------------------------------------------------------ enemies (M3)

func on_enemy_shot(_enemy: Node, origin: Vector3, end_point: Vector3, normal: Vector3, hit_train: bool, is_tracer: bool) -> void:
	if effects:
		if is_tracer:
			effects.spawn_tracer(origin, end_point, true)
		if hit_train:
			effects.spawn_impact(end_point, normal, &"metal")
	if audio:
		audio.play_enemy_shot(origin)
		if hit_train:
			audio.play_impact(end_point, &"metal")


func on_enemy_warning(enemy: Node) -> void:
	if audio:
		audio.play_warning((enemy as Node3D).global_position)


func on_enemy_detonated(_enemy: Node, point: Vector3) -> void:
	if effects:
		effects.spawn_explosion(point, 1.7, true)
	if audio:
		audio.play_explosion(point, true)
	if camera:
		camera.add_trauma(shake_kamikaze_hit)


func _on_hull_hit(amount: float, _point: Vector3) -> void:
	if hud:
		hud.flash_damage(amount)


func _on_wave_started(wave: int, count: int) -> void:
	if audio:
		audio.play_cue(&"wave_start")
	if hud and director:
		hud.show_banner("WAVE %d" % wave, "%s  ·  %d hostiles" % [director.wave_name, count])


func _on_wave_cleared(wave: int) -> void:
	if audio:
		audio.play_cue(&"wave_clear")
	if hud:
		var sub := "Hull patched +%d%%" % int(round(director.repair_per_wave * 100.0)) if director and director.repair_per_wave > 0.0 else ""
		hud.show_banner("WAVE %d CLEARED" % wave, sub)


## Game over: a ripple of explosions along the train.
func _on_train_wrecked() -> void:
	_wreck_explosions_left = 6
	_wreck_timer = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_wreck_timer -= delta
	if _wreck_timer > 0.0:
		return
	_wreck_timer = 0.28
	_wreck_explosions_left -= 1
	if hull and effects:
		var p := hull.get_aim_point()
		effects.spawn_explosion(p, 1.8, true)
		if audio:
			audio.play_explosion(p, true)
		if camera:
			camera.add_trauma(0.35)
	if _wreck_explosions_left <= 0:
		set_process(false)


func reset() -> void:
	_wreck_explosions_left = 0
	set_process(false)


func _shake_at(origin: Vector3, amount: float) -> void:
	if camera == null:
		return
	var dist := camera.global_position.distance_to(origin)
	var k := clampf(1.0 - dist / shake_max_distance, 0.0, 1.0)
	camera.add_trauma(amount * k)
