class_name PuffEmitter
extends CPUParticles3D
## Continuous stylized puff emitter, configured from a preset:
##   SMOKESTACK  - locomotive exhaust, dark puffs that trail behind the train
##   DUST        - tan dust kicked up behind a raider's wheels
##   WRECK_FIRE  - flames and black smoke pouring out of a burning wreck
## Emits in world space so the trail stays behind moving vehicles.

enum Preset { SMOKESTACK, DUST, WRECK_FIRE }

@export var preset: Preset = Preset.SMOKESTACK
@export var start_emitting: bool = true


func _ready() -> void:
	mesh = RockMeshes.puff()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	local_coords = false
	angle_max = 360.0
	particle_flag_rotate_y = true
	angular_velocity_min = -50.0
	angular_velocity_max = 50.0
	direction = Vector3.UP
	scale_amount_curve = PuffFx.grow_curve(0.2)
	match preset:
		Preset.SMOKESTACK:
			amount = 20
			lifetime = 1.5
			_set_ramp(PuffFx.ramp([
				[0.0, Color(0.16, 0.14, 0.14, 0.0)],
				[1.0, Color(0.55, 0.53, 0.52, 0.0)]]))
			scale_amount_min = 0.22
			scale_amount_max = 0.45
			spread = 12.0
			initial_velocity_min = 5.0
			initial_velocity_max = 7.0
			gravity = Vector3(0, 1.0, 0)
			damping_min = 2.0
			damping_max = 3.0
			scale_amount_curve = _curve([Vector2(0, 0.3), Vector2(0.25, 1.0), Vector2(0.75, 1.4), Vector2(1, 0)])
		Preset.DUST:
			amount = 22
			lifetime = 1.4
			_set_ramp(PuffFx.ramp([
				[0.0, Color(0.62, 0.48, 0.32, 0.0)],
				[1.0, Color(0.78, 0.66, 0.5, 0.0)]]))
			emission_shape = EMISSION_SHAPE_BOX
			emission_box_extents = Vector3(1.0, 0.1, 0.3)
			scale_amount_min = 0.3
			scale_amount_max = 0.75
			spread = 40.0
			initial_velocity_min = 1.0
			initial_velocity_max = 2.5
			gravity = Vector3(0, 0.6, 0)
			damping_min = 1.0
			damping_max = 2.0
			scale_amount_curve = _curve([Vector2(0, 0.3), Vector2(0.3, 1.0), Vector2(0.7, 1.3), Vector2(1, 0)])
		Preset.WRECK_FIRE:
			amount = 26
			lifetime = 1.6
			_set_ramp(PuffFx.ramp([
				[0.0, Color(1.0, 0.85, 0.35, 1.0)],
				[0.18, Color(1.0, 0.4, 0.08, 0.8)],
				[0.38, Color(0.25, 0.12, 0.08, 0.05)],
				[1.0, Color(0.14, 0.13, 0.13, 0.0)]]))
			emission_shape = EMISSION_SHAPE_SPHERE
			emission_sphere_radius = 0.6
			scale_amount_min = 0.4
			scale_amount_max = 0.9
			spread = 15.0
			initial_velocity_min = 2.5
			initial_velocity_max = 4.5
			gravity = Vector3(0, 2.0, 0)
			damping_min = 1.0
			damping_max = 2.0
	emitting = start_emitting


func _set_ramp(g: Gradient) -> void:
	material_override = PuffFx.material(g)


func _curve(pts: Array) -> Curve:
	var c := Curve.new()
	c.max_value = 2.0
	for p: Vector2 in pts:
		c.add_point(p)
	return c
