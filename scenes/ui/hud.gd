class_name Hud
extends CanvasLayer

const GOLD := Color(1.0, 0.78, 0.35)
const MUTED := Color(0.93, 0.87, 0.78, 0.6)
const UI := "res://assets/textures/ui/"

signal drop_requested(stack: Dictionary)

var _found_flags: Array[bool] = []
var _feed: Array[Dictionary] = []
var _names: Array[String] = []
var _found := 0
var _toast_tween: Tween
var _name_tween: Tween
var _pockets: Inventory
var _chest: Inventory
var _acorns := -1
var won := false
var _cursor := {}
var _views: Array[SlotView] = []

@onready var stats_text: Label = $Root/Stats/Box/Text
@onready var effects_text: RichTextLabel = $Root/Stats/Box/Effects
@onready var list: VBoxContainer = $Root/LostThings/List
@onready var list_title: Label = $Root/LostThings/List/Title
@onready var rows_text: RichTextLabel = $Root/LostThings/List/Rows
@onready var prompt_label: RichTextLabel = $Root/Prompt
@onready var toast_label: Label = $Root/Toast
@onready var compass: Control = $Root/Compass
@onready var charge: ProgressBar = $Root/Charge
@onready var item_name: Label = $Root/ItemName
@onready var hotbar: SlotView = $Root/Hotbar
@onready var acorn_panel: PanelContainer = $Root/Acorns
@onready var acorn_count: Label = $Root/Acorns/Box/Count
@onready var pickup_feed: RichTextLabel = $Root/PickupFeed
@onready var start_card: Control = $Root/StartCard
@onready var inventory_screen: Control = $Root/InventoryScreen
@onready var inventory_box: VBoxContainer = $Root/InventoryScreen/Center/Panel/Box
@onready var tooltip: PanelContainer = $Root/InventoryScreen/Tooltip
@onready var cursor_layer: Control = $Root/InventoryScreen/CursorLayer
@onready var chest_grid: SlotView = $Root/InventoryScreen/Center/Panel/Box/ChestGrid
@onready var day_night: DayNight = %DayNight


func _ready() -> void:
	pickup_feed.text = ""
	for path in ["ChestGrid", "Equipment/OffHand", "MainGrid", "HotbarGrid"]:
		var grid: SlotView = inventory_box.get_node(path)
		grid.clicked.connect(_on_slot_clicked)
		grid.hovered.connect(_show_tooltip)
		_views.append(grid)
	_show_controls()
	App.keys_changed.connect(_show_controls)
	App.device_changed.connect(_show_controls)


func _show_controls() -> void:
	var g := App.glyph
	var lines: Array[String] = []
	if App.using_pad:
		lines.append("%s walk   %s look   %s jump   %s dash" % [g.call(&"forward"), g.call(&"look_left"), g.call(&"jump"), g.call(&"dash")])
		lines.append("%s use item   %s %s hotbar   %s inventory" % [g.call(&"use"), g.call(&"hotbar_prev"), g.call(&"hotbar_next"), g.call(&"inventory")])
		lines.append("inventory:  %s grab   %s split   %s quick move" % [App.glyph_image("pad_0"), g.call(&"pick_up"), g.call(&"use")])
	else:
		lines.append("%s%s%s%s walk   %s%s%s%s look   %s dash   %s jump" % [g.call(&"forward"), g.call(&"left"), g.call(&"back"), g.call(&"right"),
			g.call(&"look_up"), g.call(&"look_left"), g.call(&"look_down"), g.call(&"look_right"), g.call(&"dash"), g.call(&"jump")])
		lines.append("%s / %s use item   %s-%s %s hotbar   %s inventory" % [g.call(&"use"), App.glyph_image("key_%d" % App._keys(&"use")[0]) if not App._keys(&"use").is_empty() else "",
			App.glyph_image("key_49"), App.glyph_image("key_57"), App.glyph_image("mouse_wheel"), g.call(&"inventory")])
	lines.append("%s drop   %s pick up   %s fresh leaves   %s pause" % [g.call(&"drop"), g.call(&"pick_up"), g.call(&"fresh_leaves"), g.call(&"pause")])
	$Root/Controls.text = "\n".join(lines)


