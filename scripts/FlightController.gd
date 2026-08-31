## FlightController.gd
## Baut aus einem Design einen fliegenden AircraftBody, übernimmt Steuerung,
## Verfolgerkamera und liefert Telemetrie fürs HUD.
class_name FlightController
extends Node3D

signal hud_changed(data: Dictionary)
signal map_requested                    # M im Flug -> Main öffnet/schließt die Karte

const AIRCRAFT_LAYER := 4
const GROUND_LAYER := 1
const SPAWN := Vector3(0, 2.2, 35.0)

const LOOK_SENS := 0.006        # Maus-Empfindlichkeit fürs Umschauen
const FREE_LOOK_SENS := 0.014   # Free-Look (C): flotter -> voll 360° mit normalem Swipe
const FREE_LOOK_DIST := 14.0    # Free-Look: konstanter Orbit-Radius um die Flugzeug-Mitte
const LOOK_RECENTER := 0.6      # s ohne Mausbewegung -> Kamera schwenkt sanft zurück
const CAM_HEIGHT := 4.5         # Maus-Flug: Kamerahöhe ÜBER dem Flieger = Blickpunkthöhe -> Kamera blickt
                                # exakt entlang der Zielrichtung (Aim-Kreis mittig), Flieger sitzt tief im Bild
const CAM_ZOOM_MIN := 0.45      # Mausrad-Zoom: nächster Abstand (Multiplikator)
const CAM_ZOOM_MAX := 3.0       # ... weitester Abstand
const CAM_ZOOM_STEP := 1.13     # Faktor pro Mausrad-Raste
const CAM_ZOOM_SMOOTH := 7.0    # wie schnell der Zoom dem Ziel folgt (1/s; höher = schneller/härter)
const CAM_SHAKE_DECAY := 2.8    # Kamera-Shake klingt so schnell ab (1/s)
const CAM_SHAKE_POS := 1.1      # Shake-Positionsausschlag (m bei vollem Trauma) — satter Impact
const CAM_SHAKE_ROLL := 0.1     # Shake-Rollausschlag (rad)
const FOV_BASE := 64.0          # Grund-FOV der Verfolgerkamera
const FOV_MAX := 74.0           # bei Highspeed weitet sich das Bild -> spürbares Speed-Gefühl
const FOV_SPEED := 170.0        # Speed (m/s), bei der FOV_MAX erreicht ist
# ZIELZOOM (V halten, wie in War Thunder): OPTISCH KORREKT — das FOV wird verengt UND die
# Kamera im gleichen Verhaeltnis zurueckgesetzt. Nur das FOV zu verengen wuerde das eigene
# Flugzeug genauso mitvergroessern und nichts bringen; erst der groessere Abstand laesst es
# gleich gross erscheinen, waehrend ferne Ziele um FOV_BASE/FOV_ZOOM wachsen.
const FOV_ZOOM := 22.0          # verengtes vertikales FOV bei vollem Zoom (~2.9x)
const ZOOM_RATE := 5.0          # Uebergangsgeschwindigkeit (1/s)
const ZOOM_DIST := 2.2          # Kamera-Abstand x diesem Faktor bei vollem Zoom
const ZOOM_SENS := 0.42         # Maus-Empfindlichkeit bei vollem Zoom (ruhiger zielen)
const BARREL_HOLD := 0.32       # A/D so lange halten -> Fass-Roll (War-Thunder-Stil)
# Landeklappen-Stufen (Taste F): Aus -> Start -> Landung. Wert = Klappenstellung 0..1.
const FLAP_STAGES := [0.0, 0.5, 1.0]
const FLAP_NAMES := ["AUS", "Start", "Landung"]
# Geschütz-Kaliber: Mündungsgeschwindigkeit, Schaden, Lebenszeit, Kadenz (cd),
# Bullet-Drop (m/s² Schwerkraft aufs Geschoss) und Leuchtspur. Schwereres Kaliber =
# langsameres Geschoss + mehr Drop + mehr Schaden + dickere/längere Spur.
const CALIBERS := {
	"mg":         {"speed": 380.0, "dmg": 1.2,  "life": 2.6, "cd": 0.55, "drop": 9.0,  "tcol": Color(1.0, 0.92, 0.45), "tscl": 0.8},
	"gun":        {"speed": 330.0, "dmg": 2.2,  "life": 2.8, "cd": 0.10, "drop": 12.0, "tcol": Color(1.0, 0.82, 0.30), "tscl": 1.0},
	"autocannon": {"speed": 280.0, "dmg": 5.0,  "life": 3.0, "cd": 0.28, "drop": 17.0, "tcol": Color(1.0, 0.60, 0.20), "tscl": 1.4},
	"heavy":      {"speed": 235.0, "dmg": 11.0, "life": 3.4, "cd": 0.85, "drop": 23.0, "tcol": Color(1.0, 0.45, 0.12), "tscl": 1.9},
	"minigun":    {"speed": 360.0, "dmg": 2.4,  "life": 2.8, "cd": 0.045, "drop": 11.0, "tcol": Color(1.0, 0.72, 0.25), "tscl": 1.1},
}
# Minigun (Gatling): dreht erst hoch, feuert dann sehr schnell. Läufe drehen sichtbar mit.
const MINIGUN_SPINUP := 0.75    # s bis volle Drehzahl
const MINIGUN_SPINDOWN := 0.55  # s zum Auslaufen
const MINIGUN_FIRE_SPIN := 0.82 # ab dieser Drehzahl kommen Schüsse
const MINIGUN_MAX_RPS := 46.0   # max. Lauf-Drehrate (rad/s)
# Jede montierte Bombe/Rakete = GENAU 1 Stück. Beim Abfeuern verschwindet das Teil vom Modell
# (queue_detach -> Aero neu). Mehr Munition = mehr Teile anbauen. Geschütze fehlen -> unbegrenzt.
const AMMO := {
	"rocket": 1, "salvo": 1, "missile": 1, "missile_heavy": 1, "missile_drop": 1, "bomb": 1,
}
# Rückstoß-Impuls je Schuss (N·s, entgegen der Mündungsrichtung). Bei ~1200 kg ergibt 1200 ≈ 1 m/s
# Tempoverlust. Schweres Kaliber/Raketen schubsen kräftig, MG nur leicht. Bombe: kein Rückstoß.
const RECOIL := {
	"mg": 180.0, "gun": 320.0, "autocannon": 900.0, "heavy": 2200.0, "minigun": 240.0,
	"rocket": 1500.0, "salvo": 3000.0, "missile": 1300.0, "missile_heavy": 2600.0,
	"missile_drop": 700.0,
}

# --- Maus-Flug (War-Thunder-Stil): Maus zeigt in eine WELTRICHTUNG (360°),
#     das Flugzeug dreht die Nase dorthin (Pursuit). look_yaw/look_pitch = Zielrichtung.
const AIM_LOOK_SENS_BASE := 0.005   # Maus -> Blick-/Zielrichtung (rad pro Pixel), × sens_mult
const AIM_CMD_SLEW := 6.0       # Slew-Limit der kommandierten Richtung (rad/s) — praktisch roh,
								# kappt nur Extrem-Flicks (WT localDirYawPitchRot-Äquivalent)
const AIM_PITCH_CLAMP := 1.52   # Marker-Pitch-Klemme (~87°; echtes 90° ist in Yaw/Pitch singulär)
const INS_KP_H := 2.2           # Instructor: Horizontalfehler -> Bahnrate (1/s)
const INS_KP_V := 2.5           # Instructor: Fehlerwinkel -> Drehrate (1/s, linearer Endanflug)
const AUTH_HEADROOM := 0.95     # Anteil der physisch erreichbaren Drehrate, den der Instructor
								# kommandiert (Rest = Regelreserve der inneren Raten-Schleife).
								# 0.85 -> 0.95: die 15 % Reserve waren nötig, solange die innere
								# Nickschleife reines P war und 43 % Droop hatte — sie musste den
								# Fehler ja erst aufbauen, um Ruderweg zu bekommen. Mit der
								# Vorsteuerung in [F] liefert sie die kommandierte Rate direkt
								# (gemessen Ratentreue 0.89-1.00 statt 0.37-0.99), die Reserve
								# darf also schrumpfen. GEMESSEN mit tools/mf_schlepp.gd beim
								# Ziehen mit 80 % der Zellenrate: Schleppfehler 12.11° -> 7.62°,
								# mf_track-Mittel 43.7° -> 36.7°. Nicht weiter hoch: bei 1.0
								# bliebe dem P-Anteil kein Weg mehr zum Nachkorrigieren.
const ROLL_COORD_MAX := 2.2     # Obergrenze der Rollrate, die die KOORDINIERTE Bank-
								# Kaskade fordern darf (rad/s ≈ 126°/s). Fassrolle,
								# Roll-and-Pull und Tastatur bleiben unberührt.
								# GRUND: mit der Ausroll-Planung besteht der Regler darauf,
								# dass die Fläche waagerecht liegt, wenn die Nase ankommt.
								# Am Ende eines 90°/180°-Flicks schließt der Fehler so
								# schnell, dass die dafür nötige Querlagen-Rücknahme mit
								# VOLLEM Querruder gefahren wird: gemessen (tools/_fein_maxw.gd)
								# 53.5° Querlage im Moment des Einschwingens, danach
								# in_roll = 1.00 und 2.59 rad/s reine Rollrate — über dem
								# Regressions-Gate von tools/mousefly_test.gd (max. Drehrate
								# im eingeschwungenen Zustand < 2.5). Mit 2.2 liegt die
								# erreichte Spitze bei 1.93 und der Flick wird sogar
								# schneller (t99 2.25 -> 2.16 s), weil nur das nutzlose
								# Nachrollen beschnitten wird, nicht das Zielen.
const BANK_AUS_RATE := 0.45     # Ausroll-Planung der Querlage (1/s), Herleitung in [E2]
const AIM_TURN_ACC := 1.5       # angenommene Kurvenraten-Beschleunigung (rad/s²) für die
								# STOPP-PLANUNG der Großkreis-Rate: w = sqrt(2·a·err)
								# bremst die Drehung VOR dem Ziel ab (kein Durchziehen)
const INS_YAW_BETA := 1.2       # Schiebewinkel-Koordination (β -> 0, WT AosPid). 0.8 -> 1.2.
const INS_YAW_AIM := 6.0        # GIER-RATENSCHLEIFE (yaw_track - wb.y). 0.6 -> 6.0 — die
								# größte Einzeländerung dieser Runde, und der Grund, warum
								# die WAAGERECHTE Feinkorrektur überhaupt Autorität hat.
								# WARUM: der Schiebewinkel war nicht Kosmetik, er FRASS die
								# Kurve. GEMESSEN (tools/_fein_bank.gd, 10° seitlich, 143 m/s,
								# Spieler-Design ohne Leitwerk): im Endanflug stand die Zelle
								# 30° quer und drehte trotzdem nur 0.33°/s statt der 1.97°/s,
								# die g·tan(30°)/v hergäbe. Die Bilanz erklärt es vollständig:
								# Auftriebs-Horizontalanteil n·sin φ = 0.41·mg, dagegen die
								# Rumpf-SEITENKRAFT aus β = 1.7° mit sin β·q·Fläche·SIDE =
								# 0.29·mg — netto blieben 0.13·mg = 0.48°/s. Der Bau hat
								# yaw_area = 0, seine Wetterfahne ist also schwach, während
								# DAMP_YAW·apq = 5.12 jede Gierrate bremst: β baut sich im
								# harten Einrollen auf und klingt danach mit ~1.2 s ab —
								# genau die Sekunden, die der Einschwing-Zielwert verlor.
								# Das Ruder hatte die Autorität die ganze Zeit (auth.y =
								# 0.35 rad/s, benutzt wurden 0.03-0.04 von 1.0).
								# WARUM auf die RATE und nicht auf β: β-Rückführung allein
								# (INS_YAW_BETA 4-8) machte t90 zwar schnell (2.79 -> 1.26 s),
								# erzeugte aber einen Dutch-Roll-Grenzzyklus von konstant
								# 0.7° Spitze-Spitze in ALLEN Sprungweiten. (yaw_track - wb.y)
								# dämpft Abweichungen von der KOMMANDIERTEN Rate und bremst
								# die kommandierte Kurve deshalb nicht — der Grenzzyklus
								# verschwindet: bei β=1.2/Rate=6.0 steht pp bei 0.020-0.034°.
								# Sättigung ist unkritisch: yaw_track ist auf yaw_cap ≤ 0.3
								# geklemmt, das Ruder bleibt der Helfer und dominiert nie.
const RNP_OFF := 0.45           # Blende koordinierte Kurve -> Roll-and-Pull: Beginn (rad)
const RNP_ON := 0.9             # ... voll Roll-and-Pull ab hier (rad)
const RNP_ROLL_KP := 4.0        # Roll-and-Pull: Rollrate in die Zugebene (1/s)
const RNP_ROLL_KD := 0.8        # ... Dämpfung auf die phi-Rate (Zugebene pendelt nicht)
const LATCH_ON := 2.6           # Richtungs-Latch an (Gesamtfehler, rad)
const LATCH_OFF := 2.0          # ... und wieder frei
const AOA_MAX := 0.78 * 0.27    # AoA-Limit = 0.78·STALL_A (~12°) — Instructor kann nicht stallen
const AOA_MIN := -0.39 * 0.27   # negatives AoA-Limit (asymmetrisch, wie WT)
const AOA_PUSH := 6.0           # AoA-Limiter-Härte (1/s); über dem Limit: aktives Zurückdrücken
const G_SOFT := 0.75            # G-Limiter: weiches Anschmiegen ab 75 % des Strukturlimits
const G_HARD := 0.92            # ... voll gedeckelt bei 92 % (WT overloadMult-Bereich)
const G_NEG := 0.45             # negatives G-Limit = 45 % des positiven
# Speedabhängige Raten-Tabellen (WT RateMax-Struktur): [v (m/s), rate (rad/s)]
const PITCH_RATE_TAB := [[20.0, 0.9], [60.0, 1.5], [120.0, 1.2], [250.0, 0.8]]
const ROLL_RATE_TAB := [[15.0, 2.2], [60.0, 4.5], [140.0, 4.0], [250.0, 3.0]]
const AIM_DEADZONE := 0.002     # innerer Totbereich (rad) — winzig, damit die Nase EXAKT zentriert
const AIM_DEADZONE_SOFT := 0.008 # äußere Kante: bis hier wird der Fehler weich eingeblendet (kein Knick)
const AIM_TRIM_I := 3.0         # Trim-Integrator auf dem RATENFEHLER (1 / (rad/s) / s): liefert
								# den TRIMM-Ausschlag, den die Zelle zum HALTEN der Nase braucht und
								# den das auth-Modell nicht kennt (gemessen -0.369 im Geradeausflug).
								# Der langsamste Pol der geschlossenen Kette liegt damit bei
								# INS_KP_V·I / (I + INS_KP_V·(1/auth.x + AIM_PITCH_RATE_P))
								# = 7.5/15.1 = 0.5/s, der Versatz baut sich also mit ~2 s ab —
								# nach 9 s sind von 1.743° noch 0.02° übrig (gemessen: 0.018°).
								# Höher wäre möglich (Routh-Hurwitz ist für jedes I > 0 erfüllt),
								# bringt aber nichts mehr und schöbe nur Rauschen in den Trimm.
const AIM_TRIM_MAX := 0.9       # Trim-Klemmung. 0.3 reichten NICHT: das Spieler-Design braucht allein
								# -0.37 Höhenruder, um im Geradeausflug nicht zu steigen (gemessen,
								# tools/_mf_trimm.gd). 0.9 lässt dem P-Anteil immer 10 % Ruderweg für
								# schnelle Ratenwechsel.
const BANK_OFFSET_RATE := 2.2   # A/D-Bank-Offset-Verstellrate (rad/s) im Maus-Flug
const AIM_ROLL_ACC := 6.0       # angenommene Roll-Winkelbeschleunigung (rad/s²) für die Roll-Planung
# Kamera-Blickrichtungs-Glättung (wie Free-Look-Slerp). 12.5 statt 12.0, und das ist
# eine Nachwirkung der Umstellung auf _glatt(): mit der alten Linearisierung
# clampf(delta*12, 0, 1) lag die effektive Zeitkonstante bei 60 Hz bei 74.7 ms, also
# unter der Messlatte von 80 ms — allerdings nur, weil die Naeherung zu weit zog.
# Exponentiell gerechnet sind es exakt 1/12 = 83.3 ms und damit 4 % darueber.
# 12.5 bringt sie auf 80.0 ms zurueck, ohne die Bildratenunabhaengigkeit aufzugeben.
const CAM_AIM_SMOOTH := 12.5
const CAM_LEAD := 0.65          # Geschwindigkeits-Vorhalt der Kamera (0..1): kompensiert den
								# Lerp-Schleppfehler (~v/Rate) größtenteils -> ~35 % bleiben als
								# sichtbares "Zieh"-Gefühl bei Speed (bei 100 m/s ~4-6 m extra)
