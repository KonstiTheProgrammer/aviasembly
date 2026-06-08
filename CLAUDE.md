# CLAUDE.md — Projekt-Kontext für Aviassembly

> Diese Datei wird von Claude Code automatisch als Kontext geladen. Sie fasst
> alles zusammen, damit eine andere Claude-Instanz (auf einem anderen Gerät)
> sofort produktiv weiterarbeiten kann.

## Was ist das?
**Aviassembly** — ein 3D-Flugzeug-Baukasten in **Godot 4.6** (wie SimplePlanes, im
Kleinen). Im **Hangar** baust du aus Modulen ein Flugzeug, per **Tab** wechselst du
in den **Testflug** mit echter (arcade-tauglicher, aber physikalisch fundierter)
Flugphysik. Wie du baust, bestimmt wie es fliegt.

- **Engine:** Godot **4.6.2** (Forward+/Metal). UI/Welt/Flügel weiterhin **prozedural**;
  die Bauteil-Modelle für **Rumpf, Triebwerke, Fahrwerk** sind **in Blender modelliert**
  (glTF in `res://models/*.glb`, via MCP-Blender erzeugt). Flügel/Leitwerk bleiben
  prozedural (Airfoil-Loft). Siehe Abschnitt „Bauteil-Modelle (Blender/glTF)".
- **Projektpfad (dieses Gerät):** `/Users/konstantinkanzler/Downloads/aviasembly`
- **Sprache der UI/Kommentare:** Deutsch.

## Starten, Testen, Iterieren (WICHTIG)
Godot-Binary (macOS): `/Applications/Godot.app/Contents/MacOS/Godot`

- **AUTOSTART (Wunsch des Nutzers):** Nach jeder abgeschlossenen + verifizierten Änderung
  (committet) das Spiel AUTOMATISCH via Godot-MCP `run_project` starten — NICHT auf „start an"
  warten. Laufende Instanz vorher ggf. `stop_project`.
- **Spiel starten (GUI):** über das Godot-MCP `run_project` / `get_debug_output` /
  `stop_project`, projectPath = Projektordner. (Es gibt keinen Screenshot der
  Godot-Szene — Verifikation läuft über Debug-Output + Headless-Tests.)
