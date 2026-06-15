## PartCatalog.gd
## Zentrale Definition aller Bauteile + prozedurale Mesh-/Material-Erzeugung.
## Jede Teil-Definition ist ein Dictionary. Meshes werden im Code erzeugt,
## damit das Spiel ohne externe 3D-Assets läuft.
class_name PartCatalog
extends RefCounted

# Kategorien (Reihenfolge = Reihenfolge im Bau-Menü)
const CAT_BODY := "Rumpf"
const CAT_WING := "Tragflächen"
const CAT_CTRL := "Leitwerk & Steuerung"
const CAT_PROP := "Antrieb"
const CAT_GEAR := "Fahrwerk"
const CAT_WEAPON := "Bewaffnung"

const CATEGORY_ORDER := [CAT_BODY, CAT_WING, CAT_CTRL, CAT_PROP, CAT_GEAR, CAT_WEAPON]

# Farben (klassisches Flugzeug-Look)
const C_BODY := Color(0.80, 0.82, 0.85)
const C_COCKPIT := Color(0.30, 0.45, 0.62)
const C_WING := Color(0.84, 0.28, 0.24)
const C_CTRL := Color(0.95, 0.62, 0.15)
const C_ENGINE := Color(0.26, 0.28, 0.32)
const C_GEAR := Color(0.10, 0.10, 0.12)
const C_WEAPON := Color(0.32, 0.34, 0.38)

static var _parts: Dictionary = {}
static var _order: Array = []
static var _built := false