const UP_BLEND_LO := 0.90       # ab |aim·UP| beginnt die Up-Referenz-Blende (Kamera)
const UP_BLEND_HI := 0.98       # voll auf Flugzeug-Up geblendet -> kein Horizont-Sprung senkrecht
const AIM_BANK_MAX := 1.47      # max. Querlage in Kurven (~84°). WICHTIG: bestimmt via
								# wh_cap = g·tan(BANK)/v die maximale DAUER-Kurvenrate.
								# 72° (tan=3.1) deckelte bei 200 m/s auf 0.16 rad/s (~3 G-
								# Kurve) — der Regler konnte gegen die Roll-Kopplung nicht
								# anhalten und driftete im Messer-Flug (26-37° Overshoot).
								# 84° (tan=9.8) erlaubt die G-Limiter-Kurve (~12 G); echte
								# G begrenzt weiterhin der G-/AoA-Limiter, nicht die Bank.
const AIM_ROLL_P := 2.0         # Rollraten-Fehler -> Roll-Auslenkung (straffe Ratenführung)
const AIM_PITCH_RATE_P := 1.5   # Nickraten-Fehler -> Auslenkung (gut gedämpft, kein Überziehen)
const AIM_YAW_D := 0.3          # Gier-Dämpfung
const AIM_MARK_SMOOTH := 0.5    # Nasenmarker-Pixelglättung (Lerp/Frame)

var camera: Camera3D
var _cam_vfov := FOV_BASE        # geglätteter VERTIKALER FOV (16:9-Bezug; Ultrawide via ViewUtil)
var cam_zoom := 1.0              # geglätteter Mausrad-Zoom im Flug (Abstand-Multiplikator)
var cam_zoom_target := 1.0       # Ziel-Zoom: Mausrad setzt das, cam_zoom folgt weich nach
var zoom_t := 0.0                # 0 = normal, 1 = voll gezoomt (V gehalten)
var aircraft: AircraftBody
var design: Array = []
var throttle := 0.0
var spawn_height := 2.0
var look_yaw := 0.0             # freies Umschauen (Maus) — horizontal
var look_pitch := 0.0           # vertikal
var sens_mult := 1.0            # Maus-Flug-Empfindlichkeit (0.5–2.0, Pause-Menü; persistiert)
var _cam_aim := Vector3(0, 0, -1)   # GEGLÄTTETE Kamera-Blickrichtung im Maus-Flug (gegen Ruckeln)
var _trim_pitch := 0.0          # Nick-Trim-Integrator (Maus-Flug): Nase exakt in der Kreismitte
var _bank_offset := 0.0         # mit A/D gesetzte, GEHALTENE Querlage (Offset der Kaskade)
var _turn_dir := 0              # Richtungs-Latch für 180°-Wenden (um ±π flackert das Vorzeichen)
var _aim_prev := Vector3.FORWARD  # _aim_cmd des Vorframes (Feed-Forward der Marker-Rate)
var _aim_live := false          # Totzonen-Hysterese: folgt der Befehl gerade der Maus?
var _aim_ff := Vector3.ZERO     # gefilterte Marker-Drehrate (rad/s, Welt)
var _wh_filt := 0.0             # tiefpass-gefilterter Horizontal-Drehraten-BEDARF (für die Soll-Bank)
var _rnp_on := false            # Roll-and-Pull aktiv (Hysterese RNP_ON/RNP_OFF)
var _k_rnp := 0.0               # weicher Modus-Übergang (3/s Slew)
var _prev_phi := 0.0            # Zugebenen-Winkel des Vorframes (für die phi-Dämpfung)
var _phi_rate := 0.0            # gefilterte phi-Änderungsrate (rad/s)
var _prev_horiz := 0.0          # Horizontalfehler des Vorframes (für die Fehler-Rate)
var _horiz_rate := 0.0          # gefilterte Horizontalfehler-Änderungsrate (rad/s)
var free_look := false          # C halten: Kamera frei um den Flieger schwenken (ohne zu steuern)
var flook_yaw := 0.0            # Free-Look-Blickwinkel horizontal
var flook_pitch := 0.0          # Free-Look-Blickwinkel vertikal
var _flook_basis := Basis()     # geglättete Orbit-Orientierung (Position folgt dem Flieger STARR)
var _flook_was := false         # war Free-Look letzten Frame aktiv? (für sanften Einstieg)
var _mouse_idle := 0.0
var mouse_fly := true           # Maus-Flug an? (STANDARD wie War Thunder; M = Tastatur-Modus)
var g_protect := true           # G-Schutz: Flügel können nicht abreißen (Taste H)
var arcade := false             # Arcade-Lenkung an? (kinematisch super-smooth, nur im Maus-Flug)
var _roll_hold := 0.0           # wie lange A/D schon gehalten (für Fass-Roll)
var _roll_dir := 0              # aktuelle Roll-Halterichtung (+1=A, -1=D, 0=keine)
var _flap_stage := 0            # Landeklappen-Stufe (Index in FLAP_STAGES), Taste F schaltet weiter
var _cam_shake := 0.0           # aktuelles Kamera-Shake-„Trauma" (0..~1.4), klingt ab
var _aim_cmd := Vector3(0, 0, -1)  # geglättete Zielrichtung (Regler folgt ihr -> smoother)
var _nose_px := Vector2.ZERO    # geglättete Nasenmarker-Pixelposition
var aim_screen := Vector2.ZERO  # Pixelposition Zielmarker (fürs HUD)
var nose_screen := Vector2.ZERO # Pixelposition der aktuellen Nasenrichtung
var gun_screen := Vector2.ZERO   # ballistisches Fadenkreuz: wohin die Kugeln WIRKLICH fliegen
var gun_visible := false
var _gun_px := Vector2.ZERO      # pixelgeglättet (wie der Nasenmarker)
var lock_dist := 0.0             # Entfernung zum erfassten Ziel (Referenz für den Pipper)
var aim_visible := true         # Zielmarker im Bild?
var nose_visible := true        # Nasenmarker im Bild?
var lock_screen := Vector2.ZERO # Pixelposition des erfassten Ziels (Lenkwaffen-Lock)
var lock_visible := false       # Lock-Ziel im Bild?
var lock_active := false        # Lenkwaffe an Bord + Ziel voraus erfasst?

# --- AUFSCHALTUNG UND GEGENMASSNAHMEN --------------------------------------------------
# lock_stufe: 0 = nichts, 1 = der Sucher SIEHT etwas, 2 = aufgeschaltet und schussbereit.
# Zwischen 1 und 2 liegt bei Radarwaffen eine knappe Sekunde, in der man die Nase auf dem
# Ziel halten muss — das ist die Spannung, die eine Waffe ohne Aufschaltzeit nicht hat.
var lock_stufe := 0
var lock_ziel: Node3D = null
var lock_typ := ""              # Baumuster, das gerade aufschaltet (fuer die Anzeige)
var _lock_zeit := 0.0
const LOCK_DAUER := 0.85

# Werferkassetten. Bewusst knapp: unbegrenzte Gegenmassnahmen machen jede Lenkwaffe
# wertlos. Paarweise ausgestossen, weil eine einzelne Fackel selten reicht.
var flares := 24
var chaff := 24
const CM_TAKT := 0.4
var _cm_cd := 0.0
var _flare_held := false
var _chaff_held := false
# Kurze Einblendung im HUD ("KEIN LOCK", "FACKELN LEER").
var _lenk_meldung := ""
var _lenk_meldung_t := 0.0
# Anflugwarnung: naechste auf uns gerichtete Lenkwaffe (Richtung, Zeit bis Einschlag).
var warn_aktiv := false
var warn_winkel := 0.0          # relativ zur Nase, im Bogenmass (0 = voraus)
var warn_zeit := 0.0
# Survival-Upgrade-Multiplikatoren (von Main aus GameState gesetzt)
var thrust_mult := 1.0
var wing_mult := 1.0
var mass_mult := 1.0

# Waffen (feuerbar): Mündungs-Offsets je Typ, aus dem Design gesammelt
var weapons: Array = []        # [{type, off:Vector3 lokal, cd:float}]
# --- LENKWAFFEN-BAUMUSTER --------------------------------------------------------------
#
# DREI STUECK, UND KEINES MEHR. Der Bauteilkatalog kennt drei Lenkwaffen; sie hiessen
# bisher unterschiedlich, verhielten sich aber fast gleich (nur "turn" und "seek_range"
# waren verschieden). Ihre Beschreibungen versprachen dabei schon immer IR- und
# Radarsuchkoepfe — das loest diese Tabelle jetzt ein, ohne ein einziges neues Teil.
#
# Was ein Baumuster ausmacht, sind vier gegenlaeufige Groessen. Keine ist "besser":
#
#   IR-KURZ        wendig, kurze Reichweite, kein Lock noetig, faellt auf Fackeln herein.
#                  Die Waffe fuer das Handgemenge — abdruecken und wegdrehen.
#   RADAR-MITTEL   weit, traege, braucht Aufschaltung UND Beleuchtung bis zum Einschlag.
#                  Wer nach dem Schuss abdreht, wirft ihn weg. Dueppel brechen sie.
#   IR-SCHWER      Abwurfstart, mittlere Reichweite, grosser Gefechtskopf, mittelwendig.
#                  Gegen Luftschiffe; gegen einen kurvenden Gegner zu traege.
#
# DIE ZAHLEN SIND EINGEFLOGEN, NICHT GERATEN. tools/_raketen_pruefstand.gd misst, was
# aus ihnen folgt — Reichweite und Trefferquote stehen nirgends als Wert, sie ERGEBEN
# sich aus Schub, Brenndauer, Widerstand, Querlast und Lenkgesetz. Stand der Messung:
#
#   Baumuster       Spitze   von vorn   von hinten   frei   1 Salve   Kassette
#   IR-KURZ         520 m/s    >6000 m       1400 m   67 %      50 %       17 %
#   RADAR-MITTEL    606 m/s    >6000 m       4000 m  100 %      17 %        0 %
#   IR-SCHWER       518 m/s     5600 m       1800 m   67 %      33 %       17 %
#
# Zu lesen ist die Tabelle so: RADAR-MITTEL trifft ungestoert als einzige sicher, ist
# dafuer die einzige, die eine Dueppelsalve vollstaendig ausschaltet. IR-KURZ ist gegen
# Koeder am robustesten, hat aber im Verfolgungsschuss nur 1400 m — von hinten muss man
# nah heran. Der Unterschied zwischen "von vorn" und "von hinten" ist nirgends
# eingestellt; er folgt allein daraus, dass ein entgegenkommendes Ziel der Rakete
# entgegenkommt und ein fliehendes ihr davonlaeuft, waehrend der Motor nur ein paar
# Sekunden brennt.
const LENKWAFFEN := {
	"missile": {
		"name": "IR-KURZ", "sucher": "ir", "koeder": "flare",
		"schub": 210.0, "brenndauer": 1.7, "cw": 0.00022, "max_g": 30.0,
		"start_v": 70.0, "lebensdauer": 11.0, "schwerkraft": 5.0,
		"kegel": 55.0, "erfassung": 1700.0, "lenkfaktor": 4.2,
		"zuender": 9.0, "kraft": 6.0, "cd": 0.8, "traegheit": 0.6,
		"lock_noetig": false, "beleuchtung": false,
	},
	"missile_heavy": {
		"name": "RADAR-MITTEL", "sucher": "radar", "koeder": "chaff",
		"schub": 135.0, "brenndauer": 3.2, "cw": 0.00011, "max_g": 17.0,
		"start_v": 95.0, "lebensdauer": 24.0, "schwerkraft": 6.5,
		"kegel": 24.0, "erfassung": 4200.0, "lenkfaktor": 3.4,
		"zuender": 15.0, "kraft": 14.0, "cd": 1.9, "traegheit": 3.0,
		"lock_noetig": true, "beleuchtung": true,
	},
	"missile_drop": {
		"name": "IR-SCHWER", "sucher": "ir", "koeder": "flare",
		"schub": 185.0, "brenndauer": 2.5, "cw": 0.00017, "max_g": 19.0,
		"start_v": -8.0, "lebensdauer": 16.0, "schwerkraft": 8.0,
		"kegel": 44.0, "erfassung": 2500.0, "lenkfaktor": 3.6,
		"zuender": 14.0, "kraft": 13.0, "cd": 1.5, "traegheit": 1.2,
		"lock_noetig": false, "beleuchtung": false, "abwurf": 0.55,
	},
}

# Waffengruppen (SimplePlanes-Stil): Leertaste feuert NUR die ausgewaehlte Gruppe.
# Auswahl im Flug: Tasten 1-4 direkt, V zyklisch. Reihenfolge = WGROUPS-Reihenfolge.
const WGROUPS := [
	{"id": "gun", "label": "BORDKANONEN", "types": ["mg", "gun", "autocannon", "heavy", "minigun"]},
	{"id": "rocket", "label": "RAKETEN", "types": ["rocket", "salvo"]},
	{"id": "missile", "label": "LENKWAFFEN", "types": ["missile", "missile_heavy", "missile_drop"]},
	{"id": "bomb", "label": "BOMBEN", "types": ["bomb"]},
]
var weapon_groups: Array = []   # nur die Gruppen, die dieser Bau tatsaechlich traegt
var weapon_sel := 0             # Index in weapon_groups
var _fire_held := false         # Flanken-Erkennung: Raketen/Bomben feuern EINZELN pro Klick
var _bomb_held := false
var world_root: Node3D         # wohin Geschosse/Effekte gespawnt werden (von Main gesetzt)


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)


func set_camera(c: Camera3D) -> void:
	camera = c


func set_active(active: bool) -> void:
	set_process(active)
	set_physics_process(active)
	set_process_unhandled_input(active)
	# Maus im Flug fangen (frei umschauen), im Hangar normal sichtbar.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE
	if active and aircraft:
		look_yaw = 0.0
		look_pitch = 0.0
		if mouse_fly:
			_reset_mouse_state()   # Maus-Flug ist Standard: sauber an der Nase starten
		_snap_camera()


