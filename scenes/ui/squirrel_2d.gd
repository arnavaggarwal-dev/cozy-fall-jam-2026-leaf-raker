class_name Squirrel2D
extends AnimatedSprite2D

enum Mode { WAVE, RUN, CARRY, PARTY, WATCH }

const CELL := 32

var mode := Mode.WAVE:
	set(value):
		mode = value
		if is_inside_tree():
			_play()


func _ready() -> void:
	_play()


func paw_global() -> Vector2:
	return to_global(Vector2(2, -9))


func _play() -> void:
	if mode == Mode.WATCH:
		play(&"idle")
	elif mode == Mode.WAVE or mode == Mode.PARTY:
		play(&"wave")
	else:
		play(&"run")
		frame = randi() % sprite_frames.get_frame_count(&"run")


func _swap_idle() -> void:
	if mode == Mode.WAVE:
		play(&"idle" if animation == &"wave" and randf() < 0.4 else &"wave")
