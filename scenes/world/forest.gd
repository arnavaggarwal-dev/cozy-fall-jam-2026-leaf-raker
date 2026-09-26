class_name Forest
extends Node3D

const PERIOD := 192.0
const HALF := PERIOD * 0.5
const TILE := 32.0
const TILES := 6
const PLANTING_CELLS := 46
const SPACING := PERIOD / PLANTING_CELLS
const TREE_CHANCE := 0.55
const TREE_GAP := 1.6
const BUCKET := 8.0
const BUCKETS := 24
const FOOTPRINT_SLICE := 0.08
const HEAD_CLEARANCE := 2.3
const FOLIAGE_BANDS := 10
const FADE_START := 2.0
const FADE_END := 6.0
const TREE_DRAW_RANGE := HALF - 2.0
const CLUTTER_DRAW_RANGE := 70.0
const HIDE_HEIGHTS := [0.3, 1.0]
const SETTLE_TUCK := 0.05
const SETTLE_SECONDS := 0.25
const STEP_UP := 0.25

enum Collision { NONE, TRUNK, WHOLE }
enum Foliage { NONE, CANOPY, WHOLE }

const TREE_TYPES := [
	["res://assets/models/scenery/nature/tree_oak_fall.glb", 7.0, 11.0],
	["res://assets/models/scenery/nature/tree_default_fall.glb", 7.0, 10.0],
	["res://assets/models/scenery/nature/tree_fat_fall.glb", 6.0, 9.0],
	["res://assets/models/scenery/nature/tree_detailed_fall.glb", 8.0, 12.0],
	["res://assets/models/scenery/survival/tree-autumn.glb", 7.0, 11.0],
	["res://assets/models/scenery/survival/tree-autumn-tall.glb", 10.0, 14.0],
	["res://assets/models/scenery/graveyard/pine-fall.glb", 8.0, 13.0],
	["res://assets/models/scenery/graveyard/pine-fall-crooked.glb", 7.0, 11.0],
]

const CLUTTER_TYPES := [
	["res://assets/models/scenery/nature/log.glb", 2.0, 3.2, false, Collision.WHOLE, Foliage.NONE, 70, true],
	["res://assets/models/scenery/nature/rock_largeA.glb", 0.8, 2.4, false, Collision.WHOLE, Foliage.NONE, 110, true],
	["res://assets/models/scenery/nature/plant_bushLarge.glb", 0.9, 1.6, true, Collision.NONE, Foliage.WHOLE, 160, false],
	["res://assets/models/scenery/nature/mushroom_tanGroup.glb", 0.3, 0.6, false, Collision.NONE, Foliage.NONE, 120, false],
	["res://assets/models/scenery/survival/tree-autumn-trunk.glb", 0.5, 0.9, true, Collision.WHOLE, Foliage.NONE, 60, false],
	["res://assets/models/scenery/nature/log_stack.glb", 1.6, 2.4, false, Collision.WHOLE, Foliage.NONE, 12, true],
	["res://assets/models/scenery/flowers/flower_1.glb", 0.25, 0.4, true, Collision.NONE, Foliage.NONE, 24, true],
	["res://assets/models/scenery/flowers/flower_1_clump.glb", 0.3, 0.5, true, Collision.NONE, Foliage.NONE, 19, true],
	["res://assets/models/scenery/flowers/flower_2.glb", 0.25, 0.4, true, Collision.NONE, Foliage.NONE, 24, true],
	["res://assets/models/scenery/flowers/flower_2_clump.glb", 0.3, 0.5, true, Collision.NONE, Foliage.NONE, 19, true],
	["res://assets/models/scenery/flowers/flower_3_clump.glb", 0.3, 0.5, true, Collision.NONE, Foliage.NONE, 19, true],
	["res://assets/models/scenery/flowers/flower_4_clump.glb", 0.3, 0.5, true, Collision.NONE, Foliage.NONE, 19, true],
	["res://assets/models/scenery/flowers/flower_5_clump.glb", 0.3, 0.5, true, Collision.NONE, Foliage.NONE, 16, true],
]