# ---------------------------------------------------------------------------
# Flugzeug aus Design bauen
# ---------------------------------------------------------------------------
func build_from_design(d: Array) -> void:
	clear_aircraft()
	design = d
	var body := AircraftBody.new()
	body.collision_layer = AIRCRAFT_LAYER
	body.collision_mask = GROUND_LAYER

	var min_y := INF
	var part_infos: Array = []   # je Teil: alle Aero-Beiträge (für Neuberechnung nach Bruch)
	weapons.clear()

	# Vorab: Rumpf-Boxen (Nicht-Flügel) -> im Rumpf vergrabene Flügelfläche erzeugt keinen Auftrieb.
	var body_boxes: Array = []
	for it in d:
		var bid: String = it.get("id", "")
		if not PartCatalog.has(bid):
			continue
		var bpp := PartCatalog.get_part(bid)
		if bpp.get("is_wing", false):
			continue
		body_boxes.append(PartCatalog.part_box(bpp, it.get("xform", Transform3D()), it.get("scale", Vector3.ONE)))

	# Vorab: {id, xform, pscale} aller Teile -> Sternmotor prüft damit, ob hinten ein Rumpfteil
	# sitzt (dann offene Variante). Der Motor selbst stört nicht: rear_docked sieht nur Rumpfteile.
	var dock_items: Array = []
	for it in d:
		dock_items.append({"id": it.get("id", ""), "xform": it.get("xform", Transform3D()),
			"pscale": it.get("scale", Vector3.ONE)})

	for item in d:
		var id: String = item.get("id", "")
		if not PartCatalog.has(id):
			continue
		var p := PartCatalog.get_part(id)
		var xf: Transform3D = item.get("xform", Transform3D())
		var psc: Vector3 = item.get("scale", Vector3.ONE)
		var vol: float = psc.x * psc.y * psc.z      # Volumen-Faktor (Masse/Traglast)
		var rev: bool = bool(item.get("thrust_reverse", false))   # Prop-Schub umkehren (Editor-Option)
		# Flügel-Mittelspalt-Füllung (aus dem Editor): der Flügel ist um "fill" nach innen
		# verlängert. Effektive Spann-Skalierung + nach innen verschobene Wurzel, damit der
		# durchgehende Flügel auch IM FLUG sichtbar/wirksam ist (nicht nur im Editor).
		var nspan: float = maxf(float(p.get("span", 1.0)), 0.01)
		var fill: float = float(item.get("fill", 0.0))
		var has_fill: bool = fill > 0.0
		var psx_eff: float = psc.x + (fill / nspan if has_fill else 0.0)

		var vis := PartCatalog.build_visual(p, item.get("color", Color(0, 0, 0, 0)), item.get("taper", 1.0), item.get("taper_front", 1.0), item.get("taper_y", -1.0), item.get("taper_front_y", -1.0),
			item.get("sf", Vector2.ZERO), item.get("sb", Vector2.ZERO))
		if id == "engine_radial":   # Heck offen (Rumpf dockt an) oder freistehende Gondel?
			PartCatalog.set_engine_half(vis, PartCatalog.rear_docked(id, xf, psc, dock_items))
		elif id == "cockpit_radial":   # Anschlussrahmen nur an OFFENEN Enden zeigen
			PartCatalog.set_cockpit_frames(vis,
				not PartCatalog.cockpit_side_docked(id, xf, psc, dock_items, false),
				not PartCatalog.cockpit_side_docked(id, xf, psc, dock_items, true))
		# Skalierung in die Basis einrechnen (NICHT vis.scale setzen): bei gespiegelten
		# Teilen ist die Basis improper (det<0); vis.scale würde die Spiegelung zerstören
		# -> Flügel klappt auf die andere Seite -> "halbes Flugzeug".
		if has_fill:
			vis.transform = Transform3D(xf.basis * Basis.from_scale(Vector3(psx_eff, psc.y, psc.z)),
				xf.origin - xf.basis.x * fill)
		else:
			vis.transform = Transform3D(xf.basis * Basis.from_scale(psc), xf.origin)
		body.add_child(vis)
		PartCatalog.set_gear_length(vis, p, float(item.get("glen", 1.0)))
		var br: Array = item.get("br", [])
		if br.size() == 8:
			var ra := PartCatalog.block_radien_neu()
			for bi in 8:
				ra[bi] = clampf(float(br[bi]), 0.0, 1.0)
			var bake: Vector3 = item.get("bsc", Vector3.ONE)
			PartCatalog.set_block_rounding(vis, p, ra, bake)
			vis.scale = PartCatalog.block_rest_scale(vis.scale, bake)
		var prop := vis.find_child("Prop", true, false)
		# Rad-Knoten fuers sichtbare Rollen. MEHRERE, weil ein Drehgestell (wheel_bogie)
		# zwei Achsen hat: mit nur einem Knoten wuerde das vordere Paar beim Rollen um die
		# HINTERE Achse kreisen statt sich um die eigene zu drehen.
		var wheel_nodes: Array = []
		for wnm in ["Wheel", "Wheel2", "Wheel3", "Wheel4"]:
			var wnd := vis.find_child(wnm, true, false) as Node3D
			if wnd != null:
				wheel_nodes.append(wnd)
		# Bewegliche Fläche: Hauptflügel = "FlapHinge" (Rolle "flap"), Steuerflügel = "CtrlHinge"
		# (Rolle = control: pitch/roll/yaw). Wird im AircraftBody animiert.
		var surf_node: Node3D = vis.find_child("FlapHinge", true, false)
		var surf_role := "flap"
		if surf_node == null:
			surf_node = vis.find_child("CtrlHinge", true, false)
			surf_role = String(p.get("control", ""))

		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = PartCatalog.col_size(p) * psc + (Vector3(fill, 0.0, 0.0) if has_fill else Vector3.ZERO)
		# Korrekte (ggf. gespiegelte) Box-Mitte, aber mit proper Orientierung
		# (det > 0), sonst wird der Trägheitstensor fehlerhaft -> Physik-Explosion.
		var cob: Vector3 = PartCatalog.col_offset(p) * psc - (Vector3(fill * 0.5, 0.0, 0.0) if has_fill else Vector3.ZERO)
		var is_gear := String(p.get("category", "")) == PartCatalog.CAT_GEAR
		var wheel_r := 0.3
		if is_gear:
			# FAHRWERK = KUGEL statt Box: rollt glatt über den Boden. Die Box-KANTEN
			# hackten beim Nicken/Rotieren in die Bahn -> Zittern + plötzlicher
			# Geschwindigkeitsverlust ("Stottern") beim Start. Kugel = runder Kontakt.
			wheel_r = PartCatalog.col_size(p).z * 0.5 * minf(psc.y, psc.z)
			var sph := SphereShape3D.new()
			sph.radius = wheel_r
			cs.shape = sph
			# Kugel-Unterkante = Box-Unterkante (gleiche Spawn-Höhe wie vorher)
			var scenter := PartCatalog.col_offset(p) * psc
			# Ausgefahrenes Bein: der Radaufstandspunkt wandert um genau diesen Betrag mit
			# nach unten, sonst schwebt das Flugzeug oder sinkt ein.
			var gext: float = PartCatalog.gear_ext(p, float(item.get("glen", 1.0)))
			scenter.y = (PartCatalog.col_offset(p).y - PartCatalog.col_size(p).y * 0.5
				- gext) * psc.y + wheel_r
			var sc_local: Vector3 = xf * scenter
			cs.transform = Transform3D(Basis(), sc_local)   # Kugel: Orientierung egal
			body.add_child(cs)
			min_y = minf(min_y, sc_local.y - wheel_r)
		else:
			cs.shape = box
			var center_local: Vector3 = xf * cob
			var ori := xf.basis.orthonormalized()
			if ori.determinant() < 0.0:
				ori.x = -ori.x
			cs.transform = Transform3D(ori, center_local)
			body.add_child(cs)
			# tiefsten Punkt fürs Aufsetzen auf der Bahn ermitteln
			var ext: Vector3 = box.size * 0.5
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var corner: Vector3 = xf * (cob + Vector3(sx * ext.x, sy * ext.y, sz * ext.z))
						min_y = minf(min_y, corner.y)

		# Alle Aero-Beiträge pro Teil vorberechnen -> AircraftBody kann nach einem
		# Bruch das Modell aus den ÜBRIGEN Teilen neu zusammenrechnen.
		var pinfo := {
			"vis": vis, "cs": cs, "xform": xf, "csize": box.size, "coffset": cob,
			"id": id, "pos": xf.origin, "prop": prop, "broken": false,
			"wheels": wheel_nodes, "wheel_r": wheel_r,
			"surf": surf_node, "surf_role": surf_role,
			# Welt-"unten"-Vorzeichen aus der Flügel-Oberseite (basis.y.y); kippt bei Spiegelung
			# NICHT (Mirror negiert nur X) -> beide Seiten schlagen gleich aus. Vertikale Flosse
			# (y.y≈0) -> Fallback 1. surf_side (x-Seite) für gegensinnige Quer-/Flaperon-Ausschläge.
			"surf_dn": (1.0 if absf(xf.basis.y.y) < 0.3 else signf(xf.basis.y.y)),
			"surf_side": (1.0 if xf.origin.x >= 0.0 else -1.0),
			"is_root": item.get("root", p.get("root", false)),   # Bauplan-Wurzel (Fallback: Katalog-Flag)
			"is_wing": p.get("is_wing", false), "control": String(p.get("control", "")),
			"mass": p.get("mass", 0.0) * vol,
			"drag": PartCatalog.part_drag(p) * psc.x * psc.y,
			"lift_part": 0.0, "ar": 4.0, "lift_coef": 1.0, "wing_cap": 0.0, "span": 2.0,
			"pitch_a": 0.0, "roll_a": 0.0, "yaw_a": 0.0,
			"thrust": p.get("thrust", 0.0) * vol, "jet": p.get("jet", false),
			"gear_cap": p.get("gear_capacity", 0.0) * vol, "retract": p.get("retract", false),
			# Strukturwert (Kollisions-Bruchschwelle); größere Teile sind etwas zäher.
			"strength": PartCatalog.part_strength(p) * clampf(1.0 + (vol - 1.0) * 0.25, 0.6, 2.2),
			"scale": psc, "thrust_reverse": rev,
		}
		if pinfo["is_wing"]:
			var a_full: float = p.get("area", 0.0) * psx_eff * psc.z
			var span: float = p.get("span", sqrt(maxf(a_full, 0.01))) * psx_eff
			# im Rumpf vergrabene Spannweite zählt nicht (weniger Auftrieb/Steuerkraft)
			var exposed: float = PartCatalog.wing_exposed_fraction(xf, span, PartCatalog.col_offset(p).z * psc.z, body_boxes)
			var a: float = a_full * exposed
			var up_align: float = clampf(absf(xf.basis.y.dot(Vector3.UP)), 0.0, 1.0)
			pinfo["span"] = span
			pinfo["ar"] = clampf(span * span / maxf(a_full, 0.01), 0.6, 10.0)
			pinfo["lift_coef"] = p.get("lift", 1.0)
			pinfo["wing_cap"] = a_full * PartCatalog.WING_STRESS * p.get("stress_mult", 1.0)
			pinfo["lift_part"] = a * up_align
			var ctrl_part: float = a * (1.0 - up_align)
			match pinfo["control"]:
				"pitch": pinfo["pitch_a"] = a
				"roll": pinfo["roll_a"] = a
				"yaw": pinfo["yaw_a"] = a
				_: pinfo["roll_a"] = ctrl_part
		part_infos.append(pinfo)
		var wp := String(p.get("weapon", ""))
		if wp != "":
			# ammo = -1 -> unbegrenzt (Geschütze); 1 -> Bombe/Rakete (verschwindet nach Schuss).
			# part_idx verknüpft die Waffe mit ihrem Bauteil (zum Entfernen beim Abfeuern).
			var went := {"type": wp, "off": xf.origin, "cd": 0.0,
				"ammo": int(AMMO.get(wp, -1)), "part_idx": part_infos.size() - 1}
			if wp == "minigun":
				went["spin"] = 0.0
				went["barrels"] = vis.find_child("Barrels", true, false)   # rotierendes Laufbündel
			weapons.append(went)

	_rebuild_weapon_groups()

	# Spawn-Höhe so, dass der tiefste Punkt knapp über der Bahn liegt
	if min_y == INF:
		min_y = -1.0
	spawn_height = 0.3 - min_y

	body.parts = part_infos
	body.thrust_mult = thrust_mult
	body.wing_mult = wing_mult
	body.mass_mult = mass_mult
	add_child(body)
	body.recompute_aero()        # Masse/COM/Flächen/Schub/Fahrwerk aus den Teilen
	aircraft = body
	throttle = 0.0
	_place_at_spawn()


func clear_aircraft() -> void:
	if is_instance_valid(aircraft):
		aircraft.queue_free()
	aircraft = null
	# herumliegende Trümmer entfernen
	for c in get_children():
		if c.is_in_group("debris"):
			c.queue_free()


func _place_at_spawn() -> void:
	if not is_instance_valid(aircraft):
		return
	aircraft.global_transform = Transform3D(Basis(), Vector3(0.0, spawn_height, 40.0))
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	throttle = 0.0
	aircraft.throttle = 0.0
	aircraft.in_pitch = 0.0
	aircraft.in_roll = 0.0
	aircraft.in_yaw = 0.0
	_flap_stage = 0              # Klappen eingefahren auf der Bahn
	aircraft.flaps = 0.0
	aircraft.reset_gear()
	_snap_camera()


# Reset (Enter): Flugzeug komplett neu aufbauen -> repariert Flügel/Fahrwerk
func _reset_to_runway() -> void:
	if design.is_empty():
		return
	build_from_design(design)


