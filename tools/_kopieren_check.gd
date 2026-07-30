## Prueft zwei Dinge:
##  1) Die Versatz-Griffe sehen aus wie die Bewegen-Pfeile (Schaft + Kegelspitze) und
##     ihre Klickboxen ueberlappen sich NICHT (daran starb der Versatz schon einmal).
##  2) Strg+C / Strg+V uebernimmt die FORMUNG mit — Verjuengung, Enden-Versatz,
##     Eckrundung, Beinlaenge. Vorher trug duplicate_selected nur Farbe und Groesse.
extends SceneTree
var f := 0


func _teile(bc, id: String) -> Array:
	var out: Array = []
	for c in bc.design_root.get_children():
		if String(c.get_meta("part_id", "")) == id:
			out.append(c)
	return out


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var bc := BuildController.new()
	root.add_child(bc)
	bc.load_design([
		{"id": "cockpit_transport", "xform": Transform3D(), "root": true},
		{"id": "fuselage_transport", "xform": Transform3D(Basis(), Vector3(0, 0, 2.4))},
	])
	var teil: Node3D = _teile(bc, "fuselage_transport")[0]

	# --- 1) Griff-Aussehen und Abstaende -------------------------------------------
	print("=== 1) Versatz-Griffe ===")
	bc._select_part(teil)
	bc.set_gizmo_mode(bc.GIZ_SHIFT)
	var griffe: Array = []
	for h in bc._handles:
		if String((h as Node3D).get_meta("kind", "")) == "shift":
			griffe.append(h)
	print("  Anzahl Versatz-Griffe: %d (erwartet 4)" % griffe.size())
	var alle_pfeile := true
	for h in griffe:
		var boxen := 0
		var kegel := 0
		for c in (h as Node3D).get_children():
			if c is MeshInstance3D:
				var m: Mesh = (c as MeshInstance3D).mesh
				if m is BoxMesh:
					boxen += 1
				elif m is CylinderMesh and (m as CylinderMesh).top_radius == 0.0:
					kegel += 1
		if boxen != 1 or kegel != 1:
			alle_pfeile = false
			print("  FEHLER an Griff: Schaefte=%d Spitzen=%d" % [boxen, kegel])
	print("  jeder Griff = Schaft + Kegelspitze: ", "JA" if alle_pfeile else "NEIN")

	var min_abstand := INF
	for a in griffe.size():
		for b in range(a + 1, griffe.size()):
			var pa: Vector3 = (griffe[a] as Node3D).global_position
			var pb: Vector3 = (griffe[b] as Node3D).global_position
			min_abstand = minf(min_abstand, pa.distance_to(pb))
	# Klickboxen: 1.5 lang, 0.42 quer -> halbe Diagonale quer 0.30, laengs 0.75
	print("  kleinster Griff-Abstand: %.3f (Klickbox laengs +-0.75)" % min_abstand)
	var frei: bool = min_abstand > 1.5
	print("  Klickboxen ueberlappen nicht: ", "JA" if frei else "NEIN")

	# --- 2) Kopieren/Einfuegen traegt die Formung mit --------------------------------
	print("")
	print("=== 2) Strg+C / Strg+V ===")
	teil.set_meta("shift_front", Vector2(0.2, 0.35))
	teil.set_meta("taper_front", 0.6)
	teil.set_meta("taper_front_user", true)
	bc._rebuild_visual(teil)
	bc._apply_part_scale(teil, teil.get_meta("pscale", Vector3.ONE))
	bc._select_part(teil)

	var vorher: int = _teile(bc, "fuselage_transport").size()
	bc.copy_selected()
	bc.paste_clipboard()
	var liste: Array = _teile(bc, "fuselage_transport")
	print("  Teile vorher %d, nachher %d" % [vorher, liste.size()])
	if liste.size() < 2:
		print("  FEHLER: nichts eingefuegt")
		quit()
		return true
	# WICHTIG: bei Symmetrie entstehen zwei Teile (Original + Spiegel). Das eingefuegte
	# ist das ausgewaehlte; der Spiegel wird getrennt geprueft.
	var neu: Node3D = bc.selected_part
	var spiegel: Node3D = null
	for c in liste:
		if c != teil and c != neu:
			spiegel = c
	var nsf: Vector2 = neu.get_meta("shift_front", Vector2.ZERO)
	var ntf: float = neu.get_meta("taper_front", 1.0)
	var nuser: bool = neu.has_meta("taper_front_user")
	print("  Versatz vorne : %s  (erwartet (0.2, 0.35))" % str(nsf))
	print("  Verjuengung   : %.3f (erwartet 0.600)" % ntf)
	print("  manuell-Flag  : %s (erwartet true)" % str(nuser))
	var versetzt: bool = neu.position.distance_to(teil.position) > 0.5
	print("  liegt versetzt: %s (Abstand %.3f)" % [str(versetzt), neu.position.distance_to(teil.position)])
	var ausgewaehlt: bool = bc.selected_part == neu and neu != teil
	print("  neues Teil ist ausgewaehlt: ", "JA" if ausgewaehlt else "NEIN")
	var sp_ok := true
	if spiegel != null:
		var ssf: Vector2 = spiegel.get_meta("shift_front", Vector2.ZERO)
		var stf: float = spiegel.get_meta("taper_front", 1.0)
		# Der Spiegel kippt x (siehe _sync_mirror_shift)
		sp_ok = ssf.distance_to(Vector2(-0.2, 0.35)) < 0.001 and absf(stf - 0.6) < 0.001
		print("  Spiegel Versatz %s / Verjuengung %.3f (erwartet (-0.2, 0.35) / 0.600) -> %s"
			% [str(ssf), stf, "OK" if sp_ok else "FEHLER"])
	else:
		print("  kein Spiegel entstanden (Symmetrie aus)")

	var ok: bool = alle_pfeile and frei \
		and nsf.distance_to(Vector2(0.2, 0.35)) < 0.001 \
		and absf(ntf - 0.6) < 0.001 and nuser and versetzt and ausgewaehlt and sp_ok
	print("")
	print("URTEIL: ", "OK" if ok else "FEHLER")
	quit()
	return true