- **Compile-/Fehlercheck (headless):**
  `Godot --headless --editor --path . --quit-after 3`  → stderr nach „SCRIPT ERROR"
  durchsuchen. (Die Warnung „Scan thread aborted" ist nur ein Shutdown-Artefakt.)
- **Flugphysik headless testen:** `tools/phys_test.gd` ist ein SceneTree-Skript:
  `Godot --headless --path . --script res://tools/phys_test.gd`
  → loggt Start/Steig/… Telemetrie. So wurde das Flugmodell getunt.

### Headless-Test-FALLE (mehrfach reingefallen!)
In einem `extends SceneTree` `--script`-Lauf läuft `_initialize()` **bevor** die Nodes
ihr `_ready()` bekommen. Daher Setup (BuildController/FlightController instanzieren,
`load_design`, `build_from_design`) **erst im ersten `_process(delta)`-Frame** machen,
sonst ist z. B. `design_root` noch `null` und `_ready`-Effekte (Kollaps, contact_monitor)
sind noch nicht aktiv.

## Dateien & Verantwortung
```
project.godot            Godot 4.6, Hauptszene res://scenes/Main.tscn, forward_plus
scenes/Main.tscn         nur ein Node3D-Wurzelknoten + Main.gd
scripts/Main.gd          Welt (Licht/Himmel + blauer Blueprint-Raum), Modus BUILD<->FLY,
                         gesamtes UI (Bau-Panel links, Flug-HUD), Speichern/Laden
                         (user://aircraft_design.json), Start-Flugzeug (_default_design).
                         Teile-Palette: aufklappbare Kategorie-Sektionen (▾/▸) mit Grid aus
                         3D-Vorschau-Kacheln. Jede Kachel = eigener SubViewport (own_world_3d,
                         eigene Cam+Licht+Environment, UPDATE_ONCE) der das Teil-Visual rendert.
                         Helfer: _make_part_tile/_make_preview/_visual_aabb/_style_tile.
                         Auswahl exklusiv via ButtonGroup (_part_group), aktiv = grüner Rahmen
                         (_refresh_tool_ui setzt button_pressed). STOLPERFALLE: Kamera ist beim
                         Bauen noch nicht im Baum -> look_at() schlägt fehl, daher
                         look_at_from_position() nutzen.
scripts/PartCatalog.gd   class_name PartCatalog (statisch). Alle Bauteile als Dicts +
                         build_visual(): lädt zuerst ein BLENDER-glTF-Modell
                         (res://models/<id>.glb) falls vorhanden (has_model/_attach_model),
                         sonst prozedural. Lackieren via _recolor_model (überschreibt nur
                         Material-Slots in PAINT_MATS = body/cockpit_body/tankmetal/engine).
                         part_drag()/part_cd(), WING_STRESS-Konstante.
                         Prozeduraler Fallback (Flügel + falls glTF fehlt) via _revolve() (Rotationskörper um Z,
                         outward-Wicklung, gedeckelt; Einheitsform r<=0.5/z[-0.5,0.5],
                         per Node-Scale auf size gezogen): Rumpf=ellipt. Tubus,
                         Nase/Heck=Ogive (_ogive_profile), Tank=Kapsel (_capsule_profile),
                         Cockpit=Rumpf+Glas-Blasenkanzel, Prop=Tubus+Ogiven-Spinner+
                         getwistete Blätter, Jet=Tubus+Torus-Einlauflippe+Schubdüse+
                         Nachbrenner, Rad=Torus-Reifen+Felge+Nabe+Federbein. Helfer
                         _mi(mesh,mat,pos,rot,scl). build_visual bleibt drop-in (Root-
                         Node3D mit MeshInstance3D-Kindern; "Prop"-Node für Flugrotation;
                         col = Hauptfarbe -> Lackieren/Recolor + Windkanal-Shader gehen weiter).
scripts/BuildController.gd  class_name BuildController. Hangar-Editor: Orbit-Kamera,
                         Drag&Snap (flächenbündig), Werkzeuge (Setzen/Bewegen/Abriss/
                         Lackieren), R-Drehen/Kippen, Symmetrie, Undo/Redo, Windkanal-
                         Ansicht, Zoom, Statistik, Schwerpunkt-/Auftriebspunkt-Marker
scripts/FlightController.gd class_name FlightController. Baut AircraftBody aus dem
                         Design, Steuerungs-Eingaben, Verfolgerkamera, HUD-Daten,
                         Spawn/Reset (Reset = komplettes Neuaufbauen).
scripts/AircraftBody.gd  class_name AircraftBody extends RigidBody3D. Das Flugmodell +
                         Schaden (Fahrwerk, Flügelbruch, Landung).
tools/phys_test.gd       Headless-Flugtest (kein Spielinhalt, nur Dev-Werkzeug).
README.md                Steuerung + Feature-Überblick (Spielersicht).
```

## Flugmodell (AircraftBody.gd) — so funktioniert's
**Bewusst „gebündelte Koeffizienten-Methode" (lumped), NICHT pro-Fläche.** Die volle
Streifentheorie pro Fläche war bei 60 Hz numerisch instabil (Frame-Oszillation,
Kraftspikes). Das gebündelte Modell ist stabil und trotzdem physikalisch fundiert:

- **Auftrieb:** `Cl = lerp(Cl_α·α, sin 2α, σ)` mit `Cl_α = 2π·AR/(AR+2)` (endlicher
  Flügel) und Stall-Übergang `σ` (smoothstep um STALL_A). `α` aus Körpergeschwindigkeit
  + INCIDENCE (Flügel-Einstellwinkel, damit es früh abhebt).
- **Widerstand:** `Cd0 + Cl²/(π·AR·e)` (induziert) **plus** parasitärer Modell-Widerstand
  `drag_area` (aus den Bauteil-Stirnflächen, siehe `PartCatalog.part_drag`). Flügel-Widerstand
  nutzt den ECHTEN Staudruck (NICHT mit `LIFT_K` aufgebläht), damit Sturzflüge Tempo aufbauen.
  Kraft-Limit (`tf.limit_length`) ist nur NaN-/Runaway-Sicherung (`mass·130`) und klippt die
  normale Aero/den Schub bei Highspeed nicht mehr — sonst deckelte es die Sturzflug-Speed.
- **Schub:** Pro Triebwerk in dessen **Blickrichtung** (`dir` = −Z der Teil-Basis, körper-
  lokal; im Flug `basis*dir`). Zeigt eine Engine nach oben, schiebt sie nach oben. Die Kraft
  greift an der **Triebwerksposition** an → off-center-Schub erzeugt ein **Drehmoment um den
  COM** (`r×F`, `r = basis*(pos−center_of_mass)`, in `tt`): ein hinten montiertes, nach oben
  zeigendes Triebwerk kippt die Nase nach unten (vorne über). Schub auf der COM-Achse (normale
  Flieger, symmetrische Paare) → `r×F≈0`, also kein Zusatzmoment (keine Regression). Drehmoment
  bleibt durch `tt.limit_length(mass·90)` + `MAX_ANGVEL` gedeckelt (kein NaN/Runaway).
  **Reverse-Option** (Prop, Editor-Haken `thrust_reverse`) kehrt `dir` um (Bremse/Rückwärts).
  Propellerschub fällt mit Tempo entlang der Schubrichtung (`PROP_VMAX`), Jet konstant.
  **Negativer Schub = Bremse** (Luftbremse + am Boden Radbremse).
- **Statische Stabilität:** kleine Wetterfahnen-Momente (Nase folgt Anströmung),
  skaliert mit Leitwerksfläche (`pitch_area`/`yaw_area`).
- **Steuerung = DIREKTE Steuerflächen (SimplePlanes-Feel):** Eingabe = Auslenkung →
  Drehmoment `cmd · qfac · mass` (Autorität skaliert mit Staudruck `qfac`: langsam teigig,
  schnell knackig). Dazu aerodynamische **Drehdämpfung** `−ω_body · DAMP · (0.35+qfac)`
  gegen Überschwingen + statische Stabilität (Wetterfahne). KEIN Raten-Halte-Autopilot.
  **Roll immer knackig** (hohe Basis-`CTRL_ROLL`, von Assist-Dämpfung ausgenommen). **T**:
  Assist an = mehr Nick/Gier-Dämpfung + sanftes Querlage-Ausnivellieren (`LEVEL_K`), aus =
  roh/direkt. Eingabe wird im FlightController weich gerampt (`_ramp`, analoges Gefühl).
- **Luftdichte** sinkt mit Höhe: `ρ = RHO0·e^(−h/SCALE_H)`.
- **Sicherheit:** Kräfte werden auf `mass·60`/`mass·90` begrenzt, NaN-Werte verworfen,
  Drehrate auf `MAX_ANGVEL` geklemmt.

### Tuning-Konstanten (AircraftBody, oben in der Datei)
`LIFT_K=2.9` (globaler Auftrieb/Spielgefühl, früh abheben), `INCIDENCE≈0.075`,
`STALL_A=0.27`, `CL_MAX=1.5`, `CD0=0.03`, `OSWALD=0.75`, `SIDE=0.5`,
`PITCH_STAB=0.5`/`YAW_STAB=0.6`, `PROP_VMAX=170`, `DRAG_K=0.5`, `MAX_ANGVEL=8`,
Kraft-Limit `tf=mass·130`/`tt=mass·90` (nur Sicherung),
Direktsteuerung: Autorität `CTRL_PITCH=2.2`(+`3.5`·Fläche)/`CTRL_YAW=1.5`(+`3.0`)/
`CTRL_ROLL=9.0`(+`6.0`), Dämpfung `DAMP_PITCH=5.5`/`DAMP_YAW=3.2`/`DAMP_ROLL=2.5`
(Assist ×1.6 nur Nick/Gier), `LEVEL_K=1.0`, `qfac=clamp(q/180,0.04,2.0)`,
Landung: `HARD_LAND=3`/`BREAK_LAND=7` m/s. Reifenreibung `friction=0.05`.
`PartCatalog.WING_STRESS=3600` N/m² (Flügel-Belastbarkeit).
Spawn: Startbahn `(0, spawn_height, 40)`, `spawn_height = 0.3 − tiefster Punkt`.

### Schadensmodell
- **Fahrwerk-Überlast:** Σ Traglast (`gear_capacity`) < Masse → Kollaps beim Bauen
  angezeigt; im Flug knickt's weg (Kollision aus, Bauchlandung, mehr Widerstand).
- **Harte Landung:** Sinkrate beim Aufsetzen (`get_contact_count()>0` + letztes `v.y`):
  >3 m/s = Warnung, >7 m/s = **Fahrwerk bricht**.
- **Flügelbruch:** zu viel Auftrieb (G) > `wing_capacity` → Hauptflügel **reißen physisch
  ab** als Trümmer-RigidBody und nehmen **alles auswärts darauf Montierte mit** (Triebwerke,
  Winglets …). Welche Teile mitkommen, bestimmt ein **Verbindungs-Baum** (`_build_parents`,
  BFS ab Cockpit über Box-Nachbarschaft `_attached`): nur der **Teilbaum auswärts** der Flügel
  bricht — der Rumpf/Träger (Vorfahr) bleibt dran. Danach wird das **Flugmodell aus den
  übrigen Teilen NEU berechnet** (`recompute_aero`): fehlender Schub/fehlende Flügelfläche/
  Gewicht/COM zählen sofort. Dafür trägt jedes `parts`-Element seine Aero-Beiträge
  (mass, drag, lift_part, ar, lift_coef, wing_cap, pitch/roll/yaw_a, thrust, jet, prop,
  gear_cap, pos, is_root). Abriss/Reparenting in `_process` (NICHT `_integrate_forces`),
  via `_break_pending`-Flag. `build_from_design` ruft `recompute_aero` auch beim Bau.
- **Reset (Enter)** ruft `build_from_design(design)` neu auf → repariert alles.

### Flügel-Orientierung bestimmt Funktion
Beim Bauen via `R` kippbar. In `FlightController.build_from_design` wird pro Flügel
`up_align = |basis.y·UP|` berechnet: waagerechter Anteil → **Auftrieb** (`wing_area`),
gekippter/senkrechter Anteil → **Rollsteuerung** (`roll_area`). Senkrecht = Winglet/
Querruder, kein Auftrieb.

## Bau-Editor (BuildController.gd)
- **Drag&Snap:** Teil aus Palette wählen → in den Raum ziehen, rastet flächenbündig an
  die getroffene Fläche (`_compute_snap_for`, `_orient_to_normal`). Vorhandene Teile
  greifen/verschieben. Snapping per Raycast auf StaticBody-Pick-Körper (Layer 2).
- **Symmetrie:** spiegelt über X (`_mirror_xform`) → erzeugt eine **improper** Basis
  (det<0). Für **Kollision** wird daraus eine proper Basis gemacht (x-Spalte negieren),
  sonst kaputter Trägheitstensor → Physik-Explosion/NaN. Symmetrie ist auch beim
  **Bearbeiten dynamisch** (`_sync_mirror` in `_apply_sel_transform`): Verschieben/Drehen/
  Skalieren erzeugt/aktualisiert den Spiegel. Nach `load_design` werden Spiegelpaare per
  `_relink_mirrors` (gleiche ID, an −x gespiegelte Position) neu verknüpft → kein Duplikat.
- **Werkzeuge:** Bearbeiten (Default — auswählen/skalieren/verschieben) / Abriss / Lackieren
  (Farbpalette, Farbe wird im Design + Save gespeichert). „✦ Auswählen/Bewegen"-Button
  (`clear_tools`) = zurück zum Bearbeiten-Default. **Undo/Redo** (`_history`, Strg+Z/Y). **R** dreht Box-Teile (90°)
  bzw. kippt Flügel (Bank). **M** Symmetrie. **F** Kamera zentrieren.
- **Windkanal-Ansicht** (`set_wind_tunnel`): Pro-Teil-**Druckwiderstands-Heatmap mit
  VERDECKUNG** (physikalisch korrekt). Der Wind kommt von vorne (−Z). In
  `_apply_drag_heatmap` wird ein **Strahlengitter** aus −Z über die Modell-AABB
  (`_model_aabb_world`) gecastet (gegen die Teil-Pick-Bodies auf `BUILD_LAYER`,
  `intersect_ray`); der **erste** Treffer pro Strahl = windzugewandte Fläche. So sammelt
  jedes Teil nur seine **exponierte** Stirnfläche — Teile im **Windschatten** (hinter
  anderen) bekommen ~0 und bleiben grün. Druckwiderstand je Teil = exponierte Fläche ×
  `PartCatalog.part_cd(p)` (Formbeiwert; eine Quelle für Flug + Windkanal). Einfärbung
  relativ zum größten Wert, Nenner `maxf(max_d, 0.45)` → schlanke Flieger grün, nur echte
  vorne-anliegende Bluff-Körper rot (`_drag_color` grün→gelb→rot). **Markiert wird nur die
  widerstandsauslösende OBERFLÄCHE, nicht das ganze Teil:** ein **Pixel-Shader**
  (`_get_wind_shader`/`_apply_wind_shader` als `material_override`) färbt pro Fragment nur
  Flächen, deren Weltnormale gegen den +Z-Wind zeigt (`w = max(0,−worldNormal.z)`,
  `smoothstep` → grau↔heat), Seiten-/Leeflächen bleiben grau. Die `heat_color` (Hue aus dem
  Teil-`frac`) kommt von der Verdeckungs-Rechnung; Teile ganz im Windschatten
  (`exposed < maxf(0.04, max_exp·0.05)`) bekommen `heat=grau` → komplett grau (CFD-Optik).
  Schlimmstes Teil → `wind_worst` (Toast +
  Statistik-„Hotspot“, nur wenn Windkanal an). Dazu CPUParticles-Strömungslinien (−Z→+Z).
  Aufheben via `_clear_wind_tunnel` → `_recolor` baut jedes Visual neu (Original zurück).
  `set_wind_tunnel` feuert `design_changed`, damit die Statistik sofort refresht.
  Verifiziert mit `tools/occlusion_test.gd` (zwei Boxen hintereinander → Heck im Schatten).
  Hinweis: Das Flugmodell nutzt weiter die einfache `part_drag`-Summe als `drag_area`
  (verdeckungs-frei) — die Heatmap ist die verfeinerte, anschauliche Pro-Teil-Sicht.
- **Zoom:** Mausrad + Tastatur `+`/`−` + Trackpad-Pinch (`InputEventMagnifyGesture`) +
  Zwei-Finger-Scroll (`InputEventPanGesture`). Bereich `orbit_dist` 2.5–110.
- **Blauer Blueprint-Raum** im Bau-Modus (eigenes Environment + Gitter-Shader; Shader
  `cull_back` → Gitterboden von UNTEN unsichtbar, man sieht das Flugzeug von unten;
  blauer Gradient-**Himmel als Reflexions-/Ambient-Quelle** (`reflected_light_source=SKY`,
  Hintergrund bleibt `BG_COLOR` dunkel) → metallische Teile spiegeln, Drehen ändert die
  Reflexion sichtbar), im Flug
  Himmel + Startbahn. Marker: ● gelb = Schwerpunkt, ● blau = Auftriebspunkt.

## Steuerung
**Hangar:** Palette-Teil wählen → ziehen=setzen · **vorhandenes Teil klicken=auswählen**
(Griffe+Panel: skalieren/drehen/löschen), **Body ziehen=verschieben** · leerer Raum/Rechtsmaus=drehen ·
Mausrad/`+`/`−`/Pinch=Zoom · `X` löschen · `R` drehen/kippen · `M` Symmetrie ·
`Strg+Z`/`Strg+Y` Undo/Redo · `F` Ansicht · **`Strg+D` duplizieren** (Klon+Spiegel, `duplicate_selected`) ·
**Pfeiltasten** = ausgewähltes Teil fein verschieben (`nudge_selected`, 0.25er) ·
**`1`/`2`/`3` orthografische Blueprint-Ansicht** Front/Seite/Oben, **`4`** frei (`set_view`/`_ortho_view`,
Kamera `PROJECTION_ORTHOGONAL`; manuelles Drehen → zurück Perspektive) · Tab=Testflug.
Statistik hat eine **„Fliegt's?"-Ampel** (`_update_ampel`): grün/gelb/rot aus Stabilität
(col.z−com.z), Schub/Gewicht, Tragflächen & Fahrwerk + kurzer Tipp.
**Kein freies Schweben:** `_connected_set` (BFS ab Cockpit über AABB-Nachbarschaft
`_part_world_aabb.grow(0.12)`) findet nicht verbundene Teile; `has_floating`/`floating_parts`.
Schwebende Teile bekommen einen **roten Warn-Marker** (`_update_float_markers` in `_notify_changed`),
die Ampel wird rot, und der **Start ist blockiert** (`_set_mode` → Toast statt Moduswechsel).
**Bauen = Drag&Drop aus dem Inventar:** Druck auf eine (freigeschaltete) Teile-Kachel ruft
`begin_drag_from_palette` → Ghost folgt der Maus, **in den Bauraum ziehen & loslassen** = gesetzt
(rastet flächenbündig an). Loslassen über UI = verworfen (`gui_get_hovered_control`). Release per
Polling in `_process` erkannt (Druck ging an die UI). Gesperrte Kacheln: Klick kauft.
**Vorhandenes Teil anklicken = AUSWÄHLEN** (`_on_left_press`→`_transform_left_press`) → **Blender-
artiges Gizmo** je `gizmo_mode` (Tasten **G/R/S** oder Panel-Buttons): **Bewegen** = 3 Achsen-Pfeile
(`_build_move_handles`, ziehen = entlang Achse verschieben) + Body ziehen = frei verschieben;
**Drehen** = Body ziehen dreht (`_begin_rotate`: horiz=Gier, vert=Nick) + 90°/45°-Buttons;
**Skalieren** = 6 Flächenwürfel (`_build_scale_handles`, ziehen = Achse strecken). Gizmo-Mats mit
`no_depth_test` (immer sichtbar). Kontext-Panel rechts (`_build_selection_panel`/`_on_selection_changed`,
Signal `selection_changed` inkl. `gizmo`): Modus-Buttons, pro-Achse −/+ (`nudge_scale`),
`rotate_selected`/`tilt_selected`, `reset_selected_scale`, **🗑 `delete_selected`** (Root nicht löschbar).
History nur bei echter Änderung (`_edit_xf0/_edit_sc0`-Snapshot). **Beleuchtung:** zweites
DirectionalLight von unten (`underfill`, kein Schatten) + mehr Ambient → Unterseite sichtbar.
Linkes Teile-Panel schmaler (≈238 px).
**Skalieren ohne Spalt:** Griff-Ziehen verschiebt den Mittelpunkt um die VOLLE Größenänderung
(`moved = base·new_s·0.5 − half0`, kein `·0.5`) → Gegenfläche bleibt fix. Panel +/-
(`nudge_scale`) verankert via `_scale_anchor_origin` die zur Wurzel (0,0,0) NÄHERE Fläche →
Flügel wächst nach außen, Anbindung an die Hülle bleibt bündig. Pro-Teil-Skalierung
(`pscale`, Vector3) in get/load_design persistiert; `_apply_part_scale` skaliert Visual+Pickbox;
FlightController/compute_stats skalieren Masse~Volumen, Schub~Volumen, Fläche~x·z,
Widerstand~x·y, Traglast~Volumen. Resize-Mathe: `_ray_axis_t` (Linie-Strahl).
**Flug:** **Maus/Touchpad = Umschauen** (Orbit-Kamera, Maus im Flug `MOUSE_MODE_CAPTURED`,
schwenkt bei Ruhe sanft zurück; `look_yaw`/`look_pitch` + `_cam_offset` in FlightController) ·
`Shift`/`Strg` Schub (unter 0 % = bremsen) · `W`/`S` Nase ·
`A`/`D` rollen (**vertauscht:** A=rechts, D=links; **lange halten → Fass-Roll**) · `Q`/`E` gieren = **rechts/links**
(Seitenleitwerk; auch `C`/`Z`) · `I` Steuerung umkehren · `G` Einziehfahrwerk · `T` Assist ·
`M` **Maus-Flug** umschalten · `Enter` Reset/Reparatur · `Tab` Hangar (gibt Maus frei).
**Maus-Flug (War-Thunder-Stil, `mouse_fly`, Taste `M`):** Die Maus zeigt frei in eine
**WELTRICHTUNG** (`look_yaw`/`look_pitch` als absolute Zielrichtung, `_aim_dir()` =
Einheitsvektor; yaw 360° per `wrapf`), das Flugzeug **dreht seine Nase dorthin** (Pursuit).
Schaust du nach Westen, fliegt es nach Westen — voll 360° (auch 180° hinten rum, Nase nach
oben). Regler in `_physics_process`: Zielrichtung ins Körpersystem (`e = basis.transposed()·aim`),
**Horizontalfehler** `horiz=atan2(e.x,-e.z)` und **Vertikalfehler** `vert=atan2(e.y,…)`.
- **Roll = Bank-to-turn-Kaskade** (sonst Trudeln): `target_bank = -horiz·AIM_BANK_K`
  (gekappt `AIM_BANK_MAX`) → *ratenbegrenzte* Soll-Rollrate (`AIM_BANK_P`, Cap `AIM_ROLL_RATE_MAX`)
  → `roll_cmd = (desired_rate − roll_rate)·AIM_ROLL_P`. Querlage als `asin(basis.x.y)`
  (gleiches Vorzeichen wie `in_roll`, sonst Mitkopplung→Aufschaukeln).
- **Nick** = ebenfalls Raten-Kaskade (Vertikalfehler→Soll-Nickrate `AIM_PITCH_K`, Cap
  `AIM_PITCH_RATE_MAX`, dann `(d_pitch−wb.x)·AIM_PITCH_RATE_P`, **gedämpft**) + `|horiz|·AIM_TURN_PULL`.
- **Gier** koordiniert `−horiz·AIM_YAW_K` **−`wb.y·AIM_YAW_D`** (gedämpft).
- **Anti-Zittern/smoother Flugweg:** Regler folgt einer **geglätteten** Zielrichtung
  (`_aim_smooth.slerp(_aim_dir(), δ·AIM_SMOOTH)`, wenig Lag), kleiner **Totbereich**
  `AIM_DEADZONE` auf horiz/vert killt den Limit-Cycle, Pitch/Yaw sind **gedämpft**
  (Raten-Terme `wb.x`/`wb.y`), Nasenmarker zusätzlich pixelgeglättet (`AIM_MARK_SMOOTH`).
- **Robustheit/Speed:** Querlage als **`atan2(basis.x.y, basis.y.y)`** (voller Bereich,
  kippt nicht bei 90° wie `asin` → kein Überbank-Taumeln). `AircraftBody.MOUSE_AUTH` (×1.4)
  gibt im Maus-Flug mehr Steuer-Autorität → Soll-Raten schneller erreicht; **Obergrenze
  ~1.4** — darüber überzieht der Nick (Stall/Loop) bzw. tumbled. Einrollen ist bewusst
  schnell (`AIM_ROLL_RATE_MAX/AIM_BANK_P` hoch, kostet keine G), der Kurvenzug `AIM_TURN_PULL`
  greift erst gebankt (`·|sin(bank)|`). Turn-Zeit ist sonst **airframe-limitiert**
  (~1.4 s für 90° bei ~90 m/s; bei dem Tempo stall-/G-Grenze). Headless: eingeschwungen
  Schwankung <0.001, Restdrehrate <0.03, monotone Annäherung (kein Überschwingen).
**Wichtig:** (1) Roll-/Gier-Achsen sind „vertauscht" (in_roll>0 dreht physikalisch links,
vgl. Tastatur A=rechts) ⇒ horiz-Vorzeichen negiert, damit Ziel-rechts=Rechtskurve.
(2) Befehle **direkt** anwenden (kein `_ramp` im Maus-Flug → sonst Brems-Verzug→Überschwingen).
(3) `AircraftBody.mouse_fly`-Flag schaltet das Assist-Auto-Leveling ab. Beim Einschalten wird
`look` auf die aktuelle Nasenrichtung gesetzt (kein Ruck). **Kamera** blickt im Maus-Flug in
die Zielrichtung (`_process`-Zweig: Pos hinter `-aim`, `look_at` entlang `+aim` **+UP·CAM_LOOK_ABOVE**
→ Flieger sitzt im **unteren Bilddrittel** ~0.72, nicht mittig), kein
Zurückschwenken. HUD: **Zielmarker** ⊕ grün (`unproject` von `pos+aim·400`) + **Nasenmarker**
◇ gelb (`pos−basis.z·400`); decken sie sich, fliegt es genau aufs Ziel. Sichtbarkeit via
`is_position_behind` (`aim_vis`/`nose_vis`). Headless verifiziert: Nase konvergiert in alle
Richtungen aufs Ziel (vorne/rechts/180°-hinten/oben, align≈1.0), stabil (maxAngVel<2).
- **Arcade-Lenkung (`arcade`, Taste `J`, nur im Maus-Flug):** maximal smoothe, direkte
  Lenkung. Statt Steuer-Torque dreht `AircraftBody._arcade_steer` die Orientierung
  **kinematisch per Quaternion-Slerp** (`ARCADE_RESP`) auf die Ziel-Basis (Nase=`aim_world`,
  in die Kurve gebankt) und führt die Geschwindigkeit der Nase nach (`ARCADE_VEL`).
  Unabhängig von Ruder-Autorität/Stall/G → schnappt in ~0.3–0.4 s auf jede Richtung (auch
  180°), exponentiell = **kein Überschwingen/Trudeln**; Flügelbruch im Arcade aus. **Godot-
  Falle:** `state.transform.basis = …` schreibt NICHT zurück → ganzen `state.transform`
  neu zuweisen. FlightController setzt `aircraft.arcade`/`aircraft.aim_world` (roh) je Frame;
  `_toggle_arcade` (J) schaltet ggf. den Maus-Flug mit ein. HUD zeigt „ARCADE 🎮".
