// Aviassembly-Himmel: TIEFER Verlauf, lesbare Sonne, GEMALTE Kumuluswolken.
//
// Was hier vorher stand und warum es nicht getragen hat (im Bild nachgesehen, nicht
// vermutet):
//  * Die "Fernwolken" waren keine Wolken, sondern strukturlose Schlieren. Ursache war
//    NICHT zu wenig Weichzeichnung, sondern zu wenig FLAECHE: die Projektion
//    dir.xz/(dir.y+0.22) ist durch den Summanden 0.22 hart gedeckelt — |uv| lief vom
//    Zenit bis zum Horizont nur von 0 bis 4.5, mal cloud_scale 0.85 also bis 3.8.
//    Ueber den GANZEN sichtbaren Himmel lagen damit keine vier Rauschzellen. Eine
//    einzelne fbm-Zelle deckte ein Viertel des Bildes ab — genau der milchige Fleck.
//  * Die Schwelle war so breit wie das Rauschen selbst (cloud_soft 0.30 bei einer
//    Streuung von rund 0.14): damit gibt es gar keine Kante mehr, nur eine Rampe.
//    Ohne Kante keine Silhouette, ohne Silhouette liest niemand eine Wolke.
//  * Die Beleuchtung kam aus DERSELBEN Zahl wie die Dichte (lit = f(n)). Das kann
//    prinzipiell nur konzentrische Helligkeitsringe erzeugen — hell in der Mitte,
//    dunkel am Rand —, niemals eine Sonnen- gegen eine Schattenseite.
//
// UND WAS DANACH IMMER NOCH NICHT TRUG — die Runde davor hatte zwar eine Silhouette
// gewonnen, aber keinen KOERPER. Drei Ursachen, alle am Bild nachgewiesen:
//  * Die Neigung der Wolkenoberflaeche wurde ueber einen Abstand von 0.075 uv gemessen.
//    Eine Wolkenzelle ist rund 1 uv gross, die vierte Rauschoktave 0.12 — gemessen wurde
//    also fast nur die feinste Oktave. Ergebnis: Gesprenkel statt Plastik. Die
//    grossflaechige, also beleuchtungsgetragene Varianz im Wolkeninneren betrug 44 bis
//    74 Prozent, bei den durchfliegbaren Volumenwolken im SELBEN Bild 72 Prozent bei
//    dem 4- bis 16-fachen Absolutwert.
//  * Die Kennlinie war symmetrisch um sun_dir.y gelegt: eine waagerechte Wolkenoberkante
//    landete damit definitionsgemaess in der Mitte der Spanne. Bei 50 Grad Sonnenhoehe
//    steht sie aber im vollen Licht. Zusammen mit einem zu schwachen Kippfaktor sass
//    praktisch die ganze Flaeche im weissen Ende: p05 des Bildwerts 176 bis 191 gegen
//    90 bei den Volumenwolken, Innenspanne 38 bis 68 statt 138.
//  * Es gab ueberhaupt nur EINE zeitabhaengige Zahl im ganzen Wolkenblock, und die stand
//    in einer Verschiebung. Damit KANN sich nichts entwickeln — gemessen zogen im
//    Zenitbild oben wie unten identische 72 px je 40 s durch, eine starre Tapete.
// Die Gegenmittel stehen bei cloud_form_e, cloud_lobe, cloud_shade_lo/hi und
// cloud_evolve, jeweils mit den Zahlen, an denen sie eingestellt wurden.
//  * Die Sonne war ein harter Punkt: pow(sdot,1800) faellt erst bei 1.6 Grad auf die
//    Haelfte, das ergibt eine Scheibe von ~3 Grad Durchmesser (bei 64 Grad VFOV auf
//    720 px rund 34 px) — und drumherum nichts, was sie als Lichtquelle lesbar macht.
//  * Der Verlauf lief von einem hellen Zenit in einen fast gleich hellen Horizont.
//    Ohne Spanne kein Raum: "Pastellbrei".
//
// HORIZONTBAND (unveraendert uebernommen, siehe unten): die Welt endet hart — das
// Terrain bei 3,8 km (TerrainWorld.VIEW_DIST), die Wasserplatte bei 4,6 km. Dahinter
// stand blanker Himmel, und weil der viel heller ist als das ferne Wasser, riss quer
// durchs Bild eine Kante ("Tischplatte"). Der Nebel bleibt bewusst duenn (die Ferne SOLL
// lesbar sein), stattdessen faerbt der Himmel unterhalb des Horizonts in den
// Fernwasser-Ton ein: die Weltkante trifft dann auf fast denselben Farbwert und loest
// sich auf. Darueber liegt ein schmaler Dunstsaum.
//
// DESHALB DIE WICHTIGSTE REGEL DIESER DATEI — und der Grund, warum col_deep trotz des
// komplett neuen Verlaufs NICHT neu eingemessen werden musste:
//   UNTERHALB DES HORIZONTS (dir.y < 0) DARF SICH NICHTS AENDERN. Drei Griffe dafuer:
//     - der Verlauf rechnet mit u = max(dir.y, 0.0) und ergibt unterhalb des Horizonts
//       darum konstant col_horizon — genau das, was auch der alte smoothstep lieferte;
//     - Sonnenscheibe, Glast und Hof werden mit `ueber_horizont` sauber auf null
//       gezogen, BEVOR das Band greift;
//     - Dither und Wolken laufen ohnehin nur oberhalb.
//   Nachgerechnet (beide sky()-Funktionen in Python nachgebaut, dir.y von -1 bis 0 in
//   3000 Schritten mal 64 Azimute, verglichen wird die lineare Ausgabefarbe):
//     * nur der Verlauf, ohne Sonnenterme: ab dir.y <= -0.02 exakt 0 Unterschied,
//       im Streifen darueber hoechstens 0.11 von 255 — der alte smoothstep(-0.02, ...)
//       mischte dort noch eine Spur col_mid dazu, der neue nicht;
//     * der ALTE Shader legte unterhalb des Horizonts bis zu 3.6 von 255 Sonnenhof auf
//       (pow(sdot,5) war nirgends abgeschnitten) — ausgerechnet als Aufhellung gegen
//       den Ton, auf den col_deep kalibriert ist, und nur auf der Sonnenseite;
//     * der NEUE legt dort exakt 0 auf.
//   Der neue Himmel trifft die Kalibrierung unterhalb des Horizonts also nicht nur
//   genauso gut, sondern gleichmaessiger. Wer den Verlauf spaeter anfasst, muss diese
//   Eigenschaft erhalten oder col_deep neu einmessen.
//   IM BILD nachgeprueft, diesmal PIXELGENAU (tools/_sky_render.gd liefert seit seiner
//   Reparatur bitgleiche Bilder, siehe unten). Verglichen wurden der Stand vor dieser
//   Runde und der jetzige, in allen neun Ansichten, aber nur die Zeilen UNTERHALB der
//   rechnerischen Horizontzeile:
//     * groesste Abweichung: 1 von 255, in jeder einzelnen Ansicht. Und die einzige
//       Ursache dafuer ist, dass das Wasser den geaenderten Himmel spiegelt.
//     * Plateauwert unter dem Horizont: 87.4/132.6/182.2 (ueber_decke) und
//       85.0/131.7/182.4 (hoch) — vorher wie nachher auf die Nachkommastelle gleich.
//   ZUR KALIBRIERUNG SELBST, weil die Frage in dieser Runde aufkam: an der Kante der
//   Wasserplatte steht auf der SONNENABGEWANDTEN Seite (horiz_gegen, 300 m) Wasser mit
//   80/126/182 gegen einen Himmel mit 82/129/181 — drei von 255, dort ist die Weltkante
//   tatsaechlich verschwunden, und genau dort wurde col_deep eingemessen. Auf der
//   SONNENSEITE (horiz_sonne) liegt das Wasser am Plattenrand bei 163/180/203, weil dort
//   das Glitzerband endet. Diese Differenz ist mit EINER Himmelsfarbe nicht zu schliessen:
//   was die Sonnenseite deckt, reisst die Gegenseite auf. Sie gehoert zum Wasser-Shader,
//   nicht zum Verlauf, und wird hier bewusst nicht angefasst.
//
// ZUM MESSVERFAHREN: tools/_sky_render.gd lieferte zwischen zwei Laeufen frueher KEINE
// bitgleichen Bilder — zwei Laeufe bei identischem Projektstand wichen im Mittel um 8.8
// bis 52.2 je Kanal ab, mehr als der zu beurteilende Shaderwechsel selbst. Das Werkzeug
// ist in dieser Runde repariert worden (Gelaende-Streaming, Shaderuhr, Bindung von Pose
// und Bild — die Begruendung steht in seinem Kopf). Zwei vollstaendige Laeufe liefern
// jetzt in allen neun Ansichten dieselbe md5. Alle Zahlen hier sind deshalb direkt am
// Bild gemessen und nachpruefbar.
shader_type sky;

