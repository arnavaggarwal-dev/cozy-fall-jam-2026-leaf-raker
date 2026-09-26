class_name LostItems
extends Node3D

const TILE_MARGIN := 2.0
const START_CLEARANCE := 8.0
const GLOW_FALLOFF := 1.2
const CHECK_SECONDS := 0.15
const BUTTERFLIES := 6
const BUTTERFLY_SPEED := 4.5
const BUTTERFLY_FADE_SECONDS := 1.2
const BUTTERFLY_LEAD := 2.2
const BUTTERFLY_SPACING := 1.1
const BUTTERFLY_HEIGHT := 1.35
const BUTTERFLY_NIGHT := 0.6

signal found(id: StringName, node: Node3D)

var items: Array[Dictionary] = []
var found_count := 0

var _rng := RandomNumberGenerator.new()
var _check_timer := 0.0
var _butterfly_xforms: Array[Transform3D] = []
var _butterfly_velocities: Array[Vector3] = []
@export var _butterfly_material: ShaderMaterial
var _brightness := 0.0
var _flash: Tween

@onready var butterfly_light: OmniLight3D = $ButterflyLight
@onready var butterflies: MultiMeshInstance3D = $Butterflies
@onready var flash_light: OmniLight3D = $FlashLight
@onready var field: LeafWorld = %LeafWorld
@onready var forest: Forest = %Forest
@onready var burrows: Burrows = %Burrows
@onready var day_night: DayNight = %DayNight
@onready var player: Player = %Player


func _ready() -> void:
	for i in BUTTERFLIES:
		_butterfly_xforms.append(Transform3D.IDENTITY)
		_butterfly_velocities.append(Vector3.ZERO)
		butterflies.multimesh.set_instance_custom_data(i, Color(randf(), 14.0, 0.0, 0.0))
	_set_brightness(0.0)


func scatter(item_seed: int) -> void:
	_rng.seed = item_seed
	var already := {}
	for item in items:
		if item["found"]:
			already[item["id"]] = true
		elif is_instance_valid(item["node"]):
			item["node"].queue_free()
	items.clear()
	found_count = 0

	var free_tiles := _shuffled_tiles()
	for def in ItemDb.lost_things():
		if already.has(def.id):
			items.append({"id": def.id, "index": def.lost_index, "node": null, "pos": Vector2.ZERO, "found": true})
			found_count += 1
			continue
		var holder := ItemDb.spawn_model(def.id)
		var size: Vector3 = holder.get_meta("size")
		var reveal_depth := maxf(0.03, size.y * 0.6)
		var pos := _claim_spot(free_tiles, size.y + 0.1)
		if pos == Vector2.INF:
			pos = _claim_spot(free_tiles, reveal_depth + 0.05)
		if pos == Vector2.INF:
			pos = _claim_spot(_shuffled_tiles(), reveal_depth + 0.05)
		if pos == Vector2.INF:
			push_warning("nowhere has leaves deep enough to hide the %s" % def.id)
			pos = Vector2(Forest.TILE, 0.0)
		_hide(def, holder, pos, _rng.randf() * TAU)
	check()


func restore(entries: Array) -> void:
	items.clear()
	found_count = 0
	for entry: Dictionary in entries:
		var def := ItemDb.get_item(entry["id"])
		if def == null:
			continue
		if entry["found"]:
			items.append({"id": def.id, "index": def.lost_index, "node": null, "pos": entry["pos"], "found": true})
			found_count += 1
		else:
			_hide(def, ItemDb.spawn_model(def.id), entry["pos"], entry["rot"])
	check()


func save_state() -> Array:
	return items.map(func(item: Dictionary) -> Dictionary:
		return {"id": item["id"], "pos": item["pos"], "found": item["found"], "rot": (item["node"] as Node3D).rotation.y if item["node"] else 0.0})


