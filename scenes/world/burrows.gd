class_name Burrows
extends Node3D

const SQUIRREL := preload("res://scenes/creatures/squirrel.tscn")
const NATURAL_BURROWS := 14
const MAX_ACORNS := 25
const SPROUT_HEIGHT := 0.2
const SHOW_DISTANCE := 40.0
const MAX_SPROUTS := 40
const REFRESH_SECONDS := 0.25
const SQUIRRELS := 10
const SQUIRREL_SPAWN_MIN := 8.0
const SQUIRREL_SPAWN_MAX := 38.0
const SQUIRREL_DESPAWN := 55.0
const STARTLE_RADIUS := 18.0
const BAIT_RADIUS := 25.0
const CALL_RADIUS := 15.0
const EXTRA_CALLERS := 5
const MAX_ARMY := 1000
const GATHER_SECONDS := 6.0

signal uncovered(acorn: Node3D)

var burrows: Array[Dictionary] = []
var army: Array[Squirrel] = []
var loads: Array[Dictionary] = []
var heading := Vector2.UP

var _squirrels: Array[Squirrel] = []
var _refresh := 0.0
var _reveal_depth := 0.0
var _acorn_radius := 0.0

@onready var field: LeafWorld = %LeafWorld
@onready var forest: Forest = %Forest
@onready var explosives: Explosives = %Explosives
@onready var player: Player = %Player
@onready var pickups: Pickups = %Pickups
@onready var sprouts: MultiMesh = $Sprouts.multimesh


func _ready() -> void:
	var acorn := ItemDb.spawn_model(&"acorn")
	var size: Vector3 = acorn.get_meta("size")
	_reveal_depth = maxf(0.03, size.y * 0.6)
	_acorn_radius = maxf(size.x, size.z) * 0.3
	acorn.free()


