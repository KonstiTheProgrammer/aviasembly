shader_type spatial;
// HAEUSER IM LICHT DER WELT (Stil Zelda/Ghibli). Die Bauten aus world_buildings*.glb trugen
// Godots Standardmaterial: hartes Lambert-Licht, Schattenseiten fast schwarz — neben dem
// gemalten Licht von Gelaende und Baeumen (weiches_licht) standen sie wie aus einem anderen
// Spiel in der Landschaft. CityBuilder tauscht deshalb jedes Material gegen dieses hier.
//
//  * Licht: derselbe weiche Uebergang wie Gelaende und Flora (palette.gdshaderinc).
//  * Farbe: Materialfarbe mal VERTEXFARBE — der gemalte Verlauf aus
//    tools/build_haeuser_blend.py (_verlauf: Waende unten dunkler, Daecher zum First heller).
//  * Schattenseite: kuehle Himmelsfuellung (EMISSION = Albedo x Blauton), kein Schwarz.
//  * FALLE: das Farb-Uniform darf NICHT `farbe` heissen — so heisst ein Parameter von
//    weiches_licht() im Include; mit gleichem Namen kam bei den Haeusern kein Sonnenlicht
//    mehr an (helle Waende fielen nicht auf, Daecher und die Burg standen schwarz da).
//
// EIGENE MATERIALIEN (2026-10-02, Nutzer: „mach die Stadt und die Doerfer viel besser, kannst
// auch eigene Materialien machen“). Aus der Naehe waren die Haeuser reine Farbflaechen (Plastik),
// die Fenster schwarze Loecher. Die Modelle tragen keine UVs — jedes Muster entsteht aus der
// WELTLAGE in einem Rahmen der Flaeche: t = waagerecht in der Flaeche, b = in der Flaeche nach
// oben (an Waenden senkrecht, an Daechern die Fallinie hinauf). `art` setzt CityBuilder._malen
// aus dem Materialnamen (H_dach_rot -> Ziegel, H_wand_* -> Putz, ...). Alle Muster gehen ueber
// fwidth in ihr Mittel, sobald sie kleiner als ein paar Bildpunkte werden (kein Flimmern aus
// der Hoehe, und die Fernstufe der Haeuser sieht aus wie vorher).
#include "res://shaders/palette.gdshaderinc"

uniform vec3 haus_farbe : source_color = vec3(0.8, 0.8, 0.8);
uniform float rauheit : hint_range(0.0, 1.0) = 0.9;
uniform float metall : hint_range(0.0, 1.0) = 0.0;
// 0 glatt, 1 Ziegeldach, 2 Schiefer, 3 Stroh/Reet, 4 Kupfer/Blech (Stehfalz), 5 Putz,
// 6 Backstein, 7 Holz (Bretter), 8 Glas/Fenster, 9 Naturstein, 10 Beton
uniform int art = 0;

// HIMMELSFUELLUNG: kuehles Streulicht, das auch die Schattenseite erreicht. Ohne sie standen
// abgewandte Waende und Dachflaechen fast schwarz da (das Umgebungslicht der Welt ist fuer
// senkrechte, dunkle Flaechen zu schwach) — gemalte Schatten sind blau, nicht schwarz.
uniform float fuellung = 0.26;
const vec3 FUELL_TON = vec3(0.60, 0.72, 0.95);

varying vec3 w_pos;
varying vec3 w_nrm;
varying float fuss_y;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = mat3(MODEL_MATRIX) * NORMAL;
	fuss_y = MODEL_MATRIX[3].y;
}

float h21(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(32768));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 15u)) * 2246822519u;
	h ^= h >> 13u;
	return float(h >> 8u) * (1.0 / 16777216.0);
}

