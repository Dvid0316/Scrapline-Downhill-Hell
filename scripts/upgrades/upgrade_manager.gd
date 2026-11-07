class_name UpgradeManager
extends Node
## Between-wave upgrades. When a wave is cleared the breather pauses and the
## player picks one of three cards: a new weapon (Tesla coil, rocket pod), a
## machine-gun or cannon mod, or armour. Picks stack up to each card's max
## level and last for the run. A new run starts from scratch.
##
## Stats are always recomputed from the base values captured at startup and
## the current levels ([method _recompute]), so applying and resetting can
## never drift.

signal offered(cards: Array[StringName])
signal picked(id: StringName, level: int)

enum Tag { WEAPON, MG, CANNON, ARMOR }
const TAG_NAMES := ["NEW WEAPON", "MACHINE GUN", "CANNON", "ARMOR"]
const TAG_COLORS := [Color(0.35, 0.85, 1.0), Color(1.0, 0.62, 0.15), Color(1.0, 0.36, 0.3), Color(0.5, 0.92, 0.42)]

## id -> title, tag, max level, offer weight.
const CATALOG := {
	&"tesla": {"title": "Tesla Coil", "tag": Tag.WEAPON, "max": 3, "weight": 1.3},
	&"rockets": {"title": "Rocket Pod", "tag": Tag.WEAPON, "max": 3, "weight": 1.3},
	&"ricochet": {"title": "Ricochet Rounds", "tag": Tag.MG, "max": 2, "weight": 1.0},
	&"mg_rate": {"title": "Hot Barrel", "tag": Tag.MG, "max": 3, "weight": 1.0},
	&"mg_damage": {"title": "AP Rounds", "tag": Tag.MG, "max": 3, "weight": 1.0},
	&"servo": {"title": "Turbo Servos", "tag": Tag.MG, "max": 2, "weight": 0.6},
	&"cannon_rate": {"title": "Autoloader", "tag": Tag.CANNON, "max": 3, "weight": 0.9},
	&"cannon_blast": {"title": "Big Bang Shells", "tag": Tag.CANNON, "max": 3, "weight": 0.9},
	&"armor": {"title": "Scrap Armor", "tag": Tag.ARMOR, "max": 4, "weight": 1.0},
	&"reactive": {"title": "Reactive Plating", "tag": Tag.ARMOR, "max": 3, "weight": 0.9},
	&"patch": {"title": "Emergency Patch", "tag": Tag.ARMOR, "max": 999, "weight": 0.8},
}

@export var director: WaveDirector
@export var hull: TrainHull
@export var weapon: HitscanWeapon
@export var cannon: HitscanWeapon
@export var turret: MountedTurret
@export var turret_input: TurretInput
@export var train: TrainController
@export var hud: CombatHud
@export var audio: CombatAudio
## When false, cleared waves go straight to the next breather (tests).
@export var enabled: bool = true
## Seconds after "WAVE CLEARED" before the cards come up.
@export var offer_delay: float = 1.2
@export_range(1, 4) var choices: int = 3
@export var random_seed: int = 9001

var levels := {}
var offer: Array[StringName] = []
var is_open := false
var tesla: TeslaCoil
var rockets: RocketPod
var picker: UpgradePicker

var _rng := RandomNumberGenerator.new()
var _base := {}
var _offers_made := 0
var _pending := 0   # bumps on reset so a delayed offer from a dead run is dropped
var _mouse_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	_capture_base()
	_mount_weapons()
	picker = UpgradePicker.new()
	picker.name = "Picker"
	picker.chosen.connect(choose)
	add_child(picker)
	if director:
		director.wave_cleared.connect(_on_wave_cleared)
	reset()


func _capture_base() -> void:
	if weapon:
		_base.mg_rate = weapon.fire_rate
		_base.mg_damage = weapon.damage
	if cannon:
		_base.cannon_rate = cannon.fire_rate
		_base.cannon_radius = cannon.splash_radius
		_base.cannon_splash = cannon.splash_damage
	if hull:
		_base.hull = hull.max_hull
	if turret:
		_base.yaw = turret.yaw_speed_degrees
		_base.pitch = turret.pitch_speed_degrees
		_base.yaw_acc = turret.yaw_accel_degrees
		_base.pitch_acc = turret.pitch_accel_degrees