# ---------------------------------------------------------------------------
# Steuerung
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not is_instance_valid(aircraft):
		return

	# Free-Look: C halten -> nur die Kamera schwenkt frei (siehe _process), Steuerung bleibt.
	free_look = Input.is_physical_key_pressed(KEY_C)

	# Schub (unter 0 % = bremsen, über 100 % = Nachbrenner bis 110 %)
	if Input.is_key_pressed(KEY_SHIFT):
		throttle += 0.6 * delta
	if Input.is_key_pressed(KEY_CTRL):
		throttle -= 0.6 * delta
	throttle = clamp(throttle, -0.4, 1.1)

	# Pitch (S/= Nase hoch, W/= Nase runter)
	var pitch := 0.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pitch += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pitch -= 1.0
	var pitch_key := pitch   # roher W/S-Befehl -> später VOLLER Override (volles Höhenruder sofort)
	# Roll — A und D vertauscht (A = rechts, D = links)
	var roll := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		roll += 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		roll -= 1.0
	# Gieren / Seitenleitwerk (Q = rechts, E oder Z = links). C ist jetzt Free-Look.
	var yaw := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		yaw += 1.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_Z):
		yaw -= 1.0

	# Fass-Roll (War-Thunder-Stil): A oder D LANGE halten -> kinematische 360°-Rolle um die
	# Längsachse. Kurzes Antippen rollt/bankt normal; ab BARREL_HOLD übernimmt die Fass-Roll.
	var rdir := 0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		rdir = 1
	elif Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		rdir = -1
	if rdir != 0 and rdir == _roll_dir:
		_roll_hold += delta
	else:
		_roll_dir = rdir
		_roll_hold = delta if rdir != 0 else 0.0
	aircraft.barrel_roll = rdir if (rdir != 0 and _roll_hold > BARREL_HOLD) else 0

	# Maus-Flug: Die Maus zeigt in eine WELTRICHTUNG (look_yaw/look_pitch), das Flugzeug
	# dreht seine Nase dorthin (Pursuit) — voll 360°. Schaust du nach Westen, fliegt es nach
	# Westen. Bank-to-turn: Horizontalfehler -> Soll-Querlage (Kaskade, kein Trudeln);
	# Vertikalfehler -> Nick; Zug proportional zum Horizontalfehler zieht durch die Kurve.
	if mouse_fly:
		var b := aircraft.global_transform.basis
		aircraft.aim_world = _aim_dir()   # ROH (Arcade-Pfad + HUD)
		aircraft.mouse_bank_offset = _bank_offset
		# ===== WT-INSTRUCTOR (War-Thunder-Stil): Marker roh, Slew-Limit, PID-Kaskade,
		# AoA-/G-Limiter auf MESSWERTE, Roll-and-Pull bei großen Fehlern. ============
		# [B] Kommandierte Richtung: ROHE Maus, nur Drehraten-(Slew-)Limit — KEIN Lerp-
		# Lag (WT glättet die Maus nicht; Schleppfehler war eine Überschwing-Quelle).
		var raw_aim := _aim_dir()
		var ang_cmd := _aim_cmd.angle_to(raw_aim)
		# TOTZONE mit Hysterese gegen Hand-/Sensorzittern der gefangenen Maus:
		# erst ab ~0.2° Abweichung folgt der Befehl (dann bis <0.03° nach). Mikro-
		# Rauschen erreicht so weder den Fehler-Regler noch den Feed-Forward —
		# sonst zappelten die Ruder im Geradeausflug pausenlos (gemessen: 204°
		# Höhenruder-Weg in 8 s bei ±0.09°-Zittern; mit Totzone praktisch 0).
		if not _aim_live:
			if ang_cmd > 0.0035:
				_aim_live = true
		elif ang_cmd < 0.0005:
			_aim_live = false
		if _aim_live and ang_cmd > 1e-4:
			var sl_axis := _aim_cmd.cross(raw_aim)
			if sl_axis.length() > 1e-6:
				_aim_cmd = _aim_cmd.rotated(sl_axis.normalized(), minf(AIM_CMD_SLEW * delta, ang_cmd)).normalized()
			else:
				_aim_cmd = raw_aim
		# Marker-Drehrate als FEED-FORWARD: ein P-Regler allein braucht stationären
		# Fehler, um einer wandernden Maus zu folgen (~11° Schleppfehler gemessen).
		# Die Drehrate des (slew-glatten) Befehls wird gefiltert mitkommandiert.
		var aim_w := _aim_prev.cross(_aim_cmd) / maxf(delta, 1e-5)
		_aim_prev = _aim_cmd
		_aim_ff = _aim_ff.lerp(aim_w, clampf(delta * 8.0, 0.0, 1.0))
		# [C] Fehlerzerlegung im Körpersystem (Nase = -Z)
		var e := b.transposed() * _aim_cmd
		var _horiz := _soft_dead(atan2(e.x, -e.z))             # +rechts, ±π hinten
		var vert := _soft_dead(atan2(e.y, sqrt(e.x * e.x + e.z * e.z)))  # +oben
		var err_total := acos(clampf(-e.z, -1.0, 1.0))        # Gesamtfehler 0..π
		var wb := b.transposed() * aircraft.angular_velocity
		var current_bank := atan2(b.x.y, b.y.y)
		var v := maxf(aircraft.airspeed, 12.0)
		# A/D = gehaltener Bank-Offset (WT "manual roll control")
		if aircraft.barrel_roll != 0:
			_bank_offset = 0.0
		else:
			_bank_offset = clampf(_bank_offset + roll * BANK_OFFSET_RATE * delta, -AIM_BANK_MAX, AIM_BANK_MAX)
		# [D] Modusblende: koordinierte Kurve <-> ROLL-AND-PULL (großer Fehler: erst in
		# die Zugebene rollen, dann ziehen — WT rollAndPullUpWishDir). Latch hält die
		# Rollrichtung durch die ±π-Flackerzone (180°-Wenden, Ziel unten = Split-S).
		# Modus mit HYSTERESE statt Misch-Blende: ein 30/70-Gemisch ließ den Koordi-
		# nations-Anteil (will bei horiz≈0 leveln) GEGEN den laufenden Pull rollen ->
		# die Zugrichtung driftete seitlich am Kreis vorbei (das gemessene Overshoot).
		if _rnp_on:
			# erst raus, wenn auch der PULL durch ist — sonst rollt der Koordinations-
			# modus aus, während noch gezogen wird -> Zug sprüht die Nase seitlich
			if err_total < RNP_OFF and absf(vert) < 0.18:
				_rnp_on = false
		elif err_total > RNP_ON:
			_rnp_on = true
		_k_rnp = move_toward(_k_rnp, 1.0 if _rnp_on else 0.0, 3.0 * delta)
		var k_rnp := _k_rnp
		var phi := atan2(e.x, e.y)        # Ziel relativ zur Zugebene (0 = genau "oben")
		if err_total > LATCH_ON:
			if _turn_dir == 0:
				_turn_dir = 1 if phi >= 0.0 else -1
			phi = absf(phi) * float(_turn_dir)
		elif err_total < LATCH_OFF:
			_turn_dir = 0
		# [E] EIN Gesetz statt zwei Modi: GROSSKREIS-VERFOLGUNG.
		# Soll-Drehvektor (Welt) = Achse(Nase×Ziel) · Rate. Die Rate hat ein G-Budget
		# (machbare Kurvenrate knapp unterm G-Limiter) + STOPP-PLANUNG (sqrt(2·a·err)
		# bremst VOR dem Ziel ab -> kein Durchziehen). basisᵀ verteilt die Welt-
		# Drehung VORZEICHENRICHTIG auf Nick/Gier — bei jeder Bank, auch jenseits
		# 90° (dort wird korrekt gedrückt). Rollen richtet NUR die Zugebene aus und
		# steht nie mehr im Nick-Pfad. (Die alte Kaskade Fehler->Soll-Bank->Rollen->
		# Zug war bei 200 m/s strukturell instabil: 26-57° Overshoot, Messer-Drift,
		# weil wh_cap=g·tan(BANK)/v Dauer-Kurven auf ~3 G deckelte und die Bank-
		# Trigonometrie im Nick-Pfad jede Roll-Bewegung in Seitenfehler umsetzte.)
		# DER INSTRUCTOR LIEST DEN BAU: Obergrenze = was DIESE Zelle physisch dreht
		# (Steuerflächen!), nicht nur die globale Feel-Tabelle. Großes Leitwerk =
		# schnelle Befehle, Mini-Ruder = ehrlich träge. Vorher kommandierten die
		# Tabellen Raten, die der Bau nicht fliegen kann -> innere Schleife
		# sättigte (Dauer-Vollausschlag) = schwammig + Schleppfehler.
		var auth := _auth_rates()
		var pitch_max := minf(_tab(v, PITCH_RATE_TAB), auth.x * AUTH_HEADROOM)
		var roll_max := minf(_tab(v, ROLL_RATE_TAB), auth.z * AUTH_HEADROOM)
		var nose_w := -b.z
		var g_lim := clampf(aircraft.wing_capacity / maxf(aircraft.mass * 9.81, 1.0), 3.0, 14.0)
		var n_turn := G_SOFT * g_lim     # Dauer-G knapp unterm Limiter-Einsatz
		var w_gcap := 9.81 * sqrt(maxf(n_turn * n_turn - 1.0, 0.25)) / v
		var w_cap := minf(pitch_max, w_gcap)
		var w_mag := minf(w_cap, minf(INS_KP_V * err_total, sqrt(2.0 * AIM_TURN_ACC * err_total)))
		var cross_w := nose_w.cross(_aim_cmd)
		var axis_w := Vector3.ZERO
		if cross_w.length() > 1e-4:
			axis_w = cross_w.normalized()
		elif err_total > 2.0:
			# Ziel exakt hinter uns: Achse unbestimmt -> horizontale Wende in Latch-Richtung
			axis_w = Vector3.UP * -float(_turn_dir if _turn_dir != 0 else 1)
		# FF nur bei BEWUSSTER Marker-Bewegung (Soft-Gate): Zitter-/Drift-Raten der
		# Hand (<~0.1 rad/s) injizieren sonst Dauerrauschen in den Nick-Pfad.
		var ff := _aim_ff * smoothstep(0.06, 0.18, _aim_ff.length())
		var w_des_w := axis_w * w_mag + ff.limit_length(w_cap * 0.7)
		if w_des_w.length() > w_cap:
			w_des_w = w_des_w.normalized() * w_cap
		var w_b_des := b.transposed() * w_des_w
		var d_pitch := clampf(w_b_des.x, -pitch_max, pitch_max)
		var yaw_cap := minf(0.3, auth.y * AUTH_HEADROOM)
		var yaw_track := clampf(w_b_des.y, -yaw_cap, yaw_cap)   # Ruder hilft mit, dominiert nie
		# ROLL = Zugebene ausrichten: bei großem Fehler phi-PD in die Manöverebene
		# (Latch gegen ±π-Flackern), bei kleinem Fehler Kurvengleichungs-Bank aus der
		# horizontalen Komponente der Soll-Drehrate (wh_eff). Nur der ROLL-Kanal
		# blendet (Skalar, gutmütig) — Nick/Gier folgen immer demselben Gesetz.
		var wh_eff := -w_des_w.y     # Drehrate um Welt-Oben (+ = rechtsherum)
		# Die Kurvengleichung VERSTÄRKT bei Tempo brutal: 1° Seitenfehler ergibt bei
		# 200 m/s schon ~42° Soll-Bank — jedes Maus-Mikrozittern kippte das Vorzeichen
		# und die Querruder schlugen links/rechts um ("Flugzeug gleicht sich dauernd
		# selbst aus", gemessen 28-47 Umschläge + ±14-17° Pendeln in 8 s).
		# Fix: BEDARF tiefpassen (Zitter mittelt sich zu null, echte Kurven bauen in
		# ~0.4 s auf) + Kleinst-Gate.
		# KURS-Anteil des Fehlers = der Teil, der überhaupt eine Querlage braucht:
		# der Drehvektor Nase->Marker ist axis_w·err_total, seine WELT-SENKRECHTE
		# Komponente ist die Kursänderung. Rein senkrechte Fehler haben e_kurs = 0.
		var e_kurs := axis_w.dot(Vector3.UP) * err_total
		# KLEINST-GATE AUF DEN FEHLER statt auf die gefilterte Soll-Drehrate.
		# Vorher: smoothstep(0.006, 0.018, |_wh_filt|). Im Endanflug ist _wh_filt
		# = INS_KP_V·err, die Schwellen entsprachen damit 0.138° und 0.413° Fehler —
		# der 0.2°-Akzeptanzring lag MITTEN in der Abschaltrampe (gemessen: bei 0.226°
		# Restfehler stand das Gate auf 0.366, bei 0.164° auf 0.129, ab 0.099° auf 0.0).
		# Genau dort, wo die Kennzahl misst, waren ~87 % der waagerechten Regelautorität
		# abgeschaltet. Das Gate soll Maus-Mikrozittern unterdrücken, nicht das letzte
		# halbe Grad; in Einheiten der Soll-DREHRATE kann es beides nicht unterscheiden.
		# Jetzt in Einheiten des FEHLERS und mit Schwellen UNTER dem Ring: 0.05°/0.15°.
		# Das Zittern selbst hält weiterhin die Totzonen-Hysterese von _aim_cmd (0.2°)
		# und _soft_dead draußen — dieses Gate ist nur noch die letzte Sicherung.
		_wh_filt = lerpf(_wh_filt, wh_eff, clampf(delta * 3.5, 0.0, 1.0))
		var bank_need := _wh_filt * smoothstep(0.0009, 0.0026, absf(e_kurs))
		# ROLL-AUSSTIEG PLANEN (Gegenstück zur Stopp-Planung des Nick-Kanals).
		# Die Kurvengleichung atan(Ω·v/9.81) beantwortet nur die Frage "welche Querlage
		# TRÄGT diese Drehrate" — nicht die Frage "kann ich sie rechtzeitig wieder
		# loswerden". Bei Tempo ist sie brutal: mit INS_KP_V = 2.5 verlangen schon
		# 1.6° Seitenfehler bei 140 m/s eine Querlage von 45°, ein 5°-Sprung 72°.
		# Die Querlage muss am Ende aber WIEDER WEG, und während sie weggeht, dreht
		# die Zelle weiter. GEMESSEN (tools/_fein_bank.gd, 5° seitlich, 143 m/s):
		# bei t=1.01 s war der Fehler auf 0.12° herunter, die Querlage stand aber noch
		# bei 48° und die Nase drehte mit 4.9°/s weiter -> 0.30° Überschwingen.
		# DECKEL statt Abschaltung: die zulässige Querlage wächst LINEAR mit dem
		# Restfehler, φ_max = e·BANK_AUS_RATE·v/9.81. Das ist die Umkehrung von
		# "Kurs, den das Ausrollen noch verbraucht" = (9.81/v)·φ/rate. Bei Fehler null
		# ist auch die erlaubte Querlage null — die Zelle liegt waagerecht, wenn die
		# Nase ankommt. WARUM als Deckel und nicht als Faktor auf den Bedarf: ein
		# Faktor, der auf null kollabiert, ist ein SPRUNG im Bank-Befehl und ließ die
		# Querruder voll ausschlagen; der Deckel zieht die Querlage stetig mit dem
		# Fehler herunter.
		# BANK_AUS_RATE = 0.45 gemessen, nicht geschätzt: der Ausstieg besteht aus der
		# Querruder-Umkehr (Rollrate durch null, ~0.4 s) und erst danach dem Abklingen
		# mit ~3.5/s; über den ganzen Ausstieg von 50° auf 2° bleibt eine effektive
		# Rate deutlich unter 1/s. Höher (0.70) kostete 3.2 % Überschwingen, niedriger
		# (0.28) kostete 0.17 s Anstiegszeit; 0.45 ist das Minimum beider.
		# Der Deckel gilt NUR für den FEHLER-Anteil. Wandert der Marker (Verfolgung),
		# geht der Fehler nie auf null und die Querlage muss STEHEN BLEIBEN — die
		# Ausroll-Planung wäre dort schlicht das falsche Modell. Der Vorhalt bekommt
		# deshalb seine eigene Untergrenze aus derselben Kurvengleichung.
		# GEMESSEN ohne diese Ausnahme (tools/mf_schlepp.gd): der Schleppfehler bei
		# 50 % der Zellenrate stieg von 1.74° auf 2.87° und bei 80 % von 0.16° auf
		# 7.82° — der Deckel drosselte die Dauerkurve auf 51° Querlage, obwohl 76°
		# nötig waren. Mit der Ausnahme bleibt die Dauerkurve unangetastet.
		var bank_ff := absf(atan(_aim_ff.y * v / 9.81))
		var bank_cap := maxf(absf(e_kurs) * BANK_AUS_RATE * v / 9.81, bank_ff)
		var target_bank := clampf(-atan(bank_need * v / 9.81), -bank_cap, bank_cap)
		target_bank = clampf(target_bank + _bank_offset, -AIM_BANK_MAX, AIM_BANK_MAX)
		# KURVEN-ZUG AUF DEN NICK-KANAL — die fehlende Hälfte von "bank-to-turn".
		# Querlage allein dreht nicht. Eine koordinierte Kurve mit der Rate Ω bei
		# Querlage φ verlangt die KÖRPER-Nickrate q = Ω·sin φ. Fehlt dieses Ziehen,
		# hängt die Zelle nur schräg in der Luft und sackt, statt zu drehen.
		# WARUM das Großkreis-Gesetz das nicht liefert: seine Achse ist Nase×Marker,
		# also die KÜRZESTE Verbindung. Sobald der Nick-Kanal den Vertikalfehler
		# ausgeregelt hat, liegt der Restfehler in der KÖRPER-Horizontalen; die Achse
		# kippt dann mit der Querlage mit, und ihr waagerechter Anteil erzeugt im
		# Nick-Kanal einen DRUCK, der den Kurvenzug fast exakt aufhebt.
		# GEMESSEN (tools/_fein_quer.gd, Spieler-Design, 2° seitlich, 143 m/s, t=0.76 s,
		# Querlage -44.5°): der senkrechte Anteil des Soll-Drehvektors steuert +0.0363 rad/s
		# Nick bei, der waagerechte -0.0327 — übrig blieben +0.0036 statt der nötigen
		# +0.0363. Ergebnis bei t=2.0 s: Querlage -23.9°, kommandiert 0.0285 rad/s,
		# Nickrate wb.x = -0.0080 (die Zelle DRÜCKTE), erreichte Welt-Drehrate
		# 0.0072 rad/s = 25 % der kommandierten. Die Querlage war dabei RICHTIG:
		# g·tan(23.9°)/v = 0.0304 rad/s wären damit drin gewesen, mehr als kommandiert.
		# Übrig blieb das Seitenruder, und dessen Ratentreue lag über den ganzen Vorgang
		# bei 0.24-0.29 (Messlatte: 0.90) bei nur 0.02-0.05 von 1.0 Ruderweg — der Kanal
		# war nicht am Anschlag, sondern strukturell der falsche: Gieren ist Schieben,
		# nicht Kurvenfliegen.
		# UNGEFILTERT (wh_eff statt bank_need): mit dem 3.5/s-Tiefpass und dem Gate hängt
		# der Zug dem Bedarf 0.286 s nach und zieht über das Ziel hinaus — gemessen
		# 24.5 % Überschwingen bei 5° seitlich gegenüber 2.4 % mit wh_eff.
		# VORZEICHEN: wh_eff > 0 (Rechtskurve) erzeugt oben target_bank < 0, also
		# sin(current_bank) < 0; -wh_eff·sin(bank) ist damit in BEIDEN Drehrichtungen
		# ein ZUG und bei Querlage 0 exakt null.
		# SELBSTABSCHALTEND: ohne Kurvenwunsch ist wh_eff = 0 und der Term verschwindet.
		# Geradeausflug und der mit A/D gehaltene Bank-Offset (der nicht in wh_eff steckt)
		# bleiben unberührt — gemessen mit tools/mf_ruhe.gd: Bias und Restunruhe
		# unverändert (bias 0.003-0.022°, sd ≤ 0.012°).
		# Er sitzt VOR dem AoA-/G-Limiter, kann also weiterhin nicht überziehen.
		# ... ABER NUR SO VIEL ZUG, WIE DIE AKTUELLE QUERLAGE TRÄGT.
		# q = Ω·sin φ ist die Bedingung der EINGESCHWUNGENEN Kurve. Während des
		# Einrollens ist φ aber noch klein, und die Zelle kann bei dieser Querlage gar
		# keine Rate Ω fliegen — sie kann nur g·tan φ/v. Mit der SOLL-Rate gerechnet
		# wurde der Zug dort um ein Vielfaches überkommandiert: GEMESSEN
		# (tools/_fein_bank.gd, 10° seitlich, t=0.51 s, Querlage 29.7°) 0.139 rad/s
		# Zug gegen 0.019 rad/s, die die Querlage trägt — Faktor 7. Ergebnis war eine
		# Nick-Exkursion von 3.9 g hinauf und 0.25 g hinunter, +9 m/s Steigen und
		# danach ein stehender Vertikalfehler, dessen Korrektur den Kurvenzug wieder
		# aufhob (Patt: d_pitch ≈ 0 bei 30° Querlage, die Zelle hing nur schräg).
		# Deckel = die Rate, die diese Querlage koordiniert trägt. In der
		# eingeschwungenen Kurve ist der Deckel per Definition inaktiv (dort gilt
		# g·tan φ/v = Ω), er greift also NUR im Einrollen.
		# GEMESSEN: Einschwingen 10° seitlich 5.36 s -> 4.54 s allein durch diesen Deckel.
		var w_bank := 9.81 * absf(tan(clampf(current_bank, -AIM_BANK_MAX, AIM_BANK_MAX))) / v
		var wh_pull := clampf(wh_eff, -w_bank, w_bank)
		d_pitch = clampf(d_pitch - wh_pull * sin(current_bank), -pitch_max, pitch_max)
		var dbank := wrapf(target_bank - current_bank, -PI, PI)
		# Stopp-Planung sqrt(2·a·d) hat bei d=0 UNENDLICHE Steigung -> Grenzzyklus
		# ums Bank-Ziel (Querruder schlugen permanent um). Lineares Segment nahe
		# null (4.5/s) macht den Endanflug weich, sqrt bleibt für große Fehler.
		var wr_coord := signf(dbank) * minf(minf(roll_max, ROLL_COORD_MAX), minf(sqrt(2.0 * AIM_ROLL_ACC * absf(dbank)), absf(dbank) * 4.5))
		# "Pull fertig fliegen, DANN ausrollen": solange Vertikalfehler ansteht,
		# die Zugebene halten (Rollen gedrosselt).
		wr_coord *= 1.0 - 0.8 * clampf(absf(vert) / 0.45, 0.0, 1.0)
		# phi-PD (P allein überschwang die Zugebene); Gate: bei kleinem Restfehler ist
		# phi=atan2(e.x,e.y) schlecht konditioniert (jagte Rauschen, über-rollte bis
		# -112° Bank) -> ausblenden, die Kurvengleichungs-Bank übernimmt.
		var pr := clampf(wrapf(phi - _prev_phi, -PI, PI) / maxf(delta, 1e-5), -6.0, 6.0)
		_prev_phi = phi
		_phi_rate = lerpf(_phi_rate, pr, clampf(delta * 15.0, 0.0, 1.0))
		var rnp_gate := smoothstep(0.25, 0.6, err_total)
		var wr_rnp := clampf(-(phi * RNP_ROLL_KP + _phi_rate * RNP_ROLL_KD), -roll_max, roll_max) * rnp_gate
		var wr_des := lerpf(wr_coord, wr_rnp, k_rnp)
		# AOA-LIMITER (primär, geschlossener Kreis auf MESS-AoA — der Instructor KANN
		# den Stall nicht kommandieren) + G-LIMITER (sekundär, weiches Anschmiegen).
		var aoa_hi := AOA_PUSH * (AOA_MAX - aircraft.aoa_signed)
		var aoa_lo := AOA_PUSH * (AOA_MIN - aircraft.aoa_signed)
		d_pitch = clampf(d_pitch, aoa_lo, aoa_hi)
		var gl := aircraft.load_factor
		if d_pitch > 0.0 and gl > 0.0:
			d_pitch *= 1.0 - smoothstep(G_SOFT * g_lim, G_HARD * g_lim, gl)
		elif d_pitch < 0.0 and gl < 0.0:
			d_pitch *= 1.0 - smoothstep(G_SOFT * g_lim * G_NEG, G_HARD * g_lim * G_NEG, -gl)
		# [F] innere Raten-Schleifen + Trim-Integrator + Schiebewinkel-Gier (β -> 0, WT AosPid)
		var roll_cmd := clampf((wr_des - wb.z) * AIM_ROLL_P, -1.0, 1.0)
		# VORSTEUERUNG statt reinem P — der größte Einzelverlust im Maus-Flug.
		# AircraftBody stellt sich bei Höhenruder-Ausschlag u auf die Rate auth.x·u
		# ein: Momentengleichgewicht (CTRL_PITCH+CTRL_PITCH_A·Fläche)·qfac·MOUSE_AUTH·u
		# gegen DAMP_PITCH·apq·(0.35+qfac)·w — exakt die Formel, die _auth_rates()
		# ohnehin jeden Tick ausrechnet. Der nötige Ausschlag ist damit DIREKT
		# invertierbar: u_ff = d_pitch/auth.x.
		# Ein reiner P-Regler muss den Ausschlag dagegen über den FEHLER erkaufen und
		# bleibt zwangsläufig darunter. GEMESSEN (tools/mf_schlepp.gd, Spieler-Design,
		# 140 m/s): kommandiert 0.253 rad/s, geflogen 0.145 rad/s = 43 % Droop, bei nur
		# 0.16 von 1.0 Höhenruder — 84 % Ruderweg lagen brach. Die Nase deckelte
		# dadurch bei 8.2 °/s, obwohl die Zelle 17.1 °/s dreht (Ausnutzung 0.48).
		# Weil d_pitch schon auf pitch_max = auth.x·AUTH_HEADROOM geklemmt ist, bleibt
		# |u_ff| ≤ AUTH_HEADROOM — der Rest des Ruderwegs ist die Reserve für den
		# P-Anteil. Die Strecke liefert eher MEHR als das Modell sagt (Wetterfahne
		# PITCH_STAB hilft in der Kurve mit), der P-Anteil muss also überwiegend
		# ABZIEHEN — und dafür hat er immer vollen Weg.
		# Am Ziel (d_pitch → 0) ist der Vorsteuer-Term exakt 0: die Ruhe-Kennzahlen
		# (Bias, Restunruhe) bleiben unberührt, dies ist rein ein Kurven-/Zieh-Gewinn.
		var pitch_ff := d_pitch / maxf(auth.x, 1e-3)
		# TRIM-INTEGRATOR auf dem RATENFEHLER — ohne ihn bleibt ein STEHENDER Versatz.
		# Vorsteuerung und P kennen nur das MODELL der Zelle. Was das Modell nicht kennt,
		# ist der Ausschlag, den die Zelle zum bloßen GERADEAUSFLIEGEN braucht
		# (Wetterfahne PITCH_STAB, Auftriebsmoment, Schubachse). GEMESSEN mit
		# tools/_mf_bias_trace.gd (Spieler-Design, 140 m/s, Zeiger fest nach vorn):
		# der Regler hält dauerhaft in_pitch = -0.3694, obwohl er gar nicht drehen will.
		# Ohne Integrator muss dieser Ausschlag über den FEHLER erkauft werden, und der
		# Sockel ist exakt ausrechenbar: dCmd/dErr = (1/auth.x + AIM_PITCH_RATE_P)·INS_KP_V
		# = (3.36 + 1.5)·2.5 = 12.14 pro rad, also 0.3694/12.14 = 0.0304 rad = 1.743° —
		# genau der gemessene Versatz (tools/mf_ruhe.gd: bias 1.743° in ALLEN Fällen,
		# Körper h = 0.000°, v = -1.743°, also rein die Nickachse).
		# Warum auf dem RATEN- und nicht auf dem WINKELfehler: der Ratenfehler ist der
		# Eingang der INNEREN Schleife; der Integrator sitzt damit in der schnellen
		# Kaskade, statt eine zweite Integration in die ohnehin schon integrierende
		# Winkelschleife zu legen. Über die ganze Kette (Strecke τ ≈ 0.2 s, Vorsteuerung
		# 1/auth.x, P = 1.5, außen INS_KP_V = 2.5) ist das Routh-Hurwitz-Kriterium für
		# JEDES I > 0 erfüllt; der langsamste Pol liegt bei 0.5/s, also 2.0 s Abbau.
		# Im Ziel ist der Ratenfehler exakt 0 (d_pitch → 0, wb.x → 0): der Integrator
		# HÄLT dort seinen Wert — das IST der Trimm. Er rastet also ein, statt zu schwingen.
		# EHRLICH DAZU: ganz umsonst ist er nicht. Die Restunruhe steigt von sd 0.0000°
		# auf 0.008° (Spitze-Spitze 0.000° -> 0.034°), weil der Integrator einem
		# WANDERNDEN Trimmbedarf nachläuft — im Prüfstand beschleunigt die Zelle über die
		# Messdauer von 140 auf 154 m/s. Das ist kein Grenzzyklus (Amplitude bleibt über
		# 5 s konstant) und liegt 6-fach unter dem Ziel von 0.05°; erkauft wird damit ein
		# Bias von 1.743° auf 0.018°. Die alte Ruhe war die Ruhe einer Nase, die sauber
		# still stand — 1.743° NEBEN dem Zeiger.
		var w_err := d_pitch - wb.x
		var pitch_raw := pitch_ff + w_err * AIM_PITCH_RATE_P + _trim_pitch
		var pitch_cmd := clampf(pitch_raw, -1.0, 1.0)
		# ANTI-WINDUP (bedingte Integration): nur laden, solange der Ruderweg nicht schon
		# am Anschlag ist ODER der Fehler aus dem Anschlag HERAUS führt. Ohne das lädt
		# sich der Trimm im großen Flick voll — die Vorsteuerung allein belegt dort schon
		# AUTH_HEADROOM vom Weg — und schießt beim Einlaufen über. Genau das Durchziehen
		# misst der Ruhe-Prüfstand als "durchzug".
		# ZWEITES Tor: der Trimm gehört dem HALTE-Bereich, nicht dem Manöver. Nähert sich
		# die Soll-Rate dem Autoritäts-Cap, wird der Integrator ausgeblendet.
		# GRUND, gemessen mit tools/_mf_wind_trace.gd (Marker 0.35 rad/s, Dauerkurve):
		# das auth-Modell UNTERSCHÄTZT diese Zelle. Bei in_pitch = 0.82 fliegt sie
		# 0.327 rad/s, das Modell verspricht 0.298 pro Vollausschlag — 21 % Modellfehler.
		# Vorsteuerung + P überkommandieren dadurch stationär (kommandiert 0.283 rad/s,
		# geflogen 0.325) und die Kurve wird GRATIS schneller. Ein Integrator kennt das
		# nicht: er liest die Übererfüllung als Fehler und trimmt sie weg — gemessen lief
		# der Trimm auf -0.28, das Höhenruder von 0.91 auf 0.44, die Nickrate exakt
		# zurück auf die kommandierten 0.283 und der Schleppfehler stieg von 36.7° auf
		# 46.2°. Am Cap ist für ihn ohnehin nichts zu gewinnen (die Vorsteuerung belegt
		# dort schon AUTH_HEADROOM des Ruderwegs), er kann dort nur wegnehmen.
		# Der Ruhe-Fall liegt mit Soll-Rate 0.0008 gegen Cap 0.283 (0.3 %) tief im
		# offenen Bereich; die Dauerkurve mit 97 % tief im geschlossenen.
		# Bei geschlossenem Tor wird der Trimm GEHALTEN, nicht ausgewaschen — das ist der
		# einzige Unterschied zur Vorrunde und der Grund, warum die kleinen Nick-Sprünge
		# jetzt sauber einlaufen. Die alte Zeile fuhr _trim_pitch mit 1.0/s auf null.
		# WAS DARAN FALSCH WAR (gemessen, tools/_fein_trimm2.gd, Spieler-Design, 140 m/s):
		# das Tor schließt schon bei WINZIGEN Korrekturen. Beim 2°-Sprung hebt der Vorhalt
		# die Soll-Rate für 60 ms auf den Cap (Stopp-Planung fordert 0.087 rad/s, Vorhalt
		# legt seine 0.198 drauf, Summe klemmt bei 0.283) — das Höhenruder ging voll auf
		# +1.00 und i_gate auf 0. Das Auswaschen räumte in dieser Zeit 0.115 vom gemessenen
		# Halte-Ausschlag -0.315 weg, beim 10°-Sprung sogar den ganzen (Trimm exakt 0.000
		# zwischen t=0.34 und t=0.54 s). Direkt danach braucht die Zelle diesen Ausschlag
		# WIEDER, nur um nicht weiterzusteigen — der Integrator baut ihn aber über seinen
		# 0.5/s-Pol in ~2 s auf. Solange lief die Nase weiter: reines LADUNGSDEFIZIT.
		# Kennzeichen dafür, dass es kein proportionaler Effekt war: das ABSOLUTE
		# Überschwingen war über alle Sprungweiten fast gleich (0.51 / 0.80 / 1.03 / 1.04°
		# bei 2 / 5 / 10 / 15°), also unabhängig von der Sprunggröße.
		# GEMESSEN mit tools/mf_fein.gd, nur diese Zeile geändert (senkrecht,
		# Überschwingen und Zeit in den 0.2°-Gesamtring):
		#    2°  25.5 % / 1.90 s  ->   7.0 % / 0.35 s
		#    5°  16.0 % / 3.11 s  ->   0.0 % / 0.73 s
		#   10°  10.3 % / 3.88 s  ->   0.0 % / 1.17 s
		#   15°   6.9 % / 4.12 s  ->   0.0 % / 1.50 s
		# Preis ist die Anstiegszeit, weil der gehaltene Trimm im Zug mitzieht statt
		# wegzufallen: t90 senkrecht 0.72 -> 0.88 s bei 10° (Ziel 1.00 s).
		# WARUM HALTEN UND NICHT AUSWASCHEN DAS PHYSIKALISCH RICHTIGE IST: -0.315 ist der
		# Ausschlag für NULL Nickrate, nicht für null Zug. Diese Zelle steigt bei neutralem
		# Höhenruder von selbst mit rund +0.110 rad/s (aus den Messwerten: 0 rad/s bei
		# in_pitch -0.369, auth.x = 0.298 -> 0.298·0.369). Das auth-Modell kennt diesen
		# Sockel nicht; die Vorsteuerung d_pitch/auth.x liefert nur den RATEN-Anteil
		# OBENDRAUF. Wer den Sockel im Manöver wegnimmt, verschiebt die ganze Kennlinie:
		# das Flugzeug fliegt dann schneller, als der Regler kommandiert hat, und die
		# Stopp-Planung plant gegen eine Rate, die gar nicht fliegt.
		# GEMESSEN (tools/_fein_treue.gd, Dauerkurve bei 130 % der Zellenrate):
		#   ausgewaschen  kommandiert 0.283 -> geflogen 0.337 rad/s  RATENTREUE 1.19
		#   gehalten      kommandiert 0.283 -> geflogen 0.288 rad/s  RATENTREUE 1.02
		# EHRLICH DAZU — dieses ehrlichere Kommando kostet Dauerleistung, weil die
		# 19 % Übererfüllung wegfallen. GEMESSEN mit dem SPIELER-Design:
		#   tools/mf_design.gd  r90@200  t99 5.05 -> 5.66 s | h180@160 10.18 -> 11.64 s
		#                       h135@200 t99 7.32 -> 8.64 s | r90@140   4.91 ->  4.84 s
		#   tools/mf_schlepp.gd Sättigung 130 %: Nase 19.4 -> 16.9 °/s
		#   tools/mf_track.gd   errMittel 32.3 -> 32.9°, splitS 34.4 -> 36.5°
		# Alle Zielwerte bleiben erfüllt (90° <= 7.5 s, 180° <= 14 s, Sättigungs-Zuwachs
		# 5.34 <= 5.85 °/s), und die Flicks werden dabei RUHIGER: Überschwingen 180°
		# 1.4 -> 1.1°, Pendel-Umschläge 1 -> 0 in drei von vier Fällen.
		# ACHTUNG bei der Gegenprobe mit tools/mousefly_test.gd: dort wird es SCHNELLER
		# (rechts90 2.28 -> 2.25 s, hinten180 4.61 -> 4.56 s). Das ist kein Widerspruch,
		# sondern die andere Zelle: jenes Testdesign hat ein Leitwerk und braucht deshalb
		# kaum Halte-Trimm. Die Sekundenwerte des Spieler-Designs stehen in mf_design.
		# WER DIE DAUERLEISTUNG ZURÜCKHOLEN WILL, muss an den Cap, nicht an den Trimm:
		# pitch_max = auth.x·AUTH_HEADROOM unterschlägt, dass der Trimm einen Teil des
		# Ruderwegs belegt und der Rest ASYMMETRISCH ist (bei Trimm -0.315 stehen zum
		# Ziehen 1.315 Ruderweg zur Verfügung, zum Drücken 0.685). Das ist eine eigene
		# Baustelle — sie fasst w_cap, Stopp-Planung und Vorhalt gleichzeitig an.
		var i_gate := 1.0 - smoothstep(0.35, 0.70, absf(d_pitch) / maxf(pitch_max, 1e-3))
		if i_gate > 0.0 and (absf(pitch_raw) < 1.0 or w_err * pitch_raw < 0.0):
			_trim_pitch = clampf(_trim_pitch + w_err * AIM_TRIM_I * i_gate * delta, -AIM_TRIM_MAX, AIM_TRIM_MAX)
		var v_b := b.transposed() * aircraft.linear_velocity
		var beta := atan2(v_b.x, absf(v_b.z) + 0.6)
		# Gier folgt der Gier-Komponente des Welt-Drehvektors (Raten-Tracking statt
		# Fein-Zielen auf horiz) + Schiebewinkel-Koordination.
		var yaw_cmd := clampf(-beta * INS_YAW_BETA + (yaw_track - wb.y) * INS_YAW_AIM, -1.0, 1.0)
		# Übergabe: Tastatur bleibt ADDITIV (WT: Tasten helfen dem Instructor); A/D nur
		# über den Bank-Offset (kein rohes Gegen-Rollen).
		pitch = clampf(pitch + pitch_cmd, -1.0, 1.0)
		roll = roll_cmd
		yaw = clampf(yaw + yaw_cmd, -1.0, 1.0)

	aircraft.mouse_fly = mouse_fly   # Body schaltet damit das Auto-Leveling im Maus-Flug ab
	aircraft.g_protect = g_protect   # harter Auftriebs-Deckel (Flügel reißen nie)
	aircraft.arcade = arcade         # Arcade-Lenkung (kinematisch) im Body aktivieren
	aircraft.throttle = throttle
	aircraft.flaps = FLAP_STAGES[_flap_stage]   # Landeklappen: mehr Auftrieb + Widerstand
	if mouse_fly:
		# Maus-Flug: Befehle kommen aus dem (schon glatten) Regler -> DIREKT anwenden.
		# Das _ramp würde den Brems-Befehl verzögern und Überschwingen verursachen.
		aircraft.in_pitch = pitch
		aircraft.in_roll = roll
		aircraft.in_yaw = yaw
	else:
		# Weiches Eingabe-Ramping (analoges Gefühl auf Tastatur, nicht ruckartig ±1).
		# Schnelles Aufbauen, etwas langsameres Zurückzentrieren.
		aircraft.in_pitch = _ramp(aircraft.in_pitch, pitch, delta, 4.0, 6.0)
		aircraft.in_roll = _ramp(aircraft.in_roll, roll, delta, 7.0, 9.0)
		aircraft.in_yaw = _ramp(aircraft.in_yaw, yaw, delta, 4.0, 6.0)
	# W/S = SOFORT volles Höhenruder (manueller Override in BEIDEN Modi): voll hoch/runter lenken,
	# ohne Rampe und ohne dass der Maus-Instructor dagegenhält. Loslassen -> normale Logik zentriert.
	if pitch_key != 0.0:
		aircraft.in_pitch = pitch_key

	# --- Waffen (Cooldown pro Waffe) ------------------------------------
	for w in weapons:
		w["cd"] = maxf(0.0, w["cd"] - delta)
	# Minigun: Spin-up/Spin-down + Läufe drehen (auch wenn nicht gefeuert wird)
	# Feuern: Leertaste ODER linke Maustaste (nur im Flug aktiv, da _physics_process
	# nur bei set_active(true) läuft -> im Hangar bleibt Linksklick fürs Bauen).
	var firing := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var fire_click := firing and not _fire_held   # steigende Flanke = genau EIN Abschuss
	_fire_held = firing
	var gun_sel := not weapon_groups.is_empty() and String(weapon_groups[weapon_sel]["id"]) == "gun"
	for w in weapons:
		if w["type"] != "minigun":
			continue
		var pidx: int = int(w.get("part_idx", -1))
		var alive: bool = pidx < 0 or pidx >= aircraft.parts.size() or not aircraft.parts[pidx].get("broken", false)
		var target := 1.0 if (firing and alive and gun_sel) else 0.0
		var rate := (1.0 / MINIGUN_SPINUP) if target > float(w["spin"]) else (1.0 / MINIGUN_SPINDOWN)
		w["spin"] = move_toward(float(w["spin"]), target, rate * delta)
		var b = w.get("barrels")
		if b != null and is_instance_valid(b):
			b.rotate_z(float(w["spin"]) * MINIGUN_MAX_RPS * delta)
	# Kanonen: Dauerfeuer solange gehalten. Raketen/Lenkwaffen/Bomben: EIN Schuss
	# pro Klick (der naechste bereite Mount) — kein Salven-Dump der ganzen Gruppe mehr.
	if not weapon_groups.is_empty():
		var g: Dictionary = weapon_groups[weapon_sel]
		var gid := String(g["id"])
		if gid == "gun":
			if firing:
				_fire_primary(g["types"])
		elif fire_click:
			if gid == "bomb":
				_drop_bomb(true)
			else:
				_fire_primary(g["types"], true)
	var bomb_down := Input.is_physical_key_pressed(KEY_B)
	if bomb_down and not _bomb_held:
		_drop_bomb(true)   # B: ebenfalls eine Bombe pro Druck
	_bomb_held = bomb_down

	# --- Gegenmassnahmen: K = Waermefackeln, L = Dueppel ---------------------------
	# EIGENE TASTEN, KEINE UMBELEGUNG. K und L waren die einzigen freien Buchstaben und
	# liegen nebeneinander — im Gefecht greift man sie blind.
	_cm_cd = maxf(0.0, _cm_cd - delta)
	_lenk_meldung_t = maxf(0.0, _lenk_meldung_t - delta)
	var f_down := Input.is_physical_key_pressed(KEY_K)
	if f_down and not _flare_held:
		_werfen("flare")
	_flare_held = f_down
	var c_down := Input.is_physical_key_pressed(KEY_L)
	if c_down and not _chaff_held:
		_werfen("chaff")
	_chaff_held = c_down
	_warnung_takt()

	_wolken_ruetteln()
	_emit_hud()


