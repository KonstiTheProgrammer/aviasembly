class_name ShowroomStage
extends Node3D
## Praesentations-Buehne des Bau-Modus: dunkler Petrolraum mit Blueprint-Boden,
## Drei-Punkt-Licht und Vignette. Buendelt alles, was frueher verstreut in Main.gd
## stand (env_blueprint, hangar_lights, blueprint_grid), in EINEN Knoten.
##
## WARUM DIE UMSTELLUNG: der Bau-Modus stand vorher unter einem hellen Tageshimmel
## mit drei schattenlosen Aufhellern. Das war eine bewusste fruehere Entscheidung
## ("keine Schatten"), die die jetzige Vorgabe ausdruecklich umdreht — verlangt sind
## dunkler Hintergrund, gerichtetes Dreipunktlicht und kraeftige Kontaktschatten.
##
## Die Palette steht hier zentral, damit UI und 3D dieselben Farben benutzen und
## nicht an zwanzig Stellen einzeln nachgezogen werden muessen.

# --- Palette -----------------------------------------------------------------
const BG            := Color("#173D46")   # Hintergrund, dunkles Petrol
const BODEN         := Color("#0A2129")   # Boden; deutlich dunkler als BG, weil ihn der Key aufhellt
const HIMMEL_OBEN   := Color("#0C2029")   # Hintergrund oben, dunkel
const HIMMEL_HORIZONT := Color("#1A4753") # Hintergrund am Horizont — auf den vernebelten Boden abgestimmt
const RASTER        := Color("#4FD2DE")   # Blueprint-Linien, Cyan
const KEY           := Color("#FFF0D8")   # warmes Creme
const FILL          := Color("#8CCBD8")   # kuehles Petrol
const RIM           := Color("#DAF2FF")   # neutralweiss, leicht cyan
const AKZENT        := Color("#E8823C")   # Orange, aktive UI-Elemente
const AKZENT_KALT   := Color("#7FE3EE")   # helles Cyan, inaktiv/Auswahl
const TEXT          := Color("#F2EBDD")   # cremeweiss
const KONTUR        := Color("#DDF4EA")   # Auswahlkontur

# Sichtbare Kantenlaenge des feinen Rasters in Metern.
const RASTER_ZELLE := 1.0

var environment: Environment
var boden: MeshInstance3D
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var rim_light: DirectionalLight3D

var _vignette_layer: CanvasLayer
var _sichtbar := true


func _init() -> void:
	name = "ShowroomStage"


func _ready() -> void:
	environment = _baue_environment()
	_baue_licht()
	_baue_boden()
	_baue_vignette()
	set_stage_visible(false)


# --- Environment -------------------------------------------------------------
func _baue_environment() -> Environment:
	var env := Environment.new()
	# Flache Hintergrundfarbe statt Himmel: die Buehne soll ein Raum sein, kein
	# Aussenraum. BG dient zugleich als Reflexionsquelle, sonst saufen alle
	# metallischen Teile zu Schwarz ab.
	# VERLAUFSHIMMEL statt flacher Farbe. Mit BG_COLOR liess sich der Horizont nicht
	# aufloesen: Godot nimmt background_color linear, unter AgX rendert das dunkle
	# Petrol dann fast schwarz — und die Nebelfarbe folgt dem Hintergrund-Multiplikator
	# NICHT, beide waren also nie zur Deckung zu bringen. Ein Verlauf, dessen
	# Horizontton dem vernebelten Boden entspricht, loest die Kante von selbst auf und
	# dient nebenbei als Ambient- und Reflexionsquelle.
	var himmel := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = HIMMEL_OBEN
	psm.sky_horizon_color = HIMMEL_HORIZONT
	psm.ground_horizon_color = HIMMEL_HORIZONT
	psm.ground_bottom_color = BODEN
	psm.sky_energy_multiplier = 1.0
	psm.sky_curve = 0.25                       # weicher Uebergang, kein harter Farbsprung
	psm.ground_curve = 0.20
	himmel.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = himmel
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# AgX haelt helle Kanten und Lichtsaeume zusammen, ohne die Farben auszubleichen.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0                 # fest, KEINE Auto-Belichtung
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.14
	env.adjustment_saturation = 1.08
	env.adjustment_brightness = 1.0

	# Sehr dezenter Nebel: laesst Raster und Hintergrund ineinander laufen, damit am
	# Rand der Bodenflaeche keine harte Horizontkante steht.
	# Der Nebel ist hier KEIN Wettereffekt, sondern das Mittel gegen die harte
	# Horizontkante: der beleuchtete Boden muss zum Rand hin in die Hintergrundfarbe
	# laufen. Mit zu wenig Dichte stand vorher eine sichtbare Trennlinie im Bild.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = BG
	env.fog_density = 0.0260
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0

	# Glow nur fuer wirklich helle Kanten (Auswahlkontur, UI-Akzente) — der hohe
	# Schwellwert verhindert, dass die ganze Szene zu leuchten anfaengt.
	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_strength = 0.9
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.30
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# SSAO liefert die Kontaktabdunklung in Ecken und unter dem Fahrwerk. Nur unter
	# Forward+ sinnvoll; unter Mobile/Compatibility wird es still ignoriert.
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.ssao_radius = 0.85
	env.ssao_power = 1.6
	env.ssao_light_affect = 0.15
	return env