## The coil rides the locomotive's hood roof, the pod the gun car's rear deck.
func _mount_weapons() -> void:
	if train == null or train.cars.is_empty():
		return
	tesla = TeslaCoil.new()
	tesla.name = "TeslaCoil"
	tesla.director = director
	tesla.audio = audio
	tesla.position = Vector3(0, 3.57, 0.1)
	train.cars[0].add_child(tesla)
	rockets = RocketPod.new()
	rockets.name = "RocketPod"
	rockets.director = director
	rockets.position = Vector3(0, 3.42, 5.25)
	train.cars[train.cars.size() - 1].add_child(rockets)


func level_of(id: StringName) -> int:
	return levels.get(id, 0)


## New run: no upgrades, base stats, picker closed.
func reset() -> void:
	_pending += 1
	levels.clear()
	offer.clear()
	_offers_made = 0
	_rng.seed = random_seed
	if rockets:
		rockets.reset()
	_close()
	_recompute()


## Give an upgrade directly (dev flag, tests). Applies pick effects too.
func grant(id: StringName, times: int = 1) -> void:
	for i in times:
		if not CATALOG.has(id) or level_of(id) >= CATALOG[id]["max"]:
			return
		levels[id] = level_of(id) + 1
		_on_gain(id)
	_recompute()


func _on_wave_cleared(_wave: int) -> void:
	if not enabled or (hull and hull.is_wrecked):
		return
	var cards := roll()
	if cards.is_empty():
		return
	director.hold = true
	var ticket := _pending
	if offer_delay > 0.0:
		await get_tree().create_timer(offer_delay).timeout
	if ticket != _pending or (hull and hull.is_wrecked):
		return
	open(cards)


## Pick the cards for the next offer (no repeats; the first offer of a run
## always includes a new weapon).
func roll() -> Array[StringName]:
	var pool: Array[StringName] = []
	for id: StringName in CATALOG:
		if level_of(id) < CATALOG[id]["max"]:
			pool.append(id)
	var out: Array[StringName] = []
	if _offers_made == 0:
		var weapons := pool.filter(func(id: StringName) -> bool: return CATALOG[id]["tag"] == Tag.WEAPON and level_of(id) == 0)
		if not weapons.is_empty():
			var w: StringName = weapons[_rng.randi() % weapons.size()]
			out.append(w)
			pool.erase(w)
	while out.size() < choices and not pool.is_empty():
		var total := 0.0
		for id in pool:
			total += _weight(id)
		var r := _rng.randf() * total
		var pick: StringName = pool[pool.size() - 1]
		for id in pool:
			r -= _weight(id)
			if r <= 0.0:
				pick = id
				break
		out.append(pick)
		pool.erase(pick)
	return out


func _weight(id: StringName) -> float:
	var w: float = CATALOG[id]["weight"]
	if id == &"patch" and hull:
		w *= lerpf(2.5, 0.15, hull.get_ratio())  # wanted most when hurting
	return w


func open(cards: Array[StringName]) -> void:
	offer = cards
	_offers_made += 1
	is_open = true
	if director:
		director.hold = true
	if turret_input:
		turret_input.suppress_fire = true
	if hud and hud.crosshair:
		hud.crosshair.visible = false
	_mouse_before = Input.mouse_mode
	if DisplayServer.get_name() != "headless" and Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	var data: Array[Dictionary] = []
	for id in cards:
		data.append(card_data(id))
	picker.open(director.wave if director else 0, data)
	offered.emit(cards)


## Take card [param index] of the current offer.
func choose(index: int) -> void:
	if not is_open or index < 0 or index >= offer.size():
		return
	var id := offer[index]
	levels[id] = level_of(id) + 1
	_on_gain(id)
	_recompute()
	if audio:
		audio.play_cue(&"upgrade")
	if hud:
		var lv := level_of(id)
		hud.show_banner(String(CATALOG[id]["title"]).to_upper(),
			"Online!" if lv == 1 and CATALOG[id]["tag"] == Tag.WEAPON else ("Level %d" % lv if CATALOG[id]["max"] < 99 else "Hull restored"))
	_close()
	picked.emit(id, level_of(id))


