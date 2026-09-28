class_name Main
extends Node3D

const FOREST_SEED := 4242
const LEAF_SEED := 20261014
const BURROW_SEED := 99
const DEBUG_ACORNS := 50
const DEBUG_BUDDIES := 8
const TOILET_HOME := Vector2(-30.0, -26.0)
const RUSTLE_DB := -1.41

@export var spawn_near_toilet := false
@export var spawn_with_squirrels := false
@export var spawn_with_buddies := false
@export var spawn_with_leaf_blower := false
@export var spawn_near_bucket := false
@export var spawn_with_acorns := false
@export var instant_win := false
@export var found_sound: AudioStream
@export var pickup_sound: AudioStream
@export var step_sound: AudioStream
@export var mulch_sound: AudioStream
@export var foliage_sound: AudioStream
@export var use_sound: AudioStream
@export var grab_sound: AudioStream
@export var photo_sound: AudioStream

var play_time := 0.0

var _rustle: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _level := 0.0
var _low := 0.0
var _band := 0.0
var _crackle := 0.0
var _ruffle_cooldown := 0.0
var _was_in_foliage := false
var _snapping := false

@onready var forest: Forest = %Forest
@onready var field: LeafWorld = %LeafWorld
@onready var lost_items: LostItems = %LostItems
@onready var burrows: Burrows = %Burrows
@onready var pickups: Pickups = %Pickups
@onready var player: Player = %Player
@onready var item_user: ItemUser = %ItemUser
@onready var hud: Hud = %Hud
@onready var toilet: Node3D = %Toilet
@onready var sfx: AudioStreamPlaybackPolyphonic = ($Sfx as AudioStreamPlayer).get_stream_playback()
@onready var day_night: DayNight = %DayNight
@onready var ambience: AudioStreamPlayer = $Ambience
@onready var ambience_night: AudioStreamPlayer = $AmbienceNight


func _ready() -> void:
	_rustle = ($Rustle as AudioStreamPlayer).get_stream_playback()
	App.play_music()
	var tree_clearings: Array[Vector3] = [Vector3(0.0, 0.0, 4.0), Vector3(TOILET_HOME.x, TOILET_HOME.y, 4.5)]
	var save := {} if App.new_game or not App.has_save() else App.read_save()
	App.load_progress(save.is_empty())
	App.goal_reached.connect(_on_goal)
	%WinScreen.get_node("Root/Panel/Buttons/KeepRaking").pressed.connect(_new_season)
	App.new_game = false
	forest.build(FOREST_SEED, tree_clearings)
	var leaf_clearings: Array[Vector3] = [Vector3(TOILET_HOME.x, TOILET_HOME.y, 1.4)]
	field.setup(save.get("leaf_seed", LEAF_SEED), leaf_clearings)
	if not save.is_empty():
		field.load_state(save["leaves"])
	forest.settle_on(field)
	if save.is_empty():
		burrows.populate(BURROW_SEED)
		lost_items.scatter(randi())
	else:
		burrows.burrows.assign(save["burrows"])
		lost_items.restore(save["items"])
	var start := Vector2.ZERO
	if spawn_near_toilet:
		start = TOILET_HOME + Vector2(0.0, 4.0)
	elif spawn_near_bucket:
		start = lost_items.get_item(&"tin_bucket")["pos"] + Vector2(0.0, 1.5)
	player.teleport(start, 0.0)
	if not save.is_empty():
		_load_game(save)
	if spawn_with_leaf_blower:
		item_user.inventory.add_to_pockets(&"leaf_blower", 1)
	if spawn_with_acorns:
		item_user.inventory.add_to_pockets(&"acorn", DEBUG_ACORNS)
	if spawn_with_squirrels:
		burrows.fill_army()
	if spawn_with_buddies:
		var buddy: PackedScene = load(ItemDb.get_item(&"gingerbread_buddy").placed_scene)
		for i in DEBUG_BUDDIES:
			var node: Node3D = buddy.instantiate()
			node.set_meta("debug", true)
			var spot := Forest.flat(player.position) + Vector2.from_angle(i * TAU / DEBUG_BUDDIES) * 2.0
			node.position = Vector3(spot.x, 0.0, spot.y)
			$Placed.add_child(node)
	hud.bind_inventory(item_user.inventory)
	hud.set_items(lost_items.names())
	for item in lost_items.items:
		if item["found"]:
			hud.mark_found(item["index"], false)
	hud.won = lost_items.found_count == lost_items.items.size()
	lost_items.found.connect(_on_lost_item_found)
	if not save.is_empty() and hud.won:
		_new_season.call_deferred()
	if instant_win:
		get_tree().create_timer(1.5).timeout.connect(_win)


