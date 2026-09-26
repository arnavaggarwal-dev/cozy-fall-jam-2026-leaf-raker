shader_type canvas_item;

uniform float progress = -1.0;
uniform float width = 1600.0;

varying float x;

void vertex() {
	x = VERTEX.x;
}

void fragment() {
	float band = 1.0 - smoothstep(0.0, 0.05, abs(x / width - progress));
	COLOR.rgb += band * 0.9 * COLOR.a;
}
