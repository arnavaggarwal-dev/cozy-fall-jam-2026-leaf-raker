#[compute]
#version 450

layout(local_size_x = 32, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform restrict image2D state_a;
layout(set = 0, binding = 1, rgba16f) uniform restrict image2D state_b;
layout(set = 0, binding = 2, rgba16f) uniform restrict image2D state_c;
layout(set = 0, binding = 3) uniform sampler2D packed_tex;
layout(set = 0, binding = 4) uniform sampler2D loose_tex;
layout(set = 0, binding = 5) uniform sampler2D flow_tex;
layout(set = 0, binding = 6) uniform sampler2D prev_packed_tex;
layout(set = 0, binding = 7) uniform sampler2D rot_tex;

layout(push_constant, std430) uniform Params {
	vec4 rake_a;
	vec4 rake_b;
	vec4 rect;
	vec4 rake_c;
	vec4 window;
	vec4 misc;
	ivec4 flags;
	ivec4 dims;
} p;

const int MODE_SCATTER = 0;
const int MODE_BLAST = 2;
const int MODE_ROT = 3;
const int FLAG_RAKE = 1;
const int FLAG_RELAX = 2;
const float BLAST_HOP = 3.0;
const float BLAST_HEIGHT = 2.4;
const float VANISH_AT = 0.85;
const int FLAG_VANISH = 4;
const int PATCH = 64;
const float PI = 3.14159265359;
const float TAU = 6.28318530718;

uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float rand01(inout uint state) {
	state = hash_u(state);
	return float(state >> 8u) / 16777216.0;
}

vec2 window_uv(vec2 pos) {
	return (pos - p.window.xy) / p.window.w;
}

float packed_at(vec2 pos) {
	return textureLod(packed_tex, window_uv(pos), 0.0).r;
}

float loose_at(vec2 pos) {
	return textureLod(loose_tex, window_uv(pos), 0.0).r;
}

float total_at(vec2 pos) {
	return packed_at(pos) + loose_at(pos);
}

void main() {
	ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
	if (gid.x >= p.dims.x || gid.y >= p.dims.y) {
		return;
	}
	ivec2 texel = ivec2(gid.x, gid.y + p.flags.w);
	uint id = uint(texel.y * p.dims.x + texel.x);
	vec2 origin = p.window.xy;
	float cell = p.window.z;
	float visible_depth = p.rake_c.w;

	vec2 pos;
	float layer;
	float hop = 0.0;
	float yaw;
	float loose = 0.0;
	float flight = 0.0;

	if (p.flags.x == MODE_SCATTER) {
		uint s = hash_u(id * 2654435761u + uint(p.flags.z) * 40503u + 97u);
		for (int i = 0; i < 40; i++) {
			pos = p.rect.xy + vec2(rand01(s), rand01(s)) * p.rect.z;
			if (rand01(s) * p.rect.w <= total_at(pos)) {
				break;
			}
		}
		loose = rand01(s) * total_at(pos) < loose_at(pos) ? 1.0 : 0.0;
		layer = rand01(s);
		yaw = rand01(s) * TAU;
	} else {
		vec4 a = imageLoad(state_a, texel);
		vec4 b = imageLoad(state_b, texel);
		vec4 c = imageLoad(state_c, texel);
		pos = a.xy;
		yaw = a.w;
		layer = b.x;
		hop = b.y;
		loose = c.z;
		flight = c.w;
		if (hop < 0.0) {
			return;
		}
		bool in_active = pos.x >= p.rect.x && pos.y >= p.rect.y && pos.x <= p.rect.z && pos.y <= p.rect.w;
		if (!in_active && hop <= 0.0) {
			return;
		}
		uint s = hash_u(id * 1664525u + uint(p.flags.z) * 1013904223u);
		if (p.flags.x == MODE_ROT && hop <= 1.0 && rand01(s) < texelFetch(rot_tex, ivec2(floor((pos - origin) / cell)), 0).r) {
			hop = -1.0;
		}

		if (p.flags.x == MODE_BLAST) {
			if (hop > 1.0) {
				vec2 offset = pos - p.misc.yz;
				pos = p.misc.yz + offset / max(length(offset), 0.0001) * abs(flight);
				hop = flight < 0.0 ? -1.0 : 1.0;
			}
			vec2 cell_center = (floor((pos - origin) / cell) + 0.5) * cell + origin;
			float radius = p.rake_b.z;
			float outer = radius + p.rake_b.w;
			float share = 1.0 - smoothstep(radius * 0.6, radius, distance(cell_center, p.rake_a.xy));
			if (hop >= 0.0 && share > 0.0 && rand01(s) < share) {
				flight = sqrt(radius * radius + rand01(s) * (outer * outer - radius * radius)) * ((p.flags.y & FLAG_VANISH) != 0 ? -1.0 : 1.0);
				loose = 1.0;
				layer = rand01(s);
				hop = BLAST_HOP;
			}
		}

		if ((p.flags.y & FLAG_RAKE) != 0 && hop <= 1.0) {
			ivec2 cell_index = ivec2(floor((pos - origin) / cell));
			ivec2 local = cell_index - p.dims.zw;
			vec2 rel = (vec2(cell_index) + 0.5) * cell + origin - p.rake_a.xy;
			float v = dot(rel, p.rake_a.zw);
			bool in_patch = local.x >= 0 && local.y >= 0 && local.x < PATCH && local.y < PATCH;
			if (in_patch && abs(dot(rel, p.rake_b.xy)) <= p.rake_b.z && v <= 0.0 && v >= -p.rake_b.w) {
				bool take;
				if (loose > 0.5) {
					take = rand01(s) < p.rake_c.z;
				} else {
					float d_prev = texelFetch(prev_packed_tex, local, 0).r;
					float cut = p.rake_c.y;
					take = d_prev > 0.0005 && (1.0 - layer) * d_prev < cut;
					if (!take && d_prev > cut) {
						layer = min(layer * d_prev / (d_prev - cut), 1.0);
					}
				}
				if (take) {
					pos = p.rake_a.xy + p.rake_b.xy * dot(pos - p.rake_a.xy, p.rake_b.xy) + p.rake_a.zw * (rand01(s) * p.rake_c.x);
					loose = 1.0;
					layer = rand01(s);
					hop = 1.0;
					yaw += (rand01(s) - 0.5) * 3.0;
				}
			}
		}

		if ((p.flags.y & FLAG_RELAX) != 0 && loose > 0.5 && hop <= 1.0) {
			ivec2 local = ivec2(floor((pos - origin) / cell)) - p.dims.zw;
			if (local.x >= 0 && local.y >= 0 && local.x < PATCH && local.y < PATCH) {
				vec4 f = texelFetch(flow_tex, local, 0);
				float r = rand01(s);
				if (r < f.r) {
					pos.x += cell;
				} else if (r < f.r + f.g) {
					pos.x -= cell;
				} else if (r < f.r + f.g + f.b) {
					pos.y += cell;
				} else if (r < f.r + f.g + f.b + f.a) {
					pos.y -= cell;
				}
			}
		}

		if (hop > 1.0) {
			vec2 blast_center = p.flags.x == MODE_BLAST ? p.rake_a.xy : p.misc.yz;
			vec2 offset = pos - blast_center;
			float r = length(offset);
			vec2 dir = offset / max(r, 0.0001);
			float land = abs(flight);
			float u = (BLAST_HOP - hop) / (BLAST_HOP - 1.0);
			float start = u < 0.999 ? (r - u * land) / (1.0 - u) : land;
			hop = max(hop - p.misc.x * 1.5, 1.0);
			u = (BLAST_HOP - hop) / (BLAST_HOP - 1.0);
			pos = blast_center + dir * mix(start, land, u);
			yaw += p.misc.x * 9.0;
			if (flight < 0.0 && u >= VANISH_AT) {
				hop = -1.0;
			}
		} else if (hop > 0.0) {
			yaw += p.misc.x * hop * 10.0;
			hop = max(hop - p.misc.x * 2.5, 0.0);
		}
		pos = clamp(pos, origin + 0.05, origin + p.window.w - 0.05);
	}

	float packed_depth = packed_at(pos);
	float loose_depth = loose_at(pos);
	float y;
	float burial;
	if (loose > 0.5) {
		y = packed_depth + loose_depth * layer;
		burial = loose_depth * (1.0 - layer);
	} else {
		y = packed_depth * layer;
		burial = packed_depth * (1.0 - layer) + loose_depth;
	}
	float visible = hop < 0.0 ? 0.0 : ((burial <= visible_depth || hop > 0.0) ? 1.0 : 0.0);
	float shade = clamp(1.0 - burial / visible_depth, 0.0, 1.0);
	float blast_height = BLAST_HEIGHT * (0.3 + 1.4 * float(hash_u(id + 7919u) >> 8u) / 16777216.0);
	float lift = hop > 1.0 ? sin((BLAST_HOP - hop) / (BLAST_HOP - 1.0) * PI) * blast_height : sin(max(hop, 0.0) * PI) * 0.16;

	float gx = total_at(pos + vec2(cell, 0.0)) - total_at(pos - vec2(cell, 0.0));
	float gz = total_at(pos + vec2(0.0, cell)) - total_at(pos - vec2(0.0, cell));
	vec3 n = normalize(vec3(-gx, 2.0 * cell, -gz));

	imageStore(state_a, texel, vec4(pos, y + 0.006 + lift, yaw));
	imageStore(state_b, texel, vec4(layer, hop, shade, visible));
	imageStore(state_c, texel, vec4(n.x, n.z, loose, flight));
}
