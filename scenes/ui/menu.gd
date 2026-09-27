extends Control

const GOAL_ROW := preload("res://scenes/ui/goal_row.tscn")

@onready var main: VBoxContainer = $MainCenter/Main
@onready var options: Options = $OptionsCenter/Options
@onready var credits: ScrollContainer = $CreditsCenter/Credits
@onready var credits_page: Control = $CreditsCenter
@onready var forest: Array[Node] = $Forest.get_children()
@onready var saves: VBoxContainer = $SavesCenter/Saves
@onready var fade: ColorRect = $Fade
@onready var start: Button = $MainCenter/Main/Start
@onready var best_time: Label = $MainCenter/Main/BestTime
@onready var album: VBoxContainer = $AlbumCenter/Album
@onready var book: TextureRect = $AlbumCenter/Album/Book
@onready var snaps: Array[Control] = [$AlbumCenter/Album/Book/Left/Snap, $AlbumCenter/Album/Book/Right/Snap]
@onready var zoom: Control = $Zoom
@onready var goals_page: VBoxContainer = $GoalsCenter/Goals

var _t := 0.0
var _photos := PackedStringArray()
var _favs := PackedStringArray()
var _album_slot := 1
var _spread := 0
var _zoom_side := 0
var _export_side := 0
var _sel := 1


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	App.play_music()
	$MainCenter/Main/Quit.pressed.connect(App.quit)
	$Flourish.watch(main.find_children("*", "Button", false, false) + options.buttons + saves.find_children("*", "Button", true, false) + album.find_children("*", "Button", true, false) + [$CreditsCenter/Corners/Finish] + goals_page.find_children("*", "Button", true, false))
	create_tween().tween_property(fade, "color:a", 0.0, 0.8)
	best_time.visible = App.best_time > 0.0
	best_time.text = "best time  %s" % App.format_time(App.best_time)
	(best_time.material as ShaderMaterial).set_shader_parameter("progress", -0.2)
	var shine := create_tween().set_loops()
	shine.tween_interval(1.6)
	shine.tween_property(best_time.material, "shader_parameter/progress", 1.2, 0.9).from(-0.2)
	App.save_changed.connect(_refresh_slots)
	App.device_changed.connect(_pad_ui)
	for side in 2:
		snaps[side].get_node("Frame").pressed.connect(_album_zoom.bind(side))
		snaps[side].get_node("Heart").toggled.connect(_album_fav.bind(side))
		snaps[side].get_node("Trash").pressed.connect(_album_trash.bind(side))
		snaps[side].get_node("Share").pressed.connect(_album_export.bind(side))
	_pad_ui()
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


func _input(event: InputEvent) -> void:
	if not album.is_visible_in_tree() or $Toss.visible:
		return
	if zoom.visible:
		if App.using_pad and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")):
			_zoom_close()
			get_viewport().set_input_as_handled()
		return
	var dir := -1 if event.is_action_pressed("ui_left", true) else (1 if event.is_action_pressed("ui_right", true) else 0)
	if dir != 0:
		if App.using_pad or event is InputEventJoypadButton or event is InputEventJoypadMotion:
			_pad_move(dir)
		else:
			_album_flip(dir)
		get_viewport().set_input_as_handled()
		return
	var pad := event as InputEventJoypadButton
	if pad == null or not pad.pressed or $AlbumCenter/Album/Book/Flip.is_playing():
		return
	var has := snaps[_sel].visible
	match pad.button_index:
		JOY_BUTTON_A:
			if has:
				_album_zoom(_sel)
		JOY_BUTTON_Y:
			if has:
				var heart: TextureButton = snaps[_sel].get_node("Heart")
				heart.button_pressed = not heart.button_pressed
		JOY_BUTTON_X:
			if has:
				_album_trash(_sel)
		JOY_BUTTON_DPAD_UP:
			if has:
				_album_export(_sel)
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			_album_show(App.SLOTS[posmod(App.SLOTS.find(_album_slot) + (1 if pad.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1), App.SLOTS.size())])
		_:
			return
	get_viewport().set_input_as_handled()


