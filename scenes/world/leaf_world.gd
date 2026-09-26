class_name LeafWorld
extends Node3D

const SIM_SHADER := preload("res://shaders/leaf_sim.glsl")
const PATCH_SHADER := preload("res://shaders/leaf_patch.glsl")

const CELL := 0.1
const TILE_CELLS := 80
const TILE_SIZE := 8.0
const WINDOW_TILES := 7
const WINDOW_CELLS := TILE_CELLS * WINDOW_TILES
const WINDOW_SIZE := TILE_SIZE * WINDOW_TILES
const TILE_COUNT := WINDOW_TILES * WINDOW_TILES
const STATE_WIDTH := 1024
const ROWS_PER_TILE := 156
const LEAVES_PER_TILE := STATE_WIDTH * ROWS_PER_TILE
const PATCH := 64
const PATCH_MARGIN := 16
const PERIOD_TILES := 24
const PERIOD_CELLS := PERIOD_TILES * TILE_CELLS
const BLEND_CELLS := 240
const FAR_CELLS := 480
const FAR_CELL := Forest.PERIOD / FAR_CELLS
const LOD_DISTANCE := 6.0

const BASE_DEPTH := 0.3
const DRIFT_DEPTH := 0.32
const DRIFT_FREQUENCY := 0.075
const DETAIL_DEPTH := 0.05
const DETAIL_FREQUENCY := 0.7
const TRUNK_DRIFT := 0.22
const TRUNK_DRIFT_WIDTH := 1.4
const CLEARING_FADE := 1.8
const VISIBLE_DEPTH := 0.07

const RAKE_HALF_WIDTH := 0.34
const RAKE_TOLERANCE := 0.03
const BITE_DEPTH := 0.18
const WINDROW_HEIGHT := 0.4
const MIN_BAND := 0.14
const MAX_BAND := 1.0
const FEET_CLEARANCE := 0.4
const HOP_SECONDS := 0.6
const RELAX_MAX_STEP := 0.08
const RELAX_RATE := 0.35
const RELAX_FRAMES := 90
const GLOW_CELLS := 256
const GLOW_RADIUS := 0.7
const PREWARM_TASKS := 3

const MODE_SCATTER := 0
const MODE_STEP := 1
const MODE_BLAST := 2
const BLAST_FLIGHT_SECONDS := 1.9
const FLAG_RAKE := 1
const FLAG_RELAX := 2
const FLAG_VANISH := 4
const MODE_ROT := 3
const ROT_SECONDS := 2.5
const ROT_TICK := 0.1

var window_origin := Vector2.ZERO
var leaf_seed := 0
var rake_half_width := RAKE_HALF_WIDTH

var _clearings: Array[Vector3] = []
var _player_pos := Vector2.ZERO
var _packed := PackedFloat32Array()
var _loose := PackedFloat32Array()
var _window_tile := Vector2i.ZERO
var _window_ready := false
var _tile_cache := {}
var _dirty_tiles := {}
var _edited := {}
var _pending_craters := {}
var _tile_generation := 0
var _tile_tasks := {}
var _finished_tiles: Array[Array] = []
var _tiles_mutex := Mutex.new()
var _slot_tiles: Array[Vector2i] = []
var _slot_bounds: Array[Rect2] = []
var _slot_draws: Array[Array] = []
var _last_active_slots: Array[int] = []

var _drift_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _far_noise := FastNoiseLite.new()
var _far_image: Image
var _far_texture := ImageTexture.new()
var _state_textures: Array[Texture2DRD] = [Texture2DRD.new(), Texture2DRD.new(), Texture2DRD.new()]
var _window_textures: Array[Texture2DRD] = [Texture2DRD.new(), Texture2DRD.new()]
@export var _draw_material: ShaderMaterial
var _glow_texture := ImageTexture.create_from_image(Image.create_empty(GLOW_CELLS, GLOW_CELLS, false, Image.FORMAT_RF))
var _glows: Array[Vector3] = []

var _frame_seed := 0
var _hop_timer := 0.0
var _flight_timer := 0.0
var _flight_slots: Array[int] = []
var _blast_center := Vector2.ZERO
var _patch_origin := Vector2i.ZERO
var _prev_packed := PackedFloat32Array()
var _prev_taken := false
var _patch_changed := false
var _flow := PackedFloat32Array()
var _relax_delta := PackedFloat32Array()
var _relax_frames_left := 0
var _relax_rect := Rect2()
var _rotting := {}
var _rot_timer := 0.0
var _rot_mask := PackedFloat32Array()

var _rake_this_frame := false
var _rake_rect := Rect2()
var _rake_a := Vector4()
var _rake_b := Vector4()
var _rake_c := Vector3()

var _rd: RenderingDevice
var _sim_shader: RID
var _sim_pipeline: RID
var _patch_shader: RID
var _patch_pipeline: RID
var _state_rids: Array[RID] = []
var _window_rids: Array[RID] = []
var _patch_rids: Array[RID] = []
var _prev_rid: RID
var _flow_rid: RID
var _rot_rid: RID
var _linear_sampler: RID
var _nearest_sampler: RID
var _sim_set: RID
var _patch_sets: Array[RID] = []

@onready var forest: Forest = %Forest
@onready var terrain_material: ShaderMaterial = ($Terrain as MeshInstance3D).material_override


func _init() -> void:
	_flow.resize(PATCH * PATCH * 4)
	_relax_delta.resize(PATCH * PATCH)
	_rot_mask.resize(WINDOW_CELLS * WINDOW_CELLS)


func _exit_tree() -> void:
	for task: int in _tile_tasks.values():
		WorkerThreadPool.wait_for_task_completion(task)
	_tile_tasks.clear()
	for texture in _state_textures + _window_textures:
		texture.texture_rd_rid = RID()
	RenderingServer.call_on_render_thread(_rd_free)


func setup(rng_seed: int, clearings: Array[Vector3]) -> void:
	leaf_seed = rng_seed
	_clearings = clearings
	_configure_noise(rng_seed)
	_build_far_image()
	_build_draws()
	terrain_material.set_shader_parameter("near_packed", _window_textures[0])
	terrain_material.set_shader_parameter("near_loose", _window_textures[1])
	terrain_material.set_shader_parameter("far_depth", _far_texture)
	terrain_material.set_shader_parameter("glow_map", _glow_texture)
	RenderingServer.call_on_render_thread(_rd_create)


func reset_leaves(rng_seed: int) -> void:
	leaf_seed = rng_seed
	_edited.clear()
	_tile_generation += 1
	_rotting.clear()
	_configure_noise(rng_seed)
	_tile_cache.clear()
	_dirty_tiles.clear()
	_pending_craters.clear()
	_build_far_image()
	_slot_tiles.clear()
	_slot_bounds.clear()
	_window_ready = false
	update_window(_player_pos)


