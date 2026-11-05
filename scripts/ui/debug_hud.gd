extends CanvasLayer
## Minimal text overlay with train/camera state and the debug key list. F1 toggles.

@export var train: TrainController
@export var camera: FollowCamera

@onready var _stats: Label = %Stats
@onready var _help: Label = %Help

const HELP := """W/S or Up/Down  speed ±
Space  pause    R  restart run
[ ]  camera pitch    , .  or wheel  distance
; '  look-ahead    Home  reset camera
F1  hide this    Esc  release mouse"""


func _ready() -> void:
	_help.text = HELP


func _process(_delta: float) -> void:
	if not visible or train == null:
		return
	var lines := PackedStringArray()
	lines.append("SPEED     %5.1f m/s  (%3.0f km/h)   target %4.1f%s" % [
		train.speed, train.speed * 3.6, train.target_speed, "  [PAUSED]" if train.paused else ""])
	lines.append("PROGRESS  %6.1f / %.0f m   %5.1f %%" % [
		train.head_distance, train.get_route_length(), train.get_progress_ratio() * 100.0])
	lines.append("GRADE     %+5.1f %%" % train.get_current_grade())
	if camera:
		lines.append("CAMERA    pitch %.0f°  dist %.0f m  height %.1f m  ahead %.0f m" % [
			camera.pitch_degrees, camera.distance, camera.get_height(), camera.look_ahead])
	lines.append("FPS       %d" % Engine.get_frames_per_second())
	_stats.text = "\n".join(lines)
