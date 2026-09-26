extends Node3D

const BOUNCE_RADIUS := 0.85
const LAUNCH_SPEED := 12.0
const BUDDY_SPEED := 4.2
const BUDDY_FETCH_RANGE := 12.0
const BUDDY_FOLLOW_DISTANCE := 1.6
const BUDDY_DIG_SECONDS := 1.2
const BUDDY_REACH := 0.35

@export var item_id := &""
@export var aim_height := 0.5

var storage: Inventory

var _target := Vector2.INF
var _digging := 0.0
var _carrying := 0
var _walk := 0.0

@onready var game: Main = get_parent().owner
@onready var model: Node3D = $Model


func _ready() -> void:
	match item_id:
		&"treasure_chest":
			storage = Inventory.new(27)
			scale = Vector3.ONE * 0.2
			create_tween().tween_property(self, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		&"toadstool":
			scale = Vector3.ONE * 0.05
			create_tween().tween_property(self, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func prompt() -> String:
	match item_id:
		&"treasure_chest":
			return "%s open the chest    %s pick it up" % [App.glyph(&"use"), App.glyph(&"pick_up")]
		&"toadstool":
			return "Walk onto it to bounce    %s pick it up" % App.glyph(&"pick_up")
	return "%s pick up the Gingerbread Buddy" % App.glyph(&"pick_up")


func pick_up_problem() -> String:
	return "Empty the chest before picking it up." if storage and not storage.is_empty() else ""


func _process(delta: float) -> void:
	var player := game.player
	var home := Forest.flat(player.global_position)
	if item_id == &"gingerbread_buddy":
		_fetch(home, delta)
		return
	var flat := Forest.nearest_copy(Forest.flat(position), home)
	position.x = flat.x
	position.z = flat.y
	if item_id == &"treasure_chest":
		position.y = maxf(game.field.sample_depth(flat) - 0.08, 0.0)
		return
	position.y = 0.0
	var offset := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z)
	if scale.x > 0.9 and offset.length() < BOUNCE_RADIUS and player.position.y < 0.6 and player.vertical_speed <= 0.0:
		player.launch(LAUNCH_SPEED)
		$Boing.play()
		var squash := create_tween()
		squash.tween_property(model, "scale:y", model.scale.y * 0.7, 0.08)
		squash.tween_property(model, "scale:y", model.scale.y, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _fetch(home: Vector2, delta: float) -> void:
	var burrows := game.burrows
	var me := Forest.nearest_copy(Forest.flat(position), home)
	var goal := me

	if _carrying > 0:
		goal = home
		if me.distance_to(home) < 1.0:
			var left := game.item_user.inventory.add_to_pockets(&"acorn", _carrying)
			if left < _carrying:
				game.pickups.collected.emit(&"acorn", _carrying - left)
			if left > 0:
				game.pickups.spawn(&"acorn", left, global_position + Vector3.UP * 0.3)
			_carrying = 0
	elif _target != Vector2.INF and not burrows.points_near(_target, 0.05).is_empty():
		if me.distance_to(_target) > BUDDY_REACH:
			goal = _target
		else:
			_digging += delta
			if _digging >= BUDDY_DIG_SECONDS:
				_carrying = burrows.dig(_target, 0.05)
				game.field.blast(_target, 0.4, 0.6)
				_target = Vector2.INF
				_digging = 0.0
	else:
		_target = Vector2.INF
		_digging = 0.0
		for spot in burrows.points_near(home, BUDDY_FETCH_RANGE):
			if _target == Vector2.INF or spot.distance_to(me) < _target.distance_to(me):
				_target = spot
		if _target == Vector2.INF and me.distance_to(home) > BUDDY_FOLLOW_DISTANCE:
			goal = home + (me - home).normalized() * BUDDY_FOLLOW_DISTANCE

	var step := (goal - me).limit_length(BUDDY_SPEED * delta)
	me = game.forest.push_out(me + step, 0.12)
	position = Vector3(me.x, game.field.sample_depth(me), me.y)
	if step.length() > 0.002:
		rotation.y = atan2(step.x, step.y)
		_walk += delta * 14.0
		model.rotation.z = sin(_walk) * 0.18
		model.position.y = absf(sin(_walk)) * 0.05
	elif _digging > 0.0:
		model.rotation.z = sin(_digging * 40.0) * 0.25
		model.position.y = absf(sin(_digging * 20.0)) * 0.04
	else:
		model.rotation.z = lerpf(model.rotation.z, 0.0, 1.0 - exp(-delta * 10.0))
		model.position.y = 0.0
