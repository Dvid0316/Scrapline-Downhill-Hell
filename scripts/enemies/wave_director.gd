class_name WaveDirector
extends Node3D
## Runs the enemy waves: a short breather, then a wave spawns over a few
## seconds; once every enemy in it is dead (or has blown itself up), the hull
## gets patched up a little and the next wave starts.
##
## Waves 1–5 are hand-made (see [constant WAVES]) to introduce one idea at a
## time. After that it keeps going forever: the wave-5 mix grows by 25% per
## wave and enemies get 10% tougher, so a run always ends eventually.
##
## Enemies are pooled per kind: instanced the first time they're needed,
## then reused. Nothing is freed during a run.

signal wave_started(wave: int, enemy_count: int)
signal wave_cleared(wave: int)
## Fired whenever the number of enemies left in the wave changes.
signal enemies_changed(remaining: int)

enum State { IDLE, BREATHER, SPAWNING, STOPPED }

## Hand-made waves. Kinds: buggy, truck, drone, kamikaze.
const WAVES := [
	{"name": "Scout drones", "drone": 4, "interval": 1.3},
	{"name": "Raiders on the road", "buggy": 3, "drone": 2, "interval": 1.4},
	{"name": "Incoming kamikazes", "buggy": 2, "drone": 3, "kamikaze": 3, "interval": 1.2},
	{"name": "Gun truck", "truck": 1, "buggy": 2, "drone": 4, "kamikaze": 2, "interval": 1.1},
	{"name": "Everything", "truck": 2, "buggy": 3, "drone": 5, "kamikaze": 4, "interval": 0.9},
]
const KINDS := [&"buggy", &"truck", &"drone", &"kamikaze"]

@export var train: TrainController
@export var route: RailRoute
@export var terrain: TerrainBuilder
@export var hull: TrainHull

@export_group("Enemy scenes")
@export var buggy_scene: PackedScene
@export var truck_scene: PackedScene
@export var drone_scene: PackedScene
@export var kamikaze_scene: PackedScene

@export_group("Pacing")
## When false, no waves run (tests, `--no-enemies`).
@export var enabled: bool = true
@export var first_breather: float = 4.0
@export var breather: float = 5.0
## Never more than this many enemies alive at once (later spawns wait).
@export_range(1, 40) var max_alive: int = 14
## Hull repaired after each cleared wave (fraction of max).
@export_range(0.0, 1.0) var repair_per_wave: float = 0.15
@export var random_seed: int = 4242

var state: State = State.IDLE
var wave: int = 0
var wave_name: String = ""
## Seconds left in the current breather.
var breather_left: float = 0.0
var enemies_killed: int = 0

var _pools := {}            # kind -> Array[EnemyBase]
var _queue: Array[StringName] = []
var _spawn_interval: float = 1.2
var _spawn_cd: float = 0.0
var _alive: Array[EnemyBase] = []
var _health_mult: float = 1.0
var _rng := RandomNumberGenerator.new()
var _spawn_counter: int = 0


func _ready() -> void:
	for k in KINDS:
		_pools[k] = []
	reset()


## New run: everything despawned, back to the breather before wave 1.
func reset(start_wave: int = 1) -> void:
	for k in _pools:
		for e: EnemyBase in _pools[k]:
			if e.active:
				e.despawn()
	_alive.clear()
	_queue.clear()
	_rng.seed = random_seed
	_spawn_counter = 0
	enemies_killed = 0
	wave = maxi(start_wave, 1) - 1
	wave_name = ""
	if enabled:
		state = State.BREATHER
		breather_left = first_breather
	else:
		state = State.IDLE
	enemies_changed.emit(0)


## Game over: no more spawning. Enemies already out keep flying but the
## gun logic stops shooting once the hull is wrecked.
func stop() -> void:
	state = State.STOPPED
	_queue.clear()


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		reset()
	elif state == State.IDLE:
		state = State.BREATHER
		breather_left = first_breather


