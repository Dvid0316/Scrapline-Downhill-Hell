extends SceneTree
## Headless tests for Milestone 2 (turret combat).
##
## Run:  godot --headless --path . --fixed-fps 60 -s res://tests/test_milestone2.gd
## Exit code 0 = all checks passed.
##
## These drive the real main scene. Mouse input can't be simulated headless,
## so player input (TurretInput) is switched off and the turret/weapon are
## driven through the same public calls TurretInput uses.

const PLATE := preload("res://scenes/targets/armored_plate.tscn")
const BARREL := preload("res://scenes/targets/explosive_barrel.tscn")
const CRATE := preload("res://scenes/targets/wooden_crate.tscn")

var _failures := 0
var main: Node
var train: TrainController
var turret: MountedTurret
var weapon: HitscanWeapon
var input: TurretInput
var course: TargetCourse
var score: ScoreTracker
var camera: FollowCamera
var railcar: Node3D
var loco: Node3D


func _initialize() -> void:
	_run()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	# _ready() runs on the first frame in SceneTree scripts; disable input after it.
	await process_frame
	train = main.get_node("Train")
	turret = main.get_node("Train/ArmoredRailcar/TurretMount/HeavyMGTurret")
	weapon = main.get_node("Combat/Weapon")
	input = main.get_node("Combat/TurretInput")
	course = main.get_node("TargetCourse")
	score = main.get_node("Combat/ScoreTracker")
	camera = main.get_node("FollowCamera")
	railcar = main.get_node("Train/ArmoredRailcar")
	loco = main.get_node("Train/Locomotive")
	input.set_physics_process(false)    # no mouse headless; we drive aim directly
	weapon.set_physics_process(false)   # we step the trigger manually for exact timing
	await _frames(3)

	_test_setup()
	await _test_attachment()
	await _test_camera_aim()
	_test_fire_rate()
	await _test_hitscan_damage_and_points()
	_test_no_self_hits()
	await _test_camera_unaffected_by_firing()
	await _test_barrel_aoe()
	await _test_reset_on_restart()
	_test_no_node_growth()
	_test_feedback_wiring()

	print("Milestone 2 tests: %s (%d failure%s)" % [
		"OK" if _failures == 0 else "FAILED", _failures, "" if _failures == 1 else "s"])
	main.quit_cleanly(0 if _failures == 0 else 1)  # stops audio first (no leaks at exit)


# --------------------------------------------------------------------- tests

func _test_setup() -> void:
	_check(turret != null and weapon != null and input != null, "combat nodes present")
	_check(course.targets.size() >= 30, "target course built (%d targets)" % course.targets.size())
	var lo := INF
	var hi := -INF
	for t in course.targets:
		var rel := (main.get_node("Terrain") as TerrainBuilder).track_relation(t.global_position.x, t.global_position.z)
		var dh := t.global_position.y - rel.y
		lo = minf(lo, dh)
		hi = maxf(hi, dh)
	_check(hi - lo > 10.0, "targets at varied elevations (%.1f m to %+.1f m vs track)" % [lo, hi])
	_check(InputMap.has_action(&"fire"), "fire action registered (LMB)")
	_check(is_equal_approx(weapon.fire_rate, 11.0), "default fire rate 11 rps")


## 1. Turret stays attached through curves and grades.
func _test_attachment() -> void:
	train.set_progress_ratio(0.35)
	train.target_speed = 25.0
	train.speed = 25.0
	var mount: Node3D = railcar.get_node("TurretMount")
	var start := train.head_distance
	var worst := 0.0
	var worst_up := 0.0
	for i in 90:
		await physics_frame
		worst = maxf(worst, turret.global_position.distance_to(mount.global_position))
		worst_up = maxf(worst_up, rad_to_deg(turret.global_basis.y.angle_to(railcar.global_basis.y)))
	_check(train.head_distance - start > 20.0, "train moved during attachment test (%.0f m)" % (train.head_distance - start))
	_check(worst < 0.001, "turret stays on its mount while moving (max drift %.4f m)" % worst)
	_check(worst_up < 0.01, "turret tilts with the railcar on grades (%.3f°)" % worst_up)


