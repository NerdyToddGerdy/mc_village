class_name WorldView
extends Node3D
## Draws the sim as 3D blocks. Static geometry is rebuilt only when `sim.rev` changes; residents
## and per-frame overlays (drag rectangles, placement previews, selection) update every frame.
## Grid cell (x, y) maps to world (x, height, y); ground tops sit at height 0.

var sim: Sim
## The map being drawn (issue #101). The view switches the sim to it while drawing and picking, then
## back to the village.
var map_id := "village"

var redstone_overlay := false            ## Dims the world and shows the devices and dust (issue #170).
var _built_overlay := false
var _ov_dark: Batch                      ## The batches drawn over everything while the redstone overlay is on: its dimming, and the devices and dust above it.
var _ov_col: Batch
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
var _block_mat: ShaderMaterial
var _trees_faded: MultiMeshInstance3D
var _roofs: MultiMeshInstance3D
var _occluder_sig := ""


class Batch:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var finishes: Array[Color] = []

	## A box from `lo` to `hi` in `col`, textured with one of BlockTextures' finishes (issue #206).
	func box(lo: Vector3, hi: Vector3, col: Color, finish := BlockTextures.PLAIN) -> void:
		var size := hi - lo
		xforms.append(Transform3D(Basis.from_scale(size), lo + size / 2.0))
		colors.append(col)
		finishes.append(Color(finish.x / 255.0, finish.y / 255.0, finish.z / 255.0, 0.0))

	func apply(mmi: MultiMeshInstance3D) -> void:
		var mm := mmi.multimesh
		mm.instance_count = 0
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, colors[i])
			mm.set_instance_custom_data(i, finishes[i])


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
	_block_mat = _block_material(false)
	_solid = _mm(_block_mat)
	_cart = _mm(_block_mat)
	_trees = _mm(_block_mat)
	_trees_faded = _mm(_block_material(true))
	_roofs = _mm(_block_mat)
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
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi


## The blocks' textured material (issue #206). The see-through one is for faded trees: the same
## shader, blended by the colour's alpha and still writing depth, as their old material did.
static func _block_material(transparent: bool) -> ShaderMaterial:
	var base: Shader = load("res://view/block.gdshader")
	var sh := base
	if transparent:
		sh = Shader.new()
		sh.code = base.code.replace("render_mode cull_back;", "render_mode cull_back, blend_mix, depth_draw_always;").replace("//ALPHA", "ALPHA = base.a;")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("layers", BlockTextures.array())
	return m


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
	if sim.rev != _built_rev or map_id != _built_map or redstone_overlay != _built_overlay:
		_build_static()
		_built_rev = sim.rev
		_built_map = map_id
		_built_overlay = redstone_overlay
	var sig := map_id
	for s in sim.stuck:
		sig += "%s%s%s%s%s;" % [s.map, s.cell, s.height, s.why, s.waiting]
	if sig != _stuck_sig:
		_stuck_sig = sig
		_build_flags()
	_build_occluders()
	_update_people()
	_update_sheep()
	_update_creatures()
	_build_cart()
	_update_portal_glow()
	_build_live()


# ---------------------------------------------------------------- static world

## The mines are colder and harsher than the village (issue #206): a blue-grey grade and stronger texture.
func _grade_blocks(mine: bool, nether := false) -> void:
	for m in [_block_mat, _trees_faded.material_override]:
		m.set_shader_parameter("grade", Palette.NETHER_GRADE if nether else (Palette.MINE_GRADE if mine else Color.WHITE))
		m.set_shader_parameter("contrast", Palette.MINE_CONTRAST if mine or nether else 1.0)


func _build_static() -> void:
	var solid := Batch.new()
	var ghost := Batch.new()
	var dark := Batch.new()
	var col := Batch.new()
	_grade_blocks(sim.m.kind == "site" and sim.m.id != Meadow.ID and not sim.m.id.begins_with("nether"), sim.m.id.begins_with("nether"))
	if sim.m.id == Meadow.ID:
		_add_meadow_ground(solid)
	elif sim.m.kind == "site":
		_add_site_ground(solid)
	elif sim.m.kind == "route":
		_add_route_ground(solid)
	elif sim.m.kind == "walk":
		_add_walk_ground(solid)
	else:
		for x in sim.w:
			for y in sim.h:
				var v := 0.96 + _hash(x, y) * 0.08
				solid.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.1, y + 1), Palette.DIRT, BlockTextures.EARTH)
				var stage := sim.path_stage(Vector2i(x, y))  # the ground packs down where residents walk (issue #196)
				if stage >= 2:
					solid.box(Vector3(x, -0.1, y), Vector3(x + 1, 0, y + 1), (TRODDEN if stage == 2 else PACKED) * Color(v, v, v), BlockTextures.EARTH)
				else:
					solid.box(Vector3(x, -0.1, y), Vector3(x + 1, 0, y + 1), (Palette.GRASS.lerp(TRODDEN, 0.35) if stage == 1 else Palette.GRASS) * Color(v, v, v), BlockTextures.GROUND)
	for b in sim.boulders:
		if b.alive and not b.get("hidden", false) and not _in_fog(b.cell):
			var c: Vector2i = b.cell
			var body: Color = Palette.ITEM_COLORS.obsidian if b.get("ore", "") == "obsidian" else (GRAVEL if b.get("ore", "") == "gravel" else (Palette.ITEM_COLORS.glowstone if b.get("ore", "") == "glowstone" else (NETHER_ROCK.lightened(0.25) if sim.m.id.begins_with("nether") else Palette.STONE)))
			solid.box(Vector3(c.x + 0.08, 0, c.y + 0.08), Vector3(c.x + 0.92, 0.62, c.y + 0.92), body, BlockTextures.COBBLES if b.get("ore", "") == "gravel" else BlockTextures.ROCK)
			solid.box(Vector3(c.x + 0.2, 0.62, c.y + 0.15), Vector3(c.x + 0.7, 0.95, c.y + 0.7), body.lightened(0.06), BlockTextures.ROCK)
			if b.has("ore") and b.ore != "obsidian" and b.ore != "glowstone":  # flecks of ore on its faces and top (issue #103)
				_add_ore_flecks(solid, c, Palette.ITEM_COLORS[b.get("book", Defs.ORES[b.ore].item)])
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
		if not Sim.in_store(k):  # what's in a storehouse's chests shows on their lids
			_add_item(solid, sim.items[k])
	_ov_dark = dark
	_ov_col = col
	for s in sim.sites:
		_add_site(solid, ghost, s)
		if not s.done:
			_outline(dark, col, Rect2i(s.origin, s.size), 0.52 if s.stage >= 1 else 0.02, Palette.BLUE, true)
		if s.get("plot") != null:  # the reserved plot it will grow into, faint
			_outline(dark, col, s.plot, 0.02, Color(Palette.CHALK, 0.35), true)
	if sim.m.kind == "village":
		_add_dust(solid, ghost)
	for p in sim.m.pens:
		_add_pen_plan(ghost, dark, col, p)
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
	var nether: bool = mp.id.begins_with("nether")  # red netherrack, and rock that's nearly black (issues #148, #155)
	var rock_base: Color = NETHER_ROCK if nether else MINE_ROCK
	var floor_base: Color = NETHERRACK if nether else MINE_FLOOR
	for x in mp.w:
		for y in mp.h:
			var c := Vector2i(x, y)
			var v := 0.94 + _hash(x, y) * 0.1
			if c == mp.door:
				_add_door(b, c, mp.door_state == "open", rock_base * Color(v, v, v))
				continue
			if mp.lava.has(c):  # a lava pool sunk into the rock (issue #146)
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.1, y + 1), MINE_ROCK.darkened(0.4))
				b.box(Vector3(x, -0.1, y), Vector3(x + 1, -0.02, y + 1), LAVA * Color(v, v, v))
				continue
			if mp.rock.has(c) or (sim.boulders.any(func(o): return o.alive and o.get("hidden", false) and o.cell == c)):
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, 0.7, y + 1), rock_base * Color(v, v, v), BlockTextures.ROCK)
				continue
			if mp.water.has(c):  # an underground stream (issue #132), below the floor
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.45, y + 1), MINE_FLOOR.darkened(0.3))
				b.box(Vector3(x, -0.45, y), Vector3(x + 1, -0.3, y + 1), (WATER * Color(v, v, v)).darkened(0.25 if mp.is_dark(c) else 0.0))
				continue
			var floor_col := floor_base * Color(v, v, v)
			if mp.is_dark(c):  # unlit: darker and a little cold, but still read as floor, not a hole
				floor_col = floor_col.darkened(0.38).lerp(DARK_TINT, 0.25)
			if c in mp.ledges and mp.visited:  # a ledge: the floor drops, with a pale lip (issue #110)
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.3, y + 1), floor_col.darkened(0.2), BlockTextures.COBBLES)
				b.box(Vector3(x, -0.3, y), Vector3(x + 1, 0, y + 0.12), floor_col.lightened(0.25), BlockTextures.COBBLES)
				continue
			b.box(Vector3(x, -0.6, y), Vector3(x + 1, 0, y + 1), floor_col, BlockTextures.COBBLES)
	for c in mp.fire:  # a patch of fire (issue #149)
		b.box(Vector3(c.x + 0.15, 0, c.y + 0.15), Vector3(c.x + 0.85, 0.4, c.y + 0.85), TORCH_FLAME.darkened(0.15))
		b.box(Vector3(c.x + 0.3, 0.4, c.y + 0.3), Vector3(c.x + 0.7, 0.85, c.y + 0.7), Color("#F7C948"))
		b.box(Vector3(c.x + 0.42, 0.85, c.y + 0.42), Vector3(c.x + 0.58, 1.1, c.y + 0.58), Color("#FBE58A"))
	if mp.salvage != Vector2i(-1, -1) and not mp.salvage_taken:  # the fortress's salvage chest (issue #157)
		var sv := mp.salvage
		b.box(Vector3(sv.x + 0.15, 0, sv.y + 0.2), Vector3(sv.x + 0.85, 0.45, sv.y + 0.8), Palette.PLANK.darkened(0.2), BlockTextures.BOARD)
		b.box(Vector3(sv.x + 0.12, 0.38, sv.y + 0.17), Vector3(sv.x + 0.88, 0.55, sv.y + 0.83), Palette.PLANK.darkened(0.35), BlockTextures.BOARD)
		b.box(Vector3(sv.x + 0.45, 0.3, sv.y + 0.14), Vector3(sv.x + 0.55, 0.45, sv.y + 0.2), Palette.CHALK_DIM)
	for t in mp.torches:
		var x: float = t.x + 0.5
		var z: float = t.y + 0.5
		b.box(Vector3(x - 0.06, 0.7, z - 0.06), Vector3(x + 0.06, 1.1, z + 0.06), Palette.LOG, BlockTextures.LOG)
		b.box(Vector3(x - 0.1, 1.1, z - 0.1), Vector3(x + 0.1, 1.3, z + 0.1), TORCH_FLAME)
	# The way back to the village: a timber frame over the entrance, and the party's packs beside it.
	var e := mp.entrance
	_add_packs(b, mp, Vector2(e.x + 1.2, e.y + 0.17), 1.0)
	if nether:  # the portal's far side: an obsidian arch with a violet glow, and the landmarks to survey
		_add_nether_stations(b, mp)
		if mp.id == NetherLanding.ID:
			_add_landing_features(b, mp)
		else:  # a site's way back: two dark posts and a lintel
			var ob: Color = Palette.ITEM_COLORS.obsidian
			b.box(Vector3(e.x, 0, e.y - 0.1), Vector3(e.x + 0.3, 1.5, e.y + 0.15), ob, BlockTextures.ROCK)
			b.box(Vector3(e.x, 0, e.y + 0.85), Vector3(e.x + 0.3, 1.5, e.y + 1.1), ob, BlockTextures.ROCK)
			b.box(Vector3(e.x, 1.3, e.y - 0.1), Vector3(e.x + 0.3, 1.6, e.y + 1.1), ob, BlockTextures.ROCK)
		return
	b.box(Vector3(e.x, 0, e.y - 0.05), Vector3(e.x + 0.15, 1.4, e.y + 0.1), Palette.LOG, BlockTextures.LOG)
	b.box(Vector3(e.x, 0, e.y + 0.9), Vector3(e.x + 0.15, 1.4, e.y + 1.05), Palette.LOG, BlockTextures.LOG)
	b.box(Vector3(e.x - 0.05, 1.4, e.y - 0.1), Vector3(e.x + 0.2, 1.6, e.y + 1.1), Palette.LOG, BlockTextures.LOG)