# --- TURBULENZ IN DER WOLKE ------------------------------------------------------------
# `wolken_dichte` setzt Main jeden Frame (0 = freie Luft, 1 = mitten in einer Wolke,
# Quelle CloudField.dichte_bei_allen). Ohne das Ruetteln ist eine Wolke nur eine Farbe,
# durch die man hindurchfliegt — mit ihm ist sie ein Ort, der etwas mit dem Flugzeug macht.
#
# WARUM KEIN WEISSES RAUSCHEN: zufaellige Stoesse je Frame mitteln sich weg und fuehlen
# sich wie ein Defekt an. Drei ueberlagerte Sinus je Achse mit unrunden Frequenzen ergeben
# eine wandernde, nie exakt wiederkehrende Boe — das liest sich als Luft.
#
# ZAHLEN SIND KONSERVATIV GESETZT, NICHT EINGEFLOGEN: das Ruetteln soll spuerbar sein und
# die Maschine nicht unsteuerbar machen. Wer das nachjustiert, faengt bei TURBULENZ an.
const TURBULENZ := 0.55          # Drehmoment je Masse und Dichte
const TURBULENZ_HUB := 0.40      # Anteil davon als senkrechtes Sacken/Heben
var wolken_dichte := 0.0

func _wolken_ruetteln() -> void:
	if wolken_dichte <= 0.01 or not is_instance_valid(aircraft):
		return
	var t := float(Time.get_ticks_msec()) * 0.001
	var b := aircraft.global_transform.basis
	var w := Vector3(
		sin(t * 3.11) + 0.5 * sin(t * 7.31 + 1.3),
		sin(t * 2.29 + 1.7) + 0.5 * sin(t * 5.87),
		sin(t * 4.13 + 3.1) + 0.5 * sin(t * 8.69 + 0.4))
	var kraft := wolken_dichte * TURBULENZ * aircraft.mass
	# SCHUTZSCHRANKE. Diese Funktion schiebt Kraefte direkt in einen RigidBody3D. Kaeme
	# von irgendwoher ein NaN oder Unendlich in wolken_dichte, wuerde es hier in die
	# Physik verstaerkt — und ein RigidBody mit NaN-Geschwindigkeit reisst die ganze
	# Physikwelt mit. Lieber eine Boe auslassen als das Spiel verlieren.
	if not is_finite(kraft):
		wolken_dichte = 0.0
		return
	aircraft.apply_torque(b * w * kraft)
	# Senkrechter Anteil: das Sacken beim Einflug ist das, was man als Erstes merkt.
	aircraft.apply_central_force(Vector3.UP
		* (sin(t * 2.71) + 0.6 * sin(t * 6.13 + 2.2)) * kraft * TURBULENZ_HUB)


