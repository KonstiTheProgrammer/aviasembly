## AircraftBody.gd
## Wissenschaftliches Arcade-Flugmodell (gebündelte Koeffizienten-Aufbaumethode,
## wie in vielen Flugsimulationen). Stabil bei 60 Hz, trotzdem physikalisch fundiert.
##
## Auftrieb:  Cl = lerp(Cl_α·α , sin 2α , σ)   (endlicher Flügel + realer Stall)
##            Cl_α = 2π·AR/(AR+2)              (Streckungsabhängiger Anstieg)
## Widerstand: Cd = Cd0 + Cl²/(π·AR·e) + Stall  (Parasitär + induziert)
## Schub:     Propeller fällt mit Tempo, Jet konstant.  Luftdichte sinkt mit Höhe.
## Steuerung: Fly-by-Wire-Ratenregler; Autorität & Stabilität skalieren mit
##            der Steuer-/Leitwerksfläche -> Bauen zählt.
class_name AircraftBody
extends RigidBody3D

# Naturkonstanten / Tuning
const RHO0 := 1.225           # Luftdichte Meereshöhe (kg/m³)
const SCALE_H := 8500.0       # Atmosphären-Skalenhöhe (m)
const LIFT_K := 2.9           # globaler Kraftfaktor (Spielgefühl: hebt früh & leicht ab)
const INCIDENCE := 0.075      # ~4.3° Flügel-Einstellwinkel (hebt zügig ab)
const STALL_A := 0.27         # Stall-Anstellwinkel (~15.5°)
const STALL_W := 0.12         # Stall-Übergangsbreite
const CL_MAX := 1.5
const OSWALD := 0.75          # Oswald-Faktor (induzierter Widerstand)
const CD0 := 0.030            # Parasitärwiderstand
const FLAP_LIFT := 0.55       # Landeklappen voll: zusätzlicher Auftriebsbeiwert ΔCl (mehr Auftrieb -> langsamer fliegen/abheben)
const FLAP_DRAG := 0.06       # Landeklappen voll: zusätzlicher Profilwiderstand ΔCd (bremst im Anflug, steileres Sinken)
const SIDE := 0.5             # Seitenkraft (Kurvenflug)
const PITCH_STAB := 0.5       # statische Nick-Stabilität (Wetterfahne)
const YAW_STAB := 0.6         # statische Gier-Stabilität (Wetterfahne)
const PROP_VMAX := 170.0      # Speed, bei der Propellerschub -> 0
const MAX_ANGVEL := 8.0
const LEVEL_K := 1.0          # sanftes Querlage-Ausnivellieren (nur Assist)

# Direkte Steuerflächen-Steuerung (wie SimplePlanes): Eingabe = Auslenkung,
# Drehmoment ~ Staudruck × Steuerfläche. Aerodynamische Dämpfung sorgt für satte,
# nicht-überschwingende Reaktion (statt Raten-Halte-Autopilot).
var assist := true            # T: an = mehr Dämpfung + Querlage-Hilfe, aus = roh/direkt
const CTRL_PITCH := 2.2       # Nick-Autorität (Basis + pro Steuerfläche)
const CTRL_PITCH_A := 3.5
const CTRL_YAW := 1.5
const CTRL_YAW_A := 3.0
const CTRL_ROLL := 9.0        # Rollen immer knackig (auch ohne Querruder)
const CTRL_ROLL_A := 6.0
const DAMP_PITCH := 5.5       # aerodynamische Drehdämpfung (verhindert Überdrehen)
const DAMP_YAW := 3.2
const DAMP_ROLL := 2.5
const MOUSE_AUTH := 1.4       # Maus-Flug: mehr Steuer-Autorität -> Soll-Raten schneller (Obergrenze: darüber überzieht/stallt der Nick)
const ARCADE_RESP := 6.0      # Arcade: wie schnell/smooth die Orientierung aufs Ziel slerpt (1/s) — exponentiell, kein Überschwingen
const ARCADE_VEL := 2.6       # Arcade: wie schnell die Geschwindigkeit der Nase folgt (fliegt wohin sie zeigt, kein Schlittern)
const BARREL_RATE := 5.0      # Fass-Roll: Ziel-Rollrate (rad/s) ~ 1 Rolle / 1,25 s (physikalisch geregelt)
const BARREL_GAIN := 0.9      # Fass-Roll: P-Anteil Rollraten-Regler (sanftes Anrollen)