func _hide(def: ItemData, holder: Node3D, pos: Vector2, rot: float) -> void:
	var size: Vector3 = holder.get_meta("size")
	holder.position = Vector3(pos.x, 0.0, pos.y)
	holder.rotation.y = rot
	add_child(holder)
	items.append({
		"id": def.id,
		"index": def.lost_index,
		"node": holder,
		"pos": pos,
		"radius": maxf(size.x, size.z) * 0.3,
		"reveal_depth": maxf(0.03, size.y * 0.6),
		"cover": field.procedural_depth(pos),
		"found": false,
	})


func _shuffled_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for tz in Forest.TILES:
		for tx in Forest.TILES:
			tiles.append(Vector2i(tx, tz))
	for i in range(tiles.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap := tiles[i]
		tiles[i] = tiles[j]
		tiles[j] = swap
	return tiles


func _claim_spot(tiles: Array[Vector2i], min_depth: float) -> Vector2:
	for k in tiles.size():
		var p := _spot_in_tile(tiles[k], min_depth)
		if p != Vector2.INF:
			tiles.remove_at(k)
			return p
	return Vector2.INF


func _spot_in_tile(tile: Vector2i, min_depth: float) -> Vector2:
	var corner := Vector2(-Forest.HALF + tile.x * Forest.TILE, -Forest.HALF + tile.y * Forest.TILE)
	for attempt in 80:
		var p := corner + Vector2(_rng.randf_range(TILE_MARGIN, Forest.TILE - TILE_MARGIN), _rng.randf_range(TILE_MARGIN, Forest.TILE - TILE_MARGIN))
		if Forest.wrap_position(p - Main.TOILET_HOME).length() < 6.0 or Forest.wrap_position(p).length() < START_CLEARANCE:
			continue
		if forest.nearest_obstacle_distance(p) >= 1.2 and not forest.hides(p, 0.4) and field.procedural_depth(p) >= min_depth:
			return p
	return Vector2.INF


func names() -> Array[String]:
	var out: Array[String] = []
	for item in items:
		out.append(ItemDb.display_name(item["id"]))
	return out


func get_item(id: StringName) -> Dictionary:
	for item in items:
		if item["id"] == id:
			return item
	return {}


func unfound_near(p: Vector2, radius: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for item in items:
		var pos := Forest.nearest_copy(item["pos"], p)
		if not item["found"] and pos.distance_to(p) <= radius:
			out.append(pos)
	return out


func nearest_unfound(p: Vector2) -> Dictionary:
	var best := {}
	for item in items:
		if not item["found"] and (best.is_empty() or Forest.nearest_copy(item["pos"], p).distance_to(p) < Forest.nearest_copy(best["pos"], p).distance_to(p)):
			best = item
	return best


func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = CHECK_SECONDS
		check()
	_guide_to_lantern(delta)


func check() -> void:
	var glows: Array[Vector3] = []
	var here := Forest.flat(player.camera.global_position)
	for item in items:
		if item["found"]:
			continue
		var pos := Forest.nearest_copy(item["pos"], here)
		var node: Node3D = item["node"]
		node.position = Vector3(pos.x, 0.0, pos.y)
		if field.in_window(pos):
			item["cover"] = field.cover_depth(pos, item["radius"])
			if item["cover"] < item["reveal_depth"]:
				item["found"] = true
				item["node"] = null
				found_count += 1
				flash(node.position)
				found.emit(item["id"], node)
				continue
		glows.append(_glow(pos, item["cover"]))
	for burrow in burrows.burrows:
		var spot := Forest.nearest_copy(burrow["pos"], here)
		if field.in_window(spot):
			glows.append(_glow(spot, field.cover_depth(spot, burrows._acorn_radius)))
	field.set_item_glows(glows)
	field.set_glow_intensity(lerpf(2.25, 7.5, day_night.daylight))


func _glow(pos: Vector2, cover: float) -> Vector3:
	return Vector3(pos.x, pos.y, snappedf(exp(-GLOW_FALLOFF * cover), 0.05))


func fly_to_viewer(node: Node3D) -> void:
	if node.get_parent() != self:
		node.reparent(self)
	var tween := create_tween()
	tween.tween_property(node, "position:y", node.position.y + 1.1, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(node, "rotation:y", node.rotation.y + TAU * 2.0, 1.2)
	tween.parallel().tween_property(node, "scale", Vector3.ONE * 1.8, 0.7)
	tween.tween_interval(0.2)
	tween.tween_method(func(t: float) -> void: node.global_position = node.global_position.lerp(player.camera.global_position + Vector3.DOWN * 0.4, t), 0.0, 1.0, 0.45)
	tween.parallel().tween_property(node, "scale", Vector3.ONE * 0.2, 0.45)
	tween.tween_callback(node.queue_free)


func flash(where: Vector3) -> void:
	if _flash:
		_flash.kill()
	flash_light.global_position = where + Vector3.UP * 0.8
	flash_light.light_energy = 4.0
	flash_light.visible = true
	_flash = create_tween()
	_flash.tween_property(flash_light, "light_energy", 0.0, 1.6)
	_flash.tween_callback(flash_light.hide)


func _guide_to_lantern(delta: float) -> void:
	var lantern := get_item(&"old_lantern")
	if lantern.is_empty():
		return
	var was_hidden := _brightness <= 0.0
	_set_brightness(move_toward(_brightness, 1.0 if 1.0 - day_night.daylight > BUTTERFLY_NIGHT and not lantern["found"] else 0.0, delta / BUTTERFLY_FADE_SECONDS))
	if _brightness <= 0.0:
		return

	var from := player.global_position
	var spot := Forest.nearest_copy(lantern["pos"], Forest.flat(player.position))
	var target := Vector3(spot.x, field.sample_depth(spot), spot.y)
	var to_target := Vector2(target.x - from.x, target.z - from.z)
	var distance := to_target.length()
	var direction := to_target / distance if distance > 0.01 else Vector2.ZERO
	var t := Time.get_ticks_msec() / 1000.0
	var center := Vector3.ZERO
	for i in BUTTERFLIES:
		var along := BUTTERFLY_LEAD + i * BUTTERFLY_SPACING
		var goal: Vector3
		if along < distance - 0.8:
			var ground := Forest.flat(from) + direction * along
			goal = Vector3(ground.x, from.y + BUTTERFLY_HEIGHT, ground.y)
		else:
			var angle := t * 1.4 + i * TAU / BUTTERFLIES
			goal = target + Vector3(cos(angle) * 0.7, 0.8 + 0.25 * sin(t * 2.0 + i), sin(angle) * 0.7)
		goal += Vector3(sin(t * 1.9 + i * 1.7), sin(t * 2.7 + i) * 0.5, cos(t * 1.6 + i * 2.3)) * 0.35

		if was_hidden:
			_butterfly_xforms[i].origin = from + Vector3(randf_range(-1.0, 1.0), BUTTERFLY_HEIGHT, randf_range(-1.0, 1.0))
			_butterfly_velocities[i] = Vector3.ZERO
		_butterfly_velocities[i] = _butterfly_velocities[i].lerp((goal - _butterfly_xforms[i].origin).limit_length(BUTTERFLY_SPEED), 1.0 - exp(-delta * 3.0))
		var velocity := _butterfly_velocities[i]
		var p := _butterfly_xforms[i].origin + velocity * delta
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		var basis := Basis.looking_at(flat.normalized(), Vector3.UP, true) if flat.length() > 0.1 else _butterfly_xforms[i].basis.orthonormalized()
		_butterfly_xforms[i] = Transform3D(basis, p)
		butterflies.multimesh.set_instance_transform(i, _butterfly_xforms[i])
		var custom := butterflies.multimesh.get_instance_custom_data(i)
		custom.g = 12.0 + velocity.length() * 3.0
		butterflies.multimesh.set_instance_custom_data(i, custom)
		center += p
	butterfly_light.global_position = center / BUTTERFLIES


func _set_brightness(value: float) -> void:
	_brightness = value
	_butterfly_material.set_shader_parameter("brightness", value)
	butterfly_light.light_energy = value
	butterfly_light.visible = value > 0.0
	butterflies.visible = value > 0.0

