## PACKT die Bodentexturen (tools/build_bodentexturen.py -> tools/bodentexturen/*.png) als
## Bilder mit Mipmaps nach shaders/boden/:
##   <material>_farbe.res    RGBA8: Farbfaktor/2 (RGB), Hoehe (A)
##   <material>_normale.res  RGBA8: Normale u, v (RG), Hohlkehle (B)
## TerrainWorld.boden_material() baut daraus zwei Texture2DArrays, Ebenen in der Reihenfolge
## MATERIALIEN (= TerrainWorld.BODEN_MATERIALIEN = MAT_* in gelaende_kern).
## FALLE: ein Texture2DArray selbst laesst sich nicht mit Bilddaten speichern (ResourceSaver
## schrieb 185 Bytes) — deshalb die Einzelbilder.
##
##   python3 tools/build_bodentexturen.py && \
##   Godot --headless --path . --script res://tools/_bodentexturen.gd
extends SceneTree

const MATERIALIEN := ["gras", "waldboden", "erde", "sand", "fels", "schnee"]
const QUELLE := "res://tools/bodentexturen/"


func _initialize() -> void:
	var farben: Array[Image] = []
	var normalen: Array[Image] = []
	for m in MATERIALIEN:
		var f := Image.load_from_file(ProjectSettings.globalize_path(QUELLE + m + "_farbe.png"))
		var n := Image.load_from_file(ProjectSettings.globalize_path(QUELLE + m + "_normale.png"))
		if f == null or n == null:
			push_error("fehlt: " + m)
			quit(1)
			return
		f.convert(Image.FORMAT_RGBA8)
		n.convert(Image.FORMAT_RGBA8)
		f.generate_mipmaps()
		n.generate_mipmaps()
		farben.append(f)
		normalen.append(n)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shaders/boden"))
	var fehler := 0
	for i in MATERIALIEN.size():
		fehler += ResourceSaver.save(farben[i], "res://shaders/boden/%s_farbe.res" % MATERIALIEN[i],
			ResourceSaver.FLAG_COMPRESS)
		fehler += ResourceSaver.save(normalen[i], "res://shaders/boden/%s_normale.res" % MATERIALIEN[i],
			ResourceSaver.FLAG_COMPRESS)
	print("BODENTEXTUREN %d Materialien %dx%d, Mipmaps %d, Fehler %d" % [
		farben.size(), farben[0].get_width(), farben[0].get_height(),
		farben[0].get_mipmap_count(), fehler])
	quit()
