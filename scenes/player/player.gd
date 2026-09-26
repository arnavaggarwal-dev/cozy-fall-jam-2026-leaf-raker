class_name Player
extends Node3D

const EYE_HEIGHT := 1.68
const FOV := 72.0
const JUMP_SPEED := 5.0
const GRAVITY := 9.81
const LANDING_SPEED := 2.0
const WALK_SPEED := 3.2
const DASH_SPEED := 16.0
const STRIDE := 1.25
const DASH_SECONDS := 0.3
const DASH_COOLDOWN := 0.65
const DASH_FOV := 12.0
const HANDLE_LENGTH := 2.0
const BODY_RADIUS := 0.3
const MOVE_STEP := 0.25
const REACH_MIN := 0.5
const REACH_MAX := 2.9
const HEAD_SPEED := 6.5
const HEAD_RAISED := 0.35
const TINE_DEPTH := 0.1
const MOUSE_SENSITIVITY := 0.0022
const KEY_TURN_SPEED := 2.4
const KEY_PITCH_SPEED := 1.6
const RAKE_SCALE := 1.45
const GRIP := Vector3(0.3, -0.5, -0.25)
const DRAG_GRIP := Vector3(0.3, -0.3, -0.55)
const HELD_HAND := Vector3(0.3, -0.3, -0.55)
const BLOWER_SIZE := 0.42
const OFF_HAND := Vector3(-0.28, -0.24, -0.6)
const LANTERN_SIZE := 0.2
const LANTERN_TAKE_SECONDS := 0.8
const LANTERN_ENERGY := 2.0

signal landed(speed: float)
signal dashed
signal stepped

var yaw := 0.0
var pitch := -0.45
var velocity := Vector2.ZERO
var vertical_speed := 0.0
var head_pos := Vector2.ZERO
var head_height := HEAD_RAISED
var rake_activity := 0.0
var foliage_activity := 0.0
var dragging := false
var primary_down := false
var input_enabled := true
var speed_multiplier := 1.0
var jump_multiplier := 1.0
var dash_cooldown_multiplier := 1.0
var air_jumps := 0
var blowing := false
var night := 0.0

var _last_yaw := 0.0
var _jump_queued := false
var _dash_queued := false
var _dash_left := 0.0
var _dash_cooldown := 0.0
var _dash_dir := Vector2.ZERO
var _drag := 0.0
var _shake := 0.0
var _head_dir := Vector2(0.0, -1.0)
var _air_jumps_left := 0
var _stride := 0.0
var _held_id := &"rake"
var _held_model: Node3D
var _swing := 0.0
var _lantern: Node3D
var _off_hand_id := &""
var _time := 0.0

@onready var camera: Camera3D = $Camera
@onready var held_item: Node3D = $Camera/HeldItem
@onready var lantern_hand: Node3D = $Camera/LanternHand
@onready var lantern_light: OmniLight3D = $Camera/LanternHand/Grip/Light
@onready var rake: Node3D = $Rake
@onready var falling_leaves: GPUParticles3D = $FallingLeaves
@onready var splash: GPUParticles3D = $Splash
@onready var trail: GPUParticles3D = $Trail
@onready var field: LeafWorld = %LeafWorld
@onready var forest: Forest = %Forest


func teleport(pos: Vector2, new_yaw: float) -> void:
	position = Vector3(pos.x, 0.0, pos.y)
	vertical_speed = 0.0
	yaw = new_yaw
	velocity = Vector2.ZERO
	_dash_left = 0.0
	_drag = 0.0
	dragging = false
	_head_dir = forward()
	head_pos = pos + _head_dir * 2.0
	field.update_window(pos)


func launch(speed: float) -> void:
	vertical_speed = speed
	_air_jumps_left = air_jumps
	position.y = maxf(position.y, 0.001)


func forward() -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


func aim_point(max_distance: float) -> Vector3:
	var p := Forest.flat(position)
	var target := p + forward() * max_distance
	var ray := -camera.global_basis.z
	var surface_y := field.sample_depth(p + forward() * 2.0)
	if ray.y < -0.02:
		var hit := camera.global_position + ray * ((camera.global_position.y - surface_y) / -ray.y)
		target = Forest.flat(hit)
	target = p + (target - p).limit_length(max_distance)
	return Vector3(target.x, field.sample_depth(target), target.y)


func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


func splash_at(where: Vector3, strength: float) -> void:
	splash.global_position = where
	splash.amount_ratio = clampf(strength, 0.1, 1.0)
	splash.restart()


func hold(id: StringName) -> void:
	if id == _held_id:
		return
	_held_id = id
	if _held_model:
		_held_model.queue_free()
		_held_model = null
	if id == &"" or id == &"rake":
		return
	_held_model = ItemDb.spawn_model(id, BLOWER_SIZE if id == &"leaf_blower" else clampf(ItemDb.get_item(id).world_size, 0.12, 0.3))
	_held_model.rotation.y = 0.0 if id == &"leaf_blower" else deg_to_rad(-30.0)
	for mesh: GeometryInstance3D in _held_model.find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	held_item.add_child(_held_model)
	swing()