func _process(delta: float) -> void:
	var spot := Forest.nearest_copy(TOILET_HOME, Forest.flat(player.position))
	toilet.position = Vector3(spot.x, 0.0, spot.y)
	var to_viewer := player.camera.global_position - toilet.global_position
	toilet.rotation.y = lerp_angle(toilet.rotation.y, atan2(to_viewer.x, to_viewer.z), 0.1)

	var activity := player.rake_activity
	for i in _rustle.get_frames_available():
		_level += (activity - _level) * 0.0015
		var white := _rng.randf() * 2.0 - 1.0
		_low += (white - _low) * 0.45
		_band += (_low - _band) * 0.04
		if _rng.randf() < _level * 0.003:
			_crackle = _rng.randf_range(0.4, 1.0)
		_crackle *= 0.985
		var sample := ((_low - _band) * 1.8 + white * _crackle * 0.6) * _level
		_rustle.push_frame(Vector2(sample, sample))

	if not hud.won:
		play_time += delta
	_ruffle_cooldown -= delta
	var inside := player.foliage_activity > 0.05
	if inside and (not _was_in_foliage or _ruffle_cooldown <= 0.0):
		play_sfx(foliage_sound, linear_to_db(clampf(0.3 + player.foliage_activity * 0.6, 0.05, 1.0)) + RUSTLE_DB, 1.15)
		_ruffle_cooldown = lerpf(0.6, 0.16, clampf(player.foliage_activity, 0.0, 1.0)) * randf_range(0.75, 1.25)
	_was_in_foliage = inside

	var night := 1.0 - day_night.daylight
	ambience.volume_db = linear_to_db(maxf(1.0 - night, 0.001)) - 2.0
	ambience_night.volume_db = linear_to_db(maxf(night, 0.001)) - 2.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"fresh_leaves") and not hud.is_inventory_open():
		reset_leaves(randi())
	elif event.is_action_pressed(&"photo") and not hud.is_inventory_open():
		take_photo()


func reset_leaves(new_seed: int) -> void:
	field.reset_leaves(new_seed)
	forest.settle_on(field)
	lost_items.scatter(new_seed)
	hud.set_items(lost_items.names())
	for item in lost_items.items:
		if item["found"]:
			hud.mark_found(item["index"], false)


func take_photo() -> void:
	if _snapping:
		return
	_snapping = true
	hud.visible = false
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	App.save_photo(image)
	App.bump(&"photos")
	hud.visible = true
	hud.flash_photo(image)
	play_sfx(photo_sound, -4.0, 1.3)
	_snapping = false


func _crunch(strength: float) -> void:
	play_sfx(foliage_sound, linear_to_db(clampf(0.4 + strength * 0.6, 0.05, 1.0)) + 2.0 + RUSTLE_DB, 0.8)


func play_sfx(stream: AudioStream, volume_db := 0.0, pitch := 1.0) -> void:
	sfx.play_stream(stream, 0.0, volume_db, pitch)


func _exit_tree() -> void:
	App.save_progress()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func save_game() -> void:
	App.save_progress()
	var placed: Array[Dictionary] = []
	for node: Node3D in $Placed.get_children():
		if not node.is_queued_for_deletion() and not node.has_meta("debug"):
			placed.append({"id": node.get("item_id"), "position": node.position, "rotation": node.rotation.y, "storage": node.storage.slots if node.storage else []})
	var dropped: Array[Dictionary] = []
	for entry in pickups._pickups:
		dropped.append({"id": entry["id"], "count": entry["count"], "position": (entry["node"] as Node3D).position, "delay": entry["delay"]})
	App.write_save({
		"leaf_seed": field.leaf_seed,
		"leaves": field.save_state(),
		"items": lost_items.save_state(),
		"burrows": burrows.burrows,
		"squirrels": burrows.save_squirrels(),
		"charred": forest._charred.keys(),
		"player": [player.position, player.yaw, player.pitch],
		"time": day_night.time_of_day,
		"played": play_time,
		"pockets": item_user.inventory.slots,
		"selected": item_user.inventory.selected,
		"effects": item_user.effects,
		"chalice": item_user.chalice_refill,
		"bucket": item_user.bucket_refill,
		"bottle": item_user.bottle_target,
		"placed": placed,
		"dropped": dropped,
	}, {"found": lost_items.found_count, "total": lost_items.items.size(), "time": play_time, "ids": lost_items.items.filter(func(item: Dictionary) -> bool: return item["found"]).map(func(item: Dictionary) -> StringName: return item["id"])})


