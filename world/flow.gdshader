shader_type spatial;
render_mode unshaded;
// Câble d'énergie : des impulsions lumineuses circulent quand le réseau est actif.

uniform vec4 color : source_color = vec4(0.18, 0.9, 0.84, 1.0);
uniform float active = 1.0;
uniform float speed = 0.8;
uniform float density = 3.0;

void fragment() {
	float band = fract(UV.y * density - TIME * speed);
	float pulse = smoothstep(0.0, 0.12, band) * smoothstep(0.4, 0.15, band);
	vec3 base = mix(vec3(0.25, 0.27, 0.3), color.rgb * 0.45, active);
	ALBEDO = base + color.rgb * pulse * active * 1.8;
}
