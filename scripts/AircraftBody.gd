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
const LIFT_K := 2.9           # globaler Kraftfaktor (Spielgefühl: in der Luft leicht/arcadig)
const INCIDENCE := 0.025      # ~1.4° Flügel-Einstellwinkel (KEIN Selbst-Abheben mehr -> zum Start mit W rotieren)
# Abhebe-Gate: bei niedrigem Tempo wird der Auftrieb gedämpft -> erst Tempo aufbauen
# (spürbar längere Rollstrecke). Ab LIFT_V1 voller Auftrieb -> in der Luft bleibt's leicht.
const LIFT_LO := 0.36         # Auftriebs-Faktor im Stand/sehr langsam (fest am Boden)
const LIFT_GATE_LO := 0.85    # Gate-Beginn = takeoff_v · 0.85 (darunter gedämpft)
const LIFT_GATE_HI := 1.65    # voller Auftrieb ab takeoff_v · 1.65 (in der Luft arcadig)
const STALL_A := 0.27         # Stall-Anstellwinkel (~15.5°)
const STALL_RECOVER := 2.2    # Nase-runter-Hilfe im Stall (Moment ~ mass; 0 = aus)
const STALL_W := 0.12         # Stall-Übergangsbreite
const CL_MAX := 1.5
const OSWALD := 0.75          # Oswald-Faktor (induzierter Widerstand)
const CD0 := 0.016            # Flügel-Profilwiderstand (Rumpf steckt schon in drag_area ->
							  # höher = Doppelzählung, Flieger bremste in der Luft viel zu stark aus)
const FLAP_LIFT := 0.55       # Landeklappen voll: zusätzlicher Auftriebsbeiwert ΔCl (mehr Auftrieb -> langsamer fliegen/abheben)
const FLAP_DRAG := 0.06       # Landeklappen voll: zusätzlicher Profilwiderstand ΔCd (bremst im Anflug, steileres Sinken)
const SIDE := 0.5             # Seitenkraft (Kurvenflug)
const PITCH_STAB := 0.5       # statische Nick-Stabilität (Wetterfahne)
const YAW_STAB := 0.6         # statische Gier-Stabilität (Wetterfahne)
const PROP_VMAX := 140.0      # Speed, bei der Propellerschub -> 0 (Props oben raus schwächer als Jets)
const MAX_ANGVEL := 8.0
# (Auto-Ausnivellieren der Querlage wurde auf Wunsch entfernt — Bank bleibt stehen.)

# Direkte Steuerflächen-Steuerung (wie SimplePlanes): Eingabe = Auslenkung,
# Drehmoment ~ Staudruck × Steuerfläche. Aerodynamische Dämpfung sorgt für satte,
# nicht-überschwingende Reaktion (statt Raten-Halte-Autopilot).
var assist := true            # T: an = mehr Dämpfung + Querlage-Hilfe, aus = roh/direkt
const CTRL_PITCH := 2.2       # Nick-Autorität (Basis + pro Steuerfläche)
const CTRL_PITCH_A := 3.5
const CTRL_YAW := 1.5
const CTRL_YAW_A := 3.0
const COORD_BANK := 0.32      # Auto-Ruderkoordination: Gier-Beimischung pro rad Querlage (Tastatur)
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
const AB_BOOST := 0.5         # Nachbrenner: Extra-Schub für Jets in der AB-Zone (100→110 % = +50 %)
const AB_SPOOL_UP := 2.2      # Nachbrenner zündet nicht schlagartig — er spult hoch (exp. Rate, ~1 s auf voll)
const AB_SPOOL_DN := 3.5      # ... und brennt beim Zurücknehmen schneller ab
# Triebwerks-Trägheit: der Schub kommt nicht sofort, die Turbine/der Propeller spult hoch
# (realistische Beschleunigungskurve: sanfter Anlauf, dann Aufbau). Nur der Übergang —
# der eingeschwungene Schub (Top-Speed/Sturzflug) bleibt unverändert.
const SPOOL_UP := 1.3         # Hochlauf (exp. Rate, ~90 % in ~1,8 s)
const SPOOL_DN := 2.2         # Auslauf etwas schneller

# Vom FlightController gesetzt
var wing_area := 0.0
var takeoff_v := 35.0          # Referenz-Abhebegeschwindigkeit (skaliert das Abhebe-Gate)
var eff_ar := 4.0
var lift_scale := 1.0
var pitch_area := 0.0
var roll_area := 0.0
var yaw_area := 0.0
var engines: Array = []       # [{pos, thrust, jet}]
var props: Array = []
var wheels: Array = []        # [{node ("Wheel", Origin=Achse), r}] — rollen sichtbar am Boden
var _wheel_spin := 0.0
var _overload_t := 0.0        # wie lange die Flügel-Last schon ÜBER dem Limit liegt (s)        # aktuelle Rad-Umfangsgeschwindigkeit (m/s, trudelt in der Luft aus)
var surfaces: Array = []      # [{node, role, dn, side}] bewegliche Flächen: Klappen + Ruder
var _afterburners: Array = [] # [{root, plume, core, light, sparks, plume_mat, core_mat}] an Jet-Düsen
var _ab_time := 0.0           # Flacker-/Diamanten-Animationszeit für den Nachbrenner-Shader
var _ab_spool := 0.0          # hochgespulter Nachbrenner-Pegel 0..1 (zeitlicher Verlauf, kein harter Sprung)
var _engine_spool := 0.0      # tatsächliche Triebwerksleistung 0..1 (eilt der Drossel träge nach)
var _flame_shader_cache: Shader = null
var _flame_mesh_cache := {}   # base_r -> ArrayMesh (Flammen-Kegel, Länge 1)
var _vapor: Array = []        # CPUParticles3D an Flügelspitzen (Wirbelschleppen bei hoher G)
var _damage_smoke: CPUParticles3D = null  # Rauchfahne, wenn das Flugzeug Teile verloren hat
var _exhaust_fx: Array = []   # [{startup, soot, ignite}] Rauch-Emitter je Triebwerk (Auspuff)
var _spawned := false         # erster _process-Frame -> Triebwerk "anlassen" = Startrauch-Stoß
var _ab_was_on := false       # Flanke normal->Nachbrenner -> EIN kurzer, sehr starker Rußstoß
var _flap_vis := 0.0          # geglättete sichtbare Klappenstellung 0..1 (fährt smooth aus/ein)
const FLAP_MAX_DEG := 40.0    # max. Klappenausschlag bei voll Klappen
const FLAP_RATE := 0.28       # Ausfahr-/Einfahrgeschwindigkeit (1/s): voll ~3.5 s, pro Stufe ~1.8 s (realistisch träge)
const FLAPERON_DEG := 12.0    # zusätzl. gegensinniger Klappen-Ausschlag bei Roll (Flaperon -> Roll sichtbar)
const CTRL_DEG := 24.0        # max. Ruderausschlag (Höhe/Seite/Quer)
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
var _detach_queue: Array = []  # Teil-Indizes von verschossener Munition -> Visual entfernen + Aero neu
var _recoil := Vector3.ZERO   # aufsummierter Rückstoß-Impuls (Waffenfeuer), im _integrate_forces angewandt
const DRAG_K := 0.3           # parasitärer Modell-Widerstand (0.5 bremste ohne Schub VIEL zu hart:
							  # 150->60 m/s in 5 s; jetzt rollt der Flieger realistisch träger aus)

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
var aim_world := Vector3(0, 0, -1)  # Zielrichtung (Welt), vom FlightController je Frame gesetzt
var mouse_bank_offset := 0.0   # gehaltene A/D-Querlage (vom FlightController) -> fließt in die Ziel-Lage
var barrel_roll := 0          # 0=aus, ±1=Fass-Roll-Richtung (A/D lange halten) — kinematische, saubere Rolle

