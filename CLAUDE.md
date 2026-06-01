# CLAUDE.md — Projekt-Kontext für Aviassembly

> Diese Datei wird von Claude Code automatisch als Kontext geladen. Sie fasst
> alles zusammen, damit eine andere Claude-Instanz (auf einem anderen Gerät)
> sofort produktiv weiterarbeiten kann.

## Was ist das?
**Aviassembly** — ein 3D-Flugzeug-Baukasten in **Godot 4.6** (wie SimplePlanes, im
Kleinen). Im **Hangar** baust du aus Modulen ein Flugzeug, per **Tab** wechselst du
in den **Testflug** mit echter (arcade-tauglicher, aber physikalisch fundierter)
Flugphysik. Wie du baust, bestimmt wie es fliegt.

- **Engine:** Godot **4.6.2** (Forward+/Metal). Alles ist **prozedural** erzeugt
  (Meshes, Materialien, UI) — keine externen Assets.
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
                         (user://aircraft_design.json), Start-Flugzeug (_default_design)
scripts/PartCatalog.gd   class_name PartCatalog (statisch). Alle Bauteile als Dicts +
                         prozedurale Meshes (build_visual), Airfoil-Flügel-Mesh,
                         Materialien, part_drag(), WING_STRESS-Konstante
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
- **Flügelbruch:** zu viel Auftrieb (G) > `wing_capacity` → Flügel **reißen physisch ab**
  als Trümmer-RigidBody und nehmen **alles geometrisch darauf Sitzende** mit
  (transitiv via `_origin_in_part`). Abriss/Reparenting wird in `_process` gemacht
  (NICHT in `_integrate_forces`!).
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
- **Windkanal-Ansicht** (`set_wind_tunnel`): Pro-Teil-**Widerstands-Heatmap**. Für jedes
  Teil wird der Flug-Widerstand `PartCatalog.part_drag(p)` berechnet und relativ zum
  größten Wert im Design eingefärbt — grün (wenig) → gelb → rot (viel), via
  `_apply_drag_heatmap`/`_drag_color`/`_tint` (unshaded `material_override`; heiße Teile
  glühen leicht). Nenner = `maxf(max_drag, 0.6)` → schlanke Flieger bleiben grün, nur echte
  Bluff-Körper (Rumpf-Box, Räder) werden rot. Der schlimmste Teilname → `wind_worst`
  (Toast + Statistik „Hotspot“). Dazu CPUParticles-Strömungslinien (von −Z über das Modell
  nach +Z). Aufheben via `_clear_wind_tunnel` → `_recolor` baut jedes Visual neu auf
  (Original-Material zurück). Konsistent mit dem Flugmodell, das dieselbe `part_drag`-Summe
  als `drag_area` nutzt — Visualisierung = tatsächlicher Sim-Widerstand.
- **Zoom:** Mausrad + Tastatur `+`/`−` + Trackpad-Pinch (`InputEventMagnifyGesture`) +
  Zwei-Finger-Scroll (`InputEventPanGesture`). Bereich `orbit_dist` 2.5–110.
- **Blauer Blueprint-Raum** im Bau-Modus (eigenes Environment + Gitter-Shader), im Flug
  Himmel + Startbahn. Marker: ● gelb = Schwerpunkt, ● blau = Auftriebspunkt.

## Steuerung
**Hangar:** Teil ziehen=setzen/verschieben · leerer Raum/Rechtsmaus=drehen ·
Mausrad/`+`/`−`/Pinch=Zoom · `X` löschen · `R` drehen/kippen · `M` Symmetrie ·
`Strg+Z`/`Strg+Y` Undo/Redo · `F` Ansicht · Tab=Testflug.
**Flug:** `Shift`/`Strg` Schub (unter 0 % = bremsen) · `W`/`S` Nase ·
`A`/`D` rollen (**vertauscht:** A=rechts, D=links) · `Z`/`C` gieren ·
`Q` Steuerung umkehren · `G` Einziehfahrwerk · `T` Assist an/aus ·
`Enter` Reset/Reparatur · `Tab` Hangar.

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
