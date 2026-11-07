class_name TeslaCoil
extends Node3D
## Upgrade weapon: a Tesla coil on the locomotive roof. Every [member interval]
## seconds it arcs to the nearest enemy in range and the bolt jumps on to
## more enemies nearby ([member chain] in total). Fully automatic.
##
## Level 0 = not owned (hidden, idle). The UpgradeManager sets [member level].

signal zapped(points: PackedVector3Array, targets: Array)

@export var director: WaveDirector
@export var audio: CombatAudio
@export var reach: float = 34.0
@export var chain_reach: float = 15.0
@export var damage: float = 34.0

var level: int = 0: set = set_level
var interval: float = 1.1
var chain: int = 1
var zaps: int = 0

var _cd: float = 0.5
var _bolt: LightningBolt
var _ball: MeshInstance3D
var _light: OmniLight3D
var _t: float = 0.0
static var _mesh: ArrayMesh

const DARK := preload("res://materials/armor_dark.tres")
const STEEL := preload("res://materials/steel_worn.tres")
const RUST := preload("res://materials/rust.tres")
const HAZARD := preload("res://materials/hazard_yellow.tres")
const TOP := Vector3(0, 1.75, 0)


func _ready() -> void:
	if _mesh == null:
		_mesh = _build()
	var body := MeshInstance3D.new()
	body.name = "Coil"
	body.mesh = _mesh
	add_child(body)
	_ball = MeshInstance3D.new()
	_ball.name = "Ball"
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	sm.radial_segments = 12
	sm.rings = 6
	_ball.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.9, 1.0)
	gm.emission_enabled = true
	gm.emission = Color(0.4, 0.85, 1.0)
	gm.emission_energy_multiplier = 3.0
	gm.roughness = 1.0  # outline pass skips it
	_ball.material_override = gm
	_ball.position = TOP
	add_child(_ball)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.5, 0.85, 1.0)
	_light.omni_range = 9.0
	_light.light_energy = 0.0
	_light.position = TOP
	add_child(_light)
	_bolt = LightningBolt.new()
	_bolt.name = "Bolt"
	add_child(_bolt)
	set_level(level)


func set_level(v: int) -> void:
	level = v
	interval = maxf(1.1 - 0.2 * (v - 1), 0.5)
	chain = maxi(v, 1)
	visible = v > 0
	set_physics_process(v > 0)
	set_process(v > 0)


func _process(delta: float) -> void:
	_t += delta
	var s := 1.0 + 0.08 * sin(_t * 9.0) + (0.4 if _bolt.is_active() else 0.0)
	_ball.scale = Vector3.ONE * s
	_light.light_energy = move_toward(_light.light_energy, 0.4, delta * 30.0)


func _physics_process(delta: float) -> void:
	_cd -= delta
	if _cd > 0.0:
		return
	if zap():
		_cd = interval
	else:
		_cd = 0.15  # nothing in range: check again soon


## Fire one arc now if anything is in range. Returns true if it fired.
func zap() -> bool:
	if director == null or level <= 0:
		return false
	var origin := global_transform * TOP
	var targets: Array = []
	var points := PackedVector3Array([origin])
	var from := origin
	var limit := reach
	for i in chain:
		var best: EnemyBase = null
		var best_d := limit
		for e: EnemyBase in director.get_alive():
			if not e.active or e.is_destroyed or e in targets:
				continue
			var d := e.get_effect_origin().distance_to(from)
			if d < best_d:
				best_d = d
				best = e
		if best == null:
			break
		targets.append(best)
		from = best.get_effect_origin()
		points.append(from)
		limit = chain_reach
	if targets.is_empty():
		return false
	for i in targets.size():
		var e: EnemyBase = targets[i]
		e.apply_damage(damage, points[i + 1], (points[i] - points[i + 1]).normalized(), self)
	zaps += 1
	_bolt.strike(points)
	_light.light_energy = 8.0
	if audio:
		audio.play_zap(origin)
	zapped.emit(points, targets)
	return true


static func _build() -> ArrayMesh:
	var k := CarKit.new()
	# Base plinth bolted to the roof, with a hazard collar.
	k.boxp(DARK, Vector3(0.9, 0.18, 0.9), Vector3(0, 0.09, 0), Vector3.ZERO, 0.04)
	k.cylp(HAZARD, 0.36, 0.08, Vector3(0, 0.22, 0), Vector3.ZERO, 10)
	# Insulator stack.
	for i in 3:
		k.cyl(STEEL, 0.2, 0.26, 0.12, Transform3D(Basis.IDENTITY, Vector3(0, 0.33 + i * 0.13, 0)), 10)
	# The coil: copper windings around a dark core.
	k.cylp(DARK, 0.13, 0.9, Vector3(0, 1.0, 0), Vector3.ZERO, 8)
	for i in 7:
		k.cylp(RUST, 0.2, 0.06, Vector3(0, 0.66 + i * 0.1, 0), Vector3.ZERO, 10)
	# Toroid crown under the glowing ball.
	k.cyl(STEEL, 0.42, 0.42, 0.12, Transform3D(Basis.IDENTITY, Vector3(0, 1.48, 0)), 14)
	k.cyl(DARK, 0.3, 0.3, 0.16, Transform3D(Basis.IDENTITY, Vector3(0, 1.48, 0)), 12)
	# Three braced struts.
	for a in 3:
		var ang := TAU * a / 3.0
		var foot := Vector3(cos(ang) * 0.38, 0.2, sin(ang) * 0.38)
		var head := Vector3(cos(ang) * 0.12, 1.3, sin(ang) * 0.12)
		var mid := (foot + head) * 0.5
		var dir := (head - foot).normalized()
		var b := Basis(Quaternion(Vector3.UP, dir))
		k.cyl(STEEL, 0.03, 0.03, foot.distance_to(head), Transform3D(b, mid), 5)
	return k.commit()
