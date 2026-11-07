extends SceneTree
## Headless tests for Milestone 3 (enemies, train hull, waves).
##
## Run:  godot --headless --path . --fixed-fps 60 -s res://tests/test_milestone3.gd
## Exit code 0 = all checks passed.
##
## Drives the real main scene. Mouse input is off; the turret and weapon are
## driven through the same calls TurretInput uses, and enemies are spawned
## through the WaveDirector exactly as waves do.

var _failures := 0
var main: Node
var train: TrainController
var turret: MountedTurret
var weapon: HitscanWeapon
var input: TurretInput
var course: TargetCourse
var score: ScoreTracker
var hull: TrainHull
var director: WaveDirector
var hud: CombatHud
var audio: CombatAudio
var terrain: TerrainBuilder


func _initialize() -> void:
	_run()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	train = main.get_node("Train")
	turret = main.get_node("Train/ArmoredRailcar/TurretMount/HeavyMGTurret")
	weapon = main.get_node("Combat/Weapon")
	input = main.get_node("Combat/TurretInput")
	course = main.get_node("TargetCourse")
	score = main.get_node("Combat/ScoreTracker")
	hull = main.get_node("Combat/TrainHull")
	director = main.get_node("Combat/WaveDirector")
	hud = main.get_node("CombatHud")
	audio = main.get_node("Combat/Audio")
	terrain = main.get_node("Terrain")
	input.set_physics_process(false)
	weapon.set_physics_process(false)
	director.set_enabled(false)  # tests spawn by hand until the wave test
	train.set_head_distance(316.0)  # absolute, so route changes don't move the test
	await _frames(3)

	_test_setup()
	await _test_each_kind_spawns_and_keeps_pace()
	await _test_ground_vehicle_drives()
	await _test_player_kills_enemy()
	await _test_close_raiders_hittable()
	await _test_enemy_fire_damages_hull()
	await _test_kamikaze_hits_train()
	await _test_kamikaze_chain()
	await _test_wave_flow()
	_test_endless_scaling()
	await _test_route_loop_keeps_run()
	await _test_game_over_and_restart()
	await _test_pool_reuse()

	print("Milestone 3 tests: %s (%d failure%s)" % [
		"OK" if _failures == 0 else "FAILED", _failures, "" if _failures == 1 else "s"])
	main.quit_cleanly(0 if _failures == 0 else 1)


# --------------------------------------------------------------------- tests

func _test_setup() -> void:
	_check(hull != null and director != null, "hull and wave director present")
	_check(is_equal_approx(hull.hull, hull.max_hull) and not hull.is_wrecked, "hull starts full (%.0f)" % hull.hull)
	_check(PhysicsLayers.PLAYER_SHOT_MASK & PhysicsLayers.ENEMIES != 0, "player shots can hit enemies")
	_check(PhysicsLayers.ENEMY_SHOT_MASK & (PhysicsLayers.ENEMIES | PhysicsLayers.TARGETS) == 0,
		"enemy shots ignore other enemies and range targets")
	_check(PhysicsLayers.ENEMY_SHOT_MASK & PhysicsLayers.TRAIN != 0, "enemy shots can hit the train")


## Every kind spawns into play, is a Damageable, and stays with the moving train.
func _test_each_kind_spawns_and_keeps_pace() -> void:
	_run_train(20.0)
	for kind: StringName in WaveDirector.KINDS:
		var e := director.spawn_enemy(kind)
		_check(e != null and e.active and not e.is_destroyed and e is Damageable, "%s spawns into play" % kind)
		if e == null:
			continue
		var body := e.get_node("Body") as CollisionObject3D
		_check(body.collision_layer == PhysicsLayers.ENEMIES, "%s hit box on the ENEMIES layer" % kind)
		var start := train.head_distance
		for i in 180:
			await physics_frame
		var d := e.global_position.distance_to(hull.get_core_point())
		_check(train.head_distance - start > 50.0 and d < 160.0,
			"%s keeps pace with the train (%.0f m travelled, %.0f m away)" % [kind, train.head_distance - start, d])
		e.despawn()
		_check(not e.active and not e.visible and body.collision_layer == 0, "%s despawns cleanly" % kind)


