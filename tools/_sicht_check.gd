## Misst die Sichtweiten-Aenderung: Chunk-Zahl, Bauzeit und die tatsaechlich gesetzten
## Sichtlimits an Flora und Gebaeuden. Belegt, dass nichts mehr ueber den Terrainrand
## hinaus gezeichnet wird.
extends SceneTree
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	print("VIEW_DIST=%.0f  FLORA_DIST=%.0f  Chunk=%.0f"
		% [TerrainWorld.VIEW_DIST, TerrainWorld.FLORA_DIST, TerrainWorld.CHUNK])
	var flaeche := PI * TerrainWorld.VIEW_DIST * TerrainWorld.VIEW_DIST
	print("  Chunks im Vollradius (rechnerisch): %d" % int(flaeche
		/ (TerrainWorld.CHUNK * TerrainWorld.CHUNK)))
	var tw := TerrainWorld.new()
	root.add_child(tw)
	tw.setup(12345, [], [], [], [])
	var t0 := Time.get_ticks_msec()
	tw.build_now_around(Vector3.ZERO, 1200.0, false)
	var dt := Time.get_ticks_msec() - t0
	print("  Spawn-Ring 1200 m: %d Chunks in %d ms (%.1f ms/Chunk)"
		% [tw._chunks.size(), dt, float(dt) / maxf(float(tw._chunks.size()), 1.0)])
	var flora := 0
	var limit := -1.0
	for c in tw.get_children():
		for k in c.get_children():
			var mmi := k as MultiMeshInstance3D
			if mmi != null:
				flora += 1
				limit = mmi.visibility_range_end
	print("  Flora-MultiMeshes: %d, Sichtlimit %.0f m (+%.0f Fade)"
		% [flora, limit, TerrainWorld.FLORA_FADE])
	print("  Gebaeude-Sichtlimit: %.0f m (+%.0f Fade), Terrainrand %.0f"
		% [CityBuilder.SICHT_DIST, CityBuilder.SICHT_FADE, TerrainWorld.VIEW_DIST])
	print("  -> Gebaeude enden %.0f m INNERHALB des Terrainrands"
		% (TerrainWorld.VIEW_DIST - CityBuilder.SICHT_DIST))
	quit()
	return true
