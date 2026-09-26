extends Node

const SAVE := "user://settings.cfg"
const SAVE_DIR := "user://saves"
const SLOTS := [1, 2, 3, 4]
const GLYPHS := "res://assets/textures/ui/prompts/"
const MENU := "res://scenes/ui/menu.tscn"
const GAME := "res://scenes/main.tscn"
const LEAF := preload("res://assets/textures/ui/fall_leaf.png")
const CURSOR_FRAMES := 5
const CURSOR_FPS := 10.0
const CURSOR_SCALE := 8

const KEYS := {
	&"forward": ["Walk forward", [KEY_W], [102]],
	&"back": ["Walk back", [KEY_S], [103]],
	&"left": ["Walk left", [KEY_A], [100]],
	&"right": ["Walk right", [KEY_D], [101]],
	&"jump": ["Jump", [KEY_SPACE], [JOY_BUTTON_A]],
	&"dash": ["Dash", [KEY_SHIFT], [JOY_BUTTON_B]],
	&"look_left": ["Look left", [KEY_LEFT], [104]],
	&"look_right": ["Look right", [KEY_RIGHT], [105]],
	&"look_up": ["Look up", [KEY_UP], [106]],
	&"look_down": ["Look down", [KEY_DOWN], [107]],
	&"inventory": ["Inventory", [KEY_E, KEY_TAB], [JOY_BUTTON_Y]],
	&"drop": ["Drop item", [KEY_Q], [JOY_BUTTON_DPAD_DOWN]],
	&"pick_up": ["Pick up", [KEY_F], [JOY_BUTTON_X]],
	&"fresh_leaves": ["Fresh leaves", [KEY_R], [JOY_BUTTON_BACK]],
	&"use": ["Use item", [KEY_C], [111]],
	&"hotbar_prev": ["Hotbar left", [], [JOY_BUTTON_LEFT_SHOULDER]],
	&"hotbar_next": ["Hotbar right", [], [JOY_BUTTON_RIGHT_SHOULDER]],
}

const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "LS click", JOY_BUTTON_RIGHT_STICK: "RS click",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
	100: "LS left", 101: "LS right", 102: "LS up", 103: "LS down",
	104: "RS left", 105: "RS right", 106: "RS up", 107: "RS down",
	108: "LT", 109: "LT", 110: "RT", 111: "RT",
}

signal keys_changed
signal save_changed
signal device_changed

var volume := 6
var sfx_volume := 6
var sensitivity := 1.0
var fullscreen := false
var music := 0
var slot := 1
var new_game := false
var best_time := 0.0
var using_pad := false

var _frames: Array[Image] = []
var _frame_time := 0.0
var _frame := -1
var _hotspot := Vector2.ZERO

@onready var tracks: Array[Node] = $Music.get_children()
@onready var wipe: ColorRect = $Transition/Wipe


func _ready() -> void:
	var strip := LEAF.get_image()
	strip.decompress()
	strip.convert(Image.FORMAT_RGBA8)
	var size := strip.get_width() / CURSOR_FRAMES
	for i in CURSOR_FRAMES:
		var frame := strip.get_region(Rect2i(i * size, 0, size, size))
		frame.resize(size * CURSOR_SCALE, size * CURSOR_SCALE, Image.INTERPOLATE_NEAREST)
		_frames.append(frame)
	_hotspot = Vector2.ONE * size * CURSOR_SCALE * 0.5
	_reveal()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE) == OK:
		volume = clampi(cfg.get_value("audio", "volume", volume), 0, 10)
		sfx_volume = clampi(cfg.get_value("audio", "sfx_volume", sfx_volume), 0, 10)
		sensitivity = cfg.get_value("controls", "sensitivity", sensitivity)
		fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
		best_time = cfg.get_value("records", "best_time", best_time)
		music = clampi(cfg.get_value("audio", "music", music), 0, tracks.size() - 1)
	for action: StringName in KEYS:
		InputMap.add_action(action, 0.25)
		_bind(action, [cfg.get_value("keys", action)] if cfg.has_section_key("keys", action) else KEYS[action][1],
			[cfg.get_value("pads", action)] if cfg.has_section_key("pads", action) else KEYS[action][2])
	InputMap.add_action(&"pause")
	for e: InputEvent in [_key_event(KEY_ESCAPE), _pad_event(JOY_BUTTON_START)]:
		InputMap.action_add_event(&"pause", e)
	InputMap.action_add_event(&"ui_accept", _pad_event(JOY_BUTTON_A))
	InputMap.action_add_event(&"ui_cancel", _pad_event(JOY_BUTTON_B))
	if FileAccess.file_exists("user://save.dat") and not has_save(1):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_slot_dir(1)))
		DirAccess.rename_absolute(ProjectSettings.globalize_path("user://save.dat"), ProjectSettings.globalize_path(_save_path(1)))
	apply()