func save_state() -> Dictionary:
	if _window_ready:
		_store_dirty_tiles()
	var tiles := {}
	for key: Vector2i in _edited:
		tiles[key] = [_tile_cache[key][0], _tile_cache[key][1]]
	return {"tiles": tiles, "pending": _pending_craters, "rotting": _rotting}


func load_state(state: Dictionary) -> void:
	_pending_craters = state["pending"]
	_rotting = state["rotting"]
	for key: Vector2i in state["tiles"]:
		_store_tile(key, state["tiles"][key][0], state["tiles"][key][1])
	_far_texture.update(_far_image)


func update_window(center: Vector2) -> void:
	_player_pos = center
	var tile := Vector2i(floori(center.x / TILE_SIZE), floori(center.y / TILE_SIZE)) - Vector2i(WINDOW_TILES / 2, WINDOW_TILES / 2)
	if _window_ready and tile == _window_tile:
		return
	if _window_ready:
		_store_dirty_tiles()
	_window_tile = tile
	window_origin = Vector2(tile) * TILE_SIZE
	_load_window()

	var wanted := {}
	for tz in WINDOW_TILES:
		for tx in WINDOW_TILES:
			wanted[tile + Vector2i(tx, tz)] = true
	var reinit: Array[int] = []
	if _slot_tiles.is_empty():
		for key: Vector2i in wanted:
			reinit.append(_slot_tiles.size())
			_slot_tiles.append(key)
			_slot_bounds.append(Rect2())
	else:
		for slot in TILE_COUNT:
			if not wanted.erase(_slot_tiles[slot]):
				reinit.append(slot)
		var entering: Array = wanted.keys()
		for k in reinit.size():
			_slot_tiles[reinit[k]] = entering[k]

	_frame_seed = (_frame_seed + 1) % 1_000_000
	var params: Array[PackedByteArray] = []
	for slot in reinit:
		_flight_slots.erase(slot)
		var tile_min := Vector2(_slot_tiles[slot]) * TILE_SIZE
		_slot_bounds[slot] = Rect2(tile_min, Vector2.ONE * TILE_SIZE)
		_apply_slot_bounds(slot)
		var deepest: float = _tile_data(_slot_tiles[slot])[2]
		params.append(_params(MODE_SCATTER, 0, slot, Vector4(tile_min.x, tile_min.y, TILE_SIZE, maxf(deepest, 0.01)), 0.0, _rake_a, _rake_b, _rake_c))
	_relax_frames_left = 0
	_hop_timer = 0.0
	_last_active_slots.clear()
	terrain_material.set_shader_parameter("near_origin", window_origin)
	_paint_glow_map()
	RenderingServer.call_on_render_thread(_rd_load_window.bind(_packed.to_byte_array(), _loose.to_byte_array(), params))
	_window_ready = true


func set_glow_intensity(intensity: float) -> void:
	_draw_material.set_shader_parameter("glow_intensity", intensity)
	terrain_material.set_shader_parameter("glow_intensity", intensity)


func set_item_glows(glows: Array[Vector3]) -> void:
	if glows != _glows:
		_glows = glows.duplicate()
		_paint_glow_map()


func in_window(p: Vector2) -> bool:
	var local := p - window_origin
	return local.x >= 0.0 and local.y >= 0.0 and local.x < WINDOW_SIZE and local.y < WINDOW_SIZE


func sample_depth(p: Vector2) -> float:
	if not _window_ready or not in_window(p):
		return procedural_depth(p)
	var fx := (p.x - window_origin.x) / CELL - 0.5
	var fz := (p.y - window_origin.y) / CELL - 0.5
	var x0 := clampi(floori(fx), 0, WINDOW_CELLS - 1)
	var z0 := clampi(floori(fz), 0, WINDOW_CELLS - 1)
	var x1 := mini(x0 + 1, WINDOW_CELLS - 1)
	var z1 := mini(z0 + 1, WINDOW_CELLS - 1)
	var tx := clampf(fx - x0, 0.0, 1.0)
	var top := lerpf(_packed[z0 * WINDOW_CELLS + x0] + _loose[z0 * WINDOW_CELLS + x0], _packed[z0 * WINDOW_CELLS + x1] + _loose[z0 * WINDOW_CELLS + x1], tx)
	var bottom := lerpf(_packed[z1 * WINDOW_CELLS + x0] + _loose[z1 * WINDOW_CELLS + x0], _packed[z1 * WINDOW_CELLS + x1] + _loose[z1 * WINDOW_CELLS + x1], tx)
	return lerpf(top, bottom, clampf(fz - z0, 0.0, 1.0))


func cover_depth(p: Vector2, radius: float) -> float:
	var deepest := 0.0
	for offset: Vector2 in [Vector2.ZERO, Vector2(radius, 0.0), Vector2(-radius, 0.0), Vector2(0.0, radius), Vector2(0.0, -radius)]:
		deepest = maxf(deepest, sample_depth(p + offset))
	return deepest


func procedural_depth(p: Vector2) -> float:
	var cell := Vector2(fposmod(p.x, Forest.PERIOD), fposmod(p.y, Forest.PERIOD)) / CELL
	var d := BASE_DEPTH + DRIFT_DEPTH * _periodic_noise_point(_drift_noise, cell) + DETAIL_DEPTH * (_periodic_noise_point(_detail_noise, cell) * 2.0 - 1.0)
	var in_trunk := false
	for o in forest.obstacles_near(Rect2(p, Vector2.ZERO).grow(TRUNK_DRIFT_WIDTH)):
		var r := p.distance_to(Vector2(o.x, o.y))
		if r < o.z:
			in_trunk = true
		elif r < o.z + TRUNK_DRIFT_WIDTH:
			var t := 1.0 - (r - o.z) / TRUNK_DRIFT_WIDTH
			d += TRUNK_DRIFT * t * t
	if in_trunk:
		d = 0.0
	for c in _clearings:
		d *= smoothstep(c.z, c.z + CLEARING_FADE, p.distance_to(Forest.nearest_copy(Vector2(c.x, c.y), p)))
	return d


