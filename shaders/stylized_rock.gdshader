// Stylized rock for boulders and spires: same canyon palette and strata as
// the terrain cliffs, world-space triplanar so scaled/rotated rocks match,
// and a grassy cap on upward faces so they sit in the landscape.
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D rock_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale = 0.22;
uniform vec3 rock_dark : source_color = vec3(0.30, 0.15, 0.10);
uniform vec3 rock_light : source_color = vec3(0.84, 0.54, 0.34);
uniform vec3 rock_band : source_color = vec3(0.72, 0.36, 0.22);
uniform vec3 cap_color : source_color = vec3(0.30, 0.50, 0.10);
uniform float cap_amount : hint_range(0.0, 1.0) = 0.6;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(wnrm), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 t = texture(rock_tex, wpos.zy * scale).rgb * w.x
		+ texture(rock_tex, wpos.xz * scale).rgb * w.y
		+ texture(rock_tex, wpos.xy * scale).rgb * w.z;
	float l = clamp((dot(t, vec3(0.299, 0.587, 0.114)) - 0.21) / 0.17, 0.0, 1.0);
	vec3 col = mix(rock_dark, rock_light, l);
	float strata = sin(wpos.y * 1.4 + wpos.x * 0.15);
	col = mix(col, rock_band * (0.5 + l * 0.7), smoothstep(0.4, 0.9, strata) * 0.5);
	float cap = smoothstep(0.72, 0.9, wnrm.y + (l - 0.5) * 0.2) * cap_amount;
	col = mix(col, cap_color * (0.7 + l * 0.6), cap);
	col *= COLOR.r;
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
