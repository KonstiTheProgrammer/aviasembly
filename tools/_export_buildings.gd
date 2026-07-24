## Exportiert die prozeduralen LANDMARKS-Gebaeude als glTF -> Quelle fuer
## blender_lib/gebaeude.blend (tools/build_gebaeude_blend.py macht daraus die .blend).
## Gruppen: Stadt / Bergdorf / Luftschiff_Fabrik / Leuchtturm / Windrad / Bruecke /
## Haus_A..L (Einzelbausteine).
extends SceneTree
var f := 0
func _grp(root: Node3D, nm: String, px: float) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = Vector3(px, 0, 0)
	root.add_child(n)
	return n
func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var root := Node3D.new()
	get_root().add_child(root)
	Landmarks.build_town(_grp(root, "Stadt", 0.0), Vector3.ZERO)
	Landmarks.build_village(_grp(root, "Bergdorf", 420.0), Vector3.ZERO)
	Landmarks.build_lighthouse(_grp(root, "Leuchtturm", 700.0), Vector3.ZERO)
	Landmarks.build_windmill(_grp(root, "Windrad", 800.0), Vector3.ZERO, 0.6)
	Landmarks.build_bridge(_grp(root, "Bruecke", 900.0), Vector3.ZERO, 40.0, 0.0)
	Landmarks.build_airship_factory(_grp(root, "Luftschiff_Fabrik", 1020.0), Vector3.ZERO)
	# Zwölf Einzelhaus-Varianten: je zwei Größen/Farbvarianten der sechs Silhouetten.
	var walls := [Color(0.87, 0.83, 0.74), Color(0.80, 0.55, 0.42), Color(0.72, 0.74, 0.69),
		Color(0.86, 0.79, 0.62), Color(0.68, 0.64, 0.62), Color(0.78, 0.70, 0.66)]
	for i in 12:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + i * 77
		var hn := _grp(root, "Haus_" + String.chr(65 + i), 1120.0 + float(i) * 24.0)
		var roof := Landmarks._mat(Color(0.47, 0.27, 0.22) if i % 2 == 0 else Color(0.34, 0.36, 0.41))
		Landmarks._house(hn, Vector3.ZERO, rng, walls, roof, i % Landmarks.HOUSE_STYLE_COUNT,
			i % Landmarks.HOUSE_STYLE_COUNT == Landmarks.HOUSE_CHALET)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var e1 := doc.append_from_scene(root, st)
	var e2 := doc.write_to_filesystem(st, "C:/Users/Konst/Projects/aviasembly/blender_lib/_gebaeude_export.glb")
	print("EXPORT append=", e1, " write=", e2)
	quit()
	return false