// --- Himmelsverlauf ------------------------------------------------------------------
// Zenit und Mitte sind gegenueber vorher deutlich ABGESENKT (vorher 0.24/0.49/0.86 bzw.
// 0.40/0.61/0.89). Der Horizont bleibt, wo er war — das ist der Wert, gegen den das
// Horizontband kalibriert ist. Die gewonnene Spanne Zenit->Horizont ist es, die dem
// Himmel Tiefe gibt; sie war vorher zu klein, um als Raum gelesen zu werden.
// Nicht weiter absenken ohne Gegenprobe: env.ambient_light_source steht auf SKY, der
// Zenitwert geht also direkt in die Umgebungshelligkeit der ganzen Welt.
uniform vec3 col_zenith  : source_color = vec3(0.165, 0.375, 0.800);
uniform vec3 col_mid     : source_color = vec3(0.330, 0.545, 0.875);
uniform vec3 col_horizon : source_color = vec3(0.600, 0.730, 0.880);  // NICHT anfassen
// Abklingraten des Verlaufs. exp() statt smoothstep(): smoothstep hat an seinen beiden
// Enden einen Knick in der zweiten Ableitung, und genau dort setzt Banding an. exp()
// ist ueberall glatt.
uniform float grad_mid : hint_range(0.5, 8.0) = 2.40;   // breiter Uebergang Zenit->Mitte
uniform float grad_hz  : hint_range(2.0, 20.0) = 7.00;  // schmaler Dunstsaum am Horizont

// --- Sonne ---------------------------------------------------------------------------
uniform vec3 sun_col  : source_color = vec3(1.0, 0.98, 0.92);
uniform vec3 sun_halo : source_color = vec3(1.0, 0.87, 0.68);
// Halber Oeffnungswinkel der Scheibe in Radiant. 0.016 rad = 0.92 Grad, also gut 1,8 Grad
// Durchmesser — rund 20 px bei 720 p / 64 Grad VFOV. Kleiner als vorher (3 Grad), weil
// die Lesart "Lichtquelle" jetzt vom Glast kommt und nicht mehr von der Scheibengroesse.
uniform float sun_size    : hint_range(0.004, 0.06) = 0.016;
// Energie der Scheibe. Die Nachbelichtung dieser Szene (ACES, white 6, contrast 1.05)
// ist eingemessen: sRGB 255 entspricht HDR 1.56. 5.0 liegt also gut dreifach im
// Anschlag — die Scheibe bleibt auch dann rein weiss, wenn Dunst darueber liegt.
uniform float sun_energy  : hint_range(0.0, 20.0) = 5.0;
uniform float halo_energy : hint_range(0.0, 4.0)  = 1.45;   // enger, warmer Glast
uniform float hof_energy  : hint_range(0.0, 1.0)  = 0.18;   // weiter Hof ueber ~40 Grad

