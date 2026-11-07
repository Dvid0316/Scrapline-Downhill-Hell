class_name HitscanWeapon
extends Node
## Rapid-fire hitscan gun logic. Fires along the turret's barrel and applies
## damage to whatever Damageable owns the collider it hits.
##
## Deliberately knows nothing about effects, audio, HUD, or camera. It only
## emits [signal shot_fired] and [signal shot_impact]. Anything (player input
## or, later, an AI) drives it by setting [member trigger_held].
##
## Fire rate is frame-rate independent: a cooldown accumulator can fire
## several rounds in one long frame, and the first round on trigger-press is
## immediate (unless the gun is still cooling from the previous shot).

signal shot_fired(origin: Vector3, direction: Vector3, end_point: Vector3, is_tracer: bool)
signal shot_impact(point: Vector3, normal: Vector3, surface: StringName, target: Node, killed: bool)
## Explosive rounds only: the round burst at [param point].
signal splashed(point: Vector3, radius: float)
## Ricochet upgrade: a round bounced from [param from] into another enemy.
signal ricocheted(from: Vector3, to: Vector3, target: Node, killed: bool)

@export var turret: MountedTurret
## Which of the turret's barrels this gun fires from: &"mg" or &"cannon".
@export var muzzle_slot: StringName = &"mg"

@export_group("Ballistics")
@export_range(1.0, 40.0) var fire_rate: float = 11.0  ## rounds per second
@export var damage: float = 12.0
@export var max_range: float = 320.0
@export_range(0.0, 5.0) var spread_degrees: float = 0.6
## Every Nth round is a visible tracer (1 = all).
@export_range(1, 10) var tracer_every: int = 2
@export_flags_3d_physics var collision_mask: int = PhysicsLayers.PLAYER_SHOT_MASK

@export_group("Explosive rounds")
## 0 = ordinary bullets. Above 0, every round that hits something bursts and
## damages all Damageables in this radius (falling off toward the edge).
## The thing it hit directly takes [member damage] only, not the splash too.
@export var splash_radius: float = 0.0
@export var splash_damage: float = 0.0

@export_group("Ricochet")
## Each round that hits an enemy bounces on to this many more nearby enemies.
@export_range(0, 5) var ricochet_bounces: int = 0
@export var ricochet_range: float = 16.0
@export_range(0.0, 1.0) var ricochet_damage_ratio: float = 0.6

## Set by whoever controls the gun.
var trigger_held: bool = false

# Stats (reset per run).
var shots_fired: int = 0
var shots_hit: int = 0

var _cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_query.collision_mask = collision_mask
	_query.collide_with_areas = false
	_query.hit_back_faces = false


func _physics_process(delta: float) -> void:
	step(delta)


## Advance the trigger/cooldown by [param delta] seconds. Public for tests.
func step(delta: float) -> void:
	if trigger_held:
		_cooldown -= delta
		var guard := 0
		while _cooldown <= 0.0 and guard < 8:
			fire_one()
			_cooldown += 1.0 / fire_rate
			guard += 1
	else:
		_cooldown = maxf(_cooldown - delta, 0.0)


## Fire a single round along the barrel. Returns the hit target (or null).
func fire_one() -> Node:
	if turret == null:
		return null
	var origin := turret.get_muzzle_transform(muzzle_slot).origin
	var dir := _apply_spread(turret.get_barrel_direction(muzzle_slot))
	return fire_ray(origin, dir)


## Hitscan from [param origin] along [param dir]. Public so tests and future
## systems can use the same damage path.
func fire_ray(origin: Vector3, dir: Vector3) -> Node:
	shots_fired += 1
	var world := turret.get_world_3d() if turret else null
	if world == null:
		return null
	_query.from = origin
	_query.to = origin + dir * max_range
	_query.collision_mask = collision_mask
	var hit := world.direct_space_state.intersect_ray(_query)
	var is_tracer := (shots_fired % tracer_every) == 0
	if hit.is_empty():
		shot_fired.emit(origin, dir, _query.to, is_tracer)
		return null
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	shot_fired.emit(origin, dir, point, is_tracer)
	var target := Damageable.find_in(hit.collider as Node)
	var killed := false
	var surface := &"dirt"
	if target != null:
		shots_hit += 1
		if &"surface" in target:
			surface = target.surface
		killed = target.apply_damage(damage, point, normal, self)
	if ricochet_bounces > 0 and target is EnemyBase and is_inside_tree():
		_ricochet(target, point)
	if splash_radius > 0.0 and is_inside_tree():
		Damageable.damage_area(get_tree(), point, splash_radius, splash_damage, self, target)
		splashed.emit(point, splash_radius)
	shot_impact.emit(point, normal, surface, target, killed)
	return target


## Bounce from [param first] to the nearest live enemies, one after another.
func _ricochet(first: Node, point: Vector3) -> void:
	var hit_already: Array[Node] = [first]
	var from := point
	var dmg := damage * ricochet_damage_ratio
	for b in ricochet_bounces:
		var best: EnemyBase = null
		var best_d := ricochet_range
		for n in get_tree().get_nodes_in_group(Damageable.GROUP):
			var e := n as EnemyBase
			if e == null or not e.active or e.is_destroyed or e in hit_already:
				continue
			var d := e.get_effect_origin().distance_to(from)
			if d < best_d:
				best_d = d
				best = e
		if best == null:
			return
		var to := best.get_effect_origin()
		hit_already.append(best)
		var killed := best.apply_damage(dmg, to, (from - to).normalized(), self)
		ricocheted.emit(from, to, best, killed)
		from = to


## 1 = ready to fire, 0 = just fired (for a reload indicator).
func get_ready_ratio() -> float:
	return 1.0 - clampf(_cooldown * fire_rate, 0.0, 1.0)


func reset_stats() -> void:
	shots_fired = 0
	shots_hit = 0


func _apply_spread(dir: Vector3) -> Vector3:
	if spread_degrees <= 0.0:
		return dir
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	up = right.cross(dir).normalized()
	var r := tan(deg_to_rad(spread_degrees)) * sqrt(_rng.randf())
	var a := _rng.randf() * TAU
	return (dir + right * cos(a) * r + up * sin(a) * r).normalized()