# --- Drei-Punkt-Licht --------------------------------------------------------
func _baue_licht() -> void:
	# Rotationen sind auf die Standard-Bauansicht bezogen (Kamera-Azimut ~40 Grad):
	# Key kommt von links vorn oben, Fill von rechts vorn, Rim von hinten oben.
	key_light = DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation_degrees = Vector3(-40, -14, 0)
	key_light.light_color = KEY
	key_light.light_energy = 1.55
	key_light.shadow_enabled = true
	# Weiche Schatten: angular_distance verbreitert den Halbschatten mit dem Abstand
	# zum Werfer — das gibt den kraeftigen, aber weichen Kontaktschatten der Vorgabe.
	key_light.light_angular_distance = 1.8
	key_light.shadow_blur = 1.35
	key_light.directional_shadow_max_distance = 46.0
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key_light.shadow_normal_bias = 1.4
	key_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(key_light)

	fill_light = DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.rotation_degrees = Vector3(-16, 96, 0)
	fill_light.light_color = FILL
	fill_light.light_energy = 0.48               # ~31 % des Key
	fill_light.shadow_enabled = false
	fill_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill_light)

	rim_light = DirectionalLight3D.new()
	rim_light.name = "RimLight"
	rim_light.rotation_degrees = Vector3(-52, 212, 0)
	rim_light.light_color = RIM
	rim_light.light_energy = 0.95                # ~61 % des Key -> klare Silhouette
	rim_light.shadow_enabled = false
	rim_light.light_specular = 1.4               # Kantenlicht darf glaenzen
	rim_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(rim_light)


# --- Blueprint-Boden ---------------------------------------------------------
func _baue_boden() -> void:
	boden = MeshInstance3D.new()
	boden.name = "BlueprintFloor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(220, 220)
	# Unterteilung, damit der Nebel ueber die Flaeche interpoliert statt zu kippen.
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	boden.mesh = pm
	boden.position = Vector3(0, -1.9, 0)
	boden.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/blueprint_floor.gdshader")
	sm.set_shader_parameter("grund_farbe", BODEN)
	sm.set_shader_parameter("linien_farbe", RASTER)
	sm.set_shader_parameter("zelle", RASTER_ZELLE)
	# Bewusst am unteren Ende der 8-18-%-Vorgabe: im Test war das Raster als kraeftiges
	# Cyan-Netz viel zu praesent und zog den Blick vom Flugzeug weg.
	sm.set_shader_parameter("fein_staerke", 0.042)
	sm.set_shader_parameter("haupt_staerke", 0.105)
	sm.set_shader_parameter("fade_start", 8.0)
	sm.set_shader_parameter("fade_ende", 40.0)
	boden.material_override = sm
	add_child(boden)


# --- Vignette ----------------------------------------------------------------
func _baue_vignette() -> void:
	_vignette_layer = CanvasLayer.new()
	_vignette_layer.name = "VignetteLayer"
	# Unter der Bedien-UI (die liegt bei Layer 0 bzw. darueber), aber ueber der 3D-Szene.
	_vignette_layer.layer = -1
	var rect := ColorRect.new()
	rect.name = "Vignette"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://shaders/vignette.gdshader")
	vm.set_shader_parameter("farbe", Color(0.02, 0.055, 0.066, 1.0))
	rect.material = vm
	_vignette_layer.add_child(rect)
	add_child(_vignette_layer)


# --- Sichtbarkeit ------------------------------------------------------------
func set_stage_visible(b: bool) -> void:
	## Schaltet die ganze Buehne. Eigene Methode, weil die Vignette in einem
	## CanvasLayer haengt und der sich NICHT ueber die 3D-Sichtbarkeit mitschalten
	## laesst — `visible` am Node3D wuerde sie einfach stehen lassen.
	_sichtbar = b
	visible = b
	if _vignette_layer != null:
		_vignette_layer.visible = b


func is_stage_visible() -> bool:
	return _sichtbar