# Vom FlightController gesetzt
var wing_area := 0.0
var eff_ar := 4.0
var lift_scale := 1.0
var pitch_area := 0.0
var roll_area := 0.0
var yaw_area := 0.0
var engines: Array = []       # [{pos, thrust, jet}]
var props: Array = []
var total_thrust := 0.0
# Survival-Upgrades (Multiplikatoren, vom FlightController gesetzt)
var thrust_mult := 1.0
var wing_mult := 1.0
var mass_mult := 1.0

# Tragflächen-Struktur & Widerstand
var wing_capacity := 0.0      # max. Auftriebskraft (N), bevor Flügel brechen
var drag_area := 0.0          # parasitärer Luftwiderstand cW·A (m²) des Modells
var wings_broken := false
var wing_status := "ok"
var parts: Array = []         # [{vis, cs, xform, csize, coffset, is_wing, control}]
var _break_queue: Array = []  # Teil-Indizes (Bruch-Wurzeln), abgearbeitet im _process (nicht in der Physik!)
const DRAG_K := 0.5           # parasitärer Modell-Widerstand (niedriger = schneller, v.a. im Sturzflug)

# Fahrwerk
var gear_items: Array = []    # [{vis, cs, retract, base}]
var gear_capacity := 0.0
var gear_overloaded := false
var gear_down := true         # ausgefahren?
var _gear_anim := 0.0         # 0 = unten, 1 = oben (Einziehfahrwerk)
var _collapsed := false       # Fahrwerk durch Überlast zusammengebrochen

# Eingaben
var throttle := 0.0
var in_pitch := 0.0
var in_roll := 0.0
var in_yaw := 0.0
var flaps := 0.0              # Landeklappen 0..1 (vom FlightController, Taste F): mehr Auftrieb + Widerstand
var inverted := false         # Q: Steuerung umkehren
var mouse_fly := false        # Maus-Flug aktiv? (dann kein Assist-Auto-Leveling — Bank-Regler nivelliert selbst)
var arcade := false           # Arcade-Lenkung? (kinematisch: Nase dreht super-smooth aufs Ziel, keine Stall-/G-Grenze)
var aim_world := Vector3(0, 0, -1)  # Zielrichtung (Welt), vom FlightController im Arcade-Modus gesetzt
var barrel_roll := 0          # 0=aus, ±1=Fass-Roll-Richtung (A/D lange halten) — kinematische, saubere Rolle

# Landung / Schaden
var landing_msg := ""
var _land_timer := 0.0
var _airborne := false
var _last_vy := 0.0
var _last_vel := Vector3.ZERO # Geschwindigkeit im letzten Frame in der Luft (für Aufprall-Härte)
const HARD_LAND := 3.0        # ab hier "harte Landung"
const BREAK_LAND := 7.0       # ab hier bricht das Fahrwerk
const CRASH_SPEED := 10.0     # Schließgeschwindigkeit (m/s) entlang Kontaktnormale, ab der ein
                              # getroffenes (Nicht-Fahrwerk-)Teil + sein Außen-Teilbaum abreißt

# Telemetrie
var airspeed := 0.0
var altitude := 0.0
var aoa_deg := 0.0
var climb := 0.0
var stall := false
var gforce := 1.0
var gear_status := "—"


func _ready() -> void:
	can_sleep = false
	continuous_cd = true
	angular_damp = 0.3
	linear_damp = 0.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.05
	pm.bounce = 0.0
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 8
	if gear_overloaded:
		_collapse_gear()