# Landung / Schaden
var landing_msg := ""
var _land_timer := 0.0
var _airborne := false
var _last_vy := 0.0
var _last_vel := Vector3.ZERO # Geschwindigkeit im letzten Frame in der Luft (für Aufprall-Härte)
const HARD_LAND := 3.0        # ab hier "harte Landung"
const BREAK_LAND := 7.0       # (Altwert, jetzt über Fahrwerks-Strukturwert geregelt)
const CRASH_SPEED := 10.0     # (Altwert, Bruch jetzt pro Teil über part_strength)
const EXPLODE_SPEED := 28.0   # ab hier: GANZES Flugzeug zerschellt (selbst der Rumpf hält das
                              # nicht mehr) — darunter brechen einzelne Teile gemäß Strukturwert
var exploded := false         # ganzes Flugzeug zerschellt? (bis Reset)
var _explode_pending := false # Explosion fürs nächste _process vorgemerkt (nicht in _integrate_forces!)
var _dust_pending := 0.0      # Aufsetz-Staub fürs nächste _process (Sinkrate; 0 = nichts)

# Telemetrie
var airspeed := 0.0
var altitude := 0.0
var aoa_deg := 0.0
var aoa_signed := 0.0         # AoA MIT Vorzeichen (rad) — für den Instructor-AoA-Limiter
var load_factor := 0.0        # signierter Lastfaktor lift/(m·g) — für den Instructor-G-Limiter
var climb := 0.0
var stall := false
var gforce := 1.0
var gear_status := "—"
var shake_request := 0.0      # einmaliger Kamera-Shake-Impuls (vom FlightController abgeholt)


func _ready() -> void:
	can_sleep = false
	continuous_cd = true
	angular_damp = 0.3
	# WICHTIG: REPLACE statt COMBINE — sonst wird linear_damp=0 mit dem Projekt-Default
	# (0.1) KOMBINIERT und bremst versteckt mit 0.1·v (bei 140 m/s ~14 m/s² Phantom-
	# Bremse, mehr als die ganze Aerodynamik!). Der Flieger soll NUR über die
	# modellierten Widerstände Tempo verlieren.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.05
	pm.bounce = 0.0
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 8
	if gear_overloaded:
		_queue_break(_gear_part_indices())   # überlastete Reifen reißen ab (Trümmer), nicht einknicken


