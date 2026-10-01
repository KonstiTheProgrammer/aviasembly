// Aviassembly-Wasser — gemeinsamer Kern fuer Meer, Seen und Fluesse.
// Eingebunden von shaders/water.gdshader (UNDURCHSICHTIG: Meer, Fluesse) und
// shaders/water_see.gdshader (#define DURCHSICHTIG: Seen).
//
// ALLES RECHNET IN WELTMETERN (Wellenlaengen in m, Geschwindigkeiten in m/s).
//
// WARUM UNDURCHSICHTIG, und warum KEIN TIEFENPUFFER mehr (gemessen, tools/_wasser_zeit.gd,
// 4K, MSAA 4x): das alte Wasser kostete 2,8-3,5 ms je Bild. Davon waren nur ~0,7 ms die
// eigentliche Rechnung; ~1 ms kostete allein, dass ein sichtbares Material den
// Tiefenpuffer liest (Godot muss ihn dafuer kopieren/aufloesen), ~1 ms das Mischen der
// durchsichtigen Flaeche. Eine UNDURCHSICHTIGE Wasserflaeche war dagegen 1,4 ms SCHNELLER
// als gar kein Wasser: sie verdeckt im Tiefen-Vorpass den ganzen Meeresgrund, der sonst
// schattiert wurde.
// Die Wassertiefe kommt deshalb nicht mehr aus dem Tiefenpuffer, sondern aus zwei
// Hoehentexturen des Gelaendes (TerrainWorld): FEIN = das 8-m-Raster der geladenen Chunks
// (ringfoermig adressiert, exakt die Dreiecke des Gelaendenetzes), GROB = die Hoehen der
// Weltkarte (ganze Welt, 82 bzw. 328 m je Punkt) fuer alles jenseits der Chunks.
// Das hat die alte Blickwinkel-Korrektur samt ihrer drei Fallen (Randnaht, Wolken vor dem
// Meer, Grund ausserhalb des Bildes) ueberfluessig gemacht: die Tiefe ist jetzt exakt die
// senkrechte Wassertiefe unter dem Fragment, egal wohin man schaut.
// Was durchsichtiges Wasser zeigte — den Sand unter der Untiefe — wird nachgebildet: in
// flachem Wasser mischt sich grund_col unter, mit exp(-Tiefe/klarheit).
//
// UNENDLICHES MEER (unendlich = true, nur die Meeresplatte): das Netz ist eine Scheibe um
// die Kamera. Der Vertex-Shader zieht jeden Punkt, der jenseits von schale_r laege, AUF
// DEM SICHTSTRAHL zu ihm auf schale_r heran. Die Bildabdeckung bleibt dabei die einer
// unendlichen Ebene (jede Ecke liegt auf ihrem eigenen Sichtstrahl), nur die Tiefe liegt
// diesseits der Fernebene. Vorher endete eine 28-km-Platte an der Fernebene der Kamera
// (9 km) — ab ~700 m Flughoehe stand ihre Kante als Linie tief unter dem Horizont,
// darueber ein flaches Band Himmelsfarbe. Das Fragment rechnet mit dem ECHTEN Schnittpunkt
// Sichtstrahl/Meeresebene weiter.
// FALLE (erster Versuch): feste Ringradien. Ein Dreieck zwischen einem Ring, der noch auf
// der Ebene liegt, und einem herangezogenen Ring ist eine RAMPE, die aus 700 m Flughoehe
// bis 140 m ueber das Meer steigt — sie verdeckte ferne Felder als graue Flaeche. Deshalb
// traegt das Netz nur ein Ringmass s; der Shader setzt den Ring s = 1 GENAU auf den Kreis,
// in dem die Meeresebene die Kugel schale_r schneidet (Radius sqrt(R^2 - h^2)). Innen
// liegt damit alles exakt auf der Ebene, aussen alles auf der Kugel — keine Rampe.

