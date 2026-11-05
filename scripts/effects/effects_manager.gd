class_name EffectsManager
extends Node3D
## Pooled world-space combat effects: tracers, impact sparks/dust/splinters,
## explosions. Every node is created once in _ready and recycled, so firing
## spawns no new scene nodes. When a pool is exhausted, the oldest slot is
## reused (effects are short enough that nobody notices).

@export_group("Pool sizes")
@export_range(4, 128) var tracer_pool: int = 24
@export_range(2, 64) var impact_pool: int = 14
@export_range(1, 16) var explosion_pool: int = 5

@export_group("Tracers")
@export var tracer_speed: float = 520.0
@export var tracer_length: float = 7.0
@export var tracer_width: float = 0.07

@export_group("Explosions")
@export var explosion_base_radius: float = 2.6
@export var explosion_duration: float = 0.55

const SPARK_MAT := preload("res://materials/fx_spark.tres")
const TRACER_MAT := preload("res://materials/fx_tracer.tres")
const DEBRIS_MAT := preload("res://materials/fx_debris.tres")
const DUST_MAT := preload("res://materials/fx_dust.tres")
const SPLINTER_MAT := preload("res://materials/sleeper_wood.tres")
const SMOKE_MAT := preload("res://materials/fx_smoke.tres")

# Tracer slot arrays (parallel, no per-shot allocation).
var _tracers: Array[MeshInstance3D] = []
var _tr_from: PackedVector3Array
var _tr_dir: PackedVector3Array
var _tr_total: PackedFloat32Array
var _tr_travel: PackedFloat32Array
var _tr_next := 0

var _sparks: Array[CPUParticles3D] = []
var _dust: Array[CPUParticles3D] = []
var _splinters: Array[CPUParticles3D] = []
var _impact_next := 0

class Blast:
	var root: Node3D
	var ball: MeshInstance3D
	var ball_mat: StandardMaterial3D
	var light: OmniLight3D
	var fire: CPUParticles3D
	var debris: CPUParticles3D
	var smoke: CPUParticles3D
	var age: float = 99.0
	var radius: float = 1.0

var _blasts: Array[Blast] = []
var _blast_next := 0


func _ready() -> void:
	_build_tracers()
	for i in impact_pool:
		_sparks.append(_make_burst("Sparks%d" % i, SPARK_MAT, _small_box(0.05), 14, 0.32, Vector2(7, 16), 22.0, 40.0))
		_dust.append(_make_burst("Dust%d" % i, DUST_MAT, _small_sphere(0.22), 6, 0.6, Vector2(1.5, 4), 4.0, 55.0))
		_splinters.append(_make_burst("Splinters%d" % i, SPLINTER_MAT, _small_box(0.09), 8, 0.6, Vector2(3, 8), 16.0, 60.0))
	for i in explosion_pool:
		_blasts.append(_make_blast(i))


# ------------------------------------------------------------------ tracers

func _build_tracers() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(tracer_width, tracer_width, 1.0)
	_tr_from.resize(tracer_pool)
	_tr_dir.resize(tracer_pool)
	_tr_total.resize(tracer_pool)
	_tr_travel.resize(tracer_pool)
	for i in tracer_pool:
		var mi := MeshInstance3D.new()
		mi.name = "Tracer%d" % i
		mi.mesh = mesh
		mi.material_override = TRACER_MAT
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mi.top_level = true
		add_child(mi)
		_tracers.append(mi)
		_tr_total[i] = 0.0
		_tr_travel[i] = 0.0


func spawn_tracer(from: Vector3, to: Vector3) -> void:
	var i := _tr_next
	_tr_next = (_tr_next + 1) % tracer_pool
	var v := to - from
	_tr_from[i] = from
	_tr_total[i] = v.length()
	_tr_dir[i] = v / maxf(_tr_total[i], 0.001)
	_tr_travel[i] = 0.0
	_tracers[i].visible = true
	_update_tracer(i)


func _process(delta: float) -> void:
	for i in tracer_pool:
		if not _tracers[i].visible:
			continue
		_tr_travel[i] += tracer_speed * delta
		if _tr_travel[i] - tracer_length >= _tr_total[i]:
			_tracers[i].visible = false
		else:
			_update_tracer(i)
	for b in _blasts:
		if b.age < 5.0:
			_update_blast(b, delta)


func _update_tracer(i: int) -> void:
	var head := minf(_tr_travel[i], _tr_total[i])
	var tail := maxf(_tr_travel[i] - tracer_length, 0.0)
	var seg_len := maxf(head - tail, 0.05)
	var dir: Vector3 = _tr_dir[i]
	var mid: Vector3 = _tr_from[i] + dir * ((head + tail) * 0.5)
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1.0, 1.0, seg_len))
	_tracers[i].global_transform = Transform3D(basis, mid)


