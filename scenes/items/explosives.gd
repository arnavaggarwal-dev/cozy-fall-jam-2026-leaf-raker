class_name Explosives
extends Node3D

const EXPLOSION := preload("res://scenes/fx/explosion.tscn")
const FIRE := preload("res://scenes/fx/fire.tscn")
const SMOKE := preload("res://scenes/fx/smoke.tres")
const THROWN_ACORN := preload("res://scenes/items/thrown_acorn.tscn")

const SIZE := 0.16
const RADIUS := 0.08
const THROW_SPEED := 12.0
const THROW_LIFT := 2.5
const GRAVITY := 9.8
const BOUNCE := 0.3
const FUSE_SECONDS := 0.35
const MAX_FLIGHT_SECONDS := 4.0
const COOLDOWN_SECONDS := 0.5
const CRATER_RADIUS := 7
const RING_WIDTH := 9
const FIRE_RADIUS := 10 
const SPREAD_SECONDS_PER_METER := 0.08
const GROW_SECONDS := 2.5
const CHAR_SECONDS := 9.0
const BURN_SECONDS := 16.0
const SMOKE_SECONDS := 22.0
const MAX_LIGHTS := 4
const MAX_SOUNDS := 4
const LIGHT_ENERGY := 3.0
const WATER_SPEED := 8.0
const WATER_DRAG := 0.6
const WATER_SOAK := 0.05
const WATER_MIN_SPEED := 0.5
const WATER_MIN_VOLUME := 0.08
const WATER_MAX_STREAMS := 24
const WATER_TRAIL := 40
const WATER_COLOR := Color(0.2, 0.5, 1.0, 0.8)

signal exploded(where: Vector3)

var _acorns: Array[Dictionary] = []
var _cooldown := 0.0
var _fires: Array[Dictionary] = []
var _burning := {}
var _time := 0.0
var _smoke_material: StandardMaterial3D = SMOKE.material
var _streams: Array[Dictionary] = []

@export var _water_material: StandardMaterial3D

@onready var _water_mesh: ImmediateMesh = ($Water as MeshInstance3D).mesh
@onready var field: LeafWorld = %LeafWorld
@onready var forest: Forest = %Forest
@onready var player: Player = %Player
@onready var day_night: DayNight = %DayNight


func _ready() -> void:
	get_tree().create_timer(0.5, false).timeout.connect(_prewarm)


func _prewarm() -> void:
	var spot := player.camera.global_position - player.camera.global_basis.z * 4.0 + Vector3.DOWN * 4.0
	var bang: Node3D = EXPLOSION.instantiate()
	bang.get_node("Sound").free()
	var fire: Node3D = FIRE.instantiate()
	fire.get_node("Sound").free()
	for node: Node3D in [bang, fire]:
		add_child(node)
		node.global_position = spot
	for emitter: GPUParticles3D in fire.find_children("*", "GPUParticles3D", false, false):
		emitter.emitting = true
	get_tree().create_timer(1.5).timeout.connect(bang.queue_free)
	get_tree().create_timer(1.5).timeout.connect(fire.queue_free)


func throw(origin: Vector3, direction: Vector3, carried: Vector3, power := 1.0) -> bool:
	if _cooldown > 0.0:
		return false
	_cooldown = COOLDOWN_SECONDS
	var pivot: Node3D = THROWN_ACORN.instantiate()
	add_child(pivot)
	pivot.position = origin
	_acorns.append({"node": pivot, "velocity": direction.normalized() * THROW_SPEED * power + Vector3.UP * THROW_LIFT + carried, "fuse": INF, "flight": 0.0})
	return true


func pour(from: Vector2, direction: Vector2) -> void:
	_streams.append({"pos": from, "vel": direction.normalized() * WATER_SPEED, "volume": 1.0, "trail": []})


func douse(p: Vector2, radius: float) -> int:
	var doused := 0
	for fire in _fires:
		var root: Node3D = fire["root"]
		if fire["doused"] or fire["age"] >= BURN_SECONDS or Forest.flat(root.global_position).distance_to(p) > radius:
			continue
		fire["doused"] = true
		fire["age"] = BURN_SECONDS
		_burning.erase(fire["index"])
		doused += 1
	return doused


func is_burning(index: int) -> bool:
	return _fires.any(func(fire: Dictionary) -> bool: return fire["index"] == index and fire["age"] < BURN_SECONDS)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_time += delta
	_update_acorns(delta)
	_update_fires(delta)
	_update_water(delta)


