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
