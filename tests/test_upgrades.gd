extends SceneTree
## Headless tests for between-wave upgrades: the offer flow (breather holds,
## guns don't fire, picking resumes), every stat upgrade, the two new weapons
## (Tesla coil, rocket pod), ricochet rounds, and reset on a new run.
##
## Run:  godot --headless --path . --fixed-fps 60 -s res://tests/test_upgrades.gd

var _failures := 0
var main: Node
var train: TrainController
var director: WaveDirector
var hull: TrainHull
var weapon: HitscanWeapon
var cannon: HitscanWeapon
var turret: MountedTurret
var input: TurretInput
var up: UpgradeManager
var audio: CombatAudio


func _initialize() -> void:
	_run()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	train = main.get_node("Train")
	director = main.get_node("Combat/WaveDirector")
	hull = main.get_node("Combat/TrainHull")
	weapon = main.get_node("Combat/Weapon")
	cannon = main.get_node("Combat/Cannon")
	turret = main.get_node("Train/ArmoredRailcar/TurretMount/HeavyMGTurret")
	input = main.get_node("Combat/TurretInput")
	up = main.get_node("Combat/Upgrades")
	audio = main.get_node("Combat/Audio")
	director.set_enabled(false)
	train.set_head_distance(316.0)
	train.target_speed = 0.0
	train.speed = 0.0
	await _frames(3)

	_test_starts_empty()
	_test_roll()
	await _test_offer_flow()
	await _test_keys_pick()
	_test_stat_upgrades()
	_test_armor()
	await _test_tesla()
	await _test_rockets()
	await _test_ricochet()
	_test_maxed_cards_leave_pool()
	await _test_restart_resets()

	print("Upgrade tests: %s (%d failure%s)" % [
		"OK" if _failures == 0 else "FAILED", _failures, "" if _failures == 1 else "s"])
	main.quit_cleanly(0 if _failures == 0 else 1)


func _test_starts_empty() -> void:
	_check(up != null and up.levels.is_empty(), "run starts with no upgrades")
	_check(up.tesla != null and not up.tesla.visible, "Tesla coil mounted but hidden until bought")
	_check(up.rockets != null and not up.rockets.visible, "rocket pod mounted but hidden until bought")
	_check(up.tesla.get_parent() == train.cars[0], "coil rides the locomotive")


func _test_roll() -> void:
	up.reset()
	var a := up.roll()
	var distinct := {}
	for id in a:
		distinct[id] = true
	_check(a.size() == 3 and distinct.size() == 3, "an offer is 3 different cards (%s)" % str(a))
	var has_weapon := a.any(func(id: StringName) -> bool: return UpgradeManager.CATALOG[id]["tag"] == UpgradeManager.Tag.WEAPON)
	_check(has_weapon, "first offer of a run includes a new weapon")
	for id in UpgradeManager.CATALOG:
		_check(up.describe(id, 1) != "" and up.describe(id, 2) != "", "card '%s' has text" % id)


func _test_offer_flow() -> void:
	up.reset()
	up.offer_delay = 0.1
	director.enabled = true
	director.state = WaveDirector.State.SPAWNING
	director.wave = 2
	director._finish_wave()   # as if wave 2 was just cleared
	_check(director.hold, "clearing a wave holds the breather")
	await _frames(12)
	_check(up.is_open and up.picker.visible and up.picker.get_card_count() == 3, "three cards come up after a moment")
	var left := director.breather_left
	await _frames(30)
	_check(is_equal_approx(director.breather_left, left), "next-wave countdown waits while choosing")
	_check(input.suppress_fire, "guns hold fire while the cards are up")
	var id := up.offer[0]
	var cues: int = audio.requested[&"cue"]
	up.choose(0)
	_check(up.level_of(id) == 1, "picking a card gives that upgrade (%s)" % id)
	_check(not up.is_open and not up.picker.visible and not director.hold and not input.suppress_fire,
		"cards close, countdown and guns resume")
	_check(audio.requested[&"cue"] > cues, "picking plays a chime")
	director.set_enabled(false)
	up.offer_delay = 1.2


func _test_keys_pick() -> void:
	up.reset()
	up.open(up.roll())
	var second := up.offer[1]
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_2
	ev.pressed = true
	root.push_input(ev)
	await _frames(1)
	_check(up.level_of(second) == 1 and not up.is_open, "key 2 picks the second card")


func _test_stat_upgrades() -> void:
	up.reset()
	var mg_rate := weapon.fire_rate
	var mg_dmg := weapon.damage
	var c_rate := cannon.fire_rate
	var c_rad := cannon.splash_radius
	var yaw := turret.yaw_speed_degrees
	up.grant(&"mg_rate")
	up.grant(&"mg_damage", 2)
	up.grant(&"cannon_rate")
	up.grant(&"cannon_blast")
	up.grant(&"servo")
	up.grant(&"ricochet")
	_check(is_equal_approx(weapon.fire_rate, mg_rate * 1.3), "Hot Barrel: MG fires faster (%.1f rps)" % weapon.fire_rate)
	_check(is_equal_approx(weapon.damage, mg_dmg * 1.7), "AP Rounds x2: MG hits harder (%.1f)" % weapon.damage)
	_check(is_equal_approx(cannon.fire_rate, c_rate * 1.4), "Autoloader: cannon reloads faster")
	_check(cannon.splash_radius > c_rad, "Big Bang Shells: bigger blasts (%.1f m)" % cannon.splash_radius)
	_check(turret.yaw_speed_degrees > yaw, "Turbo Servos: faster turret")
	_check(weapon.ricochet_bounces == 1, "Ricochet Rounds: bullets bounce")
	up.reset()
	_check(is_equal_approx(weapon.fire_rate, mg_rate) and is_equal_approx(weapon.damage, mg_dmg)
		and is_equal_approx(cannon.splash_radius, c_rad) and weapon.ricochet_bounces == 0
		and is_equal_approx(turret.yaw_speed_degrees, yaw), "reset puts every stat back")


