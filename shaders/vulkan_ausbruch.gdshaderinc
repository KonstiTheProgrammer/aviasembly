// AUSBRUCH: gemeinsame Bahnrechnung der LAVABOMBEN (scripts/Vulkanausbruch.gd, 2026-10-03, Nutzer:
// „mach noch krasser“). Bomben (vulkan_bomben.gdshader) und ihre Rauchspuren (vulkan_rauch.gdshader)
// rechnen dieselbe Bahn aus der Bombennummer — keine Partikelsimulation, kein Zustand: alles haengt
// an `stoss_alter` (Sekunden seit diesem Ausbruch, je Frame aus Vulkanausbruch._process; zwei
// Fassungen im Wechsel, damit ein neuer Ausbruch die Bomben des vorigen nicht wegreisst). Damit liegt
// die Rauchspur GENAU auf der Bahn ihrer Bombe, auch nach dem Aufschlag, und ein Bildwerkzeug kann
// jeden Augenblick des Ausbruchs einfrieren.
// BAHN MIT LINEARER LUFTREIBUNG: geschlossen loesbar (x(t) = Endtempo·t + (v0 − Endtempo)(1 − e^−kt)/k),
// sieht aber anders aus als die reine Parabel — die Bomben werden oben langsam und fallen steiler.
// AUFSCHLAG: das Gelaende des Kegels steht als RADIALES PROFIL in `vb_profil` (Mittel ueber 16
// Richtungen, Vulkanausbruch._profil) — die Bombe landet an der ersten Stelle ihrer Bahn unter dem
// Profil (24 Schritte, dann 6-mal halbiert) und glueht dort aus.
uniform float stoss_alter = 10000.0;
uniform vec3 schlot = vec3(0.0);
uniform vec2 wind = vec2(1.0, 0.0);
uniform float vb_profil[16];
uniform float vb_profil_r = 2400.0;      // Radius des letzten Profilpunkts (m)
uniform float rand_tiefe = 330.0;        // Kraterrand ueber dem Seespiegel

const float VB_ZAEH = 0.055;             // lineare Reibung (1/s): Endtempo 178 m/s
const float VB_WIND = 7.0;               // m/s seitlicher Wind auf den Bomben

float vb_hash(float n) {
	uint h = uint(int(n) + 7919) * 2654435761u;
	h ^= h >> 15u;
	h *= 2246822519u;
	h ^= h >> 13u;
	h *= 3266489917u;
	h ^= h >> 16u;
	return float(h >> 8u) * (1.0 / 16777216.0);
}

// Startwerte der Bombe b: Anfangsgeschwindigkeit, Verzug (die Bomben kommen in einem Schwall von
// anderthalb Sekunden), Groesse (Halbmesser des Leuchtens, m).
void vb_start(float b, out vec3 v0, out float verzug, out float gr) {
	float h1 = vb_hash(b * 5.0 + 1.0);
	float h2 = vb_hash(b * 5.0 + 2.0);
	float h3 = vb_hash(b * 5.0 + 3.0);
	float h4 = vb_hash(b * 5.0 + 4.0);
	float h5 = vb_hash(b * 5.0 + 5.0);
	float az = h1 * 6.2831853;
	// Kegel um die Senkrechte, nach aussen duenner besetzt; die schnellen fliegen steiler
	float k = 0.80 * sqrt(h2) * mix(1.0, 0.65, h3);
	float tempo = mix(55.0, 190.0, h3);
	v0 = vec3(sin(k) * cos(az), cos(k), sin(k) * sin(az)) * tempo;
	verzug = h4 * h4 * 1.6;
	gr = mix(2.4, 9.0, h5 * h5);
}

vec3 vb_ort(vec3 v0, float t) {
	vec3 ende = vec3(wind.x * VB_WIND, -9.81 / VB_ZAEH, wind.y * VB_WIND);
	float e = 1.0 - exp(-VB_ZAEH * t);
	return schlot + ende * t + (v0 - ende) * e / VB_ZAEH;
}

vec3 vb_tempo(vec3 v0, float t) {
	vec3 ende = vec3(wind.x * VB_WIND, -9.81 / VB_ZAEH, wind.y * VB_WIND);
	return ende + (v0 - ende) * exp(-VB_ZAEH * t);
}

float vb_boden(vec2 xz) {
	float u = clamp(distance(xz, schlot.xz) / vb_profil_r, 0.0, 1.0) * 15.0;
	int i = min(int(u), 14);
	return mix(vb_profil[i], vb_profil[i + 1], u - float(i));
}

// Erste Zeit, zu der die Bombe unter dem Gelaende ist (bis 34 s), sonst 1e6.
float vb_landung(vec3 v0) {
	const float DT = 34.0 / 24.0;
	for (int i = 1; i <= 24; i++) {
		float t = float(i) * DT;
		vec3 p = vb_ort(v0, t);
		if (p.y < vb_boden(p.xz)) {
			float a = t - DT;
			float b = t;
			for (int j = 0; j < 6; j++) {
				float m = (a + b) * 0.5;
				vec3 pm = vb_ort(v0, m);
				if (pm.y < vb_boden(pm.xz)) {
					b = m;
				} else {
					a = m;
				}
			}
			return b;
		}
	}
	return 1.0e6;
}