# ---------------------------------------------------------------------------
# Aufbau des Katalogs
# ---------------------------------------------------------------------------
static func _build() -> void:
	if _built:
		return
	_built = true
	_parts.clear()
	_order.clear()

	# --- Rumpf -------------------------------------------------------------
	_add({
		"id": "cockpit", "name": "Cockpit", "category": CAT_BODY,
		"mass": 180.0, "color": C_COCKPIT, "shape": "cockpit",
		"size": Vector3(1.3, 1.1, 2.2), "root": true,
		"desc": "Das Herz des Flugzeugs. Hier startet jeder Bau.",
	})
	# Cockpit-/Kanzel-Varianten (Blender-glTF, lackierbarer Body + Glas-Kanzel)
	_add({
		"id": "cockpit_bubble", "name": "Bubble-Kanzel", "category": CAT_BODY,
		"mass": 165.0, "color": C_COCKPIT, "shape": "cockpit",
		"size": Vector3(1.3, 1.3, 2.4),
		"desc": "Runde Jäger-Bubble-Kanzel mit Rundumsicht.",
	})
	_add({
		"id": "cockpit_jet", "name": "Jet-Kanzel", "category": CAT_BODY,
		"mass": 150.0, "color": C_COCKPIT, "shape": "cockpit",
		"size": Vector3(1.1, 1.05, 2.6),
		"desc": "Flache, schnittige Tropfen-Kanzel für Jets.",
	})
	_add({
		"id": "cockpit_frame", "name": "Rahmen-Kanzel", "category": CAT_BODY,
		"mass": 185.0, "color": C_COCKPIT, "shape": "cockpit",
		"size": Vector3(1.3, 1.4, 2.25),
		"desc": "Klassische Mehrscheiben-Kanzel mit Streben.",
	})
	_add({
		"id": "cockpit_tandem", "name": "Tandem-Kanzel", "category": CAT_BODY,
		"mass": 220.0, "color": C_COCKPIT, "shape": "cockpit",
		"size": Vector3(1.2, 1.25, 3.1),
		"desc": "Zweisitzer mit zwei Kanzeln hintereinander.",
	})
	_add({
		"id": "fuselage", "name": "Rumpfsegment", "category": CAT_BODY,
		"mass": 120.0, "color": C_BODY, "shape": "box",
		"size": Vector3(1.3, 1.1, 2.0), "biends": true,
		"desc": "Rumpf-Tubus. BEIDE Enden einzeln skalierbar (Panel »Vorne«/»Hinten«) — vorne/hinten verschieden dick, für fließend zulaufende Rümpfe.",
	})
	_add({
		"id": "fuselage_long", "name": "Langes Rumpfsegment", "category": CAT_BODY,
		"mass": 175.0, "color": C_BODY, "shape": "box",
		"size": Vector3(1.3, 1.1, 3.2), "biends": true,
		"desc": "Langer Rumpf-Tubus. Beide Enden einzeln dick/dünn (Panel »Vorne«/»Hinten«).",
	})
	_add({
		"id": "fuselage_wide", "name": "Breiter Rumpf", "category": CAT_BODY,
		"mass": 165.0, "color": C_BODY, "shape": "box",
		"size": Vector3(1.85, 1.0, 2.6), "biends": true,
		"desc": "Breite, flache Rumpfsektion (Blended-Body). Beide Enden einzeln skalierbar — ideal für Stealth-Jets.",
	})
	_add({
		"id": "fuselage_taper", "name": "Verjüngungs-Rumpf", "category": CAT_BODY,
		"mass": 140.0, "color": C_BODY, "shape": "box",
		"size": Vector3(1.45, 1.05, 2.8), "biends": true, "taper": 0.55,
		"desc": "Läuft von breit auf schmal zu (Übergang Rumpf↔Nase/Heck). Beide Enden einzeln skalierbar, mit R umdrehbar.",
	})
	_add({
		"id": "f22_body", "name": "F-22 Stealth-Rumpf", "category": CAT_BODY,
		"mass": 360.0, "color": Color(0.37, 0.39, 0.43), "shape": "box",
		"size": Vector3(1.35, 0.95, 8.3), "col_size": Vector3(1.2, 0.85, 8.0),
		"metal": 0.25, "rough": 0.55,
		"desc": "Gefacetteter Stealth-Rumpf mit gechinten Kanten, Kanzel und Lufteinläufen (F-22). Ein langes Stück — Flügel/Leitwerk dran, fertig.",
	})
	_add({
		"id": "f22_head", "name": "F-22 Kopf (Cockpit)", "category": CAT_BODY,
		"mass": 240.0, "color": Color(0.37, 0.39, 0.43), "shape": "box",
		"size": Vector3(1.5, 1.0, 4.0), "col_size": Vector3(1.4, 0.95, 3.8),
		"metal": 0.25, "rough": 0.5,
		"desc": "F-22-Bugsektion: Spitznase + Kanzel, endet hinten am gechinten Querschnitt. Daran den »F-22 Rumpf (verjüngbar)« andocken.",
	})
	_add({
		"id": "f22_fuselage", "name": "F-22 Rumpf (verjüngbar)", "category": CAT_BODY,
		"mass": 200.0, "color": Color(0.37, 0.39, 0.43), "shape": "prism",
		"size": Vector3(1.5, 0.95, 2.6), "col_size": Vector3(1.42, 0.9, 2.6),
		"metal": 0.25, "rough": 0.55, "biends": true, "taper": 0.78,
		"desc": "Gechinter Stealth-Rumpf — passt exakt an den Querschnitt des F-22-Kopfes. BEIDE Enden einzeln skalierbar (Panel »Vorne«/»Hinten«) → vorne breit, hinten schmal.",
	})
	_add({
		"id": "mustang_body", "name": "P-51 Mustang-Rumpf", "category": CAT_BODY,
		"mass": 290.0, "color": Color(0.80, 0.81, 0.84), "shape": "box",
		"size": Vector3(0.95, 1.15, 5.2),
		# Kollisions-/Verbindungsbox deckt die ganze Rumpflänge (Nase z≈-1.6 bis Heck z≈+3.6)
		"col_size": Vector3(0.85, 1.0, 5.3), "col_offset": Vector3(0, 0.0, 0.96),
		"metal": 1.0, "rough": 0.3,
		"desc": "Dedizierter P-51-Rumpf mit Bubble-Kanzel und Bauch-Kühlerschacht (ein Stück, Blender-Modell). Triebwerk vorn, Flügel/Leitwerk dran.",
	})
	_add({
		"id": "me262_body", "name": "Me-262-Rumpf", "category": CAT_BODY,
		"mass": 320.0, "color": Color(0.64, 0.67, 0.69), "shape": "box",
		"size": Vector3(0.8, 1.18, 6.65), "col_size": Vector3(0.72, 1.0, 6.4),
		"metal": 0.45, "rough": 0.42,
		"desc": "Dedizierter Me-262-Rumpf: dreieckiger Hai-Querschnitt, spitze Nase, flache Rahmen-Kanzel (Blender-Modell). Pfeilflügel + 2 Düsengondeln dran.",
	})
	# --- Modulare Jet-Rumpf-Abschnitte: jeder ist ein gelofteter Abschnitt mit GLEICHEM
	#     Querschnitt (0.65 x 0.55) -> stoßbündig aneinander (kein Overlap, keine Naht). ---
	_add({
		"id": "jet_nose", "name": "Jet-Nasenteil (Lufteinlauf)", "category": CAT_BODY,
		"mass": 95.0, "color": Color(0.80, 0.81, 0.84), "shape": "jet_hull",
		"size": Vector3(1.336, 1.15, 1.89), "col_size": Vector3(1.28, 1.08, 1.9),
		"metal": 0.6, "rough": 0.34, "intake": true,
		"stations": [
			Vector4(-1.0, 0.52, 0.47, 0.0), Vector4(-0.55, 0.61, 0.55, 0.0),
			Vector4(0.1, 0.65, 0.55, 0.0), Vector4(0.92, 0.65, 0.55, 0.0)],
		"desc": "Hochwertiges Blender-Nasenteil: echte gerundete Einlauf-Lippe (Außenhaut rollt über die runde Vorderkante in den tiefen, matt-schwarzen Schacht). Querschnitt hinten = Rumpfsegment -> stoßbündig.",
	})
	_add({
		"id": "jet_body", "name": "Jet-Rumpfsegment", "category": CAT_BODY,
		"mass": 110.0, "color": Color(0.80, 0.81, 0.84), "shape": "jet_hull",
		"size": Vector3(1.34, 1.12, 1.6), "col_size": Vector3(1.25, 1.05, 1.78),
		"metal": 0.55, "rough": 0.4,
		"stations": [
			Vector4(-0.8, 0.65, 0.55, 0.0), Vector4(0.0, 0.66, 0.555, 0.0),
			Vector4(0.8, 0.65, 0.55, 0.0)],
		"desc": "Generisches Jet-Rumpfsegment (gelofteter Tubus). Beide Enden offen & gleicher Querschnitt -> stoßbündig. Mit »Hinten«-Taper wird daraus ein Heckkonus (Düse).",
	})
	_add({
		"id": "jet_cockpit", "name": "Jet-Cockpit-Segment", "category": CAT_BODY,
		"mass": 150.0, "color": Color(0.80, 0.81, 0.84), "shape": "jet_hull",
		"size": Vector3(1.34, 1.5, 1.6), "col_size": Vector3(1.25, 1.2, 1.78),
		"metal": 0.55, "rough": 0.4,
		"stations": [
			Vector4(-0.8, 0.65, 0.55, 0.0), Vector4(0.0, 0.66, 0.555, 0.0),
			Vector4(0.8, 0.65, 0.55, 0.0)],
		"canopy": [-0.05, 1.25, 0.30, 0.27, 0.42],
		"desc": "Rumpfsegment mit schwarz verglaster Bubble-Kanzel. Gleicher Querschnitt wie das generische Rumpfsegment -> stoßbündig an Nase & Rumpf.",
	})
	_add({
		"id": "red_star", "name": "Roter Stern (Markierung)", "category": CAT_BODY,
		"mass": 2.0, "color": Color(0.72, 0.10, 0.11), "shape": "box",
		"size": Vector3(0.06, 0.6, 0.6), "col_size": Vector3(0.12, 0.55, 0.55),
		"metal": 0.1, "rough": 0.5,
		"desc": "Flacher roter Sowjet-Stern als Hoheitsabzeichen. Flach auf Rumpf/Flügel/Leitwerk kleben (Default-Seite = rechts).",
	})
	_add({
		"id": "mig15_hull", "name": "MiG-15-Rumpf (1 Stück, berechnet)", "category": CAT_BODY,
		"mass": 470.0, "color": Color(0.80, 0.81, 0.84), "shape": "jet_hull",
		"size": Vector3(1.34, 1.3, 7.1), "col_size": Vector3(1.2, 1.1, 6.8),
		"metal": 0.55, "rough": 0.4,
		"intake": true, "rear_cap": true,
		# durchgehendes Loft-Profil: Vector4(z, halbbreite, halbhöhe, höhen-offset)
		"stations": [
			Vector4(-3.6, 0.50, 0.46, 0.0), Vector4(-3.3, 0.57, 0.52, 0.0),
			Vector4(-2.7, 0.63, 0.57, 0.01), Vector4(-1.7, 0.66, 0.59, 0.03),
			Vector4(-0.5, 0.66, 0.59, 0.05), Vector4(0.7, 0.63, 0.56, 0.06),
			Vector4(1.7, 0.56, 0.50, 0.07), Vector4(2.5, 0.46, 0.42, 0.08),
			Vector4(3.1, 0.38, 0.35, 0.09), Vector4(3.5, 0.33, 0.31, 0.10),
		],
		"canopy": [-0.6, 1.7, 0.30, 0.28, 0.42],
		"desc": "Kompletter MiG-15-Rumpf als EINE durchgehend berechnete Fläche (Loft) — Nasen-Einlauf, Kanzel und Heckdüse integriert, keine Segment-Nähte.",
	})
	_add({
		"id": "mig15_body", "name": "MiG-15-Rumpf", "category": CAT_BODY,
		"mass": 320.0, "color": Color(0.80, 0.81, 0.84), "shape": "box",
		"size": Vector3(1.12, 1.4, 5.9), "col_size": Vector3(0.96, 1.05, 5.7),
		"metal": 0.9, "rough": 0.35,
		"desc": "Dedizierter MiG-15-Rumpf: gedrungener Tonnen-Rumpf, runder Nasen-Einlauf mit Teiler, Bubble-Kanzel (Blender-Modell). Pfeilflügel + hohes Leitwerk dran.",
	})
	_add({
		"id": "f86_body", "name": "F-86 Sabre-Rumpf", "category": CAT_BODY,
		"mass": 330.0, "color": Color(0.82, 0.83, 0.86), "shape": "box",
		"size": Vector3(1.05, 1.35, 6.6), "col_size": Vector3(0.9, 1.0, 6.4),
		"metal": 1.0, "rough": 0.28,
		"desc": "Dedizierter F-86-Sabre-Rumpf: runder Nasen-Lufteinlauf, Bubble-Kanzel (Blender-Modell). Pfeilflügel + Jet-Triebwerk (Heckdüse) dran.",
	})
	_add({
		"id": "mig21_nose", "name": "MiG-21-Nase (Schock-Konus)", "category": CAT_BODY,
		"mass": 90.0, "color": Color(0.76, 0.78, 0.82), "shape": "nose",
		"size": Vector3(0.78, 0.74, 3.0), "col_size": Vector3(0.74, 0.70, 2.05),
		"desc": "Charakteristische MiG-21-Nase: runder Überschall-Einlauf mit SCHOCK-KONUS (Blender). An schlanke Rumpfsegmente setzen.",
	})
	_add({
		"id": "mig21_front", "name": "MiG-21-Vorderrumpf (edel)", "category": CAT_BODY,
		"mass": 180.0, "color": Color(0.74, 0.76, 0.79), "shape": "box",
		"size": Vector3(0.79, 1.0, 4.73), "col_size": Vector3(0.74, 0.72, 3.7),
		"col_offset": Vector3(0, 0, 0.4),
		"desc": "Hochwertiger Vorderrumpf aus einem Guss: dünne Einlauf-Lippe, Schock-Konus, Pitot, eingepasste Kanzel mit Fairing, Panel-Linien (Blender). Hinten 0.78er-Anschluss.",
	})
	_add({
		"id": "mig21_cockpit", "name": "Schlank-Cockpit (Überschall)", "category": CAT_BODY,
		"mass": 95.0, "color": Color(0.76, 0.78, 0.82), "shape": "box",
		"size": Vector3(0.78, 0.89, 1.6), "col_size": Vector3(0.74, 0.72, 1.55),
		"desc": "Schlankes Rumpfsegment mit flacher, eingepasster Kanzel + Rückenspine (Blender). Für Überschalljäger im 0.78er-Querschnitt.",
	})
	_add({
		"id": "mig21_body", "name": "Schlank-Segment (Überschall)", "category": CAT_BODY,
		"mass": 80.0, "color": Color(0.76, 0.78, 0.82), "shape": "box",
		"size": Vector3(0.78, 0.82, 1.6), "col_size": Vector3(0.74, 0.72, 1.55),
		"desc": "Schlankes Rumpfsegment mit durchlaufendem Rückenspine (Blender). Reiht sich nahtlos an Schlank-Cockpit/-Nase.",
	})
	_add({
		"id": "mig21_tail", "name": "Schlank-Heck (Düse)", "category": CAT_BODY,
		"mass": 85.0, "color": Color(0.76, 0.78, 0.82), "shape": "box",
		"size": Vector3(0.78, 0.81, 1.68), "col_size": Vector3(0.72, 0.70, 1.6),
		"desc": "Boattail-Heck mit integrierter Düse, Spine läuft aus (Blender). Schließt die Schlank-Linie ab.",
	})
	_add({
		"id": "mig21_rear", "name": "MiG-21-Heckrumpf (Spine+Düse)", "category": CAT_BODY,
		"mass": 165.0, "color": Color(0.74, 0.76, 0.79), "shape": "box",
		"size": Vector3(0.78, 0.98, 3.6), "col_size": Vector3(0.74, 0.72, 3.5),
		"desc": "Heckrumpf aus einem Guss: Rückenspine-Fairing, Boattail-Taper, dunkler Düsenring mit Innenkonus, Ventralflosse, Bremsschirm-Behälter (Blender). Schließt bündig an den MiG-21-Vorderrumpf an.",
	})
	# MiG-21-Flächensatz: echte Blender-Geometrie (beschnittenes Delta, dünnes Profil),
	# Aero-Felder wie die generischen Pendants -> fliegt identisch, sieht echt aus.
	_add({
		"id": "mig21_wing", "name": "MiG-21-Deltaflügel", "category": CAT_WING,
		"mass": 80.0, "color": C_WING, "shape": "wing",
		"span": 3.5, "root_chord": 2.9, "tip_chord": 0.25, "sweep": 2.65, "thickness": 0.115,
		"is_wing": true, "area": 5.0, "lift": 0.9, "control": "", "orient_normal": true,
		"stress_mult": 4.0,
		"col_size": Vector3(1.75, 0.22, 2.9), "col_offset": Vector3(0.875, 0.0, 0.0),
		"metal": 0.15, "rough": 0.6,
		"desc": "Beschnittenes 57°-Delta mit scharfer Hinterkante, Querruder-Linie und Grenzschichtzaun (Blender). Extrem belastbar (Jet-Flügel).",
	})
	_add({
		"id": "mig21_stab", "name": "MiG-21-Höhenleitwerk", "category": CAT_CTRL,
		"mass": 30.0, "color": C_CTRL, "shape": "wing",
		"span": 2.4, "root_chord": 1.1, "tip_chord": 0.25, "sweep": 0.9, "thickness": 0.06,
		"is_wing": true, "area": 2.0, "lift": 0.85, "control": "pitch", "orient_normal": true,
		"stress_mult": 4.0,
		"col_size": Vector3(0.95, 0.14, 1.15), "col_offset": Vector3(0.475, 0.0, 0.0),
		"metal": 0.15, "rough": 0.6,
		"desc": "Gepfeiltes Pendelruder der MiG-21 (Blender), steuert Nick.",
	})
	_add({
		"id": "mig21_fin", "name": "MiG-21-Seitenflosse", "category": CAT_CTRL,
		"mass": 32.0, "color": C_CTRL, "shape": "wing",
		"span": 1.6, "root_chord": 1.8, "tip_chord": 0.4, "sweep": 1.5, "thickness": 0.10,
		"is_wing": true, "area": 1.8, "lift": 0.8, "control": "yaw", "orient_normal": true,
		"stress_mult": 4.0,
		"col_size": Vector3(0.14, 1.4, 1.9), "col_offset": Vector3(0.0, 0.7, 0.0),
		"metal": 0.15, "rough": 0.6,
		"desc": "Breite, stark gepfeilte Seitenflosse mit Ruderlinie (Blender), steuert Gier. Steht senkrecht — direkt auf den Rumpfrücken setzen.",
	})
	_add({
		"id": "f4_nose", "name": "F-4-Hängenase", "category": CAT_BODY,
		"mass": 95.0, "color": Color(0.45, 0.50, 0.42), "shape": "nose",
		"size": Vector3(1.336, 1.08, 2.72), "col_size": Vector3(1.25, 1.0, 2.4),
		"desc": "Die hängende Phantom-Nase mit dunklem Radom (Blender). Breit-flacher Querschnitt — passt auf breite Rumpfsegmente.",
	})
	_add({
		"id": "f4_intake", "name": "Seiten-Einlauf (Phantom)", "category": CAT_BODY,
		"mass": 55.0, "color": Color(0.45, 0.50, 0.42), "shape": "box",
		"size": Vector3(0.42, 0.81, 1.84), "col_size": Vector3(0.4, 0.75, 1.7),
		"desc": "Angewinkelter Wangen-Lufteinlauf (Blender). Paarweise seitlich an den Rumpf — Symmetrie macht den zweiten.",
	})
	_add({
		"id": "jet_nose_point", "name": "Jet-Spitznase (Radom)", "category": CAT_BODY,
		"mass": 85.0, "color": Color(0.7, 0.72, 0.76), "shape": "nose",
		"size": Vector3(1.336, 1.15, 2.77), "col_size": Vector3(1.25, 1.05, 2.4),
		"col_offset": Vector3(0, 0, 0.18),
		"desc": "Spitze Radom-Nase im Jet-Querschnitt (Blender) — für Überschalljäger ohne Nasen-Einlauf (F-14, F-4, Eigenbauten).",
	})
	_add({
		"id": "f14_nacelle", "name": "Tomcat-Gondel (Triebwerk)", "category": CAT_PROP,
		"mass": 260.0, "color": Color(0.62, 0.66, 0.72), "shape": "jet", "thrust": 11000.0, "jet": true,
		"size": Vector3(0.76, 0.77, 4.5), "col_size": Vector3(0.7, 0.72, 4.3),
		"metal": 0.8, "rough": 0.35,
		"desc": "Komplette F-14-Triebwerksgondel: eckiger Einlauf, Rohr, Düse (Blender). 11 kN Schub — paarweise unter den Rumpf.",
	})
	_add({
		"id": "nose", "name": "Nasenkonus", "category": CAT_BODY,
		"mass": 70.0, "color": C_BODY, "shape": "nose",
		"size": Vector3(1.3, 1.1, 1.8),
	})
	_add({
		"id": "tailcone", "name": "Heckkonus", "category": CAT_BODY,
		"mass": 60.0, "color": C_BODY, "shape": "nose", "reverse": true,
		"size": Vector3(1.3, 1.1, 1.8),
	})
	_add({
		"id": "strut", "name": "Tragflächenstrebe", "category": CAT_BODY,
		"mass": 25.0, "color": Color(0.32, 0.26, 0.18), "shape": "box",
		"size": Vector3(0.2, 1.5, 0.5), "metal": 0.3, "rough": 0.6,
		"desc": "Dünne Strebe — verbindet z. B. obere und untere Tragfläche beim Doppeldecker.",
	})
	_add({
		"id": "fueltank", "name": "Treibstofftank", "category": CAT_BODY,
		"mass": 240.0, "color": Color(0.7, 0.72, 0.75), "shape": "cyl",
		"size": Vector3(1.2, 1.2, 2.0), "metal": 0.6, "rough": 0.3,
	})

	# --- Tragflächen -------------------------------------------------------
	_wing("wing_straight", "Gerade Tragfläche", CAT_WING, 70.0, C_WING, 4.4, 1.7, 1.7, 0.0, 1.05)
	_wing("wing_tapered", "Trapezflügel", CAT_WING, 62.0, C_WING, 4.6, 1.9, 1.0, 0.4, 1.0)
	# Jet-Jäger-Flügel: EXTREM belastbar (×4 WING_STRESS) — für hohe G im Luftkampf gebaut.
	_wing("wing_swept", "Pfeilflügel", CAT_WING, 66.0, C_WING, 4.6, 1.7, 1.0, 1.5, 0.95, "", 4.0)
	_wing("wing_delta", "Deltaflügel", CAT_WING, 88.0, C_WING, 3.6, 3.2, 0.4, 2.7, 0.9, "", 4.0)
	_wing("wing_short", "Stummelflügel", CAT_WING, 42.0, C_WING, 2.4, 1.5, 1.1, 0.2, 1.0)
	_wing("wing_glider", "Segler-Flügel (lang)", CAT_WING, 95.0, C_WING, 6.8, 1.3, 0.75, 0.3, 1.25)
	_wing("canard", "Canard-Flügel", CAT_WING, 30.0, C_WING, 1.8, 1.0, 0.6, 0.15, 1.0)
	_wing("winglet", "Winglet", CAT_WING, 14.0, C_WING, 1.0, 0.8, 0.45, 0.25, 0.6)

	# --- Leitwerk & Steuerung ---------------------------------------------
	_wing("h_stab", "Höhenleitwerk (Pitch)", CAT_CTRL, 32.0, C_CTRL, 2.6, 1.1, 0.7, 0.25, 0.85, "pitch")
	_wing("v_stab", "Seitenleitwerk (Yaw)", CAT_CTRL, 30.0, C_CTRL, 1.8, 1.3, 0.7, 0.7, 0.8, "yaw")
	_wing("aileron", "Querruder (Roll)", CAT_CTRL, 16.0, C_CTRL, 1.8, 0.7, 0.55, 0.05, 0.7, "roll")
	_add({
		"id": "wing_fence", "name": "Grenzschichtzaun", "category": CAT_WING,
		"mass": 3.0, "color": C_WING, "shape": "plate",
		"size": Vector3(0.03, 0.16, 1.0), "col_size": Vector3(0.03, 0.16, 1.0),
		"metal": 0.4, "rough": 0.5,
		"desc": "Grenzschichtzaun (Wing Fence) — schmale Platte auf der Flügeloberseite gegen Strömungsabriss (MiG-15/-17-Detail).",
	})
	_wing("elevator", "Höhenruder klein", CAT_CTRL, 14.0, C_CTRL, 1.6, 0.7, 0.55, 0.05, 0.7, "pitch")

	# --- Antrieb -----------------------------------------------------------
	_add({
		"id": "prop_engine", "name": "Propellermotor", "category": CAT_PROP,
		"mass": 160.0, "color": C_ENGINE, "shape": "prop", "thrust": 6500.0,
		"size": Vector3(1.1, 1.1, 1.7), "metal": 0.7, "rough": 0.35,
	})
	_add({
		"id": "prop_engine_big", "name": "Großer Propeller", "category": CAT_PROP,
		"mass": 250.0, "color": C_ENGINE, "shape": "prop", "thrust": 11000.0,
		"size": Vector3(1.5, 1.5, 1.9), "metal": 0.7, "rough": 0.35,
	})
	_add({
		"id": "jet_engine", "name": "Düsentriebwerk", "category": CAT_PROP,
		"mass": 300.0, "color": C_ENGINE, "shape": "jet", "thrust": 20000.0, "jet": true,
		"size": Vector3(1.2, 1.2, 2.6), "metal": 0.8, "rough": 0.25,
	})
	_add({
		"id": "thruster", "name": "Hilfstriebwerk", "category": CAT_PROP,
		"mass": 95.0, "color": C_ENGINE, "shape": "jet", "thrust": 4200.0, "jet": true,
		"size": Vector3(0.8, 0.8, 1.4), "metal": 0.8, "rough": 0.25,
		"flame_scale": 0.5, "spin_mult": 2.2,   # kleinerer Nachbrenner + schneller drehender Fan
	})
	_add({
		"id": "jet_square", "name": "Eckiges Düsentriebwerk", "category": CAT_PROP,
		"mass": 320.0, "color": C_ENGINE, "shape": "jet", "thrust": 22000.0, "jet": true,
		"size": Vector3(1.3, 1.1, 2.8), "metal": 0.8, "rough": 0.3,
		"desc": "Rechteckiges Stealth-Triebwerk mit flacher 2D-Düse. Kräftig.",
	})
	_add({
		"id": "f22_engine", "name": "F-22 2D-Schubvektordüse", "category": CAT_PROP,
		"mass": 330.0, "color": Color(0.3, 0.31, 0.34), "shape": "jet", "thrust": 21000.0, "jet": true,
		"size": Vector3(0.62, 0.78, 1.95), "col_size": Vector3(0.6, 0.74, 1.9),
		"metal": 0.7, "rough": 0.38,
		"desc": "Rechteckige 2D-Schubvektordüse mit Petals und Nachbrenner-Glühen (F-22). Konstanter Jet-Schub.",
	})

	# --- Fahrwerk (mit Traglast in kg; Summe muss das Gewicht tragen) ------
	_add({
		"id": "wheel_light", "name": "Leichtes Fahrwerk", "category": CAT_GEAR,
		"mass": 28.0, "color": C_GEAR, "shape": "wheel", "gear_capacity": 450.0,
		"size": Vector3(0.5, 1.0, 0.7), "metal": 0.1, "rough": 0.8,
		"desc": "Leicht, aber nur ~450 kg Traglast.",
	})
	_add({
		"id": "wheel", "name": "Standard-Fahrwerk", "category": CAT_GEAR,
		"mass": 45.0, "color": C_GEAR, "shape": "wheel", "gear_capacity": 850.0,
		"size": Vector3(0.6, 1.2, 0.9), "metal": 0.1, "rough": 0.8,
		"desc": "Ausgewogen, ~850 kg Traglast.",
	})
	_add({
		"id": "wheel_heavy", "name": "Schweres Fahrwerk", "category": CAT_GEAR,
		"mass": 85.0, "color": C_GEAR, "shape": "wheel", "gear_capacity": 1750.0,
		"size": Vector3(0.78, 1.4, 1.05), "metal": 0.15, "rough": 0.75,
		"desc": "Robust, ~1750 kg Traglast — für schwere Jets.",
	})
	_add({
		"id": "wheel_retract", "name": "Einziehfahrwerk (G)", "category": CAT_GEAR,
		"mass": 60.0, "color": Color(0.16, 0.16, 0.2), "shape": "wheel", "gear_capacity": 1050.0,
		"size": Vector3(0.4, 1.1, 0.65), "col_size": Vector3(0.36, 1.05, 0.62),
		"col_offset": Vector3(0, -0.52, 0), "metal": 0.5, "rough": 0.45, "retract": true,
		"desc": "Im Flug mit G einfahren (Bein klappt hoch, Klappe schwenkt) -> weniger Widerstand. ~1050 kg.",
	})
	_add({
		"id": "wheel_jet", "name": "Jet-Fahrwerk (Einzug)", "category": CAT_GEAR,
		"mass": 55.0, "color": Color(0.17, 0.18, 0.21), "shape": "wheel", "gear_capacity": 1250.0,
		"size": Vector3(0.32, 1.05, 0.6), "col_size": Vector3(0.3, 1.0, 0.55),
		"col_offset": Vector3(0, -0.5, 0), "metal": 0.6, "rough": 0.4, "retract": true,
		"desc": "Modernes Kampfjet-Fahrwerk: schlanker Öldämpfer-Beinholm, kleines Low-Profile-Rad mit Bremsscheibe. Einziehbar (G). ~1250 kg.",
	})

	# --- Bewaffnung (feuerbar: LEERTASTE = Kanone/Raketen, B = Bombe) ------
	_add({
		"id": "cannon", "name": "Bordkanone (20 mm)", "category": CAT_WEAPON,
		"mass": 110.0, "color": C_WEAPON, "shape": "cannon", "weapon": "gun",
		"size": Vector3(0.42, 0.42, 1.6), "metal": 0.7, "rough": 0.35,
		"desc": "Mittleres Kaliber, Schnellfeuer (LEERTASTE). Flaches Geschoss, wenig Bullet-Drop.",
	})
	_add({
		"id": "autocannon", "name": "Autokanone (30 mm)", "category": CAT_WEAPON,
		"mass": 175.0, "color": Color(0.26, 0.27, 0.30), "shape": "cannon", "weapon": "autocannon",
		"size": Vector3(0.5, 0.5, 1.9), "metal": 0.72, "rough": 0.35,
		"desc": "Schweres Kaliber (LEERTASTE): langsamere, hart einschlagende Granaten — spürbarer Bullet-Drop, hoher Schaden.",
	})
	_add({
		"id": "heavy_cannon", "name": "Schwere Kanone (37 mm)", "category": CAT_WEAPON,
		"mass": 260.0, "color": Color(0.22, 0.23, 0.26), "shape": "cannon", "weapon": "heavy",
		"size": Vector3(0.62, 0.62, 2.3), "metal": 0.7, "rough": 0.4,
		"desc": "Großkaliber (LEERTASTE): sehr langsame Granate, starker Bullet-Drop, riesiger Schaden — top gegen Luftschiffe. Langsame Kadenz.",
	})
	_add({
		"id": "mg", "name": "Bord-MG (7.9 mm)", "category": CAT_WEAPON,
		"mass": 55.0, "color": Color(0.2, 0.21, 0.23), "shape": "cannon", "weapon": "mg",
		"size": Vector3(0.3, 0.3, 1.3), "metal": 0.75, "rough": 0.35,
		"desc": "Leichtes Kaliber: schnelles, flaches Geschoss (kaum Bullet-Drop), langsame Kadenz. Klassiker fürs Doppeldecker-Cockpit.",
	})
	_add({
		"id": "wing_gun", "name": "Flügel-MG (.50)", "category": CAT_WEAPON,
		"mass": 60.0, "color": Color(0.18, 0.18, 0.2), "shape": "cannon", "weapon": "gun",
		"size": Vector3(0.26, 0.26, 1.5), "col_size": Vector3(0.24, 0.24, 1.2),
		"col_offset": Vector3(0, 0, 0.1), "metal": 0.7, "rough": 0.35,
		"desc": "In die Tragfläche eingelassenes MG mit Kühlmantel — feuert schnell nach vorn (LEERTASTE). Ideal paarweise in den Flügeln.",
	})
	_add({
		"id": "minigun", "name": "GAU-8 Gatling (30 mm)", "category": CAT_WEAPON,
		"mass": 290.0, "color": Color(0.13, 0.13, 0.15), "shape": "cannon", "weapon": "minigun",
		"size": Vector3(0.38, 0.38, 3.3), "metal": 0.85, "rough": 0.4,
		"desc": "Rotierende Gatling (LEERTASTE): dreht erst hoch (Spin-up), dann BRRRRT — extreme Feuerrate, kräftiger Rückstoß. Die Kanone des A-10.",
	})
	_add({
		"id": "rocket", "name": "Ungelenkte Rakete", "category": CAT_WEAPON,
		"mass": 70.0, "color": Color(0.7, 0.55, 0.3), "shape": "missile", "weapon": "rocket",
		"size": Vector3(0.3, 0.3, 2.0), "metal": 0.4, "rough": 0.5,
		"desc": "Dumme Rakete (LEERTASTE) — fliegt schnell GERADEAUS, kein Suchkopf. Schlanker Hydra-Körper mit Ogiven-Nase, Heckflossen und Düse (Blender).",
	})
	_add({
		"id": "rocket_pod", "name": "Raketenwerfer", "category": CAT_WEAPON,
		"mass": 140.0, "color": Color(0.35, 0.37, 0.4), "shape": "pod", "weapon": "salvo",
		"size": Vector3(0.6, 0.6, 1.5), "metal": 0.6, "rough": 0.4,
		"desc": "Salve aus 3 ungelenkten Raketen auf einmal (LEERTASTE), leicht gefächert.",
	})
	_add({
		"id": "missile", "name": "Zielsuchrakete", "category": CAT_WEAPON,
		"mass": 95.0, "color": Color(0.85, 0.86, 0.9), "shape": "missile", "weapon": "missile",
		"size": Vector3(0.34, 0.34, 2.4), "metal": 0.5, "rough": 0.4,
		"desc": "Heat-Seeker (LEERTASTE) — fliegt geradeaus und kurvt aufs Ziel, sobald eins in die Nähe kommt. IR-Suchkopf, Vorder-Canards, Heckflossen mit Rollerons, Kabelkanal (Blender).",
	})
	_add({
		"id": "missile_heavy", "name": "Schwere Lenkrakete", "category": CAT_WEAPON,
		"mass": 190.0, "color": Color(0.78, 0.8, 0.85), "shape": "missile", "weapon": "missile_heavy",
		"size": Vector3(0.46, 0.46, 3.2), "metal": 0.5, "rough": 0.4,
		"desc": "Großer Suchkopf + großer Knall, größere Reichweite, träger (LEERTASTE). Radar-Lenkrakete im Sparrow-Stil: dielektrisches Radom, Mittelflügel, Steuerflossen, Kabelkanal (Blender).",
	})
	_add({
		"id": "bomb", "name": "Bombe", "category": CAT_WEAPON,
		"mass": 220.0, "color": Color(0.28, 0.34, 0.3), "shape": "bomb", "weapon": "bomb",
		"size": Vector3(0.5, 0.5, 1.9), "metal": 0.3, "rough": 0.6,
		"desc": "Freifallbombe (Taste B). Großer Knall — fällt mit der Schwerkraft.",
	})