# Mündungsrichtung = Flugzeug-Vorwärts (-Z), Position = Welt-Offset des Mounts.
func _muzzle(off: Vector3) -> Vector3:
	return aircraft.global_transform * off


# Beim Bau: welche der WGROUPS traegt diese Zelle? Auswahl zurueck auf die erste.
func _rebuild_weapon_groups() -> void:
	weapon_groups.clear()
	for g in WGROUPS:
		for w in weapons:
			if String(w["type"]) in g["types"]:
				weapon_groups.append(g)
				break
	weapon_sel = 0


func _fire_primary(types: Array = [], single := false) -> void:
	if world_root == null:
		return
	var fwd := -aircraft.global_transform.basis.z.normalized()
	var av := aircraft.linear_velocity
	for w in weapons:
		if not types.is_empty() and not (String(w["type"]) in types):
			continue   # gehoert nicht zur ausgewaehlten Gruppe
		if w["cd"] > 0.0 or int(w["ammo"]) == 0:   # Cooldown läuft ODER aufgebraucht
			continue
		var pidx: int = int(w.get("part_idx", -1))
		if pidx >= 0 and pidx < aircraft.parts.size() and aircraft.parts[pidx].get("broken", false):
			continue   # Mount/Teil weggebrochen -> nicht feuern
		var pos: Vector3 = _muzzle(w["off"])
		var fired := false
		# Geschütz-Kaliber (mit Bullet-Drop): einheitlich aus der CALIBERS-Tabelle. Unbegrenzt.
		if CALIBERS.has(w["type"]):
			if w["type"] == "minigun" and float(w.get("spin", 0.0)) < MINIGUN_FIRE_SPIN:
				continue   # Gatling noch nicht auf Drehzahl
			var c: Dictionary = CALIBERS[w["type"]]
			_spawn("bullet", pos + fwd * 1.2, av + fwd * float(c["speed"]),
				float(c["life"]), float(c["dmg"]), float(c["drop"]), c["tcol"], float(c["tscl"]))
			w["cd"] = float(c["cd"])
			fired = true
		else:
			match w["type"]:
				"rocket":
					_spawn("missile", pos, av + fwd * 150.0, 6.0, 4.0)   # geradeaus, ungelenkt
					w["cd"] = 0.5
					fired = true
				"salvo":
					var rgt := aircraft.global_transform.basis.x.normalized()
					for s in [-1.0, 0.0, 1.0]:                            # 3er-Salve gefächert
						var d: Vector3 = (fwd + rgt * (float(s) * 0.12)).normalized()
						_spawn("missile", pos, av + d * 150.0, 6.0, 3.5)
					w["cd"] = 1.0
					fired = true
				"missile", "missile_heavy", "missile_drop":
					# EIN Zweig fuer alle drei — was sie unterscheidet, steht in
					# LENKWAFFEN und nicht hier. Wer eine vierte Lenkwaffe will, traegt
					# sie dort ein und muss diese Funktion nicht anfassen.
					if _lenkwaffe_starten(String(w["type"]), pos, fwd, av):
						w["cd"] = float(LENKWAFFEN[w["type"]]["cd"])
						fired = true
		if fired:
			# (Mündungsfeuer auf Wunsch entfernt — kein Blitz/Partikel beim Schießen.)
			# Rückstoß: Impuls entgegen der Mündungsrichtung (nach hinten = -fwd).
			aircraft.add_recoil(-fwd * float(RECOIL.get(w["type"], 0.0)))
			# Kamera-Shake je nach Kaliber (aus dem Rückstoß abgeleitet)
			add_shake(clampf(float(RECOIL.get(w["type"], 300.0)) / 9000.0, 0.02, 0.16))
			# Begrenzte Munition verbrauchen; bei 0 verschwindet das Bauteil (-> Aero neu).
			if int(w["ammo"]) > 0:
				w["ammo"] -= 1
				if int(w["ammo"]) == 0:
					aircraft.queue_detach(pidx)
			if single:
				return   # ein Klick = eine Rakete/Lenkwaffe (naechster Mount beim naechsten Klick)


## Welches Lenkwaffen-Baumuster würde der nächste Klick abfeuern?
##
## Das ist nicht dasselbe wie "was ist an Bord": eine Zelle kann drei verschiedene
## Lenkwaffen tragen, und die Aufschaltung muss die Werte DER Waffe verwenden, die
## tatsaechlich als naechste von der Schiene geht — sonst zeigt das HUD einen Radar-Lock
## an und es startet eine Waermesuchende.
func _naechste_lenkwaffe() -> String:
	if weapon_groups.is_empty():
		return ""
	var g: Dictionary = weapon_groups[weapon_sel]
	if String(g["id"]) != "missile":
		return ""
	for w in weapons:
		var ty := String(w["type"])
		if not LENKWAFFEN.has(ty) or not (ty in g["types"]):
			continue
		if int(w["ammo"]) == 0:
			continue
		var pidx: int = int(w.get("part_idx", -1))
		if pidx >= 0 and pidx < aircraft.parts.size() and aircraft.parts[pidx].get("broken", false):
			continue
		return ty
	return ""


## Eine Lenkwaffe von der Schiene lassen. Gibt false zurück, wenn die Bedingungen nicht
## stimmen (dann laeuft auch kein Cooldown und die Waffe bleibt am Flugzeug).
func _lenkwaffe_starten(typ: String, pos: Vector3, fwd: Vector3, av: Vector3) -> bool:
	var spec: Dictionary = LENKWAFFEN.get(typ, {})
	if spec.is_empty() or world_root == null:
		return false
	# RADARWAFFEN SCHIESSEN NICHT INS BLAUE. Ohne Aufschaltung gibt es nichts zu
	# beleuchten, und die Rakete waere von der ersten Sekunde an blind. Lieber die Waffe
	# behalten und es dem Piloten sagen.
	if bool(spec.get("lock_noetig", false)) and (lock_stufe < 2 or lock_ziel == null):
		_lenk_meldung = "KEIN LOCK"
		_lenk_meldung_t = 1.5
		return false
	var m := Missile.new()
	m.muster = String(spec["name"])
	m.sucher = String(spec["sucher"])
	m.koeder_gruppe = String(spec["koeder"])
	m.feind_gruppe = "target"
	m.schub = float(spec["schub"])
	m.brenndauer = float(spec["brenndauer"])
	m.cw = float(spec["cw"])
	m.max_g = float(spec["max_g"])
	m.lebensdauer = float(spec["lebensdauer"])
	m.schwerkraft = float(spec["schwerkraft"])
	m.sucher_kegel = float(spec["kegel"])
	m.erfassung = float(spec["erfassung"])
	m.lenkfaktor = float(spec["lenkfaktor"])
	m.zuender = float(spec["zuender"])
	m.sprengkraft = float(spec["kraft"])
	m.braucht_beleuchtung = bool(spec.get("beleuchtung", false))
	m.startverzug = float(spec.get("abwurf", 0.0))
	m.traegheitsphase = float(spec.get("traegheit", 1.0))
	m.traeger = aircraft
	# VORGABE DES ZIELS. Der Sucher startet aufgeschaltet, statt sich erst selbst etwas zu
	# suchen — sonst nimmt eine Waermesuchende beim Start das naechstbeste Objekt im
	# Blickfeld, und das ist selten das, was der Pilot im Fadenkreuz hatte.
	if lock_stufe >= 1 and is_instance_valid(lock_ziel):
		m.ziel = lock_ziel
	world_root.add_child(m)
	m.global_position = pos
	var start := av + fwd * float(spec["start_v"])
	if m.startverzug > 0.0:
		start += Vector3.DOWN * 3.0      # aus der Aufhaengung fallen lassen
	m.v = start
	return true


