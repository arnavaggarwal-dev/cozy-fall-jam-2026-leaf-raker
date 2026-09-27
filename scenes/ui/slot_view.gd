class_name SlotView
extends Container

signal clicked(inventory: Inventory, index: int, button: MouseButton, shift: bool)
signal hovered(inventory: Inventory, index: int)

@export var indices := PackedInt32Array()
@export var show_selection := false

var container: Inventory

var _slots: Array[Control] = []


func _ready() -> void:
	_slots.assign(get_children().filter(func(n: Node) -> bool: return n.has_node("Icon")))
	for k in _slots.size():
		_slots[k].gui_input.connect(_slot_input.bind(k))
		_slots[k].mouse_entered.connect(func() -> void: hovered.emit(container, indices[k]))
		_slots[k].mouse_exited.connect(func() -> void: hovered.emit(container, -1))


func bind(inventory: Inventory) -> void:
	container = inventory
	refresh()


func refresh() -> void:
	for k in _slots.size():
		var index := indices[k]
		var stack := container.get_stack(index) if container else {}
		show_stack(_slots[k], stack)
		_slots[k].get_node("Hint").visible = stack.is_empty() and index == Inventory.OFF_HAND
		_slots[k].get_node("Vine").visible = show_selection and container != null and container.selected == index


static func show_stack(slot: Control, stack: Dictionary) -> void:
	slot.get_node("Icon").texture = null if stack.is_empty() else ItemDb.icon(stack["id"])
	slot.get_node("Count").text = str(stack["count"]) if stack.get("count", 0) > 1 else ""


func _slot_input(event: InputEvent, k: int) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed:
		clicked.emit(container, indices[k], button.button_index, button.shift_pressed)
		_slots[k].accept_event()
