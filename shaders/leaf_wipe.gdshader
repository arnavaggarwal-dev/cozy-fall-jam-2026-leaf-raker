shader_type canvas_item;

uniform float progress = 0.0;
uniform sampler2D leaf : source_color, filter_nearest;
uniform float cell = 64.0;
uniform float texel = 6.0;
uniform float pixel = 3.0;
uniform vec4 fill : source_color = vec4(0.086, 0.047, 0.024, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 screen = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 p = floor(FRAGCOORD.xy / pixel) * pixel + pixel * 0.5;
	vec2 grid = ceil(screen / cell);
	vec2 home = floor(p / cell);
	float size = float(textureSize(leaf, 0).x) * texel;
	vec4 col = vec4(0.0);
	float best = -1.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -3; x <= 1; x++) {
			vec2 id = home + vec2(float(x), float(y));
			float r = hash(id);
			float delay = (id.x / grid.x * 0.55 + id.y / grid.y * 0.45) * 0.6 + r * 0.15;
			float grow = clamp((progress - delay) / 0.25, 0.0, 1.0);
			float gone = clamp((progress - 1.0 - delay) / 0.25, 0.0, 1.0);
			if (grow <= 0.0 || gone >= 1.0 || hash(p + id) > grow * 3.0) {
				continue;
			}
			float drop = (grow - 1.0) * cell * 1.2;
			vec2 center = (id + 0.5) * cell + vec2(gone * gone * cell * 2.5, drop - gone * cell * 0.6);
			float a = r * 6.2832 + (1.0 - grow + gone) * 1.5;
			vec2 d = p - center;
			d = vec2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a));
			vec2 uv = d / size + 0.5;
			if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0 || delay < best) {
				continue;
			}
			vec4 t = texture(leaf, uv);
			if (t.a < 0.5) {
				continue;
			}
			float k = fract(r * 7.13);
			vec3 tint = k < 0.33 ? vec3(1.0) : (k < 0.66 ? vec3(0.8, 0.55, 0.5) : vec3(1.05, 1.25, 1.35));
			col = vec4(min(t.rgb * tint, vec3(1.0)), 1.0);
			best = delay;
		}
	}
	float cover = smoothstep(0.55, 0.95, progress) * (1.0 - smoothstep(1.05, 1.45, progress));
	COLOR = col.a > 0.0 ? col : vec4(fill.rgb, fill.a * cover);
}