- **Kamera-Framing:** look_at-Punkt `+UP·CAM_LOOK_ABOVE` (6.5) → Flieger sitzt **tief im
  unteren Bildbereich** (~0.78), nicht mittig.
- **Fass-Roll (`barrel_roll`, A/D lange halten ≥ `BARREL_HOLD`):** FlightController trackt die
  A/D-Haltezeit (`_roll_hold`/`_roll_dir`) und setzt `aircraft.barrel_roll = ±1`. `AircraftBody`
  rollt dann **physikalisch** (NICHT kinematisch — sonst steif/unnatürlich): der Roll-Befehl
  wird zum **Raten-Regler** auf `BARREL_RATE` (`rr = (BARREL_RATE·dir − wb.z)·BARREL_GAIN`),
  die **Roll-Dämpfung ist dabei aus** (sonst kommt die Rolle nicht auf Touren). So gibt's
  echte Trägheit beim Anrollen und die Nase wandert natürlich (≈ Aileron-Roll), nur die Rate
  ist begrenzt (~4.5 rad/s gemessen). Flügelbruch dabei aus. Headless: stabil, maxAngVel<8.
**Global:** Startet im **Vollbild** (`display/window/size/mode=3`). `F11` (oder Alt+Enter)
schaltet Vollbild um, `Esc` verlässt Vollbild bzw. beendet (Main `_input`/`_toggle_fullscreen`).

