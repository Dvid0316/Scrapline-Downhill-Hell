// Screen-space outlines for the stylized look: dark lines where depth jumps
// (silhouettes) or surface direction changes sharply (box edges). Drawn on a
// full-screen quad in front of the camera, before other transparent effects,
// so fire, smoke and tracers stay clean on top.
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D nrm_tex : hint_normal_roughness_texture, filter_nearest;
uniform vec3 line_color : source_color = vec3(0.06, 0.05, 0.08);
uniform float strength : hint_range(0.0, 1.0) = 0.75;
uniform float thickness = 1.2;
uniform float depth_threshold = 0.06;   // relative jump in distance
uniform float normal_threshold = 0.55;   // 1 - cos(angle)
uniform float fade_start = 90.0;
uniform float fade_end = 220.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 nrm(vec2 uv) {
	return normalize(texture(nrm_tex, uv).xyz * 2.0 - 1.0);
}

// Surfaces with roughness 1.0 opt out of outlines (grass).
bool skip(vec2 uv) {
	return texture(nrm_tex, uv).w > 0.995;
}

void fragment() {
	vec2 px = thickness / VIEWPORT_SIZE;
	float d0 = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 n0 = nrm(SCREEN_UV);
	float edge = 0.0;
	if (skip(SCREEN_UV)) {
		discard;
	}
	vec2 offs[4] = vec2[](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
	for (int i = 0; i < 4; i++) {
		vec2 uv = SCREEN_UV + offs[i];
		if (skip(uv)) {
			continue;
		}
		float d = lin_depth(uv, INV_PROJECTION_MATRIX);
		// Only the nearer side draws the line, so lines hug the object.
		float dd = (d - d0) / max(d0, 0.001);
		edge = max(edge, smoothstep(depth_threshold, depth_threshold * 2.0, dd));
		float nd = 1.0 - dot(n0, nrm(uv));
		edge = max(edge, smoothstep(normal_threshold, normal_threshold + 0.2, nd) * step(d0, d + 0.05 * d0));
	}
	float fade = 1.0 - smoothstep(fade_start, fade_end, d0);
	ALBEDO = line_color;
	ALPHA = edge * strength * fade;
}