var _trunk_buckets := {}
var _blocker_buckets := {}
var _cover_buckets := {}
var _settled: Array[Dictionary] = []
var _settle_timer := 0.0
var _foliage: Array[Dictionary] = []
var _foliage_buckets := {}
var _multimeshes := {}
var _tile_roots := {}
var _models := {}
var _ghost: Node3D
var _ghost_foliage := -1
var _charred := {}
@export var _charred_material: StandardMaterial3D

@onready var player: Player = %Player
@onready var field: LeafWorld = %LeafWorld


static func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func wrap_position(p: Vector2) -> Vector2:
	return Vector2(fposmod(p.x + HALF, PERIOD) - HALF, fposmod(p.y + HALF, PERIOD) - HALF)


static func nearest_copy(p: Vector2, near: Vector2) -> Vector2:
	return near + wrap_position(p - near)


func build(rng_seed: int, clearings: Array[Vector3]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var batches := {}
	for gz in PLANTING_CELLS:
		for gx in PLANTING_CELLS:
			if rng.randf() >= TREE_CHANCE:
				continue
			var cell := Vector2(-HALF + gx * SPACING, -HALF + gz * SPACING)
			var type: Array = TREE_TYPES[rng.randi() % TREE_TYPES.size()]
			var height := rng.randf_range(type[1], type[2])
			var model := _model(type[0])
			var radius := maxf(model["foot_radius"] * height / maxf((model["box"] as AABB).size.y, 0.0001), 0.15)
			for attempt in 4:
				var p := wrap_position(cell + Vector2(rng.randf(), rng.randf()) * SPACING)
				if not _in_clearing(p, clearings, 1.5) and _trunk_gap(p, radius) >= TREE_GAP:
					_place(batches, type[0], true, TREE_DRAW_RANGE, p, height, true, rng.randf() * TAU, Collision.TRUNK, Foliage.CANOPY)
					break

	for type: Array in CLUTTER_TYPES:
		for i in type[6]:
			var p := Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF))
			if _in_clearing(p, clearings, 1.0) or nearest_obstacle_distance(p) < 1.5:
				continue
			_place(batches, type[0], false, CLUTTER_DRAW_RANGE, p, rng.randf_range(type[1], type[2]), type[3], rng.randf() * TAU, type[4], type[5], type[7])

	_build_multimeshes(batches)
	_update_tiles(Vector2.ZERO)


func _process(delta: float) -> void:
	_update_tiles(Forest.flat(player.position))
	_settle_timer -= delta
	if _settle_timer <= 0.0:
		_settle_timer = SETTLE_SECONDS
		settle_on(field, true)


func obstacles_near(rect: Rect2) -> Array[Vector4]:
	return _circles_near(_trunk_buckets, rect)


func nearest_obstacle_distance(p: Vector2) -> float:
	var best := INF
	for o in _circles_near(_blocker_buckets, Rect2(p, Vector2.ZERO).grow(BUCKET)):
		best = minf(best, p.distance_to(Vector2(o.x, o.y)) - o.z)
	return best


func push_out(p: Vector2, radius: float, height := -INF) -> Vector2:
	for o in _circles_near(_blocker_buckets, Rect2(p, Vector2.ZERO).grow(radius)):
		if height + STEP_UP >= o.w:
			continue
		var center := Vector2(o.x, o.y)
		var offset := p - center
		var dist := offset.length()
		if dist < o.z + radius and dist > 0.0001:
			p = center + offset / dist * (o.z + radius)
	return p


func floor_at(p: Vector2, feet: float) -> float:
	var best := 0.0
	for o in _circles_near(_blocker_buckets, Rect2(p, Vector2.ZERO)):
		if o.w <= feet + STEP_UP and p.distance_to(Vector2(o.x, o.y)) < o.z:
			best = maxf(best, o.w)
	return best


func hides(p: Vector2, margin: float) -> bool:
	for o in _circles_near(_cover_buckets, Rect2(p, Vector2.ZERO).grow(margin)):
		if p.distance_to(Vector2(o.x, o.y)) < o.z + margin:
			return true
	return HIDE_HEIGHTS.any(func(h: float) -> bool: return foliage_at(Vector3(p.x, h, p.y)) > 0.0)


