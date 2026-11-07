extends SceneTree
## Prints the train's speed along the whole route (headless physics sim).
##   godot --headless --path . -s res://tools/speed_profile.gd -- --target=14

func _initialize() -> void:
	_run()


func _run() -> void:
	var target := 14.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--target="):
			target = a.get_slice("=", 1).to_float()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	(main.get_node("Combat/WaveDirector") as WaveDirector).set_enabled(false)
	var train: TrainController = main.get_node("Train")
	train.set_process(false)
	train.restart()
	train.target_speed = target
	train.speed = target
	var dt := 1.0 / 60.0
	var t := 0.0
	var next := 0.0
	var top := 0.0
	var coaster := train.route.get_coaster_start()
	print("coaster starts at %.0f m, route %.0f m" % [coaster, train.get_route_length()])
	while train.head_distance < train.get_route_length() - 1.0 and t < 600.0:
		train.speed = train.step_speed(train.speed, dt)
		train.head_distance += train.speed * dt
		t += dt
		top = maxf(top, train.speed)
		if train.head_distance >= next:
			var c := train.get_centre_distance()
			print("%6.0f m  y %6.1f  grade %+5.1f%%  %5.1f m/s  %4.0f km/h" % [
				train.head_distance, train.route.sample_world(c).y, train.route.grade_percent(c), train.speed, train.speed * 3.6])
			next += 50.0
	print("time %.1f s, top speed %.1f m/s (%.0f km/h)" % [t, top, top * 3.6])
	quit()
