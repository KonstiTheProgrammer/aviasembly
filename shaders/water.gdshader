// Aviassembly-Wasser — EIN Shader fuer Meer, Inlandseen und Fluesse.
//
// ALLES RECHNET IN WELTMETERN.
//
// Vorher liefen die Wellen auf der UV der Wasserplatte. Die Platte ist 9120 m gross
// (TerrainWorld.VIEW_DIST * 2.4), also wurden aus wave_scale = 6 rund 1520 m
// WELLENLAENGE und aus wave_speed = 0.35 rund 1915 m/s Musterbewegung. Zusaetzlich
// klebte das Muster am Mesh, und TerrainWorld.update_center schiebt dieses Mesh jeden
// Frame auf den Spieler — das gesamte Wellenfeld flog also mit dem Flugzeug mit. Beides
// zusammen ergab eine Oberflaeche, die aus 40 m Hoehe optisch stillstand.
//
// Jetzt wird die WELTPOSITION des Fragments abgetastet (INV_VIEW_MATRIX * VERTEX). Das
// Muster steht damit in der Welt, egal wohin die Platte geschoben wird, und jede
// Wellenlaenge/Geschwindigkeit unten ist eine echte Meter- bzw. m/s-Angabe.
//
// WASSERTIEFE wird SENKRECHT gemessen (Differenz der Welt-Y von Oberflaeche und Grund),
// nicht als Strahllaenge Kamera->Grund. Die Strahllaenge waechst mit flacherem
// Blickwinkel, dadurch war der Ufersaum vorher blickwinkelabhaengig breit.
//
// FRESNEL: bei flachem Blick geht der Reflexionsgrad gegen 1, das Wasser wird zum
// Spiegel. Der reflektierte Himmel liegt in EMISSION (Reflexion ist Licht, sie darf
// nicht noch einmal beleuchtet werden), das durchscheinende Wasser in ALBEDO. Die
// Himmelsfarben unten sind dieselben wie in shaders/sky_clouds.gdshader.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

// --- Farbe nach senkrechter Wassertiefe ---------------------------------------------
uniform vec3 shallow_col : source_color = vec3(0.32, 0.80, 0.78);   // Ufer-Tuerkis
uniform vec3 mid_col     : source_color = vec3(0.15, 0.55, 0.68);   // Lagune
uniform vec3 deep_col    : source_color = vec3(0.06, 0.29, 0.55);   // Ozean-Blau
uniform vec3 foam_col    : source_color = vec3(0.86, 0.89, 0.92);
uniform float depth_fade = 18.0;     // Tiefe (m), ueber die shallow -> deep blendet
uniform float foam_band  = 1.2;      // Schaum bis zu dieser senkrechten Tiefe (m)
// Breite des Randstreifens, in dem die Tiefenkorrektur ausblendet (Bildanteil, siehe
// welt_zu_uv). Breiter = weicher, greift aber weiter ins Bild hinein.
uniform float rand_blend : hint_range(0.01, 0.3) = 0.06;
// UNTER dieser Tiefe blendet die Wasserflaeche auf durchsichtig aus. Ohne das endet
// jedes Wassermesh an seiner Mesh-Kante mit voller Deckkraft — beim Meer faellt das
// nicht auf (die Platte reicht ueber den Horizont), beim Inlandsee stand dadurch ein
// weisser Schaumring auf der Wiese. Mit der Ausblendung ist die Uferlinie immer da,
// wo die Wassertiefe null wird, egal wie das Mesh geschnitten ist.
uniform float waterline = 0.30;      // m
// Wie stark der Saum aufhellt. Am Meer ist das Brandungsgischt und darf kraeftig sein;
// ein Binnensee hat keine Brandung, dort waere ein weisser Ring schlicht falsch.
uniform float foam_strength : hint_range(0.0, 1.0) = 0.7;

