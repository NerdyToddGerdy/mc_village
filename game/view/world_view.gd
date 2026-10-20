class_name WorldView
extends Node3D
## Draws the sim as 3D blocks. Static geometry is rebuilt only when `sim.rev` changes; residents
## and per-frame overlays (drag rectangles, placement previews, selection) update every frame.
## Grid cell (x, y) maps to world (x, height, y); ground tops sit at height 0.

var sim: Sim

var _built_rev := -1
var _stuck_sig := ""
var _solid: MultiMeshInstance3D
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
	if sim.rev != _built_rev:
		_build_static()
		_built_rev = sim.rev
	var sig := ""
	for s in sim.stuck:
		sig += "%s%s%s;" % [s.cell, s.height, s.why]
	if sig != _stuck_sig:
		_stuck_sig = sig
		_build_flags()
	_build_occluders()
	_update_people()
	_update_sheep()
	_build_live()


# ---------------------------------------------------------------- static world

func _build_static() -> void:
	var solid := Batch.new()
	var ghost := Batch.new()
	var dark := Batch.new()
	var col := Batch.new()
	for x in sim.w:
		for y in sim.h:
			var v := 0.96 + _hash(x, y) * 0.08
			solid.box(Vector3(x, -0.6, y), Vector3(x + 1, -0.1, y + 1), Palette.DIRT)
			solid.box(Vector3(x, -0.1, y), Vector3(x + 1, 0, y + 1), Palette.GRASS * Color(v, v, v))
	for b in sim.boulders:
		if b.alive:
			var c: Vector2i = b.cell
			solid.box(Vector3(c.x + 0.08, 0, c.y + 0.08), Vector3(c.x + 0.92, 0.62, c.y + 0.92), Palette.STONE)
			solid.box(Vector3(c.x + 0.2, 0.62, c.y + 0.15), Vector3(c.x + 0.7, 0.95, c.y + 0.7), Palette.STONE.lightened(0.06))
	for bush in sim.bushes:
		_add_bush(solid, bush)
	for k in sim.farm:
		_add_crop(solid, sim.farm[k])
	for k in sim.items:
		_add_item(solid, sim.items[k])
	for s in sim.sites:
		_add_site(solid, ghost, s)
		if not s.done:
			_outline(dark, col, Rect2i(s.origin, s.size), 0.52 if s.stage >= 1 else 0.02, Palette.BLUE, true)
	solid.apply(_solid)
	ghost.apply(_ghost)
	_occluder_sig = ""
	dark.apply(_over_dark)
	col.apply(_over_col)
	_build_marks()
	_build_hatch()


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
	var levels: int = mini(4, ceili(s.n / 4.0))
	for i in levels:
		b.box(Vector3(cx - 0.26, i * 0.2, cz - 0.26), Vector3(cx + 0.26, i * 0.2 + 0.2, cz + 0.26), color)


func _add_site(solid: Batch, ghost: Batch, s: Dictionary) -> void:
	var o: Vector2i = s.origin
	if s.tpl == "bench":
		var b := solid if s.done else ghost
		var top := Palette.PLANK if s.done else Color(Palette.BLUE, 0.45)
		b.box(Vector3(o.x + 0.1, 0, o.y + 0.1), Vector3(o.x + 0.9, 0.75, o.y + 0.9), top)
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
		if not t.alive:
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
			_seg(dark, p0, p1, h, 0.13, Palette.SLATE_DEEP)
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


func _person_mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _person_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		m.next_pass = _xray_material()
		_person_mats[key] = m
	return _person_mats[key]


var _xray: ShaderMaterial


## A faint chalk silhouette shown only where something (a tree, a wall) is in front of a resident,
## so they're never lost behind it. Visible parts of the resident draw normally.
func _xray_material() -> ShaderMaterial:
	if _xray == null:
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
		_xray = ShaderMaterial.new()
		_xray.shader = sh
		_xray.set_shader_parameter("tint", Color(Palette.CHALK, 0.45))
		_xray.render_priority = 1
	return _xray


