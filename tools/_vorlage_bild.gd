## Eine Vorlage im Hangar OHNE UI rendern: Draufsicht, Frontansicht, Dreiviertel.
##
##   HOME=/tmp/avi_home Godot --path . --script res://tools/_vorlage_bild.gd -- f4
## Bilder: user://vorlage_<id>_oben.png, _front.png, _34.png
extends SceneTree

var m: Node = null
var f := 0
var id := "f4"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		id = args[0]


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	var bc = m.get("build_ctrl")
	match f:
		20:
			m.call("_load_design_from", "res://designs/%s.json" % id)
			for c in m.find_children("*", "CanvasLayer", true, false):
				(c as CanvasLayer).visible = false
			bc.set("praesent_versatz", 0.0)
			bc.set_view(3)
			bc.set("orbit_dist", 16.0)
		30:
			_bild("oben")
			bc.set_view(1)
		40:
			_bild("front")
			bc.set_view(0)
			bc.set("orbit_yaw", deg_to_rad(35.0))
			bc.set("orbit_pitch", deg_to_rad(22.0))
			bc.set("orbit_dist", 17.0)
			bc.set("_ruhe_zeit", 0.0)
		50:
			_bild("34")
			quit()
	return false


func _bild(art: String) -> void:
	var name := "vorlage_%s_%s.png" % [id, art]
	root.get_viewport().get_texture().get_image().save_png("user://" + name)
	print("BILD ", name)