// --- Wellen: Laengen in METERN, Geschwindigkeiten in METERN JE SEKUNDE ---------------
// Drei Oktaven. Die Duenung traegt die grosse Form, der Chop die sichtbare Bewegung,
// die Kraeuselung das Glitzern aus geringer Flughoehe.
uniform vec2  wind_dir = vec2(0.80, 0.60);
// Die Geschwindigkeiten sind KEINE freien Regler, sondern die Phasengeschwindigkeit
// der jeweiligen Wellenlaenge in tiefem Wasser: c = sqrt(g * L / 2pi).
// 58 m -> 9.52 m/s, 13 m -> 4.51 m/s, 3.4 m -> 2.30 m/s. Mit frei geschaetzten
// Werten (erst 4.2/1.9/0.85) bewegte sich in 0,084 s nur ein Fuenfzigstel einer
// Periode und das Meer sah aus wie ein Standbild.
uniform float swell_len   = 58.0;    // m
uniform float swell_amp   = 0.55;    // m
uniform float swell_speed = 9.52;    // m/s
uniform float chop_len    = 13.0;
uniform float chop_amp    = 0.22;
uniform float chop_speed  = 4.51;
uniform float ripple_len  = 3.4;
uniform float ripple_amp  = 0.055;
uniform float ripple_speed = 2.30;
// Die Flaeche ist in dieser Runde GEOMETRISCH FLACH (keine Gerstner-Verformung). Die
// Normale kommt allein aus dem Hoehenfeld; der Faktor uebertreibt sie, damit die
// Kraeuselung ueberhaupt Licht faengt. Das ist der Platzhalter fuer Runde 2.
uniform float slope_gain = 3.0;
// Detail nach Entfernung ausblenden — sonst flimmert das Meer ab ein paar hundert
// Metern (Wellenlaenge faellt unter die Pixelbreite).
uniform float ripple_fade = 320.0;   // m: hier ist die Kraeuselung weg
uniform float chop_fade   = 1600.0;  // m: hier ist der Chop weg

// --- Fresnel / Himmelsspiegelung ----------------------------------------------------
uniform vec3 sky_horizon : source_color = vec3(0.60, 0.73, 0.88);  // wie sky_clouds
uniform vec3 sky_zenith  : source_color = vec3(0.24, 0.49, 0.86);
uniform vec3 sun_col     : source_color = vec3(1.0, 0.97, 0.90);
uniform vec3 sun_dir = vec3(0.55, 0.62, 0.55);   // wie sky_clouds.sun_dir
uniform float fresnel_f0 : hint_range(0.0, 0.2) = 0.02;   // Wasser, senkrechter Blick
uniform float sky_strength : hint_range(0.0, 2.0) = 1.0;
uniform float glint_strength : hint_range(0.0, 8.0) = 1.0;

// --- Angleichung an die Weltkante ---------------------------------------------------
// Die Wasserplatte endet 4560 m vom Spieler entfernt. shaders/sky_clouds.gdshader
// faerbt den Himmel unter dem Horizont in col_deep ein, GEMESSEN kalibriert auf den
// Bildwert des fernsten Wassers — sonst steht dort eine "Tischplatten"-Kante quer
// durchs Bild. Der Fresnel-Term macht fernes Wasser deutlich heller (flacher Blick =
// Spiegel), also wuerde diese Kalibrierung brechen. Deshalb laeuft das Wasser ueber
// die letzten Kilometer selbst in genau diesen Ton — Luftperspektive im Shader.
// far_col MUSS mit sky_clouds.col_deep uebereinstimmen.
uniform vec3 far_col : source_color = vec3(0.0, 0.233, 0.440);
// far_start/far_end und far_col sind GEMESSEN eingestellt (tools/_wasser_ap_d.gd,
// Messung D): am Plattenrand muss der Bildwert des Wassers dem des Himmelsbands
// entsprechen. far_col ist NICHT gleich sky_clouds.col_deep — zwischen beiden liegt der
// Nebel, der das Wasser auf 4,5 km um rund ein Viertel Richtung fog_light_color hebt,
// den Himmel wegen fog_sky_affect 0.1 aber kaum.
uniform float far_start = 1200.0;
uniform float far_end   = 4400.0;

// --- Deckkraft ----------------------------------------------------------------------
uniform float alpha_shallow : hint_range(0.0, 1.0) = 0.72;
uniform float alpha_deep    : hint_range(0.0, 1.0) = 0.96;

vec2 rot2(vec2 p, float a){ float s=sin(a), c=cos(a); return vec2(c*p.x-s*p.y, s*p.x+c*p.y); }
float hash(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){ vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	float a=hash(i),b=hash(i+vec2(1,0)),c=hash(i+vec2(0,1)),d=hash(i+vec2(1,1));
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y); }

