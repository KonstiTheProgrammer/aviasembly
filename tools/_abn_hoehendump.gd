extends SceneTree
## ABNAHME-HILFE: kippt das Hoehenfeld der ganzen Welt als Zahlenliste aus.
##
## WOZU. Die Frage "ist Gelaende AUSSERHALB des Hochtals unveraendert?" laesst sich am
## Bild nur ahnen — zwei Renderbilder koennen sich um eine Kachel unterscheiden, ohne
## dass man es sieht, und ein md5-Vergleich sagt nur "anders", nicht "wo" und "wie viel".
## Hier wird height_at auf einem groben Weltraster abgetastet und stumpf ausgegeben.
## Derselbe Lauf im HEAD-Arbeitsbaum liefert die Vergleichsreihe; der Diff steht dann
## ausserhalb von Godot.
##
## MAIN.TSCN UND NICHT TerrainWorld.new(). Ein nacktes TerrainWorld hat weder Seed noch
## Seen, Massive oder Flachzonen — sein height_at liefert das blanke Rauschen und damit
## eine Welt, die es nicht gibt. Genau dieselbe Falle wie frueher beim Renderwerkzeug.
##
## KEIN TEIL DES SPIELS. Reines Messwerkzeug, laeuft headless.
##
## godot --headless --path . --script res://tools/_abn_hoehendump.gd -- [schritt=250]
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var schritt := 250.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("schritt="):
			schritt = float(a.substr(8))

	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw = main.terrain

	# Weltausschnitt: deckt Spawn, Stadt, Canyon, Vulkan und das Hochtal ab.
	var von := -18000.0
	var bis := 18000.0
	var zeilen := PackedStringArray()
	var z := von
	while z <= bis:
		var x := von
		while x <= bis:
			# Auf 1 mm runden: float-Rauschen soll keinen Diff erzeugen.
			zeilen.append("%.0f %.0f %.3f" % [x, z, tw.height_at(x, z)])
			x += schritt
		z += schritt
	var pfad := "user://abn_hoehen.txt"
	var fh := FileAccess.open(pfad, FileAccess.WRITE)
	fh.store_string("\n".join(zeilen))
	fh.close()
	print("Punkte=", zeilen.size(), "  Datei=", ProjectSettings.globalize_path(pfad))
	return true
