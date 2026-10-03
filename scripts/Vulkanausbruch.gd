class_name Vulkanausbruch
extends Node3D
## DER VULKAN BRICHT AUS (2026-10-03, Nutzer nach dem Feuerberg: „mach noch krasser“).
##
## VORHER stand ueber dem Krater eine STILLE Aschesaeule aus 40 Wolkenballen (CloudField.fahne), dazu
## ein Funkenregen. Aus der Naehe ein Bild, aber nichts passierte: die Saeule hing wie ein Foto in der
## Luft. JETZT ist der Vulkan aktiv:
##   * SAEULE, die wirklich STEIGT: Ballen quellen aus dem Schlot, steigen mit abnehmendem Tempo (vom
##     Schlot ~30 m/s bis zum Schirm in ~4 km), weiten sich auf, rollen und brodeln; oben breiten sie
##     sich zum SCHIRM aus, der im Wind 5-6 km weit abzieht. Alles im Vertex-Shader aus der Zeit und
##     einer Phase je Ballen (CloudField.PUFF_SHADER, hier um die Bahn ergaenzt) — keine Rechnung auf
##     der CPU, nichts springt: unten entstehen die Ballen im Krater, oben vergehen sie im Schirm.
##   * AUSBRUECHE alle 30-60 s: Feuerball, Lichtblitz (OmniLight, nur 1,5 s), sichtbare DRUCKWELLE
##     (Kugelschale mit Schallgeschwindigkeit; am Flugzeug wackelt die Kamera, wenn sie ankommt),
##     200 LAVABOMBEN mit Rauchspuren, die auf der Flanke aufschlagen und nachgluehen, eine dunkle
##     BLUMENKOHLWOLKE, die in ~1 min auf 2-3 km steigt, und VULKANBLITZE in der Asche.
##   * LAVAFONTAENE im Krater, die in Stoessen spritzt (Funken-Partikel, vulkan_funken_bahn).
##   * ASCHEREGEN unter dem Schirm, FUMAROLEN am Kraterrand, LAVADAMPF ueber den heissen Stroemen.
##   * IM FLUG: in der Asche wird es dunkel (Main._vulkan_im_flug), heftige Turbulenz, Aufwind ueber
##     dem Schlot.
## Zwei FASSUNGEN der Ausbruchseffekte (A/B) wechseln sich ab: jede lebt bis 60 s, ein neuer Ausbruch
## kommt fruehestens nach 30 s — so reisst er die Bomben und die Wolke des vorigen nicht weg.
##
## Werkzeuge: VULKAN_STOSS=<s> friert einen Ausbruch in diesem Alter ein (Bilder), VULKAN_RUHE=1 =
## keine Ausbrueche, VULKAN_BLITZ=1 = ein Blitz steht dauernd (Bildprobe).

const SAEULE_N := 128            # Ballen in der Saeule
const SCHIRM_N := 96             # Ballen im Schirm
const WOLKE_N := 56              # Ballen der Blumenkohlwolke je Fassung
const BOMBEN_N := 200
const FEUERBALL_N := 7
const SPUR_BOMBEN := 64           # Bomben mit Rauchspur (mehr kostete mitten im Ausbruch ueber 2 ms)
const SPUR_N := 32                # Ballen je Spur (alle 0,25 s, 8 s lang)
const DAMPF_JE_QUELLE := 14
const SCHALL := 340.0

## Lage und Masse (aus Main._vulkanfahnen). schlot = Seespiegel in Kratermitte.
var schlot := Vector3.ZERO
var krater_r := 400.0
var steig_h := 4200.0            # vom Schlot bis in den Schirm
var steig_t := 230.0             # Sekunden dafuer
var r_schlot := 60.0
var aufweitung := 0.12           # Halbmesser waechst je Meter Hoehe
var wind := Vector2(1.0, 0.0)
var neigung := 0.42              # seitlicher Weg an der Spitze, Anteil von steig_h
var biegung := 2.2
var schirm_l := 5600.0
var schirm_b := 1500.0
var schirm_zeit := 420.0
var fern_ende := 8800.0          # Main.KAMERA_FERN * 0.98 (Main setzt es): dort sind Ballen klein

var rand_tiefe := 330.0          # Kraterrand ueber dem Seespiegel (aus dem Profil)
var _alter := 10000.0           # seit dem letzten Ausbruch
var _alter_ab: Array[float] = [10000.0, 10000.0]
var _fassung := 1
var _naechster := 9.0
var _test_alter := -1.0
var _ruhe := false
var _rng := RandomNumberGenerator.new()
var _wolken_mats: Array[ShaderMaterial] = []      # alle Saeulenmaterialien (Blitz-Leuchten)
var _stoss_mats: Array = [[], []]                  # je Fassung: Materialien mit stoss_alter
var _licht: OmniLight3D
var _welle: MeshInstance3D
var _welle_mat: ShaderMaterial
var _blitze: Array[MeshInstance3D] = []
var _blitz_mat: ShaderMaterial
var _blitz_t := 0.0
var _blitz_naechster := 4.0
var _blitz_test := false
var _funken: GPUParticles3D


