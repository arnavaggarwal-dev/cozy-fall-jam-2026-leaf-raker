shader_type particles;
render_mode disable_velocity, disable_force;

#include "res://shaders/leaf_common.gdshaderinc"

uniform bool falling = false;
uniform float area_half = 18.0;
uniform float spawn_height_min = 3.0;
uniform float spawn_height_max = 12.0;
uniform float leaf_size = 0.15;
uniform float spread = 1.8;

void start() {
	vec3 origin = EMISSION_TRANSFORM[3].xyz;
	if (falling) {
		uint s = hash_u(INDEX * 747796405u + RANDOM_SEED * 2891336453u + 1u);
		float x = origin.x + (rand01(s) * 2.0 - 1.0) * area_half;
		float z = origin.z + (rand01(s) * 2.0 - 1.0) * area_half;
		float h = mix(spawn_height_min, spawn_height_max, rand01(s));
		VELOCITY = vec3(x, h, z);
		CUSTOM = vec4(rand01(s) * TAU, 0.0, mix(0.6, 1.1, rand01(s)), floor(rand01(s) * 9.999));
		COLOR = vec4(autumn_leaf_color(s), 1.0);
		TRANSFORM = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(x, h, z, 1.0));
	} else {
		uint s = hash_u(INDEX * 747796405u + RANDOM_SEED * 2891336453u + 3u);
		float angle = rand01(s) * TAU;
		float offset = sqrt(rand01(s)) * 0.6;
		vec3 p = origin + vec3(cos(angle) * offset, 0.2 + rand01(s) * 0.3, sin(angle) * offset);
		float outward = spread * rand01(s);
		VELOCITY = vec3(cos(angle) * outward, mix(1.8, 4.2, rand01(s)), sin(angle) * outward);
		CUSTOM = vec4(rand01(s) * TAU, 0.0, rand01(s) * 8.0 - 4.0, floor(rand01(s) * 9.999));
		COLOR = vec4(autumn_leaf_color(s), 1.0);
		TRANSFORM = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(p, 1.0));
	}
}

void process() {
	CUSTOM.y += DELTA;
	float t = CUSTOM.y;
	if (falling) {
		float phase = CUSTOM.x;
		vec3 o = VELOCITY;
		float y = o.y - t * CUSTOM.z;
		float sway = sin(t * 1.7 + phase);
		vec3 p = vec3(o.x + sway * 0.9 + t * 0.35, y, o.z + cos(t * 1.1 + phase * 1.3) * 0.6);
		mat3 b = leaf_basis(t * 2.3 + phase, sway * 1.1, t * 0.7 + phase) * (leaf_size * (y > 0.3 ? 1.0 : 0.0));
		TRANSFORM = mat4(vec4(b[0], 0.0), vec4(b[1], 0.0), vec4(b[2], 0.0), vec4(p, 1.0));
		COLOR.a = 1.0;
	} else {
		VELOCITY.y = max(VELOCITY.y - 6.0 * DELTA, -1.2);
		VELOCITY.xz *= exp(-DELTA * 2.0);
		vec3 p = TRANSFORM[3].xyz + VELOCITY * DELTA;
		mat3 b = leaf_basis(CUSTOM.x + t * CUSTOM.z, sin(t * 3.0 + CUSTOM.x) * 1.2, t * 2.0 + CUSTOM.x) * leaf_size;
		TRANSFORM = mat4(vec4(b[0], 0.0), vec4(b[1], 0.0), vec4(b[2], 0.0), vec4(p, 1.0));
	}
}
