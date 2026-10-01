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

- **TESTS, DIE `Main.tscn` LADEN, NUR MIT UMGEBOGENEM HOME:** Main laedt beim Start den
  Autosave, markiert ihn dirty und schreibt ihn nach 2 s zurueck — `_do_load_preset`,
  Slot-Speichern und Survival-Tests schreiben ebenfalls nach `user://`. Ohne Vorkehrung
  ueberschreibt jeder Testlauf den ECHTEN Spielstand des Nutzers. Godot nimmt `user://`
  unter macOS aus `$HOME` (`XDG_DATA_HOME` wirkt NICHT):
  `HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/<t>.gd`
  (vorher `aviassembly_progress.json` dorthin kopieren, sonst erscheint die Modus-Auswahl).
  `--fixed-fps 60` = genau ein Physikschritt je Frame: schnell UND reproduzierbar.
- **REGRESSIONS-SUITE (alle headless, alle mit Urteilszeile):** `_rundflug_alle` (Erststart-
  Flugzeug + jede Vorlage: Start, Steigflug, alle Waffengruppen, Bombe, Fahrwerk, Schacht,
  Reset, Hangar), `_undo_check`, `_datei_rundlauf` (jeder Entwurfsschluessel ueberlebt
  Datei-Speichern/Laden), `_survival_check`, `_bodenkampf_check`, `_lenkwaffen_start`,
  `_schaden_check`, `_grafik_check`, dazu die aelteren (`_dock_test`, `_fluegelsnap_check`,
  `_lackieren_check`, `_raketen_pruefstand`, `_sam_pruefstand`, `_zielpruefung`,
  `mousefly_test`, `mf_speed`, …). Messwerkzeuge: `_skriptzeit` (CPU je Flugframe, ~1 ms),
  `_karte_zeit`, `_bildzeit` (GPU, braucht Fenster).