static func bauen(parent: Node3D, terrain: TerrainWorld, ms: Dictionary, wind_richtung: Vector2,
		fern: float) -> Vulkanausbruch:
	var t0 := Time.get_ticks_msec()
	var v := Vulkanausbruch.new()
	v.fern_ende = fern * 0.98
	v.name = "Vulkanausbruch"
	v.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var p: Vector3 = ms["pos"]
	v.schlot = Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
	v.krater_r = float(ms.get("crater_r", 400.0))
	v.wind = wind_richtung.normalized()
	v._rng.seed = int(p.x) * 31 + int(p.z)
	parent.add_child(v)
	var profil := v._profil(terrain)
	v._saeule_bauen()
	v._bomben_bauen(profil)
	v._quellen_bauen(terrain, ms)
	v._funken_bauen()
	v._blitze_bauen()
	v._welle_bauen()
	v._ascheregen_bauen()
	v._licht = OmniLight3D.new()
	v._licht.light_color = Color(1.0, 0.58, 0.24)
	v._licht.omni_range = 2600.0
	v._licht.omni_attenuation = 1.4
	v._licht.shadow_enabled = false
	v._licht.light_energy = 0.0
	v._licht.visible = false
	v._licht.position = v.schlot + Vector3(0.0, v.rand_tiefe + 120.0, 0.0)
	v.add_child(v._licht)
	if OS.get_environment("VULKAN_STOSS") != "":
		v._test_alter = float(OS.get_environment("VULKAN_STOSS"))
	v._ruhe = OS.get_environment("VULKAN_RUHE") != ""
	v._blitz_test = OS.get_environment("VULKAN_BLITZ") != ""
	if v._test_alter >= 0.0:
		v._alter_ab[0] = v._test_alter
		v._fassung = 0
		v._alter = v._test_alter
	print("Vulkanausbruch: Saeule %d + Schirm %d Ballen, %d Bomben, %d Spurballen, %d ms" % [
		SAEULE_N, SCHIRM_N, BOMBEN_N * 2, SPUR_BOMBEN * SPUR_N * 2, Time.get_ticks_msec() - t0])
	return v


# --- RADIALES PROFIL DES KEGELS (Aufschlag der Bomben) -------------------------------------
func _profil(terrain: TerrainWorld) -> PackedFloat32Array:
	var pr := PackedFloat32Array()
	for i in 16:
		var r := float(i) / 15.0 * 2400.0
		var summe := 0.0
		for k in 16:
			var w := TAU * float(k) / 16.0
			summe += terrain.height_at(schlot.x + cos(w) * r, schlot.z + sin(w) * r)
		pr.append(summe / 16.0)
	pr[0] = schlot.y
	# Kraterrand: hoechster mittlerer Ring zwischen 0,8 und 1,4 Kraterradien
	var rand := schlot.y
	for k in 13:
		var r := krater_r * (0.8 + 0.05 * float(k))
		var summe := 0.0
		for j in 16:
			var w := TAU * float(j) / 16.0
			summe += terrain.height_at(schlot.x + cos(w) * r, schlot.z + sin(w) * r)
		rand = maxf(rand, summe / 16.0)
	rand_tiefe = rand - schlot.y
	return pr


# --- SAEULE, SCHIRM UND BLUMENKOHLWOLKEN -----------------------------------------------------
## Der Wolken-Shader (CloudField.PUFF_SHADER) bekommt eine BAHN: die Ballen stehen als Einheits-
## Instanzen im Ursprung, der Vertex-Shader (world_vertex_coords) setzt sie aus Zeit und Phase an
## ihren Ort, dreht sie (Rollen) und laesst die Oberflaeche brodeln. Licht, Krume, Falten, Rand und
## Dunst bleiben wortgleich die der Wolken.
static func _asche_shader_code() -> String:
	var code := CloudField.PUFF_SHADER
	var ersetzt := 0
	var alt_modus := "render_mode cull_back, specular_disabled, shadows_disabled;"
	if code.contains(alt_modus):
		# EIGENER NEBEL wie die Gewitterzelle (siehe nebel_setzen)
		code = code.replace(alt_modus, alt_modus.replace(";", ", world_vertex_coords, fog_disabled;")
			+ "\n" + ASCHE_KOPF)
		ersetzt += 1
	var a := code.find("void vertex() {")
	var b := code.find("void fragment() {")
	if a >= 0 and b > a:
		code = code.substr(0, a) + ASCHE_VERTEX + "\n" + code.substr(b)
		ersetzt += 1
	var alt_farbe := "vec3 c = mix(farbe_basis, farbe_krone, smoothstep(0.0, 0.55, krone));"
	if code.contains(alt_farbe):
		code = code.replace(alt_farbe, ASCHE_FARBE)
		ersetzt += 1
	var alt_blitz := "EMISSION += blitz_farbe * blitz * mix(1.0, 0.35, krone);"
	if code.contains(alt_blitz):
		code = code.replace(alt_blitz, ASCHE_LEUCHTEN)
		ersetzt += 1
	if ersetzt != 4:
		push_error("Vulkanausbruch: Wolken-Shader hat sich geaendert (%d von 4 Stellen gefunden)" % ersetzt)
	return code


const ASCHE_KOPF := """
// --- AUSBRUCHSSAEULE (scripts/Vulkanausbruch.gd) ---------------------------------------------
uniform int art = 0;                   // 0 Saeule, 1 Schirm, 2 Blumenkohlwolke eines Ausbruchs
uniform vec3 schlot = vec3(0.0);
uniform float steig_h = 4200.0;
uniform float steig_t = 230.0;
uniform float r_schlot = 60.0;
uniform float aufweitung = 0.12;
uniform vec2 wind = vec2(1.0, 0.0);
uniform float neigung = 0.42;
uniform float biegung = 2.2;
uniform float schirm_l = 5600.0;
uniform float schirm_b = 1500.0;
uniform float schirm_zeit = 420.0;
uniform float stoss_alter = 10000.0;
uniform float rand_tiefe = 330.0;
uniform float fern_ende = 8800.0;
uniform vec3 glut_farbe = vec3(1.25, 0.34, 0.07);
uniform vec3 zk0 : source_color = vec3(0.30, 0.20, 0.15);
uniform vec3 zb0 : source_color = vec3(0.42, 0.17, 0.07);
uniform vec3 zk1 : source_color = vec3(0.26, 0.225, 0.20);
uniform vec3 zb1 : source_color = vec3(0.10, 0.07, 0.055);
uniform vec3 zk2 : source_color = vec3(0.33, 0.29, 0.255);
uniform vec3 zb2 : source_color = vec3(0.09, 0.08, 0.072);
uniform vec3 zk3 : source_color = vec3(0.48, 0.435, 0.39);
uniform vec3 zb3 : source_color = vec3(0.16, 0.14, 0.125);
uniform vec3 blitz_ort = vec3(0.0);
uniform float blitz_r = 1.0e7;
global uniform float vulkan_ausbruch;
varying float hoehe_anteil;
varying float glut_v;
varying vec3 welt_p;

vec3 drehe(vec3 v, vec3 achse, float w) {
	float c = cos(w);
	float s = sin(w);
	return v * c + cross(achse, v) * s + achse * dot(achse, v) * (1.0 - c);
}
"""

