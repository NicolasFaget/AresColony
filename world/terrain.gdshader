shader_type spatial;
render_mode diffuse_burley;
// Sol martien : grain fin, plaques de couleur, rides de sable sculptées par le vent,
// roche sombre dans les pentes. Tout est calculé en coordonnées du monde (pas de texture peinte).

uniform sampler2D noise_large : repeat_enable;
uniform sampler2D noise_fine : repeat_enable;
uniform sampler2D detail_normal : hint_normal, repeat_enable;
uniform vec3 sand_color : source_color = vec3(0.62, 0.3, 0.16);
uniform vec3 light_sand : source_color = vec3(0.76, 0.43, 0.25);
uniform vec3 dark_color : source_color = vec3(0.32, 0.15, 0.09);
uniform vec3 rock_color : source_color = vec3(0.38, 0.19, 0.12);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = world_pos.xz;
	float patches = texture(noise_large, uv * 0.025).r;
	float medium = texture(noise_large, uv * 0.13 + vec2(0.37, 0.71)).r;
	float grain = texture(noise_fine, uv * 1.7).r;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);

	vec3 col = mix(sand_color, light_sand, smoothstep(0.35, 0.75, patches));
	col = mix(col, dark_color, smoothstep(0.58, 0.85, medium) * 0.45);
	// Rides de sable : ondulations régulières, déformées par le bruit.
	float ripple = sin(dot(uv, vec2(2.1, 0.7)) * 5.0 + medium * 9.0) * 0.5 + 0.5;
	col *= 0.93 + 0.08 * ripple * (1.0 - slope);
	col = mix(col, rock_color, smoothstep(0.12, 0.4, slope));
	col *= 0.82 + 0.32 * grain;

	ALBEDO = col;
	ROUGHNESS = 0.92 - grain * 0.08;
	NORMAL_MAP = texture(detail_normal, uv * 0.6).rgb;
	NORMAL_MAP_DEPTH = 0.9;
}