func apply_rake(prev: Vector2, cur: Vector2, forward: Vector2, player_pos: Vector2) -> float:
	var along := (cur - prev).dot(forward)
	var move := absf(along)
	if move < 0.002 or not in_window(cur):
		return 0.0
	var dir := forward * signf(along)
	var side := Vector2(-dir.y, dir.x)
	var reach := move + RAKE_TOLERANCE
	_ensure_patch_around(_cell_of(cur))
	if not _prev_taken:
		_prev_taken = true
		_prev_packed = _patch_slice(_packed)

	var max_band := MAX_BAND
	var toward_player := (player_pos - cur).dot(dir)
	if toward_player > 0.0:
		max_band = clampf(toward_player - FEET_CLEARANCE, MIN_BAND, MAX_BAND)

	var swept := PackedInt32Array()
	var loose_swept := 0.0
	var ahead := 0.0
	var box := _rect_cells(cur, dir, side, -reach, max_band)
	for iz in range(box.position.y, box.end.y):
		for ix in range(box.position.x, box.end.x):
			var rel := _cell_center(ix, iz) - cur
			if absf(rel.dot(side)) > rake_half_width:
				continue
			var v := rel.dot(dir)
			var i := iz * WINDOW_CELLS + ix
			if v <= 0.0 and v >= -reach:
				swept.append(i)
				loose_swept += _loose[i]
			elif v > 0.0 and v <= max_band:
				ahead += _loose[i]
	if swept.is_empty():
		return 0.0

	var area := CELL * CELL
	var room := maxf(2.0 * rake_half_width * max_band * WINDROW_HEIGHT - ahead * area, 0.0)
	var take_loose := 1.0
	if loose_swept * area > room:
		take_loose = room / (loose_swept * area)
	var moved := loose_swept * take_loose * area
	var cut := minf(BITE_DEPTH * move / reach, maxf(room - moved, 0.0) / (swept.size() * area))
	for i in swept:
		_loose[i] *= 1.0 - take_loose
		var take := minf(_packed[i], cut)
		_packed[i] -= take
		moved += take * area

	var band := clampf((ahead * area + moved) / (2.0 * rake_half_width * WINDROW_HEIGHT), MIN_BAND, max_band)
	if moved > 0.0:
		var targets := PackedInt32Array()
		box = _rect_cells(cur, dir, side, 0.0, band)
		for iz in range(box.position.y, box.end.y):
			for ix in range(box.position.x, box.end.x):
				var rel := _cell_center(ix, iz) - cur
				var v := rel.dot(dir)
				if absf(rel.dot(side)) <= rake_half_width and v > 0.0 and v <= band:
					targets.append(iz * WINDOW_CELLS + ix)
		if targets.is_empty():
			var ahead_cell := _cell_of(cur + dir * CELL)
			targets.append(ahead_cell.y * WINDOW_CELLS + ahead_cell.x)
		for i in targets:
			_loose[i] += moved / area / targets.size()
		_relax_frames_left = RELAX_FRAMES

	var touched := _world_rect(cur, dir, side, -reach, band)
	_rake_rect = touched if _rake_rect.size == Vector2.ZERO else _rake_rect.merge(touched)
	_grow_slots(_world_rect(cur, dir, side, -reach, 0.0), touched)
	_mark_dirty(touched)
	_patch_changed = true
	_rake_this_frame = true
	_rake_a = Vector4(cur.x, cur.y, dir.x, dir.y)
	_rake_b = Vector4(side.x, side.y, rake_half_width, reach)
	_rake_c = Vector3(band, cut, take_loose)
	return moved


func blast(center: Vector2, radius: float, ring: float, vanish := false) -> void:
	if not _window_ready:
		return
	var outer := radius if vanish else radius + ring
	_blast_stored(center, radius)
	var local := (center - window_origin) / CELL - Vector2(0.5, 0.5)
	var reach := outer / CELL
	var inner := radius * 0.6 / CELL
	var edge := radius / CELL
	var moved := 0.0
	var ring_cells := PackedInt32Array()
	for iz in range(maxi(floori(local.y - reach), 0), mini(ceili(local.y + reach) + 1, WINDOW_CELLS)):
		var dz := iz - local.y
		var span := reach * reach - dz * dz
		if span < 0.0:
			continue
		span = sqrt(span)
		var row := iz * WINDOW_CELLS
		for ix in range(maxi(floori(local.x - span), 0), mini(ceili(local.x + span) + 1, WINDOW_CELLS)):
			var dx := ix - local.x
			var d := sqrt(dx * dx + dz * dz)
			if d > reach:
				continue
			var i := row + ix
			if d <= inner:
				moved += _packed[i] + _loose[i]
				_packed[i] = 0.0
				_loose[i] = 0.0
			elif d < edge:
				var share := 1.0 - smoothstep(inner, edge, d)
				moved += (_packed[i] + _loose[i]) * share
				_packed[i] *= 1.0 - share
				_loose[i] *= 1.0 - share
			else:
				ring_cells.append(i)
	if moved <= 0.0 or (ring_cells.is_empty() and not vanish):
		return
	if not vanish:
		for i in ring_cells:
			_loose[i] += moved / ring_cells.size()

	var bounds := Rect2(center - Vector2.ONE * outer, Vector2.ONE * outer * 2.0)
	_mark_dirty(bounds)
	_grow_slots(bounds, bounds)
	_relax_frames_left = 0
	var rect := bounds.grow(CELL * 2.0)
	if _flight_timer <= 0.0:
		_flight_slots.clear()
	for slot in _slots_touching(rect):
		if not _flight_slots.has(slot):
			_flight_slots.append(slot)
	_frame_seed = (_frame_seed + 1) % 1_000_000
	var params: Array[PackedByteArray] = []
	for slot in _flight_slots:
		params.append(_params(MODE_BLAST, FLAG_VANISH if vanish else 0, slot, Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y), 0.0,
			Vector4(center.x, center.y, 0.0, 0.0), Vector4(0.0, 0.0, radius, ring), Vector3.ZERO))
	_blast_center = center
	_flight_timer = BLAST_FLIGHT_SECONDS
	RenderingServer.call_on_render_thread(_rd_load_window.bind(_packed.to_byte_array(), _loose.to_byte_array(), params))


func _process(delta: float) -> void:
	if not _window_ready:
		return
	terrain_material.set_shader_parameter("grid_center", (_player_pos / 0.4).round() * 0.4)
	_prewarm_tiles()
	_rot_timer -= delta
	if not _rotting.is_empty() and _rot_timer <= 0.0:
		_rot_timer = ROT_TICK
		_rot_step()
	_frame_seed = (_frame_seed + 1) % 1_000_000

	var relaxing := false
	if _relax_frames_left > 0 and _frame_seed % 2 == 0:
		relaxing = _relax_step()
		_relax_frames_left = _relax_frames_left - 1 if relaxing else 0
	_hop_timer = HOP_SECONDS if _rake_this_frame else maxf(_hop_timer - delta, 0.0)
	_flight_timer = maxf(_flight_timer - minf(delta, 0.1), 0.0)
	if not (_patch_changed or _hop_timer > 0.0 or _flight_timer > 0.0):
		_end_frame()
		return

	var active := _rake_rect
	if relaxing:
		active = _relax_rect if active.size == Vector2.ZERO else active.merge(_relax_rect)
	var rect := Vector4(1.0, 1.0, -1.0, -1.0)
	if active.size != Vector2.ZERO:
		var grown := active.grow(CELL * 2.0)
		rect = Vector4(grown.position.x, grown.position.y, grown.end.x, grown.end.y)
		_last_active_slots = _slots_touching(grown)

	var bits := (FLAG_RAKE if _rake_this_frame else 0) | (FLAG_RELAX if relaxing else 0)
	var slots := _last_active_slots.duplicate()
	if _flight_timer > 0.0:
		for slot in _flight_slots:
			if not slots.has(slot):
				slots.append(slot)
	var params: Array[PackedByteArray] = []
	for slot in slots:
		params.append(_params(MODE_STEP, bits, slot, rect, minf(delta, 0.1), _rake_a, _rake_b, _rake_c))
	var patch_packed := _patch_slice(_packed).to_byte_array() if _patch_changed else PackedByteArray()
	var patch_loose := _patch_slice(_loose).to_byte_array() if _patch_changed else PackedByteArray()
	var prev := _prev_packed.to_byte_array() if _rake_this_frame else PackedByteArray()
	var flow := _flow.to_byte_array() if relaxing else PackedByteArray()
	RenderingServer.call_on_render_thread(_rd_step.bind(patch_packed, patch_loose, prev, flow, _patch_origin, params))
	_end_frame()


