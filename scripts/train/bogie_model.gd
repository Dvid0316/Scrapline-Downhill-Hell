class_name BogieModel
extends Node3D
## Procedural two-axle bogie: cast side frames, axle boxes, coil springs,
## bolster, brake shoes, and two wheelsets that spin with the train's speed.
## Origin is the pivot, y = 0 at rail top, front is -Z.

const DARK := preload("res://materials/armor_dark.tres")
const STEEL := preload("res://materials/steel_worn.tres")
const RUST := preload("res://materials/rust.tres")
const HAZARD := preload("res://materials/hazard_yellow.tres")

const WHEEL_R := 0.46
const GAUGE_X := 0.75
const AXLE_Z := 1.0

static var _frame_mesh: ArrayMesh
static var _wheelset_mesh: ArrayMesh

var _wheelsets: Array[Node3D] = []
var _train: TrainController
var _angle: float = 0.0


func _ready() -> void:
	if _frame_mesh == null:
		_frame_mesh = _build_frame()
		_wheelset_mesh = _build_wheelset()
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	frame.mesh = _frame_mesh
	add_child(frame)
	for z in [-AXLE_Z, AXLE_Z]:
		var w := MeshInstance3D.new()
		w.name = "Wheelset"
		w.mesh = _wheelset_mesh
		w.position = Vector3(0, WHEEL_R, z)
		add_child(w)
		_wheelsets.append(w)
	var n := get_parent()
	while n and not (n is TrainController):
		n = n.get_parent()
	_train = n as TrainController
	set_process(_train != null)


func _process(delta: float) -> void:
	_angle = wrapf(_angle - _train.speed * delta / WHEEL_R, -TAU, TAU)
	for w in _wheelsets:
		w.rotation.x = _angle


static func _build_frame() -> ArrayMesh:
	var k := CarKit.new()
	# Side frames: a cast truss shape seen from the side, extruded across X.
	var prof := PackedVector2Array([
		Vector2(-1.65, 0.52), Vector2(-1.25, 0.3), Vector2(1.25, 0.3),
		Vector2(1.65, 0.52), Vector2(1.35, 0.74), Vector2(-1.35, 0.74)])
	for s in [-1.0, 1.0]:
		# Profile x -> world z (rotate 90° about Y), extrude along world x.
		var xf := Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(s * 0.97, 0, 0))
		k.extrude(DARK, prof, -0.08, 0.08, xf)
		# Axle boxes
		for z in [-AXLE_Z, AXLE_Z]:
			k.boxp(DARK, Vector3(0.24, 0.36, 0.42), Vector3(s * 1.04, WHEEL_R, z), Vector3.ZERO, 0.05)
			k.cylp(STEEL, 0.1, 0.08, Vector3(s * 1.18, WHEEL_R, z), Vector3(0, 0, 90), 8)
		# Coil spring stack at the centre, in rust.
		for i in 3:
			k.cylp(RUST, 0.15, 0.07, Vector3(s * 0.97, 0.8 + i * 0.09, -0.22), Vector3.ZERO, 8)
			k.cylp(RUST, 0.15, 0.07, Vector3(s * 0.97, 0.8 + i * 0.09, 0.22), Vector3.ZERO, 8)
		# Brake shoes ahead of / behind each wheel.
		for z in [-AXLE_Z - 0.5, AXLE_Z + 0.5]:
			k.boxp(STEEL, Vector3(0.12, 0.3, 0.12), Vector3(s * GAUGE_X, WHEEL_R + 0.05, z), Vector3.ZERO, 0.03)
		# Yellow inspection tab on the side frame.
		k.boxp(HAZARD, Vector3(0.03, 0.12, 0.5), Vector3(s * 1.055, 0.56, 0), Vector3.ZERO, 0.0)
	# Bolster across the middle + pivot plate.
	k.boxp(DARK, Vector3(1.8, 0.28, 0.6), Vector3(0, 0.92, 0), Vector3.ZERO, 0.05)
	k.cylp(STEEL, 0.4, 0.12, Vector3(0, 1.1, 0), Vector3.ZERO, 12)
	# Transoms tying the frames together.
	for z in [-0.75, 0.75]:
		k.boxp(DARK, Vector3(1.8, 0.16, 0.16), Vector3(0, 0.66, z), Vector3.ZERO, 0.03)
	return k.commit()


static func _build_wheelset() -> ArrayMesh:
	var k := CarKit.new()
	var rz := Basis(Vector3.BACK, PI / 2.0)  # cylinder Y axis -> X
	k.cyl(STEEL, 0.08, 0.08, 1.9, Transform3D(rz, Vector3.ZERO), 8)
	for s in [-1.0, 1.0]:
		var x: float = s * GAUGE_X
		# Tread + flange (flange on the inner side) + web + hub.
		k.cyl(STEEL, WHEEL_R, WHEEL_R, 0.13, Transform3D(rz, Vector3(x, 0, 0)), 18)
		k.cyl(DARK, WHEEL_R + 0.05, WHEEL_R + 0.05, 0.04, Transform3D(rz, Vector3(x - s * 0.08, 0, 0)), 18)
		k.cyl(DARK, WHEEL_R * 0.78, WHEEL_R * 0.78, 0.15, Transform3D(rz, Vector3(x + s * 0.01, 0, 0)), 18)
		k.cyl(STEEL, 0.13, 0.13, 0.22, Transform3D(rz, Vector3(x + s * 0.06, 0, 0)), 10)
		# Ribs on the outer face so the spin reads.
		for i in 5:
			var a := TAU * i / 5.0
			var b := Basis(Vector3.RIGHT, a)
			k.box(RUST, Vector3(0.04, 0.27, 0.07), Transform3D(b, Vector3(x + s * 0.075, 0, 0) + b * Vector3(0, 0.22, 0)), 0.01)
	return k.commit()
