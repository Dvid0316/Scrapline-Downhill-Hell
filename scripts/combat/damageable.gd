class_name Damageable
extends Node3D
## Base class for anything that can take damage: range targets now, enemy
## vehicles later. Weapons don't know concrete types. They walk up from the
## collider they hit to the first node with apply_damage() (see [method find_in]).
##
## On destruction, every node in the "combat_listeners" group receives
## on_target_destroyed(target, source). That's how scoring, effects, and HUD
## react, without the target knowing about any of them.

signal damaged(amount: float, hit_point: Vector3)
signal destroyed(source: Node)

const GROUP := &"damageable"
const LISTENER_GROUP := &"combat_listeners"

@export var max_health: float = 100.0
@export var points: int = 100
@export var display_name: String = "TARGET"
## Picks impact sparks/sound: &"metal", &"wood" or &"dirt".
@export var surface: StringName = &"metal"
## Destruction look: &"explosion" (fireball) or &"debris" (just bits).
@export var destroy_effect: StringName = &"explosion"
@export_range(0.1, 4.0) var explosion_scale: float = 1.0

var health: float
var is_destroyed: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	health = max_health


## Returns true if this hit destroyed the target.
func apply_damage(amount: float, hit_point: Vector3, hit_normal: Vector3 = Vector3.UP, source: Node = null) -> bool:
	if is_destroyed or amount <= 0.0:
		return false
	health = maxf(health - amount, 0.0)
	_on_damaged(amount, hit_point, hit_normal)
	damaged.emit(amount, hit_point)
	if health <= 0.0:
		is_destroyed = true
		_on_destroyed(source)
		destroyed.emit(source)
		if is_inside_tree():
			get_tree().call_group(LISTENER_GROUP, &"on_target_destroyed", self, source)
		return true
	return false


func reset() -> void:
	health = max_health
	is_destroyed = false
	_on_reset()


func get_health_ratio() -> float:
	return health / max_health if max_health > 0.0 else 0.0


## Override points for subclasses.
func _on_damaged(_amount: float, _hit_point: Vector3, _hit_normal: Vector3) -> void:
	pass


func _on_destroyed(_source: Node) -> void:
	pass


func _on_reset() -> void:
	pass


## Walks up from [param node] (usually a collider) to the owning damage receiver.
static func find_in(node: Node) -> Node:
	var n := node
	var depth := 0
	while n != null and depth < 6:
		if n.has_method(&"apply_damage"):
			return n
		n = n.get_parent()
		depth += 1
	return null


## Damages every Damageable within [param radius] (linear falloff to 35% at the edge).
static func damage_area(tree: SceneTree, center: Vector3, radius: float, damage: float, source: Node, exclude: Node = null) -> int:
	var count := 0
	for node in tree.get_nodes_in_group(GROUP):
		var d := node as Damageable
		if d == null or d == exclude or d.is_destroyed:
			continue
		var dist := d.global_position.distance_to(center)
		if dist > radius:
			continue
		var falloff := lerpf(1.0, 0.35, dist / radius)
		var dir := (d.global_position - center).normalized()
		d.apply_damage(damage * falloff, d.global_position + Vector3.UP * 0.5, -dir, source)
		count += 1
	return count
