shader_type canvas_item;

uniform sampler2D glow_tex : source_color, filter_linear;
uniform sampler2D mask : filter_linear;
uniform float progress = 0.0;

void fragment() {
	// Patches light up in mask order, so leaves catch the glow a few at a time instead of the whole image fading.
	float m = texture(mask, UV).r;
	float lit = smoothstep(m - 0.06, m + 0.06, progress * 1.12 - 0.06);
	COLOR = mix(texture(TEXTURE, UV), texture(glow_tex, UV), lit);
}