## The portal landing's far side (issue #148): the obsidian arch you came through, and a ruined pillar at each landmark,
## with a chalk flag on the ones already seen.
func _add_landing_features(b: Batch, mp: SimMap) -> void:
	var e := mp.entrance
	var ob: Color = Palette.ITEM_COLORS.obsidian
	b.box(Vector3(e.x, 0, e.y - 0.1), Vector3(e.x + 0.3, 1.8, e.y + 0.15), ob, BlockTextures.ROCK)
	b.box(Vector3(e.x, 0, e.y + 0.85), Vector3(e.x + 0.3, 1.8, e.y + 1.1), ob, BlockTextures.ROCK)
	b.box(Vector3(e.x, 1.6, e.y - 0.1), Vector3(e.x + 0.3, 1.9, e.y + 1.1), ob, BlockTextures.ROCK)
	b.box(Vector3(e.x + 0.05, 0, e.y + 0.15), Vector3(e.x + 0.15, 1.6, e.y + 0.85), PORTAL_GLOW)
	for rk in NetherRoute.ROUTES:  # a post at each way out: grey while the route is unknown, yellow part-scouted, blue once scouted
		var ex: Vector2i = NetherRoute.ROUTES[rk].exit
		var rmap: SimMap = sim.maps[NetherRoute.ROUTES[rk].id]
		var post: Color = Palette.BLUE if rmap.surveyed else (Palette.YELLOW if rmap.seen > 1 else Palette.CHALK_DIM)
		b.box(Vector3(ex.x + 0.45, 0, ex.y + 0.45), Vector3(ex.x + 0.55, 1.4, ex.y + 0.55), Palette.LOG, BlockTextures.LOG)
		b.box(Vector3(ex.x + 0.2, 1.1, ex.y + 0.4), Vector3(ex.x + 0.8, 1.45, ex.y + 0.6), post)
	for c in mp.landmarks:
		b.box(Vector3(c.x + 0.25, 0, c.y + 0.25), Vector3(c.x + 0.75, 1.5, c.y + 0.75), NETHER_ROCK.lightened(0.12), BlockTextures.ROCK)
		b.box(Vector3(c.x + 0.2, 1.5, c.y + 0.2), Vector3(c.x + 0.8, 1.7, c.y + 0.8), NETHER_ROCK.lightened(0.2), BlockTextures.ROCK)
		if mp.landmarks_seen.has(c):
			b.box(Vector3(c.x + 0.46, 1.7, c.y + 0.46), Vector3(c.x + 0.52, 2.3, c.y + 0.52), Palette.CHALK)
			b.box(Vector3(c.x + 0.52, 2.05, c.y + 0.46), Vector3(c.x + 0.85, 2.3, c.y + 0.5), Palette.BLUE)


static var NETHERRACK := Color("#8A4040")
static var NETHER_ROCK := Color("#4A2C33")
static var PORTAL_GLOW := Color("#9A63E0")
static var WATER := Color("#4E7EA3")
static var LAVA := Color("#E0561E")
static var GRAVEL := Color("#8B8681")
static var MEADOW_GRASS := Color("#7FA055")
static var MUD := Color("#6E5A3E")


## The party's packs while it works a site (issue #109): a crate for every 3 items in them, in rows of
## three from `at` along x (`dir` 1 east, -1 west).
func _add_packs(b: Batch, mp: SimMap, at: Vector2, dir: float) -> void:
	if not (sim.expedition.get("state", "") == "out" and sim.expedition.dest == mp.id and sim.expedition.party.any(func(id): return sim.at_site(sim.resident(id)))):
		return
	for i in mini(9, ceili(sim.pack_load() / 3.0)):
		var px: float = at.x + dir * float(i % 3) * 0.3
		var pz: float = at.y
		var py := float(i / 3) * 0.26
		b.box(Vector3(px - 0.13, py, pz - 0.13), Vector3(px + 0.13, py + 0.26, pz + 0.13), CRATE, BlockTextures.BOARD)
		b.box(Vector3(px - 0.135, py + 0.1, pz - 0.135), Vector3(px + 0.135, py + 0.14, pz + 0.135), Palette.LOG, BlockTextures.LOG)


## The meadow (issue #137): bright open grass, the pond set below its muddy bank, and old fences of
## posts and rails. A signpost by the entrance on the east edge points home, with the party's packs.
func _add_meadow_ground(b: Batch) -> void:
	var mp := sim.m
	for x in mp.w:
		for y in mp.h:
			var c := Vector2i(x, y)
			var v := 0.95 + _hash(x, y) * 0.1
			if mp.water.has(c):
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.4, y + 1), MUD.darkened(0.2), BlockTextures.EARTH)
				b.box(Vector3(x, -0.4, y), Vector3(x + 1, -0.22, y + 1), WATER * Color(v, v, v))
				continue
			b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.1, y + 1), Palette.DIRT, BlockTextures.EARTH)
			var top := MUD * Color(v, v, v) if c in mp.banks else MEADOW_GRASS * Color(v, v, v)
			b.box(Vector3(x, -0.1, y), Vector3(x + 1, 0, y + 1), top, BlockTextures.EARTH if c in mp.banks else BlockTextures.GROUND)
	for c in mp.fences:
		var x: float = c.x + 0.5
		var z: float = c.y + 0.5
		b.box(Vector3(x - 0.07, 0, z - 0.07), Vector3(x + 0.07, 0.75, z + 0.07), Palette.LOG, BlockTextures.LOG)
		for d in Sim.DIRS:  # rails toward each neighbouring fence or gate
			if mp.fences.has(c + d) or mp.gates.has(c + d):
				var lo := Vector3(x + minf(0.0, d.x * 0.5), 0.0, z + minf(0.0, d.y * 0.5))
				var hi := Vector3(x + maxf(0.0, d.x * 0.5), 0.0, z + maxf(0.0, d.y * 0.5))
				for y in [0.3, 0.58]:
					b.box(Vector3(lo.x - 0.04, y, lo.z - 0.04), Vector3(hi.x + 0.04, y + 0.08, hi.z + 0.04), Palette.LOG.lightened(0.1))
	for c in mp.gates:
		_add_gate(b, c, mp.fences.has(c + Vector2i(1, 0)) or mp.fences.has(c - Vector2i(1, 0)))
	var e := mp.entrance
	_add_end_sign(b, e + Vector2i(0, -1), 1.0, Palette.GRASS)
	_add_packs(b, mp, Vector2(e.x - 1.2, e.y + 0.17), -1.0)
## A pen's gate (issue #139): two posts and a plank gate between them, paler than the fences.
func _add_gate(b: Batch, c: Vector2i, along_x: bool) -> void:
	var x: float = c.x + 0.5
	var z: float = c.y + 0.5
	var a := Vector2(1, 0) if along_x else Vector2(0, 1)
	for k in [-0.42, 0.42]:
		var p: Vector2 = Vector2(x, z) + a * k
		b.box(Vector3(p.x - 0.08, 0, p.y - 0.08), Vector3(p.x + 0.08, 0.85, p.y + 0.08), Palette.LOG, BlockTextures.LOG)
	var half := a * 0.34 + Vector2(a.y, a.x) * 0.04
	for y in [0.22, 0.42, 0.62]:
		b.box(Vector3(x - half.x, y, z - half.y), Vector3(x + half.x, y + 0.1, z + half.y), Palette.PLANK, BlockTextures.BOARD)
	var lo := Vector2(x, z) - a * 0.34
	var hi := Vector2(x, z) + a * 0.34
	_seg_box(b, lo, hi, 0.22, 0.62, Palette.PLANK.darkened(0.15))


## A diagonal brace on a gate, from low at one end to high at the other.
func _seg_box(b: Batch, lo: Vector2, hi: Vector2, y0: float, y1: float, col: Color) -> void:
	for i in 6:
		var t := (i + 0.5) / 6.0
		var p := lo.lerp(hi, t)
		var y := lerpf(y0, y1, t)
		b.box(Vector3(p.x - 0.05, y, p.y - 0.05), Vector3(p.x + 0.05, y + 0.08, p.y + 0.05), col)


## A pen's fences still to build (issue #139): blue ghost posts round its edge, and the pen's outline.
func _add_pen_plan(ghost: Batch, dark: Batch, col: Batch, p: Dictionary) -> void:
	for c in Sim.pen_edge(p):
		if p.built.has(c):
			continue
		var x: float = c.x + 0.5
		var z: float = c.y + 0.5
		var hi := 0.85 if c == p.gate else 0.75
		ghost.box(Vector3(x - 0.08, 0, z - 0.08), Vector3(x + 0.08, hi, z + 0.08), Color(Palette.BLUE, 0.5))
		ghost.box(Vector3(x - 0.3, 0.3, z - 0.3), Vector3(x + 0.3, 0.38, z + 0.3), Color(Palette.BLUE, 0.35))
	if not Sim.pen_done(p):
		_outline(dark, col, p.rect, 0.02, Palette.BLUE, true)


static var DOOR_WOOD := Color("#6B4A2B")
static var DOOR_IRON := Color("#3A3D40")
static var DOORWAY := Color("#1C1E21")