func settle_on(leaves: LeafWorld, near_only := false) -> void:
	var here := Forest.flat(player.position)
	for entry in _settled:
		var center := nearest_copy(entry["center"], here)
		if near_only and not leaves.in_window(center):
			continue
		var ring: float = entry["radius"] + 0.1
		var rest := INF
		for k in 8:
			rest = minf(rest, leaves.sample_depth(center + Vector2.from_angle(k * TAU / 8.0) * ring))
		var placement: Transform3D = entry["placement"]
		var y := maxf(rest - SETTLE_TUCK, 0.0)
		if absf(placement.origin.y - y) < 0.005:
			continue
		placement.origin.y = y
		entry["placement"] = placement
		for blocker: Vector2 in entry.get("blockers", []):
			_set_top(blocker, y + entry["height"])
		var model := _model(entry["path"])
		var multimeshes: Array = _multimeshes[entry["path"]][entry["tile"]]
		for k in multimeshes.size():
			(multimeshes[k] as MultiMesh).set_instance_transform(entry["index"], _part_transform(model, placement, model["parts"][k]))


func foliage_at(point: Vector3) -> float:
	return _foliage_hit(point)[0]


func update_camera_foliage(camera_position: Vector3) -> void:
	var index: int = _foliage_hit(camera_position)[1]
	if index == _ghost_foliage:
		return
	_clear_ghost()
	if index >= 0:
		_ghost_foliage = index
		_set_instance_visible(index, false)
		_ghost = _make_ghost(_foliage[index])
		tree_anchor(index).add_child(_ghost)


