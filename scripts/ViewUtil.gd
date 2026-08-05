class_name ViewUtil
## Ultrawide-bewusster Kamera-FOV.
##
## `vfov_16x9` ist der gewünschte VERTIKALE Sichtwinkel, ausgelegt für 16:9. Auf Schirmen,
## die BREITER als 16:9 sind (21:9, 32:9-Ultrawide), bläht ein fester vertikaler FOV den
## horizontalen FOV extrem auf (32:9 -> ~132° horizontal) → Fischaugen-Verzerrung, alles
## wirkt horizontal gestreckt (runder Rumpf sieht elliptisch aus). Lösung (Hybrid „Hor+"):
## ab >16:9 wird der HORIZONTALE FOV auf den 16:9-Wert festgenagelt (KEEP_WIDTH), der
## vertikale schrumpft stattdessen. So bleibt 16:9 (und schmaler) exakt wie bisher, und
## Ultrawide zeigt mehr Breite OHNE Verzerrung — runde Teile bleiben rund.
const REF_ASPECT := 16.0 / 9.0


static func apply_vfov(cam: Camera3D, vfov_16x9: float) -> void:
	if cam == null:
		return
	var aspect := REF_ASPECT
	var vp := cam.get_viewport()
	if vp != null:
		var sz := vp.get_visible_rect().size
		aspect = sz.x / maxf(sz.y, 1.0)
	if aspect > REF_ASPECT:
		# breiter als 16:9 -> horizontalen FOV auf den 16:9-Wert nageln (kein Aufblähen)
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(vfov_16x9 * 0.5)) * REF_ASPECT))
	else:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.fov = vfov_16x9


# Tatsächlicher VERTIKALER Öffnungswinkel (rad), wie er WIRKLICH auf dem Schirm steht.
# Bei KEEP_WIDTH (Ultrawide) ist cam.fov der horizontale FOV -> hier zurückgerechnet.
# Für FOV-sicheres Kamera-Framing (z. B. wie tief der Flieger im Bild sitzt).
static func actual_vfov_rad(cam: Camera3D) -> float:
	if cam == null:
		return deg_to_rad(60.0)
	if cam.keep_aspect == Camera3D.KEEP_HEIGHT:
		return deg_to_rad(cam.fov)
	var aspect := REF_ASPECT
	var vp := cam.get_viewport()
	if vp != null:
		var sz := vp.get_visible_rect().size
		aspect = sz.x / maxf(sz.y, 1.0)
	return 2.0 * atan(tan(deg_to_rad(cam.fov) * 0.5) / aspect)


# Kamera-Abstand, bei dem `box` den gewuenschten Anteil des Bildes einnimmt.
#
# Die Ausdehnung wird auf die ECHTEN Bildachsen projiziert (Rechts/Hoch der Kamera).
# Eine Abschaetzung ueber box.size allein geht je nach Blickwinkel deutlich daneben —
# im ersten Anlauf fuellte das Flugzeug dadurch nur ~45 % statt der gewuenschten 60 %.
static func fit_distance(box: AABB, vfov_rad: float, aspect: float, dir: Vector3,
		breiten_anteil: float, hoehen_anteil: float) -> float:
	var rechts := Vector3.UP.cross(dir)
	if rechts.length_squared() < 0.000001:
		rechts = Vector3.RIGHT
	rechts = rechts.normalized()
	var hoch := dir.cross(rechts).normalized()
	var c := box.get_center()
	var hb := 0.0
	var hh := 0.0
	for i in range(8):
		var ecke := box.position + box.size * Vector3(
			float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))
		var v := ecke - c
		hb = maxf(hb, absf(v.dot(rechts)))
		hh = maxf(hh, absf(v.dot(hoch)))
	var t := tan(vfov_rad * 0.5)
	var d_breite := (hb * 2.0 / maxf(breiten_anteil, 0.05)) / (2.0 * t * aspect)
	var d_hoehe := (hh * 2.0 / maxf(hoehen_anteil, 0.05)) / (2.0 * t)
	return maxf(d_breite, d_hoehe)