func _pad_move(dir: int) -> void:
	var to := _sel + dir
	if to >= 0 and to <= 1 and snaps[to].visible:
		_sel = to
		_show_sel()
		return
	if $AlbumCenter/Album/Book/Flip.is_playing():
		return
	var before := _spread
	await _album_flip(dir)
	if _spread != before:
		_sel = 0 if dir > 0 and snaps[0].visible else 1
		_show_sel()


func _show_sel() -> void:
	if not snaps[_sel].visible:
		_sel = 1 - _sel
	for s in 2:
		var lift := 1.07 if App.using_pad and s == _sel and snaps[s].visible else 1.0
		snaps[s].create_tween().tween_property(snaps[s], "scale", Vector2.ONE * lift, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pad_ui() -> void:
	var g := func(b: int) -> String: return App.glyph_image("pad_%d" % b)
	var hints: RichTextLabel = $AlbumCenter/Album/Row/PadHints
	hints.text = "%s look   %s favourite   %s throw away   %s share   %s%s save   %s back" % [g.call(JOY_BUTTON_A), g.call(JOY_BUTTON_Y), g.call(JOY_BUTTON_X), g.call(JOY_BUTTON_DPAD_UP), g.call(JOY_BUTTON_LEFT_SHOULDER), g.call(JOY_BUTTON_RIGHT_SHOULDER), g.call(JOY_BUTTON_B)]
	hints.visible = App.using_pad
	for n in ["Prev", "Back", "Next"]:
		$AlbumCenter/Album/Row.get_node(n).visible = not App.using_pad
	_show_sel()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and zoom.visible:
		_zoom_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not main.visible:
		_open("")
		get_viewport().set_input_as_handled()


func _open(page: String) -> void:
	var to: Control = {"": main, "options": options, "controls": options, "credits": credits_page, "saves": saves, "album": album, "goals": goals_page}[page]
	for from: Control in [main, options, credits_page, saves, album, goals_page]:
		if from.visible and from != to:
			if from == album:
				$AlbumCenter/Album/Book/CloseSound.play()
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
	elif goals_page.visible:
		_goals_show(App.slot)
		goals_page.get_node("Slots/Slot%d" % App.slot).grab_focus()
	elif album.visible:
		$AlbumCenter/Album/Book/OpenSound.play()
		_album_show(App.slot)
		album.get_node("Slots/Slot%d" % App.slot).grab_focus()
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
		for icon: TextureRect in row.get_node("Play/Row/Info/Found").get_children():
			icon.modulate = Color.WHITE if StringName(icon.name) in info.get("ids", []) else Color(0.0, 0.0, 0.0, 0.55)


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


func _goals_show(slot: int) -> void:
	(goals_page.get_node("Slots/Slot%d" % slot) as Button).set_pressed_no_signal(true)
	var progress := App.read_progress(slot)
	var stats: Dictionary = progress["stats"]
	var tiers: Dictionary = progress["tiers"]
	goals_page.get_node("Season").text = "season %d" % (int(stats.get(&"seasons", 0.0)) + 1)
	var list := goals_page.get_node("Scroll/List")
	for row in list.get_children():
		row.free()
	for goal in App.goals:
		var tier: int = tiers.get(goal.id, 0)
		var have: float = stats.get(goal.stat, 0.0)
		var target := goal.target(tier)
		var row := GOAL_ROW.instantiate()
		list.add_child(row)
		row.get_node("Box/Info/Title").text = goal.text(tier)
		row.get_node("Box/Info/Progress/Bar").value = have / target
		row.get_node("Box/Info/Progress/Count").text = "%d / %d" % [have, target]
		row.get_node("Box/Side/Tier").text = "tier %d" % (tier + 1)
		row.get_node("Box/Side/Reward/Count").text = "+%d" % goal.reward_for(tier)
		row.get_node("Box/Side/Reward/Icon").texture = ItemDb.icon(goal.reward)
		if goal.maxed(tier):
			row.get_node("Box/Info/Title").text = goal.text(tier - 1)
			row.get_node("Box/Info/Progress/Bar").value = 1.0
			row.get_node("Box/Info/Progress/Count").text = "complete!"
			row.get_node("Box/Side/Tier").text = "all done"
			row.get_node("Box/Side/Reward").visible = false


func _album_show(slot: int) -> void:
	(album.get_node("Slots/Slot%d" % slot) as Button).set_pressed_no_signal(true)
	if album.is_visible_in_tree() and slot != _album_slot:
		$AlbumCenter/Album/Book/FlipSound.play()
	_album_slot = slot
	_photos = App.photos(slot)
	_favs = App.photo_favs(slot)
	_spread = 0
	for side in 2:
		_draw_page(side)


func _draw_page(side: int) -> void:
	var page := _spread * 2 + side
	var at: Control = book.get_node(["Left", "Right"][side])
	var snap := snaps[side]
	snap.visible = page > 0 and page <= _photos.size()
	snap.scale = Vector2.ONE
	_show_sel.call_deferred()
	snap.modulate.a = 1.0
	at.get_node("Number").text = str(page) if snap.visible else ""
	if side == 0:
		at.get_node("Cover").visible = page == 0
		if page == 0:
			_draw_cover()
	else:
		at.get_node("Empty").visible = _photos.is_empty()
		at.get_node("Empty").text = "No photos yet.\nPress %s in the forest to take one." % App.key_name(&"photo")
	var leaves := book.get_children().filter(func(n: Node) -> bool: return n.name.contains("Leaf"))
	for i in leaves.size():
		leaves[i].visible = (i + _spread) % 2 == 0
	$AlbumCenter/Album/Row/Prev.disabled = _spread == 0
	$AlbumCenter/Album/Row/Next.disabled = _spread >= _photos.size() / 2
	if not snap.visible:
		return
	var path := _photos[page - 1]
	(snap.get_node("Photo") as TextureRect).texture = ImageTexture.create_from_image(Image.load_from_file(path))
	snap.rotation_degrees = float(hash(path) % 9 - 4)
	snap.get_node("Caption").text = App.photo_caption(path.get_file())
	var fav := path.get_file() in _favs
	(snap.get_node("Heart") as TextureButton).set_pressed_no_signal(fav)
	snap.get_node("Heart").modulate.a = 1.0 if fav else 0.35


func _draw_cover() -> void:
	var cover := book.get_node("Left/Cover")
	var info := App.slot_info(_album_slot)
	cover.get_node("Owner").text = "Save %d" % _album_slot
	cover.get_node("Found").text = "%d / %d lost things found" % [info["found"], info["total"]] if not info.is_empty() else "not started yet"
	cover.get_node("Played").text = "played %s" % App.format_time(info["time"]) if not info.is_empty() else ""
	cover.get_node("Count").text = "%d photos   %d favourites" % [_photos.size(), _favs.size()]
	cover.get_node("Since").text = "since %s" % App.photo_caption(_photos[0].get_file()).get_slice("  ", 0) if not _photos.is_empty() else ""
	cover.get_node("Hint").visible = not _photos.is_empty()


func _album_flip(step: int) -> void:
	var flip: AnimationPlayer = $AlbumCenter/Album/Book/Flip
	var to := _spread + step
	if flip.is_playing() or to < 0 or to > _photos.size() / 2:
		return
	$AlbumCenter/Album/Book/FlipSound.play()
	_spread = to
	var first := 1 if step > 0 else 0
	_draw_page(first)
	flip.play(&"next" if step > 0 else &"prev")
	await flip.animation_finished
	_draw_page(1 - first)


func _album_fav(on: bool, side: int) -> void:
	var file := _photos[_spread * 2 + side - 1].get_file()
	App.set_photo_fav(_album_slot, file, on)
	_favs = App.photo_favs(_album_slot)
	var heart: Control = snaps[side].get_node("Heart")
	heart.modulate.a = 1.0 if on else 0.35
	heart.create_tween().tween_property(heart, "scale", Vector2.ONE, 0.3).from(Vector2.ONE * 1.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _album_trash(side: int) -> void:
	var snap := snaps[side]
	var tex: Texture2D = (snap.get_node("Photo") as TextureRect).texture
	App.delete_photo(_album_slot, _photos[_spread * 2 + side - 1])
	var ball: Node3D = $Toss/Viewport/Paper
	var cam: Camera3D = $Toss/Viewport/Camera
	var anim: AnimationPlayer = ball.get_node("AnimationPlayer")
	var mat: ShaderMaterial = (ball.get_node("Paper") as MeshInstance3D).material_override
	mat.set_shader_parameter("photo", tex)
	mat.set_shader_parameter("photo_aspect", float(tex.get_width()) / tex.get_height())
	anim.play(&"RESET")
	anim.advance(0.0)
	var toss: SubViewportContainer = $Toss
	var rect := snap.get_global_rect()
	var depth := 1.414 * toss.size.y / (rect.size.y * 2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	ball.position = cam.project_position(rect.get_center() - toss.global_position, depth)
	ball.rotation = Vector3(0.0, -snap.rotation, 0.0)
	$Toss/Viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	$Toss.visible = true
	snap.visible = false
	$Toss/CrumpleSound.play()
	anim.play(&"crumple")
	_photos = App.photos(_album_slot)
	_favs = App.photo_favs(_album_slot)
	_spread = mini(_spread, _photos.size() / 2)
	await anim.animation_finished
	$AlbumCenter/Album/Book/FlipSound.play()
	var spin := Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	var t := create_tween().set_parallel()
	t.tween_property(ball, "position", cam.position + Vector3(0.0, -0.35, 0.0), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(ball, "rotation", ball.rotation + spin, 0.45)
	await t.finished
	$Toss.visible = false
	$Toss/Viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for s in 2:
		_draw_page(s)


func _album_export(side: int) -> void:
	_export_side = side
	var dialog: FileDialog = $ExportDialog
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	dialog.current_file = _photos[_spread * 2 + side - 1].get_file()
	dialog.popup_centered()


func _export_to(path: String) -> void:
	var from := ProjectSettings.globalize_path(_photos[_spread * 2 + _export_side - 1])
	var ok := DirAccess.copy_absolute(from, path) == OK
	var caption: Label = snaps[_export_side].get_node("Caption")
	var old := caption.text
	caption.text = "saved!" if ok else "couldn't save"
	get_tree().create_timer(1.5).timeout.connect(func() -> void: caption.text = old)


func _album_zoom(side: int) -> void:
	var photo: TextureRect = $Zoom/Photo
	var from := (snaps[side].get_node("Photo") as Control).get_global_rect()
	_zoom_side = side
	photo.texture = (snaps[side].get_node("Photo") as TextureRect).texture
	photo.position = from.position
	photo.size = from.size
	photo.rotation = snaps[side].rotation
	zoom.modulate.a = 1.0
	zoom.visible = true
	var t := zoom.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property($Zoom/Dim, "color:a", 1.0, 0.35).from(0.0)
	t.tween_property(photo, "position", Vector2.ZERO, 0.35)
	t.tween_property(photo, "size", zoom.size, 0.35)
	t.tween_property(photo, "rotation", 0.0, 0.35)
	t.tween_property($Zoom/Caption, "modulate:a", 1.0, 0.3).from(0.0).set_delay(0.3)
	$AlbumCenter/Album/Book/FlipSound.play()


func _zoom_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_zoom_close()


func _zoom_close() -> void:
	var photo: TextureRect = $Zoom/Photo
	var to := (snaps[_zoom_side].get_node("Photo") as Control).get_global_rect()
	var t := zoom.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property($Zoom/Dim, "color:a", 0.0, 0.3)
	t.tween_property($Zoom/Caption, "modulate:a", 0.0, 0.1)
	t.tween_property(photo, "position", to.position, 0.3)
	t.tween_property(photo, "size", to.size, 0.3)
	t.tween_property(photo, "rotation", snaps[_zoom_side].rotation, 0.3)
	t.chain().tween_callback(zoom.hide)
