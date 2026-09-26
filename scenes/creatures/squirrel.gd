class_name Squirrel
extends Node3D

enum State { SIT, SCURRY, FLEE, CLIMB_UP, PERCH, CLIMB_DOWN, DIG, NIBBLE, FETCH, FOLLOW }

const RUN_SPEED := 3.0
const FLEE_SPEED := 6.0
const CLIMB_SPEED := 2.4
const HOP_RATE := 16.0
const HOP_HEIGHT := 0.08
const SCARE_DISTANCE := 5.5
const TREE_SEARCH := 14.0
const TRUNK_GAP := 0.06
const BODY_RADIUS := 0.12
const DIG_SECONDS := 1.4
const NIBBLE_SECONDS := 2.5
const CARRY_CHANCE := 0.094
const GIVE_UP_SECONDS := 8.0
const ROW := 4
const ROW_GAP := 0.7
const FILE_GAP := 0.6

var state := State.SIT
var carrying := false

var _timer := 1.0
var _yaw := 0.0
var _goal := Vector2.ZERO
var _then := State.SIT
var _speed := RUN_SPEED
var _tree := {}
var _height := 0.0
var _perch := 0.0
var _around := 0.0
var _hop := 0.0
var _look := 0.0
var _target := {}

@onready var burrows: Burrows = get_parent()
@onready var body: Node3D = $Body
@onready var acorn: Node3D = $Body/Acorn


func _ready() -> void:
	_timer = randf_range(0.2, 1.5)
	_yaw = randf() * TAU
	_hop = randf() * TAU
	_look = randf() * TAU


func is_up_a_tree() -> bool:
	return state == State.CLIMB_UP or state == State.PERCH or state == State.CLIMB_DOWN


func loyal() -> bool:
	return state == State.FETCH or state == State.FOLLOW


func startle(from: Vector3) -> void:
	if is_up_a_tree() or state == State.FLEE or loyal():
		return
	var tree := _nearest_tree(false)
	if tree.is_empty():
		_run_to(_flat() + Vector2(position.x - from.x, position.z - from.z).normalized() * 10.0, State.SIT, FLEE_SPEED)
	else:
		_go_climb(tree, FLEE_SPEED, randf_range(4.0, 7.0))
	state = State.FLEE


func fetch(entry: Dictionary) -> void:
	_target = entry
	carrying = false
	body.rotation.z = 0.0
	state = State.FETCH
	_timer = 0.0


func lure(spot: Vector2) -> void:
	if not is_up_a_tree() and not loyal():
		_run_to(spot + Vector2.from_angle(randf() * TAU) * randf_range(0.25, 0.6), State.NIBBLE, FLEE_SPEED * 0.8)


func _process(delta: float) -> void:
	_timer -= delta
	var player := burrows.player
	var after_crumbs := state == State.NIBBLE or (state == State.SCURRY and _then == State.NIBBLE)
	if not after_crumbs and state != State.FLEE and not is_up_a_tree() and not loyal() and Forest.flat(player.global_position).distance_to(_flat()) < SCARE_DISTANCE:
		startle(player.global_position)
	match state:
		State.SIT:
			_sit(delta)
		State.SCURRY, State.FLEE:
			_scurry(delta)
		State.CLIMB_UP:
			_climb(delta, 1.0)
		State.PERCH:
			_perch_on_branch(delta)
		State.CLIMB_DOWN:
			_climb(delta, -1.0)
		State.DIG:
			_dig()
		State.NIBBLE:
			_nibble(delta)
		State.FETCH:
			_fetch(delta)
		State.FOLLOW:
			_follow(delta)
	acorn.visible = carrying


func _idle(delta: float) -> void:
	_stand(_flat(), 0.0)
	_look += delta * 1.3
	body.rotation.x = lerpf(body.rotation.x, -0.9 if sin(_look) > 0.4 else 0.0, 1.0 - exp(-delta * 8.0))
	body.rotation.z = 0.0