func _process(delta: float) -> void:
	# Abreißen/Reparenting/Explosion NUR hier (nicht in _integrate_forces).
	if _explode_pending:
		_explode_pending = false
		_break_queue.clear()
		_explode()
	elif not _break_queue.is_empty():
		# Mehrere Brüche nacheinander möglich (erst Flügelüberlast, später Crash) -> Queue.
		var roots: Array = _break_queue.duplicate()
		_break_queue.clear()
		_break_subtree(roots)
	# Aufsetz-Staub (in _integrate_forces vorgemerkt; Node-Spawn nur hier)
	if _dust_pending > 0.0:
		_spawn_landing_dust(_dust_pending)
		_dust_pending = 0.0
	# Verschossene Munition: Teil-Visual entfernen (ist weggeflogen) + Flugmodell neu rechnen.
	if not _detach_queue.is_empty():
		var changed := false
		for idx in _detach_queue:
			if idx >= 0 and idx < parts.size() and not parts[idx].get("broken", false):
				parts[idx]["broken"] = true
				var dcs = parts[idx]["cs"]
				if is_instance_valid(dcs):
					dcs.queue_free()
				var dvis = parts[idx]["vis"]
				if is_instance_valid(dvis):
					dvis.queue_free()
				changed = true
		_detach_queue.clear()
		if changed:
			recompute_aero()   # leichter, weniger Widerstand, COM verschiebt sich
	# Propeller drehen gemächlich; Jet-Fans drehen viel schneller — und bei Vollgas/
	# Nachbrenner ("richtig Gas") nochmal deutlich schneller.
	var prop_spd := 4.0 + _engine_spool * 60.0
	var jet_spd := 25.0 + _engine_spool * 150.0 + _ab_spool * 110.0
	for p in props:
		var pn = p["node"]
		if is_instance_valid(pn):
			pn.rotate_z((jet_spd if p["jet"] else prop_spd) * float(p.get("spin", 1.0)) * delta)
	# Räder ROLLEN am Boden: Drehrate = Bodengeschwindigkeit / Radius (um die Achs-X).
	# In der Luft trudeln sie langsam aus (kein abruptes Stehenbleiben).
	if not wheels.is_empty():
		var vfwd: float = -(global_transform.basis.transposed() * linear_velocity).z
		if get_contact_count() > 0 and absf(vfwd) > 0.05:
			_wheel_spin = vfwd
		else:
			_wheel_spin = move_toward(_wheel_spin, 0.0, 18.0 * delta)
		if absf(_wheel_spin) > 0.02:
			for w in wheels:
				var wn = w["node"]
				if is_instance_valid(wn):
					wn.rotate_x(_wheel_spin / w["r"] * delta)
	# Bewegliche Flächen animieren (Scharnier dreht um lokale X-Achse). dn = Welt-"unten"-Vorzeichen.
	# Klappe: Landestellung + gegensinniger Roll-Anteil (Flaperon). Ruder folgen Pitch/Yaw/Roll.
	# _flap_vis wird in _integrate_forces (physikgetaktet) langsam gerampt -> hier nur lesen.
	for s in surfaces:
		var node = s["node"]
		if not is_instance_valid(node):
			continue
		var defl := 0.0     # Grad, + = Hinterkante nach unten (Welt), über dn ausgerichtet
		match String(s["role"]):
			"flap":
				defl = _flap_vis * FLAP_MAX_DEG + in_roll * float(s["side"]) * FLAPERON_DEG
			"pitch":
				defl = -in_pitch * CTRL_DEG                        # Höhenruder hoch beim Ziehen
			"roll":
				defl = in_roll * float(s["side"]) * CTRL_DEG       # Querruder gegensinnig
			"yaw":
				defl = in_yaw * CTRL_DEG                           # Seitenruder
		# NICHT 1:1 pro Frame aufs Scharnier malen: der Maus-Instructor dithert
		# naturgemäß minimal um die Nulllage (Raten-Schleife + Trim) — die Ruder
		# zappelten sichtbar im Geradeausflug. Mini-Hysterese friert Chatter unter
		# ~0.7° ein, ein Tiefpass (Servo-Gefühl) lässt echte Ausschläge flüssig durch.
		var tgt := float(s["dn"]) * deg_to_rad(defl)
		var cur: float = node.rotation.x
		var rate := 10.0 if absf(tgt - cur) > deg_to_rad(0.7) else 1.5
		node.rotation.x = lerpf(cur, tgt, clampf(delta * rate, 0.0, 1.0))

	# Turbine 0..100 %: dezentes kurzes Abgasglühen. Nachbrenner 100..110 %: lange,
	# helle Flamme (blau-weißer Kern -> orange Fahne mit Mach-Diamanten) + Funken + Glow.
	_ab_time += delta
	var thr_n := clampf(throttle, 0.0, 1.0)
	var ab := _ab_spool                                   # hochgespulter Nachbrenner (zeitlicher Verlauf)
	var lit := throttle > 0.04 or ab > 0.01
	for d in _afterburners:
		var root = d["root"]
		if not is_instance_valid(root):
			continue
		root.visible = lit
		if not lit:
			continue
		var plume: MeshInstance3D = d["plume"]
		var core: MeshInstance3D = d["core"]
		var rfac: float = d.get("rfac", 1.0)        # Flamme skaliert mit der Triebwerksgröße
		# Normal kurz/schmal, im Nachbrenner schießt die Flamme lang & breit raus.
		var pw := (0.7 + ab * 0.6) * rfac
		plume.scale = Vector3(pw, pw, (0.45 + thr_n * 0.75 + ab * 4.2) * rfac)
		var cw := (0.62 + ab * 0.55) * rfac
		core.scale = Vector3(cw, cw, (0.3 + thr_n * 0.45 + ab * 1.6) * rfac)
		var pm: ShaderMaterial = d["plume_mat"]
		var cm: ShaderMaterial = d["core_mat"]
		pm.set_shader_parameter("intensity", 0.18 + thr_n * 0.32 + ab * 1.35)
		pm.set_shader_parameter("t_time", _ab_time)
		cm.set_shader_parameter("intensity", 0.22 + thr_n * 0.4 + ab * 1.5)
		cm.set_shader_parameter("t_time", _ab_time)
		cm.set_shader_parameter("diamonds", ab)
		var light: OmniLight3D = d["light"]
		light.light_energy = thr_n * 0.45 + ab * 5.5
		light.omni_range = (2.5 + ab * 5.0) * rfac
		var sparks = d["sparks"]
		if is_instance_valid(sparks):
			sparks.emitting = ab > 0.05
	# Auspuff-Rauch (nur Spitfire-Engine): Startrauch beim Anlassen + schwarzer Rauch bei 100..110 %
	if not _spawned and not _exhaust_fx.is_empty():
		_spawned = true
		for fxd in _exhaust_fx:
			var su = fxd.get("startup")
			if su != null and is_instance_valid(su):
				su.restart()
				su.emitting = true
	# Schwarzer Rauch nur als EIN kurzer, starker Stoß beim Übergang normal -> Nachbrenner (>100 %)
	var ab_now := throttle >= 1.0
	if ab_now and not _ab_was_on:               # steigende Flanke: rein in den Nachbrenner
		for fxd in _exhaust_fx:
			var bk = fxd.get("black")
			if bk != null and is_instance_valid(bk):
				bk.restart()
				bk.emitting = true
	_ab_was_on = ab_now
	var vap_on := gforce > 4.5 or airspeed > 130.0
	for v in _vapor:
		if is_instance_valid(v):
			v.emitting = vap_on
	# Einziehfahrwerk animieren
	if not _collapsed:
		var target := 0.0 if gear_down else 1.0
		if absf(_gear_anim - target) > 0.001:
			_gear_anim = move_toward(_gear_anim, target, delta * 1.35)
			var a := _gear_anim
			var leg_fold := smoothstep(0.12, 0.9, a)
			var door_open := smoothstep(0.0, 0.16, a) - smoothstep(0.84, 1.0, a)
			for g in gear_items:
				if not g["retract"]:
					continue
				var leg = g["leg"]
				if leg != null and is_instance_valid(leg):
					# Außen sitzende Beine (Tragflächen-Fahrwerk) klappen um die LÄNGSACHSE (Z)
					# nach AUSSEN in den Flügel hoch (echte Spitfire-Art); die gespiegelte linke
					# Hälfte (improper Basis) klappt automatisch zur Gegenseite (auch nach außen).
					# Mittig sitzende Beine (Bug-/Heckfahrwerk) klappen stattdessen um X nach VORN.
					var lr: Transform3D = g["leg_rest"]
					var fold_axis := Vector3.BACK if absf(g["base"].origin.x) > 0.25 else Vector3.RIGHT
					leg.transform = Transform3D(Basis(fold_axis, deg_to_rad(88.0 * leg_fold)) * lr.basis, lr.origin)
					var door = g["door"]
					if door != null and is_instance_valid(door):
						var dr: Transform3D = g["door_rest"]
						door.transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(92.0 * door_open)) * dr.basis, dr.origin)
				else:
					# Fallback: altes Einteiler-Modell um Box-Mitte klappen
					var vis = g["vis"]
					if is_instance_valid(vis):
						vis.transform = g["base"] * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(88.0 * a)), Vector3(0, 0.55 * a, 0))
				var cs = g["cs"]
				if is_instance_valid(cs):
					cs.disabled = a > 0.5
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
	var fl: Array = []
	var gi: Array = []
	var whl: Array = []
	var gc := 0.0
	for pi in parts:
		if pi.get("broken", false):
			continue
		if pi.get("surf") != null and is_instance_valid(pi["surf"]):
			fl.append({"node": pi["surf"], "role": pi.get("surf_role", "flap"),
				"dn": pi.get("surf_dn", 1.0), "side": pi.get("surf_side", 1.0)})
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
			# Schubrichtung = Blickrichtung des Triebwerks (-Z seiner Teil-Basis), KÖRPER-LOKAL.
			# Bei 'reverse' (Prop-Option) kehrt sich die Richtung um (Schub nach hinten).
			var ex: Transform3D = pi["xform"]
			var eb := ex.basis.orthonormalized()      # Orientierung des Triebwerks (für FX-Ausrichtung)
			if eb.determinant() < 0.0:                 # gespiegelte Teile: proper machen
				eb.x = -eb.x
			var edir: Vector3 = (-ex.basis.z).normalized()
			if bool(pi.get("thrust_reverse", false)):
				edir = -edir
			eng.append({"id": pi.get("id", ""), "pos": pi["pos"], "thrust": et, "jet": pi["jet"],
				"scale": pi.get("scale", Vector3.ONE), "dir": edir, "basis": eb})
			thr += et
			if pi["prop"] != null and is_instance_valid(pi["prop"]):
				prp.append({"node": pi["prop"], "jet": pi.get("jet", false),
					"spin": float(PartCatalog.get_part(pi.get("id", "")).get("spin_mult", 1.0))})
		if float(pi["gear_cap"]) > 0.0:
			gc += pi["gear_cap"]
			var gvis = pi["vis"]
			var gleg = null
			var gdoor = null
			var glr := Transform3D.IDENTITY
			var gdr := Transform3D.IDENTITY
			if is_instance_valid(gvis):
				gleg = gvis.find_child("Leg", true, false)
				gdoor = gvis.find_child("Door", true, false)
				if gleg != null:
					glr = gleg.transform
				if gdoor != null:
					gdr = gdoor.transform
			gi.append({"vis": gvis, "cs": pi["cs"], "retract": pi["retract"], "base": pi["xform"],
				"leg": gleg, "door": gdoor, "leg_rest": glr, "door_rest": gdr})
			# Rad-Node ("Wheel", Origin = Achse) fürs sichtbare Rollen am Boden
			var wn = pi.get("wheel")
			if wn != null and is_instance_valid(wn):
				whl.append({"node": wn, "r": maxf(float(pi.get("wheel_r", 0.3)), 0.05)})
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
	surfaces = fl
	gear_items = gi
	wheels = whl
	gear_capacity = gc
	var tm_eff := tm * mass_mult
	gear_overloaded = gc > 0.0 and tm_eff > gc
	mass = maxf(tm_eff, 1.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = (com / tm) if tm > 0.0 else Vector3.ZERO
	# Referenz-Abhebegeschwindigkeit aus der Flächenbelastung (v=√(2·W/(ρ·S·CL))).
	# Daran wird das Abhebe-Gate ausgerichtet: leichte Props heben früh ab, schwere Jets
	# brauchen mehr Tempo -> physikalisch korrekt skaliert über alle Flugzeuge.
	takeoff_v = clampf(sqrt(2.0 * mass * 9.81 / maxf(RHO0 * wing_area, 1.0)), 14.0, 80.0) if wing_area > 0.1 else 35.0
	_rebuild_fx()


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


# Indizes aller (noch heilen) Fahrwerksteile — für Reifen-Abriss bei Überlast.
func _gear_part_indices() -> Array:
	var r: Array = []
	for i in parts.size():
		if not parts[i].get("broken", false) and float(parts[i]["gear_cap"]) > 0.0:
			r.append(i)
	return r


# Bruch zum nächsten _process vormerken (Node-Umbau NIE in _integrate_forces).
func _queue_break(roots: Array) -> void:
	for r in roots:
		if not _break_queue.has(r):
			_break_queue.append(r)


# Verschossene Munition vormerken: das Teil (Index in parts) verschwindet im nächsten _process.
func queue_detach(part_index: int) -> void:
	if part_index >= 0 and not _detach_queue.has(part_index):
		_detach_queue.append(part_index)


# Rückstoß vom Waffenfeuer (Impuls, Weltkoordinaten). Wird im nächsten Physikschritt angewandt.
func add_recoil(impulse: Vector3) -> void:
	if impulse.is_finite():
		_recoil += impulse


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
	# Rauchfahne: die abgerissenen Teile qualmen im Fallen
	var smoke := _fx_make(18, 0.9, 0.0, 2.0, Color(0.26, 0.26, 0.29, 0.7), 0.3, false, 1.5, Vector3(0, 1, 0))
	debris.add_child(smoke)
	smoke.emitting = true
	var tmr := get_tree().create_timer(9.0)
	tmr.timeout.connect(debris.queue_free)
	recompute_aero()


# Zerschellen: ALLE Teile fliegen als einzelne Trümmer radial auseinander (Spielzeug zerlegt
# sich) + bunte, übertriebene "Toy"-Explosion. Danach bleibt nur ein leerer, eingefrorener
# Körper am Crash-Ort (Kamera schaut zu); Reset (Enter) baut alles neu.
func _explode() -> void:
	if exploded:
		return
	exploded = true
	shake_request = 1.4   # heftiger Kamera-Stoß bei der Explosion
	var par := get_parent()
	var com_world: Vector3 = global_transform * center_of_mass
	var base_vel := linear_velocity
	if par != null:
		for i in parts.size():
			if parts[i].get("broken", false):
				continue
			var cs = parts[i]["cs"]
			if is_instance_valid(cs):
				cs.disabled = true
			var vis = parts[i]["vis"]
			parts[i]["broken"] = true
			if not is_instance_valid(vis):
				continue
			var deb := RigidBody3D.new()
			deb.add_to_group("debris")
			deb.collision_layer = 8
			deb.collision_mask = 1
			deb.angular_damp = 0.12
			par.add_child(deb)
			deb.global_transform = vis.global_transform
			vis.reparent(deb, true)
			var outward: Vector3 = deb.global_position - com_world
			if outward.length() < 0.2:
				outward = Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1))
			outward = outward.normalized()
			# kräftig radial wegsprengen + nach oben + Zufall -> Teile stieben auseinander
			deb.linear_velocity = base_vel * 0.35 + outward * randf_range(9.0, 19.0) + Vector3.UP * randf_range(4.0, 11.0)
			deb.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
			deb.mass = maxf(float(parts[i]["mass"]) * 0.5, 4.0)
			var box := BoxShape3D.new()
			box.size = Vector3(0.7, 0.5, 0.7)
			var dcs := CollisionShape3D.new()
			dcs.shape = box
			deb.add_child(dcs)
			var tmr := get_tree().create_timer(randf_range(7.0, 10.0))
			tmr.timeout.connect(deb.queue_free)
		_toy_explosion(com_world)
		_mushroom_cloud(com_world)
	recompute_aero()
	landing_msg = "💥 ZERSCHELLT!  (Enter = neu)"
	_land_timer = 6.0
	# Leerer Körper bleibt am Crash-Ort stehen (Kamera schaut auf die Explosion).
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true


