class_name CarBody
extends MeshInstance3D
## Builds the detailed body of a rail vehicle procedurally with [CarKit] in
## _ready and caches it, so the scene file stays small. One mesh, a surface
## per material. Bogies, lights, smoke and collision live in the car scene.
##
## Car convention: front -Z, y = 0 at rail top, deck/walkway at y ≈ 1.48.

enum Kind { LOCOMOTIVE, GUN_CAR }

@export var kind: Kind = Kind.LOCOMOTIVE

const PLATE := preload("res://materials/armor_plate.tres")
const DARK := preload("res://materials/armor_dark.tres")
const STEEL := preload("res://materials/steel_worn.tres")
const RUST := preload("res://materials/rust.tres")
const HAZARD := preload("res://materials/hazard_yellow.tres")
const GLASS := preload("res://materials/glass_dark.tres")
const HEADLIGHT := preload("res://materials/lamp_headlight.tres")
const LAMP_RED := preload("res://materials/lamp_red.tres")
const LAMP_AMBER := preload("res://materials/lamp_amber.tres")
const SANDBAG := preload("res://materials/sandbag.tres")
const WOOD := preload("res://materials/crate_wood.tres")
const BARREL := preload("res://materials/barrel_red.tres")

const DECK_Y := 1.48

static var _cache := {}


func _ready() -> void:
	if not _cache.has(kind):
		var k := CarKit.new()
		match kind:
			Kind.LOCOMOTIVE:
				_locomotive(k)
			Kind.GUN_CAR:
				_gun_car(k)
		_cache[kind] = k.commit()
	mesh = _cache[kind]


# ------------------------------------------------------------------ shared

## Underframe, walkway deck, sole-bar rivets, end beams with hazard stripes.
static func _chassis(k: CarKit, half_len: float, bogie_z: float) -> void:
	k.boxp(DARK, Vector3(2.9, 0.42, half_len * 2.0 - 0.3), Vector3(0, 1.2, 0), Vector3.ZERO, 0.05)
	k.boxp(STEEL, Vector3(3.1, 0.08, half_len * 2.0 - 0.1), Vector3(0, DECK_Y - 0.04, 0), Vector3.ZERO, 0.02)
	for s in [-1.0, 1.0]:
		# Sole bar lip + rivets between the bogies.
		k.boxp(DARK, Vector3(0.08, 0.3, half_len * 2.0 - 0.4), Vector3(s * 1.5, 1.2, 0), Vector3.ZERO, 0.02)
		k.rivets(DARK, CarKit.line(Vector3(s * 1.54, 1.25, -bogie_z + 1.9), Vector3(s * 1.54, 1.25, bogie_z - 1.9), 12), Vector3(s, 0, 0), 0.05)
		# Steps at each corner.
		for e in [-1.0, 1.0]:
			var z: float = e * (half_len - 0.5)
			for i in 2:
				k.boxp(STEEL, Vector3(0.45, 0.05, 0.35), Vector3(s * 1.35, 0.98 - i * 0.32, z), Vector3.ZERO, 0.01)
			k.boxp(DARK, Vector3(0.04, 0.7, 0.04), Vector3(s * 1.56, 0.85, z - 0.18), Vector3.ZERO, 0.0)
			k.boxp(DARK, Vector3(0.04, 0.7, 0.04), Vector3(s * 1.56, 0.85, z + 0.18), Vector3.ZERO, 0.0)
	# End beams: dark beam with yellow/black chevrons, coupler and buffers.
	for e in [-1.0, 1.0]:
		var z: float = e * (half_len - 0.12)
		k.boxp(DARK, Vector3(3.0, 0.5, 0.24), Vector3(0, 1.15, z), Vector3.ZERO, 0.04)
		_chevrons(k, Vector3(0, 1.15, z + e * 0.125), 2.8, 0.36, e)
		k.boxp(DARK, Vector3(0.36, 0.3, 0.5), Vector3(0, 1.0, z + e * 0.3), Vector3.ZERO, 0.04)
		k.boxp(STEEL, Vector3(0.26, 0.22, 0.14), Vector3(0, 1.0, z + e * 0.58), Vector3.ZERO, 0.03)
		for s in [-1.0, 1.0]:
			k.cylp(DARK, 0.09, 0.3, Vector3(s * 1.0, 1.15, z + e * 0.25), Vector3(90, 0, 0), 8)
			k.cylp(STEEL, 0.19, 0.06, Vector3(s * 1.0, 1.15, z + e * 0.42), Vector3(90, 0, 0), 12)