// EIGENER_DUNST (Meer und Fluesse): Godots Nebel ist AUS, der Shader rechnet dieselbe
// Formel selbst — mit der ECHTEN Entfernung statt der gezeichneten. Godots Nebel sah hinter
// der Kugel schale_r nur noch deren Radius; mit einem Zusatzdunst ab dort blieb an der
// Kugelgrenze ein Knick im Verlauf, aus 2,5 km Hoehe als Bogen quer durchs Meer sichtbar.
#ifdef EIGENER_DUNST
render_mode world_vertex_coords, cull_disabled, diffuse_burley, specular_schlick_ggx, fog_disabled;
#else
render_mode world_vertex_coords, cull_disabled, diffuse_burley, specular_schlick_ggx;
#endif

// --- Gelaende unter dem Wasser --------------------------------------------------------
uniform sampler2D tiefe_fein : filter_nearest, repeat_disable;
uniform bool  fein_da = false;
uniform int   fein_n = 1152;          // Kantenlaenge in Stuetzpunkten (ringfoermig)
uniform float fein_zelle = 8.0;       // m, = TerrainWorld.CHUNK / CELLS
uniform vec2  fein_mitte = vec2(0.0); // um hier sind die Chunks geladen
uniform float fein_r = 3500.0;        // bis hier gilt das feine Raster
uniform sampler2D tiefe_grob : filter_linear, repeat_disable;
uniform bool  grob_da = false;
uniform float grob_r = 84000.0;       // halbe Kantenlaenge der Grobkarte (m)
uniform float grob_n = 512.0;         // Bildpunkte je Kante
uniform float boden_ohne = -80.0;     // Grundhoehe, wenn keine Daten vorliegen: tief

// --- Farbe nach senkrechter Wassertiefe ---------------------------------------------
uniform vec3 shallow_col : source_color = vec3(0.32, 0.80, 0.78);   // Ufer-Tuerkis
uniform vec3 mid_col     : source_color = vec3(0.15, 0.55, 0.68);   // Lagune
uniform vec3 deep_col    : source_color = vec3(0.06, 0.29, 0.55);   // Ozean-Blau
uniform vec3 foam_col    : source_color = vec3(0.86, 0.89, 0.92);
// Grund, der in der Untiefe durchscheint (Sand). Das Klima tauscht ihn (Kies im Norden).
uniform vec3 grund_col   : source_color = vec3(0.80, 0.72, 0.52);
uniform float klarheit = 1.6;        // m: auf diese Tiefe faellt der Grund auf 1/e
uniform float depth_fade = 18.0;     // Tiefe (m), ueber die shallow -> deep blendet
uniform float foam_band  = 1.2;      // Uferschaum bis zu dieser senkrechten Tiefe (m)
uniform float waterline = 0.30;      // m: Randausblendung (nur durchsichtige Seen)
uniform float foam_strength : hint_range(0.0, 1.0) = 0.7;

// --- Brandung: Schaumlinien, die auf das Ufer zulaufen -------------------------------
// Linien gleicher TIEFE — sie liegen damit von selbst parallel zur Kueste, am flachen
// Strand weit auseinander, am Steilufer dicht. brandung = 0 schaltet sie ab (Binnenwasser).
uniform float brandung : hint_range(0.0, 1.0) = 0.0;
uniform float brandung_tiefe = 3.2;   // m: so tief reicht die Brandungszone
uniform float brandung_abstand = 0.85; // m Tiefe zwischen zwei Linien
uniform float brandung_takt = 0.11;   // Linien je Sekunde
uniform float weisskappen : hint_range(0.0, 1.0) = 0.0;   // Schaumkronen auf offener See
// FLIESSENDES WASSER (Fluesse): die Vertexfarbe traegt die Fliessrichtung (RG) und das
// Gefaelle (B) des Bandes (TerrainWorld._build_river_water). Die Wellen laufen dann
// flussab statt mit dem Wind, schneller, je steiler es wird, und wo es steil ist,
// schaeumt Wildwasser; dazu ziehen feine Schaumschlieren mit der Stroemung.
uniform bool fliessend = false;
uniform float stroemung = 1.6;       // m/s Grundstroemung im Flachen

