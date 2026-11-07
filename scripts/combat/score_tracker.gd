class_name ScoreTracker
extends Node
## Keeps score for the current run. Hears about kills through the
## "combat_listeners" group (see Damageable), so it scores anything that dies,
## including chain-reaction kills. Points are awarded once per destruction
## because Damageable only reports a death once.

signal score_changed(score: int, destroyed: int)

var score: int = 0
## Everything destroyed (range targets + enemies).
var destroyed: int = 0
## Enemies only (Milestone 3).
var enemy_kills: int = 0


func _ready() -> void:
	add_to_group(Damageable.LISTENER_GROUP)


func on_target_destroyed(target: Node, _source: Node) -> void:
	var pts: int = target.points if &"points" in target else 0
	score += pts
	destroyed += 1
	if target is EnemyBase:
		enemy_kills += 1
	score_changed.emit(score, destroyed)


func reset() -> void:
	score = 0
	destroyed = 0
	enemy_kills = 0
	score_changed.emit(score, destroyed)
