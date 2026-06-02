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
| **Teil im Menü wählen → in den Raum ziehen & loslassen** | Neues Teil setzen (rastet flächenbündig an) |
| **Vorhandenes Teil anklicken** (kein Menü-Teil gewählt) | **Auswählen** → Griffe + Panel: skalieren, drehen, löschen |
| **Ausgewähltes Teil am Körper ziehen** | Verschieben · **farbige Griffe ziehen** = strecken (Breite/Höhe/Länge) |
| **Linke Maus auf leeren Raum ziehen** | Ums Flugzeug drehen (Blueprint-Orbit) |
| **Rechte Maus ziehen** | Ebenfalls Orbit |
| **Mausrad** | Zoom |
| **Mittlere Maus ziehen** | Ansicht verschieben |
| **✦ Auswählen/Bewegen** / **🧹 Abriss** (Buttons) | Zum Bearbeiten zurück / Abriss umschalten |
| **🎨 Farbe wählen → Teil klicken** | Teil lackieren (Farbe wird gespeichert) |
| **↶ Undo / ↷ Redo** bzw. **Strg+Z / Strg+Y** | Schritt zurück / vor |
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
| **M** | **Maus-Flug** an/aus (War-Thunder-Stil — siehe unten) |
| **J** | **Arcade-Lenkung** an/aus (super-smooth, schnappt sofort aufs Ziel; aktiviert Maus-Flug) |
| **Shift / Strg** | Schub hoch / runter — **unter 0 % = bremsen** (Luft- & Radbremse) |
| **S / ↓** und **W / ↑** | Nase hoch / runter |
| **A / ←** und **D / →** | rollen — **A = rechts, D = links** (vertauscht) |
| **Q / E** | nach rechts / links gieren (Seitenleitwerk) — auch **C / Z** |
| **G** | Einziehfahrwerk ein-/ausfahren |
| **I** | Steuerung umkehren (alles in die andere Richtung) |
| **T** | Assist an/aus (an = ruhig, aus = direkter „Pro"-Modus) |
| **Enter** | Reset auf die Startbahn (repariert auch gebrochenes Fahrwerk) |
| **Tab** | zurück in den Hangar |

**🖱 Maus-Flug (Taste M) — wie in War Thunder:** Die Maus zeigt frei in eine **Richtung in
der Welt** — und das Flugzeug **dreht seine Nase genau dorthin**. Schaust du nach links,
fliegt es nach links; schaust du nach hinten, dreht es sich **komplett herum** (volle 360°,
auch steil hoch/runter). Ein **grüner Zielmarker** ⊕ zeigt, wohin du zielst, ein **gelber
Nasenmarker** ◇ zeigt, wohin die Nase gerade weist — decken sie sich, fliegst du genau aufs
Ziel. Kurven (Rollen + Ziehen) werden automatisch koordiniert. Tastatur (W/S/A/D/Q/E) wirkt
zusätzlich. Nochmal **M** schaltet zurück auf freies Umschauen.

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
**„🌬 Windkanal-Ansicht"** → das Flugzeug wird zu **einem Modell zusammengebacken**
und **Luftstrom-Linien** strömen wie im Windkanal darüber.

**Abheben:** Vollgas (Shift halten), auf der Bahn beschleunigen, ab ~120 km/h sanft
ziehen (S) → das Flugzeug rotiert und steigt. Die Flügel haben einen Einstellwinkel,
es hebt fast von allein ab, sobald genug Tempo da ist. Im Steigflug baut sich
(realistisch) Geschwindigkeit ab — nicht zu steil ziehen, sonst **Stall**.

---

## 🧩 Bauteile

- **Rumpf:** Cockpit (Basis), Rumpfsegmente, Nasen-/Heckkonus, Treibstofftank
- **Tragflächen:** Gerade · Trapez · Pfeil · Delta · Stummel · Segler (lang) · Canard · Winglet
- **Leitwerk & Steuerung:** Höhenleitwerk (Pitch), Seitenleitwerk (Yaw), Querruder (Roll), kleines Höhenruder
- **Antrieb:** Propeller, großer Propeller, Düsentriebwerk, **eckiges Düsentriebwerk** (2D-Düse), Hilfstriebwerk
- **Fahrwerk (4 Varianten mit Traglast):** Leicht (~450 kg) · Standard (~850 kg) ·
  Schwer (~1750 kg) · **Einziehfahrwerk (~1050 kg, Taste G)**
- **Bewaffnung (feuerbar!):** Bordkanone (Schnellfeuer) · **Ungelenkte Rakete** (fliegt
  geradeaus) · **Raketenwerfer** (3er-Salve) · **Zielsuchrakete** (Heat-Seeker) ·
  **Schwere Lenkrakete** (große Reichweite, viel Schaden) · Bombe (Freifall, **Taste B**) —
  alles außer Bombe feuert per **Leertaste**

*Mit `tools/build_jet.gd` gibt's einen vorgebauten zweimotorigen Delta-Canard-Jet
(zwei eckige Triebwerke) im Speicherstand.*

## 🎈 Luftkampf

Am Himmel schweben **Luftballons** und **Luftschiffe** (Zeppeline) zum Abschießen.
Bau Waffen an dein Flugzeug, ziel mit dem Fadenkreuz und feuere:

- **Leertaste** — feuert alle montierten Rohrwaffen: Kanone (geradeaus), ungelenkte
  Raketen & Salven (geradeaus) sowie Lenkraketen. **Heat-Seeker fliegen erst geradeaus
  und kurven erst dann aufs Ziel, wenn eines in ihre Nähe kommt** — also vorher grob zielen.
- **Taste B** — Bombe abwerfen

Jeder Abschuss gibt **Geld** (Ballon +120, Luftschiff +600) → so verdienst du im Survival.
Abgeschossene Ballons werden nach kurzer Zeit durch neue ersetzt.

Mehr/größere **Steuerflächen** → mehr Wendigkeit. Mehr **Flügelfläche** → mehr
Auftrieb (langsameres Abheben). Mehr **Schub** → bessere Beschleunigung.

**Fahrwerk-Traglast:** Die Summe der Fahrwerks-Traglasten muss das Gesamtgewicht
tragen. Ist das Flugzeug zu schwer, **bricht das Fahrwerk zusammen** (Anzeige im
Hangar bei „Fahrwerk-Last" und im Flug-HUD als „KOLLABIERT"). Das **Einziehfahrwerk**
fährt im Flug mit **G** ein → weniger Widerstand, höhere Geschwindigkeit.

---

## 🛠️ Technik

Alles ist **prozedural** erzeugt (Meshes, Materialien, UI) – keine externen Assets nötig.

```
project.godot          Projektkonfiguration (Godot 4.6, Forward+)
scenes/Main.tscn        Hauptszene (nur Wurzelknoten + Main.gd)
scripts/
  Main.gd               Welt, Licht, Himmel, Modus-Umschaltung, UI/HUD, Speichern/Laden
  PartCatalog.gd        Alle Bauteile + prozedurale Mesh-/Material-Erzeugung
  BuildController.gd    Hangar: Orbit-Kamera, flächenbündiges Snapping, Ghost, Symmetrie, Statistik
  FlightController.gd   Baut den Flieger aus dem Design, Steuerung, Verfolgerkamera, HUD
  AircraftBody.gd       Der fliegende RigidBody: Aerodynamik (Auftrieb/Widerstand/Stabilität), Rate-Regler
tools/
  phys_test.gd          Headless-Physiktest (zum Nachtunen): Godot --headless --path . --script res://tools/phys_test.gd
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

Darüber liegt ein **Fly-by-Wire-Lageassistent** (Taste **T**): Eingabe kommandiert
Drehraten, ohne Eingabe wird Lage/Querlage gehalten (ruhiges, spaßiges Fliegen).
Mit **T aus** bekommst du den direkteren „Pro"-Modus.

**Was beim Bauen zählt:** Flügelfläche (Auftrieb & Abrissgeschwindigkeit), Streckung
(Gleitleistung/Widerstand), Leitwerksfläche (Stabilität & Steuerautorität), Schub
(Beschleunigung/Steigen) und der Schwerpunkt (im Hangar als Marker sichtbar).

Speicherstand: `user://aircraft_design.json` (Buttons **Speichern/Laden** im Hangar).

---

## 🎮 Spielmodi, Geld & Upgrades

Beim ersten Start wählst du einen **Modus**:

- **🧰 Sandbox** — alle Teile frei, unbegrenzt bauen & fliegen, kein Geld-Stress.
- **🪖 Survival** — du startest mit **🪙 1500** und nur Basis-Teilen. **Kaufe** weitere
  Teile (Schloss-Symbol + Preis in der Palette) und **upgrade** dein Flugzeug
  (Triebwerks-Tuning, verstärkte Flügel, Leichtbau).

Fortschritt (Geld, Freischaltungen, Upgrades) wird in
`user://aviassembly_progress.json` gespeichert.

---

## 💡 Ideen-Roadmap (noch nicht eingebaut)

- 🎯 Missionen & Parcours (Ringe durchfliegen, Landeherausforderungen, Zeitrennen)
- 🪙 Münzen sammeln → neue Teile / Lackierungen freischalten
- 💥 Schadensmodell & Crash-Effekte, Landungsbewertung
- 🌦️ Wind, Turbulenzen, Wetter, Tag/Nacht
- 🌊 Schwimmer & Wasserung, Träger-Starts
- 🎨 Lackier-Editor, Foto-Modus, Replays
- 🕹️ Gamepad-Support, mehr Kamera-Modi (Cockpit-Sicht)
- 🧰 Mehr Teile: Klappen, Luftbremsen, Raketen, Fahrwerk einfahrbar
- 👥 Geteilte Designs / Bestenlisten

Viel Spaß beim Bauen und Fliegen! 🛩️