static func _add(p: Dictionary) -> void:
	# Standardwerte
	var d := {
		"shape": "box", "color": Color.WHITE, "mass": 50.0,
		"size": Vector3.ONE, "is_wing": false, "thrust": 0.0,
		"control": "", "orient_normal": false, "area": 0.0, "lift": 1.0,
		"metal": 0.3, "rough": 0.55, "root": false, "reverse": false,
		"gear_capacity": 0.0, "retract": false, "weapon": "",
	}
	for k in p.keys():
		d[k] = p[k]
	_parts[d["id"]] = d
	_order.append(d["id"])


static func _wing(id: String, name: String, cat: String, mass: float, color: Color,
		span: float, rc: float, tc: float, sweep: float, lift: float, control: String = "",
		stress := 1.0) -> void:
	# stress = Festigkeits-Multiplikator auf WING_STRESS (Jet-Flügel >> Holz/Stoff-Flügel)
	var thick := 0.16
	var maxc: float = max(rc, tc)
	var area := (rc + tc) * 0.5 * span
	_add({
		"id": id, "name": name, "category": cat, "mass": mass, "color": color,
		"shape": "wing", "span": span, "root_chord": rc, "tip_chord": tc,
		"sweep": sweep, "thickness": thick, "is_wing": true, "area": area,
		"lift": lift, "control": control, "orient_normal": true, "stress_mult": stress,
		"col_size": Vector3(span, thick + 0.1, maxc + absf(sweep)),
		"col_offset": Vector3(span * 0.5, 0.0, sweep * 0.5),
		"metal": 0.15, "rough": 0.6,
	})


