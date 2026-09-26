class_name WinScreen
extends CanvasLayer

const SQUIRREL := preload("res://scenes/ui/squirrel_2d.tscn")
const PRIMO_DROP := 3.0
const STAR_GAP := 130.0
const FOCUS := Vector3(0.0, 0.9, 0.0)
const FOV := 38.0
const BEAT := 2.0

var _squirrels: Array[Dictionary] = []
var _t := 0.0
var _shake := 0.0
var _spawn := 0.0
var _count := -1
var _shine: Tween
var _launches: Array = []

@export var fanfare_sound: AudioStream
@export var chime_sound: AudioStream
@export var tick_sound: AudioStream
@export var stamp_sound: AudioStream
var _firework := 1.0
var _next_firework := 0

@onready var root: Control = $Root
@onready var rays: ColorRect = $Root/Rays
@onready var stampede: Node2D = $Root/Stampede
@onready var title: RichTextLabel = $Root/Title
@onready var counter: Label = $Root/Panel/Counter
@onready var buttons: HBoxContainer = $Root/Panel/Buttons
@onready var flash: ColorRect = $Root/Flash
@onready var primo: Node3D = $Root/Stage/Viewport/Primo
@onready var camera: Camera3D = $Root/Stage/Viewport/Camera
@onready var stars: Control = $Root/Panel/Stars
@onready var orbits: Array = [$Root/OrbitBack, $Root/OrbitFront]
@onready var best_time: Label = $Root/Panel/BestTime
@onready var sfx: AudioStreamPlaybackPolyphonic = ($Sfx as AudioStreamPlayer).get_stream_playback()
@onready var stage: Control = $Root/Stage
@onready var spot: SpotLight3D = $Root/Stage/Viewport/Spot
@onready var ring: StandardMaterial3D = ($Root/Stage/Viewport/Ring as MeshInstance3D).mesh.material


func _ready() -> void:
	$Root/Panel/Buttons/MainMenu.pressed.connect(App.go.bind(App.MENU))
	$Root/Flourish.watch(buttons.get_children())
	for emitter in find_children("*", "CPUParticles2D", true, false) + [$Root/Stage/Viewport/Burst]:
		emitter.emitting = false