// --- Wellen: Laengen in METERN, Geschwindigkeiten in METERN JE SEKUNDE ---------------
// Die Geschwindigkeit ist die Phasengeschwindigkeit in tiefem Wasser, c = sqrt(g L / 2pi)
// — kein freier Regler (mit geschaetzten Werten stand das Meer optisch still).
// Jede Oktave tastet DIESELBE Wellentextur ab, gedreht in ihre eigene Richtung. Die
// Duenung zweimal, leicht gegeneinander verdreht und verschieden lang: aus der
// Ueberlagerung entstehen wandernde Wellengruppen statt eines starr gleitenden Musters.
// OHNE Anisotropie — gemessen (tools/_wasser_zeit.gd, 4K): mit ihr kostete das Wasser
// 0,8-3,6 ms, ohne -0,2-1,7 ms. Unter flachem Blick nimmt sie je Abruf bis zu 16 Proben,
// und hier sind es bis zu sieben Abrufe je Pixel. Die Ferne wird dadurch weicher — auf
// Wasser eher ein Gewinn (weniger Flimmern).
uniform sampler2D wellen_tex : filter_linear_mipmap, repeat_enable;
uniform vec2  wind_dir = vec2(0.80, 0.60);
uniform float swell_len   = 58.0;
uniform float swell_amp   = 0.55;
uniform float swell_speed = 9.52;
uniform float chop_len    = 13.0;
uniform float chop_amp    = 0.22;
uniform float chop_speed  = 4.51;
uniform float ripple_len  = 3.4;
uniform float ripple_amp  = 0.055;
uniform float ripple_speed = 2.30;
// Die Hoehen sind echte Meter; fuer das Licht werden die Steigungen verstaerkt, sonst
// faengt eine 0,5-m-Duenung auf 58 m kaum Licht.
uniform float slope_gain = 2.6;
// Windfelder: grossflaechig mal rauer, mal glatter — von oben die typischen hellen und
// dunklen Bahnen auf dem Meer. 0 = gleichmaessig.
uniform float windfelder : hint_range(0.0, 1.0) = 0.0;

// --- Fresnel / Himmelsspiegelung ----------------------------------------------------
uniform vec3 sky_horizon : source_color = vec3(0.60, 0.73, 0.88);  // wie sky_clouds
uniform vec3 sky_zenith  : source_color = vec3(0.24, 0.49, 0.86);
uniform vec3 sun_col     : source_color = vec3(1.0, 0.97, 0.90);
uniform vec3 sun_dir = vec3(0.55, 0.62, 0.55);   // setzt TerrainWorld.setze_sonne
uniform float fresnel_f0 : hint_range(0.0, 0.2) = 0.02;
uniform float sky_strength : hint_range(0.0, 2.0) = 1.0;
uniform float glint_strength : hint_range(0.0, 8.0) = 1.0;
// Raues Wasser spiegelt unter flachem Winkel weniger als ein Spiegel (Wellen verschatten
// einander). In der Ferne, wo die Mipmaps die Wellen glaetten, waere die Flaeche sonst
// ein perfekter Spiegel und der Horizont ein weisses Band.
uniform float fern_spiegel : hint_range(0.0, 1.0) = 0.62;

// --- Unendliches Meer + eigener Dunst ------------------------------------------------
uniform bool  unendlich = false;
uniform float wasser_y = -5.85;        // Hoehe der Meeresebene (m)
uniform float schale_r = 8800.0;       // knapp diesseits der Fernebene der Kamera
// Godots Nebel nachgebaut (nur mit EIGENER_DUNST): TIEFENNEBEL wie die Umgebung (Main.
// NEBEL_ENDE), Menge smoothstep(0, Ende, Entfernung) ^ Form (Godots fog_depth_* bei
// Dichte 1), Farbe = Nebellicht gemischt mit dem Himmel unter dem Horizont
// (fog_aerial_perspective) plus Sonnenstreuung. Alle setzt TerrainWorld.setze_dunst/
// setze_nebel_licht aus der echten Umgebung, Farben LINEAR (kein source_color).
uniform float dunst_ende = 18000.0;
uniform float dunst_form = 0.6;
uniform vec3  dunst_col = vec3(0.24, 0.33, 0.48);
uniform vec3  dunst_sonne = vec3(0.23, 0.20, 0.14);
// Land JENSEITS der Fernebene: dort steht kein Gelaende mehr, nur noch die Scheibe. Wo die
// Grobkarte Land meldet, malt sie es als dunstige Silhouette — ferne Kuesten und Inseln
// stehen so bis zum Horizont, statt als heller Sandfleck im Meer zu liegen.
uniform vec3  land_col : source_color = vec3(0.26, 0.33, 0.24);

