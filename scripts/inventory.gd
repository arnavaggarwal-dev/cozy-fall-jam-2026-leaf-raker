class_name Inventory
extends RefCounted

const HOTBAR := 9
const MAIN_END := 36
const OFF_HAND := 36

signal changed
signal selection_changed

var slots: Array[Dictionary] = []
var pockets := false
var selected := 0


func _init(size: int, is_pockets := false) -> void:
	pockets = is_pockets
	for i in size:
		slots.append({})


func get_stack(index: int) -> Dictionary:
	return slots[index]


func id_at(index: int) -> StringName:
	return slots[index].get("id", &"")


func count_at(index: int) -> int:
	return slots[index].get("count", 0)


func set_stack(index: int, stack: Dictionary) -> void:
	slots[index] = {} if stack.is_empty() or stack["count"] <= 0 else {"id": stack["id"], "count": stack["count"]}
	changed.emit()


func max_stack(id: StringName) -> int:
	return ItemDb.get_item(id).max_stack


func add(id: StringName, count: int, order: Array = []) -> int:
	var limit := max_stack(id)
	var indices: Array = order if not order.is_empty() else range(slots.size())
	var left := count
	for i: int in indices:
		var stack := slots[i]
		if left > 0 and not stack.is_empty() and stack["id"] == id and stack["count"] < limit:
			var put := mini(left, limit - stack["count"])
			stack["count"] += put
			left -= put
	for i: int in indices:
		if left > 0 and slots[i].is_empty():
			slots[i] = {"id": id, "count": mini(left, limit)}
			left -= slots[i]["count"]
	if left != count:
		changed.emit()
	return left


func add_to_pockets(id: StringName, count: int) -> int:
	return add(id, count, range(MAIN_END))


func count_of(id: StringName) -> int:
	var total := 0
	for stack in slots:
		if stack.get("id") == id:
			total += stack["count"]
	return total


func remove(id: StringName, count: int) -> int:
	var taken := 0
	for i in range(slots.size() - 1, -1, -1):
		if taken < count and slots[i].get("id") == id:
			var take_now := mini(count - taken, slots[i]["count"])
			slots[i]["count"] -= take_now
			taken += take_now
			if slots[i]["count"] <= 0:
				slots[i] = {}
	if taken > 0:
		changed.emit()
	return taken


func take(index: int, count: int) -> Dictionary:
	var stack := slots[index]
	if stack.is_empty() or count <= 0:
		return {}
	var out := {"id": stack["id"], "count": mini(count, stack["count"])}
	stack["count"] -= out["count"]
	if stack["count"] <= 0:
		slots[index] = {}
	changed.emit()
	return out


func is_empty() -> bool:
	return slots.all(func(stack: Dictionary) -> bool: return stack.is_empty())


func selected_id() -> StringName:
	return id_at(selected)


func select(index: int) -> void:
	index = posmod(index, HOTBAR)
	if index != selected:
		selected = index
		selection_changed.emit()