func apply() -> void:
	_set_level(0, volume)
	_set_level(AudioServer.get_bus_index(&"SFX"), sfx_volume)
	if fullscreen != (DisplayServer.window_get_mode() >= DisplayServer.WINDOW_MODE_FULLSCREEN):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


# 0-10 steps, 10 is untouched full volume
func _set_level(bus: int, steps: int) -> void:
	AudioServer.set_bus_mute(bus, steps == 0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(steps / 10.0) if steps > 0 else -80.0)


func save() -> void:
	apply()
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("controls", "sensitivity", sensitivity)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("audio", "music", music)
	cfg.set_value("records", "best_time", best_time)
	for action: StringName in KEYS:
		var keys := _keys(action)
		if keys != Array(KEYS[action][1]) and not keys.is_empty():
			cfg.set_value("keys", action, keys[0])
		var pads := _pads(action)
		if pads != Array(KEYS[action][2]) and not pads.is_empty():
			cfg.set_value("pads", action, pads[0])
	cfg.save(SAVE)


func rebind(action: StringName, key: Key) -> void:
	_bind(action, [key], _pads(action))
	save()


func rebind_pad(action: StringName, code: int) -> void:
	_bind(action, _keys(action), [code])
	save()


func reset_keys() -> void:
	for action: StringName in KEYS:
		_bind(action, KEYS[action][1], KEYS[action][2])
	save()


func key_name(action: StringName) -> String:
	var names: Array = _keys(action).map(func(k: Key) -> String: return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(k)))
	return " / ".join(names) if not names.is_empty() else "-"


func pad_name(action: StringName) -> String:
	var names: Array = _pads(action).map(func(c: int) -> String: return PAD_NAMES.get(c, "Pad %d" % c))
	return " / ".join(names) if not names.is_empty() else "-"


func _keys(action: StringName) -> Array:
	return InputMap.action_get_events(action).filter(func(e: InputEvent) -> bool: return e is InputEventKey).map(func(e: InputEventKey) -> Key: return e.physical_keycode)


func _pads(action: StringName) -> Array:
	return InputMap.action_get_events(action).map(pad_code).filter(func(c: int) -> bool: return c >= 0)


func glyph(action: StringName) -> String:
	if action == &"use" and not using_pad:
		return glyph_image("mouse_left")
	var codes := _pads(action) if using_pad else _keys(action)
	if codes.is_empty():
		return "-"
	var file := ("pad_%d" if using_pad else "key_%d") % codes[0]
	if ResourceLoader.exists(GLYPHS + file + ".png"):
		return glyph_image(file)
	return "[%s]" % (pad_name(action) if using_pad else key_name(action))


func glyph_image(file: String) -> String:
	return "[img=center]%s%s.png[/img]" % [GLYPHS, file]


func pad_code(e: InputEvent) -> int:
	if e is InputEventJoypadButton:
		return e.button_index
	if e is InputEventJoypadMotion:
		return 100 + e.axis * 2 + (1 if e.axis_value > 0.0 else 0)
	return -1


func _bind(action: StringName, keys: Array, pads: Array) -> void:
	InputMap.action_erase_events(action)
	for k: int in keys:
		InputMap.action_add_event(action, _key_event(k))
	for c: int in pads:
		InputMap.action_add_event(action, _pad_event(c))
	keys_changed.emit()