## 2. Aim maths with the angled-overhead camera, while the train moves.
func _test_camera_aim() -> void:
	var target := _visible_course_target()
	_check(target != null, "a course target is on screen")
	if target == null:
		return
	var centre: Vector3 = target.get_effect_origin()
	var screen := camera.unproject_position(centre)
	var p := input.screen_to_aim_point(screen)
	_check(p.distance_to(centre) < 2.6,
		"mouse ray hits the target under the cursor (%.2f m from centre)" % p.distance_to(centre))
	# Swing: the turret is heavy now, so a big swing takes a moment but settles.
	var start_aim := turret.global_position - turret.global_basis.z * -30.0
	turret.aim_at(start_aim)
	turret.snap_to_aim()
	turret.aim_at(input.screen_to_aim_point(camera.unproject_position(target.get_effect_origin())))
	var initial_err := turret.get_aim_error_degrees()
	await physics_frame
	await physics_frame
	var early_err := turret.get_aim_error_degrees()
	var frames := 0
	while frames < 120:
		await physics_frame
		frames += 1
		turret.aim_at(input.screen_to_aim_point(camera.unproject_position(target.get_effect_origin())))
		if turret.get_aim_error_degrees() < 1.0:
			break
	_check(early_err > 5.0 and frames < 120,
		"turret swings with weight, then settles (%.0f° → %.0f° after 2 frames, on target after %d frames)" % [initial_err, early_err, frames])
	# Track it while the train moves and turns: the barrel should stay on it.
	var worst := 0.0
	for i in 60:
		await physics_frame
		screen = camera.unproject_position(target.get_effect_origin())
		turret.aim_at(input.screen_to_aim_point(screen))
		if i > 20:
			worst = maxf(worst, turret.get_aim_error_degrees())
	_check(worst < 2.0, "barrel tracks the aim point while moving (max error %.2f°)" % worst)
	# Front-arc limit: can't depress into the locomotive.
	turret.aim_at(loco.global_position + Vector3.UP * 1.0)
	turret.snap_to_aim()
	var pitch := rad_to_deg((turret.get_node("Yaw/Pitch") as Node3D).rotation.x)
	_check(pitch >= turret.front_arc_min_pitch - 0.01, "turret won't depress into the locomotive (pitch %.1f°)" % pitch)


## 3–5. Fire rate, holding fires repeatedly, releasing stops.
func _test_fire_rate() -> void:
	weapon.reset_stats()
	weapon.trigger_held = true
	weapon.step(0.0)
	_check(weapon.shots_fired == 1, "first round fires immediately on trigger")
	for i in 59:
		weapon.step(1.0 / 60.0)
	_check(absi(weapon.shots_fired - 11) <= 1, "11 rps at 60 FPS (%d shots in 1 s)" % weapon.shots_fired)
	var at60 := weapon.shots_fired
	weapon.trigger_held = false
	for i in 60:
		weapon.step(1.0 / 60.0)
	_check(weapon.shots_fired == at60, "releasing the trigger stops fire")
	# Frame-rate independence: same second at 20 FPS and 144 FPS.
	for fps in [20, 144]:
		weapon.reset_stats()
		weapon.trigger_held = true
		weapon.step(0.0)
		for i in fps - 1:
			weapon.step(1.0 / fps)
		weapon.trigger_held = false
		_check(absi(weapon.shots_fired - 11) <= 1, "fire rate independent of frame rate (%d FPS → %d shots)" % [fps, weapon.shots_fired])
		for i in 30:
			weapon.step(1.0 / 60.0)


## 6, 8, 9. Hitscan reaches targets, health drops by damage, points awarded once.
func _test_hitscan_damage_and_points() -> void:
	_stop_train()
	var plate := _spawn_beside_train(PLATE, 14.0, 0.0) as DestructibleTarget
	await _frames(2)
	weapon.spread_degrees = 0.0
	turret.aim_at(plate.get_effect_origin())
	turret.snap_to_aim()
	await _frames(1)
	var hit := weapon.fire_one()
	_check(hit == plate, "hitscan hits the target in front of the barrel")
	_check(is_equal_approx(plate.health, plate.max_health - weapon.damage),
		"target loses exactly one round of damage (%.0f → %.0f)" % [plate.max_health, plate.health])
	var destroyed_count := [0]
	plate.destroyed.connect(func(_s: Node) -> void: destroyed_count[0] += 1)
	var score_before := score.score
	var guard := 0
	while not plate.is_destroyed and guard < 50:
		weapon.fire_one()
		guard += 1
	_check(plate.is_destroyed, "target destroyed after enough hits (%d rounds)" % (guard + 1))
	_check(score.score - score_before == plate.points, "destruction awards %d points" % plate.points)
	plate.apply_damage(500.0, plate.global_position)
	weapon.fire_one()
	_check(score.score - score_before == plate.points and destroyed_count[0] == 1,
		"points awarded once (extra damage after death ignored)")
	_check(weapon.fire_one() != plate, "destroyed target no longer blocks shots")


## 7. Shots never hit the train.
func _test_no_self_hits() -> void:
	var muzzle := turret.get_muzzle_transform().origin
	var aim := loco.global_position + loco.global_basis.y * 2.2
	var dir := (aim - muzzle).normalized()
	# Sanity: the hull really is in the way when the TRAIN layer is included.
	var q := PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * 300.0, 0xFFFFFFFF)
	var raw := turret.get_world_3d().direct_space_state.intersect_ray(q)
	var raw_hits_train: bool = not raw.is_empty() and (raw.collider as CollisionObject3D).collision_layer & PhysicsLayers.TRAIN != 0
	_check(raw_hits_train, "sanity: an all-layer ray toward the loco hits the train hull")
	var impacts: Array[Vector3] = []
	var cb := func(p: Vector3, _n: Vector3, _s: StringName, _t: Node, _k: bool) -> void: impacts.append(p)
	weapon.shot_impact.connect(cb)
	var target := weapon.fire_ray(muzzle, dir)
	weapon.shot_impact.disconnect(cb)
	var inside := false
	for p in impacts:
		var local := loco.global_transform.affine_inverse() * p
		if absf(local.x) < 1.6 and local.y > 0.8 and local.y < 4.4 and absf(local.z) < 8.6:
			inside = true
	_check(target == null and not inside, "player shots pass through the train (no self-hits)")


