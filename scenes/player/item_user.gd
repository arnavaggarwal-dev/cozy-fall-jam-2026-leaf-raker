class_name ItemUser
extends Node

const CRUMBS := preload("res://scenes/fx/crumbs.tscn")
const BLOW_START := 0.8
const BLOW_END := 2.8
const BLOW_SPEED := Player.HEAD_SPEED * 1.1
const PLACE_REACH := 3.5
const LOOK_REACH := 3.5
const LOOK_RADIUS := 0.5
const CURSOR_SPEED := 1100.0
const CRUMB_REACH := 8.0
const SLING_WIND_SECONDS := 1.0
const SLING_MAX_POWER := 2.6
const CHALICE_SECONDS := 20.0
const CHALICE_REFILL_SECONDS := 40.0
const CHALICE_RANGE := 30.0
const SHIMMERS := 32
const BUCKET_COOLDOWN := 30.0
const PRESENT_SNACKS := [&"shiny_apple", &"cookie", &"sprinkle_donut", &"coffee_mug"]
const EFFECT_NAMES := {&"bouncy": "Bouncy legs", &"sugar": "Sugar rush", &"caffeine": "Caffeinated", &"dowsing": "Dowsing"}

@export var shimmer_column: QuadMesh

var inventory := Inventory.new(Inventory.OFF_HAND + 1, true)
var effects := {}
var effect_totals := {}
var chalice_refill := 0.0
var bucket_refill := 0.0
var sling_charge := -1.0
var bottle_target := &""

var _primary_down := false
var _closed_frame := -1
var _blowing := false
var _blow_along := BLOW_START
var _look_refresh := 0.0
var _shimmer_time := 0.0

@onready var shimmer_material: StandardMaterial3D = shimmer_column.material
@onready var blower_sound: AudioStreamPlayer = $BlowerSound
@onready var player: Player = %Player
@onready var field: LeafWorld = %LeafWorld
@onready var forest: Forest = %Forest
@onready var day_night: DayNight = %DayNight
@onready var burrows: Burrows = %Burrows
@onready var lost_items: LostItems = %LostItems
@onready var explosives: Explosives = %Explosives
@onready var pickups: Pickups = %Pickups
@onready var placed: Node3D = %Placed
@onready var shimmers: MultiMeshInstance3D = %Shimmers
@onready var hud: Hud = %Hud


func _ready() -> void:
	inventory.selection_changed.connect(_on_selection_changed)
	inventory.add_to_pockets(&"rake", 1)


func selected_item() -> ItemData:
	return ItemDb.get_item(inventory.selected_id())


func _input(event: InputEvent) -> void:
	if hud.is_inventory_open():
		if event.is_action_pressed(&"inventory") or event.is_action_pressed(&"ui_cancel"):
			close_inventory()
			_closed_frame = Engine.get_process_frames()
			get_viewport().set_input_as_handled()
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var key := event as InputEventKey
	var button := event as InputEventMouseButton
	if button and button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if button.pressed:
			press_use()
		else:
			release_use()
	elif button and button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
		inventory.select(inventory.selected - 1)
	elif button and button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		inventory.select(inventory.selected + 1)
	elif key and key.pressed and not key.echo and key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_9:
		inventory.select(key.physical_keycode - KEY_1)


func _poll_actions() -> void:
	var stick := Input.get_vector(&"left", &"right", &"forward", &"back")
	if hud.is_inventory_open() and stick != Vector2.ZERO:
		var viewport := get_viewport()
		var motion := InputEventMouseMotion.new()
		motion.position = (viewport.get_mouse_position() + stick * CURSOR_SPEED * get_process_delta_time()).clamp(Vector2.ZERO, viewport.get_visible_rect().size)
		motion.global_position = motion.position
		motion.device = InputEvent.DEVICE_ID_EMULATION
		viewport.warp_mouse(motion.position)
		Input.parse_input_event(motion)
	if hud.is_inventory_open():
		for pad: Array in [[&"ui_accept", MOUSE_BUTTON_LEFT, false], [&"pick_up", MOUSE_BUTTON_RIGHT, false], [&"use", MOUSE_BUTTON_LEFT, true]]:
			if Input.is_action_just_pressed(pad[0]) or Input.is_action_just_released(pad[0]):
				var click := InputEventMouseButton.new()
				click.button_index = pad[1]
				click.shift_pressed = pad[2]
				click.pressed = Input.is_action_pressed(pad[0])
				click.position = get_viewport().get_mouse_position()
				click.global_position = click.position
				click.device = InputEvent.DEVICE_ID_EMULATION
				Input.parse_input_event(click)
	if Input.is_action_just_released(&"use"):
		release_use()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or hud.is_inventory_open() or Engine.get_process_frames() == _closed_frame:
		return
	if Input.is_action_just_pressed(&"use"):
		press_use()
	if Input.is_action_just_pressed(&"hotbar_prev"):
		inventory.select(inventory.selected - 1)
	if Input.is_action_just_pressed(&"hotbar_next"):
		inventory.select(inventory.selected + 1)
	if Input.is_action_just_pressed(&"drop"):
		var stack := inventory.take(inventory.selected, inventory.count_at(inventory.selected) if Input.is_key_pressed(KEY_CTRL) else 1)
		if not stack.is_empty():
			drop_stack(stack)
	if Input.is_action_just_pressed(&"pick_up"):
		pick_up_looked_at()
	if Input.is_action_just_pressed(&"inventory"):
		open_inventory()