## Buggy: catches up from behind, drives on the ground beside the track.
func _test_ground_vehicle_drives() -> void:
	_run_train(16.0)
	var b := director.spawn_enemy(&"buggy") as RaiderVehicle
	b.armed = false
	var start_rel := b.rel_offset
	for i in 360:
		await physics_frame
	_check(start_rel < -40.0 and b.rel_offset > -35.0,
		"buggy catches up from behind (%.0f m → %.0f m relative)" % [start_rel, b.rel_offset])
	var ground := terrain.sample_height(b.global_position.x, b.global_position.z)
	_check(absf(b.global_position.y - ground) < 0.25, "buggy drives on the terrain (%.2f m off)" % (b.global_position.y - ground))
	var rel := terrain.track_relation(b.global_position.x, b.global_position.z)
	_check(absf(rel.x) > 6.5 and absf(rel.x) < 13.0, "buggy stays in its lane beside the track (%.1f m)" % rel.x)
	b.armed = true
	b.despawn()


## Player hitscan destroys an enemy: points, enemy kill count, explosion requested.
func _test_player_kills_enemy() -> void:
	_stop_train()
	var e := director.spawn_enemy(&"drone") as DroneEnemy
	e.armed = false
	# Park it in clear air beside the railcar.
	e.state = DroneEnemy.State.CRUISE
	e.rel_offset = e.core_rel_offset() + 6.0
	e.lateral = 14.0
	e.height = 9.0
	e.set_physics_process(false)
	e._place(0.0)
	await _frames(2)
	weapon.spread_degrees = 0.0
	turret.aim_at(e.get_effect_origin())
	turret.snap_to_aim()
	await _frames(1)
	var score_before := score.score
	var kills_before := score.enemy_kills
	var explosions_before: int = audio.requested[&"explosion"]
	var hit := weapon.fire_one()
	_check(hit == e, "hitscan hits a drone in front of the barrel")
	var guard := 0
	while not e.is_destroyed and guard < 40:
		weapon.fire_one()
		guard += 1
	_check(e.is_destroyed, "drone destroyed by gunfire (%d rounds)" % (guard + 1))
	_check(score.score - score_before == e.points and score.enemy_kills == kills_before + 1,
		"enemy kill awards %d points and counts as an enemy kill" % e.points)
	_check(audio.requested[&"explosion"] > explosions_before, "enemy destruction requests an explosion")
	e.set_physics_process(true)
	for i in 200:
		await physics_frame
		if not e.active:
			break
	_check(not e.active, "shot-down drone falls, then returns to the pool")
	weapon.spread_degrees = 0.6


## Raiders hugging the car (and below the coaster trestles) can be hit when
## the crosshair is on them: the gun tips down steeply instead of shooting
## over them.
func _test_close_raiders_hittable() -> void:
	var camera: Camera3D = main.get_node("FollowCamera")
	var space := camera.get_world_3d().direct_space_state
	var e := director.spawn_enemy(&"buggy") as RaiderVehicle
	e.armed = false
	e.set_physics_process(false)
	for spot in [[316.0, -5.0], [316.0, 5.0], [316.0, -8.0], [1400.0, -6.0], [1400.0, 8.0]]:
		train.set_head_distance(spot[0])
		_stop_train()
		await _frames(2)
		(camera as FollowCamera).snap()
		await _frames(2)
		e.rel_offset = e.core_rel_offset()
		e.lateral = spot[1]
		e._place(0.0)
		await physics_frame
		turret.aim_at(input.screen_to_aim_point(camera.unproject_position(e.get_effect_origin())))
		turret.snap_to_aim()
		await process_frame
		var mz := turret.get_muzzle_transform().origin
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			mz, mz + turret.get_barrel_direction() * 320.0, PhysicsLayers.PLAYER_SHOT_MASK))
		var ok := not h.is_empty() and Damageable.find_in(h.collider as Node) == e
		_check(ok, "raider %.0f m to the %s at %.0f m along the route is hittable" % [
			absf(spot[1]), "left" if spot[1] < 0.0 else "right", spot[0]])
	e.armed = true  # pooled: leave it as we found it
	e.set_physics_process(true)
	e.despawn()
	train.set_head_distance(316.0)
	await _frames(2)


## Enemy rounds hit the hull (and report to the presentation layer).
func _test_enemy_fire_damages_hull() -> void:
	_stop_train()
	hull.reset()
	var b := director.spawn_enemy(&"buggy") as RaiderVehicle
	b.rel_offset = b.core_rel_offset()
	b.lateral = 9.5
	b._place(0.0)
	b.set_physics_process(false)
	b.spread_degrees = 0.0
	await _frames(2)
	var shots_before: int = audio.requested[&"enemy_shot"]
	var hits := 0
	for i in 10:
		if b.fire_round():
			hits += 1
	_check(hits >= 8, "enemy rounds hit the train at close range (%d/10)" % hits)
	_check(is_equal_approx(hull.hull, hull.max_hull - hits * b.round_damage),
		"each hit takes round_damage off the hull (%.0f → %.1f)" % [hull.max_hull, hull.hull])
	_check(hull.hits_taken == hits, "hull counts hits (%d)" % hull.hits_taken)
	_check(audio.requested[&"enemy_shot"] > shots_before, "enemy gunfire requests sounds")
	# The AI fires on its own when in range.
	hull.reset()
	b.spread_degrees = 2.8
	b.set_physics_process(true)
	b._burst_cd = 0.0
	for i in 120:
		await physics_frame
	_check(b.shots_fired > 10 and hull.hull < hull.max_hull, "buggy fires bursts at the train on its own (%d rounds, hull %.0f)" % [b.shots_fired, hull.hull])
	b.despawn()
	hull.reset()


