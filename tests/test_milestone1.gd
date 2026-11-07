extends SceneTree
## Headless smoke test for Milestone 1.
##
## Run:  godot --headless --path . --fixed-fps 60 -s res://tests/test_milestone1.gd
## Exit code 0 = all checks passed, 1 = at least one failure.

var _failures := 0
var _main: Node
var _train: TrainController
var _camera: FollowCamera
var _frame := 0
var _start_distance := 0.0


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	_check(packed != null, "main.tscn loads")
	if packed == null:
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	_train = _main.get_node("Train")
	_camera = _main.get_node("FollowCamera")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_static_checks()
		_start_distance = _train.head_distance
	elif _frame == 122:
		_motion_checks()
		_loop_check_begin()
	elif _frame == 130:
		_loop_check_end()
		_finish()
		return true
	return false


func _static_checks() -> void:
	var route := _train.route
	var length := route.get_length()
	_check(length > 400.0, "route is long enough (%.0f m)" % length)
	var drop := route.sample_world(0.0).y - route.sample_world(length).y
	_check(drop > 20.0, "route descends (%.1f m drop)" % drop)
	_check(_train.cars.size() == 2, "train has locomotive + railcar (%d cars)" % _train.cars.size())

	# The original gentle part is downhill everywhere (no climbs > 0.5%).
	# After it comes the rollercoaster section (tests/test_coaster.gd).
	var worst := -INF
	var d := 20.0
	while d < route.get_coaster_start() - 40.0:
		worst = maxf(worst, route.grade_percent(d))
		d += 10.0
	_check(worst < 0.5, "no uphill on the gentle section (max grade %+.2f %%)" % worst)

	# Generated geometry exists.
	var rails := _main.get_node("Track/Rails")
	_check(rails.get_node_or_null("RailLeft") != null, "rails generated")
	_check(rails.get_node_or_null("Sleepers") != null, "sleepers generated")
	_check(_main.get_node("Terrain").get_node_or_null("TerrainMesh") != null, "terrain generated")
	var prop_count := 0
	for layer in _main.get_node("Props").get_children():
		prop_count += layer.get_child_count()
	_check(prop_count > 100, "props scattered (%d)" % prop_count)

	# Locomotive leads, railcar follows behind it along the route.
	var loco: Node3D = _train.cars[0]
	var car: Node3D = _train.cars[1]
	var ahead := route.tangent_world(_train.head_distance)
	_check((loco.global_position - car.global_position).dot(ahead) > 10.0, "railcar trails locomotive")
	var gap := loco.global_position.distance_to(car.global_position)
	_check(absf(gap - 16.5) < 1.0, "car spacing ≈ 16.5 m (%.2f)" % gap)

	# Camera framing within locked design.
	var fwd := -_camera.global_transform.basis.z
	var pitch := rad_to_deg(asin(-fwd.y))
	_check(pitch >= 44.5 and pitch <= 60.5, "camera pitch in 45–60° (%.1f°)" % pitch)
	var to_train := loco.global_position - _camera.global_position
	_check(to_train.dot(fwd) > 0.0, "train is in front of the camera")
	_check(_camera.global_position.y > loco.global_position.y + 15.0, "camera is overhead")


func _motion_checks() -> void:
	var moved := _train.head_distance - _start_distance
	_check(moved > 5.0, "train moved along the route (%.1f m in ~2 s)" % moved)
	_check(_train.speed > 1.0, "train has speed (%.1f m/s)" % _train.speed)
	# Downhill: later position is lower.
	var y_then := _train.route.sample_world(_start_distance).y
	var y_now := _train.route.sample_world(_train.head_distance).y
	_check(y_now <= y_then + 0.01, "train descended (%.2f → %.2f)" % [y_then, y_now])
	var to_train: Vector3 = (_train.cars[0] as Node3D).global_position - _camera.global_position
	_check(to_train.length() < 90.0, "camera kept up with train (%.1f m)" % to_train.length())

	# Speed adjustment.
	_train.target_speed = 30.0
	_check(is_equal_approx(_train.target_speed, 30.0), "target speed adjustable")


func _loop_check_begin() -> void:
	_train.head_distance = _train.get_route_length() - 0.5
	_train.target_speed = 30.0
	_train.speed = 30.0


func _loop_check_end() -> void:
	_check(_train.head_distance < 100.0, "run loops back to start at route end (%.1f m)" % _train.head_distance)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


func _finish() -> void:
	print("Milestone 1 tests: %s (%d failure%s)" % [
		"OK" if _failures == 0 else "FAILED", _failures, "" if _failures == 1 else "s"])
	quit(0 if _failures == 0 else 1)