// --- Wolken --------------------------------------------------------------------------
// Die Spanne zwischen Schatten- und Sonnenseite ist der ganze Punkt, und sie ist am
// FERTIGEN BILD eingemessen, nicht geraten. Massstab sind die durchfliegbaren
// Volumenwolken (CloudField) im selben Bild — die Fernwolken muessen zu ihnen passen,
// sonst sieht man zwei verschiedene Wettersysteme. Gemessen in unter_decke, Helligkeit
// nach der ganzen Kette:
//   Volumenwolken:   p05  91   Median 192   p95 226
//   Fernwolken alt: p05 137   Median 202   p95 227   <- Schattenseite viel zu hell
// Aus zwei bekannten Punkten (linear 0.380 -> 128, linear 1.279 -> 234) faellt die
// Kennlinie der Nachbelichtung als sRGB ~ (0.663 * linear)^0.5 heraus. Fuer eine
// Schattenseite bei 95 braucht es demnach linear 0.21 — daher dieser Wert.
uniform vec3 cloud_lit  : source_color = vec3(1.0, 0.985, 0.955);
// Schattenfarbe.
// ACHTUNG BEIM LESEN DIESER ZAHLEN: der Hinweis source_color bedeutet, dass Godot sie als
// sRGB auffasst und vor der Uebergabe an den Shader nach linear umrechnet. 0.150 steht
// hier also fuer linear 0.019, nicht fuer 0.150. Wer sie fuer linear haelt, rechnet um den
// Faktor 5 bis 8 daneben — nachgewiesen, indem dieselbe Farbe einmal als Color (mit
// Umrechnung) und einmal als Vector3 (ohne) gesetzt wurde: das Bild wurde HELLER, obwohl
// die Zahl kleiner war.
// Die Helligkeit war schon vorher richtig. Falsch war die SAETTIGUNG: mit 0.150/0.205/0.335
// stand Blau beim 2,2-fachen von Rot, und auf weisser Flaeche liest sich das nicht als
// Schatten, sondern als blaue Marke, die jemand aufgetupft hat.
// Am fertigen Bild eingemessen (unter_decke, dunkelstes Zwanzigstel des Wolkeninneren,
// Massstab sind die Volumenwolken im selben Bild bei 58/74/99):
//   0.150/0.205/0.335 (vorher)   Bild 114/135/180   b:r = 1.58   <- und dazu viel zu hell
//   0.150/0.196/0.290            Bild  70/ 96/140   b:r = 2.00
//   0.145/0.175/0.225 (jetzt)    Bild  70/ 93/129   b:r = 1.84
//   Volumenwolken                Bild  58/ 74/ 99   b:r = 1.71
// Weiter herunterzugehen bringt kaum noch etwas: von 0.290 auf 0.225 sind 43 Prozent
// weniger Blau in der Eingabe und nur 16 Prozent weniger im Bild. Der Rest kommt nicht
// aus dieser Farbe, sondern aus dem Himmel, der durch die Wolke durchscheint
// (cloud_opacity) und aus der Luftperspektive weiter unten.
uniform vec3 cloud_dark : source_color = vec3(0.145, 0.175, 0.225);
uniform float cloud_gain : hint_range(1.0, 2.0) = 1.30;
uniform vec3 sun_dir = vec3(0.55, 0.62, 0.55);
// cloud_cover ist eine SCHWELLE, kein Anteil: die Rohdichte streut um 0.5 mit einer
// Standardabweichung von rund 0.14 (aus den Oktavgewichten gerechnet). 0.600 liegt gut
// 0.75 Sigma darueber -> knapp ein Viertel Himmelsbedeckung, und vor allem: die
// Wolkenflecken haengen nicht mehr zusammen, sondern stehen einzeln.
// Groesserer Wert = WENIGER Wolken.
uniform float cloud_cover : hint_range(0.2, 0.9) = 0.600;
// Breite des Schwellenuebergangs, in denselben Einheiten wie oben. 0.075 ist gut ein
// halbes Sigma: scharf genug fuer eine Silhouette, weich genug, dass sie nicht treppt.
uniform float cloud_soft  : hint_range(0.02, 0.30) = 0.075;
// Rauschfrequenz, siehe Projektion unten. Zusammen mit cloud_persp ergibt das rund 12
// Rauschzellen vom Zenit bis zum Horizont — statt der knapp vier von vorher.
uniform float cloud_scale = 2.80;
// Perspektivstaerke der Wolkenebene. Direkt ueber dem Kopf ist der Massstab
// cloud_persp * cloud_scale, am Horizont waechst der Radius nur noch mit log.
// Erster Versuch stand hier auf 1.0: dann kollabiert die Gegend um den Zenit auf so
// wenige Rauschzellen, dass einzelne Wolken den halben Bildschirm fuellen und wie eine
// Landkarte wirken. 3.0 verdoppelt die Aufloesung ueber dem Kopf und kostet am Horizont
// nur gut 10 Prozent.
uniform float cloud_persp : hint_range(0.3, 6.0) = 3.0;
// WIND, in Einheiten der WOLKENEBENE je Sekunde (eine Ebeneneinheit = Hoehe der
// Wolkenbasis ueber dem Auge, also rund 1 km -> 0.005 entspricht knapp 5 m/s).
// WICHTIG, UND DER GRUND FUER DIE UMSTELLUNG: der Versatz greift jetzt an `eben`, also
// VOR der logarithmischen Stauchung. Vorher lag er dahinter (uv += TIME * cloud_speed) —
// ein konstanter Versatz im gestauchten Raum verschiebt aber den ganzen Himmel mit
// derselben Bildgeschwindigkeit, oben wie unten. Genau das war im Zenitbild nachweisbar:
// 72 px je 40 s am oberen wie am unteren Bildrand, eine starre Tapete, die ueber den
// Himmel zieht. In der Ebene dagegen ist die Winkelgeschwindigkeit dTheta/dd = 1/(1+d^2):
// nahe dem Zenit (d ~ 0.7) rund 0.67 rad je Ebeneneinheit, bei 5 Grad Hoehe (d = 11.4)
// nur noch 0.0076 — Faktor 88. Ferne Wolken stehen damit fast still und nahe ziehen,
// wie es die Perspektive verlangt.
// NACHGEMESSEN, Bildversatz zwischen t = 0 und t = 40 s in derselben Ansicht:
//                              vorher              jetzt
//   unter_decke, 47-56 Grad    30.8 px             73.9 px
//   unter_decke, 10-16 Grad    19.6 px             17.0 px
//   Verhaeltnis hoch zu tief    1.6                 4.3
//   zenit, 74 Grad / 37 Grad   37.6 / 38.9 px      70.3 / 41.1 px
// In der zenit-Ansicht war der Versatz oben und unten vorher auf 3 Prozent gleich — das
// ist die Tapete, die aufgefallen ist. Jetzt zieht der Himmel ueber dem Kopf knapp doppelt
// so schnell wie der auf halber Hoehe.
uniform float cloud_wind : hint_range(0.0, 0.05) = 0.005;
// ENTWICKLUNG. Versatz der ERSTEN Rauschoktave je Sekunde; jede weitere Oktave wandert
// um den Faktor 3.4 schneller, waehrend ihre Frequenz nur um 2.03 steigt. Die Oktaven
// laufen dadurch GEGENEINANDER: der Umriss bleibt ueber Minuten stehen, die Buckel darauf
// ordnen sich um. Die vierte Oktave kommt auf 3.4^3 = 39-fache Geschwindigkeit, mit
// 0.0003 also auf 0.0118 Zellen je Sekunde — nach 40 s knapp eine halbe Zelle, nach zwei
// Minuten ist von ihrem Muster nichts mehr wiederzuerkennen.
// Ohne diesen Term gibt es im ganzen Wolkenblock genau EINE zeitabhaengige Zahl (den
// Wind), und dann KANN das Ergebnis nichts anderes sein als eine Verschiebung.
// NACHGEMESSEN (t = 0 gegen t = 40 s, bester ganzzahliger Versatz per Kreuzkorrelation,
// danach der verbleibende Rest — dieselben Bildfenster fuer beide Staende):
//                            vorher                        jetzt
//   unter_decke, oben        r = 0.98, Rest  2.3           r = 0.65, Rest 10.7
//   unter_decke, unten       r = 0.92, Rest  2.8           r = 0.86, Rest  4.8
//   zenit, 74 Grad           r = 0.89, Rest  9.5           r = 0.72, Rest 23.0
//   zenit, 37 Grad           r = 0.99, Rest  2.3           r = 0.81, Rest 13.5
// Vorher liessen sich also 79 bis 99 Prozent des Unterschieds (r hoch zwei) durch reines
// Verschieben erklaeren, jetzt 42 bis 74; der Rest nach dem Ausrichten ist von 2 bis 10
// auf 5 bis 23 Luma gestiegen, bei praktisch gleichem Fensterkontrast. Nach 120 s faellt
// r auf 0.12 bis 0.36 — dann ist das Muster nicht mehr wiederzuerkennen.
uniform float cloud_evolve : hint_range(0.0, 0.002) = 0.0003;
// WOLKENUHR. Normalfall -1: dann laeuft TIME wie ueberall sonst. Ein Wert >= 0 haelt die
// Uhr auf genau diesem Zeitpunkt fest.
// Warum das im Shader stehen muss und nicht im Werkzeug geloest werden kann: TIME haengt
// am Renderer und laesst sich von aussen weder anhalten (Engine.time_scale erreicht sie
// nicht) noch setzen. Ohne diesen Griff ist KEIN Bild reproduzierbar — gemessen wichen
// zwei Laeufe des Abnahmewerkzeugs bei identischem Projektstand im Mittel um bis zu 52
// von 255 je Kanal ab, mehr als der zu beurteilende Shaderwechsel selbst.
// ALLE zeitabhaengigen Terme unten benutzen ausschliesslich diese eine Zahl (Drift wie
// Entwicklung), sonst waere "eingefroren" nur halb wahr.
uniform float cloud_clock = -1.0;
// AUF NULL = GEMALTE FERNWOLKEN AUS. Auf Wunsch abgeschaltet: sie stehen unendlich weit
// weg und haben deshalb keine Parallaxe — sie ziehen nie naeher, egal wie lange man
// darauf zufliegt, und lesen sich dadurch als aufgemaltes Hintergrundbild statt als
// Himmel. Den Wolkenhimmel tragen jetzt allein die echten, durchfliegbaren Schichten aus
// CloudField.
// NICHT GELOESCHT, sondern abgeschaltet: der ganze Block darunter haengt an dieser
// Bedingung, und weil das Uniform fuer JEDES Pixel denselben Wert hat, ueberspringt die
// GPU ihn geschlossen — es kostet also nichts. Wer sie zurueckwill, setzt hier 0.97.
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.0;
// Staerke der Netzverzerrung. Sie bricht die runden fbm-Blasen zu Wolkenumrissen auf.
// NICHT hochdrehen: bei 1.4 (erster Versuch) zieht sie ganze Gebiete zu Schlieren
// auseinander, das Ergebnis liest sich als zerrissener Cirrus statt als Kumulus.
uniform float cloud_warp : hint_range(0.0, 1.5) = 0.35;
// --- Plastik: Koerperform gegen Oberflaechenkorn ---------------------------------------
// Der Abstand, ueber den die Neigung der Wolkenoberflaeche gemessen wird, IN uv-EINHEITEN.
// Das ist die wichtigste Zahl dieses Abschnitts, und sie stand vorher auf 0.075.
// Warum das der Fehler war: eine Wolkenzelle ist rund 1 uv gross, die vierte Rauschoktave
// dagegen 0.12. Eine Differenz ueber 0.075 misst also fast nur die feinste Oktave. Genau
// deshalb war die Schattierung Gesprenkel und kein Koerper — nachgemessen trug die
// grossflaechige Varianz im Wolkeninneren nur 44 Prozent (Volumenwolken im selben Bild:
// 72 Prozent).
// Eine Differenz ueber e wirkt wie ein Tiefpass: eine Welle der Laenge L wird mit
// 2*sin(pi*e/L)/e gemessen statt mit ihrer wahren Steigung 2*pi/L. Mit e = 0.22 kommen
// heraus:
//   Wolkenzelle    L = 1.00  ->  92 % ihrer Steigung   (die Koerperform bleibt)
//   Lappen         L = 0.49  ->  70 %                  (die Buckel bleiben)
//   vierte Oktave  L = 0.12  ->   9 %                  (das Korn ist weg)
// Genau diese Trennung war der Sinn der Uebung. Zum Horizont hin waechst der Schritt
// weiter mit: dort liegen mehrere Rauschzellen auf einem Pixel, und eine feine Differenz
// waere nur noch Flimmern.
uniform float cloud_form_e : hint_range(0.05, 1.0) = 0.22;
// Wie stark das Relief die Normale insgesamt kippt.
// AM BILD eingemessen: mit Probeschuessen, in denen die Kennlinie unten auf eine STUFE bei
// N·L = tau festgenagelt wird, laesst sich die Verteilung von N·L im Wolkeninneren direkt
// ablesen — jeder Schuss liefert einen Punkt der Summenhaeufigkeit
// (tools/_sky_render.gd, Argument set=). Mit dem hier eingestellten Stand:
//   P(N·L < tau)   tau = 0.00  0.20  0.40  0.60  0.80
//   unter_decke            5 %  13 %  27 %  38 %  50 %
//   zenit                  5 %  11 %  27 %  48 %  78 %
// Ein Viertel der Wolkenflaeche sieht die Sonne also nur noch streifend oder gar nicht —
// das ist die Spanne, die es fuer eine Schattenseite braucht.
// HOEHER ZU DREHEN LOEST DAS PROBLEM NICHT. Ohne den Lappenterm gemessen, Kennlinie bei
// lo = 0.20: bump 1.5 -> p05 107 / Median 194, bump 3.0 -> p05 94 / Median 185. Die Spanne
// waechst zwar, aber der Median wandert mit nach unten — Kippen allein macht die Wolke
// insgesamt dunkler statt plastischer, weil es alles gleichmaessig neigt. Was fehlt, ist
// VARIATION, und die kommt aus der Form: siehe cloud_lobe.
uniform float cloud_bump : hint_range(0.0, 2.5) = 1.00;
// LAPPENHOEHE — die zweite Haelfte der Plastik, und ohne sie geht es nachweislich nicht.
// Die Kuppel aus koerper() allein liefert im Inneren einer grossen Wolke fast keine
// Neigung: bei Hoehe ~ sqrt(dichte - schwelle) ist die Steigung |grad n| / (2*sqrt(...)),
// also gerade dort klein, wo die Wolke dick ist. Steil wird es nur in einem schmalen Saum
// am Umriss. Im Bild sieht man das daran, dass die reine Kuppel die Spanne nur ueber ein
// insgesamt DUNKLERES Bild bekommt (Zahlen bei cloud_bump), nie ueber mehr Struktur.
// Mit Lappen und bump 1.0 dagegen: p05 94 bei Median 197 — dieselbe Spanne wie mit
// bump 3.0 ohne Lappen (p05 94), aber der Median steht 12 Werte hoeher und damit dort,
// wo die Volumenwolken ihn haben (205).
// Ein Kumulus besteht eben nicht aus einer Kuppel, sondern aus BUCKELN, jeder mit eigener
// Sonnen- und Schattenseite. Dieser Term legt sie auf die Kuppel.
// Es ist bewusst KEIN neues Rauschen, sondern genau die zweite Oktave desselben Feldes,
// aus dem der Umriss entsteht: die Buckel sitzen dadurch dort, wo die Wolke wirklich
// ausbeult, statt als fremdes Muster darueberzuliegen.
uniform float cloud_lobe : hint_range(0.0, 1.0) = 0.30;
// Die Beleuchtungskennlinie, in Einheiten von N·L: darunter voll im Schatten, darueber
// voll besonnt.
// Vorher stand hier EIN Wert, symmetrisch um sun_dir.y = 0.766 gelegt — eine waagerechte
// Stelle landete damit definitionsgemaess in der MITTE der Spanne. Das ist physikalisch
// falsch herum: eine waagerechte Wolkenoberkante steht bei 50 Grad Sonnenhoehe im vollen
// Licht, sie gehoert ins obere Drittel. Und weil zusaetzlich fast die ganze Flaeche im
// weissen Ende landete, blieb vom Schatten nichts uebrig.
// Die Grenzen sind AM BILD eingemessen. Dazu wurde zuerst die Kennlinie der
// Nachbelichtung bestimmt (Probeschuesse mit festgenageltem lit, Ansicht zenit):
//   lit  0.0  0.1  0.3  0.5  0.7  0.9  1.0
//   Bild  96  118  181  208  222  231  234
// Diese Kurve ist der Grund, warum die Wolken so hartnaeckig weiss blieben: oberhalb
// lit = 0.3 liegen nur noch 53 der 138 Bildwerte. Wer lit dort nicht unter 0.3 druecken
// kann, bekommt kein Volumen, egal wie er die Farben waehlt.
// Zusammen mit der gemessenen N·L-Verteilung (siehe cloud_bump) ergibt 0.18 / 1.18 im
// Wolkeninneren (Endstand, gegen den Stand vor dieser Runde):
//   Ansicht        p05        Median     p95        Spanne     Varianz
//   unter_decke    154 ->  94 211 -> 197 230 -> 234  77 -> 140  598 -> 1736
//   zenit          105 ->  84 208 -> 200 228 -> 233 123 -> 149 1309 -> 2950
//   sonne_frei     151 ->  90 213 -> 212 228 -> 234  77 -> 144  659 -> 2219
//   Volumenwolken   89        205        234        144        2445  <- Massstab,
//                                                            gleiches Bild, unveraendert
uniform float cloud_shade_lo : hint_range(-0.5, 0.5) = 0.18;
uniform float cloud_shade_hi : hint_range(0.5, 1.5) = 1.18;
// Luftperspektive AUF der Wolkenebene: e-Faltung nach 1/0.05 = 20 Ebeneneinheiten.
// Wolken nahe am Horizont laufen dadurch in den Dunst statt sich zu einem harten,
// flimmernden Band zu stapeln — und genau dort staucht die Projektion das Rauschen am
// staerksten, das wuerde sonst flirren.
uniform float cloud_aerial : hint_range(0.0, 0.4) = 0.050;

