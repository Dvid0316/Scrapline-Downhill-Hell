class_name TrestleBuilder
extends Node3D
## Wooden rollercoaster-style trestles wherever the track stands high above
## the ground (see [method TerrainBuilder.is_trestle]): a bent every few
## metres with splayed legs, a cap beam, horizontal ties and X-bracing.
## All bents go into two MultiMeshes (posts/beams + braces), so a long
## trestle is still cheap to draw. Purely visual; no collision.

@export var route: RailRoute
@export var terrain: TerrainBuilder
@export var material: Material
## Metres between bents.
@export var spacing: float = 5.0
## Below this height the track sits on an embankment instead.
@export var min_height: float = 2.5
@export var post_size: float = 0.32
## Legs spread outward by this much per metre of height.
@export var splay: float = 0.08
## Height between horizontal ties.
@export var tie_spacing: float = 5.0

var bent_count: int = 0


func _ready() -> void:
	if route == null or terrain == null:
		push_error("TrestleBuilder: route/terrain missing")
		return
	build.call_deferred()


func build() -> void:
	for c in get_children():
		c.queue_free()
	var beams: Array[Transform3D] = []
	var braces: Array[Transform3D] = []
	bent_count = 0
	var length := route.get_length()
	var d := spacing * 0.5
	while d < length:
		if terrain.is_trestle(d) or terrain.track_lift(d) > min_height:
			_bent(d, beams, braces)
		d += spacing
	_add("Beams", beams)
	_add("Braces", braces)


func _bent(d: float, beams: Array[Transform3D], braces: Array[Transform3D]) -> void:
	var c := route.sample_world(d)
	var t := route.tangent_world(d)
	var right := t.cross(Vector3.UP).normalized()
	var top_y := c.y - 0.95
	var ground_c := terrain.sample_height(c.x, c.z)
	var h := top_y - ground_c
	if h < min_height:
		return
	bent_count += 1
	var tops: Array[Vector3] = []
	var bots: Array[Vector3] = []
	for s: float in [-1.0, 1.0]:
		var top: Vector3 = c + right * s * 1.25
		top.y = top_y
		var bot: Vector3 = c + right * s * (1.25 + splay * h)
		bot.y = terrain.sample_height(bot.x, bot.z) - 0.4
		tops.append(top)
		bots.append(bot)
		beams.append(_stick(bot, top, post_size))
	# Cap beam under the ballast deck.
	beams.append(_stick(tops[0] - right * 0.4, tops[1] + right * 0.4, post_size * 1.2))
	# Ties + X-braces, panel by panel from the top down.
	var lo := maxf(bots[0].y, bots[1].y)
	var y := top_y
	while y - lo > 1.5:
		var y2 := maxf(y - tie_spacing, lo + 0.3)
		var a0 := _on_leg(tops[0], bots[0], y)
		var a1 := _on_leg(tops[1], bots[1], y)
		var b0 := _on_leg(tops[0], bots[0], y2)
		var b1 := _on_leg(tops[1], bots[1], y2)
		beams.append(_stick(b0 - right * 0.2, b1 + right * 0.2, post_size * 0.8))
		braces.append(_stick(a0, b1, post_size * 0.55))
		braces.append(_stick(a1, b0, post_size * 0.55))
		y = y2


func _on_leg(top: Vector3, bot: Vector3, y: float) -> Vector3:
	var f := clampf((top.y - y) / maxf(top.y - bot.y, 0.01), 0.0, 1.0)
	return top.lerp(bot, f)


## Unit box stretched from a to b with a square cross-section.
func _stick(a: Vector3, b: Vector3, thick: float) -> Transform3D:
	var dir := b - a
	var len := dir.length()
	var z := dir / maxf(len, 0.001)
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	return Transform3D(Basis(x * thick, y * thick, z * len), (a + b) * 0.5)


func _add(n: String, xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)