func press_use() -> void:
	var looked := _looked_at()
	if looked and looked.get("storage"):
		looked.get_node("OpenSound").play()
		open_inventory(looked.get("storage"))
		return
	var item := selected_item()
	if item == null:
		return
	match item.action:
		&"rake":
			_primary_down = true
		&"blow":
			_blowing = true
		&"throw":
			if _throw_acorn(1.0):
				inventory.take(inventory.selected, 1)
		&"sling":
			if inventory.count_of(&"acorn") == 0:
				hud.toast("No acorns to fling. Rake some up where the sprouts lie.")
			else:
				sling_charge = 0.0
		&"eat":
			_eat(item)
		&"off_hand":
			_swap_off_hand()
		&"place":
			_place(item)
		&"read_note":
			_read_note()
		&"open_present":
			_open_present()
		&"drink_chalice":
			_drink_chalice()
		&"pour":
			_pour()
		&"crumbs":
			_crumble_cookie()
		_:
			hud.toast(item.description)


func release_use() -> void:
	_primary_down = false
	_blowing = false
	if sling_charge >= 0.0:
		var power := lerpf(1.0, SLING_MAX_POWER, sling_charge)
		sling_charge = -1.0
		if inventory.count_of(&"acorn") > 0 and _throw_acorn(power):
			inventory.remove(&"acorn", 1)


func drop_stack(stack: Dictionary) -> void:
	var ahead := -player.camera.global_basis.z
	var entry := pickups.spawn(stack["id"], stack["count"], player.camera.global_position + ahead * 0.5 + Vector3.DOWN * 0.3, ahead * 3.0 + Vector3.UP * 1.5, 1.5)
	if stack["id"] != &"rake":
		var coming := burrows.call_squirrels(entry)
		if coming > 0:
			hud.toast("%d squirrel%s scamper over for the %s!" % [coming, "s" if coming > 1 else "", ItemDb.display_name(stack["id"]).to_lower()])


func pick_up_looked_at() -> void:
	var node := _looked_at()
	if node == null:
		return
	if node.pick_up_problem() != "":
		hud.toast(node.pick_up_problem())
		return
	node.queue_free()
	_give(node.get("item_id"), 1)
	owner.play_sfx(owner.grab_sound, -6.0, 1.3)


func open_inventory(chest: Inventory = null) -> void:
	_primary_down = false
	_blowing = false
	sling_charge = -1.0
	hud.open_inventory(chest)
	player.input_enabled = false
	Input.set_deferred("mouse_mode", Input.MOUSE_MODE_VISIBLE)


func close_inventory() -> void:
	hud.close_inventory()
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func on_lost_item_found(id: StringName, node: Node3D) -> void:
	if id == &"old_lantern" and inventory.get_stack(Inventory.OFF_HAND).is_empty():
		inventory.set_stack(Inventory.OFF_HAND, {"id": id, "count": 1})
		player.take_lantern(node)
	else:
		_give(id, 1)
		lost_items.fly_to_viewer(node)