// --- Horizontband -------------------------------------------------------------------
// col_deep: Ton, in den der Himmel UNTER dem Horizont laeuft. Ziel ist der Farbwert,
// den das ferne Wasser nach Nebel und Tonemapping hat — dann ist die Weltkante weg.
// GEMESSEN eingestellt, nicht geschaetzt. Der Wert ist NICHT die Wasserfarbe: zwischen
// hier und dem Bild liegen Nebel-Himmelsanteil, ACES-Tonemapping (white 6) und
// adjustment_saturation 1.18 — Letzteres zieht Rot in einem blauen Ton stark herunter,
// weshalb der Rotanteil hier so hoch stehen muss. Kalibriert gegen das ferne Wasser
// am Plattenrand (sRGB 82/128/182); dieser Wert kommt als 81/129/181 heraus.
uniform vec3 col_deep : source_color = vec3(0.285, 0.405, 0.555);
// Ueber wie viel Blickwinkel (in dir.y) der Uebergang laeuft. 0.045 = gut 2,5 Grad.
// GEMESSEN gewaehlt: die Wasserplatte endet je nach Flughoehe bei dir.y -0.025 (110 m)
// bis -0.14 (620 m). Der Uebergang muss also schon VOR -0.025 durch sein, sonst steht
// die Kante wieder im Hellen. Kurz ist ausserdem richtig: Meer und Himmel treffen sich
// in echt auch an einer Linie, nicht ueber einen Verlauf.
uniform float band_depth : hint_range(0.02, 1.0) = 0.045;
uniform float band_strength : hint_range(0.0, 1.0) = 1.0;
// Dunstsaum direkt am Horizont (beidseitig), bindet Ferne und Himmel aneinander.
// SCHMAL halten: waere er breiter als band_depth, wuerde er die Fernwasser-Faerbung
// genau dort wieder aufhellen, wo die Weltkante steht — er arbeitete gegen sich selbst.
uniform vec3 col_haze : source_color = vec3(0.72, 0.82, 0.93);
uniform float haze_width : hint_range(0.005, 0.3) = 0.020;
uniform float haze_strength : hint_range(0.0, 1.0) = 0.40;