# ---------------------------------------------------------------------------
# Zugriff
# ---------------------------------------------------------------------------
static func all() -> Dictionary:
	_build()
	return _parts

static func get_part(id: String) -> Dictionary:
	_build()
	return _parts.get(id, {})

static func has(id: String) -> bool:
	_build()
	return _parts.has(id)

static func categories() -> Array:
	return CATEGORY_ORDER

static func parts_in(cat: String) -> Array:
	_build()
	var out: Array = []
	for id in _order:
		if _parts[id]["category"] == cat:
			out.append(_parts[id])
	return out

## Strukturelle Belastbarkeit pro m² Flügelfläche (N) — für die G-Last-Grenze
const WING_STRESS := 3600.0

## Parasitärer Luftwiderstand eines Teils (cW·A in m²), aus Stirnfläche × Füllgrad × Form.
# Form-Widerstandsbeiwert (cd) — physikalisch: flache/kastige Stirn = hoher Bluff-Widerstand,
# runde Körper weniger, schlanke/spitze Formen sehr wenig. Eine Quelle für Flug & Windkanal.
static func part_cd(p: Dictionary) -> float:
	match p.get("shape", "box"):
		"nose": return 0.12        # spitze Ogive — sehr windschlüpfrig
		"wing": return 0.05        # Airfoil-Kante (kaum Stirnwiderstand)
		"cockpit": return 0.28     # gerundete Kanzel
		"cyl": return 0.45         # liegender Zylinder (gerundet)
		"jet": return 0.42
		"prop": return 0.55
		"missile": return 0.12     # schlanker Flugkörper
		"bomb": return 0.16        # tropfenförmig
		"wheel": return 0.85       # stumpfer Reifen (Bluff-Körper)
		"cannon": return 0.92      # flache, kastige Geschütz-Stirn
		"pod": return 0.55         # runder Werfer-Pod
		"box": return 1.05         # Würfel/Platte — der widerstandsstärkste Bluff-Körper
		"prism": return 0.20       # gechinter Stealth-Rumpf — schlank/windschlüpfrig
		"jet_hull": return 0.15    # durchgehend gelofteter Jet-Rumpf — sehr windschlüpfrig
	return 0.9


# Füllgrad: Anteil der Bounding-Box-Stirnfläche, der tatsächlich Material ist (Rest = Luft).
# Ein Rad sitzt z.B. an einem DÜNNEN Federbein in einer hohen Box -> nur ~40 % gefüllt,
# darum war es vorher viel zu widerstandsstark.
static func _frontal_fill(shape: String) -> float:
	match shape:
		"wheel": return 0.42       # dünnes Federbein + kleiner Reifen in hoher Box
		"prop": return 0.45        # Spinner + dünne Blätter (viel Luft)
		"cannon": return 0.80      # Gehäuse füllt, Lauf dünn
		"pod": return 0.85         # runder Pod
		"cockpit": return 0.85
		"cyl", "jet", "nose", "missile", "bomb": return 0.80   # runder Querschnitt (~π/4)
		"box", "wing": return 1.0  # füllt die Box / Stirnfläche ist real
		"prism": return 0.78       # gechinter Querschnitt füllt ~78 % der Box
		"jet_hull": return 0.80    # runder gelofteter Querschnitt (~π/4)
	return 0.85


static func part_drag(p: Dictionary) -> float:
	var s: Vector3 = col_size(p)
	var shape: String = p.get("shape", "box")
	# echte Stirnfläche ≈ Box-Querschnitt (x·y, Flugrichtung -Z) × Füllgrad, mal Formbeiwert
	return s.x * s.y * _frontal_fill(shape) * part_cd(p)


## Kaufpreis eines Teils (Survival-Shop), aus Masse/Schub/Fläche/Traglast.
static func part_cost(p: Dictionary) -> int:
	var c: float = p.get("mass", 0.0) * 1.5 + p.get("thrust", 0.0) * 0.045 \
		+ p.get("area", 0.0) * 65.0 + p.get("gear_capacity", 0.0) * 0.4
	return int(round(maxf(c, 80.0) / 50.0)) * 50


## STRUKTURWERT: wie hart ein Aufprall (Schließgeschwindigkeit in m/s entlang der
## Kontaktnormale) sein darf, bevor das Teil bei einer Kollision ABBRICHT. Niedrig =
## bricht leicht (Holz/Leichtbau, z. B. ein Stoff-/Holzflügel), hoch = robust (Metall-
## Rumpf, Stealth-Chine). Bricht ein Teil, schluckt es den Stoß -> der Rest fliegt weiter.
## Reihenfolge: ausdrücklicher "strength"-Wert > leichte Sonderfälle (Holz) > Kategorie-Default.
static func part_strength(p: Dictionary) -> float:
	if p.has("strength"):
		return float(p["strength"])
	var id: String = p.get("id", "")
	# Holz/Leichtbau — brechen leicht weg:
	if id == "strut": return 4.0          # dünne Holzstrebe
	if id == "wing_straight": return 7.0  # einfacher (Holz-/Stoff-)Flügel
	if id == "wing_short": return 8.0
	if id == "winglet": return 9.0
	if id == "wing_swept" or id == "wing_delta": return 26.0  # Jet-Jäger-Flügel: extrem robust
	var cat: String = p.get("category", "")
	var shape: String = String(p.get("shape", ""))
	match cat:
		CAT_BODY:
			if shape == "cyl": return 11.0   # Tank
			if shape == "prism": return 28.0 # gechinter F-22-Rumpf (sehr robust)
			return 22.0                       # Rumpf/Cockpit/Nase/Heck
		CAT_WING: return 13.0                 # Metall-Tragflächen (überstehen mehr)
		CAT_CTRL: return 10.0                 # Leitwerk/Ruder
		CAT_PROP: return 20.0 if p.get("jet", false) else 15.0
		CAT_GEAR: return 8.0
		CAT_WEAPON: return 12.0
	return 14.0


static func col_size(p: Dictionary) -> Vector3:
	return p.get("col_size", p.get("size", Vector3.ONE))

static func col_offset(p: Dictionary) -> Vector3:
	return p.get("col_offset", Vector3.ZERO)


