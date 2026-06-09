## FlightAudio.gd — prozedurale Flug-Sounds OHNE externe Assets (AudioStreamGenerator):
## - Triebwerks-Brummen: Pitch & Lautstärke folgen der Triebwerksleistung (Spool);
##   Props = tiefes Brummen mit Obertönen, Jets = Rausch-lastig + Pfeifton, Nachbrenner
##   legt Rumpeln drauf.
## - Windrauschen: Lautstärke & "Helligkeit" (Tiefpass) wachsen mit dem Tempo.
## - Stall-Warnton: gepulster Piep im Strömungsabriss.
## Headless-sicher: alle Playback-Zugriffe geguardet (Dummy-Audiotreiber liefert null/0).
class_name FlightAudio
extends Node

const RATE := 22050.0

# Vom FlightController je Frame gesetzt:
var active := false            # false = Stille pushen (Hangar/inaktiv)
var spool := 0.0               # Triebwerksleistung 0..1 (eilt der Drossel nach)
var ab := 0.0                  # Nachbrenner 0..1
var is_jet := false            # überwiegend Düsentriebwerke?
var has_engine := true
var airspeed := 0.0
var stall := false

var _engine: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _warn: AudioStreamPlayer
var _ph1 := 0.0                # Triebwerks-Grundton-Phase
var _phj := 0.0                # Jet-Pfeifton-Phase
var _phw := 0.0                # Warnton-Phase
var _warn_t := 0.0             # Warnton-Puls-Timer
var _lp := 0.0                 # Wind-Tiefpass-Zustand
var _lpe := 0.0                # Engine-Rausch-Tiefpass
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_engine = _make_player(-9.0)
	_wind = _make_player(-11.0)
	_warn = _make_player(-12.0)
	_rng.randomize()


func _make_player(db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = 0.12
	p.stream = g
	p.volume_db = db
	add_child(p)
	p.play()
	return p


func _process(_d: float) -> void:
	_fill_engine()
	_fill_wind()
	_fill_warn()


# Sicher das Playback holen (headless/Dummy-Treiber -> null) und Frames zählen.
func _playback(p: AudioStreamPlayer) -> AudioStreamGeneratorPlayback:
	if p == null or not p.playing:
		return null
	var pb := p.get_stream_playback()
	return pb as AudioStreamGeneratorPlayback


func _fill_engine() -> void:
	var pb := _playback(_engine)
	if pb == null:
		return
	var n := pb.get_frames_available()
	if n <= 0:
		return
	if not active or not has_engine:
		_push_silence(pb, n)
		return
	# Grundton: Props tief (38..95 Hz), Jets höher (85..240 Hz); Lautstärke folgt Spool.
	var f := (85.0 + spool * 155.0) if is_jet else (38.0 + spool * 57.0)
	var inc := TAU * f / RATE
	var incj := TAU * (900.0 + spool * 1400.0) / RATE      # Jet-Pfeifton (leise)
	var vol := 0.06 + spool * (0.55 if is_jet else 0.62) + ab * 0.25
	var nmix := (0.34 + ab * 0.5) if is_jet else 0.12      # Rausch-Anteil
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		_ph1 = fmod(_ph1 + inc, TAU)
		_phj = fmod(_phj + incj, TAU)
		var nz := _rng.randf_range(-1.0, 1.0)
		_lpe += (nz - _lpe) * 0.22                           # dunkles Rauschen (Tiefpass)
		var s := sin(_ph1) * 0.42 + sin(_ph1 * 2.01) * 0.2 + sin(_ph1 * 3.02) * 0.09
		s += _lpe * nmix
		if is_jet:
			s += sin(_phj) * 0.05 * spool                    # feines Turbinen-Pfeifen
		s *= vol
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)


func _fill_wind() -> void:
	var pb := _playback(_wind)
	if pb == null:
		return
	var n := pb.get_frames_available()
	if n <= 0:
		return
	var amp := clampf((airspeed - 8.0) / 130.0, 0.0, 1.0)
	if not active or amp <= 0.001:
		_push_silence(pb, n)
		return
	amp = pow(amp, 1.3) * 0.8
	# Tiefpass-Rauschen: mit Tempo wird der Wind "heller" (höherer Cutoff).
	var k := clampf(0.06 + airspeed / 320.0, 0.06, 0.55)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var nz := _rng.randf_range(-1.0, 1.0)
		_lp += (nz - _lp) * k
		var s := _lp * amp
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)


func _fill_warn() -> void:
	var pb := _playback(_warn)
	if pb == null:
		return
	var n := pb.get_frames_available()
	if n <= 0:
		return
	if not active or not stall:
		_warn_t = 0.0
		_push_silence(pb, n)
		return
	# Gepulster Piep (850 Hz, 5 Hz Puls) — klassische Stall-Warnung.
	var inc := TAU * 850.0 / RATE
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		_phw = fmod(_phw + inc, TAU)
		_warn_t += 1.0 / RATE
		var on := fmod(_warn_t, 0.2) < 0.105
		var s := (sin(_phw) * 0.3) if on else 0.0
		buf[i] = Vector2(s, s)
	pb.push_buffer(buf)


func _push_silence(pb: AudioStreamGeneratorPlayback, n: int) -> void:
	var buf := PackedVector2Array()
	buf.resize(n)        # Vector2.ZERO-initialisiert
	pb.push_buffer(buf)