// Dither gegen Banding, in LINEAREN Einheiten.
//
// Der erste Ansatz stand hier auf 0.0045, hergeleitet aus der sRGB-Kennlinie — und war
// damit WIRKUNGSLOS: gemessen am Bild (Ansicht hoch, Blaukanal, Spalte 300) blieben
// Laeufe von bis zu 109 Pixeln mit exakt gleichem Wert stehen, also breite Streifen.
// Der Fehler war die Kennlinie: massgeblich ist nicht sRGB allein, sondern die GANZE
// Kette aus ACES (white 6), saturation 1.18, contrast 1.05 und sRGB. Die wurde an zwei
// bekannten Punkten des Bildes eingemessen (linear 0.380 -> 128, linear 1.279 -> 234)
// und laeuft dort wie sRGB_norm = (0.663 * linear)^0.5. Die ist im HELLEN viel flacher
// als reines sRGB, und genau im Hellen liegt der Blaukanal des Himmels (Zenit 0.80).
// Eine Stufe von 255 entspricht damit:
//     bei linear 0.80 (Zenitblau)      0.0086
//     bei linear 0.20 (dunkle Anteile) 0.0043
// 0.009 deckt also den ungünstigsten Kanal mit rund einer ganzen Stufe ab. Groesser
// waere im Dunklen als Korn sichtbar, kleiner bricht die Streifen im Zenit nicht auf.
uniform float dither_amp : hint_range(0.0, 0.03) = 0.009;

