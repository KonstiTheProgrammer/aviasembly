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
  `drag_area` (aus den Bauteil-Stirnflächen, siehe `PartCatalog.part_drag`).
- **Schub:** Summe der Triebwerke, **zentral durch den Schwerpunkt** (sonst „Pendel-
  Raketen"-Instabilität!). Propellerschub fällt mit Tempo (`PROP_VMAX`), Jet konstant.
  **Negativer Schub = Bremse** (Luftbremse + am Boden Radbremse).
- **Statische Stabilität:** kleine Wetterfahnen-Momente (Nase folgt Anströmung),
  skaliert mit Leitwerksfläche (`pitch_area`/`yaw_area`).
- **Steuerung = Fly-by-Wire-Ratenregler (PID-artig):** Eingabe kommandiert Drehraten,
  ohne Eingabe wird die Lage gehalten + Querlage sanft ausnivelliert (LEVEL_K). Mit
  **T** abschaltbar („Pro"-Modus, weniger Hilfe). Integralanteil (`GAIN_I`) tilgt
  Trimm-Abweichung. Liegt ÜBER der echten Aero (die Performance/Stall bestimmt).
- **Luftdichte** sinkt mit Höhe: `ρ = RHO0·e^(−h/SCALE_H)`.
- **Sicherheit:** Kräfte werden auf `mass·60`/`mass·90` begrenzt, NaN-Werte verworfen,
  Drehrate auf `MAX_ANGVEL` geklemmt.

### Tuning-Konstanten (AircraftBody, oben in der Datei)
`LIFT_K=2.9` (globaler Auftrieb/Spielgefühl, früh abheben), `INCIDENCE≈0.075`,
`STALL_A=0.27`, `CL_MAX=1.5`, `CD0=0.03`, `OSWALD=0.75`, `SIDE=0.5`,
`PITCH_STAB=0.5`/`YAW_STAB=0.6`, `PROP_VMAX=170`, `DRAG_K=0.45`, `MAX_ANGVEL=7`,
Ratenregler: `PITCH_RATE=0.85`/`YAW_RATE=0.6`/`ROLL_RATE=2.1`,
`GAIN_P=7`/`GAIN_Y=4`/`GAIN_R=7.5`/`GAIN_I=12`, `LEVEL_K=2`,
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
  sonst kaputter Trägheitstensor → Physik-Explosion/NaN.
- **Werkzeuge:** Bewegen / Abriss / Lackieren (Farbpalette, Farbe wird im Design +
  Save gespeichert). **Undo/Redo** (`_history`, Strg+Z/Y). **R** dreht Box-Teile (90°)
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
- **Blauer Blueprint-Raum** im Bau-Modus (eigenes Environment + Gitter-Shader), im Flug
  Himmel + Startbahn. Marker: ● gelb = Schwerpunkt, ● blau = Auftriebspunkt.

## Steuerung
**Hangar:** Teil ziehen=setzen/verschieben · leerer Raum/Rechtsmaus=drehen ·
Mausrad/`+`/`−`/Pinch=Zoom · `X` löschen · `R` drehen/kippen · `M` Symmetrie ·
`Strg+Z`/`Strg+Y` Undo/Redo · `F` Ansicht · Tab=Testflug.
**Transformieren-Werkzeug** (`set_transform_mode`): Teil klicken=auswählen → 6 farbige
Flächen-Griffe (X=rot Breite, Y=grün Höhe, Z=blau Länge); Griff ziehen=Achse strecken
(Gegenfläche verankert), Body ziehen=verschieben (Bildschirmebene). Pro-Teil-Skalierung
(`pscale`, Vector3) wird in get/load_design persistiert; `_apply_part_scale` skaliert
Visual+Pickbox; FlightController/compute_stats skalieren Masse~Volumen, Fläche~x·z,
Widerstand~x·y, Traglast~Volumen. Resize-Mathe: `_ray_axis_t` (Linie-Strahl), Move: Ebene.
**Flug:** **Maus/Touchpad = Umschauen** (Orbit-Kamera, Maus im Flug `MOUSE_MODE_CAPTURED`,
schwenkt bei Ruhe sanft zurück; `look_yaw`/`look_pitch` + `_cam_offset` in FlightController) ·
`Shift`/`Strg` Schub (unter 0 % = bremsen) · `W`/`S` Nase ·
`A`/`D` rollen (**vertauscht:** A=rechts, D=links) · `Q`/`E` gieren = **rechts/links**
(Seitenleitwerk; auch `C`/`Z`) · `I` Steuerung umkehren · `G` Einziehfahrwerk · `T` Assist ·
`Enter` Reset/Reparatur · `Tab` Hangar (gibt Maus frei).
**Global:** Startet im **Vollbild** (`display/window/size/mode=3`). `F11` (oder Alt+Enter)
schaltet Vollbild um, `Esc` verlässt Vollbild bzw. beendet (Main `_input`/`_toggle_fullscreen`).

## Bauteile (PartCatalog)
Rumpf (Cockpit=Wurzel, Segmente, Nase/Heck, Tank) · 8 Tragflächen (gerade, Trapez,
Pfeil, Delta, Stummel, Segler, Canard, Winglet) · Leitwerk/Steuerung (Höhen-, Seiten-
leitwerk, Querruder) · 4 Triebwerke (Propeller, groß, Jet, Hilfstriebwerk) · 4 Fahrwerke
(leicht/Standard/schwer/**Einziehfahrwerk**, je mit `gear_capacity`).
Wichtige Part-Felder: `is_wing, area, span, lift, control("pitch"/"roll"/"yaw"/""),
thrust, jet, gear_capacity, retract, shape, size, col_size/col_offset, orient_normal`.

## GDScript-/Godot-Stolpersteine (gelernt)
- `:=` nur für NEUE lokale Variablen; Member mit `=` zuweisen.
- Bei Variant-Inferenz (Dict-Zugriff `* float`) explizit typisieren (`var f: Vector3 = …`).
- **Keine Node-Änderungen in `_integrate_forces`** (reparent/add/remove) → in `_process`
  verschieben (Flügelbruch nutzt `_break_pending`-Flag).
- `contact_monitor=true` + `max_contacts_reported>0` nötig für `get_contact_count()`.
- Gespiegelte (det<0) Basis nur für Visuals ok; für Kollision proper machen.

## Bauteil-Modelle (Blender/glTF)
- **14 Teile** (Rumpf, Nase/Heck, Tank, Cockpit, 2 Prop, 2 Jet, 4 Fahrwerke) sind in
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
