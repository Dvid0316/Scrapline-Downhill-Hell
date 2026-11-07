shader_type spatial;
// Chunky toon smoke / fire puffs for CPUParticles3D.
// Colour comes from `ramp` sampled by particle age (INSTANCE_CUSTOM.y):
// rgb = tint, a = heat (0 = cold smoke, 1 = white-hot fire).
// Hot puffs glow; cold ones get hard toon shading with a soft floor.
render_mode cull_back, diffuse_toon, specular_disabled;

uniform sampler2D ramp : source_color, repeat_disable, filter_linear;
uniform float glow = 5.0;
uniform float shade_floor = 0.45;

varying vec4 tint;

void vertex() {
	tint = texture(ramp, vec2(clamp(INSTANCE_CUSTOM.y, 0.0, 1.0), 0.5));
	// heat is stored in alpha, which source_color leaves linear.
}

void fragment() {
	float heat = tint.a;
	ALBEDO = tint.rgb * (1.0 - heat * 0.7);
	EMISSION = tint.rgb * heat * heat * glow;
	ROUGHNESS = 0.95;  // < 1.0 so the outline pass still draws puffs
	BACKLIGHT = vec3(shade_floor * (1.0 - heat)) * tint.rgb;
}