## Yellow/black diagonal stripes on an end face (plane z = const, facing e).
static func _chevrons(k: CarKit, c: Vector3, width: float, height: float, e: float) -> void:
	var n := 9
	var w := width / n
	for i in n:
		var x0 := c.x - width * 0.5 + i * w
		var mat := HAZARD if i % 2 == 0 else DARK
		var sk := w * 0.6
		var pts := PackedVector3Array([
			Vector3(x0, c.y - height * 0.5, c.z),
			Vector3(x0 + w, c.y - height * 0.5, c.z),
			Vector3(x0 + w + sk, c.y + height * 0.5, c.z),
			Vector3(x0 + sk, c.y + height * 0.5, c.z)])
		if i == n - 1:
			pts[2].x = minf(pts[2].x, c.x + width * 0.5)
			pts[3].x = minf(pts[3].x, c.x + width * 0.5)
		k.poly(mat, pts, c - Vector3(0, 0, e))


## Hand rail: posts plus a top rail from z0 to z1 at side x.
static func _railing(k: CarKit, x: float, z0: float, z1: float, y0: float, h: float) -> void:
	var count := maxi(2, int(absf(z1 - z0) / 1.6) + 1)
	for p in CarKit.line(Vector3(x, y0 + h * 0.5, z0), Vector3(x, y0 + h * 0.5, z1), count):
		k.cylp(STEEL, 0.03, h, p, Vector3.ZERO, 6)
	k.cylp(STEEL, 0.035, absf(z1 - z0), Vector3(x, y0 + h, (z0 + z1) * 0.5), Vector3(90, 0, 0), 6)
	k.cylp(STEEL, 0.025, absf(z1 - z0), Vector3(x, y0 + h * 0.5, (z0 + z1) * 0.5), Vector3(90, 0, 0), 6)


## Louvre grille on a side face at x (facing s).
static func _grille(k: CarKit, s: float, x: float, y: float, z: float, w: float, h: float) -> void:
	k.boxp(DARK, Vector3(0.05, h, w), Vector3(x, y, z), Vector3.ZERO, 0.0)
	var slats := int(h / 0.16)
	for i in slats:
		var yy := y - h * 0.5 + (i + 0.5) * h / slats
		k.boxp(PLATE, Vector3(0.05, 0.05, w - 0.1), Vector3(x + s * 0.04, yy, z), Vector3(0, 0, -s * 40.0), 0.0)
	k.rivets(DARK, PackedVector3Array([
		Vector3(x + s * 0.02, y + h * 0.5 + 0.06, z - w * 0.5), Vector3(x + s * 0.02, y + h * 0.5 + 0.06, z + w * 0.5),
		Vector3(x + s * 0.02, y - h * 0.5 - 0.06, z - w * 0.5), Vector3(x + s * 0.02, y - h * 0.5 - 0.06, z + w * 0.5)]), Vector3(s, 0, 0), 0.05)


# ------------------------------------------------------------------ locomotive

