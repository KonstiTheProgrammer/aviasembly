# Survival-Progression — Konzept

> Design-Dokument, noch nicht implementiert. Alle Zahlen sind Startwerte zum Tunen.
> Grundsatz: **nur auf Systemen aufbauen, die es schon gibt** (Telemetrie, Ziele, Flak-Zone,
> Lande-Erkennung, Teil-Familien) — kein neues Missions-System (wurde bewusst entfernt).

## 1. Ist-Zustand (Befund)

- Start: **2200 🪙** + 12 Starter-Teile (Holzflieger-Kit: cockpit, fuselage, nose, tailcone,
  strut, wing_straight, h_stab, v_stab, prop_engine, wheel, wheel_light, mg)
- **Einzige Einnahme:** Ballon-Abschuss **+120**, Luftschiff **+600** (Respawn nach 7 s)
- Ausgaben: Teile (Formel `mass·1.5 + thrust·0.045 + area·65 + gear_cap·0.4`, min 80,
  auf 50er gerundet) und 3 Upgrade-Tracks à 3 Stufen (600/1200/1800)
- **Probleme:**
  1. Kein Ziel-Gerüst — nichts sagt dem Spieler, worauf er sparen soll oder was als Nächstes kommt.
  2. Eine einzige Einnahme-Schleife (Ballon-Farming) → wird nach ~15 Minuten monoton.
  3. Risiko lohnt nicht: Flak-Zone, G-Schutz-Aus, saubere Landung — alles ohne Belohnung.
  4. Die Teil-Palette ist ein flacher Shop: der Sprung „Holzvogel → F-22" hat keine Dramaturgie.

## 2. Leitidee: „Vom Holzvogel zum Überschalljäger" (5 Ären)

Das Content-Regal ist bereits da — die vorhandenen Teil-Familien ergeben von selbst eine
historische Progression. Die Palette wird in **Ären** gegliedert; jede Ära schaltet man mit
einem **Flugpatent** frei (Geld + Meilensteine, siehe §3).

| Ära | Name | Kern-Teile (existieren alle schon) | Patent-Preis |
|---|---|---|---|
| **T1** | Pioniere | Starter-Kit + Doppeldecker-Familie: `cockpit_radial`, `engine_radial`, `reto_engine`, Speichen-/Scheibenrad, `mg` | — (Start) |
| **T2** | Warbirds | Spitfire-Familie (Cockpit/Motor/Flügel), `mustang_body`, `prop_engine_big`, `wheel_retract`, `wheel_spitfire`, `cannon`, `wing_gun`, `bomb` | 1 500 |
| **T3** | Frühe Jets | `me262_body`, `f86_body`, `mig15_body`, `jet_engine`, `jet_nose`, `wheel_jet`, `autocannon`, `rocket`, `rocket_pod` | 4 000 |
| **T4** | Überschall | MiG-21-Familie, F-4-Familie, `heavy_cannon`, `missile`, `missile_heavy` | 9 000 |
| **T5** | Moderne | F-14-/F-22-Familie, `jet_square`, `minigun` (GAU-8), `thruster` | 18 000 |

Teilpreise bleiben aus der bestehenden Formel (T1 ~80–700, T2 ~400–1500, T3 ~900–2200,
T4/T5 ~1500–3500) — die Patente strecken die Kurve, ohne einzelne Teile künstlich zu verteuern.

**Upgrades pro Ära gedeckelt:** T1 max. Stufe 1, T2 max. 2, ab T3 alle 3 Stufen.
So bleibt der bestehende Upgrade-Shop über die ganze Laufzeit relevant.

## 3. Flugpatente: Meilensteine statt Missionen

Missionen wurden bewusst entfernt — Patente nutzen stattdessen **zustandslose, passiv
erfüllbare Meilensteine** aus vorhandener Telemetrie (Speed/Höhe im HUD, Kill-Zähler,
Sinkraten-Erkennung, Flak-Zonen-Position). Kein Questlog, keine Skripte: Werte beobachten,
Haken setzen (persistiert im vorhandenen `missions_done`-Hook von GameState).

| Patent | Geld | Meilensteine (je 2–3, alle passiv messbar) |
|---|---|---|
| **T2** | 1 500 | 200 km/h erreicht · 5 Abschüsse in einem Flug · eine „Saubere Landung ✓" |
| **T3** | 4 000 | 450 km/h · Luftschiff über 300 m Höhe abgeschossen · 30 s in der Flak-Zone überlebt |
| **T4** | 9 000 | 800 km/h · 3 000 m Höhe · 10 Abschüsse in einem Flug ohne Schaden |
| **T5** | 18 000 | 1 200 km/h · Abschuss in der Flak-Zone mit G-Schutz AUS · 5 000 m Höhe |

