## PACKT den Laub-Atlas (tools/build_laubtextur.py -> tools/bodentexturen/laub_atlas.png)
## als Bild mit Mipmaps nach shaders/flora_laub.res (TerrainWorld laedt es fuer den Flora-
## Shader, Uniform laub_atlas).
##
##   python3 tools/build_laubtextur.py && \
##   Godot --headless --path . --script res://tools/_laubtextur.gd
extends SceneTree


func _initialize() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(
		"res://tools/bodentexturen/laub_atlas.png"))
	if img == null:
		push_error("laub_atlas.png fehlt")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var e := ResourceSaver.save(img, "res://shaders/flora_laub.res", ResourceSaver.FLAG_COMPRESS)
	print("LAUBATLAS %dx%d, Mipmaps %d, Fehler %d" % [img.get_width(), img.get_height(),
		img.get_mipmap_count(), e])
	quit()
