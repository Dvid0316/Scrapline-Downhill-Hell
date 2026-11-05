class_name InputActions
extends RefCounted
## Registers default input actions at startup. Defined in code so bindings
## are readable in one place; actions already present in Project Settings
## (Input Map) are left untouched, so the editor can override any of them.

const KEYS := {
	"speed_up": [KEY_UP, KEY_W, KEY_EQUAL, KEY_KP_ADD],
	"speed_down": [KEY_DOWN, KEY_S, KEY_MINUS, KEY_KP_SUBTRACT],
	"toggle_pause": [KEY_SPACE],
	"restart_run": [KEY_R],
	"toggle_debug": [KEY_F1],
	"cam_pitch_up": [KEY_BRACKETRIGHT],
	"cam_pitch_down": [KEY_BRACKETLEFT],
	"cam_zoom_in": [KEY_PERIOD],
	"cam_zoom_out": [KEY_COMMA],
	"cam_look_ahead_more": [KEY_APOSTROPHE],
	"cam_look_ahead_less": [KEY_SEMICOLON],
	"cam_reset": [KEY_HOME],
	"release_mouse": [KEY_ESCAPE],
	"fire": [],
}

const MOUSE := {
	"fire": [MOUSE_BUTTON_LEFT],
	"cam_zoom_in": [MOUSE_BUTTON_WHEEL_UP],
	"cam_zoom_out": [MOUSE_BUTTON_WHEEL_DOWN],
}


static func register_defaults() -> void:
	for action: String in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		for button: MouseButton in MOUSE.get(action, []):
			var mb := InputEventMouseButton.new()
			mb.button_index = button
			InputMap.action_add_event(action, mb)