const ASCHE_VERTEX := """
void vertex() {
	vec4 k = INSTANCE_CUSTOM;
	vec3 lv = VERTEX - MODEL_MATRIX[3].xyz;     // Einheitsballen um seine Mitte (Instanz traegt Drehung)
	vec3 ln = normalize(NORMAL);
	falte = COLOR.g;
	vec3 mitte = schlot;
	float s = 0.0;
	float flach = 1.0;
	vec2 aussen = k.zw;
	glut_v = 0.0;
	float top_x = neigung * steig_h;
	if (art == 0) {
		// SAEULE: steigt mit abnehmendem Tempo, weitet sich, neigt sich oben in den Wind
		float p = fract(TIME / steig_t + k.x);
		float y = steig_h * (1.0 - pow(1.0 - p, 1.6));
		float hz = y / steig_h;
		float r = r_schlot + aufweitung * y;
		vec2 seit = wind * top_x * pow(hz, biegung) + k.zw * 0.42 * r;
		mitte = schlot + vec3(seit.x, y, seit.y);
		s = r * k.y * smoothstep(0.0, 0.025, p) * (1.0 - smoothstep(0.90, 1.0, p));
		glut_v = 1.0 - smoothstep(0.0, 0.09, hz);
	} else if (art == 1) {
		// SCHIRM: zieht vom Kopf der Saeule im Wind ab, faechert auf, flacht ab und vergeht
		float u = fract(TIME / schirm_zeit + k.x);
		float r_top = r_schlot + aufweitung * steig_h;
		vec2 quer = vec2(-wind.y, wind.x);
		vec2 seit = wind * (top_x + schirm_l * pow(u, 0.85)) + quer * schirm_b * sqrt(u) * k.z;
		mitte = schlot + vec3(seit.x, steig_h + k.w * 260.0 + 160.0 * sin(u * 3.1416), seit.y);
		s = r_top * k.y * mix(0.80, 1.25, u) * smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.72, 1.0, u));
		flach = 0.62;
		aussen = quer * k.z;
	} else {
		// BLUMENKOHLWOLKE eines Ausbruchs: schiesst mit ~200 m/s heraus, bremst, quillt auf
		float a = stoss_alter - k.x * 2.2;
		float hk = fract(k.x * 13.7 + k.y * 3.1);
		vec3 dir = normalize(vec3(k.z, 0.25 + hk * 0.9, k.w));
		// startet am Kraterrand (im Kessel saehe man den Knall nicht), ~250 m/s
		float hc = rand_tiefe * 0.55 + 2400.0 * (1.0 - exp(-max(a, 0.0) / 9.0)) * mix(0.55, 1.0, hk);
		float weit = 560.0 * (1.0 - exp(-max(a, 0.0) / 6.5));
		vec2 seit = wind * max(a, 0.0) * 10.0;
		mitte = schlot + vec3(seit.x, hc, seit.y) + dir * weit;
		s = (55.0 + 260.0 * (1.0 - exp(-max(a, 0.0) / 9.0))) * k.y
			* smoothstep(0.0, 0.5, a) * (1.0 - smoothstep(40.0, 58.0, a));
		glut_v = (1.0 - smoothstep(0.5, 7.0, a)) * 0.9 + (1.0 - smoothstep(0.0, 0.10, hc / steig_h)) * 0.4;
		aussen = dir.xz;
	}
	// ROLLEN: um eine waagerechte Achse quer zur Richtung vom Kern nach aussen
	vec3 rad = vec3(aussen.x, 0.0, aussen.y);
	float rl = length(rad);
	vec3 achse = rl > 0.01 ? normalize(cross(vec3(0.0, 1.0, 0.0), rad / rl)) : vec3(1.0, 0.0, 0.0);
	float w = TIME * 0.035 * (0.6 + fract(k.x * 91.7)) + k.x * 40.0;
	lv = drehe(lv, achse, w);
	ln = drehe(ln, achse, w);
	// Die KRONE folgt der Lage NACH dem Rollen (sonst rollte die helle Kuppe nach unten)
	krone = clamp(0.5 + lv.y * 0.65, 0.0, 1.0);
	lokal = lv * 70.0;
	// BRODELN: die Oberflaeche quillt langsam auf und sinkt zurueck
	float b = wrausch(lv * 2.4 + vec3(k.x * 31.0, -TIME * 0.10, TIME * 0.04)) - 0.5;
	lv += ln * b * 0.14;
	float d = distance(mitte, CAMERA_POSITION_WORLD);
	// Erst JENSEITS der Fernebene vergehen: vorher (schon ab „Mitte + Halbmesser = Fernebene“) war
	// die Saeule aus 8,5 km ganz verschwunden. Ein angeschnittener Ballen faellt im Dunst kaum auf.
	s *= 1.0 - smoothstep(fern_ende, fern_ende + 1500.0, d - s * 0.5);
	if (PROJECTION_MATRIX[3][3] < 0.5) {
		s *= smoothstep(nah_weg, nah_voll, d);
	}
	VERTEX = mitte + lv * s * vec3(1.0, flach, 1.0);
	NORMAL = normalize(ln * vec3(1.0, 1.0 / flach, 1.0));
	welt_p = VERTEX;
	welt_y = VERTEX.y;
	hoehe_anteil = (mitte.y - schlot.y) / steig_h;
	nah = 1.0 - smoothstep(krume_fern * 0.45, krume_fern, distance(VERTEX, CAMERA_POSITION_WORLD));
}
"""

