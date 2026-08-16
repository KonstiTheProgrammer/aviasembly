## ECHTE AUSDEHNUNG VON BAUTEILEN — gegen das Katalog-Feld `size`, das luegt.
##
## Beim Zusammenbau eines Flugzeugs braucht man den URSPRUNG eines Teils relativ zu
## seiner Geometrie: nur so laesst sich von "diese Station soll hierhin" auf den zu
## setzenden Wert schliessen. `size` im Katalog gibt das NICHT her — es ist eine
## Huellbox, und wo darin der Ursprung sitzt, steht nirgends.
## Konkret gekostet hat das eine ganze Runde am Me-262-Entwurf: `me262_body` hat
## size.z = 6.65, liegt aber NICHT mittig (z von -2.88 bis +3.72, Ursprung bei 44 %).
## Wer mit der Mitte rechnet, setzt alles um 0,42 m zu weit vorn.
##
## Godot --path . --script res://tools/_aabb_me262.gd
extends SceneTree
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var root3 := Node3D.new()
	get_root().add_child(root3)
	for id in ["wheel_jet", "me262_body", "autocannon", "wheel_nose", "v_stab", "h_stab", "wing_swept", "jet_engine"]:
		var p := PartCatalog.get_part(id)
		var n := PartCatalog.build_visual(p)
		root3.add_child(n)
		var ab := AABB()
		var erst := true
		for c in n.find_children("*", "VisualInstance3D", true, false):
			var vi := c as VisualInstance3D
			var w: AABB = vi.global_transform * vi.get_aabb()
			ab = w if erst else ab.merge(w)
			erst = false
		print("%-12s  x[%6.2f..%6.2f]  y[%6.2f..%6.2f]  z[%6.2f..%6.2f]   Katalog-size=%s"
			% [id, ab.position.x, ab.end.x, ab.position.y, ab.end.y, ab.position.z, ab.end.z,
				str(p.get("size", Vector3.ONE))])
		n.queue_free()
	quit()
	return true
