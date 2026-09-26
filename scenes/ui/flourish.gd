class_name Flourish
extends Control

const GAP := 14.0

var _target: Button

@onready var left: AnimatedSprite2D = $Left
@onready var right: AnimatedSprite2D = $Right
@onready var _size := left.scale


func watch(buttons: Array) -> void:
	for b: Button in buttons:
		b.mouse_entered.connect(point_at.bind(b))
		b.focus_entered.connect(point_at.bind(b))
		b.pressed.connect($Click.play)


func point_at(target: Button) -> void:
	if target == _target:
		return
	if _target:
		$Hover.play()
	_target = target
	for leaf: AnimatedSprite2D in [left, right]:
		leaf.scale = Vector2.ZERO
		leaf.create_tween().tween_property(leaf, "scale", _size, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(_delta: float) -> void:
	var shown := _target != null and _target.is_visible_in_tree()
	left.visible = shown
	right.visible = shown
	if not shown:
		return
	var text_w := _target.get_theme_font("font").get_string_size(_target.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _target.get_theme_font_size("font_size")).x
	var mid := _target.get_global_rect().get_center()
	var reach := text_w * 0.5 + GAP + 8.0 * _size.x
	left.global_position = mid - Vector2(reach, 0)
	right.global_position = mid + Vector2(reach, 0)
