@tool
class_name FoundRow
extends Control

const SIZE := 34.0
const GAP := 6.0

var found: Array = []


func show_found(ids: Array) -> void:
	found = ids
	queue_redraw()


func _draw() -> void:
	var things := ItemDb.lost_things()
	for i in things.size():
		var rect := Rect2(Vector2(i * (SIZE + GAP), 0.0), Vector2(SIZE, SIZE))
		var icon := ItemDb.icon(things[i].id)
		var got := things[i].id in found
		draw_circle(rect.get_center(), SIZE * 0.55, Color(1.0, 0.75, 0.3, 0.18) if got else Color(0.0, 0.0, 0.0, 0.25))
		if icon:
			draw_texture_rect(icon, rect, false, Color.WHITE if got else Color(0.0, 0.0, 0.0, 0.55))
