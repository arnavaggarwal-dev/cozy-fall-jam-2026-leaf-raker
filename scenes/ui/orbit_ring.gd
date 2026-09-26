@tool
class_name OrbitRing
extends Node2D

@export var front := true
@export var center := Vector2(448.0, 546.0)
@export var radius := Vector2(270.0, 60.0)

var time := 0.0
var from := Vector2.ZERO
var launches: Array = []

var _icons: Array[Texture2D] = []


func _ready() -> void:
	for item in ItemDb.lost_things():
		_icons.append(ItemDb.icon(item.id))


func _draw() -> void:
	var n := _icons.size()
	for i in n:
		var angle := time * 0.9 + i * TAU / n
		var depth := sin(angle)
		if (depth > 0.0) != front or _icons[i] == null:
			continue
		var k := 1.0 if Engine.is_editor_hint() else (clampf((time - launches[i]) / 0.55, 0.0, 1.0) if i < launches.size() else 0.0)
		if k <= 0.0:
			continue
		var spot := center + Vector2(cos(angle) * radius.x, depth * radius.y + sin(time * 3.0 + i) * 10.0)
		var pos := from.lerp(spot, ease(k, 0.4)) + Vector2(0.0, -sin(k * PI) * 160.0)
		var s := (0.62 + 0.16 * depth) * minf(k * 3.0, 1.0)
		draw_set_transform(pos, sin(time * 2.0 + i) * 0.2, Vector2(s, s))
		draw_texture(_icons[i], -_icons[i].get_size() * 0.5, Color.WHITE.darkened(0.35 * maxf(-depth, 0.0)))
	draw_set_transform_matrix(Transform2D.IDENTITY)