# ------------------------------------------------------------------ impacts

func spawn_impact(point: Vector3, normal: Vector3, surface: StringName) -> void:
	var i := _impact_next
	_impact_next = (_impact_next + 1) % impact_pool
	match surface:
		&"metal":
			_fire_burst(_sparks[i], point, normal)
		&"wood":
			_fire_burst(_splinters[i], point, normal)
			_fire_burst(_sparks[i], point, normal)
		_:
			_fire_burst(_dust[i], point, normal)


func _fire_burst(p: CPUParticles3D, point: Vector3, normal: Vector3) -> void:
	var n := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	var side := Vector3.RIGHT if absf(n.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := side.cross(n).normalized()
	var z := x.cross(n).normalized()
	p.global_transform = Transform3D(Basis(x, n, z), point + n * 0.05)
	p.restart()


# ------------------------------------------------------------------ explosions

## [param size] scales radius; 1.0 ≈ a crate-to-barrel sized blast.
func spawn_explosion(center: Vector3, size: float = 1.0, fireball: bool = true) -> void:
	var b := _blasts[_blast_next]
	_blast_next = (_blast_next + 1) % explosion_pool
	b.root.global_position = center
	b.radius = explosion_base_radius * size
	b.age = 0.0
	b.ball.visible = fireball
	b.light.visible = fireball
	b.debris.scale_amount_min = 0.6 * size
	b.debris.scale_amount_max = 1.6 * size
	b.debris.initial_velocity_max = 9.0 + 5.0 * size
	b.debris.restart()
	if fireball:
		b.fire.restart()
		b.smoke.restart()
	_update_blast(b, 0.0)


func _update_blast(b: Blast, delta: float) -> void:
	b.age += delta
	var t := b.age / explosion_duration
	if t >= 1.0:
		b.ball.visible = false
		b.light.light_energy = 0.0
		if b.age > 4.0:
			b.age = 99.0
		return
	var grow := 1.0 - pow(1.0 - t, 3.0)
	var r := b.radius * (0.35 + 0.65 * grow)
	b.ball.scale = Vector3(r, r * 0.85, r)
	var a := (1.0 - t) * (1.0 - t)
	b.ball_mat.albedo_color.a = a
	b.ball_mat.emission_energy_multiplier = 6.0 * a + 0.5
	b.light.light_energy = 14.0 * a
	b.light.omni_range = b.radius * 4.0


func _make_blast(i: int) -> Blast:
	var b := Blast.new()
	b.root = Node3D.new()
	b.root.name = "Blast%d" % i
	b.root.top_level = true
	add_child(b.root)
	b.ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	b.ball.mesh = sm
	b.ball_mat = StandardMaterial3D.new()
	b.ball_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.ball_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b.ball_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	b.ball_mat.albedo_color = Color(1.0, 0.55, 0.15, 1.0)
	b.ball_mat.emission_enabled = true
	b.ball_mat.emission = Color(1.0, 0.45, 0.1)
	b.ball.material_override = b.ball_mat
	b.ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.ball.visible = false
	b.root.add_child(b.ball)
	b.light = OmniLight3D.new()
	b.light.light_color = Color(1.0, 0.6, 0.25)
	b.light.light_energy = 0.0
	b.light.shadow_enabled = false
	b.root.add_child(b.light)
	b.fire = _make_burst("Fire", SPARK_MAT, _small_box(0.12), 26, 0.55, Vector2(6, 15), 9.0, 80.0)
	b.debris = _make_burst("Debris", DEBRIS_MAT, _small_box(0.25), 16, 1.3, Vector2(5, 12), 18.0, 70.0)
	b.smoke = _make_burst("Smoke", SMOKE_MAT, _small_sphere(0.9), 10, 2.2, Vector2(1, 3.5), -1.5, 60.0)
	b.smoke.scale_amount_min = 1.0
	b.smoke.scale_amount_max = 2.6
	for p: CPUParticles3D in [b.fire, b.debris, b.smoke]:
		remove_child(p)
		p.top_level = false
		b.root.add_child(p)
	return b


# ------------------------------------------------------------------ builders

func _make_burst(n: String, mat: Material, mesh: Mesh, amount: int, lifetime: float,
		speed: Vector2, gravity: float, spread: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = n
	p.top_level = true
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.mesh = mesh
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0, -gravity, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.angle_max = 360.0
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = fade
	add_child(p)
	return p


func _small_box(s: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(s, s, s * 1.6)
	return m


func _small_sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m