const float ZYKLEN = 10.0;   // Wellenlaengen je Kachel, siehe tools/_wellen_textur.gd

float hash(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){ vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	float a=hash(i),b=hash(i+vec2(1,0)),c=hash(i+vec2(0,1)),d=hash(i+vec2(1,1));
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y); }
vec2 dreh(vec2 v, float a) { float s = sin(a), c = cos(a); return vec2(c*v.x - s*v.y, s*v.x + c*v.y); }

// Eine Oktave. Liefert (dh/dx, dh/dz) in Metern je Meter, h in Metern, Schaum 0..1.
vec4 welle(vec2 p, vec2 dir, float len, float amp, float speed, float t) {
	float kachel = len * ZYKLEN;
	vec2 q = vec2(dot(p, dir), dot(p, vec2(-dir.y, dir.x))) / kachel;
	q.x -= speed * t / kachel;
	vec4 s = texture(wellen_tex, q);
	// Kettenregel: u = (p.dir)/K, v = (p.perp)/K  ->  d/dx = (dir.x d/du - dir.y d/dv)/K
	vec2 g = vec2(s.r * dir.x - s.g * dir.y, s.r * dir.y + s.g * dir.x) * (amp / kachel);
	return vec4(g, s.b * amp, s.a);
}

// Gelaendehoehe aus dem feinen Raster. EXAKT die zwei Dreiecke je Zelle, die auch das
// Gelaendenetz hat (v00,v10,v11 und v00,v11,v01) — bilinear laege der Uferschaum bis zu
// Dezimeter neben der Linie, an der Wasser und Gelaende sich wirklich schneiden.
// Nicht geladene Chunks tragen 20000 (TerrainWorld.TIEFE_LEER): dann zaehlt das Raster
// hier nicht, und es gilt die Grobkarte.
float fein_hoehe(vec2 xz, out float gueltig) {
	vec2 g = xz / fein_zelle;
	vec2 i0 = floor(g);
	vec2 f = g - i0;
	float n = float(fein_n);
	ivec2 a = ivec2(mod(i0, n));
	ivec2 b = ivec2(mod(i0 + 1.0, n));
	float h00 = texelFetch(tiefe_fein, a, 0).r;
	float h10 = texelFetch(tiefe_fein, ivec2(b.x, a.y), 0).r;
	float h01 = texelFetch(tiefe_fein, ivec2(a.x, b.y), 0).r;
	float h11 = texelFetch(tiefe_fein, b, 0).r;
	gueltig = step(max(max(h00, h10), max(h01, h11)), 9000.0);
	return f.x > f.y ? h00 + f.x * (h10 - h00) + f.y * (h11 - h10)
	                 : h00 + f.y * (h01 - h00) + f.x * (h11 - h01);
}

float grob_hoehe(vec2 xz) {
	if (!grob_da) { return boden_ohne; }
	vec2 uv = (xz / grob_r * 0.5 + 0.5) * ((grob_n - 1.0) / grob_n) + 0.5 / grob_n;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) { return boden_ohne; }
	return texture(tiefe_grob, uv).r;
}

float boden_hoehe(vec2 xz) {
	float w = 0.0;
	float hf = 0.0;
	float df = distance(xz, fein_mitte);
	if (fein_da && df < fein_r) {
		float gueltig;
		hf = fein_hoehe(xz, gueltig);
		// Breiter Uebergang: die Grobkarte loest Sandbaenke nicht auf (82 m, anfangs 328 m je
		// Punkt), bei 500 m Blende stand ihre Grenze als gerade Kante in der Lagune.
		w = gueltig * (1.0 - smoothstep(fein_r - 1400.0, fein_r, df));
	}
	if (w > 0.999) { return hf; }
	return mix(grob_hoehe(xz), hf, w);
}

