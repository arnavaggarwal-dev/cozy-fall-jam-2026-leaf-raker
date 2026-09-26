class_name PauseMenu
extends CanvasLayer

signal opened

@onready var box: VBoxContainer = $Root/Center/Box
@onready var options: Options = $Root/Center/Options
@onready var thief: ButtonThief = $Root/QuitThief


func _ready() -> void:
	$Root/Center/Box/Restart.pressed.connect(func() -> void:
		App.new_game = true
		App.go(App.GAME))
	$Root/Center/Box/MainMenu.pressed.connect(App.go.bind(App.MENU))
	$Root/Quit.pressed.connect(App.quit)
	$Root/Flourish.watch(box.find_children("*", "Button", false, false) + [$Root/Quit] + options.buttons)


func open() -> void:
	visible = true
	App.appear($Root)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	thief.arrive()
	_show_options(false)
	opened.emit()


func close() -> void:
	thief.leave()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await App.vanish($Root)
	visible = false
	options.visible = false
	$Root.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause") and not (visible and event.is_action_pressed("ui_cancel")):
		return
	get_viewport().set_input_as_handled()
	if not visible:
		open()
	elif options.visible:
		_show_options(false)
	else:
		close()


func _show_options(show: bool) -> void:
	App.appear(options if show else box)
	(box if show else options).visible = false
	if show:
		options.show_page(false)
	else:
		$Root/Center/Box/Resume.grab_focus()
