// STADTSTRASSEN (scripts/Stadtstrassen.gd): Fahrbahn, Bordstein, Gehweg und Markierung aus
// EINEM Band. Stil Zelda/Ghibli wie Gelaende und Haeuser: klare Flaechen, weiches Licht,
// keine Rauschtextur.
//
//   UV.x     Abstand von der Strassenachse in Metern (mit Vorzeichen)
//   UV.y     Laufmeter ab Bandanfang
//   UV2      Abstand zur Einmuendung am Anfang / am Ende des Bands (1e4 = keine)
//   CUSTOM0  (halbe Fahrbahnbreite, Gehwegbreite, Art, Markierung an)
//
// Arten: 0 Gasse (Pflaster), 1 Strasse, 2 Boulevard (vier Spuren), 3 Weg (Schotter),
//        4 Dorfstrasse, 5 Landstrasse (wie shaders/strasse.gdshader).
// Kreuzungsflaechen kommen als eigene Dreiecke: Asphalt mit halber Breite 1000 (immer
// Fahrbahn), Gehwegecken mit halber Breite 0 und UV.x = Abstand vom Bordstein.
//
// Alle Linien werden ueber fwidth ausgeblendet, sobald sie schmaler als ein Bildpunkt sind —
// sonst flimmern sie aus der Hoehe (wie bei den Landstrassen). Der Zebrastreifen wird in der
// Ferne zu einer halbhellen Flaeche statt zu verschwinden: so bleibt die Kreuzung lesbar.
shader_type spatial;

#include "res://shaders/palette.gdshaderinc"

varying vec4 dat;

const vec3 ASPHALT = vec3(0.35, 0.35, 0.37);
const vec3 ASPHALT_DORF = vec3(0.46, 0.44, 0.41);   // heller, warm: Dorfstrasse
const vec3 ASPHALT_TIEF = vec3(0.30, 0.30, 0.325);
const vec3 PFLASTER = vec3(0.52, 0.47, 0.41);
const vec3 GEHWEG = vec3(0.67, 0.65, 0.61);
const vec3 BORDSTEIN = vec3(0.82, 0.80, 0.75);
const vec3 LINIE = vec3(0.92, 0.91, 0.86);
const vec3 SCHOTTER = vec3(0.58, 0.53, 0.43);
const vec3 SPUR = vec3(0.47, 0.42, 0.34);

void vertex() {
	dat = CUSTOM0;
}

// Linie der halben Breite b um m (in Metern quer), kantengeglaettet und ausgeblendet, wenn
// sie schmaler als ein Bildpunkt wird.
float linie(float x, float m, float b, float fw) {
	float sichtbar = clamp(b / fw - 0.3, 0.0, 1.0);
	return (1.0 - smoothstep(b - fw, b + fw, abs(x - m))) * sichtbar;
}

void fragment() {
	float x = UV.x;
	float ax = abs(x);
	float v = UV.y;
	float hc = dat.x;
	float geh = dat.y;
	int art = int(dat.z + 0.5);
	float fw = max(fwidth(x), 1e-4);
	float fv = max(fwidth(v), 1e-4);
	float nah = min(UV2.x, UV2.y);

	vec3 c = ASPHALT;
	if (art == 0) {
		c = PFLASTER;
		// Rinne in der Mitte der Gasse: ein Hauch dunkler
		c *= 1.0 - 0.10 * linie(x, 0.0, 0.22, fw);
	} else if (art == 2) {
		c = ASPHALT_TIEF;
	} else if (art == 4) {
		c = ASPHALT_DORF;
	} else if (art == 3) {
		c = SCHOTTER;
		// zwei Fahrspuren, Grasnarbe in der Mitte und an den Raendern
		c = mix(c, SPUR, linie(ax, hc * 0.45, 0.32, fw) * 0.8);
		c = mix(c, GRAS_MITTE, linie(x, 0.0, 0.22, fw) * 0.55);
		c = mix(c, GRAS_MITTE, smoothstep(hc - 0.35, hc, ax) * 0.55);
	}
	// Rinnstein: die Fahrbahn wird zum Bordstein hin etwas dunkler (gibt der Flaeche Form)
	if (art == 1 || art == 2) {
		c *= 1.0 - 0.10 * smoothstep(hc - 1.0, hc, ax) * step(ax, hc);
	}

	float m = 0.0;
	if (dat.w > 0.5) {
		// im Kreuzungsbereich keine Laengsmarkierung
		float frei = smoothstep(6.5, 7.5, nah);
		float strich = step(0.56, fract(v / 9.0));
		if (art == 1) {
			m = linie(x, 0.0, 0.07, fw) * strich * frei;
		} else if (art == 2) {
			m = linie(ax, 0.17, 0.065, fw) * frei;                       // doppelte Mittellinie
			m = max(m, linie(ax, hc * 0.5 + 0.1, 0.065, fw) * strich * frei);   // Spurtrenner
		} else if (art == 5) {
			// Masse wie shaders/strasse.gdshader (Landstrassenband)
			m = linie(x, 0.0, 0.115, fw) * step(0.45, fract(v / 12.0)) * frei;
			m = max(m, linie(ax, hc - 0.43, 0.13, fw));                  // Randlinien
		}
		// ZEBRASTREIFEN vor jeder Einmuendung: Balken laengs der Fahrtrichtung, 0,5 m breit.
		if (art == 1 || art == 2) {
			float im = smoothstep(1.3 - fv, 1.3 + fv, nah) * (1.0 - smoothstep(4.8 - fv, 4.8 + fv, nah));
			float balken = 1.0 - smoothstep(0.25 - fw, 0.25 + fw, abs(fract(x) - 0.5));
			float scharf = clamp(0.25 / fw - 0.3, 0.0, 1.0);
			float zebra = mix(0.5, balken, scharf) * im * step(ax, hc - 0.35);
			m = max(m, zebra);
			// Haltelinie davor
			m = max(m, (1.0 - smoothstep(0.2 - fv, 0.2 + fv, abs(nah - 6.0)))
				* clamp(0.2 / fv - 0.3, 0.0, 1.0) * step(ax, hc - 0.35) * 0.85);
		}
	}
	c = mix(c, LINIE, m);

	if (geh > 0.05) {
		// Bordstein (0,3 m, hell) und Gehweg
		float bord = (1.0 - smoothstep(hc + 0.30 - fw, hc + 0.30 + fw, ax)) * clamp(0.15 / fw - 0.3, 0.0, 1.0);
		vec3 g = mix(GEHWEG, BORDSTEIN, bord);
		c = mix(c, g, smoothstep(hc - fw, hc + fw, ax));
	} else if (art == 4 || art == 5) {
		// Bankett: schmaler Schotterrand
		c = mix(c, SCHOTTER * 0.9, smoothstep(hc - 0.32, hc - 0.12, ax));
	}
	ALBEDO = srgb_linear(c);
	ROUGHNESS = 0.92;
}

void light() {
	DIFFUSE_LIGHT += klares_licht(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, mat3(INV_VIEW_MATRIX) * LIGHT);
}