void vertex() {
	if (unendlich) {
		// VERTEX ist Weltraum (world_vertex_coords). Der Knoten steht im Ursprung, die
		// Scheibe wird hier um die Kamera gelegt — so folgt sie ohne Skript jedem Bild.
		// Das Netz traegt nur Richtung und Ringmass s (= Laenge von VERTEX.xz).
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		float hc = max(cam.y - wasser_y, 0.5);
		float rb = sqrt(max(schale_r * schale_r - hc * hc, 1.0));
		float s = length(VERTEX.xz);
		vec2 richtung = s > 0.0 ? VERTEX.xz / s : vec2(0.0);
		vec3 p = vec3(cam.x + richtung.x * s * rb, wasser_y, cam.z + richtung.y * s * rb);
		vec3 d = p - cam;
		float l = length(d);
		if (l > schale_r) { p = cam + d * (schale_r / l); }
		VERTEX = p;
	}
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float rend_d = length(VERTEX);
	if (unendlich) {
		// Echter Schnittpunkt des Sichtstrahls mit der Meeresebene.
		vec3 rd = normalize(wpos - cam);
		float hc = cam.y - wasser_y;
		if (hc > 0.05 && rd.y < -1.0e-6) {
			wpos = cam + rd * min(hc / -rd.y, 4.0e5);
		}
		wpos.y = wasser_y;
	}
	float cam_d = distance(wpos, cam);
	float t = TIME;

	// --- Tiefe -------------------------------------------------------------------------
	float tiefe = wpos.y - boden_hoehe(wpos.xz);

	// --- Wellen --------------------------------------------------------------------------
	vec2 w = normalize(wind_dir);
	float steil = 0.0;
	float zug = 0.0;
	if (fliessend) {
		vec2 fd = COLOR.rg * 2.0 - 1.0;
		if (dot(fd, fd) > 0.01) {
			w = normalize(fd);
		}
		steil = COLOR.b;
		zug = stroemung * (1.0 + 4.0 * steil);
	}
	float wf = 1.0;
	float wfn = 0.5;
	if (windfelder > 0.0) {
		wfn = vnoise(wpos.xz / 2300.0 + w * (t * 0.004)) * 0.65
			+ vnoise(wpos.xz / 900.0 - w * (t * 0.006)) * 0.35;
		wf = mix(1.0, mix(0.45, 1.35, smoothstep(0.25, 0.75, wfn)), windfelder);
	}
	vec4 s1 = welle(wpos.xz, dreh(w, 0.17), swell_len, swell_amp * 0.62, swell_speed + zug, t);
	vec4 s2 = welle(wpos.xz, dreh(w, -0.24), swell_len * 0.77, swell_amp * 0.50,
		swell_speed * 0.877 + zug, t);
	// Kurze Oktaven nur, wo sie noch mehr als einen Bildpunkt haben: dahinter liefern die
	// Mipmaps ohnehin nur noch ihren Mittelwert (Steigung null). Die Grenzen laufen mit
	// der Wellenlaenge, damit Seen und Fluesse (kurze Wellen) sie frueher abgeben.
	vec4 c1 = vec4(0.0);
	vec4 r1 = vec4(0.0);
	vec4 r2 = vec4(0.0);
	if (cam_d < chop_len * 450.0) {
		c1 = welle(wpos.xz, dreh(w, 0.62), chop_len, chop_amp * wf * (1.0 + 2.5 * steil),
			chop_speed + zug, t);
	}
	if (cam_d < ripple_len * 450.0) {
		r1 = welle(wpos.xz, dreh(w, -0.45), ripple_len, ripple_amp * wf * (1.0 + 2.0 * steil),
			ripple_speed + zug, t);
		r2 = welle(wpos.xz, dreh(w, 1.10), ripple_len * 0.37, ripple_amp * 0.35 * wf,
			ripple_speed * 0.61 + zug * 0.8, t);
	}
	vec2 grad = s1.xy + s2.xy + c1.xy + r1.xy + r2.xy;
	float h0 = s1.z + s2.z + c1.z;
	// Normierte Kammhoehe (etwa -1..1) fuer Schaumkronen und Durchleuchtung.
	float h_norm = h0 / max(swell_amp * 1.12 + chop_amp * wf, 1.0e-4);
	vec3 nw = normalize(vec3(-grad.x * slope_gain, 1.0, -grad.y * slope_gain));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// Der Wellenberg hebt den Wasserspiegel — Untiefen und Ufersaum atmen mit.
	float d_eff = max(tiefe + h0 * 0.6, 0.0);

	// --- Farbe nach Tiefe ------------------------------------------------------------
	float tt = smoothstep(0.0, depth_fade, d_eff);
	vec3 col = mix(shallow_col, mid_col, smoothstep(0.0, 0.45, tt));
	col = mix(col, deep_col, smoothstep(0.45, 1.0, tt));
#ifndef DURCHSICHTIG
	// Der Grund scheint durch die Untiefe: Sand, vom Wasser eingefaerbt. Direkt an der
	// Wasserlinie ist es fast nur Sand — so laeuft das Wasser ohne Kante in den Strand.
	float durch = exp(-d_eff / klarheit);
	col = mix(col, grund_col * mix(vec3(1.0), shallow_col * 1.25, 0.45), durch * 0.88);
#endif

	// --- Schaum ------------------------------------------------------------------------
	float fern = smoothstep(700.0, 2600.0, cam_d);
	float netz = 0.5;
	float netz2 = 0.5;
	if (fern < 1.0) {
		netz = texture(wellen_tex, wpos.xz / 23.0 + w * (t * 0.012)).a;
		netz2 = texture(wellen_tex, wpos.xz / 9.0 - w * (t * 0.02) + 0.37).a;
	}
	// Uferschaum: ein BAND an der Wasserlinie, vom Schaumnetz aufgebrochen.
	float saum = (1.0 - smoothstep(0.0, foam_band, d_eff)) * (1.0 - 0.6 * fern);
	float schaum = saum * mix(0.55, 1.0, max(netz, netz2) * (1.0 - fern) + fern * 0.5);
	// Brandungslinien: Phase aus der Tiefe — mit der Zeit wandert jede Linie zu kleinerer
	// Tiefe, also aufs Ufer zu. Ein Rauschen laengs der Kueste versetzt und bricht sie.
	if (brandung > 0.0 && d_eff < brandung_tiefe) {
		float bruch = vnoise(wpos.xz / 38.0 + vec2(t * 0.05, 0.0));
		float phase = d_eff / brandung_abstand + t * brandung_takt + bruch * 0.7;
		float s = fract(phase);
		float linie = smoothstep(0.0, 0.07, s) * (1.0 - smoothstep(0.07, 0.42, s));
		float zone = smoothstep(brandung_tiefe, brandung_tiefe * 0.45, d_eff);
		linie *= zone * smoothstep(0.28, 0.62, bruch) * mix(0.6, 1.0, netz);
		schaum = max(schaum, linie * brandung * (1.0 - fern));
	}
	// Fluss: Schaumschlieren mit der Stroemung (laengs gestrecktes Schaumnetz) und Wildwasser,
	// wo das Band steil wird.
	if (fliessend && fern < 1.0) {
		vec2 ql = vec2(dot(wpos.xz, w), dot(wpos.xz, vec2(-w.y, w.x)));
		float schliere = texture(wellen_tex, ql / vec2(26.0, 7.0) - vec2(t * zug / 26.0, 0.0)).a;
		float wild = smoothstep(0.10, 0.45, steil);
		float wildnetz = texture(wellen_tex, ql / vec2(9.0, 5.0) - vec2(t * zug / 9.0, 0.3)).a;
		schaum = max(schaum, schliere * 0.22 * (1.0 - wild) * (1.0 - fern));
		schaum = max(schaum, wild * mix(0.55, 1.0, max(schliere, wildnetz)) * (1.0 - fern * 0.5));
	}
	// Schaumkronen auf offener See, nur auf den hoechsten Kaemmen und in rauen Windfeldern.
	if (weisskappen > 0.0) {
		float krone = smoothstep(0.48, 0.92, h_norm) * smoothstep(0.35, 0.8, wfn * wf)
			* netz2 * (1.0 - smoothstep(500.0, 1600.0, cam_d));
		schaum = max(schaum, krone * weisskappen);
	}
	float land = 0.0;
	if (unendlich) {
		land = smoothstep(schale_r * 0.96, schale_r * 0.995, rend_d) * smoothstep(-0.3, -3.0, tiefe);
	}
	schaum = clamp(schaum * foam_strength, 0.0, 1.0) * (1.0 - land);
	col = mix(col, foam_col, schaum);
	col = mix(col, land_col, land);

	// --- Fresnel + Himmelsspiegelung --------------------------------------------------
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = fresnel_f0 + (1.0 - fresnel_f0) * pow(1.0 - ndv, 5.0);
	fres *= mix(1.0, fern_spiegel, smoothstep(400.0, 6000.0, cam_d));
	vec3 rv = reflect(-VIEW, NORMAL);
	vec3 rw = normalize((INV_VIEW_MATRIX * vec4(rv, 0.0)).xyz);
	vec3 sky = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.55, clamp(rw.y, 0.0, 1.0)));
	// Sonnenglitzer: harte Keule fuer die Funken, weiche fuer den Lichtpfad. In der Ferne
	// (Wellen durch die Mipmaps geglaettet) wird der Pfad breiter statt zum Punkt.
	float sd = max(dot(rw, normalize(sun_dir)), 0.0);
	float breit = mix(90.0, 30.0, fern);
	sky += sun_col * (pow(sd, 1400.0) * 2.2 * (1.0 - fern * 0.7) + pow(sd, breit) * 0.10)
		* glint_strength;
	float refl = fres * sky_strength * (1.0 - schaum) * (1.0 - land);

	// Durchleuchtete Kaemme: schaut man gegen die Sonne, glimmt der Kamm tuerkis.
	vec3 rdw = normalize(wpos - cam);
	float gegen = pow(max(dot(normalize(rdw.xz + vec2(1.0e-5)), normalize(sun_dir.xz)), 0.0), 3.0);
	vec3 sss = shallow_col * smoothstep(0.15, 0.9, h_norm) * gegen * 0.09 * (1.0 - fern);

	// --- Dunst ------------------------------------------------------------------------
