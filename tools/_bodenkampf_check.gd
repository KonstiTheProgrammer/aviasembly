## BODENKAMPF: schlagen Geschosse im Gelaende ein, und wirken Bomben im Umkreis?
##
## Prueft im echten Spiel (Main-Szene, Flugmodus, gestreamtes Gelaende):
##   BOMBE HANG    Bombe ueber erhoehtem Gelaende -> zuendet AUF dem Boden, nicht bei y=0,4
##   KUGEL BODEN   Kugel senkrecht nach unten -> verschwindet an der Oberflaeche
##   BOMBE FLAK    Bombe 8 m neben ein Flakgeschuetz -> Geschuetz zerstoert (Flaechenschaden)
##   BOMBE SAM     Bombe 4 m neben eine Raketenstellung -> Stellung zerstoert
##
## Mit umgebogenem HOME starten (Main schreibt sonst den echten Autosave):
##   HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/_bodenkampf_check.gd
extends SceneTree

var m: Node = null
var f := 0
var fc: Node = null
var terrain: Node = null
var proben: Array = []        # [{name, node, last: Vector3, boden: float, fertig}]
var flak: Node3D = null
var sam: Node3D = null
var t0 := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 30:
		m.call("_load_design_from", "res://designs/nachtfalke.json")
	if f == 40:
		m.call("_set_mode", 1)
	if f == 90:
		fc = m.get("flight_ctrl")
		terrain = m.get("terrain")
		for c in (m.get("fly_world") as Node).get_children():
			if c is FlakGun and flak == null:
				flak = c
			if c is SamSite and sam == null and String(c.get("art")) == "ir":
				sam = c
		print("Flak gefunden: %s   SAM gefunden: %s" % [str(flak != null), str(sam != null)])
		# Das Flugzeug an den Ort der Proben setzen, damit dort Gelaende gestreamt wird.
		var ac: RigidBody3D = fc.get("aircraft")
		ac.freeze = true
		ac.global_position = Vector3(250.0, 400.0, -2400.0)
		terrain.call("build_now_around", ac.global_position, 1400.0)
		return false
	if f == 100:
		var ac: RigidBody3D = fc.get("aircraft")
		terrain.call("build_now_around", ac.global_position, 1400.0)
		# 1) Bombe ueber dem hoechsten Punkt eines Probenrasters um die Flakzone
		var best := Vector3.ZERO
		var best_h := -1e9
		for i in 21:
			for j in 21:
				var x := 250.0 - 600.0 + float(i) * 60.0
				var z := -2400.0 - 600.0 + float(j) * 60.0
				var h: float = terrain.call("height_at", x, z)
				if h > best_h:
					best_h = h
					best = Vector3(x, h, z)
		_probe("BOMBE HANG", "bomb", best + Vector3(0, 150.0, 0), Vector3.ZERO, 15.0, 24.0, best_h)
		# 2) Kugel senkrecht nach unten
		var kp := Vector3(250.0 + 40.0, 0.0, -2400.0 + 300.0)
		var kh: float = terrain.call("height_at", kp.x, kp.z)
		_probe("KUGEL BODEN", "bullet", Vector3(kp.x, kh + 60.0, kp.z), Vector3(0, -800.0, 0), 1.0, 0.0, kh)
		# 3) Bombe 8 m neben das Flakgeschuetz
		if flak != null:
			var fp := flak.global_position
			_probe("BOMBE FLAK", "bomb", fp + Vector3(8.0, 120.0, 0.0), Vector3.ZERO, 15.0, 24.0, fp.y)
		if sam != null:
			var sp := sam.global_position
			_probe("BOMBE SAM", "bomb", sp + Vector3(0.0, 120.0, 4.0), Vector3.ZERO, 15.0, 24.0, sp.y)
		t0 = f
		return false
	if f > 100:
		for p in proben:
			if p["fertig"]:
				continue
			var n = p["node"]
			if is_instance_valid(n):
				p["last"] = (n as Node3D).global_position
			else:
				p["fertig"] = true
		if f - t0 > 60 * 8:
			_bericht()
			quit()
	return false


func _probe(name: String, kind: String, pos: Vector3, vel: Vector3, dmg: float, grav: float,
		boden: float) -> void:
	var p = fc.call("_spawn", kind, pos, vel, 12.0, dmg, grav)
	proben.append({"name": name, "node": p, "last": pos, "boden": boden, "fertig": false})


func _bericht() -> void:
	var fehler := 0
	print("")
	for p in proben:
		var last: Vector3 = p["last"]
		var dy: float = last.y - float(p["boden"])
		var ok: bool = p["fertig"] and absf(dy) < 8.0
		# Die letzte gemessene Lage ist der letzte Frame VOR dem Einschlag — bei 800 m/s
		# (Kugel) liegt der bis zu 13 m ueber dem Boden. Entscheidend ist daher: ist das
		# Geschoss vor Ablauf seiner Lebenszeit verschwunden, und lag es zuletzt ueber dem
		# Boden statt darunter.
		if String(p["name"]) == "KUGEL BODEN":
			ok = p["fertig"] and dy > -1.0 and dy < 14.0
		# Die Kollision ist das facettierte 8-m-Dreiecksnetz, height_at die glatte
		# Funktion: auf einer Kuppe liegt das Netz bis zu einigen Metern darunter.
		# Vorher zuendete die Bombe bei y = 0,4, also rund 146 m unter der Oberflaeche.
		if String(p["name"]) == "BOMBE HANG":
			ok = p["fertig"] and dy > -4.0 and dy < 6.0
		print("%-12s  Boden %7.1f   zuletzt gesehen y %7.1f  (%+.1f)   %s" % [
			p["name"], float(p["boden"]), last.y, dy, "OK" if ok else "FALSCH"])
		if not ok and not String(p["name"]).begins_with("BOMBE FLAK") \
				and not String(p["name"]).begins_with("BOMBE SAM"):
			fehler += 1
	var flak_weg: bool = flak == null or not is_instance_valid(flak) or bool(flak.get("_tot"))
	var sam_weg: bool = sam == null or not is_instance_valid(sam) or bool(sam.get("_tot"))
	print("Flak zerstoert: %s   SAM zerstoert: %s" % [str(flak_weg), str(sam_weg)])
	if flak != null and not flak_weg:
		fehler += 1
	if sam != null and not sam_weg:
		fehler += 1
	print("-> %d Beanstandungen" % fehler)
