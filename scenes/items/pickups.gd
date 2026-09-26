class_name Pickups
extends Node3D

const MAGNET_RADIUS := 1.6
const COLLECT_DISTANCE := 0.4
const GRAVITY := 9.8
const MAX_PICKUPS := 150
const LIFETIME := 600.0
const PICKUP := preload("res://scenes/items/pickup.tscn")

signal collected(id: StringName, count: int)

@export var glow: QuadMesh

var _pickups: Array[Dictionary] = []
var _time := 0.0

@onready var glow_material: StandardMaterial3D = glow.material
@onready var field: LeafWorld = %LeafWorld
@onready var player: Player = %Player
@onready var inventory: Inventory = (%ItemUser as ItemUser).inventory


func spawn(id: StringName, count: int, where: Vector3, velocity := Vector3.ZERO, delay := 0.3) -> Dictionary:
	var node: Node3D = PICKUP.instantiate()
	var model := ItemDb.spawn_model(id)
	node.add_child(model)
	add_child(node)
	node.position = where
	node.rotation.y = randf() * TAU
	var entry := {"id": id, "count": count, "node": node, "model": model, "velocity": velocity, "delay": delay, "age": 0.0}
	_pickups.append(entry)
	if _pickups.size() > MAX_PICKUPS:
		_remove(0)
	return entry


func take_one(entry: Dictionary) -> bool:
	var k := _pickups.find(entry)
	if k < 0:
		return false
	entry["count"] -= 1
	if entry["count"] <= 0:
		_remove(k)
	return true


func _process(delta: float) -> void:
	_time += delta
	glow_material.albedo_color.a = 0.55 + 0.3 * sin(_time * 3.0)
	var here := Forest.flat(player.global_position)
	var chest := player.global_position + Vector3.UP * 0.7
	for k in range(_pickups.size() - 1, -1, -1):
		var entry := _pickups[k]
		var node: Node3D = entry["node"]
		entry["age"] += delta
		entry["delay"] -= delta
		if entry["age"] > LIFETIME:
			_remove(k)
			continue
		var flat := Forest.nearest_copy(Forest.flat(node.position), here)
		var p := Vector3(flat.x, node.position.y, flat.y)

		var distance := flat.distance_to(here)
		if entry["delay"] <= 0.0 and distance < MAGNET_RADIUS and absf(p.y - chest.y) < 2.0:
			p = p.move_toward(chest, delta * (3.0 + 10.0 * (1.0 - distance / MAGNET_RADIUS)))
			node.position = p
			if p.distance_to(chest) < COLLECT_DISTANCE:
				var left := inventory.add_to_pockets(entry["id"], entry["count"])
				if left < entry["count"]:
					collected.emit(entry["id"], entry["count"] - left)
				if left == 0:
					_remove(k)
				else:
					entry["count"] = left
					entry["delay"] = 2.0
			continue

		var velocity: Vector3 = entry["velocity"]
		var rest := field.sample_depth(flat) + 0.03
		if p.y > rest + 0.001 or velocity != Vector3.ZERO:
			velocity.y -= GRAVITY * delta
			p += velocity * delta
			if p.y <= rest:
				p.y = rest
				velocity = Vector3(velocity.x * 0.3, -velocity.y * 0.25, velocity.z * 0.3) if velocity.y < -2.5 else Vector3.ZERO
		else:
			p.y = rest
		entry["velocity"] = velocity
		node.position = p
		node.rotation.y += delta * 1.2
		(entry["model"] as Node3D).position.y = 0.05 + sin(entry["age"] * 2.5) * 0.03


func _remove(index: int) -> void:
	(_pickups[index]["node"] as Node3D).queue_free()
	_pickups.remove_at(index)
