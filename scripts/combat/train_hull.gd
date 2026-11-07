class_name TrainHull
extends Node
## The player train's health. Enemy rounds and kamikaze blasts call
## [method apply_hit]; when the hull reaches zero the run is over.
##
## It's deliberately separate from [Damageable]: the train isn't a target,
## isn't scored, and player shots never reach it (TRAIN layer). It lives in
## the "train_hull" group so enemies can find it without a scene path.

signal hull_changed(hull: float, max_hull: float)
signal hit_taken(amount: float, point: Vector3)
signal wrecked

const GROUP := &"train_hull"

@export var train: TrainController
@export var max_hull: float = 400.0
## Dev/testing: hits are still reported but don't reduce the hull.
@export var invulnerable: bool = false
## Incoming damage is multiplied by this (armour upgrades lower it).
@export_range(0.05, 2.0) var damage_mult: float = 1.0

var hull: float
var is_wrecked: bool = false
## Stats for the current run.
var damage_taken: float = 0.0
var hits_taken: int = 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)
	reset()


func reset() -> void:
	hull = max_hull
	is_wrecked = false
	damage_taken = 0.0
	hits_taken = 0
	hull_changed.emit(hull, max_hull)


func apply_hit(amount: float, point: Vector3) -> void:
	if is_wrecked or amount <= 0.0:
		return
	amount *= damage_mult
	hits_taken += 1
	damage_taken += amount
	if not invulnerable:
		hull = maxf(hull - amount, 0.0)
	hit_taken.emit(amount, point)
	hull_changed.emit(hull, max_hull)
	if hull <= 0.0:
		is_wrecked = true
		wrecked.emit()


## Change the maximum, keeping the current hull; [param heal] is added on top.
func set_max_hull(value: float, heal: float = 0.0) -> void:
	max_hull = maxf(value, 1.0)
	hull = clampf(hull + heal, 0.0, max_hull)
	hull_changed.emit(hull, max_hull)


## Patch the hull up by a fraction of max (between waves).
func repair_fraction(fraction: float) -> void:
	if is_wrecked:
		return
	hull = minf(hull + max_hull * fraction, max_hull)
	hull_changed.emit(hull, max_hull)


func get_ratio() -> float:
	return hull / max_hull if max_hull > 0.0 else 0.0


## A random point on the outside of one of the cars, for enemies to shoot at.
func get_aim_point(rng: RandomNumberGenerator = null) -> Vector3:
	var r := rng if rng else _rng
	var car := _pick_car(r)
	if car == null:
		return Vector3.ZERO
	var half := car.car_length * 0.5 * 0.8
	return car.global_transform * Vector3(r.randf_range(-1.1, 1.1), r.randf_range(1.0, 2.6), r.randf_range(-half, half))


## Centre of the armored railcar (where the gun crew is): kamikaze dive target.
func get_core_point() -> Vector3:
	if train == null or train.cars.is_empty():
		return Vector3.ZERO
	var car: TrainCar = train.cars[train.cars.size() - 1]
	return car.global_transform * Vector3(0.0, 1.8, 0.0)


func _pick_car(r: RandomNumberGenerator) -> TrainCar:
	if train == null or train.cars.is_empty():
		return null
	return train.cars[r.randi() % train.cars.size()]
