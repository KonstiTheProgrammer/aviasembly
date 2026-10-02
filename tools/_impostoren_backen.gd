## IMPOSTOREN BACKEN: rendert jeden Kartenbaum (Bueschelkronen, Nadelschuerzen, Wedel) aus
## TerrainWorld.IMPOSTOR_N x IMPOSTOR_N Richtungen ueber der oberen Halbkugel — mit dem echten
## Flora-Shader im Backmodus (#define BAKE: unbeleuchtet, ROHE Farbe vor Ton und Licht bzw. die
## Weltnormale) — und speichert je Art zwei Atlanten nach shaders/impostor/:
##   <Art>_farbe.res    RGBA8, IMPOSTOR_PX je Bild, RGB = rohe Farbe (sRGB-kodiert wie COLOR),
##                      A = Deckung (achtfach ueberabgetastet)
##   <Art>_normale.res  RGBA8, IMPOSTOR_PX_N je Bild, RGB = Normale * 0.5 + 0.5
##   <Art>_rahmen.res   RGBAF, N x N: je Bild das Rechteck mit Inhalt (u0, u1, v0, v1) — der
##                      Shader schneidet die Tafel darauf zu (weniger verworfene Pixel)
## Der Impostor-Shader (TerrainWorld.IMPOSTOR_SHADER) rechnet daraus Ton je Baum, Tonkurve,
## Himmelsfuellung und Licht genau wie der Flora-Shader.
## NEU BACKEN nach jeder Aenderung an tools/build_baeume.py, build_laubtextur.py,
## TerrainWorld._weiche_krone/_karten_aufbereiten oder dem Flora-Vertex-/Fragmentteil.
## Aufruf (FENSTER, nicht headless; ~1 min):
##   HOME=<test-home> Godot --path . --script res://tools/_impostoren_backen.gd [-- Fichte,Eiche]
extends SceneTree

const N := TerrainWorld.IMPOSTOR_N
const PX := TerrainWorld.IMPOSTOR_PX
const PXN := TerrainWorld.IMPOSTOR_PX_N
const RENDER := 1024
const BAKE_LOD := 4.0

var f := 0
var tw: TerrainWorld
var vp: SubViewport
var cam: Camera3D
var mi: MeshInstance3D
var m_fest: ShaderMaterial
var m_karte: ShaderMaterial


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		_aufbauen()
	elif f == 5:
		_backen()
		quit()
		return true
	return false


func _aufbauen() -> void:
	get_root().size = Vector2i(320, 240)
	tw = TerrainWorld.new()
	tw.setup(12345, [], [], [], [])
	vp = SubViewport.new()
	vp.size = Vector2i(RENDER, RENDER)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# OHNE Physik-Interpolation (im Projekt an): sonst uebernimmt die Kamera ihre neue Lage erst
	# im naechsten Physikschritt — alle 64 Bilder zeigten dieselbe Ansicht.
	vp.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_root().add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = e
	vp.add_child(we)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	cam.current = true
	mi = MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vp.add_child(mi)
	m_fest = _backmaterial(tw._flora_mat)
	m_karte = _backmaterial(tw._flora_karten_mat)
	m_karte.set_shader_parameter("laub_atlas", TerrainWorld.laub_atlas())


func _backmaterial(vorlage: ShaderMaterial) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = vorlage.shader.code.replace("shader_type spatial;", "shader_type spatial;\n#define BAKE")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("fade_start", 1.0e6)
	m.set_shader_parameter("fade_end", 2.0e6)
	m.set_shader_parameter("wind_staerke", 0.0)
	# Backbild 1024 px fuer ~2R, im Spiel am Uebergang (KARTEN_BIS, ~420 m) ~64 px: vier
	# Mipstufen Unterschied — so deckend sehen die Laubkarten dort aus.
	m.set_shader_parameter("bake_lod", BAKE_LOD)
	return m