func _process(delta: float) -> void:
	if not _feed.is_empty():
		for entry in _feed:
			entry["age"] += delta
		_feed = _feed.filter(func(entry: Dictionary) -> bool: return entry["age"] < 2.4)
		_render_feed()
	stats_text.text = "%d fps    %s" % [roundi(Engine.get_frames_per_second()), day_night.clock_text()]
	start_card.visible = not won and not get_tree().paused and not inventory_screen.visible and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if inventory_screen.visible:
		tooltip.position = (inventory_screen.get_local_mouse_position() + Vector2(18.0, 18.0)).clamp(Vector2.ZERO, inventory_screen.size - tooltip.size)
		tooltip.visible = tooltip.visible and _cursor.is_empty()
		cursor_layer.queue_redraw()


func bind_inventory(pockets: Inventory) -> void:
	_pockets = pockets
	for grid: SlotView in _views + [hotbar]:
		if grid != chest_grid:
			grid.bind(pockets)
	pockets.changed.connect(_refresh_hotbar)
	pockets.selection_changed.connect(_refresh_hotbar)
	pockets.changed.connect(_update_acorns)
	pockets.changed.connect(_redraw_inventory)
	_refresh_hotbar()
	_update_acorns()


func show_pickup(title: String, count: int) -> void:
	if not _feed.is_empty() and _feed[-1]["title"] == title:
		_feed[-1]["count"] += count
		_feed[-1]["age"] = 0.0
	else:
		_feed.append({"title": title, "count": count, "age": 0.0})
		if _feed.size() > 5:
			_feed.pop_front()
	_render_feed()


func _render_feed() -> void:
	var lines: Array[String] = []
	for entry in _feed:
		var fade := clampf(1.0 - (entry["age"] - 1.8) / 0.6, 0.0, 1.0)
		var title: String = entry["title"]
		lines.append("[img=center color=#ffffff%02x]%sbullet_leaf.png[/img] [color=#ffc759%02x]+%d  %s%s[/color]" % [roundi(fade * 255), UI, roundi(fade * 255), entry["count"], title, "s" if entry["count"] > 1 and not title.ends_with("s") else ""])
	pickup_feed.text = "\n".join(lines)


func set_effects(list: Array) -> void:
	effects_text.visible = not list.is_empty()
	var lines: Array[String] = []
	for effect: Array in list:
		var vine := "[img=center]%stimer_vine.png[/img]" % UI
		lines.append("[img=center]%seffect_%s.png[/img] %s  %ds\n%s[img=center]%stimer_tip.png[/img]" % [UI, effect[0], effect[1], ceili(effect[2]), vine.repeat(ceili(effect[2] / effect[3] * 10.0)), UI])
	effects_text.text = "\n".join(lines)


func set_items(names: Array[String]) -> void:
	_names = names
	_found = 0
	_found_flags.assign(names.map(func(_n: String) -> bool: return false))
	_render_rows()
	won = false


func mark_found(index: int, announce := true) -> void:
	_found += 1
	_found_flags[index] = true
	_render_rows()
	if announce:
		toast("You found: %s!" % _names[index])


func _render_rows() -> void:
	var lines: Array[String] = []
	for i in _names.size():
		lines.append("[img=center]%srow_found.png[/img] [color=#ffc759]%s[/color]" % [UI, _names[i]] if _found_flags[i] else "[img=center]%srow_missing.png[/img] %s" % [UI, _names[i]])
	rows_text.text = "\n".join(lines)
	list_title.text = "Lost things  %d / %d" % [_found, _names.size()]


func toast(text: String) -> void:
	toast_label.text = text
	_toast_tween = _flash_label(toast_label, _toast_tween, 2.2, 0.8)


func show_item_name(text: String) -> void:
	item_name.text = text
	_name_tween = _flash_label(item_name, _name_tween, 1.5, 0.6)


func set_charge(value: float) -> void:
	charge.visible = value >= 0.0
	charge.value = maxf(value, 0.0)


func show_compass(angle: float, distance: float, label: String) -> void:
	$Root/Compass/Arrow.rotation = angle
	$Root/Compass/Distance.text = "%s  %d m" % [label, roundi(distance)]


func is_inventory_open() -> bool:
	return inventory_screen.visible


func open_inventory(chest: Inventory) -> void:
	_chest = chest
	inventory_box.get_node("ChestLabel").visible = chest != null
	inventory_box.get_node("ChestGrid").visible = chest != null
	chest_grid.bind(chest)
	if chest and not chest.changed.is_connected(_redraw_inventory):
		chest.changed.connect(_redraw_inventory)
	App.appear(inventory_screen)
	_redraw_inventory()


