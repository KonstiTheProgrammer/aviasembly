## WAS LIEGT AUF DER BAHN IN DER KAVERNE — UND AUF WELCHER HOEHE?
##
## Rechnerisch sitzt der Belag buendig mit der Bodenplatte (bahn_hub). Im Bild ist der
## Korridor trotzdem eine dunkle Flaeche ohne Markierung. Rechnung und Bild widersprechen
## sich, also wird nachgesehen statt weiter gerechnet: welche Knoten stehen dort, auf
## welcher Hoehe, und wie hell sind ihre Materialien.
##
## Godot --headless --path . --script res://tools/_bahn_hoehe.gd
extends SceneTree

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if not has_meta("m"):
		var m: Node = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		set_meta("m", m)
		return false
	if f < 30:
		return false
	var main: Node = get_meta("m")
	var platz: Node = null
	for k in main.get("fly_world").get_children():
		if String(k.name).begins_with("Flugplatz_ADLERHORST"):
			platz = k
	if platz == null:
		print("Flugplatz nicht gefunden")
		quit()
		return true
	print("Platzknoten steht auf y = %.2f" % (platz as Node3D).global_position.y)
	# Die groessten Flaechen unter dem Platzknoten, nach Weltflaeche sortiert.
	var liste: Array = []
	_sammeln(platz, liste)
	liste.sort_custom(func(a, b): return a["flaeche"] > b["flaeche"])
	print("\ngroesste Flaechen unter dem Platz (Welt-y = Oberkante):")
	print("  Welt-y | Breite x Laenge | Albedo | Name")
	for e in liste.slice(0, 12):
		print("  %6.2f | %6.1f x %6.1f | %6.3f | %s"
			% [e["oben"], e["bx"], e["bz"], e["hell"], e["name"]])
	quit()
	return true


func _sammeln(n: Node, out: Array) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh is BoxMesh:
		var g: Vector3 = (mi.mesh as BoxMesh).size * mi.global_transform.basis.get_scale()
		var mat := mi.material_override as StandardMaterial3D
		var c: Color = mat.albedo_color if mat != null else Color.MAGENTA
		out.append({"oben": mi.global_position.y + g.y * 0.5, "bx": g.x, "bz": g.z,
			"hell": (c.r + c.g + c.b) / 3.0, "flaeche": g.x * g.z, "name": mi.name})
	for c in n.get_children():
		_sammeln(c, out)
