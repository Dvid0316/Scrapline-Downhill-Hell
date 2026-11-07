extends SceneTree
## Headless tests for the rollercoaster section: track shape, train gravity
## physics, trestles/ground, camera at speed, and the speed HUD.
##
## Run:  godot --headless --path . --fixed-fps 60 -s res://tests/test_coaster.gd
## Exit code 0 = all checks passed.

var _failures := 0
var main: Node
var train: TrainController
var route: RailRoute
var terrain: TerrainBuilder
var trestles: TrestleBuilder
var camera: FollowCamera
var hud: CombatHud

const DT := 1.0 / 60.0


func _initialize() -> void:
	_run()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	train = main.get_node("Train")
	route = train.route
	terrain = main.get_node("Terrain")
	trestles = main.get_node("Trestles")
	camera = main.get_node("FollowCamera")
	hud = main.find_children("*", "CombatHud", true, false)[0]
	(main.get_node("Combat/WaveDirector") as WaveDirector).set_enabled(false)
	train.set_process(false)

	_test_track_shape()
	_test_gentle_section_holds_speed()
	_test_drops_build_speed()
	_test_climb_bleeds_momentum()
	_test_terminal_speed()
	_test_pause_brakes_downhill()
	_test_trestles_and_ground()
	await _test_camera_and_hud_at_speed()

	print("Coaster tests: %s (%d failure%s)" % [
		"OK" if _failures == 0 else "FAILED", _failures, "" if _failures == 1 else "s"])
	main.quit_cleanly(0 if _failures == 0 else 1)


# ------------------------------------------------------------------ track

func _test_track_shape() -> void:
	var start := route.get_coaster_start()
	var length := route.get_length()
	_check(start > 900.0 and start < length - 1000.0,
		"coaster section starts after the gentle run (%.0f m of %.0f m)" % [start, length])
	var max_up := -INF
	var max_down := INF
	var climbs := 0
	var was_up := false
	var d := start
	while d < length - 20.0:
		var g := route.grade_percent(d)
		max_up = maxf(max_up, g)
		max_down = minf(max_down, g)
		var up := g > 8.0
		if up and not was_up:
			climbs += 1
		was_up = up
		d += 5.0
	_check(climbs >= 3, "several hills to climb (%d)" % climbs)
	_check(max_up > 12.0 and max_up < 30.0, "climbs are steep but drivable (max %+.0f%%)" % max_up)
	_check(max_down < -35.0 and max_down > -50.0, "big plunges (steepest %.0f%%)" % max_down)
	var drop := route.sample_world(start).y - route.sample_world(length).y
	_check(drop > 100.0, "coaster ends far below where it starts (%.0f m)" % drop)


# ------------------------------------------------------------------ physics

## Simulate from [param from] to [param to] metres; returns [min, max, end] speed.
func _sim(from: float, to: float, target: float, v0: float) -> Vector3:
	train.paused = false
	train.target_speed = target
	train.head_distance = from
	train.speed = v0
	var lo := INF
	var hi := 0.0
	var t := 0.0
	while train.head_distance < to and t < 300.0:
		train.speed = train.step_speed(train.speed, DT)
		train.head_distance += train.speed * DT
		lo = minf(lo, train.speed)
		hi = maxf(hi, train.speed)
		t += DT
	return Vector3(lo, hi, train.speed)


func _test_gentle_section_holds_speed() -> void:
	var r := _sim(train.get_start_distance(), route.get_coaster_start() - 20.0, 14.0, 14.0)
	_check(absf(r.x - 14.0) < 0.3 and absf(r.y - 14.0) < 0.3,
		"gentle section holds the set speed (%.1f–%.1f m/s)" % [r.x, r.y])
	r = _sim(train.get_start_distance(), route.get_coaster_start() - 20.0, 30.0, 30.0)
	_check(absf(r.y - 30.0) < 0.5, "…at a higher setting too (max %.1f m/s)" % r.y)


func _test_drops_build_speed() -> void:
	var r := _sim(route.get_coaster_start(), route.get_length() - 5.0, 14.0, 14.0)
	_check(r.y * 3.6 > 180.0, "drops push past the set speed (top %.0f km/h at 50 set)" % (r.y * 3.6))
	r = _sim(route.get_coaster_start(), route.get_length() - 5.0, train.max_speed, train.max_speed)
	_check(r.y * 3.6 > 230.0, "full throttle hits really high speed (top %.0f km/h)" % (r.y * 3.6))
	_check(r.x > 5.0, "never stalls on a climb (slowest %.1f m/s)" % r.x)