// Wasserhoehe (m) ueber der Ruhelage an der Weltposition p (m). Eine Oktave wandert mit
// speed/len Perioden je Sekunde: das Argument p/len - dir*(speed*TIME/len) haelt einen
// festen Musterpunkt bei p = dir*speed*TIME, also exakt speed Meter je Sekunde.
float wave_h(vec2 p, float rip, float chp) {
	vec2 w = normalize(wind_dir);
	vec2 q = vec2(-w.y, w.x);
	float t = TIME;
	// Jede Oktave bekommt ihr eigenes GEDREHTES Gitter (rot2). vnoise sitzt auf einem
	// achsenparallelen Raster; ohne die Drehung liegen alle drei Oktaven auf demselben
	// Gitter und das Meer bekommt ein sichtbares Nord-Sued-Streifenmuster. Weil rot2
	// linear ist, darf die Drehung erst auf das fertige Argument.
	vec2 cd = normalize(w * 0.75 + q * 0.66);
	float h = swell_amp * (vnoise(rot2(p / swell_len - w * (swell_speed * t / swell_len), 0.7)) - 0.5);
	h += chp * chop_amp * (vnoise(rot2(p / chop_len - cd * (chop_speed * t / chop_len), 2.3)) - 0.5);
	h += rip * ripple_amp * (vnoise(rot2(p / ripple_len + q * (ripple_speed * t / ripple_len), 4.1)) - 0.5);
	return h;
}

// Grund-Weltposition an einer Bildschirmkoordinate.
// Die Matrizen kommen als Parameter: Godots eingebaute Groessen sind lokal in der
// erzeugten main()-Funktion und in eigenen Funktionen NICHT sichtbar.
//
// hat_grund meldet, ob an der Stelle ueberhaupt Geometrie steht. Auf der Fernebene ist
// der Tiefenpuffer leer (Himmel) und der rekonstruierte Punkt liegt kilometerweit weg —
// ihn als "Grund" zu nehmen liefert Unsinn. Der Test deckt beide Z-Konventionen ab
// (Forward+ rechnet umgekehrt, Fernebene = 0).
vec3 grund_welt(vec2 uv, sampler2D dtex, mat4 inv_proj, mat4 inv_view, out bool hat_grund) {
	float dz = texture(dtex, uv).x;
	hat_grund = dz > 0.0 && dz < 1.0;
	vec4 v = inv_proj * vec4(vec3(uv * 2.0 - 1.0, dz), 1.0);
	return (inv_view * vec4(v.xyz / v.w, 1.0)).xyz;
}

// Weltpunkt zurueck auf Bildschirmkoordinaten, mit einem Gewicht dafuer, wie brauchbar
// die Stelle ist.
//
// ZWEI ANLAEUFE SIND HIER GESCHEITERT, beide am selben Punkt: liegt der gesuchte Grund
// ausserhalb des Bildes, steht dort schlicht keine Tiefeninformation zur Verfuegung —
// und JEDE harte Entscheidung an dieser Grenze wird zu einer sichtbaren Naht, weil die
// Grenze im Bildraum eine schnurgerade Linie ist.
//   1. Abbrechen und den unkorrigierten Wert nehmen: waagerechte Kante ueber die volle
//      Bildbreite, Zeilensprung 0,089 im Rotkanal gegen 0,0025 ohne Korrektur.
//   2. An den Bildrand klemmen: schlimmer statt besser. Der Abtast-ORT wandert dann zwar
//      stetig, der abgetastete WERT aber nicht — alle weiter aussen liegenden Fragmente
//      lesen denselben Randtexel, die Tiefe wird dort konstant und kippt gegen die
//      Nachbarschaft. Gemessen 0,153, und bei gerollter Kamera stand die Naht senkrecht
//      am rechten Bildrand, also in jedem Kurvenflug.
// Deshalb jetzt keine Entscheidung mehr, sondern ein GEWICHT: je weiter der Punkt aus
// dem Bild faellt, desto mehr blendet die Korrektur auf den unkorrigierten Wert zurueck.
// Der ist blickwinkelabhaengig — das war der Zustand vor der ganzen Korrektur —, aber er
// ist ueberall stetig. Wo er uebernimmt, gibt es ohnehin keine bessere Information;
// ausserhalb des Bildes bleibt nur, es nicht zu verschlimmern.
//
// Sauber loesen laesst sich das im Bildraum ueberhaupt nicht. Dafuer braeuchte es die
// Gelaendehoehe aus einer mitgefuehrten Hoehentextur statt aus dem Tiefenpuffer — das
// gehoert ins Wasser-Paket, nicht in diese Korrektur.
vec2 welt_zu_uv(vec3 w, mat4 view, mat4 proj, float blend, out float gewicht) {
	vec4 c = proj * (view * vec4(w, 1.0));
	if (c.w <= 0.0001) {          // hinter der Kamera: keine sinnvolle Bildkoordinate
		gewicht = 0.0;
		return vec2(0.5);
	}
	vec2 uv = (c.xy / c.w) * 0.5 + 0.5;
	// Abstand zum naechsten Bildrand; negativ, wenn der Punkt draussen liegt.
	vec2 d = min(uv, vec2(1.0) - uv);
	// Das Gewicht faellt schon INNERHALB des Bildes auf null. Genau daran ist der erste
	// Ueberblend-Versuch noch gescheitert: er blendete zwar stetig, mischte dabei aber
	// anteilig einen geklemmten — also fremden — Abtastwert bei, und uebrig blieb eine
	// duenne blaue Linie entlang des Bildrands. Faellt das Gewicht schon vorher auf
	// null, fliesst an keiner Stelle mit Gewicht > 0 jemals ein geklemmter Wert ein.
	// smoothstep laeuft an beiden Enden flach aus — kein Knick im Bild.
	gewicht = smoothstep(0.0, blend, min(d.x, d.y));
	return clamp(uv, vec2(0.0), vec2(1.0));
}

