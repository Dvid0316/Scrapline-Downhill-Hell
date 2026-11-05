class_name ExplosiveBarrel
extends DestructibleTarget
## Blows up when destroyed and damages nearby Damageables (other barrels too,
## so you get chain reactions). The small delay staggers chains for effect.

@export var blast_radius: float = 8.0
@export var blast_damage: float = 150.0
@export var chain_delay: float = 0.12

## Bumped on reset so a pending blast from a previous run is ignored.
var _generation: int = 0


func _on_destroyed(source: Node) -> void:
	super._on_destroyed(source)
	var gen := _generation
	if chain_delay <= 0.0 or not is_inside_tree():
		_blast()
		return
	get_tree().create_timer(chain_delay, false).timeout.connect(func() -> void:
		if gen == _generation:
			_blast())


func _blast() -> void:
	if is_inside_tree():
		Damageable.damage_area(get_tree(), get_effect_origin(), blast_radius, blast_damage, self, self)


func _on_reset() -> void:
	_generation += 1
	super._on_reset()
