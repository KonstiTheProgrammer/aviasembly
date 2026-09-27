## GEHT DIE KLAPPE IM FLUG WIRKLICH AUF?
##
## Die Bilder aus _schacht_render zeigen nur, dass sich der Drehknoten drehen LAESST. Ob
## das Flugzeug ihn im Flug auch findet und bewegt, ist eine andere Frage — und sie
## haengt an drei Stellen, die alle stimmen muessen: das Metadatum am Knoten, das
## Einsammeln in AircraftBody, und die Weiterschaltung in _process.
##
## Geprueft wird deshalb die ganze Kette:
##   PALETTE   Steht das Teil ueberhaupt zur Auswahl?
##   FINDEN    Findet _sammle_klappen genau zwei Drehknoten?
##   DREHEN    Bewegt toggle_bay sie ueber mehrere Takte bis zum Anschlag — und zurueck?
##   SPIEGEL   Drehen beide GEGENSINNIG? Zwei gleichsinnige Klappen hiesse, dass eine in
##             den Rumpf faehrt statt heraus.
##
## Godot --headless --path . --script res://tools/_schacht_test.gd
extends SceneTree

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var fehler := 0

	var pal := PartCatalog.get_part("bombbay")
	print("PALETTE  %s" % ("gefunden: " + String(pal.get("name", "?")) if not pal.is_empty()
		else "FEHLT"))
	if pal.is_empty():
		quit()
		return true

	var body := AircraftBody.new()
	root.add_child(body)
	var vis := PartCatalog.build_visual(pal)
	body.add_child(vis)
	var klappen: Array = body._sammle_klappen(body)
	print("FINDEN   %d Drehknoten (erwartet 2)" % klappen.size())
	if klappen.size() != 2:
		fehler += 1
	body._bay_doors = klappen

	# Aufmachen und takten. 0.05 s je Schritt, 1.7 pro Sekunde -> nach ~12 Schritten offen.
	body.bay_open = true
	var vorher := 0.0
	for i in 20:
		body._process(0.05)
	var a0: float = (klappen[0] as Node3D).rotation.z
	var a1: float = (klappen[1] as Node3D).rotation.z
	print("DREHEN   nach dem Oeffnen: %.1f Grad / %.1f Grad (Anschlag %.0f)"
		% [rad_to_deg(a0), rad_to_deg(a1), rad_to_deg(AircraftBody.BAY_WINKEL)])
	if absf(absf(a0) - AircraftBody.BAY_WINKEL) > 0.01:
		fehler += 1
	print("SPIEGEL  %s" % ("gegensinnig — richtig" if a0 * a1 < 0.0
		else "GLEICHSINNIG — eine Klappe faehrt in den Rumpf"))
	if a0 * a1 >= 0.0:
		fehler += 1
	print("STATUS   \"%s\"" % body.bay_status)

	body.bay_open = false
	for i in 20:
		body._process(0.05)
	var z0: float = (klappen[0] as Node3D).rotation.z
	print("ZU       zurueck auf %.2f Grad, Status \"%s\"" % [rad_to_deg(z0), body.bay_status])
	if absf(z0) > 0.01:
		fehler += 1

	print("\n-> %d Beanstandungen" % fehler)
	quit()
	return true