# Bunte, übertriebene Spielzeug-Explosion: Feuerball + weißer Blitz + buntes Konfetti + Rauch.
func _toy_explosion(pos: Vector3) -> void:
	var par := get_parent()
	if par == null:
		return
	_burst(par, pos, 48, 0.7, 6.0, 26.0, Vector3(0, -6, 0), Color(1.0, 0.55, 0.12), 0.42, true, false)   # Feuerball
	_burst(par, pos, 12, 0.22, 0.0, 5.0, Vector3.ZERO, Color(1.0, 0.96, 0.85), 1.1, true, false)          # weißer Blitz
	for c in [Color(1, 0.2, 0.25), Color(0.2, 0.6, 1.0), Color(1, 0.9, 0.2), Color(0.3, 1, 0.45), Color(0.9, 0.4, 1.0)]:
		_burst(par, pos, 14, 1.5, 9.0, 32.0, Vector3(0, -13, 0), c, 0.16, false, true)                    # buntes Konfetti
	_burst(par, pos, 18, 1.3, 2.0, 9.0, Vector3(0, 3.5, 0), Color(0.55, 0.55, 0.6), 0.45, false, false)   # Rauchpuffs


func _burst(par: Node, pos: Vector3, amount: int, life: float, vmin: float, vmax: float,
		grav: Vector3, color: Color, size: float, emissive: bool, cube: bool) -> void:
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.96
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = grav
	var mesh: Mesh
	if cube:
		var bm := BoxMesh.new()
		bm.size = Vector3(size, size, size)
		mesh = bm
	else:
		var sm := SphereMesh.new()
		sm.radius = size
		sm.height = size * 2.0
		mesh = sm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = color
	if emissive:
		mm.emission_enabled = true
		mm.emission = color
		mm.emission_energy_multiplier = 2.6
	mesh.material = mm
	p.mesh = mesh
	par.add_child(p)
	p.global_position = pos
	var tmr := get_tree().create_timer(life + 0.6)
	tmr.timeout.connect(p.queue_free)


