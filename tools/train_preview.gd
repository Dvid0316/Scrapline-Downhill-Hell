extends SceneTree
## Close-up beauty shots of the train (art check, not a test).
##
## Run (needs a display):
##   godot --path . --resolution 1600x900 -s res://tools/train_preview.gd -- --out=captures/train
## Saves <out>_0.png .. <out>_3.png from four angles with enemies off.

const SHOTS := [
	# [car, eye offset in that car's local frame, look-at offset]
	["Locomotive", Vector3(7.0, 4.0, -17.0), Vector3(0, 2.0, -5.0)],    # loco front three-quarter
	["ArmoredRailcar", Vector3(-10.0, 6.0, 4.0), Vector3(0, 2.4, -2.0)],  # side, gun car + loco rear
	["ArmoredRailcar", Vector3(5.5, 1.6, -3.0), Vector3(0, 0.8, 3.5)],    # low, bogie close-up
	["ArmoredRailcar", Vector3(3.0, 13.0, 9.0), Vector3(0, 3.0, -1.0)],   # high, gameplay-ish angle
]


func _initialize() -> void:
	_run()


func _run() -> void:
	var out := "captures/train"
	var at_ratio := 0.22
	var shots := SHOTS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--at="):
			at_ratio = a.get_slice("=", 1).to_float()
		elif a == "--wide":
			# Far side views for the track/trestles.
			shots = [["Locomotive", Vector3(-45.0, 6.0, 40.0), Vector3(0, -2.0, -10.0)],
				["Locomotive", Vector3(55.0, 10.0, -60.0), Vector3(0, -8.0, -20.0)]]
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var director: WaveDirector = main.get_node("Combat/WaveDirector")
	director.set_enabled(false)
	var train: TrainController = main.get_node("Train")
	train.set_progress_ratio(at_ratio)
	train.target_speed = 0.0
	train.speed = 0.0
	var follow: Node = main.get_node("FollowCamera")
	follow.process_mode = Node.PROCESS_MODE_DISABLED
	var hud := main.get_node_or_null("CombatHUD")
	if hud:
		hud.visible = false
	for c in main.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = 50.0
	main.add_child(cam)
	# Re-parent the outline quad onto our camera so outlines match the game.
	var outline := follow.find_child("Outlines", true, false) as Node3D
	if outline:
		outline.reparent(cam, false)
	cam.make_current()
	for f in 30:
		await process_frame
	for i in shots.size():
		var s: Array = shots[i]
		var car: Node3D = main.get_node("Train/" + str(s[0]))
		var eye: Vector3 = car.global_transform * (s[1] as Vector3)
		var at: Vector3 = car.global_transform * (s[2] as Vector3)
		cam.global_position = eye
		cam.look_at(at, Vector3.UP)
		for f in 20:
			await process_frame
		var img := root.get_texture().get_image()
		var path := "%s_%d.png" % [out, i]
		img.save_png(path)
		print("saved ", path)
	quit()
