class_name WorldView
extends Node3D
## Draws the sim as 3D blocks. Static geometry is rebuilt only when `sim.rev` changes; residents
## and per-frame overlays (drag rectangles, placement previews, selection) update every frame.
## Grid cell (x, y) maps to world (x, height, y); ground tops sit at height 0.

var sim: Sim
## The map being drawn (issue #101). The view switches the sim to it while drawing and picking, then
## back to the village.
var map_id := "village"

var _built_rev := -1
var _built_map := ""
var _stuck_sig := ""
var _solid: MultiMeshInstance3D
var _cart: MultiMeshInstance3D  ## The minecart, redrawn as it moves (issue #124).
var _cart_sig := ""
var _ghost: MultiMeshInstance3D
var _over_dark: MultiMeshInstance3D
var _over_col: MultiMeshInstance3D
var _live_dark: MultiMeshInstance3D
var _live_col: MultiMeshInstance3D
var _marks := Node3D.new()
var _flags := Node3D.new()
var _hatch := Node3D.new()
var _people := {}
var _hatch_mat: StandardMaterial3D
var _person_mats := {}

## Set by the game each frame.
var live_outlines: Array = []   ## {rect: Rect2i, h: float, color: Color, dashed: bool}
var live_fills: Array = []      ## {rect: Rect2i, h: float, color: Color}
var selected_ids: Array = []    ## Resident ids with a selection ring.
var hover_id := 0               ## The resident under the mouse, who shows a name tag; 0 for none.
## What the player is looking at, as [world point, entity id to ignore]. Trees standing between the
## camera and any of these fade to a see-through shape (brief §11: fade obstructing objects).
var focus_points: Array = []
var open_roofs: Array = []      ## House ids whose roof is cut away (selected, or the cursor is inside).
var faded_trees: Array = []     ## Tree ids currently faded.
## Residents are drawn between their position before the last tick and their current one, this
## far along (0..1), so walking looks smooth although the sim moves them 20 times a second.
var tick_fraction := 1.0
var _prev_pos := {}             ## Resident id -> position before the latest tick.

var _trees: MultiMeshInstance3D
var _trees_faded: MultiMeshInstance3D
var _roofs: MultiMeshInstance3D
var _occluder_sig := ""


class Batch:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []

	func box(lo: Vector3, hi: Vector3, col: Color) -> void:
		var size := hi - lo
		xforms.append(Transform3D(Basis.from_scale(size), lo + size / 2.0))
		colors.append(col)

	func apply(mmi: MultiMeshInstance3D) -> void:
		var mm := mmi.multimesh
		mm.instance_count = 0
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, colors[i])


## Switches to another sim (after loading a save) and redraws everything.
func set_sim(s: Sim) -> void:
	sim = s
	_prev_pos.clear()
	_built_rev = -1
	_stuck_sig = "-"
	for id in _people:
		_people[id].queue_free()
	_people.clear()
	_hops.clear()
	for id in _sheep_nodes:
		_sheep_nodes[id].queue_free()
	_sheep_nodes.clear()


func _ready() -> void:
	_solid = _mm(_material(false, false, 0))
	_cart = _mm(_material(false, false, 0))
	_trees = _mm(_material(false, false, 0))
	var faded := _material(true, false, 0)
	faded.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_trees_faded = _mm(faded)
	_roofs = _mm(_material(false, false, 0))
	_ghost = _mm(_material(true, false, 0))
	_over_dark = _mm(_material(true, true, 9))
	_over_col = _mm(_material(true, true, 10))
	_live_dark = _mm(_material(true, true, 11))
	_live_col = _mm(_material(true, true, 12))
	add_child(_hatch)
	add_child(_marks)
	add_child(_flags)
	_hatch_mat = StandardMaterial3D.new()
	_hatch_mat.albedo_texture = MarkTextures.hatch()
	_hatch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hatch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hatch_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _mm(mat: Material) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = BoxMesh.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi


func _material(transparent: bool, overlay: bool, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if overlay:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.render_priority = priority
	return m


func _process(delta: float) -> void:
	_frame_delta = delta
	if sim == null:
		return
	sim.use_map(map_id)
	_draw_map()
	sim.use_map("village")


func _draw_map() -> void:
	if sim.rev != _built_rev or map_id != _built_map:
		_build_static()
		_built_rev = sim.rev
		_built_map = map_id
	var sig := map_id
	for s in sim.stuck:
		sig += "%s%s%s%s%s;" % [s.map, s.cell, s.height, s.why, s.waiting]
	if sig != _stuck_sig:
		_stuck_sig = sig
		_build_flags()
	_build_occluders()
	_update_people()
	_update_sheep()
	_build_cart()
	_build_live()


# ---------------------------------------------------------------- static world

func _build_static() -> void:
	var solid := Batch.new()
	var ghost := Batch.new()
	var dark := Batch.new()
	var col := Batch.new()
	if sim.m.kind == "site":
		_add_site_ground(solid)
	elif sim.m.kind == "route":
		_add_route_ground(solid)
	else:
		for x in sim.w:
			for y in sim.h:
				var v := 0.96 + _hash(x, y) * 0.08
				solid.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.1, y + 1), Palette.DIRT)
				solid.box(Vector3(x, -0.1, y), Vector3(x + 1, 0, y + 1), Palette.GRASS * Color(v, v, v))
	for b in sim.boulders:
		if b.alive and not b.get("hidden", false) and not _in_fog(b.cell):
			var c: Vector2i = b.cell
			solid.box(Vector3(c.x + 0.08, 0, c.y + 0.08), Vector3(c.x + 0.92, 0.62, c.y + 0.92), Palette.STONE)
			solid.box(Vector3(c.x + 0.2, 0.62, c.y + 0.15), Vector3(c.x + 0.7, 0.95, c.y + 0.7), Palette.STONE.lightened(0.06))
			if b.has("ore"):  # flecks of ore on its faces and top (issue #103)
				_add_ore_flecks(solid, c, Palette.ITEM_COLORS[Defs.ORES[b.ore].item])
			if b.get("loose", false) and sim.m.visited:  # a loose ceiling: cracks, and props holding it (issue #110)
				for k in 2:
					var x := c.x + 0.25 + k * 0.4
					solid.box(Vector3(x, 0.62, c.y + 0.9), Vector3(x + 0.06, 0.95, c.y + 0.95), CRACK)
					solid.box(Vector3(c.x + 0.9, 0.62, c.y + 0.25 + k * 0.4), Vector3(c.x + 0.95, 0.95, c.y + 0.31 + k * 0.4), CRACK)
	for bush in sim.bushes:
		_add_bush(solid, bush)
	if sim.m.kind == "village":
		_add_signpost(solid, sim.meadow_sign())
		_add_route_sign(solid, sim.route_sign())
	for k in sim.farm:
		_add_crop(solid, sim.farm[k])
	for k in sim.items:
		_add_item(solid, sim.items[k])
	for s in sim.sites:
		_add_site(solid, ghost, s)
		if not s.done:
			_outline(dark, col, Rect2i(s.origin, s.size), 0.52 if s.stage >= 1 else 0.02, Palette.BLUE, true)
		if s.get("plot") != null:  # the reserved plot it will grow into, faint
			_outline(dark, col, s.plot, 0.02, Color(Palette.CHALK, 0.35), true)
	solid.apply(_solid)
	ghost.apply(_ghost)
	_occluder_sig = ""
	dark.apply(_over_dark)
	col.apply(_over_col)
	_build_marks()
	_build_hatch()