## The door down to the next level (issue #132): a heavy plank door with iron bands, standing in a
## timber frame taller than the rock around it, at the far end of the level. The camera looks at it
## from outside the level, so its planks, bands and frame are drawn on the faces it sees. Open, it
## stands swung back against the frame over a dark doorway.
func _add_door(b: Batch, c: Vector2i, open: bool, rock: Color) -> void:
	var x := float(c.x)
	var z := float(c.y)
	b.box(Vector3(x, -0.6, z), Vector3(x + 1, 0, z + 1), rock.darkened(0.15))
	for k in [0.0, 0.84]:  # the frame: two posts and a lintel
		b.box(Vector3(x + 0.1, 0, z + k), Vector3(x + 0.9, 1.55, z + k + 0.16), Palette.LOG, BlockTextures.LOG)
	b.box(Vector3(x + 0.05, 1.4, z - 0.04), Vector3(x + 0.95, 1.62, z + 1.04), Palette.LOG.darkened(0.1))
	if open:
		b.box(Vector3(x + 0.15, 0, z + 0.16), Vector3(x + 0.85, 1.4, z + 0.84), DOORWAY)
		b.box(Vector3(x + 0.12, 0, z + 0.7), Vector3(x + 0.88, 1.3, z + 0.82), DOOR_WOOD)  # swung back against the frame
		return
	b.box(Vector3(x + 0.18, 0, z + 0.16), Vector3(x + 0.82, 1.4, z + 0.84), DOOR_WOOD)
	for k in 3:  # the planks' seams
		var px := x + 0.34 + k * 0.16
		b.box(Vector3(px - 0.01, 1.4, z + 0.16), Vector3(px + 0.01, 1.41, z + 0.84), DOOR_WOOD.darkened(0.3))
	for y in [0.25, 1.0]:  # iron bands round it, and a ring
		b.box(Vector3(x + 0.16, y, z + 0.14), Vector3(x + 0.84, y + 0.12, z + 0.86), DOOR_IRON)
	b.box(Vector3(x + 0.84, 0.55, z + 0.4), Vector3(x + 0.9, 0.75, z + 0.6), DOOR_IRON)


static var TRODDEN := Color("#8C7B58")
static var PACKED := Color("#74664A")  ## A packed village path, darker than a dirt one (issue #196).
static var FOG := Color("#A9B3AF")
static var SLEEPER := Color("#6A4A2E")


## The road to the mine (issue #118): grass with a trodden path along the line, the stream, and the
## rocky cut's walls. Past the segments anyone has walked, it's fog (issue #119).
func _add_route_ground(b: Batch) -> void:
	var mp := sim.m
	if mp.id.begins_with("nether"):  # a route out of the portal landing (issue #153)
		_add_nether_route_ground(b)
		return
	for x in mp.w:
		for y in mp.h:
			var c := Vector2i(x, y)
			var v := 0.96 + _hash(x, y) * 0.08
			if _in_fog(c):
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, 0.05, y + 1), FOG * Color(v, v, v))
				continue
			if mp.rock.has(c):
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, 1.2, y + 1), MINE_ROCK * Color(v, v, v), BlockTextures.ROCK)
				continue
			if mp.water.has(c):  # a little below the banks
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.4, y + 1), Palette.DIRT, BlockTextures.EARTH)
				b.box(Vector3(x, -0.4, y), Vector3(x + 1, -0.25, y + 1), WATER * Color(v, v, v))
				continue
			b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.1, y + 1), Palette.DIRT, BlockTextures.EARTH)
			var on_line := y == Road.LINE_ROW
			b.box(Vector3(x, -0.1, y), Vector3(x + 1, 0, y + 1), (TRODDEN if on_line else Palette.GRASS) * Color(v, v, v), BlockTextures.EARTH if on_line else BlockTextures.GROUND)
	_add_end_sign(b, Road.VILLAGE_END + Vector2i(0, -1), -1.0, Palette.GRASS)
	_add_end_sign(b, Road.MINE_END + Vector2i(0, -1), 1.0, Palette.STONE)


## The road to the meadow (issue #210): grass, with the trodden line a party walks.
func _add_walk_ground(b: Batch) -> void:
	var mp := sim.m
	for x in mp.w:
		for y in mp.h:
			var v := 0.96 + _hash(x, y) * 0.08
			b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.1, y + 1), Palette.DIRT, BlockTextures.EARTH)
			var on_line := y == MeadowRoad.LINE_ROW
			b.box(Vector3(x, -0.1, y), Vector3(x + 1, 0, y + 1), (TRODDEN if on_line else Palette.GRASS) * Color(v, v, v), BlockTextures.EARTH if on_line else BlockTextures.GROUND)
	_add_end_sign(b, MeadowRoad.VILLAGE_END + Vector2i(0, -1), -1.0, Palette.GRASS)
	_add_end_sign(b, MeadowRoad.far_end() + Vector2i(0, -1), 1.0, Palette.GRASS)


## A Nether route strip: netherrack, rock and lava as laid out, fire, and the dark where nobody has scouted yet.
func _add_nether_route_ground(b: Batch) -> void:
	var mp := sim.m
	for x in mp.w:
		for y in mp.h:
			var c := Vector2i(x, y)
			var v := 0.96 + _hash(x, y) * 0.08
			if _in_fog(c):
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, 0.05, y + 1), NETHER_FOG * Color(v, v, v))
				continue
			if mp.lava.has(c):
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.1, y + 1), NETHER_ROCK.darkened(0.4))
				b.box(Vector3(x, -0.1, y), Vector3(x + 1, -0.02, y + 1), LAVA * Color(v, v, v))
				continue
			if mp.rock.has(c):
				b.box(Vector3(x, -0.6, y), Vector3(x + 1, 1.0, y + 1), NETHER_ROCK * Color(v, v, v), BlockTextures.ROCK)
				continue
			var ledge: bool = c in mp.ledges
			b.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.3 if ledge else 0.0, y + 1), (NETHERRACK * Color(v, v, v)).darkened(0.2 if ledge else 0.0), BlockTextures.COBBLES)
	for c in mp.fire:
		if not _in_fog(c):
			b.box(Vector3(c.x + 0.15, 0, c.y + 0.15), Vector3(c.x + 0.85, 0.4, c.y + 0.85), TORCH_FLAME.darkened(0.15))
			b.box(Vector3(c.x + 0.3, 0.4, c.y + 0.3), Vector3(c.x + 0.7, 0.85, c.y + 0.7), Color("#F7C948"))
	_add_nether_line(b)


static var NETHER_FOG := Color("#2B1A1E")


## The Nether line along the quartz route (issue #159): planks over the bridged segments, sleepers and rails as far as they're
## laid, the two stations and the parked cart.
func _add_nether_line(b: Batch) -> void:
	var mp := sim.m
	if mp.id != NetherRoute.ROUTES.quartz.id or mp.line.is_empty():
		return
	var l: Dictionary = mp.line
	for i in Road.segment_count():
		if l.bridged.has(i):
			var x0: int = Road.SEGMENTS[i].x
			for x in range(x0 + 2, x0 + Road.seg_len(i) - 2):
				b.box(Vector3(x, -0.12, NetherRoute.LINE_ROW), Vector3(x + 1, 0.0, NetherRoute.LINE_ROW + 1), Palette.PLANK, BlockTextures.BOARD)
		var len: int = Road.seg_len(i)
		var cells: int = ceili(float(len) * l.laid[i] / Tuning.RAILS_PER_SEGMENT)
		for k in cells:
			var x: int = Road.SEGMENTS[i].x + k
			b.box(Vector3(x + 0.1, 0.0, NetherRoute.LINE_ROW + 0.35), Vector3(x + 0.9, 0.05, NetherRoute.LINE_ROW + 0.65), Palette.LOG, BlockTextures.LOG)
			for z in [0.3, 0.62]:
				b.box(Vector3(x, 0.05, NetherRoute.LINE_ROW + z), Vector3(x + 1, 0.1, NetherRoute.LINE_ROW + z + 0.08), Palette.ITEM_COLORS.rail)
	if l.stations.landing:
		b.box(Vector3(1, 0, NetherRoute.LINE_ROW + 1), Vector3(4, 0.3, NetherRoute.LINE_ROW + 2), Palette.COBBLE, BlockTextures.COBBLES)
	if l.cart and mp.line.stations.site:
		b.box(Vector3(1.3, 0.3, NetherRoute.LINE_ROW + 1.2), Vector3(2.1, 0.7, NetherRoute.LINE_ROW + 1.8), Palette.ITEM_COLORS.minecart)


static var REDSTONE_ON := Color("#FF5A4A")
static var REDSTONE_OFF := Color("#6B2A26")