func _process(delta: float) -> void:
	# Abreißen/Reparenting NUR hier (nicht in _integrate_forces). Mehrere Brüche nacheinander
	# möglich (erst Flügelüberlast, später Crash) -> Queue statt einmaligem Flag.
	if not _break_queue.is_empty():
		var roots: Array = _break_queue.duplicate()
		_break_queue.clear()
		_break_subtree(roots)
	var spd := 4.0 + throttle * 60.0
	for p in props:
		if is_instance_valid(p):
			p.rotate_z(spd * delta)
	# Einziehfahrwerk animieren
	if not _collapsed:
		var target := 0.0 if gear_down else 1.0
		if absf(_gear_anim - target) > 0.001:
			_gear_anim = move_toward(_gear_anim, target, delta * 1.6)
			for g in gear_items:
				if not g["retract"]:
					continue
				var vis = g["vis"]
				if is_instance_valid(vis):
					var fold := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(88.0 * _gear_anim)),
						Vector3(0, 0.55 * _gear_anim, 0))
					vis.transform = g["base"] * fold
				var cs = g["cs"]
				if is_instance_valid(cs):
					cs.disabled = _gear_anim > 0.5
	_update_gear_status()
	if _land_timer > 0.0:
		_land_timer -= delta
		if _land_timer <= 0.0:
			landing_msg = ""


func _collapse_gear() -> void:
	_collapsed = true
	for g in gear_items:
		var cs = g["cs"]
		if is_instance_valid(cs):
			cs.set_deferred("disabled", true)   # nicht während _integrate_forces umschalten!
		var vis = g["vis"]
		if is_instance_valid(vis):
			# zur Seite weggeknickt + abgesenkt -> sichtbarer Kollaps
			vis.transform = g["base"] * Transform3D(Basis(Vector3.BACK, deg_to_rad(72.0)), Vector3(0, -0.12, 0))
	_update_gear_status()


func toggle_gear() -> void:
	if _collapsed:
		return
	var has_retract := false
	for g in gear_items:
		if g["retract"]:
			has_retract = true
			break
	if has_retract:
		gear_down = not gear_down


func _update_gear_status() -> void:
	if _collapsed:
		gear_status = "GEBROCHEN ⚠"
	elif gear_items.is_empty():
		gear_status = "keins"
	elif _gear_anim > 0.5:
		gear_status = "eingefahren"
	else:
		gear_status = "ausgefahren"


func toggle_invert() -> void:
	inverted = not inverted