// weiches Wertrauschen 0..1
float rauschen(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

// Fuge der Breite bf (m) an den Zellgrenzen von x (Zellmass m): 1 in der Fuge; in der Ferne Mittel.
float fuge(float x, float m, float bf, float fw) {
	float d = abs(fract(x / m + 0.5) - 0.5) * m;
	float l = 1.0 - smoothstep(bf * 0.5 - fw * 0.5, bf * 0.5 + fw * 0.5, d);
	return mix(bf / m, l, clamp(1.5 - fw / bf, 0.0, 1.0));
}

vec3 lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	vec3 c = haus_farbe * COLOR.rgb;
	float rau = rauheit;
	vec3 n = normalize(w_nrm);
	vec3 t = cross(vec3(0.0, 1.0, 0.0), n);
	t = length(t) < 0.05 ? vec3(1.0, 0.0, 0.0) : normalize(t);
	vec3 b = normalize(cross(n, t));
	float u = dot(w_pos, t);
	float v = dot(w_pos, b);
	// je Richtung: unter flachem Blick ist eine Richtung stark gestaucht — mit dem groesseren Wert
	// fuer beide verschwand das Muster ganzer Dachflaechen (gerade die, auf die man von der Strasse
	// aus schaut)
	float fwu = max(fwidth(u), 1.0e-4);
	float fwv = max(fwidth(v), 1.0e-4);
	float fw = max(fwu, fwv);
	vec3 nd = vec3(0.0);               // Normalenstoerung in Weltlage (t/b-Anteile)
	// Aus der Ferne (mehr als 0,6 m je Bildpunkt) sind alle Muster in ihrem Mittel — nicht rechnen
	// (gemessen: die Fernstufe der Grossstadt kostete mit den Mustern +0,25 ms in 4K)
	int a = (fw > 0.6 && art != 8) ? 0 : art;
	vec3 emi = vec3(0.0);
	float hoch = w_pos.y - fuss_y;     // Hoehe ueber dem Hausfuss
	if (a == 1 || a == 2) {
		// ZIEGEL- bzw. SCHIEFERDACH: Reihen die Fallinie hinauf, je Reihe versetzt, die
		// Unterkante jeder Reihe liegt ueber der naechsten (heller Saum, Schatten darunter)
		float rh = a == 1 ? 0.34 : 0.24;
		float bw = a == 1 ? 0.27 : 0.24;
		float sicht = clamp(1.6 - fwv / (rh * 0.25), 0.0, 1.0);
		float sicht_u = clamp(1.6 - fwu / (bw * 0.25), 0.0, 1.0);
		float reihe = floor(v / rh);
		float fv = fract(v / rh);
		float uu = u + bw * 0.5 * mod(reihe, 2.0);
		vec2 zelle = vec2(floor(uu / bw), reihe);
		float ton = h21(zelle);
		float var_t = a == 1 ? 0.84 + 0.30 * ton : 0.80 + 0.36 * ton;
		float schatten = smoothstep(0.55, 1.0, fv);          // oben in der Reihe: unter der naechsten
		float saum = 1.0 - smoothstep(0.0, 0.12, fv);         // Unterkante: im Licht
		float seiten = a == 1 ? 0.5 + 0.5 * cos(fract(uu / bw) * 6.2831853) : fuge(uu, bw, 0.02, fwu);
		var_t = mix(1.0, var_t, sicht_u);
		float k = var_t * (1.0 - 0.32 * schatten + 0.10 * saum);
		if (a == 1) {
			k *= 1.0 + (0.10 * seiten - 0.05) * sicht_u;      // Pfannenwoelbung
			nd += t * sin(fract(uu / bw) * 6.2831853) * 0.35 * sicht_u;
		} else {
			k *= 1.0 - 0.35 * seiten * sicht_u;               // Fuge zwischen den Platten
			c = mix(c, c * vec3(0.92, 0.97, 1.08), ton * 0.5);
		}
		nd += b * (schatten * 0.55 - saum * 0.25);
		// Alterung: Flechten und Moos (grosse weiche Flecken)
		float alt = rauschen(vec2(u, v) * 0.35);
		k *= 0.92 + 0.12 * alt;
		c *= mix(1.0, k, sicht);
		nd *= sicht;
	} else if (a == 3) {
		// STROH/REET: dicke Lagen, feine Halme die Fallinie hinab
		float sicht = clamp(1.6 - fw / 0.12, 0.0, 1.0);
		float lage = fract(v / 0.55);
		float halm = h21(vec2(floor(u / 0.045), floor(v / 0.55)));
		float k = (0.86 + 0.22 * halm) * (1.0 - 0.28 * smoothstep(0.6, 1.0, lage))
			* (0.90 + 0.15 * rauschen(vec2(u, v) * 0.5));
		c *= mix(1.0, k, sicht);
		nd += b * smoothstep(0.6, 1.0, lage) * 0.5 * sicht;
	} else if (a == 4) {
		// KUPFER/PATINA/BLECH: Stehfalze die Fallinie hinauf alle 0,55 m, Patina fleckig
		float sicht = clamp(1.6 - fw / 0.05, 0.0, 1.0);
		float falz = fuge(u, 0.55, 0.05, fw);
		float flecken = rauschen(vec2(u, v) * 0.6) * 0.6 + rauschen(vec2(u, v) * 2.2) * 0.4;
		c *= mix(1.0, (0.88 + 0.22 * flecken) * (1.0 + 0.25 * falz), sicht);
		nd += t * (fuge(u - 0.02, 0.55, 0.04, fw) - fuge(u + 0.02, 0.55, 0.04, fw)) * 0.6 * sicht;
	} else if (a == 5) {
		// PUTZ: grosse weiche Flecken, feine Koernung, Spritzwasser am Sockel, Regenspuren
		float gross = rauschen(vec2(u, v) * 0.22) * 0.65 + rauschen(vec2(u, v) * 0.9) * 0.35;
		float korn = h21(vec2(u, v) * 22.0);
		float sicht_k = clamp(1.6 - fw / 0.05, 0.0, 1.0);
		float k = 0.93 + 0.11 * gross + (korn - 0.5) * 0.05 * sicht_k;
		float sockel = 1.0 - smoothstep(0.15, 0.85, hoch);
		float regen = rauschen(vec2(u * 1.6, v * 0.08)) * smoothstep(0.6, 3.0, hoch);
		k *= 1.0 - 0.18 * sockel - 0.06 * regen;
		c *= k;
		c = mix(c, c * vec3(0.92, 0.94, 0.86), sockel * 0.5);   // gruenlich-erdig am Fuss
	} else if (a == 6) {
		// BACKSTEIN: Laeufer 0,25 x 0,075 m, jede zweite Schicht versetzt, helle Fugen
		float sicht = clamp(1.6 - fw / 0.02, 0.0, 1.0);
		float sch = floor(v / 0.0833);
		float uu = u + 0.13 * mod(sch, 2.0);
		float ton = h21(vec2(floor(uu / 0.26), sch));
		float f = max(fuge(v, 0.0833, 0.011, fw), fuge(uu, 0.26, 0.011, fw));
		vec3 stein = c * (0.82 + 0.32 * ton) * mix(vec3(1.0), vec3(1.05, 0.95, 0.92), step(0.8, ton));
		vec3 fug = lin(vec3(0.74, 0.71, 0.66));
		vec3 grob = c * 0.96;                                  // Mittel in der Ferne
		c = mix(grob, mix(stein, fug, f), sicht);
		c *= 1.0 - 0.12 * (1.0 - smoothstep(0.15, 0.8, hoch));
	} else if (a == 7) {
		// HOLZ: senkrechte Bretter 0,18 m (an Waenden; waagerechte Teile laengs), dunkle Fugen,
		// Maserung entlang des Bretts
		float sicht = clamp(1.6 - fw / 0.03, 0.0, 1.0);
		float brett = floor(u / 0.18);
		float ton = h21(vec2(brett, 7.0));
		float maser = rauschen(vec2(u * 30.0, v * 1.2 + brett * 3.1));
		float f = fuge(u, 0.18, 0.018, fw);
		float k = (0.84 + 0.28 * ton) * (0.92 + 0.14 * maser) * (1.0 - 0.45 * f);
		c *= mix(0.97, k, sicht);
		nd += t * (fuge(u - 0.01, 0.18, 0.01, fw) - fuge(u + 0.01, 0.18, 0.01, fw)) * 0.5 * sicht;
	} else if (a == 8) {
		// GLAS UND FENSTER: Spiegelung des Himmels (Fresnel), dahinter ein Raum mit weichem Licht
		// statt schwarzer Loecher. Keine Zellen: die Fensterflaechen der Modelle sind mal ein
		// Fenster, mal ein ganzes Fensterband — ein festes Raster lag darauf als Pixelmuster.
		vec3 blick = normalize(CAMERA_POSITION_WORLD - w_pos);
		vec3 r = reflect(-blick, n);
		vec3 himmel = mix(vec3(0.78, 0.85, 0.93), vec3(0.34, 0.54, 0.86), smoothstep(0.0, 0.7, r.y));
		himmel = mix(vec3(0.30, 0.34, 0.30), himmel, smoothstep(-0.08, 0.04, r.y));   // Boden (sRGB)
		float fres = 0.06 + 0.94 * pow(1.0 - clamp(dot(n, blick), 0.0, 1.0), 5.0);
		float hz = rauschen(vec2(u, v) * 0.35);
		vec3 raum = c * 0.6 + lin(vec3(0.20, 0.17, 0.14)) * (0.6 + 0.8 * hz);
		c = raum * (1.0 - fres * 0.7);
		emi += lin(himmel) * (0.05 + fres * 0.28);
		rau = 0.15;
	} else if (a == 9) {
		// NATURSTEIN: Quader 0,9 x 0,45 m, unregelmaessige Laenge, Fugen
		float sicht = clamp(1.6 - fw / 0.05, 0.0, 1.0);
		float sch = floor(v / 0.45);
		float l = 0.7 + 0.5 * h21(vec2(sch, 2.0));
		float uu = u + l * 0.5 * mod(sch, 2.0);
		float ton = h21(vec2(floor(uu / l), sch));
		float f = max(fuge(v, 0.45, 0.04, fw), fuge(uu, l, 0.04, fw));
		c *= mix(0.97, (0.84 + 0.26 * ton) * (1.0 - 0.32 * f), sicht);
	} else if (a == 10) {
		// BETON: Plattenfugen 3 x 1,5 m, Flecken
		float f = max(fuge(u, 3.0, 0.03, fw), fuge(v, 1.5, 0.03, fw));
		float flecken = rauschen(vec2(u, v) * 0.4);
		c *= (0.92 + 0.12 * flecken) * (1.0 - 0.25 * f);
	}
	ALBEDO = c;
	ROUGHNESS = rau;
	METALLIC = art == 8 ? 0.0 : metall;
	if (dot(nd, nd) > 0.0) {
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n + nd), 0.0)).xyz);
	}
	EMISSION = ALBEDO * FUELL_TON * fuellung * (1.0 - METALLIC) + emi;
}

void light() {
	DIFFUSE_LIGHT += weiches_licht(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
	float glatt = 1.0 - ROUGHNESS;
	if (glatt > 0.5) {
		float nh = max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * pow(nh, 120.0) * glatt * 1.6;
	}
}