func _backen() -> void:
	var wahl: Array = []
	for a in OS.get_cmdline_user_args():
		wahl.append_array(String(a).split(","))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TerrainWorld.IMPOSTOR_PFAD))
	for art in tw._flora:
		var mesh: Mesh = tw._flora[art]
		if not TerrainWorld.hat_karten(mesh) or (not wahl.is_empty() and not wahl.has(art)):
			continue
		var t0 := Time.get_ticks_msec()
		mi.mesh = mesh
		for si in mesh.get_surface_count():
			mi.set_surface_override_material(si, m_karte if (mesh as ArrayMesh).surface_get_name(si) == "karten" else m_fest)
		var rahmen := TerrainWorld.impostor_rahmen(mesh)
		var mitte := Vector3(rahmen.x, rahmen.y, rahmen.z)
		var r := rahmen.w
		cam.size = 2.0 * r
		cam.near = 0.05
		cam.far = 6.0 * r
		var atlas_f := Image.create(N * PX, N * PX, false, Image.FORMAT_RGBA8)
		var atlas_n := Image.create(N * PXN, N * PXN, false, Image.FORMAT_RGBA8)
		var deckung := 0.0
		for modus in [1, 2]:
			m_fest.set_shader_parameter("bake_modus", modus)
			m_karte.set_shader_parameter("bake_modus", modus)
			var px: int = PX if modus == 1 else PXN
			var atlas: Image = atlas_f if modus == 1 else atlas_n
			for j in N:
				for i in N:
					var d := TerrainWorld.impostor_richtung(i, j)
					cam.global_transform = Transform3D(TerrainWorld.impostor_basis(d), mitte + d * 3.0 * r)
					cam.force_update_transform()
					RenderingServer.force_draw(false)
					var img := vp.get_texture().get_image()
					img.convert(Image.FORMAT_RGBA8)
					# TRILINEAR = ueber die Mipmaps gemittelt (bilinear allein saehe nur 2x2 von 8x8
					# Pixeln). Der Hintergrund ist (0,0,0,0) -> das Ergebnis ist VORMULTIPLIZIERT.
					img.resize(px, px, Image.INTERPOLATE_TRILINEAR)
					atlas.blit_rect(img, Rect2i(0, 0, px, px), Vector2i(i * px, j * px))
		var rahmen_bild := _rahmen_je_bild(atlas_f)
		deckung = _aufbereiten(atlas_f)
		_aufbereiten(atlas_n)
		ResourceSaver.save(atlas_f, TerrainWorld.IMPOSTOR_PFAD + art + "_farbe.res", ResourceSaver.FLAG_COMPRESS)
		ResourceSaver.save(atlas_n, TerrainWorld.IMPOSTOR_PFAD + art + "_normale.res", ResourceSaver.FLAG_COMPRESS)
		ResourceSaver.save(rahmen_bild, TerrainWorld.IMPOSTOR_PFAD + art + "_rahmen.res", ResourceSaver.FLAG_COMPRESS)
		atlas_f.save_png("user://impostor_%s_farbe.png" % art)
		atlas_n.save_png("user://impostor_%s_normale.png" % art)
		print("IMPOSTOR %-11s Radius %5.2f m, Mitte %s, Deckung %4.1f %%, %d ms" % [art, r, mitte,
			deckung * 100.0, Time.get_ticks_msec() - t0])


## Vormultipliziert -> gerade Farbe; ganz durchsichtige Texel bekommen die Farbe der Umgebung
## (sonst zoegen Mipmaps und bilineares Filtern Schwarz in den Rand). Liefert die mittlere Deckung.
func _aufbereiten(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var klein := img.duplicate() as Image
	klein.resize(maxi(w / 16, 1), maxi(h / 16, 1), Image.INTERPOLATE_TRILINEAR)
	var kd := klein.get_data()
	var mittel := Vector3.ZERO
	var mn := 0.0
	for i in range(0, kd.size(), 4):
		var a := kd[i + 3]
		if a > 0:
			for k in 3:
				kd[i + k] = mini(255, int(kd[i + k] * 255 / a))
			mittel += Vector3(kd[i], kd[i + 1], kd[i + 2])
			mn += 1.0
	mittel /= maxf(mn, 1.0)
	for i in range(0, kd.size(), 4):
		if kd[i + 3] == 0:
			kd[i] = int(mittel.x)
			kd[i + 1] = int(mittel.y)
			kd[i + 2] = int(mittel.z)
		kd[i + 3] = 255
	klein.set_data(klein.get_width(), klein.get_height(), false, Image.FORMAT_RGBA8, kd)
	klein.resize(w, h, Image.INTERPOLATE_BILINEAR)
	kd = klein.get_data()
	var data := img.get_data()
	var summe := 0
	for i in range(0, data.size(), 4):
		var a := data[i + 3]
		summe += a
		if a == 0:
			data[i] = kd[i]
			data[i + 1] = kd[i + 1]
			data[i + 2] = kd[i + 2]
		elif a < 255:
			for k in 3:
				data[i + k] = mini(255, int(data[i + k] * 255 / a))
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)
	return float(summe) / (255.0 * float(w * h))


## Je Bild das Rechteck, in dem Deckung > 0 liegt, in Bildkoordinaten 0..1 (u0, u1, v0, v1).
func _rahmen_je_bild(atlas: Image) -> Image:
	var aus := Image.create(N, N, false, Image.FORMAT_RGBAF)
	var data := atlas.get_data()
	var breite := atlas.get_width()
	for j in N:
		for i in N:
			var x0 := PX
			var x1 := -1
			var y0 := PX
			var y1 := -1
			for y in PX:
				var zeile := ((j * PX + y) * breite + i * PX) * 4 + 3
				for x in PX:
					if data[zeile + x * 4] > 0:
						x0 = mini(x0, x)
						x1 = maxi(x1, x)
						y0 = mini(y0, y)
						y1 = maxi(y1, y)
			if x1 < 0:
				aus.set_pixel(i, j, Color(0.5, 0.5, 0.5, 0.5))
			else:
				aus.set_pixel(i, j, Color(float(x0) / PX, float(x1 + 1) / PX, float(y0) / PX, float(y1 + 1) / PX))
	return aus