Die Patent-Kachel in der Palette zeigt die Checkliste — das ist gleichzeitig das
Ziel-Gerüst, das aktuell fehlt („worauf spare/übe ich gerade?").

## 4. Einnahmen-Fächer (Risiko ↔ Ertrag)

| Quelle | Betrag | Risiko | Status |
|---|---|---|---|
| Ballon | 120 | keins | existiert |
| Luftschiff | 600 | gering (höher/weiter) | existiert |
| **Flak-Zonen-Kopfgeld** | Abschüsse **in** der Zone ×3 | hoch (Flak schießt!) | NEU — nutzt `zone_center/radius` |
| **Landegeld** | +150 je „Saubere Landung ✓" nach ≥1 Abschuss | gering | NEU — nutzt Sinkraten-Erkennung |
| **Rekord-Prämien** | je 200–500, einmalig pro Schwelle (Speed/Höhe/Distanz) | selbstgewählt | NEU — nutzt HUD-Telemetrie |

- Das Landegeld belohnt den **Heimflug statt Enter-Reset** — gibt jedem Flug einen Bogen
  (raus → jagen → heil zurück).
- Rekord-Prämien bedienen den Explorer-Spielstil (die Welt mit Bergen, Stadt, Leuchtturm,
  Bergdorf existiert — bislang ohne spielerischen Grund, sie zu besuchen).
- Einkommensrate wächst pro Ära von selbst (bessere Waffen = schnellere Kills; Zone-Multiplikator
  wird mit schnellen Jets erst richtig farmbar) → „Käufe pro Session" bleiben ~konstant.
- **V2-Option** (bewusst zurückgestellt, da missions-artig): Frachtflüge zwischen den
  Landmarks (Leuchtturm → Stadt → Bergdorf) als opt-in Lieferaufträge.

## 5. Geld-Senken & Risiko-Ökonomie

- Teile + Patente + Upgrades (siehe oben).
- **Optional — Bergungskosten:** Totalverlust (Flügelbruch/Absturz statt Landung) kostet
  10 % der verbauten Teilwerte, gedeckelt auf 300. Enter-Reset auf der Startbahn bleibt
  **gratis** (kein Frust-Tax beim Üben) — nur der Crash im Feld kostet. Macht G-Schutz-Aus
  zur echten Entscheidung (T5-Meilenstein + Nervenkitzel vs. Bergungskosten).

## 6. Pacing-Ziel

| Zeit | Zustand |
|---|---|
| 0–15 min | T1: erste 3–4 Käufe (zweites Flügelpaar, Sternmotor, besseres Rad) — Kaufgefühl alle ~4 min |
| ~25 min | **T2-Patent** → Spitfire-Moment (erste große Belohnung) |
| ~1 h | **T3** → erster Jet (größter inszenierter Sprung: Sound/Speed) |
| ~2 h | **T4** → Überschall + Lenkraketen |
| ~3–4 h | **T5** → F-22 / GAU-8 als Endgame-Trophäen |

## 7. UX-Anker

- **Palette:** Ären-Sektionen mit Banner; gesperrte Ära zeigt die Patent-Kachel samt
  Meilenstein-Checkliste (statt nur 🔒+Preis auf jedem Teil).
- **Flug-Bilanz:** kleine Zusammenfassung nach jedem Flug (Abschüsse, Zonen-Bonus,
  Landegeld, neue Rekorde) — macht die Einnahmen-Quellen sichtbar/lernbar.
- **Ampel-Erweiterung:** „Nächstes Ziel"-Zeile (nächster offener Meilenstein).

## 8. Implementierungs-Hinweise (alles hat Andockpunkte)

| Baustein | Andockpunkt | Aufwand |
|---|---|---|
| Meilenstein-Kern (beobachten + persistieren) | `GameState.missions_done` (ungenutzter Hook!), HUD-Telemetrie, `Target.killed` | S |
| Ären-Gating der Palette | `PartCatalog`-Teil-Feld `era`, `Main._rebuild_palette`/`buy_part` | S–M |
| Flak-Zonen-Multiplikator | `FlakGun.zone_center/zone_radius` + Kill-Position | S |
| Landegeld | vorhandene Sinkraten-/`landing_msg`-Logik | S |
| Rekord-Prämien | `airspeed`/`alt` im FlightController-HUD-Pfad | S |
| Patent-UI (Checkliste) | Palette-Sektionen in `Main` | M |
| Bergungskosten (optional) | Flügelbruch-/Kollaps-Pfad in `AircraftBody` | S |
| Frachtflüge (V2) | `Landmarks`-Positionen | L |

Balancing-Konstanten (Patente, Prämien, Multiplikator) an **einer** Stelle in `GameState`
sammeln, damit Tuning ein Ein-Datei-Edit bleibt.

## 9. Offene Fragen / Risiken

- Bleibt Ballon-Farming dominant? → Zone-×3 und Rekorde sollten es schlagen; falls nicht:
  Ballon-Ertrag pro Flug degressiv (ab dem 10. Ballon 60).
- Patent-Preise zu grindig? → Zahlen sind Startwerte; Ziel ist „Patent ≈ 10–15 min
  fokussiertes Spielen der jeweiligen Ära".
- Luftschiff-Respawn (7 s) exploitbar bei T4/T5-Speed? → ggf. Respawn-Distanzregel.