# Welt-Box eines Teils (für Verdeckungs-/Vergrabungs-Tests). basis_t = transponierte Basis.
static func part_box(p: Dictionary, xf: Transform3D, psc := Vector3.ONE) -> Dictionary:
	return {
		"center": xf * (col_offset(p) * psc),
		"basis_t": xf.basis.orthonormalized().transposed(),
		"half": col_size(p) * psc * 0.5,
	}


# Anteil der Flügel-Spannweite, der NICHT in einem Rumpf-Teil steckt (0..1). Im Rumpf vergrabene
# Spannweite erzeugt keinen Auftrieb -> effektive Fläche schrumpft. Sampling entlang der
# Spannweite (lokal X, Wurzel..Spitze) gegen die Rumpf-Boxen (point-in-OBB). Die innersten ~6 %
# (Anbindungs-Überlappung) werden nicht bestraft.
static func wing_exposed_fraction(wing_xf: Transform3D, span: float, sweep_off: float, body_boxes: Array) -> float:
	if body_boxes.is_empty() or span <= 0.01:
		return 1.0
	var n := 16
	var exposed := 0
	for k in n:
		var t: float = lerpf(0.06, 1.0, (float(k) + 0.5) / float(n))
		var wp: Vector3 = wing_xf * Vector3(t * span, 0.0, sweep_off)
		var inside := false
		for b in body_boxes:
			var lp: Vector3 = (b["basis_t"] as Basis) * (wp - (b["center"] as Vector3))
			var hf: Vector3 = b["half"]
			if absf(lp.x) <= hf.x and absf(lp.y) <= hf.y and absf(lp.z) <= hf.z:
				inside = true
				break
		if not inside:
			exposed += 1
	return float(exposed) / float(n)