- **FALLE `Performance.TIME_PROCESS`/`TIME_PHYSICS_PROCESS`:** das ist das MAXIMUM der letzten
  Echtzeit-Sekunde, nur einmal je Sekunde erneuert — kein Frame-Wert. CPU je Frame misst man
  headless ueber die Wandzeit zwischen zwei `_process`-Aufrufen (siehe `_skriptzeit`).

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
                         (user://aircraft_design.json), Start-Flugzeug (_default_design):
                         laedt beim ERSTSTART ohne Speicherstand (20-Teile-Doppeldecker,
                         verifiziert via tools/_firststart_check.gd — Save-Datei beiseite
                         legen!). AUTOSAVE: design_changed -> _design_dirty, 2-s-Debounce
                         in _process + Sicherung bei WM_CLOSE/Quit-Button. (War seit dem
                         Slot-Menue-Umbau TOT — Bauten gingen beim Beenden verloren, dazu
                         startete der Hangar leer: genau die Nutzer-Beschwerde.)
                         Teile-Palette: aufklappbare Kategorie-Sektionen (▾/▸) mit Grid aus
                         3D-Vorschau-Kacheln. Jede Kachel = eigener SubViewport (own_world_3d,
                         eigene Cam+Licht+Environment, UPDATE_ONCE) der das Teil-Visual rendert.
                         Helfer: _make_part_tile/_make_preview/_visual_aabb/_style_tile.
                         VORSCHAU-KACHELN (_make_preview): Blickrichtung `Vector3(0.78, hoehe, -1.0)` — die Kamera
                         stand vorher bei **+Z** und damit HINTER dem Teil (Nasen zeigen nach −Z), man sah von
                         jedem Teil nur das Heck; Cockpits, Nasen und Motoren waren nicht zu unterscheiden.
                         `hoehe` kommt aus der TEILFORM: flache Teile (Höhe/Grundkante < 0.30, also
                         Tragflächen) bekommen den Blick von OBEN, sonst 3/4 von schräg vorn — von der Seite
                         sind Trapez-, Pfeil- und Deltaflügel alle nur ein Splitter. Rahmung über
                         `_vorschau_abstand`: projiziert die ACHT BOXECKEN ins Kamerabild statt die Umkugel zu
                         nehmen (bei breiten dünnen Formen wie einer Propellerscheibe ist die Umkugel viel
                         größer als die Silhouette). Hintergrund ist ein ProceduralSky als Studio-Hohlkehle
                         (oben dunkel, unten hell) — liefert Verlauf UND Reflexionsquelle, vorher verschwanden
                         dunkle Teile in der flachen Fläche und Metall wirkte wie Grauguss. Dazu Drei-Punkt-
                         Licht mit Kante von hinten, MSAA 8x (UPDATE_ONCE, kostet nichts Laufendes),
                         Kachelhöhe 176 (bei 156 schnitt clip_contents die Massenangabe ab).
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
scripts/FlightHud.gd     Canvas-HUD (Custom-_draw, Vorbild SimplePlanes-Mockup): FLUG-STATUS-
                         Panel oben links (Zeilen mit Trennern, gruene AN-Werte), Kompass-Pille +
                         Kursbox + NAV-Pille (naechster Flugplatz), grosse GESCHWINDIGKEIT/HOEHE-
                         Boxen unten, Systeme-Panel (Schub-Balken/Klappen/Fahrwerk) ueber der
                         Speed-Box, WAFFENWAHL-Leiste unten Mitte (Pille je Gruppe, Tasten-
                         Kaestchen 1-4, Cyan-Rahmen = gewaehlt, Restmunition/∞), Corner-MINIMAP (7-km-
                         Fenster, spielerzentriert). Design-Tokens P_BG/CYAN/GREEN/GOLD, Titillium-
                         Fonts, alles skaliert mit u = size.y/1080. FALLE: `var x := dict/Variant`
                         bricht als Warning-as-Error den ganzen Compile -> explizit typisieren;
                         Check via tools/_loadcheck.gd (der --editor-Grep uebersieht diese Klasse!).
scripts/WorldMap.gd      Vollbild-Inselkarte (Taste M im Flug) = RELIEFKARTE + VEKTOR-EBENEN.
                         RASTER (generate_image, Hintergrund-Thread, keine Chunks noetig), ZWEISTUFIG
                         wie die Fernschuerze: Main erzeugt erst 512 px mit Vorrang (M geht nach ~6 s),
                         dann 2048 px ohne Vorrang (~40 s, drei Viertel sind Meer) und tauscht still
                         aus (`set_image`). Drei Durchgaenge: (1) height_at + Klasse Meer/See/Land fein,
                         (2) Farben aus _face_color/wald_anteil auf einem GROBRASTER (FARB_RASTER 250 m,
                         nur 4 Faeden — die beiden skalieren wegen atomarer Referenzzaehler auf geteilte
                         Dict-Arrays nicht: 1 Faden 5,6 s, 4 Faeden 3,9 s, 12 Faeden 5,6 s),
                         (3) Relief/Hoehenlinien/Kueste je Pixel. Geglaettet wird NATIV per
                         Image.resize (vormultiplizierte Farben kubisch hoch; Hoehen auf GLATT_M 200 m
                         herunter und wieder hoch; FARB_RUHE mischt ein ~1-km-Farbfeld unter) — punkt-
                         genau war die Insel ein braunes Tarnmuster (jede Kuppe >50 m traegt Fels),
                         bilinear gab Karomuster. Hoehenlinien 50 m, im Steilen ausgeduennt.
                         Abbruch ueber `stopp`-Array (Main._map_stopp in _exit_tree), sonst wartete
                         Beenden bis zu einer Minute. Mipmaps im Thread.
                         VEKTOREN (`zeichne_ebenen`, nutzt AUCH die HUD-Minimap): Fluesse
                         (terrain.rivers), Strassen + echte Hausgrundrisse (CityBuilder.karte_strassen/
                         karte_haeuser, gesammelt in build/_band, geleert in Main._setup_world), Bahnen
                         im wahren Kurs (Flugkarten-Symbol bzw. echtes 900-m-Rechteck ab 16 px),
                         Flugabwehr-Reichweiten (SamSite WERTE.reichweite, FlakGun zone_radius — nur
                         solange die Stellung steht), Ziele, Flugspur (je Flugzeug-Instanz, Luecke bei
                         Sprung >1,5 km) und Kurslinie. Was erscheint, haengt am Massstab (m/px).
                         Alles wird selbst auf das Kartenrechteck BESCHNITTEN (_clip_strecke/Liang-
                         Barsky, _flaeche/intersect_polygons) — CanvasItem kennt keinen Beschnitt je
                         Aufruf. `_poly` zeichnet nur Triangulierbares (sonst Logflut aus der Minimap).
                         Rahmen: Planquadrate A-Q/1-17 je 10 km (`planquadrat()`), Windrose, Massstab
                         mit Wechselfeldern (runde Laenge), Innenschatten, Konturschrift.
                         POIs tragen `art` (ort/natur/gefahr/sonst Wahrzeichen) und bei Orten `radius`.
                         GROSS + INTERAKTIV: fast bildschirmfuellend (Rand 18 px) mit SEITENLEISTE
                         (Position, Wegpunkt, Flugplaetze nach Entfernung — anklickbar —, Lage: aktive
                         Flugabwehr + Ziele, Legende, Bedienung). Ansicht = `_mitte` + `_zoom` (1..14,
                         1 = Welthoehe passt ins Rechteck, das breiter als hoch ist; jenseits des
                         Weltrands wird mit `_rand_farbe` = Randpixel des Bilds weitergemalt).
                         Oeffnen gibt die Maus frei (`oeffnen`/`schliessen` merken den Mausmodus),
                         mouse_filter STOP -> `_gui_input`: Rad/Pinch zoomt ZUM CURSOR (Anker bleibt
                         stehen, weich), Ziehen/Zwei-Finger verschiebt, Klick = Wegpunkt, Rechtsklick
                         loescht, Knopf "ZU MIR" (`_folgen`), Tooltip (Planquadrat, Entfernung, Peilung,
                         Hoehe via height_at). Main: Esc schliesst die Karte vor der Pause,
                         `_karte_schliessen` in _set_mode (VOR set_active, sonst kaeme im Hangar die
                         gefangene Maus zurueck) und _set_pause. FlightController feuert per Linksklick
                         NUR bei gefangener Maus (sonst loeste ein Kartenklick eine Rakete).
                         WEGPUNKT: `wegpunkt`/`wegpunkt_name`, HUD-NAV-Pille zeigt ihn statt des
                         naechsten Platzes (Main._on_hud_changed -> `wegpunkt_text`), Linie + Fahne in
                         beiden Karten, loest sich unter 350 m auf (Signal `wegpunkt_erreicht` -> Toast).
                         DETAILKACHELN (scharf beim Zoomen): Stufe 1 = 20x20 Kacheln a 8,4 km, Stufe 2 =
                         40x40 a 4,2 km, je 512 px (16,4 / 8,2 m je Punkt), per `erzeuge_kachel`
                         (= generate_image mit `mitte`/`detail`, feinere STUFE_*-Generalisierung, 24 px
                         Ueberstand gegen Naehte, dann beschnitten). EIN Hintergrund-Thread, naechste zur
                         Bildmitte zuerst, LRU-Cache 48. Schwellen in ECHTEN Bildpunkten (`_skala` =
                         Fensterskalierung): Stufe 1 unter 40 m/px, Stufe 2 unter 12. `zeichne_raster`
                         (Meer, Grundkarte, Kacheln) nutzt auch die Minimap; sie meldet ihren
                         Ausschnitt, und _process laedt dort Stufe-1-Kacheln vor -> Minimap scharf.
                         Warnungen pruefen mit `Godot --headless -d --path . --quit-after 200` (OHNE -d
                         druckt Godot die GDScript-Warnungen nicht; _loadcheck sieht sie auch nicht).
                         Messen: tools/_karte_zeit.gd (misst MAINS Erzeugung, Stufenzeiten), Bilder:
                         tools/_flug_bilder.gd (flug_karte.png, _zoom.png 3x, _zoom8.png, flug_hud_
                         wegpunkt.png) — wartet per `kacheln_bereit()` auf die scharfen Kacheln.
scripts/TerrainWorld.gd  class_name TerrainWorld. SEED-basiertes Chunk-Terrain, 384-m-Chunks,
                         8-m-Raster, GLATT schattiert (Normale+Farbe je Eckpunkt, siehe Abschnitt
                         „Welt-Look"), Shader shaders/gelaende_kern.gdshaderinc, Graswiesen.
                         HÖHE (height_at): sanfte fBm-Grundwelligkeit + RIDGED-Noise-Bergketten,
                         skaliert mit relief_at (sehr grobes Rauschen 0=Ebene..1=Alpen) und
                         Distanz-Ramp (Spawn ruhig, Gebirge ab ~3 km). BIOME (biome_at, grobes
                         _biome-Rauschen): WALD (Sage-Grün + Tannen/Laub), WUESTE (Sand + Palmen),
                         HEIDE (Ocker/Rosé, karg); Fels+Schnee kommen aus Höhe/Hang (Schnee
                         >124 m). _face_color schaltet die Palette je Biom. KEIN Domain-Warp im
                         Ridge (zu teuer pro Vertex -> Spawn-Build ~384 ms). WAHRZEICHEN/POIs (Stufe 2, scripts/Landmarks.gd, statisch -> Spiel+Render-Tool teilen): Stadt mit Kirche+Turm + Leuchtturm (rot-weiß), platziert auf eigenen Flachzonen in Main._setup_world. INLAND-SEEN: lakes-Array an setup(); height_at gräbt ein Becken (Boden über SEA_Y), eigene Wasser-Quads je See. FLÜSSE (Stufe 3): kuratierte Splines [{pts:[Vector3(x,surf_y,z)...], w, valley, depth}] an setup(); _river_carve gräbt entlang des nächsten Segments ein Tal+Bett (robust: Ufer immer >Wasser -> kein schwebendes Wasser; AABB-Early-Out -> nur Fluss-Chunks zahlen), Wasser = feste Ribbon-Meshes. MASSIVE: erzwungene Berge {pos,r,peak} (max-Anhebung) -> garantieren Berg fürs Bergdorf/Flussquelle seed-unabhängig. Flatzone mit y>0 = Hochplateau (Bergdorf). Landmarks.build_village/build_bridge.
                         Streaming um den Spieler auf WORKER-THREAD (Mesh+Trimesh-Shape im
                         Thread, ~7.5 ms/Chunk riss sonst den 120-fps-Frame -> Zucken beim
                         Nachladen; Main hängt nur fertige Daten ein, 1/Frame; update_center
                         scannt nur bei Chunk-Zellenwechsel; build_now_around = Spawn synchron, die Chunkdaten
                         aber PARALLEL im WorkerThreadPool gerechnet und in alter Reihenfolge
                         eingehaengt: 3,1 s -> 1,8 s beim Start, bitgleich).
                         Flugplätze werden EINGEEBNET (height *= smoothstep(r_flat,r_blend));
                         Meer y=-6 (Main: WorldBoundary dort = Wasser-/Sicherheitsboden).
                         Seed: GameState.world_seed (einmal gewürfelt, persistiert).
                         FLORA: Tannen/Laubbäume/Felsen (glb bzw. SurfaceTool-Meshes, weiche Kronen,
                         einmal gebaut) via MultiMesh je Chunk (1 Draw-Call/Variante);
                         Wald-CLUSTER über _forest-Noise (1/260), deterministisch je
                         Chunk (RNG-Seed hash(key,seed)); Bäume nur 0.8<h<48 + flacher
                         Hang, keine auf Flugplatz-Ebene (|h|<0.4-Filter bei Felsen);
                         Erd-Flecken im Gras via _patch<-0.52. Transforms rechnet der
                         Worker, MultiMesh baut der Main-Thread (keine Kollision).
                         FALLEN: Dreiecks-Wicklung = im Uhrzeigersinn von außen (sonst
                         cullt ALLES von oben); Steilheits-Farbe über |n.y| (geometrische
                         Normale zeigt je nach Wicklung nach unten -> sonst alles Fels).
tools/phys_test.gd       Headless-Flugtest (kein Spielinhalt, nur Dev-Werkzeug).
README.md                Steuerung + Feature-Überblick (Spielersicht).
```

## Die Hauptinsel (Neubau: Gebirge, Kueste, Feldflur, Hoehenstufen)
- GEBIRGE als Kuestenform `"art": "gebirge"` (TerrainWorld._kf_gebirge): Hoehe = Huelle(Abstand
  zur Kammlinie, VERRAUSCHTER Rand) × Gratmuster aus Ridged-Rauschen `_gebirg` (3 Oktaven —
  mit 4 gab es Cord-Falten) in VERBOGENEN Kammkoordinaten (laengs 3 km, quer 5,6 km; die
  Achse ist EINE Gerade erster→letzter Punkt, sonst Naht am Knick) + richtungsloser Anteil;
  innen Talboeden auf 0,22 der Kammhoehe, am Rand tiefe Taeler (Auslaeufer). Schluessel:
  `hs`, `breite` (je laengs), `fuss`, `seed`, `tal_schutz` (0 im Hochtal: `_tal_schutz`).
  Hauptinsel: NORDKETTE West/Ost (bis 2650 m), Westkamm + Suedkamm aussen am Hochtal,
  Ostbergland (bewaldet; das Westbergland ist jetzt das Kalkplateau), Sturmkap = Land-Koerper + Gebirge; Nordland-Gletscherkette
  (zwei Ketten mit Laengstal), Fjordwaende, Dschungelkamm ebenfalls als Gebirge.
- HOEHENSTUFEN (`_face_color_grund`, Konstanten HAUPT_*): Bergwald bis FLORA_MAX_H 860 m
  (Baeume bis BERGWALD_STEIL_AB), Almwiese 480–780, Fels ab 740 (unten nur an Waenden),
  Schnee ab 860 (haftet in der Hoehe auch steiler), Gletschereis `_eis_farbe` ab 1450.
  Grenzen wandern ±90 m. Vorher: Fels ab 59 m, Schnee ab 188 m = braunes Tarnmuster.
- KUESTE: `_kueste_versatz` (3 Massstaebe, bis ±7 km, Steilkueste an Kaps) mit
  `kuesten_anker` (fest = Kuestenflugplaetze, meer = Schiffe/Inseln/Wracks/Lagune duerfen nur
  Wasser bleiben). Drei Golfe (`nur_senken`, `breite`, `breit_rausch`; Muendung auf SEA_Y−18,
  sonst Rinne durchs Meer), Suedostzunge, gewundener Fjord, Hakenzunge mit Seegatten
  (`luecken`, `breit_rausch` fuer Landformen).
- LANDSCHAFTSKAMMERN `land_kammer` (~14 km): Huegelland (+28..90 m, dicht bewaldet,
  `kammer_wald`) gegen Ebenen mit FELDFLUR (`_feld_staerke`/`_feld_raster`/`_feld_farbe`):
  Flurbloecke 2,2 km mit eigenem Winkel (stetiger Winkel drehte um den Weltursprung =
  Wirbel!), Felder 110–190 × 1,9, Hecken an den Rainen (`_feld_wald`), nicht im Hochtal.
  Grundwelligkeit angehoben (+55 % Amplitude): vorher 6,6 % des Binnenlands auf Strandhoehe.
  Wueste auf der Hauptinsel nur noch unter HAUPT_WUESTE_AB (−0,50) und unter 140 m.
- DUNST wird mit der Kamerahoehe duenner (`Main.nebel_ende_bei`/`nebel_form_bei`, siehe
  Abschnitt „Tiefennebel“ unter Welt-Look); Godots fog_height hilft NICHT (legt nur Dunst unter eine Hoehe,
  entfernungsunabhaengig).
- STREAMING: 2 eigene Worker-Faeden (`WORKER_FAEDEN`, Messreihe dort) — die Chunks kosten
  ~50 % mehr; im WorkerThreadPool standen sie hinter der Fernschuerze (schlechter als 1 Faden).
  Jeder Faden kostet den Hauptfaden Zeit: CPU je Flugframe jetzt ~1,8 ms (vorher ~1,2).
- Wasser: siehe Abschnitt „Wasser" (Meeresscheibe bis zum Horizont statt Platte).
- KARTE: Feinstufe (2048) wartet, bis die Fernschuerze steht (sonst 36 s Horizont beim Start,
  jetzt 4,6 s; die Feinstufe braucht dafuer ~64 s statt 48). Hangschattierung in
  `WorldMap._zeile` ist SYMMETRISCH (Gefaelle · Lichtrichtung, kein Lambert): Lambert dunkelt
  raues Gelaende im Mittel ab, die Detailkacheln (kuerzere Messbasis) lagen als dunkle
  Quadrate auf der Grundkarte.
- Belege: `_luftbild.gd`, `_welt_uebersicht.gd`, `_ruck_check.gd` (Rueckstand in Baumreichweite
  ~30 wie vorher), Hochtal-Checks (`_gebirge_check`, `_kaverne_*`, `_tor_check`) unveraendert.
  `_haupt_pruefsumme.gd` gilt ab jetzt fuer den NEUEN Stand (Eingriffe an Regionen pruefen).

## Wasser (Umbau 2026-09: undurchsichtig, Tiefentextur, Meer bis zum Horizont)
Shader: `shaders/wasser_kern.gdshaderinc` (ganze Logik + Begruendung), eingebunden von
`water.gdshader` (UNDURCHSICHTIG + `EIGENER_DUNST`: Meer, Fluesse) und `water_see.gdshader`
(`DURCHSICHTIG`: Inlandseen, klein im Bild). Materialien baut `TerrainWorld._water_mat`.
- GEMESSEN (`tools/_wasser_zeit.gd`, 4K MSAA 4x, mit/ohne Wasser): alt 2,8 / 3,4 / 3,5 ms
  (Strand / Gegenlicht / offene See 2,5 km), neu −0,1 / 0,3 / 1,3 ms. Die Posten waren:
  Tiefenpuffer lesen (~1 ms: Godot kopiert/loest ihn auf, sobald EIN sichtbares Material
  `hint_depth_texture` nutzt), Mischen der durchsichtigen Flaeche (~1 ms), anisotrope
  Filterung der Wellentextur (1–2 ms!). Undurchsichtiges Wasser verdeckt dafuer im
  Tiefen-Vorpass den Meeresgrund — deshalb am Strand billiger als gar kein Wasser.
- TIEFE OHNE TIEFENPUFFER: zwei Hoehentexturen. FEIN = 8-m-Raster der geladenen Chunks
  (`_make_chunk_data` liefert je Chunk einen 48×48-Block `tiefe`, `_tiefe_eintragen`
  blittet ihn RINGFOERMIG in ein 1152²-RH-Bild — Chunk (kx,kz) → Block (kx mod 24, kz mod
  24); abgebaute Chunks bekommen `TIEFE_LEER` = 20000; Upload hoechstens alle 0,12 s).
  Der Shader interpoliert EXAKT die zwei Dreiecke je Zelle wie das Gelaendenetz. GROB =
  rohe Hoehen der Weltkarte (`WorldMap.generate_image(..., hoehen_aus)` → Main
  `_wasser_grund_bild`/`_wasser_grund_setzen` → `setze_grobe_tiefe`), 512 dann 2048 px.
  Durchsichtigkeit wird nachgebildet: `grund_col` (Sand; je Klima in `_wasser_klima`)
  scheint mit exp(−Tiefe/`klarheit`) durch.
- MEER BIS ZUM HORIZONT (`unendlich`): Netz `_meer_scheibe` traegt nur ein Ringmass s; der
  Vertex-Shader legt s = 1 auf den Kreis, in dem die Meeresebene die Kugel `schale_r`
  (= 0,975 × Fernebene, `setze_sichtweite`) schneidet, und zieht alles dahinter auf dem
  Sichtstrahl auf die Kugel. FALLE: mit FESTEN Ringradien entstand zwischen letztem
  ebenen und erstem herangezogenen Ring eine Rampe (aus 700 m bis 140 m hoch), die ferne
  Felder als graue Flaeche verdeckte. Jenseits der Fernebene malt die Scheibe Land aus der
  Grobkarte als dunstige Silhouette (`land_col`).
- EIGENER DUNST (`fog_disabled`): Godots Nebel saehe hinter der Kugel nur deren Radius →
  Knick im Verlauf, aus 2,5 km Hoehe ein Bogen quer durchs Meer. Der Shader rechnet
  Godots Formel selbst mit der ECHTEN Entfernung (Tiefennebel: `pow(smoothstep(dunst_anfang,
  dunst_ende, d), dunst_form)`); Farbe/Kurve aus der Umgebung (`setze_nebel_licht` einmal
  nach setup, `setze_dunst(anfang, ende, form, farbe)` je Frame aus
  `Main._wolken_aufenthalt`): Nebellicht
  (linear) gemischt mit sky `col_deep` um `fog_aerial_perspective`, plus Sonnenstreuung.
- WELLEN: `shaders/wasser_wellen.res` (von `tools/_wellen_textur.gd`): kachelbare Summe von
  56 Sinuswellen mit ganzzahligen Wellenvektoren, RGBA-Halbfloat = (dh/du, dh/dv, h,
  Schaumnetz), Mipmaps. Fuenf Oktaven (Duenung doppelt → wandernde Gruppen) je EIN Abruf;
  kurze Oktaven und Schaumnetz entfallen in der Ferne. KEINE Anisotropie (s. Messung).
  Brandung: Linien gleicher TIEFE laufen aufs Ufer zu (`brandung*`), Schaumkronen auf
  Kaemmen in rauen Windfeldern (`weisskappen`, `windfelder`), Durchleuchtung im Gegenlicht.
- Werkzeuge: `_wasser_zeit.gd` (GPU-Preis, 4K), `_tiefe_upload_zeit.gd` (Upload im Fenster —
  headless ist `ImageTexture.update` ein Leerlauf), `_luftbild.gd` (wartet jetzt bis 9000
  Frames auf die Schuerze: nach einem 20-km-Sprung braucht die grobe Stufe ~67 s, solange
  die 2048er-Karte rechnet — vorher entstanden Bilder mit fehlender Kachel).

## Bild-Look (2026-09): Farbabstimmung, Lichtglanz, Flug-Blick, Wolken
- FARBABSTIMMUNG: `Main._farb_lut` baut eine 24³-LUT (sRGB → sRGB) fuer
  `env.adjustment_color_correction` — laeuft im Tonemap-Pass mit, kostet nichts. Sanfte
  S-Kurve (30 %), Schatten kuehl / Lichter leicht warm (quadratisch gewichtet, Mitten
  neutral), Filmschwarz. FALLE: die Waerme im ersten Anlauf (0.030/0.012/−0.024) machte
  sonnenbeschienene Wolken beige.
- LICHTGLANZ = Glow, Grafikoption `gfx_lichtglanz` (Pausenmenue, Standard an). Schwelle
  2.4 UEBER sRGB-Weiss (1.56): nur Sonne, Glitzerfunken, Nachbrenner, Explosionen gluehen.
  Gemessen 1,5 ms in 4K (`tools/_gefuehl_zeit.gd`) — der teuerste Teil des Looks.
  Schwelle 1.6/2.0 liess den Glitzerpfad zu einer weissen Saeule aufbluehen.
- FLUG-BLICK (`shaders/flug_blick.gdshader`, ColorRect `_blick` als ERSTES Kind von
  `flight_root`, also unter dem HUD; `Main._blick_nachfuehren`): Sonnenschleier +
  Linsenreflexe auf der Achse Sonne→Mitte, Tunnelblick ab ~4,8 G (voll 9,5), Rotsicht
  unter −1,2 G, leichte Tempo-Vignette ab 150 m/s. KEIN SCREEN_TEXTURE: alles mit
  `blend_premul_alpha` in einem Aufruf (0,3 ms in 4K). Sonnensicht = im Bild UND nicht
  hinter Gelaende (Strahl, Ebene 1) UND Wolkendichte an 9 Punkten des Sonnenstrahls
  (jeden 3. Frame), geglaettet. Last = `AircraftBody.load_factor`, traege nachgefuehrt
  (Aufbau ~1 s, Erholung schneller). `blick_test_g` erzwingt eine Last fuer Bildwerkzeuge.
- WOLKEN (`CloudField.PUFF_SHADER`): FALTEN aus `COLOR.g` — beim Bauen
  (`_nachbearbeiten`) aus der UNGEMISCHTEN Normale gegen die Richtung zur Wolkenmitte
  gemessen (Kuppe 0, Kerbe 1), weil die Normalenmischung (NORMALEN_MISCHUNG) genau diese
  Kerben fuer das Sonnenlicht glaettet. Dazu weiche Silhouette (Rand nimmt Himmelsfarbe
  an, Emission), Nahdunst unter ~300 m, dunklere kuehle Baeuche, Wrap 0.38 statt 0.60
  (sonst mit der Sonne im Ruecken alles weiss), Helligkeit 0.47, dritte Krume-Oktave nah.
  Hohe Lagen mischen Himmelsfarbe bei (`himmel_misch` Schaefchen 0.52, Linse 0.30) —
  sie standen als weisse Punkte ueber dem Himmel; Schaefchen `cover_thresh` 0.20.
- Werkzeuge: `_gefuehl_bilder.gd [-- sonne berge wolken kueste g_last]` (echte
  Verfolgerkamera; `GEFUEHL_ALT=1` = ohne LUT/Glow/Blick, `GEFUEHL_OHNE_GLOW=1`),
  `_gefuehl_zeit.gd` (Kosten von Glow, Blick, Wolken in 4K).

## Welt-Look (2026-09): Stil Zelda BotW / Ghibli — seit 2026-10-01 „SATT & KLAR“ (siehe unten)
Verlauf: Low-Poly (Facetten) passte laut Nutzer nicht zum Spielkonzept → erste glatte Fassung
mit Rauschkorn-Detailtextur, Fleckenmuster und Blattrauschen wirkte "billig und alt" →
Nutzerentscheid: MODERN-STILISIERT wie Zelda/Ghibli (Memory `stil-zelda-ghibli`). Keine
hochfrequenten Rauschtexturen mehr; Form ueber Palette, weiches Licht und Dunst.
- GLATTES NETZ (`TerrainWorld._make_chunk_data`, `Main._fern_kachel`): Hoehenraster MIT RAND
  ((n+3)^2, `RAND_N`), Normale je Eckpunkt aus zentralen Differenzen (`glatte_normalen`) —
  der Rand sorgt dafuer, dass Nachbarchunks an der Naht dieselbe Normale haben. Farbe je
  Eckpunkt (`_face_color` mit Eckpunkt + Normale, 2401 statt 4608 Aufrufe je Chunk),
  indiziertes Netz, dieselben Dreiecke (Diagonale 00-11 — Wasser-Tiefentextur, Baumfuss,
  Kollision rechnen damit). MULDENTOENUNG (`mulden`, `mulden_ton`): Rinnen dunkler, Grate
  heller. Chunkbau 27,8 → 19,7 ms (mit Grasmaske 22,5 ms). `_face_color`/Hoehe/Wald/Biom
  unveraendert (`_haupt_pruefsumme` bitgleich). `_skriptzeit` unveraendert (Silberfluss 1,99).
- PALETTE + LICHT (`shaders/palette.gdshaderinc`, geteilt von Gelaende und Gras; Werte und
  Licht seit 2026-10-01 siehe „STIL SATT & KLAR“ unten): EINE
  Gruen-Rampe (GRAS_TIEF Blaugruen → MITTE → HELL Gelbgruen, bewusst gedeckt — hellere Werte
  gaben mit Sonne 1.7 grelles Lindgelb); Lage auf der Rampe aus der Helligkeit der Rohfarbe
  (`gras_lage`: Waldboden dunkel, trockene Wiese hell) + sehr grosse Verlaeufe (`VERLAUF`,
  5,2/1,3 km, G-Kanal von `boden_detail.res`) + Almen heller. Fels: nur der FARBTON aus einer
  kuehl-grau → warm-Kalk-Rampe, Helligkeit bleibt (sonst wurde der Vulkanbasalt mittelgrau),
  an steilen Flanken grosse weiche Baenke aus dem G-Kanal (der R-Kanal ist Korn = Rauschen).
  Schnee blauweiss. `weiches_licht` in light(): smoothstep(-0.18, 0.72, N·L) statt Lambert.
- GELAENDE-SHADER `shaders/gelaende_kern.gdshaderinc` (Chunks `gelaende.gdshader`, Schuerze
  `gelaende_fern.gdshader` mit FERN = Grundabsenkung, Felsboegen in Landmarks). Glut der
  Lavarinnen weiter aus COLOR.a.
- UMGEBUNG (Main._setup_world): Tiefennebel NEBEL_ANFANG 800 m / NEBEL_ENDE 17 km /
  NEBEL_FORM 1.0, NEBEL_FARBE_FREI sattes Mittelblau (0.36/0.54/0.86), aerial 0.25,
  Sonnenstreuung 0.25 (Stand „Baba“-Runde, siehe unten; davor 1 km / 20 km, 0.70/0.81/0.95,
  0.74, 0.35), Ambient 0.62, Sonne 1.7 NEUTRAL (1.0/0.95/0.86, vorher golden
  1.0/0.91/0.74), Gegenlicht 0.46, Saettigung 1.06 (vorher 1.18: Bonbonfarben).
- TIEFENNEBEL STATT EXPONENTIELL (2026-10, Nutzer: „Boden und Berge schauen washed aus“).
  BEFUND (`tools/_boden_look.gd`, feste Stellungen, Saettigung/Helligkeit je Bildstreifen):
  der exponentielle Dunst (0.000155) lag schon auf 1 km bei 14 %, auf 3 km bei 37 %. Er ist
  in LINEARER Helligkeit vier- bis fuenfmal so hell wie besonnte Wiese — 15 % davon
  halbieren die Saettigung im sRGB-Bild (aus 950 m: 0.86 ohne Dunst, 0.41 mit). Aus der
  Flughoehe sieht man den Boden aber immer aus 1-3 km. Die DUNSTFARBE zu aendern brachte
  nichts (dunkleres Blau, weniger Luftperspektive: gleiche Zahlen), nur die MENGE.
  `FOG_MODE_DEPTH`: Menge = smoothstep(Anfang, Ende, d)^Form (Dichte 1 = Hoechstmenge). Erste
  Fassung (Commit 9deb8a7) Anfang 0 / 18 km / 0.6 — dem Nutzer immer noch „richtig milchig“;
  gewuenscht Dunst NUR AM HORIZONT. JETZT am Boden 3 km 3 %, 5 km 11 %, 9 km 38 %, 14 km
  76 %. Ganz klar bis 10 km geht nicht, solange die Kamera bei KAMERA_FERN 9 km endet
  (dahinter nur die Landsilhouette der Meeresscheibe). HOEHE in zwei Stufen: bis 2,2 km nur
  Ende x1,5 (Boden aus Reiseflughoehe klar), 2-5 km Form 1 -> 0.45 und Ende noch x1,35 —
  nur das Ende zu strecken liess an der Fernebene zu wenig Dunst (Land endete aus 5 km Hoehe
  als scharfe Scheibe), sonst machte die Kurve vor den fernen Kuesten zu; oben verhaelt er
  sich jetzt wie der alte (9 km 37 %, 25 km 83 %). In der Wolke: Anfang -> 0, Ende
  LOGARITHMISCH auf NEBEL_WOLKE_ENDE (160 m), Form -> 0.6 (Weissabriss wie vorher, Bildprobe
  `fetzen`/`im_sturm`). Wasser (wasser_kern `dunst_anfang/_ende/_form`) und Gewitterzelle
  (CloudField `nebel_anfang/_ende/_form`) rechnen dieselbe Kurve; Main reicht sie je Frame
  ueber `TerrainWorld.setze_dunst(anfang, ende, form, farbe)` weiter.
  WERKZEUG-FALLE: `Main._wolken_aufenthalt` setzt Nebelkurve und -farbe JEDEN Frame neu —
  wer im Werkzeug an der Umgebung dreht, muss es in `RenderingServer.frame_pre_draw` tun
  (so `_boden_look`, Fassungen ueber `BODEN_FASSUNGEN`, z. B. `basis,ohne_dunst,e1.3+f0.7`).
- STIL „SATT & KLAR“ (2026-10-01, Nutzer nach dem ersten Dunst-Umbau: Berge „richtig
  milchig“, Boden-Stil „ned so gut“; aus drei Optionen gewaehlt: glatte Farbflaechen OHNE
  Texturen, aber dunkler, satter, kontrastreicher; Memory `stil-zelda-ghibli`). Ursachen des
  Milchigen in den Bergen ausser dem Dunst: (1) `TerrainWorld._warm_kalt` gab der Schatten-
  seite steiler Felsen eine HELL-BLAUE Albedo (0.44/0.47/0.56) — mit Himmels- und Gegenlicht
  fahl-blaue Flanken; (2) das breite `weiches_licht` (flacher Boden 0.71 gegen Sonnenhang
  0.92 — kaum Relief); (3) blasse Almwiese (0.56/0.60/0.36, knapp ueber der Gruenerkennung
  des Shaders, blieb roh). JETZT:
  * `klares_licht` (palette.gdshaderinc) fuer Gelaende, Gras und beide Strassenshader:
    smoothstep(-0.06, 0.90, N·L)·1.08 (flach 0.57, Sonnenhang 1.08). Haeuser behalten
    `weiches_licht`.
  * HIMMELSFUELLUNG IM LICHT: wo die Sonne nicht ankommt (abgewandt ODER Schlagschatten),
    addiert `klares_licht` HIMMEL_FUELL (0.36/0.43/0.55) — die Sonne erkennt es an der
    Richtung (`step(0.995, dot(l_welt, sonne_dir))`, neue globale Shader-Variable
    `sonne_dir` in project.godot, gesetzt in `TerrainWorld.setze_sonne`). FALLE: Godots
    ACES drueckt alles unter ~0.02 linear fast auf null (0.01 -> 9/255) — Schattenseiten
    waren mit dunklem Fels SCHWARZ (unterstes Zehntel 3/255). Pauschale Emission 0.12 gab
    9/255, eine nach Flaechenrichtung gerichtete 15/255 (erreichte die Schlagschatten der
    Grate nicht), die im Licht jetzt 26/255.
  * Palette: GRAS_TIEF 0.08/0.23/0.15, MITTE 0.20/0.39/0.16, HELL 0.40/0.53/0.22
    (Saettigung 0.6; 0.7 gab ohne Dunst Neonrasen 0.78-0.85 im Bild). FELS_TIEF
    0.34/0.36/0.40 -> FELS_HELL 0.58/0.57/0.55 (neutrales Granitgrau), Felshelligkeit
    `hell*0.85+0.02` (Basalt bleibt schwarz). Eine dunkle Skala 0.10-0.50 mit Graubraun gab
    „Schokoladenberge“ mit schwarzen Schatten. CPU (`_face_color`): Hochgebirgsfels
    0.24/0.23/0.22, Almwiese 0.40/0.54/0.24, `_warm_kalt` kalt 0.25/0.27/0.32 / warm
    0.68/0.57/0.42 (Karte und `_haupt_pruefsumme` aendern sich damit).
  * SONNE NEUTRAL (1.0/0.95/0.86): die goldene Sonne liess linear nur 51 % Blau durch und
    machte grauen Fels braun (Median 78/67/45) und Wiesen gelb-neon. Nebeneffekt: Wolken
    und Gewitter grau-weiss statt beige.
  Werte (Median Fels der Hauptkette im `berge`-Flugbild): vorher 146/150/157, P10 84 (fahl)
  -> 90/87/79, P10 26. `_boden_look` Saettigung nah/mitte: berge 0.41/0.32 -> 0.78/0.68,
  ebene 0.55/0.44 -> 0.86/0.81, wiese 0.48/0.40 -> 0.76/0.79, reise 0.43/0.36 -> 0.72/0.68.
  Bildprobe: `_gefuehl_bilder.gd -- berge mittel reise heimat_ost wald_sonne kueste hoch`.
- BODENMATERIALIEN / ECHTE TEXTUREN (2026-10-01, Nutzer: „schaut alles so billig aus,
  rueste es auf“; gewaehlt: echte Texturen, SELBST ERZEUGT, kein Download). Sechs kachelbare
  Materialien aus `tools/build_bodentexturen.py` (numpy/scipy, periodisch: FFT-Rauschen,
  Zellen mit `cKDTree(boxsize)`, `np.roll`): Gras (Halme + Bueschel), Waldboden (Nadeln, Laub,
  Moos), Erde (Klumpen, Kiesel), Sand (Windrippel), Fels (Kluftkoerper mit schraegen
  Flaechen, GESTUFTE waagerechte Schichten, Risse auf den Blockkanten), Schnee. Je Material
  Farbe als FAKTOR mit Kanalmittel 1 (RGB/2) + Hoehe (A) und Normale (RG) + Hohlkehle (B).
  `--vorschau <png>` zeigt alle sechs beleuchtet. `tools/_bodentexturen.gd` speichert sie als
  Image-Ressourcen nach `shaders/boden/` (FALLE: ein Texture2DArray speichert seine Bilddaten
  NICHT mit — 185 Bytes), `TerrainWorld.boden_material()` baut daraus zwei Texture2DArrays
  (`boden_material_setzen` fuer Chunks und Felsboegen; die Schuerze FERN tastet nicht ab).
  SHADER (`gelaende_kern`): Material aus der Rohfarbe erkannt (dunkles Gruen = Waldboden,
  Gruen/Stroh = Gras, warm-hell = Sand, warm-dunkel = Erde, steil oder grau = Fels, Weiss =
  Schnee; Sonderfarben bleiben glatt), je Material zwei Massstaebe (zweiter x4,7 und
  gedreht, Normale zurueckgedreht), Fels TRIPLANAR (Zeilen = Hoehe, Schichten waagerecht —
  die alte Felszeichnung hing nur an (x, z) und lief an jeder Wand als senkrechte Streifen),
  UEBERBLENDEN NACH HOEHE (Steine ragen aus der Wiese), Farbe = Palette x Faktor, Normale
  gestoert (RELIEF), Hohlkehle in die Albedo, ROUGHNESS 1 / SPECULAR 0.2 (die Standard-
  Rauheit 0.5 legte bei flachem Blick eine Himmelsspiegelung als Schleier aufs Gelaende).
  Felshelligkeit ueber 0.2 zur Haelfte auf 0.42 gezogen (Streifen und weisse Kalkwaende
  weg). Dazu WIESEN_FLECKEN (palette: 240 m + 70 m, Gelaende UND Grashalme) und flache
  BODENBUCKEL (B/A-Kanal von boden_detail, 34 m) — die Grastextur sieht man erst unter
  ~30 m, aus Flughoehe lag die Wiese sonst als Golfplatz da. Werkzeug-Fehler beim Bauen
  (fuer spaeter): Zellnummern beim Verbiegen interpolieren gibt Schnoerkel an den
  Zellgrenzen (ordnung=0), Nulllinien eines Rauschfelds als Risse sind geschlossene
  Schleifen (Wuermer).
  KOSTEN (`_gelaende_zeit`, 4K MSAA 4x, alle fuenf Stellungen): Bild im Mittel 14,26 ->
  15,38 ms (Wald 16,48 -> 17,24, Schlucht 12,43 -> 13,67, Mittel 700 m 16,90 -> 18,68).
- BAEUME: Modelle (`tools/build_baeume.py`, zweite Fassung 2026-10; Datei zum Ansehen
  `blender_lib/baeume.blend`). BEFUND der ersten Fassung: in JEDER Laubkrone zeigten 144
  Flaechen nach innen (die ganze untere Kronenhaelfte, gemessen per Volumenvorzeichen) —
  Kronen waren von der Seite/unten HOHL; Palm-/Farnwedel einseitig; Birkenringe standen als
  Kragen ab; Schnee der Schneetanne schwebte als Baender neben den Kraenzen. Ursache: offene
  Ringstreifen + `recalc_face_normals` (raet auf offenen Streifen falsch). JETZT: jedes Teil
  ein GESCHLOSSENER Koerper im eigenen bmesh (`ballen` = Ikosaederkugel 80 bzw. UV 8x4 = 48
  fuer Nebenballen, `kranz` = Kegel mit Zackenrand UND Unterseite, `rohr` = Zylinderzug per
  Paralleltransport), Wicklung per Volumenvorzeichen gesichert, DANACH verdeckte Deckel
  entfernt (`offen="uo"`: Fuss im Boden, Enden in der Krone). Wedel ZWEISEITIG (eigene
  Eckpunkte, bmesh verbietet zwei Flaechen ueber dieselben). Staemme bis 0.8 m UNTER den
  Boden (am Hang schwebte die Talseite). Schnee = Farbe in den Kerben jedes Kranzes. Kronen
  als Wolken aus 3-5 Ballen, Stamm weich schattiert (`set_sharp_from_angle` 95 Grad),
  Farbstreuung je ECKPUNKT (je Flaeche zerfiel der Stamm im Export in Einzelecken).
  Neuer FELSBROCKEN "Fels" im selben glb (ersetzt `_build_rock_mesh`, der bleibt Ersatz).
  LAUB-ERKENNUNG (`_ist_laub`): Farbregel Gruen > Rot (Holz/Rinde haben Rot >= Gruen) — eine
  Marke im Alpha kam nicht an (glTF-Export ohne Alpha). Zahlen (`tools/_flora_zahlen.gd`,
  nach der Aufbereitung): 3921 Dreiecke / 2208 Eckpunkte fuer 13 Arten (vorher 3743 / 3260).
  GPU (`_gelaende_zeit`, 4K): Flora 2,27 -> 2,51 ms im Mittel, Wald 22 m 4,26 -> 4,53.
  Sichtprobe: `tools/_flora_tafel.gd -- <ordner>` (Spielweg, drei Blickwinkel + Fernstufe).
- BAEUME, DRITTE FASSUNG (2026-10, Nutzer: "mach dass die Baeume und so besser aussehen").
  BEFUND aus Flugbildern (nicht aus der Artentafel — dort sah die zweite Fassung gut aus):
  der Nadelwald, also fast die ganze Insel, stand als Stapel glatter Zackenkegel in EINEM
  Smaragdgruen da (ueber 42 m gab es nur Fichte + 14 % Totholz), Laubkronen als 3-5 Kugeln,
  jede fuer sich beleuchtet, Birken neongelb, die Fernstufe der Laubbaeume fuenfeckige Rauten,
  und im Gegenlicht leuchtete jeder Baum flaechig grell.
  * MODELLE (`tools/build_baeume.py`): `Baum.etage` = Astlage als GLOCKE aus haengenden
    Zweigen (Ruecken, Spitze, Kerbe; 6 Dreiecke je Zweig, geschlossen), Farbe nach der ROLLE
    des Punkts (helle Ruecken/Spitzen, dunkle Kerben) — von oben ein Stern aus Zweigen. Sechs
    flache Etagen mit Schattenspalt darunter (erster Anlauf: fuenf hohe = Umhaenge aus Stoff;
    Zacken 0.30 mit hochgezogener Kerbe = rechteckige Ausschnitte). `Baum.krone` = ein Kern
    (80 Dreiecke) + 3-4 Wolken + Buckel aus der 60er-Kugel ("mittel": Ikosaeder + `poke`);
    das nackte Ikosaeder (20) taugt nur fuer Steine — als Laubbuckel stand es als Kristall
    im Umriss. Jeder zweite Ballen heller. Palme mit zwei Wedellagen, Fels = Block + zwei
    Brocken in Gelaendefarben. Palette gedeckter (NADEL_*, BIRKENLAUB 0.36/0.55/0.25).
    FALLEN: (1) Farbe aus der FLAECHENNORMALE gibt je Flaeche eine andere Farbe am selben
    Punkt -> der Export teilt jeden Eckpunkt (Fels 227 statt 66 Eckpunkte); Farbe nur aus der
    Lage rechnen. (2) Dreiseitige Aeste (segs=3) sparen Dreiecke, kosten aber Eckpunkte: 120
    Grad zwischen den Flaechen liegen ueber der Weichgrenze (95), jede Kante wird geteilt.
  * LICHT BEIM LADEN (`TerrainWorld._weiche_krone`): Normale = 0.45 geglaettete Netznormale
    + 0.20 Huelle des Ballens + 0.35 Huelle der GANZEN Krone (vorher reine Ballenhuelle =
    lauter einzeln beleuchtete Murmeln). FUGEN: Abstand zum naechsten ANDEREN Ballen in
    dessen Halbachsen -> dunkel in der Kehle (KRONE_FUGE 0.64); dieselbe Regel dunkelt jede
    Astetage unter der naechsten ab. Verlauf zur Haelfte aus "Flaeche zeigt nach oben".
  * SHADER (Flora, in TerrainWorld.setup): kuehle Himmelsfuellung als EMISSION auf dem Laub
    (wie haus.gdshader; Schattenseite Blaugruen statt Schwarz) und DURCHSCHEINEN NUR AM SAUM
    (`saum = 1 - N.V`, hoch 3) — flaechig gerechnet war ein Wald im Gegenlicht grell und
    formlos, jetzt dunkle Massen mit leuchtendem Rand.
  * BERGMISCHWALD (`_bewuchs_rechnen`, BERGWALD_REIN_AB 360 m): zwischen 42 und 360 m
    Fichte 74 / Kiefer 12 / Birke 5 / Busch 4 / Totholz 5 %, darueber Fichte 88 / Totholz 12.
    Weiter EIN Zufallszug je Pflanze -> Lage und Drehung aller Pflanzen unveraendert.
  * FERNSTUFE (`_stellvertreter`, `_stellvertreter_flach`): Masse und Farben (drei Lagen) aus
    dem LAUB des Originals; rund oder spitz entscheidet der Kronenradius im oberen Drittel
    (> 55 % = Kuppel aus zwei verdrehten Viererringen, sonst Kegel) — vorher "breiter als
    55 % der Hoehe", damit war die Birke in der Ferne eine Fichte. Stamm als Pyramide (3
    statt 6 Dreiecke): Fichte 8 statt 11, Kuppel 19 statt 26. Busch und Fels: Huegel aus 12
    Dreiecken statt des halben Originalnetzes. ALTER FEHLER dabei gefunden: `_grobe_fassung`
    zaehlte "Eckpunkte / 3" als Dreiecke — das indizierte Totholz (125 Dreiecke, 78 Eckpunkte)
    fiel unter die Schwelle, bekam nie einen Stellvertreter und kostete allein 0,6 ms.
  * GEMESSEN (`_gelaende_zeit`, 4K, alle fuenf Stellungen im selben Lauf): Flora alt 2,59 ms
    -> neu 2,42 (Wald 22 m 4,61 -> 3,80; Mittel 700 m 3,23 -> 3,37), Bild 14,26 -> 14,15.
    Zwischenstand mit Mischwald und alten Fernfassungen: 3,28 ms — die Fernstufe ist der
    groesste Posten, nicht die Nahmodelle. Dreiecke/Eckpunkte aller Arten (`_flora_zahlen`):
    4001/2288 -> 4627/2553. FALLE: `GZ_NUR=<eine Stellung>` ist mit dem vollen Lauf NICHT
    vergleichbar (Hang allein 4,09 ms, im vollen Lauf 1,40 — andere Sparstufen der Chunks).
  * WERKZEUGE: `tools/_baum_probe.gd -- <ordner> [nah] [wald]` (Nahaufnahmen je Art aus drei
    Richtungen, Probewald tief/hoch/gegen die Sonne, Fernstufe — mit dem Spielweg, ohne die
    Welt zu laden: Sekunden statt Minuten; FALLE: verdeckt macOS das Fenster, speichert es
    denselben Frame mehrfach — gleiche Dateigroessen pruefen). `_gefuehl_bilder` hat die
    Szenen `wald_gegen`/`wald_sonne` (30 m ueber den Wipfeln; `tief_wald` steckt je nach Lauf
    mit der Kamera in einer Kiefernkrone). `_bewuchs_stufen_check` unveraendert OK.
  Beim Laden `_weiche_krone`: Normale je LAUBBALLEN (Union-Find ueber Eckpunktlagen),
  Farbe je Lage gemittelt (Flicken der Flaechenstreuung weg), Verlauf oben warm/hell
  (KRONE_OBEN_TON) → unten kuehl/tief (KRONE_UNTEN_TON), innen dunkler; dann
  `_laub_verschweissen` (gleiche Lage = ein Eckpunkt). Flora-Shader: Ton je Baum in COLOR,
  weiches Licht + Durchscheinen im Gegenlicht (in light(), Laub am ALBEDO erkannt — KEINE
  Varying: zehn Floats kosteten auf Apples Kachel-GPU 2,5 ms in 4K).
  FALLE SCHATTENNETZ (teuer gelernt): `shadow_mesh` des Imports zu uebernehmen ging schief —
  Godot zeichnet damit auch den TIEFEN-VORPASS; es passte nach dem Neuaufbau nicht exakt und
  der Farbdurchgang verwarf Teile jeder Krone (Loecher, fehlende Staemme, zerrissene Platten)
  — und die Messung sah dadurch "billiger" aus. Ein eigenes, UNKOMPRIMIERTES Schattennetz war
  noch schlimmer (gar nichts sichtbar: 16-bit-Lagen des Hauptnetzes ≠ Float-Lagen). Jetzt
  `_schattennetz` aus denselben Dreiecken mit DEMSELBEN Kompressionsflag. Beleg: Einzelbaum-
  Render roh vs. aufbereitet (Werkzeug im Verlauf, `TerrainWorld._weiche_krone` direkt).
- ZELDA-FASSUNG DER TEXTUREN (2026-10-01 abends). Die realistischen Boden- und Laubtexturen
  (Halme, Kiesel, Gesteinsschichten, Blaetter mit Mittelrippe, Einzelnadeln) fand der Nutzer
  „nicht passend“ — gewuenscht ist „zelda-maessig“ (BotW/TotK), ausdruecklich KEIN Comic
  (Memory `stil-zelda-ghibli`). Dieselbe Pipeline, neue Inhalte:
  * BODEN (`build_bodentexturen.py`): `tupfen` = Pinseltupfen mit Umlauf, Richtung aus einem
    weichen Stroemungsfeld, drei bis vier Toene (dunkel zuerst, hell zuletzt). Gras =
    gekaemmte Striche, Waldboden = Moostupfen, Erde = runde Tupfen (laengliche lasen sich als
    Fell), Sand = glatte Rippelbaender (Striche ebenfalls Fell), Fels = FLACHE BLOECKE
    (Zellen in einem Raum, dessen Hoehe doppelt zaehlt; runde Zellen = Pflaster) mit
    Lichtkante oben, Schatten unten, wenigen Fugen, Schnee = breite Verwehungen. FALLE:
    Tonstreuung je Farbkanal gab bunte Pastellflecken — Streuung nur in der Helligkeit.
    Shader: Kacheln groesser (Gras 4,5 m, Fels 34 m — mit 14 m lagen die Facetten als
    Schuppenhaut an den Waenden), RELIEF 0.9 -> 0.40, Hohlkehle 0.75 -> 0.45.
  * LICHT (`palette.gdshaderinc`, `klares_licht`): CEL-Rampe smoothstep(-0.02, 0.16, N·L) ·
    (0.74 + 0.31 · smoothstep(0.15, 0.95, N·L)) — weiche, aber klare Kante, flache helle
    Lichtseite (flacher Boden 0.80 statt 0.57), Himmelsfuellung im Schatten wie gehabt.
    Gruen etwas frischer (GRAS_MITTE 0.22/0.41/0.15, GRAS_HELL 0.42/0.54/0.20).
  * LAUB (`build_laubtextur.py`): `puff` = gemalte Laubwolke (gewellter Rand mit 5-7
    Lappen — mehr und ein zweiter Oberton gaben Zahnraeder), Licht von oben links, darauf
    `tupfer` (Pinselstruktur nur auf gedeckten Pixeln). Laubwolke, Birkenstraenge aus
    Woelkchen, Fichtenzweig aus ueberlappenden spitzen `lappen` mit Fransen (Fransen
    innerhalb des Umrisses anfangen, sonst schweben sie), Kiefer = leicht gezackte
    Bueschel OHNE Zweigstriche (die lagen als dunkle Linien ueber den Karten).
  Kosten unveraendert (4K Mittel 15,97 ms, Flora 2,63).
- „BABA“-RUNDE (2026-10-01 nachts, Nutzer nach der Zelda-Fassung: „schaut schon besser aus,
  aber mach so, dass es baba ausschaut“). BEFUND aus den Flugbildern, gemessen: Wald Median
  2/51/10 (Helligkeit 0.20, Saettigung 0.96) gegen Wiese 93/152/29 (0.60) = schwarzgruener
  Teppich neben Neonrasen; die Ferne lief ohne Tiefe in den hellen Horizont, das ferne Meer
  stand als GRAUES Band da; die Wolken fast einfarbig weiss (Styropor). Fuenf Eingriffe:
  * LAUB (Flora-Shader, `LAUB_TON`/`LAUB_SOCKEL`/`LAUB_SCHATTEN`/`FUELL_*`): EINE Tonkurve
    fuer alles Laub statt zwanzig Modellfarben — nur das DUNKLE Laub (g < 0.30..0.52) wird
    angehoben und zum Gelbgruen der Wiese gerueckt (mit derselben Kurve fuer helles Laub
    stand die Birke als Neon-Limette da), Schlagschatten auf Laub nur zu 72 % (bei 26 Grad
    Sonnenhoehe liegt im Wald fast alles im Schatten des Nachbarn, ACES drueckt das auf
    null), Cel-Rampe wie der Boden, mehr Himmelsfuellung. Dazu FARBTON je Baum (gelbgruen
    bis blaugruen, vorher nur Helligkeit) und gedecktere Rinde (Kiefernrot stand orange im
    Wald). FALLE: `_baum_probe` lief mit FILMIC und 42 Grad Sonne — dort sah der Wald laengst
    gut aus. Jetzt mit den Tonwerten des Spiels (ACES, LUT, SONNE_WINKEL, Gegenlicht).
  * BLAUE TIEFE (Main): Dunst als SATTES Mittelblau `NEBEL_FARBE_FREI` 0.36/0.54/0.86
    (vorher helles 0.70/0.81/0.95), `fog_aerial_perspective` 0.25 (vorher 0.74),
    NEBEL_ANFANG 800 m / NEBEL_ENDE 17 km (3 km 5 %, 5 km 17 %, 7 km 33 %, 9 km 51 %).
    Heller Dunst hellt die Ferne auf, bis sie im Horizont verschwindet (= milchig); sattes
    Blau FAERBT sie: blaugruene Staffeln vor hellem Horizont, das ferne Meer blau. Erste
    Fassung 300 m / 14 km legte auf die Gletscherkette aus 7 km einen sichtbaren Schleier.
    In der Hoehe wieder helle Luft (`nebel_farbe_bei`, NEBEL_FARBE_HOCH ab 1,5-4,5 km) —
    im Mittelblau stand das Land aus 5 km wie ein zweites Meer da. Wasser/Gewitter folgen
    ueber `setze_dunst`. Werkzeuge (`_luftbild`, `_boden_look`) setzen die Farbe mit.
  * WIESE: Gruen eine Spur weniger gelb (GRAS_MITTE 0.20/0.42/0.19, GRAS_HELL
    0.36/0.55/0.25), und WINDWELLEN (`WIESEN_WIND` in palette: wandernde Lichtbaender
    190 x 620 m, 8,5 m/s, ein Abruf des weichen G-Kanals; Gelaende und Grashalme).
  * WOLKEN (`PUFF_SHADER.light`): ZWEI TOENE mit weicher Kante (`kante`, `kante_weich`) statt
    Wrap-Verlauf, Schattenseite bekommt ein helles Himmelsblau als Licht (`schatten_ton`),
    das Gegenlicht zaehlt nur noch zu 35 % (es lief genauso weit um die Wolke wie die Sonne
    und hob die Schattenseite auf ~70 % der Lichtseite). PUFF_LOD_BIAS 0.35 -> 0.55 (eckige
    Umrisse naher Wolken).
  * ALMZONE (`_face_color_grund`, `steil_fels`): Fels in der Hochregion erst ab ~40 Grad
    (0.76/0.60 statt 0.82/0.68) — vorher Tarnmuster aus Wiesen- und Felsflecken. Aendert
    Karte und `_haupt_pruefsumme` oberhalb ~540 m.
  KOSTEN (`_gelaende_zeit`, 4K): Bild im Mittel 15,97 -> 16,12 ms, Flora 2,63 -> 2,70.
  Belege: `_loadcheck` 7x OK, `_grafik_check` 0 Beanstandungen, keine Warnungen.
  NICHT GEMACHT: Schneetanne/Palme/Dschungelarten haben weiter die alten glatten Kronen;
  aus 5 km Hoehe sieht man vom Land fast nichts (Fernebene 9 km, schon vorher so).
- BAEUME, VIERTE FASSUNG: BLATTKARTEN (2026-10-01, Nutzer: „billig, rueste es auf“, Baeume
  mit, Quelle SELBST ERZEUGT). Laub-Atlas `tools/build_laubtextur.py` (1024², vier Felder:
  Laubbueschel, Birkenzweiglein, Fichtenzweig mit Ansatz links, Kiefernbueschel; RGB =
  Helligkeitsfaktor/2 mit Mittel 1, A = Kontur, Farbe unter transparenten Pixeln ausgedehnt)
  -> `tools/_laubtextur.gd` -> `shaders/flora_laub.res`. `tools/build_baeume.py`: `Baum.karte`,
  `karten_krone` (je Ballen ein kleiner dunkler KERN gegen Durchblick + Karten auf der Huelle,
  nach aussen gedreht), `nadel_etage` (je Zweig zwei gekreuzte Nadelzweigkarten). Neu gebaut:
  Fichte, Kiefer, Birke, Eiche, Busch; die uebrigen Arten unveraendert. Karten erkennt man am
  UV (u > 0; feste Teile liegen auf u = 0, v ist nach dem Export 1). Beim Laden trennt
  `_karten_abtrennen` sie in eine eigene Flaeche "karten" (`_karten_aufbereiten`: Normale
  75 % Kronenhuelle, gemalter Verlauf, nicht verschweisst, KEIN Schattennetz — es traegt
  keine UVs). ZWEI MATERIALIEN aus einer Shader-Vorlage: `_flora_mat` (fest) und
  `_flora_karten_mat` (`#define KARTE`: Alpha-Schnitt, cull_disabled, Rueckseiten-Normale
  gedreht, Deckung waechst mit der Mipstufe — sonst wurden Kronen in der Ferne durchsichtig);
  Netze mit Karten bekommen KEIN material_override (`hat_karten`, `flora_materialien_setzen`,
  auch Hafenstadt und die Probe-Werkzeuge). DREI STUFEN: Karten bis `KARTEN_BIS` (420 m,
  skaliert mit der Baumweite), dahinter die geschlossenen Kronen der dritten Fassung
  (`<Art>_massiv` im selben glb, `_flora_massiv`/`_massiv_von`, eigene MultiMesh „mittel“ je
  Chunk ueber visibility_range), ganz fern die Stellvertreter (jetzt aus der massiven Krone).
  KOSTEN (`_gelaende_zeit`, 4K): ein Material fuer alles und Karten bis 1,2 km: Flora
  2,0 -> 9,4 ms; getrennte Materialien 7,1 ms; mit Mittelstufe 2,66 ms (Bild 15,38 -> 16,02).
  FALLEN: (1) eine eigene Materialflaeche fuer die Karten verlor im glTF-Export die
  Vertexfarben (Karten weiss, auch mit gesetztem aktivem Farbattribut) — dasselbe Material,
  Trennung erst in Godot. (2) Ein Texture2DArray speichert seine Bilder nicht (siehe Boden).
  (3) Nach dem Blender-Lauf `--editor --import`, sonst laedt Godot das alte glb.
  Belege: `_baum_probe` (Sichtprobe), `_baum_ausfall_check` 0 Ausfaelle,
  `_bewuchs_stufen_check` OK, `_hafenstadt_check` OK.
- GRASWIESEN (`_gras_aufbauen`, `shaders/gras_bahn.gdshader` platziert, `gras.gdshader`
  zeichnet): GPUParticles3D auf WELTFESTEM Raster um die Kamera (Hash je Zelle → nichts
  schwimmt), zwei Ringe (150² a 0,7 m bis 52 m, 112² a 1,9 m bis 105 m), Hoehe aus der
  Wasser-Tiefentextur (exakte Dreiecke), Maske `_gras_block` je Chunk (RG8 im selben Ring:
  Dichte aus gruener Bodenfarbe/flach/`_open_ground`, Helligkeit fuer die Rampe). Halme mit
  Normale nach OBEN (auch Rueckseite, cull_disabled) → gleiche Beleuchtung wie der Boden.
  Ab ~240 m ueber Grund aus, `GRAS_AUS_UEBER` gar nicht gezeichnet. `setze_gras(an)`.
  FALLE: Partikel-Builtins (INDEX, TRANSFORM, CUSTOM) gibt es nur direkt in start()/
  process() — in eine Hilfsfunktion als Parameter reichen.
- GEMESSEN (`tools/_gelaende_zeit.gd`, 4K MSAA 4x, 5 Stellungen): Bild im Mittel vor allen
  Umbauten 13,96 ms → jetzt 13,71; Flora 2,51 → 2,07 (korrekt gezeichnet, rundere Kronen);
  Gras 0,57 ms im Wald auf 22 m, 0,2 am Hang, 0 ab Reiseflughoehe. `_ruck_check` im FENSTER
  (headless rafft er 60 s auf 1 s Echtzeit): Fernfassungen der Baeume (`_grob_cache`) werden
  beim Laden gebaut statt beim ersten Gebrauch im Flug.
- WERKZEUG-FALLEN: `_luftbild` fotografiert nach einem Kamerasprung, bevor die Pflegeschleife
  die Chunks auf die Nahstufe stellt — Baeume in Chunks, die vom Start aus >1,2 km entfernt
  angelegt wurden, stehen dann als Fern-Stellvertreter (flache Rauten) im Nahbild. Test-HOMEs
  im Scratchpad koennen zwischen Sitzungen geleert werden: dann Erststart mit NEUEM Welt-Seed
  (andere Welt!) — vorher den Fortschritt (world_seed) aus dem echten user:// kopieren.
- FALLE: Tests mit Main.tscn und `--quit-after` ohne umgebogenes HOME laufen gegen den echten
  Spielstand — auch fuer den Warnungscheck immer HOME umbiegen.
- BEKANNT, ALT (nicht durch den Look): seltener Absturz beim Start (etwa 1 von 16–48), der
  Kartenfaden (WorldMap._grobfarben) meldet "propagate_notification ... caller thread" in
  `match reg:` der Nordregion und stuerzt ab. Auch auf 4f8a9da nachgewiesen. Werkzeug zum
  Nachstellen: `tools/_start_stress.gd` (mehrfach parallel, je eigenes HOME).

## Lebendige Welt (2026-09): Wolkenstrassen, Baumwind, Voegel
- WOLKENSTRASSEN (`CloudField._strassen_wert`, `STRASSEN_JE_TYP`): die Deckung der
  wandernden Decken folgt zusaetzlich Strassen laengs des Windes (Rauschen 9 km x 1,5 km
  gedreht) und Feldern (~11 km); Groesse nach Dichte quadratisch 0,48..1,85. Vorher ein
  gleichmaessiges Wattebausch-Raster (Ballung ~480 m bei 340 m Rasterabstand).
- TURMWOLKEN (`_form_turm`): 5-6 Ebenen, Schritt 0,55-0,75 Radius, Seitenwuelste je Ebene —
  vorher Kugeln im Abstand > Radius = Schneemaenner am Horizont.
- BAUMWIND (Flora-Shader in TerrainWorld.setup): Auslenkung ~Hoehe², Boeen als wandernde
  Welle, in WELTRICHTUNG gerechnet und per transpose(m)/s² in den Instanzraum gedreht
  (jeder Baum ist beliebig gedreht). Nur bis 900 m. Kosten nicht messbar.
- VOEGEL (`Main._voegel_aufbauen`, `_schwarm`): je Schwarm EIN GPUParticles3D, Bahn im
  Partikel-Shader aus TIME (Kreis bzw. Schwarm um wanderndes Zentrum), Fluegelschlag im
  Zeichen-Shader. Moewen an den Kuesten, Kraehen/Stare ueber Feldern, Greife ueber
  Schlucht/Kette/Hochtal, Raben am Vulkan. Groessen stilisiert (~2x echt). FALLE: das erste
  Vogelnetz lag in EINER Ebene — von gleicher Hoehe aus unsichtbar (per capture_aabb
  belegt: die Partikel waren da). Jetzt Rumpf mit Volumen, Moewenfluegel mit V-Stellung,
  Kreisende legen sich 20-35 Grad in die Kurve.
- WERKZEUGE: `_gefuehl_bilder.gd` haelt das Flugzeug waehrend des Wartens fest (sonst flog
  es Kilometer weiter, Chunks am Startpunkt wurden abgebaut, im Bild ein blasses Band, das
  im Spiel nicht existiert), `GEFUEHL_OHNE=fern|wasser|wolken|formationen` zum Eingrenzen;
  `_luftbild.gd` mit `LUFT_REL=1` = Hoehen ueber Grund.

## Sondergelaende der Hauptinsel (2026-09): Kalkplateau, Teufelsschlucht, Felsenstadt, Nadelkueste
Orte zum Herumfliegen, alle im HOEHENFELD (Kollision, Farbe, Bewuchs, Karte, Fernschuerze
gratis). Lage/Masse in `Main._sondergelaende` (feste Seeds), Gelaende in TerrainWorld
(`sonder_setzen` VOR setup(), `_plateau`, `_schlucht_cut`, `_tuerme`), alles in Packed-Arrays.
- KALKPLATEAU (ersetzt das WESTBERGLAND): Achse `PLATEAU_ACHSE`, halbe Breite
  `PLATEAU_BREITE`, Deckflaeche `PLATEAU_TOP` 250 m ABSOLUT (+-22 m Wellung). Kante =
  verrauschter Abstand zur Achse, gestuftes Profil `_plateau_rand_e` (Schutthang, untere
  Wand, Band, obere Wand). Eingehaengt NACH dem Felsrelief (sonst Buckelpiste). 11
  Zeugenberge vor der Kante. FALLE: Kantenrauschen 160 m auf 170 m Wellenlaenge = Orgel-
  pfeifen, aus der Ferne eine Zackenkette — jetzt 85 m auf ~300 m.
- TEUFELSSCHLUCHT + 2 Seitenschluchten (`_schlucht_linien`, `_linie_nachtasten` mit ueber
  +-150 m gemittelter Richtung — sonst springt der Maeander an Knicken): schneidet den
  Plateauanteil weg (gestufte Waende, Band), Raster `_sl_*` (CSR, 250 m). Boden im Plateau
  auf `SCHLUCHT_BODEN` 12 m gedrueckt — unter dem Plateau liegen Huegel bis 150 m, die
  Schlucht war dort halb so tief und der Bach grub einen 146-m-Schlitz. Beide Enden offen.
- KLAMMBACH (`_klammbach`, profil): NO-Ende → Hauptschlucht → Seitenschlucht 1 → Spitze
  der Westbucht. Tiefster Einschnitt 58 m (Durchbruch kurz vor der Bucht).
- FELSBRUECKEN (3) und MEERESTOR: `Landmarks.build_felsbogen` — Ringroehre um eine
  Bogenlinie, Enden tauchen ins Gestein, Wicklung selbstkorrigierend (`_bogen_tri`),
  Kalkfarbe, ConcavePolygon-Kollision. `_felsboegen_bauen` nach dem Felsentor.
- NADELKUESTE (27 Kreidetuerme vor der Westkueste, Riffsaum) und FELSENSTADT (34 Tuerme an
  Land vor der SO-Flanke, Luecken >= 80 m): `_tuerme` mit Form je Turm aus der Lage
  (Saeule, Zuckerhut, Stufenturm). FALLE: der Turmterm galt zuerst im ganzen Suchquadrat
  und hob dort den Meeresgrund per max() auf SEA_Y → helle quadratische Flachwasserfelder.
  Getrennte Huellrechtecke fuer Meer und Land.
- FARBE (`_sonder_farbe`, `kalk_farbe` static — auch fuer die Boegen): Waende am Plateau
  (nur wo `_plateau_anteil` > 0.02, im Huellrechteck liegen auch normale Huegel), Tuerme
  nur im Turm selbst (`_turm_u`), gruene Kappe oben.
- KOSTEN: height_at auf dem Plateau wie vorher mit dem Westbergland (15,4 us), in Schlucht
  und bei den Nadeln +2 us (gleiche Messung alt/neu, Fernschuerze angehalten).
- Kamerapunkte fuer Bilder: Schlucht nie schaetzen — die Linie ausgeben (sonst steht die
  Kamera im Fels und man sieht das Plateau von unten).

## Fluesse (Umbau 2026-09: Hauptstrom, Profil aus dem Gelaende, Zellenraster)
- HAUPTSTROM "Silberfluss" (`Main.HAUPTSTROM_PFAD`, `_hauptstrom`): 41 km von einer
  Gletscherquelle an der Nordkette (1038 m) durch Vorland, einen Huegelriegel (Durchbruch)
  und das Tiefland in die Suedostkueste. LAUF GEMESSEN mit `tools/_fluss_route.gd -- qx qz`
  (Dijkstra auf gewachsenem Gelaende, Talboeden bevorzugt, bergauf ×300, Flugplaetze/Orte/
  Vulkan gesperrt; gibt Punktliste + Profil aus). Waechst 4 → 26 m, Trichter an der
  Muendung, Maeander erst ab 5,5 km.
- PROFIL AUS DEM GELAENDE (`"profil": true`, `ziel_h`, `einsatz`): `TerrainWorld.
  _fluesse_profilieren` tastet das GEWACHSENE Gelaende (Fluesse aus) ab: laufendes Minimum
  unter dem Boden, Mindestgefaelle, nicht unter das Ziel, geglaettet. Wo der Lauf einen
  Riegel quert, graebt der Carve den Durchbruch. MUSS NACH den Kuestenformen und Felswaenden
  laufen (Main ruft `terrain.fluesse_fertigstellen()` direkt danach, vor build_now_around
  und Kartenfaden) — in setup() stand die Quelle sonst auf 8 statt 1038 m.
- BREITE/TIEFE JE STUETZPUNKT (`w_quelle`/`w`, `depth_quelle`/`depth`, `trichter`) →
  `rv["breite"]`, `rv["tiefe"]`; `maeander_ab` = Maeander erst ab Laufmeter.
- ZELLENRASTER FLACH (CSR): `_fl_start`/`_fl_seg` + Segmentdaten in Packed-Arrays
  (`_fl_a/_fl_b/_fl_w/_fl_t/_fl_d/_fl_mt`), 200-m-Zellen. `_river_carve`, `_fluss_naechst`,
  `_fluss_bereich_h`, `_submerged` lesen nur ihre Zelle. FALLE: die erste Fassung hielt die
  Segmentlisten in Dictionary/Array-Variants — die Chunk-Worker zaehlen dort atomar
  Referenzen, gemessen +0,3 ms je Flugframe auf dem HAUPTfaden. Raster nach jeder
  Hoehenaenderung neu bauen (`_fluss_gitter_bauen`: prepare, nach Seebaechen, nach Profil).
  Und die Grenze fuer Ufer/Auwald/Flussbett ist JE CHUNK (`_fluss_bereich_h`), nicht die
  weltweite `_flora_fluss_h` (seit der Gletscherquelle 1040 m → alles wurde geprueft).
- UFERDAMM LAEUFT AUS: `bank = lerp(max(Wasser+1,2, h), h, smoothstep(2w, Talband))` —
  vorher sprang es an der Talbandkante vom Damm aufs Gelaende (schwarze Zickzackwaende).
- KIESUFER (`_ufer_farbe`, in `_tri` nur unter Chunk-Spiegel + 2,5 m) und AUWALD (`_auwald`,
  Mindestdichte im Talband neben dem Kies).
- FLIESSENDES WASSER (`fliessend` in wasser_kern): das Band traegt Fliessrichtung (RG) und
  Gefaelle (B) als Vertexfarbe; Wellen laufen flussab, schneller wo steil, Schaumschlieren,
  Wildwasser an steilen Stellen. Das Band endet, wo der Spiegel das Meer erreicht.
- MUEHLBACH (Zufluss Stadtsee) jetzt auch `profil` (Handwerte lagen ueber/unter dem Gelaende).
- CPU (`_skriptzeit`, Stellung "Silberfluss" neu): 1,69 → 2,02 ms am Strom (Auwald-Baeume
  und Ufer), sonst unveraendert.
- WERKZEUGE `_see_abfluss`/`_see_pass` stuerzten ab (Signal 11, auch vor diesem Umbau):
  sie tauschen `lakes`/`rivers`, waehrend der Fernschuerzen-Faden liest → halten die
  Schuerze jetzt vorher an (`_fern_stopp` + wait_to_finish). Befund dabei: der Bergsee-
  Abfluss meldet "ZU HOCH" (Schwelle +208 m) — so auch im alten Stand, nicht angefasst.

## Nachladen: Schnellflug und weiches Erscheinen (2026-09)
Nutzer: „mit einem schnellen Flugzeug laedt die Map viel zu langsam — du bist zu schnell".
Gemessen mit `tools/_tempo_nachladen.gd` (IM FENSTER, Echtzeit; fliegt eine Gerade mit festem
Tempo und misst alle 0,5 s den Vorlauf von Chunks, Loechern im 2-km-Umkreis, Schuerze grob/
fein, Minimap-Kacheln und die Framezeit; `TEMPO_BILD=<s>` macht ein Bild, `TEMPO_STEHEN=1`
Vergleich im Stand, Profil der Hauptfaden-Abschnitte am Ende). Headless taugt dafuer NICHT.
- BEFUND alter Stand: schon bei 280 m/s nach 28 s KEIN Chunk mehr im 2-km-Umkreis (84 Loecher,
  darunter lag die um 480 m abgesenkte Schuerze = Loch), bei 450 m/s nach 13 s. Ursachen:
  (1) die Auftragsliste wurde nur hinten ergaenzt — die Worker bauten der Reihe nach Chunks,
  die laengst HINTER dem Flugzeug lagen (Haelfte verworfen); (2) ein Chunk kostete auf der
  Hauptinsel 135 ms statt der dokumentierten ~22 ms, und mehrere Faeden bremsten sich an
  GETEILTEN Woerterbuechern aus (sechs Faeden lieferten weniger als zwei); (3) Schuerze und
  Kartenkacheln belegten ALLE Pool-Faeden bzw. standen hinter der 2048er-Karte an.
- RUCKLER-FALLE (Nutzer: „ruckelt, nicht mehr smooth" nach dem ersten Umbau): das Neu-
  sortieren der Auftragsliste per `sort_custom` mit `_vorrang` im Vergleicher kostete bei
  ~370 Chunks bis 24 ms in EINEM Frame, bei jedem Zellwechsel (im Flug alle 1-3 s). Jetzt:
  Vorrang einmal je Chunk, mit dem Index in eine Ganzzahl gepackt, `PackedInt64Array.sort()`
  (nativ) — Spitze 1,6–4 ms; dasselbe in `Main._fern_ring`. Allgemein: GDScript-Vergleicher
  ueber Hunderte Elemente im Frame sind teuer. `_tempo_nachladen` meldet jetzt Spitzen je
  Abschnitt, Frames ueber 20/33 ms und ordnet langsame Frames Ereignissen zu (Zellwechsel,
  Chunk, Schuerze, Kachel). Vergleich 150 m/s: alter Stand 73 % der Frames ueber 20 ms
  (Warten auf den Renderfaden), neu ~5 % (120-Hz-Takt: 25-ms-Frames), keiner ueber 33 ms.
  Niedrige Fadenprioritaet fuer die Worker brachte messbar nichts.
- AUFTRAGSLISTE (`TerrainWorld.update_center`): bei jedem Zellwechsel NEU aufgestellt —
  nur Gewolltes, nicht Stehendes, nicht im Bau (`_in_arbeit`), nicht fertig wartend (`_done`),
  sortiert nach `_vorrang` (Abstand, voraus bis auf 40 % verkuerzt, `VORAUS_GEWICHT`,
  Flugrichtung `_flug_dir`). Zusatzfaden (`WORKER_ZUSATZ` = 1) nimmt nur ab `ZUSATZ_AB`
  wartenden Auftraegen mit. Mehr Faeden bringen nichts (gemessen: Durchsatz ~flach, Hauptfaden
  leidet).
- CHUNK 135 → 60 ms (`_haupt_pruefsumme` bitgleich): FLACHZONEN-RASTER (`zonen_gitter_bauen`,
  1-km-CSR; height_at/_open_ground liefen je Probe ueber alle 46 Zonen-Woerterbuecher, 6 von
  16 us), Kuestenanker gepackt (`_ka_p/_ka_fest` — `_kueste_versatz` erzeugte je Anker und
  Probe einen STRING), Seen-Vorfilter (`seen_vorfilter_bauen`), Hochtal-Achse ausgepackt
  (`_tal_st/_ri/_lg`). `airfields`, `lakes`, `tal`, `kuesten_anker` haben SETTER, die das neu
  bauen; wer an Ort und Stelle aendert, ruft `zonen_gitter_bauen()`/`seen_vorfilter_bauen()`.
  Messwerte je Chunk jetzt: Hoehe 26, Farben 14, Bewuchs 14, Grasmaske 4 ms.
- RUECKFALLEBENE: die Schuerze taucht nur ab, wo ein Chunk STEHT (`gelaende_kern`, `chunk_da`
  liest das Tiefenraster `_tiefe_tex`, TIEFE_LEER = kein Chunk; vier Proben ±6 m, damit ein
  Eckpunkt auf der Chunkgrenze nur bei beidseitig stehenden Chunks abtaucht). Fehlende Chunks
  zeigen also grobes Gelaende ohne Baeume statt eines Lochs (Bild bei 450 m/s: lueckenlos).
- SCHUERZE (Main): ab `FERN_SCHNELL_AB` (120 m/s) Pakete zu `FERN_PAKET_SCHNELL` (16) statt 90
  (ein 90er-Paket fuer die alte Stelle lief >25 s, solange wurde nichts Neues bestellt),
  voraus zuerst (`_fern_vorrang`), im Flug nur `FERN_POOL_FAEDEN` (3) mit Pool-VORRANG.
- KARTE: Minimap-Kacheln werden auch um den Punkt in 20 s bestellt und nach dem Punkt in 8 s
  sortiert (`WorldMap._process`, `_kacheln_planen(..., vorzug)`), mit Pool-Vorrang und 3
  Faeden; die feine 2048er-Uebersicht im Hintergrund nur mit 2 Faeden (`n_pool` in
  generate_image: nur die Startkarte nimmt alle).
- HAUPTFADEN: Bewuchs-Einhaengen kostete 9,4 ms und der Sparstufenwechsel 3,6 ms JE FRAME —
  beides Warten auf den Renderfaden (siehe Stolpersteine: Physik-Interpolation + MultiMesh).
  Jetzt: Welt-Wurzeln ohne Physik-Interpolation, und je Art ZWEI MultiMeshes (voll bis
  `_flora_grob_ab`, grob = Stellvertreternetz ab dort, `_flora_reichweiten`); umgeschaltet
  wird nur noch `visible` (je Chunk, siehe „Bewuchs unabhaengig von der Detailstufe") — nie
  das Netz an einer eingehaengten MultiMesh. Streaming auf dem Hauptfaden ~0,5 ms je Frame.
- ERGEBNIS 280 m/s (realistischer Schnellflug): Chunks ≥ 2,5 km voraus, zeitweise seitliche
  Luecken im 2-km-Umkreis von der Schuerze gedeckt, Minimap ≥ 5 km, feine Schuerze ≥ 4 km,
  Frame 16,5 ms (alter Stand 15,0 — aber dort kam ab 28 s gar nichts mehr an). 450 m/s: die
  Chunks fallen seitlich zurueck (CPU-Grenze), die Schuerze deckt alles.
- WEICHES ERSCHEINEN (Nutzer: „Optik und Feeling" beim Reinladen): ein GESTREAMTER Chunk
  waechst in `MORPH_S` (1,4 s) aus der Hoehe der Fernschuerze in seine Form, seine Pflanzen
  wachsen in `WACHSEN_S` (1,6 s, je Pflanze um bis 0,5 s versetzt) aus dem Boden. Vorher
  sprang das Gelaende um das in der Schuerze fehlende Felsrelief (bis ~20 m) und der Wald
  stand schlagartig da. Technik: UV2.x = Schuerzenhoehe je Eckpunkt (`_schuerzen_hoehen`:
  13 x 13 Proben height_at(..., 32) — das 32er-Raster laesst das Felsrelief weg, siehe
  DETAILMASS —, gleiche Diagonale 00-11 wie die Schuerze), `instance uniform erschienen` je
  Chunk-MeshInstance und je Flora-MultiMesh, globale Shader-Uhr `welt_zeit`
  (project.godot `[shader_globals]`, je Frame in `TerrainWorld._process` =
  `TerrainWorld.welt_zeit()`). Nur der Streaming-Weg (`_attach_chunk(..., weich = true)`,
  Flora-Eintrag "weich"); Startbereich/`build_now_around` stehen sofort. MORPH_S/WACHSEN_S
  stehen ZUSAETZLICH als Konstanten in `gelaende_kern` bzw. im Flora-Shader — gleich halten.
  Kosten: +1,7 ms je Chunk (Worker), Framezeit unveraendert (gemessen). Sichtprobe:
  `tools/_weich_bild.gd [x z]` (setzt das Alter je Bild selbst: 0,05 / 0,7 / 2,0 s).
- WEITERE VORFILTER (alle bitgleich, `_haupt_pruefsumme`): Kuestenformen abgeflacht
  (`_kf_pts` + Bereiche `_kf_*_ab`, Gesamtlaenge `_kf_*_ges` — `_kf_lage` summierte sie je
  Aufruf neu —, Reichweite `_kf_*_raus`/`_kf_g_bmax` VOR dem Woerterbuch; `_kf_flach` gibt ein
  Array zurueck, ein Vector3 haette die 64-Bit-Laenge auf 32 Bit gekuerzt), Massive gepackt
  (`_ms_r/_ms_typ/_ms_dehn/_ms_drall`, keine String-Erzeugung je Probe mehr), Felswaende
  (`_fw_*`, Setter), Seen in der Farbe (`_see_farb2`). height_at 13,2 → 12,1 us (Inselmittel),
  Chunk 59 → 56 ms (+1,7 fuer das weiche Erscheinen). Profil-Anteile (mit Messmarken):
  Gebirgsformen, Massive, Kuestenversatz, Wasserformen — der Rest sind die Rauschaufrufe selbst.
- CHUNK-DETAILSTUFEN (Nutzerwunsch): Chunks mit Mitte jenseits `FEIN_DIST` (1100 m) stehen
  GROB — `_make_chunk_data(key, AUFTRAG_GROB)`: 16-m-Raster (zn = 24, ein Viertel der Proben),
  abgetastet mit `height_at(..., 8.0)` — die groben Punkte sind damit BITGENAU jeder zweite
  feine. Keine Grasmaske (Ring an der Stelle geleert), Kollision gleich weit (16 m),
  Tiefenblock auf 48x48 hochgerechnet, KEIN Bewuchs (siehe unten). Grob 14,5 ms, fein 57 ms
  (mit Bewuchs-Vorlage 47). Auftraege sind Vector3i (x, z, Art | `AUFTRAG_MERKEN`): fehlende
  Chunks entstehen IMMER zuerst grob (Abdecken vor Verfeinern), im Schnellflug nicht hinten am
  Rand (`HINTEN_RAND`); Verfeinern (`AUFTRAG_FEIN_AUS_GROB`) mit Nachrang `FEIN_NACHRANG` und
  im Schnellflug (`FEIN_HINTEN_AB`) nicht hinter dem Flugzeug (`FEIN_HINTEN`). Der feine Chunk
  waechst aus der groben Flaeche (UV2 aus `_bewuchs_raster`). RANDSTREIFEN (`RAND_TIEF` 20 m)
  an jeder Chunkkante gegen Spalten fein/grob. `build_now_around` (Start, Werkzeuge) baut fein.
  INSTANZ-UNIFORMS belegen je Instanz einen Platz im globalen Shader-Puffer (Standard 65 536,
  ~4000 Instanzen); mit zwei Flora-MultiMeshes je Art und Chunk lief er ueber ("Too many
  instances using shader instance variables") → project.godot
  `rendering/limits/global_shader_variables/buffer_size=262144`.
- BEWUCHS UNABHAENGIG VON DER DETAILSTUFE (Nutzer: „die Baeume verschwinden die ganze Zeit,
  auch wenn sie unter mir sind, und diese Animation, wenn die Renderobjekte ausgetauscht
  werden, verwirrt"). Vorher setzte die grobe Stufe eigene 16-m-Zellen: beim Verfeinern
  schrumpften die alten Baeume weg (`VERGEHEN_S`) und ANDERE wuchsen woanders nach; dazu zeigte
  die Fernstufe nur 75 % der Pflanzen und blendete beim Naeherkommen ueber (`STUFE_S`). Alles
  entfernt. Jetzt:
  * EINE Entscheidungsflaeche: `_bewuchs_raster` rechnet aus dem 16-m-Raster ein 8-m-Raster
    (Dreiecksregel 00-11) — in beiden Stufen bitgleich. `_bewuchs_rechnen(key, hd, hp_src)`
    entscheidet ALLES darauf (Hoehe, Steilheit, Gewaesser, Dichte, Art — auch die
    Hoehenschwellen der Baumart), nur die Standhoehe kommt aus der eigenen Flaeche. Beleg:
    `tools/_bewuchs_stufen_check.gd` (16 Chunks: 0 Abweichungen in Art/Zahl/Lage/Drehung,
    Hoehendifferenz Median 6 cm, 99 % 1,05 m, max 4,5 m).
  * GROBE CHUNKS BEKOMMEN IHREN BEWUCHS ALS EIGENEN AUFTRAG (`AUFTRAG_BEWUCHS`, 10,9 ms,
    Nachrang `BEWUCHS_NACHRANG`): im Gelaendeauftrag machte die 8-m-Schleife grobe Chunks von
    14,5 auf 25 ms teuer, bei 450 m/s fehlten bis zu 14 Chunks im 2-km-Umkreis. Die Flaeche
    (`hd`) legt der Worker in `_grob_hd` ab; `_bewuchs_bestellen` stellt den Auftrag beim
    Einhaengen hinten an (sonst kaeme er erst beim naechsten Zellwechsel — im Stand nie),
    `_bewuchs_nachreichen` haengt ihn weich an. Meta `bewuchs_offen`.
  * VORLAGE: Bewuchs-Auftraege naeher als `FEIN_DIST + VORLAGE_RAND` legen ihr Ergebnis in
    `_bewuchs_vorlage`; der feine Bau uebernimmt es (`_bewuchs_umsetzen`, nur neue Standhoehe,
    Abweichung zum frisch gerechneten ≤ 1 mm) statt die Schleife neu zu rechnen.
  * TAUSCH OHNE ANIMATION (`_chunk_abloesen`): altes Gelaende und Kollision sofort weg, die alten
    Pflanzen BLEIBEN, die neuen haengen verdeckt ein (Meta `ersatz`, Zaehler `flora_offen`);
    sobald die letzte steht, werden sie sichtbar und der Vorgaenger im SELBEN Frame
    ausgeblendet (`_flora_eintrag_haengen`) — sonst stand der Wald einen Frame doppelt. Stand
    auf dem groben noch kein Bewuchs, wachsen die neuen normal aus dem Boden.
  * Fernstufe mit ALLEN Pflanzen (`FLORA_GROB_ANTEIL` 1.0), Wechsel voll/grob hart per
    `visible` im 3D-Abstand mit Totband `FLORA_HYSTERESE` (`_flora_stufe_setzen`) — die
    Formen sind in der Ferne ununterscheidbar, kein Ueberblenden mehr.
  * Vulkan-Vorpruefung je Chunk (`_vulkan_im_rechteck`, bitgleich): spart ~1,8 ms je Chunk.
  BELEG: `tools/_baum_ausfall_check.gd` (fliegt tief, zaehlt je Frame die sichtbaren
  Pflanzen je Chunk ueber alle Knoten dieses Chunks; jede Abnahme naeher als 1,5 km ist ein
  Ausfall): alter Stand 247 Ausfaelle in 30 s, jetzt 0 bei 30 Tauschvorgaengen.
  GEMESSEN (_tempo_nachladen, Fenster): 280 m/s 0 Loecher, 2,3 % Frames ueber 20 ms (vorher
  3,7 %); 450 m/s max 1 Loch in 2 von 78 Proben, 1,5 % ueber 20 ms (vorher ~25 %). Tiefflug
  140 m ueber Wald, 280 m/s: 28-31 % ueber 20 ms, alter Stand 30-31 % — dort ist die GPU die
  Grenze. `_haupt_pruefsumme` bitgleich. Die ~240 verworfenen Chunks im Werkzeug fallen alle
  in der Startphase an (vor dem Messflug), im Flug keine.
- OFFEN: Grasmaske nur bei Annaeherung — bewusst NICHT gemacht (feine Chunks sind nach den
  Detailstufen ein kleiner Teil der Arbeit, Ersparnis ~3 % der Worker-Zeit, dafuer eigener
  Auftragstyp und Raster im Speicher).

## Stadtstrassen (2026-10): echtes Strassennetz, Gehwege, Kreuzungen, Haeuser an der Strasse
Nutzerwunsch: „mach die strassen besser". BEFUND aus Nahbildern: die Ortsstrassen
(CityBuilder.strassennetz, Hafenstadt._pflaster) waren einfarbige Rechtecke auf dem Gelaende —
an jeder Kreuzung zwei Baender uebereinander, der Ring der Grossstadt klaffte an jedem Knick
als Saegezahn, kein Gehweg, keine Linie; die Diagonalen liefen mitten durch Haeuser, und im
Landdorf standen die (zufaellig gestreuten) Haeuser AUF den Strassen. Die Landstrassen
(Strassen.gd) liefen als markiertes Band quer durch das Ortsnetz bis in die Ortsmitte.
- `scripts/Stadtstrassen.gd` (statisch) + `shaders/stadtstrasse.gdshader`:
  * NETZ: `strecke`/`zug` sammeln Rohstrecken, `schliessen(netz, sperr)` zerlegt sie an allen
    Schnitt- und Beruehrpunkten in Knoten und Kanten (O(n²), ~150 Strecken) und laesst
    Kanten unter grossen Bauten weg (`sperr`: OBBs, z. B. der Bahnhof ueber zwei Bloecke).
  * KNOTEN, fuer JEDEN Winkel: Arme nach Winkel ordnen; jeder Arm wird um
    (w_j/2 + w_i/2·cos φ)/sin φ zurueckgeschnitten (dort treffen sich die Aussenkanten der
    Nachbarbaender), die Luecke fuellt ein Asphalt-Faecher um den Knoten und je Armpaar eine
    Gehwegecke (vier Dreiecke: Bordsteinpunkte, Aussenpunkte, deren Schnittpunkte). Dasselbe
    Verfahren macht Kreuzung, Einmuendung, Knick (Gehrung am Ring) und Breitenwechsel
    (`UEBERGANG`). Nie mehr als 48 % der Kante (spitze Winkel).
  * BAND je Kante: drei Punkte quer (links, Achse, rechts), alle 24 m dem Gelaende
    nachgefuehrt, `HUB` 0,35 m. UV.x = Abstand von der Achse in METERN, UV.y = Laufmeter,
    UV2 = Abstand zur Einmuendung an Anfang/Ende, CUSTOM0 = (halbe Fahrbahn, Gehweg, Art,
    Markierung). Der Shader malt daraus Fahrbahn, Rinnstein, Bordstein, Gehweg, Mittel-/
    Spurlinien, Haltelinie und ZEBRASTREIFEN vor jeder Einmuendung (Grad >= 3); Linien
    blenden ueber fwidth aus, der Zebrastreifen wird in der Ferne zur halbhellen Flaeche.
    Arten: GASSE (Pflaster 5 m), STRASSE (6,5 m + 2×2,25 m Gehweg), BOULEVARD (12 m, vier
    Spuren, 2×3 m), WEG (Schotter), DORF (heller Asphalt 5,5 m), LAND (wie das
    Landstrassenband; `strasse.gdshader` hat jetzt denselben Asphaltton).
  * `bebauen(netz, rng, waehle, belegt, arten, abstand, luecke)`: Haeuser entlang der
    Kanten, Front (+z des Modells) zur Strasse, `abstand` hinter dem Gehweg; verworfen, was
    ein anderes Band oder Haus schneidet (OBB gegen OBB, `obb_schnitt`). `waehle(probe, rng)`
    liefert den Typ je Stelle ("" = Luecke) — darueber laufen Dichte und Viertel.
- `CityBuilder.netz_ort(r_kern, r_ring, r_aus, sperr, zufahrt)`: STADT = Raster 46 m bis an
  die Ringstrasse (Linien, deren Stummel zum Ring kuerzer als ein halber Block waere, enden
  an der letzten Kreuzung), zwei BOULEVARDS als Achsenkreuz (laufen als Landstrasse, zuletzt
  als Feldweg hinaus), acht Vorstadtstrassen; die Diagonalen sind weg. DORF = Strassenkreuz
  um den Anger, Dorfstrasse als Ring, vier Feldwege. `plan_grossstadt`/`plan_dorf` bauen
  ihre Haeuser mit `bebauen` an GENAU dieses Netz (Zwischenspeicher `_netz_cache`, geleert
  in `karte_leeren`); feste Bauten stehen in Blockmitte (`GROSSSTADT_FEST`, `DORF_FEST`).
  Grossstadt: 811 Bauten (vorher rund 250 lose), Landdorf 61.
- ZUFAHRTEN: `CityBuilder.zufahrten(terrain, mitte, r)` findet, wo Landstrassen den Kreis
  um den Ort kreuzen; das Netz schliesst sie an (an das naechste Strassenende, wenn es
  innerhalb 110 m und in Richtung liegt — sonst liefe die Landstrasse 30 m neben einer
  eigenen Ausfallstrasse her —, sonst ueber einen eigenen Ringpunkt mit >= 36 m Abstand zu
  den anderen). `Strassen.stadt_kreise` (von Main gesetzt, gleiche Radien 360/180) blendet
  das Landstrassenband innerhalb aus.
- HAFENSTADT: `Hafenstadt.netz()` aus `strassen()` + Kaistrasse + Landstrasse nach Westen;
  Breiten jetzt 11 / 18 / 5 m (= `Stadtstrassen.breite`), Haeuser 1 m hinter dem Gehweg,
  Plaetze (Markt, Kaipflaster westlich der Kaistrasse, Bahnhofsplatz) liegen als Platten
  UNTER der Strassenhoehe, die Strassen laufen darueber.
- GEMESSEN (`tools/_hafen_zeit.gd`, 4K; `HZ_ORT=grossstadt`): Grossstadt samt Netz 0,58 ms
  im Kern, 1,13 ms aus 150 m, 0,14 ms im Anflug, 0,65 ms aus 3 km. Hafenstadt unveraendert
  (hoechstens 1,46 ms).
- BELEG: `tools/_stadtstrassen_check.gd` (headless, Urteilszeile): je Ort kein Haus auf
  einer Strasse und keine zwei ineinander (gegen die echten Netzgrundrisse), und 500
  Stichpunkte um die Knoten: nirgends zwei Dreiecke uebereinander, im Kern jedes Knotens
  kein Loch. `_hafenstadt_check` weiter OK.
- FALLEN: (1) Die Lochpruefung meldete zuerst 4 "Loecher": Punkte genau auf einer Speiche
  des Faechers liegen in KEINEM Dreieck strikt innen — fuer Loecher nicht-strikt zaehlen.
  (2) `parent.add_child` vergibt einem zweiten Knoten gleichen Namens einen @-Namen; die
  Netze heissen deshalb `Strassen_<x>_<z>`. (3) Kreuzungsflaechen brauchen UV.x WEIT weg
  von Achse und Rand (500 bei halber Breite 1000), sonst malt der Shader die Gassenrinne
  bzw. den Rinnstein ueber die ganze Flaeche. (4) Ein Turm mit yaw 0,35 ragte aus seinem
  Block in den Boulevard — feste Bauten in Blockmitte, ungedreht.
- OFFEN: `CityBuilder._band` ist unbenutzt (die Kommentare in Strassen.gd/Skyline.gd
  verweisen auf seine Wicklungs-Lektion). Die 20 Strassendoerfer (Strassen._dorf) haben
  weiter ihr Schotterband.

## Hafenstadt FREIHAFEN mit Freiheitsstatue (2026-10)
Nutzerwunsch: „baue eine hafenstadt mit freiheitstatue". Alles in `scripts/Hafenstadt.gd`
(statisch, feste RNG-Seeds), eingehaengt in Main an vier Stellen: `flat_zones`
(`flachzonen()`), `kuestenformen` (`wasserformen()`), `_setup_world` (`bauen()` nach
Skyline), Kartenpunkte (`pois()`).
- LAGE: Westufer des Ostgolfs, `MITTE` (14300, 9900) — gerade Kueste, flaches Land, tiefes
  Wasser; der Silberfluss laeuft 900 m suedwestlich vorbei (Zone bleibt mit r_blend 800
  davon frei). Ausgesucht mit `tools/_hafen_platz.gd -- x0 z0 x1 z1 schritt` (Hoehenraster
  als Zeichenbild: `~` tief, `-` flach, `.` Land bis 6 m, `F` Fluss).
- KAIKANTE (neu in TerrainWorld.height_at): Flachzonen kennen den Schluessel
  `"kai": Vector3(nx, nz, abstand)` — die Zone gilt nur diesseits einer Geraden, jenseits
  faellt das Gelaende ueber `KAI_RAMPE` (10 m) auf den gewachsenen Grund. Eine Kreiszone
  allein gibt einen runden Strand; ein Hafen braucht eine gerade Kante. Die Kaimauer aus
  Hafenstadt._kai steht `KAI_VOR` (12 m) davor und verdeckt die Boeschung (auch im
  16-m-Raster der groben Chunks). Flachzonen laufen NACH den Wasserformen — eine Zone mit
  y ueber dem Meer im Wasser ist deshalb eine INSEL (Statueninsel, y −2,5).
- HAFENBECKEN als eigene Wasserform (`nur_senken`, ohne `breit_rausch`): der Rand des
  Ostgolfs haengt am Welt-Seed, das Becken vor dem Kai nicht.
- STADTPLAN (`plan()`): Strassenraster 120 m (`NS`/`OW`) plus GASSEN, die in Altstadt,
  Speicherstadt und Fischerviertel die Bloecke halbieren (erste Fassung ohne Gassen: je
  Block eine duenne Zeile um einen leeren Hof = Vorort-Raster). Blockrand entlang JEDES
  Strassenstuecks, Front zur Strasse, Typen je Viertel (`VIERTEL`: alt / speicher / fisch /
  wohn), Dichte faellt landeinwaerts; von Hand gesetzt: Rathaus, Kirche, Hotel, Kaufhaus,
  Bahnhof, Krankenhaus, Kraene, Silo, Tanks, Fabrik, Lotsenhaeuser; Villen und Hoefe am
  Hang. 1124 Bauten. `strassen()` ist die EINE Liste fuer Plan, Pflaster, Baeume und
  Pruefung.
- KAI/PIERS/MOLEN/SCHIFFE: je EIN SurfaceTool-Netz mit `shaders/haus.gdshader` (Farbe je
  Eckpunkt, vorher per `srgb_to_linear` gewandelt — der Shader multipliziert die Vertexfarbe
  roh), Flaechen ueber `_viereck(..., aussen)` gewickelt (nie von Hand). Kastenkollision auf
  Kai, Piers, Molen, Containern (man kann landen). Schiffe ohne Kollision.
- BAEUME: eigene MultiMeshes mit `terrain._flora`-Netzen und `_flora_mat` (die Flachzone
  haelt den Bewuchs des Gelaendes frei): Allee an Kai und Hauptstrasse, Stadtpark, Hoefe
  (900 Zufallspunkte, verworfen auf Haus, Strasse, Platz).
- FREIHEITSSTATUE: `Haus_Freiheitsstatue` in `tools/build_haeuser_blend.py` (64. Typ, LOD
  691 / HD 2479 Dreiecke): Sternfort mit 11 Bastionen, Unterbau, Sockel mit Loggia, Figur
  aus `schlauch` (Gewand, Kopf), `rohr` (Arme, Ueberwurf), `strahl` (Krone) — neue Bausteine
  `stumpf`, `stern`, `schlauch`, `rohr`, `strahl`. Palette `dach_patina` (Schluessel mit
  "dach" → Verlauf Fuss–Kopf) und `gold`. Im Spiel `STATUE_MASS` 1,6 (150 m; in
  Originalgroesse war sie vom Kai aus eine kleine Figur), Fernstufe bis `STATUE_SICHT` 9 km,
  eigene Kollision (`_statue_kollision`). Insel mit gepflastertem Uferweg auf einer
  Ringmauer — ohne sie stand die Boeschung der Flachzone als Saegezahn aus Strandfarbe im
  Wasser.
- GEMESSEN (`tools/_hafen_zeit.gd`, 4K, mit/ohne Knoten "Hafenstadt"): Kai 40 m 0,42 ms,
  ueber der Stadt 150 m 1,46 ms, Anflug 400 m 0,22 ms, 3 km entfernt 0,65 ms.
- BELEG: `tools/_hafenstadt_check.gd` (headless, Urteilszeile): Stadtflaeche eben, Becken
  tief, Insel, Bauplan gegen die ECHTEN Netzgrundrisse (0 Ueberschneidungen, 0 Haeuser auf
  Strassen), Kollision per Strahl (Kai, Pier, Mole, Uferweg, Statuenkopf, Fackelarm).
  Bilder: `_luftbild.gd -- hafen_blick 14180 120 9980 15340 60 9960` (Stadt → Statue),
  `hafen_statue 15540 70 10160 15340 100 9960`, `hafen_oben 14350 950 10950 14400 0 9900`.
- FALLEN: (1) Laeuft das Spiel im Vollbild, sind alle Fenster-Werkzeuge SCHWARZ (verdeckt)
  — vor Bildwerkzeugen das Spiel beenden. (2) `for seite in [-1, 1]` gibt eine
  Variant-Schleifenvariable; jede `:=`-Ableitung daraus bricht den Compile von Main mit —
  `for seite: int in ...`. (3) Direkt nach `--import` kam einmal ein Schwall Fehler aus
  CloudField (leere Netze); beim zweiten Lauf weg — nicht vom Hafen.
- ANSCHLUSS ANS LANDSTRASSENNETZ (Nutzerwunsch): zwei Ortsausgaenge (`AUSGANG_WEST`,
  `AUSGANG_NORD`, im Stadtnetz als Landstrassen-Stummel), ab dort Landstrassen aus
  `scripts/StrassenZusatz.gd` — ERZEUGT mit `tools/_dorf_planer.gd -- anschluss` (~10 s).
  Der Modus laesst `StrassenDaten` UNVERAENDERT (ein voller Neulauf wuerfelt alle Doerfer und
  Strassen neu): er tastet nur einen Ausschnitt ab (`fenster`), traegt das alte Netz in die
  Strassenmaske ein, sperrt die Stadtflaeche und sucht mit demselben A* samt Buendelung von
  `Hafenstadt.anschluesse()` aus; was ueber alte Strasse laeuft, entfaellt, das Ende wird
  AUF die alte Fahrbahn gezogen (lag sonst nur in deren Rasterzelle, gemessen 34 m daneben).
  Ergebnis: West 10,6 km mit 120-m-Bruecke ueber den Silberfluss bei (10811, 8158), Einmuendung
  bei (4441, 5245) in die Strasse GROSSSTADT–Hasenwinkel; Nord 5,4 km — das Ziel war
  Fuchsried, die Buendelung fuehrt aber ueber die Nebenstrasse bei Rosenthal (18180, 6433),
  dort trifft Asphalt auf Schotterweg. `Strassen.strassen_daten()` haengt die Zusatzstrassen
  an; Hanghaeuser auf der Trasse filtert `Hafenstadt.bauen` (strasse_abstand < 20 m).
  Beleg in `_hafenstadt_check` (Start am Stadtnetz, Ende auf dem alten Netz, kein Haus auf
  der Landstrasse); `_strassen_check`: 33 Strassen, 294 km, 6 Bruecken, max. 8 %.
  NACH AENDERUNGEN AN DER STADTLAGE ODER DEN AUSGAENGEN den Modus neu laufen lassen.
- `_haupt_pruefsumme` aendert sich im Umkreis der Stadt (neue Zonen, Wasserform) und
  entlang der Anschlussstrassen.

## Doerfer und Landstrassen (2026-09)
Wunsch des Nutzers: mehr Doerfer auf der Hauptinsel, mit Strassen verbunden. 20 neue
Doerfer, 31 Strassenstuecke (~278 km), 5 Bruecken; Anschluss an alle Orte (ausser NEONBUCHT
und Bergdorf) und alle Flugplaetze der Hauptinsel (ausser ADLERHORST).
- (Dazu `scripts/StrassenZusatz.gd`: Anschlussstrassen der Hafenstadt, Planer-Modus
  `-- anschluss`, siehe Abschnitt Hafenstadt.)
- DATEN `scripts/StrassenDaten.gd` sind ERZEUGT von `tools/_dorf_planer.gd` — nicht von Hand
  aendern, neu erzeugen: `HOME=<test-home> Godot --headless --path . --script
  res://tools/_dorf_planer.gd` (~4 min, deterministisch). Der Planer haelt Schuerzen- und
  Kartenfaden an, BEVOR er Gelaendelisten veraendert (sonst Signal 11 im Kartenfaden), schaltet
  die eigenen Strassen ab und nimmt die eigenen Dorfzonen aus `airfields` (sonst plant er auf
  dem vorigen Stand und setzt 20 neue Doerfer daneben).
- PLANER: 100-m-Raster; Sperren (Meer, andere Regionen, Vulkan, Neonbucht, Bahnen, Seen,
  Plateau), Flusstal = Brueckenzone (queren teuer, laengs fahren teurer), RAUHEIT = steilste
  25-m-Steigung (auf 100 m sah eine Felsstufe harmlos aus → 282 m Einschnitt ins Hochtal).
  Doerfer nach Abdeckung gewaehlt (Abstand ≥ 3,6 km untereinander, ≥ 2,8 km zu Orten), nicht
  im Hochtal. Netz = Spannbaum + Abkuerzungen (< 62 % des Baumwegs), A* mit
  Laenge·(1+(Steigung/4,5 %)²), Buendelung ×0,33 auf gebauter Strasse. Danach DP 30 m + 2×
  Chaikin, FLUSSQUERUNGEN BEGRADIGEN (`_querungen_begradigen`: Querungen unter 65 Grad werden
  durch Rampe unter 90/70/55 Grad + Hermite-Anschluss ersetzt, jede Variante mit dem ECHTEN
  Profil `TerrainWorld.strasse_profil` bewertet — stur rechtwinklig trieb das S der
  Anschlusskurven 36 m tief in den Uferhang), dann noch 1× Chaikin.
- LAUFZEIT (TerrainWorld): `strassen` (vor setup) → `strassen_fertigstellen()` (Main, direkt
  nach `fluesse_fertigstellen`, vor `build_now_around` und Kartenfaden): 20-m-Abtastung
  (`strasse_abtasten`), Profil (`strasse_profil`: ±100 m geglaettet, max 8 % nach echtem
  Abstand, ueber Fluss/Meer Mindesthoehe +4,5 m, nur-nach-oben-Durchgaenge fuer Rampen;
  Bruecke wo ueber Wasser >2 m ueber Grund oder >10 m Damm = Viadukt) und CSR-Raster
  (`_st_*`, 100-m-Zellen). `height_at` ruft am Ende `_strasse_carve`: Kern (halbe Breite +
  STRASSE_RAND 12 m) exakt auf Fahrbahnhoehe − 3 cm, Boeschung 1:1,7 bis 48 m. KERN ≥ 8·√2 m:
  jedes Dreieck des 8-m-Netzes, das das Band beruehrt, hat dann ALLE Ecken auf Fahrbahnhoehe
  (mit 7 m ragte das Netz in Kurven/Haengen ueber das Band). Bruecken lassen das Gelaende
  unberuehrt. Baeume/Gras halten ueber `strasse_abstand` Abstand.
- SICHTBAR (`scripts/Strassen.gd`): Band je 50 Abschnitte (1 km) als MeshInstance3D, Shader
  `shaders/strasse.gdshader` (Asphalt mit Rand-/Mittellinien, Schotterweg mit Spuren; Linien
  per fwidth ausgeblendet), Bruecken mit Platte, Gelaender, Pfeilern und Kastenkollision (man
  kann landen), Doerfer als Strassendorf (`plan_strassendorf`, Achse `dreh` laengs der
  Strasse, Haeuser mit `frei`-Abstand zur Fahrbahn) ueber CityBuilder. Karte: WorldMap
  zeichnet `terrain.strassen` (Landstrasse mit Saum, Nebenstrasse heller), Doerfer als Orte.
- FALLEN (alle hier reingelaufen): (1) PACKED-ARRAYS SIND WERTTYPEN:
  `(listen[k] as PackedInt32Array).append(si)` haengt an eine KOPIE — das Raster war leer, es
  gab keinen Einschnitt, und die Baumpruefung ueber `strasse_abstand` meldete wegen INF
  "0 Baeume auf der Fahrbahn". Raster jetzt zweistufig (zaehlen, fuellen); `_strassen_check`
  prueft Rasterfunde, Gelaende ueber dem Band und Baeume per Brute Force. Die fehlenden
  Baender auf den ersten Bildern kamen NUR daher (Gelaende lag ueber dem Band) — die
  Vermutung „visibility_range misst ab dem Knoten" war falsch (nachgemessen). (3) Strassen parallel zum Fluss
  querten unter 19 Grad = 237 m Bruecke LAENGS am Ufer. (4) Schmale Meeresarme sieht das
  100-m-Raster nicht: Fahrbahn lag unter dem Meeresspiegel → `strasse_profil` behandelt
  Gelaende < SEA_Y+0,5 wie Wasser. (5) `Strassen.dorf_hoehen` erst NACH den Kuestenformen
  (direkt vor fluesse_fertigstellen), sonst lagen Doerfer auf 4 m.
- WERKZEUGE: `_strassen_check` (Laenge, Steigung, Bruecken, Zonen, Haeuser je Dorf,
  Raster/Band, height_at-Kosten, Baeume), `_strassen_einschnitte` (alle Einschnitte/Daemme
  > 8 m). Bilder: `_luftbild.gd` mit `LUFT_REL=1` (z. B. Lindenau −650 120 17350 → −950 0 17050,
  Bruecke −5560 70 2380 → −5760 0 2225, Draufsicht −5700 900 2250 → −5700 0 2245).
- KOSTEN: height_at nahe Strassen +7 us (~26 → ~34 us), sonst ein Rechteck-Test.
  `_skriptzeit` alt → neu: Startbahn 1,90 → 2,25 ms, Flakzone 2,13 → 2,32, Silberfluss
  1,99 → 1,72, uebrige ±0,3 ms (Rauschen der Messung); +~700 Knoten (Baender, Doerfer).
- DORFSTRASSE (`_dorfstrasse`): Schotterband laengs der Dorfachse, wo keine Landstrasse
  liegt — die Netzstrassen ENDEN meist in der Dorfmitte, die Haeuser der Gegenseite standen
  sonst an keiner Strasse. 3 cm unter dem Landstrassenband.
  `_haupt_pruefsumme` aendert sich (Einschnitte veraendern Hoehe/Farbe entlang der Strassen).

## Himmel und Wolkenformationen (2026-09)
- HIMMEL (`shaders/sky_clouds.gdshader`): Zenit/Mitte dunkeln mit der KAMERAHOEHE
  (`POSITION.y`, `hoehe_bereich` 900–7000 m, `col_*_hoch`), Dunstsaum schmaler; warmes
  Mie-Leuchten am Horizont auf der Sonnenseite (`sonnenseite`); ZIRREN (`zirren_schicht`:
  billige Feldermaske, nur dort Fasern, gestreckt in Windrichtung) mit 22-Grad-Halo wo
  Zirren stehen. Alles NUR ueber dem Horizont, col_horizon unberuehrt (Kalibrierung!).
  Kosten Zirren 4K: 0,3–0,65 ms. FALLE: AT_HALF_RES_PASS/HALF_RES_COLOR in Godot 4.6
  ausprobiert — der ganze Himmel wurde weiss. Und `return` ist in sky() verboten.
- FORMATIONEN (`CloudField.formation`, Main `_wolken_formationen`): feste Orte statt
  wanderndem Wetter, MultiMesh je Form/Variante/1,6-km-Kachel, eigene Ellipsoidliste fuer
  `dichte_bei` (Zweig `_dichte_formation`, jeder Puff in allen beruehrten Zellen). Die
  Dichteabfragen in Main laufen ueber `_wolken_alle` (Decken + Formationen) → Nebel,
  Turbulenz, Flak-Deckung, Sonnenverdeckung ohne Extracode. `mitfuehren` laesst sie stehen
  (kein "puffs"-Meta). SPERRZONEN (`CloudField.sperrzonen`, `_wolken_sperrzonen`): die
  wandernden Decken setzen dort keine Puffs (6,5 km um die Gewitterzelle).
  WOLKENTORE und WOLKENSCHLUCHT sind auf Wunsch des Nutzers WIEDER ENTFERNT ("bs") —
  nicht erneut einbauen.
  * GEWITTERZELLE (`gewitter_puffs`, 31,5 km O): Turm bis 5,2 km, Amboss 6 km nach Lee,
    VERDUNKLUNG NACH WELTHOEHE (`dunkel_unten`/`dunkel_hoehe` — COLOR.r faerbt nur je Puff),
    Randemission dort gedaempft, EIGENER NEBEL (`_cloud_material(true)` → fog_disabled,
    Dunstfarbe `TerrainWorld.dunst_farbe`, unter dem Bauch abgedunkelt — Godots Nebel wusch
    die Basis sonst hellgrau; per Rotprobe belegt), Blitze (OmniLight + `blitz`-Emission +
    Zickzackbahn), Regenvorhang, Turbulenz ×3,5 (`FlightController.turbulenz_faktor`),
    Aufwind im Kern / Fallwind unter der Basis (`aufwind` in g).
  * NEBELMEER (`nebelmeer_puffs`, Westbucht, 330 m): flache Kumulus-Kissen, dicht
    ueberlappend (duenne Linsen waren Eisschollen), einzelne Kuppen.
- WOLKENFETZEN (`_fetzen`, GPUParticles3D an der Kamera, world-space): Menge aus der Dichte
  ~140 m VORAUS (`amount_ratio`), in der Wolke naeher und grauer (sonst frisst der Nebel sie).
- Kosten 4K (`_gefuehl_zeit.gd`): Formationen 0–1,1 ms (Gewitter aus der Naehe).
- Bildwerkzeug: `_gefuehl_bilder.gd` Szenen gewitter, gewitter_nah, im_sturm, blitz
  (erzwingt Blitz ueber `Main.blitz_test`), nebelmeer, fetzen, hoch.

## Die Welt jenseits der Hauptinsel (Landmassen, Regionen, Biome)
Die Welt misst 168 km (WorldMap.WORLD_R = Main.FERN_WELT = 84 km). Regionen-Eingriffe duerfen
die Hauptinsel nicht veraendern — `tools/_haupt_pruefsumme.gd` belegt es (Hoehe, Farbe, Wald,
Biom ueber ±34 km bitgleich; Stand seit dem Hauptinsel-Neubau oben); VORHER/NACHHER pruefen.
- `Main.LANDMASSEN` → `TerrainWorld.landmassen` (vor setup()): Mitte, r, `rauh`, `region`,
  `teile` (Lappen), optional `ruhe` (Punkte: Gebirge/Karst/Canyon/Seen setzen aus), `karst`,
  `seen`. Kueste = Isolinie m = max_Lappen(1 − d²/r²) + rauh·fbm (Domain-Warp), NICHT ein
  Radius. Alles laeuft erst ab `_lm_ab` (je LAPPEN gerechnet — je Landmasse reichte der
  Umkreis des Nordlands in die Hauptinsel und faerbte deren Nordkueste). `region_at`,
  `landmasse_bei`, `klima_gewicht` (Wasserfarbe folgt dem Klima, `_wasser_klima`).
- Regionen: NORD (Tundra/Taiga, Gletscherkette mit Paessen, Eisfjord, Seenplatte, Kies),
  SUED (Dschungel/Tropenwiese, Kegelkarst `_karst_turm` = ein Turm je verwuerfelter
  380-m-Zelle, Mangroven `_mangrove`, Korallensand), WEST (Tafelland: Plateau-Maske
  `_west_tafel` mit Schichtstufe, Zeugenberge `_zeugenberg`, maeandernder Canyon, Savanne).
  Gelaende `_region_form`, Farben `_region_farbe` (_farbe_nord/_sued/_west), Wald
  `_region_dichte` (EINE Regel fuer Boden, Karte, Schuerze und Baeume), Arten `_region_flora`,
  Baumgrenze `_region_baumgrenze`. Biome-Enum um TUNDRA/TAIGA/DSCHUNGEL/GRASLAND/SAVANNE/CANYON
  erweitert. Dichte Waelder: weniger, groessere Baeume (gemessen: sonst 3,3× Dreiecke/Chunk).
- Feste Wahrzeichen als Kuestenformen (`Main._region_formen`, seed-unabhaengig, auf der Karte
  benannt). Neue Schluessel: `fuss` (Landform laeuft auf diese Hoehe statt 0 aus — sonst ein
  Landring um jede Form im Meer) und `nur_senken` (Wasserform hebt nie an).
- Plaetze EISHAFEN/PALMENBUCHT/TAFELBERG (`"region": true`) und Orte `REGION_ORTE`: Hoehe
  erst nach setup() aus dem Ring-Median (`_region_hoehen`); die Schluessel stehen vorher
  (Chunk-Worker liest schon). Trittstein-Inseln in den Meeresstrassen.
- 13 Baumarten + Fels (`tools/build_baeume.py`, Blender 5.2 `--background`), neu: Schneetanne,
  Urwaldbaum, Baumfarn, Akazie, Mangrove, Kaktus. Fern-Stellvertreter: runde Kronen
  als Kuppel statt Kegel (siehe „BAEUME, DRITTE FASSUNG“); Schnee zaehlt in der Kronenfarbe nur 0,4.
- FERNSCHUERZE STREAMT (Main._fern_pruefen, 1×/s, auch im Hangar): grob bis FERN_GROB_R,
  fein bis FERN_FEIN_R um den Spieler, Pakete à FERN_PAKET, naechste zuerst. FERN_KACHEL
  2176 (ganzes Vielfaches beider Zellweiten — mit 2200 klaffte ein 24-m-Spalt).
- BEHOBEN (betraf auch die Hauptinsel): die Flora-Fernstufe zeigt ein Praefix der Instanzen
  (FLORA_GROB_ANTEIL); die Liste war zeilenweise geordnet → Streifen im Wald. Jetzt je Chunk
  deterministisch gemischt (_make_chunk_data).
- Werkzeuge: `_welt_uebersicht.gd -- px [x z halb]` (Kartenbild eines Ausschnitts),
  `_luftbild.gd -- name px py pz zx zy zz ...` (echtes Spielbild, wartet auf Schuerze,
  Chunks und Baeume; LUFT_OHNE_FERN/…SCHATTEN/…STELLV zum Eingrenzen), `_skriptzeit` misst
  jetzt auch Nord-Taiga, Sued-Dschungel, West-Tafelland.

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
  Assist an = mehr Nick/Gier-Dämpfung, aus = roh/direkt. KEIN Auto-Ausnivellieren der
  Querlage mehr (auf Wunsch entfernt): mit A/D gesetzte Bank bleibt stehen.
  Eingabe wird im FlightController weich gerampt (`_ramp`, analoges Gefühl).
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
(Assist ×1.6 nur Nick/Gier; kein Querlage-Auto-Leveling mehr), `qfac=clamp(q/180,0.04,2.0)`,
Landung: `HARD_LAND=3`/`BREAK_LAND=7` m/s. Reifenreibung `friction=0.05`.
`PartCatalog.WING_STRESS=3600` N/m² (Flügel-Belastbarkeit).
Spawn: Startbahn `(0, spawn_height, 40)`, `spawn_height = 0.3 − tiefster Punkt`.

### Fahrwerk: BLOB-Einfahranimation (fuer JEDEN einziehbaren Reifen)
Zusaetzlich zur jeweiligen Mechanik (gebackene glb-Animation „retract", klappendes Bein oder
Fallback-Klappe) legt `_process` einen **Blob** auf das Reifen-VISUAL: ab `_gear_anim` 0.52
quillt der Reifen kurz auf (`bulge = sin(PI*k)`, +45 % in der Breite), quetscht flach und
verschwindet bei 1.0 ganz (Skalierung 0, `visible=false`); beim Ausfahren laeuft das
rueckwaerts, unter a<0.10 mit elastischem Nachfedern. Damit haben auch `wheel_retract` und
`wheel_jet` eine Animation, obwohl ihre glbs KEINE tragen (nur biplane_spoke/disc und
spitfire haben eine gebackene). Gemessen mit `tools/_blob_check.gd`:
1.00 -> 1.02/0.96 -> 0.30/0.29 -> 0.00 + unsichtbar.
FALLEN: (1) Der Blob wird IMMER aus `g["base"]` (Ruhelage) gerechnet, nie aus der aktuellen
Transform — sonst multipliziert sich die Skalierung jeden Frame auf; und nie
`orthonormalized()`, das wuerfe die Teil-Skalierung (`pscale`) des Spielers weg.
`Basis.scaled()` haengt die Faktoren rechts an, dadurch behalten gespiegelte Teile ihre
improper Basis (det<0). (2) Der fruehere Early-Out `if absf(_gear_anim - target) > 0.001`
liess den LETZTEN Schritt ausfallen — der Reifen hing bei ~30 % Groesse sichtbar fest statt
zu verschwinden. Deshalb laeuft der Block jetzt jeden Frame.

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
- **Zerschellen** (`_explode`): jedes Teil wird ein eigener Trümmer-RigidBody. FALLE: der
  Trümmer-Körper bekommt die (orthonormierte) Drehung des FLUGZEUGS, nicht die Transform des
  Visuals — die trägt pscale, Spiegelung (det<0) und bei eingefahrenem Fahrwerk Skalierung 0
  (Blob). Ein RigidBody damit ist singulär („det == 0"), und die Physik orthonormiert ihn
  ohnehin, wodurch gespiegelte Trümmer umklappten. Die Form bleibt lokal am Visual.
  Beleg: `tools/_schaden_check.gd` (Flügelbruch, Flak-Volltreffer, Absturz mit eingefahrenem
  Fahrwerk, jeweils Reset).
- **Reset (Enter)** ruft `build_from_design(design)` neu auf → repariert alles.

### Bombenschacht (`bombbay`, Taste H)
Rumpfsegment (`shape "bay_tube"`, `biends`) mit echtem Loch im Bauch, Laderaum mit
Innenwänden und zwei Klappen-Drehknoten (Meta `bay_door` = Drehrichtung ±1). Kollisionsbox
nur obere Hälfte (`col_size`/`col_offset`), damit der Bau-Strahl IN den Schacht trifft und
man Bomben hineinsetzen kann. Im Hangar stehen die Klappen offen (`set_bay_open`), im Flug
sammelt `recompute_aero` sie über das Meta (`_sammle_klappen`) und stellt sie zu. `H` fährt
sie in ~0,6 s (`_bay_anim`); offene Klappen = +1,1 m² Widerstand je Schacht. Bomben, deren
Aufhängepunkt im Lichtraum liegt (`PartCatalog.bay_hold`, in Schacht-Koordinaten geprüft),
bekommen `w["schacht"]=true` und fallen nur bei `bay_frei()` (>85 % offen) — sonst HUD-
Hinweis „ZU — H DRUECKEN". Vorlage „Nachtfalke". Belege: `_schacht_test`, `_schacht_system`,
`_falke_check`, `_falke_flug`.

### Flügel-Orientierung bestimmt Funktion
Beim Bauen via `R` kippbar. In `FlightController.build_from_design` wird pro Flügel
`up_align = |basis.y·UP|` berechnet: waagerechter Anteil → **Auftrieb** (`wing_area`),
gekippter/senkrechter Anteil → **Rollsteuerung** (`roll_area`). Senkrecht = Winglet/
Querruder, kein Auftrieb.

### FLÜGEL-ANHAFTUNG (`_fluegel_snap`, ersetzt `_wing_level_orient`/`_orient_to_normal`)
Gerechnet wird im **Bezugssystem des getroffenen Teils**, nicht in Weltachsen — dadurch
stimmt es auch am gerollten Rumpf, und ein Flügel auf einem bereits gespiegelten Flügel
(Basis det<0) erbt die Spiegelung von selbst. Drei Regeln:
1. **Seite aus dem Treffer:** Vorzeichen aus der Normale, wo sie eindeutig ist
   (`|ln.x| > 0.30`), sonst aus der Trefferposition, sonst rechts.
2. **Links ist die SPIEGELUNG, keine 180°-Drehung** — Sehne zeigt immer nach hinten,
   nur die Spannachse kippt (Basis wird improper, det<0, genau wie beim Symmetrie-Modus;
   `FlightController:340` / `AircraftBody:506` machen sie generisch proper).
3. **Sehne folgt der Längsachse des getroffenen Teils.**
Die Spannachse eines Teils kommt aus `col_offset`: auf ihr ist der Versatz genau die halbe
Boxgröße (`_fluegel_spannachse`). Fast alle spannen in +X, `mig21_fin` ist als stehende
Flosse in +Y gebaut. Wurzel rastet längs/hoch auf 0.25 IM ZIELSYSTEM (linke und rechte
Seite landen auf derselben Station) und sinkt um `col_size.y*0.25` (3–10 cm) unter die Haut.
GESCHICHTE (nicht wiederholen): `z = x × y` kippte die Sehne mit der Spannweite um →
gepfeilte und Deltaflügel pfeilten LINKS NACH VORNE (gemessen: Delta −1.35 statt +1.35).
Oben/unten getroffen war `Vector3(n.x,0,n.z)` ≈ 0 → Fallback `Vector3.RIGHT`, also IMMER
rechts. Und `_orient_to_normal` setzte X = Normale, was `mig21_fin` (X = Dicke 0.14) flach
hinlegte. Harness: `tools/_fluegelsnap_check.gd` (17 Flügel × 9 Trefferstellen mit Urteil),
`tools/_fluegel_flug.gd` (direkt links gesetzter Flügel fliegt: 0 NaN-Frames, Drehrate 0.00).

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
- **Werkzeuge:** Bearbeiten (Default — auswählen/skalieren/verschieben) / Abriss / **LACKIEREN**:
  Vorschau der aktuellen Farbe + `ColorPickerButton` „Farbe mischen" (Farbrad/RGB/Hex) +
  **Pipette** (`pick_mode`, Taste **P**) + zwei Palettenblöcke (Militär&Zivil / Kräftig, je 14).
  Die Pipette nimmt beim nächsten Klick die Farbe eines Teils und **schaltet sich danach selbst
  ab**, fällt also direkt in den Lackiermodus mit der geholten Farbe — man will fast immer eine
  Farbe holen und sie dann auftragen. `teil_farbe()` liefert bei einem NIE lackierten Teil die
  WERKSFARBE aus dem Katalog (Meta `color` hat dort a=0) — sonst käme Schwarz heraus.
  `pick_mode` schliesst sich mit brush/erase/paint gegenseitig aus; Signale `farbe_gepickt`
  und `pipette_umgeschaltet` halten den Panel-Knopf synchron. Beleg: `tools/_lackieren_check.gd`.
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
- **AUTO-TAPER (beidseitig):** `_sync_auto_taper` (in `_notify_changed`, bis zu 3 Passes fuer
  Ketten): Sitzt an einem Ende eines `biends`-Segments buendig ein Rumpfteil/Antrieb
  (Testpunkt 0.06 jenseits der Stirnflaeche, wie `cockpit_side_docked`), wird DIESES Ende
  automatisch auf dessen Querschnitt (`size`.x/y × pscale, bei biends-Nachbarn inkl. deren
  Taper am beruehrten Ende) verjuengt/aufgeweitet — vorne und hinten UNABHAENGIG (schmaler
  Motor vorn + breites Cockpit hinten -> fliessender Uebergang). X und Y getrennt (echte
  Ellipsen-Anpassung). MANUELL geformte Enden sind tabu: Panel-Regler/Enden-Drag setzen
  `taper[_front]_user`-Metas (persistiert als `tuser_f/b`; ALT-Saves ohne Flags: jedes vom
  Teil-Default abweichende Ende gilt als manuell -> bestehende Designs werden beim Laden
  nicht umgeformt). Freie Enden behalten ihren letzten Wert. Kein History-Push
  (abgeleiteter Zustand wie `engine_half`). Regression: `tools/_dock_test.gd` Abschnitt 7.
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
(Griffe+Panel: skalieren/drehen/löschen), **Body ziehen=verschieben** (AUSWÄRTIGER TEILBAUM wandert mit — `_capture_move_kids`, BFS wie beim Flügelbruch; Alt = nur das Teil) · leerer Raum/Rechtsmaus=drehen ·
Mausrad/`+`/`−`/Pinch=Zoom · `X` löschen · `R` drehen/kippen · `M` Symmetrie ·
`Strg+Z`/`Strg+Y` Undo/Redo · `F` Ansicht · **`Strg+D` duplizieren** (Klon+Spiegel, `duplicate_selected`) ·
**`Strg+C`/`Strg+V` kopieren/einfügen** (`copy_selected`/`paste_clipboard`; `_clipboard` hält
reine DATEN, keinen Node-Verweis, überlebt also Löschen und Moduswechsel) · Alle drei Wege
gehen über `_teil_schnappschuss` → `_teil_einsetzen` → `_form_uebernehmen`, also **denselben**
Code wie `load_design`. Vorher trug `duplicate_selected` nur Farbe/Größe mit und verlor still
Verjüngung, Enden-Versatz, Eckrundung und Beinlänge — inklusive am erzeugten Spiegel ·
**Pfeiltasten** = ausgewähltes Teil fein verschieben (`nudge_selected`, 0.25er; `_notify_changed()`
kommt dort — wie bei nudge_scale/rotate/tilt — schon aus `_apply_sel_transform`) ·
**`1`/`2`/`3` orthografische Blueprint-Ansicht** Front/Seite/Oben, **`4`** frei (`set_view`/`_ortho_view`,
Kamera `PROJECTION_ORTHOGONAL`; manuelles Drehen → zurück Perspektive) · Tab=Testflug.
Statistik hat eine **„Fliegt's?"-Ampel** (`_update_ampel`): grün/gelb/rot aus Stabilität
(col.z−com.z), Schub & Fahrwerk + kurzer Tipp. Berücksichtigt die verstellbaren Antriebe
(`compute_stats`): `tw`=**Vorwärts**-Schub/Gewicht (gedrehte/Reverse-Triebwerke zählen nur
mit ihrer −Z-Komponente), `up_tw`=Senkrechtschub/Gewicht (VTOL-Erkennung), `thrust_offset`=
effektiver Hebel des Netto-Schubs um den COM (außermittig/schräg → zieht/kippt). Rot: stark
außermittiger Schub (`offset>1.0`, z. B. Düse hinten nach oben), Schub zeigt nicht nach vorne
(Reverse/gedreht, `tw<0.12` & `up_tw<0.9`), zu wenig Schub, kopflastig, keine Flügel,
Fahrwerk-Überlast. Gelb: Senkrechtschub-Stil (VTOL), wenig Vorwärtsschub, **Schub nicht durch
den COM** (`offset>0.15` — zieht/kippt beim Gasgeben; betrifft z. B. Nasen-Props mit COM unter
der Schublinie wie Spitfire/Mustang), grenzwertig stabil, kein Fahrwerk, schwache Flügel.
**Kein freies Schweben:** `_connected_set` (BFS ab Cockpit über AABB-Nachbarschaft
`_part_world_aabb.grow(0.12)`) findet nicht verbundene Teile; `has_floating`/`floating_parts`.
Schwebende Teile bekommen einen **roten Warn-Marker** (`_update_float_markers` in `_notify_changed`),
die Ampel wird rot, und der **Start ist blockiert** (`_set_mode` → Toast statt Moduswechsel).
**Bauen = Drag&Drop aus dem Inventar:** Druck auf eine (freigeschaltete) Teile-Kachel ruft
`begin_drag_from_palette` → Ghost folgt der Maus, **in den Bauraum ziehen & loslassen** = gesetzt
(rastet flächenbündig an). Loslassen über UI = verworfen (`gui_get_hovered_control`). Release per
Polling in `_process` erkannt (Druck ging an die UI). Gesperrte Kacheln: Klick kauft.
**Vorhandenes Teil anklicken = AUSWÄHLEN** (`_on_left_press`→`_transform_left_press`) → **Blender-
artiges Gizmo** je `gizmo_mode` (Tasten **G/R/S** oder Panel-Buttons): **Bewegen** = 3 Achsen-Pfeile, JE ACHSE so weit aussen wie die Huelle des Teils auf dieser Weltachse reicht (`_giz_halb` aus `_part_world_aabb` — dieselbe Box, die der Debug-Haken zeichnet), plus die halbe Schaftlaenge; Pfeilgroesse `_giz_gr` skaliert mit dem Teil, geklemmt auf 0.45..1.5. FRUEHER galt fuer ALLE drei Pfeile die GROESSTE Halbachse + RING_MARGIN: an `wing_straight` (Halbmasse 2.20/0.10/0.85) hing der Y-Pfeil 3.20 von der Oberflaeche weg statt 1.15, am winzigen `aileron` 1.96 statt 0.64. Die Dreh-Ringe nutzen weiter den gemeinsamen Radius (ein Ring ist rund). Harness: `tools/_pfeil_abstand_check.gd` (8 Teile), `tools/_pfeil_render.gd` (Sichtprobe mit eingeschalteter Debug-Box) + Body ziehen = frei verschieben;
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
`V` (HALTEN) **Zielzoom** · `N` **Maus-/Tastatur-Flug** umschalten (Maus-Flug = STANDARD beim Flugstart) · `M` **Karte** (Vollbild-Inselkarte, Mausrad = Zoomstufen 1/2.5/6; Corner-Minimap läuft immer mit) · `H` **Bombenschacht** auf/zu (siehe unten) · `O` **G-Schutz** (lag frueher auf H; Default AN, persistiert: `AircraftBody.g_protect` kappt den Auftrieb hart bei 95 % der Flügel-Belastbarkeit -> Flügel können NICHT abreißen, Mush am Limit; AUS = volle Physik + Flügelbruch, HUD-Badge) · `Enter` Reset/Reparatur · `Tab` Hangar (gibt Maus frei).
**Maus-Flug (GROSSKREIS-INSTRUCTOR, STANDARD; `N` = Tastatur-Modus):** Maus zeigt eine
WELTRICHTUNG (`look_yaw/pitch`, ROH — kein Glättungs-Lag); Pitch-Klemme `AIM_PITCH_CLAMP≈87°`.
`mouse_fly=true` als Default; `set_active(true)` ruft `_reset_mouse_state()` (Aim an der
Nase ausrichten, Filter/Trim nullen — auch vom M-Toggle genutzt).
**DER INSTRUCTOR LIEST DEN BAU (`_auth_rates()`):** Obergrenze der kommandierten Nick-/
Roll-/Gier-Raten = physisch erreichbare Dauer-Drehrate DIESER Zelle aus dem Torque-
Gleichgewicht (CTRL+CTRL_A·Steuerfläche)·qfac·MOUSE_AUTH = DAMP·apq·(0.35+qfac) — exakt
die AircraftBody-Formeln, ×`AUTH_HEADROOM=0.85` Regelreserve, min() mit den Feel-Tabellen.
Großes Leitwerk = schnelle Befehle, Mini-/kein Ruder = ehrlich träge OHNE Sättigungs-Lag
(`tools`-Beleg: Bau ohne h_stab konvergiert 2.6°/0 Pendel statt Dauer-Vollausschlag).
Signalfluss (FlightController, `if mouse_fly:`): Maus → `_aim_cmd` (Slew-Limit
`AIM_CMD_SLEW=6 rad/s` + ZITTER-TOTZONE mit Hysterese 0.2°/0.03° (`_aim_live`) —
Handzittern der gefangenen Maus erreicht weder Fehler-P noch FF; der FF hat
zusätzlich ein Soft-Gate smoothstep(0.06,0.18,|w|); Ruder-Visuals werden in
AircraftBody zusätzlich servo-geglättet 10/s bzw. 1.5/s unter 0.7°) → **EIN Gesetz für Nick/Gier (kein Modus-Blending!)**:
Soll-Drehvektor (Welt) = Achse(`Nase×Ziel`)·Rate; Rate = min(G-Budget
`g·√(n²−1)/v` mit `n=G_SOFT·g_lim`, `PITCH_RATE_TAB(v)`, Stopp-Planung
`√(2·AIM_TURN_ACC·err)` — bremst VOR dem Ziel, linearer Endanflug `INS_KP_V·err`)
+ **Feed-Forward der Marker-Drehrate** (`_aim_ff`, gefiltert 8/s — sonst ~11°
Schleppfehler beim Maus-Ziehen) → `basisᵀ` verteilt die Welt-Drehung
VORZEICHENRICHTIG auf Körper-Nick/Gier (jede Bank, jenseits 90° wird gedrückt) →
**AoA-LIMITER** (primär, geschlossener Kreis auf `aircraft.aoa_signed`,
`AOA_MAX=0.78·STALL_A`, Mush: Nase sackt unter den Marker) → **G-LIMITER**
(sekundär, weich 75→92 % von `wing_capacity/(m·g)`) → innere Raten-P + Auto-Trim;
Gier = β-Koordination (`INS_YAW_BETA`) + Raten-Tracking (`yaw_track`, ±0.3).
ROLL (eigener Kanal, NUR Zugebenen-Ausrichtung, nie im Nick-Pfad): Hysterese
`_rnp_on` (RNP_ON 0.9/RNP_OFF 0.45 + `|vert|<0.18`): groß = phi-PD in die
Manöverebene (`RNP_ROLL_KP/KD`, Richtungs-Latch 2.6/2.0, Gate smoothstep(0.25,
0.6, err) gegen phi-Rauschen bei kleinem Fehler), klein = Kurvengleichungs-Bank
`atan(wh_filt·v/g)` aus der TIEFPASS-gefilterten (3.5/s) + kleinst-gegateten
horizontalen Soll-Drehrate (1° Fehler ergäbe sonst bei 200 m/s ~42° Soll-Bank —
Maus-Zittern kippte das Vorzeichen -> Querruder-Schaukeln), Roll stopp-geplant
(`min(√(2·AIM_ROLL_ACC·Δbank), 4.5·Δbank)` — das lineare Endsegment killt den
sqrt-Grenzzyklus ums Bank-Ziel), gedrosselt solange Vertikal-Pull ansteht
("Pull fertig fliegen, dann ausrollen"). `AIM_BANK_MAX=1.47` (~84°; 72° deckelte
Dauerkurven auf ~3 G → Messer-Drift bei 200 m/s). **A/D = gehaltener Bank-Offset**,
Tasten additiv. Kamera: eigener Rig (`_cam_aim` 12/s auf ROHE Maus, `CAM_LEAD`),
Marker im HUD roh. Lücke Nase↔Marker ist REINE Physik. GESCHICHTE (nicht
wiederholen!): die alte Kaskade Fehler→Soll-Bank→Rollen→Zug mit Modusblende war
bei 200 m/s strukturell instabil (26–57° Overshoot) — Bank-Trigonometrie im
Nick-Pfad setzt jede Roll-Bewegung in Seitenfehler um, und `wh_cap=g·tan(BANK)/v`
war der Engpass. Headless-Harness: `tools/mousefly_test.gd` (Konvergenz/Pendeln),
`tools/mf_speed.gd` (MiG, echtes Überschwingen = Peak NACH erstem ~0-Durchgang),
`tools/mf_design.gd` (Spieler-Design aus user://, 140–200 m/s), `tools/mf_track.gd`
(wandernder Marker + Split-S), `tools/mf_mush.gd` (Mush unter Stall-Speed).
- **Arcade-Lenkung (`arcade`, Taste `J`, nur im Maus-Flug):** maximal smoothe, direkte
  Lenkung. Statt Steuer-Torque dreht `AircraftBody._arcade_steer` die Orientierung
  **kinematisch per Quaternion-Slerp** (`ARCADE_RESP`) auf die Ziel-Basis (Nase=`aim_world`,
  in die Kurve gebankt) und führt die Geschwindigkeit der Nase nach (`ARCADE_VEL`).
  Unabhängig von Ruder-Autorität/Stall/G → schnappt in ~0.3–0.4 s auf jede Richtung (auch
  180°), exponentiell = **kein Überschwingen/Trudeln**; Flügelbruch im Arcade aus. **Godot-
  Falle:** `state.transform.basis = …` schreibt NICHT zurück → ganzen `state.transform`
  neu zuweisen. FlightController setzt `aircraft.arcade`/`aircraft.aim_world` (roh) je Frame;
  `_toggle_arcade` (J) schaltet ggf. den Maus-Flug mit ein. HUD zeigt „ARCADE 🎮".
- **ZIELZOOM (`V` halten, War-Thunder-Art):** OPTISCH KORREKT umgesetzt — `FOV_ZOOM=22`
  verengt das vertikale FOV UND `ZOOM_DIST=2.2` setzt die Kamera im gleichen Verhaeltnis
  zurueck. NUR das FOV zu verengen brächte nichts: es vergroessert das eigene Flugzeug
  genauso mit. Erst der groessere Abstand laesst die eigene Zelle gleich gross erscheinen,
  waehrend ferne Ziele um FOV_BASE/FOV_ZOOM (~2.9x) wachsen. `zoom_t` wird GEPOLLT
  (`Input.is_physical_key_pressed(KEY_V)` im Kamera-Update), damit HALTEN zaehlt — ueber
  `_unhandled_input` gaebe es nur den Tastendruck. Die Maus-Empfindlichkeit skaliert mit
  (`ZOOM_SENS=0.42`), sonst ist Zielen unmoeglich; das HUD zeigt den Faktor als Badge.
  Gemessen/belegt mit `tools/_zoom_check.gd` (zwei Bilder derselben Szene). Der Abstands-
  faktor gilt in BEIDEN Kamerapfaden (`_cam_offset` UND Maus-Flug-Zweig in `_process`) — im
  Maus-Flug fehlte er lange, die eigene Zelle wuchs beim Zoomen auf das 2,9-fache.
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
Rumpf (Cockpit=Wurzel, Segmente, Nase/Heck, Tank) · **Kanzeln:** `cockpit` (Standard,
offene Doppeldecker-Wanne) und `cockpit_radial` (Doppeldecker/Stern) — die vier generischen
Varianten (Bubble/Jet/Rahmen/Tandem) sind auf Wunsch ENTFERNT. Dazu **`canopy_bean`**
(„Bohnen-Kanzel"): glatter ovaler Blister zum AUFSETZEN, steckt zu 40 % im Rumpf. Das macht
`shape "bean"` + Feld `embed`: `size.y` umfasst nur den SICHTBAREN Teil (der generische Snap
legt die Unterkante der Box auf die Flaeche), die Geometrie wird um `size.y/(1-embed)`
gestreckt und nach unten versetzt -> gemessen exakt 40.0 % eingebettet
(`tools/_bean_check.gd`). Und **`cockpit_b29`** („B-29-Kanzel"): ein eigenes
Blender/glTF-Bauteil (`models/cockpit_b29.glb`, Quelle
`tools/build_b29_cockpit_model.py`) mit der charakteristischen rundum verglasten
Superfortress-Nase statt eines Dach-Canopys. Das `glass`-Material ist nach der letzten
Referenz fast schwarz und vollständig blickdicht (`Color(0.015,0.025,0.055)`,
Metallic 0.25, Roughness 0.12, Alpha 1.0); der niedrige Roughness-Wert erhält den
glänzenden Bubble-Eindruck, ohne den Innenraum durchscheinen zu lassen. Die Fenster sind
bewusst einzelne flache Facetten: Jedes Feld hat eine etwas größere Metallfläche als Träger und eine
parametrisch eingerückte Scheibe, sodass der bündige Rahmen direkt in der Außenhaut liegt
und nicht wie ein Drahtkäfig vor der Nase schwebt. In der finalen Geometrie sind Rahmen,
Scheiben und Metallkinn sogar ohne überlappende Flächen in **einem** `B29_Nasenhaut`-Mesh
mit Materialindizes aufgebaut; dadurch gibt es keine gestapelten Einzelplatten oder
Z-Fighting. Die Pilotenfenster sind keine aufgesetzte zweite Schale mehr. Die
Außenproportion folgt dem kompakten B-29-Bug: Die rundliche Glasnase endet bereits
bei Y=-0.34 und geht dort in einen 1.06 m langen, geraden Metallrumpf bis Y=-1.40
über. Die Scheiben reichen vorn rund um das Bombenschützenfenster; nach hinten
steigt die Metall-Kinnlinie stufenweise an, sodass die letzten beiden Reihen nur
die obere Druckkabinenhälfte verglasen. Die untere Silhouette wächst über mehrere
Querschnitte ohne harten Ausschlag auf den konstanten Rumpfradius. Beim Blender-Build werden
`B29_Nasenhaut` und `B29_Rumpf_komplett`
anschließend gejoint und die zwölf identischen Vertex-Paare per
`bmesh.ops.remove_doubles(dist=0.00001)` verschweißt; Normalen werden neu berechnet.
Der Export enthält nur noch **ein** `B29_Rumpf_mit_Nase`-Mesh für die gesamte Außenhaut
und insgesamt vier Mesh-Baugruppen. Die gesamte hintere Rumpfschale verwendet an jeder Station exakt denselben
elliptischen Querschnitt und dieselbe Z-Mitte — sie ist ein gerader Zylinder, keine
gebogene oder bauchige Röhre. Beide Anschlussringe haben dieselbe 12er-Teilung und dieselben Koordinaten;
so entstehen auch zwischen unterschiedlich triangulierten Polygonringen keine Spalte.
Der Katalog bildet die echte Rückseite mit `col_size=(1.68,1.48,2.67)`,
`col_offset=(0,0.04,0.065)` und `dock_size=(1.68,1.48)` ab. Beim Platzieren eines
`biends`-Rumpfsegments auf dem geraden B-29-Metallkragen zieht
`BuildController._compute_snap_for` es unabhängig vom genauen Treffpunkt mittig auf
die Rückfläche. `_taper_neighbor` verwendet `dock_size` statt der größeren
Gesamt-Bounding-Box, damit Auto-Taper die zuvor passende Verbindung nicht wieder aufbläht.

Beide teilen dort die Kontur, aber keine Fläche. Die außen herausragenden
Kinn-/Fahrwerksblöcke und Nieten wurden entfernt; Steuerhörner und Bombenschützenplatz
liegen weiter innen und verwenden keine hellen Außenrahmen-Materialien. Der Cockpitboden
ist schmaler und höher, damit auch seine Ecken innerhalb der elliptischen Außenhaut
liegen. Frontscheibe und Frontring sitzen beide bei Z=-0.05 und sind dadurch exakt
konzentrisch. Der frühere dicke Torus bzw. die zu flache Ringplatte wurde durch eine
kurze konische Ringlippe mit drei Querschnitten ersetzt: außen exakt die erste
Nasenstation (0.20 × 0.18), mittig 0.165 × 0.155 und vorn ein zwölfeckiger 0.138er Rand.
Die zwölfeckige schwarze Scheibe (r=0.126) sitzt 0.004 hinter dieser Vorderkante. Damit wächst
das Frontteil aus der Nase, ohne wie ein aufgesetztes Rohr oder eine Platte zu wirken. Der Export fasst
die übrigen Konstruktionsobjekte zu `B29_Rumpf_komplett`, `B29_Glasdetails`,
`B29_Rahmendetails` und `B29_Innenraum` zusammen; nach dem Verschweißen bleiben insgesamt
vier Meshes. Die nach hinten ansteigende Metall-
Kinnlinie, kleine runde Bombenschützen-Frontscheibe und zurücklaufende Pilotenfenster
bilden die Referenz-Silhouette; Astrodome und Antenne gehören zu späteren Rumpfsegmenten
und sitzen bewusst nicht auf diesem Cockpitteil. Der Innenraum folgt jetzt dem
echten B-29-Vorderdruckraum: Pilot und Copilot sitzen nebeneinander auf dem erhöhten
Flugdeck mit getrennten Instrumententafeln, großen runden Steuerhörnern, Pedalen und
zentralem Vierfach-Gashebel. Davor liegt der Bombenschütze tiefer in der Glasnase
mit Klappsitz, Tisch und detailliertem Norden-Visier. Hinten links liegen
Navigator-Kartentisch und Leselampe, hinten rechts das hohe Flugingenieur-Seitenpanel
mit 16 Instrumenten; Dachkonsole und runder Drucktunnel-Anschluss schließen den
Vorderraum ab. `cockpit_body` bleibt lackierbar,
`glass` unangetastet. Das prozedurale `shape "b29_nose"` bleibt nur als Fallback, falls
das glTF fehlt. `col_size` hält die hintere Andockfläche trotz vorstehender Glasnase
spaltfrei an dicken Rumpfsegmenten.

Eigenständiges Konzeptmodell **modernes Transportflugzeug-Cockpit**:
`blender_lib/transport_cockpit.blend`, Export `models/cockpit_transport.glb`,
reproduzierbar über `tools/build_transport_cockpit_model.py`. Kurzer kantiger Bug mit
einem einzigen umlaufenden Band aus sechs bündig eingelassenen dunklen Scheiben,
dezenten Seitentürfugen, feinen Pitotrohren und keilförmigen Dachantennen. Der
Rumpfquerschnitt ist als leicht abgeflachte Superellipse gebaut, nicht kreisrund.
Die ebene Rückseite liegt in Blender bei Y=-1.40; der gerade
Anschlussquerschnitt ist 2.20 × 1.86 m. Das GLB enthält genau zwei Meshgruppen
(`Transport_Cockpit_Hull`, `Transport_Cockpit_Details`). Es ist als
`cockpit_transport` in der Rumpfpalette registriert und darf als Wurzelteil starten.
Beim Ablegen eines normalen Rumpfsegments auf dem geraden Metallkragen ersetzt
`BuildController` es automatisch durch das versteckte `fuselage_transport`. Dieses
prozedurale Segment verwendet dieselbe 12-seitige Superellipse und denselben
2.20 × 1.86-m-Querschnitt; weitere Segmente führen das Profil als Kette fort.
`tools/transport_cockpit_test.gd` prüft Godot-Import, Meshgruppen, Materialien,
Außenmaße, Palette, Spezial-Snap und die Andockebene.

### C-130-BAUKASTEN (`tools/build_c130_kit.py`)
Vier Teile aus ZWEI mitgelieferten Blender-Quellen: `blender_lib/c130_kit_flugzeug.blend`
(→ `cockpit_c130`, `fuselage_c130_long`, `fuselage_c130_short`) und
`c130_kit_triebwerk.blend` (→ `engine_c130`). Aus dem Flugzeug wird bewusst NUR Cockpit und
die zwei Rumpfringe geholt; Flügel/Fahrwerk/Details bleiben draußen.
**Maßstab:** Quellrumpf 4.35 → **2.55** Querschnitt, also etwas größer als das bisher
größte Cockpit (`cockpit_transport`, 2.20) — es ist ein Frachter. Das Cockpit wird UNIFORM
skaliert (2.55×2.55×2.591; eine geformte Nase darf man nicht längs ziehen). Die beiden
Ringe sind nachgemessen echte Röhren mit konstantem Querschnitt (alle Innenringe identisch,
nur 0.04 Fase an den Enden) und dürfen daher längs gestreckt werden: EIN gemeinsamer
Faktor 1.6 bringt den langen auf **2.40** (= `fuselage_transport`), der kurze folgt mit
**1.92** und behält damit das Quellverhältnis.
**Länge entscheidet die Variante:** `BuildController._c130_segment_id()` summiert die Länge
von Cockpit + allen C-130-Ringen (`_c130_kette_laenge`, bewusst NICHT die Design-Bounding-Box
— sonst verschöben Flügel und Motoren die Wahl) und schaltet ab `C130_LANG_AB = 4.4` auf den
langen Ring. Cockpit allein sind 2.591, Cockpit + ein kurzer Ring 4.511 → hinter dem Cockpit
sitzt genau EIN kurzer Ring, alles dahinter ist lang. Das ist exakt der Aufbau der Quelldatei.
Beide Ringe sind `PALETTE_HIDDEN`: man zieht ein normales Rumpfsegment an die Kette, die
Regel wählt. Beide sind `biends`, obwohl sie aus einem **glb** kommen — siehe
„Formbare Enden am importierten Modell" unten. Der Shape `c130_tube` (Loft über
`C130_PROFILE` mit `_profile_tube`) ist nur noch der Notnagel, falls ein glb fehlt.
`C130_PROFILE` kommt aus `tools/extract_c130_profile.py` (mittlerer Ring von
`Fuselage_long`, 82 → 24 Punkte, CCW, normiert); der Querschnitt ist KEIN Kreis, an den
Diagonalen liegt er bei 0.512 statt 0.500.

### FORMBARE ENDEN AM IMPORTIERTEN MODELL (`_modell_enden_formen`)
Ein glb-Teil lässt sich nicht loften — es gibt kein Profil, nur fertige Dreiecke. Deshalb
wird die **Original-Geometrie selbst verformt**: jeder Vertex wird nach seiner Lage auf der
Längsachse (`t = 0` vorne … 1 hinten) quer skaliert (`taper`) und versetzt (`shift`). Für
einen Rumpf mit durchgehendem Querschnitt ergibt das exakt dieselbe Form wie `_profile_tube`,
nur mit ALLEN Details, Materialien und UVs des Modells. Damit bekommt jedes `biends`-Teil mit
glb automatisch Enden-Skalierung und -Versatz; ein prozeduraler Nachbau ist nicht nötig.
ZWEI PUNKTE, an denen es sonst kippt: (1) Es wird ein **neues ArrayMesh** gebaut — das
geladene glb ist eine geteilte Ressource, wer sie ändert verbiegt jedes andere Exemplar
gleich mit. (2) Die **Normalen** werden mit der inversen Transponierten der lokalen
Jacobi-Matrix mitgedreht (`n' = (nx/sx, ny/sy, nz − ax·nx/sx − ay·ny/sy)`), sonst wird die
schräge Flanke eines verjüngten Rumpfs falsch beleuchtet. Der Versatz steht als ANTEIL der
Teilbreite in den Metas (so rechnet der Zieh-Griff), das Modell liegt in Endmaßen → beim
Anwenden mit `size` hochrechnen. Beleg: `tools/_c130_enden_check.gd` (Verjüngung 0.55 →
Halbbreite 1.2627→0.6945 bei unverändertem Heck; Versatz 0.22/0.30 → 0.5610/0.7650 = Anteil
× 2.55, Gegenfläche 0.0000) und `tools/_c130_verform_render.gd` (Sichtprobe Beleuchtung). Angedockt wird über einen EIGENEN Zweig `_c130_fit` statt `_fuselage_fit` —
dessen „längste Achse"-Heuristik hielte den 2.55 breiten, 2.40 langen Ring für querliegend
und dockte SEITLICH an (gleicher Grund wie beim Sternmotor).
**Triebwerk:** Gondel + drehender Knoten **`Prop`** (Spinner + 6 Blätter). `col_size` ist NUR
die Gondel (1.124×0.951×3.104), nicht die 2.52 breite Propellerscheibe — sonst höbe der
Motor beim Andocken um deren halbe Breite ab.
FALLEN (beide hier reingelaufen): (1) Die sechs Blätter sind **Linked Duplicates** (ein
Mesh-Datenblock) → `transform_apply` bricht mit „Cannot apply to a multi user" ab, erst
`make_single_user`. (2) `o.bound_box` und `matrix_world` sind nach direktem Schreiben von
`v.co` bzw. `.location` **veraltet** — die Teile kamen dadurch mit exakt der unskalierten
Quellgröße heraus und die Propellerscheibe wurde in die Gondel gerechnet. AABB direkt aus
den Vertices nehmen und nach `.location` ein `view_layer.update()`.
Harness: `tools/_c130_kit_check.gd` (glb-Maße, Prop-Achse, Materialien),
`tools/_c130_bau_check.gd` (Kette bauen: Variantenwahl, Spalt 0.00000, koaxial 1.0000,
Propeller dreht sich im Flug).

Dazu **`b29_wing`** („B-29-Tragflaeche"): langer Streckungsfluegel (Spannweite 7.2,
Wurzel 2.0 / Spitze 1.1, leichte Pfeilung, `stress_mult` 1.9 fuer den kraeftigen Hauptholm)
— traegt viel, dreht traege, wie das Original.
Und **`jet_cockpit`** („Delta-Jet-Cockpit", jetzt in der Palette
statt versteckt): `_jet_hull` lofted seither MIT Stirndeckeln — ohne sie war das Segment ein
offenes Rohr, mitten im Rumpf unauffaellig, als vorderstes Teil aber sichtbar aufgerissen
(genau das gemeldete „vorne kaputt"). Einlaufteile (`intake`) bleiben vorne offen. ·
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
- **UI läuft aus dem Bild — zweimal dieselbe Ursache:** Ein `Label` ohne Umbruch hat als
  Mindestbreite die volle TEXTBREITE, eine `HBoxContainer` die SUMME ihrer Kinder. `Control.size`
  wird nie unter `get_combined_minimum_size()` gedrückt — Anker helfen also nicht, das Element
  wächst aus dem Bild. Gemessen: Hinweiszeile 398 px über den rechten Rand, Werkzeugleiste
  1018 px nötig bei 946 px Platz. Fix: Label `autowrap_mode`, Leiste `HFlowContainer` (bricht um)
  statt `HBoxContainer`. Dazu spannt ein unsichtbarer Halter nur den freien Bereich ZWISCHEN
  Bau-Panel (endet 496) und Statistik-Panel (beginnt −376) auf. Harness: `tools/_ui_rand_check.gd`
  läuft die echte Main-Szene ab, misst jedes Control gegen den Bildschirm UND die Überlappung der
  Leiste mit beiden Panels. FALLE dabei: die Leiste über die Baumform zu suchen brach beim
  nächsten Umbau still ab und die Probe mass etwas anderes — sie heisst jetzt `Werkzeugleiste`
  und wird über den Namen gefunden.
- **Blender -> glTF -> Godot (Weltmodelle), drei Fallen:** (1) `create_icosphere(subdivisions=1)`
  ist das NACKTE Ikosaeder (20 Flaechen), die 80er-Kugel ist `subdivisions=2`. (2) Der glTF-
  Export schreibt die Vertexfarbe OHNE Alpha — Informationen dort kommen nie an. (3)
  `recalc_face_normals` raet auf OFFENEN Streifen falsch herum; nur geschlossene Koerper
  ausrichten (und per Volumenvorzeichen pruefen), Deckel erst danach entfernen.
- **Messwerkzeuge muessen den Zustand WIEDERHERSTELLEN, nicht "einschalten".** `_gelaende_zeit`
  setzte nach der Messung ohne Flora JEDE MultiMesh auf sichtbar — auch die Fernfassungen, die
  TerrainWorld gerade ausgeblendet hatte. Ab da zeichnete die Szene jeden Baum doppelt, die
  Fehler summierten sich von Stellung zu Stellung (Hang: "Flora 10 ms" statt 1,6; Gras
  negativ). Jetzt merkt `_setze` den alten Zustand. Alte Flora-Zahlen vor 2026-10 sind davon
  betroffen (Mittelwerte ueber mehrere Stellungen zu hoch).
- **`node.visible` ist nur der EIGENE Schalter.** Wer „ist das zu sehen?" meint, muss auch die
  Eltern prüfen (oder den Zustand dort abfragen, wo er gesetzt wird). Beispiel: die Grafik-
  einstellung „Wolkenlagen" blendet das ganze CloudField aus, `CloudField.dichte_bei` prüfte
  nur `mi.visible` der einzelnen Wolke — unsichtbare Wolken machten weiter Nebel, Turbulenz
  und Flak-Deckung. Beleg: `tools/_grafik_check.gd`.
- **Packed-Arrays sind Werttypen.** `(arr[k] as PackedInt32Array).append(x)` ändert eine Kopie;
  das Original im Array bleibt leer — ohne Fehlermeldung. Direkt in Packed-Arrays arbeiten
  (CSR: zählen, dann füllen). Und eine Prüfung, die über dieselbe kaputte Struktur fragt,
  meldet „alles gut“: gegen eine unabhängige Brute-Force-Rechnung prüfen (Landstraßen).
- **Physik-Interpolation + MultiMesh = Warten auf den Renderfaden.** Im Projekt ist
  `physics_interpolation` an. Wird eine MultiMeshInstance3D eingehaengt oder an einer
  eingehaengten MultiMesh das Netz/`visible_instance_count` geaendert, wartet der Hauptfaden
  synchron auf den Renderfaden — der ERSTE solche Vorgang je Frame kostete gemessen ~13 ms,
  jeder weitere ~0,3 ms. Statische Welt-Wurzeln tragen deshalb
  `physics_interpolation_mode = OFF` (TerrainWorld, Fernschuerze, Landstrassen, CityBuilder-
  Viertel), und an eingehaengten MultiMeshes wird nichts mehr umgestellt (Details im
  Abschnitt „Nachladen: Schnellflug und weiches Erscheinen"). Headless faellt das nicht auf.
- **Instanz-Uniforms haben ein Budget.** Jede Instanz, deren Material `instance uniform`s hat,
  belegt einen Block im globalen Shader-Puffer (`rendering/limits/global_shader_variables/
  buffer_size`, Standard 65 536 → rund 4000 Instanzen). Laeuft er voll, meldet Godot „Too many
  instances using shader instance variables" und die Parameter wirken still nicht mehr.
  Im Projekt auf 262 144 gestellt (Chunk-Detailstufen, zwei Flora-MultiMeshes je Art).
- **`visibility_range` misst ab der Huelle der Geometrie** (nachgemessen: Knoten am Ursprung,
  Geometrie 5 km daneben, Kamera davor → sichtbar), nicht ab dem Knotenursprung.
- **WorkerThreadPool-Gruppen stehen in einer Schlange.** Die Fernschürze legt beim Start 577
  Kacheln hinein; alles, was danach kommt und zeitkritisch ist (Weltkarte, Spawn-Chunks),
  braucht `high_priority=true`, sonst wird es LANGSAMER als der alte Einzelthread.
- `:=` nur für NEUE lokale Variablen; Member mit `=` zuweisen.
- Bei Variant-Inferenz (Dict-Zugriff `* float`) explizit typisieren (`var f: Vector3 = …`).
- **Keine Node-Änderungen in `_integrate_forces`** (reparent/add/remove) → in `_process`
  verschieben (Flügelbruch nutzt `_break_pending`-Flag).
- `contact_monitor=true` + `max_contacts_reported>0` nötig für `get_contact_count()`.
- Gespiegelte (det<0) Basis nur für Visuals ok; für Kollision proper machen.
- **Ein neues Pro-Teil-Meta braucht VIER Stellen, sonst wirkt das Feature „kaputt":**
  (1) `BuildController.get_design/load_design`, (2) `Main._design_data` (Datei schreiben),
  (3) `Main._load_design_from` (Datei lesen), (4) den Mesh-Bauer JEDER betroffenen
  `shape`. Genau daran starb „Enden verschieben" doppelt: `_prism_mesh` (Formen
  `transport_tube`/`prism`) kannte den Versatz nicht, und die Datei transportierte
  `sf`/`sb`/`glen`/`br`/`bsc` gar nicht — im Editor gesetzt, beim Neustart still weg.
  Beim Debuggen also nicht bei der Interaktion anfangen, sondern die Kette Meta →
  Datei → Mesh je Form durchmessen (`tools/_versatz_form.gd` macht das für alle
  `biends`-Formen auf einen Schlag).

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
- **MODELLBIBLIOTHEK `blender_lib/`** (traegt `.gdignore`): eine .blend je Kategorie
  (motoren/fahrwerke/cockpits/ruempfe/fluegel_leitwerk/waffen — Quelle models/*.glb,
  via `tools/build_blender_lib.py`) + **`gebaeude.blend`**: ALLE prozeduralen
  Landmarks-Bauwerke (Stadt/Bergdorf/Leuchtturm/Windrad/Bruecke + Einzelhaeuser
  Haus_A..F, je eigene Collection). Pipeline dafuer ist ZWEISTUFIG, weil die Quelle
  GDScript ist: `tools/_export_buildings.gd` (Godot headless, GLTFDocument.append_from_scene
  -> transientes glb) -> `tools/build_gebaeude_blend.py` (Blender: Collections, Viewport-
  Farben aus glTF-Materialien, speichern; env `GEBAEUDE_PREVIEW=<png>` rendert Uebersicht).
- **HAEUSER-BAUKASTEN `blender_lib/haeuser.blend`** (`tools/build_haeuser_blend.py`):
  EIGENSTAENDIGE Datei, wird aus einer LEEREN Szene gebaut — `gebaeude.blend` wird nicht
  einmal mehr gelesen (frueher shutil.copyfile; die importierten Landmarks sind auf Wunsch
  raus). **42 Gebaeudetypen**, je eigene Collection unter `HAEUSER`, nach Reihen sortiert:
  Dorf/Kleinstadt (Bauernhaus, Fachwerk, Kate, Scheune, Stall, Silo, Wasser-/Windmuehle,
  Stadthaus 2+3, Reihenhaus, Eckhaus, Gasthaus, Villa) · oeffentlich (Kirche, Kapelle,
  Rathaus, Bahnhof, Krankenhaus mit Dach-Helipad, Kaufhaus, Hotel) · HOCHHAEUSER
  (Wohnturm 40 m, Bueroturm 52 m Glas, Wolkenkratzer 92 m mit Ruecksprungen, Plattenbau,
  Parkhaus, Speicher, Werkstatt) · Industrie (Fabrik mit Sheddach, Kraftwerk mit
  Kuehlturm, Getreidesilo, Hafenkran, Funkturm, Wasserturm, Tanklager) · Flugplatz/Spezial
  (Hangar, Tower, Radarstation, Bunker, Stadion, Burg, Lotsenhaus).
  **ZWEI DETAILSTUFEN AUS EINEM CODE:** jedes Haus wird zweimal gebaut — `Bau(name)` gibt
  die Fernsilhouette, `Bau(name, hd=True)` dieselbe Form mit Nahdetails. Die HD-Stufe
  entsteht automatisch (Fenster als Glas + Rahmenleisten + Sprossenkreuz + Fensterbank statt
  einem Quad, Daecher mit Traufbrettern/Firstziegel/Ziegelreihen, Rundungen doppelt so fein,
  Fassadenbaender mit Geschossgesimsen und Pfeilern) plus per `HD_EXTRAS` ein handgesetzter
  Detailsatz je Gebaeude (Strebepfeiler an der Kirche, Zinnen und Wehrgang auf der Burg,
  Balkongelaender an Wohnturm und Plattenbau, Dachtraeger im Stadion, Binder im Hangar,
  Rohre am Kraftwerk, Gitter am Kran ...). Ergebnis: **LOD 94 Tris im Schnitt, HD 576**
  (Kirche 1340). Weil beide aus DEMSELBEN Aufbau kommen, sind die Silhouetten
  deckungsgleich -> beim Umschalten springt die Form nicht. Export: `world_buildings.glb`
  (fern) + `world_buildings_hd.glb` (nah, Knoten heissen dort `<Typ>_HD`, weil Blender
  keine zwei gleichnamigen Objekte erlaubt — CityBuilder schneidet das Suffix ab).
  PERFORMANCE: EIN Multi-Material-Mesh je Haus (MultiMesh-tauglich), verdeckte Flaechen
  (Bodenplatten/Dachunterseiten) entstehen gar nicht, Fenster/Tueren/Fachwerkbalken sind
  flache Quads statt Boxen, bei Hochhaeusern durchgehende Fassaden-BAENDER (`_baender`:
  1 Quad je Fassade+Band) statt Einzelfenster, flat shaded, keine UVs -> **3958 Tris fuer
  alle 42 zusammen, Schnitt 94, Maximum 214** (Stadion).
  Baukasten in `class Bau`: box/dach(inset=Walm)/spitze/pultdach/zyl(achse="y" = liegender
  Tank)/kegel/feld/fenster_reihe/profil(Hallenbogen, Sheddach, Bunker)/rad(Muehlrad).
  Alle Haeuser schauen nach -Y. FALLEN: (1) ein um 180 Grad gedrehtes Rechteck ist mit sich
  selbst deckungsgleich — 4 Windmuehlen-Fluegel als 4 Panels gaben 2 Duplikate mit
  Z-Fighting, richtig sind ZWEI gekreuzte Bahnen; (2) Blender-BaseColor ist LINEAR ->
  `srgb2lin` wie beim Cockpit. `HAEUSER_PREVIEW=<ordner>` rendert Gruppenbilder (Dorf,
  Stadt, Grossbauten, LOD, Varianten) und Nahaufnahmen (Workbench).
  **UMBAU 2026-10 (Daecher, Dorfhaeuser, Varianten):**
  * DACH-FEHLER: `dach(axis="x")` vertauschte Laenge und Spannweite — das Dach eines 11 x 8
    Hauses war 8.8 lang und 11.8 breit, lag also QUER (vorn weit ueberhaengend, seitlich
    standen die Wandecken frei). Betraf 13 Daecher = fast jedes Dorfhaus. Dazu war der Giebel
    ein Dreieck in DACHFARBE aussen am Ueberstand, die Dachflaeche hauchduenn, und alle
    Kamine/Masten waren auf das falsche Dach gesetzt (schwebten bis 0.9 m darueber).
  * NEUES `dach()`: w/d = Masse des Baukoerpers in X/Y, axis = Firstrichtung. Die Platte ist
    ein GESCHLOSSENER Koerper (`add_koerper`: Wicklung per recalc + Vorzeichen des Volumens,
    nicht von Hand), laeuft durch die Wandkrone und endet UNTER ihr an der Traufe; sichtbare
    Staerke (0.24/0.30 HD), Walmdach mit zur Neigung passendem Ueberstand. GIEBEL in
    Wandfarbe BUENDIG in der Wandebene (Farbe = `wand_key`, den `box()` bei Baukoerpern
    >= 12 m2 merkt; `giebel=` ueberschreibt, auch als (links, rechts)). Die Platte liegt um die
    halbe Staerke hoeher als die Wandkrone — lief sie genau durch die Wandkante, flimmerte
    dort eine gepunktete Linie. Rueckgabe = Dachmasse fuer `gaube(info, u, seite)` (Giebel-
    gaube mit eigenem Dach und Fenster) und `kamin(info, u, lx)` (steht auf der Dachflaeche).
  * Weitere Bausteine: `tuer(vordach=)`, `fenster(laeden=, kasten=)` (Fensterlaeden in beiden
    Stufen, Blumenkasten HD), `sockel()` (HD), `feld(zweiseitig=True)` fuer frei stehende
    Flaechen (Muehlenfluegel, Fahnen, Schilder, Gelaender — einseitig verschwanden sie von
    hinten), `pultdach()` schliesst die Wand unter der Schraege (vorher klaffte ein Keil).
  * Dorf-/Stadthaeuser neu modelliert: Bauernhaus (Gauben, Laeden), Fachwerk (Giebel zur
    Strasse, vorkragendes OG, Fachwerk in BEIDEN Stufen), Kate (Reet-Walmdach 0.55 dick),
    Scheune (Torrahmen, Heuluken, Dachreiter, Bretterfugen HD), Stadthaus2 (Giebelhaus),
    Stadthaus3 (TREPPENGIEBEL), Reihenhaus (je Einheit Farbe/Tuer/Gaube/Kamin), Eckhaus,
    Gasthaus (Laube, Schild), Villa (Walmdach mit Gauben).
  * FARBVARIANTEN (`VARIANTEN`): Farbtausch je Materialschluessel (`Bau.tausch`), Export als
    `<Typ>_2`, `<Typ>_3`. CityBuilder ordnet sie beim Laden zu
    (`_varianten`) und waehlt je Bauplatz per Hash der Weltlage (`variante()`); die Plaene
    nennen weiter nur den Grundtyp. Beleg: `tools/_haus_varianten_check.gd`.
  * `pruefen()` am Ende des Baus: jede geschlossene Insel mit positivem Volumen.
  * HOCHHAEUSER UND INDUSTRIE (zweite Runde 2026-10) neu modelliert, HD-Details stehen jetzt
    in der Hausfunktion (`if b.hd:`) statt in getrennten `hd_*`-Extras:
    Wohnturm (Loggienachsen in Akzentfarbe, Fensterraster), Bueroturm (zwei verschraenkte
    GLASSCHEIBEN auf Steinsockel), Wolkenkratzer (Art Deco: senkrechte Fensterachsen = ein
    Quad je Achse, Gesimse, Kupferkrone), Plattenbau (Treppenhaus-Risalite, farbige
    Bruestungen), Hotel (Penthouse, Glasbruestungen), Krankenhaus (Helipad-Plattform, rotes
    Kreuz), Kaufhaus (Parkdeck mit Rampe), Parkhaus; Fabrik (Sheddach aus Glas + Blech —
    vorher war das ganze Dach ZIEGEL —, Verwaltung, Laderampe, frei stehender Schornstein),
    Kraftwerk (Kesselhaus, Turbinenhalle, rot-weisse Schornsteine, Kuehlturm als Hyperboloid
    mit dunklem Inneren, Foerderbruecke), Getreidesilo (Elevatorturm, Galerie), Hafenkran
    (Portalkran mit schraegem Ausleger), Funkturm (jetzt Fernsehturm: Schaft, Kanzel,
    Ringelmast), Wasserturm (Ziegelschaft), Tanklager (stehende Grosstanks), Stadion
    (Tribuenenringe, Kragdach LIEGT auf der Aussenwand — vorher schwebten Dachplatten).
    Neue Bausteine: `flachdach()` (Attika + Kies/Asphalt), `balken(p0, p1, b, h)` (Quader in
    beliebiger Richtung), `boden()` (waagrechte Flaeche — `feld` kann nur Waende: das "H" des
    Helipads stand vorher senkrecht), `ring()`, `ringel()`, `zyl(dreh=)` (eine Flaeche zeigt
    genau nach vorn), `_baender` (HD: Pfeilerstreifen ueber alle Geschosse = Fensterraster),
    `_geraete`, `_auto`. `gelaender()` mit zwei grossen Massen ist jetzt UMLAUFEND (vorher
    eine Platte: ueber dem Krankenhausdach schwebte ein 30 x 16 m Deckel).
    GLAS UND FENSTER glaenzen (Rauheit 0.2, Metall 0.25) und spiegeln im Spiel den Himmel;
    mit Metall 0.45 standen die Glastuerme fast schwarz da.
    Varianten auch fuer Wohnturm (3), Bueroturm, Plattenbau, Hotel (je 2) -> 63 Meshes.
    Hangar: Binder folgen dem Bogen (ragten vorher als gerade Balken aus dem Dach).
    VORSCHAU-FALLEN: Workbench-Schatten zerkratzen offene Flaechen (aus); nahe Clipebene mit
    dem Abstand mitfuehren, sonst flimmern Felder 4 cm vor der Wand (kein Modellfehler).
    `HAEUSER_BILDER=hd_hoch,hd_industrie,nah:Fabrik[:hinten]` waehlt die Bilder.
  * RESTLICHE BAUTEN (dritte Runde 2026-10): Werkstatt (Satteldach, zwei Rolltore, Schild,
    Buero; HD Paletten/Faesser/Lieferwagen), Hofsilo (Kuppeldach, zweiter Silo, Foerderrohr),
    Speicher (Rundbogen-Ladeluken, Windenerker mit Ladebalken, Fenster ringsum, Gauben),
    Kontrollturm (achteckiger Schaft, nach oben weitere GLASKANZEL, Betriebsgebaeude),
    Radarstation (Radomkugel, Parabolspiegel, echter Zaun statt loser Pfosten), Bunker
    (Grasdach, Panzerkuppel, Splitterschutzmauer), Burg (Torhaus mit Flankentuermen und
    Zugbruecke, Bergfried seitlich im Hof, Palas, Brunnen), Kirche (Spitzbogenfenster,
    Schalluken und Zifferblaetter auf drei Seiten, Eckfialen, Rosette, Sakristei), Kapelle,
    Rathaus (Arkaden, Balkon, Glockenstube, Gauben), Bahnhof (Mittelbau mit Giebel und Uhr,
    Bogenportale, Bahnsteigdach auf Stuetzen, zwei Gleise im Schotterbett), Windmuehle (runde
    Haube, vier Fluegel aus Rute + versetztem Gatter, Eingang als Vorbau — ein senkrechtes
    Tuerfeld schneidet die schraege Turmwand). Nicht angefasst: Stall, Wassermuehle,
    Lotsenhaus, Hangar (haben die Dach-/Binder-Korrekturen der ersten Runden).
    Bausteine dazu: `bogen()` (Rund-/Spitzbogenfeld als EIN Vieleck), `rundfeld()`
    (Zifferblatt, Rosette), `kuppel()` (Halbkugel bis Radomkugel, `von` < 0). `zinnen()` mit
    zwei grossen Massen ist jetzt ein KRANZ (vorher Balken quer ueber die Plattform).
    FALLE BEIM PATCHEN: Funktionen per "bis zur naechsten dreifachen Leerzeile" zu ersetzen
    frass die HAEUSER-Liste, weil nach `bunker` nur EINE Leerzeile stand — nach solchen
    Ersetzungen die Liste der `def`-Namen gegen den alten Stand vergleichen.
  * Zahlen jetzt: 63 Meshes, LOD 190 Tris im Schnitt, HD 883 (mit Gaerten).
  * **DESIGN-RUNDE (2026-10, "alle Haeuser noch besser"): Haeuser im Stil der Welt.**
    - HAUS-SHADER `shaders/haus.gdshader`: `CityBuilder._malen` tauscht beim Laden jedes
      importierte Standardmaterial gegen ein ShaderMaterial (Farbe, Rauheit, Metall
      uebernommen, je Quellmaterial eines). Licht = `weiches_licht` wie Gelaende und Baeume,
      dazu KUEHLE HIMMELSFUELLUNG (`fuellung` 0.26, EMISSION = Albedo x Blauton): vorher
      standen Schattenseiten fast schwarz da (Burgmauer, abgewandte Daecher). Glas/Fenster
      bekommen ein Sonnen-Glanzlicht.
      FALLE (eine Stunde gesucht): das Farb-Uniform hiess zuerst `farbe` — so heisst auch
      ein Parameter von `weiches_licht()` im Include. Kein Compilerfehler, aber bei den
      Haeusern kam KEIN Sonnenlicht mehr an: helle Waende fielen nicht auf (Umgebungslicht),
      Daecher und die Burg standen schwarz da. Uniforms in Shadern mit Include nie wie
      Parameter der eingebundenen Funktionen nennen (jetzt `haus_farbe`).
    - GEMALTER VERLAUF (`Bau._verlauf`): Vertexfarbe als Faktor — Waende unten dunkler
      (0.78) und nach oben heller, Daecher von der Traufe zum First heller, Glas unveraendert.
      glTF-Export mit `export_vertex_color='ACTIVE'`, der Shader multipliziert COLOR.rgb.
    - WEICHE RUNDUNGEN: `set_sharp_from_angle(40 Grad)` statt flacher Facetten — Tuerme,
      Silos, Kuppeln, Kuehlturm, Hallenbogen, Kegeldaecher sind rund. 40 Grad ist die Grenze:
      flache Dachfirste haben ab 43 Grad, darueber wuerde der First verschmiert.
    - FUNDAMENT: jeder Eckpunkt auf z = 0 wandert 1.6 m in den Boden (`FUNDAMENT`). Ein Haus
      steht auf der Gelaendehoehe seiner MITTE — am Hang schwebte die Talseite, und durch den
      offenen Boden sah man darunter durch.
    - GESCHWUNGENE TRAUFE (`Bau.schwung`, Satteldaecher der Dorf-/Stadthaeuser 0.55): Knick an
      der Wandlinie, der Ueberstand laeuft flacher aus; ueber den Waenden bleibt die
      Dachflaeche gleich (Gauben/Kamine rechnen unveraendert).
    - GARTEN UND HOF (nur Nahstufe — die Fernstufe ist der Kartengrundriss): `zaun`, `hecke`,
      `beet`, `waescheleine`, `schirm` (Biergarten), `laterne`, `brunnen`, `holzstapel`,
      `heuballen`. Bauernhaus mit Garten und Waescheleine, Kate mit Vorgarten und
      Ziehbrunnen, Scheune mit Koppel/Heuballen/Leiterwagen, Gasthaus mit Biergarten,
      Villa mit Park und Brunnen, Reihenhaus mit Vor- und Hintergaerten, Stadthaeuser mit
      Hofmauer und Laterne, Kirche mit Kirchhofmauer und Grabsteinen, Rathaus mit
      Marktbrunnen, Muehlgraben an der Wassermuehle, Boot am Lotsenhaus.
    - Sichtprobe: `tools/_haus_tafel.gd -- <ordner> [Typen]` (Haeuser mit dem Spiel-Shader
      in einer kleinen Szene, drei Blickwinkel — ohne die Welt zu laden; damit wurde der
      Shaderfehler in einer Minute eingekreist, den vier Welt-Renders nicht erklaerten).
- **GEBAEUDE IN DER WELT (`scripts/CityBuilder.gd`)**: die 42 Haeuser (+21 Farbvarianten) gehen als EIN glb
  (`models/world_buildings.glb`, aus `build_haeuser_blend.py` mitexportiert) ins Spiel;
  `CityBuilder` zieht daraus die Meshes und setzt sie **je Typ und Viertel als ein
  MultiMeshInstance3D** (ein Draw-Call pro Typ, wie die Baeume) — und zwar ZWEIMAL: die
  Nahstufe aus `world_buildings_hd.glb` mit `visibility_range_end = LOD_DIST (900 m)`, die
  Fernstufe mit `visibility_range_begin = LOD_DIST`. Beide teilen dieselben Transforms. Keine Kollision — genau
  wie die Landmarks-Bauten. (Dazu seit 2026-10 die Hafenstadt FREIHAFEN, eigener Abschnitt.) 12 Viertel / 180 Gebaeude: Grossstadt (Skyline + Blockrand,
  70), Industriehafen, Landdorf, Burgberg (eigenes Massiv + Flachzone y=78), Militaerposten
  an der FLAK-ZONE und Hangar/Tower/Radar an ALLEN 7 Flugplaetzen. Layouts sind
  deterministisch (feste RNG-Seeds), Positionen/Flachzonen stehen in `Main._setup_world`.
  Werkzeuge: `tools/_city_count.gd` (zaehlt headless, was wirklich gesetzt wurde),
  `tools/_city_render.gd` (Luftbilder je Viertel), `tools/_citylib_check.gd` (glb-Inhalt).
  DREI FALLEN, alle hier reingelaufen: (1) ein neues glb muss ERST importiert werden
  (`--headless --editor --import`), sonst liefert `load()` null und es wird stumm nichts
  gebaut — `--quit-after 4` reicht dafuer NICHT; (2) ein von Hand gesetztes `custom_aabb`
  am MultiMeshInstance3D cullt das ganze Viertel weg, wenn die Instanzen in Weltkoordinaten
  liegen, die Box aber am Node-Ursprung — MultiMesh leitet seine Bounds selbst aus den
  Instanzen ab, also weglassen; (3) Render-Tools MUESSEN das Flugzeug mitversetzen, sonst
  laesst `update_center(aircraft.pos)` den Chunk-Worker endlos bauen und verwerfen (Haenger).
  Die Flugplatzbauten sitzen NEBEN der Bahn (die laeuft im lokalen Z, 900 m) und werden mit
  `dreh = af.heading` mitgedreht.
- **Regenerieren:** Blender starten (`open -a Blender`, Port 9876 muss offen sein), dann
  das bpy-Bau+Export-Skript erneut laufen lassen; danach `Godot --headless --editor --import`.
  Neue/zusätzliche Teile bekommen automatisch ein Modell, sobald `models/<id>.glb` existiert.
- **MiG-21 (Hybrid-Ikone, Referenz-Qualitätspfad):** `mig21_front` (edler Vorderrumpf:
  Einlauf-Lippe, grüner Matt-Radom-Schockkonus, Pitot, Kanzel + Fairing, Panel-Linien) +
  `mig21_rear` (Heck aus einem Guss: Boattail, dunkler Düsenring+Innenkonus, Ventralflosse,
  Bremsschirm, RÜCKENSPINE — setzt EXAKT am gemessenen Endprofil des Front-Teils an:
  Halbbreite 0.115/Top 0.441, sonst Stufe/Z-Fighting) + **echte Blender-FLÜGEL-Teile**
  `mig21_wing` (beschnittenes 57°-Delta, dünnes 6-Punkt-Profil, Querruder-Linie, Zaun),
  `mig21_stab` (pitch), `mig21_fin` (yaw, Geometrie senkrecht +Y) — alle als normale
  Wing-Parts mit Aero-Feldern (is_wing/area/lift/control/stress_mult), glb ersetzt nur das
  Visual. LEKTION: Die prozeduralen Dreiecks-Flügel waren der Papierflieger-Look, nicht der
  Rumpf. Flügel-glb: Wurzel am Origin, Spannweite +X, Sehne z-zentriert (col_offset x=span/2).
  Front-glb-Origin liegt NICHT mittig (Ende bei z=0.35 lokal+pos!) — Stoß via
  `tools/_aabb_check.gd` (druckt Welt-AABB je Preset-Teil) verifizieren.
  Flugcheck ohne user://-Anfassen: `tools/_preset_fly.gd -- mig21` (Luftstart, 90°-Kurve).
- **F-4 / F-14 (Hybrid abgeschlossen):** Beide haben jetzt einen sculpteten Blender-
  Vorderrumpf aus einem Guss (Radom-Nase + Pitot + langes TANDEM-Kanzeldach):
  `f4_front` (tief, area-ruled, gedroopte Nase; Heck-Querschnitt 0.65×0.55 -> stoßbündig
  an `jet_body`) und `f14_front` (flach+breit; Heck blendet in den 1.7×-breiten
  Pancake-`jet_body`). Ersetzen je `*_nose` + `jet_cockpit` im Preset. Rest modular:
  `jet_body`, `jet_engine`/`f14_nacelle`, generische (jetzt gewölbte) Flügel, Anhedral-
  Stabilatoren, ein/zwei `v_stab`.
- **Generischer Flügel-Mesh (`_wing_mesh`) aufgewertet:** NACA-Wölbung (`_camber_y`, nur
  Auftriebsflügel, control=="") + elliptisch gerundete, leicht gepfeilte Spitze (kein
  Papier-Zipfel mehr) + 8 Stationen. Hebt ALLE Generik-Flügel gleichzeitig. Rein visuell —
  Aero/Pickbox kommen aus dem Teil-Dict. **Spitfire** hat ein eigenes Blender-Teil
  `spitfire_wing` (echte elliptische Planform, 6° V-Stellung).
- **Sternmotor `engine_radial` (ZWEI Varianten in EINEM glb):** aus `Downloads/Engine.blend` via
  `tools/build_engine_radial.py` (Regenerator; schreibt auch `tools/radial_profile.json`).
  Das glb trägt drei Geschwister-Knoten: **`Full`** (freistehende Gondel mit eigenem Heck),
  **`Half`** (vorne bis auf 0.000 deckungsgleich, hinten flach aufgeschnitten) und **`Prop`**.
  `PartCatalog.set_engine_half(vis, bool)` schaltet nur die SICHTBARKEIT um (kein Neubau, keine
  Verschiebung — Nasenebene beider Varianten ist identisch, in Blender nachgemessen).
  Wer umschaltet: `PartCatalog.rear_docked()` (Testpunkt knapp hinter der Schnittebene auf der
  Schubachse; trifft er die Box eines Rumpfteils = angedockt) — aufgerufen aus
  `BuildController._sync_engine_variants()` (in `_notify_changed`, deckt Setzen/Verschieben/
  Löschen/Undo/Laden ab) und `FlightController.build_from_design`.
  **ZWEI Boxen, das ist der Knackpunkt:** `col_size` (1.2×1.135×**0.639**, col_offset=0) ist die
  MONTAGE-Box Nase..Schnittebene — mit ihr rechnet die Snap-Mathematik; ihre Rückseite IST die
  Schnittebene. `solo_size`/`solo_offset` (1.206×1.135×**1.494**, off z=+0.427) ist die volle
  Gondel und wird NUR auf Klickkörper/Nachbarschaft gezogen, solange „Full“ sichtbar ist
  (`_part_box()` + `_apply_engine_pickbox()`, gesteuert übers Meta `engine_half`).
  Warum so: (a) Der generische Snap IGNORIERT `col_offset` (er setzt den Ursprung stumpf
  `col_size.z/2` von der Fläche weg) -> col_offset MUSS 0 bleiben, sonst versinkt der Motor beim
  Ziehen auf einen Rumpf. (b) Weil die Montage-Box hinten die Schnittebene ist, landet dabei die
  Schnittebene GRATIS bündig am Rumpf (gemessen: Spalt 0.00000) und `rear_docked` greift -> Half.
  (c) Wäre nur die Montage-Box da, hätte der sichtbare Heckkonus (57 % der Länge!) keinen
  Klickkörper — man könnte dort nichts andocken (genau der gemeldete Bug).
  Andocken selbst läuft NICHT über `_fuselage_fit` (dessen „längste Achse“-Heuristik hielte die
  1.2 breite / 0.639 lange Montage-Box für quer und dockte SEITLICH an), sondern über einen
  eigenen Zweig in `_compute_snap_for`, der immer koaxial an `engine_cut_z()` setzt — egal wo man
  den Motor trifft (die große Cowl reicht als Ziel, das macht das Ziehen tolerant).
  Querschnitt = `RADIAL_PROFILE` (24 Punkte, aus dem flachen 'Fuselage'-Blatt der Datei) ->
  andockende Segmente werden zu `fuselage_radial` (Shape `radial_tube`, palette-versteckt).
  Regressions-Harness: `tools/_dock_test.gd` (fährt den echten BuildController: beide
  Richtungen, Treffer auf Cowl-Seite/Heckkonus, Löschen -> zurück auf Full; Abschnitt 6:
  Cockpit-Rahmen).
  **COCKPIT-ANSCHLUSSRAHMEN (AUTO, pro Seite):** `cockpit_radial.glb` traegt ZWEI eingebaute
  Rahmen-Instanzen **`FrameF`/`FrameB`** (im Regenerator per 180-Grad-Z-Drehung ans
  Gegenende gestellt, Blender-y ±0.665 — bewusst NUR -bc-zentriert, die sx/sz-
  Profilkorrektur gilt dem roten Rumpf, der Rahmen ist schon masshaltig).
  `PartCatalog.set_cockpit_frames(vis, front, back)` schaltet die Sichtbarkeit;
  `PartCatalog.cockpit_side_docked` prueft je Ende einen Testpunkt 0.06 jenseits der
  Stirnflaeche (zaehlt Rumpfteile UND Antriebe/CAT_PROP — Sternmotor vor dem Cockpit
  verdeckt den Rahmen genauso wie ein Rumpf). Gerufen aus `_sync_engine_variants`
  (Editor, in `_notify_changed`) und `FlightController.build_from_design`. Das SEPARATE
  Palette-Teil `cockpit_radial_frame` (Metallrahmen als manueller Adapter) bleibt davon
  unberuehrt.
  **FALLEN (beide hier reingelaufen):** (1) Die Nase liegt in Engine.blend bei **−Y** -> 180° um Z
  statt der üblichen +90°. (2) Das Prop-Blatt nutzt eine **prozedurale** Wave-Texture+Color-Ramp —
  glTF exportiert das NICHT (Blatt käme flach weiß); das Skript mittelt die Color-Ramp zu einem
  flachen Holzton. (3) `engine_half` trägt `.001`-Material-Duplikate — erst umhängen, DANN die
  Originale umbenennen (sonst findet der Namens-Lookup sie nicht mehr).
  Anders als beim Reto-Motor braucht der Prop **keinen** Node-Fix: nach JEDEM Transformschritt
  `transform_apply` -> alle glTF-Knoten kommen mit Identität an (in Godot nachgemessen).
- **Raketen (Blender, detailliert):** `missile` (Sidewinder: IR-Glas-Suchkopf, Canards,
  Heckflossen mit Rollerons, Kabelkanal), `missile_heavy` (Sparrow: Radom, Mittelflügel,
  Steuerflossen), `rocket` (Hydra: Ogive, Heckflossen). Material `body` lackierbar,
  `glass`/`radome`/`dark` bleiben.

## Modi, Geld & Upgrades (`scripts/GameState.gd`)
- **GameState** (Node, in Main als `game` erzeugt + `load_state()`): hält `mode`
  (NONE/SANDBOX/SURVIVAL), `money`, `unlocked` (Teil-IDs), `upgrades` (thrust/wing/light).
  Persistiert nach `user://aviassembly_progress.json`. Signal `changed`.
- **Modus-Auswahl** beim ersten Start (Overlay `_show_mode_select`, falls `mode==NONE`):
  **Sandbox** = alles frei (`start_mode` unlockt alle, money ∞); **Survival** = Starter-Teile
  (`STARTER`) + `START_MONEY=2200`.
- **SURVIVAL-STARTSPERRE** (`Main._ungekaufte_teile`, geprueft in `_set_mode`): geflogen wird
  nur, was gekauft ist. Vorlagen/Sandbox-Slots darf man laden und ansehen, der Start meldet
  „Noch nicht gekauft: …". Es zaehlen NUR Palettenteile (`PartCatalog.in_palette`) —
  versteckte Auto-Varianten (fuselage_transport/_radial, C-130-Ringe) sind nicht kaufbar und
  duerfen nie sperren. Beleg: `tools/_survival_check.gd`.
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
- **Persistenz Design** (`_design_data`/`_load_design_from`): JEDER Schluessel aus
  `get_design()` muss dort stehen — inkl. **`root`** (fehlte lange: `_ensure_root` riet nach
  jedem Neustart die Wurzel). `tools/_datei_rundlauf.gd` vergleicht jeden Schluessel ueber
  Datei-Speichern/Laden fuer alle Vorlagen; bei neuen Metas dort zuerst nachsehen.
- **ERSTSTART-FLUGZEUG** (`Main._default_design`): muss `floating_count()==0` haben, sonst ist
  der allererste Start blockiert (war so: Hauptraeder 28 cm unter der Flaeche bei 24 cm
  Toleranz). `_rundflug_alle` fliegt es als erstes mit und meldet frei haengende Teile.

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
  **GELAENDETREFFER** (`_gelaende_treffer`): Strahl ueber die Strecke des Physikschritts auf
  Ebene 1 (Gelaende, Bahnen, Bauwerke, Wasserebene) — wie `Missile.gd`. Vorher fielen Bomben
  durch jeden Huegel und zuendeten erst bei y<=0,4. Das eigene Flugzeug liegt auf Ebene 4
  (`AIRCRAFT_LAYER`) und wird nie getroffen. **SPRENGRADIUS** Bombe 22 / Rakete 6 /
  Drop-Rakete 9 m, voller Schaden im `hit_radius` des Ziels, dann linear; Bombe 15 Schaden
  (raeumt eine SAM-Stellung mit 14 HP). Beleg: `tools/_bodenkampf_check.gd`.
- **BODENZIELE:** `SamSite` (14 HP) und **`FlakGun` (8 HP, seit dieser Runde zerstoerbar)**
  stehen in der Gruppe `"target"` (Metas `hit_radius`/`ir_signatur`/`radar_signatur`), Signal
  `zerstoert(reward,pos)` → Main `_on_sam_zerstoert`/`_on_flak_zerstoert` (Geld, KEIN
  Wellenfortschritt). Sie haengen unter `fly_world`, NICHT unter `targets_root`.
- **`scripts/Target.gd`** (`class_name Target`, Gruppe `"target"`): Luftballon (1 HP, +120)
  oder Luftschiff (4 HP, +600). Schwebt/driftet, `hit(dmg)` mit `_dead`-Flag (kein
  Doppel-Reward), `_die()` → Signal `killed(reward,pos)` + Partikel. Main spawnt sie in
  `targets_root` (in `fly_world`), vor der Startbahn (`_rand_target_pos`); Abschuss →
  `game.add_money` + Toast; Nachschub-Ballon nach 7 s.
- **Feuern** (`FlightController`): sammelt `weapons` = `[{type, off, cd}]` beim Bauen
  (jede Waffe hat **eigenen Cooldown** `cd`, pro Frame heruntergezählt).
  **WAFFENGRUPPEN (SimplePlanes-Stil):** `WGROUPS` = Bordkanonen/Raketen/Lenkwaffen/Bomben;
  `_rebuild_weapon_groups()` beim Bau sammelt die vorhandenen, `weapon_sel` = Auswahl
  (**1–4** direkt, **X** zyklisch — V ist jetzt der Zielzoom; nur im Flug, der Hangar behält 1–4 als Ansichten, weil
  dort `set_process_unhandled_input(false)`). **Leertaste / Linksklick** feuert NUR die
  gewählte Gruppe — **Kanonen als Dauerfeuer solange gehalten, Raketen/Lenkwaffen/Bomben
  als EINZELSCHUSS pro Klick** (Flanken-Erkennung `_fire_held`; `_fire_primary(types,
  single)` bzw. `_drop_bomb(single)` returnen nach dem ersten Abschuss → naechster Mount
  beim naechsten Klick). Die Minigun spint nur auf, wenn die Kanonen-Gruppe gewählt ist.
  `_emit_hud` liefert `wgroups` (Label + Restmunition, Waffen auf gebrochenen Teilen zählen
  nicht) + `wsel` → FlightHud-Waffenleiste unten Mitte. `_fire_primary` filtert auf die
  Gruppe (`match w["type"]` für gun/rocket/salvo/missile/missile_heavy; setzt bei
  Lenkraketen `guided/turn/seek_range` + jeweiligen `cd`), **B** → eine Bombe pro Druck
  (`_bomb_held`-Flanke, geht immer, unabhängig von der Auswahl). Die Flug-Hinweiszeile
  unten wurde auf Wunsch ENTFERNT (Steuerung steht im README); Waffenleiste sitzt auf der
  46-px-Grundlinie der Speed-/Hoehen-Boxen. `_spawn`
  gibt das `Projectile` zurück. Spawnt in `world_root` (= `targets_root`, von Main gesetzt;
  `_fire_primary` guardet `world_root==null`). Mündung = `aircraft.global_transform * off`,
  Vorwärts = `-basis.z`. Fadenkreuz im Flug-HUD.
  -> Abschüsse sind die Survival-Einnahmequelle.

## Status & nächste Schritte
- **Git:** Branch `main`, Remote `origin` = `git@github.com:KonstiTheProgrammer/aviasembly.git`
  (SSH). `.godot/` ignoriert.
- **Ideen für später:** Lande-Score/Punkte, Cockpit-Kamera, Strömungslinien die sich
  am Modell verbiegen, Rumpf/Leitwerk auch abreißbar, Funken/Rauch, Missionen/Parcours,
  Teile freischalten.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships. It COVERS THE GDSCRIPT GAME CODE (classes, functions, signals, inheritance, call graph, scene instantiation) plus the Python tools.

WICHTIG — zwei graphify-Installationen (GDScript-Grund):
- Der Extraktor MUSS der Godot-Fork sein (`graphifyy 0.5.0+godot1`, via `tree-sitter-language-pack`), sonst werden ALLE `.gd`-Dateien als "not classified" übersprungen. Der Fork liegt in einem eigenen venv: `C:\Users\Konst\graphify-godot\.venv\Scripts\python.exe`.
- Zum LESEN/Abfragen ist die globale `graphify` (0.9.22) ok — sie liest den Fork-Graphen problemlos (verifiziert: god-nodes/query liefern die .gd-Symbole mit Quellorten).

Node-IDs sind pro Datei qualifiziert (`aircraftbody_toy_explosion`) — gleichnamige Funktionen in
verschiedenen Dateien sind SEPARATE Knoten (gemessen: `_process` = 27 Knoten, `_ready` = 9), also
KEINE Namenskollision trotz der pre-#1504-Warnung (die betrifft nur gleichnamige DATEIEN in
verschiedenen Ordnern — hat dieses Projekt nicht).

DOKU-SCHICHT (semantisch, LLM war der Host-Agent — KEIN API-Key noetig/verwendet): CLAUDE.md +
README.md sind als ~140 Konzept-/Rationale-Knoten eingemerged, 393 Kanten treffen echte Code-Knoten.
Das WARUM (GESCHICHTE/FALLE/LEKTION-Abschnitte) haengt als `rationale`-Attribut an den Konzept-Knoten
— `graphify explain "<Konzept>"` liefert Konzept + Code-Verbindungen, das Rationale steht im
graph.json-Knoten. Die Extraktion liegt GETRACKT in `tools/semantic_docs_chunk.json` (Graph damit
komplett offline reproduzierbar); neu extrahieren nur noetig, wenn sich CLAUDE.md/README stark
aendern -> Subagent nach Muster in tools/graph_merge_semantic.py-Docstring, IDs MUESSEN aus
`graphify-out/.existing_nodes.tsv` kommen (Skill-Spec-ID-Schema passt NICHT zum Fork -> Geisterknoten).

Rules:
- Für Orientierung/Navigation zuerst `graphify-out/COMMUNITIES.md` lesen — ~15 Cluster mit
  Klartext-Thema + zentralen Symbolen; Doku-Konzepte clustern MIT ihrem Code (z. B. Flugmodell-
  Rationale bei _integrate_forces/recompute_aero). Löst die `Community N`-Nummern auf.
- For codebase questions, run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, refresh with `tools/graph-update.ps1` — volle Pipeline, kein LLM:
  [1] AST (Fork, tools/graph_ast_extract.py) -> [2] Merge Code+Doku (tools/graph_merge_semantic.py:
  haltbar-Regrade Doku->Code auf INFERRED, Stub-Knoten fuer Shader/Fonts/bpy, TSV-Refresh) ->
  [3] Labeling (tools/graph_label.py: COMMUNITIES.md + Report-Namen + graph.html) ->
  [4] Testsuite (tools/graph_check.py, 12 Pruefungen, Exit != 0 bei rot).
  NIE `graphify update .` mit der globalen 0.9.22 — droppt GDScript UND (watch.py-Filter) alle
  EXTRACTED-Doku->Code-Kanten.