## Firing never rotates or moves the camera (shake only comes from destructions).
func _test_camera_unaffected_by_firing() -> void:
	_stop_train()
	await _frames(2)
	camera.snap()  # settle smoothing so only firing could move it
	await _frames(2)
	var basis_before := camera.global_basis
	var pos_before := camera.global_position
	turret.aim_at(train.route.sample_world(train.get_centre_distance() + 40.0))
	weapon.trigger_held = true
	for i in 45:
		weapon.step(1.0 / 60.0)
		await process_frame
	weapon.trigger_held = false
	var rot_change := rad_to_deg(basis_before.get_rotation_quaternion().angle_to(camera.global_basis.get_rotation_quaternion()))
	_check(rot_change < 0.01 and pos_before.distance_to(camera.global_position) < 0.01,
		"sustained fire leaves camera orientation unchanged (%.4f°)" % rot_change)


## 10. Explosive barrel damages nearby targets, not far ones.
func _test_barrel_aoe() -> void:
	var barrel := _spawn_beside_train(BARREL, 16.0, 30.0) as ExplosiveBarrel
	var near_crate := _spawn_beside_train(CRATE, 16.0, 33.0)
	var far_plate := _spawn_beside_train(PLATE, 16.0, 30.0 + barrel.blast_radius + 6.0)
	await _frames(1)
	var score_before := score.score
	barrel.apply_damage(999.0, barrel.global_position)
	_check(barrel.is_destroyed, "barrel destroyed")
	await create_timer(barrel.chain_delay + 0.2).timeout
	_check(near_crate.is_destroyed, "barrel blast destroys a crate 3 m away")
	_check(is_equal_approx(far_plate.health, far_plate.max_health), "target outside blast radius untouched")
	_check(score.score - score_before == barrel.points + near_crate.points, "chain kill points credited once each")


## Course targets and score reset for a new run.
func _test_reset_on_restart() -> void:
	var t: Damageable = course.targets[0]
	t.apply_damage(9999.0, t.global_position)
	_check(t.is_destroyed and score.score > 0, "course target destroyed, score > 0")
	train.restart()
	await _frames(1)
	_check(not t.is_destroyed and is_equal_approx(t.health, t.max_health), "run restart restores targets")
	_check(score.score == 0 and weapon.shots_fired == 0, "run restart resets score and stats")


## Effects are pooled: sustained fire doesn't add nodes.
func _test_no_node_growth() -> void:
	var before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	weapon.trigger_held = true
	for i in 300:
		weapon.step(1.0 / 60.0)
	weapon.trigger_held = false
	var after := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	_check(after == before, "sustained fire spawns no new nodes (%d → %d)" % [before, after])


## Shots/impacts/kills reach the audio + effects layer (sound itself can't be heard headless).
func _test_feedback_wiring() -> void:
	var audio := main.get_node("Combat/Audio") as CombatAudio
	_check(audio.requested[&"shot"] > 0, "gun sound requested per shot (%d)" % audio.requested[&"shot"])
	_check(audio.requested[&"impact"] > 0, "impact sounds requested (%d, rate-limited)" % audio.requested[&"impact"])
	_check(audio.requested[&"explosion"] > 0, "destruction sounds requested (%d)" % audio.requested[&"explosion"])
	_check(audio.requested[&"impact"] < audio.requested[&"shot"], "impact sounds are throttled below shot count")


# --------------------------------------------------------------------- helpers

func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _stop_train() -> void:
	train.target_speed = 0.0
	train.speed = 0.0


func _spawn_beside_train(scene: PackedScene, lateral: float, ahead: float) -> Damageable:
	var d := train.get_centre_distance() + ahead
	var c := train.route.sample_world(d)
	var f := train.route.tangent_world(d)
	var right := Vector3(-f.z, 0.0, f.x).normalized()
	var pos := c + right * lateral
	var terrain := main.get_node("Terrain") as TerrainBuilder
	pos.y = terrain.sample_height(pos.x, pos.z)
	var t := scene.instantiate() as Damageable
	main.add_child(t)
	t.global_position = pos
	return t


func _visible_course_target() -> DestructibleTarget:
	var vp := camera.get_viewport().get_visible_rect().size
	var best: DestructibleTarget = null
	var best_d := INF
	for ct in course.targets:
		var t := ct as DestructibleTarget
		if t == null or t.is_destroyed:
			continue
		var p: Vector3 = t.get_effect_origin()
		if camera.is_position_behind(p):
			continue
		var s := camera.unproject_position(p)
		if s.x < 50 or s.y < 50 or s.x > vp.x - 50 or s.y > vp.y - 50:
			continue
		var d := p.distance_to(turret.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)
