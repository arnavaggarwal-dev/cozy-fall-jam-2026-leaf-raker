shader_type sky;

uniform vec3 top_color : source_color = vec3(0.32, 0.52, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.82, 0.76, 0.66);
uniform vec3 ground_color : source_color = vec3(0.22, 0.17, 0.12);
uniform float stars = 0.0;
uniform float disk_size = 0.035;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	float up = EYEDIR.y;
	vec3 col;
	if (up >= 0.0) {
		col = mix(horizon_color, top_color, pow(up, 0.6));
	} else {
		col = mix(horizon_color, ground_color, clamp(-up * 4.0, 0.0, 1.0));
	}
	if (LIGHT0_ENABLED) {
		float facing = dot(EYEDIR, LIGHT0_DIRECTION);
		float disk = smoothstep(cos(disk_size), cos(disk_size * 0.6), facing);
		float halo = pow(max(facing, 0.0), 48.0) * 0.35;
		col += LIGHT0_COLOR * (disk * 3.0 + halo) * clamp(LIGHT0_ENERGY * 2.0, 0.4, 1.5);
	}
	if (stars > 0.0 && up > 0.0) {
		float star = step(0.9975, hash13(floor(EYEDIR * 240.0)));
		col += vec3(star) * stars * smoothstep(0.0, 0.25, up);
	}
	COLOR = col;
}