void fragment() {
	// --- Welt- und Kameraabstand --------------------------------------------------
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;   // Oberflaeche, Weltmeter
	float cam_d = length(VERTEX);

	// --- SENKRECHTE Wassertiefe aus dem Tiefenpuffer -------------------------------
	// ACHTUNG, hier steckte ein subtiler Fehler: die Tiefe wurde zwar senkrecht
	// GERECHNET (wpos.y - bpos.y), aber am falschen Ort ABGETASTET. texture(depth_tex,
	// SCREEN_UV) liefert den Grund dort, wo der SICHTSTRAHL auftrifft — nicht den Grund
	// senkrecht unter dem Wasserfragment. Der seitliche Versatz ist Tiefe/tan(Elevation),
	// bei 20 Grad und 6 m Tiefe also 16,5 m. Gemessen lag der Ufersaum dadurch 10 m
	// seewaerts verschoben, das waren 65 % der ganzen Schaumbandbreite — der Saum war
	// sichtbar blickwinkelabhaengig breit.
	//
	// Korrigiert wird der ABTASTPUNKT, nicht die Trigonometrie: erst naiv abtasten,
	// dann den so gefundenen Grund senkrecht unter das Fragment zurueckprojizieren und
	// dort erneut abtasten. Der Fehler faellt je Schritt etwa mit der Hangneigung; am
	// Ufer ist die klein, weiter draussen traegt der dritte Schritt noch messbar zum
	// Tuerkis-nach-Blau-Verlauf bei und kostet rund 0,04 ms je Bild.
	bool hat_grund;
	vec3 b0 = grund_welt(SCREEN_UV, depth_tex, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, hat_grund);
	float depth_m;
	if (!hat_grund) {
		// Hinter diesem Wasserpixel steht gar keine Geometrie — es gibt keinen Grund in
		// Sicht, also ist "tief" die richtige Antwort und nicht der Zufallswert, den die
		// Rekonstruktion auf der Fernebene liefert. Weit jenseits von depth_fade, damit
		// der Farbverlauf sicher gesaettigt ist.
		depth_m = depth_fade * 4.0;
	} else {
		vec3 bpos = b0;
		float g_min = 1.0;
		for (int i = 0; i < 3; i++) {
			float g;
			vec2 uv_k = welt_zu_uv(vec3(wpos.x, bpos.y, wpos.z),
				VIEW_MATRIX, PROJECTION_MATRIX, rand_blend, g);
			g_min = min(g_min, g);
			if (g_min <= 0.0) { break; }          // ganz draussen: b0 gilt, Schleife spart
			bool g2;
			vec3 b2 = grund_welt(uv_k, depth_tex, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, g2);
			// Zwei Gruende, einen Abtastwert zu verwerfen:
			//   !g2        — dort steht Himmel, die Rekonstruktion liefert Unsinn.
			//   b2.y >= wpos.y — was dort steht, liegt UEBER dem Wasserspiegel und kann
			//                    deshalb nicht der Grund darunter sein.
			// Der zweite Fall ist nicht theoretisch: die Rueckprojektion trifft regelmaessig
			// eine WOLKE, die vor dem Meer haengt (die Decke liegt bei 320 m, der Spieler
			// fliegt oft darunter). grund_welt liefert dann deren Oberseite, die Tiefe wird
			// null und der Schaum schlaegt voll durch — um jede Wolke stand ein abgeloester
			// heller Saum im Wasser, mit blauem Wasser dazwischen.
			// Zurueck auf den letzten gueltigen Grund. Ueber offener See ist das ohnehin die
			// richtige Antwort, denn dort ist der Grund weit weg und "tief" bleibt "tief".
			if (!g2 || b2.y >= wpos.y) { break; }
			bpos = b2;
		}
		// Unkorrigiert (b0) und korrigiert (bpos) STETIG ueberblendet, nie umgeschaltet.
		depth_m = mix(max(wpos.y - b0.y, 0.0), max(wpos.y - bpos.y, 0.0), g_min);
	}

	// --- Wellen (Weltmeter) --------------------------------------------------------
	float rip = 1.0 - smoothstep(ripple_fade * 0.35, ripple_fade, cam_d);
	float chp = 1.0 - smoothstep(chop_fade * 0.35, chop_fade, cam_d);
	float e = max(0.25, cam_d * 0.0012);      // Ableitungsschritt waechst mit Entfernung
	float h0 = wave_h(wpos.xz, rip, chp);
	float hx = wave_h(wpos.xz + vec2(e, 0.0), rip, chp);
	float hz = wave_h(wpos.xz + vec2(0.0, e), rip, chp);
	vec3 nw = normalize(vec3(-(hx - h0) / e * slope_gain, 1.0, -(hz - h0) / e * slope_gain));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// Der Wellenberg hebt den Wasserspiegel — Untiefen und Ufersaum atmen mit.
	float d_eff = max(depth_m + h0, 0.0);

	// --- Farbe nach Tiefe ----------------------------------------------------------
	float t = smoothstep(0.0, depth_fade, d_eff);
	vec3 col = mix(shallow_col, mid_col, smoothstep(0.0, 0.45, t));
	col = mix(col, deep_col, smoothstep(0.45, 1.0, t));
	// Schaum ist ein BAND, kein gefuellter Fleck: bei Tiefe null ist gar kein Wasser
	// mehr da, das schaeumen koennte.
	float edge = smoothstep(0.0, waterline, d_eff);
	float foam = (1.0 - smoothstep(0.0, foam_band, d_eff)) * edge;
	col = mix(col, foam_col, foam * foam_strength);

	// --- Fresnel + Himmelsspiegelung ----------------------------------------------
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = fresnel_f0 + (1.0 - fresnel_f0) * pow(1.0 - ndv, 5.0);
	vec3 rv = reflect(-VIEW, NORMAL);
	vec3 rw = normalize((INV_VIEW_MATRIX * vec4(rv, 0.0)).xyz);
	vec3 sky = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.55, clamp(rw.y, 0.0, 1.0)));
	// Sonnenglitzer: die Himmelssonne ist prozedural, es gibt keine Reflexionssonde.
	// Zwei Keulen: eine harte fuer die Funken, eine breite weiche fuer den Lichtpfad.
	// Eine einzelne mittelbreite Keule ergab einen weissen Fleck statt Glitzer.
	float sd = max(dot(rw, normalize(sun_dir)), 0.0);
	sky += sun_col * (pow(sd, 1400.0) * 2.2 + pow(sd, 90.0) * 0.10) * glint_strength;
	// Schaum reflektiert nicht, er streut.
	float refl = fres * sky_strength * (1.0 - foam);

	// --- Weltkanten-Angleichung ----------------------------------------------------
	float farf = smoothstep(far_start, far_end, cam_d);

	ALBEDO = mix(col * (1.0 - refl), vec3(0.0), farf);
	EMISSION = mix(sky * refl, far_col, farf);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	ROUGHNESS = mix(mix(0.06, 0.16, t), 0.5, farf);
	// COLOR.a ist die Mesh-eigene Randausblendung. Meer (PlaneMesh ohne Farbattribut)
	// und Fluss liefern 1.0; nur der aeusserste Ring der See-Scheibe faehrt sie auf 0,
	// damit ein Beckenrand, der ausnahmsweise noch unter Wasser liegt, nicht als harte
	// Linie endet (TerrainWorld._build_lake_water).
	ALPHA = clamp(mix(mix(alpha_shallow, alpha_deep, t) + foam * 0.25 + refl * 0.6,
	                  1.0, farf), 0.0, 1.0) * max(edge, farf) * COLOR.a;
}