static func _locomotive(k: CarKit) -> void:
	var half := 8.5
	_chassis(k, half, 5.0)
	# Fuel tank slung between the bogies.
	var tank := PackedVector2Array([
		Vector2(-0.8, 0.5), Vector2(0.8, 0.5), Vector2(1.1, 0.72),
		Vector2(1.1, 0.98), Vector2(-1.1, 0.98), Vector2(-1.1, 0.72)])
	k.extrude(DARK, tank, -2.9, 2.9)
	for z in [-1.6, 1.6]:
		k.extrude(HAZARD, PackedVector2Array([
			Vector2(-0.82, 0.48), Vector2(0.82, 0.48), Vector2(1.12, 0.71),
			Vector2(1.12, 0.99), Vector2(-1.12, 0.99), Vector2(-1.12, 0.71)]), z - 0.08, z + 0.08)

	# --- Hood (engine compartment), sloped armour shoulders.
	var hood := PackedVector2Array([
		Vector2(-1.22, DECK_Y), Vector2(1.22, DECK_Y), Vector2(1.22, 2.95),
		Vector2(0.82, 3.5), Vector2(-0.82, 3.5), Vector2(-1.22, 2.95)])
	k.extrude(PLATE, hood, -2.0, 6.9, Transform3D.IDENTITY, Vector2.ONE, Vector2(0.94, 0.93))
	# Hood roof walk plate + radiator fans at the rear.
	k.boxp(DARK, Vector3(1.5, 0.08, 4.0), Vector3(0, 3.53, 0.6), Vector3.ZERO, 0.02)
	for z in [4.3, 5.8]:
		k.boxp(DARK, Vector3(1.5, 0.16, 1.4), Vector3(0, 3.48, z), Vector3.ZERO, 0.04)
		k.cylp(STEEL, 0.6, 0.06, Vector3(0, 3.58, z), Vector3.ZERO, 16)
		k.cylp(DARK, 0.5, 0.07, Vector3(0, 3.6, z), Vector3.ZERO, 16)
		for i in 4:
			k.boxp(STEEL, Vector3(0.9, 0.03, 0.1), Vector3(0, 3.65, z), Vector3(0, i * 45.0, 0), 0.0)
		k.cylp(RUST, 0.1, 0.08, Vector3(0, 3.67, z), Vector3.ZERO, 8)
	# Exhaust stacks (smoke emitters sit on top of these: x ±0.42, z 2.6).
	for s in [-1.0, 1.0]:
		k.boxp(DARK, Vector3(0.5, 0.18, 0.55), Vector3(s * 0.42, 3.55, 2.6), Vector3.ZERO, 0.04)
		k.cyl(DARK, 0.15, 0.18, 0.95, Transform3D(Basis.IDENTITY, Vector3(s * 0.42, 4.0, 2.6)), 10)
		k.cyl(STEEL, 0.2, 0.2, 0.1, Transform3D(Basis.IDENTITY, Vector3(s * 0.42, 4.45, 2.6)), 10, false)
	# Side detail: grilles, bolted applique armour, seam rivets.
	for s in [-1.0, 1.0]:
		var x: float = s * 1.22
		_grille(k, s, x + s * 0.02, 2.35, 4.0, 2.4, 0.95)
		_grille(k, s, x + s * 0.02, 2.35, 1.2, 1.6, 0.95)
		# Applique armour plate near the cab, slightly proud.
		k.boxp(PLATE, Vector3(0.08, 1.15, 2.2), Vector3(x + s * 0.05, 2.25, -0.8), Vector3.ZERO, 0.04)
		k.rivets(DARK, CarKit.line(Vector3(x + s * 0.1, 2.75, -1.75), Vector3(x + s * 0.1, 2.75, 0.15), 6), Vector3(s, 0, 0), 0.05)
		k.rivets(DARK, CarKit.line(Vector3(x + s * 0.1, 1.75, -1.75), Vector3(x + s * 0.1, 1.75, 0.15), 6), Vector3(s, 0, 0), 0.05)
		# Seam rivets along the hood shoulder.
		k.rivets(DARK, CarKit.line(Vector3(x + s * 0.01, 2.9, 0.6), Vector3(x * 0.95 + s * 0.01, 2.85, 6.6), 14), Vector3(s, 0, 0), 0.045)
		# Scrap plate welded on crooked (it's a scrap train).
		k.boxp(STEEL, Vector3(0.06, 0.6, 0.9), Vector3(x + s * 0.06, 1.95, 5.9), Vector3(0, 0, s * 4.0) + Vector3(7.0, 0, 0), 0.02)
		# Walkway railings.
		_railing(k, s * 1.46, -1.7, 7.9, DECK_Y, 0.95)
		# Hazard band along the walkway edge.
		k.boxp(HAZARD, Vector3(0.03, 0.08, 15.6), Vector3(s * 1.555, DECK_Y - 0.02, 0.2), Vector3.ZERO, 0.0)

	# --- Cab
	var cab := PackedVector2Array([
		Vector2(-1.45, DECK_Y), Vector2(1.45, DECK_Y), Vector2(1.45, 3.35),
		Vector2(1.12, 4.05), Vector2(-1.12, 4.05), Vector2(-1.45, 3.35)])
	k.extrude(PLATE, cab, -6.4, -2.0, Transform3D.IDENTITY, Vector2(0.97, 1.0), Vector2.ONE)
	# Roof cap, beacon, horn, antenna.
	k.boxp(DARK, Vector3(2.15, 0.14, 4.2), Vector3(0, 4.1, -4.2), Vector3.ZERO, 0.05)
	k.cylp(DARK, 0.14, 0.1, Vector3(-0.6, 4.22, -3.0), Vector3.ZERO, 10)
	k.mesh(LAMP_AMBER, _sphere(0.13), Transform3D(Basis.IDENTITY, Vector3(-0.6, 4.32, -3.0)))
	k.cyl(STEEL, 0.03, 0.09, 0.5, Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0, 0)), Vector3(0.55, 4.28, -5.6)), 8)
	k.cyl(STEEL, 0.06, 0.12, 0.35, Transform3D(Basis.from_euler(Vector3(PI / 2.0, 0, 0)), Vector3(0.25, 4.28, -5.5)), 8)
	k.cylp(DARK, 0.015, 1.8, Vector3(0.75, 5.0, -2.6), Vector3(0, 0, -8), 4)
	# Front windows behind an armoured visor.
	for s in [-1.0, 1.0]:
		k.boxp(GLASS, Vector3(0.95, 0.42, 0.06), Vector3(s * 0.55, 3.25, -6.36), Vector3.ZERO, 0.02)
	k.boxp(DARK, Vector3(0.14, 0.5, 0.1), Vector3(0, 3.25, -6.4), Vector3.ZERO, 0.02)
	k.boxp(DARK, Vector3(2.7, 0.1, 0.35), Vector3(0, 3.55, -6.5), Vector3(-12, 0, 0), 0.03)
	k.boxp(DARK, Vector3(2.7, 0.08, 0.12), Vector3(0, 2.95, -6.42), Vector3.ZERO, 0.02)
	# Side windows, doors, grab rails, rivets.
	for s in [-1.0, 1.0]:
		var x: float = s * 1.45
		for z in [-5.1, -3.4]:
			k.boxp(GLASS, Vector3(0.05, 0.42, 1.0), Vector3(x + s * 0.01, 3.1, z), Vector3.ZERO, 0.015)
			k.boxp(DARK, Vector3(0.22, 0.07, 1.15), Vector3(x + s * 0.08, 3.38, z), Vector3.ZERO, 0.02)
		k.boxp(DARK, Vector3(0.04, 1.5, 0.9), Vector3(x + s * 0.01, 2.3, -2.6), Vector3.ZERO, 0.0)
		k.boxp(PLATE, Vector3(0.05, 1.42, 0.82), Vector3(x + s * 0.03, 2.3, -2.6), Vector3.ZERO, 0.02)
		k.cylp(STEEL, 0.025, 1.1, Vector3(x + s * 0.1, 2.3, -2.0), Vector3.ZERO, 6)
		k.rivets(DARK, CarKit.line(Vector3(x + s * 0.01, 1.7, -6.2), Vector3(x + s * 0.01, 1.7, -3.2), 8), Vector3(s, 0, 0), 0.045)
		k.rivets(DARK, CarKit.line(Vector3(x + s * 0.01, 2.75, -6.2), Vector3(x + s * 0.01, 2.75, -3.2), 8), Vector3(s, 0, 0), 0.045)
		# Big unit stripe on the cab side.
		k.boxp(HAZARD, Vector3(0.02, 0.16, 3.0), Vector3(x + s * 0.02, 2.05, -4.6), Vector3.ZERO, 0.0)

	# --- Short nose with a sloped front plate.
	var nose := PackedVector2Array([
		Vector2(-1.3, DECK_Y), Vector2(1.3, DECK_Y), Vector2(1.3, 2.55),
		Vector2(1.0, 2.9), Vector2(-1.0, 2.9), Vector2(-1.3, 2.55)])
	k.extrude(PLATE, nose, -8.15, -6.4, Transform3D.IDENTITY, Vector2(0.9, 0.82), Vector2.ONE)
	k.boxp(DARK, Vector3(2.2, 0.08, 1.4), Vector3(0, 2.92, -7.1), Vector3(-9, 0, 0), 0.02)
	# Twin headlights in armoured hoods + marker lamps.
	for s in [-1.0, 1.0]:
		k.cylp(DARK, 0.22, 0.25, Vector3(s * 0.7, 2.2, -8.13), Vector3(90, 0, 0), 12)
		k.cylp(HEADLIGHT, 0.17, 0.06, Vector3(s * 0.7, 2.2, -8.27), Vector3(90, 0, 0), 12)
		k.boxp(DARK, Vector3(0.5, 0.06, 0.3), Vector3(s * 0.7, 2.47, -8.2), Vector3(-15, 0, 0), 0.01)
		k.mesh(LAMP_RED, _sphere(0.07), Transform3D(Basis.IDENTITY, Vector3(s * 1.15, 1.75, -8.2)))

	# --- Plow (cowcatcher): yellow V with black stripes and ram spikes.
	for s in [-1.0, 1.0]:
		var b := Basis.from_euler(Vector3(deg_to_rad(18.0), -s * deg_to_rad(32.0), 0))
		var c := Vector3(s * 0.72, 0.62, -8.95)
		k.box(HAZARD, Vector3(1.75, 0.9, 0.1), Transform3D(b, c), 0.03)
		for i in 3:
			var off := b * Vector3(-s * 0.55 + s * i * 0.5, 0, -0.06)
			k.box(DARK, Vector3(0.16, 0.85, 0.02), Transform3D(b * Basis(Vector3.BACK, s * 0.5), c + off), 0.0)
		k.cyl(STEEL, 0.0, 0.09, 0.55, Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), Vector3(s * 0.75, 0.75, -9.05 - 0.2)), 6)
	k.cyl(STEEL, 0.0, 0.11, 0.7, Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0, 0)), Vector3(0, 0.7, -9.75)), 6)

	# --- Rear: deck railing across the end.
	k.cylp(STEEL, 0.035, 2.9, Vector3(0, DECK_Y + 0.95, 8.15), Vector3(0, 0, 90), 6)


