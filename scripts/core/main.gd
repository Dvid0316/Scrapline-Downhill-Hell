extends Node3D
## Root of the playable scene: wires debug controls to the train and camera.
##
## Dev command-line options (pass after `--`):
##   --start-at=0.5        start the run at 50% of the route
##   --capture=PATH.png    save a screenshot after --capture-delay seconds, then quit
##   --capture-delay=3.0
##   --demo-fire           auto-aim at the nearest target and hold the trigger (screenshots/bench)
##   --bench=SECONDS       measure frame times, print a report, then quit (vsync off)

@export var train: TrainController
@export var camera: FollowCamera
@export var hud: CanvasLayer

@export_group("Combat (Milestone 2)")
@export var target_course: TargetCourse
@export var score: ScoreTracker
@export var weapon: HitscanWeapon
@export var turret_input: TurretInput
@export var combat_hud: CombatHud

@export_group("Debug tuning steps")
@export var speed_step: float = 2.0
@export var pitch_step: float = 1.0
@export var distance_step: float = 2.0
@export var look_ahead_step: float = 2.0

var _capture_path := ""
var _capture_delay := 3.0
var _elapsed := 0.0
var _bench_seconds := 0.0
var _bench_frames := PackedFloat32Array()
var _bench_gpu_ms := 0.0
var _bench_cpu_ms := 0.0


func _ready() -> void:
	get_tree().auto_accept_quit = false  # we quit via quit_cleanly()
	InputActions.register_defaults()
	train.run_restarted.connect(_on_run_restarted)
	if combat_hud and target_course:
		combat_hud.set_total_targets(target_course.targets.size())
	_parse_user_args()


## New run: targets come back, score and accuracy start over.
func _on_run_restarted() -> void:
	if target_course:
		target_course.reset_all()
	if score:
		score.reset()
	if weapon:
		weapon.reset_stats()


func _parse_user_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--start-at="):
			train.set_progress_ratio(arg.get_slice("=", 1).to_float())
			camera.snap()
		elif arg.begins_with("--capture="):
			_capture_path = arg.get_slice("=", 1)
		elif arg.begins_with("--capture-delay="):
			_capture_delay = arg.get_slice("=", 1).to_float()
		elif arg == "--demo-fire" and turret_input:
			turret_input.debug_auto_aim = true
			turret_input.debug_auto_fire = true
		elif arg.begins_with("--bench="):
			_bench_seconds = arg.get_slice("=", 1).to_float()
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	if _bench_seconds > 0.0:
		_bench_step(delta)
	if _capture_path == "":
		return
	_elapsed += delta
	if _elapsed >= _capture_delay:
		var img := get_viewport().get_texture().get_image()
		var abs_path := _capture_path
		if not abs_path.is_absolute_path():
			abs_path = ProjectSettings.globalize_path("res://").path_join(_capture_path)
		DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
		# Keep Godot from importing screenshots as project assets.
		var marker := abs_path.get_base_dir().path_join(".gdignore")
		if not FileAccess.file_exists(marker):
			FileAccess.open(marker, FileAccess.WRITE)
		var err := img.save_png(abs_path)
		print("capture: saved %s (err=%d)" % [abs_path, err])
		_capture_path = ""
		quit_cleanly()


func _bench_step(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 3.0:
		return  # warm-up: shader compilation, pools
	_bench_frames.append(delta)
	var vp := get_viewport().get_viewport_rid()
	_bench_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	_bench_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
	if _elapsed < 3.0 + _bench_seconds:
		return
	var sorted := _bench_frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in _bench_frames:
		total += f
	var n := sorted.size()
	var p99: float = sorted[int(n * 0.99) - 1]
	print("BENCH frames=%d  avg=%.1f fps (%.2f ms)  1%%-low=%.1f fps  worst=%.2f ms  res=%s  renderer=%s" % [
		n, n / total, total / n * 1000.0, 1.0 / p99, sorted[n - 1] * 1000.0,
		get_viewport().get_visible_rect().size, RenderingServer.get_video_adapter_name()])
	print("BENCH render cost per frame: GPU %.2f ms, CPU %.2f ms  (vsync-independent; 16.7 ms = 60 FPS budget)" % [
		_bench_gpu_ms / n, _bench_cpu_ms / n])
	print("BENCH shots=%d hits=%d destroyed=%d" % [
		weapon.shots_fired if weapon else 0, weapon.shots_hit if weapon else 0, score.destroyed if score else 0])
	_bench_seconds = 0.0
	quit_cleanly()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_cleanly()


## Stop audio and give the audio server a couple of frames to release its
## playbacks before quitting (avoids "leaked AudioStreamPlayback" at exit).
func quit_cleanly(exit_code: int = 0) -> void:
	if turret_input:
		turret_input.set_physics_process(false)
	if weapon:
		weapon.trigger_held = false
		weapon.set_physics_process(false)
	get_tree().call_group(&"audio_shutdown", &"stop_all")
	for i in 3:
		await get_tree().process_frame
	get_tree().call_group(&"audio_shutdown", &"stop_all")
	await get_tree().process_frame
	get_tree().quit(exit_code)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		# Frees the cursor. Clicking back into the window re-confines it (TurretInput).
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
