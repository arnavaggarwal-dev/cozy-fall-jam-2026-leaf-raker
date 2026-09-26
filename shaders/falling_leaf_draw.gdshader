shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley;

uniform sampler2D leaf_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float atlas_cells = 4.0;
uniform float alpha_cutoff = 0.4;

varying vec3 v_tint;
varying vec2 v_cell;

void vertex() {
	float cell = INSTANCE_CUSTOM.w;
	v_cell = vec2(mod(cell, atlas_cells), floor(cell / atlas_cells));
	v_tint = COLOR.rgb;
	NORMAL = normalize(NORMAL + vec3((UV.x - 0.5) * 1.2, 0.0, 0.0));
}

void fragment() {
	vec4 tex = texture(leaf_atlas, (v_cell + UV) / atlas_cells);
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = v_tint * clamp(lum * 2.2, 0.25, 1.25);
	ALBEDO = col;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.4;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
