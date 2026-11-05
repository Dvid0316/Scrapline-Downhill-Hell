extends Node3D
## Root of the playable scene: wires debug controls to the train and camera.
##
## Dev command-line options (pass after `--`):
##   --start-at=0.5        start the run at 50% of the route
##   --capture=PATH.png    save a screenshot after --capture-delay seconds, then quit
##   --capture-delay=3.0

@export var train: TrainController
@export var camera: FollowCamera
@export var hud: CanvasLayer

@export_group("Debug tuning steps")
@export var speed_step: float = 2.0
@export var pitch_step: float = 1.0
@export var distance_step: float = 2.0
@export var look_ahead_step: float = 2.0

var _capture_path := ""
var _capture_delay := 3.0
var _elapsed := 0.0


func _ready() -> void:
	InputActions.register_defaults()
	_parse_user_args()


func _parse_user_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--start-at="):
			train.set_progress_ratio(arg.get_slice("=", 1).to_float())
			camera.snap()
		elif arg.begins_with("--capture="):
			_capture_path = arg.get_slice("=", 1)
		elif arg.begins_with("--capture-delay="):
			_capture_delay = arg.get_slice("=", 1).to_float()


func _process(delta: float) -> void:
	if _capture_path == "":
		return
	_elapsed += delta
	if _elapsed >= _capture_delay:
		var img := get_viewport().get_texture().get_image()
		var abs_path := _capture_path
		if not abs_path.is_absolute_path():
			abs_path = ProjectSettings.globalize_path("res://").path_join(_capture_path)
		DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		var err := img.save_png(abs_path)
		print("capture: saved %s (err=%d)" % [abs_path, err])
		_capture_path = ""
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		# Milestone 1 never captures the mouse, but keep Esc as the universal
		# "give me my cursor back" key for later milestones.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("speed_up", true):
		train.target_speed = clampf(train.target_speed + speed_step, 0.0, train.max_speed)
	elif event.is_action_pressed("speed_down", true):
		train.target_speed = clampf(train.target_speed - speed_step, 0.0, train.max_speed)
	elif event.is_action_pressed("toggle_pause"):
		train.paused = not train.paused
	elif event.is_action_pressed("restart_run"):
		train.restart()
	elif event.is_action_pressed("toggle_debug"):
		hud.visible = not hud.visible
	elif event.is_action_pressed("cam_pitch_up", true):
		camera.pitch_degrees += pitch_step
	elif event.is_action_pressed("cam_pitch_down", true):
		camera.pitch_degrees -= pitch_step
	elif event.is_action_pressed("cam_zoom_in", true):
		camera.distance -= distance_step
	elif event.is_action_pressed("cam_zoom_out", true):
		camera.distance += distance_step
	elif event.is_action_pressed("cam_look_ahead_more", true):
		camera.look_ahead = clampf(camera.look_ahead + look_ahead_step, 0.0, 60.0)
	elif event.is_action_pressed("cam_look_ahead_less", true):
		camera.look_ahead = clampf(camera.look_ahead - look_ahead_step, 0.0, 60.0)
	elif event.is_action_pressed("cam_reset"):
		camera.reset_framing()