#ifdef EIGENER_DUNST
	float dunst = pow(smoothstep(0.0, dunst_ende, cam_d), dunst_form);
	vec3 dfarbe = dunst_col + dunst_sonne * pow(max(dot(rdw, normalize(sun_dir)), 0.0), 8.0);
#else
	float dunst = 0.0;
	vec3 dfarbe = vec3(0.0);
#endif

	ALBEDO = col * (1.0 - refl) * (1.0 - dunst);
	EMISSION = mix(sky * refl + sss, dfarbe, dunst);
	METALLIC = 0.0;
	SPECULAR = 0.5 * (1.0 - schaum) * (1.0 - dunst);
	ROUGHNESS = mix(mix(0.06, 0.16, tt), 0.45, max(schaum, fern * 0.6));
#ifdef DURCHSICHTIG
	// Seen bleiben durchsichtig (klein im Bild, Mischen kostet dort nichts): in der Untiefe
	// sieht man den echten Grund. Am Rand laeuft die Flaeche ueber die Tiefe aus, ganz
	// aussen zusaetzlich ueber COLOR.a (TerrainWorld._build_lake_water).
	float edge = smoothstep(0.0, waterline, d_eff);
	ALPHA = clamp(mix(0.45, 0.94, tt) + schaum * 0.3 + refl * 0.6, 0.0, 1.0) * edge * COLOR.a;
#endif
}
