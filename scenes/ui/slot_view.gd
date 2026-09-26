class_name SlotView
extends Control

const SIZE := 64.0
const SLOT := preload("res://assets/textures/ui/slot.png")
const SLOT_HOVER := preload("res://assets/textures/ui/slot_hover.png")
const VINE := preload("res://assets/textures/ui/slot_vine.png")

signal clicked(inventory: Inventory, index: int, button: MouseButton, shift: bool)
signal hovered(inventory: Inventory, index: int)

@export var indices := PackedInt32Array()
@export var columns := 9
@export var gap := 4.0
@export var lead_gap := 0.0
@export var show_selection := false

var container: Inventory

var _hover := -1


func _ready() -> void:
	var rows := ceili(indices.size() / float(columns))
	var cols := mini(columns, indices.size())
	custom_minimum_size = Vector2(cols * SIZE + (cols - 1) * gap + lead_gap, rows * SIZE + (rows - 1) * gap)


func bind(inventory: Inventory) -> void:
	container = inventory
	queue_redraw()


func slot_rect(k: int) -> Rect2:
	var col := k % columns
	return Rect2(Vector2(col * (SIZE + gap) + (lead_gap if col > 0 else 0.0), (k / columns) * (SIZE + gap)), Vector2(SIZE, SIZE))


func _slot_at(p: Vector2) -> int:
	for k in indices.size():
		if slot_rect(k).has_point(p):
			return k
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hover(_slot_at(event.position))
	var button := event as InputEventMouseButton
	if button and button.pressed:
		var k := _slot_at(button.position)
		if k >= 0:
			clicked.emit(container, indices[k], button.button_index, button.shift_pressed)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hover(-1)


func _set_hover(k: int) -> void:
	if k == _hover:
		return
	_hover = k
	queue_redraw()
	hovered.emit(container, indices[k] if k >= 0 else -1)


func _draw() -> void:
	for k in indices.size():
		var rect := slot_rect(k)
		var index := indices[k]
		draw_texture_rect(SLOT_HOVER if k == _hover else SLOT, rect, false)
		var stack := container.get_stack(index) if container else {}
		if not stack.is_empty():
			draw_item(self, stack, rect.grow(-6.0))
		elif index == Inventory.OFF_HAND:
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(0.0, SIZE * 0.5 + 5.0), "Off hand", HORIZONTAL_ALIGNMENT_CENTER, SIZE, 12, Color(1.0, 1.0, 1.0, 0.4))
	if show_selection and container and container.selected in indices:
		draw_texture_rect(VINE, slot_rect(indices.find(container.selected)).grow(8.0), false)


static func draw_item(canvas: CanvasItem, item_stack: Dictionary, rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var icon := ItemDb.icon(item_stack["id"])
	if icon:
		canvas.draw_texture_rect(icon, rect, false)
	else:
		canvas.draw_string(font, rect.position + Vector2(0.0, rect.size.y * 0.55), ItemDb.display_name(item_stack["id"]).left(4), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14)
	if item_stack["count"] > 1:
		var at := rect.position + Vector2(0.0, rect.size.y + 3.0)
		canvas.draw_string_outline(font, at, str(item_stack["count"]), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x + 3.0, 18, 5, Color(0.05, 0.03, 0.02))
		canvas.draw_string(font, at, str(item_stack["count"]), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x + 3.0, 18, Color.WHITE)
