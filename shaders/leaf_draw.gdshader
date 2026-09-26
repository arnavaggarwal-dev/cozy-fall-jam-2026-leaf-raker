shader_type spatial;
render_mode world_vertex_coords, cull_disabled, depth_draw_opaque, diffuse_burley;

#include "res://shaders/leaf_common.gdshaderinc"

uniform sampler2D state_a : filter_nearest;
uniform sampler2D state_b : filter_nearest;
uniform sampler2D state_c : filter_nearest;
uniform sampler2D leaf_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int tex_width = 1024;
uniform float leaf_size = 0.17;
uniform float atlas_cells = 4.0;
uniform float alpha_cutoff = 0.4;
uniform float lod_distance = 7.0;
uniform bool glow_enabled = false;
uniform float glow_intensity = 1.0;
uniform sampler2D glow_map : filter_linear, repeat_disable;
uniform vec2 glow_origin = vec2(0.0);
uniform float glow_size = 56.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.68, 0.25);

instance uniform int leaf_offset = 0;
instance uniform int leaf_stride = 1;

varying vec3 v_tint;
varying float v_shade;
varying vec2 v_cell;
varying vec2 v_uv;
varying float v_glow;

void vertex() {
	int index = leaf_offset + (VERTEX_ID / 4) * leaf_stride;
	int corner = VERTEX_ID % 4;
	ivec2 texel = ivec2(index % tex_width, index / tex_width);
	vec4 a = texelFetch(state_a, texel, 0);
	vec4 b = texelFetch(state_b, texel, 0);
	vec4 c = texelFetch(state_c, texel, 0);

	uint s = hash_u(uint(index) * 2246822519u + 3266489917u);
	float size = leaf_size * mix(0.7, 1.3, rand01(s)) * b.w;
	float tilt = mix(0.05, 0.45, rand01(s)) + b.y * 1.2;
	float tilt_dir = rand01(s) * TAU;
	float cell = floor(rand01(s) * 9.999);
	v_cell = vec2(mod(cell, atlas_cells), floor(cell / atlas_cells));
	v_tint = autumn_leaf_color(s);
	v_shade = b.z;

	vec3 center = vec3(a.x, a.z, a.y);
	v_glow = glow_enabled ? textureLod(glow_map, (a.xy - glow_origin) / glow_size, 0.0).r : 0.0;
	float dist = length(center - CAMERA_POSITION_WORLD);
	float keep = clamp(lod_distance * lod_distance / max(dist * dist, 0.0001), 0.0625, 1.0);
	uint low = uint(index) & 15u;
	float rank = float(((low & 1u) << 3u) | ((low & 2u) << 1u) | ((low & 4u) >> 1u) | ((low & 8u) >> 3u));
	size *= (rank + rand01(s)) / 16.0 < keep ? inversesqrt(keep) : 0.0;

	vec3 n = vec3(c.x, sqrt(max(1.0 - c.x * c.x - c.y * c.y, 0.0)), c.y);
	mat3 basis = align_up(n) * leaf_basis(a.w, tilt, tilt_dir);
	vec2 uv = vec2(corner == 1 || corner == 2 ? 1.0 : 0.0, corner >= 2 ? 1.0 : 0.0);
	v_uv = uv;
	VERTEX = center + basis * vec3(uv.x - 0.5, 0.0, uv.y - 0.5) * size;
	NORMAL = normalize(basis * vec3((uv.x - 0.5) * 1.2, 1.0, 0.0));
}

void fragment() {
	vec4 tex = texture(leaf_atlas, (v_cell + v_uv) / atlas_cells);
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = v_tint * clamp(lum * 2.2, 0.25, 1.25) * mix(0.5, 1.0, v_shade);
	ALBEDO = col;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.4;
	if (glow_enabled) {
		EMISSION = mix(col, glow_color, 0.6) * v_glow * (0.75 + 0.25 * sin(TIME * 1.8)) * 0.8 * glow_intensity;
	}
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
