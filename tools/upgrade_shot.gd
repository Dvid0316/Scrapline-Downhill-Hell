extends SceneTree
## Screenshots for the upgrade system:
##   captures/upgrade_cards.png   the card picker after wave 1
##   captures/upgrade_combat.png  Tesla coil + rocket pod fighting
##   godot --path . -s res://tools/upgrade_shot.gd
func _initialize() -> void:
	_run()

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var train: TrainController = main.get_node("Train")
	var director: WaveDirector = main.get_node("Combat/WaveDirector")
	var up: UpgradeManager = main.get_node("Combat/Upgrades")
	var hull: TrainHull = main.get_node("Combat/TrainHull")
	var cam: FollowCamera = main.get_node("FollowCamera")
	hull.invulnerable = true
	director.set_enabled(false)
	train.set_head_distance(330.0)
	cam.snap()
	for i in 30: await process_frame
	# 1. Cards.
	director.wave = 1
	up.open(up.roll())
	for i in 40: await process_frame
	await _save("captures/upgrade_cards.png")
	up.choose(0)
	# 2. Combat with both new weapons.
	up.grant(&"tesla", 2)
	up.grant(&"rockets", 2)
	var spots := [[&"buggy", -10.0, 2.0], [&"truck", 10.0, -6.0], [&"drone", -12.0, 22.0], [&"drone", 14.0, 30.0], [&"buggy", 9.0, 12.0]]
	for s in spots:
		var e := director.spawn_enemy(s[0])
		e.armed = false
		e.set_physics_process(false)
		e.health = 9999.0
		e.rel_offset = e.core_rel_offset() + s[2]
		e.lateral = s[1]
		e._place(0.0)
	for i in 600:
		await process_frame
		if up.tesla._bolt.is_active() and up.rockets._rockets.size() >= 2:
			break
	await _save("captures/upgrade_combat.png")
	await up.tesla.zapped
	await process_frame
	await _save("captures/upgrade_zap.png")
	quit()

func _save(p: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://" + p)
	print("saved ", p)