const ASCHE_FARBE := """
	// ZONEN NACH DER HOEHE: unten von der Glut angeleuchtet, dann dunkle Asche, oben heller
	float hzf = clamp(hoehe_anteil, 0.0, 1.0);
	vec3 fk = mix(zk0, zk1, smoothstep(0.02, 0.16, hzf));
	fk = mix(fk, zk2, smoothstep(0.25, 0.55, hzf));
	fk = mix(fk, zk3, smoothstep(0.72, 1.0, hzf));
	vec3 fb = mix(zb0, zb1, smoothstep(0.02, 0.16, hzf));
	fb = mix(fb, zb2, smoothstep(0.25, 0.55, hzf));
	fb = mix(fb, zb3, smoothstep(0.72, 1.0, hzf));
	vec3 c = mix(fb, fk, smoothstep(0.0, 0.55, krone));
"""

const ASCHE_LEUCHTEN := """
	// BLITZ in der Asche: nur um den Einschlag herum
	EMISSION += blitz_farbe * blitz * mix(1.0, 0.45, krone)
		* (1.0 - smoothstep(blitz_r * 0.25, blitz_r, distance(welt_p, blitz_ort)));
	// GLUT VON UNTEN: der Lavasee leuchtet die Unterseiten an; beim Ausbruch blitzt die Saeule auf
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float unten = clamp(0.15 - nw.y * 0.85, 0.0, 1.0);
	float stoss = exp(-vulkan_ausbruch * 2.5) * 2.5 * (1.0 - smoothstep(0.0, 0.45, hoehe_anteil));
	EMISSION += glut_farbe * (glut_v + stoss) * unten * (1.0 - krone * 0.5)
		* (0.85 + 0.15 * sin(TIME * 3.0 + welt_p.y * 0.01));
	// WARME FUELLUNG: das blaue Himmelslicht machte die dunkle Asche auf der Schattenseite marineblau
	EMISSION += ALBEDO * vec3(0.40, 0.34, 0.27);
"""


func _asche_material(art: int) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = _asche_shader_code()
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("art", art)
	m.set_shader_parameter("schlot", schlot)
	m.set_shader_parameter("steig_h", steig_h)
	m.set_shader_parameter("steig_t", steig_t)
	m.set_shader_parameter("r_schlot", r_schlot)
	m.set_shader_parameter("aufweitung", aufweitung)
	m.set_shader_parameter("wind", wind)
	m.set_shader_parameter("neigung", neigung)
	m.set_shader_parameter("biegung", biegung)
	m.set_shader_parameter("schirm_l", schirm_l)
	m.set_shader_parameter("schirm_b", schirm_b)
	m.set_shader_parameter("schirm_zeit", schirm_zeit)
	m.set_shader_parameter("fern_ende", fern_ende)
	m.set_shader_parameter("rand_tiefe", rand_tiefe)
	# Werte der alten Aschesaeule (CloudField.fahne mit "asche"): kein Himmelsblau, kein blauer
	# Schattenton, wenig Silberrand, schmaler weicher Rand
	m.set_shader_parameter("helligkeit", 0.40)
	m.set_shader_parameter("himmel_misch", 0.0)
	m.set_shader_parameter("schatten_ton", Vector3(0.115, 0.10, 0.10))
	m.set_shader_parameter("silber", 0.12)
	m.set_shader_parameter("rand_weich", 0.08)
	m.set_shader_parameter("nah_dunst", 0.12)
	m.set_shader_parameter("falten", 0.34)
	# Krume schwaecher: aus der Naehe lagen die Ballen sonst gefleckt wie Felsbrocken da
	m.set_shader_parameter("krume", 0.16)
	m.set_shader_parameter("blitz_farbe", Color(0.86, 0.90, 1.0))
	m.set_shader_parameter("eigener_nebel", true)
	m.set_shader_parameter("himmel_fern", 0.0)
	_wolken_mats.append(m)
	return m