static var MINE_FLOOR := Color("#5B5650")
static var CRACK := Color("#2A2724")
static var MINE_ROCK := Color("#6E6A63")
static var TORCH_FLAME := Color("#F2A640")
static var DARK_TINT := Color("#2C3445")


## A site map's ground (issue #102): a stone floor, rock walls a block high, torches on the walls,
## and the tunnels no torch reaches drawn darker, so the dark parts read at a glance.
func _add_site_ground(b: Batch) -> void:
	var mp := sim.m
	for x in mp.w:
		for y in mp.h:
			var c := Vector2i(x, y)
			var v := 0.94 + _hash(x, y) * 0.1
			if mp.rock.has(c) or (sim.boulders.any(func(o): return o.alive and o.get("hidden", false) and o.cell == c)):
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, 0.7, y + 1), MINE_ROCK * Color(v, v, v))
				continue
			var floor_col := MINE_FLOOR * Color(v, v, v)
			if mp.is_dark(c):  # unlit: darker and a little cold, but still read as floor, not a hole
				floor_col = floor_col.darkened(0.38).lerp(DARK_TINT, 0.25)
			if c in mp.ledges and mp.visited:  # a ledge: the floor drops, with a pale lip (issue #110)
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.3, y + 1), floor_col.darkened(0.2))
				b.box(Vector3(x, -0.3, y), Vector3(x + 1, 0, y + 0.12), floor_col.lightened(0.25))
				continue
			b.box(Vector3(x, -0.6, y), Vector3(x + 1, 0, y + 1), floor_col)
	for t in mp.torches:
		var x: float = t.x + 0.5
		var z: float = t.y + 0.5
		b.box(Vector3(x - 0.06, 0.7, z - 0.06), Vector3(x + 0.06, 1.1, z + 0.06), Palette.LOG)
		b.box(Vector3(x - 0.1, 1.1, z - 0.1), Vector3(x + 0.1, 1.3, z + 0.1), TORCH_FLAME)
	# The way back to the village: a timber frame over the entrance, and the party's packs beside it
	# while it works the site (issue #109): a crate for every 3 items in them.
	var e := mp.entrance
	if sim.expedition.get("state", "") == "out" and sim.expedition.dest == mp.id and sim.expedition.party.any(func(id): return sim.at_site(sim.resident(id))):
		var crates := mini(9, ceili(sim.pack_load() / 3.0))
		for i in crates:
			var px: float = e.x + 1.2 + float(i % 3) * 0.3  # along the tunnel wall just inside
			var pz: float = e.y + 0.17
			var py := float(i / 3) * 0.26
			b.box(Vector3(px - 0.13, py, pz - 0.13), Vector3(px + 0.13, py + 0.26, pz + 0.13), CRATE)
			b.box(Vector3(px - 0.135, py + 0.1, pz - 0.135), Vector3(px + 0.135, py + 0.14, pz + 0.135), Palette.LOG)
	b.box(Vector3(e.x, 0, e.y - 0.05), Vector3(e.x + 0.15, 1.4, e.y + 0.1), Palette.LOG)
	b.box(Vector3(e.x, 0, e.y + 0.9), Vector3(e.x + 0.15, 1.4, e.y + 1.05), Palette.LOG)
	b.box(Vector3(e.x - 0.05, 1.4, e.y - 0.1), Vector3(e.x + 0.2, 1.6, e.y + 1.1), Palette.LOG)


static var WATER := Color("#4E7EA3")
static var TRODDEN := Color("#8C7B58")
static var FOG := Color("#A9B3AF")
static var SLEEPER := Color("#6A4A2E")


## The road to the mine (issue #118): grass with a trodden path along the line, the stream, and the
## rocky cut's walls. Past the segments anyone has walked, it's fog (issue #119).
func _add_route_ground(b: Batch) -> void:
	var mp := sim.m
	for x in mp.w:
		for y in mp.h:
			var c := Vector2i(x, y)
			var v := 0.96 + _hash(x, y) * 0.08
			if _in_fog(c):
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, 0.05, y + 1), FOG * Color(v, v, v))
				continue
			if mp.rock.has(c):
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, 1.2, y + 1), MINE_ROCK * Color(v, v, v))
				continue
			if mp.water.has(c):  # a little below the banks
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.4, y + 1), Palette.DIRT)
				b.box(Vector3(x, -0.4, y), Vector3(x + 1, -0.25, y + 1), WATER * Color(v, v, v))
				continue
			b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.1, y + 1), Palette.DIRT)
			var top := TRODDEN if y == Road.LINE_ROW else Palette.GRASS
			b.box(Vector3(x, -0.1, y), Vector3(x + 1, 0, y + 1), top * Color(v, v, v))
	_add_end_sign(b, Road.VILLAGE_END + Vector2i(0, -1), -1.0, Palette.GRASS)
	_add_end_sign(b, Road.MINE_END + Vector2i(0, -1), 1.0, Palette.STONE)


## True for a cell on the road nobody has walked to yet (issue #119).
func _in_fog(c: Vector2i) -> bool:
	return sim.m.kind == "route" and Road.segment_at(c.x) >= sim.m.seen


## A signpost at an end of the road, its board pointing off the map (-1 west, 1 east) with a dab of
## where it leads.
func _add_end_sign(b: Batch, c: Vector2i, dir: float, dab: Color) -> void:
	var x := c.x + 0.5
	var z := c.y + 0.5
	b.box(Vector3(x - 0.09, 0, z - 0.09), Vector3(x + 0.09, 1.8, z + 0.09), Palette.LOG)
	var a := x + 0.15 * -dir
	var e := x + 0.7 * dir
	b.box(Vector3(minf(a, e), 1.15, z - 0.06), Vector3(maxf(a, e), 1.6, z + 0.06), Palette.PLANK)
	b.box(Vector3(minf(e, e + 0.15 * dir), 1.25, z - 0.05), Vector3(maxf(e, e + 0.15 * dir), 1.5, z + 0.05), Palette.PLANK)
	var m0 := x + 0.12 * dir
	var m1 := x + 0.45 * dir
	b.box(Vector3(minf(m0, m1), 1.24, z - 0.08), Vector3(maxf(m0, m1), 1.5, z + 0.08), dab)