# Flügel physisch abreißen — mit allem, was darauf montiert ist (Trümmer)
# Flugmodell aus den NICHT gebrochenen Teilen neu zusammenrechnen (nach Bruch/Build).
func recompute_aero() -> void:
	var tm := 0.0
	var com := Vector3.ZERO
	var wa := 0.0
	var ars := 0.0
	var lifts := 0.0
	var pa := 0.0
	var ra := 0.0
	var ya := 0.0
	var wc := 0.0
	var da := 0.0
	var thr := 0.0
	var eng: Array = []
	var prp: Array = []
	var gi: Array = []
	var gc := 0.0
	for pi in parts:
		if pi.get("broken", false):
			continue
		var m: float = pi["mass"]
		tm += m
		com += m * pi["pos"]
		da += pi["drag"]
		if pi["is_wing"]:
			var lp: float = pi["lift_part"]
			wa += lp
			ars += lp * float(pi["ar"])
			lifts += lp * float(pi["lift_coef"])
			wc += pi["wing_cap"]
			pa += pi["pitch_a"]
			ra += pi["roll_a"]
			ya += pi["yaw_a"]
		if float(pi["thrust"]) > 0.0:
			var et: float = float(pi["thrust"]) * thrust_mult
			eng.append({"pos": pi["pos"], "thrust": et, "jet": pi["jet"]})
			thr += et
			if pi["prop"] != null and is_instance_valid(pi["prop"]):
				prp.append(pi["prop"])
		if float(pi["gear_cap"]) > 0.0:
			gc += pi["gear_cap"]
			gi.append({"vis": pi["vis"], "cs": pi["cs"], "retract": pi["retract"], "base": pi["xform"]})
	wing_area = wa
	eff_ar = (ars / wa) if wa > 0.0 else 4.0
	lift_scale = (lifts / wa) if wa > 0.0 else 1.0
	pitch_area = pa
	roll_area = ra
	yaw_area = ya
	wing_capacity = wc * wing_mult
	drag_area = da
	total_thrust = thr
	engines = eng
	props = prp
	gear_items = gi
	gear_capacity = gc
	var tm_eff := tm * mass_mult
	gear_overloaded = gc > 0.0 and tm_eff > gc
	mass = maxf(tm_eff, 1.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = (com / tm) if tm > 0.0 else Vector3.ZERO


# Verbindungs-Baum ab dem Cockpit (BFS über Box-Nachbarschaft). parent[i] = Träger.
func _build_parents() -> Array:
	var n := parts.size()
	var parent: Array = []
	var adj: Array = []
	for i in n:
		parent.append(-1)
		adj.append([])
	for i in n:
		for j in range(i + 1, n):
			if _attached(parts[i], parts[j]) or _attached(parts[j], parts[i]):
				adj[i].append(j)
				adj[j].append(i)
	var root := 0
	for i in n:
		if parts[i].get("is_root", false):
			root = i
			break
	var seen := {root: true}
	var queue := [root]
	while not queue.is_empty():
		var cur = queue.pop_front()
		for nb in adj[cur]:
			if not seen.has(nb):
				seen[nb] = true
				parent[nb] = cur
				queue.append(nb)
	return parent


# Hauptflügel (ohne Steuerflächen) als Bruch-Wurzeln für den Flügel-Überlast-Bruch.
func _wing_root_indices() -> Array:
	var roots: Array = []
	for i in parts.size():
		if parts[i]["is_wing"] and String(parts[i]["control"]) == "":
			roots.append(i)
	if roots.is_empty():
		for i in parts.size():
			if parts[i]["is_wing"]:
				roots.append(i)
	return roots


# Bruch zum nächsten _process vormerken (Node-Umbau NIE in _integrate_forces).
func _queue_break(roots: Array) -> void:
	for r in roots:
		if not _break_queue.has(r):
			_break_queue.append(r)


# Reißt die Wurzel-Teile + ihren Außen-Teilbaum ab (alles, dessen Weg zum Cockpit durch
# eine Wurzel läuft); das Cockpit (Wurzel) bleibt immer dran. Die abgerissenen Teile werden
# zu einem Trümmer-RigidBody. Danach wird das Flugmodell (Auftrieb/Widerstand/Schub/Masse/
# COM) aus den ÜBRIGEN Teilen NEU berechnet -> fehlende Fläche/Schub/Gewicht zählt sofort.
func _break_subtree(roots: Array) -> void:
	if parts.is_empty() or roots.is_empty():
		return
	var parent := _build_parents()
	var rset := {}
	for r in roots:
		if r >= 0 and r < parts.size() and not parts[r].get("broken", false):
			rset[r] = true
	if rset.is_empty():
		return
	var brk := {}
	for i in parts.size():
		if parts[i].get("broken", false):
			continue
		var c = i
		var guard := 0
		while c >= 0 and guard < 256:
			if rset.has(c):
				brk[i] = true
				break
			c = parent[c]
			guard += 1
	for i in parts.size():
		if parts[i].get("is_root", false):
			brk.erase(i)
	if brk.is_empty():
		return
	var par := get_parent()
	if par == null:
		return
	# Trümmer-Körper mit den abgerissenen Teilen
	var debris := RigidBody3D.new()
	debris.add_to_group("debris")
	debris.collision_layer = 8
	debris.collision_mask = 1          # nur Boden/Hindernisse
	debris.angular_damp = 0.1
	var dmass := 0.0
	par.add_child(debris)
	debris.global_transform = global_transform
	debris.linear_velocity = linear_velocity
	debris.angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0), randf_range(-4.0, 4.0))
	for i in brk.keys():
		var cs = parts[i]["cs"]
		if is_instance_valid(cs):
			cs.disabled = true
		var vis = parts[i]["vis"]
		if is_instance_valid(vis):
			vis.reparent(debris, true)   # Weltposition beibehalten (Teil fällt mit ab)
		dmass += float(parts[i]["mass"])
		parts[i]["broken"] = true        # raus aus dem Flugmodell
	debris.mass = clampf(dmass, 20.0, 4000.0)
	var box := BoxShape3D.new()
	box.size = Vector3(3.5, 0.5, 2.0)
	var dcs := CollisionShape3D.new()
	dcs.shape = box
	debris.add_child(dcs)
	var tmr := get_tree().create_timer(9.0)
	tmr.timeout.connect(debris.queue_free)
	recompute_aero()