# ---------------------------------------------------------------------------
# Material-Helfer
# ---------------------------------------------------------------------------
static func make_material(c: Color, metal := 0.3, rough := 0.55, double_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.metallic_specular = 0.6
	m.roughness = rough
	# leichter Kanten-Glanz für mehr Plastizität
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.35
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# Glüh-Material (Auspuff/Akzente)
static func glow_material(c: Color, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


# MeshInstance3D mit Material + Transform in einem Rutsch (gegen Boilerplate).
static func _mi(mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO,
		scl := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	if mat != null:
		m.material_override = mat
	m.position = pos
	m.rotation = rot
	m.scale = scl
	return m


# ---------------------------------------------------------------------------
# Visuelle Erzeugung — gibt einen Node3D zurück (kann mehrere Meshes enthalten)
# ---------------------------------------------------------------------------
const MODEL_DIR := "res://models/"
# Materialnamen aus den Blender-glTF-Modellen, die beim Lackieren umgefärbt werden.
const PAINT_MATS := ["body", "cockpit_body", "tankmetal", "engine"]


static func has_model(id: String) -> bool:
	return id != "" and ResourceLoader.exists(MODEL_DIR + id + ".glb")


static func build_visual(p: Dictionary, col_override := Color(0, 0, 0, 0), taper := 1.0, taper_front := 1.0, taper_y := -1.0, taper_front_y := -1.0) -> Node3D:
	# taper/taper_front = X-Skalierung des hinteren/vorderen Endes; taper_y/taper_front_y =
	# separate Y-Skalierung (< 0 -> wie X, also gleichförmig). So lässt sich jedes Rumpf-Ende
	# in Breite (X) und Höhe (Y) getrennt formen.
	var ef := Vector2(maxf(taper_front, 0.02), maxf(taper_front_y if taper_front_y >= 0.0 else taper_front, 0.02))
	var eb := Vector2(maxf(taper, 0.02), maxf(taper_y if taper_y >= 0.0 else taper, 0.02))
	var root := Node3D.new()
	# Hochwertiges Blender-Modell (glTF), falls vorhanden — sonst prozedural.
	var pid: String = p.get("id", "")
	if has_model(pid):
		_attach_model(root, pid, col_override)
		return root
	var shape: String = p.get("shape", "box")
	var col: Color = p.get("color", Color.WHITE)
	if col_override.a > 0.0:   # Lackierung überschreibt die Standardfarbe
		col = col_override
	var metal: float = p.get("metal", 0.3)
	var rough: float = p.get("rough", 0.55)
	var size: Vector3 = p.get("size", Vector3.ONE)

	match shape:
		"box":
			# Rumpfsegment als glatter, leicht abgerundeter Tubus (elliptischer Querschnitt).
			# BEIDE Enden einzeln in X UND Y skalierbar (elliptischer Loft): ef = vorderes
			# (-Z) Ende (x,y), eb = hinteres (+Z) -> Segment vorne/hinten verschieden breit/hoch.
			var tube := _box_tube(ef, eb, 18)
			root.add_child(_mi(tube, make_material(col, metal, rough), Vector3.ZERO,
				Vector3.ZERO, size))

		"jet_hull":
			# Gelofteter Rumpf-Abschnitt (Loft durch Querschnitt-Stationen). Stoßbündig an
			# Nachbarn (gleicher Querschnitt) -> keine Naht; taper formt ein Heckkonus-Ende.
			_jet_hull(root, p, col, metal, rough, ef, eb)

		"plate":
			# Dünne, leicht verrundete Platte (z. B. Grenzschichtzaun auf dem Flügel)
			var plm := BoxMesh.new()
			plm.size = size
			root.add_child(_mi(plm, make_material(col, metal, rough), Vector3.ZERO, Vector3.ZERO, Vector3.ONE))

		"prism":
			# Gechinter Stealth-Rumpf (F-22-Querschnitt). Beide Enden in X UND Y getrennt:
			# ef = vorderer (-Z) Querschnitt (x,y), eb = hinterer (+Z) -> Verjüngung/Formung.
			var pm := _prism_mesh(_f22_cross_section(), ef, eb)
			var pmat := make_material(col, metal, rough)
			pmat.cull_mode = BaseMaterial3D.CULL_DISABLED   # beidseitig -> kein Durchsehen
			root.add_child(_mi(pm, pmat, Vector3.ZERO, Vector3.ZERO, size))

		"wing":
			var mi := MeshInstance3D.new()
			# Auftriebsflügel gewölbt; Leitwerke/Ruder (control != "") symmetrisch.
			var camber: float = 0.0 if String(p.get("control", "")) != "" else 0.018
			mi.mesh = _wing_mesh(p.get("span", 4.0), p.get("root_chord", 1.5),
				p.get("tip_chord", 1.5), p.get("sweep", 0.0), p.get("thickness", 0.16), camber)
			mi.material_override = make_material(col, metal, rough, true)
			root.add_child(mi)
			# Bewegliche Hinterkanten-Fläche: Hauptflügel -> Landeklappe (innen),
			# Steuerflügel -> Ruder (Höhe/Seite/Quer). Eingefahren bündig, im Flug sichtbar.
			if String(p.get("control", "")) == "":
				if p.get("span", 0.0) >= 2.2:
					_trailing_panel(root, p, "FlapHinge", 0.5, 0.33, 0.28, col, metal, rough)
			else:
				_trailing_panel(root, p, "CtrlHinge", 0.85, 0.5, 0.42, col, metal, rough)

		"cyl":
			# Tank mit gewölbten Enden (Kapselprofil), schön metallisch.
			var tank := _revolve(_capsule_profile(), 22)
			root.add_child(_mi(tank, make_material(col, metal, rough), Vector3.ZERO,
				Vector3.ZERO, size))

		"nose":
			# Glatte paraboloide Ogive. Standard: Spitze nach vorne (-Z),
			# reverse = Spitze nach hinten (Heckkonus).
			var og := _revolve(_ogive_profile(p.get("reverse", false)), 24)
			root.add_child(_mi(og, make_material(col, metal, rough), Vector3.ZERO,
				Vector3.ZERO, size))

		"cockpit":
			# Runder Rumpf-Körper, vorne leicht verjüngt (verrundet).
			var cbody := _revolve([
				Vector2(-0.5, 0.4), Vector2(-0.42, 0.48), Vector2(-0.2, 0.5),
				Vector2(0.46, 0.5), Vector2(0.5, 0.49)
			], 20)
			root.add_child(_mi(cbody, make_material(col, metal, rough), Vector3.ZERO,
				Vector3.ZERO, size))
			# Blasen-Kanzel (halb eingelassene Glaskuppel).
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 24
			sm.rings = 12
			var glass := make_material(Color(0.13, 0.24, 0.4), 0.1, 0.05)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.albedo_color.a = 0.6
			glass.rim_enabled = true
			glass.rim = 0.6
			root.add_child(_mi(sm, glass, Vector3(0, size.y * 0.32, -size.z * 0.06),
				Vector3.ZERO, Vector3(size.x * 0.62, size.y * 0.7, size.z * 0.92)))

		"prop":
			# Gondel als runder Tubus, hinten verrundet.
			var nac := _revolve([
				Vector2(-0.5, 0.5), Vector2(0.34, 0.5), Vector2(0.46, 0.42), Vector2(0.5, 0.28)
			], 20)
			root.add_child(_mi(nac, make_material(col, metal, rough), Vector3(0, 0, size.z * 0.08),
				Vector3.ZERO, Vector3(size.x * 0.68, size.x * 0.68, size.z * 0.72)))
			# Spinner vorne (glatte Ogive, Spitze nach -Z).
			var spin := _revolve(_ogive_profile(false), 20)
			root.add_child(_mi(spin, make_material(Color(0.72, 0.12, 0.1), 0.5, 0.4),
				Vector3(0, 0, -size.z * 0.44), Vector3.ZERO,
				Vector3(size.x * 0.36, size.x * 0.36, size.x * 0.55)))
			# Propeller (dreht sich im Flug) — getwistete, sich verjüngende Blätter.
			var prop := Node3D.new()
			prop.name = "Prop"
			prop.position = Vector3(0, 0, -size.z * 0.52)
			var blade_mat := make_material(Color(0.08, 0.08, 0.09), 0.25, 0.5)
			var blade_len: float = size.x * 1.05
			for i in 3:
				var holder := Node3D.new()
				holder.rotation = Vector3(0, 0, deg_to_rad(120.0 * i))
				# Blatt: lang in Y (radial), dünn, mit Anstellwinkel (Twist um Y).
				var bbm := BoxMesh.new()
				bbm.size = Vector3(0.055, blade_len, 0.18)
				var blade := _mi(bbm, blade_mat, Vector3(0, blade_len * 0.5, 0),
					Vector3(0, deg_to_rad(22), 0))
				holder.add_child(blade)
				prop.add_child(holder)
			root.add_child(prop)
			# durchscheinende Propeller-Scheibe (Bewegungsunschärfe-Look)
			var dm := CylinderMesh.new()
			dm.top_radius = blade_len
			dm.bottom_radius = blade_len
			dm.height = 0.02
			dm.radial_segments = 24
			var dmat := make_material(Color(0.5, 0.5, 0.55), 0.1, 0.6)
			dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			dmat.albedo_color.a = 0.12
			dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
			dm.material = dmat
			root.add_child(_mi(dm, null, Vector3(0, 0, -size.z * 0.54), Vector3(PI * 0.5, 0, 0)))

		"jet":
			# Triebwerksgondel als runder Tubus (vorne/hinten leicht verrundet).
			var jbody := _revolve([
				Vector2(-0.5, 0.45), Vector2(-0.44, 0.5), Vector2(0.4, 0.5), Vector2(0.5, 0.42)
			], 22)
			root.add_child(_mi(jbody, make_material(col, metal, rough), Vector3.ZERO,
				Vector3.ZERO, Vector3(size.x, size.x, size.z)))
			# Einlauf-Lippe (Torus) vorne
			var lip := TorusMesh.new()
			lip.inner_radius = size.x * 0.4
			lip.outer_radius = size.x * 0.52
			lip.rings = 26
			lip.ring_segments = 12
			root.add_child(_mi(lip, make_material(Color(0.2, 0.21, 0.24), 0.75, 0.3),
				Vector3(0, 0, -size.z * 0.5), Vector3(PI * 0.5, 0, 0)))
			# dunkler Einlauf-Innenraum
			var face := CylinderMesh.new()
			face.top_radius = size.x * 0.4
			face.bottom_radius = size.x * 0.4
			face.height = 0.04
			root.add_child(_mi(face, make_material(Color(0.03, 0.03, 0.04), 0.2, 0.7),
				Vector3(0, 0, -size.z * 0.45), Vector3(PI * 0.5, 0, 0)))
			# Schubdüse hinten (konvergent)
			var noz := _revolve([
				Vector2(-0.5, 0.5), Vector2(0.2, 0.46), Vector2(0.5, 0.34)
			], 20)
			root.add_child(_mi(noz, make_material(Color(0.22, 0.22, 0.24), 0.7, 0.3),
				Vector3(0, 0, size.z * 0.5), Vector3.ZERO,
				Vector3(size.x, size.x, size.z * 0.22)))
			# Nachbrenner-Glühen
			var glow := CylinderMesh.new()
			glow.top_radius = size.x * 0.3
			glow.bottom_radius = size.x * 0.3
			glow.height = 0.04
			var em := make_material(Color(0.7, 0.3, 0.1), 0.3, 0.4)
			em.emission_enabled = true
			em.emission = Color(1.0, 0.45, 0.12)
			em.emission_energy_multiplier = 1.3
			root.add_child(_mi(glow, em, Vector3(0, 0, size.z * 0.6), Vector3(PI * 0.5, 0, 0)))

		"wheel":
			# Reifen als runder Torus (Achse entlang X), Felge + Nabe + Federbein.
			var r: float = size.z * 0.5
			var wpos := Vector3(0, -size.y * 0.5 + r, 0)
			var tire_w: float = size.x * 0.5
			var tire := TorusMesh.new()
			tire.inner_radius = r * 0.52
			tire.outer_radius = r
			tire.rings = 24
			tire.ring_segments = 14
			# Torus liegt in XZ (Loch-Achse Y); 90° um Z -> Loch-Achse X (Raddrehachse).
			root.add_child(_mi(tire, make_material(col, 0.05, 0.9),
				wpos, Vector3(0, 0, PI * 0.5)))
			# Felge/Radscheibe (metallisch)
			var rim := CylinderMesh.new()
			rim.top_radius = r * 0.56
			rim.bottom_radius = r * 0.56
			rim.height = tire_w * 0.7
			rim.radial_segments = 20
			root.add_child(_mi(rim, make_material(Color(0.7, 0.72, 0.78), 0.85, 0.3),
				wpos, Vector3(0, 0, PI * 0.5)))
			# Nabe
			var hub := CylinderMesh.new()
			hub.top_radius = r * 0.2
			hub.bottom_radius = r * 0.2
			hub.height = tire_w * 1.02
			root.add_child(_mi(hub, make_material(Color(0.3, 0.31, 0.34), 0.8, 0.35),
				wpos, Vector3(0, 0, PI * 0.5)))
			# Federbein (rundes Standrohr) + Achsschenkel
			var leg := _revolve(_capsule_profile(), 12)
			root.add_child(_mi(leg, make_material(Color(0.55, 0.57, 0.62), 0.8, 0.35),
				Vector3(0, size.y * 0.12, 0), Vector3(PI * 0.5, 0, 0),
				Vector3(0.16, 0.16, size.y * 0.72)))

		"missile":
			# Flugkörper: spitze Nase (-Z) -> Körper -> verjüngtes Heck, + Finnen + Düse.
			# Lenkraketen (weapon "missile…") bekommen einen Glas-Suchkopf an der Spitze.
			var guided: bool = String(p.get("weapon", "")).begins_with("missile")
			var mbody := _revolve([
				Vector2(-0.5, 0.0), Vector2(-0.42, 0.24), Vector2(-0.3, 0.42),
				Vector2(-0.12, 0.5), Vector2(0.4, 0.5), Vector2(0.5, 0.34)
			], 20)
			root.add_child(_mi(mbody, make_material(col, metal, rough), Vector3.ZERO, Vector3.ZERO, size))
			# Mittel-Band (Akzent)
			var bandr := CylinderMesh.new()
			bandr.top_radius = size.x * 0.52; bandr.bottom_radius = size.x * 0.52
			bandr.height = size.z * 0.04; bandr.radial_segments = 18
			root.add_child(_mi(bandr, make_material(col.darkened(0.4), metal, rough),
				Vector3(0, 0, -size.z * 0.05), Vector3(PI * 0.5, 0, 0)))
			if guided:
				var dome := SphereMesh.new()
				dome.radius = size.x * 0.4; dome.height = size.x * 0.8
				var gmat := make_material(Color(0.1, 0.16, 0.26), 0.3, 0.1)
				gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				gmat.albedo_color.a = 0.8
				gmat.rim_enabled = true; gmat.rim = 0.6
				root.add_child(_mi(dome, gmat, Vector3(0, 0, -size.z * 0.46)))
			# Düse hinten (+Z)
			var noz := CylinderMesh.new()
			noz.top_radius = size.x * 0.34; noz.bottom_radius = size.x * 0.22
			noz.height = size.z * 0.1; noz.radial_segments = 16
			root.add_child(_mi(noz, make_material(Color(0.08, 0.08, 0.09), 0.6, 0.5),
				Vector3(0, 0, size.z * 0.5), Vector3(PI * 0.5, 0, 0)))
			# 4 Finnen hinten (kreuzförmig)
			var fmat := make_material(col.darkened(0.4), metal, rough)
			for i in 4:
				var fin := BoxMesh.new()
				fin.size = Vector3(size.x * 0.55, 0.028, size.z * 0.22)
				var holder := Node3D.new()
				holder.rotation = Vector3(0, 0, deg_to_rad(45.0 + 90.0 * i))
				holder.add_child(_mi(fin, fmat, Vector3(size.x * 0.44, 0, size.z * 0.4)))
				root.add_child(holder)

		"bomb":
			# Tropfen-Körper + Kreuz-Leitwerk + Heckring + Aufhänge-Öse.
			var bb := _revolve([
				Vector2(-0.5, 0.16), Vector2(-0.4, 0.38), Vector2(-0.18, 0.5),
				Vector2(0.2, 0.5), Vector2(0.42, 0.34), Vector2(0.5, 0.18)
			], 20)
			root.add_child(_mi(bb, make_material(col, metal, rough), Vector3.ZERO, Vector3.ZERO, size))
			var bfmat := make_material(col.darkened(0.3), metal, rough)
			for i in 4:
				var fin := BoxMesh.new()
				fin.size = Vector3(size.x * 0.62, 0.03, size.z * 0.26)
				var holder := Node3D.new()
				holder.rotation = Vector3(0, 0, deg_to_rad(45.0 + 90.0 * i))
				holder.add_child(_mi(fin, bfmat, Vector3(size.x * 0.44, 0, size.z * 0.42)))
				root.add_child(holder)
			var ring := TorusMesh.new()
			ring.inner_radius = size.x * 0.32; ring.outer_radius = size.x * 0.42
			ring.rings = 24
			root.add_child(_mi(ring, bfmat, Vector3(0, 0, size.z * 0.5), Vector3(PI * 0.5, 0, 0)))
			var lug := BoxMesh.new()
			lug.size = Vector3(size.x * 0.1, size.y * 0.2, size.z * 0.12)
			root.add_child(_mi(lug, bfmat, Vector3(0, size.y * 0.52, -size.z * 0.05)))

		"cannon":
			# Geschütz: Verschluss-Block (+Z) + Lauf (-Z) + Mündung(-sbremse) + Zuführung oben.
			var gunmetal := make_material(Color(0.12, 0.12, 0.14), 0.85, 0.3)
			var housemat := make_material(col, metal, rough)
			var house := BoxMesh.new()
			house.size = Vector3(size.x * 0.94, size.y * 0.94, size.z * 0.4)
			root.add_child(_mi(house, housemat, Vector3(0, 0, size.z * 0.28)))
			var barrel := CylinderMesh.new()
			barrel.top_radius = size.x * 0.2; barrel.bottom_radius = size.x * 0.2
			barrel.height = size.z * 0.78; barrel.radial_segments = 16
			root.add_child(_mi(barrel, gunmetal, Vector3(0, 0, -size.z * 0.12), Vector3(PI * 0.5, 0, 0)))
			var big: bool = size.x > 0.45    # Auto-/Schwere Kanone -> dickere Mündungsbremse
			var muzzle := CylinderMesh.new()
			muzzle.top_radius = size.x * (0.32 if big else 0.26)
			muzzle.bottom_radius = muzzle.top_radius
			muzzle.height = size.z * (0.16 if big else 0.1); muzzle.radial_segments = 16
			root.add_child(_mi(muzzle, gunmetal, Vector3(0, 0, -size.z * 0.46), Vector3(PI * 0.5, 0, 0)))
			var feed := BoxMesh.new()
			feed.size = Vector3(size.x * 0.36, size.y * 0.42, size.z * 0.32)
			root.add_child(_mi(feed, housemat, Vector3(0, size.y * 0.5, size.z * 0.22)))

		"pod":
			# Raketenwerfer-Pod: Röhre mit 7 Abschussrohren (1 Mitte + 6 außen) an der Front (-Z).
			var podbody := _revolve([
				Vector2(-0.5, 0.42), Vector2(-0.46, 0.5), Vector2(0.46, 0.5), Vector2(0.5, 0.44)
			], 22)
			root.add_child(_mi(podbody, make_material(col, metal, rough), Vector3.ZERO, Vector3.ZERO, size))
			var tubemat := make_material(Color(0.05, 0.05, 0.06), 0.5, 0.6)
			var tubepos := [Vector2.ZERO]
			for k in 6:
				tubepos.append(Vector2(cos(TAU * k / 6.0), sin(TAU * k / 6.0)) * 0.28)
			for tp in tubepos:
				var tube := CylinderMesh.new()
				tube.top_radius = size.x * 0.12; tube.bottom_radius = size.x * 0.12
				tube.height = size.z * 0.55; tube.radial_segments = 12
				root.add_child(_mi(tube, tubemat,
					Vector3(tp.x * size.x, tp.y * size.y, -size.z * 0.22), Vector3(PI * 0.5, 0, 0)))

		_:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm
			mi.material_override = make_material(col, metal, rough)
			root.add_child(mi)

	return root


# Lädt ein Blender-glTF-Modell und hängt es unter root. Beim Lackieren werden
# die Haupt-Materialien (PAINT_MATS) auf die Wunschfarbe gesetzt; Akzente (Glas,
# Spinner, Gummi, Auspuff-Glühen ...) bleiben. Der "Prop"-Knoten bleibt erhalten
# (FlightController dreht ihn im Flug).
static func _attach_model(root: Node3D, id: String, col_override: Color) -> void:
	var ps: Resource = load(MODEL_DIR + id + ".glb")
	if ps == null or not (ps is PackedScene):
		return
	var inst: Node = (ps as PackedScene).instantiate()
	root.add_child(inst)
	if col_override.a > 0.0:                 # nur bei Lackierung umfärben
		_recolor_model(inst, col_override)
	_tone_model_accents(inst)               # zu grelle Chrom-Akzente (Federbein-Kolben) dämpfen


# Dämpft im glTF gebackene, spiegelglatte Chrom-Akzente (z. B. das polierte
# Federbein-Kolben-Material "piston"), die unter starkem Licht weiß ausbrennen und
# wie ein fehlplatzierter weißer Würfel wirken. Brüniertes Metall statt Spiegel.
static func _tone_model_accents(node: Node) -> void:
	for ch in node.get_children():
		_tone_model_accents(ch)
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			return
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is StandardMaterial3D and (m as StandardMaterial3D).resource_name == "piston":
				var dup: StandardMaterial3D = m.duplicate()
				dup.albedo_color = Color(0.50, 0.51, 0.55)
				dup.metallic = 0.6
				dup.roughness = 0.45
				mi.set_surface_override_material(i, dup)
			elif m is StandardMaterial3D and (m as StandardMaterial3D).resource_name == "ductdark":
				# Lufteinlauf-Schacht: BEIDSEITIG (sonst sieht man durch die abgewandte Wand auf
				# den Rumpf) + matt tiefschwarz, damit es als echtes dunkles Loch liest.
				var dd: StandardMaterial3D = m.duplicate()
				dd.cull_mode = BaseMaterial3D.CULL_DISABLED
				dd.albedo_color = Color(0.02, 0.02, 0.025)
				dd.metallic = 0.0
				dd.roughness = 1.0
				dd.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mi.set_surface_override_material(i, dd)
			elif m is StandardMaterial3D and (m as StandardMaterial3D).resource_name == "ductsplit":
				var ds: StandardMaterial3D = m.duplicate()
				ds.cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.set_surface_override_material(i, ds)


static func _recolor_model(node: Node, col: Color) -> void:
	for ch in node.get_children():
		_recolor_model(ch, col)
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			return
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is StandardMaterial3D and PAINT_MATS.has(m.resource_name):
				var dup: StandardMaterial3D = m.duplicate()
				dup.albedo_color = col
				mi.set_surface_override_material(i, dup)


# ---------------------------------------------------------------------------
# Tragflächen-Mesh (Trapez mit Pfeilung), Spannweite entlang +X, Sehne entlang Z
# ---------------------------------------------------------------------------
# Bewegliche Hinterkanten-Fläche (Klappe/Ruder): Scharnier-Node an der Hinterkante (lokal +Z),
# schwenkt im Flug um die lokale X-Achse (Spannweite). AircraftBody animiert es.
#   sfrac = Anteil der Spannweite, cfrac = Mitte (Anteil Spannweite), chfrac = Sehnenanteil.
static func _trailing_panel(root: Node3D, p: Dictionary, hinge_name: String,
		sfrac: float, cfrac: float, chfrac: float, col: Color, metal: float, rough: float) -> void:
	var span: float = p.get("span", 4.0)
	var rc: float = p.get("root_chord", 1.5)
	var sweep: float = p.get("sweep", 0.0)
	var ssp: float = span * sfrac
	var sx: float = span * cfrac
	var fchord: float = rc * chfrac
	var cz: float = lerpf(0.0, sweep, sx / maxf(span, 0.01))
	var te: float = cz + rc * 0.5                 # Hinterkante (lokal +Z)
	var hinge := Node3D.new()
	hinge.name = hinge_name
	hinge.position = Vector3(sx, 0.0, te - fchord)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(ssp, 0.06, fchord)
	mi.mesh = bm
	mi.position = Vector3(0, 0, fchord * 0.5)     # Panel hinter dem Scharnier (+Z)
	mi.material_override = make_material(col.darkened(0.14), metal, rough)
	hinge.add_child(mi)
	root.add_child(hinge)


static func _wing_mesh(span: float, rc: float, tc: float, sweep: float, _thick: float,
		camber := 0.018) -> ArrayMesh:
	# GEWÖLBTES Profil (NACA-Dickenverteilung + Mittellinien-Wölbung -> gewölbte
	# Oberseite statt flacher Platte) von der Wurzel zur GERUNDETEN, leicht
	# nach hinten gepfeilten Spitze gelofted. Mehr Spannweiten-Stationen +
	# dichter Profilrundgang -> weiche, volle Optik statt Papierdreieck.
	# camber = max. Wölbung (Sehnenanteil); 0 für symmetrische Leitwerke.
	# Profilrundgang: f = Sehnenanteil (0 Nase .. 1 Hinterkante), side: +oben/-unten
	var prof := [
		[0.0, 0.0], [0.02, 1.0], [0.05, 1.0], [0.10, 1.0], [0.18, 1.0], [0.28, 1.0],
		[0.40, 1.0], [0.55, 1.0], [0.70, 1.0], [0.85, 1.0], [0.94, 1.0], [1.0, 0.0],
		[0.94, -1.0], [0.85, -1.0], [0.70, -1.0], [0.55, -1.0], [0.40, -1.0],
		[0.28, -1.0], [0.18, -1.0], [0.10, -1.0], [0.05, -1.0], [0.02, -1.0],
	]
	var m := prof.size()
	# Spannweiten-Stationen: zur Spitze hin dichter (rundet das Tip glatt aus)
	var us := [0.0, 0.20, 0.40, 0.60, 0.78, 0.88, 0.95, 1.0]
	var tip0 := 0.78                       # ab hier beginnt die Spitzen-Rundung
	var tratio := 0.12
	var cpos := 0.40                       # Position max. Wölbung (40 % Sehne)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in us.size():
		var u: float = us[s]
		var base_chord: float = lerpf(rc, tc, u)
		var chord := base_chord
		var rake := 0.0
		if u > tip0:
			# Spitze: Sehne entlang einer Viertelellipse einziehen (rund, kein
			# scharfer Zipfel) + leicht nach hinten pfeilen (gerundetes Rakentip).
			var lt: float = (u - tip0) / (1.0 - tip0)        # 0..1 über das Tip-Segment
			var ellipt: float = sqrt(maxf(1.0 - lt * lt, 0.0))   # Viertelellipse 1..0
			chord = lerpf(maxf(tc * 0.18, 0.12), base_chord, ellipt)
			rake = lt * base_chord * 0.32
		var cx: float = u * span
		var cz: float = lerpf(0.0, sweep, u) + rake
		for i in m:
			var f: float = prof[i][0]
			var yt: float = _airfoil_y(f, tratio) * chord
			var yc: float = _camber_y(f, camber, cpos) * chord
			st.add_vertex(Vector3(cx, yc + prof[i][1] * yt, (cz - chord * 0.5) + f * chord))
	for s in us.size() - 1:
		var b0 := s * m
		var b1 := (s + 1) * m
		for i in m:
			var j := (i + 1) % m
			st.add_index(b0 + i); st.add_index(b1 + i); st.add_index(b1 + j)
			st.add_index(b0 + i); st.add_index(b1 + j); st.add_index(b0 + j)
	var lb := (us.size() - 1) * m
	for i in range(1, m - 1):       # Spitzen-Kappe
		st.add_index(lb); st.add_index(lb + i); st.add_index(lb + i + 1)
	for i in range(1, m - 1):       # Wurzel-Kappe
		st.add_index(0); st.add_index(i + 1); st.add_index(i)
	st.generate_normals()
	return st.commit()


static func _airfoil_y(f: float, t: float) -> float:
	f = clampf(f, 0.0, 1.0)
	return (t / 0.2) * (0.2969 * sqrt(f) - 0.1260 * f - 0.3516 * f * f + 0.2843 * f * f * f - 0.1015 * f * f * f * f)


# NACA-Mittellinien-Wölbung: m = max. Wölbung (Sehnenanteil), p = deren Position.
# Hebt die Oberseite an / senkt die Unterseite -> der Flügel wirkt voll statt flach.
static func _camber_y(f: float, m: float, p: float) -> float:
	if m <= 0.0:
		return 0.0
	f = clampf(f, 0.0, 1.0)
	if f < p:
		return m / (p * p) * (2.0 * p * f - f * f)
	return m / ((1.0 - p) * (1.0 - p)) * ((1.0 - 2.0 * p) + 2.0 * p * f - f * f)


# ---------------------------------------------------------------------------
# Rotationskörper um die Z-Achse. profile = Array[Vector2(z, radius)], radius>=0.
# Enden mit radius>0 werden flach gedeckelt. Outward gewickelt, glatte Normalen.
# Als EINHEITSform gedacht (r<=0.5, z in [-0.5,0.5]) und per Node-Skalierung gezogen.
# ---------------------------------------------------------------------------
static func _revolve(profile: Array, segs := 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var stride := segs + 1
	for ring in n:
		var z: float = profile[ring].x
		var rad: float = profile[ring].y
		for s in stride:
			var a: float = TAU * float(s) / float(segs)
			st.add_vertex(Vector3(cos(a) * rad, sin(a) * rad, z))
	for ring in n - 1:
		for s in segs:
			var i0 := ring * stride + s
			var i1 := ring * stride + s + 1
			var i2 := (ring + 1) * stride + s
			var i3 := (ring + 1) * stride + s + 1
			# Wicklung nach AUSSEN (sonst sind Nase/Heck/Tank inside-out)
			st.add_index(i0); st.add_index(i2); st.add_index(i1)
			st.add_index(i1); st.add_index(i2); st.add_index(i3)
	var verts := n * stride
	if float(profile[0].y) > 0.001:                  # vorderer Deckel (-Z)
		st.add_vertex(Vector3(0, 0, profile[0].x))
		var c0 := verts
		verts += 1
		for s in segs:
			st.add_index(c0); st.add_index(s); st.add_index(s + 1)
	if float(profile[n - 1].y) > 0.001:              # hinterer Deckel (+Z)
		st.add_vertex(Vector3(0, 0, profile[n - 1].x))
		var cn := verts
		var rb := (n - 1) * stride
		for s in segs:
			st.add_index(cn); st.add_index(rb + s + 1); st.add_index(rb + s)
	st.generate_normals()
	return st.commit()


# Gechinter F-22-Rumpf-Querschnitt (normiert auf ±0.5, Flugrichtung -Z). Wird vom Kopf-Modell
# (Blender) UND vom prozeduralen "prism"-Rumpf geteilt -> beide docken bündig aneinander.
static func _f22_cross_section() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-0.30, 0.50), Vector2(0.30, 0.50),     # flaches Dach (Spine)
		Vector2(0.50, 0.06),                            # rechte Chine (breiteste Stelle)
		Vector2(0.32, -0.50), Vector2(-0.32, -0.50),    # flacher Unterboden
		Vector2(-0.50, 0.06),                           # linke Chine
	])


# Querschnitt entlang Z extrudieren (unit ±0.5). Vorderes (-Z) Ende × ef=(x,y),
# hinteres (+Z) × eb=(x,y) -> beide Enden in X UND Y getrennt skalierbar (Frustum).
# FLACHE Facetten = gechintes Stealth-Aussehen.
static func _prism_mesh(cs: PackedVector2Array, ef: Vector2, eb: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := cs.size()
	var zf := -0.5
	var zb := 0.5
	for i in n:                                         # Seitenfacetten (Trapeze)
		var j := (i + 1) % n
		var f0 := Vector3(cs[i].x * ef.x, cs[i].y * ef.y, zf)
		var f1 := Vector3(cs[j].x * ef.x, cs[j].y * ef.y, zf)
		var b0 := Vector3(cs[i].x * eb.x, cs[i].y * eb.y, zb)
		var b1 := Vector3(cs[j].x * eb.x, cs[j].y * eb.y, zb)
		var mid := (f0 + f1 + b0 + b1) * 0.25
		var outward := Vector3(mid.x, mid.y, 0.0).normalized()
		_face(st, f0, f1, b1, outward)
		_face(st, f0, b1, b0, outward)
	var cf := Vector3(0, 0, zf)
	var cb := Vector3(0, 0, zb)
	for i in n:                                         # Deckel vorne (-Z) / hinten (+Z)
		var j := (i + 1) % n
		_face(st, cf, Vector3(cs[i].x * ef.x, cs[i].y * ef.y, zf), Vector3(cs[j].x * ef.x, cs[j].y * ef.y, zf), Vector3(0, 0, -1))
		_face(st, cb, Vector3(cs[i].x * eb.x, cs[i].y * eb.y, zb), Vector3(cs[j].x * eb.x, cs[j].y * eb.y, zb), Vector3(0, 0, 1))
	return st.commit()


# Elliptischer Rumpf-Tubus entlang Z (leicht gerundete Enden). Vorderes (-Z) Ende
# Querschnitt × ef=(x,y), hinteres (+Z) × eb=(x,y) -> X UND Y pro Ende getrennt.
static func _box_tube(ef: Vector2, eb: Vector2, segs := 18) -> ArrayMesh:
	var prof := [Vector2(-0.5, 0.49), Vector2(-0.46, 0.5), Vector2(0.46, 0.5), Vector2(0.5, 0.49)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := prof.size()
	var stride := segs + 1
	for ring in n:
		var z: float = prof[ring].x
		var rad: float = prof[ring].y
		var t: float = z + 0.5                          # 0 vorne (-Z) .. 1 hinten (+Z)
		var sx: float = lerp(ef.x, eb.x, t)
		var sy: float = lerp(ef.y, eb.y, t)
		for s in stride:
			var a: float = TAU * float(s) / float(segs)
			st.add_vertex(Vector3(cos(a) * rad * sx, sin(a) * rad * sy, z))
	for ring in n - 1:
		for s in segs:
			var i0 := ring * stride + s
			var i1 := ring * stride + s + 1
			var i2 := (ring + 1) * stride + s
			var i3 := (ring + 1) * stride + s + 1
			# Wicklung so, dass die Normalen NACH AUSSEN zeigen (sonst Rumpf inside-out)
			st.add_index(i0); st.add_index(i2); st.add_index(i1)
			st.add_index(i1); st.add_index(i2); st.add_index(i3)
	var verts := n * stride
	st.add_vertex(Vector3(0, 0, prof[0].x))             # Deckel vorne (-Z)
	var c0 := verts
	verts += 1
	for s in segs:
		st.add_index(c0); st.add_index(s); st.add_index(s + 1)
	st.add_vertex(Vector3(0, 0, prof[n - 1].x))         # Deckel hinten (+Z)
	var cn := verts
	var rb := (n - 1) * stride
	for s in segs:
		st.add_index(cn); st.add_index(rb + s + 1); st.add_index(rb + s)
	st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------------------
# LOFT-RUMPF-SYSTEM: berechnet EINE durchgehende Rumpfhaut aus Querschnitt-Stationen.
# Statt mehrere Segmente zu überlappen (-> Nähte/Z-Fighting) entsteht so EINE einzige
# glatte Fläche über die ganze Länge. Jede Station = Vector4(z, halbbreite, halbhöhe,
# höhen-offset_cy). Smooth-Normalen -> komplett nahtlos.
static func _loft(stations: Array, segs := 32, cap_front := false, cap_back := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := stations.size()
	var stride := segs + 1
	for ring in n:
		var s4: Vector4 = stations[ring]
		for k in stride:
			var a: float = TAU * float(k) / float(segs)
			st.add_vertex(Vector3(cos(a) * s4.y, s4.w + sin(a) * s4.z, s4.x))
	for ring in n - 1:
		for k in segs:
			var i0 := ring * stride + k
			var i1 := ring * stride + k + 1
			var i2 := (ring + 1) * stride + k
			var i3 := (ring + 1) * stride + k + 1
			st.add_index(i0); st.add_index(i2); st.add_index(i1)
			st.add_index(i1); st.add_index(i2); st.add_index(i3)
	var verts := n * stride
	if cap_front:
		var f: Vector4 = stations[0]
		st.add_vertex(Vector3(0, f.w, f.x))
		var c0 := verts; verts += 1
		for k in segs:
			st.add_index(c0); st.add_index(k); st.add_index(k + 1)
	if cap_back:
		var b: Vector4 = stations[n - 1]
		st.add_vertex(Vector3(0, b.w, b.x))
		var cn := verts
		var rb := (n - 1) * stride
		for k in segs:
			st.add_index(cn); st.add_index(rb + k + 1); st.add_index(rb + k)
	st.generate_normals()
	return st.commit()


# Baut EINEN gelofteten Rumpf-ABSCHNITT aus p["stations"] + Aufsätze: Lufteinlauf vorn
# (Lippe + matt-schwarzer Schacht + Teiler), Bubble-Kanzel oben, Heck-Düsenkappe.
# ef/eb = Front-/Heck-Skalierung (taper_front/taper) -> Enden in X/Y verjüngen. So kann
# EIN generisches Segment gerade (taper 1) ODER als Heckkonus (taper < 1) verwendet werden.
# Ein verjüngtes Heck (eb < 0.9) bekommt automatisch eine dunkle Düsenkappe; gerade Enden
# bleiben OFFEN -> stoßbündig (gleicher Querschnitt) an den Nachbarn, ohne Überlappung.
static func _jet_hull(root: Node3D, p: Dictionary, col: Color, metal: float, rough: float,
		ef := Vector2.ONE, eb := Vector2.ONE) -> void:
	var raw: Array = p.get("stations", [])
	if raw.size() < 2:
		return
	# Stationen über die Länge per ef/eb skalieren (vorne -> hinten interpolieren).
	var zmin: float = raw[0].x
	var zmax: float = raw[raw.size() - 1].x
	var span: float = maxf(zmax - zmin, 0.0001)
	var stations: Array = []
	for s in raw:
		var t: float = (s.x - zmin) / span
		var sx: float = lerp(ef.x, eb.x, t)
		var sy: float = lerp(ef.y, eb.y, t)
		stations.append(Vector4(s.x, s.y * sx, s.z * sy, s.w * sy))
	var body_mat := make_material(col, metal, rough)
	root.add_child(_mi(_loft(stations, 36), body_mat))
	var first: Vector4 = stations[0]
	var last: Vector4 = stations[stations.size() - 1]
	if p.get("intake", false):
		var z0: float = first.x; var hw: float = first.y; var hh: float = first.z; var cy: float = first.w
		# DÜNNE Lippe, nur leicht nach innen gerundet (kein vorstehender Ring, matt -> kein
		# Spiegel-„Heiligenschein") -> WEITE Öffnung: man sieht tief in den Schacht, auch
		# schräg von der Seite (beide Hälften sichtbar).
		var lipmat := make_material(col, 0.10, 0.55)
		root.add_child(_mi(_loft([
			Vector4(z0, hw, hh, cy),
			Vector4(z0 + 0.05, hw - 0.045, hh - 0.04, cy)], 36), lipmat))
		# Weiter, tiefer matt-schwarzer Schacht (kaum verjüngt -> offener Kanal mit Tiefe)
		var dark := make_material(Color(0.02, 0.02, 0.025), 0.0, 1.0)
		dark.cull_mode = BaseMaterial3D.CULL_DISABLED
		root.add_child(_mi(_loft([
			Vector4(z0 + 0.05, hw - 0.045, hh - 0.04, cy),
			Vector4(z0 + 0.75, hw - 0.09, hh - 0.08, cy),
			Vector4(z0 + 1.65, hw - 0.16, hh - 0.15, cy)], 36, false, true), dark))
		# (Kein senkrechter Teiler mehr — sah als Objekt im Loch deplatziert aus. Sauberer,
		# tiefer, runder Einlauf wie bei den meisten MiG-15-Darstellungen.)
	var can: Array = p.get("canopy", [])
	if can.size() >= 5:
		var zc: float = can[0]; var ln: float = can[1]; var cw: float = can[2]; var chh: float = can[3]; var base: float = can[4]
		var glass := make_material(Color(0.03, 0.03, 0.035), 0.30, 0.08)
		root.add_child(_mi(_loft([
			Vector4(zc - ln * 0.52, 0.05, 0.04, base + 0.02),
			Vector4(zc - ln * 0.22, cw * 0.82, chh * 0.80, base + chh * 0.55),
			Vector4(zc + ln * 0.04, cw, chh, base + chh * 0.62),
			Vector4(zc + ln * 0.32, cw * 0.80, chh * 0.74, base + chh * 0.50),
			Vector4(zc + ln * 0.52, 0.05, 0.04, base + 0.02)], 32, true, true), glass))
	# Heck-Düsenkappe: explizit (rear_cap) ODER automatisch bei verjüngtem Heck (Heckkonus).
	if p.get("rear_cap", false) or eb.x < 0.9:
		var rmat := make_material(Color(0.05, 0.05, 0.06), 0.3, 0.4)
		root.add_child(_mi(_loft([
			Vector4(last.x, last.y, last.z, last.w),
			Vector4(last.x + 0.06, last.y * 0.5, last.z * 0.5, last.w),
			Vector4(last.x + 0.06, 0.05, 0.05, last.w)], 28, false, true), rmat))


# Flaches Dreieck mit korrekter Wicklung: Normale zeigt in want_dir (sonst b/c tauschen).
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want_dir: Vector3) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.dot(want_dir) < 0.0:
		var tmp := b; b = c; c = tmp
		nrm = -nrm
	st.set_normal(nrm); st.add_vertex(a)
	st.set_normal(nrm); st.add_vertex(b)
	st.set_normal(nrm); st.add_vertex(c)


# Ogiven-/Paraboloid-Nasenprofil (Spitze bei -Z). reverse -> Spitze bei +Z.
static func _ogive_profile(reverse: bool) -> Array:
	var pts: Array = []
	var steps := 10
	for i in steps + 1:
		var t: float = float(i) / float(steps)        # 0 = Spitze .. 1 = Basis
		var z: float = -0.5 + t
		var r: float = 0.5 * sqrt(t)                   # paraboloide Rundung
		pts.append(Vector2(z if not reverse else -z, r))
	if reverse:
		pts.reverse()                                  # z wieder aufsteigend
	return pts


# Tank-/Kapselprofil mit gewölbten Enden (Einheits-Radius 0.5, z in [-0.5,0.5]).
static func _capsule_profile() -> Array:
	return [
		Vector2(-0.5, 0.0), Vector2(-0.47, 0.3), Vector2(-0.42, 0.45), Vector2(-0.34, 0.5),
		Vector2(0.34, 0.5), Vector2(0.42, 0.45), Vector2(0.47, 0.3), Vector2(0.5, 0.0),
	]
