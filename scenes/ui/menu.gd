extends Control

@onready var main: VBoxContainer = $MainCenter/Main
@onready var options: Options = $OptionsCenter/Options
@onready var credits: ScrollContainer = $CreditsCenter/Credits
@onready var credits_page: Control = $CreditsCenter
@onready var forest: Array[Node] = $Forest.get_children()
@onready var saves: VBoxContainer = $SavesCenter/Saves
@onready var fade: ColorRect = $Fade
@onready var start: Button = $MainCenter/Main/Start
@onready var best_time: Label = $MainCenter/Main/BestTime

var _t := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	App.play_music()
	$MainCenter/Main/Quit.pressed.connect(App.quit)
	$Flourish.watch(main.find_children("*", "Button", false, false) + options.buttons + saves.find_children("*", "Button", true, false))
	create_tween().tween_property(fade, "color:a", 0.0, 0.8)
	best_time.visible = App.best_time > 0.0
	best_time.text = "best time  %s" % App.format_time(App.best_time)
	(best_time.material as ShaderMaterial).set_shader_parameter("progress", -0.2)
	var shine := create_tween().set_loops()
	shine.tween_interval(1.6)
	shine.tween_property(best_time.material, "shader_parameter/progress", 1.2, 0.9).from(-0.2)
	App.save_changed.connect(_refresh_slots)
	_refresh_slots()
	start.grab_focus.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	best_time.pivot_offset = best_time.size * 0.5
	best_time.rotation = sin(_t * 1.7) * 0.04
	(best_time.material as ShaderMaterial).set_shader_parameter("width", best_time.size.x)
	var tilt := get_viewport().get_mouse_position().x / get_viewport_rect().size.x - 0.5
	for i in forest.size():
		forest[i].position.x = -60.0 - tilt * (10.0 + i * 16.0)
	if credits.is_visible_in_tree():
		credits.scroll_vertical += ceili(delta * 40.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not main.visible:
		_open("")
		get_viewport().set_input_as_handled()


func _open(page: String) -> void:
	var to: Control = {"": main, "options": options, "controls": options, "credits": credits_page, "saves": saves}[page]
	for from: Control in [main, options, credits_page, saves]:
		if from.visible and from != to:
			await App.vanish(from)
	if not to.visible:
		App.appear(to)
	credits.scroll_vertical = 0
	if options.visible:
		options.show_page(page == "controls", true)
	elif saves.visible:
		_refresh_slots()
		saves.get_node("Slot%d/Play" % App.slot).grab_focus()
		for slot in App.SLOTS:
			var row: Control = saves.get_node("Slot%d" % slot)
			row.modulate.a = 0.0
			create_tween().tween_property(row, "modulate:a", 1.0, 0.35).set_delay(slot * 0.07)
	elif page == "":
		start.grab_focus()


func _refresh_slots() -> void:
	for slot in App.SLOTS:
		var row := saves.get_node("Slot%d" % slot)
		var info := App.slot_info(slot)
		var clear: Button = row.get_node("Clear")
		clear.remove_meta("armed")
		clear.text = "Clear"
		clear.disabled = info.is_empty()
		var sapling: AnimatedSprite2D = clear.get_node("Sapling")
		sapling.play(&"idle")
		sapling.modulate.a = 0.35 if clear.disabled else 1.0
		var status: Label = row.get_node("Play/Row/Info/Status")
		var done: bool = not info.is_empty() and info["found"] >= info["total"]
		status.modulate = Color(1.0, 0.85, 0.4) if done else Color.WHITE
		if info.is_empty():
			status.text = "New game"
		else:
			status.text = "%s   %d / %d found   %s" % ["Complete!" if done else "In progress", info["found"], info["total"], App.format_time(info["time"])]
		row.get_node("Play/Row/Info/Found").show_found(info.get("ids", []))


func _play_slot(slot: int) -> void:
	App.slot = slot
	App.new_game = false
	App.go(App.GAME)


func _clear_slot(slot: int) -> void:
	var clear: Button = saves.get_node("Slot%d/Clear" % slot)
	if not clear.has_meta("armed"):
		clear.set_meta("armed", true)
		clear.text = "Sure?"
		clear.get_node("Sapling").play(&"wilt")
		return
	App.delete_save(slot)
	saves.get_node("Slot%d/Play" % slot).grab_focus()