// --- Rauschen ------------------------------------------------------------------------
// Hash ohne sin (Hoskins). Der vorherige Hash (fract(p.x*p.y)) hat sichtbare Gitter-
// struktur entlang der Achsen; das faellt bei drei Oktaven kaum auf, bei vier sehr wohl
// — und die Beleuchtung unten bildet DIFFERENZEN des Feldes, das haette die Struktur
// noch verstaerkt.
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Wertrauschen mit QUINTISCHER Glaettung (6t^5-15t^4+10t^3). Die vorherige kubische
// Variante ist nur C1-stetig: an den Zellgrenzen springt die zweite Ableitung. Sichtbar
// wird das erst, seit die Beleuchtung aus einer DIFFERENZ zweier Rauschwerte kommt —
// dort haetten die Zellgrenzen als Rautenmuster in der Schattierung gestanden.
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash21(i), b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0)), d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Drehung zwischen den Oktaven (sin/cos 37 Grad). Ohne sie stapeln sich alle Oktaven auf
// denselben Achsen und das Ergebnis bekommt ein Karomuster.
const mat2 ROT = mat2(vec2(0.7986, 0.6018), vec2(-0.6018, 0.7986));

// 4 Oktaven, Verstaerkung 0.52 statt 0.45. Die hoeheren Oktaven tragen dadurch mehr bei
// — das ist es, was den Wolken ihre gebuckelten RAENDER gibt. Amplitudensumme
// 0.5+0.26+0.135+0.070 = 0.965, daher die Normierung 1.036.
// 4 Oktaven, Verstaerkung 0.46. Erster Ansatz stand auf 0.52: dann tragen alle Oktaven
// etwa gleich viel STEIGUNG bei (0.52 * 2.03 = 1.06 je Oktave), das Ergebnis ist eine
// fraktale Kuestenlinie — im Bild zerrissene Fetzen statt Wolken. Mit 0.46 faellt die
// Steigung je Oktave um gut 7 Prozent, die Umrisse werden rundlich und behalten trotzdem
// gebuckelte Raender. Amplitudensumme 0.5+0.23+0.106+0.049 = 0.885, daher 1.130.
// `tw` ist der Zeitversatz der ERSTEN Oktave. Er wird je Oktave mit 3.4 multipliziert,
// die Frequenz aber nur mit 2.03 — die Oktaven wandern also GEGENEINANDER. Waere der
// Faktor gleich (also tw genauso transformiert wie p), waere das Ergebnis exakt eine
// Verschiebung des ganzen Feldes: vnoise(R^k s^k (p + tw)) haengt dann nur von p + tw ab.
// Genau diese Falle war der alte Zustand, und sie ist im Bild als "starre Tapete"
// aufgefallen.
float fbm4(vec2 p, vec2 tw) {
	float s = 0.0, a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += a * vnoise(p + tw);
		p = ROT * p * 2.03;
		a *= 0.46;
		tw = ROT * tw * 3.4;
	}
	return s * 1.130;
}
float fbm3(vec2 p) {
	float s = 0.0, a = 0.5;
	for (int k = 0; k < 3; k++) { s += a * vnoise(p); p = ROT * p * 2.11; a *= 0.5; }
	return s * 1.143;
}

// Die Lappen: die zweite Oktave des Formfeldes, also genau das, was ROT * p * 2.03 in
// fbm4 als naechstes abtastet. Zellgroesse rund 0.49 uv — zwei bis drei Buckel je
// Wolkenzelle, das ist der Massstab, in dem ein Kumulus ausbeult.
// Frueher stand hier stattdessen eine Feinstruktur mit Frequenz 5.7 (Zelle 0.18 uv). Die
// ist eine Groessenordnung zu fein: sie hat die Normale bestimmt und damit das Gesprenkel
// erzeugt, das als "mottenzerfressene Papierbahn" aufgefallen ist.
float lappen(vec2 p) {
	return vnoise(ROT * p * 2.03);
}

// Aus der Dichte ueber der Schwelle wird die HOEHE des Wolkenkoerpers.
//
// Das ist der Kern des Ganzen und war die letzte fehlende Zutat. Nimmt man das Rauschen
// selbst als Hoehenfeld (so lief der dritte Versuch), schattiert man eine fraktale
// Landschaft — im Bild fleckige Fetzen. Eine Kumuluswolke ist aber keine Landschaft,
// sondern ein KOERPER, der auf der Wolkenebene aufsitzt. Fuer eine Kugelkappe der Dicke
// t ueber der Grundflaeche gilt Hoehe ~ sqrt(t): innen ein flaches Gewoelbe, und am Rand
// steht die Steigung senkrecht. Genau daher kommt der harte Schattenterminator an der
// abgewandten Flanke und der helle Buckel zur Sonne — die Lesart "prall".
float koerper(float dichte) {
	return sqrt(max(dichte - cloud_cover, 0.0));
}

