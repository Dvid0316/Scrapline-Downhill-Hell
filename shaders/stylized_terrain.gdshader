// Stylized terrain. Photo textures (Poly Haven, CC0) provide detail only:
// each layer's luminance is gradient-mapped onto a hand-picked palette, so the
// world stays bold and consistent instead of photo-muddy.
//
// Layers: grass (default), dirt (shoulders + patches), rock (steep slopes,
// with canyon strata bands), gravel (next to the track).
// Vertex colour masks from TerrainBuilder:
//   r = gravel (next to the track), g = shoulder dirt, b = mountain side.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_tex : filter_linear_mipmap_anisotropic, repeat_enable;

uniform float ground_scale = 0.16;   // texture repeats per metre
uniform float rock_scale = 0.07;

uniform vec3 grass_dark : source_color = vec3(0.09, 0.22, 0.05);
uniform vec3 grass_light : source_color = vec3(0.42, 0.64, 0.14);
uniform vec3 grass_dry : source_color = vec3(0.70, 0.62, 0.24);
uniform vec3 dirt_dark : source_color = vec3(0.30, 0.17, 0.09);
uniform vec3 dirt_light : source_color = vec3(0.80, 0.56, 0.32);
uniform vec3 rock_dark : source_color = vec3(0.30, 0.15, 0.10);
uniform vec3 rock_light : source_color = vec3(0.84, 0.54, 0.34);
uniform vec3 rock_band : source_color = vec3(0.72, 0.36, 0.22);
uniform vec3 gravel_dark : source_color = vec3(0.17, 0.15, 0.14);
uniform vec3 gravel_light : source_color = vec3(0.58, 0.53, 0.48);

uniform float rock_slope_start = 0.22;
uniform float rock_slope_end = 0.42;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

float remap(float v, float lo, float hi) {
	return clamp((v - lo) / (hi - lo), 0.0, 1.0);
}

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Two scales blended so tiling doesn't show from the 50 m camera.
vec3 sample2(sampler2D t, vec2 uv) {
	return mix(texture(t, uv).rgb, texture(t, uv * 0.27 + 0.31).rgb, 0.4);
}

vec3 triplanar(sampler2D t, vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy * scale).rgb * w.x
		+ texture(t, p.xz * scale).rgb * w.y
		+ texture(t, p.xy * scale).rgb * w.z;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = world_pos.xz * ground_scale;
	float macro = fbm(world_pos.xz * 0.012);
	float patch = fbm(world_pos.xz * 0.045 + 7.0);

	// Grass: gradient-mapped, drifting toward dry yellow in patches.
	vec3 gt = sample2(grass_tex, uv);
	float gl = remap(lum(gt), 0.17, 0.36);
	vec3 grass = mix(grass_dark, grass_light, gl);
	grass = mix(grass, grass_dry * (0.55 + gl * 0.6), smoothstep(0.5, 0.78, macro) * 0.45);

	vec3 dt = sample2(dirt_tex, uv * 0.8);
	float dl = remap(lum(dt), 0.28, 0.66);
	vec3 dirt = mix(dirt_dark, dirt_light, dl);

	vec3 rt = triplanar(rock_tex, world_pos, world_nrm, rock_scale);
	float rl = remap(lum(rt), 0.21, 0.38);
	// Canyon strata: wavy horizontal bands of warmer rock.
	float strata = sin(world_pos.y * 0.55 + fbm(world_pos.xz * 0.05) * 6.0);
	// Second, larger rock scale breaks up big cliff faces.
	vec3 rt2 = triplanar(rock_tex, world_pos * 0.31 + 11.0, world_nrm, rock_scale);
	float rl2 = remap(lum(rt2), 0.21, 0.38);
	vec3 rock = mix(rock_dark, rock_light, rl * 0.6 + rl2 * 0.4);
	rock = mix(rock, rock_band * (0.5 + rl * 0.7), smoothstep(0.35, 0.8, strata) * 0.6);
	// Crevices: darker where both scales are dark, plus vertical streaks.
	float streak = fbm(vec2(world_pos.x * 0.35 + world_pos.z * 0.35, world_pos.y * 0.04));
	rock *= 0.55 + 0.6 * smoothstep(0.1, 0.6, rl * rl2 + streak * 0.5);

	vec3 gv = sample2(gravel_tex, uv * 1.6);
	vec3 gravel = mix(gravel_dark, gravel_light, remap(lum(gv), 0.33, 0.8));

	// Masks. Height-aware blending: texture brightness nudges the edges so
	// transitions look like clumps, not smears.
	float slope = 1.0 - world_nrm.y;
	float rock_w = smoothstep(rock_slope_start, rock_slope_end, slope + (rl - 0.5) * 0.12);
	float dirt_w = clamp(COLOR.g + smoothstep(0.58, 0.72, patch + (dl - 0.5) * 0.3) * 0.85, 0.0, 1.0);
	dirt_w = smoothstep(0.35, 0.65, dirt_w + (dl - gl) * 0.25);
	float gravel_w = smoothstep(0.3, 0.7, COLOR.r + (remap(lum(gv), 0.33, 0.8) - 0.5) * 0.4);

	vec3 col = mix(grass, dirt, dirt_w);
	col = mix(col, rock, rock_w);
	col = mix(col, gravel, gravel_w);
	// Gentle large-scale brightness variation.
	col *= 0.88 + macro * 0.24;

	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.75, rock_w);
	// Ground normal detail from the top projection; cliffs get it faded out.
	vec3 nmap = mix(texture(grass_nrm, uv).rgb, texture(dirt_nrm, uv * 0.8).rgb, dirt_w);
	NORMAL_MAP = mix(nmap, vec3(0.5, 0.5, 1.0), rock_w * 0.8 + 0.2);
}