## Ballen-Netze: dieselbe Kumulusform und dieselben Kugeln wie die Wolken. Mit groeberen Kugeln
## (14x7 statt 20x10) standen die Ballen aus der Naehe als Vielecke da; die LOD-Stufen der Netze
## (CloudField._nachbearbeiten) sparen in der Ferne.
func _ballen_formen(n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4411
	var kern := CloudField._kugel(20, 10)
	var schulter := CloudField._kugel(14, 7)
	var knubbel := CloudField._kugel(8, 4)
	var formen: Array = []
	for i in n:
		formen.append(CloudField._puff_mesh("kumulus", kern, schulter, knubbel, rng))
	return formen


## Eine Ballengruppe: je Form eine MultiMesh, Instanzen als EINHEITSBALLEN um ihre Mitte (Drehung um
## die Hochachse, Groesse 1), INSTANCE_CUSTOM = (Phase, Groesse, quer a, quer b).
func _ballen_gruppe(name_: String, mat: ShaderMaterial, formen: Array, customs: Array[Color],
		huelle: AABB) -> void:
	var je_form: Array = []
	for f in formen.size():
		je_form.append([])
	for i in customs.size():
		(je_form[i % formen.size()] as Array).append(customs[i])
	for f in formen.size():
		var liste: Array = je_form[f]
		if liste.is_empty():
			continue
		var mesh: Mesh = formen[f]
		var ab := mesh.get_aabb()
		var halb := maxf(ab.size.x, ab.size.z) * 0.5
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = liste.size()
		for i in liste.size():
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE / halb)
			mm.set_instance_transform(i, Transform3D(b, -(b * ab.get_center())))
			mm.set_instance_custom_data(i, liste[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [name_, f]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = huelle
		mmi.lod_bias = CloudField.PUFF_LOD_BIAS
		add_child(mmi)


func _saeule_bauen() -> void:
	var formen := _ballen_formen(4)
	var r_top := r_schlot + aufweitung * steig_h
	var top := Vector2(wind.x, wind.y) * neigung * steig_h
	var ende := Vector2(wind.x, wind.y) * (neigung * steig_h + schirm_l)
	var lo := Vector3(minf(minf(top.x, ende.x), 0.0) - schirm_b - 2.0 * r_top, -200.0,
		minf(minf(top.y, ende.y), 0.0) - schirm_b - 2.0 * r_top)
	var hi := Vector3(maxf(maxf(top.x, ende.x), 0.0) + schirm_b + 2.0 * r_top, steig_h + 1400.0,
		maxf(maxf(top.y, ende.y), 0.0) + schirm_b + 2.0 * r_top)
	var huelle := AABB(schlot + lo, hi - lo)
	# Saeule: Phasen GESCHICHTET (i/N + wenig Streuung) — mit freiem Zufall klafften unten Luecken
	var cs: Array[Color] = []
	for i in SAEULE_N:
		var q := _scheibe()
		cs.append(Color((float(i) + _rng.randf() * 0.7) / float(SAEULE_N), _rng.randf_range(0.80, 1.30), q.x, q.y))
	_ballen_gruppe("Saeule", _asche_material(0), formen, cs, huelle)
	cs = []
	for i in SCHIRM_N:
		cs.append(Color((float(i) + _rng.randf() * 0.7) / float(SCHIRM_N), _rng.randf_range(0.75, 1.20),
			_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)))
	_ballen_gruppe("Schirm", _asche_material(1), formen, cs, huelle)
	for f in 2:
		cs = []
		for i in WOLKE_N:
			var q := _scheibe()
			cs.append(Color(_rng.randf(), _rng.randf_range(0.75, 1.25), q.x, q.y))
		var m := _asche_material(2)
		(_stoss_mats[f] as Array).append(m)
		_ballen_gruppe("Ausbruchswolke%d" % f, m, formen, cs, huelle)


func _scheibe() -> Vector2:
	var w := _rng.randf() * TAU
	var r := sqrt(_rng.randf())
	return Vector2(cos(w), sin(w)) * r


# --- LAVABOMBEN, FEUERBALL, RAUCHSPUREN ------------------------------------------------------
func _tafel_multimesh(name_: String, mat: ShaderMaterial, customs: Array[Color], groesse: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = customs.size()
	for i in customs.size():
		# Einheitslage setzen: ungesetzt ist die Instanz eine NULL-Matrix und wird nicht gezeichnet
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(schlot - Vector3(groesse, 900.0, groesse), Vector3(groesse * 2.0, 3800.0, groesse * 2.0))
	add_child(mmi)


func _bomben_material(shader_pfad: String, profil: PackedFloat32Array) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(shader_pfad)
	m.set_shader_parameter("schlot", schlot)
	m.set_shader_parameter("wind", wind)
	m.set_shader_parameter("vb_profil", profil)
	m.set_shader_parameter("vb_profil_r", 2400.0)
	m.set_shader_parameter("rand_tiefe", rand_tiefe)
	return m


func _bomben_bauen(profil: PackedFloat32Array) -> void:
	for f in 2:
		var mb := _bomben_material("res://shaders/vulkan_bomben.gdshader", profil)
		var cs: Array[Color] = []
		for i in BOMBEN_N:
			cs.append(Color(float(i), 0.0, 0.0, 0.0))
		for i in FEUERBALL_N:
			cs.append(Color(_rng.randf(), 1.0, _rng.randf(), _rng.randf()))
		_tafel_multimesh("Lavabomben%d" % f, mb, cs, 3600.0)
		var mr := _bomben_material("res://shaders/vulkan_rauch.gdshader", profil)
		mr.set_shader_parameter("modus", 1)
		cs = []
		for b in SPUR_BOMBEN:
			for j in SPUR_N:
				cs.append(Color(float(b), float(j), _rng.randf(), _rng.randf()))
		_tafel_multimesh("Rauchspuren%d" % f, mr, cs, 3600.0)
		(_stoss_mats[f] as Array).append(mb)
		(_stoss_mats[f] as Array).append(mr)


# --- FUMAROLEN UND LAVADAMPF -----------------------------------------------------------------
## Fumarolen: sechs am Kraterrand. Lavadampf: die heissesten Stellen der Stroeme, aus derselben Haut
## gelesen, die das Gelaende faerbt (TerrainWorld._vulkan_haut, Alpha = 1 − Glut).
func _quellen_bauen(terrain: TerrainWorld, ms: Dictionary) -> void:
	var quellen: Array[Vector4] = []
	for i in 6:
		var w := TAU * (float(i) + _rng.randf() * 0.6) / 6.0
		var r := krater_r * _rng.randf_range(0.92, 1.12)
		var x := schlot.x + cos(w) * r
		var z := schlot.z + sin(w) * r
		quellen.append(Vector4(x, terrain.height_at(x, z) - 2.0, z, _rng.randf_range(0.7, 1.15)))
	var heiss: Array = []
	if not terrain._vulkane.is_empty():
		var vk: Dictionary = terrain._vulkane[0]
		var mr := float(ms.get("r", 1750.0))
		var r := krater_r * 1.15
		while r < mr * 0.95:
			for k in 72:
				var w := TAU * float(k) / 72.0
				var ux := cos(w)
				var uz := sin(w)
				var x := schlot.x + ux * r
				var z := schlot.z + uz * r
				var cen := Vector3(x, terrain.height_at(x, z), z)
				var haut: Color = terrain._vulkan_haut(vk, cen, r, ux, uz, 0.85)
				var glut := 1.0 - haut.a
				if glut > 0.30:
					heiss.append([glut, cen])
			r += 32.0
	heiss.sort_custom(func(a, b): return a[0] > b[0])
	var gewaehlt: Array[Vector3] = []
	for h in heiss:
		if gewaehlt.size() >= 10:
			break
		var p: Vector3 = h[1]
		var frei := true
		for g in gewaehlt:
			if Vector2(g.x - p.x, g.z - p.z).length() < 260.0:
				frei = false
				break
		if frei:
			gewaehlt.append(p)
			quellen.append(Vector4(p.x, p.y, p.z, -0.75))
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/vulkan_rauch.gdshader")
	m.set_shader_parameter("modus", 0)
	m.set_shader_parameter("wind", wind)
	m.set_shader_parameter("schlot", schlot)
	var arr := PackedVector4Array()
	for q in quellen:
		arr.append(q)
	while arr.size() < 16:
		arr.append(Vector4(0, -10000, 0, 0))
	m.set_shader_parameter("quellen", arr)
	var cs: Array[Color] = []
	for qi in quellen.size():
		for j in DAMPF_JE_QUELLE:
			cs.append(Color(float(qi), (float(j) + _rng.randf() * 0.5) / float(DAMPF_JE_QUELLE), _rng.randf(), _rng.randf()))
	_tafel_multimesh("Dampf", m, cs, 2200.0)
	print("Vulkanausbruch: %d Fumarolen, %d Lavadampfquellen" % [6, gewaehlt.size()])


# --- LAVAFONTAENE (Funken-Partikel) ----------------------------------------------------------
func _funken_bauen() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vulkan_funke.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = mat
	var bahn := ShaderMaterial.new()
	bahn.shader = load("res://shaders/vulkan_funken_bahn.gdshader")
	bahn.set_shader_parameter("schlot_r", krater_r * 0.10)
	_funken = GPUParticles3D.new()
	_funken.name = "Funken"
	_funken.amount = 1600
	_funken.lifetime = 8.5
	_funken.preprocess = 8.5
	_funken.randomness = 0.6
	_funken.explosiveness = 0.0
	_funken.process_material = bahn
	_funken.draw_pass_1 = quad
	_funken.local_coords = true
	_funken.visibility_aabb = AABB(Vector3(-krater_r * 2.0, -80.0, -krater_r * 2.0),
		Vector3(krater_r * 4.0, krater_r * 4.0, krater_r * 4.0))
	_funken.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_funken.visibility_range_end = 12000.0
	_funken.position = schlot + Vector3(0.0, 10.0, 0.0)
	add_child(_funken)


# --- VULKANBLITZE ----------------------------------------------------------------------------
## Blitze in der Asche laufen in alle Richtungen und verzweigen sich (Reibung der Aschekoerner) —
## anders als die Gewitterblitze nicht vom Himmel zum Boden.
func _blitze_bauen() -> void:
	_blitz_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled;\n" \
		+ "uniform float hell = 1.0;\n" \
		+ "void fragment() { ALBEDO = vec3(4.6, 4.2, 6.8) * hell; }\n"
	_blitz_mat.shader = sh
	for i in 6:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_blitz_ast(st, Vector3.ZERO, Vector3(_rng.randf_range(-0.4, 0.4), -1.0, _rng.randf_range(-0.4, 0.4)).normalized(),
			_rng.randf_range(260.0, 620.0), 2.6, 0)
		var mi := MeshInstance3D.new()
		mi.name = "Vulkanblitz%d" % i
		mi.mesh = st.commit()
		mi.material_override = _blitz_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_blitze.append(mi)


func _blitz_ast(st: SurfaceTool, start: Vector3, richtung: Vector3, laenge: float, breite: float, tiefe: int) -> void:
	var p := start
	var weg := 0.0
	while weg < laenge:
		var schritt := _rng.randf_range(18.0, 46.0)
		var dir := (richtung + Vector3(_rng.randf_range(-0.7, 0.7), _rng.randf_range(-0.5, 0.5),
			_rng.randf_range(-0.7, 0.7))).normalized()
		var q := p + dir * schritt
		var b := breite * (1.0 - weg / laenge * 0.6)
		for quer in [Vector3(b, 0, 0), Vector3(0, 0, b), Vector3(0, b, 0)]:
			var qv: Vector3 = quer
			st.add_vertex(p - qv); st.add_vertex(p + qv); st.add_vertex(q + qv)
			st.add_vertex(p - qv); st.add_vertex(q + qv); st.add_vertex(q - qv)
		if tiefe < 2 and _rng.randf() < 0.16:
			var neu := (richtung + Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-0.6, 0.6),
				_rng.randf_range(-1.2, 1.2))).normalized()
			_blitz_ast(st, q, neu, (laenge - weg) * _rng.randf_range(0.3, 0.6), b * 0.55, tiefe + 1)
		p = q
		weg += schritt


