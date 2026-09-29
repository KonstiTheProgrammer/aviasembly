# ✈️ Aviassembly — 3D Plane Builder (Godot 4.6)

Baue dein eigenes Flugzeug aus Modulen und fliege es! Wie du baust, **bestimmt
wie es fliegt** – echte (arcade-taugliche) Aerodynamik.

Öffne das Projekt in Godot 4.6 und drücke **▶ (F5)**. Es startet direkt im Hangar
mit einem fertigen Beispielflugzeug.

---

## 🎮 Steuerung

### Hangar (Bau-Modus) — blauer Blueprint-Raum
Der Bau passiert in einem blauen 3D-Blueprint-Raster. Du baust per **Drag & Snap**.

| Eingabe | Aktion |
|---|---|
| **Teil im Menü packen → in den Bauraum ziehen & loslassen** | Neues Teil setzen (Drag&Drop aus dem Inventar, rastet flächenbündig an) |
| **Vorhandenes Teil anklicken** | **Auswählen** → Blender-artiges Gizmo + Panel |
| **G / R / S** (oder Panel-Buttons) | Werkzeug: **Bewegen** (Achsen-Pfeile) / **Drehen** (Teil ziehen) / **Skalieren** (Würfel) |
| **Pfeile / Würfel ziehen** | Entlang Achse verschieben bzw. Achse strecken · **Körper ziehen** = frei verschieben/drehen |
| **Linke Maus auf leeren Raum ziehen** | Ums Flugzeug drehen (Blueprint-Orbit) |
| **Rechte Maus ziehen** | Ebenfalls Orbit |
| **Mausrad** | Zoom |
| **Mittlere Maus ziehen** | Ansicht verschieben |
| **✋ Bewegen/Greifen** / **🧹 Abriss** (Buttons) | Werkzeug ablegen / Abriss umschalten |
| **🎨 Farbe wählen → Teil klicken** | Teil lackieren (Farbe wird gespeichert) |
| **Farbe mischen** (Werkzeuge-Reiter) | beliebige Farbe über Farbrad / RGB / Hex |
| **Pipette** bzw. **P** | Farbe von einem vorhandenen Teil aufnehmen |
| **↶ Undo / ↷ Redo** bzw. **Strg+Z / Strg+Y** | Schritt zurück / vor |
| **Strg+C / Strg+V** | Teil kopieren / einfügen (mit Form: Verjüngung, Enden-Versatz, Rundung, Beinlänge) |
| **Strg+D** | Teil sofort duplizieren |
| **🎯 Ansicht** bzw. **F** | Kamera zentrieren |
| **X** | Teil unter der Maus löschen |
| **R** | Teil drehen (90°) |
| **M** | Symmetrie an/aus |
| **ESC** | aktuelles Ziehen abbrechen / Werkzeug ablegen |
| **Tab / ▶-Button** | Testflug starten |

Tipp: **Symmetrie** ist standardmäßig an – ein Drag baut beide Seiten (z. B. linke
und rechte Tragfläche gleichzeitig). Achte auf die Marker: **● gelb = Schwerpunkt**,
**● blau = Auftriebspunkt**. Liegt der Auftriebspunkt *hinter* dem Schwerpunkt, ist
das Flugzeug längsstabil.

