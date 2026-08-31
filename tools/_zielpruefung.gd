## ANTWORTET JEDES ZIEL AUF DAS, WAS DIE WAFFEN VON IHM LESEN?
##
## Anlass ist ein Fehler, der im Spiel zehnmal in Folge auftrat und im Bild unsichtbar
## war: Projectile las den Trefferradius als EIGENSCHAFT (t.hit_radius), SamSite legt ihn
## aber nur als Metadatum ab. Ergebnis war kein Absturz, sondern etwas Schlimmeres — die
## Trefferschleife brach an der Flakstellung ab, die Bordwaffe konnte sie nicht treffen,
## und alle Ziele NACH ihr in der Liste wurden ebenfalls nicht mehr geprueft.
##
## Solche Fehler entstehen immer dann, wenn eine neue Zielart in die Gruppe "target"
## kommt. Dieses Werkzeug prueft deshalb die GRUPPE, nicht eine einzelne Klasse: jedes
## Mitglied muss Trefferradius, hit() und eine Position liefern.
##
## Godot --headless --path . --script res://tools/_zielpruefung.gd
extends SceneTree

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if not has_meta("main"):
		var m: Node = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		set_meta("main", m)
		return false
	# Ziele entstehen erst mit der ersten Welle; ein paar Takte warten.
	if f < 60:
		return false
	var ziele := root.get_tree().get_nodes_in_group("target")
	print("Ziele in der Gruppe \"target\": %d" % ziele.size())
	print("Klasse               | Radius | hit() | Urteil")
	print("---------------------+--------+-------+--------")
	var fehler := 0
	var gesehen := {}
	for t in ziele:
		var klasse: String = String(t.get_script().resource_path.get_file()) \
			if t.get_script() != null else String(t.get_class())
		if gesehen.has(klasse):
			continue
		gesehen[klasse] = true
		var hat_meta: bool = t.has_meta("hit_radius")
		var r: float = float(t.get_meta("hit_radius", -1.0))
		var hat_hit: bool = t.has_method("hit")
		var ok := hat_meta and r > 0.0 and hat_hit
		if not ok:
			fehler += 1
		print("%-20s | %6.1f | %5s | %s"
			% [klasse, r, "ja" if hat_hit else "NEIN",
				"in Ordnung" if ok else "UNVOLLSTAENDIG"])
	print("\n-> %d Zielarten beanstandet" % fehler)
	quit()
	return true