func _sit(delta: float) -> void:
	_idle(delta)
	if _timer > 0.0:
		return
	var me := _flat()
	var roll := randf()
	if carrying and roll < 0.6:
		_run_to(me + Vector2.from_angle(randf() * TAU) * randf_range(1.5, 5.0), State.DIG, RUN_SPEED)
	elif roll < 0.45:
		var tree := _nearest_tree(true)
		if tree.is_empty():
			_run_to(me + Vector2.from_angle(randf() * TAU) * randf_range(2.0, 8.0), State.SIT, RUN_SPEED)
		else:
			_go_climb(tree, RUN_SPEED, randf_range(2.5, minf(tree["height"] * 0.6, 6.0)))
	elif roll < 0.9:
		_run_to(me + Vector2.from_angle(randf() * TAU) * randf_range(2.0, 8.0), State.SIT, RUN_SPEED)
	else:
		_timer = randf_range(1.0, 3.0)


func _scurry(delta: float) -> void:
	var me := _flat()
	var distance := me.distance_to(_goal)
	if distance < 0.15 or _timer < -GIVE_UP_SECONDS:
		match _then:
			State.CLIMB_UP:
				state = State.CLIMB_UP
				_height = 0.0
			State.DIG:
				state = State.DIG
				_timer = DIG_SECONDS
			State.NIBBLE:
				state = State.NIBBLE
				_timer = NIBBLE_SECONDS
			_:
				_sit_for(randf_range(0.8, 3.0))
		return
	var burst := 1.0 if state == State.FLEE or _then == State.NIBBLE else clampf(0.35 + 0.9 * sin(_hop * 0.21), 0.0, 1.0)
	_step(_goal, _speed * burst, burst, delta)


func _step(goal: Vector2, speed: float, lift: float, delta: float) -> void:
	var me := _flat()
	var distance := me.distance_to(goal)
	var dir := (goal - me) / distance
	_hop += delta * HOP_RATE
	var next := burrows.forest.push_out(me + dir * minf(speed * delta, distance), BODY_RADIUS)
	_yaw = lerp_angle(_yaw, atan2(dir.x, dir.y), 1.0 - exp(-delta * 14.0))
	body.rotation.x = lerpf(body.rotation.x, 0.0, 1.0 - exp(-delta * 12.0))
	_stand(next, absf(sin(_hop)) * HOP_HEIGHT * lift)


func _fetch(delta: float) -> void:
	if _target not in burrows.pickups._pickups or _timer < -GIVE_UP_SECONDS:
		_sit_for(randf_range(0.5, 1.5))
		return
	var goal := Forest.nearest_copy(Forest.flat((_target["node"] as Node3D).position), _flat())
	if _flat().distance_to(goal) > 0.25:
		_step(goal, FLEE_SPEED, 1.0, delta)
	elif burrows.pickups.take_one(_target):
		carrying = true
		burrows.army.append(self)
		state = State.FOLLOW


func _follow(delta: float) -> void:
	var k := burrows.army.find(self)
	var fwd := burrows.heading
	var me := _flat()
	var slot := Forest.nearest_copy(Forest.flat(burrows.player.global_position), me) - fwd * (1.4 + (k / ROW) * ROW_GAP) + Vector2(-fwd.y, fwd.x) * ((k % ROW) - (ROW - 1) * 0.5) * FILE_GAP
	var distance := me.distance_to(slot)
	if distance > 30.0:
		position = Vector3(slot.x, 0.0, slot.y)
	elif distance > 0.3:
		_step(slot, clampf(distance * 3.0, 1.5, 10.0), 1.0, delta)
		return
	var to_player := Forest.flat(burrows.player.global_position) - slot
	_yaw = lerp_angle(_yaw, atan2(to_player.x, to_player.y), 1.0 - exp(-delta * 6.0))
	_idle(delta)