func _physics_process(delta: float) -> void:
	match state:
		State.BREATHER:
			breather_left -= delta
			if breather_left <= 0.0:
				start_next_wave()
		State.SPAWNING:
			_spawn_cd -= delta
			if _spawn_cd <= 0.0 and not _queue.is_empty() and _alive.size() < max_alive:
				spawn_enemy(_queue.pop_front())
				_spawn_cd = _spawn_interval
			if _queue.is_empty() and _alive.is_empty():
				_finish_wave()


func start_next_wave() -> void:
	wave += 1
	var def := get_wave_definition(wave)
	wave_name = def.get("name", "Wave %d" % wave)
	_spawn_interval = def.get("interval", 1.0)
	_health_mult = def.get("health_mult", 1.0)
	_queue = _build_queue(def)
	_spawn_cd = 0.0
	state = State.SPAWNING
	wave_started.emit(wave, _queue.size())
	enemies_changed.emit(get_remaining())


## Composition of wave [param n] (1-based). Past the hand-made list, the
## last wave scales up.
func get_wave_definition(n: int) -> Dictionary:
	if n <= WAVES.size():
		return WAVES[n - 1]
	var extra := n - WAVES.size()
	var base: Dictionary = WAVES[WAVES.size() - 1]
	var def := {"name": "Wave %d: no let-up" % n,
		"interval": maxf(0.55, base["interval"] - 0.05 * extra),
		"health_mult": 1.0 + 0.1 * extra}
	for k in KINDS:
		def[k] = int(round(base.get(k, 0) * (1.0 + 0.25 * extra)))
	return def


func _build_queue(def: Dictionary) -> Array[StringName]:
	var q: Array[StringName] = []
	for k: StringName in KINDS:
		for i in int(def.get(k, 0)):
			q.append(k)
	# Deterministic shuffle so kinds arrive mixed, but drones lead the first wave.
	for i in range(q.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := q[i]
		q[i] = q[j]
		q[j] = tmp
	return q


## Spawn one enemy of [param kind] right now (also used by tests).
func spawn_enemy(kind: StringName) -> EnemyBase:
	var e := _acquire(kind)
	if e == null:
		return null
	_spawn_counter += 1
	e.spawn(train, route, terrain, hull, random_seed * 7919 + _spawn_counter, _health_mult)
	_alive.append(e)
	return e


func _acquire(kind: StringName) -> EnemyBase:
	var pool: Array = _pools.get(kind, [])
	for e: EnemyBase in pool:
		if not e.active:
			return e
	var scene: PackedScene
	match kind:
		&"buggy": scene = buggy_scene
		&"truck": scene = truck_scene
		&"drone": scene = drone_scene
		&"kamikaze": scene = kamikaze_scene
	if scene == null:
		push_warning("WaveDirector: no scene for enemy kind '%s'" % kind)
		return null
	var e := scene.instantiate() as EnemyBase
	e.name = "%s%d" % [String(kind).capitalize(), pool.size()]
	add_child(e)
	e.despawned.connect(_on_enemy_despawned)
	e.destroyed.connect(_on_enemy_destroyed.bind(e))
	pool.append(e)
	_pools[kind] = pool
	return e


func _on_enemy_destroyed(_source: Node, e: EnemyBase) -> void:
	enemies_killed += 1
	# A wreck no longer counts toward the wave, even while it's still falling.
	_alive.erase(e)
	enemies_changed.emit(get_remaining())


func _on_enemy_despawned(e: EnemyBase) -> void:
	_alive.erase(e)
	enemies_changed.emit(get_remaining())


func _finish_wave() -> void:
	if hull and repair_per_wave > 0.0:
		hull.repair_fraction(repair_per_wave)
	wave_cleared.emit(wave)
	state = State.BREATHER
	breather_left = breather


## Enemies still to deal with in this wave (alive + not yet spawned).
func get_remaining() -> int:
	return _alive.size() + _queue.size()


func get_alive() -> Array[EnemyBase]:
	return _alive


## Every pooled enemy instance (for tests: node counts).
func get_pool_size() -> int:
	var n := 0
	for k in _pools:
		n += (_pools[k] as Array).size()
	return n