func populate(rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	burrows.clear()
	while burrows.size() < NATURAL_BURROWS and acorn_count() < MAX_ACORNS:
		var p := Vector2(rng.randf_range(-Forest.HALF, Forest.HALF), rng.randf_range(-Forest.HALF, Forest.HALF))
		if forest.nearest_obstacle_distance(p) > 0.8 and not forest.hides(p, 0.2):
			bury(p, rng.randi_range(1, 2))


func bury(p: Vector2, count: int) -> void:
	count = mini(count, MAX_ACORNS - acorn_count())
	if count <= 0:
		return
	burrows.append({"pos": Forest.wrap_position(p), "count": count})
	_refresh = 0.0


func acorn_count() -> int:
	var total := 0
	for burrow in burrows:
		total += burrow["count"]
	return total


func dig(p: Vector2, radius: float) -> int:
	var total := 0
	for k in range(burrows.size() - 1, -1, -1):
		if Forest.wrap_position(burrows[k]["pos"] - p).length() <= radius:
			total += burrows[k]["count"]
			burrows.remove_at(k)
	_refresh = 0.0
	return total


func points_near(p: Vector2, radius: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for burrow in burrows:
		var pos := Forest.nearest_copy(burrow["pos"], p)
		if pos.distance_to(p) <= radius:
			out.append(pos)
	return out


func startle(where: Vector3) -> void:
	for squirrel in _squirrels:
		if squirrel.position.distance_to(where) < STARTLE_RADIUS:
			squirrel.startle(where)


func bait(spot: Vector2) -> int:
	var coming := 0
	for squirrel in _squirrels:
		if not squirrel.is_up_a_tree() and not squirrel.loyal() and Forest.flat(squirrel.position).distance_to(spot) < BAIT_RADIUS:
			squirrel.lure(spot)
			coming += 1
	return coming


func call_squirrels(entry: Dictionary) -> int:
	var here := Forest.flat(player.global_position)
	var wanted: int = mini(entry["count"] * carriers_for(entry["id"]), MAX_ARMY - army.size())
	var near := _squirrels.filter(func(s: Squirrel) -> bool: return not s.loyal() and not s.is_up_a_tree() and Forest.flat(s.position).distance_to(here) < CALL_RADIUS)
	near.sort_custom(func(a: Squirrel, b: Squirrel) -> bool: return Forest.flat(a.position).distance_squared_to(here) < Forest.flat(b.position).distance_squared_to(here))
	near = near.slice(0, wanted)
	for i in mini(wanted - near.size(), EXTRA_CALLERS):
		var p := here + Vector2.from_angle(randf() * TAU) * randf_range(CALL_RADIUS * 0.75, CALL_RADIUS)
		if forest.nearest_obstacle_distance(p) > 0.5:
			near.append(_spawn_squirrel(p))
	for squirrel: Squirrel in near:
		squirrel.fetch(entry)
	return near.size()


func save_squirrels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for squirrel in (army + _squirrels.filter(func(s: Squirrel) -> bool: return s.slot < 0)).filter(func(s: Squirrel) -> bool: return not s.debug):
		out.append({"pos": Forest.flat(squirrel.position), "yaw": squirrel._yaw, "carrying": squirrel.carrying, "follow": squirrel.slot >= 0,
			"cargo": squirrel.cargo.get("id", &""), "group": loads.find(squirrel.cargo)})
	return out


func restore_squirrels(entries: Array) -> void:
	var groups := {}
	for entry: Dictionary in entries:
		var squirrel := _spawn_squirrel(entry["pos"])
		squirrel.restore(entry)
		var group: int = entry.get("group", -1)
		if group < 0 or squirrel.slot < 0:
			continue
		if groups.has(group):
			join_load(squirrel, groups[group])
		else:
			groups[group] = start_load(squirrel, entry["cargo"])


static func carriers_for(id: StringName) -> int:
	return maxi(ItemDb.get_item(id).carriers, 1)


func start_load(squirrel: Squirrel, id: StringName) -> Dictionary:
	var node := ItemDb.spawn_model(id)
	add_child(node)
	node.position = squirrel.position
	var cargo := {"id": id, "node": node, "carriers": [squirrel], "need": carriers_for(id), "wait": GATHER_SECONDS}
	loads.append(cargo)
	squirrel.cargo = cargo
	return cargo


func join_load(squirrel: Squirrel, cargo: Dictionary) -> void:
	cargo["carriers"].append(squirrel)
	squirrel.cargo = cargo


func _carry_loads(delta: float) -> void:
	for cargo in loads:
		if cargo["carriers"].size() < cargo["need"]:
			cargo["wait"] -= delta
		var carriers: Array = cargo["carriers"]
		var sum := Vector3.ZERO
		for squirrel: Squirrel in carriers:
			sum += squirrel.position
		var node: Node3D = cargo["node"]
		node.position = sum / carriers.size() + Vector3.UP * (0.2 if carriers.size() == 1 else 0.26)
		node.rotation.y = (carriers[0] as Squirrel)._yaw


func row_width() -> int:
	return maxi(4, ceili(sqrt(army.size() / 1.5)))


func fill_army() -> void:
	var here := Forest.flat(player.global_position)
	for i in MAX_ARMY - army.size():
		var squirrel := _spawn_squirrel(here + Vector2.from_angle(randf() * TAU) * randf_range(2.0, 6.0))
		squirrel.debug = true
		squirrel.restore({"yaw": randf() * TAU, "carrying": false, "follow": true})


func _spawn_squirrel(p: Vector2) -> Squirrel:
	var squirrel: Squirrel = SQUIRREL.instantiate()
	add_child(squirrel)
	squirrel.position = Vector3(p.x, field.sample_depth(p), p.y)
	_squirrels.append(squirrel)
	return squirrel


func _process(delta: float) -> void:
	_carry_loads(delta)
	var here := Forest.flat(player.global_position)
	if player.velocity.length() > 0.5:
		heading = player.velocity.normalized()
	for k in range(_squirrels.size() - 1, -1, -1):
		if _squirrels[k].slot < 0 and Vector2(_squirrels[k].position.x, _squirrels[k].position.z).distance_to(here) > SQUIRREL_DESPAWN:
			_squirrels[k].queue_free()
			_squirrels.remove_at(k)
	for attempt in 8:
		if _squirrels.size() - army.size() >= SQUIRRELS:
			break
		var p := here + Vector2.from_angle(randf() * TAU) * randf_range(SQUIRREL_SPAWN_MIN, SQUIRREL_SPAWN_MAX)
		if forest.nearest_obstacle_distance(p) > 0.5:
			_spawn_squirrel(p)

	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = REFRESH_SECONDS

	for k in range(burrows.size() - 1, -1, -1):
		var spot := Forest.nearest_copy(burrows[k]["pos"], here)
		if field.in_window(spot) and field.cover_depth(spot, _acorn_radius) < _reveal_depth:
			for i in burrows[k]["count"]:
				var acorn := ItemDb.spawn_model(&"acorn")
				acorn.position = Vector3(spot.x + i * 0.08, 0.0, spot.y)
				acorn.rotation.y = randf() * TAU
				add_child(acorn)
				uncovered.emit(acorn)
				App.bump(&"acorns_dug")
			burrows.remove_at(k)

	var near: Array[Array] = []
	for burrow in burrows:
		var p := Forest.nearest_copy(burrow["pos"], here)
		if p.distance_to(here) <= SHOW_DISTANCE:
			near.append([p.distance_to(here), p, burrow["pos"]])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	sprouts.visible_instance_count = mini(near.size(), MAX_SPROUTS)
	for k in sprouts.visible_instance_count:
		var p: Vector2 = near[k][1]
		sprouts.set_instance_transform(k, Transform3D(Basis(Vector3.UP, float(hash(near[k][2]) % 628) * 0.01), Vector3(p.x, maxf(field.sample_depth(p) - SPROUT_HEIGHT * 0.25, 0.0), p.y)))