func soak(from: Vector2, to: Vector2, width: float) -> void:
	var box := Rect2(from, Vector2.ZERO).expand(to).grow(width * 0.5)
	for cz in range(floori(box.position.y / CELL), ceili(box.end.y / CELL)):
		for cx in range(floori(box.position.x / CELL), ceili(box.end.x / CELL)):
			var center := Vector2(cx + 0.5, cz + 0.5) * CELL
			if not _rotting.has(Vector2i(cx, cz)) and Geometry2D.get_closest_point_to_segment(center, from, to).distance_to(center) <= width * 0.5:
				_rotting[Vector2i(cx, cz)] = ROT_SECONDS


func _rot_step() -> void:
	_rot_mask.fill(0.0)
	var base := _window_tile * TILE_CELLS
	var lo := Vector2i(WINDOW_CELLS, WINDOW_CELLS)
	var hi := Vector2i(-1, -1)
	for key: Vector2i in _rotting.keys():
		var local := key - base
		var left: float = _rotting[key]
		if left <= ROT_TICK or local.x < 0 or local.y < 0 or local.x >= WINDOW_CELLS or local.y >= WINDOW_CELLS:
			_rotting.erase(key)
		else:
			_rotting[key] = left - ROT_TICK
		if local.x < 0 or local.y < 0 or local.x >= WINDOW_CELLS or local.y >= WINDOW_CELLS:
			continue
		var share := minf(ROT_TICK / left, 1.0)
		var i := local.y * WINDOW_CELLS + local.x
		_packed[i] *= 1.0 - share
		_loose[i] *= 1.0 - share
		_rot_mask[i] = share
		lo = lo.min(local)
		hi = hi.max(local)
	if hi.x < 0:
		return
	var rect := Rect2(window_origin + Vector2(lo) * CELL, Vector2(hi - lo + Vector2i.ONE) * CELL).grow(CELL)
	_mark_dirty(rect)
	_frame_seed = (_frame_seed + 1) % 1_000_000
	var params: Array[PackedByteArray] = []
	for slot in _slots_touching(rect):
		params.append(_params(MODE_ROT, 0, slot, Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y), 0.0, Vector4(), Vector4(), Vector3.ZERO))
	RenderingServer.call_on_render_thread(_rd_load_window.bind(_packed.to_byte_array(), _loose.to_byte_array(), params, _rot_mask.to_byte_array()))


func _end_frame() -> void:
	_rake_this_frame = false
	_patch_changed = false
	_prev_taken = false
	_rake_rect = Rect2()


func _relax_step() -> bool:
	var n := PATCH
	var ox := _patch_origin.x
	var oz := _patch_origin.y
	_flow.fill(0.0)
	_relax_delta.fill(0.0)
	var moved := false
	var lo := Vector2i(n, n)
	var hi := Vector2i(-1, -1)
	for lz in n:
		var row := (oz + lz) * WINDOW_CELLS + ox
		for lx in n:
			var i := row + lx
			var loose := _loose[i]
			if loose < 0.004:
				continue
			var height := _packed[i] + loose - RELAX_MAX_STEP
			var fxp := maxf(height - _packed[i + 1] - _loose[i + 1], 0.0) if lx < n - 1 else 0.0
			var fxn := maxf(height - _packed[i - 1] - _loose[i - 1], 0.0) if lx > 0 else 0.0
			var fzp := maxf(height - _packed[i + WINDOW_CELLS] - _loose[i + WINDOW_CELLS], 0.0) if lz < n - 1 else 0.0
			var fzn := maxf(height - _packed[i - WINDOW_CELLS] - _loose[i - WINDOW_CELLS], 0.0) if lz > 0 else 0.0
			var total := fxp + fxn + fzp + fzn
			if total < 0.004:
				continue
			var rate := minf(RELAX_RATE, loose * 0.5 / total)
			var k := lz * n + lx
			lo = lo.min(Vector2i(lx, lz))
			hi = hi.max(Vector2i(lx, lz))
			_flow[k * 4] = fxp * rate / loose
			_flow[k * 4 + 1] = fxn * rate / loose
			_flow[k * 4 + 2] = fzp * rate / loose
			_flow[k * 4 + 3] = fzn * rate / loose
			_relax_delta[k] -= total * rate
			if fxp > 0.0:
				_relax_delta[k + 1] += fxp * rate
			if fxn > 0.0:
				_relax_delta[k - 1] += fxn * rate
			if fzp > 0.0:
				_relax_delta[k + n] += fzp * rate
			if fzn > 0.0:
				_relax_delta[k - n] += fzn * rate
			moved = true
	if not moved:
		return false
	for lz in n:
		var row := (oz + lz) * WINDOW_CELLS + ox
		for lx in n:
			_loose[row + lx] += _relax_delta[lz * n + lx]
	_relax_rect = Rect2(window_origin + Vector2(_patch_origin + lo - Vector2i.ONE) * CELL, Vector2(hi - lo + Vector2i(3, 3)) * CELL)
	_mark_dirty(_relax_rect)
	_grow_slots(_relax_rect, _relax_rect)
	_patch_changed = true
	return true


