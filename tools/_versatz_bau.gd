## Kompletter Rundlauf fuer den Bau des Nutzers (cockpit_transport + fuselage_transport):
##   Ende verschieben -> Mesh messen -> SPEICHERN (Main._design_data/_write_design)
##   -> neu LADEN (Main._load_design_from) -> Mesh erneut messen.
## Deckt beide Fehler ab, die das Feature tot aussehen liessen:
##   1. "transport_tube" baute den Versatz gar nicht ins Mesh (_prism_mesh kannte ihn nicht),
##   2. die Datei transportierte sf/sb nie — nach jedem Neustart war alles wieder Null.
extends SceneTree
var f := 0

const DATEI := "user://_versatz_test.json"


func _ringmitte(teil: Node3D, hinten: bool) -> Vector3:
	var vis := teil.get_node_or_null("Visual") as Node3D
	if vis == null:
		return Vector3.INF
	var mis := vis.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		return Vector3.INF
	var m: Mesh = (mis[0] as MeshInstance3D).mesh
	var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var grenze := -9.9 if hinten else 9.9
	for v in vs:
		grenze = maxf(grenze, v.z) if hinten else minf(grenze, v.z)
	var s := Vector3.ZERO
	var n := 0
	for v in vs:
		if absf(v.z - grenze) < 0.002:
			s += v
			n += 1
	return s / maxf(float(n), 1.0)


func _erstes(bc, id: String) -> Node3D:
	for c in bc.design_root.get_children():
		if String(c.get_meta("part_id", "")) == id:
			return c
	return null


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false

	# Main OHNE _ready bauen — wir brauchen nur seine Speicher-/Ladefunktionen,
	# nicht die ganze Welt.
	var m = load("res://scripts/Main.gd").new()
	var bc := BuildController.new()
	root.add_child(bc)
	m.build_ctrl = bc

	# Der Bau des Nutzers: Transport-Cockpit + zwei Transport-Rumpfsegmente
	bc.load_design([
		{"id": "cockpit_transport", "xform": Transform3D(), "root": true},
		{"id": "fuselage_transport", "xform": Transform3D(Basis(), Vector3(0, 0, 2.4))},
		{"id": "fuselage_transport", "xform": Transform3D(Basis(), Vector3(0, 0, 4.8))},
	])
	var teil: Node3D = _erstes(bc, "fuselage_transport")
	if teil == null:
		print("kein fuselage_transport gebaut")
		quit()
		return true

	var sc: Vector3 = teil.get_meta("pscale", Vector3.ONE)
	var v0 := _ringmitte(teil, false)
	var h0 := _ringmitte(teil, true)
	print("Ruhe                  : vorn (%+.4f %+.4f)  hinten (%+.4f %+.4f)"
		% [v0.x, v0.y, h0.x, h0.y])

	# Ziehen, Schritt fuer Schritt wie _update_transform_drag
	for schritt in [Vector2(0.0, 0.15), Vector2(0.0, 0.30), Vector2(0.25, 0.30)]:
		teil.set_meta("shift_front", schritt)
		bc._rebuild_visual(teil)
		bc._apply_part_scale(teil, sc)
		var v := _ringmitte(teil, false)
		var h := _ringmitte(teil, true)
		print("ziehen auf %-11s: vorn (%+.4f %+.4f)  hinten (%+.4f %+.4f)"
			% [str(schritt), v.x, v.y, h.x, h.y])

	bc._notify_changed()          # Auto-Taper laeuft mit, darf nichts wegbuegeln
	var v1 := _ringmitte(teil, false)
	var h1 := _ringmitte(teil, true)
	print("nach _notify_changed  : vorn (%+.4f %+.4f)  hinten (%+.4f %+.4f)"
		% [v1.x, v1.y, h1.x, h1.y])

	# --- Speichern und frisch laden -------------------------------------------------
	var ok_schreiben: bool = m._write_design(DATEI)
	var roh := FileAccess.get_file_as_string(DATEI)
	var hat_sf: bool = roh.find("\"sf\"") >= 0
	print("")
	print("geschrieben: %s | Datei enthaelt \"sf\": %s" % [str(ok_schreiben), str(hat_sf)])

	var ok_laden: bool = m._load_design_from(DATEI)
	var teil2: Node3D = _erstes(bc, "fuselage_transport")
	var v2 := _ringmitte(teil2, false)
	var h2 := _ringmitte(teil2, true)
	print("nach Neuladen         : vorn (%+.4f %+.4f)  hinten (%+.4f %+.4f)   (geladen: %s)"
		% [v2.x, v2.y, h2.x, h2.y, str(ok_laden)])
	print("Meta nach Neuladen    : sf=%s" % str(teil2.get_meta("shift_front", Vector2.ZERO)))

	var wandert: bool = absf(v1.y - v0.y) > 0.05 and absf(v1.x - v0.x) > 0.05
	var steht: bool = absf(h1.y - h0.y) < 0.001 and absf(h1.x - h0.x) < 0.001
	var ueberlebt: bool = absf(v2.y - v1.y) < 0.001 and absf(v2.x - v1.x) < 0.001
	print("")
	print("vordere Flaeche wandert     : ", "JA" if wandert else "NEIN")
	print("hintere Flaeche steht still : ", "JA" if steht else "NEIN")
	print("ueberlebt Speichern/Laden   : ", "JA" if ueberlebt else "NEIN")
	print("URTEIL: ", "OK" if (wandert and steht and ueberlebt) else "FEHLER")
	quit()
	return true
