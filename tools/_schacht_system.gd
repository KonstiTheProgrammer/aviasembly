## DAS SCHACHTSYSTEM ALS GANZES — vom Bauplan bis zum Abwurf.
##
## Die Einzelteile sind schon geprueft (Geometrie mit _schacht_render, Mechanik mit
## _schacht_test). Was fehlte, ist die Kette dazwischen: erkennt der Flugcode, welche
## Bombe IM Schacht haengt? Sperrt er sie bei geschlossenen Klappen? Laesst er
## Aussenlasten in Ruhe? Genau da entstehen die Fehler, die kein Bild zeigt.
##
## Godot --headless --path . --script res://tools/_schacht_system.gd
extends SceneTree

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var fehler := 0
	var bay := PartCatalog.get_part("bombbay")

	# --- 1. Lichtraum: stimmen die Masse mit der Geometrie ueberein? -------------------
	var psc := Vector3(1.5, 1.4, 1.3)      # wie im Nachtfalken
	var h := PartCatalog.bay_hold(bay, psc)
	var gs: Vector3 = Vector3(bay["size"]) * psc
	print("LICHTRAUM bei Skalierung %s" % psc)
	print("  quer +-%.2f   laengs +-%.2f   Decke %+.2f   Boden %+.2f"
		% [h["halb_x"], h["halb_z"], h["oben"], h["unten"]])
	if not (h["halb_x"] > 0.0 and h["halb_z"] > 0.0 and h["oben"] > h["unten"]):
		fehler += 1
		print("  !! unbrauchbare Masse")
	# Der Lichtraum darf nicht groesser sein als das Teil.
	if h["halb_x"] > gs.x * 0.5 or h["halb_z"] > gs.z * 0.5:
		fehler += 1
		print("  !! Lichtraum groesser als das Bauteil")

	# --- 2. Bauansicht: stehen die Klappen offen? -------------------------------------
	var vis := PartCatalog.build_visual(bay)
	PartCatalog.set_bay_open(vis, true)
	var offen := _winkel(vis)
	PartCatalog.set_bay_open(vis, false)
	var zu := _winkel(vis)
	print("\nBAUANSICHT  offen %.0f Grad, zu %.0f Grad" % [offen, zu])
	if offen < 90.0 or absf(zu) > 0.01:
		fehler += 1
		print("  !! set_bay_open wirkt nicht")

	# --- 3. Abwurfsperre --------------------------------------------------------------
	var body := AircraftBody.new()
	root.add_child(body)
	var v2 := PartCatalog.build_visual(bay)
	body.add_child(v2)
	body._bay_doors = body._sammle_klappen(body)
	body._bay_anim = 0.0
	var zu_frei := body.bay_frei()
	body._bay_anim = 1.0
	var auf_frei := body.bay_frei()
	body._bay_anim = 0.5
	var halb_frei := body.bay_frei()
	print("\nABWURFSPERRE  zu: %s   halb offen: %s   offen: %s"
		% [str(zu_frei), str(halb_frei), str(auf_frei)])
	if zu_frei or halb_frei or not auf_frei:
		fehler += 1
		print("  !! Sperre greift nicht wie gedacht")

	# Ohne Schacht muss IMMER geworfen werden duerfen — sonst waeren alle anderen
	# Flugzeuge der Welt plötzlich waffenlos.
	var leer := AircraftBody.new()
	root.add_child(leer)
	leer._bay_doors = []
	print("OHNE SCHACHT  frei: %s" % str(leer.bay_frei()))
	if not leer.bay_frei():
		fehler += 1
		print("  !! ein Flugzeug ohne Schacht koennte nichts mehr abwerfen")

	print("\n-> %d Beanstandungen" % fehler)
	quit()
	return true


func _winkel(n: Node) -> float:
	for k in PartCatalog._bay_doors(n):
		return absf(rad_to_deg((k as Node3D).rotation.z))
	return -1.0