# Sitzt Teil "ci" auf Teil "pj"? (Box-Nachbarschaft in pj-Achsen, inkl. ci-Größe)
func _attached(ci: Dictionary, pj: Dictionary) -> bool:
	var xf: Transform3D = pj["xform"]
	var center: Vector3 = xf * pj["coffset"]
	var b := xf.basis.orthonormalized()
	var cc: Vector3 = ci["xform"] * ci["coffset"]
	var local := b.transposed() * (cc - center)
	var ch: Vector3 = ci["csize"] * 0.5
	var pad: float = maxf(maxf(ch.x, ch.y), ch.z) + 0.2
	var half: Vector3 = pj["csize"] * 0.5 + Vector3(pad, pad, pad)
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z


# Aufprall auswerten (Übergang Luft -> Boden/Hindernis): Landenote, Fahrwerksbruch und —
# bei hartem Aufprall — Abriss der GETROFFENEN Teile. Härte = Schließgeschwindigkeit entlang
# der Kontaktnormale, d.h. wie schnell man IN die Fläche fliegt (so zählt "ins Gelände/in eine
# Wand krachen", aber nicht das harmlose schnelle Entlanggleiten beim Landen). Bricht nur vor.
func _evaluate_impact(state: PhysicsDirectBodyState3D) -> void:
	var descent := maxf(0.0, -_last_vy)         # vertikale Sinkrate (für die Landenote)
	var n := state.get_contact_count()
	var crash_roots := {}
	var gear_hit_hard := false
	for i in n:
		var nrm := state.get_contact_local_normal(i)
		var closing := maxf(0.0, -_last_vel.dot(nrm))   # Tempo IN die getroffene Fläche
		if closing > CRASH_SPEED:
			var idx := _nearest_part_index(state.transform, state.get_contact_local_position(i))
			if idx < 0:
				continue
			if float(parts[idx]["gear_cap"]) > 0.0:
				gear_hit_hard = true            # Rad hart aufgesetzt -> Fahrwerkskollaps (kein Debris)
			else:
				crash_roots[idx] = true         # Flügel/Rumpf/Triebwerk … -> abreißen
	if not crash_roots.is_empty():
		_queue_break(crash_roots.keys())
		landing_msg = "💥 CRASH — Teile abgerissen!"
		_land_timer = 4.0
	# Fahrwerk: zerstörerische Sinkrate ODER harter Radkontakt -> Kollaps
	if descent > BREAK_LAND or gear_hit_hard:
		if not _collapsed and not gear_items.is_empty():
			_collapse_gear()
		if crash_roots.is_empty():
			landing_msg = "💥 HARTE LANDUNG — Fahrwerk gebrochen!"
			_land_timer = 3.5
		return
	# normale Landenoten (nur wenn nichts abgerissen ist)
	if crash_roots.is_empty():
		if descent > HARD_LAND:
			landing_msg = "⚠ Harte Landung (%d m/s)" % int(round(descent))
			_land_timer = 3.5
		elif descent > 0.6:
			landing_msg = "🛬 Saubere Landung ✓"
			_land_timer = 3.5