# --- DRUCKWELLE ------------------------------------------------------------------------------
const WELLE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform float staerke = 0.0;
void fragment() {
	// nur der duenne Saum der Kugel (dicker wirkte sie wie eine Glaskuppel)
	float rand = pow(1.0 - abs(dot(NORMAL, VIEW)), 7.0);
	ALBEDO = vec3(0.95, 0.93, 0.90);
	ALPHA = rand * staerke;
}
"""


func _welle_bauen() -> void:
	var kugel := SphereMesh.new()
	kugel.radius = 1.0
	kugel.height = 2.0
	kugel.radial_segments = 48
	kugel.rings = 24
	_welle_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WELLE_SHADER
	_welle_mat.shader = sh
	_welle = MeshInstance3D.new()
	_welle.name = "Druckwelle"
	_welle.mesh = kugel
	_welle.material_override = _welle_mat
	_welle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_welle.position = schlot + Vector3(0.0, rand_tiefe * 0.8, 0.0)
	_welle.visible = false
	add_child(_welle)


# --- ASCHEREGEN unter dem Schirm -------------------------------------------------------------
const REGEN_SHADER := """
shader_type spatial;
// EIGENER DUNST (fog_disabled): mit Godots Nebel nahm der duenne dunkle Schleier auf 5-8 km fast nur
// noch die blaue Dunstfarbe an und stand als Lichtstrahlen unter dem Schirm.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// HELLES Graubraun: Asche streut Licht. Dunkel und duenn verdunkelte der Schleier nur das Himmelsblau
// — er stand als blaue Lichtstrahlen da.
uniform vec3 farbe : source_color = vec3(0.47, 0.42, 0.38);
float h(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float rausch(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(h(i), h(i + 1.0), f * f * (3.0 - 2.0 * f));
}
void fragment() {
	// UV.x laeuft rundum, UV.y von oben (0) nach unten (1). WEICHE Schleier statt Streifen: die erste
	// Fassung (Strichmuster wie der Gewitterregen) stand als gestreifter Glaskasten in der Luft.
	float u = UV.x * 6.0 + UV.y * 0.8;
	float schleier = rausch(u * 3.0 + TIME * 0.02) * 0.6 + rausch(u * 7.0 - TIME * 0.035) * 0.4;
	schleier = smoothstep(0.30, 0.85, schleier);
	// laengere und kuerzere Faeden: jeder Schleier endet auf einer anderen Hoehe
	float ende = mix(0.45, 0.95, rausch(u * 3.0 + 11.0));
	float unten = 1.0 - smoothstep(ende - 0.35, ende, UV.y);
	float oben = smoothstep(0.0, 0.12, UV.y);
	float rand = smoothstep(0.15, 0.85, abs(dot(NORMAL, VIEW)));
	float fern = 1.0 - smoothstep(5000.0, 13000.0, length(VERTEX)) * 0.7;
	ALBEDO = farbe;
	ALPHA = 0.50 * schleier * oben * unten * rand * fern;
}
"""


func _ascheregen_bauen() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.15
	cm.height = 1.0
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 40
	var mi := MeshInstance3D.new()
	mi.name = "Ascheregen"
	mi.mesh = cm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = REGEN_SHADER
	sm.shader = sh
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var oben := schlot.y + steig_h - 350.0
	var unten := TerrainWorld.SEA_Y
	var mitte_l := neigung * steig_h + schirm_l * 0.50
	var w3 := Vector3(wind.x, 0.0, wind.y)
	var q3 := Vector3(-wind.y, 0.0, wind.x)
	var b := Basis(w3 * schirm_l * 0.30, Vector3.UP * (oben - unten), q3 * schirm_b * 0.55)
	mi.transform = Transform3D(b, schlot + w3 * mitte_l + Vector3(0.0, (oben + unten) * 0.5 - schlot.y, 0.0))
	add_child(mi)


# --- ABLAUF ----------------------------------------------------------------------------------
func ausloesen() -> void:
	_fassung = 1 - _fassung
	_alter_ab[_fassung] = 0.0
	_alter = 0.0
	_naechster = _rng.randf_range(30.0, 60.0)
	_blitz_naechster = 0.6


func _process(delta: float) -> void:
	if _test_alter >= 0.0:
		_alter = _test_alter
		_alter_ab[_fassung] = _test_alter
	else:
		_alter += delta
		_alter_ab[0] += delta
		_alter_ab[1] += delta
		if not _ruhe:
			_naechster -= delta
			if _naechster <= 0.0:
				ausloesen()
	RenderingServer.global_shader_parameter_set("vulkan_ausbruch", _alter)
	for f in 2:
		for m in (_stoss_mats[f] as Array):
			(m as ShaderMaterial).set_shader_parameter("stoss_alter", _alter_ab[f])
	# LICHTBLITZ des Ausbruchs (nur kurz: ein OmniLight ueber dem Krater kostet ~0,85 ms)
	var hell := exp(-_alter * 2.6) * smoothstep(0.0, 0.08, _alter)
	_licht.visible = hell > 0.02
	_licht.light_energy = 16.0 * hell
	# DRUCKWELLE: Kugelschale mit Schallgeschwindigkeit, nach 3 s unsichtbar duenn
	var wa := _alter
	_welle.visible = wa < 3.2
	if _welle.visible:
		_welle.scale = Vector3.ONE * maxf(SCHALL * wa, 1.0)
		_welle_mat.set_shader_parameter("staerke", 0.85 * (1.0 - smoothstep(0.2, 2.6, wa)) * smoothstep(0.0, 0.1, wa))
	_blitze_fuehren(delta)


func _blitze_fuehren(delta: float) -> void:
	_blitz_naechster -= delta
	if _blitz_naechster <= 0.0:
		# Nach einem Ausbruch gewittert es in der Wolke, sonst nur selten
		_blitz_naechster = _rng.randf_range(0.25, 1.6) if _alter < 28.0 else _rng.randf_range(7.0, 20.0)
		_blitz_t = _rng.randf_range(0.10, 0.32)
		for b in _blitze:
			b.visible = false
		var bl: MeshInstance3D = _blitze[_rng.randi() % _blitze.size()]
		var h := _rng.randf_range(250.0, 1700.0) if _alter < 28.0 else _rng.randf_range(400.0, 2600.0)
		var hz := h / steig_h
		var r := r_schlot + aufweitung * h
		var achse := Vector2(wind.x, wind.y) * neigung * steig_h * pow(hz, biegung)
		var q := _scheibe() * r * 0.5
		bl.position = schlot + Vector3(achse.x + q.x, h, achse.y + q.y)
		bl.basis = Basis(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			_rng.randf() * TAU)
		bl.visible = true
		for m in _wolken_mats:
			m.set_shader_parameter("blitz_ort", bl.position)
			m.set_shader_parameter("blitz_r", 520.0)
	if _blitz_test:
		_blitz_t = maxf(_blitz_t, 0.2)
	if _blitz_t > 0.0:
		_blitz_t -= delta
		var f := 1.0 if _blitz_test else 0.5 + 0.5 * sin(_blitz_t * 80.0)
		var st := clampf(_blitz_t * 6.0, 0.0, 1.0) * f
		_blitz_mat.set_shader_parameter("hell", 0.4 + 0.6 * st)
		for m in _wolken_mats:
			m.set_shader_parameter("blitz", 0.45 * st)
		if _blitz_t <= 0.0:
			for b in _blitze:
				b.visible = false
			for m in _wolken_mats:
				m.set_shader_parameter("blitz", 0.0)


## EIGENER NEBEL der Saeule (Main._wolken_aufenthalt, je Frame): Godots Tiefennebel legte aus 6 km
## sein sattes Blau ueber die sonnenbeschienene Asche — sie stand lavendelfarben da. Dieselbe Kurve,
## aber die Dunstfarbe zur Haelfte entsaettigt (Asche schluckt, statt blau zu streuen).
func nebel_setzen(anfang: float, ende: float, form: float, farbe: Vector3) -> void:
	var grau := farbe.dot(Vector3(0.2126, 0.7152, 0.0722))
	var f := farbe.lerp(Vector3(grau, grau * 0.97, grau * 0.93), 0.55)
	for m in _wolken_mats:
		m.set_shader_parameter("nebel_anfang", anfang)
		m.set_shader_parameter("nebel_ende", ende)
		m.set_shader_parameter("nebel_form", form)
		m.set_shader_parameter("nebel_farbe", f)


# --- FUER DEN FLUG (Main._vulkan_im_flug) ----------------------------------------------------
## Aschedichte 0..1 am Ort: Saeule, Schirm und die Blumenkohlwolke des laufenden Ausbruchs —
## dieselben Formeln wie der Vertex-Shader (mit kleinerem Wirkkoerper, die Ballen sind Kugeln).
func dichte_bei(pos: Vector3) -> float:
	var hy := pos.y - schlot.y
	var dichte := 0.0
	var top_x := neigung * steig_h
	if hy > -100.0 and hy < steig_h * 1.05:
		var hz := clampf(hy / steig_h, 0.0, 1.0)
		var achse := Vector2(schlot.x, schlot.z) + wind * top_x * pow(hz, biegung)
		var r := r_schlot + aufweitung * maxf(hy, 0.0)
		var d := Vector2(pos.x, pos.z).distance_to(achse)
		dichte = 1.0 - smoothstep(r * 0.55, r * 1.10, d)
	var r_top := r_schlot + aufweitung * steig_h
	var rel := Vector2(pos.x - schlot.x, pos.z - schlot.z) - wind * top_x
	var laengs := rel.dot(wind)
	var quer := absf(rel.dot(Vector2(-wind.y, wind.x)))
	if laengs > -r_top and laengs < schirm_l + r_top:
		var u := clampf(laengs / schirm_l, 0.0, 1.0)
		var breit := schirm_b * sqrt(u) + r_top
		var dick := r_top * 0.62 * 1.2
		var ds := (1.0 - smoothstep(breit * 0.7, breit * 1.1, quer)) \
			* (1.0 - smoothstep(dick * 0.5, dick, absf(hy - steig_h - 80.0))) \
			* (1.0 - smoothstep(0.62, 0.85, u))
		dichte = maxf(dichte, ds)
	for f in 2:
		var a: float = _alter_ab[f]
		if a < 55.0:
			var hc := rand_tiefe * 0.55 + 2400.0 * (1.0 - exp(-a / 9.0)) * 0.78
			var weit := 560.0 * (1.0 - exp(-a / 6.5)) + 75.0 + 360.0 * (1.0 - exp(-a / 9.0))
			var m := schlot + Vector3(wind.x * a * 10.0, hc, wind.y * a * 10.0)
			var d := (pos - m) * Vector3(1.0, 0.6, 1.0)
			dichte = maxf(dichte, (1.0 - smoothstep(weit * 0.6, weit * 1.05, d.length()))
				* (1.0 - smoothstep(40.0, 55.0, a)))
	return dichte


## Aufwind (in g) ueber dem Schlot: im Kern der Saeule bis 0,7 g, unten am staerksten.
func aufwind_bei(pos: Vector3) -> float:
	var hy := pos.y - schlot.y
	if hy < -50.0 or hy > steig_h:
		return 0.0
	var hz := hy / steig_h
	var achse := Vector2(schlot.x, schlot.z) + wind * neigung * steig_h * pow(hz, biegung)
	var r := r_schlot + aufweitung * maxf(hy, 0.0)
	var d := Vector2(pos.x, pos.z).distance_to(achse)
	return 0.7 * (1.0 - smoothstep(r * 0.3, r * 0.9, d)) * (1.0 - hz * 0.6)


## Wie stark die Druckwelle diesen Ort in diesem Frame trifft (0 = gar nicht). Die Welle laeuft mit
## Schallgeschwindigkeit weiter, auch wenn die Kugelschale schon nicht mehr zu sehen ist.
func welle_trifft(pos: Vector3, delta: float) -> float:
	var d := pos.distance_to(schlot + Vector3(0.0, rand_tiefe * 0.8, 0.0))
	var r1 := SCHALL * _alter
	var r0 := SCHALL * (_alter - delta)
	if d <= r0 or d > r1 or d > 12000.0:
		return 0.0
	return clampf(1.25 - d / 6000.0, 0.15, 1.1)
