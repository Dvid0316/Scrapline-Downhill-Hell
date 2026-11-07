// Stylized sky: saturated gradient, soft sun glow, chunky cartoon clouds that
// drift slowly. Also lights the scene (ambient + reflections), so its colours
// set the mood of everything.
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.13, 0.36, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.8, 0.95);
uniform vec3 sunset_tint : source_color = vec3(1.0, 0.72, 0.45);
uniform vec3 ground_color : source_color = vec3(0.3, 0.28, 0.24);
uniform vec3 cloud_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shade : source_color = vec3(0.55, 0.62, 0.78);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.48;
uniform float cloud_scale = 1.6;
uniform float cloud_speed = 0.006;
uniform float sun_size : hint_range(0.0, 0.2) = 0.035;
uniform float sun_glow = 6.0;
uniform float exposure = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sun_dot = max(dot(dir, sun_dir), 0.0);

	// Base gradient, warmer toward the sun near the horizon.
	float t = pow(clamp(up, 0.0, 1.0), 0.45);
	vec3 col = mix(horizon_color, zenith_color, t);
	float sun_side = pow(sun_dot, 3.0) * (1.0 - t);
	col = mix(col, sunset_tint, sun_side * 0.55);

	// Below the horizon: fade to a hazy ground colour.
	if (up < 0.0) {
		col = mix(horizon_color * 0.9, ground_color, smoothstep(0.0, 0.25, -up));
	}

	// Cartoon clouds on a flat plane above the camera.
	if (up > 0.02) {
		vec2 uv = dir.xz / (up + 0.12) * cloud_scale;
		uv += TIME * cloud_speed * vec2(1.0, 0.35);
		float n = fbm(uv);
		float edge = 1.0 - cloud_coverage;
		float c = smoothstep(edge, edge + 0.06, n);           // hard-ish edge = stylized
		float core = smoothstep(edge + 0.04, edge + 0.22, n);  // darker bellies
		vec3 cc = mix(cloud_color, cloud_shade, core * 0.55);
		cc = mix(cc, cc * sunset_tint * 1.2, pow(sun_dot, 6.0) * 0.6);
		float fade = smoothstep(0.02, 0.25, up);
		col = mix(col, cc, c * fade);
	}

	// Sun disc + glow (only in the sky pass, not too strong for ambient).
	if (AT_CUBEMAP_PASS) {
		col += sunset_tint * pow(sun_dot, 64.0) * 0.4;
	} else {
		float disc = smoothstep(1.0 - sun_size * 0.02, 1.0 - sun_size * 0.015, sun_dot);
		col += vec3(1.0, 0.95, 0.85) * disc * sun_glow;
		col += sunset_tint * pow(sun_dot, 24.0) * 0.6;
	}
	COLOR = col * exposure;
}