func swing() -> void:
	_swing = 1.0


func take_lantern(lantern: Node3D) -> void:
	if _lantern:
		_lantern.queue_free()
	_lantern = lantern
	_off_hand_id = &"old_lantern"
	lantern_hand.visible = true
	var size: Vector3 = lantern.get_meta("size")
	lantern.reparent(lantern_hand.get_node("Grip"), true)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(lantern, "position", Vector3.ZERO, LANTERN_TAKE_SECONDS)
	tween.tween_property(lantern, "quaternion", Quaternion.IDENTITY, LANTERN_TAKE_SECONDS)
	tween.tween_property(lantern, "scale", Vector3.ONE * (LANTERN_SIZE / maxf(maxf(size.x, size.y), size.z)), LANTERN_TAKE_SECONDS)


func set_off_hand(id: StringName) -> void:
	if id == _off_hand_id:
		return
	_off_hand_id = id
	if _lantern:
		_lantern.queue_free()
		_lantern = null
	lantern_hand.visible = id != &""
	lantern_light.visible = false
	if id != &"":
		_lantern = ItemDb.spawn_model(id, LANTERN_SIZE)
		lantern_hand.get_node("Grip").add_child(_lantern)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var motion := event as InputEventMouseMotion
	if motion and captured:
		yaw -= motion.relative.x * MOUSE_SENSITIVITY * App.sensitivity
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENSITIVITY * App.sensitivity, -1.5, 0.6)
	elif (event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed() and not captured:
		Input.set_deferred("mouse_mode", Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var fwd := forward()
	var right := Vector2(-fwd.y, fwd.x)

	var input := Vector2.ZERO
	if captured and input_enabled:
		input = Vector2(_key(&"right") - _key(&"left"), _key(&"forward") - _key(&"back"))
		yaw += (_key(&"look_left") - _key(&"look_right")) * KEY_TURN_SPEED * App.sensitivity * delta
		pitch = clampf(pitch + (_key(&"look_up") - _key(&"look_down")) * KEY_PITCH_SPEED * App.sensitivity * delta, -1.5, 0.6)
		_jump_queued = _jump_queued or Input.is_action_just_pressed(&"jump")
		_dash_queued = _dash_queued or Input.is_action_just_pressed(&"dash")
	var wish := (right * input.x + fwd * input.y).limit_length(1.0) * WALK_SPEED * speed_multiplier

	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	if _dash_queued and _dash_cooldown <= 0.0:
		_dash_dir = wish.normalized() if wish.length() > 0.1 else fwd
		_dash_left = DASH_SECONDS
		_dash_cooldown = DASH_COOLDOWN * dash_cooldown_multiplier
		dashed.emit()
	_dash_queued = false
	var dashing := _dash_left > 0.0
	if dashing:
		_dash_left -= delta
		velocity = _dash_dir * DASH_SPEED
	else:
		velocity = velocity.lerp(wish, 1.0 - exp(-delta * 10.0))

	var p := Forest.flat(position)
	var travel := velocity * delta
	var steps := maxi(ceili(travel.length() / MOVE_STEP), 1)
	for step in steps:
		p = forest.push_out(p + travel / steps, BODY_RADIUS, position.y)
	var ground := forest.floor_at(p, position.y)

	if _jump_queued:
		if position.y <= ground and vertical_speed <= 0.0:
			vertical_speed = JUMP_SPEED * jump_multiplier
			_air_jumps_left = air_jumps
		elif _air_jumps_left > 0:
			_air_jumps_left -= 1
			vertical_speed = JUMP_SPEED * jump_multiplier
	_jump_queued = false
	vertical_speed -= GRAVITY * delta
	var feet := position.y + vertical_speed * delta
	if feet <= ground:
		if vertical_speed < -LANDING_SPEED:
			landed.emit(-vertical_speed)
		feet = ground
		vertical_speed = 0.0
	if feet <= ground:
		_stride += Forest.flat(position).distance_to(p)
		if _stride >= STRIDE:
			_stride = fmod(_stride, STRIDE)
			stepped.emit()
	position = Vector3(p.x, feet, p.y)

	var inside := maxf(forest.foliage_at(Vector3(p.x, feet + EYE_HEIGHT, p.y)), forest.foliage_at(Vector3(p.x, feet + 0.9, p.y)))
	var push := 0.0
	if inside > 0.0:
		var turning := absf(angle_difference(_last_yaw, yaw)) / maxf(delta, 0.0001)
		push = clampf(velocity.length() / WALK_SPEED + turning * 0.15, 0.0, 1.5) * (0.4 + 0.6 * inside)
	foliage_activity = lerpf(foliage_activity, push, 1.0 - exp(-delta * 10.0))
	_last_yaw = yaw
	forest.update_camera_foliage(Vector3(p.x, feet + EYE_HEIGHT, p.y))
	field.update_window(p)
	rotation.y = yaw
	camera.rotation.x = pitch
	var bob := -absf(sin(_stride / STRIDE * PI)) * 0.03 * clampf(velocity.length() / WALK_SPEED, 0.0, 1.0) if feet <= ground else 0.0
	camera.position.y = EYE_HEIGHT + bob
	camera.fov = lerpf(camera.fov, FOV + (DASH_FOV if dashing else 0.0), 1.0 - exp(-delta * 12.0))
	_shake = maxf(_shake - delta * 1.6, 0.0)
	var jitter := _shake * _shake * 0.15
	camera.h_offset = randf_range(-jitter, jitter)
	camera.v_offset = randf_range(-jitter, jitter)

	var aim := aim_point(REACH_MAX)
	var offset := Forest.flat(aim) - p
	var dist := offset.length()
	var dir := offset / dist if dist > 0.001 else fwd
	var target := p + dir * clampf(dist, REACH_MIN, REACH_MAX)

	var rake_in_hand := _held_id == &"rake"
	rake.visible = rake_in_hand
	var towing := rake_in_hand and (dashing or (_drag >= 1.0 and velocity.length() > WALK_SPEED * 1.3))
	_drag = move_toward(_drag, 1.0 if towing else 0.0, delta / (0.08 if towing else 0.3))
	dragging = _drag >= 1.0
	var prev := head_pos
	head_pos = head_pos + (target - head_pos).limit_length(HEAD_SPEED * delta)
	if _drag > 0.0:
		var hand := camera.global_transform * DRAG_GRIP
		var towed := Forest.flat(hand)
		var drop := hand.y - maxf(field.sample_depth(towed) - TINE_DEPTH, 0.0)
		towed -= _dash_dir * sqrt(maxf(HANDLE_LENGTH * HANDLE_LENGTH - drop * drop, 0.0))
		head_pos = head_pos.lerp(towed, _drag)
	if (head_pos - p).length() > 0.05:
		_head_dir = (head_pos - p).normalized()

	var wants_down := rake_in_hand and captured and primary_down
	var surface := field.sample_depth(head_pos)
	var tines_y := maxf(surface - TINE_DEPTH, 0.0)
	var on_ground := (wants_down and head_height <= tines_y + 0.25 and feet <= 0.05) or (dragging and feet <= 0.3)
	var scraped := field.apply_rake(prev, head_pos, _head_dir, p) if on_ground else 0.0
	if dragging:
		head_height = tines_y
	else:
		head_height = move_toward(head_height, tines_y if wants_down else surface + HEAD_RAISED, delta * 6.0)

	var target_activity := 0.0
	if on_ground:
		target_activity = clampf(prev.distance_to(head_pos) / maxf(delta, 0.0001) / 3.0, 0.0, 1.0) * clampf(0.25 + scraped * 60.0, 0.0, 1.0)
	rake_activity = lerpf(rake_activity, target_activity, 1.0 - exp(-delta * 12.0))
	_update_hands(delta)
	falling_leaves.global_position = global_position
	trail.emitting = dragging and field.sample_depth(head_pos) > 0.05
	trail.global_position = Vector3(head_pos.x, head_height, head_pos.y)


func _key(action: StringName) -> float:
	return Input.get_action_strength(action)


func _update_hands(delta: float) -> void:
	var head := Vector3(head_pos.x, head_height, head_pos.y)
	var grip := camera.global_transform * GRIP.lerp(DRAG_GRIP, _drag)
	var x_axis := -(grip - head).normalized()
	var lateral := Vector3(-_head_dir.y, 0.0, _head_dir.x)
	var z_axis := -(lateral - x_axis * x_axis.dot(lateral)).normalized()
	rake.global_transform = Transform3D(Basis(x_axis, z_axis.cross(x_axis), z_axis).scaled(Vector3.ONE * RAKE_SCALE), head)

	_time += delta
	_swing = move_toward(_swing, 0.0, delta * 3.0)
	var buzz := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.004 if blowing else Vector3.ZERO
	held_item.position = HELD_HAND + Vector3(0.0, -0.15 * _swing + sin(_time * 2.0) * 0.005, 0.0) + buzz
	held_item.rotation.x = -0.6 * _swing

	if lantern_hand.visible:
		lantern_light.light_energy = LANTERN_ENERGY * night * (0.9 + 0.06 * sin(_time * 13.0) + 0.04 * sin(_time * 29.0))
		lantern_light.visible = night > 0.01 and _off_hand_id == &"old_lantern"
		var walk := clampf(velocity.length() / WALK_SPEED, 0.0, 1.0) if is_zero_approx(vertical_speed) else 0.0
		lantern_hand.position = OFF_HAND + Vector3(0.0, sin(_stride / STRIDE * TAU) * 0.02 * walk + sin(_time * 2.2) * 0.008, 0.0)
		lantern_hand.rotation = Vector3(sin(_time * 1.1) * 0.02, 0.0, sin(_time * 1.3) * 0.03)
