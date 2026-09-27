## FLIEGT DER NACHTFALKE UEBERHAUPT?
##
## Ein Bauplan, der gut aussieht und nicht abhebt, ist kein Geschenk. Geprueft wird
## deshalb dasselbe, was das Flugmodell im Spiel rechnet: Masse gegen Schub gegen
## Flaeche. Dazu die Frage, an der der ganze Auftrag haengt — sind die Klappen da und
## liegen die Bomben WIRKLICH im Schacht und nicht daneben?
##
## Godot --headless --path . --script res://tools/_falke_check.gd
extends SceneTree

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var fh := FileAccess.open("res://designs/nachtfalke.json", FileAccess.READ)
	var liste: Array = JSON.parse_string(fh.get_as_text())

	var masse := 0.0
	var schub := 0.0
	var flaeche := 0.0
	var moment := Vector3.ZERO      # Masse mal Ort, fuer den Schwerpunkt
	var rad_z: Array = []           # Laengslage der Raeder
	var bay := {}
	var bomben: Array = []
	for e in liste:
		var p := PartCatalog.get_part(String(e["id"]))
		var sc: Array = e.get("scale", [1, 1, 1])
		var vol: float = float(sc[0]) * float(sc[1]) * float(sc[2])
		masse += float(p.get("mass", 0.0)) * maxf(vol, 0.2)
		schub += float(p.get("thrust", 0.0)) * maxf(vol, 0.2)
		if String(p.get("shape", "")) == "wing":
			flaeche += float(p.get("span", 0.0)) * float(p.get("root_chord", 0.0)) \
				* float(sc[0]) * float(sc[2])
		var x: Array = e["xform"]
		var ort := Vector3(x[9], x[10], x[11])
		moment += ort * (float(p.get("mass", 0.0)) * maxf(vol, 0.2))
		if String(e["id"]).begins_with("wheel"):
			rad_z.append(ort.z)
		if String(e["id"]) == "bombbay":
			bay = {"pos": Vector3(x[9], x[10], x[11]),
				"sc": Vector3(sc[0], sc[1], sc[2]),
				"size": p.get("size", Vector3.ONE)}
		elif String(e["id"]) == "bomb":
			bomben.append(Vector3(x[9], x[10], x[11]))

	var sp := moment / maxf(masse, 1.0)
	print("Masse   %7.0f kg" % masse)
	print("Schwerpunkt bei z = %+.2f" % sp.z)
	# DAS HAUPTFAHRWERK MUSS HINTER DEN SCHWERPUNKT. Steht es davor oder darauf, kippt die
	# Maschine im Stand auf das Heck; steht es weit dahinter, hebt die Nase beim Start nicht.
	# Die Faustregel im Flugzeugbau sind 8 bis 15 Prozent der Fluegeltiefe dahinter.
	var haupt := -1.0e9
	var bug := 1.0e9
	for z: float in rad_z:
		haupt = maxf(haupt, z)
		bug = minf(bug, z)
	print("Bugrad z = %+.2f   Hauptbeine z = %+.2f   (Hauptbein - Schwerpunkt = %+.2f)"
		% [bug, haupt, haupt - sp.z])
	if haupt <= sp.z + 0.15:
		print("  !! HAUPTFAHRWERK ZU WEIT VORN — die Maschine kippt auf das Heck")
	elif haupt > sp.z + 1.6:
		print("  !! HAUPTFAHRWERK ZU WEIT HINTEN — die Nase kommt beim Start nicht hoch")
	else:
		print("  Fahrwerkslage in Ordnung")
	print("Schub   %7.0f  (Verhaeltnis %.2f)" % [schub, schub / maxf(masse, 1.0)])
	print("Flaeche %7.1f m2 (Flaechenbelastung %.0f kg/m2)"
		% [flaeche, masse / maxf(flaeche, 0.01)])

	print("\nSCHACHT UND BOMBEN")
	if bay.is_empty():
		print("  KEIN Schacht im Bauplan")
		quit()
		return true
	# Lichtraum des Laderaums in Weltmassen, aus denselben Konstanten wie die Geometrie.
	var gs: Vector3 = bay["size"] * bay["sc"]
	var halb_z: float = PartCatalog.LUKE_Z * gs.z
	var halb_x: float = sin(PartCatalog.LUKE_HALB) * 0.5 * gs.x
	var decke: float = float(bay["pos"].y) + PartCatalog.LADE_DECKE * gs.y
	var boden: float = float(bay["pos"].y) - 0.5 * gs.y
	print("  Laderaum: x +-%.2f   z %.2f bis %.2f   y %.2f bis %.2f"
		% [halb_x, bay["pos"].z - halb_z, bay["pos"].z + halb_z, boden, decke])
	var drin := 0
	for b in bomben:
		var ok: bool = absf(b.x - bay["pos"].x) < halb_x \
			and absf(b.z - bay["pos"].z) < halb_z and b.y < decke and b.y > boden
		print("  Bombe (%5.2f,%5.2f,%5.2f)  %s" % [b.x, b.y, b.z,
			"im Schacht" if ok else "AUSSERHALB"])
		if ok:
			drin += 1
	print("  -> %d von %d Bomben im Schacht" % [drin, bomben.size()])
	quit()
	return true
