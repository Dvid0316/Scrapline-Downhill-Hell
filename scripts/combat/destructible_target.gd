class_name DestructibleTarget
extends Damageable
## A static target with visible damage reactions.
##
## Expected children:
##   Intact  (Node3D): visuals while alive
##   Wreck   (Node3D, optional): visuals after destruction
##   Body    (CollisionObject3D): hit box on the TARGETS layer
##
## Reaction: a short white flash plus a jolt on each hit, darker overlay as
## health drops, and on death the Intact visuals swap for the Wreck and the
## collider turns off. Nothing is freed, so [method reset] can restore it for
## the next run.

const FLASH_MATERIAL := preload("res://materials/fx_damage_flash.tres")
const SCORCH_MATERIAL := preload("res://materials/fx_scorched.tres")

@export var flash_time: float = 0.06
@export var jolt_distance: float = 0.06

var _intact: Node3D
var _wreck: Node3D
var _body: CollisionObject3D
var _meshes: Array[GeometryInstance3D] = []
var _flash_left: float = 0.0
var _intact_rest: Vector3
var _body_layer: int = 0


func _ready() -> void:
	super._ready()
	_intact = get_node_or_null(^"Intact")
	_wreck = get_node_or_null(^"Wreck")
	_body = get_node_or_null(^"Body")
	if _intact:
		_intact_rest = _intact.position
		for n in _intact.find_children("*", "GeometryInstance3D", true, false):
			_meshes.append(n)
	if _body:
		_body_layer = _body.collision_layer
	_on_reset()


func _on_damaged(_amount: float, _hit_point: Vector3, _hit_normal: Vector3) -> void:
	_flash_left = flash_time
	_set_overlay(FLASH_MATERIAL)
	set_process(true)


func _process(delta: float) -> void:
	_flash_left -= delta
	if _intact:
		var j := jolt_distance * clampf(_flash_left / flash_time, 0.0, 1.0)
		_intact.position = _intact_rest + Vector3(randf_range(-j, j), 0.0, randf_range(-j, j))
	if _flash_left <= 0.0:
		_set_overlay(SCORCH_MATERIAL if get_health_ratio() < 0.5 else null)
		if _intact:
			_intact.position = _intact_rest
		set_process(false)


func _on_destroyed(_source: Node) -> void:
	set_process(false)
	if _intact:
		_intact.visible = false
		_intact.position = _intact_rest
	if _wreck:
		_wreck.visible = true
	if _body:
		_body.collision_layer = 0


func _on_reset() -> void:
	_flash_left = 0.0
	set_process(false)
	_set_overlay(null)
	if _intact:
		_intact.visible = true
		_intact.position = _intact_rest
	if _wreck:
		_wreck.visible = false
	if _body:
		_body.collision_layer = _body_layer


func _set_overlay(mat: Material) -> void:
	for m in _meshes:
		m.material_overlay = mat


## World-space centre of the hit box (where effects spawn and aim helpers point).
func get_effect_origin() -> Vector3:
	if _body:
		for c in _body.get_children():
			if c is CollisionShape3D:
				return (c as Node3D).global_position
		return _body.global_position
	return global_position + Vector3.UP
