## WIE GEGLIEDERT SIND DIE BERGE?
##
## Dieselbe Frage wie bei der Talschlusswand (tools/_wandprofil.gd), nur fuer das ganze
## Gebirge. Im Bild sind zwei entgegengesetzte Fehler zu sehen: die Talflanken sind glatte
## Duenen ohne Struktur, die fernen Ketten ein gleichmaessiges Dreiecksrauschen ohne grosse
## Form. Beides sind Aussagen ueber die KRUEMMUNG auf einer bestimmten Laenge — und genau
## die misst dieses Werkzeug, auf drei Massstaeben zugleich.
##
## Gemessen wird je Feld eine 640-m-Linie mit 8 m Abtastung. Ausgegeben werden Spanne,
## die mittlere Kruemmung auf 8 m (das Dreiecksmass, verraet Rauschen) und die mittlere
## Kruemmung auf 48 m (das Formmass, verraet fehlende Struktur).
##
## Godot --headless --path . --script res://tools/_bergprofil.gd
extends SceneTree

const FELDER := [
	["Tiefland (Referenz)", Vector2(1500.0, 1000.0)],
	["Talflanke Nordwest", Vector2(-8300.0, -6100.0)],
	["Talflanke Suedost", Vector2(-6300.0, -7300.0)],
	["Hochkette am Kamm", Vector2(-9200.0, -5200.0)],
	["Gebirge Mitte", Vector2(2600.0, 1500.0)],
	["Vulkanflanke", Vector2(11800.0, -4700.0)],
]

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	print("%-22s | %6s | %14s | Kruemmung 8 m | Kruemmung 48 m"
		% ["Feld", "h", "Spanne"])
	for e in FELDER:
		var p: Vector2 = e[1]
		var h: PackedFloat64Array = []
		for k in 81:
			h.append(tw.height_at(p.x + float(k) * 8.0, p.y))
		var hmin := h[0]
		var hmax := h[0]
		for v in h:
			hmin = minf(hmin, v)
			hmax = maxf(hmax, v)
		var k8 := 0.0
		for k in range(1, h.size() - 1):
			k8 += absf(h[k - 1] - 2.0 * h[k] + h[k + 1])
		k8 /= float(h.size() - 2)
		# Grobmass: dieselbe zweite Differenz, aber ueber sechs Abtastungen (48 m).
		var k48 := 0.0
		var n48 := 0
		for k in range(6, h.size() - 6):
			k48 += absf(h[k - 6] - 2.0 * h[k] + h[k + 6])
			n48 += 1
		k48 /= float(n48)
		print("%-22s | %6.0f | %6.0f .. %-6.0f | %10.2f m | %10.2f m"
			% [String(e[0]), h[40], hmin, hmax, k8, k48])
	quit()
	return true
