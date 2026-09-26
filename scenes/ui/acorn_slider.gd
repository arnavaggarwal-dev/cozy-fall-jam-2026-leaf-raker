@tool
extends HSlider

@export var cold: Texture2D
@export var hot: Texture2D

@onready var acorn: TextureRect = $Acorn


func _process(_delta: float) -> void:
	var grab := get_theme_icon("grabber").get_size()
	var ratio := 0.0 if max_value == min_value else (value - min_value) / (max_value - min_value)
	acorn.position = Vector2(ratio * (size.x - grab.x) + grab.x * 0.5, size.y * 0.5) - acorn.size * 0.5
	acorn.texture = hot if has_focus() or get_global_rect().has_point(get_global_mouse_position()) else cold