func _paint_glow_map() -> void:
	var values := PackedFloat32Array()
	values.resize(GLOW_CELLS * GLOW_CELLS)
	var cell := WINDOW_SIZE / GLOW_CELLS
	var reach := ceili(GLOW_RADIUS * 3.0 / cell)
	var any_glow := false
	for glow in _glows:
		if glow.z <= 0.0:
			continue
		var center := (Vector2(glow.x, glow.y) - window_origin) / cell
		for iz in range(maxi(floori(center.y) - reach, 0), mini(floori(center.y) + reach + 1, GLOW_CELLS)):
			for ix in range(maxi(floori(center.x) - reach, 0), mini(floori(center.x) + reach + 1, GLOW_CELLS)):
				var offset := (Vector2(ix + 0.5, iz + 0.5) - center) * cell
				values[iz * GLOW_CELLS + ix] += glow.z * exp(-offset.length_squared() / (GLOW_RADIUS * GLOW_RADIUS))
				any_glow = true
	_glow_texture.update(Image.create_from_data(GLOW_CELLS, GLOW_CELLS, false, Image.FORMAT_RF, values.to_byte_array()))
	for material: ShaderMaterial in [_draw_material, terrain_material]:
		material.set_shader_parameter("glow_origin", window_origin)
		material.set_shader_parameter("glow_enabled", any_glow)


func _configure_noise(rng_seed: int) -> void:
	for noise: FastNoiseLite in [_drift_noise, _far_noise]:
		noise.seed = rng_seed
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3
	_drift_noise.frequency = DRIFT_FREQUENCY * CELL
	_far_noise.frequency = DRIFT_FREQUENCY * FAR_CELL
	_detail_noise.seed = rng_seed + 7
	_detail_noise.frequency = DETAIL_FREQUENCY * CELL


func _noise_values(noise: FastNoiseLite, size: int) -> PackedFloat32Array:
	var image := noise.get_image(size, size, false, false, false)
	image.convert(Image.FORMAT_RF)
	return image.get_data().to_float32_array()


func _generate_tile(key: Vector2i, drift_noise: FastNoiseLite, detail_noise: FastNoiseLite) -> Array:
	var n := TILE_CELLS
	var drift := _periodic_noise_tile(drift_noise, key * n, n, PERIOD_CELLS, BLEND_CELLS)
	var detail := _periodic_noise_tile(detail_noise, key * n, n, PERIOD_CELLS, BLEND_CELLS)
	var packed := PackedFloat32Array()
	packed.resize(n * n)
	for i in n * n:
		packed[i] = BASE_DEPTH + DRIFT_DEPTH * drift[i] + DETAIL_DEPTH * (detail[i] * 2.0 - 1.0)

	var tile_min := Vector2(key) * TILE_SIZE
	var tile_rect := Rect2(tile_min, Vector2.ONE * TILE_SIZE)
	var solid := PackedInt32Array()
	for o in forest.obstacles_near(tile_rect.grow(TRUNK_DRIFT_WIDTH)):
		var center := Vector2(o.x, o.y)
		var outer := o.z + TRUNK_DRIFT_WIDTH
		for iz in range(clampi(floori((center.y - outer - tile_min.y) / CELL), 0, n - 1), clampi(ceili((center.y + outer - tile_min.y) / CELL), 0, n - 1) + 1):
			for ix in range(clampi(floori((center.x - outer - tile_min.x) / CELL), 0, n - 1), clampi(ceili((center.x + outer - tile_min.x) / CELL), 0, n - 1) + 1):
				var r := (tile_min + Vector2(ix + 0.5, iz + 0.5) * CELL).distance_to(center)
				if r < o.z:
					solid.append(iz * n + ix)
				elif r < outer:
					var t := 1.0 - (r - o.z) / TRUNK_DRIFT_WIDTH
					packed[iz * n + ix] += TRUNK_DRIFT * t * t
	for i in solid:
		packed[i] = 0.0
	for c in _clearings:
		var center := Forest.nearest_copy(Vector2(c.x, c.y), tile_rect.get_center())
		var outer := c.z + CLEARING_FADE
		if not tile_rect.grow(outer).has_point(center):
			continue
		for iz in n:
			for ix in n:
				var r := (tile_min + Vector2(ix + 0.5, iz + 0.5) * CELL).distance_to(center)
				if r < outer:
					packed[iz * n + ix] *= smoothstep(c.z, outer, r)

	var deepest := 0.0
	for d in packed:
		deepest = maxf(deepest, d)
	var loose := PackedFloat32Array()
	loose.resize(n * n)
	return [packed, loose, deepest]


func _periodic_noise_tile(noise: FastNoiseLite, origin: Vector2i, size: int, period: int, band: int) -> PackedFloat32Array:
	noise.offset = Vector3(origin.x, origin.y, 0.0)
	var out := _noise_values(noise, size)
	var start := period - band
	var first_x := maxi(start - origin.x, 0)
	var first_z := maxi(start - origin.y, 0)
	if first_x >= size and first_z >= size:
		return out
	var copy_x := PackedFloat32Array()
	var copy_z := PackedFloat32Array()
	var copy_xz := PackedFloat32Array()
	if first_x < size:
		noise.offset = Vector3(origin.x - period, origin.y, 0.0)
		copy_x = _noise_values(noise, size)
	if first_z < size:
		noise.offset = Vector3(origin.x, origin.y - period, 0.0)
		copy_z = _noise_values(noise, size)
	if first_x < size and first_z < size:
		noise.offset = Vector3(origin.x - period, origin.y - period, 0.0)
		copy_xz = _noise_values(noise, size)
	for iz in size:
		var b := clampf(float(origin.y + iz - start) / band, 0.0, 1.0)
		for ix in range(0 if b > 0.0 else first_x, size):
			var a := clampf(float(origin.x + ix - start) / band, 0.0, 1.0)
			var i := iz * size + ix
			var w0 := (1.0 - a) * (1.0 - b)
			var w1 := a * (1.0 - b)
			var w2 := (1.0 - a) * b
			var w3 := a * b
			var v := out[i] * w0
			if w1 > 0.0:
				v += copy_x[i] * w1
			if w2 > 0.0:
				v += copy_z[i] * w2
			if w3 > 0.0:
				v += copy_xz[i] * w3
			out[i] = clampf(0.5 + (v - 0.5) / sqrt(w0 * w0 + w1 * w1 + w2 * w2 + w3 * w3), 0.0, 1.0)
	return out


func _periodic_noise_point(noise: FastNoiseLite, cell: Vector2) -> float:
	noise.offset = Vector3.ZERO
	var period := float(PERIOD_CELLS)
	var start := period - BLEND_CELLS
	var a := clampf((cell.x - start) / BLEND_CELLS, 0.0, 1.0)
	var b := clampf((cell.y - start) / BLEND_CELLS, 0.0, 1.0)
	var weights := PackedFloat32Array([(1.0 - a) * (1.0 - b), a * (1.0 - b), (1.0 - a) * b, a * b])
	var shifts := [Vector2.ZERO, Vector2(period, 0.0), Vector2(0.0, period), Vector2(period, period)]
	var v := 0.0
	var norm := 0.0
	for k in 4:
		if weights[k] > 0.0:
			var at: Vector2 = cell - shifts[k]
			v += clampf((noise.get_noise_2d(at.x, at.y) + 1.0) * 0.5, 0.0, 1.0) * weights[k]
			norm += weights[k] * weights[k]
	return clampf(0.5 + (v - 0.5) / sqrt(norm), 0.0, 1.0)