func _process(delta: float) -> void:
	_poll_actions()
	var item := selected_item()
	var id := item.id if item else &""
	player.primary_down = _primary_down and id == &"rake"
	player.hold(id)

	player.blowing = _blowing and id == &"leaf_blower"
	if player.blowing:
		var feet := Forest.flat(player.position)
		if _blow_along >= BLOW_END:
			_blow_along = BLOW_START
		var prev := feet + player.forward() * _blow_along
		_blow_along += BLOW_SPEED * delta
		var cur := feet + player.forward() * _blow_along
		field.apply_rake(prev, cur, player.forward(), feet)
		player.trail.emitting = true
		player.trail.global_position = Vector3(cur.x, field.sample_depth(cur), cur.y)
	if player.blowing != blower_sound.playing:
		blower_sound.playing = player.blowing

	if sling_charge >= 0.0:
		sling_charge = minf(sling_charge + delta / SLING_WIND_SECONDS, 1.0) if id == &"missing_sock" else -1.0
	hud.set_charge(sling_charge)
	_update_effects(delta)

	var off_hand := inventory.id_at(Inventory.OFF_HAND)
	day_night.night_vision = move_toward(day_night.night_vision, 1.0 if off_hand == &"jack_o_lantern" else 0.0, delta * 1.5)
	player.set_off_hand(off_hand)
	player.night = 1.0 - day_night.daylight

	var feet := Forest.flat(player.position)
	var spots: Array = []
	if effects.has(&"dowsing"):
		spots = burrows.points_near(feet, CHALICE_RANGE) + lost_items.unfound_near(feet, CHALICE_RANGE)
		spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(feet) < b.distance_squared_to(feet))
	shimmers.multimesh.visible_instance_count = mini(spots.size(), SHIMMERS)
	for i in shimmers.multimesh.visible_instance_count:
		shimmers.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(spots[i].x, field.sample_depth(spots[i]), spots[i].y)))
	_shimmer_time += delta
	shimmer_material.albedo_color.a = 0.55 + 0.35 * sin(_shimmer_time * 4.0)

	var told_of := lost_items.get_item(bottle_target)
	hud.compass.visible = not told_of.is_empty() and not told_of["found"]
	if hud.compass.visible:
		var spot := Forest.nearest_copy(told_of["pos"], feet)
		hud.show_compass(player.forward().angle_to(spot - feet), spot.distance_to(feet), ItemDb.display_name(bottle_target))

	_look_refresh -= delta
	if _look_refresh <= 0.0:
		_look_refresh = 0.1
		var looked := _looked_at()
		hud.prompt_label.text = looked.prompt() if looked else ""


func _update_effects(delta: float) -> void:
	var shown: Array = []
	for effect: StringName in effects.keys():
		effects[effect] -= delta
		if effects[effect] <= 0.0:
			effects.erase(effect)
		else:
			shown.append([effect, EFFECT_NAMES[effect], effects[effect], effect_totals.get(effect, effects[effect])])
	chalice_refill = maxf(chalice_refill - delta, 0.0)
	bucket_refill = maxf(bucket_refill - delta, 0.0)
	player.jump_multiplier = 1.5 if effects.has(&"bouncy") else 1.0
	player.air_jumps = 1 if effects.has(&"bouncy") else 0
	player.speed_multiplier = 1.6 if effects.has(&"sugar") else 1.0
	player.dash_cooldown_multiplier = 0.5 if effects.has(&"sugar") else 1.0
	field.rake_half_width = LeafWorld.RAKE_HALF_WIDTH * (2.0 if effects.has(&"caffeine") else 1.0)
	hud.set_effects(shown)


func _on_selection_changed() -> void:
	sling_charge = -1.0
	hud.show_item_name(ItemDb.display_name(inventory.selected_id()) if inventory.selected_id() != &"" else "")


func _looked_at() -> Node3D:
	var camera := player.camera
	var best: Node3D = null
	var best_margin := 0.0
	for node: Node3D in placed.get_children():
		var to: Vector3 = node.global_position + Vector3.UP * node.get("aim_height") - camera.global_position
		var distance := to.length()
		if distance > LOOK_REACH or distance < 0.01:
			continue
		var margin := -camera.global_basis.z.dot(to / distance) - cos(atan2(LOOK_RADIUS, distance))
		if margin >= 0.0 and (best == null or margin > best_margin):
			best = node
			best_margin = margin
	return best


func _throw_acorn(power: float) -> bool:
	var camera := player.camera
	var thrown := explosives.throw(camera.global_transform * Vector3(0.3, -0.25, -0.5), -camera.global_basis.z, Vector3(player.velocity.x, 0.0, player.velocity.y), power)
	if thrown:
		player.swing()
		App.bump(&"acorns_thrown")
	return thrown


func _eat(item: ItemData) -> void:
	inventory.take(inventory.selected, 1)
	effects[item.effect] = item.effect_seconds
	effect_totals[item.effect] = item.effect_seconds
	owner.play_sfx(owner.use_sound, -6.0)
	player.swing()
	hud.toast("%s: %s for %d seconds!" % [item.display_name, EFFECT_NAMES[item.effect], roundi(item.effect_seconds)])


