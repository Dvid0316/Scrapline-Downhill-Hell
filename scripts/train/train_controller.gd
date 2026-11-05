class_name TrainController
extends Node3D
## Moves a consist of [TrainCar] children along a [RailRoute].
##
## This is path following, not a physics simulation: the lead car's front
## sits at [member head_distance] metres along the route; every car behind is
## placed by sampling the curve at its two bogie pivots, which gives correct
## yaw on curves and pitch on grades for free.

signal run_restarted
signal run_finished

@export var route: RailRoute

@export_group("Speed")
## Speed the train accelerates/brakes toward, in m/s (14 m/s ≈ 50 km/h).
@export_range(0.0, 60.0, 0.5) var target_speed: float = 14.0
@export_range(1.0, 80.0, 0.5) var max_speed: float = 40.0
## m/s² used when changing speed. High values feel instant.
@export_range(0.1, 30.0) var acceleration: float = 5.0

@export_group("Consist")
@export var coupling_gap: float = 1.0
## Height of the rail top above the route centreline (see TrackBuilder).
@export var ride_height: float = 0.33
## Restart from the beginning when the end of the route is reached.
@export var loop_route: bool = true

var speed: float = 0.0
var head_distance: float = 0.0
var paused: bool = false
var cars: Array[TrainCar] = []


func _ready() -> void:
	for child in get_children():
		if child is TrainCar:
			cars.append(child)
	if route == null:
		push_error("TrainController: no route assigned")
		set_process(false)
		return
	restart()


func restart() -> void:
	head_distance = get_consist_length() + 2.0
	speed = target_speed
	_place_cars()
	run_restarted.emit()


func _process(delta: float) -> void:
	var goal := 0.0 if paused else clampf(target_speed, 0.0, max_speed)
	speed = move_toward(speed, goal, acceleration * delta)
	head_distance += speed * delta
	var end := route.get_length()
	if head_distance >= end:
		if loop_route:
			restart()
			return
		head_distance = end
		speed = 0.0
		run_finished.emit()
	_place_cars()


func _place_cars() -> void:
	var front := head_distance
	for car in cars:
		var centre := front - car.car_length * 0.5
		var pf := route.sample_world(centre + car.bogie_spacing * 0.5)
		var pr := route.sample_world(centre - car.bogie_spacing * 0.5)
		var dir := pf - pr
		if dir.length_squared() > 0.0001:
			var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
			var pos := (pf + pr) * 0.5 + basis.y * ride_height
			car.global_transform = Transform3D(basis, pos)
		front -= car.car_length + coupling_gap


func get_consist_length() -> float:
	var total := 0.0
	for car in cars:
		total += car.car_length
	return total + coupling_gap * maxf(cars.size() - 1, 0)


## Route offset of the middle of the whole train.
func get_centre_distance() -> float:
	return head_distance - get_consist_length() * 0.5


func get_route_length() -> float:
	return route.get_length() if route else 0.0


func get_progress_ratio() -> float:
	var l := get_route_length()
	return clampf(head_distance / l, 0.0, 1.0) if l > 0.0 else 0.0


func set_progress_ratio(ratio: float) -> void:
	head_distance = clampf(ratio, 0.0, 1.0) * get_route_length()
	head_distance = maxf(head_distance, get_consist_length() + 2.0)
	_place_cars()


func get_current_grade() -> float:
	return route.grade_percent(get_centre_distance()) if route else 0.0
