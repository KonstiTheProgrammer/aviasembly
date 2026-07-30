## Misst, wie weit die BEWEGEN-PFEILE von der Huelle des Teils entfernt sitzen — also von
## genau der Box, die der Debug-Haken zeichnet.
##
## Frueher galt fuer alle drei Pfeile die GROESSTE Halbachse plus RING_MARGIN (1.1). An
## einem Fluegel mit 4.4 Spannweite hing der Y-Pfeil dadurch 2.2+1.1 in der Luft, obwohl
## das Teil dort nur 0.1 dick ist. Erwartet wird jetzt: jeder Pfeil sitzt knapp AUSSERHALB
## der Huelle auf SEINER Achse — der Schaft setzt an der Flaeche an.
extends SceneTree
var f := 0

const TEILE: Array = ["wing_straight", "b29_wing", "aileron", "fuselage",
	"fuselage_c130_long", "wheel_light", "engine_c130", "v_stab"]


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var bc := BuildController.new()
	root.add_child(bc)
	bc.symmetry = false
	var fehler: Array = []
	print("%-20s %-22s   Abstand Pfeil -> Huelle je Achse" % ["Teil", "Huelle (halb)"])
	print("-".repeat(88))
	for id in TEILE:
		bc.load_design([
			{"id": "cockpit", "xform": Transform3D(), "root": true},
			{"id": id, "xform": Transform3D(Basis(), Vector3(0, 0, 3.0))},
		])
		var teil: Node3D = null
		for c in bc.design_root.get_children():
			if String(c.get_meta("part_id", "")) == id:
				teil = c
		if teil == null:
			print("%-20s  nicht gebaut" % id)
			continue
		bc._select_part(teil)
		bc.set_gizmo_mode(bc.GIZ_MOVE)
		var wab: AABB = bc._part_world_aabb(teil)
		var halb: Vector3 = wab.size * 0.5
		var mitte: Vector3 = wab.get_center()
		var texte: Array = []
		for h in bc._handles:
			if String((h as Node3D).get_meta("kind", "")) != "move":
				continue
			var achse: int = (h as Node3D).get_meta("axis")
			# Wie weit steht der Griff jenseits der Huellenflaeche auf SEINER Achse?
			var pos: Vector3 = (h as Node3D).global_position - mitte
			var wert: float = [pos.x, pos.y, pos.z][achse]
			var rand: float = [halb.x, halb.y, halb.z][achse]
			var luft: float = wert - rand
			texte.append("%s %+.2f" % [["X", "Y", "Z"][achse], luft])
			# Zu weit weg = genau die Beschwerde. Zu nah = Pfeil steckt im Teil.
			if luft > 1.60:
				fehler.append("%s: %s-Pfeil %.2f von der Huelle weg" % [id, ["X", "Y", "Z"][achse], luft])
			if luft < 0.05:
				fehler.append("%s: %s-Pfeil steckt in der Huelle (%.2f)" % [id, ["X", "Y", "Z"][achse], luft])
		print("%-20s (%4.2f %4.2f %4.2f)      %s"
			% [id, halb.x, halb.y, halb.z, "   ".join(texte)])

	print("")
	print("=".repeat(88))
	if fehler.is_empty():
		print("URTEIL: OK — jeder Pfeil sitzt knapp ausserhalb der Huelle SEINER Achse")
	else:
		print("URTEIL: %d FEHLER" % fehler.size())
		for m in fehler:
			print("   ", m)
	quit()
	return true