# Index des Teils, dessen Kollisionsbox-Mitte dem Welt-Kontaktpunkt am nächsten liegt.
func _nearest_part_index(body_xf: Transform3D, wpos: Vector3) -> int:
	var best := -1
	var bestd := INF
	for i in parts.size():
		if parts[i].get("broken", false):
			continue
		var center_local: Vector3 = parts[i]["xform"] * parts[i]["coffset"]
		var wc: Vector3 = body_xf * center_local
		var d := wc.distance_squared_to(wpos)
		if d < bestd:
			bestd = d
			best = i
	return best


# Beim Neustart: Fahrwerk wiederherstellen (außer dauerhaft überlastet)
func reset_gear() -> void:
	landing_msg = ""
	_land_timer = 0.0
	_airborne = false
	_last_vy = 0.0
	wings_broken = false
	wing_status = "ok"
	gear_down = true
	_gear_anim = 0.0
	if gear_overloaded:
		_collapse_gear()
	else:
		_collapsed = false
		for g in gear_items:
			var cs = g["cs"]
			if is_instance_valid(cs):
				cs.disabled = false
			var vis = g["vis"]
			if is_instance_valid(vis):
				vis.transform = g["base"]
		_update_gear_status()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not state.linear_velocity.is_finite():
		state.linear_velocity = Vector3.ZERO
	if not state.angular_velocity.is_finite():
		state.angular_velocity = Vector3.ZERO

	var xf := state.transform
	var v_lin := state.linear_velocity
	var v_ang := state.angular_velocity
	var fwd := -xf.basis.z

	airspeed = v_lin.length()
	altitude = xf.origin.y
	climb = v_lin.y
	var rho := RHO0 * exp(-maxf(altitude, 0.0) / SCALE_H)

	# --- Aufsetz-Erkennung (harte Landung / Fahrwerksbruch) ----------------
	var on_ground := state.get_contact_count() > 0
	if on_ground:
		if _airborne:
			_airborne = false
			_evaluate_impact(state)   # Landenote + Fahrwerksbruch + Teile-Abriss bei hartem Aufprall
	else:
		_airborne = true
		_last_vy = v_lin.y
		_last_vel = v_lin

	var tf := Vector3.ZERO
	var tt := Vector3.ZERO

	# --- Schub (zentral; Propeller fällt mit Tempo, Jet konstant) ----------
	var fs := v_lin.dot(fwd)
	var thr := 0.0
	for e in engines:
		var t: float = float(e["thrust"])
		if not e.get("jet", false):
			t *= clampf(1.0 - fs / PROP_VMAX, 0.0, 1.0)
		thr += t
	tf += fwd * (thr * maxf(throttle, 0.0))
	# Bremsen bei negativem Gas: Luftbremse + (am Boden) Radbremse
	if throttle < 0.0 and airspeed > 0.3:
		var brake := -throttle
		tf += -v_lin.normalized() * (0.5 * rho * airspeed * airspeed * (wing_area * 0.3 + drag_area + 0.5) * brake)
		if on_ground:
			tf += -v_lin * (brake * mass * 3.0)

	# --- Aerodynamik (gebündelt, wissenschaftliche Koeffizienten) ----------
	var sp := v_lin.length()
	if sp > 0.5 and wing_area > 0.0:
		var v_b := xf.basis.transposed() * v_lin
		var denom: float = absf(v_b.z) + 0.6
		var aoa := atan2(-v_b.y, denom) + INCIDENCE
		var beta := atan2(v_b.x, denom)
		var q := 0.5 * rho * sp * sp * LIFT_K
		var cl_a := TAU * eff_ar / (eff_ar + 2.0)
		var sigma := smoothstep(STALL_A, STALL_A + STALL_W, absf(aoa))
		var cl := lerpf(clampf(cl_a * aoa, -CL_MAX, CL_MAX), sin(2.0 * aoa), sigma) * lift_scale
		# Landeklappen: heben den Auftriebsbeiwert an (Kamber) -> Abheben/Landen bei weniger Tempo.
		# NACH der CL_MAX-Klemmung addiert, da Klappen den Maximalauftrieb real anheben.
		cl += flaps * FLAP_LIFT
		var cd := CD0 + cl * cl / (PI * eff_ar * OSWALD) + sigma * (1.0 - cos(2.0 * aoa)) * 0.5 + flaps * FLAP_DRAG
		var lift_mag := q * wing_area * cl
		# Strukturelle Überlast: zu viel Auftrieb (zu hohe G) -> Flügel brechen
		if not wings_broken and not arcade and barrel_roll == 0 and wing_capacity > 0.0 and absf(lift_mag) > wing_capacity:
			wings_broken = true
			_queue_break(_wing_root_indices())   # Abtrennen erst im _process (nicht im Physik-Schritt)
			landing_msg = "💥 FLÜGEL ÜBERLASTET — abgerissen!"
			_land_timer = 4.0
		if wings_broken:
			cd += 0.25          # zerfetzte Struktur -> mehr Widerstand
			lift_mag = q * wing_area * cl
		var f_b := Vector3(-sin(beta) * q * wing_area * SIDE, lift_mag, 0.0)
		# Flügel-Widerstand mit ECHTEM Staudruck (nicht mit LIFT_K aufblähen) -> im
		# Sturzflug baut sich realistisch Tempo auf.
		f_b += -v_b.normalized() * ((q / LIFT_K) * wing_area * cd)
		tf += xf.basis * f_b
		# statische Stabilität (Nase folgt der Anströmung; skaliert mit Leitwerk)
		tt += xf.basis.x * (-aoa * q * (0.3 + pitch_area) * PITCH_STAB)
		tt += xf.basis.y * (beta * q * (0.3 + yaw_area) * YAW_STAB)
		aoa_deg = rad_to_deg(absf(aoa))
		stall = absf(aoa) > STALL_A
	else:
		aoa_deg = 0.0
		stall = false
	wing_status = "GEBROCHEN ⚠" if wings_broken else "ok"

	# --- Parasitärer Luftwiderstand des Modells (Bauform zählt) ------------
	if drag_area > 0.0 and sp > 0.5:
		tf += -v_lin.normalized() * (0.5 * rho * sp * sp * drag_area * DRAG_K)

	# --- Fahrwerks-Widerstand (ausgefahren bremst; Bauchlandung = viel) ----
	if sp > 0.5:
		var gd := 0.0
		if _collapsed:
			gd = float(gear_items.size()) * 2.5
		else:
			for g in gear_items:
				gd += (1.0 - _gear_anim) if g["retract"] else 1.0
		if gd > 0.0:
			tf += -v_lin.normalized() * (0.5 * rho * sp * sp * gd * 0.06)

	# --- Steuerung: Arcade (kinematisch) ODER Steuerflächen-Torque (inkl. Fass-Roll) ---------
	var arcade_steer := arcade and mouse_fly
	if not arcade_steer:
		var wb := xf.basis.transposed() * v_ang
		var inv := -1.0 if inverted else 1.0
		# Steuer-Autorität skaliert mit Staudruck: langsam teigig, schnell knackig
		var qfac := clampf(0.5 * rho * airspeed * airspeed / 180.0, 0.04, 2.0)
		var roll_cmd := in_roll * inv * (CTRL_ROLL + CTRL_ROLL_A * roll_area)
		if barrel_roll != 0:
			# Fass-Roll: Roll als RATENREGLER auf BARREL_RATE -> PHYSIKALISCH (Trägheit beim
			# Anrollen, Nase wandert leicht = natürlich), aber auf eine kontrollierte Rate begrenzt.
			var rr := clampf((BARREL_RATE * float(barrel_roll) - wb.z) * BARREL_GAIN, -1.0, 1.0)
			roll_cmd = rr * (CTRL_ROLL + CTRL_ROLL_A * roll_area)
		var cmd := Vector3(
			in_pitch * inv * (CTRL_PITCH + CTRL_PITCH_A * pitch_area),
			in_yaw * inv * (CTRL_YAW + CTRL_YAW_A * yaw_area),
			roll_cmd)
		tt += xf.basis * (cmd * qfac * mass * (MOUSE_AUTH if mouse_fly else 1.0))
		# Aerodynamische Drehdämpfung (gegen Schwingen) — wächst mit Tempo.
		# Im Fass-Roll die ROLL-Dämpfung aus (sonst kommt die Rolle nicht auf Touren);
		# Nick/Gier bleiben gedämpft. Assist verstärkt nur Nick/Gier.
		var dfac := (0.35 + qfac) * mass
		var apq := 1.6 if assist else 1.0
		var roll_d: float = 0.0 if barrel_roll != 0 else wb.z * DAMP_ROLL
		tt += xf.basis * (-Vector3(wb.x * DAMP_PITCH * apq, wb.y * DAMP_YAW * apq, roll_d) * dfac)
		# sanftes Ausnivellieren der Querlage, wenn kein Roll-Befehl (nur Assist; nicht im Fass-Roll).
		if assist and not mouse_fly and barrel_roll == 0 and absf(in_roll) < 0.05 and airspeed > 6.0:
			tt += xf.basis.z * (-xf.basis.x.y * LEVEL_K * mass)

	# --- Sicherheit & Anwenden ---------------------------------------------
	if not tf.is_finite():
		tf = Vector3.ZERO
	if not tt.is_finite():
		tt = Vector3.ZERO
	tf = tf.limit_length(mass * 130.0)   # nur NaN-/Runaway-Sicherung, klippt normale Aero nicht mehr
	tt = tt.limit_length(mass * 90.0)
	state.apply_central_force(tf)
	if arcade_steer:
		_arcade_steer(state)   # kinematische, butterweiche Lenkung (keine Stall-/G-Grenze)
	else:
		state.apply_torque(tt)
		if state.angular_velocity.length() > MAX_ANGVEL:
			state.angular_velocity = state.angular_velocity.normalized() * MAX_ANGVEL

	gforce = tf.length() / maxf(mass * 9.81, 1.0)


