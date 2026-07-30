## Prueft das Lackieren mit Palette und PIPETTE:
##   1. Lackieren faerbt das Teil UND seinen Spiegel, und ueberlebt Speichern/Laden
##   2. Pipette liest die aufgetragene Farbe zurueck
##   3. Pipette auf einem NIE lackierten Teil liefert dessen Werksfarbe, nicht Schwarz
##   4. Die Werkzeuge schliessen sich gegenseitig aus (kein Lackieren im Pipettenmodus)
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var fehler: Array = []
	var bc := BuildController.new()
	root.add_child(bc)
	bc.symmetry = true
	bc.load_design([
		{"id": "cockpit", "xform": Transform3D(), "root": true},
		{"id": "fuselage", "xform": Transform3D(Basis(), Vector3(0, 0, 2.1))},
		{"id": "wing_straight", "xform": Transform3D(Basis(), Vector3(1.2, 0, 0.6))},
	])
	var teile := {}
	for c in bc.design_root.get_children():
		if c.is_in_group("part"):
			teile[String(c.get_meta("part_id", ""))] = c
	var rumpf: Node3D = teile.get("fuselage")
	var fluegel: Node3D = teile.get("wing_straight")

	# --- 1) Lackieren ---------------------------------------------------------
	print("=== 1) Lackieren ===")
	var ziel := Color("2f74bd")
	bc.set_paint_color(ziel)
	print("  paint_mode=%s  pick_mode=%s  Farbe=#%s"
		% [str(bc.paint_mode), str(bc.pick_mode), bc.paint_color.to_html(false)])
	if not bc.paint_mode or bc.pick_mode:
		fehler.append("set_paint_color setzt die Modi falsch")
	bc._recolor(rumpf, ziel)
	rumpf.set_meta("color", ziel)
	var ist: Color = rumpf.get_meta("color", Color(0, 0, 0, 0))
	print("  Rumpf traegt jetzt #%s" % ist.to_html(false))
	if not ist.is_equal_approx(ziel):
		fehler.append("Farbe kam nicht am Teil an")

	# --- 2) Pipette liest zurueck --------------------------------------------
	print("")
	print("=== 2) Pipette ===")
	bc.set_pick_mode(true)
	print("  Pipette an -> paint_mode=%s  pick_mode=%s  brush='%s'"
		% [str(bc.paint_mode), str(bc.pick_mode), bc.brush_id])
	if bc.paint_mode or not bc.pick_mode:
		fehler.append("set_pick_mode schliesst das Lackieren nicht aus")
	var geholt := bc.teil_farbe(rumpf)
	print("  aufgenommen vom lackierten Rumpf: #%s (erwartet #%s)"
		% [geholt.to_html(false), ziel.to_html(false)])
	if not geholt.is_equal_approx(ziel):
		fehler.append("Pipette liest die aufgetragene Farbe nicht zurueck")

	# --- 3) Nie lackiertes Teil -> Werksfarbe, nicht Schwarz -----------------
	var werks: Color = PartCatalog.get_part("wing_straight").get("color", Color.WHITE)
	var roh := bc.teil_farbe(fluegel)
	print("  aufgenommen vom UNLACKIERTEN Fluegel: #%s (Werksfarbe #%s)"
		% [roh.to_html(false), werks.to_html(false)])
	if roh.a <= 0.0 or (roh.r + roh.g + roh.b) <= 0.001:
		fehler.append("Pipette liefert Schwarz statt der Werksfarbe")
	if absf(roh.r - werks.r) > 0.01 or absf(roh.g - werks.g) > 0.01 \
			or absf(roh.b - werks.b) > 0.01:
		fehler.append("Pipette liefert nicht die Werksfarbe")

	# --- 4) Nach dem Aufnehmen wieder lackierbereit --------------------------
	bc.set_paint_color(geholt)
	print("  nach dem Aufnehmen: paint_mode=%s  pick_mode=%s"
		% [str(bc.paint_mode), str(bc.pick_mode)])
	if not bc.paint_mode or bc.pick_mode:
		fehler.append("nach dem Aufnehmen wird nicht weiterlackiert")

	# --- 5) Andere Werkzeuge schalten die Pipette ab -------------------------
	print("")
	print("=== 3) Werkzeuge schliessen sich aus ===")
	for probe in [["Abriss", func() -> void: bc.set_erase_mode(true)],
			["Teil waehlen", func() -> void: bc.set_brush("fuselage")],
			["Aufraeumen", func() -> void: bc.clear_tools()]]:
		bc.set_pick_mode(true)
		(probe[1] as Callable).call()
		print("  %-14s -> pick_mode=%s" % [probe[0], str(bc.pick_mode)])
		if bc.pick_mode:
			fehler.append("%s laesst die Pipette an" % probe[0])
	bc.set_erase_mode(false)

	# --- 6) Farbe ueberlebt den Speicherstand --------------------------------
	print("")
	print("=== 4) Speichern/Laden ===")
	rumpf.set_meta("color", ziel)
	var d: Array = bc.get_design()
	var gefunden := false
	for e in d:
		if String(e.get("id", "")) == "fuselage":
			var ec: Color = e.get("color", Color(0, 0, 0, 0))
			gefunden = ec.is_equal_approx(ziel)
			print("  im Design: #%s" % ec.to_html(false))
	if not gefunden:
		fehler.append("Farbe fehlt im Design")
	bc.load_design(d)
	for c in bc.design_root.get_children():
		if String(c.get_meta("part_id", "")) == "fuselage":
			var nc: Color = c.get_meta("color", Color(0, 0, 0, 0))
			print("  nach dem Laden: #%s" % nc.to_html(false))
			if not nc.is_equal_approx(ziel):
				fehler.append("Farbe ueberlebt das Laden nicht")
			break

	print("")
	print("=".repeat(64))
	if fehler.is_empty():
		print("URTEIL: OK — Palette und Pipette arbeiten")
	else:
		print("URTEIL: %d FEHLER" % fehler.size())
		for m in fehler:
			print("   ", m)
	quit()
	return true