func _tile_data(tile: Vector2i) -> Array:
	var key := _canonical_tile(tile)
	if not _tile_cache.has(key) and _tile_tasks.has(key):
		WorkerThreadPool.wait_for_task_completion(_tile_tasks[key])
		_tile_tasks.erase(key)
		_collect_finished_tiles()
	if not _tile_cache.has(key):
		_tile_cache[key] = _generate_tile(key, _drift_noise, _detail_noise)
	if _pending_craters.has(key):
		var data: Array = _tile_cache[key]
		var packed: PackedFloat32Array = data[0]
		var loose: PackedFloat32Array = data[1]
		for crater: Array in _pending_craters[key]:
			_carve_tile(packed, loose, crater[0], crater[1])
		_pending_craters.erase(key)
		_store_tile(key, packed, loose)
	return _tile_cache[key]


func _canonical_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(posmod(tile.x, PERIOD_TILES), posmod(tile.y, PERIOD_TILES))


func _prewarm_tiles() -> void:
	_collect_finished_tiles()
	for tz in range(-1, WINDOW_TILES + 1):
		for tx in range(-1, WINDOW_TILES + 1):
			if _tile_tasks.size() >= PREWARM_TASKS:
				return
			var key := _canonical_tile(_window_tile + Vector2i(tx, tz))
			if not _tile_cache.has(key) and not _tile_tasks.has(key):
				_tile_tasks[key] = WorkerThreadPool.add_task(_generate_tile_task.bind(key, _tile_generation, _drift_noise.duplicate(), _detail_noise.duplicate()), true, "Leaf tile")


func _generate_tile_task(key: Vector2i, generation: int, drift_noise: FastNoiseLite, detail_noise: FastNoiseLite) -> void:
	var data := _generate_tile(key, drift_noise, detail_noise)
	_tiles_mutex.lock()
	_finished_tiles.append([key, generation, data])
	_tiles_mutex.unlock()


func _collect_finished_tiles() -> void:
	for key: Vector2i in _tile_tasks.keys():
		if WorkerThreadPool.is_task_completed(_tile_tasks[key]):
			WorkerThreadPool.wait_for_task_completion(_tile_tasks[key])
			_tile_tasks.erase(key)
	_tiles_mutex.lock()
	var finished := _finished_tiles
	_finished_tiles = []
	_tiles_mutex.unlock()
	for entry in finished:
		if entry[1] == _tile_generation and not _tile_cache.has(entry[0]):
			_tile_cache[entry[0]] = entry[2]


func _load_window() -> void:
	_packed = PackedFloat32Array()
	_loose = PackedFloat32Array()
	for tz in WINDOW_TILES:
		var row_tiles: Array[Array] = []
		for tx in WINDOW_TILES:
			row_tiles.append(_tile_data(_window_tile + Vector2i(tx, tz)))
		for r in TILE_CELLS:
			for data in row_tiles:
				_packed.append_array((data[0] as PackedFloat32Array).slice(r * TILE_CELLS, (r + 1) * TILE_CELLS))
				_loose.append_array((data[1] as PackedFloat32Array).slice(r * TILE_CELLS, (r + 1) * TILE_CELLS))
	_dirty_tiles.clear()


func _store_dirty_tiles() -> void:
	if _dirty_tiles.is_empty():
		return
	for tile: Vector2i in _dirty_tiles:
		var local := tile - _window_tile
		var packed := PackedFloat32Array()
		var loose := PackedFloat32Array()
		for r in TILE_CELLS:
			var start := (local.y * TILE_CELLS + r) * WINDOW_CELLS + local.x * TILE_CELLS
			packed.append_array(_packed.slice(start, start + TILE_CELLS))
			loose.append_array(_loose.slice(start, start + TILE_CELLS))
		_store_tile(_canonical_tile(tile), packed, loose)
	_far_texture.update(_far_image)
	_dirty_tiles.clear()


func _store_tile(key: Vector2i, packed: PackedFloat32Array, loose: PackedFloat32Array) -> void:
	var deepest := 0.0
	for i in packed.size():
		deepest = maxf(deepest, packed[i] + loose[i])
	_tile_cache[key] = [packed, loose, deepest]
	_edited[key] = true
	var step := roundi(FAR_CELL / CELL)
	for fz in TILE_CELLS / step:
		for fx in TILE_CELLS / step:
			var i := (fz * step + step / 2) * TILE_CELLS + fx * step + step / 2
			_far_image.set_pixel(key.x * (TILE_CELLS / step) + fx, key.y * (TILE_CELLS / step) + fz, Color(packed[i] + loose[i], 0.0, 0.0))


func _blast_stored(center: Vector2, radius: float) -> void:
	var box := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	var any := false
	for tz in range(floori(box.position.y / TILE_SIZE), floori(box.end.y / TILE_SIZE) + 1):
		for tx in range(floori(box.position.x / TILE_SIZE), floori(box.end.x / TILE_SIZE) + 1):
			var tile := Vector2i(tx, tz)
			var in_view := tile - _window_tile
			if in_view.x >= 0 and in_view.y >= 0 and in_view.x < WINDOW_TILES and in_view.y < WINDOW_TILES:
				continue
			var key := _canonical_tile(tile)
			var local := center - Vector2(tile) * TILE_SIZE
			if _tile_cache.has(key):
				var data: Array = _tile_cache[key]
				var packed: PackedFloat32Array = data[0]
				var loose: PackedFloat32Array = data[1]
				_carve_tile(packed, loose, local, radius)
				_store_tile(key, packed, loose)
			else:
				if not _pending_craters.has(key):
					_pending_craters[key] = []
				_pending_craters[key].append([local, radius])
				_paint_far_crater(key, local, radius)
			any = true
	if any:
		_far_texture.update(_far_image)


func _carve_tile(packed: PackedFloat32Array, loose: PackedFloat32Array, local: Vector2, radius: float) -> void:
	var lo := ((local - Vector2.ONE * radius) / CELL).floor()
	var hi := ((local + Vector2.ONE * radius) / CELL).ceil()
	for r in range(maxi(int(lo.y), 0), mini(int(hi.y), TILE_CELLS)):
		for c in range(maxi(int(lo.x), 0), mini(int(hi.x), TILE_CELLS)):
			var d := (Vector2(c + 0.5, r + 0.5) * CELL).distance_to(local)
			if d < radius:
				var keep := smoothstep(radius * 0.6, radius, d)
				packed[r * TILE_CELLS + c] *= keep
				loose[r * TILE_CELLS + c] *= keep


