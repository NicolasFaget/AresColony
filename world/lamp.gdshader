shader_type spatial;
// Lampe, hublot ou voyant : couleur propre et lueur. Chaque module règle sa lueur (`lit`) : éteinte
// quand il est à l'arrêt, plus forte la nuit. Les balises rouges clignotent, chacune à son rythme.

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform bool blink = false;
instance uniform float lit = 1.0;

void fragment() {
	float on = clamp(lit, 0.0, 3.0);
	if (blink) {
		float phase = fract(TIME * 0.6 + NODE_POSITION_WORLD.x * 0.37 + NODE_POSITION_WORLD.z * 0.21);
		on *= 0.12 + 0.88 * step(0.6, phase);
	}
	ALBEDO = color.rgb * mix(0.3, 1.0, clamp(on, 0.0, 1.0));
	EMISSION = color.rgb * energy * on;
	ROUGHNESS = 0.5;
}