func _part(parent: Node3D, size: Vector3, y: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _person_mat(color)
	mi.position = Vector3(0, y + size.y / 2, 0)
	parent.add_child(mi)
	return mi


func _make_person(r: Dictionary) -> Node3D:
	var n := Node3D.new()
	# The body hops while walking; the selection ring stays on the ground.
	var body := Node3D.new()
	body.name = "Body"
	n.add_child(body)
	_part(body, Vector3(0.26, 0.32, 0.26), 0, Palette.LEGS)
	_part(body, Vector3(0.34, 0.46, 0.34), 0.32, Color("#" + r.shirt))
	_part(body, Vector3(0.24, 0.32, 0.24), 0.78, Palette.SKIN)
	var carry := _part(body, Vector3(0.28, 0.24, 0.28), 1.14, Palette.PLANK)
	carry.name = "Carry"
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.4
	ring.mesh = torus
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.03
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Palette.CHALK
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.name = "Ring"
	n.add_child(ring)
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
		var at := drawn_pos(r)
		n.position = Vector3(at.x + 0.5, 0, at.y + 0.5)
		(n.get_node("Body") as Node3D).position.y = _hop(r.id, at)
		var carry: MeshInstance3D = n.get_node("Body/Carry")
		carry.visible = r.carry != null
		if r.carry != null:
			carry.material_override = _person_mat(Palette.ITEM_COLORS[r.carry.type])
		(n.get_node("Ring") as Node3D).visible = selected_ids.has(r.id)
		var bar: Sprite3D = n.get_node("Body/Bar")
		bar.visible = r.progress >= 0.0
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
	for sh in sim.sheep:
		if not sh.alive:
			if _sheep_nodes.has(sh.id):
				_sheep_nodes[sh.id].queue_free()
				_sheep_nodes.erase(sh.id)
			continue
		if not _sheep_nodes.has(sh.id):
			_sheep_nodes[sh.id] = _make_sheep()
		var n: Node3D = _sheep_nodes[sh.id]
		n.position = Vector3(sh.pos.x + 0.5, 0, sh.pos.y + 0.5)
		if sh.dest != null:
			var d: Vector2 = Vector2(sh.dest) - sh.pos
			if d.length() > 0.01:
				(n.get_node("Body") as Node3D).rotation.y = atan2(-d.y, d.x)
		(n.get_node("Mark") as Node3D).visible = sh.des


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
func pick(origin: Vector3, dir: Vector3, residents := true):
	if residents:
		var r = _nearest_hit(origin, dir, sim.residents.map(func(r):
			var p := Vector3(r.pos.x + 0.5, 0, r.pos.y + 0.5)
			return [r, AABB(p - Vector3(0.25, 0, 0.25), Vector3(0.5, 1.15, 0.5))]))
		if r != null:
			return r
	var solid: Array = []
	for t in sim.trees:
		if t.alive:
			solid.append([t, AABB(Vector3(t.cell.x + 0.1, 0, t.cell.y + 0.1), Vector3(0.8, 3, 0.8))])
	for b in sim.boulders:
		if b.alive:
			solid.append([b, AABB(Vector3(b.cell.x, 0, b.cell.y), Vector3(1, 0.95, 1))])
	for sh in sim.sheep:
		if sh.alive:
			solid.append([sh, AABB(Vector3(sh.pos.x + 0.15, 0, sh.pos.y + 0.15), Vector3(0.7, 0.7, 0.7))])
	for bush in sim.bushes:
		solid.append([bush, AABB(Vector3(bush.cell.x + 0.14, 0, bush.cell.y + 0.14), Vector3(0.72, 0.52, 0.72))])
	for s in sim.sites:
		solid.append([s, AABB(Vector3(s.origin.x, 0, s.origin.y), Vector3(s.size.x, maxf(sim.site_height(s), 0.3), s.size.y))])
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
