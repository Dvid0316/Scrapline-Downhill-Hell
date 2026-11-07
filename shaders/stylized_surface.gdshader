// Stylized hard-surface material for vehicles, props and targets.
// Bold flat base colour, with Poly Haven (CC0) textures used only as
// greyscale detail: painted-metal grunge, rust patches that gather low on the
// object, and a normal map for dents. Object-space triplanar, so it works on
// primitive meshes without UVs and stays put on moving vehicles.
// A sky-tinted rim light keeps silhouettes readable from the high camera.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.5);
uniform float metallic : hint_range(0.0, 1.0) = 0.3;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;

uniform sampler2D grunge_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.45;
uniform float grunge_strength : hint_range(0.0, 1.0) = 0.35;
uniform float rust_amount : hint_range(0.0, 1.0) = 0.25;
uniform vec3 rust_color : source_color = vec3(0.62, 0.27, 0.09);
uniform float normal_strength : hint_range(0.0, 2.0) = 0.6;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
uniform vec3 rim_color : source_color = vec3(0.75, 0.88, 1.0);

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy * tex_scale) * w.x
		+ texture(t, p.xz * tex_scale) * w.y
		+ texture(t, p.xy * tex_scale) * w.z;
}

void fragment() {
	vec3 w = pow(abs(onrm), vec3(4.0));
	w /= (w.x + w.y + w.z);
	// Detail textures are read as raw data and stretched to 0..1.
	float g = clamp((dot(tri(grunge_tex, opos, w).rgb, vec3(0.333)) - 0.17) / 0.21, 0.0, 1.0);
	float r = clamp((dot(tri(rust_tex, opos * 0.7 + 3.1, w).rgb, vec3(0.333)) - 0.15) / 0.35, 0.0, 1.0);

	vec3 col = base_color * mix(1.0, 0.55 + g * 0.9, grunge_strength);
	// Rust: patchy, heavier toward the bottom of the object.
	float low = clamp(0.6 - opos.y * 0.25, 0.0, 1.0);
	float rust = smoothstep(0.62, 0.72, r + rust_amount * 0.55 + low * rust_amount * 0.35 - 0.25) * step(0.001, rust_amount);
	col = mix(col, rust_color * (0.6 + g * 0.8), rust);

	ALBEDO = col;
	METALLIC = mix(metallic, 0.1, rust);
	ROUGHNESS = mix(roughness, 0.9, rust) * (0.85 + g * 0.3);
	NORMAL_MAP = tri(detail_nrm, opos, w).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	RIM = rim_strength;
	RIM_TINT = 0.6;
}