func _paint_far_crater(key: Vector2i, local: Vector2, radius: float) -> void:
	var per_tile := TILE_CELLS / roundi(FAR_CELL / CELL)
	for fz in per_tile:
		for fx in per_tile:
			var d := (Vector2(fx + 0.5, fz + 0.5) * FAR_CELL).distance_to(local)
			if d < radius:
				var px := Vector2i(key.x * per_tile + fx, key.y * per_tile + fz)
				_far_image.set_pixelv(px, Color(_far_image.get_pixelv(px).r * smoothstep(radius * 0.6, radius, d), 0.0, 0.0))


func _build_far_image() -> void:
	var drift := _periodic_noise_tile(_far_noise, Vector2i.ZERO, FAR_CELLS, FAR_CELLS, BLEND_CELLS * FAR_CELLS / PERIOD_CELLS)
	var values := PackedFloat32Array()
	values.resize(FAR_CELLS * FAR_CELLS)
	for i in values.size():
		values[i] = BASE_DEPTH + DRIFT_DEPTH * drift[i]
	_far_image = Image.create_from_data(FAR_CELLS, FAR_CELLS, false, Image.FORMAT_RF, values.to_byte_array())
	_far_texture.set_image(_far_image)


func _cell_of(p: Vector2) -> Vector2i:
	var local := (p - window_origin) / CELL
	return Vector2i(clampi(floori(local.x), 0, WINDOW_CELLS - 1), clampi(floori(local.y), 0, WINDOW_CELLS - 1))


func _cell_center(ix: int, iz: int) -> Vector2:
	return window_origin + Vector2(ix + 0.5, iz + 0.5) * CELL


func _patch_slice(source: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for r in PATCH:
		var start := (_patch_origin.y + r) * WINDOW_CELLS + _patch_origin.x
		out.append_array(source.slice(start, start + PATCH))
	return out


func _ensure_patch_around(cell: Vector2i) -> void:
	var local := cell - _patch_origin
	if local.x >= PATCH_MARGIN and local.y >= PATCH_MARGIN and local.x < PATCH - PATCH_MARGIN and local.y < PATCH - PATCH_MARGIN:
		return
	_patch_origin = (cell - Vector2i(PATCH / 2, PATCH / 2)).clamp(Vector2i.ZERO, Vector2i.ONE * (WINDOW_CELLS - PATCH))
	_relax_frames_left = 0


func _mark_dirty(rect: Rect2) -> void:
	for tz in range(floori(rect.position.y / TILE_SIZE), floori(rect.end.y / TILE_SIZE) + 1):
		for tx in range(floori(rect.position.x / TILE_SIZE), floori(rect.end.x / TILE_SIZE) + 1):
			var local := Vector2i(tx, tz) - _window_tile
			if local.x >= 0 and local.y >= 0 and local.x < WINDOW_TILES and local.y < WINDOW_TILES:
				_dirty_tiles[Vector2i(tx, tz)] = true


func _slots_touching(rect: Rect2) -> Array[int]:
	var out: Array[int] = []
	for slot in TILE_COUNT:
		if _slot_bounds[slot].intersects(rect):
			out.append(slot)
	return out


func _grow_slots(touched: Rect2, reach: Rect2) -> void:
	for slot in _slot_bounds.size():
		if _slot_bounds[slot].intersects(touched) and not _slot_bounds[slot].encloses(reach):
			_slot_bounds[slot] = _slot_bounds[slot].merge(reach)
			_apply_slot_bounds(slot)


func _apply_slot_bounds(slot: int) -> void:
	var bounds := _slot_bounds[slot].grow(0.3)
	var aabb := AABB(Vector3(-bounds.size.x * 0.5, -0.5, -bounds.size.y * 0.5), Vector3(bounds.size.x, 4.0, bounds.size.y))
	var edge := bounds.size.length() * 0.5 + 0.5
	var ranges := [0.0, LOD_DISTANCE * 2.0 + edge, LOD_DISTANCE * 4.0 + edge, 0.0]
	for k in 3:
		var draw: MeshInstance3D = _slot_draws[slot][k]
		draw.position = Vector3(bounds.get_center().x, 0.0, bounds.get_center().y)
		draw.custom_aabb = aabb
		draw.visibility_range_begin = ranges[k]
		draw.visibility_range_end = ranges[k + 1]


func _world_rect(origin: Vector2, dir: Vector2, side: Vector2, v_min: float, v_max: float) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for su in [-rake_half_width, rake_half_width]:
		for sv in [v_min, v_max]:
			var corner: Vector2 = origin + side * su + dir * sv
			lo = lo.min(corner)
			hi = hi.max(corner)
	return Rect2(lo, hi - lo)


func _rect_cells(origin: Vector2, dir: Vector2, side: Vector2, v_min: float, v_max: float) -> Rect2i:
	var r := _world_rect(origin, dir, side, v_min, v_max)
	var lo := (r.position - window_origin) / CELL
	var hi := (r.end - window_origin) / CELL
	var x0 := clampi(floori(lo.x - 0.5), 0, WINDOW_CELLS)
	var z0 := clampi(floori(lo.y - 0.5), 0, WINDOW_CELLS)
	return Rect2i(x0, z0, clampi(ceili(hi.x + 0.5), 0, WINDOW_CELLS) - x0, clampi(ceili(hi.y + 0.5), 0, WINDOW_CELLS) - z0)


func _params(mode: int, bits: int, slot: int, rect: Vector4, delta: float, a: Vector4, b: Vector4, c: Vector3) -> PackedByteArray:
	var bytes := PackedFloat32Array([
		a.x, a.y, a.z, a.w,
		b.x, b.y, b.z, b.w,
		rect.x, rect.y, rect.z, rect.w,
		c.x, c.y, c.z, VISIBLE_DEPTH,
		window_origin.x, window_origin.y, CELL, WINDOW_SIZE,
		delta, _blast_center.x, _blast_center.y, 0.0,
	]).to_byte_array()
	bytes.append_array(PackedInt32Array([mode, bits, _frame_seed, slot * ROWS_PER_TILE, STATE_WIDTH, ROWS_PER_TILE, _patch_origin.x, _patch_origin.y]).to_byte_array())
	return bytes


func _build_draws() -> void:
	for i in 3:
		_draw_material.set_shader_parameter("state_" + "abc"[i], _state_textures[i])
	_draw_material.set_shader_parameter("glow_map", _glow_texture)
	_draw_material.set_shader_parameter("lod_distance", LOD_DISTANCE)
	var strides := [1, 4, 16]
	var meshes := strides.map(func(stride: int) -> ArrayMesh: return _quad_batch(LEAVES_PER_TILE / stride))
	for slot in TILE_COUNT:
		var draws: Array[MeshInstance3D] = []
		for k in 3:
			var draw := MeshInstance3D.new()
			draw.mesh = meshes[k]
			draw.material_override = _draw_material
			draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			draw.set_instance_shader_parameter("leaf_offset", slot * LEAVES_PER_TILE)
			draw.set_instance_shader_parameter("leaf_stride", strides[k])
			add_child(draw)
			draws.append(draw)
		_slot_draws.append(draws)


func _quad_batch(count: int) -> ArrayMesh:
	var indices := PackedInt32Array()
	indices.resize(count * 6)
	for q in count:
		indices[q * 6] = q * 4
		indices[q * 6 + 1] = q * 4 + 1
		indices[q * 6 + 2] = q * 4 + 2
		indices[q * 6 + 3] = q * 4
		indices[q * 6 + 4] = q * 4 + 2
		indices[q * 6 + 5] = q * 4 + 3
	var vertices := PackedVector3Array()
	vertices.resize(count * 4)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _rd_create() -> void:
	_rd = RenderingServer.get_rendering_device()
	_sim_shader = _rd.shader_create_from_spirv(SIM_SHADER.get_spirv())
	_sim_pipeline = _rd.compute_pipeline_create(_sim_shader)
	_patch_shader = _rd.shader_create_from_spirv(PATCH_SHADER.get_spirv())
	_patch_pipeline = _rd.compute_pipeline_create(_patch_shader)

	var rows := ROWS_PER_TILE * TILE_COUNT
	var storage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var update := RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	_state_rids = [
		_rd_texture(STATE_WIDTH, rows, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, storage),
		_rd_texture(STATE_WIDTH, rows, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, storage),
		_rd_texture(STATE_WIDTH, rows, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, storage),
	]
	var patch_zero := PackedByteArray()
	patch_zero.resize(PATCH * PATCH * 4)
	var flow_zero := PackedByteArray()
	flow_zero.resize(PATCH * PATCH * 16)
	for i in 2:
		_window_rids.append(_rd_texture(WINDOW_CELLS, WINDOW_CELLS, RenderingDevice.DATA_FORMAT_R32_SFLOAT, storage | update))
		_patch_rids.append(_rd_texture(PATCH, PATCH, RenderingDevice.DATA_FORMAT_R32_SFLOAT, update, [patch_zero]))
	_prev_rid = _rd_texture(PATCH, PATCH, RenderingDevice.DATA_FORMAT_R32_SFLOAT, update, [patch_zero])
	_flow_rid = _rd_texture(PATCH, PATCH, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, update, [flow_zero])
	_rot_rid = _rd_texture(WINDOW_CELLS, WINDOW_CELLS, RenderingDevice.DATA_FORMAT_R32_SFLOAT, update)

	var sampler := RDSamplerState.new()
	sampler.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_nearest_sampler = _rd.sampler_create(sampler)
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_linear_sampler = _rd.sampler_create(sampler)

	var sim_uniforms: Array[RDUniform] = []
	for i in 3:
		sim_uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, i, [_state_rids[i]]))
	sim_uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_linear_sampler, _window_rids[0]]))
	sim_uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_linear_sampler, _window_rids[1]]))
	sim_uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 5, [_nearest_sampler, _flow_rid]))
	sim_uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 6, [_nearest_sampler, _prev_rid]))
	sim_uniforms.append(_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 7, [_nearest_sampler, _rot_rid]))
	_sim_set = _rd.uniform_set_create(sim_uniforms, _sim_shader, 0)
	for i in 2:
		var patch_uniforms: Array[RDUniform] = [_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [_window_rids[i]]), _uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_nearest_sampler, _patch_rids[i]])]
		_patch_sets.append(_rd.uniform_set_create(patch_uniforms, _patch_shader, 0))
	_on_rd_ready.call_deferred(_state_rids.duplicate(), _window_rids.duplicate())


