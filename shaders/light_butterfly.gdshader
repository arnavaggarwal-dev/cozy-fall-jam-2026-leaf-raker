shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.95, 0.75);
uniform vec3 edge_color : source_color = vec3(1.0, 0.7, 0.3);
uniform float brightness = 1.0;

void vertex() {
	float phase = INSTANCE_CUSTOM.r;
	float flap_speed = INSTANCE_CUSTOM.g;
	float span = abs(VERTEX.x);
	if (span > 0.0) {
		float angle = (0.35 + 0.75 * sin(TIME * flap_speed + phase * TAU)) * sign(VERTEX.x);
		VERTEX.x = span * cos(angle) * sign(VERTEX.x);
		VERTEX.y = span * abs(sin(angle));
	}
}

float lobe(vec2 uv, vec2 center, vec2 radius) {
	vec2 q = (uv - center) / radius;
	return 1.0 - smoothstep(0.55, 1.0, dot(q, q));
}

void fragment() {
	float wing = max(lobe(UV, vec2(0.55, 0.64), vec2(0.5, 0.38)), lobe(UV, vec2(0.42, 0.25), vec2(0.36, 0.26)));
	float core = wing * wing * (1.0 - UV.x * 0.6);
	vec3 col = mix(edge_color, core_color, core) * (wing * 1.2 + core * 2.5);
	ALBEDO = col * brightness * 2.2;
}
