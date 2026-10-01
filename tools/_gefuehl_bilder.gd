## BILDER VOM FLUGGEFUEHL: echte Verfolgerkamera im Flug (Flugzeug fliegt, Physik laeuft),
## HUD-Tafeln aus, der Flug-Blick (Blendung, G, Tempo) bleibt an. Fuer die Abnahme von
## Farbabstimmung, Glow, Wolken und shaders/flug_blick.gdshader.
##
##   HOME=<test-home> Godot --path . --script res://tools/_gefuehl_bilder.gd [-- name ...]
## Bilder: user://gefuehl_<name>.png. Ohne Argumente alle Szenen.
extends SceneTree

# name, Position, Blickrichtung (waagerecht), Tempo m/s, erzwungene G (-99 = echt)
const SZENEN := [
	["sonne", Vector3(7400, 140, 26600), Vector2(-0.766, 0.643), 140.0, -99.0],
	["berge", Vector3(-2600, 950, -4500), Vector2(0.10, -1.0), 150.0, -99.0],
	["wolken", Vector3(1500, 1050, -2500), Vector2(1.0, 0.25), 150.0, -99.0],
	["kueste", Vector3(9000, 70, 24500), Vector2(-1.0, -0.15), 230.0, -99.0],
	["g_last", Vector3(-2600, 950, -4500), Vector2(0.10, -1.0), 150.0, 7.8],
	["gewitter", Vector3(24500, 1400, 2500), Vector2(1.0, 0.0), 150.0, -99.0],
	["nebelmeer", Vector3(-32500, 440, 9500), Vector2(1.0, 0.05), 150.0, -99.0],
	["gewitter_nah", Vector3(29200, 1200, 600), Vector2(0.75, 0.66), 150.0, -99.0],
	["fetzen", Vector3(-32000, 368, 9500), Vector2(1.0, 0.05), 170.0, -99.0],
	["heimat_ost", Vector3(74, 410, -1933), Vector2(0.747, -0.664), 140.0, -99.0],
	["tief_wald", Vector3(-3500, 70, 6000), Vector2(-0.6, 0.8), 120.0, -99.0],
	# Wald aus der ueblichen Tiefflughoehe (30 m ueber den Wipfeln), gegen die Sonne und mit
	# der Sonne im Ruecken — "tief_wald" fliegt auf Wipfelhoehe und steckt je nach Lauf mit
	# der Kamera in einer Krone.
	["wald_gegen", Vector3(-3500, 105, 6000), Vector2(-0.6, 0.8), 120.0, -99.0],
	["wald_sonne", Vector3(-4400, 105, 7200), Vector2(0.6, -0.8), 120.0, -99.0],
	["mittel", Vector3(-6000, 700, 3000), Vector2(-0.7, 0.7), 150.0, -99.0],
	["reise", Vector3(2000, 1800, 8000), Vector2(0.2, 1.0), 180.0, -99.0],
	["schlucht_flug", Vector3(-13686, 70, 11879), Vector2(0.2, 1.0), 120.0, -99.0],
	["blitz", Vector3(27800, 420, 2600), Vector2(1.0, 0.0), 140.0, -99.0],
	["im_sturm", Vector3(30300, 1700, 2500), Vector2(1.0, 0.0), 150.0, -99.0],
	["hoch", Vector3(0, 5200, 3000), Vector2(0.3, -1.0), 180.0, -99.0],
]

var m: Node
var f := 0
var i := 0
var phase := 0       # 0 setzen, 1 auf Gelaende warten, 2 einschwingen
var t := 0
var wahl: Array = []
var alt := OS.get_environment("GEFUEHL_ALT") != ""   # Vergleich: ohne LUT, Glow, Blick


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for s in SZENEN:
		if a.is_empty() or a.has(String(s[0])):
			wahl.append(s)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		get_root().add_child(m)
		return false
	if f == 30:
		m._set_mode(1)
		if alt:
			var env: Environment = m.get("env_sky")
			env.glow_enabled = false
			env.adjustment_color_correction = null
			(m.get("_blick") as Control).visible = false
		if OS.get_environment("GEFUEHL_OHNE_GLOW") != "":
			(m.get("env_sky") as Environment).glow_enabled = false
		return false
	if f < 60:
		return false
	if i >= wahl.size():
		quit()
		return true
	var s: Array = wahl[i]
	t += 1
	match phase:
		0:
			_setze(s)
			phase = 1
			t = 0
		1:
			var ac = m.flight_ctrl.aircraft
			var bereit: bool = m.call("fern_bereit", ac.global_position) \
				and (m.terrain.get("_pending") as Dictionary).is_empty() \
				and (m.terrain.get("_flora_warteschlange") as Array).is_empty()
			if bereit or t > 6000:
				_setze(s, true)    # nach dem Warten frisch aufsetzen und losfliegen lassen
				phase = 2
				t = 0
		2:
			# Gewitter: kurz vor der Aufnahme einen Blitz ausloesen (sonst Zufall)
			if t == 146 and String(s[0]).begins_with("blitz"):
				m.set("blitz_test", true)
				m.set("_blitz_naechster", 0.0)
			if t == 148:
				# Eingrenzen: GEFUEHL_OHNE=fern|wasser|wolken|formationen
				var ohne := OS.get_environment("GEFUEHL_OHNE")
				if ohne == "fern" and m.fern_root != null:
					m.fern_root.visible = false
				elif ohne == "wasser":
					for n in m.terrain.find_children("*", "MeshInstance3D", true, false):
						var mt := (n as MeshInstance3D).material_override as ShaderMaterial
						if mt != null and mt.shader != null and mt.shader.resource_path.contains("water"):
							(n as MeshInstance3D).visible = false
				elif ohne == "wolken":
					for c in m.get("cloud_fields"):
						(c as Node3D).visible = false
				elif ohne == "formationen":
					for c in m.get("wolken_formationen"):
						(c as Node3D).visible = false
			if t == 150:
				var name := String(s[0]) + ("_alt" if alt else "") + OS.get_environment("GEFUEHL_OHNE") \
					+ ("_ohneglow" if OS.get_environment("GEFUEHL_OHNE_GLOW") != "" else "")
				get_root().get_viewport().get_texture().get_image().save_png(
					"user://gefuehl_%s.png" % name)
				print("GEFUEHL ", name)
				i += 1
				phase = 0
	return false


## frei = false: waehrend des Wartens FESTHALTEN. Sonst flog das Flugzeug beim Warten
## Kilometer weiter, die Chunks um den Startpunkt wurden abgebaut, und nach dem
## Zuruecksetzen fehlte im Bild ein Ring zwischen 2,6 und 3,8 km (ein blasses Band, das
## wie ein Fehler im Spiel aussah — im echten Flug gibt es diesen Sprung nicht).
func _setze(s: Array, frei := false) -> void:
	var fc = m.flight_ctrl
	var ac = fc.aircraft
	ac.freeze = not frei
	var r: Vector2 = (s[2] as Vector2).normalized()
	var vor := Vector3(r.x, 0.0, r.y)
	var b := Basis.looking_at(vor, Vector3.UP)
	ac.global_transform = Transform3D(b, s[1])
	ac.linear_velocity = vor * float(s[3])
	ac.angular_velocity = Vector3.ZERO
	fc.set("throttle", 0.8)
	fc.call("_reset_mouse_state")
	m.set("blick_test_g", float(s[4]))
	m.terrain.build_now_around(s[1], 2600.0)
	m.flight_hud.visible = false
