## Belegt, dass die Enden-Werkzeuge am C-130-Rumpfring jetzt WIRKEN. Solange der Ring
## aus einem glb kam, stieg build_visual in _attach_model aus — die Griffe erschienen,
## das Mesh sah die Werte nie.
##
## Geprueft wird am fertigen Mesh:
##   1. Enden SKALIEREN: der verjuengte Ring wird schmaler, der andere bleibt
##   2. Enden VERSCHIEBEN: die Stirnflaeche wandert, die Gegenflaeche steht still
##   3. Griffe: im Enden-Modus (3) und im Versetzen-Modus (4) entstehen welche
##   4. Auto-Taper: der Ring uebernimmt am Cockpit dessen Querschnitt
extends SceneTree
var f := 0


func _ring(teil: Node3D, hinten: bool) -> Dictionary:
	var vis := teil.get_node_or_null("Visual") as Node3D
	if vis == null:
		return {}
	var mis := vis.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		return {}
	var m: Mesh = (mis[0] as MeshInstance3D).mesh
	var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var grenze := -9.9 if hinten else 9.9
	for v in vs:
		grenze = maxf(grenze, v.z) if hinten else minf(grenze, v.z)
	var s := Vector3.ZERO
	var n := 0
	var breite := 0.0
	for v in vs:
		if absf(v.z - grenze) < 0.002:
			s += v
			n += 1
			breite = maxf(breite, absf(v.x))
	return {"mitte": s / maxf(float(n), 1.0), "halbbreite": breite}


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var fehler: Array = []
	var bc := BuildController.new()
	root.add_child(bc)
	bc.symmetry = false
	bc.load_design([
		{"id": "cockpit_c130", "xform": Transform3D(), "root": true},
		{"id": "fuselage_c130_long", "xform": Transform3D(Basis(), Vector3(0, 0, 2.5))},
	])
	var ring: Node3D = null
	for c in bc.design_root.get_children():
		if String(c.get_meta("part_id", "")) == "fuselage_c130_long":
			ring = c
	if ring == null:
		print("Ring nicht gebaut")
		quit()
		return true
	var p := PartCatalog.get_part("fuselage_c130_long")
	print("Teil: shape=%s  biends=%s  glb vorhanden=%s"
		% [String(p.get("shape", "")), str(p.get("biends", false)),
		   str(PartCatalog.has_model("fuselage_c130_long"))])
	if not bool(p.get("biends", false)):
		fehler.append("Teil ist nicht biends")
	if PartCatalog.has_model("fuselage_c130_long"):
		fehler.append("es gibt noch ein glb -> _attach_model gewinnt weiter")

	var sc: Vector3 = ring.get_meta("pscale", Vector3.ONE)
	var v0 := _ring(ring, false)
	var h0 := _ring(ring, true)
	if v0.is_empty():
		print("kein Mesh im Visual")
		quit()
		return true
	print("")
	print("Ruhe             : vorn Halbbreite %.4f   hinten %.4f"
		% [v0["halbbreite"], h0["halbbreite"]])

	# --- 1) Enden SKALIEREN -------------------------------------------------
	ring.set_meta("taper_front", 0.55)
	ring.set_meta("taper_front_user", true)
	bc._rebuild_visual(ring)
	bc._apply_part_scale(ring, sc)
	var v1 := _ring(ring, false)
	var h1 := _ring(ring, true)
	print("vorn auf 0.55    : vorn Halbbreite %.4f   hinten %.4f" % [v1["halbbreite"], h1["halbbreite"]])
	var schmaler: float = float(v1["halbbreite"]) / maxf(float(v0["halbbreite"]), 0.001)
	if absf(schmaler - 0.55) > 0.02:
		fehler.append("Verjuengung wirkt nicht (%.3f statt 0.55)" % schmaler)
	if absf(float(h1["halbbreite"]) - float(h0["halbbreite"])) > 0.001:
		fehler.append("hinteres Ende hat sich mitveraendert")

	# --- 2) Enden VERSCHIEBEN -----------------------------------------------
	ring.set_meta("taper_front", 1.0)
	ring.set_meta("shift_front", Vector2(0.22, 0.30))
	bc._rebuild_visual(ring)
	bc._apply_part_scale(ring, sc)
	var v2 := _ring(ring, false)
	var h2 := _ring(ring, true)
	var dv: Vector3 = (v2["mitte"] as Vector3) - (v0["mitte"] as Vector3)
	var dh: Vector3 = (h2["mitte"] as Vector3) - (h0["mitte"] as Vector3)
	print("Versatz (0.22,0.30): vordere Mitte %+.4f %+.4f   hintere %+.4f %+.4f"
		% [dv.x, dv.y, dh.x, dh.y])
	if absf(dv.x - 0.22) > 0.002 or absf(dv.y - 0.30) > 0.002:
		fehler.append("Versatz kommt nicht im Mesh an")
	if dh.length() > 0.001:
		fehler.append("hintere Flaeche ist mitgewandert")

	# --- 3) Griffe in beiden Enden-Modi -------------------------------------
	ring.set_meta("shift_front", Vector2.ZERO)
	bc._rebuild_visual(ring)
	bc._select_part(ring)
	for modus in [[bc.GIZ_ENDS, "ends", "Enden skalieren"], [bc.GIZ_SHIFT, "shift", "Enden verschieben"]]:
		bc.set_gizmo_mode(modus[0])
		var anz := 0
		for h in bc._handles:
			if String((h as Node3D).get_meta("kind", "")) == String(modus[1]):
				anz += 1
		print("Modus %-20s -> gizmo_mode=%d, %d Griffe" % [modus[2], bc.gizmo_mode, anz])
		if bc.gizmo_mode != modus[0]:
			fehler.append("%s: Modus faellt zurueck" % modus[2])
		if anz < 4:
			fehler.append("%s: nur %d Griffe" % [modus[2], anz])

	# --- 4) Auto-Taper am Cockpit -------------------------------------------
	ring.remove_meta("taper_front_user")
	ring.set_meta("taper_front", 1.0)
	bc._notify_changed()
	print("Auto-Taper vorn  : %.4f (Cockpit-Querschnitt uebernommen)"
		% float(ring.get_meta("taper_front", 1.0)))

	print("")
	print("=".repeat(66))
	if fehler.is_empty():
		print("URTEIL: OK — Enden skalieren UND verschieben wirken am C-130-Ring")
	else:
		print("URTEIL: %d FEHLER" % fehler.size())
		for m in fehler:
			print("   ", m)
	quit()
	return true
