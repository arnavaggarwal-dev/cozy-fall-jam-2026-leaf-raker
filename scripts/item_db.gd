class_name ItemDb
extends RefCounted

const ITEM_DIR := "res://items"
const ICON_DIR := "res://assets/textures/icons"
const GRASS_COLOR := Color(0.42, 0.66, 0.26)

static var _items := _load_items()
static var _icons := {}


static func _load_items() -> Dictionary:
	var items := {}
	for file in ResourceLoader.list_directory(ITEM_DIR):
		if file.get_extension() == "tres":
			var item: ItemData = load(ITEM_DIR.path_join(file))
			items[item.id] = item
	return items


static func get_item(id: StringName) -> ItemData:
	return _items.get(id)


static func lost_things() -> Array[ItemData]:
	var out: Array[ItemData] = []
	out.assign(_items.values().filter(func(item: ItemData) -> bool: return item.lost_index >= 0))
	out.sort_custom(func(a: ItemData, b: ItemData) -> bool: return a.lost_index < b.lost_index)
	return out


static func display_name(id: StringName) -> String:
	var item := get_item(id)
	return item.display_name if item else String(id)


static func icon(id: StringName) -> Texture2D:
	if not _icons.has(id):
		var path := ICON_DIR.path_join(String(id) + ".png")
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[id]


static func spawn_model(id: StringName, size := 0.0) -> Node3D:
	var item := get_item(id)
	return spawn_normalized(item.model, size if size > 0.0 else item.world_size)


static func load_model(path: String) -> Node3D:
	var model: Node3D = (load(path) as PackedScene).instantiate()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if material and material.resource_name == "grass":
				material.albedo_color = GRASS_COLOR
	return model


static func compute_aabb(root: Node3D) -> AABB:
	var parts := collect_mesh_parts(root)
	var box: AABB = (parts[0][1] as Transform3D) * (parts[0][0] as Mesh).get_aabb()
	for part in parts:
		box = box.merge((part[1] as Transform3D) * (part[0] as Mesh).get_aabb())
	return box


static func spawn_normalized(path: String, size: float, by_height := false) -> Node3D:
	var model := load_model(path)
	var box := compute_aabb(model)
	var dim := box.size.y if by_height else maxf(box.size.x, maxf(box.size.y, box.size.z))
	var s := size / maxf(dim, 0.0001)
	model.scale = Vector3.ONE * s
	model.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * s
	var holder := Node3D.new()
	holder.add_child(model)
	holder.set_meta("size", box.size * s)
	return holder


static func collect_mesh_parts(root: Node3D) -> Array[Array]:
	var parts: Array[Array] = []
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node = entry[0]
		var xform: Transform3D = entry[1]
		if node is Node3D:
			xform *= (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			parts.append([(node as MeshInstance3D).mesh, xform])
		for child in node.get_children():
			stack.append([child, xform])
	return parts