func close_inventory() -> void:
	if not _cursor.is_empty():
		var left := _pockets.add_to_pockets(_cursor["id"], _cursor["count"])
		if left > 0:
			drop_requested.emit({"id": _cursor["id"], "count": left})
		_cursor = {}
	if _chest and _chest.changed.is_connected(_redraw_inventory):
		_chest.changed.disconnect(_redraw_inventory)
	_chest = null
	inventory_screen.visible = false
	tooltip.visible = false


func _flash_label(label: Label, old: Tween, hold: float, fade: float) -> Tween:
	if old:
		old.kill()
	label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(hold)
	tween.tween_property(label, "modulate:a", 0.0, fade)
	return tween


func _refresh_hotbar() -> void:
	hotbar.queue_redraw()


func _update_acorns() -> void:
	var count := _pockets.count_of(&"acorn")
	if count == _acorns:
		return
	var gained := _acorns >= 0 and count > _acorns
	_acorns = count
	acorn_count.text = "x %d" % count
	acorn_count.add_theme_color_override("font_color", GOLD if count > 0 else MUTED)
	acorn_panel.modulate.a = 1.0 if count > 0 else 0.55
	if gained:
		acorn_panel.pivot_offset = acorn_panel.size * 0.5
		var pulse := create_tween()
		pulse.tween_property(acorn_panel, "scale", Vector2.ONE * 1.25, 0.08)
		pulse.tween_property(acorn_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_slot_clicked(inventory: Inventory, index: int, button: MouseButton, shift: bool) -> void:
	if inventory == null:
		return
	var stack := inventory.get_stack(index)
	if shift and button == MOUSE_BUTTON_LEFT:
		_quick_move(inventory, index)
	elif button == MOUSE_BUTTON_LEFT:
		if _cursor.is_empty():
			_cursor = inventory.take(index, inventory.count_at(index))
		elif stack.is_empty():
			inventory.set_stack(index, _cursor)
			_cursor = {}
		elif stack["id"] == _cursor["id"]:
			var put := mini(maxi(inventory.max_stack(stack["id"]) - stack["count"], 0), _cursor["count"])
			inventory.set_stack(index, {"id": stack["id"], "count": stack["count"] + put})
			_cursor["count"] -= put
			if _cursor["count"] <= 0:
				_cursor = {}
		else:
			var old := stack.duplicate()
			inventory.set_stack(index, _cursor)
			_cursor = old
	elif button == MOUSE_BUTTON_RIGHT:
		if _cursor.is_empty():
			if not stack.is_empty():
				_cursor = inventory.take(index, ceili(stack["count"] / 2.0))
		elif stack.is_empty() or (stack["id"] == _cursor["id"] and stack["count"] < inventory.max_stack(stack["id"])):
			inventory.set_stack(index, {"id": _cursor["id"], "count": stack.get("count", 0) + 1})
			_cursor["count"] -= 1
			if _cursor["count"] <= 0:
				_cursor = {}
	_redraw_inventory()


func _quick_move(inventory: Inventory, index: int) -> void:
	var stack := inventory.get_stack(index)
	if stack.is_empty():
		return
	var left: int
	if inventory == _chest:
		left = _pockets.add_to_pockets(stack["id"], stack["count"])
	elif _chest != null:
		left = _chest.add(stack["id"], stack["count"])
	elif index < Inventory.HOTBAR:
		left = _pockets.add(stack["id"], stack["count"], range(Inventory.HOTBAR, Inventory.MAIN_END))
	elif index < Inventory.MAIN_END:
		left = _pockets.add(stack["id"], stack["count"], range(Inventory.HOTBAR))
	else:
		left = _pockets.add_to_pockets(stack["id"], stack["count"])
	inventory.set_stack(index, {"id": stack["id"], "count": left})


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed() and not _cursor.is_empty():
		drop_requested.emit(_cursor)
		_cursor = {}
		_redraw_inventory()


func _show_tooltip(inventory: Inventory, index: int) -> void:
	if inventory == null or index < 0 or inventory.get_stack(index).is_empty():
		tooltip.hide()
		return
	var item := ItemDb.get_item(inventory.get_stack(index)["id"])
	$Root/InventoryScreen/Tooltip/Box/Name.text = item.display_name
	$Root/InventoryScreen/Tooltip/Box/Description.text = item.description
	tooltip.reset_size()
	tooltip.visible = true


func _draw_cursor() -> void:
	if not _cursor.is_empty():
		SlotView.draw_item(cursor_layer, _cursor, Rect2(cursor_layer.get_local_mouse_position() - Vector2(26.0, 26.0), Vector2(52.0, 52.0)))


func _redraw_inventory() -> void:
	for view in _views:
		view.queue_redraw()
	cursor_layer.queue_redraw()