## Kassette abfeuern. Paarweise, mit kurzer Sperre — Dauerdruck leert nur den Vorrat.
func _werfen(art: String) -> void:
	if _cm_cd > 0.0 or not is_instance_valid(aircraft) or world_root == null:
		return
	var vorrat := flares if art == "flare" else chaff
	if vorrat <= 0:
		_lenk_meldung = "FACKELN LEER" if art == "flare" else "DUEPPEL LEER"
		_lenk_meldung_t = 1.4
		return
	var b := aircraft.global_transform.basis
	var av := aircraft.linear_velocity
	# NACH HINTEN UND ZUR SEITE AUSGESTOSSEN. Nach hinten, weil dort der Sucher hinsieht,
	# der einen von hinten verfolgt; zur Seite, damit sich Koeder und Flugzeug trennen —
	# ein Koeder, der genau mitfliegt, verdeckt nichts.
	for seite in [-1.0, 1.0]:
		var pos: Vector3 = aircraft.global_position + b * Vector3(seite * 1.2, -0.6, 1.8)
		var stoss: Vector3 = b * Vector3(seite * 7.0, -5.0, 9.0)
		Countermeasure.werfen(world_root, art, pos, av * 0.85 + stoss)
	if art == "flare":
		flares -= 1
	else:
		chaff -= 1
	_cm_cd = CM_TAKT


## Anflugwarnung: sucht die gefährlichste auf uns gerichtete Lenkwaffe.
##
## WARUM ES DIE BRAUCHT: Gegenmassnahmen ohne Warnung sind Raten. Erst wenn man weiss,
## dass etwas kommt, aus welcher Richtung und wie lange man noch hat, wird aus "Taste
## druecken" eine Entscheidung — jetzt werfen oder noch kurven?
func _warnung_takt() -> void:
	warn_aktiv = false
	if not is_instance_valid(aircraft):
		return
	var beste_zeit := 1.0e20
	var beste: Missile = null
	for n in get_tree().get_nodes_in_group("missile"):
		var m := n as Missile
		if m == null or not is_instance_valid(m) or m.feind_gruppe != "player":
			continue
		var zu: Vector3 = aircraft.global_position - m.global_position
		var d := zu.length()
		if d < 1.0:
			continue
		# Nur was sich naehert. Eine Rakete, die schon vorbei ist, ist keine Warnung wert.
		var nae := m.v.dot(zu / d)
		if nae < 40.0:
			continue
		var t := d / nae
		if t < beste_zeit:
			beste_zeit = t
			beste = m
	if beste == null:
		return
	warn_aktiv = true
	warn_zeit = beste_zeit
	var b := aircraft.global_transform.basis
	var rel: Vector3 = (beste.global_position - aircraft.global_position)
	# Winkel in der Flugzeugebene: 0 = voraus, positiv = nach rechts.
	warn_winkel = atan2(rel.dot(b.x), rel.dot(-b.z))


func _drop_bomb(single := false) -> void:
	var av := aircraft.linear_velocity
	for w in weapons:
		if w["type"] != "bomb" or w["cd"] > 0.0 or int(w["ammo"]) == 0:
			continue
		var pidx: int = int(w.get("part_idx", -1))
		if pidx >= 0 and pidx < aircraft.parts.size() and aircraft.parts[pidx].get("broken", false):
			continue   # Bombe schon weg/abgerissen
		_spawn("bomb", _muzzle(w["off"]), av, 12.0, 6.0, 24.0)   # Bombe fällt (Schwerkraft)
		add_shake(0.1)
		w["cd"] = 0.8
		if int(w["ammo"]) > 0:
			w["ammo"] -= 1
			if int(w["ammo"]) == 0:
				aircraft.queue_detach(pidx)   # Bombe verschwindet vom Modell -> Aero neu
		if single:
			return   # ein Druck = eine Bombe


func _spawn(kind: String, pos: Vector3, vel: Vector3, life: float, dmg: float,
		grav := 0.0, tcol := Color(1.0, 0.85, 0.2), tscl := 1.0) -> Projectile:
	var root := world_root if world_root != null else get_parent()
	if root == null:
		return null
	var p := Projectile.new()
	p.kind = kind
	p.vel = vel
	p.life = life
	p.damage = dmg
	p.gravity = grav        # Bullet-Drop / Bomben-Fall
	p.tracer_color = tcol
	p.tracer_scale = tscl
	root.add_child(p)       # _ready -> _build_visual nutzt die schon gesetzten Tracer-Werte
	p.global_position = pos
	return p


