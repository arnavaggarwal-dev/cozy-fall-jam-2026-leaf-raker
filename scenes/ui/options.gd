class_name Options
extends PanelContainer

signal closed

var _waiting := &""
var _direct := false
var _pad := false

@onready var settings: VBoxContainer = $Pages/Settings
@onready var controls: VBoxContainer = $Pages/Controls
@onready var keys: GridContainer = $Pages/Controls/Keys
@onready var back: Button = $Pages/Settings/Back
@onready var music_button: Button = $Pages/Settings/MusicButton
@onready var buttons: Array = find_children("*", "Button", true, false)


func _ready() -> void:
	_slider($Pages/Settings/Sensitivity/Slider, App.sensitivity, func(v: float) -> void: App.sensitivity = v)
	_slider($Pages/Settings/Volume/Slider, App.volume, func(v: float) -> void: App.volume = int(v))
	_slider($Pages/Settings/SfxVolume/Slider, App.sfx_volume, func(v: float) -> void: App.sfx_volume = int(v))
	var full: CheckBox = $Pages/Settings/Fullscreen
	full.button_pressed = App.fullscreen
	full.toggled.connect(func(on: bool) -> void:
		App.fullscreen = on
		App.save())
	music_button.pressed.connect(func() -> void:
		App.next_music()
		_refresh_music())
	_refresh_music()
	back.pressed.connect(closed.emit)
	$Pages/Controls/Reset.pressed.connect(App.reset_keys)
	$Pages/Controls/Device/Keyboard.pressed.connect(_show_device.bind(false))
	$Pages/Controls/Device/Controller.pressed.connect(_show_device.bind(true))
	$Pages/Controls/Back.pressed.connect(func() -> void:
		if _direct:
			closed.emit()
		else:
			show_page(false))
	for key: Button in _key_buttons():
		key.pressed.connect(_listen.bind(StringName(key.name)))
	App.keys_changed.connect(_refresh_keys)
	_refresh_keys()


func show_page(on_controls: bool, direct := false) -> void:
	_direct = direct
	_refresh_music()
	App.appear(controls if on_controls else settings)
	(settings if on_controls else controls).visible = false
	_show_device(App.using_pad)
	var first: Button = back
	if on_controls:
		first = $Pages/Controls/Device/Controller if _pad else $Pages/Controls/Device/Keyboard
	first.grab_focus.call_deferred()


func _show_device(pad: bool) -> void:
	_pad = pad
	_waiting = &""
	($Pages/Controls/Device/Controller as Button).set_pressed_no_signal(pad)
	($Pages/Controls/Device/Keyboard as Button).set_pressed_no_signal(not pad)
	_refresh_keys()


func _process(_delta: float) -> void:
	($Pages/Settings/Fullscreen as CheckBox).set_pressed_no_signal(App.fullscreen)


func _input(event: InputEvent) -> void:
	if _waiting == &"":
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and (key.physical_keycode == KEY_ESCAPE or not _pad):
		if key.physical_keycode != KEY_ESCAPE:
			App.rebind(_waiting, key.physical_keycode)
	elif _pad and ((event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.6)):
		App.rebind_pad(_waiting, App.pad_code(event))
	else:
		return
	get_viewport().set_input_as_handled()
	_waiting = &""
	_refresh_keys()


func _listen(action: StringName) -> void:
	_waiting = action
	_refresh_keys()


func _refresh_keys() -> void:
	for key: Button in _key_buttons():
		var action := StringName(key.name)
		key.text = "%s: %s" % [App.KEYS[action][0], ("press a button..." if _pad else "press a key...") if action == _waiting else App.pad_name(action) if _pad else App.key_name(action)]


func _refresh_music() -> void:
	music_button.text = "Music: %s" % App.music_name()


func _key_buttons() -> Array:
	return keys.get_children().filter(func(n: Node) -> bool: return n is Button)


func _slider(slider: HSlider, value: float, set_value: Callable) -> void:
	slider.value = value
	slider.value_changed.connect(func(v: float) -> void:
		set_value.call(v)
		App.save())
