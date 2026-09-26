shader_type spatial;
render_mode world_vertex_coords, diffuse_burley;

uniform sampler2D near_packed : filter_linear, repeat_disable;
uniform sampler2D near_loose : filter_linear, repeat_disable;
uniform sampler2D far_depth : filter_linear, repeat_enable;
uniform sampler2D litter : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 grid_center = vec2(0.0);
uniform vec2 near_origin = vec2(0.0);
uniform float near_size = 56.0;
uniform float far_period = 192.0;
uniform float grid_inner = 12.8;
uniform float grid_outer = 97.2;
uniform float tuck = 0.05;
uniform bool glow_enabled = false;
uniform float glow_intensity = 1.0;
uniform sampler2D glow_map : filter_linear, repeat_disable;
uniform vec2 glow_origin = vec2(0.0);
uniform float glow_size = 56.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.68, 0.25);

varying vec3 v_world;
varying float v_depth;

float surface(vec2 p, out float near_weight) {
	float far_s = textureLod(far_depth, p / far_period, 0.0).r;
	vec2 uv = (p - near_origin) / near_size;
	float edge = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
	near_weight = smoothstep(0.0, 0.05, edge);
	if (near_weight <= 0.0) {
		return far_s;
	}
	float near_s = textureLod(near_packed, uv, 0.0).r + textureLod(near_loose, uv, 0.0).r;
	return mix(far_s, near_s, near_weight);
}

void vertex() {
	vec2 u = VERTEX.xz;
	vec2 offset = u * grid_inner + u * u * u * grid_outer;
	vec2 p = grid_center + offset;
	float weight;
	float unused;
	float s = surface(p, weight);
	float e = max(0.08, length(offset) * 0.03);
	float sx = surface(p + vec2(e, 0.0), unused) - surface(p - vec2(e, 0.0), unused);
	float sz = surface(p + vec2(0.0, e), unused) - surface(p - vec2(0.0, e), unused);
	v_depth = s;
	v_world = vec3(p.x, max(s - tuck * weight, 0.0), p.y);
	VERTEX = v_world;
	NORMAL = normalize(vec3(-sx, 2.0 * e, -sz));
}

void fragment() {
	vec2 p = v_world.xz;
	vec3 litter_a = texture(litter, p / 1.6).rgb;
	vec3 litter_b = texture(litter, mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / 2.3).rgb;
	vec3 litter_col = mix(litter_a, litter_b, 0.35) * 0.85;
	vec3 dirt_col = texture(dirt, p / 3.0).rgb * vec3(0.8, 0.72, 0.64);
	float cover = smoothstep(0.01, 0.06, v_depth);
	ALBEDO = mix(dirt_col, litter_col, cover);
	if (glow_enabled) {
		float glow = texture(glow_map, (p - glow_origin) / glow_size).r * (0.75 + 0.25 * sin(TIME * 1.8));
		float gap = 1.0 - smoothstep(0.02, 0.08, dot(litter_col, vec3(0.299, 0.587, 0.114)));
		float pinhole = step(0.93, fract(sin(dot(floor(p * 24.0), vec2(12.9898, 78.233))) * 43758.5453));
		EMISSION = glow_color * glow * (gap * 4.0 + pinhole * 3.0 + 0.04) * cover * glow_intensity;
	}
	NORMAL_MAP = mix(texture(dirt_normal, p / 3.0).rgb, vec3(0.5, 0.5, 1.0), cover);
	ROUGHNESS = 0.92;
}