func _test_armor() -> void:
	up.reset()
	hull.reset()
	var base := hull.max_hull
	hull.apply_hit(150.0, Vector3.ZERO)
	var before := hull.hull
	up.grant(&"armor")
	_check(is_equal_approx(hull.max_hull, base + 100.0) and is_equal_approx(hull.hull, before + 100.0),
		"Scrap Armor: +100 max and +100 now (%.0f/%.0f)" % [hull.hull, hull.max_hull])
	up.grant(&"reactive", 2)
	var h := hull.hull
	hull.apply_hit(10.0, Vector3.ZERO)
	_check(is_equal_approx(h - hull.hull, 7.0), "Reactive Plating x2: 30%% less damage (took %.1f)" % (h - hull.hull))
	up.grant(&"patch")
	_check(is_equal_approx(hull.hull, hull.max_hull), "Emergency Patch: hull back to full")
	up.reset()
	hull.reset()
	_check(is_equal_approx(hull.max_hull, base) and is_equal_approx(hull.damage_mult, 1.0), "reset: base hull, normal damage")


func _spawn(kind: StringName, lateral: float, ahead: float) -> EnemyBase:
	var e := director.spawn_enemy(kind)
	e.armed = false
	e.set_physics_process(false)
	e.rel_offset = e.core_rel_offset() + ahead
	e.lateral = lateral
	if e is DroneEnemy:
		e.height = 6.0
	e._place(0.0)
	return e


func _release(e: EnemyBase) -> void:
	e.armed = true
	e.set_physics_process(true)
	if e.active:
		e.despawn()


func _test_tesla() -> void:
	up.reset()
	var a := _spawn(&"truck", -9.0, 10.0)
	var b := _spawn(&"buggy", -9.0, 18.0)
	a.health = 1000.0  # tough enough to survive every zap here
	b.health = 1000.0
	await _frames(2)
	_check(not up.tesla.zap(), "coil does nothing until bought")
	up.grant(&"tesla")
	_check(up.tesla.visible, "Tesla coil appears on the engine")
	var ha := a.health
	var hb := b.health
	_check(up.tesla.zap(), "coil zaps an enemy in range")
	_check(a.health < ha or b.health < hb, "the zap does damage")
	_check(not (a.health < ha and b.health < hb), "level 1 hits one enemy")
	up.grant(&"tesla")
	ha = a.health
	hb = b.health
	up.tesla.zap()
	_check(a.health < ha and b.health < hb, "level 2 lightning chains to a second enemy")
	# Fires on its own.
	var zaps := up.tesla.zaps
	await _physics(90)
	_check(up.tesla.zaps > zaps, "coil fires automatically (%d zaps in 1.5 s)" % (up.tesla.zaps - zaps))
	_release(a)
	_release(b)
	up.reset()


func _test_rockets() -> void:
	up.reset()
	var d := _spawn(&"drone", 10.0, 25.0)
	await _frames(2)
	up.grant(&"rockets")
	_check(up.rockets.visible and up.rockets.volley == 2, "rocket pod appears (2 per volley)")
	up.rockets._cd = 0.0
	var rockets_before: int = audio.requested[&"rocket"]
	var guard := 0
	while not d.is_destroyed and guard < 300:
		await physics_frame
		guard += 1
	_check(d.is_destroyed, "homing rockets shoot down a drone (%.1f s)" % (guard / 60.0))
	_check(audio.requested[&"rocket"] > rockets_before, "launch sound requested")
	_check(up.rockets.fired >= 1, "rockets fired (%d)" % up.rockets.fired)
	await _physics(60)
	_release(d)
	up.reset()
	_check(up.rockets._rockets.is_empty() and not up.rockets.visible, "reset clears rockets in flight")


func _test_ricochet() -> void:
	up.reset()
	var a := _spawn(&"truck", -10.0, 0.0)
	var b := _spawn(&"buggy", -10.0, 9.0)
	await _frames(2)
	var hb := b.health
	var origin := turret.get_muzzle_transform().origin
	weapon.fire_ray(origin, (a.get_effect_origin() - origin).normalized())
	_check(is_equal_approx(b.health, hb), "no ricochet without the upgrade")
	up.grant(&"ricochet")
	var bounced := []
	weapon.ricocheted.connect(func(_f: Vector3, _t: Vector3, t: Node, _k: bool) -> void: bounced.append(t), CONNECT_ONE_SHOT)
	weapon.fire_ray(origin, (a.get_effect_origin() - origin).normalized())
	_check(b.health < hb and bounced == [b], "Ricochet Rounds: the bullet bounces into the next enemy")
	_release(a)
	_release(b)
	up.reset()


func _test_maxed_cards_leave_pool() -> void:
	up.reset()
	for id: StringName in UpgradeManager.CATALOG:
		if id != &"patch":
			up.grant(id, 99)
	var a := up.roll()
	_check(a == [&"patch"], "maxed-out cards stop appearing; Emergency Patch is always there (%s)" % str(a))
	up.reset()


func _test_restart_resets() -> void:
	up.grant(&"tesla", 2)
	up.grant(&"armor")
	train.restart()
	await _frames(2)
	_check(up.levels.is_empty() and not up.tesla.visible, "a new run starts without upgrades")
	_check(is_equal_approx(hull.hull, hull.max_hull) and is_equal_approx(hull.max_hull, 400.0), "…and with the normal hull")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)