// Vollstaendige Wolkenhoehe: Kuppel plus Lappen. Wird an drei Stellen gebraucht (Mitte
// und zwei Nachbarn), daher als Funktion — der Mittelpunkt teilt sich seine fbm4-Auswertung
// allerdings mit der Silhouette und wird deshalb unten von Hand zusammengesetzt.
//
// KOSTEN, weil das hier ein sky-Shader ist und ueber das ganze Bild laeuft: der
// Wolkenblock braucht 20 vnoise-Auswertungen je Pixel — 4 fuer die Silhouette, 2 mal 5
// fuer die Nachbarn, 1 fuer die Lappen in der Mitte, 3 fuer die Ballung, 2 fuer die
// Netzverzerrung. Das ist EXAKT so viel wie vorher (damals 3 mal fbm4 plus 3 Feinkorn plus
// 2 plus 3): die Plastik kostet nichts, sie war nur falsch verteilt. Keine Schleife ueber
// Dutzende Oktaven, kein Raymarching.
float hoehe(vec2 p, vec2 tw, float ballung) {
	return koerper(fbm4(p, tw) + ballung) + cloud_lobe * lappen(p);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	float up = clamp(dir.y, -1.0, 1.0);
	// ENTSCHEIDEND fuer das Horizontband: unterhalb des Horizonts ist u == 0, der
	// Verlauf liefert dort also unveraendert col_horizon (siehe Kopfkommentar).
	float u = max(up, 0.0);

	// --- (a) Verlauf: zwei ueberlagerte Exponentialabfaelle ---------------------------
	// Der breite Term traegt den Raum (Zenit -> Mitte), der schmale den Dunst direkt
	// ueber dem Horizont. Beide sind glatt, es gibt keinen Knick, an dem Banding
	// ansetzen koennte.
	vec3 sky_col = mix(col_zenith, col_mid, exp(-u * grad_mid));
	sky_col = mix(sky_col, col_horizon, exp(-u * grad_hz));

	// --- (b) Sonne: Scheibe + enger Glast + weiter Hof --------------------------------
	float sdot = dot(dir, sd);
	// Winkelabstand zur Sonne. sqrt(2(1-cos t)) = 2 sin(t/2): bis 30 Grad auf 1 % genau
	// und billiger als acos. Genauer muss es fuer einen Helligkeitsabfall nicht sein.
	float ang = sqrt(max(2.0 * (1.0 - sdot), 0.0));
	// Scheibe mit weichem Saum ueber 35 % des Radius — hart geschnitten flimmert sie
	// beim Kameraschwenk, MSAA greift bei einem Shader nicht.
	float disc = 1.0 - smoothstep(sun_size, sun_size * 1.35, ang);
	// Zwei Exponentialen: der enge (auf 1/e nach 1.7 Grad) macht den gleissenden Kern,
	// der weite (nach 6.4 Grad) den warmen Uebergang zum Himmel. Ein einzelner Abfall
	// kann beides nicht — deshalb war der alte pow(sdot,5)-Hof unsichtbar: so breit,
	// dass er nirgends genug Amplitude hatte, um sich gegen den Himmel durchzusetzen.
	float glast = exp(-ang * 34.0) * 0.90 + exp(-ang * 9.0) * 0.35;
	// Weiter Hof, auf 1/e nach rund 26 Grad. Der waermt die ganze Sonnenhaelfte des
	// Himmels gegen die kalte Gegenseite auf — das ist der eigentliche Tiefenhinweis,
	// viel mehr als die Scheibe selbst.
	float hof = exp(-ang * 2.2);
	// Unterhalb des Horizonts steht kein Himmel mehr, sondern der Ersatzton fuer fernes
	// Wasser. Wuerde der Hof dort weiterleuchten, verschoebe er genau den Wert, gegen
	// den col_deep kalibriert ist — nachgerechnet 2.8 von 255 bei dir.y knapp unter 0.
	// Die untere Kante liegt deshalb EXAKT auf 0: fuer dir.y <= 0 ist der Beitrag
	// bitgenau null, und smoothstep hat an seinen Enden Steigung 0, der Anschluss bei
	// dir.y = 0 bleibt also knickfrei. Die 0.05 (gut 2,9 Grad) sind so breit gewaehlt,
	// dass das Einblenden ueber rund 36 Bildzeilen laeuft und nicht als Saum auffaellt.
	float ueber_horizont = smoothstep(0.0, 0.05, up);
	sky_col += (sun_col * disc * sun_energy
			+ sun_halo * glast * halo_energy
			+ sun_halo * hof * hof_energy) * ueber_horizont;

	// --- (c) Gemalte Fernwolken -------------------------------------------------------
	if (cloud_opacity > 0.001 && dir.y > 0.012) {
		// Projektion auf eine Ebene ueber dem Auge, danach LOGARITHMISCH gestaucht.
		// Warum die Stauchung: die reine Ebenenprojektion dir.xz/dir.y laeuft am
		// Horizont gegen unendlich (Rauschen flirrt), der alte Deckel (dir.y + 0.22)
		// dagegen begrenzt sie auf lachhafte 4.5 Einheiten (Rauschen wird zum Fleck).
		// log(1 + d * cloud_persp) macht beides richtig: nahe dem Zenit ist der Massstab
		// cloud_persp * cloud_scale = 8.4 pro Ebeneneinheit, und zum Horizont hin waechst
		// der Radius nur noch logarithmisch — beim dir.y-Deckel 0.045, also d = 22, auf
		// log(67) * 2.8 = 11.8. Ueber den ganzen sichtbaren Himmel liegen damit rund
		// 12 Rauschzellen statt der knapp vier von vorher. Wolken werden zum Horizont hin
		// kleiner und draengen sich zusammen, wie die Perspektive es verlangt, ohne dass
		// das Rauschen je unter die Pixelaufloesung faellt und flirrt.
		float t = cloud_clock < 0.0 ? TIME : cloud_clock;
		float yy = max(dir.y, 0.045);
		// WIND: Versatz IN DER EBENE, also vor der Stauchung — siehe cloud_wind. Die
		// Richtung ist auf Laenge 1 gebracht, damit cloud_wind wirklich Ebeneneinheiten
		// je Sekunde bedeutet und nicht irgendetwas Schraeges.
		vec2 eben = dir.xz / yy + normalize(vec2(1.0, 0.55)) * (cloud_wind * t);
		float d = length(eben);
		vec2 uv = eben * (log(1.0 + d * cloud_persp) / max(d, 1e-4)) * cloud_scale;

		// Luftperspektive frueh, weil sie unten auch die Reliefaufloesung steuert.
		float ferne = 1.0 - exp(-d * cloud_aerial);

		// Netzverzerrung: verbiegt das Koordinatennetz, bevor die Form entsteht. Ohne
		// sie bleibt fbm rundlich-blasig; mit ihr bekommen die Umrisse Einbuchtungen
		// und Auswuechse, also Wolkenform. Einmal berechnet und fuer alle drei
		// Abtastungen unten wiederverwendet — sie ist niederfrequent, der Fehler durch
		// das Wiederverwenden liegt weit unter der Reliefaufloesung.
		vec2 warp = vec2(vnoise(uv * 0.9), vnoise(uv * 0.9 + vec2(4.7, 2.1))) - 0.5;
		vec2 q = uv + warp * cloud_warp;
		// Ballung: sehr grobes Rauschen, ADDITIV. Additiv verschiebt die Schwelle
		// ortsabhaengig, ganze Gebiete fallen also komplett unter cloud_cover (blanker
		// Himmel) und andere komplett darueber (dichtes Feld). Multiplikativ haette nur
		// die Deckkraft moduliert und ueberall duennen Schleier stehen lassen.
		// Amplitude 0.75, nicht 0.55: bei 0.55 liegt das ganze Feld so dicht an der
		// Schwelle, dass ueberall duenne Fetzen entstehen, die gerade eben ueberstehen.
		// Mit 0.75 kippen ganze Gebiete klar unter oder klar ueber die Schwelle — dort
		// blanker Himmel, hier dicke Ballen. Das ist der Unterschied zwischen "verteiltes
		// Rauschen" und "Schoenwetterkumulus in Feldern".
		// Die Ballung bekommt einen EIGENEN, langsamen Zeitversatz in eine andere Richtung
		// als der Wind. Sie entscheidet, wo ueberhaupt Wolke ist — wandert sie, dann
		// wachsen an einer Stelle Wolken auf und loesen sich an einer anderen auf, statt
		// dass immer dieselben Ballen vorbeiziehen. Faktor 15 gegenueber cloud_evolve:
		// ihre Zellen sind im fbm3-Argument 1 gross, mit 0.0045 je Sekunde also 18 Prozent
		// einer Zelle in 40 s — sichtbar an den Raendern, aber kein Aufploppen.
		vec2 bw = vec2(0.30, -0.95) * (t * cloud_evolve * 15.0);
		float ballung = (fbm3(uv * 0.30 + vec2(17.3, 5.1) + bw) - 0.5) * 0.75;

		// Zeitversatz der Oktaven (siehe cloud_evolve und fbm4). Richtung bewusst quer
		// zum Wind, sonst laesst sich Entwicklung nicht von Verschiebung unterscheiden.
		vec2 tw = normalize(vec2(-0.55, 1.0)) * (cloud_evolve * t);

		// KOERPERFORM. Der Messabstand ist lang (cloud_form_e) — das ist der ganze Punkt,
		// siehe dort. Zum Horizont hin waechst er weiter, weil dort mehrere Rauschzellen
		// auf einem Pixel liegen und eine kurze Differenz nur noch Flimmern waere.
		float e = mix(cloud_form_e, cloud_form_e * 1.8, ferne);
		float f0 = fbm4(q, tw);
		float n = f0 + ballung;          // Silhouette
		// Die Ballung ist niederfrequent und wird fuer alle drei Abtastungen wiederverwendet;
		// ueber den Abstand e aendert sie sich um Groessenordnungen weniger als die Form.
		// Der Mittelpunkt teilt sich seine fbm4-Auswertung mit der Silhouette — deshalb
		// hier von Hand statt hoehe(q, ...): das spart eine ganze fbm4-Auswertung.
		float h0 = koerper(n) + cloud_lobe * lappen(q);
		float hx = hoehe(q + vec2(e, 0.0), tw, ballung);
		float hz = hoehe(q + vec2(0.0, e), tw, ballung);

		float dens = smoothstep(cloud_cover, cloud_cover + cloud_soft, n);
		dens *= smoothstep(0.020, 0.100, dir.y);    // unterster Streifen: Dunst statt Wolke

		// BELEUCHTUNG. Aus den zwei Nachbarabtastungen entsteht die Neigung der
		// Wolkenoberflaeche, daraus eine Normale im WELTsystem: die uv-Achsen sind x und z,
		// die Wolkenebene liegt waagerecht, also zeigt die ungestoerte Normale nach +Y.
		// Damit ist dot(nrm, sd) ein echtes N·L mit dem Sonnenstand aus dem Uniform —
		// Schattenrichtung im Gelaende, Wasserglitzer und Wolkenplastik koennen gar nicht
		// auseinanderlaufen.
		vec2 g = vec2(hx - h0, hz - h0) / e * cloud_bump;
		vec3 nrm = normalize(vec3(-g.x, 1.0, -g.y));
		float ndl = dot(nrm, sd);
		// Kennlinie direkt in N·L, asymmetrisch — Herleitung bei cloud_shade_lo/hi.
		float lit = smoothstep(cloud_shade_lo, cloud_shade_hi, ndl);
		// Silberrand: wo die Wolke duenn ist (dens zwischen 0 und 1) und die Flanke zur
		// Sonne zeigt, reisst der Rand auf. Das ist das Detail, an dem das Auge "Wolke"
		// erkennt statt "weisser Fleck". Deutlich schwaecher als vorher (0.9): der Bezug
		// ist jetzt N·L selbst statt N·L - sd.y, der Term wuerde sonst die halbe
		// Wolkenflanke mit aufhellen und die eben erst gewonnene Spanne wieder zudecken.
		lit += dens * (1.0 - dens) * 4.0 * max(ndl, 0.0) * 0.30;
		// Von unten sieht man die Basis, von der Seite die besonnte Flanke — im Zenit
		// also dunkler. Klein halten, sonst kippt der Himmel oben ins Graue.
		lit -= smoothstep(0.20, 0.85, dir.y) * 0.14;
		// Gegenlicht: dicht an der Sonne wird auch die Schattenseite durchleuchtet.
		// Hohe Potenz, damit das nur die Wolken direkt vor der Sonne betrifft und nicht
		// die halbe Bildhaelfte weisswaescht (so war es im ersten Versuch).
		float geg = max(sdot, 0.0);
		geg *= geg; geg *= geg; geg *= geg;                    // sdot^8
		lit = mix(lit, 1.0, geg * 0.35);
		vec3 ccol = mix(cloud_dark, cloud_lit * cloud_gain, clamp(lit, 0.0, 1.0));

		// Entfernte Wolken verlieren Kontrast und Deckkraft und laufen in den Dunstton.
		ccol = mix(ccol, col_haze, ferne * 0.62);
		dens *= 1.0 - ferne * 0.30;

		sky_col = mix(sky_col, ccol, dens * cloud_opacity);
	}

	// --- HORIZONTBAND: Weltkante aufloesen ---------------------------------------
	// 1) unter dem Horizont in den Fernwasser-Ton laufen. smoothstep haelt den Anschluss
	//    bei dir.y = 0 ableitungsfrei -> kein zweiter sichtbarer Knick.
	float below = smoothstep(0.0, 1.0, clamp(-up / band_depth, 0.0, 1.0));
	sky_col = mix(sky_col, col_deep, below * band_strength);
	// 2) Dunstsaum um den Horizont. Liegt NACH den Wolken, damit auch sie dort weich
	//    wegtauchen — genau wie echte Wolken in der Luftperspektive.
	float haze = exp(-abs(up) / haze_width);
	sky_col = mix(sky_col, col_haze, haze * haze_strength);

	// Dither ganz zum Schluss, auf dem fertigen Wert — aber STRIKT nur oberhalb des
	// Horizonts: unterhalb liegt der gegen das ferne Wasser kalibrierte Ton, dort darf
	// nichts wackeln (siehe Kopfkommentar). step() statt smoothstep, weil ein weicher
	// Uebergang hier nichts brachte: 0.002 Rauschen mehr oder weniger sieht niemand,
	// eine harte Aussage ueber den Bereich unter dem Horizont dagegen schon.
	// Das Muster haengt an den Bildschirmpixeln, nicht an der Blickrichtung — sonst
	// schwimmt es beim Schwenken mit und wird als Kribbeln sichtbar.
	sky_col += (hash21(SCREEN_UV * vec2(1731.0, 1093.0)) - 0.5) * dither_amp * step(0.0, up);

	COLOR = sky_col;
}