func celebrate(found: int, time := 0.0, new_best := false) -> void:
	if visible:
		return
	visible = true
	_t = 0.0
	_shake = 1.0
	_count = -1
	_firework = 1.0
	$Root/Twinkle.emitting = true
	for node: Squirrel2D in stampede.get_children():
		_add_squirrel(node)
	_launches.resize(found)
	_launches.fill(INF)
	for orbit in orbits:
		orbit.launches = _launches
	best_time.text = ("new best time  %s" % App.format_time(time)) if new_best else ("time  %s     best  %s" % [App.format_time(time), App.format_time(App.best_time)])
	best_time.pivot_offset = best_time.size * 0.5
	(best_time.material as ShaderMaterial).set_shader_parameter("width", best_time.size.x)
	(best_time.material as ShaderMaterial).set_shader_parameter("progress", -0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for cannon: CPUParticles2D in [$Root/CannonLeft, $Root/CannonRight, $Root/Rain]:
		cannon.restart()
	Engine.time_scale = 0.08
	var fx := create_tween().set_ignore_time_scale(true)
	fx.tween_interval(0.5)
	fx.tween_property(Engine, "time_scale", 1.0, 1.2).set_trans(Tween.TRANS_SINE)
	flash.color.a = 1.0
	_tween().tween_property(flash, "color:a", 0.0, 0.45)
	rays.modulate.a = 0.0
	_tween().tween_property(rays, "modulate:a", 1.0, 0.35)
	_tween().tween_property(rays.material, "shader_parameter/grow", 1.0, 1.4).from(0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	sfx.play_stream(fanfare_sound, 0.0, -3.0)

	primo.position.y = PRIMO_DROP
	(primo.get_node("AnimationPlayer") as AnimationPlayer).play(&"mixamo_com")
	var drop := _tween()
	drop.tween_interval(0.25)
	drop.tween_property(primo, "position:y", 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drop.tween_callback(func() -> void:
		$Root/Stage/Viewport/Burst.restart()
		sfx.play_stream(stamp_sound, 0.0, 0.0, 0.6)
		camera.fov = FOV - 8.0
		_shake = maxf(_shake, 0.9))

	title.pivot_offset = title.size * 0.5
	title.scale = Vector2.ZERO
	(title.material as ShaderMaterial).set_shader_parameter("width", title.size.x)
	(title.material as ShaderMaterial).set_shader_parameter("progress", -0.2)
	var slam := _tween()
	slam.tween_interval(0.35)
	slam.tween_property(title, "scale", Vector2.ONE, 0.22).from(Vector2.ONE * 3.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	slam.tween_callback(func() -> void: _shake = 1.3)
	_shine = _tween().set_loops()
	_shine.tween_interval(1.2)
	_shine.tween_property(title.material, "shader_parameter/progress", 1.2, 0.8).from(-0.2)
	_shine.parallel().tween_property(best_time.material, "shader_parameter/progress", 1.2, 0.8).from(-0.2)

	counter.pivot_offset = counter.size * 0.5
	counter.text = "0 / %d" % found
	_tween().tween_method(_tick.bind(found), 0.0, float(found), 1.0).set_delay(1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	for i in 3:
		var star: Node2D = stars.get_child(i)
		star.scale = Vector2.ZERO
		var pop := _tween()
		pop.tween_interval(2.3 + i * 0.25)
		pop.tween_callback(func() -> void:
			(star.get_node("Sparkle") as CPUParticles2D).restart()
			sfx.play_stream(chime_sound, 0.0, -3.0, 1.38 + i * 0.19)
			_shake = maxf(_shake, 0.5))
		pop.tween_property(star, "scale", Vector2.ONE * (1.25 if i == 1 else 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	buttons.pivot_offset = buttons.size * 0.5
	buttons.modulate.a = 0.0
	buttons.scale = Vector2.ONE * 0.6
	var reveal := _tween()
	reveal.tween_interval(3.2)
	reveal.tween_property(buttons, "modulate:a", 1.0, 0.2)
	reveal.parallel().tween_property(buttons, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_callback($Root/Panel/Buttons/KeepRaking.grab_focus)


func _process(delta: float) -> void:
	if not visible:
		return
	var real := delta / maxf(Engine.time_scale, 0.01)
	_t += real
	_shake = maxf(_shake - real * 1.6, 0.0)
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 26.0 * _shake * _shake
	rays.material.set("shader_parameter/aspect", rays.size.x / maxf(rays.size.y, 1.0))
	camera.position = Vector3(sin(_t * 0.3) * 1.2, 1.25 + sin(_t * 0.5) * 0.1, 4.2)
	camera.look_at(FOCUS)
	counter.scale = counter.scale.lerp(Vector2.ONE, 1.0 - exp(-real * 12.0))
	camera.fov = lerpf(camera.fov, FOV, 1.0 - exp(-real * 5.0))
	var beat := pow(absf(sin(_t * PI * BEAT)), 6.0)
	ring.emission_energy_multiplier = 2.0 + 3.0 * beat
	spot.light_color = Color.from_hsv(fmod(_t * 0.15, 1.0), 0.35, 1.0)
	if _t > 0.7:
		title.scale = Vector2.ONE * (1.0 + 0.03 * beat)
	_update_orbit()
	best_time.rotation = sin(_t * 1.7) * 0.04
	_firework -= real
	if _firework <= 0.0:
		_firework = randf_range(0.3, 0.8) if _t < 6.0 else randf_range(0.9, 1.8)
		var burst := get_node("Root/Firework%d" % (_next_firework + 1)) as CPUParticles2D
		_next_firework = (_next_firework + 1) % 3
		burst.position = Vector2(randf_range(0.08, 0.92), randf_range(0.08, 0.42)) * root.size
		burst.color = Color.from_hsv(randf(), 0.55, 1.0)
		burst.restart()
		sfx.play_stream(stamp_sound, 0.0, -9.0, randf_range(1.5, 2.2))
	for i in 3:
		var star := stars.get_child(i) as Node2D
		star.position = Vector2(stars.size.x * 0.5 + (i - 1) * STAR_GAP, stars.size.y * 0.5 - (12.0 if i == 1 else 0.0))
		star.rotation = sin(_t * 2.0 + i) * 0.1
	if buttons.modulate.a >= 1.0:
		($Root/Panel/Buttons/KeepRaking as Control).pivot_offset = ($Root/Panel/Buttons/KeepRaking as Control).size * 0.5
		($Root/Panel/Buttons/KeepRaking as Control).scale = Vector2.ONE * (1.0 + 0.04 * sin(_t * 4.0))

	_spawn -= real
	if _spawn <= 0.0:
		_spawn = randf_range(0.05, 0.2) if _t < 4.0 else randf_range(0.35, 1.1)
		_add_squirrel()
	for k in range(_squirrels.size() - 1, -1, -1):
		var s: Dictionary = _squirrels[k]
		var node: Squirrel2D = s["node"]
		s["x"] += s["v"] * real
		node.position = Vector2(s["x"], s["y"] - absf(sin(_t * s["hop"] + s["phase"])) * s["jump"])
		if node.position.x < -200.0 or node.position.x > root.size.x + 200.0:
			node.queue_free()
			_squirrels.remove_at(k)


func _tick(value: float, found: int) -> void:
	var n := roundi(value)
	if n == _count:
		return
	_count = n
	counter.text = "%d / %d" % [n, found]
	counter.scale = Vector2.ONE * 1.3
	if n >= 1 and n <= _launches.size():
		_launches[n - 1] = _t
	sfx.play_stream(tick_sound, 0.0, -6.0, 0.8 + 0.8 * n / maxf(found, 1.0))
	if n == found:
		counter.scale = Vector2.ONE * 1.7
		sfx.play_stream(stamp_sound, 0.0, 0.0, 0.6)
		_shake = maxf(_shake, 1.0)


func _update_orbit() -> void:
	var rect := stage.get_global_rect()
	var center := Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.52)
	for orbit in orbits:
		orbit.center = center
		orbit.from = counter.get_global_rect().get_center()
		orbit.time = _t
		orbit.queue_redraw()


func _tween() -> Tween:
	return create_tween().set_ignore_time_scale(true)


func _add_squirrel(node: Squirrel2D = null) -> void:
	var fresh := node == null
	if fresh:
		node = SQUIRREL.instantiate()
		node.mode = Squirrel2D.Mode.PARTY if randf() < 0.35 else Squirrel2D.Mode.RUN
		var big := randf_range(2.5, 6.0)
		node.scale = Vector2(big * (1.0 if randf() < 0.5 else -1.0), big)
		stampede.add_child(node)
	node.speed_scale = randf_range(0.9, 1.6)
	var right := node.scale.x > 0.0
	_squirrels.append({
		"node": node,
		"x": (-150.0 if right else root.size.x + 150.0) if fresh else node.position.x,
		"y": randf_range(root.size.y * 0.9, root.size.y - 5.0) if fresh else node.position.y,
		"v": randf_range(500.0, 1150.0) * (1.0 if right else -1.0),
		"hop": randf_range(8.0, 14.0),
		"phase": randf() * TAU,
		"jump": randf_range(120.0, 260.0) if randf() < 0.2 else randf_range(4.0, 14.0),
	})


func _close() -> void:
	visible = false
	Engine.time_scale = 1.0
	offset = Vector2.ZERO
	(primo.get_node("AnimationPlayer") as AnimationPlayer).stop()
	_shine.kill()
	$Root/Twinkle.emitting = false
	_launches.clear()
	for s in _squirrels:
		(s["node"] as Node).queue_free()
	_squirrels.clear()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
