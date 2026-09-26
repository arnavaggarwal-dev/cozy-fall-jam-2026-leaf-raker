class_name ButtonThief
extends Node2D

enum State { OFF, ENTER, WATCH, STEAL, EXIT, SHOCK }

const RUN_SPEED := 520.0
const ENTER_SECONDS := 0.6
const DODGE_DISTANCE := 170.0
const DODGE_COOLDOWN := 0.45
const EDGE := 90.0
const SHOCK_SECONDS := 1.1
const FLEE_SPEED := 900.0

@export var button: Button
@export var slot: Control
@export var side := 1
@export var arrives := true
@export var waves := false
@export var grab_distance := 110.0

var state := State.OFF
var _wanted := false
var _carrying := false
var _dropped := false
var _scared := false
var _goal := Vector2.ZERO
var _dodge := 0.0
var _speed := RUN_SPEED
var _shock := 0.0
var _shock_spot := Vector2.ZERO

@onready var squirrel: Squirrel2D = $Squirrel
@onready var emote: AnimatedSprite2D = $Squirrel/Emote


func _ready() -> void:
	button.pressed.connect(func() -> void:
		if state == State.STEAL:
			_caught())


func arrive() -> void:
	_wanted = true
	_scared = false
	_dropped = false
	if not arrives:
		_carrying = false
		state = State.WATCH
		squirrel.mode = Squirrel2D.Mode.WAVE if waves else Squirrel2D.Mode.WATCH
	elif state == State.OFF:
		_enter()


func leave() -> void:
	_wanted = false
	if state != State.OFF and state != State.SHOCK:
		_run_off(RUN_SPEED)


func _enter() -> void:
	state = State.ENTER
	squirrel.position = Vector2(-150.0 if side < 0 else _screen().x + 150.0, _post().y)
	_speed = maxf(RUN_SPEED, squirrel.position.distance_to(_post()) / ENTER_SECONDS)
	squirrel.mode = Squirrel2D.Mode.RUN
	emote.visible = false


func _run_off(speed: float) -> void:
	state = State.EXIT
	_speed = speed
	_goal = Vector2(-150.0 if side < 0 else _screen().x + 150.0, squirrel.position.y)
	squirrel.mode = Squirrel2D.Mode.CARRY if _carrying else Squirrel2D.Mode.RUN


func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if state != State.STEAL or click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var a := squirrel.to_global(squirrel.offset)
	var b := squirrel.to_global(squirrel.offset + Vector2(Squirrel2D.CELL, Squirrel2D.CELL))
	if Rect2(a, Vector2.ZERO).expand(b).has_point(click.position):
		get_viewport().set_input_as_handled()
		if button.toggle_mode:
			button.button_pressed = not button.button_pressed
		button.pressed.emit()


func _caught() -> void:
	state = State.SHOCK
	_shock = SHOCK_SECONDS
	_shock_spot = squirrel.position
	_carrying = false
	_dropped = true
	squirrel.play(&"panic")
	emote.visible = true
	emote.play(&"shock")


func _process(delta: float) -> void:
	if slot.custom_minimum_size == Vector2.ZERO:
		slot.custom_minimum_size = button.get_combined_minimum_size()
	var mouse := get_viewport().get_mouse_position()
	var home := slot.is_visible_in_tree()
	match state:
		State.ENTER:
			if _run_to(_post(), delta):
				state = State.WATCH
				_speed = RUN_SPEED
				squirrel.mode = Squirrel2D.Mode.WAVE if waves else Squirrel2D.Mode.WATCH
		State.WATCH:
			squirrel.position = _post()
			squirrel.scale.x = absf(squirrel.scale.x) * (1.0 if mouse.x > squirrel.position.x else -1.0)
			var r := slot.get_global_rect()
			if home and not _dropped and mouse.distance_to(mouse.clamp(r.position, r.end)) < grab_distance:
				state = State.STEAL
				_carrying = true
				squirrel.mode = Squirrel2D.Mode.CARRY
				_goal = _escape_spot(mouse)
		State.STEAL:
			_dodge -= delta
			if _dodge <= 0.0 and mouse.distance_to(squirrel.position) < DODGE_DISTANCE:
				_goal = _escape_spot(mouse)
				_dodge = DODGE_COOLDOWN
			if _run_to(_goal, delta):
				_goal = _escape_spot(mouse)
		State.SHOCK:
			squirrel.position = _shock_spot + Vector2(randf_range(-6, 6), randf_range(-4, 4))
			_shock -= delta
			if _shock < SHOCK_SECONDS * 0.5 and emote.animation != &"sweat":
				emote.play(&"sweat")
			if _shock <= 0.0:
				_scared = true
				_run_off(FLEE_SPEED)
		State.EXIT:
			if _run_to(_goal, delta):
				state = State.OFF
				_carrying = false
				emote.visible = false
				if _wanted and not _scared:
					_enter()
	squirrel.visible = state != State.OFF and (state != State.WATCH or home)
	button.disabled = state == State.ENTER
	if _carrying:
		button.visible = true
		button.position = squirrel.paw_global() - Vector2(button.size.x * 0.5, button.size.y - 10.0)
	elif _dropped:
		button.visible = home
	else:
		var r := slot.get_global_rect()
		button.position = r.position
		button.size = r.size
		button.visible = home


func _run_to(target: Vector2, delta: float) -> bool:
	var to := target - squirrel.position
	squirrel.position += to.limit_length(_speed * delta)
	if absf(to.x) > 4.0:
		squirrel.scale.x = absf(squirrel.scale.x) * signf(to.x)
	return to.length() < 20.0


func _post() -> Vector2:
	var r := slot.get_global_rect()
	return Vector2(r.get_center().x + side * (button.get_combined_minimum_size().x * 0.5 + 40.0), r.end.y + 4.0)


func _escape_spot(mouse: Vector2) -> Vector2:
	var best := squirrel.position
	var best_d := -1.0
	for i in 8:
		var p := Vector2(randf_range(EDGE + 80.0, _screen().x - EDGE), randf_range(EDGE + 120.0, _screen().y - EDGE))
		if p.distance_to(mouse) > best_d:
			best_d = p.distance_to(mouse)
			best = p
	return best


func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size
