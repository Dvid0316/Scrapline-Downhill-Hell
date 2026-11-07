// Foliage for MultiMesh trees, bushes and grass. Colour comes from vertex
// colours (dark base → bright tips), varied per instance so forests don't
// look copy-pasted. Vertex colour alpha = how much that vertex sways.
shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 tint_alt : source_color = vec3(1.0, 0.9, 0.6);
uniform float sway = 0.25;
uniform float sway_speed = 1.4;
uniform float gust_scale = 0.03;
// Roughness exactly 1.0 tells the outline pass to skip this (busy grass).
uniform bool no_outline = false;

varying float inst_rand;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	inst_rand = hash(origin.xz);
	float bend = COLOR.a;
	float t = TIME * sway_speed + inst_rand * 6.28;
	float gust = sin(TIME * 0.6 + origin.x * gust_scale + origin.z * gust_scale) * 0.5 + 0.5;
	vec2 offs = vec2(sin(t), cos(t * 0.8)) * sway * bend * (0.5 + gust);
	VERTEX.xz += offs * VERTEX.y * 0.2;
}

void fragment() {
	vec3 c = COLOR.rgb * mix(tint, tint_alt, inst_rand * 0.6);
	c *= 0.85 + inst_rand * 0.3;
	ALBEDO = c;
	ROUGHNESS = no_outline ? 1.0 : 0.9;
	// A little light through leaves (backlit edges glow).
	BACKLIGHT = c * 0.35;
}