## A redstone device (issues #170, #171): a small stone block with a redstone top that glows when it's on, and a post for the sensor.
func _add_device(b_in: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	var done: bool = s.done
	var b := _ov_col if redstone_overlay and done else b_in  # over the dimming, seen through whatever stands in front
	var lift := 0.0
	var on: bool = done and s.out
	b.box(Vector3(o.x + 0.12, lift, o.y + 0.12), Vector3(o.x + 0.88, lift + 0.4, o.y + 0.88), Palette.STONE if done else Color(Palette.BLUE, 0.45), BlockTextures.ROCK)
	if not done:
		return
	b.box(Vector3(o.x + 0.25, lift + 0.4, o.y + 0.25), Vector3(o.x + 0.75, lift + 0.46, o.y + 0.75), REDSTONE_ON if on else REDSTONE_OFF)
	if Defs.TEMPLATES[s.tpl].device == "sensor":
		b.box(Vector3(o.x + 0.42, lift + 0.46, o.y + 0.42), Vector3(o.x + 0.58, lift + 0.85, o.y + 0.58), Palette.STONE)
		b.box(Vector3(o.x + 0.38, lift + 0.85, o.y + 0.38), Vector3(o.x + 0.62, lift + 0.95, o.y + 0.62), REDSTONE_ON if on else REDSTONE_OFF)
	if Defs.TEMPLATES[s.tpl].device == "dispatcher":  # a signal lamp on a post
		b.box(Vector3(o.x + 0.45, lift + 0.46, o.y + 0.45), Vector3(o.x + 0.55, lift + 1.0, o.y + 0.55), Palette.PLANK)
		b.box(Vector3(o.x + 0.3, lift + 1.0, o.y + 0.3), Vector3(o.x + 0.7, lift + 1.2, o.y + 0.7), REDSTONE_ON if on else REDSTONE_OFF)
	if Defs.TEMPLATES[s.tpl].device == "loader":  # a chute over the cart's place
		b.box(Vector3(o.x + 0.2, lift + 0.46, o.y + 0.2), Vector3(o.x + 0.8, lift + 0.7, o.y + 0.35), Palette.STONE)
		b.box(Vector3(o.x + 0.2, lift + 0.46, o.y + 0.65), Vector3(o.x + 0.8, lift + 0.7, o.y + 0.8), Palette.STONE)
	if redstone_overlay:  # a beacon so it stands out from the dimmed world
		b.box(Vector3(o.x + 0.45, lift + 0.46, o.y + 0.45), Vector3(o.x + 0.55, lift + 1.6, o.y + 0.55), Color(REDSTONE_ON, 0.8) if on else Color(REDSTONE_OFF, 0.8))


## Dust lines (issue #170): a red trail over the cells laid, bright while the signal runs; and the redstone overlay's dimming.
func _add_dust(solid: Batch, ghost: Batch) -> void:
	if redstone_overlay:  # the world dims; devices and dust are drawn over it
		_ov_dark.box(Vector3(0, 0, 0), Vector3(sim.w, 0.1, sim.h), Color(0.03, 0.02, 0.06, 0.62))
	var lift := 0.0
	var dust: Batch = _ov_col if redstone_overlay else solid
	for w in sim.wires:
		var src := sim.device_by_id(w.from)
		var live: bool = Sim.wire_complete(w) and not src.is_empty() and src.out
		for i in w.laid:
			var c: Vector2i = w.cells[i]
			dust.box(Vector3(c.x + 0.3, lift, c.y + 0.3), Vector3(c.x + 0.7, lift + (0.07 if live else 0.04), c.y + 0.7), REDSTONE_ON if live else REDSTONE_OFF)
		if redstone_overlay:  # the unlaid cells, as a faint plan
			for i in range(w.laid, w.cells.size()):
				var c: Vector2i = w.cells[i]
				ghost.box(Vector3(c.x + 0.35, lift, c.y + 0.35), Vector3(c.x + 0.65, lift + 0.03, c.y + 0.65), Color(REDSTONE_ON, 0.4))


## The portal line's rails on the landing, from the portal's far side as far as they're laid (issue #168).
func _add_portal_track(b: Batch) -> void:
	var n: int = ceili(float(NetherLanding.TRACK.size()) * sim.portal_line.laid / Tuning.PORTAL_LINE_RAILS)
	for k in n:
		var c: Vector2i = NetherLanding.TRACK[k]
		b.box(Vector3(c.x + 0.1, 0.0, c.y + 0.35), Vector3(c.x + 0.9, 0.05, c.y + 0.65), Palette.LOG, BlockTextures.LOG)
		for z in [0.3, 0.62]:
			b.box(Vector3(c.x, 0.05, c.y + z), Vector3(c.x + 1, 0.1, c.y + z + 0.08), Palette.ITEM_COLORS.rail)


## The stations on the landing's edge and the quartz site (issue #159).
func _add_nether_stations(b: Batch, mp: SimMap) -> void:
	var l: Dictionary = sim.maps[NetherRoute.ROUTES.quartz.id].line
	if l.is_empty():
		return
	if mp.id == NetherLanding.ID:
		_add_portal_track(b)
	if mp.id == NetherLanding.ID and l.stations.landing:  # one station for both lines, beside the shelter (issue #168)
		var at: Vector2i = NetherLanding.STATION_AT
		b.box(Vector3(at.x, 0, at.y), Vector3(at.x + 3, 0.3, at.y + 1), Palette.COBBLE, BlockTextures.COBBLES)
		b.box(Vector3(at.x + 2.9, 0.3, at.y), Vector3(at.x + 3, 1.0, at.y + 1), Palette.PLANK, BlockTextures.BOARD)
	if mp.id == NetherRoute.ROUTES.quartz.site and l.stations.site:
		var p: Rect2i = NetherRoute.QUARTZ_STATION_PLOT
		b.box(Vector3(p.position.x, 0, p.position.y), Vector3(p.position.x + 3, 0.3, p.position.y + 1), Palette.COBBLE, BlockTextures.COBBLES)
		b.box(Vector3(p.position.x + 2.9, 0.3, p.position.y), Vector3(p.position.x + 3, 1.0, p.position.y + 1), Palette.PLANK, BlockTextures.BOARD)
		if l.cart:
			b.box(Vector3(p.position.x + 0.4, 0.3, p.position.y + 0.25), Vector3(p.position.x + 1.4, 0.75, p.position.y + 0.75), Palette.ITEM_COLORS.minecart)


## True for a cell on the road nobody has walked to yet (issue #119).
func _in_fog(c: Vector2i) -> bool:
	return sim.m.kind == "route" and Road.segment_at(c.x) >= sim.m.seen


## A signpost at an end of the road, its board pointing off the map (-1 west, 1 east) with a dab of
## where it leads.
func _add_end_sign(b: Batch, c: Vector2i, dir: float, dab: Color) -> void:
	var x := c.x + 0.5
	var z := c.y + 0.5
	b.box(Vector3(x - 0.09, 0, z - 0.09), Vector3(x + 0.09, 1.8, z + 0.09), Palette.LOG, BlockTextures.LOG)
	var a := x + 0.15 * -dir
	var e := x + 0.7 * dir
	b.box(Vector3(minf(a, e), 1.15, z - 0.06), Vector3(maxf(a, e), 1.6, z + 0.06), Palette.PLANK, BlockTextures.BOARD)
	b.box(Vector3(minf(e, e + 0.15 * dir), 1.25, z - 0.05), Vector3(maxf(e, e + 0.15 * dir), 1.5, z + 0.05), Palette.PLANK, BlockTextures.BOARD)
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
		b.box(Vector3(x0, 0.14, z), Vector3(x1, 0.62, z + 0.12), Palette.LOG, BlockTextures.LOG)


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
	b.box(Vector3(x0, 0, o.y + 0.05), Vector3(x1, 0.22, o.y + 0.95), Palette.COBBLE, BlockTextures.COBBLES)
	b.box(Vector3(x0, 0.22, o.y + 0.05), Vector3(x1, 0.3, o.y + 0.95), Palette.PLANK, BlockTextures.BOARD)
	var stop := x0 if s.get("end", "village") == "village" else x1 - 0.25  # the buffer stop, at the line's end
	b.box(Vector3(stop, 0, Road.LINE_ROW + 0.15), Vector3(stop + 0.25, 0.5, Road.LINE_ROW + 0.85), Palette.LOG, BlockTextures.LOG)
	b.box(Vector3(stop - 0.02, 0.38, Road.LINE_ROW + 0.2), Vector3(stop + 0.27, 0.48, Road.LINE_ROW + 0.8), Palette.RED)


static var CART_DARK := Color("#3E4448")


## The minecart on the line (issues #123, #124), with any cargo heaped in it. Riders are drawn as
## people at the cart's place.
func _build_cart() -> void:
	var c: Dictionary = sim.cart
	var fp := sim.freight_place()
	var fsig: String = "" if fp.is_empty() or fp.map != map_id else "f%s%.2f%s" % [fp.map, sim.freight.pos, sim.freight.load]
	var msig := "" if c.is_empty() or map_id != Road.ID else "%.2f%s" % [c.x, c.load]
	var sig := msig + fsig
	if sig == _cart_sig:
		return
	_cart_sig = sig
	var b := Batch.new()
	if fsig != "":  # the portal line's freight cart, with its load stacked on it (issue #169)
		var fx: float = fp.at.x + 0.5
		var fz: float = fp.at.y + 0.5
		b.box(Vector3(fx - 0.42, 0.12, fz - 0.3), Vector3(fx + 0.42, 0.5, fz + 0.3), Palette.ITEM_COLORS.minecart)
		b.box(Vector3(fx - 0.36, 0.42, fz - 0.24), Vector3(fx + 0.36, 0.51, fz + 0.24), CART_DARK)
		for k in [-0.26, 0.26]:
			b.box(Vector3(fx + k - 0.08, 0.0, fz - 0.34), Vector3(fx + k + 0.08, 0.16, fz + 0.34), Palette.SLATE_DEEP)
		var fn := 0
		for k in sim.freight.load:
			var col: Color = Palette.item_color(k)
			for i in mini(sim.freight.load[k], 6 - fn):
				b.box(Vector3(fx - 0.35 + float(fn % 3) * 0.25, 0.5, fz - 0.18 + float(fn / 3) * 0.2), Vector3(fx - 0.15 + float(fn % 3) * 0.25, 0.64, fz - 0.02 + float(fn / 3) * 0.2), col)
				fn += 1
	if msig != "":
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
			var it_col: Color = Palette.item_color(k)
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
	b.box(Vector3(cx - 0.36, 0, cz - 0.36), Vector3(cx + 0.36, 0.42, cz + 0.36), BUSH_GREEN, BlockTextures.FOLIAGE)
	var spots := [Vector2(-0.18, 0.2), Vector2(0.2, -0.12), Vector2(0.05, 0.22)]
	for i in bush.berries:
		var p: Vector2 = spots[i % spots.size()]
		b.box(Vector3(cx + p.x - 0.07, 0.42, cz + p.y - 0.07), Vector3(cx + p.x + 0.07, 0.52, cz + p.y + 0.07), Palette.ITEM_COLORS.berries)


## The meadow signpost (issue #50): a post with a board pointing off the map's left edge.
func _add_signpost(b: Batch, c: Vector2i) -> void:
	var x := c.x + 0.5
	var z := c.y + 0.5
	b.box(Vector3(x - 0.09, 0, z - 0.09), Vector3(x + 0.09, 1.8, z + 0.09), Palette.LOG, BlockTextures.LOG)
	# An arrow-shaped board pointing off the edge, with a sheep's white fleece painted on it.
	b.box(Vector3(x - 0.7, 1.15, z - 0.06), Vector3(x + 0.15, 1.6, z + 0.06), Palette.PLANK, BlockTextures.BOARD)
	b.box(Vector3(x - 0.85, 1.25, z - 0.05), Vector3(x - 0.7, 1.5, z + 0.05), Palette.PLANK, BlockTextures.BOARD)
	b.box(Vector3(x - 0.45, 1.27, z - 0.08), Vector3(x - 0.12, 1.48, z + 0.08), SHEEP_WOOL, BlockTextures.FLEECE)
	b.box(Vector3(x - 0.55, 1.33, z - 0.08), Vector3(x - 0.45, 1.44, z + 0.08), SHEEP_FACE)


## The signpost to the old mine (issue #108): a board pointing off the east edge, with a grey block of
## stone and a fleck of coal painted on it.
func _add_route_sign(b: Batch, c: Vector2i) -> void:
	var x := c.x + 0.5
	var z := c.y + 0.5
	b.box(Vector3(x - 0.09, 0, z - 0.09), Vector3(x + 0.09, 1.8, z + 0.09), Palette.LOG, BlockTextures.LOG)
	b.box(Vector3(x - 0.15, 1.15, z - 0.06), Vector3(x + 0.7, 1.6, z + 0.06), Palette.PLANK, BlockTextures.BOARD)
	b.box(Vector3(x + 0.7, 1.25, z - 0.05), Vector3(x + 0.85, 1.5, z + 0.05), Palette.PLANK, BlockTextures.BOARD)
	b.box(Vector3(x + 0.12, 1.24, z - 0.08), Vector3(x + 0.45, 1.5, z + 0.08), Palette.STONE, BlockTextures.ROCK)
	b.box(Vector3(x + 0.26, 1.33, z - 0.09), Vector3(x + 0.36, 1.42, z + 0.09), Palette.ITEM_COLORS.coal)


static var SOIL := Color("#5E4430")
static var SPROUT := Color("#7FA84A")
static var WHEAT_RIPE := Color("#D8B65A")


## A tilled plot with two furrows, and wheat rising through three stages to golden ripe ears
## (issue #45).
func _add_crop(b: Batch, crop: Dictionary) -> void:
	var x: float = crop.cell.x
	var z: float = crop.cell.y
	b.box(Vector3(x + 0.04, 0, z + 0.04), Vector3(x + 0.96, 0.03, z + 0.96), SOIL, BlockTextures.TILLED)
	var stage := Sim.crop_stage(crop)
	for row in 2:
		var rz := z + 0.27 + row * 0.46
		b.box(Vector3(x + 0.1, 0.03, rz - 0.09), Vector3(x + 0.9, 0.06, rz + 0.09), SOIL.darkened(0.18), BlockTextures.TILLED)
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
	_add_item_shape(b, s)
	if "+" in s.type:  # an enchanted item shimmers: a violet spark above it (issue #166)
		var sx: float = s.cell.x + 0.5
		var sz: float = s.cell.y + 0.5
		b.box(Vector3(sx - 0.07, 0.34, sz - 0.07), Vector3(sx + 0.07, 0.5, sz + 0.07), PORTAL_GLOW)
		b.box(Vector3(sx - 0.03, 0.5, sz - 0.03), Vector3(sx + 0.03, 0.62, sz + 0.03), Color("#E8D6FF"))


func _add_item_shape(b: Batch, s: Dictionary) -> void:
	var cx: float = s.cell.x + 0.5
	var cz: float = s.cell.y + 0.5
	var color: Color = Palette.item_color(s.type)
	if Defs.is_armor(s.type):  # a folded piece of leather with a darker seam (issue #140)
		b.box(Vector3(cx - 0.24, 0, cz - 0.2), Vector3(cx + 0.24, 0.1, cz + 0.2), color)
		b.box(Vector3(cx - 0.25, 0.02, cz - 0.03), Vector3(cx + 0.25, 0.11, cz + 0.03), color.darkened(0.3))
		return
	if Defs.is_tool_item(s.type):
		b.box(Vector3(cx - 0.3, 0, cz - 0.06), Vector3(cx + 0.3, 0.08, cz + 0.06), Palette.LOG, BlockTextures.LOG)
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
			b.box(Vector3(cx - 0.3, y, cz - 0.08), Vector3(cx + 0.3, y + 0.05, cz + 0.08), Palette.LOG, BlockTextures.LOG)
			for k in [-0.16, 0.16]:
				b.box(Vector3(cx - 0.06 + k, y + 0.05, cz - 0.32), Vector3(cx + 0.06 + k, y + 0.1, cz + 0.32), color)
		return
	if s.type == "stone_brick":  # bricks lie in courses, each offset from the one below (issue #178)
		for i in levels:
			var y := i * 0.13
			var off := 0.0 if i % 2 == 0 else 0.12
			for k in 2:
				var x0 := cx - 0.3 + off + k * 0.3
				b.box(Vector3(x0, y, cz - 0.26), Vector3(minf(x0 + 0.28, cx + 0.3), y + 0.12, cz + 0.26), color if k == 0 else color.darkened(0.08))
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
	if _add_loose_shape(b, s.type, cx, cz, levels, color):
		return
	for i in levels:
		b.box(Vector3(cx - 0.26, i * 0.2, cz - 0.26), Vector3(cx + 0.26, i * 0.2 + 0.2, cz + 0.26), color)


## Offsets and sizes of a heap's lumps, bottom to top (issue #206): uneven, and the same every time.
const LUMPS := [Vector3(-0.1, -0.08, 0.17), Vector3(0.14, 0.1, 0.14), Vector3(0.1, -0.14, 0.12), Vector3(-0.12, 0.12, 0.11), Vector3(0.0, 0.0, 0.1)]
const FOODS := ["berries", "bread", "mutton", "cooked_mutton", "beef", "cooked_beef", "porkchop", "cooked_porkchop"]


## The shapes of the common loose materials (issue #206): each a few boxes, growing with the count
## (up to 4 levels) so a stack still reads at a glance. Returns false for an item without one.
func _add_loose_shape(b: Batch, type: String, cx: float, cz: float, levels: int, color: Color) -> bool:
	if type == "log":  # lengths lying crosswise, a layer to every 4, end rings showing
		for i in levels:
			var y := i * 0.2
			for k in 2:
				var off := -0.14 + k * 0.28
				if i % 2 == 0:
					b.box(Vector3(cx - 0.3, y, cz + off - 0.1), Vector3(cx + 0.3, y + 0.2, cz + off + 0.1), color, BlockTextures.LOG)
				else:
					b.box(Vector3(cx + off - 0.1, y, cz - 0.3), Vector3(cx + off + 0.1, y + 0.2, cz + 0.3), color, BlockTextures.LOG)
	elif type == "plank":  # a neat stack of boards, each a shade apart
		for i in levels:
			var y := i * 0.1
			var off := 0.03 * (i % 2)
			b.box(Vector3(cx - 0.3 + off, y, cz - 0.26), Vector3(cx + 0.3 + off, y + 0.1, cz + 0.26), color.darkened(0.05 * (i % 3)), BlockTextures.BOARD)
	elif type in ["cobble", "coal", "iron_ore", "diamond"]:  # a heap of uneven lumps
		var finish := BlockTextures.COBBLES if type == "cobble" else BlockTextures.ROCK
		for i in levels + 1:
			var l: Vector3 = LUMPS[i]
			var r := 0.17 if i == 0 else 0.13
			var base := 0.0 if i < 3 else 0.2
			b.box(Vector3(cx + l.x - r, base, cz + l.y - r), Vector3(cx + l.x + r, base + r * 2.0, cz + l.y + r), color.darkened(0.06 * (i % 2)), finish)
	elif type == "stick":  # a loose bundle, crossed
		for i in levels:
			var y := i * 0.1
			for k in 2:
				var off := -0.1 + k * 0.2
				if i % 2 == 0:
					b.box(Vector3(cx - 0.3, y, cz + off - 0.04), Vector3(cx + 0.3, y + 0.08, cz + off + 0.04), color, BlockTextures.LOG)
				else:
					b.box(Vector3(cx + off - 0.04, y, cz - 0.3), Vector3(cx + off + 0.04, y + 0.08, cz + 0.3), color, BlockTextures.LOG)
	elif type == "wheat":  # upright sheaves, tied at the middle
		for i in mini(levels, 2):
			var x := cx - 0.14 + i * 0.28
			b.box(Vector3(x - 0.07, 0, cz - 0.07), Vector3(x + 0.07, 0.4, cz + 0.07), color.darkened(0.1))
			b.box(Vector3(x - 0.1, 0.4, cz - 0.1), Vector3(x + 0.1, 0.56, cz + 0.1), color.lightened(0.12))
			b.box(Vector3(x - 0.09, 0.18, cz - 0.09), Vector3(x + 0.09, 0.24, cz + 0.09), Palette.STICK)
	elif type == "sapling":  # a little tuft of leaves on a stem
		b.box(Vector3(cx - 0.03, 0, cz - 0.03), Vector3(cx + 0.03, 0.2, cz + 0.03), Palette.LOG, BlockTextures.LOG)
		b.box(Vector3(cx - 0.2, 0.18, cz - 0.2), Vector3(cx + 0.2, 0.4, cz + 0.2), color, BlockTextures.FOLIAGE)
		b.box(Vector3(cx - 0.12, 0.38, cz - 0.12), Vector3(cx + 0.12, 0.5, cz + 0.12), color.lightened(0.1), BlockTextures.FOLIAGE)
	elif type in FOODS:  # a few pieces on a cloth
		b.box(Vector3(cx - 0.3, 0, cz - 0.26), Vector3(cx + 0.3, 0.03, cz + 0.26), Palette.CHALK.darkened(0.1), BlockTextures.FLEECE)
		for i in levels:
			var l: Vector3 = LUMPS[i]
			var r := 0.1
			b.box(Vector3(cx + l.x * 1.4 - r, 0.03, cz + l.y * 1.4 - r), Vector3(cx + l.x * 1.4 + r, 0.03 + r * 1.6, cz + l.y * 1.4 + r), color)
	elif type == "wool":  # soft, so flat paint
		for i in mini(levels, 2):
			b.box(Vector3(cx - 0.26 + i * 0.04, i * 0.2, cz - 0.24), Vector3(cx + 0.26 + i * 0.04, i * 0.2 + 0.2, cz + 0.24), color.darkened(0.04 * i), BlockTextures.FLEECE)
	elif type == "leather":  # a folded hide
		for i in levels:
			b.box(Vector3(cx - 0.28, i * 0.08, cz - 0.22), Vector3(cx + 0.28, i * 0.08 + 0.08, cz + 0.22), color.darkened(0.05 * (i % 2)))
	elif type == "chest":
		b.box(Vector3(cx - 0.3, 0, cz - 0.22), Vector3(cx + 0.3, 0.34, cz + 0.22), color, BlockTextures.BOARD)
		b.box(Vector3(cx - 0.32, 0.3, cz - 0.24), Vector3(cx + 0.32, 0.42, cz + 0.24), color.darkened(0.12), BlockTextures.BOARD)
		b.box(Vector3(cx - 0.04, 0.2, cz - 0.25), Vector3(cx + 0.04, 0.34, cz - 0.21), Palette.CHALK_DIM)
	else:
		return false
	return true


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
	if s.tpl == "chopping_block":
		_add_chopping_block(solid if s.done else ghost, s)
		return
	if s.tpl == "mason_bench":
		_add_mason_bench(solid if s.done else ghost, s)
		return
	if s.tpl in ["toolsmith_bench", "composter", "lodge", "builder_table"]:
		_add_small_station(solid if s.done else ghost, s)
		return
	if s.tpl == "portal":
		_add_portal(solid if s.done else ghost, s)
		return
	if s.tpl == "shelter":
		_add_shelter(solid if s.done else ghost, s)
		return
	if s.tpl == "enchanting_workshop":
		_add_enchanting_workshop(solid if s.done else ghost, s)
		return
	if s.tpl == "storehouse":
		_add_storehouse(solid if s.stage >= 1 else ghost, s)
		return
	if s.tpl == "claim_stakes":
		_add_claim_stakes(solid if s.done else ghost, s)
		return
	if s.tpl == "bridge":
		_add_bridge(solid if s.done else ghost, s)
		return
	if s.tpl == "track":
		_add_track(solid, ghost, s)
		return
	if Defs.TEMPLATES[s.tpl].has("device"):
		_add_device(solid if s.done else ghost, s)
		return
	if s.tpl == "station" or s.tpl == "portal_station":
		_add_station(solid if s.done else ghost, s)
		return
	var stage: int = s.stage
	var gcol := Color(Palette.BLUE, 0.4)
	for x in range(o.x, o.x + 5):
		for y in range(o.y, o.y + 5):
			if stage >= 1:
				solid.box(Vector3(x, 0, y), Vector3(x + 1, 0.5, y + 1), Palette.COBBLE, BlockTextures.COBBLES)
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
			b.box(Vector3(x, lo, y), Vector3(x + 1, 2.5, y + 1), cc, BlockTextures.LOG if corner else BlockTextures.BOARD)
	if stage == 2:
		_add_roof(ghost, o, gcol)
	# A finished roof is drawn by _build_occluders, so it can be cut away.
	if stage == 3:
		_add_bed(ghost, o, true)
	elif stage >= 4:
		_add_bed(solid, o, false)


static var EMBER := Color("#E8763A")


## Boundary stakes for a land claim (issue #187): a stake on their own cell, and one at each corner
## of the strip they mark, off the edge of the map. Blue ghosts until the builder has planted them.
func _add_claim_stakes(b: Batch, s: Dictionary) -> void:
	var col := Palette.LOG if s.done else Color(Palette.BLUE, 0.6)
	var strip := Claims.strip(s.edge, sim.w, sim.h)
	var spots: Array = [s.origin, strip.position, Vector2i(strip.end.x - 1, strip.position.y), Vector2i(strip.position.x, strip.end.y - 1), strip.end - Vector2i.ONE]
	for c in spots:
		b.box(Vector3(c.x + 0.4, 0, c.y + 0.4), Vector3(c.x + 0.6, 1.1, c.y + 0.6), col)
		b.box(Vector3(c.x + 0.3, 0.8, c.y + 0.3), Vector3(c.x + 0.7, 0.95, c.y + 0.7), Palette.RED if s.done else col)


## A box in a 3×3 building's own frame (x and z from 0 to 3, its door on the far side, +z), turned
## to face the way the building does.
func _box_turned(b: Batch, s: Dictionary, lo: Vector3, hi: Vector3, col: Color) -> void:
	var a := _turn(s, Vector2(lo.x, lo.z))
	var c := _turn(s, Vector2(hi.x, hi.z))
	var o := Vector2(s.origin)
	b.box(Vector3(o.x + minf(a.x, c.x), lo.y, o.y + minf(a.y, c.y)), Vector3(o.x + maxf(a.x, c.x), hi.y, o.y + maxf(a.y, c.y)), col)


static func _turn(s: Dictionary, p: Vector2) -> Vector2:
	match s.rot % 4:
		1: return Vector2(3.0 - p.y, p.x)
		2: return Vector2(3.0 - p.x, 3.0 - p.y)
		3: return Vector2(p.y, 3.0 - p.x)
	return p


## The storehouse (issue #189): a cobblestone floor inside low plank walls, open at the door so its
## chests show. Each chest's lid carries a square of the first few kinds of thing in it.
func _add_storehouse(b: Batch, s: Dictionary) -> void:
	var done: bool = s.done
	var ghost := Color(Palette.BLUE, 0.45)
	_box_turned(b, s, Vector3(0, 0, 0), Vector3(3, 0.15, 3), Palette.COBBLE if s.stage >= 1 else ghost)
	if not done:
		return
	var wall := Palette.PLANK
	var walls := [[Vector3(0, 0.15, 0), Vector3(3, 1.0, 0.18)], [Vector3(0, 0.15, 0), Vector3(0.18, 1.0, 3)], [Vector3(2.82, 0.15, 0), Vector3(3, 1.0, 3)],
		[Vector3(0, 0.15, 2.82), Vector3(1.0, 1.0, 3)], [Vector3(2.0, 0.15, 2.82), Vector3(3, 1.0, 3)]]
	for w in walls:
		_box_turned(b, s, w[0], w[1], wall)
	for p in [Vector2(0.18, 0.18), Vector2(2.82, 0.18), Vector2(0.18, 2.82), Vector2(2.82, 2.82)]:  # corner posts
		_box_turned(b, s, Vector3(p.x - 0.12, 0.15, p.y - 0.12), Vector3(p.x + 0.12, 1.15, p.y + 0.12), Palette.LOG)
	var spots := [Vector2(0.3, 0.3), Vector2(1.95, 0.3), Vector2(0.3, 1.45), Vector2(1.95, 1.45)]  # clear of the path from the door
	var slots := Sim.store_slots(s)
	for i in mini(s.get("chests", 0), spots.size()):
		var p: Vector2 = spots[i]
		_box_turned(b, s, Vector3(p.x, 0.15, p.y), Vector3(p.x + 0.75, 0.62, p.y + 0.55), Palette.PLANK.darkened(0.15))
		_box_turned(b, s, Vector3(p.x - 0.02, 0.5, p.y - 0.02), Vector3(p.x + 0.77, 0.56, p.y + 0.57), Palette.LOG)
		var kinds: Array = []
		for k in slots.slice(i * Tuning.CHEST_STACKS, (i + 1) * Tuning.CHEST_STACKS):
			var it = sim.items.get(k)
			if it != null and not kinds.has(it.type):
				kinds.append(it.type)
		for j in mini(kinds.size(), 3):
			var x := p.x + 0.08 + j * 0.22
			_box_turned(b, s, Vector3(x, 0.62, p.y + 0.15), Vector3(x + 0.16, 0.7, p.y + 0.4), Palette.ITEM_COLORS.get(kinds[j], Palette.CHALK))


## The enchanting workshop (issue #165): an obsidian table with a lectern, an open book and a violet glow. A blueprint until it's built.
func _add_enchanting_workshop(b: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	var done: bool = s.done
	var ob: Color = Palette.ITEM_COLORS.obsidian if done else Color(Palette.BLUE, 0.45)
	b.box(Vector3(o.x + 0.1, 0, o.y + 0.1), Vector3(o.x + 0.9, 0.7, o.y + 0.9), ob, BlockTextures.ROCK)
	if not done:
		return
	b.box(Vector3(o.x + 0.2, 0.7, o.y + 0.25), Vector3(o.x + 0.8, 0.78, o.y + 0.75), Palette.PLANK, BlockTextures.BOARD)
	b.box(Vector3(o.x + 0.28, 0.78, o.y + 0.32), Vector3(o.x + 0.72, 0.84, o.y + 0.68), Palette.ITEM_COLORS.book_efficiency)
	b.box(Vector3(o.x + 0.42, 0.9, o.y + 0.42), Vector3(o.x + 0.58, 1.06, o.y + 0.58), PORTAL_GLOW)


## The landing's shelter (issue #152): a cobblestone floor inside low plank walls, a doorway on the south side, and a crate
## in it for each few meals in the cache. A blueprint until it's built.
func _add_shelter(b: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	var done: bool = s.done
	var floor_c: Color = Palette.COBBLE if done else Color(Palette.BLUE, 0.45)
	var wall: Color = Palette.PLANK if done else Color(Palette.BLUE, 0.45)
	b.box(Vector3(o.x, 0, o.y), Vector3(o.x + 3, 0.12, o.y + 3), floor_c, BlockTextures.COBBLES)
	for k in 3:
		b.box(Vector3(o.x + k, 0.12, o.y), Vector3(o.x + k + 1, 1.0, o.y + 0.2), wall, BlockTextures.BOARD)  # north
		b.box(Vector3(o.x, 0.12, o.y + k), Vector3(o.x + 0.2, 1.0, o.y + k + 1), wall, BlockTextures.BOARD)  # west
		b.box(Vector3(o.x + 2.8, 0.12, o.y + k), Vector3(o.x + 3, 1.0, o.y + k + 1), wall, BlockTextures.BOARD)  # east
	for k in [0, 2]:  # the south wall, with a gap in the middle
		b.box(Vector3(o.x + k, 0.12, o.y + 2.8), Vector3(o.x + k + 1, 1.0, o.y + 3), wall, BlockTextures.BOARD)
	if done:
		b.box(Vector3(o.x - 0.1, 1.0, o.y - 0.1), Vector3(o.x + 3.1, 1.15, o.y + 3.1), Palette.ROOF, BlockTextures.SHINGLES)
		for i in mini(3, ceili(sim.cache_meals() / 2.0)):
			b.box(Vector3(o.x + 0.35 + i * 0.7, 0.12, o.y + 0.4), Vector3(o.x + 0.8 + i * 0.7, 0.55, o.y + 0.85), CRATE, BlockTextures.BOARD)


## The Nether portal (issue #147): a frame of obsidian, four blocks wide, a sill, two pillars and a lintel. Until it's
## built, a blueprint shows where it will stand.
func _add_portal(b: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	var col: Color = Palette.ITEM_COLORS.obsidian if s.done else Color(Palette.BLUE, 0.45)
	var z0 := o.y + 0.2
	var z1 := o.y + 0.8
	b.box(Vector3(o.x, 0, z0), Vector3(o.x + 4.0, 0.3, z1), col, BlockTextures.ROCK)
	b.box(Vector3(o.x, 0.3, z0), Vector3(o.x + 0.7, 2.4, z1), col, BlockTextures.ROCK)
	b.box(Vector3(o.x + 3.3, 0.3, z0), Vector3(o.x + 4.0, 2.4, z1), col, BlockTextures.ROCK)
	b.box(Vector3(o.x + 0.7, 2.1, z0), Vector3(o.x + 3.3, 2.4, z1), col, BlockTextures.ROCK)
	if s.done:  # a few violet specks on the frame, so it isn't a black slab
		for k in [0.3, 1.0, 2.1, 3.6]:
			b.box(Vector3(o.x + k, 0.3 + fmod(k * 1.7, 1.6), z0 - 0.02), Vector3(o.x + k + 0.18, 0.5 + fmod(k * 1.7, 1.6), z0 + 0.02), PORTAL_SPECK)


static var PORTAL_SPECK := Color("#7A4FB5")
var _portal_fx := {}   ## Portal site id -> the lit portal's shimmering plane.


## A lit portal's violet plane, pulsing (issue #147). Drawn each frame, since the batches only rebuild when the sim changes.
func _update_portal_glow() -> void:
	var lit := {}
	if map_id == "village":
		for s in sim.maps.village.sites:
			if s.tpl == "portal" and s.done and s.lit:
				lit[s.id] = s
	for id in _portal_fx.keys():
		if not lit.has(id):
			_portal_fx[id].queue_free()
			_portal_fx.erase(id)
	for id in lit:
		var s: Dictionary = lit[id]
		if not _portal_fx.has(id):
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(2.6, 1.8, 0.1)
			mi.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("#8E5CD6", 0.5)
			mat.emission_enabled = true
			mat.emission = Color("#8E5CD6")
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = mat
			mi.position = Vector3(s.origin.x + 2.0, 1.2, s.origin.y + 0.5)
			add_child(mi)
			_portal_fx[id] = mi
		var pulse := 0.5 + 0.18 * sin(Time.get_ticks_msec() / 400.0 + id)
		(_portal_fx[id].material_override as StandardMaterial3D).albedo_color.a = pulse


## A squat cobblestone hearth with a chimney at the back and embers in its mouth, which faces its
## kitchen plot (issue #46).
func _add_fireplace(b: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	var done: bool = s.done
	var stone: Color = Palette.COBBLE if done else Color(Palette.BLUE, 0.45)
	b.box(Vector3(o.x + 0.08, 0, o.y + 0.08), Vector3(o.x + 0.92, 0.5, o.y + 0.92), stone, BlockTextures.COBBLES)
	# The back is away from the plot: rot 0 opens toward +y, 1 toward -x, 2 toward -y, 3 toward +x.
	var back := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][int(s.get("rot", 0)) % 4] as Vector2
	var c := Vector2(o.x + 0.5, o.y + 0.5)
	var ch := c + back * 0.24
	b.box(Vector3(ch.x - 0.2, 0.5, ch.y - 0.2), Vector3(ch.x + 0.2, 1.05, ch.y + 0.2), stone.darkened(0.08) if done else stone, BlockTextures.COBBLES)
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
		b.box(Vector3(p.x - 0.06, 0, p.y - 0.06), Vector3(p.x + 0.06, 1.55, p.y + 0.06), Palette.LOG, BlockTextures.LOG)
	var half := side * 0.46 + depth * 0.04
	b.box(Vector3(c.x - half.x, 0.7, c.y - half.y), Vector3(c.x + half.x, 1.45, c.y + half.y), Palette.PLANK, BlockTextures.BOARD)
	var mc := c + front * 0.05
	var sheet := side * 0.32 + depth * 0.01
	b.box(Vector3(mc.x - sheet.x, 0.8, mc.y - sheet.y), Vector3(mc.x + sheet.x, 1.35, mc.y + sheet.y), MAP_SHEET)
	# The route drawn on the map, and the red pin on the old mine at its end.
	var route := c + front * 0.06
	var line := side * 0.2 + depth * 0.012
	b.box(Vector3(route.x - line.x, 1.0, route.y - line.y), Vector3(route.x + line.x, 1.04, route.y + line.y), Palette.LOG, BlockTextures.LOG)
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
		b.box(Vector3(p.x - 0.13, y, p.y - 0.13), Vector3(p.x + 0.13, y + 0.26, p.y + 0.13), CRATE, BlockTextures.BOARD)
		b.box(Vector3(p.x - 0.135, y + 0.1, p.y - 0.135), Vector3(p.x + 0.135, y + 0.14, p.y + 0.135), Palette.LOG, BlockTextures.LOG)


## The chopping block (issue #177): a squat round of log with an axe bitten into its top.
func _add_chopping_block(b: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	if not s.done:
		b.box(Vector3(o.x + 0.15, 0, o.y + 0.15), Vector3(o.x + 0.85, 0.2, o.y + 0.85), Color(Palette.BLUE, 0.45))
		return
	b.box(Vector3(o.x + 0.2, 0, o.y + 0.2), Vector3(o.x + 0.8, 0.45, o.y + 0.8), Palette.LOG, BlockTextures.STUMP)
	b.box(Vector3(o.x + 0.24, 0.45, o.y + 0.24), Vector3(o.x + 0.76, 0.48, o.y + 0.76), Palette.PLANK, BlockTextures.CUT)
	b.box(Vector3(o.x + 0.46, 0.48, o.y + 0.3), Vector3(o.x + 0.54, 0.62, o.y + 0.5), Palette.STONE, BlockTextures.ROCK)
	b.box(Vector3(o.x + 0.47, 0.55, o.y + 0.48), Vector3(o.x + 0.53, 0.6, o.y + 0.85), Palette.LOG.lightened(0.2))


## The mason's bench (issue #177): a plank trestle with a dressed stone block and a chisel on top.
func _add_mason_bench(b: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	if not s.done:
		b.box(Vector3(o.x + 0.1, 0, o.y + 0.1), Vector3(o.x + 0.9, 0.2, o.y + 0.9), Color(Palette.BLUE, 0.45))
		return
	if s.get("shaft", false):  # a mineshaft (issue #204): a stone rim round a dark pit, under a timber frame
		b.box(Vector3(o.x + 0.04, 0, o.y + 0.04), Vector3(o.x + 0.96, 0.16, o.y + 0.96), Palette.STONE, BlockTextures.ROCK)
		b.box(Vector3(o.x + 0.22, 0.16, o.y + 0.22), Vector3(o.x + 0.78, 0.18, o.y + 0.78), Palette.SLATE_DEEP)
		for k in [0.1, 0.8]:
			b.box(Vector3(o.x + k, 0.16, o.y + 0.1), Vector3(o.x + k + 0.1, 0.85, o.y + 0.2), Palette.LOG, BlockTextures.LOG)
			b.box(Vector3(o.x + k, 0.16, o.y + 0.8), Vector3(o.x + k + 0.1, 0.85, o.y + 0.9), Palette.LOG, BlockTextures.LOG)
		b.box(Vector3(o.x + 0.1, 0.85, o.y + 0.1), Vector3(o.x + 0.9, 0.95, o.y + 0.2), Palette.PLANK, BlockTextures.BOARD)
		b.box(Vector3(o.x + 0.1, 0.85, o.y + 0.8), Vector3(o.x + 0.9, 0.95, o.y + 0.9), Palette.PLANK, BlockTextures.BOARD)
		return
	for k in [0.15, 0.75]:
		b.box(Vector3(o.x + k, 0, o.y + 0.15), Vector3(o.x + k + 0.1, 0.55, o.y + 0.85), Palette.LOG, BlockTextures.LOG)
	b.box(Vector3(o.x + 0.08, 0.55, o.y + 0.1), Vector3(o.x + 0.92, 0.65, o.y + 0.9), Palette.PLANK, BlockTextures.BOARD)
	b.box(Vector3(o.x + 0.25, 0.65, o.y + 0.3), Vector3(o.x + 0.6, 0.85, o.y + 0.65), Palette.COBBLE.lightened(0.15), BlockTextures.BRICKS)
	b.box(Vector3(o.x + 0.66, 0.65, o.y + 0.35), Vector3(o.x + 0.72, 0.69, o.y + 0.75), Palette.STONE, BlockTextures.ROCK)


static var COMPOST := Color("#4E3B28")


## The other jobs' workstations (issue #184), each a small build you can tell apart at a glance.
func _add_small_station(b: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	if not s.done:
		b.box(Vector3(o.x + 0.1, 0, o.y + 0.1), Vector3(o.x + 0.9, 0.2, o.y + 0.9), Color(Palette.BLUE, 0.45))
		return
	var x := float(o.x)
	var z := float(o.y)
	match s.tpl:
		"toolsmith_bench":  # a plank bench with a stone block for an anvil, and a hammer
			b.box(Vector3(x + 0.1, 0, z + 0.15), Vector3(x + 0.9, 0.6, z + 0.85), Palette.PLANK, BlockTextures.BOARD)
			b.box(Vector3(x + 0.25, 0.6, z + 0.3), Vector3(x + 0.6, 0.85, z + 0.7), Palette.STONE, BlockTextures.ROCK)
			b.box(Vector3(x + 0.65, 0.6, z + 0.45), Vector3(x + 0.85, 0.66, z + 0.55), Palette.LOG, BlockTextures.LOG)
		"composter":  # a plank bin full of dark compost
			b.box(Vector3(x + 0.12, 0, z + 0.12), Vector3(x + 0.88, 0.7, z + 0.88), Palette.PLANK, BlockTextures.BOARD)
			b.box(Vector3(x + 0.2, 0.2, z + 0.2), Vector3(x + 0.8, 0.72, z + 0.8), COMPOST, BlockTextures.EARTH)
		"lodge":  # a lean-to of logs with a hide stretched on its frame
			b.box(Vector3(x + 0.1, 0, z + 0.1), Vector3(x + 0.9, 0.15, z + 0.9), Palette.LOG, BlockTextures.LOG)
			for k in [0.15, 0.75]:
				b.box(Vector3(x + k, 0, z + 0.15), Vector3(x + k + 0.1, 1.0, z + 0.25), Palette.LOG, BlockTextures.LOG)
			b.box(Vector3(x + 0.2, 0.35, z + 0.17), Vector3(x + 0.8, 0.95, z + 0.23), Palette.ITEM_COLORS.leather, BlockTextures.FLEECE)
		"builder_table":  # a sawhorse and a trestle with a plank across them
			for k in [0.12, 0.78]:
				b.box(Vector3(x + k, 0, z + 0.2), Vector3(x + k + 0.1, 0.5, z + 0.8), Palette.LOG, BlockTextures.LOG)
			b.box(Vector3(x + 0.05, 0.5, z + 0.35), Vector3(x + 0.95, 0.58, z + 0.65), Palette.PLANK, BlockTextures.BOARD)


static var BED_BLANKET := Color("#B83A3A")


## The bed sits in the house's top corner: the back corner, furthest from the camera (issue #43).
## Two cells long against the back wall, with a plank frame, a red blanket and a white pillow.
func _add_bed(b: Batch, o: Vector2i, ghost: bool) -> void:
	var g := Color(Palette.BLUE, 0.45)
	var x0 := float(o.x + 1) + 0.1
	var z0 := float(o.y + 1) + 0.1
	b.box(Vector3(x0, 0.5, z0), Vector3(x0 + 1.8, 0.72, z0 + 0.8), g if ghost else Palette.PLANK, BlockTextures.BOARD)
	if ghost:
		return
	b.box(Vector3(x0 + 0.05, 0.72, z0 + 0.05), Vector3(x0 + 0.55, 0.84, z0 + 0.75), Palette.ITEM_COLORS.wool, BlockTextures.FLEECE)
	b.box(Vector3(x0 + 0.6, 0.72, z0 + 0.03), Vector3(x0 + 1.77, 0.82, z0 + 0.77), BED_BLANKET, BlockTextures.FLEECE)


func _add_roof(b: Batch, o: Vector2i, color: Color) -> void:
	for a in 3:
		for x in range(o.x + a, o.x + 5 - a):
			for y in range(o.y + a, o.y + 5 - a):
				b.box(Vector3(x, 2.5 + a * 0.5, y), Vector3(x + 1, 3.0 + a * 0.5, y + 1), color, BlockTextures.SHINGLES)


# ---------------------------------------------------------------- trees and roofs that get out of the way

const _TOWARD_CAMERA := Vector3(0.57735, 0.57735, 0.57735)


static func _tree_boxes(c: Vector2i, stage := 2) -> Array:
	match stage:
		0:  # a sapling: a thin stem with a tuft of leaves (issue #177)
			return [AABB(Vector3(c.x + 0.42, 0, c.y + 0.42), Vector3(0.16, 0.6, 0.16)),
				AABB(Vector3(c.x + 0.25, 0.6, c.y + 0.25), Vector3(0.5, 0.4, 0.5)),
				AABB(Vector3(c.x + 0.38, 1.0, c.y + 0.38), Vector3(0.24, 0.2, 0.24))]
		1:  # a young tree: a cell wide, half height
			return [AABB(Vector3(c.x + 0.3, 0, c.y + 0.3), Vector3(0.4, 1.5, 0.4)),
				AABB(Vector3(c.x - 0.1, 1.5, c.y - 0.1), Vector3(1.2, 0.8, 1.2)),
				AABB(Vector3(c.x + 0.2, 2.3, c.y + 0.2), Vector3(0.6, 0.5, 0.6))]
	return [AABB(Vector3(c.x + 0.1, 0, c.y + 0.1), Vector3(0.8, 3, 0.8)),
		AABB(Vector3(c.x - 1, 3, c.y - 1), Vector3(3, 1, 3)),
		AABB(Vector3(c.x, 4, c.y), Vector3(1, 1, 1))]


## True when the tree stands between the camera and one of the focus points.
func _tree_occludes(t: Dictionary) -> bool:
	for f in focus_points:
		if f[1] == t.id:
			continue
		var p: Vector3 = f[0]
		for box in _tree_boxes(t.cell, Sim.tree_stage(t)):
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
		var boxes := _tree_boxes(t.cell, Sim.tree_stage(t))
		b.box(boxes[0].position, boxes[0].end, Color(Palette.LOG, alpha), BlockTextures.LOG)
		b.box(boxes[1].position, boxes[1].end, Color(Palette.LEAVES, alpha), BlockTextures.FOLIAGE)
		b.box(boxes[2].position, boxes[2].end, Color(Palette.LEAVES, alpha), BlockTextures.FOLIAGE)
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
	for o in sim.trees + sim.boulders:  # kept from gatherers' own work (issue #177)
		if o.alive and o.get("keep", false) and not o.des:
			_sprite(MarkTextures.keep(), Vector3(o.cell.x + 0.5, 1.6 if o.kind == "tree" else 0.7, o.cell.y + 0.5), 0.6, _marks)


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
func _person_mat(color: Color, tunic: Color, finish := BlockTextures.PLAIN) -> Material:
	var key := color.to_html() + tunic.to_html() + str(finish)
	if not _person_mats.has(key):
		var m: Material
		if finish == BlockTextures.PLAIN:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = color
			sm.roughness = 1.0
			sm.next_pass = _xray_material(tunic)
			m = sm
		else:  # a pixel texture (issue #206, phase 4), through the blocks' shader
			var shm := _block_material(false)
			shm.set_shader_parameter("from_instance", false)
			shm.set_shader_parameter("local_uv", true)
			shm.set_shader_parameter("tint", color)
			shm.set_shader_parameter("finish", Vector3(finish))
			shm.next_pass = _xray_material(tunic)
			m = shm
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


func _part(parent: Node3D, size: Vector3, y: float, color: Color, tunic := Palette.CHALK, finish := BlockTextures.PLAIN) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _person_mat(color, tunic, finish)
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
	# Feet, legs and shirt are their own boxes, so worn armor (issue #140) can recolour each.
	_part(body, Vector3(0.26, 0.1, 0.26), 0, Palette.LEGS, tunic).name = "Feet"
	_part(body, Vector3(0.26, 0.22, 0.26), 0.1, Palette.LEGS, tunic, BlockTextures.CLOTHING).name = "Legs"
	_part(body, Vector3(0.34, 0.46, 0.34), 0.32, tunic, tunic, BlockTextures.CLOTHING).name = "Shirt"
	_part(body, Vector3(0.24, 0.32, 0.24), 0.78, Palette.SKIN, tunic)
	var carry := _part(body, Vector3(0.28, 0.24, 0.28), 1.14, Palette.PLANK, tunic)
	carry.name = "Carry"
	var bandage := _part(body, Vector3(0.27, 0.08, 0.27), 0.96, Palette.CHALK, tunic)  # hurt (issue #110)
	bandage.name = "Bandage"
	var cap := _part(body, Vector3(0.28, 0.08, 0.28), 1.1, Palette.ITEM_COLORS.leather.darkened(0.15), tunic)  # a leather cap on top (issue #140)
	cap.name = "Cap"
	cap.visible = false
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
		_dress(n, r)
		if r.carry != null:
			carry.material_override = _person_mat(Palette.item_color(r.carry.type), Color("#" + r.shirt))
		(n.get_node("Ring") as Node3D).visible = selected_ids.has(r.id)
		var bar: Sprite3D = n.get_node("Body/Bar")
		bar.visible = r.progress >= 0.0
		var tag: Label3D = n.get_node("Body/Tag")
		tag.visible = selected_ids.has(r.id) or hover_id == r.id
		tag.position.y = 1.95 if bar.visible else 1.55
		if bar.visible:
			bar.texture = _bar_texture(r.progress)


## Worn armor tints the model (issue #140): brown boots, trousers and tunic in place of the clothes,
## and a cap on the head.
func _dress(n: Node3D, r: Dictionary) -> void:
	var worn := Sim.armor_worn(r)
	var tunic := Color("#" + r.shirt)
	var leather: Color = Palette.ITEM_COLORS.leather
	(n.get_node("Body/Cap") as Node3D).visible = worn.has("head")
	for p in [["Feet", "feet", Palette.LEGS, leather.darkened(0.15)], ["Legs", "legs", Palette.LEGS, leather], ["Shirt", "chest", tunic, leather]]:
		var on: bool = worn.has(p[1])
		var finish := BlockTextures.HIDE if on else (BlockTextures.PLAIN if p[0] == "Feet" else BlockTextures.CLOTHING)
		(n.get_node("Body/" + p[0]) as MeshInstance3D).material_override = _person_mat(p[3] if on else p[2], tunic, finish)


# ---------------------------------------------------------------- animals (issues #42, #138)

static var SHEEP_WOOL := Color("#EEEBE3")
static var SHEEP_FACE := Color("#5A4E44")
static var COW_HIDE := Color("#6B4429")
static var COW_PATCH := Color("#EDE6DA")
static var HORN := Color("#D8CDB4")
static var PIG_SKIN := Color("#E8A2A0")
static var PIG_SNOUT := Color("#D07C80")
var _sheep_nodes := {}


## An animal made of boxes, told apart by shape as well as colour: a sheep is a woolly block on a dark
## face, a cow is tall and long, brown with white patches and horns, a pig is low and pink with a snout.
func _make_animal(species: String) -> Node3D:
	var n := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	n.add_child(body)
	match species:
		"cow":
			_part(body, Vector3(0.58, 0.26, 0.34), 0.0, COW_HIDE.darkened(0.3))  # legs
			var hide := _part(body, Vector3(0.74, 0.36, 0.44), 0.24, COW_HIDE, Palette.CHALK, BlockTextures.HIDE)
			hide.name = "Hide"
			var patch := _part(body, Vector3(0.28, 0.37, 0.45), 0.24, COW_PATCH)  # a white patch round its middle
			patch.position.x = -0.1
			var head := _part(body, Vector3(0.24, 0.26, 0.26), 0.4, COW_HIDE)
			head.position.x = 0.46
			var muzzle := _part(body, Vector3(0.08, 0.12, 0.2), 0.42, COW_PATCH)
			muzzle.position.x = 0.61
			for z in [-0.17, 0.17]:
				var horn := _part(body, Vector3(0.06, 0.1, 0.06), 0.66, HORN)
				horn.position.x = 0.46
				horn.position.z = z
		"pig":
			_part(body, Vector3(0.38, 0.1, 0.26), 0.0, PIG_SNOUT.darkened(0.2))  # short legs
			_part(body, Vector3(0.5, 0.26, 0.36), 0.08, PIG_SKIN, Palette.CHALK, BlockTextures.HIDE)
			var head := _part(body, Vector3(0.2, 0.2, 0.24), 0.12, PIG_SKIN)
			head.position.x = 0.32
			var snout := _part(body, Vector3(0.06, 0.1, 0.14), 0.16, PIG_SNOUT)
			snout.position.x = 0.44
		_:
			_part(body, Vector3(0.44, 0.16, 0.30), 0.0, SHEEP_FACE)     # legs, as one dark block
			_part(body, Vector3(0.56, 0.34, 0.42), 0.14, SHEEP_WOOL, Palette.CHALK, BlockTextures.FLEECE)     # woolly body
			var head := _part(body, Vector3(0.2, 0.22, 0.2), 0.3, SHEEP_FACE)
			head.name = "Head"
			head.position.x = 0.34
	var mark := _sprite(MarkTextures.crosshair(), Vector3(0, 1.1 if species == "cow" else 1.0, 0), 0.6, n)
	mark.name = "Mark"
	var lead := _sprite(MarkTextures.lead(), Vector3(0, 1.1 if species == "cow" else 1.0, 0), 0.6, n)
	lead.name = "Lead"
	var heart := _sprite(MarkTextures.heart(), Vector3(0, 1.0 if species == "cow" else 0.9, 0), 0.4, n)
	heart.name = "Heart"
	add_child(n)
	return n


## Animals move every tick, so they're drawn like residents rather than as static blocks. A marked
## one carries a red crosshair that follows it.
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
			_sheep_nodes[sh.id] = _make_animal(sh.get("species", "sheep"))
		var n: Node3D = _sheep_nodes[sh.id]
		n.visible = true
		n.position = Vector3(sh.pos.x + 0.5, 0, sh.pos.y + 0.5)
		if sh.dest != null:
			var d: Vector2 = Vector2(sh.dest) - sh.pos
			if d.length() > 0.01:
				(n.get_node("Body") as Node3D).rotation.y = atan2(-d.y, d.x)
		(n.get_node("Mark") as Node3D).visible = sh.des
		(n.get_node("Lead") as Node3D).visible = sh.get("lead", false) and not sh.des
		(n.get_node("Heart") as Node3D).visible = sh.get("fed_at", -1) >= 0
		(n.get_node("Body") as Node3D).scale = Vector3.ONE * (0.6 if sh.get("young", false) else 1.0)  # issue #139
		if sh.get("led_by", 0) != 0:
			var lr := sim.resident(sh.led_by)
			var d: Vector2 = lr.get("pos", sh.pos) - sh.pos
			if d.length() > 0.01:
				(n.get_node("Body") as Node3D).rotation.y = atan2(-d.y, d.x)
	for id in _sheep_nodes:  # sheep on a map that isn't in view
		if not here.has(id):
			_sheep_nodes[id].visible = false


# ---------------------------------------------------------------- the Nether's creatures (issue #151)

static var CREATURE_COLORS := {"magma_cube": Color("#C4501E"), "zombified_piglin": Color("#C98A83"), "skeleton": Color("#DCD7C5"), "blaze": Color("#F2B531")}
var _creature_nodes := {}   ## Creature id -> its model.


func _make_creature(species: String) -> Node3D:
	var n := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	n.add_child(body)
	var col: Color = CREATURE_COLORS[species]
	match species:
		"magma_cube":  # a squat cube with a darker crust and a glowing seam
			_part(body, Vector3(0.62, 0.5, 0.62), 0.0, col.darkened(0.25))
			_part(body, Vector3(0.64, 0.12, 0.64), 0.2, Color("#F7C948"))
			_part(body, Vector3(0.5, 0.14, 0.5), 0.5, col)
		"zombified_piglin":  # a pink head over a green rag of a shirt
			_part(body, Vector3(0.26, 0.3, 0.26), 0.0, Color("#4B4F5C"))
			_part(body, Vector3(0.34, 0.44, 0.34), 0.3, Color("#6E8E58"))
			_part(body, Vector3(0.32, 0.3, 0.32), 0.74, col)
		"skeleton":  # thin and pale
			_part(body, Vector3(0.18, 0.4, 0.18), 0.0, col)
			_part(body, Vector3(0.28, 0.4, 0.2), 0.4, col.darkened(0.08))
			_part(body, Vector3(0.26, 0.26, 0.26), 0.8, col)
		_:  # a blaze: a head over three yellow rods that hover
			_part(body, Vector3(0.3, 0.3, 0.3), 0.7, col)
			for k in 3:
				_part(body, Vector3(0.08, 0.5, 0.08), 0.15 + k * 0.05, col.darkened(0.2)).position.x = -0.18 + k * 0.18
	add_child(n)
	return n


## Draws the creatures of the map in view, a little larger for a moment after a blow either way.
func _update_creatures() -> void:
	var here := {}
	for x in sim.m.creatures:
		if not x.alive or _in_fog(x.cell):
			continue
		here[x.id] = true
		if not _creature_nodes.has(x.id):
			_creature_nodes[x.id] = _make_creature(x.species)
		var n: Node3D = _creature_nodes[x.id]
		n.visible = true
		n.position = Vector3(x.pos.x + 0.5, 0, x.pos.y + 0.5)
		(n.get_node("Body") as Node3D).scale = Vector3.ONE * (1.25 if sim.tick < x.flash else 1.0)
	for id in _creature_nodes.keys():
		if not here.has(id):
			_creature_nodes[id].queue_free()
			_creature_nodes.erase(id)


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
	for p in sim.m.pens:  # a pen is picked by its fences (issue #139)
		for c in Sim.pen_edge(p):
			solid.append([p, AABB(Vector3(c.x + 0.1, 0, c.y + 0.1), Vector3(0.8, 0.8, 0.8))])
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
