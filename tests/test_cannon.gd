extends SceneTree
## Headless tests for the heavy cannon (right mouse button).
##
## Run:  godot --headless --path . --fixed-fps 60 -s res://tests/test_cannon.gd
## Exit code 0 = all checks passed.

const PLATE := preload("res://scenes/targets/armored_plate.tscn")
const CRATE := preload("res://scenes/targets/wooden_crate.tscn")

var _failures := 0
var main: Node
var train: TrainController
var turret: MountedTurret
var mg: HitscanWeapon
var cannon: HitscanWeapon
var input: TurretInput
var score: ScoreTracker
var hull: TrainHull
var director: WaveDirector
var audio: CombatAudio
var camera: FollowCamera


func _initialize() -> void:
	_run()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	train = main.get_node("Train")
	turret = main.get_node("Train/ArmoredRailcar/TurretMount/HeavyMGTurret")
	mg = main.get_node("Combat/Weapon")
	cannon = main.get_node("Combat/Cannon")
	input = main.get_node("Combat/TurretInput")
	score = main.get_node("Combat/ScoreTracker")
	hull = main.get_node("Combat/TrainHull")
	director = main.get_node("Combat/WaveDirector")
	audio = main.get_node("Combat/Audio")
	camera = main.get_node("FollowCamera")
	director.set_enabled(false)
	input.set_physics_process(false)
	mg.set_physics_process(false)
	cannon.set_physics_process(false)
	train.set_head_distance(316.0)  # absolute, so route changes don't move the test
	train.target_speed = 0.0
	train.speed = 0.0
	await _frames(3)

	_test_setup()
	_test_fire_rate()
	await _test_fires_from_cannon_barrel()
	await _test_direct_and_splash_damage()
	await _test_splash_chains_drones()
	await _test_no_self_damage()
	await _test_feedback_and_camera()
	_test_independent_of_mg()
	await _test_no_node_growth()

	print("Cannon tests: %s (%d failure%s)" % [
		"OK" if _failures == 0 else "FAILED", _failures, "" if _failures == 1 else "s"])
	main.quit_cleanly(0 if _failures == 0 else 1)


func _test_setup() -> void:
	_check(cannon != null and cannon.muzzle_slot == &"cannon" and turret.has_cannon(), "cannon mounted on the turret")
	_check(InputMap.has_action(&"fire_cannon"), "fire_cannon action registered (RMB)")
	var rmb := false
	for ev in InputMap.action_get_events(&"fire_cannon"):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			rmb = true
	_check(rmb, "right mouse button fires the cannon")
	_check(cannon.fire_rate < mg.fire_rate and cannon.damage > mg.damage * 3.0,
		"cannon is slower and much harder-hitting (%.1f rps × %.0f vs %.0f rps × %.0f)" % [cannon.fire_rate, cannon.damage, mg.fire_rate, mg.damage])


func _test_fire_rate() -> void:
	cannon.reset_stats()
	cannon.trigger_held = true
	cannon.step(0.0)
	_check(cannon.shots_fired == 1, "first shell fires immediately")
	_check(cannon.get_ready_ratio() < 0.05, "reload indicator empties after a shot (%.2f)" % cannon.get_ready_ratio())
	for i in 119:
		cannon.step(1.0 / 60.0)
	_check(absi(cannon.shots_fired - 4) <= 1, "about %.0f shells per second (%d in 2 s)" % [cannon.fire_rate, cannon.shots_fired])
	cannon.trigger_held = false
	for i in 60:
		cannon.step(1.0 / 60.0)
	_check(is_equal_approx(cannon.get_ready_ratio(), 1.0), "reload indicator full when loaded")
	cannon.reset_stats()


func _test_fires_from_cannon_barrel() -> void:
	var origins: Array[Vector3] = []
	var cb := func(o: Vector3, _d: Vector3, _e: Vector3, _t: bool) -> void: origins.append(o)
	cannon.shot_fired.connect(cb)
	cannon.fire_one()
	cannon.shot_fired.disconnect(cb)
	var cm := turret.get_muzzle_transform(&"cannon").origin
	var mm := turret.get_muzzle_transform(&"mg").origin
	_check(origins.size() == 1 and origins[0].distance_to(cm) < 0.01 and cm.distance_to(mm) > 0.3,
		"shells leave from the cannon barrel, not the MG")
	var a := turret.get_barrel_direction(&"cannon")
	var b := turret.get_barrel_direction(&"mg")
	_check(rad_to_deg(a.angle_to(b)) < 0.5, "cannon and MG point the same way (one turret)")
	cannon.reset_stats()


