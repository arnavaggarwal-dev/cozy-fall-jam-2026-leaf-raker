class_name DayNight
extends Node

const DAY_SECONDS := 480.0
const LIGHT_REFRESH_SECONDS := 0.25
const SKY_REFRESH_SECONDS := 2.0

var time_of_day := 0.32
var night_vision := 0.0
var daylight := 1.0

var _light_refresh := 0.0
var _sky_refresh := 0.0

@onready var environment: Environment = ($WorldEnvironment as WorldEnvironment).environment
@onready var sun: DirectionalLight3D = $Sun
@onready var sky_material: ShaderMaterial = environment.sky.sky_material


func _ready() -> void:
	_apply(true)


func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / DAY_SECONDS, 1.0)
	_light_refresh -= delta
	_sky_refresh -= delta
	if _light_refresh <= 0.0:
		_light_refresh = LIGHT_REFRESH_SECONDS
		var update_sky := _sky_refresh <= 0.0
		if update_sky:
			_sky_refresh = SKY_REFRESH_SECONDS
		_apply(update_sky)


func clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func _apply(update_sky: bool) -> void:
	var angle := (time_of_day - 0.25) * TAU
	var sun_dir := Vector3(cos(angle), sin(angle) * 0.85, 0.4).normalized()
	var day := smoothstep(-0.12, 0.2, sun_dir.y)
	daylight = day
	var low_sun := 1.0 - smoothstep(0.0, 0.45, absf(sun_dir.y))

	if sun_dir.y > -0.05:
		sun.basis = Basis.looking_at(-sun_dir, Vector3.UP)
		sun.light_color = Color(1.0, 0.9, 0.75).lerp(Color(1.0, 0.55, 0.3), low_sun)
		sun.light_energy = 1.45 * smoothstep(-0.05, 0.15, sun_dir.y)
	else:
		sun.basis = Basis.looking_at(sun_dir, Vector3.UP)
		sun.light_color = Color(0.6, 0.7, 1.0)
		sun.light_energy = 0.3 * smoothstep(0.05, 0.3, -sun_dir.y)

	var vision := night_vision * (1.0 - day)
	var warm_fog := Color(0.72, 0.62, 0.5).lerp(Color(0.85, 0.5, 0.35), low_sun)
	environment.fog_light_color = Color(0.07, 0.09, 0.15).lerp(warm_fog, day).lerp(Color(0.45, 0.3, 0.18), vision * 0.5)
	environment.fog_density = lerpf(0.024, 0.018, day)
	environment.ambient_light_color = Color(0.25, 0.3, 0.5).lerp(Color(0.9, 0.72, 0.55), day).lerp(Color(1.0, 0.72, 0.45), vision * 0.6)
	environment.ambient_light_energy = lerpf(0.35, 0.8, day) + vision * 0.9
	environment.tonemap_exposure = lerpf(1.35, 1.05, day) + vision * 0.5

	if update_sky:
		var day_horizon := Color(0.82, 0.76, 0.66).lerp(Color(0.98, 0.55, 0.32), low_sun)
		var day_top := Color(0.32, 0.52, 0.85).lerp(Color(0.35, 0.4, 0.65), low_sun * 0.6)
		sky_material.set_shader_parameter("horizon_color", Color(0.05, 0.07, 0.13).lerp(day_horizon, day))
		sky_material.set_shader_parameter("top_color", Color(0.015, 0.025, 0.07).lerp(day_top, day))
		sky_material.set_shader_parameter("ground_color", Color(0.03, 0.03, 0.04).lerp(Color(0.22, 0.17, 0.12), day))
		sky_material.set_shader_parameter("stars", 1.0 - smoothstep(0.0, 0.35, day))