## Kamikaze: arms, dives, blows up on the railcar. Big hull hit, no points.
func _test_kamikaze_hits_train() -> void:
	_run_train(14.0)
	hull.reset()
	var k := director.spawn_enemy(&"kamikaze") as DroneEnemy
	var score_before := score.score
	var warn_before: int = audio.requested[&"warning"]
	var saw_arming := false
	var saw_diving := false
	for i in 900:
		await physics_frame
		saw_arming = saw_arming or k.state == DroneEnemy.State.ARMING
		saw_diving = saw_diving or k.state == DroneEnemy.State.DIVING
		if not k.active:
			break
	_check(saw_arming and saw_diving, "kamikaze arms (warning) then dives")
	_check(audio.requested[&"warning"] > warn_before, "kamikaze arming plays a warning beep")
	_check(not k.active, "kamikaze reached the train and detonated")
	_check(is_equal_approx(hull.max_hull - hull.hull, k.impact_damage),
		"kamikaze hit takes %.0f hull" % (hull.max_hull - hull.hull))
	_check(score.score == score_before, "no points for a kamikaze that got through")
	hull.reset()


## A kamikaze shot down near other drones takes them with it.
func _test_kamikaze_chain() -> void:
	_stop_train()
	var k := director.spawn_enemy(&"kamikaze") as DroneEnemy
	var d := director.spawn_enemy(&"drone") as DroneEnemy
	for e: DroneEnemy in [k, d]:
		e.set_physics_process(false)
		e.rel_offset = 20.0
		e.height = 10.0
	k.lateral = 15.0
	d.lateral = 18.0
	k._place(0.0)
	d._place(0.0)
	await _frames(1)
	var kills_before := score.enemy_kills
	k.apply_damage(999.0, k.global_position)
	_check(d.is_destroyed, "kamikaze blast destroys a drone 3 m away")
	_check(score.enemy_kills - kills_before == 2, "chain kill credited for both")
	k.despawn()
	d.despawn()


## Waves: breather → spawn → clear → repair → next wave.
func _test_wave_flow() -> void:
	_run_train(14.0)
	hull.reset()
	hull.invulnerable = true
	var started: Array = []
	var cleared: Array = []
	director.wave_started.connect(func(w: int, c: int) -> void: started.append([w, c]))
	director.wave_cleared.connect(func(w: int) -> void: cleared.append(w))
	director.set_enabled(true)
	director.reset(1)
	_check(director.state == WaveDirector.State.BREATHER and director.wave == 0, "run starts with a breather")
	var cues_before: int = audio.requested[&"cue"]
	director.breather_left = 0.05
	for i in 10:
		await physics_frame
	_check(started.size() == 1 and started[0][0] == 1 and started[0][1] == 4,
		"wave 1 starts with 4 drones (%s)" % str(started))
	_check(audio.requested[&"cue"] > cues_before, "wave start plays the horn")
	# Let them all spawn, then shoot them down.
	var guard := 0
	while (director.get_remaining() > 0) and guard < 1200:
		await physics_frame
		guard += 1
		for e in director.get_alive().duplicate():
			if not e.is_destroyed and e.rel_offset < 80.0:
				e.apply_damage(999.0, e.global_position, Vector3.UP, weapon)
	for i in 3:
		await physics_frame  # the director notices on its next tick
	_check(cleared == [1], "wave 1 cleared once every drone is down (%d frames)" % guard)
	_check(director.state == WaveDirector.State.BREATHER and director.wave == 1, "breather before wave 2")
	hull.invulnerable = false
	hull.apply_hit(200.0, Vector3.ZERO)
	var before := hull.hull
	director._finish_wave()
	_check(is_equal_approx(hull.hull - before, hull.max_hull * director.repair_per_wave),
		"clearing a wave patches the hull (+%.0f)" % (hull.hull - before))
	director.breather_left = 0.05
	for i in 10:
		await physics_frame
	var def2 := director.get_wave_definition(2)
	_check(director.wave == 2 and started.size() == 2 and started[1][1] == def2["buggy"] + def2["drone"],
		"wave 2 brings raiders and drones (%d)" % started[1][1])
	director.set_enabled(false)
	_check(director.get_alive().is_empty(), "disabling waves clears the field")
	hull.reset()


