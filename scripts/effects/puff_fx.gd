class_name PuffFx
extends RefCounted
## Builders for stylized "puff" particle systems: chunky low-poly balls that
## grow, change colour through a gradient (hot fire -> cold smoke) and shrink
## away. Used for explosions, locomotive exhaust, dust trails and wreck fires.

const SHADER := preload("res://shaders/stylized_puff.gdshader")

## A puff material whose colour follows [param colors] over each particle's life.
static func material(colors: Gradient) -> ShaderMaterial:
	var tex := GradientTexture1D.new()
	tex.gradient = colors
	tex.width = 64
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"ramp", tex)
	return m


## Gradient stops: [offset, Color(r, g, b, heat)], ...
static func ramp(stops: Array) -> Gradient:
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	var g := Gradient.new()
	g.colors = cols
	g.offsets = offs
	return g


## Scale over life: pop up fast, hold, shrink to nothing.
static func grow_curve(peak_at: float = 0.15) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.25))
	c.add_point(Vector2(peak_at, 1.0))
	c.add_point(Vector2(0.7, 0.85))
	c.add_point(Vector2(1.0, 0.0))
	return c


static func make(n: String, colors: Gradient, amount: int, lifetime: float, size: Vector2) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = n
	p.mesh = RockMeshes.puff()
	p.material_override = material(colors)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	p.scale_amount_curve = grow_curve()
	p.angle_max = 360.0
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.direction = Vector3.UP
	return p


## Fire -> smoke explosion palette.
static func fire_ramp() -> Gradient:
	return ramp([
		[0.0, Color(1.0, 0.95, 0.7, 1.0)],
		[0.12, Color(1.0, 0.72, 0.15, 0.95)],
		[0.3, Color(0.98, 0.32, 0.06, 0.7)],
		[0.5, Color(0.35, 0.16, 0.1, 0.1)],
		[1.0, Color(0.22, 0.2, 0.2, 0.0)]])


static func smoke_ramp(c: Color) -> Gradient:
	return ramp([[0.0, Color(c, 0.0)], [1.0, Color(c.lightened(0.3), 0.0)]])
