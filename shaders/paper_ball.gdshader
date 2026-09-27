shader_type spatial;
render_mode cull_disabled;

uniform sampler2D frame_tex : source_color, filter_linear_mipmap;
uniform sampler2D photo : source_color, filter_linear_mipmap;
uniform vec4 window = vec4(0.097, 0.085, 0.829, 0.698);
uniform vec4 pin = vec4(0.16, 0.0, 0.26, 0.07);
uniform float photo_aspect = 1.778;
uniform float frame_aspect = 0.806;
uniform vec3 paper : source_color = vec3(0.95, 0.94, 0.91);

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec3 col = paper;
	if (FRONT_FACING) {
		vec4 frame = texture(frame_tex, uv);
		vec2 w = (uv - window.xy) / window.zw;
		float win_aspect = window.z / window.w * frame_aspect;
		vec2 puv = vec2(0.5 + (w.x - 0.5) * win_aspect / photo_aspect, w.y);
		float inside = step(0.0, w.x) * step(w.x, 1.0) * step(0.0, w.y) * step(w.y, 1.0);
		vec3 pic = mix(paper, texture(photo, puv).rgb, inside);
		float in_pin = step(pin.x, uv.x) * step(uv.x, pin.z) * step(pin.y, uv.y) * step(uv.y, pin.w);
		col = mix(pic, frame.rgb, frame.a * (1.0 - in_pin));
	}
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