func _swap_off_hand() -> void:
	var held := inventory.get_stack(inventory.selected).duplicate()
	var other := inventory.get_stack(Inventory.OFF_HAND).duplicate()
	inventory.set_stack(Inventory.OFF_HAND, held)
	inventory.set_stack(inventory.selected, other)
	owner.play_sfx(owner.use_sound, -6.0)
	hud.toast("The %s is in your off hand." % ItemDb.display_name(held["id"]))


func _place(item: ItemData) -> void:
	var feet := Forest.flat(player.position)
	var aim := player.aim_point(PLACE_REACH)
	var spot := Forest.flat(aim)
	if spot.distance_to(feet) < 1.2:
		spot = feet + player.forward() * 1.2
	if forest.nearest_obstacle_distance(spot) < 0.6:
		hud.toast("There's no room for that here.")
		return
	var node: Node3D = (load(item.placed_scene) as PackedScene).instantiate()
	node.position = Vector3(spot.x, field.sample_depth(spot), spot.y)
	node.rotation.y = atan2(feet.x - spot.x, feet.y - spot.y)
	placed.add_child(node)
	inventory.take(inventory.selected, 1)
	owner.play_sfx(owner.use_sound, -6.0)
	player.swing()


func _read_note() -> void:
	var feet := Forest.flat(player.position)
	owner.play_sfx(owner.use_sound, -6.0)
	if bottle_target == &"":
		var closest := lost_items.nearest_unfound(feet)
		if closest.is_empty():
			hud.toast("The note is blank. Nothing in the forest is lost anymore.")
			return
		bottle_target = closest["id"]
		hud.toast("The note tells of a lost %s, %d m away. Follow the arrow." % [ItemDb.display_name(bottle_target), roundi(Forest.nearest_copy(closest["pos"], feet).distance_to(feet))])
	elif lost_items.get_item(bottle_target)["found"]:
		hud.toast("The note has nothing more to tell. It only knew of the %s." % ItemDb.display_name(bottle_target))
	else:
		var there := Forest.nearest_copy(lost_items.get_item(bottle_target)["pos"], feet)
		hud.toast("The note still tells of the lost %s, %d m away." % [ItemDb.display_name(bottle_target), roundi(there.distance_to(feet))])


func _open_present() -> void:
	inventory.take(inventory.selected, 1)
	var snacks := PRESENT_SNACKS.duplicate()
	snacks.shuffle()
	var names: Array[String] = []
	for snack: StringName in snacks.slice(0, 2):
		_give(snack, 1)
		names.append(ItemDb.display_name(snack))
	owner.play_sfx(owner.use_sound, -6.0)
	hud.toast("Inside: a %s!" % " and a ".join(names))


func _drink_chalice() -> void:
	if chalice_refill > 0.0:
		hud.toast("The chalice is still refilling (%d s)." % ceili(chalice_refill))
		return
	effects[&"dowsing"] = CHALICE_SECONDS
	effect_totals[&"dowsing"] = CHALICE_SECONDS
	chalice_refill = CHALICE_REFILL_SECONDS
	owner.play_sfx(owner.use_sound, -6.0)
	hud.toast("The ground around you starts to shimmer...")


func _pour() -> void:
	if bucket_refill > 0.0:
		hud.toast("The bucket is still refilling (%d s)." % ceili(bucket_refill))
		return
	var aim := player.aim_point(1.2)
	explosives.pour(Forest.flat(aim), player.forward())
	bucket_refill = BUCKET_COOLDOWN
	$WaterSplash.global_position = aim + Vector3.UP * 0.3
	$WaterSplash.restart()
	owner.play_sfx(owner.use_sound, -6.0)
	player.swing()


func _crumble_cookie() -> void:
	var aim := player.aim_point(CRUMB_REACH)
	inventory.take(inventory.selected, 1)
	var crumbs: Node3D = CRUMBS.instantiate()
	get_parent().add_child(crumbs)
	crumbs.global_position = aim + Vector3.UP * 0.2
	var coming := burrows.bait(Forest.flat(aim))
	owner.play_sfx(owner.use_sound, -6.0)
	hud.toast("%d squirrels smell the crumbs!" % coming if coming > 0 else "No squirrels close enough to smell it.")


func _give(id: StringName, count: int) -> void:
	var left := inventory.add_to_pockets(id, count)
	if left > 0:
		pickups.spawn(id, left, player.global_position + Vector3.UP, Vector3.ZERO, 1.5)