# Wolken-Mesh mit eigenem (tweenbarem) Material. Rauch = alpha-geblendet & beleuchtet,
# Feuer = additiv leuchtend.
func _cloud_mesh(parent: Node3D, mesh: Mesh, color: Color, emissive: bool, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.6
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = m
	parent.add_child(mi)
	return mi


# Cooler Atompilz: Stiel wächst hoch, feuriger Kern steigt auf & wird zur ausblühenden Kappe,
# Roll-Ring um die Kappe + Boden-Schockwelle. Alles per Tween animiert, räumt sich selbst auf.
func _mushroom_cloud(pos: Vector3) -> void:
	var par := get_parent()
	if par == null:
		return
	var root := Node3D.new()
	par.add_child(root)
	root.global_position = Vector3(pos.x, maxf(pos.y, 0.5), pos.z)
	var smoke := Color(0.66, 0.63, 0.6, 0.9)
	var dark := Color(0.4, 0.38, 0.37, 0.92)
	var fire := Color(1.0, 0.55, 0.16, 1.0)
	var tw := root.create_tween()
	tw.set_parallel(true)

	# Stiel — Pivot an der Basis, wächst nach oben
	var stem_pivot := Node3D.new()
	root.add_child(stem_pivot)
	var stem_cyl := CylinderMesh.new()
	stem_cyl.top_radius = 2.4
	stem_cyl.bottom_radius = 3.4
	stem_cyl.height = 20.0
	var stem := _cloud_mesh(stem_pivot, stem_cyl, dark, false, Vector3(0, 10.0, 0))
	stem_pivot.scale = Vector3(0.6, 0.05, 0.6)
	tw.tween_property(stem_pivot, "scale", Vector3(1, 1, 1), 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(stem.material_override, "albedo_color:a", 0.0, 1.6).set_delay(3.0)

	# Feuriger Kern — steigt auf und bläht sich (wird zur Kappe), dann erlischt er
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 4.0
	core_mesh.height = 8.0
	var core := _cloud_mesh(root, core_mesh, fire, true, Vector3(0, 3, 0))
	tw.tween_property(core, "position", Vector3(0, 22, 0), 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(core, "scale", Vector3(2.4, 1.7, 2.4), 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(core.material_override, "emission_energy_multiplier", 0.0, 1.3).set_delay(0.5)
	tw.tween_property(core.material_override, "albedo_color:a", 0.0, 1.0).set_delay(0.9)

	# Kappe — abgeflachte Kugel, bildet sich oben und blüht weit aus
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 5.0
	cap_mesh.height = 7.0
	var cap := _cloud_mesh(root, cap_mesh, smoke, false, Vector3(0, 18, 0))
	cap.scale = Vector3(0.3, 0.3, 0.3)
	tw.tween_property(cap, "scale", Vector3(3.4, 2.1, 3.4), 1.6).set_delay(0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(cap, "position", Vector3(0, 25, 0), 1.6).set_delay(0.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(cap.material_override, "albedo_color:a", 0.0, 1.6).set_delay(3.0)

	# Roll-Ring um die Kappe (Torus liegt flach um die senkrechte Achse)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 4.5
	ring_mesh.outer_radius = 8.0
	var ring := _cloud_mesh(root, ring_mesh, smoke, false, Vector3(0, 24, 0))
	ring.scale = Vector3(0.4, 0.4, 0.4)
	tw.tween_property(ring, "scale", Vector3(2.9, 1.3, 2.9), 1.8).set_delay(0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring.material_override, "albedo_color:a", 0.0, 1.4).set_delay(2.6)

	# Boden-Schockwelle — flacher Ring, schnell nach außen + aus
	var sw_mesh := TorusMesh.new()
	sw_mesh.inner_radius = 1.2
	sw_mesh.outer_radius = 2.2
	var sw := _cloud_mesh(root, sw_mesh, Color(1.0, 0.82, 0.4, 1.0), true, Vector3(0, 0.6, 0))
	tw.tween_property(sw, "scale", Vector3(9.0, 1.0, 9.0), 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(sw.material_override, "albedo_color:a", 0.0, 0.7)

	var tmr := get_tree().create_timer(5.2)
	tmr.timeout.connect(root.queue_free)


# Allgemeiner Partikel-Emitter (Welt-Spur). dir = Emissionsrichtung im Emitter-Frame.
func _fx_make(amount: int, life: float, vmin: float, vmax: float, color: Color, size: float,
		emissive: bool, grav_y: float, dir: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false      # Partikel bleiben in der Welt -> trailen hinter dem Flieger
	p.direction = dir
	p.spread = 14.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, grav_y, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	var mm := StandardMaterial3D.new()
	mm.albedo_color = color
	if emissive:
		mm.emission_enabled = true
		mm.emission = color
		mm.emission_energy_multiplier = 3.0
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mm
	p.mesh = mesh
	return p


# Weicher Rauch: kleine Kugeln, die über die Lebenszeit AUFQUELLEN (Curve) und AUSFADEN
# (Alpha-Gradient) -> sieht aus wie echter Qualm statt fetter Blasen.
func _make_smoke(amount: int, life: float, vmin: float, vmax: float, color: Color,
		size: float, grow: float, grav_y: float, dir: Vector3, spread: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false       # in der Welt simulieren -> trailt hinter dem Flieger
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, grav_y, 0)
	p.damping_min = 0.8
	p.damping_max = 1.8
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sc := Curve.new()             # klein starten, aufquellen
	sc.add_point(Vector2(0.0, 0.3))
	sc.add_point(Vector2(1.0, grow))
	p.scale_amount_curve = sc
	var g := Gradient.new()           # über die Lebenszeit ausfaden
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var mm := StandardMaterial3D.new()
	mm.albedo_color = color
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.vertex_color_use_as_albedo = true
	mesh.material = mm
	p.mesh = mesh
	return p


# Additiver Flammen-Shader: Farbverlauf weiß→blau→orange→rot entlang der Länge (UV.y),
# Mach-Diamanten im vorderen Bereich, Flackern. Wird von Kern- und Fahnenkegel geteilt.
func _flame_shader() -> Shader:
	if _flame_shader_cache != null:
		return _flame_shader_cache
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
uniform float intensity = 0.0;
uniform float t_time = 0.0;
uniform float diamonds = 0.0;
uniform vec3 col_near : source_color = vec3(0.55, 0.78, 1.0);
uniform vec3 col_mid : source_color = vec3(1.0, 0.6, 0.2);
uniform vec3 col_far : source_color = vec3(0.9, 0.14, 0.03);
void fragment() {
	float t = UV.y;                       // 0 = Düse, 1 = Spitze
	vec3 col;
	if (t < 0.16) col = mix(vec3(1.0, 0.96, 0.9), col_near, t / 0.16);
	else if (t < 0.5) col = mix(col_near, col_mid, (t - 0.16) / 0.34);
	else col = mix(col_mid, col_far, (t - 0.5) / 0.5);
	float dia = 0.0;
	if (diamonds > 0.001) {               // Mach-Diamanten: helle Bänder vorne
		float band = sin(t * 40.0 - t_time * 7.0);
		dia = smoothstep(0.55, 1.0, band) * diamonds * (1.0 - smoothstep(0.0, 0.45, t)) * 0.8;
	}
	float flick = 0.8 + 0.2 * sin(t_time * 45.0 + t * 24.0);
	float a = pow(1.0 - t, 1.25);
	ALBEDO = (col * flick + vec3(dia)) * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
	_flame_shader_cache = sh
	return sh


# Tropfenförmiger Flammen-Kegel (Länge 1 entlang +Z), UV.y = Längsparameter 0..1.
func _flame_mesh(base_r: float) -> ArrayMesh:
	var key := snappedf(base_r, 0.001)
	if _flame_mesh_cache.has(key):
		return _flame_mesh_cache[key]
	var rings := 18
	var seg := 16
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in range(rings):
		var t := float(i) / float(rings)
		var r: float = base_r * pow(1.0 - t, 0.7)
		for j in range(seg):
			var a := TAU * float(j) / float(seg)
			verts.append(Vector3(cos(a) * r, sin(a) * r, t))
			uvs.append(Vector2(float(j) / float(seg), t))
	var tip_i := verts.size()
	verts.append(Vector3(0, 0, 1.0))
	uvs.append(Vector2(0.5, 1.0))
	var idx := PackedInt32Array()
	for i in range(rings - 1):
		for j in range(seg):
			var j2 := (j + 1) % seg
			var a0 := i * seg + j
			var a1 := i * seg + j2
			var b0 := (i + 1) * seg + j
			var b1 := (i + 1) * seg + j2
			idx.append(a0); idx.append(b0); idx.append(a1)
			idx.append(a1); idx.append(b0); idx.append(b1)
	var li := (rings - 1) * seg
	for j in range(seg):
		var j2 := (j + 1) % seg
		idx.append(li + j); idx.append(tip_i); idx.append(li + j2)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_flame_mesh_cache[key] = m
	return m


func _flame_cone(base_r: float, near: Color, mid: Color, far: Color) -> Array:
	var mi := MeshInstance3D.new()
	mi.mesh = _flame_mesh(base_r)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _flame_shader()
	mat.set_shader_parameter("col_near", near)
	mat.set_shader_parameter("col_mid", mid)
	mat.set_shader_parameter("col_far", far)
	mat.set_shader_parameter("intensity", 0.0)
	mi.material_override = mat
	return [mi, mat]


# Ein kompletter Nachbrenner (Fahne + Kern + Funken + Licht), Wurzel zeigt +Z (Heck).
func _build_afterburner() -> Dictionary:
	var root := Node3D.new()
	var plume_pair := _flame_cone(0.34, Color(0.7, 0.85, 1.0), Color(1.0, 0.55, 0.16), Color(0.85, 0.12, 0.02))
	var core_pair := _flame_cone(0.19, Color(0.85, 0.92, 1.0), Color(0.7, 0.85, 1.0), Color(1.0, 0.55, 0.16))
	var plume: MeshInstance3D = plume_pair[0]
	var core: MeshInstance3D = core_pair[0]
	root.add_child(plume)
	root.add_child(core)
	var sparks := _fx_make(26, 0.35, 6.0, 16.0, Color(1.0, 0.72, 0.32), 0.055, true, 0.0, Vector3(0, 0, 1))
	sparks.spread = 5.0
	sparks.emitting = false
	root.add_child(sparks)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 0.0
	light.omni_range = 3.0
	light.shadow_enabled = false
	light.position = Vector3(0, 0, 0.4)
	root.add_child(light)
	return {
		"root": root, "plume": plume, "core": core, "light": light, "sparks": sparks,
		"plume_mat": plume_pair[1], "core_mat": core_pair[1],
	}


# Alle Auspuff-Stutzen-Knoten (exhaust_R0..L5) im Triebwerks-Visual finden.
func _find_exhaust_nodes(n: Node) -> Array:
	var out: Array = []
	for ch in n.get_children():
		if ch is Node3D and String(ch.name).to_lower().begins_with("exhaust"):
			out.append(ch)
		out.append_array(_find_exhaust_nodes(ch))
	return out


# FX-Emitter neu aufbauen (nach Bau/Bruch): Nachbrenner an Jet-Düsen, Wirbelschleppen an
# Hauptflügelspitzen. Ein-/Ausschalten passiert je Frame im _process.
func _rebuild_fx() -> void:
	for d in _afterburners:
		var r = d.get("root") if d is Dictionary else d
		if is_instance_valid(r):
			r.queue_free()
	for n in _vapor:
		if is_instance_valid(n):
			n.queue_free()
	if is_instance_valid(_damage_smoke):
		_damage_smoke.queue_free()
	_damage_smoke = null
	for fxd in _exhaust_fx:
		for k in ["startup", "black"]:
			var n = fxd.get(k)
			if n != null and is_instance_valid(n):
				n.queue_free()
	_exhaust_fx.clear()
	_afterburners.clear()
	_vapor.clear()
	# Schadensrauch: hat das Flugzeug Teile verloren (aber lebt noch) -> qualmt aus der Wunde
	var wound := Vector3.ZERO
	var nbroken := 0
	for pi in parts:
		if pi.get("broken", false):
			wound += pi["pos"]
			nbroken += 1
	if nbroken > 0 and not exploded:
		var ds := _fx_make(22, 1.1, 0.0, 2.5, Color(0.2, 0.2, 0.22, 0.75), 0.34, false, 1.2, Vector3(0, 1, 0))
		add_child(ds)
		ds.position = wound / float(nbroken)
		ds.emitting = true
		_damage_smoke = ds
	for e in engines:
		if not e.get("jet", false):
			continue
		# Flamme an die Triebwerksgröße koppeln: radiale Skalierung = Düsendurchmesser,
		# Längen-Skalierung schiebt die Düse (und damit den Flammenansatz) weiter nach hinten.
		var sc: Vector3 = e.get("scale", Vector3.ONE)
		# Pro-Teil Flammen-Größe (kleine Triebwerke wie das Hilfstriebwerk haben eine kleinere Flamme)
		var fscale: float = float(PartCatalog.get_part(e.get("id", "")).get("flame_scale", 1.0))
		var rfac: float = maxf((sc.x + sc.y) * 0.5, 0.05) * fscale
		var lfac: float = maxf(sc.z, 0.05)
		var d := _build_afterburner()
		d["rfac"] = rfac
		var root: Node3D = d["root"]
		add_child(root)
		# Flamme MIT dem Triebwerk ausgerichtet: +Z des Triebwerks = Heck. Dreht man die Engine,
		# dreht die Flamme (samt Funken/Licht, da Kinder von root) mit und schießt aus der Düse.
		var eb: Basis = e.get("basis", Basis())
		root.transform = Transform3D(eb, e["pos"] + eb.z * (1.12 * lfac * fscale))
		root.visible = false
		var sparks: CPUParticles3D = d["sparks"]
		sparks.scale = Vector3(rfac, rfac, rfac)
		var light: OmniLight3D = d["light"]
		light.position = Vector3(0, 0, 0.4 * rfac)
		_afterburners.append(d)
	# Auspuff-Rauch NUR für die Spitfire-Engine (prop_engine_big), direkt AUS DEN EXHAUST-Stutzen.
	# Viel Qualm (hohe Anzahl), aber bleibt NAH (kurze Lebenszeit + starke Dämpfung, kein weiter Trail).
	for pi in parts:
		if pi.get("broken", false) or String(pi.get("id", "")) != "prop_engine_big":
			continue
		var evis = pi.get("vis")
		if evis == null or not is_instance_valid(evis):
			continue
		# Welt-Positionen der Auspuff-Stutzen (exhaust_*-Knoten) -> Emissionspunkte (körperlokal)
		var pts := PackedVector3Array()
		for ch in _find_exhaust_nodes(evis):
			pts.append(to_local(ch.global_position))
		if pts.is_empty():
			pts.append(pi["pos"])
		var exf: Transform3D = pi["xform"]
		var eb := exf.basis.orthonormalized()   # Rauchrichtung mit dem Triebwerk mitdrehen
		if eb.determinant() < 0.0:
			eb.x = -eb.x
		var fx := {}
		# Startrauch: kräftiger grauer Qualmstoß aus allen Stutzen (one-shot, bleibt nah)
		var st := _make_smoke(38, 0.9, 0.15, 0.7, Color(0.58, 0.56, 0.53, 0.55), 0.05, 3.0, 0.55, eb * Vector3(0, 0.6, 0.35), 46.0)
		st.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
		st.emission_points = pts
		st.one_shot = true
		st.explosiveness = 0.5
		st.emitting = false
		st.damping_min = 2.2
		st.damping_max = 3.8
		add_child(st)
		fx["startup"] = st
		# Schwarzer Rauch: EIN SEHR STARKER, etwas längerer Rußstoß aus allen Stutzen beim
		# Wechsel normal -> Nachbrenner (one-shot). Viele Partikel + lange Lebenszeit + Emission
		# über ein größeres Zeitfenster (niedrigere explosiveness) -> dicker, länger anhaltender Qualm.
		var bk := _make_smoke(220, 2.4, 0.2, 1.0, Color(0.04, 0.04, 0.04, 0.66), 0.062, 3.9, 0.5, eb * Vector3(0, 0.6, 0.35), 48.0)
		bk.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
		bk.emission_points = pts
		bk.one_shot = true
		bk.explosiveness = 0.55
		bk.emitting = false
		bk.damping_min = 2.0
		bk.damping_max = 3.8
		add_child(bk)
		fx["black"] = bk
		_exhaust_fx.append(fx)
	for pi in parts:
		if pi.get("broken", false) or not pi["is_wing"] or String(pi["control"]) != "":
			continue
		var xf: Transform3D = pi["xform"]
		var tip: Vector3 = pi["pos"] + xf.basis.x.normalized() * float(pi.get("span", 2.0))
		var v := _fx_make(14, 0.5, 0.0, 1.2, Color(0.95, 0.97, 1.0, 0.5), 0.11, false, 0.0, Vector3(0, 0, 1))
		add_child(v)
		v.position = tip
		v.emitting = false
		_vapor.append(v)


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
	if exploded:
		return
	var descent := maxf(0.0, -_last_vy)         # vertikale Sinkrate (für die Landenote)
	if descent > 0.6:
		_dust_pending = descent                 # Staub-Burst (Spawn deferred nach _process)
	var n := state.get_contact_count()
	var break_set := {}
	var only_gear := true
	var worst := 0.0
	var core_fail := false
	for i in n:
		var nrm := state.get_contact_local_normal(i)
		var closing := maxf(0.0, -_last_vel.dot(nrm))   # Tempo IN die getroffene Fläche
		worst = maxf(worst, closing)
		var idx := _nearest_part_index(state.transform, state.get_contact_local_position(i))
		if idx < 0:
			continue
		# STRUKTURWERT entscheidet: hält das getroffene Teil dem Stoß stand?
		var pstr: float = float(parts[idx].get("strength", 14.0))
		if closing <= pstr:
			continue                            # Teil hält -> kein Bruch
		if bool(parts[idx].get("is_root", false)):
			core_fail = true                    # Cockpit/Kern weggebrochen -> Totalverlust
		else:
			break_set[idx] = true               # Teil bricht ab (schluckt den Stoß)
			if float(parts[idx].get("gear_cap", 0.0)) <= 0.0:
				only_gear = false
	# Totalschaden: Kern versagt ODER extrem harter Aufprall (über jede Struktur hinaus).
	if core_fail or worst > EXPLODE_SPEED:
		_explode_pending = true
		landing_msg = "💥 ZERSCHELLT!"
		_land_timer = 5.0
		return
	if not break_set.is_empty():
		_queue_break(break_set.keys())
		# Aufprall ABSORBIERT: das/die gebrochene(n) Teil(e) schlucken den Stoß -> der Rest
		# fliegt mit fast unveränderter Geschwindigkeit weiter (kaum Force aufs restliche Flugzeug),
		# nur der Einschlag in die Fläche (senkrechte Komponente) wird abgefangen.
		var keep := _last_vel
		keep.y = maxf(keep.y, -1.5)
		state.linear_velocity = keep * 0.92
		landing_msg = "💥 Räder abgerissen!" if only_gear else "💥 Teil abgerissen!"
		_land_timer = 4.0
		shake_request = maxf(shake_request, 0.7)
		return
	# nichts abgerissen -> reine Landenoten
	if descent > HARD_LAND:
		landing_msg = "⚠ Harte Landung (%d m/s)" % int(round(descent))
		_land_timer = 3.5
		shake_request = maxf(shake_request, 0.4)
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


# Brauner Staub-Burst am Boden beim Aufsetzen (Menge ~ Sinkrate). Nur aus _process rufen!
func _spawn_landing_dust(descent: float) -> void:
	var par := get_parent()
	if par == null or not is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = clampi(int(8.0 + descent * 9.0), 8, 56)
	p.lifetime = 1.1
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0 + descent * 1.2
	p.gravity = Vector3(0, -3.5, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.4
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var mesh := SphereMesh.new()
	mesh.radius = 0.30
	mesh.height = 0.60
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.62, 0.54, 0.42, 0.55)   # sandiger Staub, halbtransparent
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mm
	p.mesh = mesh
	par.add_child(p)
	p.global_position = Vector3(global_position.x, 0.25, global_position.z)
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free())


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
		# Reifen-Überlast (zu schwer fürs Fahrwerk) -> Reifen reißen beim Flugstart AB (Trümmer),
		# nicht nur einknicken. Abriss erst im _process (Node-Umbau), via _break_queue.
		_collapsed = false
		_queue_break(_gear_part_indices())
		landing_msg = "💥 Fahrwerk überlastet — Reifen abgerissen!"
		_land_timer = 4.0
	else:
		_collapsed = false
		for g in gear_items:
			var cs = g["cs"]
			if is_instance_valid(cs):
				cs.disabled = false
			var vis = g["vis"]
			if is_instance_valid(vis):
				vis.transform = g["base"]
			var leg = g["leg"]
			if leg != null and is_instance_valid(leg):
				leg.transform = g["leg_rest"]
			var door = g["door"]
			if door != null and is_instance_valid(door):
				door.transform = g["door_rest"]
		_update_gear_status()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not state.linear_velocity.is_finite():
		state.linear_velocity = Vector3.ZERO
	if not state.angular_velocity.is_finite():
		state.angular_velocity = Vector3.ZERO

	# Landeklappen fahren langsam/realistisch aus (Motorgeschwindigkeit). _flap_vis = tatsächlich
	# ausgefahrene Stellung -> Auftrieb/Widerstand UND Optik bauen sich damit allmählich auf.
	_flap_vis = move_toward(_flap_vis, flaps, state.step * FLAP_RATE)

	var xf := state.transform
	var v_lin := state.linear_velocity
	var v_ang := state.angular_velocity

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
	# Turbine: Drossel 0..100 % = normaler Schub. Nachbrenner-Zone 100..110 %:
	# nur Jets, on top des vollen Turbinenschubs (+AB_BOOST). Propeller bleiben bei 100 %.
	# Der Nachbrenner zündet nicht schlagartig — _ab_spool fährt zeitlich hoch/runter.
	var base_thr := clampf(throttle, 0.0, 1.0)
	# Triebwerks-Trägheit: tatsächliche Leistung eilt der Drossel nach (Turbinen-Hochlauf).
	var er := SPOOL_UP if base_thr > _engine_spool else SPOOL_DN
	_engine_spool += (base_thr - _engine_spool) * clampf(er * state.step, 0.0, 1.0)
	# Nachbrenner spult separat (zündet erst >100 %).
	var ab_target := clampf((throttle - 1.0) / 0.10, 0.0, 1.0)   # 0 bei 100 %, 1 bei 110 %
	var sr := AB_SPOOL_UP if ab_target > _ab_spool else AB_SPOOL_DN
	_ab_spool += (ab_target - _ab_spool) * clampf(sr * state.step, 0.0, 1.0)
	# Jedes Triebwerk schiebt in SEINE Blickrichtung (zeigt es nach oben -> Schub nach oben).
	# Zentral durch den COM angewandt (kein Hebel -> stabil, kein "Pendel-Raketen"-Effekt).
	for e in engines:
		var ld: Vector3 = e.get("dir", Vector3(0, 0, -1))
		var edir := (xf.basis * ld).normalized()
		var t: float = float(e["thrust"])
		if not e.get("jet", false):
			var fe := v_lin.dot(edir)      # Propellerschub fällt mit dem Tempo ENTLANG der Schubrichtung
			t *= clampf(1.0 - fe / PROP_VMAX, 0.0, 1.0) * _engine_spool
		else:
			t *= (_engine_spool + AB_BOOST * _ab_spool)
		var force := edir * t
		tf += force
		# Off-Center-Schub erzeugt ein Drehmoment um den COM: ein hinten montiertes, nach
		# oben zeigendes Triebwerk hebt das Heck -> die Nase kippt nach unten (vorne über).
		# Sitzt der Schub auf der Achse durch den COM (normale Flieger), ist r×F ≈ 0.
		var epos: Vector3 = e.get("pos", Vector3.ZERO)
		var r := xf.basis * (epos - center_of_mass)
		tt += r.cross(force)
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
		cl += _flap_vis * FLAP_LIFT
		var cd := CD0 + cl * cl / (PI * eff_ar * OSWALD) + sigma * (1.0 - cos(2.0 * aoa)) * 0.5 + _flap_vis * FLAP_DRAG
		# Abhebe-Gate: Auftrieb bei niedrigem Tempo dämpfen (längere Rollstrecke), ab
		# der plane-spezifischen Abhebegeschwindigkeit voll -> in der Luft leicht/arcadig.
		# LANDEKLAPPEN senken die Gate-Schwelle (-25 % bei voll): sonst fräße das Gate im
		# langsamen Landeanflug genau den Auftrieb weg, den die Klappen liefern sollen.
		var gate_v := takeoff_v * (1.0 - _flap_vis * 0.25)
		var lift_gate := lerpf(LIFT_LO, 1.0, smoothstep(gate_v * LIFT_GATE_LO, gate_v * LIFT_GATE_HI, sp))
		var lift_mag := q * wing_area * cl * lift_gate
		# (Der frühere Force-Clamp aufs Lift ist raus: Limitierung passiert jetzt auf der
		# KOMMANDO-Seite im Instructor (AoA-/G-Limiter auf Messwerte) — die Physik bleibt
		# unverfälscht. Backstop: 0.12-s-Überlast-Fenster + Flügelbruch darunter.)
		# Strukturelle Überlast: zu viel Auftrieb (zu hohe G) -> Flügel brechen.
		# NUR bei ANHALTENDER Überlast (>0.12 s): Einzel-Tick-Spitzen (Regler-Transienten,
		# numerisches Rauschen bei Highspeed) reißen keine Flügel mehr ab — echtes
		# Dauer-Überziehen über dem Limit weiterhin schon.
		if not arcade and barrel_roll == 0 and wing_capacity > 0.0 and absf(lift_mag) > wing_capacity:
			_overload_t += state.step
		else:
			_overload_t = maxf(_overload_t - state.step * 2.0, 0.0)
		if not wings_broken and _overload_t > 0.12:
			wings_broken = true
			_queue_break(_wing_root_indices())   # Abtrennen erst im _process (nicht im Physik-Schritt)
			landing_msg = "💥 FLÜGEL ÜBERLASTET — abgerissen!"
			_land_timer = 4.0
			shake_request = maxf(shake_request, 0.7)
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
		aoa_signed = aoa
		load_factor = lift_mag / maxf(mass * 9.81, 1.0)
		stall = absf(aoa) > STALL_A
		# STALL-BUFFET: kurz VOR dem Abriss schüttelt die Zelle spürbar (ansteigend) ->
		# man FÜHLT die Grenze, bevor das STALL-Banner kommt. Physischer Jitter (Nase
		# zittert leicht) + dezentes Kamera-Zittern; Arcade/Fass-Roll ausgenommen.
		var buf := smoothstep(STALL_A * 0.72, STALL_A, absf(aoa)) * clampf(sp / 30.0, 0.0, 1.0)
		if buf > 0.02 and not arcade and barrel_roll == 0:
			tt += xf.basis * (Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * (buf * mass * 0.6))
			shake_request = maxf(shake_request, buf * 0.4 * state.step)
		# STALL-RECOVERY: im Abriss drückt ein sanftes Nase-runter-Moment (massebasiert,
		# wirkt auch bei wenig Staudruck) die Nase zur Anströmung -> Tempo baut sich auf,
		# Überziehen wird ERHOLBAR statt Kontrollverlust. Voller Zug am Höhenruder
		# (absichtliches Überziehen) hebt die Hilfe auf; Arcade/Fass-Rolle ausgenommen.
		if stall and not arcade and barrel_roll == 0:
			var rec := (1.0 - clampf(in_pitch, 0.0, 1.0)) * sigma
			tt += xf.basis.x * (-signf(aoa) * mass * STALL_RECOVER * rec)
	else:
		aoa_deg = 0.0
		aoa_signed = 0.0
		load_factor = 0.0
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

	# --- Steuerung: Arcade (kinematisch) ODER Steuerflächen-Torque (inkl. Maus-Flug) -------
	# Maus-Flug = PHYSISCHE Steuerung (Trägheit/Ruder/Momente = realistisch); die
	# Manöver-PLANUNG (Stopp-Distanz-Profile, G-Limits) passiert im FlightController.
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
		# AUTO-RUDERKOORDINATION (nur Tastatur-Modus): bei Querlage automatisch etwas
		# Seitenruder in die Kurve -> Kurven ziehen sauber/koordiniert statt zu schmieren,
		# ohne Q/E-Gefummel. Vorzeichen: Bank links (atan2>0, wie in_roll>0) -> Gier links.
		# Bewusst OHNE inv (Aerodynamik-Hilfe, keine Spieler-Eingabe).
		if not mouse_fly and barrel_roll == 0:
			var cbank := atan2(xf.basis.x.y, xf.basis.y.y)
			var coord := clampf(cbank * COORD_BANK, -0.45, 0.45)
			tt += xf.basis.y * (coord * (CTRL_YAW + CTRL_YAW_A * yaw_area) * qfac * mass)
		# Aerodynamische Drehdämpfung (gegen Schwingen) — wächst mit Tempo.
		# Im Fass-Roll die ROLL-Dämpfung aus (sonst kommt die Rolle nicht auf Touren);
		# Nick/Gier bleiben gedämpft. Assist verstärkt nur Nick/Gier.
		var dfac := (0.35 + qfac) * mass
		var apq := 1.6 if assist else 1.0
		var roll_d: float = 0.0 if barrel_roll != 0 else wb.z * DAMP_ROLL
		tt += xf.basis * (-Vector3(wb.x * DAMP_PITCH * apq, wb.y * DAMP_YAW * apq, roll_d) * dfac)
		# KEIN Auto-Ausnivellieren der Querlage mehr (Wunsch): mit A/D gesetzte Bank
		# bleibt stehen, das Flugzeug dreht nicht von selbst zurück auf gerade.
		# (Assist behält Nick-/Gier-Dämpfung; die Roll-DREHRATE wird weiter gedämpft,
		# der Roll-WINKEL aber nicht mehr zurückgestellt.)

	# --- Sicherheit & Anwenden ---------------------------------------------
	if not tf.is_finite():
		tf = Vector3.ZERO
	if not tt.is_finite():
		tt = Vector3.ZERO
	tf = tf.limit_length(mass * 130.0)   # nur NaN-/Runaway-Sicherung, klippt normale Aero nicht mehr
	tt = tt.limit_length(mass * 90.0)
	state.apply_central_force(tf)
	# Waffen-Rückstoß als sofortiger Impuls (entgegen der Mündungsrichtung).
	if _recoil != Vector3.ZERO:
		state.apply_central_impulse(_recoil)
		_recoil = Vector3.ZERO
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
# Pursuit-Ziel-Lage: Nase (-Z) auf aim_world, in die Kurve gebankt (+ gehaltener
# A/D-Bank-Offset). Referenz-Up so wählen, dass es NIE (fast) parallel zu fwd ist ->
# sonst ist fwd×up0 ≈ 0 und .normalized() liefert NaN (Basis zerlegt).
func _pursuit_basis(cur_basis: Basis) -> Basis:
	var fwd := aim_world.normalized()
	var e := cur_basis.transposed() * fwd
	var bank := clampf(atan2(e.x, -e.z) * 0.9 + mouse_bank_offset, -1.25, 1.25)
	var up0 := Vector3.UP
	if absf(fwd.dot(up0)) > 0.985:
		up0 = cur_basis.y
		if absf(fwd.dot(up0)) > 0.985:
			up0 = cur_basis.x       # Flieger-Up ebenfalls parallel -> Seitenachse
	var right0 := fwd.cross(up0)
	if right0.length() < 0.001:      # Sicherung: garantiert nicht-degeneriert
		right0 = fwd.cross(Vector3.RIGHT)
		if right0.length() < 0.001:
			right0 = fwd.cross(Vector3.BACK)
	right0 = right0.normalized()
	var up1 := right0.cross(fwd).normalized()
	return Basis(right0.rotated(fwd, bank), up1.rotated(fwd, bank), -fwd).orthonormalized()


func _arcade_steer(state: PhysicsDirectBodyState3D) -> void:
	var cur_basis := state.transform.basis
	if aim_world.length() < 0.01:
		return
	var tb := _pursuit_basis(cur_basis)
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