func _rd_texture(width: int, height: int, format: int, extra_usage: int, data: Array[PackedByteArray] = []) -> RID:
	var texture_format := RDTextureFormat.new()
	texture_format.width = width
	texture_format.height = height
	texture_format.format = format
	texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | extra_usage
	return _rd.texture_create(texture_format, RDTextureView.new(), data)


func _uniform(type: RenderingDevice.UniformType, binding: int, ids: Array[RID]) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for id in ids:
		uniform.add_id(id)
	return uniform


func _on_rd_ready(state: Array[RID], window: Array[RID]) -> void:
	for i in 3:
		_state_textures[i].texture_rd_rid = state[i]
	for i in 2:
		_window_textures[i].texture_rd_rid = window[i]


func _rd_load_window(packed: PackedByteArray, loose: PackedByteArray, params: Array[PackedByteArray], rot := PackedByteArray()) -> void:
	if not _rd:
		return
	_rd.texture_update(_window_rids[0], 0, packed)
	_rd.texture_update(_window_rids[1], 0, loose)
	if not rot.is_empty():
		_rd.texture_update(_rot_rid, 0, rot)
	_rd_dispatch_sim(params)


func _rd_step(patch_packed: PackedByteArray, patch_loose: PackedByteArray, prev: PackedByteArray, flow: PackedByteArray, patch_origin: Vector2i, params: Array[PackedByteArray]) -> void:
	if not _rd:
		return
	if not patch_packed.is_empty():
		_rd.texture_update(_patch_rids[0], 0, patch_packed)
		_rd.texture_update(_patch_rids[1], 0, patch_loose)
		var push := PackedInt32Array([patch_origin.x, patch_origin.y, PATCH, 0]).to_byte_array()
		for i in 2:
			var list := _rd.compute_list_begin()
			_rd.compute_list_bind_compute_pipeline(list, _patch_pipeline)
			_rd.compute_list_bind_uniform_set(list, _patch_sets[i], 0)
			_rd.compute_list_set_push_constant(list, push, push.size())
			_rd.compute_list_dispatch(list, ceili(PATCH / 16.0), ceili(PATCH / 16.0), 1)
			_rd.compute_list_end()
	if not prev.is_empty():
		_rd.texture_update(_prev_rid, 0, prev)
	if not flow.is_empty():
		_rd.texture_update(_flow_rid, 0, flow)
	_rd_dispatch_sim(params)


func _rd_dispatch_sim(params: Array[PackedByteArray]) -> void:
	if params.is_empty():
		return
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _sim_pipeline)
	_rd.compute_list_bind_uniform_set(list, _sim_set, 0)
	for push in params:
		_rd.compute_list_set_push_constant(list, push, push.size())
		_rd.compute_list_dispatch(list, ceili(STATE_WIDTH / 32.0), ceili(ROWS_PER_TILE / 8.0), 1)
	_rd.compute_list_end()


func _rd_free() -> void:
	if not _rd:
		return
	for rid in _state_rids + _window_rids + _patch_rids + [_prev_rid, _flow_rid, _rot_rid, _linear_sampler, _nearest_sampler, _sim_shader, _patch_shader]:
		if rid.is_valid():
			_rd.free_rid(rid)
	_rd = null