func _test_direct_and_splash_damage() -> void:
	var plate := _spawn_beside(PLATE, 16.0, 0.0) as DestructibleTarget
	var near := _spawn_beside(CRATE, 16.0, 2.5) as DestructibleTarget
	near.max_health = 500.0
	near.reset()
	var far := _spawn_beside(CRATE, 16.0, 2.5 + cannon.splash_radius + 4.0) as DestructibleTarget
	await _frames(2)
	_aim(plate.get_effect_origin())
	await _frames(1)
	var splashes := [0]
	var cb := func(_p: Vector3, _r: float) -> void: splashes[0] += 1
	cannon.splashed.connect(cb)
	cannon.spread_degrees = 0.0
	var hit := cannon.fire_one()
	cannon.splashed.disconnect(cb)
	_check(hit == plate, "shell hits the target under the barrel")
	_check(is_equal_approx(plate.max_health - plate.health, cannon.damage),
		"direct hit does %.0f (no double-dip from its own splash)" % (plate.max_health - plate.health))
	_check(near.health < near.max_health, "splash damages a crate 2.5 m away (%.0f)" % (near.max_health - near.health))
	_check(is_equal_approx(far.health, far.max_health), "nothing outside the blast radius is touched")
	_check(splashes[0] == 1, "shell bursts once")
	cannon.fire_one()
	_check(plate.is_destroyed, "two shells destroy a steel plate (MG needs 7 rounds)")
	cannon.spread_degrees = 0.3
	for t in [plate, near, far]:
		t.queue_free()


func _test_splash_chains_drones() -> void:
	var a := director.spawn_enemy(&"drone") as DroneEnemy
	var b := director.spawn_enemy(&"drone") as DroneEnemy
	for e: DroneEnemy in [a, b]:
		e.set_physics_process(false)
		e.armed = false
		e.rel_offset = a.core_rel_offset() + 10.0
		e.height = 9.0
	a.lateral = 16.0
	b.lateral = 18.0
	a._place(0.0)
	b._place(0.0)
	await _frames(2)
	_aim(a.get_effect_origin())
	await _frames(1)
	cannon.spread_degrees = 0.0
	var kills := score.enemy_kills
	cannon.fire_one()
	_check(a.is_destroyed and b.is_destroyed, "one shell takes out two drones flying together")
	_check(score.enemy_kills - kills == 2, "both drones credited")
	cannon.spread_degrees = 0.3
	a.despawn()
	b.despawn()


func _test_no_self_damage() -> void:
	hull.reset()
	# Shoot the ground right beside the gun car: the burst is within reach of the train.
	var car: Node3D = main.get_node("Train/ArmoredRailcar")
	var ground := car.global_position + car.global_basis.x * 3.5
	_aim(ground)
	await _frames(1)
	cannon.spread_degrees = 0.0
	for i in 5:
		cannon.fire_one()
	cannon.spread_degrees = 0.3
	_check(is_equal_approx(hull.hull, hull.max_hull), "shells bursting next to the train don't hurt it")


func _test_feedback_and_camera() -> void:
	camera.snap()
	await _frames(2)
	var basis_before := camera.global_basis
	var cannon_before: int = audio.requested[&"cannon"]
	var expl_before: int = audio.requested[&"explosion"]
	_aim(train.route.sample_world(train.get_centre_distance() + 40.0))
	await _frames(1)
	cannon.trigger_held = true
	for i in 60:
		cannon.step(1.0 / 60.0)
		await process_frame
	cannon.trigger_held = false
	_check(audio.requested[&"cannon"] > cannon_before, "cannon sound requested per shot")
	_check(audio.requested[&"explosion"] > expl_before, "every shell bursts with an explosion")
	var rot := rad_to_deg(basis_before.get_rotation_quaternion().angle_to(camera.global_basis.get_rotation_quaternion()))
	_check(rot < 0.01, "firing the cannon doesn't rotate the camera (%.4f°)" % rot)


func _test_independent_of_mg() -> void:
	mg.reset_stats()
	cannon.reset_stats()
	mg.trigger_held = true
	cannon.trigger_held = true
	mg.step(0.0)
	cannon.step(0.0)
	for i in 59:
		mg.step(1.0 / 60.0)
		cannon.step(1.0 / 60.0)
	mg.trigger_held = false
	cannon.trigger_held = false
	_check(absi(mg.shots_fired - 11) <= 1 and absi(cannon.shots_fired - 2) <= 1,
		"MG and cannon fire together at their own rates (%d + %d in 1 s)" % [mg.shots_fired, cannon.shots_fired])


func _test_no_node_growth() -> void:
	_aim(train.route.sample_world(train.get_centre_distance() + 30.0))
	await _frames(1)
	cannon.trigger_held = true
	for i in 60:
		cannon.step(1.0 / 60.0)
		await process_frame
	var before := _count(root)
	for i in 180:
		cannon.step(1.0 / 60.0)
		await process_frame
	cannon.trigger_held = false
	var after := _count(root)
	_check(after == before, "sustained cannon fire spawns no new nodes (%d → %d)" % [before, after])


# --------------------------------------------------------------------- helpers

func _aim(p: Vector3) -> void:
	turret.aim_at(p)
	turret.snap_to_aim()


func _spawn_beside(scene: PackedScene, lateral: float, ahead: float) -> Node3D:
	var off := train.get_centre_distance() + ahead
	var c := train.route.sample_world(off)
	var t := train.route.tangent_world(off)
	var right := Vector3(-t.z, 0.0, t.x).normalized()
	var n := scene.instantiate() as Node3D
	main.add_child(n)
	n.global_position = c + right * lateral
	return n


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)