func _load_game(save: Dictionary) -> void:
	var at: Vector3 = save["player"][0]
	player.teleport(Vector2(at.x, at.z), save["player"][1])
	player.position.y = at.y
	player.pitch = save["player"][2]
	burrows.restore_squirrels(save.get("squirrels", []))
	day_night.time_of_day = save["time"]
	play_time = save.get("played", 0.0)
	for index: int in save["charred"]:
		forest.char_tree(index)
	for i in save["pockets"].size():
		item_user.inventory.set_stack(i, save["pockets"][i])
	item_user.inventory.select(save["selected"])
	item_user.effects = save["effects"]
	item_user.chalice_refill = save["chalice"]
	item_user.bucket_refill = save["bucket"]
	item_user.bottle_target = save["bottle"]
	for entry: Dictionary in save["placed"]:
		var node: Node3D = (load(ItemDb.get_item(entry["id"]).placed_scene) as PackedScene).instantiate()
		node.position = entry["position"]
		node.rotation.y = entry["rotation"]
		$Placed.add_child(node)
		for i in entry["storage"].size():
			node.storage.set_stack(i, entry["storage"][i])
	for entry: Dictionary in save["dropped"]:
		pickups.spawn(entry["id"], entry["count"], entry["position"], Vector3.ZERO, maxf(entry["delay"], 0.0))


func _on_lost_item_found(id: StringName, node: Node3D) -> void:
	hud.mark_found(lost_items.get_item(id)["index"])
	App.bump(&"lost_found")
	play_sfx(found_sound, -4.0)
	item_user.on_lost_item_found(id, node)
	if lost_items.found_count == lost_items.items.size():
		_win()
	save_game()


func _new_season() -> void:
	App.bump(&"seasons")
	item_user.bottle_target = &""
	var new_seed := randi()
	field.reset_leaves(new_seed)
	forest.settle_on(field)
	lost_items.scatter(new_seed, true)
	hud.set_items(lost_items.names())
	play_time = 0.0
	hud.toast("Season %d. The leaves fell again and everything got lost." % (int(App.stats.get(&"seasons", 0.0)) + 1))
	save_game()


func _on_goal(goal: Goal, tier: int) -> void:
	var count := goal.reward_for(tier)
	item_user.inventory.add_to_pockets(goal.reward, count)
	hud.toast("Goal done: %s   +%d %s" % [goal.text(tier), count, ItemDb.display_name(goal.reward).to_lower() + ("s" if count > 1 else "")])
	play_sfx(found_sound, -8.0, 1.4)


func _win() -> void:
	hud.won = true
	player.shake(1.0)
	%WinScreen.celebrate(lost_items.items.size(), play_time, App.record_time(play_time))


func _on_acorn_uncovered(acorn: Node3D) -> void:
	lost_items.flash(acorn.position)
	item_user.on_lost_item_found(&"acorn", acorn)
	_on_collected(&"acorn", 1)


func _on_collected(id: StringName, count: int) -> void:
	play_sfx(pickup_sound, -8.0, 1.5)
	hud.show_pickup(ItemDb.display_name(id), count)


func _on_player_landed(speed: float) -> void:
	if field.sample_depth(Forest.flat(player.position)) >= 0.05:
		player.splash_at(player.global_position, clampf(speed / Player.JUMP_SPEED, 0.3, 1.0))
		_crunch(clampf(speed / Player.JUMP_SPEED, 0.3, 1.0))


func _on_step() -> void:
	play_sfx(step_sound, -4.0)
	var depth := field.sample_depth(Forest.flat(player.position))
	if depth > 0.02:
		play_sfx(mulch_sound, linear_to_db(clampf(0.35 + depth * 1.5, 0.35, 1.0)) + 2.0 + RUSTLE_DB)


func _on_player_dashed() -> void:
	if field.sample_depth(Forest.flat(player.position)) > 0.05:
		_crunch(0.6)


func _on_exploded(where: Vector3) -> void:
	player.shake(clampf(1.2 - player.camera.global_position.distance_to(where) / 25.0, 0.0, 1.0))
	burrows.startle(where)
	lost_items.check()
