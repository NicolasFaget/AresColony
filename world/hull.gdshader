shader_type spatial;
// Revêtement des modules : joints de panneaux, petites variations, usure, poussière martienne
// déposée sur les faces tournées vers le ciel et au pied des parois.
// Calculé dans le repère de l'objet : les motifs restent fixes quand il bouge.

uniform vec4 albedo : source_color = vec4(0.92, 0.92, 0.9, 1.0);
uniform float metallic = 0.0;
uniform float roughness = 0.65;
uniform float panel_scale = 5.0;
uniform float dust = 0.3;
uniform float crinkle = 0.0;
uniform sampler2D grime : repeat_enable;

varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_normal;
varying float world_y;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

float seam(vec2 p) {
	vec2 d = abs(fract(p * panel_scale) - 0.5);
	return smoothstep(0.455, 0.49, max(d.x, d.y));
}

// Projection sur l'axe dominant de la normale : une seule lecture de texture (économe sur mobile).
vec2 project(vec3 p, vec3 n) {
	vec3 a = abs(n);
	return a.x > a.y && a.x > a.z ? p.yz : (a.y > a.z ? p.xz : p.xy);
}

void fragment() {
	vec3 w = pow(abs(local_normal), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float lines = panel_scale > 0.0 ? seam(local_pos.yz) * w.x + seam(local_pos.xz) * w.y + seam(local_pos.xy) * w.z : 0.0;
	vec2 uv = project(local_pos, local_normal);
	float g = texture(grime, uv * 1.3).r;
	float fine = texture(grime, uv * 6.0).r;

	vec3 col = albedo.rgb * (1.0 - lines * 0.22) * (0.94 + 0.08 * g);
	// Feuille thermique froissée (or de l'atterrisseur).
	col *= 1.0 + crinkle * (fine - 0.5) * 0.3;
	// Poussière : sur le dessus des volumes et au ras du sol.
	float top = smoothstep(0.55, 0.95, world_normal.y) * (0.55 + 0.45 * fine) * (0.8 + 0.2 * g);
	float base = 1.0 - smoothstep(0.0, 0.25, world_y);
	col = mix(col, vec3(0.74, 0.44, 0.27), clamp(top * dust + base * dust * 0.6, 0.0, 0.6));

	ALBEDO = col;
	METALLIC = metallic;
	ROUGHNESS = clamp(roughness + lines * 0.15 + (g - 0.5) * 0.15 + crinkle * (fine - 0.5) * 0.4, 0.05, 1.0);
}