### Flug-Modus
| Eingabe | Aktion |
|---|---|
| **Maus / Touchpad** | **Umschauen** — Kamera frei ums Flugzeug schwenken (schwenkt bei Ruhe zurück) |
| **M** | **KARTE** öffnen/schließen (auch **Esc**) — große Reliefkarte mit Höhenlinien, Flüssen, Straßen und Gebäuden, Bahnen im echten Kurs, Flugabwehr-Reichweiten, Zielen, deiner Flugspur und Planquadraten. **Mausrad/Pinch** = stufenlos zum Cursor zoomen (beim Hineinzoomen werden scharfe Detailkacheln nachgeladen), **Ziehen** = verschieben, **Klick** = Wegpunkt setzen (erscheint im HUD, auch Klick auf einen Flugplatz in der Seitenleiste), **Rechtsklick** = Wegpunkt löschen, **ZU MIR** = zurück zum Flugzeug |
| **N** | **Maus-/Tastatur-Flug** umschalten (Maus-Flug ist **Standard** — siehe unten) |
| **V halten** | **Zielzoom** (~2,8×, wie in War Thunder): FOV verengt sich und die Kamera geht im gleichen Verhältnis zurück, dadurch werden ferne Ziele größer statt nur das eigene Flugzeug; die Maus wird dabei ruhiger gestellt |
| **1–4 / X** | **Waffengruppe** wählen / durchschalten (Leiste unten Mitte) |
| **J** | **Arcade-Lenkung** an/aus (super-smooth, schnappt sofort aufs Ziel; aktiviert Maus-Flug) |
| **Shift / Strg** | Schub hoch / runter — **unter 0 % = bremsen** (Luft- & Radbremse) |
| **S / ↓** und **W / ↑** | Nase hoch / runter |
| **A / ←** und **D / →** | rollen — **A = rechts, D = links** (vertauscht) · **lange halten = 🔄 Barrel Roll** |
| **Q / E** | nach rechts / links gieren (Seitenleitwerk) — **Z** = auch links |
| **C halten** | **Free-Look**: Kamera frei ums Flugzeug schwenken, ohne zu lenken |
| **G** | Einziehfahrwerk ein-/ausfahren |
| **F** | Landeklappen: Aus → Start → Landung |
| **H** | **Bombenschacht** auf/zu — Bomben IM Schacht fallen nur bei offener Klappe, offene Klappen bremsen |
| **K / L** | **Fackeln / Düppel** werfen (gegen Wärme- bzw. Radar-Lenkwaffen) |
| **O** | **G-Schutz** an/aus (an = Flügel können nicht abreißen; war früher **H**) |
| **I** | Steuerung umkehren (alles in die andere Richtung) |
| **T** | Assist an/aus (an = ruhig, aus = direkter „Pro"-Modus) |
| **Enter** | Reset auf die Startbahn (repariert auch gebrochenes Fahrwerk) |
| **Tab** | zurück in den Hangar |

**🖱 Maus-Flug (Taste N) — wie in War Thunder:** Die Maus zeigt frei in eine **Richtung in
der Welt** — und das Flugzeug **dreht seine Nase genau dorthin**. Schaust du nach links,
fliegt es nach links; schaust du nach hinten, dreht es sich **komplett herum** (volle 360°,
auch steil hoch/runter). Ein **grüner Zielmarker** ⊕ zeigt, wohin du zielst, ein **gelber
Nasenmarker** ◇ zeigt, wohin die Nase gerade weist — decken sie sich, fliegst du genau aufs
Ziel. Kurven (Rollen + Ziehen) werden automatisch koordiniert. Tastatur (W/S/A/D/Q/E) wirkt
zusätzlich. Nochmal **N** schaltet zurück auf freies Umschauen.

**🎮 Arcade-Lenkung (Taste J):** Für maximal smoothes, direktes Handling. Die Nase folgt der
Maus **butterweich und sofort** (schnappt in ~0,3–0,4 s auf jede Richtung, auch 180°),
ohne Stall/Strömungsabriss und ohne G-Grenze (keine Flügelbrüche). Ideal, wenn du einfach
fix dahin fliegen willst, wo du hinschaust. **J** schaltet wieder auf die physikalische
Maus-Steuerung zurück.

**Landung & Schaden:** Sinkrate beim Aufsetzen zählt — sanft = „Saubere Landung ✓",
zu schnell (>3 m/s) = „Harte Landung ⚠", sehr hart (>7 m/s) = **Fahrwerk bricht**
(Bauchlandung, viel Widerstand). Reset (Enter) repariert.

**Flügel-Belastung:** Jeder Flügel trägt nur eine begrenzte Last. Zu enge/schnelle
Manöver erzeugen zu viel G → **die Flügel reißen physisch ab** und trudeln als
Trümmer weg — **mitsamt allem, was darauf montiert ist** (z. B. Triebwerke, Winglets).
Im Hangar zeigt „Max. Flügellast" an, bis zu wie viel g die Konstruktion hält.
**Reset (Enter)** baut das Flugzeug wieder komplett auf.

**Flügel-Orientierung:** Ein flach montierter Flügel erzeugt **Auftrieb**. Kippst du
ihn mit **R** (bis senkrecht), wird er zur **Rollsteuerung** und erzeugt keinen
Auftrieb mehr — so baust du Winglets/Querruder-Flächen.

**Luftwiderstand & Windkanal:** Der Widerstand wird aus der Bauform berechnet
(Stirnflächen + Form, Stat „cW·A") und bremst das Flugzeug. Button
**„🌬 Windkanal-Ansicht"** → **Pro-Teil-Druckwiderstands-Heatmap mit Verdeckung**:
nur windzugewandte Flächen färben sich (grün→gelb→rot), Teile im **Windschatten**
hinter anderen bleiben grau — dazu Strömungslinien und ein „Hotspot"-Hinweis
auf das widerstandsstärkste Teil.

**Abheben:** Vollgas (Shift halten), auf der Bahn beschleunigen, ab ~120 km/h sanft
ziehen (S) → das Flugzeug rotiert und steigt. Die Flügel haben einen Einstellwinkel,
es hebt fast von allein ab, sobald genug Tempo da ist. Im Steigflug baut sich
(realistisch) Geschwindigkeit ab — nicht zu steil ziehen, sonst **Stall**.

---

## 🗺️ Die Welt

Die Welt ist **168 × 168 km** groß. Die **Hauptinsel** trägt im Norden die vergletscherte
**Nordkette** (bis 2650 m) mit dem Hochtal und dem Felsenhorst ADLERHORST, im Tiefland eine
Heckenlandschaft aus Feldern und Wäldern, bewaldete Bergländer, drei große Golfe, das
Sturmkap mit seinem Fjord, den Vulkan und die Großstadt. Dazu drei Landmassen mit eigenem
Klima, durch Meeresstraßen getrennt (mit kleinen Trittstein-Inseln dazwischen):

| Region | Lage | Biome & Landschaft | Flugplatz / Ort |
|---|---|---|---|
| **Nordland** | ~55 km nördlich | Tundra, Taiga mit Schneetannen, **Gletscherkette** mit Pässen, gewundener **Eisfjord**, **Seenplatte**, Kiesstrände, kaltes dunkles Meer | EISHAFEN / Eisbucht |
| **Südland** | ~55 km südlich | Dschungel (Urwaldriesen, Palmen, Baumfarne), Tropenwiesen, **Kegelkarst**-Türme, **Mangrovenlagune**, Korallensand, türkises Wasser | PALMENBUCHT / Palmdorf |
| **Westland** | ~60 km westlich | Savanne mit Akazien, rote **Tafelberge** mit Sandsteinbändern, Zeugenberge, **Großer Canyon** mit Kakteen | TAFELBERG / Minenstadt |

Alle Regionen stehen auf der Karte (**M**); ein Klick auf einen Flugplatz setzt dort einen Wegpunkt.

**Wolken zum Durchfliegen** (alle auf der Karte):
- **Wolkentore** gleich hinter HEIMAT — sieben Ringe, das nächste Tor leuchtet golden;
  wer alle in einem Flug schafft, bekommt im Survival eine Prämie.
- **Wolkenschlucht** vor der Ostküste — ein Gang zwischen zwei Wolkenwänden, mit Tunnelbögen.
- **Gewitterzelle** weit draußen im Osten — 5 km hoher Turm mit Amboss, Blitzen und Regen,
  heftiger Turbulenz, Aufwind im Kern und Fallwind unter der Basis.
- **Nebelmeer** in der Westbucht — eine geschlossene Wolkendecke zum Drüberhinstreichen.
Beim Eintauchen rauschen Wolkenfetzen vorbei; je höher man steigt, desto dunkler wird der
Himmel, und hohe Zirren ziehen darüber.

Das **Meer reicht bis zum Horizont**: türkise Untiefen, durch die der Sand scheint,
Brandungslinien, die auf die Strände zulaufen, Schaumkronen auf offener See, ein
Glitzerpfad unter der Sonne und ferne Küsten als Silhouette im Dunst.

## 🧩 Bauteile

- **Rumpf:** Cockpit (Basis), modernes Transport-Cockpit, B-29-Glasnase,
  Rumpfsegmente, Nasen-/Heckkonus, Treibstofftank ·
  Rotes-Baron-Cockpit mit separat ansteckbarem, genietetem Metallrahmen
- **Tragflächen:** Gerade · Trapez · Pfeil · Delta · Stummel · Segler (lang) · Canard · Winglet
- **Leitwerk & Steuerung:** Höhenleitwerk (Pitch), Seitenleitwerk (Yaw), Querruder (Roll), kleines Höhenruder
- **Antrieb:** Propeller, großer Propeller, Düsentriebwerk, **eckiges Düsentriebwerk** (2D-Düse),
  Hilfstriebwerk, **Raketenantrieb** mit Turbopumpen und kupfergekühlter Düsenglocke
- **Fahrwerk (4 Varianten mit Traglast):** Leicht (~450 kg) · Standard (~850 kg) ·
  Schwer (~1750 kg) · **Einziehfahrwerk (~1050 kg, Taste G)**
- **Bewaffnung (feuerbar!):** Bordkanone (Schnellfeuer) · **Ungelenkte Rakete** (fliegt
  geradeaus) · **Raketenwerfer** (3er-Salve) · **Zielsuchrakete** (Heat-Seeker) ·
  **Schwere Lenkrakete** (große Reichweite, viel Schaden) · Bombe (Freifall, **Taste B**) —
  gefeuert wird per **Leertaste** oder **linker Maustaste** — und zwar die unten in der
  Mitte **ausgewählte Waffengruppe** (Auswahl: **1–4** direkt, **X** durchschalten)

*Mit `tools/build_jet.gd` gibt's einen vorgebauten zweimotorigen Delta-Canard-Jet
(zwei eckige Triebwerke) im Speicherstand.*

## 🎈 Luftkampf

Am Himmel schweben **Luftballons** und **Luftschiffe** (Zeppeline) zum Abschießen.
Bau Waffen an dein Flugzeug, ziel mit dem Fadenkreuz und feuere:

- Unten in der Bildmitte sitzt die **Waffenwahl-Leiste** (eine Pille je Gruppe:
  Bordkanonen · Raketen · Lenkwaffen · Bomben, mit Restmunition). **1–4** wählt die
  Gruppe direkt, **X** schaltet durch.
- **Leertaste / linke Maustaste** — feuert die **ausgewählte** Gruppe: Kanonen als
  **Dauerfeuer** (halten), Raketen/Lenkwaffen/Bomben als **Einzelschuss pro Klick**
  (jeder Klick löst den nächsten bereiten Mount aus). **Heat-Seeker fliegen erst geradeaus
  und kurven erst dann aufs Ziel, wenn eines in ihre Nähe kommt** — also vorher grob zielen.
- **Taste B** — eine Bombe pro Druck (geht immer, egal welche Gruppe gewählt ist;
  Bomben im geschlossenen Schacht erst nach **H**)

Jeder Abschuss gibt **Geld** (Ballon +120, Luftschiff +600) → so verdienst du im Survival.

**Bodenziele:** Die **Flak-Geschütze** und **Raketenstellungen (SAM)** schießen zurück —
und lassen sich zerstören (Flak +200, SAM +300/+450). Geschosse schlagen im Gelände ein,
**Bomben wirken im Umkreis** (~22 m): ein Treffer in die Stellung räumt eine SAM-Stellung,
daneben braucht es zwei. Lenkwaffen können auch Bodenstellungen aufschalten.
Abgeschossene Ballons werden nach kurzer Zeit durch neue ersetzt.

Mehr/größere **Steuerflächen** → mehr Wendigkeit. Mehr **Flügelfläche** → mehr
Auftrieb (langsameres Abheben). Mehr **Schub** → bessere Beschleunigung.

**Fahrwerk-Traglast:** Die Summe der Fahrwerks-Traglasten muss das Gesamtgewicht
tragen. Ist das Flugzeug zu schwer, **bricht das Fahrwerk zusammen** (Anzeige im
Hangar bei „Fahrwerk-Last" und im Flug-HUD als „KOLLABIERT"). Das **Einziehfahrwerk**
fährt im Flug mit **G** ein → weniger Widerstand, höhere Geschwindigkeit.

---

## 🛠️ Technik

**Welt, UI, Flügel und Terrain sind prozedural** erzeugt; die **Bauteil-Modelle**
(Rumpf, Kanzeln, Triebwerke, Fahrwerke, Raketen …) sind in **Blender** modelliert und
liegen als glTF in `res://models/*.glb` — fehlt ein Modell, greift automatisch der
prozedurale Fallback.

```
project.godot          Projektkonfiguration (Forward+)
scenes/Main.tscn        Hauptszene (nur Wurzelknoten + Main.gd)
scripts/
  Main.gd               Welt, Licht, Himmel, Modus-Umschaltung, UI/HUD, Speichern/Laden
  PartCatalog.gd        Alle Bauteile + glTF-Anbindung + prozedurale Mesh-/Material-Erzeugung
  BuildController.gd    Hangar: Orbit-Kamera, flächenbündiges Snapping, Gizmos, Symmetrie, Windkanal
  FlightController.gd   Baut den Flieger aus dem Design, Steuerung/Maus-Flug, Verfolgerkamera, Waffen
  AircraftBody.gd       Der fliegende RigidBody: Aerodynamik, Schadensmodell (Flügelbruch, Fahrwerk)
  TerrainWorld.gd       Chunk-Terrain mit Biomen, Flüssen, Seen und Flora (Worker-Thread-Streaming)
  GameState.gd          Spielmodi, Geld, Freischaltungen, Upgrades (Persistenz)
  Projectile.gd/Target.gd/FlakGun.gd   Geschosse, Ziele, Flak-Zone
  Missile.gd/SamSite.gd/Countermeasure.gd   Lenkwaffen, Raketenstellungen, Fackeln/Düppel
tools/
  phys_test.gd          Headless-Physiktest (zum Nachtunen): Godot --headless --path . --script res://tools/phys_test.gd
  _rundflug_alle.gd     Smoketest: jede Vorlage starten, fliegen, schießen, zurück in den Hangar
  _undo_check.gd, _datei_rundlauf.gd, _survival_check.gd, _bodenkampf_check.gd,
  _lenkwaffen_start.gd  Regressionstests für Verlauf, Speichern, Survival, Bodenkampf, Lenkwaffen
                        (Tests, die Main laden, mit HOME=/tmp/avi_home starten — sonst
                        überschreibt Main den echten Autosave)
  graph-update.ps1      Wissensgraph des Codes aktualisieren (graphify, siehe graphify-out/)
```

**Flugmodell (wissenschaftlich, aber spielbar):** Gebündelte Koeffizienten-Aufbaumethode
wie in vielen Flugsimulationen — stabil bei 60 Hz, trotzdem physikalisch fundiert:

- **Auftrieb:** endliche-Flügel-Kurve `Cl = lerp(Cl_α·α, sin 2α, σ)` mit `Cl_α = 2π·AR/(AR+2)`
  und realem **Stall** (Übergang zur Plattenströmung bei ~15.5°)
- **Widerstand:** `Cd = Cd0 + Cl²/(π·AR·e)` — Parasitär- + **induzierter Widerstand**
  (hohe Streckung/Segler-Flügel sind effizienter und gleiten weiter)
- **Schub:** Propellerschub fällt mit der Geschwindigkeit, Jet bleibt konstant
- **Luftdichte** nimmt mit der Höhe ab (`ρ = ρ₀·e^(−h/8500)`)
- **Statische Stabilität** (Nase folgt der Anströmung) skaliert mit der Leitwerksfläche
- **G-Kraft** wird aus der resultierenden Kraft berechnet und im HUD angezeigt

Die Steuerung sind **direkte Steuerflächen** (SimplePlanes-Gefühl): Eingabe = Ausschlag,
Autorität wächst mit dem Staudruck (langsam teigig, schnell knackig). **Kein**
Lage-Autopilot und **kein** Auto-Ausnivellieren — eine mit A/D gesetzte Querlage
bleibt stehen. Taste **T** (Assist) erhöht nur die Nick-/Gier-**Dämpfung** (ruhiger),
**T aus** = roh/direkt. Rollen ist immer knackig.

**Was beim Bauen zählt:** Flügelfläche (Auftrieb & Abrissgeschwindigkeit), Streckung
(Gleitleistung/Widerstand), Leitwerksfläche (Stabilität & Steuerautorität), Schub
(Beschleunigung/Steigen) und der Schwerpunkt (im Hangar als Marker sichtbar).

Speicherstand: `user://aircraft_design.json` (Buttons **Speichern/Laden** im Hangar).

---

## 🎮 Spielmodi, Geld & Upgrades

Beim ersten Start wählst du einen **Modus**:

- **🧰 Sandbox** — alle Teile frei, unbegrenzt bauen & fliegen, kein Geld-Stress.
- **🪖 Survival** — du startest mit **🪙 2200** und nur Basis-Teilen. **Kaufe** weitere
  Teile (Schloss-Symbol + Preis in der Palette) und **upgrade** dein Flugzeug
  (Triebwerks-Tuning, verstärkte Flügel, Leichtbau). Vorlagen und gespeicherte Flugzeuge
  darfst du laden und ansehen — **starten** geht aber erst, wenn alle Teile gekauft sind.
  Geld gibt es für Abschüsse, Combos und jede überstandene **Welle**.

Fortschritt (Geld, Freischaltungen, Upgrades) wird in
`user://aviassembly_progress.json` gespeichert.

---

## 💡 Ideen-Roadmap (noch nicht eingebaut)

- 🎯 Missionen & Parcours (Ringe durchfliegen, Landeherausforderungen, Zeitrennen)
- 🪙 Münzen sammeln → neue Teile / Lackierungen freischalten
- 💥 Landungsbewertung/-Score, mehr Crash-Effekte
- 🌦️ Wind, Turbulenzen, Wetter, Tag/Nacht
- 🌊 Schwimmer & Wasserung, Träger-Starts
- 🎨 Lackier-Editor, Foto-Modus, Replays
- 🕹️ Gamepad-Support, mehr Kamera-Modi (Cockpit-Sicht)
- 🧰 Mehr Teile: Klappen, Luftbremsen
- 👥 Geteilte Designs / Bestenlisten

Viel Spaß beim Bauen und Fliegen! 🛩️