# Eingabe sanft Richtung Ziel führen (rise = drücken, fall = loslassen/zentrieren).
func _ramp(cur: float, target: float, delta: float, rise: float, fall: float) -> float:
	var rate := rise if absf(target) > absf(cur) else fall
	return move_toward(cur, target, rate * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Mausrad = Kamera-Abstand (gilt für Maus-Flug, Verfolger UND Free-Look/C)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_zoom_target = clampf(cam_zoom_target / CAM_ZOOM_STEP, CAM_ZOOM_MIN, CAM_ZOOM_MAX)   # ranzoomen
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom_target = clampf(cam_zoom_target * CAM_ZOOM_STEP, CAM_ZOOM_MIN, CAM_ZOOM_MAX)   # rauszoomen
			return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if free_look:
			# Free-Look (C): Maus schwenkt nur die Kamera frei um den Flieger (voll 360°), lenkt NICHT.
			flook_yaw = wrapf(flook_yaw - event.relative.x * FREE_LOOK_SENS, -PI, PI)
			flook_pitch = clampf(flook_pitch - event.relative.y * FREE_LOOK_SENS, -1.7, 1.7)
			return
		if mouse_fly:
			# Maus-Flug: Maus dreht die ZIELRICHTUNG frei in der Welt (360° horizontal).
			# Nach rechts schauen -> rechts; nach hinten schauen -> Flieger dreht ganz herum.
			# Beim Zoomen entspricht ein Mausweg einem VIEL groesseren Winkel am Ziel ->
			# Empfindlichkeit mitskalieren, sonst ist praezises Zielen unmoeglich.
			var zs := AIM_LOOK_SENS_BASE * sens_mult * lerpf(1.0, ZOOM_SENS, zoom_t)
			look_yaw = wrapf(look_yaw + event.relative.x * zs, -PI, PI)
			look_pitch = clampf(look_pitch - event.relative.y * zs, -AIM_PITCH_CLAMP, AIM_PITCH_CLAMP)
		else:
			# Umschauen: Kamera frei um das Flugzeug schwenken
			look_yaw = clampf(look_yaw - event.relative.x * LOOK_SENS, -PI, PI)
			look_pitch = clampf(look_pitch - event.relative.y * LOOK_SENS, -1.2, 1.35)
			_mouse_idle = 0.0
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_BACKSPACE or event.keycode == KEY_KP_ENTER:
			_reset_to_runway()
		elif event.keycode == KEY_N:
			# N = Maus-/Tastatur-Flug (war M; M oeffnet jetzt die KARTE — Signal an Main)
			_toggle_mouse_fly()
		elif event.keycode == KEY_M:
			map_requested.emit()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
			# 1-4 = Waffengruppe direkt anwaehlen (nur vorhandene)
			var wi: int = event.keycode - KEY_1
			if wi < weapon_groups.size():
				weapon_sel = wi
		elif event.keycode == KEY_X:
			# X = Waffengruppe durchschalten (war V; V ist jetzt der Zielzoom)
			if weapon_groups.size() > 1:
				weapon_sel = (weapon_sel + 1) % weapon_groups.size()
		elif event.keycode == KEY_H:
			g_protect = not g_protect
		elif event.keycode == KEY_J:
			_toggle_arcade()
		elif event.keycode == KEY_T and is_instance_valid(aircraft):
			aircraft.assist = not aircraft.assist
		elif event.keycode == KEY_G and is_instance_valid(aircraft):
			aircraft.toggle_gear()
		elif event.keycode == KEY_F:
			_flap_stage = (_flap_stage + 1) % FLAP_STAGES.size()   # Aus -> Start -> Landung -> Aus
		elif event.keycode == KEY_I and is_instance_valid(aircraft):
			aircraft.toggle_invert()


# Maus-Flug umschalten: Maus = Weltzielrichtung (an) <-> freies Umschauen (aus).
func _toggle_mouse_fly() -> void:
	mouse_fly = not mouse_fly
	if mouse_fly and is_instance_valid(aircraft):
		_reset_mouse_state()
	else:
		look_yaw = 0.0
		look_pitch = 0.0


# Regler-/Zielzustand frisch an der aktuellen Nase ausrichten (kein Ruck beim
# Einschalten oder Flugstart). Wird von set_active UND _toggle_mouse_fly genutzt.
func _reset_mouse_state() -> void:
	var f := -aircraft.global_transform.basis.z
	look_yaw = atan2(f.x, -f.z)
	look_pitch = asin(clampf(f.y, -1.0, 1.0))
	_aim_cmd = _aim_dir()
	_trim_pitch = 0.0
	_bank_offset = 0.0
	_prev_horiz = 0.0
	_horiz_rate = 0.0
	_prev_phi = 0.0
	_phi_rate = 0.0
	_rnp_on = false
	_k_rnp = 0.0
	_aim_prev = _aim_cmd
	_aim_ff = Vector3.ZERO
	_aim_live = false
	_wh_filt = 0.0
	# Kamera-Aim aus der AKTUELLEN Blickrichtung starten -> kein Kamera-Schnitt.
	if camera != null:
		_cam_aim = -camera.global_transform.basis.z


# Arcade-Lenkung umschalten. Braucht den Maus-Flug -> ggf. mit einschalten.
func _toggle_arcade() -> void:
	arcade = not arcade
	if arcade and not mouse_fly:
		_toggle_mouse_fly()


# Physisch erreichbare DAUER-Drehraten (x=Nick, y=Gier, z=Roll, rad/s) DIESES Baus:
# Torque-Gleichgewicht Steuer-Autorität (CTRL + CTRL_A·Fläche)·qfac·MOUSE_AUTH gegen
# Dämpfung DAMP·apq·(0.35+qfac) — exakt die Formeln aus AircraftBody._integrate_forces.
func _auth_rates() -> Vector3:
	var rho := AircraftBody.RHO0 * exp(-maxf(aircraft.global_position.y, 0.0) / AircraftBody.SCALE_H)
	var qf := clampf(0.5 * rho * aircraft.airspeed * aircraft.airspeed / 180.0, 0.04, 2.0)
	var apq := 1.6 if aircraft.assist else 1.0
	var dn := 0.35 + qf
	return Vector3(
		(AircraftBody.CTRL_PITCH + AircraftBody.CTRL_PITCH_A * aircraft.pitch_area) * qf * AircraftBody.MOUSE_AUTH / (AircraftBody.DAMP_PITCH * apq * dn),
		(AircraftBody.CTRL_YAW + AircraftBody.CTRL_YAW_A * aircraft.yaw_area) * qf * AircraftBody.MOUSE_AUTH / (AircraftBody.DAMP_YAW * apq * dn),
		(AircraftBody.CTRL_ROLL + AircraftBody.CTRL_ROLL_A * aircraft.roll_area) * qf * AircraftBody.MOUSE_AUTH / (AircraftBody.DAMP_ROLL * dn))


# Zielrichtung (Weltkoordinaten) aus look_yaw/look_pitch. yaw=0,pitch=0 -> -Z (vorne/Nord).
func _aim_dir() -> Vector3:
	var cp := cos(look_pitch)
	return Vector3(sin(look_yaw) * cp, sin(look_pitch), -cos(look_yaw) * cp)


# Stückweise lineare Tabelle [[x, y], ...] auswerten (Raten über Geschwindigkeit).
func _tab(x: float, tab: Array) -> float:
	if x <= tab[0][0]:
		return tab[0][1]
	for i in range(1, tab.size()):
		if x <= tab[i][0]:
			var f: float = (x - tab[i - 1][0]) / (tab[i][0] - tab[i - 1][0])
			return lerpf(tab[i - 1][1], tab[i][1], f)
	return tab[tab.size() - 1][1]


# Weicher Totbereich: unter AIM_DEADZONE = 0, bis AIM_DEADZONE_SOFT per Smoothstep
# eingeblendet, darüber unverändert -> kein „Knick" an der Totbereichs-Kante.
func _soft_dead(err: float) -> float:
	var ae := absf(err)
	if ae < AIM_DEADZONE:
		return 0.0
	if ae < AIM_DEADZONE_SOFT:
		var s := (ae - AIM_DEADZONE) / (AIM_DEADZONE_SOFT - AIM_DEADZONE)
		return signf(err) * s * s * (3.0 - 2.0 * s) * ae
	return err


# ---------------------------------------------------------------------------
# Verfolgerkamera
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if camera == null or not is_instance_valid(aircraft):
		return
	# Kamera-Shake: Anfragen vom Flugzeug (Aufprall/Explosion/Bruch) aufnehmen + abklingen
	_cam_shake = minf(_cam_shake + aircraft.shake_request, 1.4)
	aircraft.shake_request = 0.0
	_cam_shake = maxf(0.0, _cam_shake - delta * CAM_SHAKE_DECAY)
	# FOV-Speed-Zoom: weitet sich mit dem Tempo (sanft nachgeführt) -> Speed-Gefühl
	# V gehalten -> Zielzoom. Gepollt (nicht ueber _unhandled_input), damit HALTEN zaehlt.
	zoom_t = move_toward(zoom_t, 1.0 if Input.is_physical_key_pressed(KEY_V) else 0.0,
		delta * ZOOM_RATE)
	var fov_target := lerpf(FOV_BASE, FOV_MAX, clampf(aircraft.airspeed / FOV_SPEED, 0.0, 1.0))
	if zoom_t > 0.0:
		fov_target = lerpf(fov_target, FOV_ZOOM, zoom_t)
	# Glättung im vertikalen FOV halten, dann ultrawide-bewusst anwenden (kein Fischauge auf 32:9).
	_cam_vfov = lerpf(_cam_vfov, fov_target, _glatt(2.5, delta))
	ViewUtil.apply_vfov(camera, _cam_vfov)
	# Mausrad-Zoom weich nachführen -> sanfte Distanz-Transition statt hartem Sprung pro Raste
	cam_zoom = lerpf(cam_zoom, cam_zoom_target, _glatt(CAM_ZOOM_SMOOTH, delta))
	# INTERPOLIERTE Transform: das Flugzeug rendert seit physics_interpolation
	# glatt mit Display-Rate — eine an der ROHEN 60-Hz-Physikposition verankerte
	# Kamera ließe es relativ zur Kamera zittern (genau das gemeldete Beben).
	var t := aircraft.get_global_transform_interpolated()
	if free_look:
		# C halten: Kamera orbitet als KUGEL (konstanter Abstand) um die Flugzeug-Mitte (Schwerpunkt).
		# Die Orientierung wird DIREKT aus Heading + Free-Look-Winkeln gebaut (kein look_at) -> smooth
		# über den Scheitel, KEIN 180°-Flip beim Drüberfahren. Flug läuft normal weiter.
		var center: Vector3 = t * aircraft.center_of_mass
		var heading: float = atan2(t.basis.z.x, t.basis.z.z)   # horizontale "Hinten"-Richtung
		var b_target := Basis(Vector3.UP, heading + flook_yaw) * Basis(Vector3.RIGHT, flook_pitch)
		if not _flook_was:
			_flook_basis = camera.global_transform.basis.orthonormalized()   # sanfter Einstieg aus aktueller Sicht
		_flook_was = true
		# Nur die ORIENTIERUNG glätten; die POSITION folgt dem (auch schnellen) Flieger STARR -> kein Lag.
		_flook_basis = _flook_basis.slerp(b_target, _glatt(12.0, delta)).orthonormalized()
		camera.global_transform = Transform3D(_flook_basis, center + _flook_basis.z * (FREE_LOOK_DIST * cam_zoom))
		_apply_cam_shake()
		return
	# Free-Look-Winkel sanft zurückstellen, wenn nicht (mehr) aktiv
	_flook_was = false
	flook_yaw = lerpf(flook_yaw, 0.0, _glatt(5.0, delta))
	flook_pitch = lerpf(flook_pitch, 0.0, _glatt(5.0, delta))
	if mouse_fly:
		# Kamera blickt in die ZIELRICHTUNG (Maus), Flugzeug im Vordergrund -> du siehst,
		# wohin du zeigst und wie die Nase nachzieht. Kein Zurückschwenken (Ziel bleibt stehen).
		# WICHTIG: die Kamera folgt einer EIGENEN geglätteten Richtung (_cam_aim, 12/s wie
		# Free-Look) — vorher ruckte das harte look_at entlang der rohen Maus bei jedem Tick.
		_cam_aim = _cam_aim.lerp(_aim_dir(), _glatt(CAM_AIM_SMOOTH, delta)).normalized()
		# Up-Referenz WEICH von Welt-UP auf Flugzeug-Up blenden, statt bei 0.97 hart zu
		# flippen -> kein sichtbarer Horizont-Sprung beim Senkrechtziehen.
		var upk := clampf((absf(_cam_aim.dot(Vector3.UP)) - UP_BLEND_LO) / (UP_BLEND_HI - UP_BLEND_LO), 0.0, 1.0)
		var up_ref := Vector3.UP.lerp(t.basis.y, upk).normalized()
		# Kamera-Höhe UND Blickpunkt-Höhe GLEICH -> die Kamera blickt exakt entlang der
		# Zielrichtung (_cam_aim), d.h. der Aim-Kreis sitzt MITTIG. Der Flieger sitzt durch die
		# Kamerahöhe trotzdem tief im Bild. Höhe mit dem echten vertikalen FOV skalieren (32:9
		# schmal) -> gleiches Framing auf jedem Seitenverhältnis. Abstand nur per Zoom.
		var fov_fac := tan(ViewUtil.actual_vfov_rad(camera) * 0.5) / tan(deg_to_rad(FOV_BASE) * 0.5)
		var cam_h := CAM_HEIGHT * fov_fac * cam_zoom
		var cam_pos := t.origin - _cam_aim * (13.0 * cam_zoom) + Vector3.UP * cam_h
		# Geschwindigkeits-Vorhalt: der 8/s-Lerp hinkt sonst ~v/8 m hinterher (bei 100 m/s
		# über 12 m extra Abstand!) -> Vorhalt hält die Distanz auch bei Highspeed stabil.
		cam_pos += aircraft.linear_velocity * (CAM_LEAD / 8.0)
		camera.global_position = camera.global_position.lerp(cam_pos, _glatt(8.0, delta))
		camera.look_at(t.origin + _cam_aim * 30.0 + Vector3.UP * cam_h, up_ref)
		_apply_cam_shake()
		return
	# Ohne Mausbewegung sanft zur Verfolgeransicht zurückschwenken
	_mouse_idle += delta
	if _mouse_idle > LOOK_RECENTER:
		var k := _glatt(2.2, delta)
		look_yaw = lerpf(look_yaw, 0.0, k)
		look_pitch = lerpf(look_pitch, 0.0, k)
	var desired := t.origin + _cam_offset(t)
	# Geschwindigkeits-Vorhalt (s.o.): hält den Verfolger-Abstand auch bei Highspeed stabil.
	desired += aircraft.linear_velocity * (CAM_LEAD / 6.0)
	camera.global_position = camera.global_position.lerp(desired, _glatt(6.0, delta))
	camera.look_at(t.origin + Vector3.UP * 0.8, Vector3.UP)
	_apply_cam_shake()


# Kamera-Shake auslösen (Feuer/Aufprall) und anwenden (Positions- + Roll-Jitter, quadratisch).
func add_shake(amount: float) -> void:
	_cam_shake = minf(_cam_shake + amount, 1.4)


## BILDRATENUNABHAENGIGER GLAETTUNGSFAKTOR.
##
## Ueberall im Kameracode stand vorher `clampf(delta * rate, 0, 1)`. Das ist die
## Linearisierung von `1 - exp(-rate * delta)` und stimmt nur, solange delta klein ist.
## Bei einem langen Frame zieht sie ZU WEIT: mit rate 6 und 60 ms Frame liefert die
## Linearisierung 0.60 statt korrekt 0.45.
##
## GENAU DAS war das gemeldete "Flugzeug zittert kurz zurueck in der Kamera" beim
## Nachladen: die Kamera ueberschwingt bei einem langen Frame nach vorn, also rutscht
## das Flugzeug im Bild zur Kamera zurueck. Gerechnet (Verfolgerkamera, 170 m/s):
##      Frame     linear (vorher)   exponentiell (jetzt)
##       25 ms        -0.21 m            -0.09 m
##       40 ms        -0.95 m            -0.40 m
##       60 ms        -2.65 m            -1.03 m
##      100 ms        -8.50 m            -2.83 m
## Das beseitigt den Ruck nicht, wenn ein Frame wirklich lange dauert — der Flieger legt
## in 60 ms nun einmal 10 m zurueck — aber es nimmt die UEBERREAKTION der Kamera heraus,
## und die war zweieinhalb- bis dreimal so gross wie die Bewegung selbst.
static func _glatt(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


func _apply_cam_shake() -> void:
	if _cam_shake <= 0.001:
		return
	var s := _cam_shake * _cam_shake   # quadratisch -> satter Stoß, sanftes Ausklingen
	var b := camera.global_transform.basis
	var off: Vector3 = b.x * randf_range(-1.0, 1.0) + b.y * randf_range(-1.0, 1.0)
	camera.global_position += off * (s * CAM_SHAKE_POS)
	camera.rotate_object_local(Vector3(0, 0, 1), randf_range(-1.0, 1.0) * s * CAM_SHAKE_ROLL)


# Kamera-Versatz hinter dem Flugzeug, per Umschau-Winkeln (look_yaw/pitch) gedreht.
# look=0 -> klassische Verfolgeransicht.
func _cam_offset(t: Transform3D) -> Vector3:
	var base: Vector3 = t.basis.z.normalized() * 12.0 + Vector3.UP * 3.8
	var off: Vector3 = Basis(Vector3.UP, look_yaw) * base
	var rightax: Vector3 = off.cross(Vector3.UP)
	if rightax.length() > 0.01:
		off = Basis(rightax.normalized(), look_pitch) * off
	return off * cam_zoom * lerpf(1.0, ZOOM_DIST, zoom_t)


func _snap_camera() -> void:
	if camera == null or not is_instance_valid(aircraft):
		return
	var t := aircraft.global_transform
	camera.global_position = t.origin + _cam_offset(t)
	camera.look_at(t.origin + Vector3.UP * 0.8, Vector3.UP)


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------
func _update_markers() -> void:
	# Zielmarker = wohin die Maus zeigt (Weltrichtung), Nasenmarker = wohin die Nase zeigt.
	# Decken sie sich, fliegt das Flugzeug genau aufs Ziel.
	var vp := get_viewport().get_visible_rect().size
	var ctr := vp * 0.5
	if camera == null or not camera.is_inside_tree():
		aim_screen = ctr
		nose_screen = ctr
		aim_visible = false
		nose_visible = false
		return
	var ti := aircraft.get_global_transform_interpolated()
	var ap := ti.origin + _aim_dir() * 400.0
	var np := ti.origin - ti.basis.z * 400.0
	aim_visible = not camera.is_position_behind(ap)
	nose_visible = not camera.is_position_behind(np)
	aim_screen = camera.unproject_position(ap) if aim_visible else ctr
	# Nasenmarker zusätzlich pixelgeglättet (kleine Restbewegung der Nase nicht sichtbar zittern)
	if nose_visible:
		var raw := camera.unproject_position(np)
		_nose_px = raw if _nose_px == Vector2.ZERO else _nose_px.lerp(raw, AIM_MARK_SMOOTH)
		nose_screen = _nose_px
	else:
		_nose_px = Vector2.ZERO
		nose_screen = ctr
	# BALLISTISCHER PIPPER: wohin fliegen die Kugeln WIRKLICH? Erste Kanone mit
	# Munition: v0 = Flugzeug-Geschwindigkeit + Mündungsgeschwindigkeit nach vorn,
	# darüber der kaliberabhängige Bullet-Drop bis zur Referenzdistanz (erfasstes
	# Ziel oder 400 m). Deckt Eigenfahrt-Versatz UND Drop ab — im Gegensatz zum
	# alten statischen Bildmitte-Kreuz, das nichts mit der Flugbahn zu tun hatte.
	gun_visible = false
	for w in weapons:
		var ty := String(w.get("type", ""))
		if not CALIBERS.has(ty) or int(w.get("ammo", -1)) == 0:
			continue
		var pidx: int = int(w.get("part_idx", -1))
		if pidx >= 0 and pidx < aircraft.parts.size() and aircraft.parts[pidx].get("broken", false):
			continue
		var cal: Dictionary = CALIBERS[ty]
		var fwd := -aircraft.global_transform.basis.z
		var v0: Vector3 = aircraft.linear_velocity + fwd * float(cal["speed"])
		var dist := lock_dist if (lock_active and lock_visible and lock_dist > 10.0) else 400.0
		var tfly := dist / maxf(v0.dot(fwd), 60.0)
		var pp: Vector3 = _muzzle(w["off"]) + v0 * tfly + Vector3.UP * (-0.5 * float(cal["drop"]) * tfly * tfly)
		if not camera.is_position_behind(pp):
			var rawg := camera.unproject_position(pp)
			_gun_px = rawg if _gun_px == Vector2.ZERO else _gun_px.lerp(rawg, AIM_MARK_SMOOTH)
			gun_screen = _gun_px
			gun_visible = true
		else:
			_gun_px = Vector2.ZERO
		break


# Waffengruppen fuer die HUD-Leiste: Label + Restmunition (-1 = unbegrenzt).
# Waffen auf abgebrochenen Teilen zaehlen nicht mehr mit.
func _wgroups_hud() -> Array:
	var out: Array = []
	for g in weapon_groups:
		var cnt := 0
		var inf := false
		for w in weapons:
			if not (String(w["type"]) in g["types"]):
				continue
			var pidx: int = int(w.get("part_idx", -1))
			if pidx >= 0 and is_instance_valid(aircraft) and pidx < aircraft.parts.size() \
					and aircraft.parts[pidx].get("broken", false):
				continue
			var a: int = int(w["ammo"])
			if a < 0:
				inf = true
			else:
				cnt += a
		out.append({"label": g["label"], "count": (-1 if inf else cnt)})
	return out


# Restmunition der begrenzten Waffen (Raketen/Lenkwaffen/Bomben) je Kategorie summiert.
func _ammo_text() -> String:
	var rockets := 0
	var missiles := 0
	var bombs := 0
	var has_r := false
	var has_m := false
	var has_b := false
	for w in weapons:
		var a: int = int(w["ammo"])
		match String(w["type"]):
			"rocket", "salvo":
				has_r = true
				rockets += maxi(a, 0)
			"missile", "missile_heavy", "missile_drop":
				has_m = true
				missiles += maxi(a, 0)
			"bomb":
				has_b = true
				bombs += maxi(a, 0)
	var parts: Array = []
	if has_r:
		parts.append("Rak. %d" % rockets)
	if has_m:
		parts.append("Lenk. %d" % missiles)
	if has_b:
		parts.append("Bomben %d" % bombs)
	return "   ".join(parts)


# Nasenkurs in Grad (0 = Nord/-Z, im Uhrzeigersinn: O=90, S=180, W=270).
func _heading_deg() -> float:
	var fwd := -aircraft.global_transform.basis.z
	return fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)


func _has_guided_ammo() -> bool:
	for w in weapons:
		var ty: String = w.get("type", "")
		if ty == "missile" or ty == "missile_heavy" or ty == "missile_drop":
			if int(w.get("ammo", -1)) != 0:
				return true
	return false


# --- AUFSCHALTUNG ----------------------------------------------------------------------
#
# WAS SICH GEAENDERT HAT UND WARUM. Vorher galt ein fester 30-Grad-Kegel und 230 m
# Reichweite fuer ALLE Lenkwaffen — unabhaengig davon, welche gerade an der Reihe war.
# Damit war die Anzeige eine Behauptung: sie zeigte "erfasst" auch dort, wo die Waffe
# nichts sehen konnte, und blieb dunkel, wo eine Radarwaffe laengst haette schiessen
# koennen. Jetzt liest die Aufschaltung ihre Werte aus dem Baumuster, das als naechstes
# von der Schiene geht (_naechste_lenkwaffe) — die Anzeige sagt damit die Wahrheit.
#
# ZWEI STUFEN. Eine Waermesuchende ist sofort bereit, sobald ihr Sucher etwas hat; eine
# halbaktive Radarwaffe braucht knapp eine Sekunde ruhige Nase, bevor sie aufgeschaltet
# ist. Diese Wartezeit ist kein Schikane, sondern der Grund, warum die beiden Waffen sich
# im Gefecht verschieden anfuehlen.
func _update_lock() -> void:
	lock_active = false
	lock_visible = false
	lock_typ = _naechste_lenkwaffe()
	if lock_typ == "" or camera == null or not camera.is_inside_tree() \
			or not is_instance_valid(aircraft):
		lock_stufe = 0
		lock_ziel = null
		_lock_zeit = 0.0
		return
	var spec: Dictionary = LENKWAFFEN[lock_typ]
	# Der Aufschaltkegel ist ENGER als der Sucherkegel: der Pilot zielt, danach uebernimmt
	# der Suchkopf und darf mehr sehen als der Pilot ihm vorgeben konnte.
	var kegel := cos(deg_to_rad(minf(float(spec["kegel"]), 28.0)))
	var reich := float(spec["erfassung"])
	var origin := aircraft.global_position
	var fwd := -aircraft.global_transform.basis.z
	var best: Node3D = null
	var best_d := 1.0e20
	for t in get_tree().get_nodes_in_group("target"):
		if not is_instance_valid(t):
			continue
		var to: Vector3 = (t as Node3D).global_position - origin
		var dist := to.length()
		if dist < 2.0 or dist > reich:
			continue
		if fwd.dot(to / dist) < kegel:
			continue
		if dist < best_d:
			best_d = dist
			best = t
	if best == null:
		lock_stufe = 0
		lock_ziel = null
		_lock_zeit = 0.0
		return
	# Zielwechsel setzt die Uhr zurueck — man kann sich nicht von einem Ziel zum naechsten
	# "durchschalten" und dabei die Aufschaltzeit mitnehmen.
	if best != lock_ziel:
		_lock_zeit = 0.0
	lock_ziel = best
	_lock_zeit += get_physics_process_delta_time()
	lock_dist = best_d
	lock_stufe = 1
	if not bool(spec.get("lock_noetig", false)) or _lock_zeit >= LOCK_DAUER:
		lock_stufe = 2
	if not camera.is_position_behind(best.global_position):
		lock_screen = camera.unproject_position(best.global_position)
		lock_visible = true
	lock_active = true


func _emit_hud() -> void:
	if not is_instance_valid(aircraft):
		return
	_update_markers()
	_update_lock()
	hud_changed.emit({
		"lock": lock_screen,
		"lock_vis": lock_visible,
		"lock_active": lock_active,
		"lock_stufe": lock_stufe,
		"lock_dist": lock_dist,
		"lock_name": String(LENKWAFFEN[lock_typ]["name"]) if LENKWAFFEN.has(lock_typ) else "",
		"lock_sucher": String(LENKWAFFEN[lock_typ]["sucher"]) if LENKWAFFEN.has(lock_typ) else "",
		"flares": flares,
		"chaff": chaff,
		"warn_aktiv": warn_aktiv,
		"warn_winkel": warn_winkel,
		"warn_zeit": warn_zeit,
		"lenk_meldung": _lenk_meldung if _lenk_meldung_t > 0.0 else "",
		"mouse_fly": mouse_fly,
		"zoom": (FOV_BASE / maxf(lerpf(FOV_BASE, FOV_ZOOM, zoom_t), 1.0)) if zoom_t > 0.02 else 0.0,
		"arcade": arcade,
		"aim": aim_screen,
		"nose": nose_screen,
		"gun": gun_screen,
		"gun_vis": gun_visible,
		"g_protect": g_protect,
		"aim_vis": aim_visible,
		"nose_vis": nose_visible,
		"throttle": throttle,
		"heading": _heading_deg(),
		"speed": aircraft.airspeed,
		"kmh": aircraft.airspeed * 3.6,
		"alt": aircraft.altitude,
		"aoa": aircraft.aoa_deg,
		"climb": aircraft.climb,
		"stall": aircraft.stall,
		"gforce": aircraft.gforce,
		"thrust": aircraft.total_thrust,
		"assist": aircraft.assist,
		"flaps": FLAP_NAMES[_flap_stage],
		"ammo": _ammo_text(),
		"wgroups": _wgroups_hud(),
		"wsel": weapon_sel,
		"gear": aircraft.gear_status,
		"wings": aircraft.wing_status,
		"inverted": aircraft.inverted,
		"land_msg": aircraft.landing_msg,
		"pos": aircraft.global_position,
	})
