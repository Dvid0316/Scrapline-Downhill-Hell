class_name DroneEnemy
extends EnemyBase
## Flying enemy. Two flavours, set per scene:
##
## Strafer (kamikaze = false): flies in from ahead, then darts between orbit
##   points around the train, firing short bursts.
## Kamikaze (kamikaze = true): flies in, stops at a staging point and blinks
##   (ARMING, your warning), then dives at the armored railcar. If it reaches
##   it, it blows up for heavy hull damage. Shot down, it blows up where it
##   is and damages anything nearby, including other drones.
##
## Movement is a simple steering model in the track frame (rel, lateral,
## height), so drones keep up with the train and follow it around curves.
## Shot-down drones fall and tumble in world space, then get recycled.

enum State { CRUISE, ARMING, DIVING }

@export var kamikaze: bool = false

@export_group("Flight")
@export var cruise_speed: float = 17.0
@export var accel: float = 15.0
## Orbit points: metres relative to the train front, sideways, and up.
@export var orbit_rel: Vector2 = Vector2(-30.0, 30.0)
@export var orbit_lateral: Vector2 = Vector2(9.0, 20.0)
@export var orbit_height: Vector2 = Vector2(8.0, 13.0)
@export var retarget_time: Vector2 = Vector2(1.8, 3.2)
@export var spawn_ahead: Vector2 = Vector2(110.0, 140.0)
@export var spawn_height: float = 26.0
@export var rotor_speed: float = 40.0

@export_group("Kamikaze")
## Seconds it hovers, blinking, before diving.
@export var arm_time: float = 1.3
@export var dive_speed: float = 24.0
@export var detonate_radius: float = 3.0
## Hull damage when it reaches the train.
@export var impact_damage: float = 45.0
## Area damage when it's shot down (can chain into other drones).
@export var death_blast_radius: float = 6.0
@export var death_blast_damage: float = 80.0

var state: State = State.CRUISE
var _vel := Vector3.ZERO      # track frame: (rel, lateral, height) per second
var _goal := Vector3.ZERO
var _retarget: float = 0.0
var _state_time: float = 0.0
var _t: float = 0.0
var _rotors: Array[Node3D] = []
var _beacon: Node3D
var _fall_velocity := Vector3.ZERO
var _spin := Vector3.ZERO
var _passes: int = 0


func _ready() -> void:
	super._ready()
	for n in find_children("Rotor*", "Node3D", true, false):
		_rotors.append(n)
	_beacon = find_child("Beacon", true, false) as Node3D
	set_process(false)


func _on_spawn() -> void:
	state = State.CRUISE
	_state_time = 0.0
	_passes = 0
	_t = rng.randf() * 10.0
	var s := -1.0 if rng.randf() < 0.5 else 1.0
	rel_offset = rng.randf_range(spawn_ahead.x, spawn_ahead.y)
	lateral = s * rng.randf_range(14.0, 30.0)
	height = spawn_height + rng.randf_range(-3.0, 3.0)
	_vel = Vector3(-cruise_speed * 0.6, 0.0, 0.0)
	_pick_goal()
	if _beacon:
		_beacon.visible = true


func _pick_goal() -> void:
	var s := -1.0 if rng.randf() < 0.5 else 1.0
	if kamikaze:
		# Staging point: off to one side of the railcar, up high.
		_goal = Vector3(core_rel_offset() + rng.randf_range(-6.0, 14.0),
			s * rng.randf_range(12.0, 18.0), rng.randf_range(11.0, 15.0))
	else:
		_goal = Vector3(rng.randf_range(orbit_rel.x, orbit_rel.y),
			s * rng.randf_range(orbit_lateral.x, orbit_lateral.y),
			rng.randf_range(orbit_height.x, orbit_height.y))
	_retarget = rng.randf_range(retarget_time.x, retarget_time.y)


