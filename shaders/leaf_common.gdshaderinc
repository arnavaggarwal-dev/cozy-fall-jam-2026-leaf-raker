uint hash_u(uint x) {
	uint h = x;
	h ^= h >> 16u;
	h *= 2146121005u;
	h ^= h >> 15u;
	h *= 2221713035u;
	h ^= h >> 16u;
	return h;
}

float rand01(inout uint state) {
	state = hash_u(state);
	return float(state >> 8u) / 16777216.0;
}

vec3 autumn_leaf_color(inout uint state) {
	float r = rand01(state);
	vec3 c;
	if (r < 0.30) {
		c = vec3(0.852, 0.268, 0.0113);
	} else if (r < 0.52) {
		c = vec3(0.935, 0.579, 0.0474);
	} else if (r < 0.72) {
		c = vec3(0.579, 0.0356, 0.00502);
	} else if (r < 0.88) {
		c = vec3(0.302, 0.0993, 0.0178);
	} else {
		c = vec3(0.699, 0.148, 0.00394);
	}
	return c * mix(0.58, 1.23, rand01(state));
}

mat3 rotate_axis(vec3 k, float c, float s) {
	float t = 1.0 - c;
	return mat3(
			vec3(t * k.x * k.x + c, t * k.x * k.y + s * k.z, t * k.x * k.z - s * k.y),
			vec3(t * k.x * k.y - s * k.z, t * k.y * k.y + c, t * k.y * k.z + s * k.x),
			vec3(t * k.x * k.z + s * k.y, t * k.y * k.z - s * k.x, t * k.z * k.z + c));
}

mat3 align_up(vec3 n) {
	vec3 axis = vec3(n.z, 0.0, -n.x);
	float s = length(axis);
	if (s < 0.0001) {
		return mat3(1.0);
	}
	return rotate_axis(axis / s, n.y, s);
}

mat3 leaf_basis(float yaw, float tilt, float tilt_dir) {
	float cy = cos(yaw);
	float sy = sin(yaw);
	mat3 ry = mat3(vec3(cy, 0.0, -sy), vec3(0.0, 1.0, 0.0), vec3(sy, 0.0, cy));
	return rotate_axis(vec3(cos(tilt_dir), 0.0, sin(tilt_dir)), cos(tilt), sin(tilt)) * ry;
}
