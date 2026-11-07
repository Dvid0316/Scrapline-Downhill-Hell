extends SceneTree
## Diagnostic: park a buggy at spots beside the railcar, aim at it the way the
## player does (camera ray through its screen position), then check what the
## barrel ray hits (no damage dealt). Prints a hit grid per track position.
##   godot --headless --path . -s res://tools/aim_probe.gd [-- --min-pitch=-22]

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
	var cam: Camera3D = main.get_node("FollowCamera")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--min-pitch="):
			turret.min_pitch = float(a.get_slice("=", 1))
	input.set_physics_process(false)
	director.set_enabled(false)
	var space := cam.get_world_3d().direct_space_state
	var total := 0
	var hits := 0
	for hd in [316.0, 600.0, 1400.0]:
		train.set_head_distance(hd)
		train.speed = 0.0
		train.paused = true
		for i in 5: await physics_frame
		(cam as FollowCamera).snap()
		for i in 5: await process_frame
		var e := director.spawn_enemy(&"buggy") as RaiderVehicle
		e.set_physics_process(false)
		e.armed = false
		var core := e.core_rel_offset()
		var rows := []
		for rel in [-6.0, 0.0, 6.0]:
			var row := "  rel %+3.0f  " % rel
			for lat in [-14.0, -10.0, -8.0, -6.0, -4.5, 4.5, 6.0, 8.0, 10.0, 14.0]:
				e.rel_offset = core + rel
				e.lateral = lat
				e._place(0.0)
				await physics_frame
				var aim := input.screen_to_aim_point(cam.unproject_position(e.get_effect_origin()))
				turret.aim_at(aim)
				turret.snap_to_aim()
				await process_frame
				var mz := turret.get_muzzle_transform().origin
				var q := PhysicsRayQueryParameters3D.create(mz, mz + turret.get_barrel_direction() * 320.0, PhysicsLayers.PLAYER_SHOT_MASK)
				var h := space.intersect_ray(q)
				var ok := not h.is_empty() and Damageable.find_in(h.collider as Node) == e
				total += 1
				hits += int(ok)
				row += " HIT " if ok else " ..  "
			rows.append(row)
		print("head %.0f m (lat -14 … +14):" % hd)
		for r in rows: print(r)
		e.despawn()
	print("min_pitch %.0f°: %d/%d hit" % [turret.min_pitch, hits, total])
	quit()
