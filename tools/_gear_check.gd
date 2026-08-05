## Prueft ALLE animierten Fahrwerke gegen den Vertrag von AircraftBody/PartCatalog:
##   - genau EINE Animation "retract" am AnimationPlayer
##   - Knoten: Leg (Node3D!) / LegMesh / Wheel — Radachse muss lokal X sein
##   - Teleskop (Slider) und Editor-Beinlaenge (Extend) duerfen sich NICHT ueberschreiben
##   /opt/homebrew/bin/godot --headless --script tools/_gear_check.gd
## Loest das frueher teil-spezifische tools/_f22_gear_check.gd ab.
extends SceneTree

const IDS := ["wheel_f22", "wheel_tail", "wheel_nose", "wheel_bomber", "wheel_bogie", "wheel_carrier", "wheel_rough", "wheel_tandem", "wheel_outrigger",
	"wheel_ww2", "wheel_biplane_spoke", "wheel_biplane_disc", "wheel_spitfire"]
# Feste Fahrwerke: gleicher Knotenvertrag, aber bewusst OHNE "retract"-Animation.
const IDS_FEST := ["wheel_spat"]
# Kufen: fest UND ohne Rad-Knoten.
const IDS_KUFE := ["wheel_skid"]

var f := 0
var fehler := 0

func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var erst := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.get_aabb()
		var t: Transform3D = n.global_transform.affine_inverse() * mi.global_transform
		var w := AABB(t * b.position, Vector3.ZERO)
		for i in range(8):
			w = w.expand(t * (b.position + b.size * Vector3(
				float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))))
		box = w if erst else box.merge(w)
		erst = false
	return box

