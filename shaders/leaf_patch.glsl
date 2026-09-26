#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, r32f) uniform restrict image2D window_depth;
layout(set = 0, binding = 1) uniform sampler2D patch_depth;

layout(push_constant, std430) uniform Params {
	ivec4 origin_size;
} p;

void main() {
	ivec2 local = ivec2(gl_GlobalInvocationID.xy);
	if (local.x >= p.origin_size.z || local.y >= p.origin_size.z) {
		return;
	}
	imageStore(window_depth, p.origin_size.xy + local, texelFetch(patch_depth, local, 0));
}