func trees_near(p: Vector2, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for hit in _foliage_near(p, radius + BUCKET):
		var entry := _foliage[hit[0]]
		var trunk: Vector2 = entry["center"] + entry["trunk_offset"] + hit[1]
		if entry["tree"] and trunk.distance_to(p) <= radius:
			out.append({"index": hit[0], "position": trunk, "height": entry["height"], "radius": entry["trunk_radius"]})
	return out


func tree_anchor(index: int) -> Node3D:
	return _tile_roots[_foliage[index]["tile"]]


func tree_local_position(index: int) -> Vector3:
	var entry := _foliage[index]
	var trunk := nearest_copy(entry["center"] + entry["trunk_offset"], _tile_center(entry["tile"]))
	return Vector3(trunk.x, 0.0, trunk.y)


func is_charred(index: int) -> bool:
	return _charred.has(index)


func char_tree(index: int) -> void:
	if _charred.has(index):
		return
	if _ghost_foliage == index:
		_clear_ghost()
	_set_instance_visible(index, false)
	_charred[index] = _make_husk(_foliage[index])
	tree_anchor(index).add_child(_charred[index])
	var entry := _foliage[index]
	var model := _model(entry["path"])
	var top: float = ((model["husk"] as ArrayMesh).get_aabb().end.y - (model["box"] as AABB).position.y) * entry["scale"]
	_set_top(wrap_position(entry["center"] + entry["trunk_offset"]), top)


func _set_top(canonical: Vector2, top: float) -> void:
	var bucket: Array = _blocker_buckets.get(_buckets_in(Rect2(canonical, Vector2.ZERO))[0][0], [])
	for k in bucket.size():
		if Vector2(bucket[k].x, bucket[k].y).is_equal_approx(canonical):
			var o: Vector4 = bucket[k]
			o.w = top
			bucket[k] = o


func _update_tiles(view: Vector2) -> void:
	for tile: Vector2i in _tile_roots:
		var root: Node3D = _tile_roots[tile]
		var shift := nearest_copy(_tile_center(tile), view) - _tile_center(tile)
		if not is_equal_approx(root.position.x, shift.x) or not is_equal_approx(root.position.z, shift.y):
			root.position = Vector3(shift.x, 0.0, shift.y)


func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(-HALF + (tile.x + 0.5) * TILE, -HALF + (tile.y + 0.5) * TILE)


func _tile_of(p: Vector2) -> Vector2i:
	var canonical := wrap_position(p)
	return Vector2i(clampi(floori((canonical.x + HALF) / TILE), 0, TILES - 1), clampi(floori((canonical.y + HALF) / TILE), 0, TILES - 1))


func _foliage_hit(point: Vector3) -> Array:
	var p := Forest.flat(point)
	var best := [0.0, -1]
	for hit in _foliage_near(p, BUCKET):
		if _charred.has(hit[0]):
			continue
		var entry := _foliage[hit[0]]
		var s: float = entry["scale"]
		var profile: Dictionary = entry["profile"]
		var y := point.y / s
		if y < profile["y0"] or y > profile["y1"]:
			continue
		var band := clampi(int((y - profile["y0"]) / maxf(profile["y1"] - profile["y0"], 0.0001) * FOLIAGE_BANDS), 0, FOLIAGE_BANDS - 1)
		var radius: float = profile["radii"][band] * s
		var dist := p.distance_to(entry["center"] + hit[1])
		if dist < radius and 1.0 - dist / radius > best[0]:
			best = [1.0 - dist / radius, hit[0]]
	return best


func _foliage_near(p: Vector2, reach: float) -> Array[Array]:
	var out: Array[Array] = []
	for bucket in _buckets_in(Rect2(p, Vector2.ZERO).grow(reach)):
		for index: int in _foliage_buckets.get(bucket[0], []):
			out.append([index, bucket[1]])
	return out


func _circles_near(buckets: Dictionary, rect: Rect2) -> Array[Vector4]:
	var out: Array[Vector4] = []
	for bucket in _buckets_in(rect.grow(4.0)):
		for o: Vector4 in buckets.get(bucket[0], []):
			var center: Vector2 = Vector2(o.x, o.y) + bucket[1]
			if rect.grow(o.z).has_point(center):
				out.append(Vector4(center.x, center.y, o.z, o.w))
	return out


func _buckets_in(rect: Rect2) -> Array[Array]:
	var out: Array[Array] = []
	for bz in range(floori((rect.position.y + HALF) / BUCKET), floori((rect.end.y + HALF) / BUCKET) + 1):
		for bx in range(floori((rect.position.x + HALF) / BUCKET), floori((rect.end.x + HALF) / BUCKET) + 1):
			var wrapped := Vector2i(posmod(bx, BUCKETS), posmod(bz, BUCKETS))
			out.append([wrapped, Vector2(bx - wrapped.x, bz - wrapped.y) * BUCKET])
	return out


func _add_to_bucket(buckets: Dictionary, p: Vector2, value: Variant) -> void:
	var bucket: Vector2i = _buckets_in(Rect2(p, Vector2.ZERO))[0][0]
	buckets.get_or_add(bucket, []).append(value)


func _in_clearing(p: Vector2, clearings: Array[Vector3], margin: float) -> bool:
	return clearings.any(func(c: Vector3) -> bool: return p.distance_to(nearest_copy(Vector2(c.x, c.y), p)) < c.z + margin)


func _trunk_gap(p: Vector2, radius: float) -> float:
	var gap := INF
	for o in _circles_near(_trunk_buckets, Rect2(p, Vector2.ZERO).grow(radius + TREE_GAP)):
		gap = minf(gap, p.distance_to(Vector2(o.x, o.y)) - o.z - radius)
	return gap


func _place(batches: Dictionary, path: String, shadow: bool, draw_range: float, p: Vector2, size: float, by_height: bool, yaw: float, collision: int, foliage: int, on_leaves := false) -> void:
	var model := _model(path)
	var box: AABB = model["box"]
	var s := size / maxf(box.size.y if by_height else maxf(box.size.x, maxf(box.size.y, box.size.z)), 0.0001)
	var rotation := Basis(Vector3.UP, yaw)
	var placement := Transform3D(rotation.scaled(Vector3.ONE * s), Vector3(p.x, 0.0, p.y))
	var tile := _tile_of(p)
	var placements: Array = batches.get_or_add(path, {"shadow": shadow, "range": draw_range, "tiles": {}})["tiles"].get_or_add(tile, [])
	placements.append(placement)

	var foot_center: Vector2 = model["foot_center"]
	var foot_offset := rotation * Vector3(foot_center.x, 0.0, foot_center.y) * s
	var trunk_center := p + Forest.flat(foot_offset)
	var trunk_radius := maxf(model["foot_radius"] * s, 0.15)
	if collision != Collision.NONE:
		var canonical := wrap_position(trunk_center)
		if not on_leaves:
			_add_to_bucket(_trunk_buckets, canonical, Vector4(canonical.x, canonical.y, trunk_radius, INF))
		var block_radius := maxf(trunk_radius, _reach_below_head(model, size, s)) if collision == Collision.WHOLE else trunk_radius
		var top := box.size.y * s
		for circle in _footprint(canonical, box, s, rotation, block_radius, collision == Collision.WHOLE):
			_add_to_bucket(_blocker_buckets, Vector2(circle.x, circle.y), Vector4(circle.x, circle.y, circle.z, top))
	if collision != Collision.TRUNK:
		var cover_center := wrap_position(trunk_center)
		_add_to_bucket(_cover_buckets, cover_center, Vector4(cover_center.x, cover_center.y, maxf(trunk_radius, _reach_below_head(model, size, s)), INF))
	if on_leaves:
		_settled.append({"path": path, "tile": tile, "index": placements.size() - 1, "placement": placement, "center": trunk_center, "radius": trunk_radius})
		if collision != Collision.NONE:
			_settled[-1]["blockers"] = _footprint(wrap_position(trunk_center), box, s, rotation, 0.0, collision == Collision.WHOLE).map(func(c: Vector3) -> Vector2: return Vector2(c.x, c.y))
			_settled[-1]["height"] = box.size.y * s

	if foliage == Foliage.NONE:
		return
	var profile := _foliage_profile(model, foliage == Foliage.WHOLE)
	if profile.is_empty():
		return
	var axis_offset := rotation * Vector3(profile["axis"].x, 0.0, profile["axis"].y) * s
	var axis_center := p + Forest.flat(axis_offset)
	_add_to_bucket(_foliage_buckets, wrap_position(axis_center), _foliage.size())
	_foliage.append({
		"center": wrap_position(axis_center),
		"scale": s,
		"profile": profile,
		"path": path,
		"tile": tile,
		"index": placements.size() - 1,
		"placement": placement,
		"tree": collision == Collision.TRUNK,
		"trunk_offset": trunk_center - axis_center,
		"height": size,
		"trunk_radius": trunk_radius,
	})



func _footprint(center: Vector2, box: AABB, s: float, rotation: Basis, radius: float, whole: bool) -> Array[Vector3]:
	var span := Vector2(box.size.x, box.size.z) * s
	var length := maxf(span.x, span.y)
	var thick := minf(span.x, span.y)
	if not whole or length < thick * 1.8:
		return [Vector3(center.x, center.y, radius)]
	var axis := Forest.flat(rotation * (Vector3.RIGHT if span.x >= span.y else Vector3.BACK))
	var count := ceili(length / thick)
	var out: Array[Vector3] = []
	for i in count:
		var along := lerpf(-(length - thick) * 0.5, (length - thick) * 0.5, float(i) / maxf(count - 1, 1))
		var c := wrap_position(center + axis * along)
		out.append(Vector3(c.x, c.y, thick * 0.5))
	return out


func _reach_below_head(model: Dictionary, size: float, s: float) -> float:
	var key := roundi(size * 2.0)
	if not model["reach"].has(key):
		var box: AABB = model["box"]
		var axis: Vector2 = model["foot_center"] + Vector2(box.get_center().x, box.get_center().z)
		var reach := 0.0
		for v: Vector3 in model["vertices"]:
			if v.y < box.position.y + HEAD_CLEARANCE / s:
				reach = maxf(reach, Forest.flat(v).distance_to(axis))
		model["reach"][key] = reach * s
	return model["reach"][key]


func _foliage_profile(model: Dictionary, whole: bool) -> Dictionary:
	var key := "whole" if whole else "canopy"
	if model.has(key):
		return model[key]
	var box: AABB = model["box"]
	var center := Vector2(box.get_center().x, box.get_center().z)
	var trunk_axis: Vector2 = model["foot_center"] + center
	var cutoff := box.position.y + box.size.y * FOOTPRINT_SLICE
	var picked := PackedVector3Array()
	for v: Vector3 in model["vertices"]:
		if whole or (v.y > cutoff and Forest.flat(v).distance_to(trunk_axis) > model["foot_radius"] * 1.6):
			picked.append(v)
	model[key] = {}
	if picked.is_empty():
		return model[key]

	var axis := Vector2.ZERO
	var y0 := INF
	var y1 := -INF
	for v in picked:
		axis += Forest.flat(v)
		y0 = minf(y0, v.y)
		y1 = maxf(y1, v.y)
	axis /= picked.size()
	var radii := PackedFloat32Array()
	radii.resize(FOLIAGE_BANDS)
	for v in picked:
		var band := clampi(int((v.y - y0) / maxf(y1 - y0, 0.0001) * FOLIAGE_BANDS), 0, FOLIAGE_BANDS - 1)
		radii[band] = maxf(radii[band], Forest.flat(v).distance_to(axis))
	var below := radii.duplicate()
	var above := radii.duplicate()
	for band in range(1, FOLIAGE_BANDS):
		below[band] = maxf(below[band], below[band - 1])
		above[FOLIAGE_BANDS - 1 - band] = maxf(above[FOLIAGE_BANDS - 1 - band], above[FOLIAGE_BANDS - band])
	for band in FOLIAGE_BANDS:
		radii[band] = minf(below[band], above[band])
	model[key] = {"axis": axis - center, "y0": y0 - box.position.y, "y1": y1 - box.position.y, "radii": radii}
	return model[key]


func _model(path: String) -> Dictionary:
	if _models.has(path):
		return _models[path]
	var root := ItemDb.load_model(path)
	var box := ItemDb.compute_aabb(root)
	var parts := ItemDb.collect_mesh_parts(root)
	root.free()

	var vertices := PackedVector3Array()
	var cutoff := box.position.y + box.size.y * FOOTPRINT_SLICE
	var ground := PackedVector2Array()
	for part in parts:
		for surface in (part[0] as Mesh).get_surface_count():
			for v: Vector3 in (part[0] as Mesh).surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var world := (part[1] as Transform3D) * v
				vertices.append(world)
				if world.y <= cutoff:
					ground.append(Forest.flat(world))

	var foot_center := Vector2.ZERO
	var foot_radius := minf(box.size.x, box.size.z) * 0.25
	if not ground.is_empty():
		var centroid := Vector2.ZERO
		for g in ground:
			centroid += g
		centroid /= ground.size()
		var distances := PackedFloat32Array()
		for g in ground:
			distances.append(g.distance_to(centroid))
		distances.sort()
		foot_radius = distances[distances.size() / 2]
		foot_center = centroid - Vector2(box.get_center().x, box.get_center().z)

	_models[path] = {"box": box, "parts": parts, "vertices": vertices, "foot_center": foot_center, "foot_radius": foot_radius, "reach": {}, "variants": {}}
	return _models[path]


func _base_offset(model: Dictionary) -> Transform3D:
	var box: AABB = model["box"]
	return Transform3D(Basis.IDENTITY, -Vector3(box.get_center().x, box.position.y, box.get_center().z))


func _part_transform(model: Dictionary, placement: Transform3D, part: Array) -> Transform3D:
	return placement * _base_offset(model) * (part[1] as Transform3D)


func _set_instance_visible(index: int, visible_now: bool) -> void:
	if visible_now and _charred.has(index):
		return
	var entry := _foliage[index]
	var model := _model(entry["path"])
	var multimeshes: Array = _multimeshes[entry["path"]][entry["tile"]]
	var placement: Transform3D = entry["placement"]
	for k in multimeshes.size():
		var xform := _part_transform(model, placement, model["parts"][k]) if visible_now else Transform3D(Basis().scaled(Vector3.ZERO), placement.origin)
		(multimeshes[k] as MultiMesh).set_instance_transform(entry["index"], xform)


func _clear_ghost() -> void:
	if _ghost_foliage < 0:
		return
	_set_instance_visible(_ghost_foliage, true)
	_ghost.queue_free()
	_ghost = null
	_ghost_foliage = -1


func _make_ghost(entry: Dictionary) -> Node3D:
	var model := _model(entry["path"])
	var copy := Node3D.new()
	for part: Array in model["parts"]:
		var node := MeshInstance3D.new()
		node.mesh = part[0]
		node.transform = _part_transform(model, entry["placement"], part)
		var overrides := _ghost_materials(model, part[0])
		for surface in overrides.size():
			node.set_surface_override_material(surface, overrides[surface])
		copy.add_child(node)
	return copy


func _ghost_materials(model: Dictionary, mesh: Mesh) -> Array:
	var cache: Dictionary = model["variants"]
	if cache.has(mesh.get_instance_id()):
		return cache[mesh.get_instance_id()]
	var overrides := []
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as BaseMaterial3D
		var material_name := material.resource_name.to_lower() if material else "wood"
		if material_name.contains("wood") or material_name.contains("bark"):
			overrides.append(null)
			continue
		material = material.duplicate()
		material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		material.distance_fade_min_distance = FADE_START
		material.distance_fade_max_distance = FADE_END
		overrides.append(material)
	cache[mesh.get_instance_id()] = overrides
	return overrides


func _make_husk(entry: Dictionary) -> Node3D:
	var model := _model(entry["path"])
	if not model.has("husk"):
		model["husk"] = _husk_mesh(model)
	var node := MeshInstance3D.new()
	node.mesh = model["husk"]
	node.material_override = _charred_material
	node.transform = (entry["placement"] as Transform3D) * _base_offset(model)
	return node


func _husk_mesh(model: Dictionary) -> ArrayMesh:
	var box: AABB = model["box"]
	var cutoff := box.position.y + box.size.y * FOOTPRINT_SLICE
	var triangles: Array[Array] = []
	var wood := {}
	for k in model["parts"].size():
		var mesh: Mesh = model["parts"][k][0]
		var xform: Transform3D = model["parts"][k][1]
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for t in range(0, (vertices.size() if indices.is_empty() else indices.size()) - 2, 3):
				var corner := [t, t + 1, t + 2] if indices.is_empty() else [indices[t], indices[t + 1], indices[t + 2]]
				var key := "%d:%d" % [k, surface]
				if not uvs.is_empty():
					key += ":%d:%d" % [floori(uvs[corner[0]].x * 64.0), floori(uvs[corner[0]].y * 64.0)]
				var triangle := [key, xform * vertices[corner[0]], xform * vertices[corner[1]], xform * vertices[corner[2]]]
				triangles.append(triangle)
				if minf(triangle[1].y, minf(triangle[2].y, triangle[3].y)) <= cutoff:
					wood[key] = true
	var candidates := triangles.filter(func(t: Array) -> bool: return wood.has(t[0]))
	var sharing := {}
	for i in candidates.size():
		for v in 3:
			sharing.get_or_add(Vector3i((candidates[i][v + 1] * 1000.0).round()), []).append(i)
	var attached := {}
	var stack: Array[int] = []
	for i in candidates.size():
		if minf(candidates[i][1].y, minf(candidates[i][2].y, candidates[i][3].y)) <= cutoff:
			attached[i] = true
			stack.append(i)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		for v in 3:
			for j: int in sharing[Vector3i((candidates[i][v + 1] * 1000.0).round())]:
				if not attached.has(j):
					attached[j] = true
					stack.append(j)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(0xFFFFFFFF)
	for i: int in attached:
		for v in 3:
			tool.add_vertex(candidates[i][v + 1])
	tool.generate_normals()
	return tool.commit()


func _build_multimeshes(batches: Dictionary) -> void:
	for tz in TILES:
		for tx in TILES:
			_tile_roots[Vector2i(tx, tz)] = get_node("Tile%d_%d" % [tx, tz])
	for path: String in batches:
		var batch: Dictionary = batches[path]
		var model := _model(path)
		_multimeshes[path] = {}
		for tile: Vector2i in batch["tiles"]:
			var placements: Array = batch["tiles"][tile]
			var tile_multimeshes: Array[MultiMesh] = []
			for part: Array in model["parts"]:
				var multimesh := MultiMesh.new()
				multimesh.transform_format = MultiMesh.TRANSFORM_3D
				multimesh.mesh = part[0]
				multimesh.instance_count = placements.size()
				for k in placements.size():
					multimesh.set_instance_transform(k, _part_transform(model, placements[k], part))
				var node := MultiMeshInstance3D.new()
				node.multimesh = multimesh
				node.visibility_range_end = batch["range"]
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if batch["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_tile_roots[tile].add_child(node)
				tile_multimeshes.append(multimesh)
			_multimeshes[path][tile] = tile_multimeshes
