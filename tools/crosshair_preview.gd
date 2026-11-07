extends SceneTree
## Readability check for the crosshair: draws one crosshair per colour preset
## over different backgrounds (sand, grass, trees, train) and saves a shot.
##   godot --path . --resolution 1600x900 -s res://tools/crosshair_preview.gd -- --out=captures/xhair.png

const SPOTS := [Vector2(250, 300), Vector2(560, 560), Vector2(1350, 560), Vector2(800, 640), Vector2(1100, 250)]


func _initialize() -> void:
	_run()


func _run() -> void:
	var out := "captures/xhair.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	(main.get_node("Combat/WaveDirector") as WaveDirector).set_enabled(false)
	var train: TrainController = main.get_node("Train")
	train.set_progress_ratio(0.62)
	var hud: Node = main.find_child("Crosshair", true, false).get_parent()
	for i in SPOTS.size():
		var x := Crosshair.new()
		var p: Vector2 = SPOTS[i]
		x.aim_provider = func() -> Vector2: return p
		x.gun_provider = func() -> Variant: return p + Vector2(22, -14)
		x.cannon_provider = func() -> Variant: return 0.6
		hud.add_child(x)
		x.set_preset(i, false)
	for f in 90:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