# Arcade-Lenkung: dreht die Orientierung kinematisch (per Slerp) super-smooth Richtung
# Zielrichtung und lässt die Geschwindigkeit der Nase folgen. Unabhängig von Ruder-
# Autorität/Stall/G -> butterweiches, direktes Lenken (kein Trudeln, kein Überschwingen).
func _arcade_steer(state: PhysicsDirectBodyState3D) -> void:
	var cur_basis := state.transform.basis
	var fwd := aim_world
	if fwd.length() < 0.01:
		return
	fwd = fwd.normalized()
	# Soll-Querlage (kosmetisch): in die Kurve lehnen, proportional zum Horizontalfehler
	var e := cur_basis.transposed() * fwd
	var bank := clampf(atan2(e.x, -e.z) * 0.9, -1.15, 1.15)
	# Ziel-Basis: Nase (-Z) auf fwd, um fwd gebankt
	var up0 := Vector3.UP
	if absf(fwd.dot(up0)) > 0.985:
		up0 = cur_basis.y
	var right0 := fwd.cross(up0).normalized()
	var up1 := right0.cross(fwd).normalized()
	var tb := Basis(right0.rotated(fwd, bank), up1.rotated(fwd, bank), -fwd).orthonormalized()
	# Orientierung smooth (exponentiell) zum Ziel slerpen -> reagiert sofort, ohne zu zappeln
	var k := clampf(ARCADE_RESP * state.step, 0.0, 1.0)
	var nb := Basis(cur_basis.get_rotation_quaternion().slerp(tb.get_rotation_quaternion(), k))
	# WICHTIG: ganzen Transform zuweisen (state.transform.basis=… schreibt nicht zurück — Godot-Falle)
	var xform := state.transform
	xform.basis = nb
	state.transform = xform
	state.angular_velocity = Vector3.ZERO
	# Geschwindigkeit der Nase nachführen (fliegt wohin sie zeigt) — Betrag bleibt, Schub/Schwerkraft wirken weiter
	var spd := state.linear_velocity.length()
	if spd > 1.0:
		var nd := -nb.z
		state.linear_velocity = state.linear_velocity.lerp(nd * spd, clampf(ARCADE_VEL * state.step, 0.0, 1.0))