func _update_acorns(delta: float) -> void:
	for k in range(_acorns.size() - 1, -1, -1):
		var acorn := _acorns[k]
		var node: Node3D = acorn["node"]
		var velocity: Vector3 = acorn["velocity"]
		velocity.y -= GRAVITY * delta
		var p := node.position + velocity * delta
		var hit := false

		var flat := Forest.flat(p)
		var pushed := forest.push_out(flat, RADIUS, p.y)
		if pushed != flat:
			hit = true
			var normal := (pushed - flat).normalized()
			var across := Forest.flat(velocity)
			if across.dot(normal) < 0.0:
				across = (across - 2.0 * across.dot(normal) * normal) * 0.5
			velocity = Vector3(across.x, velocity.y, across.y)
			p = Vector3(pushed.x, p.y, pushed.y)

		var rest := field.sample_depth(Forest.flat(p)) + SIZE * 0.25
		if p.y <= rest:
			hit = true
			p.y = rest
			velocity.y = -velocity.y * BOUNCE if velocity.y < -2.0 else 0.0
			velocity.x *= exp(-delta * 6.0)
			velocity.z *= exp(-delta * 6.0)
		var rolling := Forest.flat(velocity)
		if rolling.length() > 0.1:
			node.basis = node.basis.rotated(Vector3(rolling.y, 0.0, -rolling.x).normalized(), rolling.length() / (SIZE * 0.5) * delta)
		node.position = p
		acorn["velocity"] = velocity

		if hit and acorn["fuse"] == INF:
			acorn["fuse"] = FUSE_SECONDS
		acorn["fuse"] -= delta
		acorn["flight"] += delta
		if acorn["fuse"] <= 0.0 or acorn["flight"] >= MAX_FLIGHT_SECONDS:
			_acorns.remove_at(k)
			node.queue_free()
			_explode(p)


func _explode(where: Vector3) -> void:
	var flat := Forest.flat(where)
	field.blast(flat, CRATER_RADIUS, RING_WIDTH, true)
	for tree in forest.trees_near(flat, FIRE_RADIUS):
		var index: int = tree["index"]
		if not _burning.has(index) and not forest.is_charred(index):
			_burning[index] = true
			App.bump(&"trees_burned")
			_fires.append(_make_fire(index, tree["height"], -flat.distance_to(tree["position"]) * SPREAD_SECONDS_PER_METER))
	var effect: Node3D = EXPLOSION.instantiate()
	add_child(effect)
	effect.position = Vector3(where.x, field.sample_depth(flat), where.z)
	effect.create_tween().tween_property(effect.get_node("Flash"), "light_energy", 0.0, 0.8)
	get_tree().create_timer(6.0).timeout.connect(effect.queue_free)
	exploded.emit(where)


func _update_water(delta: float) -> void:
	for k in range(_streams.size() - 1, -1, -1):
		var stream := _streams[k]
		var trail: Array = stream["trail"]
		var pos: Vector2 = stream["pos"]
		var vel: Vector2 = stream["vel"]
		var volume: float = stream["volume"]
		if volume < WATER_MIN_VOLUME or vel.length() < WATER_MIN_SPEED:
			trail.pop_front()
			if trail.size() < 2:
				_streams.remove_at(k)
			continue

		var slope := Vector2(field.sample_depth(pos + Vector2(0.1, 0.0)) - field.sample_depth(pos - Vector2(0.1, 0.0)),
			field.sample_depth(pos + Vector2(0.0, 0.1)) - field.sample_depth(pos - Vector2(0.0, 0.1))) / 0.2
		vel = (vel - slope * GRAVITY * delta) * exp(-WATER_DRAG * delta)
		var travel := vel * delta
		var steps := maxi(ceili(travel.length() / 0.1), 1)
		for step in steps:
			var next := pos + travel / steps
			var pushed := forest.push_out(next, 0.1)
			if pushed != next:
				var normal := (pushed - next).normalized()
				var side := Vector2(-normal.y, normal.x)
				if absf(vel.normalized().dot(side)) < 0.5 and volume > WATER_MIN_VOLUME * 2.0 and _streams.size() < WATER_MAX_STREAMS:
					volume *= 0.5
					var speed := vel.length() * 0.8
					vel = (side + normal * 0.3).normalized() * speed
					var depth := field.sample_depth(pushed)
					_streams.append({"pos": pushed - side * 0.1, "vel": (-side + normal * 0.3).normalized() * speed, "volume": volume, "trail": [Vector3(pushed.x, depth + 0.03, pushed.y)]})
				else:
					vel = (vel - normal * vel.dot(normal)) * 0.9
				field.soak(pos, pushed, lerpf(0.2, 0.5, volume))
				pos = pushed
				break
			field.soak(pos, next, lerpf(0.2, 0.5, volume))
			volume -= pos.distance_to(next) * WATER_SOAK
			pos = next
		douse(pos, 1.5)
		trail.append(Vector3(pos.x, field.sample_depth(pos) + 0.03, pos.y))
		if trail.size() > WATER_TRAIL:
			trail.pop_front()
		stream["pos"] = pos
		stream["vel"] = vel
		stream["volume"] = volume

	_water_mesh.clear_surfaces()
	for stream in _streams:
		var trail: Array = stream["trail"]
		if trail.size() < 2:
			continue
		var half := lerpf(0.1, 0.25, stream["volume"])
		_water_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _water_material)
		for i in trail.size():
			var a: Vector3 = trail[maxi(i - 1, 0)]
			var b: Vector3 = trail[mini(i + 1, trail.size() - 1)]
			var side := Vector3(b.z - a.z, 0.0, a.x - b.x).normalized() * half
			_water_mesh.surface_set_color(Color(WATER_COLOR, WATER_COLOR.a * (i + 1) / trail.size()))
			_water_mesh.surface_add_vertex(trail[i] + side)
			_water_mesh.surface_add_vertex(trail[i] - side)
		_water_mesh.surface_end()