func _key_event(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k as Key
	return e


func _pad_event(code: int) -> InputEvent:
	if code >= 100:
		var motion := InputEventJoypadMotion.new()
		motion.axis = ((code - 100) / 2) as JoyAxis
		motion.axis_value = 1.0 if (code - 100) % 2 == 1 else -1.0
		return motion
	var button := InputEventJoypadButton.new()
	button.button_index = code as JoyButton
	return button


func play_music() -> void:
	var current: AudioStreamPlayer = tracks[music]
	if current.stream_paused:
		current.stream_paused = false
	elif not current.playing:
		current.play()


func next_music() -> void:
	(tracks[music] as AudioStreamPlayer).stream_paused = true
	music = (music + 1) % tracks.size()
	save()
	play_music()


func music_name() -> String:
	return tracks[music].name


func record_time(seconds: float) -> bool:
	if best_time > 0.0 and seconds >= best_time:
		return false
	best_time = seconds
	save()
	return true


func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d:%02d" % [s / 3600, s / 60 % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]


func has_save(which := -1) -> bool:
	return FileAccess.file_exists(_save_path(which))


func slot_info(which := -1) -> Dictionary:
	var cfg := ConfigFile.new()
	if not has_save(which) or cfg.load(_slot_dir(which) + "/info.cfg") != OK:
		return {}
	return {"found": cfg.get_value("slot", "found", 0), "total": cfg.get_value("slot", "total", 15), "time": cfg.get_value("slot", "time", 0.0), "ids": cfg.get_value("slot", "ids", [])}


func _slot_dir(which := -1) -> String:
	return "%s/slot%d" % [SAVE_DIR, slot if which < 0 else which]


func _save_path(which := -1) -> String:
	return _slot_dir(which) + "/save.dat"


func save_megabytes(which := -1) -> float:
	var file := FileAccess.open(_save_path(which), FileAccess.READ)
	return file.get_length() / 1048576.0 if file else 0.0


func write_save(data: Dictionary, info: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_slot_dir()))
	var file := FileAccess.open_compressed(_save_path(), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file:
		file.store_var(data)
		file.close()
		var cfg := ConfigFile.new()
		for k: String in info:
			cfg.set_value("slot", k, info[k])
		cfg.save(_slot_dir() + "/info.cfg")
		save_changed.emit()


func read_save() -> Dictionary:
	var file := FileAccess.open_compressed(_save_path(), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	var data: Variant = file.get_var() if file else null
	return data if data is Dictionary else {}


func delete_save(which := -1) -> void:
	for f in ["/save.dat", "/info.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_slot_dir(which) + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_slot_dir(which)))
	save_changed.emit()


func appear(node: CanvasItem) -> void:
	node.visible = true
	node.modulate.a = 0.0
	var t := _fresh_tween(node).set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "modulate:a", 1.0, 0.35)
	if node is Control:
		node.pivot_offset_ratio = Vector2(0.5, 0.5)
		t.tween_property(node, "scale", Vector2.ONE, 0.35).from(Vector2.ONE * 0.97)
	for divider: Control in node.find_children("Divider", "TextureRect", true, false):
		divider.scale.x = 0.0
		divider.modulate.a = 0.0
		t.tween_property(divider, "scale:x", 1.0, 0.6).set_delay(0.12)
		t.tween_property(divider, "modulate:a", 1.0, 0.4).set_delay(0.12)


func vanish(node: CanvasItem) -> void:
	var t := _fresh_tween(node)
	t.tween_property(node, "modulate:a", 0.0, 0.15)
	await t.finished
	node.visible = false
	node.modulate.a = 1.0


func _fresh_tween(node: CanvasItem) -> Tween:
	if node.has_meta("tween"):
		(node.get_meta("tween") as Tween).kill()
	var t := node.create_tween()
	node.set_meta("tween", t)
	return t


func go(scene: String) -> void:
	if wipe.visible:
		return
	Engine.time_scale = 1.0
	wipe.visible = true
	wipe.mouse_filter = Control.MOUSE_FILTER_STOP
	await _wipe(0.0, 1.0)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(scene)
	_reveal()


func _reveal() -> void:
	wipe.visible = true
	wipe.mouse_filter = Control.MOUSE_FILTER_STOP
	(wipe.material as ShaderMaterial).set_shader_parameter("progress", 1.0)
	for i in 60:
		await get_tree().process_frame
		if i > 2 and get_process_delta_time() < 0.05:
			break
	await _wipe(1.0, 2.0)
	wipe.visible = false
	wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE


func quit() -> void:
	if wipe.visible:
		return
	wipe.visible = true
	wipe.mouse_filter = Control.MOUSE_FILTER_STOP
	await _wipe(0.0, 1.0)
	get_tree().quit()


func _wipe(from: float, to: float) -> void:
	var t := create_tween().set_ignore_time_scale()
	t.tween_method(func(v: float) -> void: (wipe.material as ShaderMaterial).set_shader_parameter("progress", v), from, to, 0.9)
	await t.finished


func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5)
	if (pad or ((event is InputEventKey or event is InputEventMouseButton) and event.device != InputEvent.DEVICE_ID_EMULATION)) and pad != using_pad:
		using_pad = pad
		device_changed.emit()
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and (key.keycode == KEY_F11 or (key.keycode == KEY_ENTER and key.alt_pressed)):
		fullscreen = not fullscreen
		save()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return
	_frame_time += delta / maxf(Engine.time_scale, 0.01)
	var frame := int(_frame_time * CURSOR_FPS) % CURSOR_FRAMES
	if frame != _frame:
		_frame = frame
		Input.set_custom_mouse_cursor(_frames[frame], Input.CURSOR_ARROW, _hotspot)
		Input.set_custom_mouse_cursor(_frames[frame], Input.CURSOR_POINTING_HAND, _hotspot)
