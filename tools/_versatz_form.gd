# Beweist, dass der Enden-Versatz bei JEDER biends-Form im MESH ankommt.
# Kern der Zusage: die versetzte Stirnflaeche wandert, die gegenueberliegende bleibt
# exakt stehen, der Mantel dazwischen wird schraeg. Genau das wird hier je Form gemessen —
# vorher verschluckten "transport_tube" (der Bau des Nutzers!) und "prism" den Versatz.
extends SceneTree

const FORMEN: Array = ["fuselage", "fuselage_reto", "fuselage_radial",
	"fuselage_transport", "fuselage_long", "fuselage_wide", "fuselage_taper",
	"f22_fuselage"]

const VERSATZ := 0.30    # Teil-Einheiten, quer nach oben (+Y)


# Mittelpunkt und Spanne der Verts einer Stirnflaeche (vorne = kleinstes z, hinten = groesstes)
func _stirn(v: Node3D, vorne: bool) -> Dictionary:
	var pts: Array = []
	var stapel: Array = [v]
	while not stapel.is_empty():
		var n: Node = stapel.pop_back()
		for c in n.get_children():
			stapel.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var xf: Transform3D = mi.transform
			var p: Node = mi.get_parent()
			while p != null and p != v:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			for s in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(s)
				for pv in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					pts.append(xf * pv)
	if pts.is_empty():
		return {}
	var zmin := INF
	var zmax := -INF
	for p2 in pts:
		zmin = minf(zmin, (p2 as Vector3).z)
		zmax = maxf(zmax, (p2 as Vector3).z)
	var ziel: float = zmin if vorne else zmax
	var summe := Vector3.ZERO
	var anz := 0
	for p3 in pts:
		if absf((p3 as Vector3).z - ziel) < 0.02:
			summe += p3
			anz += 1
	return {"mitte": summe / maxf(float(anz), 1.0), "anz": anz}


func _initialize() -> void:
	print("Form                    | vorne dy  hinten dy | Urteil")
	print("------------------------+---------------------+--------")
	var alles_ok := true
	for id in FORMEN:
		var p: Dictionary = PartCatalog.get_part(id)
		var ruhe: Node3D = PartCatalog.build_visual(p)
		var v0: Dictionary = _stirn(ruhe, true)
		var h0: Dictionary = _stirn(ruhe, false)
		# NUR das vordere Ende nach oben versetzen
		var vers: Node3D = PartCatalog.build_visual(p, Color(0, 0, 0, 0), 1.0, 1.0, -1.0,
			-1.0, Vector2(0.0, VERSATZ), Vector2.ZERO)
		var v1: Dictionary = _stirn(vers, true)
		var h1: Dictionary = _stirn(vers, false)
		if v0.is_empty() or v1.is_empty():
			print("%-23s |  KEIN MESH GEFUNDEN" % id)
			alles_ok = false
			continue
		var dv: float = (v1["mitte"] as Vector3).y - (v0["mitte"] as Vector3).y
		var dh: float = (h1["mitte"] as Vector3).y - (h0["mitte"] as Vector3).y
		# erwartet: vorne wandert (>0), hinten steht still (==0)
		var ok: bool = dv > 0.05 and absf(dh) < 0.001
		alles_ok = alles_ok and ok
		print("%-23s | %+8.4f  %+8.4f | %s" % [id, dv, dh, "OK" if ok else "FEHLER"])
		ruhe.free()
		vers.free()
	print("")
	print("GESAMT: ", "alle Formen setzen den Versatz um" if alles_ok else "MINDESTENS EINE FORM IGNORIERT IHN")
	quit()
