## MEHRERE LAND-WASSER-WECHSEL JE RICHTUNG — GIBT ES SIE JETZT?
##
## Das ist die eine Frage, an der der ganze Umbau haengt. Die alte Kueste entstand aus
## r_coast(winkel), also aus EINEM Radius je Richtung: auf jedem Strahl vom Mittelpunkt
## genau ein Wechsel von Land zu Wasser. Damit sind Fjorde, Lagunen und zurueckgekruemmte
## Landzungen ausgeschlossen — nicht schwierig, sondern unmoeglich.
##
## Ein Bild beweist das schlecht (Dunst, Blickwinkel, Wasserfarbe). Ein Profil beweist es
## direkt: es laeuft den Strahl ab und schreibt fuer jeden Schritt hin, ob dort Land oder
## Wasser ist. Wer mehr als einen Wechsel zaehlt, hat eine Kueste, die ein Radius nicht
## beschreiben kann.
##
## Godot --headless --path . --script res://tools/_kuestenprofil.gd
extends SceneTree

# Peilungen: durch den Fjord, durch die Lagune, und zwei Kontrollrichtungen, in denen
# nichts gebaut wurde — dort MUSS es bei einem Wechsel bleiben.
const PEILUNGEN := [
	[220.5, "Fjord (Sturmkap)"],
	[224.0, "Fjord, weiter innen"],
	[227.0, "neben dem Fjord — Kapflanke"],
	[105.0, "Hakenzunge / Lagune"],
	[115.0, "Lagune, weiter suedlich"],
	[ 60.0, "Kontrolle (unveraendert)"],
	[300.0, "Kontrolle (unveraendert)"],
]

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
	if f < 8:
		return false
	var main: Node = get_meta("main")
	var tw = main.get("terrain")
	var meer: float = tw.SEA_Y

	print("Profil von 16 bis 36 km, Schritt 200 m.  '#' Land   '~' Wasser")
	print("                              16km                        26km              36km")
	for e in PEILUNGEN:
		var grad: float = e[0]
		var a := deg_to_rad(grad)
		var ri := Vector2(cos(a), sin(a))
		var zeile := ""
		var wechsel := 0
		var vorher := true          # bei 16 km ist ueberall Land
		for i in 101:
			var r := 16000.0 + float(i) * 200.0
			var land: bool = tw.height_at(ri.x * r, ri.y * r) > meer
			zeile += "#" if land else "~"
			if land != vorher:
				wechsel += 1
				vorher = land
		print("%-28s %s  %d Wechsel" % [e[1], zeile, wechsel])
	quit()
	return true