## Bauteile (PartCatalog)
Rumpf (Cockpit=Wurzel, Segmente, Nase/Heck, Tank) · **4 Kanzel-Varianten** (Bubble/Jet/
Rahmen/Tandem, Blender-glTF `cockpit_<v>.glb`, lackierbarer `cockpit_body` + `glass`-Kanzel) ·
8 Tragflächen (gerade, Trapez,
Pfeil, Delta, Stummel, Segler, Canard, Winglet) · Leitwerk/Steuerung (Höhen-, Seiten-
leitwerk, Querruder) · 5 Triebwerke (Propeller, groß, Jet, **Eckiges Düsentriebwerk**
[`jet_square`, Blender-glTF, rechteckige 2D-Düse, 22000 N], Hilfstriebwerk) · 4 Fahrwerke
(leicht/Standard/schwer/**Einziehfahrwerk**, je mit `gear_capacity`).
Wichtige Part-Felder: `is_wing, area, span, lift, control("pitch"/"roll"/"yaw"/""),
thrust, jet, gear_capacity, retract, shape, size, col_size/col_offset, orient_normal, cost`.
**Vorgebauter Jet:** `tools/build_jet.gd` (headless) setzt einen zweimotorigen Delta-Canard-
Jet zusammen (2× `jet_square`, Symmetrie via BuildController) und schreibt ihn nach
`user://aircraft_design.json`. (Bewaffnung wurde auf Wunsch wieder entfernt.)

## GDScript-/Godot-Stolpersteine (gelernt)
- `:=` nur für NEUE lokale Variablen; Member mit `=` zuweisen.
- Bei Variant-Inferenz (Dict-Zugriff `* float`) explizit typisieren (`var f: Vector3 = …`).
- **Keine Node-Änderungen in `_integrate_forces`** (reparent/add/remove) → in `_process`
  verschieben (Flügelbruch nutzt `_break_pending`-Flag).
- `contact_monitor=true` + `max_contacts_reported>0` nötig für `get_contact_count()`.
- Gespiegelte (det<0) Basis nur für Visuals ok; für Kollision proper machen.

## Bauteil-Modelle (Blender/glTF)
- **18 Teile** (Rumpf, Nase/Heck, Tank, Cockpit, 4 Kanzel-Varianten [Bubble/Jet/Rahmen/Tandem],
  2 Prop, 2 Jet, 4 Fahrwerke) sind in
  **Blender 5.1** modelliert und als `res://models/<id>.glb` exportiert (+ `.glb.import`).
  Erzeugt **per Blender-MCP** (`execute_blender_code`, bpy): glatte Tubus-/Lathe-Formen
  (`bmesh.ops.spin`), Bevel, Smooth-Shading, Multi-Material (genannte Materialien:
  body, cockpit_body, tankmetal, engine, glass, spinner, dark, rubber, rim, hub, strut).
- **Achsen-Konvention (empirisch verifiziert):** glTF-Export `+Y up` ⇒
  Blender X→Godot X, Blender Z→Godot Y(oben), **Blender +Y → Godot −Z (VORNE)**.
  Also Nasenspitze/Spinner in Blender bei **+Y** bauen; Teildim. Blender (X=sx, Y=sz, Z=sy).
  Geometrie auf Objekt-Origin = Box-Mitte zentrieren (Location vor Join applien); Rad sitzt
  unten (Reifen bei Blender −Z). Prop-Blätter als Kind-Objekt **„Prop"** (auf Mittelachse
  vorne) — `FlightController` dreht es mit `rotate_z`.
- **Verifikation ohne Sicht:** Blender-Renders via `render_viewport_to_path` → mit Read
  ansehen; in Godot AABB/Orientierung per `GLTFDocument.append_from_file` headless prüfen;
  Hangar-Screenshot via `get_viewport().get_texture().get_image().save_png()` (echtes Fenster).
- **Regenerieren:** Blender starten (`open -a Blender`, Port 9876 muss offen sein), dann
  das bpy-Bau+Export-Skript erneut laufen lassen; danach `Godot --headless --editor --import`.
  Neue/zusätzliche Teile bekommen automatisch ein Modell, sobald `models/<id>.glb` existiert.

## Modi, Geld & Upgrades (`scripts/GameState.gd`)
- **GameState** (Node, in Main als `game` erzeugt + `load_state()`): hält `mode`
  (NONE/SANDBOX/SURVIVAL), `money`, `unlocked` (Teil-IDs), `upgrades` (thrust/wing/light).
  Persistiert nach `user://aviassembly_progress.json`. Signal `changed`.
- **Modus-Auswahl** beim ersten Start (Overlay `_show_mode_select`, falls `mode==NONE`):
  **Sandbox** = alles frei (`start_mode` unlockt alle, money ∞); **Survival** = Starter-Teile
  (`STARTER`) + `START_MONEY=1500`.
- **Shop:** Palette-Kacheln zeigen 🔒+Preis (`PartCatalog.part_cost`) für gesperrte Teile;
  Klick kauft (`_on_pick_part` → `game.buy_part`), `_rebuild_palette` aktualisiert. Sandbox:
  alles frei.
- **Upgrades** (`_build_upgrades_ui`, Hangar): Triebwerk +15%/Lv, Flügel +30%/Lv, Leichtbau
  −8%/Lv (max 3, 600·(Lv+1) 🪙). Wirken im Flug: Main setzt `flight_ctrl.thrust/wing/mass_mult`
  → `AircraftBody.recompute_aero` wendet sie an (überleben auch den Flügelbruch).
- Geld-Anzeige im Hangar (`money_label`) + Flug (`fly_money_label`).
  HINWEIS: Missionen wurden auf Wunsch wieder entfernt — Survival hat aktuell keine
  laufende Einnahmequelle (nur Startgeld). `GameState` hat noch ungenutzte Mission-Hooks
  (`missions_done`/`complete_mission`), falls man Missionen später wieder einbaut.
- **Persistenz Design** (`_save_design`/`_load_design`): serialisiert id/xform/color/**scale**.

## Luftkampf: Waffen, Geschosse, Ziele
- **Waffen-Bauteile** (`CAT_WEAPON`, Feld `weapon`): `cannon`→`gun`, `rocket`→`rocket`
  (ungelenkt, gerade), `rocket_pod`→`salvo` (3er-Fächer), `missile`→`missile` (Heat-Seeker),
  `missile_heavy`→`missile_heavy` (große Reichweite/Schaden), `bomb`→`bomb`. Prozedurale
  Shapes; mountbar wie jedes Teil.
- **`scripts/Projectile.gd`** (`class_name Projectile`): `bullet`/`missile`/`bomb`.
  Bewegung + Bomben-Schwerkraft. **Rakete `missile` nur mit `guided=true` lenkend** — und
  auch dann **proximity-aktiviert**: `_home` lenkt nur, wenn ein Ziel im `seek_range`
  UND grob voraus (`SEEK_CONE`-Kegel) liegt (`_in_seek`/`_nearest`); sonst fliegt sie
  **geradeaus** weiter. So ist eine ungelenkte Rakete einfach `guided=false`, und der
  Heat-Seeker fliegt erst stur geradeaus und kurvt erst rein, wenn ein Ziel in die Nähe
  kommt. Lenkung = `slerp` der Geschwindigkeit (`turn`·delta). Treffer via Segment-Abstand
  gegen Gruppe `"target"` (kein Durchtunneln); Knall-Partikel. Lebenszeit-begrenzt.
- **`scripts/Target.gd`** (`class_name Target`, Gruppe `"target"`): Luftballon (1 HP, +120)
  oder Luftschiff (4 HP, +600). Schwebt/driftet, `hit(dmg)` mit `_dead`-Flag (kein
  Doppel-Reward), `_die()` → Signal `killed(reward,pos)` + Partikel. Main spawnt sie in
  `targets_root` (in `fly_world`), vor der Startbahn (`_rand_target_pos`); Abschuss →
  `game.add_money` + Toast; Nachschub-Ballon nach 7 s.
- **Feuern** (`FlightController`): sammelt `weapons` = `[{type, off, cd}]` beim Bauen
  (jede Waffe hat **eigenen Cooldown** `cd`, pro Frame heruntergezählt). **Leertaste** →
  `_fire_primary` (`match w["type"]` für gun/rocket/salvo/missile/missile_heavy; setzt bei
  Lenkraketen `guided/turn/seek_range` + jeweiligen `cd`), **B** → `_drop_bomb`. `_spawn`
  gibt das `Projectile` zurück. Spawnt in `world_root` (= `targets_root`, von Main gesetzt;
  `_fire_primary` guardet `world_root==null`). Mündung = `aircraft.global_transform * off`,
  Vorwärts = `-basis.z`. Fadenkreuz im Flug-HUD.
  -> Abschüsse sind die Survival-Einnahmequelle.

## Status & nächste Schritte
- **Git:** lokal initialisiert, Branch `main`, alles committet (`.godot/` ignoriert).
  GitHub-User (SSH funktioniert): **KonstiTheProgrammer**.
- **GitHub-Push: NOCH OFFEN** — `gh` (2.93) ist installiert, aber `gh auth login`
  (Device-Flow) wurde noch nicht autorisiert. Zum Abschließen: `gh auth login`
  (GitHub.com → SSH), dann
  `gh repo create aviasembly --public --source=. --remote=origin --push`.
- **Ideen für später:** Lande-Score/Punkte, Cockpit-Kamera, Strömungslinien die sich
  am Modell verbiegen, Rumpf/Leitwerk auch abreißbar, Funken/Rauch, Missionen/Parcours,
  Teile freischalten.