func _pruefe(id: String, animiert: bool, mit_rad: bool = true) -> void:
	var p := PartCatalog.get_part(id)
	if p.is_empty():
		print("  FEHLT im Katalog!"); fehler += 1; return
	var vis := PartCatalog.build_visual(p)
	if vis == null:
		print("  build_visual lieferte null"); fehler += 1; return
	get_root().add_child(vis)

	# --- Knotenvertrag ---
	var leg := vis.find_child("Leg", true, false)
	var ok_leg: bool = leg != null and leg.get_class() == "Node3D"
	print("  Leg=%s%s" % [leg.get_class() if leg != null else "FEHLT",
		"" if ok_leg else "  <-- muss Node3D sein!"])
	if not ok_leg: fehler += 1
	# Die Spornkufe bringt bewusst KEINEN "Wheel"-Knoten mit — sie schleift, statt zu
	# rollen. Darum ist das Rad hier nur bei mit_rad Pflicht.
	var pflicht: Array = ["LegMesh", "Extend"] if not mit_rad else ["LegMesh", "Extend", "Wheel"]
	var fehlend: Array = []
	for nm in pflicht:
		if vis.find_child(nm, true, false) == null:
			fehlend.append(nm)
	if fehlend.is_empty():
		print("  Knoten     : alle da (%s)%s" % [" / ".join(pflicht),
			"" if vis.find_child("Slider", true, false) == null else " + Slider"])
	else:
		print("  Knoten     : FEHLEN ", fehlend); fehler += 1

	# Mehrere Rad-Knoten sind erlaubt (Drehgestell: Wheel + Wheel2). Jeder muss fuer
	# sich eine lokale X-Achse als Radachse haben, sonst rollt er schief.
	var raeder: Array = []
	for wnm in ["Wheel", "Wheel2", "Wheel3", "Wheel4"]:
		var wn := vis.find_child(wnm, true, false) as Node3D
		if wn == null:
			continue
		var ax: Vector3 = (vis.global_transform.basis.inverse()
			* wn.global_transform.basis.x).normalized()
		var ok_ax: bool = absf(ax.x) > 0.999
		raeder.append("%s=%s%s" % [wnm, ax, "" if ok_ax else " FALSCH!"])
		if not ok_ax: fehler += 1
	if raeder.is_empty():
		print("  Radachsen  : keine — Kufe, rollt nicht%s"
			% ("" if not mit_rad else "   <-- hier wird aber ein Rad erwartet!"))
		if mit_rad: fehler += 1
	else:
		print("  Radachsen  : ", " | ".join(raeder))

	# --- Animation ---
	var ap := vis.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not animiert:
		# Festes Fahrwerk (wheel_spat): darf gar KEINE Animation mitbringen, sonst wuerde
		# G es klappen lassen, obwohl der Katalog kein retract fuehrt.
		print("  Animation  : %s" % ("keine — richtig fuer ein festes Fahrwerk"
			if ap == null else "UNERWARTET vorhanden!"))
		if ap != null: fehler += 1
		var bf := _aabb(vis)
		var kf: Vector3 = p.get("size", Vector3.ONE)
		print("  Aufstand   : y = %.3f  (Katalog size.y = %.3f)" % [bf.position.y, kf.y])
		var zf := "  Beinlaenge :"
		for fak in [1.0, 1.7, 2.4]:
			PartCatalog.set_gear_length(vis, p, fak)
			zf += "  f=%.1f->%.3f m" % [fak, _aabb(vis).size.y]
		print(zf)
		vis.queue_free()
		return
	if ap == null or not ap.has_animation("retract"):
		print("  Animation  : KEINE 'retract'!"); fehler += 1
		vis.queue_free(); return
	var liste := ap.get_animation_list()
	print("  Animation  : %s%s" % [liste, "" if liste.size() == 1 else "  <-- sollte genau eine sein"])

	# --- Teleskop ---
	var L: float = ap.get_animation("retract").length
	var sl := vis.find_child("Slider", true, false) as Node3D
	ap.play("retract"); ap.pause()
	ap.seek(0.0, true)
	var s0: float = sl.position.y if sl != null else 0.0
	var b0 := _aabb(vis)
	ap.seek(L, true)
	var s1: float = sl.position.y if sl != null else 0.0
	var b1 := _aabb(vis)
	# Kein Slider = kein Oleo (die Vintage-Beine federn ueber Gummiseile) — kein Fehler.
	var tel: String = "%.3f m" % (s1 - s0) if sl != null else "keins"
	print("  Teleskop   : %-8s |  Bauhoehe aus %.3f -> ein %.3f  |  Bautiefe ein %.3f"
		% [tel, b0.size.y, b1.size.y, b1.size.z])
	var ksize: Vector3 = p.get("size", Vector3.ONE)
	print("  Aufstand   : y = %.3f  (Katalog size.y = %.3f)" % [b0.position.y, ksize.y])

	# --- Klappen: muessen sich bewegen. Der Winkel allein sagt nichts darueber, ob
	# herum richtig ist (je nach Bauweise ist 0 offen ODER zu) — darum beide Enden
	# ausgeben, damit eine vertauschte Keyframe-Reihenfolge auffaellt.
	for dn in ["Door", "DoorR"]:
		var d := vis.find_child(dn, true, false) as Node3D
		if d == null:
			continue
		ap.seek(0.0, true)
		var d0: Vector3 = d.rotation_degrees
		ap.seek(L, true)
		var d1: Vector3 = d.rotation_degrees
		var weg: float = (d1 - d0).length()
		print("  %-11s aus %s -> ein %s  (%.0f Grad)%s"
			% [dn, d0.round(), d1.round(), weg, "" if weg > 5.0 else "  <-- bewegt sich nicht!"])
		if weg <= 5.0: fehler += 1

	# --- Editor-Beinlaenge ---
	ap.seek(0.0, true)
	var ex := vis.find_child("Extend", true, false) as Node3D
	var zeile := "  Beinlaenge :"
	for fak in [1.0, 1.7, 2.4]:
		PartCatalog.set_gear_length(vis, p, fak)
		zeile += "  f=%.1f->%.3f m" % [fak, _aabb(vis).size.y]
	print(zeile)

	# --- Zusammenspiel: darf sich nicht gegenseitig ueberschreiben ---
	PartCatalog.set_gear_length(vis, p, 1.8)
	var e0: float = ex.position.y
	ap.seek(L * 0.5, true); ap.seek(L, true); ap.seek(0.0, true)
	var e1: float = ex.position.y
	var stabil: bool = absf(e0 - e1) < 0.0005
	print("  Zusammensp.: Extend %+.3f -> %+.3f  %s" % [e0, e1, "stabil" if stabil else "UEBERSCHRIEBEN!"])
	if not stabil: fehler += 1
	vis.queue_free()

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	for id in IDS:
		print("\n=== ", id, " ===")
		_pruefe(id, true)
	for id in IDS_FEST:
		print("\n=== ", id, "  (fest) ===")
		_pruefe(id, false)
	for id in IDS_KUFE:
		print("\n=== ", id, "  (fest, ohne Rad) ===")
		_pruefe(id, false, false)
	print("\n", "ALLES OK" if fehler == 0 else "%d PROBLEM(E)" % fehler)
	quit()
	return true