func _climb(delta: float, direction: float) -> void:
	_height += direction * CLIMB_SPEED * delta
	_around += delta * 0.5 * direction
	var out := Vector2.from_angle(_around)
	var flat: Vector2 = _tree["position"] + out * (_tree["radius"] + TRUNK_GAP)
	position = Vector3(flat.x, burrows.field.sample_depth(flat) + maxf(_height, 0.0), flat.y)
	basis = Basis.looking_at(Vector3.UP * direction, Vector3(out.x, 0.0, out.y), true)
	_hop += delta * HOP_RATE
	body.rotation = Vector3(0.0, 0.0, sin(_hop) * 0.12)
	body.position.y = 0.0
	if direction > 0.0 and _height >= _perch:
		_height = _perch
		state = State.PERCH
		_timer = randf_range(3.0, 9.0)
		if randf() < CARRY_CHANCE:
			carrying = true
	elif direction < 0.0 and _height <= 0.0:
		_height = 0.0
		_yaw = atan2(out.x, out.y)
		if carrying and randf() < 0.7:
			_run_to(flat + out * randf_range(1.5, 5.0), State.DIG, RUN_SPEED)
		else:
			_sit_for(randf_range(0.5, 2.0))


func _perch_on_branch(delta: float) -> void:
	var out := Vector2.from_angle(_around)
	var flat: Vector2 = _tree["position"] + out * (_tree["radius"] + TRUNK_GAP + 0.12)
	position = Vector3(flat.x, burrows.field.sample_depth(flat) + _height, flat.y)
	basis = Basis.looking_at(Vector3(out.x, 0.0, out.y), Vector3.UP, true)
	_look += delta * 2.0
	body.rotation = Vector3(-0.5 + sin(_look) * 0.1, 0.0, 0.0)
	if _timer <= 0.0:
		state = State.CLIMB_DOWN


func _dig() -> void:
	_stand(_flat(), 0.0)
	body.rotation.x = 0.55 + sin(_timer * 40.0) * 0.12
	if _timer > 0.0:
		return
	if carrying:
		burrows.bury(_flat(), 1)
		carrying = false
	_sit_for(randf_range(0.8, 2.0))


func _nibble(delta: float) -> void:
	_stand(_flat(), 0.0)
	_look += delta * 18.0
	body.rotation.x = -0.8 + sin(_look) * 0.08
	if _timer > 0.0:
		return
	burrows.bury(_flat(), 1)
	_sit_for(randf_range(1.0, 2.0))


func _go_climb(tree: Dictionary, speed: float, perch: float) -> void:
	_tree = tree
	_perch = perch
	_around = (_flat() - tree["position"]).angle()
	_run_to(tree["position"] + Vector2.from_angle(_around) * (tree["radius"] + TRUNK_GAP + 0.1), State.CLIMB_UP, speed)


func _run_to(goal: Vector2, then: State, speed: float) -> void:
	_goal = goal
	_then = then
	_speed = speed
	state = State.SCURRY
	_timer = 0.0


func _sit_for(seconds: float) -> void:
	state = State.SIT
	_timer = seconds


func _nearest_tree(random_pick: bool) -> Dictionary:
	var usable: Array[Dictionary] = []
	for tree in burrows.forest.trees_near(_flat(), TREE_SEARCH):
		if not burrows.explosives.is_burning(tree["index"]) and not burrows.forest.is_charred(tree["index"]):
			usable.append(tree)
	if usable.is_empty():
		return {}
	if random_pick:
		return usable.pick_random()
	var best := usable[0]
	for tree in usable:
		if (tree["position"] as Vector2).distance_to(_flat()) < (best["position"] as Vector2).distance_to(_flat()):
			best = tree
	return best


func _stand(flat: Vector2, lift: float) -> void:
	basis = Basis(Vector3.UP, _yaw)
	position = Vector3(flat.x, burrows.field.sample_depth(flat) - 0.02 + lift, flat.y)


func _flat() -> Vector2:
	return Forest.flat(position)
