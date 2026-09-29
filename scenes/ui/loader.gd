extends TextureRect

## Caps how fast the glow spreads, so a near-instant load still reads as leaves lighting up.
const MAX_RATE := 0.7

var _lit := 0.0
var _menu: PackedScene


func _ready() -> void:
	ResourceLoader.load_threaded_request(App.MENU)


func _process(delta: float) -> void:
	var progress := [0.0]
	var status := ResourceLoader.load_threaded_get_status(App.MENU, progress)
	var loaded := status != ResourceLoader.THREAD_LOAD_IN_PROGRESS
	_lit = move_toward(_lit, 1.0 if loaded else progress[0], delta * MAX_RATE)
	(material as ShaderMaterial).set_shader_parameter("progress", _lit)
	if loaded and _lit >= 1.0:
		set_process(false)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_menu = ResourceLoader.load_threaded_get(App.MENU)
		App.go(App.MENU)
