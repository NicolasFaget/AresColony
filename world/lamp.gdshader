shader_type spatial;
// Lampe, hublot ou voyant : couleur propre et lueur, plus forte la nuit (`night_glow`, commun à
// toute la scène). Un module à l'arrêt reçoit la variante éteinte du matériau (`off`). Pas de
// paramètre par objet : le moteur OpenGL des téléphones modestes n'en accepte que peu.
// Les balises rouges clignotent, chacune à son rythme.

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform bool blink = false;
uniform bool off = false;
global uniform float night_glow;

void fragment() {
	float on = off ? 0.08 : 1.0 + 1.3 * night_glow;
	if (blink) {
		float phase = fract(TIME * 0.6 + NODE_POSITION_WORLD.x * 0.37 + NODE_POSITION_WORLD.z * 0.21);
		on *= 0.12 + 0.88 * step(0.6, phase);
	}
	ALBEDO = color.rgb * mix(0.3, 1.0, clamp(on, 0.0, 1.0));
	EMISSION = color.rgb * energy * on;
	ROUGHNESS = 0.5;
}
