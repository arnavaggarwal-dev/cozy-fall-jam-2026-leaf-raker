shader_type canvas_item;

uniform vec4 center_color : source_color = vec4(1.0, 0.72, 0.3, 1.0);
uniform vec4 edge_color : source_color = vec4(0.18, 0.05, 0.16, 1.0);
uniform vec4 ray_color : source_color = vec4(1.0, 0.92, 0.65, 1.0);
uniform vec2 center = vec2(0.28, 0.62);
uniform float rays = 12.0;
uniform float spin = 0.15;
uniform float grow : hint_range(0.0, 1.0) = 1.0;
uniform float aspect = 1.777;

void fragment() {
	vec2 p = (UV - center) * vec2(aspect, 1.0);
	float r = length(p);
	float a = atan(p.y, p.x) + TIME * spin;
	float beam = smoothstep(0.35, 0.65, sin(a * rays) * 0.5 + 0.5);
	float reach = 1.0 - smoothstep(0.0, grow * 1.8 + 0.001, r);
	vec3 col = mix(center_color.rgb, edge_color.rgb, smoothstep(0.0, 1.3, r));
	col += ray_color.rgb * beam * reach * 0.22 * grow;
	col += ray_color.rgb * (1.0 - smoothstep(0.0, 0.35, r)) * 0.25 * grow;
	col *= 1.0 - smoothstep(0.9, 1.9, r) * 0.55;
	COLOR = vec4(col, 1.0);
}
