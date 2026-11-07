extends SceneTree
## Screenshot: gun tipped down at a buggy right beside the railcar.
func _initialize() -> void:
	_run()
func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var train: TrainController = main.get_node("Train")
	var turret: MountedTurret = main.get_node("Train/ArmoredRailcar/TurretMount/HeavyMGTurret")
	var input: TurretInput = main.get_node("Combat/TurretInput")
	var director: WaveDirector = main.get_node("Combat/WaveDirector")
	var cam: FollowCamera = main.get_node("FollowCamera")
	input.set_physics_process(false)
	director.set_enabled(false)
	var i := 0
	for spot in [[316.0, -5.0], [1400.0, -6.0]]:
		train.set_head_distance(spot[0])
		train.speed = 0.0
		train.target_speed = 0.0
		for k in 5: await physics_frame
		cam.snap()
		var e := director.spawn_enemy(&"buggy") as RaiderVehicle
		e.set_physics_process(false)
		e.rel_offset = e.core_rel_offset() + 3.0
		e.lateral = spot[1]
		e._place(0.0)
		for k in 30: await process_frame
		turret.aim_at(input.screen_to_aim_point(cam.unproject_position(e.get_effect_origin())))
		turret.snap_to_aim()
		for k in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://captures/aim_close_%d.png" % i)
		i += 1
		e.despawn()
	quit()