## The plank bridge over the stream (issue #119): a deck across it with a rail each side.
func _add_bridge(b: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	var col := Palette.PLANK if s.done else Color(Palette.BLUE, 0.4)
	var x0 := float(o.x)
	var x1 := float(o.x + s.size.x)
	b.box(Vector3(x0, 0, o.y + 0.1), Vector3(x1, 0.14, o.y + s.size.y - 0.1), col)
	if not s.done:
		return
	for k in range(o.x, o.x + s.size.x):
		b.box(Vector3(k + 0.02, 0.14, o.y + 0.1), Vector3(k + 0.06, 0.15, o.y + s.size.y - 0.1), Palette.PLANK.darkened(0.25))
	for z in [o.y + 0.1, o.y + s.size.y - 0.22]:
		b.box(Vector3(x0, 0.14, z), Vector3(x1, 0.62, z + 0.12), Palette.LOG)


## A segment of track (issues #121, #122): sleepers across the line and a rail each side where it's
## laid, rail by rail from the village end, and its blueprint on the rest.
func _add_track(solid: Batch, ghost: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	var laid: int = s.size.x if s.done else s.get("laid", 0) * s.size.x / Tuning.RAILS_PER_SEGMENT
	var rail: Color = Palette.ITEM_COLORS.rail
	for k in s.size.x:
		var x: int = o.x + k
		var on_bridge: bool = Road.bridge_rect().has_point(Vector2i(x, o.y)) and sim.bridge().get("done", false)
		var y := 0.14 if on_bridge else 0.0  # up on the bridge's deck
		if k >= laid:
			ghost.box(Vector3(x + 0.3, y, o.y + 0.12), Vector3(x + 0.7, y + 0.06, o.y + 0.88), Color(Palette.BLUE, 0.4))
			continue
		solid.box(Vector3(x + 0.3, y, o.y + 0.08), Vector3(x + 0.7, y + 0.07, o.y + 0.92), SLEEPER)
		for z in [o.y + 0.22, o.y + 0.7]:
			solid.box(Vector3(x, y + 0.07, z), Vector3(x + 1, y + 0.15, z + 0.08), rail)


## A station (issue #123): a plank platform on a stone kerb beside the line, with a buffer stop at its
## far end, facing off the map.
func _add_station(b: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	var x0 := float(o.x)
	var x1 := float(o.x + s.size.x)
	if not s.done:
		b.box(Vector3(x0, 0, o.y + 0.05), Vector3(x1, 0.25, o.y + 0.95), Color(Palette.BLUE, 0.4))
		return
	b.box(Vector3(x0, 0, o.y + 0.05), Vector3(x1, 0.22, o.y + 0.95), Palette.COBBLE)
	b.box(Vector3(x0, 0.22, o.y + 0.05), Vector3(x1, 0.3, o.y + 0.95), Palette.PLANK)
	var stop := x0 if s.get("end", "village") == "village" else x1 - 0.25  # the buffer stop, at the line's end
	b.box(Vector3(stop, 0, Road.LINE_ROW + 0.15), Vector3(stop + 0.25, 0.5, Road.LINE_ROW + 0.85), Palette.LOG)
	b.box(Vector3(stop - 0.02, 0.38, Road.LINE_ROW + 0.2), Vector3(stop + 0.27, 0.48, Road.LINE_ROW + 0.8), Palette.RED)


static var CART_DARK := Color("#3E4448")


## The minecart on the line (issues #123, #124), with any cargo heaped in it. Riders are drawn as
## people at the cart's place.
func _build_cart() -> void:
	var c: Dictionary = sim.cart
	var sig := "" if c.is_empty() or map_id != Road.ID else "%.2f%s" % [c.x, c.load]
	if sig == _cart_sig:
		return
	_cart_sig = sig
	var b := Batch.new()
	if sig != "":
		var x: float = c.x + 0.5
		var z := Road.LINE_ROW + 0.5
		var y: float = 0.14 if Road.bridge_rect().has_point(Vector2i(roundi(c.x), Road.LINE_ROW)) and sim.bridge().get("done", false) else 0.0
		var col: Color = Palette.ITEM_COLORS.minecart
		b.box(Vector3(x - 0.42, y + 0.12, z - 0.3), Vector3(x + 0.42, y + 0.5, z + 0.3), col)
		b.box(Vector3(x - 0.36, y + 0.42, z - 0.24), Vector3(x + 0.36, y + 0.51, z + 0.24), CART_DARK)
		for k in [-0.26, 0.26]:
			b.box(Vector3(x + k - 0.08, y, z - 0.34), Vector3(x + k + 0.08, y + 0.16, z + 0.34), Palette.SLATE_DEEP)
		var n := 0
		for k in c.load:
			var it_col: Color = Palette.ITEM_COLORS[k]
			for i in mini(c.load[k], 6 - n):
				var px := x - 0.25 + float(n % 3) * 0.25
				var pz := z - 0.1 + float(n / 3) * 0.2
				b.box(Vector3(px - 0.1, y + 0.5, pz - 0.08), Vector3(px + 0.1, y + 0.64, pz + 0.08), it_col)
				n += 1
	b.apply(_cart)


func _add_ore_flecks(b: Batch, c: Vector2i, col: Color) -> void:
	for p in [Vector3(0.25, 0.3, 0.92), Vector3(0.62, 0.45, 0.92), Vector3(0.92, 0.25, 0.4), Vector3(0.92, 0.48, 0.7)]:
		var lo := Vector3(c.x + p.x - 0.09, p.y - 0.07, c.y + p.z - 0.09)
		b.box(lo, lo + Vector3(0.18, 0.14, 0.18), col)
	b.box(Vector3(c.x + 0.35, 0.95, c.y + 0.3), Vector3(c.x + 0.55, 0.98, c.y + 0.5), col)


static var BUSH_GREEN := Color("#3F6B33")


## A low leafy bush with a red dot for each berry it holds (issue #44).
func _add_bush(b: Batch, bush: Dictionary) -> void:
	var cx: float = bush.cell.x + 0.5
	var cz: float = bush.cell.y + 0.5
	b.box(Vector3(cx - 0.36, 0, cz - 0.36), Vector3(cx + 0.36, 0.42, cz + 0.36), BUSH_GREEN)
	var spots := [Vector2(-0.18, 0.2), Vector2(0.2, -0.12), Vector2(0.05, 0.22)]
	for i in bush.berries:
		var p: Vector2 = spots[i % spots.size()]
		b.box(Vector3(cx + p.x - 0.07, 0.42, cz + p.y - 0.07), Vector3(cx + p.x + 0.07, 0.52, cz + p.y + 0.07), Palette.ITEM_COLORS.berries)


## The meadow signpost (issue #50): a post with a board pointing off the map's left edge.
func _add_signpost(b: Batch, c: Vector2i) -> void:
	var x := c.x + 0.5
	var z := c.y + 0.5
	b.box(Vector3(x - 0.09, 0, z - 0.09), Vector3(x + 0.09, 1.8, z + 0.09), Palette.LOG)
	# An arrow-shaped board pointing off the edge, with a sheep's white fleece painted on it.
	b.box(Vector3(x - 0.7, 1.15, z - 0.06), Vector3(x + 0.15, 1.6, z + 0.06), Palette.PLANK)
	b.box(Vector3(x - 0.85, 1.25, z - 0.05), Vector3(x - 0.7, 1.5, z + 0.05), Palette.PLANK)
	b.box(Vector3(x - 0.45, 1.27, z - 0.08), Vector3(x - 0.12, 1.48, z + 0.08), SHEEP_WOOL)
	b.box(Vector3(x - 0.55, 1.33, z - 0.08), Vector3(x - 0.45, 1.44, z + 0.08), SHEEP_FACE)


## The signpost to the old mine (issue #108): a board pointing off the east edge, with a grey block of
## stone and a fleck of coal painted on it.
func _add_route_sign(b: Batch, c: Vector2i) -> void:
	var x := c.x + 0.5
	var z := c.y + 0.5
	b.box(Vector3(x - 0.09, 0, z - 0.09), Vector3(x + 0.09, 1.8, z + 0.09), Palette.LOG)
	b.box(Vector3(x - 0.15, 1.15, z - 0.06), Vector3(x + 0.7, 1.6, z + 0.06), Palette.PLANK)
	b.box(Vector3(x + 0.7, 1.25, z - 0.05), Vector3(x + 0.85, 1.5, z + 0.05), Palette.PLANK)
	b.box(Vector3(x + 0.12, 1.24, z - 0.08), Vector3(x + 0.45, 1.5, z + 0.08), Palette.STONE)
	b.box(Vector3(x + 0.26, 1.33, z - 0.09), Vector3(x + 0.36, 1.42, z + 0.09), Palette.ITEM_COLORS.coal)


static var SOIL := Color("#5E4430")
static var SPROUT := Color("#7FA84A")
static var WHEAT_RIPE := Color("#D8B65A")


## A tilled plot with two furrows, and wheat rising through three stages to golden ripe ears
## (issue #45).
func _add_crop(b: Batch, crop: Dictionary) -> void:
	var x: float = crop.cell.x
	var z: float = crop.cell.y
	b.box(Vector3(x + 0.04, 0, z + 0.04), Vector3(x + 0.96, 0.03, z + 0.96), SOIL)
	var stage := Sim.crop_stage(crop)
	for row in 2:
		var rz := z + 0.27 + row * 0.46
		b.box(Vector3(x + 0.1, 0.03, rz - 0.09), Vector3(x + 0.9, 0.06, rz + 0.09), SOIL.darkened(0.18))
		if stage == 0:
			continue
		var height: float = [0.0, 0.14, 0.3, 0.46, 0.58][stage]
		var col: Color = [SPROUT, SPROUT, SPROUT.lerp(WHEAT_RIPE, 0.35), SPROUT.lerp(WHEAT_RIPE, 0.6), WHEAT_RIPE][stage]
		for i in 3:
			var cx := x + 0.2 + i * 0.3
			b.box(Vector3(cx - 0.06, 0.06, rz - 0.06), Vector3(cx + 0.06, 0.06 + height, rz + 0.06), col)
			if stage == 4:
				b.box(Vector3(cx - 0.08, 0.06 + height, rz - 0.08), Vector3(cx + 0.08, 0.2 + height, rz + 0.08), WHEAT_RIPE.lightened(0.15))


func _add_item(b: Batch, s: Dictionary) -> void:
	var cx: float = s.cell.x + 0.5
	var cz: float = s.cell.y + 0.5
	var color: Color = Palette.ITEM_COLORS[s.type]
	if Defs.is_tool_item(s.type):
		b.box(Vector3(cx - 0.3, 0, cz - 0.06), Vector3(cx + 0.3, 0.08, cz + 0.06), Palette.LOG)
		b.box(Vector3(cx + 0.12, 0, cz - 0.16), Vector3(cx + 0.3, 0.14, cz + 0.16), color)
		return
	if s.type == "minecart":  # a tub on wheels, set down on the ground (issue #120)
		b.box(Vector3(cx - 0.36, 0.12, cz - 0.28), Vector3(cx + 0.36, 0.55, cz + 0.28), color)
		b.box(Vector3(cx - 0.3, 0.45, cz - 0.22), Vector3(cx + 0.3, 0.56, cz + 0.22), color.darkened(0.4))
		for k in [-0.22, 0.22]:
			b.box(Vector3(cx + k - 0.08, 0, cz - 0.32), Vector3(cx + k + 0.08, 0.16, cz + 0.32), Palette.SLATE_DEEP)
		return
	var levels: int = mini(4, ceili(s.n / 4.0))
	if s.type == "rail":  # rails lie in bundles: a pair of bars over a sleeper, a layer to every 4
		for i in levels:
			var y := i * 0.1
			b.box(Vector3(cx - 0.3, y, cz - 0.08), Vector3(cx + 0.3, y + 0.05, cz + 0.08), Palette.LOG)
			for k in [-0.16, 0.16]:
				b.box(Vector3(cx - 0.06 + k, y + 0.05, cz - 0.32), Vector3(cx + 0.06 + k, y + 0.1, cz + 0.32), color)
		return
	if s.type == "iron_ingot":  # ingots lie as bars, two to a layer, crossing each layer (issue #103)
		for i in levels:
			var y := i * 0.12
			for k in 2:
				var off := -0.14 + k * 0.28
				if i % 2 == 0:
					b.box(Vector3(cx - 0.28, y, cz + off - 0.1), Vector3(cx + 0.28, y + 0.12, cz + off + 0.1), color)
				else:
					b.box(Vector3(cx + off - 0.1, y, cz - 0.28), Vector3(cx + off + 0.1, y + 0.12, cz + 0.28), color.darkened(0.08))
		return
	for i in levels:
		b.box(Vector3(cx - 0.26, i * 0.2, cz - 0.26), Vector3(cx + 0.26, i * 0.2 + 0.2, cz + 0.26), color)


func _add_site(solid: Batch, ghost: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	if s.tpl == "bench":
		var b := solid if s.done else ghost
		var top := Palette.PLANK if s.done else Color(Palette.BLUE, 0.45)
		b.box(Vector3(o.x + 0.1, 0, o.y + 0.1), Vector3(o.x + 0.9, 0.75, o.y + 0.9), top)
		return
	if s.tpl == "fireplace":
		_add_fireplace(solid if s.done else ghost, s)
		return
	if s.tpl == "board":
		_add_board(solid if s.done else ghost, s)
		return
	if s.tpl == "bridge":
		_add_bridge(solid if s.done else ghost, s)
		return
	if s.tpl == "track":
		_add_track(solid, ghost, s)
		return
	if s.tpl == "station":
		_add_station(solid if s.done else ghost, s)
		return
	var stage: int = s.stage
	var gcol := Color(Palette.BLUE, 0.4)
	for x in range(o.x, o.x + 5):
		for y in range(o.y, o.y + 5):
			if stage >= 1:
				solid.box(Vector3(x, 0, y), Vector3(x + 1, 0.5, y + 1), Palette.COBBLE)
			else:
				ghost.box(Vector3(x, 0, y), Vector3(x + 1, 0.5, y + 1), gcol)
	if stage < 1:
		return
	var door := sim.door_cell(o, s.rot)
	for x in range(o.x, o.x + 5):
		for y in range(o.y, o.y + 5):
			var edge := x == o.x or x == o.x + 4 or y == o.y or y == o.y + 4
			if not edge:
				continue
			var corner := (x == o.x or x == o.x + 4) and (y == o.y or y == o.y + 4)
			var c := Palette.LOG if corner else Palette.PLANK
			var b := ghost if stage == 1 else solid
			var cc := gcol if stage == 1 else c
			var lo := 1.7 if Vector2i(x, y) == door else 0.5
			b.box(Vector3(x, lo, y), Vector3(x + 1, 2.5, y + 1), cc)
	if stage == 2:
		_add_roof(ghost, o, gcol)
	# A finished roof is drawn by _build_occluders, so it can be cut away.
	if stage == 3:
		_add_bed(ghost, o, true)
	elif stage >= 4:
		_add_bed(solid, o, false)


static var EMBER := Color("#E8763A")


## A squat cobblestone hearth with a chimney at the back and embers in its mouth, which faces its
## kitchen plot (issue #46).
func _add_fireplace(b: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	var done: bool = s.done
	var stone: Color = Palette.COBBLE if done else Color(Palette.BLUE, 0.45)
	b.box(Vector3(o.x + 0.08, 0, o.y + 0.08), Vector3(o.x + 0.92, 0.5, o.y + 0.92), stone)
	# The back is away from the plot: rot 0 opens toward +y, 1 toward -x, 2 toward -y, 3 toward +x.
	var back := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][int(s.get("rot", 0)) % 4] as Vector2
	var c := Vector2(o.x + 0.5, o.y + 0.5)
	var ch := c + back * 0.24
	b.box(Vector3(ch.x - 0.2, 0.5, ch.y - 0.2), Vector3(ch.x + 0.2, 1.05, ch.y + 0.2), stone.darkened(0.08) if done else stone)
	if done:
		var m := c - back * 0.3
		b.box(Vector3(m.x - 0.2, 0.06, m.y - 0.2), Vector3(m.x + 0.2, 0.3, m.y + 0.2), EMBER)


static var MAP_SHEET := Color("#E6DCC0")
static var CRATE := Color("#A97E4E")


## The expedition board (issue #105): a plank board on two posts with a map of the way to the old
## mine pinned to its face, which looks out over its plot. What's packed for an expedition stacks up
## as crates on the plot in front of it, past where the party waits (issue #107).
func _add_board(b: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	var front: Vector2 = [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)][int(s.get("rot", 0)) % 4]
	var side := Vector2(absf(front.y), absf(front.x))
	var depth := Vector2(absf(front.x), absf(front.y))
	var c := Vector2(o.x + 0.5, o.y + 0.5)
	if not s.done:
		b.box(Vector3(o.x + 0.1, 0, o.y + 0.1), Vector3(o.x + 0.9, 0.2, o.y + 0.9), Color(Palette.BLUE, 0.45))
		return
	for k in [-1.0, 1.0]:
		var p: Vector2 = c + side * 0.38 * k
		b.box(Vector3(p.x - 0.06, 0, p.y - 0.06), Vector3(p.x + 0.06, 1.55, p.y + 0.06), Palette.LOG)
	var half := side * 0.46 + depth * 0.04
	b.box(Vector3(c.x - half.x, 0.7, c.y - half.y), Vector3(c.x + half.x, 1.45, c.y + half.y), Palette.PLANK)
	var mc := c + front * 0.05
	var sheet := side * 0.32 + depth * 0.01
	b.box(Vector3(mc.x - sheet.x, 0.8, mc.y - sheet.y), Vector3(mc.x + sheet.x, 1.35, mc.y + sheet.y), MAP_SHEET)
	# The route drawn on the map, and the red pin on the old mine at its end.
	var route := c + front * 0.06
	var line := side * 0.2 + depth * 0.012
	b.box(Vector3(route.x - line.x, 1.0, route.y - line.y), Vector3(route.x + line.x, 1.04, route.y + line.y), Palette.LOG)
	var pin := route + side * 0.2
	b.box(Vector3(pin.x - 0.045, 0.98, pin.y - 0.045), Vector3(pin.x + 0.045, 1.08, pin.y + 0.045), Palette.RED)
	var n := 0
	for k in s.store:
		n += s.store[k]
	var crates := mini(6, ceili(n / 2.0))
	var at := c + front * 2.0
	for i in crates:
		var p: Vector2 = at + side * (float(i % 3) - 1.0) * 0.3
		var y := float(i / 3) * 0.26
		b.box(Vector3(p.x - 0.13, y, p.y - 0.13), Vector3(p.x + 0.13, y + 0.26, p.y + 0.13), CRATE)
		b.box(Vector3(p.x - 0.135, y + 0.1, p.y - 0.135), Vector3(p.x + 0.135, y + 0.14, p.y + 0.135), Palette.LOG)


static var BED_BLANKET := Color("#B83A3A")


## The bed sits in the house's top corner: the back corner, furthest from the camera (issue #43).
## Two cells long against the back wall, with a plank frame, a red blanket and a white pillow.
func _add_bed(b: Batch, o: Vector2i, ghost: bool) -> void:
	var g := Color(Palette.BLUE, 0.45)
	var x0 := float(o.x + 1) + 0.1
	var z0 := float(o.y + 1) + 0.1
	b.box(Vector3(x0, 0.5, z0), Vector3(x0 + 1.8, 0.72, z0 + 0.8), g if ghost else Palette.PLANK)
	if ghost:
		return
	b.box(Vector3(x0 + 0.05, 0.72, z0 + 0.05), Vector3(x0 + 0.55, 0.84, z0 + 0.75), Palette.ITEM_COLORS.wool)
	b.box(Vector3(x0 + 0.6, 0.72, z0 + 0.03), Vector3(x0 + 1.77, 0.82, z0 + 0.77), BED_BLANKET)


func _add_roof(b: Batch, o: Vector2i, color: Color) -> void:
	for a in 3:
		for x in range(o.x + a, o.x + 5 - a):
			for y in range(o.y + a, o.y + 5 - a):
				b.box(Vector3(x, 2.5 + a * 0.5, y), Vector3(x + 1, 3.0 + a * 0.5, y + 1), color)


# ---------------------------------------------------------------- trees and roofs that get out of the way

const _TOWARD_CAMERA := Vector3(0.57735, 0.57735, 0.57735)


static func _tree_boxes(c: Vector2i) -> Array:
	return [AABB(Vector3(c.x + 0.1, 0, c.y + 0.1), Vector3(0.8, 3, 0.8)),
		AABB(Vector3(c.x - 1, 3, c.y - 1), Vector3(3, 1, 3)),
		AABB(Vector3(c.x, 4, c.y), Vector3(1, 1, 1))]


## True when the tree stands between the camera and one of the focus points.
func _tree_occludes(t: Dictionary) -> bool:
	for f in focus_points:
		if f[1] == t.id:
			continue
		var p: Vector3 = f[0]
		for box in _tree_boxes(t.cell):
			if box.intersects_segment(p + _TOWARD_CAMERA * 0.05, p + _TOWARD_CAMERA * 80.0) != null:
				return true
	return false


## Draws trees (solid or faded) and finished roofs (unless cut away). Cheap to check every frame;
## the meshes are only rebuilt when which trees are faded or which roofs are open changes.
func _build_occluders() -> void:
	var faded: Array = []
	for t in sim.trees:
		if t.alive and _tree_occludes(t):
			faded.append(t.id)
	var sig := "%d|%s|%s" % [sim.rev, faded, open_roofs]
	if sig == _occluder_sig:
		return
	_occluder_sig = sig
	faded_trees = faded
	var solid := Batch.new()
	var see_through := Batch.new()
	for t in sim.trees:
		if not t.alive or _in_fog(t.cell):
			continue
		var fade: bool = faded.has(t.id)
		var b := see_through if fade else solid
		var alpha := 0.3 if fade else 1.0
		var boxes := _tree_boxes(t.cell)
		b.box(boxes[0].position, boxes[0].end, Color(Palette.LOG, alpha))
		b.box(boxes[1].position, boxes[1].end, Color(Palette.LEAVES, alpha))
		b.box(boxes[2].position, boxes[2].end, Color(Palette.LEAVES, alpha))
	solid.apply(_trees)
	see_through.apply(_trees_faded)
	var roofs := Batch.new()
	for s in sim.sites:
		if s.tpl == "house" and s.stage >= 3 and not open_roofs.has(s.id):
			_add_roof(roofs, s.origin, Palette.ROOF)
	roofs.apply(_roofs)


## A chalk outline around `rect` at height `h`, drawn over everything, on a dark under-stroke.
func _outline(dark: Batch, col: Batch, rect: Rect2i, h: float, color: Color, dashed: bool) -> void:
	var x0 := float(rect.position.x)
	var z0 := float(rect.position.y)
	var x1 := float(rect.end.x)
	var z1 := float(rect.end.y)
	var edges := [[Vector2(x0, z0), Vector2(x1, z0)], [Vector2(x1, z0), Vector2(x1, z1)],
		[Vector2(x1, z1), Vector2(x0, z1)], [Vector2(x0, z1), Vector2(x0, z0)]]
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var length := a.distance_to(b)
		var dirv := (b - a) / length
		var pieces: Array = []
		if dashed:
			var t := 0.0
			while t < length:
				pieces.append([t, minf(t + 0.32, length)])
				t += 0.52
		else:
			pieces.append([0.0, length])
		for pc in pieces:
			var p0: Vector2 = a + dirv * pc[0]
			var p1: Vector2 = a + dirv * pc[1]
			_seg(dark, p0, p1, h, 0.13, Color(Palette.SLATE_DEEP, color.a))
			_seg(col, p0, p1, h + 0.005, 0.06, color)


func _seg(b: Batch, p0: Vector2, p1: Vector2, h: float, thick: float, color: Color) -> void:
	var lo := Vector3(minf(p0.x, p1.x) - thick / 2, h, minf(p0.y, p1.y) - thick / 2)
	var hi := Vector3(maxf(p0.x, p1.x) + thick / 2, h + 0.02, maxf(p0.y, p1.y) + thick / 2)
	b.box(lo, hi, color)


func _sprite(tex: Texture2D, pos: Vector3, size: float, parent: Node3D) -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.no_depth_test = true
	sp.render_priority = 14
	sp.shaded = false
	sp.pixel_size = size / 64.0
	sp.position = pos
	parent.add_child(sp)
	return sp


func _build_marks() -> void:
	for ch in _marks.get_children():
		ch.queue_free()
	for t in sim.trees:
		if t.alive and t.des:
			_sprite(MarkTextures.slash(), Vector3(t.cell.x + 0.5, 1.6, t.cell.y + 0.5), 0.75, _marks)
	for b in sim.boulders:
		if b.alive and b.des:
			_sprite(MarkTextures.cross(), Vector3(b.cell.x + 0.5, 0.7, b.cell.y + 0.5), 0.7, _marks)


func _build_flags() -> void:
	for ch in _flags.get_children():
		ch.queue_free()
	for s in sim.stuck:
		if s.waiting or s.map != map_id:
			continue  # a standing order short of materials is advice, not a blocker (issue #77)
		var sp := _sprite(MarkTextures.flag(), Vector3(s.cell.x, s.height + 0.45, s.cell.y), 0.9, _flags)
		sp.render_priority = 15


func _build_hatch() -> void:
	for ch in _hatch.get_children():
		ch.queue_free()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	for c in sim.zone:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _hatch_mat
		mi.position = Vector3(c.x + 0.5, 0.012, c.y + 0.5)
		_hatch.add_child(mi)


# ---------------------------------------------------------------- residents

## Called just before each sim tick.
func remember_positions() -> void:
	for r in sim.residents:
		_prev_pos[r.id] = r.pos


## Where to draw a resident this frame: partway from the previous tick's position to the current
## one. A jump of more than a cell (a load, being moved off a new building) snaps instead.
func drawn_pos(r: Dictionary) -> Vector2:
	var prev = _prev_pos.get(r.id)
	if prev == null or prev.distance_to(r.pos) > 1.0:
		return r.pos
	return prev.lerp(r.pos, tick_fraction)


## A resident's body part. Parts hidden behind a tree or wall show as a faint silhouette in the
## resident's tunic colour, so who is who reads even under a canopy (issue #79).
func _person_mat(color: Color, tunic: Color) -> StandardMaterial3D:
	var key := color.to_html() + tunic.to_html()
	if not _person_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		m.next_pass = _xray_material(tunic)
		_person_mats[key] = m
	return _person_mats[key]


var _xrays := {}
var _tag_font: FontVariation


## A faint silhouette shown only where something (a tree, a wall) is in front of a resident,
## so they're never lost behind it. Visible parts of the resident draw normally.
func _xray_material(tunic: Color) -> ShaderMaterial:
	var key := tunic.to_html()
	if not _xrays.has(key):
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back;
uniform vec4 tint : source_color;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void fragment() {
	// Reverse-Z: larger depth is closer. Where the scene is no closer than this fragment, the
	// resident is visible and drawn normally, so the silhouette is skipped.
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	if (FRAGCOORD.z >= scene_depth - 0.00002) {
		discard;
	}
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
"""
		var x := ShaderMaterial.new()
		x.shader = sh
		x.set_shader_parameter("tint", Color(tunic.lerp(Palette.CHALK, 0.3), 0.7))
		x.render_priority = 1
		_xrays[key] = x
	return _xrays[key]


func _part(parent: Node3D, size: Vector3, y: float, color: Color, tunic := Palette.CHALK) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _person_mat(color, tunic)
	mi.position = Vector3(0, y + size.y / 2, 0)
	parent.add_child(mi)
	return mi


func _make_person(r: Dictionary) -> Node3D:
	var n := Node3D.new()
	# The body hops while walking; the selection ring stays on the ground.
	var body := Node3D.new()
	body.name = "Body"
	n.add_child(body)
	var tunic := Color("#" + r.shirt)
	_part(body, Vector3(0.26, 0.32, 0.26), 0, Palette.LEGS, tunic)
	_part(body, Vector3(0.34, 0.46, 0.34), 0.32, tunic, tunic)
	_part(body, Vector3(0.24, 0.32, 0.24), 0.78, Palette.SKIN, tunic)
	var carry := _part(body, Vector3(0.28, 0.24, 0.28), 1.14, Palette.PLANK, tunic)
	carry.name = "Carry"
	var bandage := _part(body, Vector3(0.27, 0.08, 0.27), 0.96, Palette.CHALK, tunic)  # hurt (issue #110)
	bandage.name = "Bandage"
	var pack := _part(body, Vector3(0.3, 0.34, 0.14), 0.38, CRATE, tunic)  # an expedition's packs (issue #108)
	pack.name = "Pack"
	pack.position += Vector3(0.24, 0, -0.04)
	# The selection ring: a chalk band on a dark under-stroke, drawn over everything like the
	# other marks so light grass and trees can't swallow it (issue #79).
	var ring := Node3D.new()
	ring.name = "Ring"
	for band in [[0.27, 0.55, Palette.SLATE_DEEP, 12], [0.33, 0.48, Palette.CHALK, 13]]:
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = band[0]
		torus.outer_radius = band[1]
		torus.rings = 48
		mi.mesh = torus
		mi.scale = Vector3(1, 0.05, 1)
		mi.position.y = 0.04
		var rm := StandardMaterial3D.new()
		rm.albedo_color = band[2]
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.no_depth_test = true
		rm.render_priority = band[3]
		mi.material_override = rm
		ring.add_child(mi)
	n.add_child(ring)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.text = r.name
	if _tag_font == null:  # the HUD's condensed bold, as for names on the slate boards
		_tag_font = FontVariation.new()
		_tag_font.base_font = load("res://assets/fonts/BricolageGrotesque.ttf")
		_tag_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 720, TextServerManager.get_primary_interface().name_to_tag("wdth"): 80}
	tag.font = _tag_font
	tag.font_size = 40
	tag.pixel_size = 0.01
	tag.modulate = Palette.CHALK
	tag.outline_modulate = Palette.SLATE_DEEP
	tag.outline_size = 16
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.render_priority = 17
	tag.outline_render_priority = 16
	tag.position.y = 1.55
	tag.visible = false
	body.add_child(tag)
	var bar := Sprite3D.new()
	bar.name = "Bar"
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.no_depth_test = true
	bar.render_priority = 16
	bar.shaded = false
	bar.position.y = 1.6
	bar.pixel_size = 0.014
	body.add_child(bar)
	add_child(n)
	return n


func _update_people() -> void:
	for r in sim.residents:
		if not _people.has(r.id):
			_people[r.id] = _make_person(r)
		var n: Node3D = _people[r.id]
		n.visible = not r.away and r.map == map_id  # off the map on a meadow trip, or on another map
		var at := drawn_pos(r)
		n.position = Vector3(at.x + 0.5, 0, at.y + 0.5)
		(n.get_node("Body") as Node3D).position.y = _hop(r.id, at)
		var carry: MeshInstance3D = n.get_node("Body/Carry")
		carry.visible = r.carry != null
		(n.get_node("Body/Pack") as Node3D).visible = sim.carrying_packs(r)
		(n.get_node("Body/Bandage") as Node3D).visible = r.get("hurt", 0) > 0
		if r.carry != null:
			carry.material_override = _person_mat(Palette.ITEM_COLORS[r.carry.type], Color("#" + r.shirt))
		(n.get_node("Ring") as Node3D).visible = selected_ids.has(r.id)
		var bar: Sprite3D = n.get_node("Body/Bar")
		bar.visible = r.progress >= 0.0
		var tag: Label3D = n.get_node("Body/Tag")
		tag.visible = selected_ids.has(r.id) or hover_id == r.id
		tag.position.y = 1.95 if bar.visible else 1.55
		if bar.visible:
			bar.texture = _bar_texture(r.progress)


# ---------------------------------------------------------------- sheep (issue #42)

static var SHEEP_WOOL := Color("#EEEBE3")
static var SHEEP_FACE := Color("#5A4E44")
var _sheep_nodes := {}


func _make_sheep() -> Node3D:
	var n := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	n.add_child(body)
	_part(body, Vector3(0.44, 0.16, 0.30), 0.0, SHEEP_FACE)     # legs, as one dark block
	_part(body, Vector3(0.56, 0.34, 0.42), 0.14, SHEEP_WOOL)     # woolly body
	var head := _part(body, Vector3(0.2, 0.22, 0.2), 0.3, SHEEP_FACE)
	head.name = "Head"
	head.position.x = 0.34
	var mark := _sprite(MarkTextures.crosshair(), Vector3(0, 1.0, 0), 0.6, n)
	mark.name = "Mark"
	add_child(n)
	return n


## Sheep move every tick, so they're drawn like residents rather than as static blocks. A marked
## sheep carries a red crosshair that follows it.
func _update_sheep() -> void:
	var here := {}
	for sh in sim.sheep:
		here[sh.id] = true
		if not sh.alive:
			if _sheep_nodes.has(sh.id):
				_sheep_nodes[sh.id].queue_free()
				_sheep_nodes.erase(sh.id)
			continue
		if not _sheep_nodes.has(sh.id):
			_sheep_nodes[sh.id] = _make_sheep()
		var n: Node3D = _sheep_nodes[sh.id]
		n.visible = true
		n.position = Vector3(sh.pos.x + 0.5, 0, sh.pos.y + 0.5)
		if sh.dest != null:
			var d: Vector2 = Vector2(sh.dest) - sh.pos
			if d.length() > 0.01:
				(n.get_node("Body") as Node3D).rotation.y = atan2(-d.y, d.x)
		(n.get_node("Mark") as Node3D).visible = sh.des
	for id in _sheep_nodes:  # sheep on a map that isn't in view
		if not here.has(id):
			_sheep_nodes[id].visible = false


const HOP_STRIDE := 0.5    ## Cells walked per hop.
const HOP_HEIGHT := 0.12   ## How high a hop lifts the body, in blocks.
const HOP_SETTLE := 1.5    ## How fast a resident who stops settles back down, blocks per second.

var _frame_delta := 0.0
var _hops := {}            ## Resident id -> {last: Vector2, phase: float, lift: float}


## A little hop while walking: the body rises and falls once per HOP_STRIDE of distance, so it
## keeps step with the walk at any game speed and stops when they stop.
func _hop(id: int, at: Vector2) -> float:
	var h: Dictionary = _hops.get(id, {"last": at, "phase": 0.0, "lift": 0.0})
	var moved: float = at.distance_to(h.last)
	h.last = at
	if moved > 0.0005 and moved < 1.0:
		h.phase = fmod(h.phase + moved / HOP_STRIDE * PI, TAU)
		h.lift = absf(sin(h.phase)) * HOP_HEIGHT
	else:
		h.lift = move_toward(h.lift, 0.0, HOP_SETTLE * _frame_delta)
		if h.lift == 0.0:
			h.phase = 0.0
	_hops[id] = h
	return h.lift


var _bar_cache := {}


func _bar_texture(p: float) -> ImageTexture:
	var step := int(p * 20)
	if not _bar_cache.has(step):
		var img := Image.create_empty(40, 8, false, Image.FORMAT_RGBA8)
		img.fill(Palette.SLATE_DEEP)
		img.fill_rect(Rect2i(1, 1, int(38 * step / 20.0), 6), Palette.CHALK)
		var tex := ImageTexture.create_from_image(img)
		_bar_cache[step] = tex
	var t: ImageTexture = _bar_cache[step]
	return t


# ---------------------------------------------------------------- per-frame overlays

func _build_live() -> void:
	var dark := Batch.new()
	var col := Batch.new()
	for f in live_fills:
		var r: Rect2i = f.rect
		col.box(Vector3(r.position.x, f.h, r.position.y), Vector3(r.end.x, f.h + 0.02, r.end.y), f.color)
	for o in live_outlines:
		_outline(dark, col, o.rect, o.h, o.color, o.dashed)
	dark.apply(_live_dark)
	col.apply(_live_col)


# ---------------------------------------------------------------- picking

## The ground cell under a camera ray, or null when the ray misses the map.
func ground_cell(origin: Vector3, dir: Vector3):
	if sim.map_id != map_id:
		return sim.on_map(map_id, ground_cell.bind(origin, dir))
	if absf(dir.y) < 1e-5:
		return null
	var t := -origin.y / dir.y
	if t < 0:
		return null
	var p := origin + dir * t
	var c := Vector2i(floori(p.x), floori(p.z))
	return c if sim.in_bounds(c) else null


## What a camera ray points at, in priority order:
## 1. a resident, even behind a tree, since their silhouette shows through (skipped when
##    `residents` is false, as when Mine is active);
## 2. the nearest tree trunk, boulder, sheep, bush, building or farm plot;
## 3. a tree canopy, only when nothing else is under the cursor, so leaves in front don't
##    swallow clicks meant for what's behind them.
## The resident under a ray from the camera, or null.
func pick_resident(origin: Vector3, dir: Vector3):
	return _nearest_hit(origin, dir, sim.residents.filter(func(r): return not r.away and r.map == map_id).map(func(r):
		var p := Vector3(r.pos.x + 0.5, 0, r.pos.y + 0.5)
		return [r, AABB(p - Vector3(0.25, 0, 0.25), Vector3(0.5, 1.15, 0.5))]))


func pick(origin: Vector3, dir: Vector3, residents := true):
	if sim.map_id != map_id:
		return sim.on_map(map_id, pick.bind(origin, dir, residents))
	if residents:
		var r = pick_resident(origin, dir)
		if r != null:
			return r
	var solid: Array = []
	for t in sim.trees:
		if t.alive:
			solid.append([t, AABB(Vector3(t.cell.x + 0.1, 0, t.cell.y + 0.1), Vector3(0.8, 3, 0.8))])
	for b in sim.boulders:
		if b.alive and not b.get("hidden", false):
			solid.append([b, AABB(Vector3(b.cell.x, 0, b.cell.y), Vector3(1, 0.95, 1))])
	for sh in sim.sheep:
		if sh.alive:
			solid.append([sh, AABB(Vector3(sh.pos.x + 0.15, 0, sh.pos.y + 0.15), Vector3(0.7, 0.7, 0.7))])
	for bush in sim.bushes:
		solid.append([bush, AABB(Vector3(bush.cell.x + 0.14, 0, bush.cell.y + 0.14), Vector3(0.72, 0.52, 0.72))])
	for s in sim.sites:
		solid.append([s, AABB(Vector3(s.origin.x, 0, s.origin.y), Vector3(s.size.x, maxf(sim.site_height(s), 0.3), s.size.y))])
	if sim.m.kind == "route":  # the signposts at both ends of the road show the route (issue #119)
		for e in [Road.VILLAGE_END, Road.MINE_END]:
			var at: Vector2i = e + Vector2i(0, -1)
			solid.append([{"kind": "route", "id": 0, "cell": at}, AABB(Vector3(at.x - 0.3, 0, at.y + 0.3), Vector3(1.6, 1.8, 0.4))])
	if sim.m.kind == "village":
		var sign := sim.meadow_sign()
		solid.append([{"kind": "meadow", "id": 0, "cell": sign}, AABB(Vector3(sign.x - 0.4, 0, sign.y + 0.3), Vector3(1.1, 1.8, 0.4))])
		var road := sim.route_sign()
		solid.append([{"kind": "route", "id": 0, "cell": road}, AABB(Vector3(road.x + 0.3, 0, road.y + 0.3), Vector3(1.1, 1.8, 0.4))])
	for k in sim.farm:
		var crop: Dictionary = sim.farm[k]
		solid.append([crop, AABB(Vector3(crop.cell.x, 0, crop.cell.y), Vector3(1, 0.1 + 0.15 * Sim.crop_stage(crop), 1))])
	var hit = _nearest_hit(origin, dir, solid)
	if hit != null:
		return hit
	var canopies: Array = []
	for t in sim.trees:
		if t.alive:
			canopies.append([t, AABB(Vector3(t.cell.x - 1, 3, t.cell.y - 1), Vector3(3, 2, 3))])
	return _nearest_hit(origin, dir, canopies)


func _nearest_hit(origin: Vector3, dir: Vector3, candidates: Array):
	var best = null
	var best_d := INF
	for c in candidates:
		var p = (c[1] as AABB).intersects_ray(origin, dir)
		if p != null and origin.distance_to(p) < best_d:
			best_d = origin.distance_to(p)
			best = c[0]
	return best


static func _hash(x: int, y: int) -> float:
	var hsh := (x * 374761393 + y * 668265263) & 0x7fffffff
	hsh = ((hsh ^ (hsh >> 13)) * 1274126177) & 0x7fffffff
	return float(hsh % 1000) / 1000.0