func _test_endless_scaling() -> void:
	var w5 := director.get_wave_definition(5)
	var w8 := director.get_wave_definition(8)
	var n5 := 0
	var n8 := 0
	for k in WaveDirector.KINDS:
		n5 += int(w5.get(k, 0))
		n8 += int(w8.get(k, 0))
	_check(n8 > n5 and is_equal_approx(w8["health_mult"], 1.3),
		"waves keep scaling after 5 (wave 5: %d, wave 8: %d enemies, ×%.1f health)" % [n5, n8, w8["health_mult"]])


## Reaching the end of the line loops the train but keeps the run going.
func _test_route_loop_keeps_run() -> void:
	director.set_enabled(true)
	director.reset(1)
	director.breather_left = 0.05
	_run_train(14.0)
	for i in 10:
		await physics_frame
	var e := director.spawn_enemy(&"drone")
	e.armed = false
	await _frames(2)
	score.score = 777
	var wave := director.wave
	var t: Damageable = course.targets[0]
	t.apply_damage(9999.0, t.global_position)
	score.score = 777
	var gap_before := e.global_position.distance_to(hull.get_core_point())
	train.head_distance = train.get_route_length() - 0.05
	await _frames(5)
	var gap_after := e.global_position.distance_to(hull.get_core_point())
	_check(train.head_distance < 100.0, "train looped back to the start (%.0f m)" % train.head_distance)
	_check(score.score == 777 and director.wave == wave, "loop keeps score and wave")
	_check(not t.is_destroyed, "loop brings the range targets back")
	_check(e.active and absf(gap_after - gap_before) < 15.0,
		"enemies come along through the loop (%.0f m → %.0f m from the railcar)" % [gap_before, gap_after])
	director.set_enabled(false)


## Hull at zero: game over. R (train.restart) starts a fresh run.
func _test_game_over_and_restart() -> void:
	director.set_enabled(true)
	director.reset(3)
	director.breather_left = 0.0
	_run_train(14.0)
	for i in 30:
		await physics_frame
	var b := director.spawn_enemy(&"buggy")
	b.rel_offset = b.core_rel_offset()
	input.set_physics_process(true)
	hull.apply_hit(hull.max_hull + 10.0, hull.get_core_point())
	_check(hull.is_wrecked and main.game_over, "hull at zero ends the run")
	_check(train.paused and not input.is_physics_processing() and not weapon.trigger_held,
		"train brakes and the gun goes quiet")
	_check(director.state == WaveDirector.State.STOPPED, "waves stop")
	_check(hud.is_game_over_visible(), "game-over panel shown")
	var fired := b.shots_fired
	for i in 90:
		await physics_frame
	_check(b.shots_fired == fired, "enemies stop shooting at the wreck")
	_check(train.speed < 14.0, "train is braking (%.1f m/s)" % train.speed)
	score.score = 500
	train.restart()
	await physics_frame
	_check(not hull.is_wrecked and is_equal_approx(hull.hull, hull.max_hull), "restart repairs the hull")
	_check(director.state == WaveDirector.State.BREATHER and director.wave == 0 and director.get_alive().is_empty(),
		"restart clears enemies and starts again from wave 1")
	_check(score.score == 0 and not main.game_over and not train.paused and not hud.is_game_over_visible(),
		"restart resets score, unpauses, hides the panel")
	_check(input.is_physics_processing(), "restart gives the gun back")
	input.set_physics_process(false)
	director.set_enabled(false)


## Enemies are pooled: running wave after wave doesn't keep adding nodes.
func _test_pool_reuse() -> void:
	_run_train(14.0)
	hull.invulnerable = true
	var counts: Array[int] = []
	for cycle in 3:
		for k: StringName in WaveDirector.KINDS:
			for i in 3:
				director.spawn_enemy(k)
		for i in 20:
			await physics_frame
		for e in director.get_alive().duplicate():
			e.apply_damage(999.0, e.global_position)
		for i in 320:  # longest wreck time is 4 s
			await physics_frame
		counts.append(director.get_child_count())
	_check(counts[1] == counts[0] and counts[2] == counts[0],
		"enemy pool reused across waves (%s nodes)" % str(counts))
	hull.invulnerable = false


# --------------------------------------------------------------------- helpers

func _run_train(speed: float) -> void:
	train.paused = false
	train.target_speed = speed
	train.speed = speed


func _stop_train() -> void:
	train.target_speed = 0.0
	train.speed = 0.0


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)