func _test_climb_bleeds_momentum() -> void:
	# Find the steepest climb and roll into it fast with the throttle low.
	var best := 0.0
	var at := 0.0
	var d := route.get_coaster_start()
	while d < route.get_length() - 50.0:
		var g := route.grade_percent(d)
		if g > best:
			best = g
			at = d
		d += 5.0
	var r := _sim(at - 10.0, at + 30.0, 10.0, 50.0)
	_check(r.z < 45.0, "climbing a hill slows a fast train (50 → %.1f m/s over 40 m)" % r.z)


func _test_terminal_speed() -> void:
	train.paused = false
	train.target_speed = train.max_speed
	train.head_distance = route.get_length() * 0.88
	var v := 200.0
	v = train.step_speed(v, DT)
	_check(v <= train.terminal_speed, "speed is capped at the terminal speed (%.0f km/h)" % (train.terminal_speed * 3.6))


func _test_pause_brakes_downhill() -> void:
	# Steepest drop, at speed, then Space.
	var worst := 0.0
	var at := 0.0
	var d := route.get_coaster_start()
	while d < route.get_length() - 50.0:
		var g := route.grade_percent(d)
		if g < worst:
			worst = g
			at = d
		d += 5.0
	train.head_distance = at
	train.speed = 40.0
	train.paused = true
	var t := 0.0
	while train.speed > 0.0 and t < 30.0:
		train.speed = train.step_speed(train.speed, DT)
		t += DT
	train.paused = false
	_check(train.speed == 0.0 and t < 10.0, "Space stops the train even on the steepest drop (%.1f s)" % t)


# ------------------------------------------------------------------ world

func _test_trestles_and_ground() -> void:
	_check(trestles.bent_count > 40, "trestles built where the track flies (%d bents)" % trestles.bent_count)
	# Highest lift on the coaster: track well above its ground, and the
	# terrain under the track really is down there.
	var best := 0.0
	var at := 0.0
	var d := route.get_coaster_start()
	while d < route.get_length():
		var l := terrain.track_lift(d)
		if l > best:
			best = l
			at = d
		d += 5.0
	var p := route.sample_world(at)
	var ground := terrain.sample_height(p.x, p.z)
	_check(best > 12.0 and p.y - ground > 10.0,
		"crests stand high above the ground (%.0f m lift, %.0f m to the terrain)" % [best, p.y - ground])
	# Gentle section: ground still hugs the track.
	var g := route.get_coaster_start() * 0.5
	_check(absf(terrain.track_lift(g)) < 0.5, "gentle section is unchanged (lift %.2f m)" % terrain.track_lift(g))
	var bed := route.sample_world(g)
	_check(absf(terrain.sample_height(bed.x, bed.z) - (bed.y - 0.35)) < 0.3, "track bed still on the ground there")


func _test_camera_and_hud_at_speed() -> void:
	train.set_process(true)
	train.head_distance = route.get_length() * 0.87
	train.target_speed = train.max_speed
	train.speed = 70.0
	camera.snap()
	for i in 90:
		await process_frame
	var loco := train.cars[0] as Node3D
	var vp := camera.get_viewport().get_visible_rect().size
	var s := camera.unproject_position(loco.global_position)
	var on := not camera.is_position_behind(loco.global_position) and \
		Rect2(Vector2.ZERO, vp).grow(-vp.x * 0.1).has_point(s)
	_check(on, "camera keeps the train on screen at %.0f km/h" % (train.speed * 3.6))
	var base_fov: float = camera.get("_base_fov")
	_check(camera.fov > base_fov + 5.0, "field of view widens at speed (%.1f° → %.1f°)" % [base_fov, camera.fov])
	_check(hud.speed_hud != null and hud.speed_hud.get_rush() > 0.5, "speed lines kick in (rush %.2f)" % hud.speed_hud.get_rush())
	_check(hud.speed_hud.size.x > 100.0, "speed overlay covers the screen")
	train.head_distance = 400.0  # gentle section, so gravity can't re-accelerate
	train.target_speed = 10.0
	train.speed = 10.0
	for i in 120:
		await process_frame
	_check(hud.speed_hud.get_rush() == 0.0, "…and fade out at low speed")
	train.set_process(false)


# ------------------------------------------------------------------ helpers

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)
