## Prueft fuer jede generische Kanzel: (a) das Teil existiert samt Rumpfsegment,
## (b) ein gezogenes Rumpfsegment wird zur passenden Variante und sitzt SPALTFREI
## an der ebenen Stirnflaeche.
extends SceneTree
var bc: BuildController
var frame := 0

func _hit(part: Node3D, lp: Vector3, ln: Vector3) -> Dictionary:
	return {"position": part.global_transform * lp,
		"normal": (part.global_transform.basis * ln).normalized(),
		"collider": part.get_node_or_null("Pick")}

func _process(_d: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	bc = BuildController.new()
	root.add_child(bc)
	bc.clear_design()
	var x := 0.0
	for stil_v in ["spitfire", "bubble", "jet", "frame", "tandem"]:
		var stil := String(stil_v)
		var cid := "cockpit_" + stil
		var fid := "fuselage_" + stil
		var cd := PartCatalog.get_part(cid)
		var fd := PartCatalog.get_part(fid)
		print("=== ", stil, "  Kanzel size=", cd.get("size"), "  Rumpf size=", fd.get("size"))
		var cp := bc._place_id(cid, Transform3D(Basis(), Vector3(x, 0, 0)))
		bc._notify_changed()
		# hinten (+Z) andocken: Treffer auf der hinteren Stirnflaeche
		var hz: float = PartCatalog.col_size(cd).z * 0.5
		var h := _hit(cp, Vector3(0, 0, hz), Vector3(0, 0, 1))
		var snap := bc._compute_snap_for("fuselage", h)
		if not snap.get("valid", false):
			print("   KEIN Snap"); x += 12.0; continue
		var gid := String(snap.get("id", "fuselage"))
		var xf: Transform3D = snap["xform"]
		var vorn: float = xf.origin.z - PartCatalog.col_size(fd).z * 0.5
		var kante: float = cp.global_position.z + hz
		print("   -> id=%s (erwartet %s)  scale=%v" % [gid, fid, snap.get("scale", Vector3.ONE)])
		print("   -> Rumpf-Vorderkante %.4f  Kanzel-Hinterkante %.4f  SPALT %.5f"
			% [vorn, kante, absf(vorn - kante)])
		bc._place_id(gid, xf, snap.get("scale", Vector3.ONE))
		bc._notify_changed()
		x += 12.0
	quit()
	return true