func _update_fires(delta: float) -> void:
	_smoke_material.albedo_color = Color(0.3, 0.2, 0.15).lerp(Color.WHITE, day_night.daylight)
	var lit: Array[Dictionary] = []
	for k in range(_fires.size() - 1, -1, -1):
		var fire := _fires[k]
		fire["age"] += delta
		var age: float = fire["age"]
		if age >= SMOKE_SECONDS:
			fire["root"].queue_free()
			_fires.remove_at(k)
			continue
		if age < 0.0:
			continue
		var flames: GPUParticles3D = fire["flames"]
		if not fire["charred"] and not fire["doused"] and age >= CHAR_SECONDS:
			fire["charred"] = true
			forest.char_tree(fire["index"])
			(flames.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.3, fire["height"] * 0.22, 0.3)
			flames.position.y = fire["height"] * 0.25
			fire["light"].position.y = fire["height"] * 0.3
		fire["strength"] = _strength(age)
		flames.emitting = age < BURN_SECONDS
		flames.amount_ratio = clampf(fire["strength"], 0.1, 1.0)
		fire["smoke"].emitting = age > 0.8 and age < BURN_SECONDS + 2.0
		fire["distance"] = (fire["root"] as Node3D).global_position.distance_to(player.camera.global_position)
		lit.append(fire)

	lit.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	for i in lit.size():
		var strength: float = lit[i]["strength"]
		var index: int = lit[i]["index"]
		var light: OmniLight3D = lit[i]["light"]
		light.visible = i < MAX_LIGHTS and strength > 0.02
		light.light_energy = LIGHT_ENERGY * strength * (0.8 + 0.12 * sin(_time * 17.0 + index) + 0.08 * sin(_time * 7.3 + index * 0.7))
		var sound: AudioStreamPlayer3D = lit[i]["sound"]
		var audible := i < MAX_SOUNDS and strength > 0.05
		if audible and not sound.playing:
			sound.play(randf() * 3.0)
		elif not audible and sound.playing:
			sound.stop()
		sound.volume_db = linear_to_db(maxf(strength, 0.05))


func _strength(age: float) -> float:
	if age < GROW_SECONDS:
		return age / GROW_SECONDS
	if age < CHAR_SECONDS:
		return 1.0
	return clampf(lerpf(0.6, 0.0, (age - CHAR_SECONDS) / (BURN_SECONDS - CHAR_SECONDS)), 0.0, 1.0)


func _make_fire(index: int, height: float, age: float) -> Dictionary:
	var root: Node3D = FIRE.instantiate()
	root.position = forest.tree_local_position(index)
	forest.tree_anchor(index).add_child(root)
	var canopy := height * 0.22
	var flames: GPUParticles3D = root.get_node("Flames")
	(flames.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(canopy, height * 0.2, canopy)
	flames.position.y = height * 0.62
	flames.visibility_aabb = AABB(Vector3(-canopy - 3.0, -height, -canopy - 3.0), Vector3(canopy * 2.0 + 6.0, height + 8.0, canopy * 2.0 + 6.0))
	var smoke: GPUParticles3D = root.get_node("Smoke")
	(smoke.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(canopy * 0.7, 0.8, canopy * 0.7)
	smoke.position.y = height * 0.9
	var light: OmniLight3D = root.get_node("Light")
	light.position.y = height * 0.45
	return {"index": index, "height": height, "age": age, "strength": 0.0, "distance": 0.0, "charred": false, "doused": false,
		"root": root, "flames": flames, "smoke": smoke, "light": light, "sound": root.get_node("Sound")}
