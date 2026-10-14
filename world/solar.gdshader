shader_type spatial;
// Panneau solaire : cellules bleu nuit séparées par un quadrillage argenté, reflets nets.

uniform vec3 cell_color : source_color = vec3(0.04, 0.08, 0.22);
uniform vec3 grid_color : source_color = vec3(0.7, 0.74, 0.8);
uniform float cells = 9.0;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	// Seule la face avant porte les cellules ; tranches et dos en aluminium.
	float front = step(0.9, abs(local_normal.y));
	vec2 d = abs(fract(local_pos.xz * cells) - 0.5);
	float grid = smoothstep(0.43, 0.48, max(d.x, d.y));
	float diag = smoothstep(0.47, 0.5, abs(fract((local_pos.x + local_pos.z) * cells * 0.5) - 0.5)) * 0.15;
	vec3 col = mix(cell_color + diag, grid_color, grid);
	ALBEDO = mix(grid_color * 0.8, col, front);
	METALLIC = mix(0.7, 0.35, front);
	ROUGHNESS = mix(0.35, 0.12 + grid * 0.3, front);
	SPECULAR = 0.7;
}