# ------------------------------------------------------------------ gun car

static func _gun_car(k: CarKit) -> void:
	var half := 7.0
	_chassis(k, half, 4.5)
	var top := 3.4
	# Sloped armour hull.
	var hull := PackedVector2Array([
		Vector2(-1.5, DECK_Y), Vector2(1.5, DECK_Y), Vector2(1.5, 2.25),
		Vector2(1.34, top), Vector2(-1.34, top), Vector2(-1.5, 2.25)])
	k.extrude(PLATE, hull, -6.45, 6.45, Transform3D.IDENTITY, Vector2(0.96, 1.0), Vector2(0.96, 1.0))
	k.boxp(DARK, Vector3(2.6, 0.06, 12.6), Vector3(0, top + 0.02, 0), Vector3.ZERO, 0.0)
	# Anti-slip tread strips on the deck.
	for z in [-5.0, -3.0, 3.0, 5.0]:
		k.boxp(STEEL, Vector3(2.2, 0.02, 0.08), Vector3(0, top + 0.06, z), Vector3.ZERO, 0.0)
	# Turret barbette: chunky octagon + rivet ring (the turret ring itself
	# stays a separate node in the scene).
	k.cyl(DARK, 1.42, 1.5, 0.3, Transform3D(Basis.IDENTITY, Vector3(0, top + 0.17, 0)), 8)
	var ring := PackedVector3Array()
	for i in 16:
		var a := TAU * i / 16.0
		ring.append(Vector3(cos(a) * 1.44, top + 0.33, sin(a) * 1.44))
	k.rivets(STEEL, ring, Vector3.UP, 0.05)

	for s in [-1.0, 1.0]:
		var x: float = s * 1.5
		# Lower hull rivet rows, vertical seams.
		k.rivets(DARK, CarKit.line(Vector3(x + s * 0.01, 1.75, -6.0), Vector3(x + s * 0.01, 1.75, 6.0), 22), Vector3(s, 0, 0), 0.045)
		for z in [-2.15, 2.15]:
			k.rivets(DARK, CarKit.line(Vector3(x + s * 0.01, 1.7, z), Vector3(x + s * 0.01, 2.2, z), 3), Vector3(s, 0, 0), 0.045)
		# Spaced armour slats hanging off the side: alternating paint and scrap.
		for i in 3:
			var z: float = -4.3 + i * 4.3
			var mat := DARK if i != 1 else STEEL
			var tilt := Vector3(0, 0, s * -6.0) + Vector3((i - 1) * 2.0, 0, 0)
			k.boxp(mat, Vector3(0.09, 1.25, 3.7), Vector3(s * 1.66, 2.55, z), tilt, 0.04)
			for zz in [z - 1.5, z + 1.5]:
				k.boxp(STEEL, Vector3(0.18, 0.12, 0.12), Vector3(s * 1.57, 2.9, zz), Vector3.ZERO, 0.02)
			k.rivets(DARK, CarKit.line(Vector3(s * 1.72, 3.05, z - 1.6), Vector3(s * 1.72, 3.05, z + 1.6), 7), Vector3(s, 0, 0), 0.05)
		# Hazard bands at the hull ends.
		for e in [-1.0, 1.0]:
			k.boxp(HAZARD, Vector3(0.03, 0.2, 0.55), Vector3(x + s * 0.01, 1.95, e * 5.95), Vector3.ZERO, 0.0)
		# Parapet: outward-leaning plates with gun slits between them.
		for i in 4:
			var z0 := -6.1 + i * 3.1
			var c := Vector3(s * 1.38, top + 0.45, z0 + 1.4)
			k.boxp(PLATE, Vector3(0.1, 0.85, 2.75), c, Vector3(0, 0, s * -12.0), 0.04)
			k.rivets(DARK, CarKit.line(c + Vector3(s * 0.12, 0.3, -1.2), c + Vector3(s * 0.12, 0.3, 1.2), 6), Vector3(s, 0.2, 0), 0.04)
	# End parapets with a central slit, plus sandbag lines behind them.
	for e in [-1.0, 1.0]:
		for s in [-1.0, 1.0]:
			k.boxp(PLATE, Vector3(1.15, 0.85, 0.1), Vector3(s * 0.75, top + 0.45, e * 6.3), Vector3(e * 10.0, 0, 0), 0.04)
		for i in 5:
			var x := -1.0 + i * 0.5
			k.mesh(SANDBAG, _sphere(1.0), Transform3D(Basis.from_euler(Vector3(0, 0.2 * (i % 2), 0)).scaled(Vector3(0.27, 0.13, 0.17)), Vector3(x, top + 0.13, e * 5.95)))
		for i in 4:
			var x := -0.75 + i * 0.5
			k.mesh(SANDBAG, _sphere(1.0), Transform3D(Basis.from_euler(Vector3(0, -0.15 * (i % 2), 0)).scaled(Vector3(0.27, 0.13, 0.17)), Vector3(x, top + 0.36, e * 5.95)))
		# Tail / marker lamps.
		for s in [-1.0, 1.0]:
			k.mesh(LAMP_RED, _sphere(0.1), Transform3D(Basis.IDENTITY, Vector3(s * 1.2, 2.0, e * 6.45)))
		# End ladder up to the deck.
		for s in [-0.3, 0.3]:
			k.boxp(STEEL, Vector3(0.05, 2.0, 0.05), Vector3(s, 2.45, e * 6.5), Vector3.ZERO, 0.0)
		for i in 5:
			k.boxp(STEEL, Vector3(0.6, 0.04, 0.04), Vector3(0, 1.65 + i * 0.4, e * 6.5), Vector3.ZERO, 0.0)

	# Deck cargo.
	_ammo_crate(k, Vector3(0.7, top + 0.3, -4.4))
	_ammo_crate(k, Vector3(0.7, top + 0.3, -3.6))
	k.boxp(DARK, Vector3(0.8, 0.4, 0.55), Vector3(-0.75, top + 0.22, -4.3), Vector3(0, 8, 0), 0.04)
	k.boxp(RUST, Vector3(0.82, 0.08, 0.58), Vector3(-0.75, top + 0.44, -4.3), Vector3(0, 8, 0), 0.02)
	_ammo_crate(k, Vector3(-0.6, top + 0.3, 4.0))
	# Jerry cans and a spare wheel.
	for i in 3:
		k.boxp(BARREL, Vector3(0.18, 0.45, 0.34), Vector3(0.85 + i * 0.22 - 0.22, top + 0.25, 4.3), Vector3.ZERO, 0.03)
	k.cyl(DARK, 0.42, 0.42, 0.2, Transform3D(Basis.from_euler(Vector3(0, 0, deg_to_rad(80.0))), Vector3(0.95, top + 0.48, 3.0)), 14)
	k.cyl(RUST, 0.16, 0.16, 0.24, Transform3D(Basis.from_euler(Vector3(0, 0, deg_to_rad(80.0))), Vector3(0.95, top + 0.48, 3.0)), 8)


static func _ammo_crate(k: CarKit, p: Vector3) -> void:
	k.boxp(PLATE, Vector3(0.9, 0.45, 0.6), p, Vector3.ZERO, 0.04)
	k.boxp(HAZARD, Vector3(0.92, 0.08, 0.62), p + Vector3(0, 0.08, 0), Vector3.ZERO, 0.0)
	k.boxp(DARK, Vector3(0.3, 0.05, 0.1), p + Vector3(0, 0.25, 0), Vector3.ZERO, 0.0)


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 10
	m.rings = 5
	return m