## Close the cards without picking (game over).
func cancel() -> void:
	_pending += 1
	_close()


func _close() -> void:
	if picker:
		picker.close()
	if is_open:
		if DisplayServer.get_name() != "headless" and Input.mouse_mode == Input.MOUSE_MODE_CONFINED \
				and _mouse_before == Input.MOUSE_MODE_CONFINED_HIDDEN:
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	is_open = false
	if director:
		director.hold = false
	if turret_input:
		turret_input.suppress_fire = false
	if hud and hud.crosshair:
		hud.crosshair.visible = true


## One-off effects of gaining a level (on top of the recomputed stats).
func _on_gain(id: StringName) -> void:
	match id:
		&"armor":
			if hull:
				hull.set_max_hull(_base.hull + 100.0 * level_of(&"armor"), 100.0)
		&"patch":
			if hull:
				hull.repair_fraction(1.0)


func _recompute() -> void:
	if weapon:
		weapon.fire_rate = _base.mg_rate * (1.0 + 0.3 * level_of(&"mg_rate"))
		weapon.damage = _base.mg_damage * (1.0 + 0.35 * level_of(&"mg_damage"))
		weapon.ricochet_bounces = level_of(&"ricochet")
	if cannon:
		cannon.fire_rate = _base.cannon_rate * (1.0 + 0.4 * level_of(&"cannon_rate"))
		cannon.splash_radius = _base.cannon_radius * (1.0 + 0.3 * level_of(&"cannon_blast"))
		cannon.splash_damage = _base.cannon_splash * (1.0 + 0.25 * level_of(&"cannon_blast"))
	if hull:
		hull.damage_mult = 1.0 - 0.15 * level_of(&"reactive")
		var want: float = _base.hull + 100.0 * level_of(&"armor")
		if not is_equal_approx(hull.max_hull, want):
			hull.set_max_hull(want)
	if turret:
		var k := 1.0 + 0.5 * level_of(&"servo")
		turret.yaw_speed_degrees = _base.yaw * k
		turret.pitch_speed_degrees = _base.pitch * k
		turret.yaw_accel_degrees = _base.yaw_acc * k
		turret.pitch_accel_degrees = _base.pitch_acc * k
	if tesla:
		tesla.level = level_of(&"tesla")
	if rockets:
		rockets.level = level_of(&"rockets")


## What a card says, for the level it would give.
func card_data(id: StringName) -> Dictionary:
	var c: Dictionary = CATALOG[id]
	var next := level_of(id) + 1
	return {"id": id, "title": c["title"], "tag": TAG_NAMES[c["tag"]], "color": TAG_COLORS[c["tag"]],
		"level": next, "max": c["max"], "text": describe(id, next)}


func describe(id: StringName, lv: int) -> String:
	match id:
		&"tesla":
			if lv == 1:
				return "A coil on the engine roof zaps the nearest enemy every second. Fully automatic!"
			return "Zaps faster, and the lightning jumps to %d enemies." % lv
		&"rockets":
			if lv == 1:
				return "Fires 2 homing rockets every few seconds. They chase enemies down."
			return "%d rockets per volley, fired more often." % (lv + 1)
		&"ricochet":
			return "Bullets that hit an enemy bounce into %s nearby." % ("another one" if lv == 1 else "two more")
		&"mg_rate":
			return "Machine gun fires 30% faster."
		&"mg_damage":
			return "Machine gun bullets hit 35% harder."
		&"servo":
			return "Turret swings 50% faster. Snap onto targets!"
		&"cannon_rate":
			return "Cannon reloads 40% faster."
		&"cannon_blast":
			return "Cannon blasts are 30% bigger and 25% stronger."
		&"armor":
			return "+100 max hull, and patches 100 right now."
		&"reactive":
			return "Take 15% less damage from everything."
		&"patch":
			return "Repair the hull to full right now."
	return ""