func _think(delta: float) -> void:
	_t += delta
	_state_time += delta
	var pos := Vector3(rel_offset, lateral, height)
	match state:
		State.CRUISE:
			_retarget -= delta
			var to_goal := _goal - pos
			if kamikaze and to_goal.length() < 3.0:
				_enter(State.ARMING)
			elif not kamikaze and (_retarget <= 0.0 or to_goal.length() < 2.0):
				_pick_goal()
				_passes += 1
			_steer(to_goal, cruise_speed, delta)
		State.ARMING:
			_steer(_goal - pos, 3.0, delta)
			if _state_time >= arm_time:
				_enter(State.DIVING)
		State.DIVING:
			var target := Vector3(core_rel_offset(), 0.0, 1.8)
			var to_t := target - pos
			_vel = _vel.move_toward(to_t.normalized() * dive_speed, 60.0 * delta)
			if to_t.length() <= detonate_radius or \
					(hull and global_position.distance_to(hull.get_core_point()) <= detonate_radius):
				_detonate()
				return
	pos += _vel * delta
	# Never fly into the ground (unless diving at the train).
	if state != State.DIVING:
		pos.z = maxf(pos.z, 4.0)
	rel_offset = pos.x
	lateral = pos.y
	height = pos.z


func _steer(to_goal: Vector3, max_speed: float, delta: float) -> void:
	var dist := to_goal.length()
	var desired := Vector3.ZERO
	if dist > 0.01:
		# Ease in as it arrives.
		desired = to_goal / dist * minf(max_speed, dist * 2.0)
	_vel = _vel.move_toward(desired, accel * delta)


func _enter(s: State) -> void:
	state = s
	_state_time = 0.0
	if s == State.ARMING and is_inside_tree():
		get_tree().call_group(FIRE_LISTENER_GROUP, &"on_enemy_warning", self)


func _place(delta: float) -> void:
	var bob := 0.0 if state == State.DIVING else sin(_t * 2.3) * 0.35
	var p := frame_point(rel_offset, lateral, height + bob)
	# Face the train; bank into sideways motion.
	var look := (hull.get_core_point() if hull else p + Vector3.FORWARD) - p
	look.y = 0.0
	if look.length_squared() < 0.01:
		look = frame_forward(rel_offset)
	var basis := Basis.looking_at(look.normalized(), Vector3.UP)
	var bank := clampf(-_vel.y * 0.04, -0.5, 0.5)
	var pitch := clampf(-_vel.x * 0.02, -0.4, 0.4)
	if state == State.DIVING:
		pitch = -0.7
	basis = basis * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, bank)
	global_transform = Transform3D(basis, p)
	_spin_rotors(delta)
	_blink()


func _spin_rotors(delta: float) -> void:
	for r in _rotors:
		r.rotate_y(rotor_speed * delta)


func _blink() -> void:
	if _beacon == null:
		return
	var rate := 2.0
	if state == State.ARMING:
		rate = 9.0
	elif state == State.DIVING:
		rate = 16.0
	_beacon.visible = fmod(_t * rate, 1.0) < 0.5


func _wants_to_fire() -> bool:
	return state == State.CRUISE and _passes >= 1


## Kamikaze reached the train: big hull hit, explosion, no points.
func _detonate() -> void:
	var p := global_position
	if hull:
		hull.apply_hit(impact_damage, p)
	get_tree().call_group(FIRE_LISTENER_GROUP, &"on_enemy_detonated", self, p)
	despawn()


func is_threatening() -> bool:
	return kamikaze and active and not is_destroyed and state != State.CRUISE


func _on_wrecked() -> void:
	# Fall forward with roughly the train's speed, tumbling.
	var fwd := frame_forward(rel_offset)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var world_vel := fwd * ((train.speed if train else 0.0) + _vel.x) + right * _vel.y + Vector3.UP * _vel.z
	_fall_velocity = world_vel + Vector3.UP * 3.0
	_spin = Vector3(rng.randf_range(-6, 6), rng.randf_range(-9, 9), rng.randf_range(-6, 6))
	if _beacon:
		_beacon.visible = false
	if kamikaze and is_inside_tree():
		Damageable.damage_area(get_tree(), global_position, death_blast_radius, death_blast_damage, self, self)


func _wreck_update(delta: float) -> void:
	_fall_velocity.y -= 22.0 * delta
	var p := global_position + _fall_velocity * delta
	rotation += _spin * delta
	global_position = p
	var ground := terrain.sample_height(p.x, p.z) if terrain else -INF
	if p.y <= ground + 0.3:
		_wreck_left = 0.0
	_spin_rotors(delta * 0.3)
