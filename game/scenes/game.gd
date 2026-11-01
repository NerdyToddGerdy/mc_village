class_name Game
extends Node3D
## Hosts the sim at a fixed tick rate, owns the camera and selection, and turns input into sim
## commands. Views never change the sim directly; they call the methods here.

const ISO_DIR := Vector3(1, 1, 1)      ## True isometric: camera looks down (-1, -1, -1).
const ELEVATION_SIN := 0.57735         ## sin(35.26°), for converting screen drags to ground moves.

var sim: Sim
var speed := 1
var last_speed := 1
var tool := ""                          ## "", a Gather or Paint order (OrderMenus.MARK_TOOLS) or "build"
var placing := ""                       ## Template being placed while tool == "build".
var rot := 0
var area_site := 0                      ## The workstation whose work area is being painted, while tool == "area" (issue #203).
var menu_open := ""                     ## The toolbar menu that's open: "", "gather", "paint" or "build".
var build_menu_open: bool:
	get: return menu_open == "build"
	set(v): menu_open = "build" if v else ("" if menu_open == "build" else menu_open)
var craft_menu_open := false            ## The Craft panel above the toolbar (issue #57).
var craft_bench_i := 0                  ## Which finished bench the Craft panel shows.
var jobs_board_open: bool:                ## The village book is open on its Jobs page (issues #78, #198).
	get: return book_open and book_page == "jobs"
	set(v): toggle_jobs_board(v)
var book_open := false                  ## The village book (issue #198).
var book_page := "goals"                ## Its open page: "goals", "jobs", "residents", or a page's id from Goals.PAGES.
var planner_open := false               ## The expedition planner above the toolbar (issue #106).
var line_preview := false                ## The route panel shows the line's cost before it's planned (issue #121).
var plan := {}                          ## The plan being drawn up in the planner; the sim's once confirmed.
var adventure := ""                     ## The destination the board's Location dropdown shows (issues #136, #181): the last one chosen.
var selection := {}                     ## {} | {kind:"res", ids:[...]} | {kind:"tree"/"boulder"/"site", id}
var radial := {}                        ## The open radial Gather menu (issue #176), or {}.
## The map in view (issue #101): "village" or a site map. The sim stays on the village between
## frames; input and drawing switch it to this map while they work, then back.
var view_map := "village"
var _cams := {}                         ## Map id -> {target, size}: where each map's camera was left.

var _acc := 0.0
var _hud_t := 0.0
var _cam := Camera3D.new()
var _target := Vector3.ZERO
var _world := WorldView.new()
var _hud := Hud.new()
var _drag := {}
var _hover = null                       ## Ground cell under the mouse, or null.
var _mouse := Vector2.ZERO
var _stuck_i := -1
var _mods := {"shift": false, "alt": false}  ## Modifier keys, from the latest input event.
var _menu := GameMenu.new()
var keys: KeyBindings
var keys_path := ""  ## Tests set this before the game starts, so they always use default keys.
var _menu_prev_speed := 1

var skipping := false  ## Running fast until something needs the player (issue #299).
var _skip_from := 0
var _skip_sig := ""
var _skip_problems := {}
var _skip_decisions := {}
var _autosave_tick := 0  ## The sim tick of the last autosave, or of the load.
var _autosave_sig := ""
var save_dir := "user://saves"  ## Tests point this elsewhere so they never touch real saves.
const SLOTS := 5
const WATCHED_SITES := 8  ## Blueprints and stuck buildings whose trees in front fade, besides the selected one (issue #304).

## How big the HUD and menus are drawn (issue #80), the player's choice from the menu. The world
## isn't scaled. Saved beside the key bindings, so tests use their own settings folder.
const UI_SCALES := [0.9, 1.0, 1.15, 1.3]
var ui_scale := 1.0


func _ui_settings_path() -> String:
	return keys.path.get_base_dir().path_join("ui.cfg")


func _load_ui_scale() -> void:
	var cfg := ConfigFile.new()
	var v = cfg.get_value("ui", "scale", 1.0) if cfg.load(_ui_settings_path()) == OK else 1.0
	ui_scale = v if v is float and UI_SCALES.has(v) else 1.0
	for a in OS.get_cmdline_user_args():  # --ui-scale=1.15, for checking the layout in screenshots
		if a.begins_with("--ui-scale="):
			ui_scale = a.get_slice("=", 1).to_float()
	get_window().content_scale_factor = ui_scale


## Sets the interface size and saves it. Returns "" or a message for the player.
func set_ui_scale(v: float) -> String:
	ui_scale = v
	get_window().content_scale_factor = v
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_ui_settings_path().get_base_dir()))
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "scale", v)
	return "" if cfg.save(_ui_settings_path()) == OK else "Couldn’t save the interface size."


## The next interface size after the current one, round to the smallest.
func next_ui_scale() -> float:
	var i := UI_SCALES.find(ui_scale)
	return UI_SCALES[(i + 1) % UI_SCALES.size()]


func _ready() -> void:
	keys = KeyBindings.new(keys_path)
	_load_ui_scale()
	sim = Sim.new_game()
	_setup_scene()
	_world.sim = sim
	add_child(_world)
	_look_at_first_resident()
	_hud.game = self
	add_child(_hud)
	_menu.game = self
	_menu.hud = _hud
	_hud.add_overlay(_menu)
	selection = {"kind": "res", "ids": [sim.residents[0].id]}
	if "--screenshot" in OS.get_cmdline_user_args():
		_menu.visible = false
		_hud.minimap_on = "--minimap" in OS.get_cmdline_user_args()
		_screenshot_scene.call_deferred()
	elif "--screenshot-menu" in OS.get_cmdline_user_args():
		_screenshot_menu.call_deferred()
	else:
		open_menu("main")


func _setup_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.86, 0.9)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	add_child(sun)
	# Light from above and slightly to the camera's left: tops brightest, left faces next, right faces darkest.
	sun.look_at_from_position(Vector3.ZERO, -Vector3(0.25, 0.85, 0.5), Vector3.UP)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 17.0
	_cam.near = 0.1
	_cam.far = 200.0
	add_child(_cam)
	_place_camera()


func _look_at_first_resident() -> void:
	var r: Dictionary = sim.residents[0]
	_target = Vector3(r.pos.x + 0.5, 0, r.pos.y + 0.5)
	_place_camera()


func _place_camera() -> void:
	var mp := sim.get_map(view_map)
	var margin: float = Tuning.CLAIM_DEPTH + 2.0 if tool == "claim" else 2.0  # room to see the strips on offer (issue #187)
	_target.x = clampf(_target.x, -margin, mp.w + margin)
	_target.z = clampf(_target.z, -margin, mp.h + margin)
	_cam.position = _target + ISO_DIR.normalized() * 60.0
	_cam.look_at(_target, Vector3.UP)


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	_pan_with_keys(delta)
	_acc += minf(delta, 0.1) * (Tuning.SKIP_SPEED if skipping else float(speed))
	var n := 0
	while _acc >= Tuning.DT and n < 30:
		_world.remember_positions()
		sim.step()
		_acc -= Tuning.DT
		n += 1
		if not sim.pending.is_empty():
			if skipping:
				_end_skip("a choice is waiting")
			break
		if skipping:
			var why := _skip_stop_reason()
			if why != "":
				_end_skip(why)
				break
	if _autosave_due():
		autosave()
	# A choice for the player stops the game until it's answered (issues #110, #111).
	if not sim.pending.is_empty() and speed != 0:
		set_speed(0)
	# How far the game is into the next tick, for drawing residents between ticks (issue #4).
	# Paused, they're drawn exactly where they are.
	_world.tick_fraction = 1.0 if speed == 0 else clampf(_acc / Tuning.DT, 0.0, 1.0)
	for ev in sim.events:
		if ev.type == "toast":
			_hud.add_toast(ev)
	handle_view_events(sim.events)
	sim.events.clear()
	_in_view(_update_live_overlays)
	_world.selected_ids = selection.get("ids", [])
	var ray := _ray(_mouse)
	var under = null if get_viewport().gui_get_hovered_control() != null else _world.pick_resident(ray[0], ray[1])
	_world.hover_id = under.id if under != null else 0
	_hud_t += delta
	if _hud_t > 0.15:
		_hud_t = 0.0
		_hud.refresh(sim)


func _pan_with_keys(delta: float) -> void:
	var v := Vector2.ZERO
	if _menu.visible:
		return
	if keys.is_down("pan_up"): v.y -= 1
	if keys.is_down("pan_down"): v.y += 1
	if keys.is_down("pan_left"): v.x -= 1
	if keys.is_down("pan_right"): v.x += 1
	if v != Vector2.ZERO:
		_pan_screen(v * _cam.size * 0.9 * delta * get_viewport().get_visible_rect().size.y / _cam.size)


## Moves the view by a screen-space offset in pixels.
func _pan_screen(px: Vector2) -> void:
	var upp := _cam.size / get_viewport().get_visible_rect().size.y
	var right := Vector3(_cam.global_basis.x.x, 0, _cam.global_basis.x.z).normalized()
	var down := Vector3(-_cam.global_basis.z.x, 0, -_cam.global_basis.z.z).normalized() * -1.0
	_target += right * px.x * upp + down * px.y * upp / ELEVATION_SIN
	_place_camera()


# ---------------------------------------------------------------- overlays and hints

func _update_live_overlays() -> void:
	var outlines: Array = []
	var fills: Array = []
	var hint := ""
	var hint_col := Palette.CHALK
	if not _drag.is_empty() and _drag.kind == "rect":
		if _drag.get("erase", false):  # erasing a zone: a red outline, and a red fill on each cell that goes
			var cells: Dictionary = sim.farm if tool == "farm" else (_area_cells() if tool == "area" else sim.zone)
			outlines.append({"rect": _drag.rect, "h": 0.03, "color": Palette.RED, "dashed": true})
			for x in range(_drag.rect.position.x, _drag.rect.end.x):
				for y in range(_drag.rect.position.y, _drag.rect.end.y):
					if cells.has(Vector2i(x, y)):
						fills.append({"rect": Rect2i(x, y, 1, 1), "h": 0.02, "color": Color(Palette.RED, 0.45)})
			hint = "Release to erase these farm plots. Anything growing on them is lost." if tool == "farm" else "Release to erase these stockpile cells. Anything on them stays and is hauled to the rest."
			if tool == "area":
				hint = "Release to take these cells out of the work area."
			if tool == "pen":
				hint = "Release to take this pen down. Its fences come down and its animals go free."
			hint_col = Palette.RED
		else:
			var col: Color = {"stock": Palette.GREEN, "farm": Palette.WHEAT, "lead": Palette.BLUE, "pen": Palette.BLUE, "area": Palette.CHALK}.get(tool, Palette.RED)
			if tool == "area":
				var site := sim.site(area_site)
				if not site.is_empty():
					var far := _cells_out_of_reach(site, _drag.rect)
					hint = "Release to add these cells to the work area." if far == 0 else "%d of these cells are more than %d cells from it, and stay unpainted." % [far, int(Tuning.WORK_REACH)]
					hint_col = Palette.CHALK if far == 0 else Palette.YELLOW
			if tool == "pen":  # issue #139: red, with the reason, where a pen can't go
				var why := sim.pen_check(_drag.rect)
				if why != "":
					col = Palette.RED
					hint = why
					hint_col = Palette.YELLOW
				else:
					hint = "Release to paint a %d×%d pen: room for %d, %s." % [_drag.rect.size.x, _drag.rect.size.y, (_drag.rect.size.x - 2) * (_drag.rect.size.y - 2), Defs.words("stick", 2 * (_drag.rect.size.x + _drag.rect.size.y) - 4)]
			outlines.append({"rect": _drag.rect, "h": 0.03, "color": col, "dashed": true})
	elif tool in OrderMenus.MARK_TOOLS and _hover != null:
		outlines.append({"rect": Rect2i(_hover, Vector2i.ONE), "h": 0.03, "color": Palette.CHALK, "dashed": false})
	if view_map == "village":  # strips already staked, until the builder finishes (issue #187)
		for st in sim.sites:
			if st.tpl == "claim_stakes":
				outlines.append({"rect": Claims.strip(st.edge, sim.w, sim.h), "h": 0.03, "color": Palette.BLUE, "dashed": true})
	if tool == "claim":
		var edge := _claim_edge()
		var why := sim.claim_check(edge)
		for e in Claims.EDGES:
			var strip := Claims.strip(e, sim.w, sim.h)
			if e == edge:
				outlines.append({"rect": strip, "h": 0.03, "color": Palette.RED if why != "" else Palette.BLUE, "dashed": true})
				if why == "":
					for k in [strip.position, Vector2i(strip.end.x - 1, strip.position.y), Vector2i(strip.position.x, strip.end.y - 1), strip.end - Vector2i.ONE]:
						fills.append({"rect": Rect2i(k, Vector2i.ONE), "h": 0.02, "color": Color(Palette.BLUE, 0.55)})
			else:
				outlines.append({"rect": strip, "h": 0.02, "color": Color(Palette.CHALK, 0.35), "dashed": true})
		if why != "":
			hint = why
			hint_col = Palette.YELLOW
		else:
			hint = "Claim %d cells of new land to the %s. Click to stake it (%s)." % [Tuning.CLAIM_DEPTH * (sim.h if edge in ["east", "west"] else sim.w), edge, Defs.words("stick", Tuning.CLAIM_STAKES)]
	if tool == "build" and placing != "" and _hover != null:
		var origin := _placement_origin()
		var size: Vector2i = Defs.TEMPLATES[placing].size
		var err := sim.placement_check(placing, origin, rot)
		var plot = Sim.plot_rect(placing, origin, rot)
		if plot != null:
			outlines.append({"rect": plot, "h": 0.02, "color": Color(Palette.RED if err != "" else Palette.CHALK, 0.6), "dashed": true})
		outlines.append({"rect": Rect2i(origin, size), "h": 0.03, "color": Palette.RED if err != "" else Palette.BLUE, "dashed": true})
		if Defs.TEMPLATES[placing].has("work"):  # the work area it'll start with, which can be repainted (issues #177, #203)
			fills.append_array(_area_fills(sim.work_area_start(placing, origin), _area_color(placing), 0.22))
		if err == "" and placing == "house":
			fills.append({"rect": Rect2i(sim.door_cell(origin, rot), Vector2i.ONE), "h": 0.02, "color": Color(Palette.BLUE, 0.55)})
		if err != "":
			hint = err
			hint_col = Palette.YELLOW
		else:
			var clr := Sim.clearing_text(sim.obstacles_in(Rect2i(origin, size)))
			var turn := keys.first("rotate")
			var tpl_def: Dictionary = Defs.TEMPLATES[placing]
			var name: String = tpl_def.name.to_lower()
			var turning := "the door" if placing == "house" else "its %s plot" % tpl_def.get("plot", "")
			hint = "Place %s." % name + (" %s turns %s." % [turn, turning] if turn != "" else "") + (" Clears %s." % clr if clr != "" else "")
	var sel = selected_entity()
	if sel != null and sel.kind in ["tree", "boulder", "animal", "bush", "crop", "meadow", "route"]:
		outlines.append({"rect": Rect2i(sel.cell, Vector2i.ONE), "h": 0.03, "color": Palette.CHALK, "dashed": false})
	elif sel != null and sel.kind == "site":
		outlines.append({"rect": Rect2i(sel.origin, sel.size), "h": 0.04, "color": Palette.CHALK, "dashed": false})
		if not Sim.work_of(sel).is_empty() and sel.has("area"):  # its painted work area (issues #177, #203)
			fills.append_array(_area_fills(sel.area, _area_color(sel.tpl), 0.3 if tool == "area" else 0.22))
	elif sel != null and sel.kind == "pen":
		outlines.append({"rect": sel.rect, "h": 0.04, "color": Palette.CHALK, "dashed": false})
	if hint == "" and tool in ["chop", "break"] and _hover != null and _drag.is_empty():
		hint = "Drag to mark trees. Boulders are left alone." if tool == "chop" else "Drag to mark boulders. Trees are left alone."
	if hint == "" and tool == "mine" and _hover != null:
		var kinds := mine_kinds(_mods.shift, _mods.alt)
		if kinds.size() == 1:
			hint = "Marking trees only" if kinds[0] == "tree" else "Marking boulders only"
		elif _drag.is_empty():
			hint = "Drag to mark trees and boulders. Shift: trees only. Alt/Option: boulders only."
	if hint == "" and tool == "stock" and _hover != null and _drag.is_empty():
		hint = "Click or drag from a stockpile cell to erase." if sim.zone.has(_hover) else "Drag over open ground to paint a stockpile. Start on a stockpile to erase instead."
	if hint == "" and tool == "area" and _hover != null and _drag.is_empty():
		var site := sim.site(area_site)
		hint = "Drag to paint the ground it works. Start on a painted cell to erase. Cells more than %d from it stay unpainted." % int(Tuning.WORK_REACH) if site.is_empty() or not site.has("area") or not Sim.in_area(site, _hover) else "Click or drag from a painted cell to erase."
	if hint == "" and tool == "keep" and _hover != null and _drag.is_empty():
		hint = "Click or drag over trees and boulders that lumberjacks and stonemasons should leave alone. Click a kept one to unmark it."
	if hint == "" and tool == "hunt" and _hover != null and _drag.is_empty():
		hint = "Click or drag over animals to hunt them. Shift: only the kind you start on."
	if hint == "" and tool == "lead" and _hover != null and _drag.is_empty():
		hint = "Click or drag over animals for the party to lead into a pen with room."
	if hint == "" and tool == "pen" and _hover != null and _drag.is_empty():
		hint = "Click or drag from a pen to take it down." if sim.pen_at(_hover) != null else "Drag out a pen, fences included: %d×%d to %d×%d." % [Tuning.PEN_MIN, Tuning.PEN_MIN, Tuning.PEN_MAX, Tuning.PEN_MAX]
	if hint == "" and tool == "farm" and _hover != null and _drag.is_empty():
		var why := sim.farm_blocked(_hover)
		if sim.farm.has(_hover):
			hint = "Click or drag from a farm plot to erase. Anything growing there is lost."
		elif why != "":
			hint = "Farms go on open grass, not on %s." % why
			hint_col = Palette.YELLOW
		else:
			hint = "Drag over open grass to paint a farm. Start on a farm plot to erase instead."
	if not radial.is_empty():  # issue #176
		var hv: int = radial.hover
		if hv >= 0:
			var w: Dictionary = radial.wedges[hv]
			hint = w.why if not w.ok else "%d: %s" % [hv + 1, w.label]
			hint_col = Palette.YELLOW if not w.ok else Palette.CHALK
		else:
			hint = "Pick an order, or press 1–%d. Click the middle to select it. Esc closes." % radial.wedges.size()
	elif hint == "" and tool == "" and _drag.is_empty():
		var hit = _pick(_mouse, false)
		if hit != null and hit.kind in ["tree", "boulder", "animal"]:
			hint = "Right-click: options." + (" Shift queues %s." % ("a hunt" if hit.kind == "animal" else "it") if selection.get("kind", "") == "res" else "")
	_world.live_outlines = outlines
	_world.live_fills = fills
	var hint_at: Vector2 = _mouse if radial.is_empty() else radial.center + Vector2(-90, RADIAL_OUT - 8)  # below the radial, clear of its wedges
	_hud.show_hint(hint, hint_at, hint_col)
	_update_focus(sel)


## Tells the world view what the player is looking at, so trees in front of it fade and the roof
## of a selected or hovered house is cut away (issue #3).
func _update_focus(sel) -> void:
	var pts: Array = []
	for id in selection.get("ids", []):
		var r := sim.resident(id)
		if not r.is_empty():
			pts.append([Vector3(r.pos.x + 0.5, 0.2, r.pos.y + 0.5), 0])
			pts.append([Vector3(r.pos.x + 0.5, 1.0, r.pos.y + 0.5), 0])
	if _hover != null:
		# The tree under the cursor stays solid, so you can see what you're about to mine.
		var under = _pick(_mouse, false)
		var keep: int = under.id if under != null and under.kind == "tree" else 0
		pts.append([Vector3(_hover.x + 0.5, 0.05, _hover.y + 0.5), keep])
	if tool == "build" and placing != "" and _hover != null:
		_add_rect_points(pts, Rect2i(_placement_origin(), Defs.TEMPLATES[placing].size), 0.1, 0)
	if sel != null:
		if sel.kind == "site":
			_add_rect_points(pts, Rect2i(sel.origin, sel.size), sim.site_height(sel), 0)
		elif sel.kind == "pen":  # issue #139
			_add_rect_points(pts, sel.rect, 0.8, 0)
		else:
			pts.append([Vector3(sel.cell.x + 0.5, 0.5, sel.cell.y + 0.5), sel.id])
	# What's being built, and what's stuck, stay in view without selecting it: the trees in front of them fade (issue #304).
	var watched := 0
	var stuck_sites: Array = sim.stuck.filter(func(x): return not x.waiting and x.focus_kind == "site" and x.map == "village").map(func(x): return x.focus_id)
	for s in sim.sites:
		if watched >= WATCHED_SITES:
			break
		if (not s.done or stuck_sites.has(s.id)) and not (sel != null and sel.kind == "site" and sel.id == s.id):
			_add_rect_points(pts, Rect2i(s.origin, s.size), sim.site_height(s), 0)
			watched += 1
	_world.focus_points = pts
	var roofs: Array = []
	if sel != null and sel.kind == "site" and sel.tpl == "house":
		roofs.append(sel.id)
	for s in sim.sites:
		if s.tpl == "house" and s.stage == 3 and not s.done and not roofs.has(s.id):
			roofs.append(s.id)  # watch the bed go in while its stage is being built
	if _hover != null:
		var h = sim.site_at(_hover)
		if h != null and h.tpl == "house" and not roofs.has(h.id):
			roofs.append(h.id)
	_world.open_roofs = roofs


## The corners and centre of a footprint, so a tree hiding any part of it fades.
static func _add_rect_points(pts: Array, r: Rect2i, h: float, ignore: int) -> void:
	for p in [Vector2(r.position) + Vector2(0.5, 0.5), Vector2(r.end) - Vector2(0.5, 0.5),
			Vector2(r.position.x + 0.5, r.end.y - 0.5), Vector2(r.end.x - 0.5, r.position.y + 0.5),
			(Vector2(r.position) + Vector2(r.end)) / 2.0]:
		pts.append([Vector3(p.x, h, p.y), ignore])


## The kind of animal a Shift-drag with Hunt marks (issue #138): the one nearest where the drag began.
func hunt_species(c: Vector2i) -> String:
	var near = Sim.nearest(sim.sheep.filter(func(x): return x.alive), c)
	return near.species if near != null else ""


## What a Mine drag marks: Shift limits it to trees, Alt (Option on a Mac) to boulders (issue #7).
static func mine_kinds(shift: bool, alt: bool) -> Array:
	if shift and not alt:
		return ["tree"]
	if alt and not shift:
		return ["boulder"]
	return ["tree", "boulder"]


## What the Mine, Chop trees or Break boulders order marks (issue #94).
func order_kinds(shift: bool, alt: bool) -> Array:
	match tool:
		"chop": return ["tree"]
		"break": return ["boulder"]
	return mine_kinds(shift, alt)


func _placement_origin() -> Vector2i:
	var size: Vector2i = Defs.TEMPLATES[placing].size
	return _hover - Vector2i(size.x / 2, size.y / 2)


# ---------------------------------------------------------------- picking

func _ray(screen: Vector2) -> Array:
	return [_cam.project_ray_origin(screen), _cam.project_ray_normal(screen)]


func _pick(screen: Vector2, residents := true):
	var r := _ray(screen)
	return _world.pick(r[0], r[1], residents)


func _cell_at(screen: Vector2):
	var r := _ray(screen)
	return _world.ground_cell(r[0], r[1])


func selected_entity():
	if sim.map_id != view_map:
		return _in_view(selected_entity)
	match selection.get("kind", ""):
		"tree":
			for t in sim.trees:
				if t.id == selection.id and t.alive:
					return t
		"boulder":
			for b in sim.boulders:
				if b.id == selection.id and b.alive:
					return b
		"animal":
			for sh in sim.sheep:
				if sh.id == selection.id and sh.alive:
					return sh
		"bush":
			for b in sim.bushes:
				if b.id == selection.id:
					return b
		"meadow":
			if view_map == "village":
				return {"kind": "meadow", "id": 0, "cell": sim.meadow_sign()}
		"route":
			if view_map == "village":
				return {"kind": "route", "id": 0, "cell": sim.route_sign()}
			if view_map == Road.ID:  # either end's signpost on the road itself (issue #119)
				return {"kind": "route", "id": 0, "cell": Road.VILLAGE_END}
		"crop":
			for c in sim.farm.values():
				if c.id == selection.id:
					return c
		"pen":
			var p := sim.pen(selection.id)
			return null if p.is_empty() else p
		"site":
			var s := sim.site(selection.id)
			return null if s.is_empty() else s
	return null


func _select(hit) -> void:
	_hud.equip_kind = ""
	if hit == null:
		selection = {}
	elif hit.kind == "res":
		selection = {"kind": "res", "ids": [hit.id]}
	else:
		selection = {"kind": hit.kind, "id": hit.id}
		if hit.kind == "site" and Sim.is_station(hit) and hit.done:
			open_craft_menu(hit)
		elif hit.kind == "site" and hit.tpl == "board" and hit.done:
			plan = {}  # a fresh plan each time the board is selected, on the last place chosen or the first (issue #181)
			open_planner()
		elif hit.kind == "meadow":  # the meadow's signpost opens its adventure on the board (issue #136)
			open_adventure(Meadow.ID)


## Opens the Craft panel on a particular bench (selecting a bench does this).
func open_craft_menu(bench: Dictionary) -> void:
	var i := benches().find(bench)
	if i < 0:
		return
	craft_bench_i = i
	craft_menu_open = true
	planner_open = false
	menu_open = ""


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	_in_view(_handle_input.bind(event))


## The map key is taken before the HUD sees it: its default, Tab, would otherwise move keyboard
## focus between buttons once one has been clicked.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and not _menu.visible and keys.action_for(event) == "map":
		next_map()
		get_viewport().set_input_as_handled()


## Runs `f` with the sim on the map in view, then puts it back on the village.
func _in_view(f: Callable):
	sim.use_map(view_map)
	var out = f.call()
	sim.use_map("village")
	return out


func _handle_input(event: InputEvent) -> void:
	if event is InputEventWithModifiers:
		_mods.shift = event.shift_pressed
		_mods.alt = event.alt_pressed
	if _radial_input(event):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_key(event)
	elif event is InputEventMouseMotion:
		_mouse = event.position
		_hover = _cell_at(_mouse)
		if not _drag.is_empty():
			match _drag.kind:
				"pan": _pan_screen(-event.relative)
				"press":
					# A left press on the map becomes a pan once it moves a few pixels.
					if event.position.distance_to(_drag.start) > 6:
						_drag.kind = "pan"
						Input.set_default_cursor_shape(Input.CURSOR_DRAG)
						_pan_screen(_drag.start - event.position)
				"rect":
					if _hover != null:
						var a: Vector2i = _drag.a
						var lo := Vector2i(mini(a.x, _hover.x), mini(a.y, _hover.y))
						var hi := Vector2i(maxi(a.x, _hover.x), maxi(a.y, _hover.y))
						_drag.rect = Rect2i(lo, hi - lo + Vector2i.ONE)
				"box": _drag.cur = _mouse
	elif event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMagnifyGesture:
		zoom(1.0 / event.factor)


func _mouse_button(e: InputEventMouseButton) -> void:
	if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
		zoom(1 / 1.12)
	elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
		zoom(1.12)
	elif e.button_index == MOUSE_BUTTON_MIDDLE:
		_drag = {"kind": "pan"} if e.pressed else {}
		if not e.pressed:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
		_right_click(e)
	elif e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_left_down(e)
		else:
			_left_up(e)


## Right-click on a tree, boulder or animal opens the radial Gather menu (issue #176); Shift +
## right-click skips it and queues the order for the selected residents. Elsewhere it orders them
## to walk there. It never fails silently: placing a building or with a menu open, it cancels; with
## an order tool on and nobody selected it turns the tool off; with nobody selected, or someone
## starving, it says why nothing happened.
func _right_click(e: InputEventMouseButton) -> void:
	var has_residents: bool = selection.get("kind", "") == "res" and not selection.ids.is_empty()
	if menu_open != "" or tool == "build" or tool == "claim":
		set_tool("")
		return
	# Residents aren't order targets, so look past anyone standing in front of the tree or sheep.
	var hit = _pick(e.position, false)
	var cell = _cell_at(e.position)
	if hit != null and hit.kind in ["tree", "boulder", "animal"] and not e.shift_pressed:
		open_radial(hit, e.position, true)  # issue #176: with or without residents; Shift skips it
		return
	if tool != "" and not has_residents:
		set_tool("")
		return
	if not has_residents:
		var key := keys.first("next_res")
		_hud.add_toast({"text": "Select a resident first." + (" %s selects the next one." % key if key != "" else ""), "res_id": 0, "site_id": 0})
		return
	for id in selection.ids:
		var r := sim.resident(id)
		if r.is_empty():
			continue
		if r.away:
			_hud.add_toast({"text": "%s is %s." % [r.name, "on the way with the party"], "res_id": r.id, "site_id": 0})
			continue
		if r.get("hunger", 100.0) <= 0.0:
			_hud.add_toast({"text": "%s is starving and won’t work until fed." % r.name, "res_id": r.id, "site_id": 0})
			continue
		var target = hit if hit != null and hit.kind in ["tree", "boulder", "animal"] else null
		if e.shift_pressed:
			sim.queue_order(r, target, cell)
		else:
			sim.direct_order(r, target, cell)


func _left_down(e: InputEventMouseButton) -> void:
	var c = _cell_at(e.position)
	if tool == "claim":  # stake the strip under the cursor (issue #187)
		var edge := _claim_edge()
		var why := sim.place_claim(edge)
		if why != "":
			_hud.add_toast({"text": why + ".", "res_id": 0, "site_id": 0})
		else:
			var staked: Array = sim.sites.filter(func(st): return st.tpl == "claim_stakes")
			selection = {"kind": "site", "id": staked[0].id}
			set_tool("")
		return
	if tool == "build":
		if placing != "" and c != null:
			var origin := _placement_origin()
			if sim.placement_check(placing, origin, rot) == "":
				var s := sim.place_site(placing, origin, rot)
				selection = {"kind": "site", "id": s.id}
				if not e.shift_pressed:
					set_tool("")
		return
	if tool in OrderMenus.MARK_TOOLS and c != null:
		# A drag that starts on a painted cell erases that zone instead (issues #63, #93).
		var erase: bool = (tool == "stock" and sim.zone.has(c)) or (tool == "farm" and sim.farm.has(c)) or (tool == "pen" and sim.pen_at(c) != null) or (tool == "area" and sim.site(area_site).has("area") and Sim.in_area(sim.site(area_site), c))
		_drag = {"kind": "rect", "a": c, "rect": Rect2i(c, Vector2i.ONE), "start": e.position, "erase": erase}
		return
	# Shift-drag box-selects residents; a plain drag pans the map; a click selects.
	_drag = {"kind": "box" if e.shift_pressed else "press", "start": e.position, "cur": e.position}


func _left_up(e: InputEventMouseButton) -> void:
	var d := _drag
	_drag = {}
	if d.is_empty():
		return
	var small: bool = e.position.distance_to(d.get("start", e.position)) < 6
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	match d.kind:
		"press":
			_select(_pick(e.position))
		"rect":
			if tool == "stock" and d.get("erase", false):
				sim.erase_zone(d.rect)
			elif tool == "stock":
				sim.paint_zone(d.rect)
			elif tool == "farm" and d.get("erase", false):
				sim.clear_farm(d.rect)
			elif tool == "farm":
				sim.paint_farm(d.rect)
			elif tool == "area":
				var site := sim.site(area_site)
				if not site.is_empty():
					sim.paint_work_area(site, d.rect, d.get("erase", false))
			elif tool == "pen" and d.get("erase", false):
				var p = sim.pen_at(d.a)
				if p != null:
					sim.remove_pen(p)
			elif tool == "pen":
				if sim.paint_pen(d.rect) == "" and not e.shift_pressed:
					set_tool("")
			elif tool == "lead":
				var hit = _pick(e.position, false) if small else null
				sim.designate_lead(d.rect, hit if hit != null and hit.kind == "animal" else null)
			elif tool == "keep":  # issue #177
				var hit = _pick(e.position, false) if small else null
				sim.designate_keep(d.rect, hit if hit != null and hit.kind in ["tree", "boulder"] else null)
			elif tool == "hunt":
				var hit = _pick(e.position, false) if small else null
				sim.designate_hunt(d.rect, hit if hit != null and hit.kind == "animal" else null, hunt_species(d.a) if e.shift_pressed else "")
			else:
				var hit = _pick(e.position, false) if small else null
				sim.designate_mine(d.rect, hit if hit != null and hit.kind in ["tree", "boulder"] else null, order_kinds(e.shift_pressed, e.alt_pressed))
		"box":
			if small:
				_select(_pick(e.position))
				return
			var r := Rect2(d.start, Vector2.ZERO).expand(e.position)
			var ids: Array = []
			for res in sim.here():
				if r.has_point(_cam.unproject_position(Vector3(res.pos.x + 0.5, 0.5, res.pos.y + 0.5))):
					ids.append(res.id)
			selection = {"kind": "res", "ids": ids} if not ids.is_empty() else {}


func _key(e: InputEventKey) -> void:
	if e.ctrl_pressed or e.meta_pressed or e.alt_pressed:
		return
	if _menu.visible:
		if _menu.listening != "":
			_menu.key_pressed(e)
		elif e.keycode == KEY_ESCAPE:
			_menu.back()
		else:
			match keys.action_for(e):
				"menu":
					if _menu.view == "main":
						close_menu()
				"controls": _menu.show_view("main" if _menu.view == "keys" else "keys")
				_: return
		get_viewport().set_input_as_handled()
		return
	if menu_open != "" and e.keycode >= KEY_1 and e.keycode <= KEY_9 and not e.shift_pressed:
		# In an open toolbar menu, 1–9 pick its rows (Z then 1 paints a stockpile, issue #93).
		var list: Array = OrderMenus.entries(menu_open, sim)
		var i: int = e.keycode - KEY_1
		if i < list.size():
			pick_order(menu_open, list[i].id)
		get_viewport().set_input_as_handled()
		return
	if _hud.list_open():  # a dropdown or the equip list: 1–9 pick its entries, not the speed (issue #197)
		var li := keys.list_index(e)
		if li >= 0:
			_hud.press_list_key(li)
			get_viewport().set_input_as_handled()
			return
	if not selection.is_empty() and tool == "" and menu_open == "" and placing == "" and e.keycode != KEY_ESCAPE:
		# The selection panel's buttons have keys (issue #197): the same actions as clicking them.
		var pi := keys.panel_index(e)
		if pi >= 0 and _hud.press_panel_key(pi):
			get_viewport().set_input_as_handled()
			return
		_hud.disarm_panel()
	if e.keycode == KEY_ESCAPE:
		if tool != "" or menu_open != "":
			set_tool("")
		elif book_open:
			book_open = false
		elif jobs_board_open:
			jobs_board_open = false
		elif craft_menu_open:
			craft_menu_open = false
		elif planner_open:
			planner_open = false
		elif not selection.is_empty():  # clears the selection, which gives the order keys back (issue #197)
			selection = {}
		else:
			open_menu("main")
		get_viewport().set_input_as_handled()
		return
	match keys.action_for(e):
		"menu": open_menu("main")
		"controls": open_menu("keys")
		"toggle_pause": set_speed(last_speed if speed == 0 else 0)
		"pause": set_speed(0)
		"speed1": set_speed(1)
		"speed2": set_speed(2)
		"speed3": set_speed(3)
		"mine": set_tool("mine")
		"chop": set_tool("chop")
		"break": set_tool("break")
		"keep": set_tool("keep")
		"craft": toggle_craft_menu()
		"jobs": toggle_jobs_board()
		"hunt": set_tool("hunt")
		"lead": set_tool("lead")
		"stock": set_tool("stock")
		"farm": set_tool("farm")
		"pen": set_tool("pen")
		"gather": set_tool("gather")
		"paint": set_tool("paint")
		"build": set_tool("build")
		"bench": start_placing("bench")
		"house": start_placing("house")
		"fireplace": start_placing("fireplace")
		"board": start_placing("board")
		"chopping_block": start_placing("chopping_block")
		"storehouse": start_placing("storehouse")
		"portal": start_placing("portal")
		"enchanting_workshop": start_placing("enchanting_workshop")
		"portal_station": start_placing("portal_station")
		"cache_sensor", "condition", "freight_loader", "dispatcher": start_placing(keys.action_for(e))
		"redstone_overlay": toggle_redstone_overlay()
		"minimap": _hud.toggle_minimap()
		"claim": start_claiming()
		"mason_bench": start_placing("mason_bench")
		"toolsmith_bench", "composter", "lodge", "builder_table": start_placing(keys.action_for(e))
		"rotate":
			if tool == "build":
				rot = (rot + 1) % 4
		"next_res": _next_resident()
		"next_stuck": _next_stuck()
		"map": next_map()
		"zoom_in": zoom(1 / 1.15)
		"zoom_out": zoom(1.15)
		_: return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- menu, saving and loading

func open_menu(view: String) -> void:
	skipping = false
	if not _menu.visible:
		_menu_prev_speed = speed if speed != 0 else last_speed
		speed = 0
		_acc = 0.0
		set_tool("")
	_menu.show_view(view)


## The HUD's Menu button (issue #216): opens the main menu as Esc does, or closes it again.
func toggle_menu() -> void:
	if not _menu.visible:
		open_menu("main")
	elif _menu.view == "main":
		close_menu()
	else:
		_menu.back()


func close_menu() -> void:
	_menu.visible = false
	speed = 1 if _menu.first else _menu_prev_speed
	_menu.first = false


## Quits the game (the menu's Quit, after it confirms).
## Closing the window, by its button or the system's quit, autosaves too.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave()


func quit_game() -> void:
	autosave()
	get_tree().quit()


func restart() -> void:
	autosave()  # the village that's being left stays loadable (issue #295)
	_use_sim(Sim.new_game())
	_cams = {}
	view_map = "village"
	_world.map_id = view_map
	_look_at_first_resident()
	_cam.size = 17.0
	_place_camera()
	selection = {"kind": "res", "ids": [sim.residents[0].id]}
	_menu_prev_speed = 1
	close_menu()


func _use_sim(s: Sim) -> void:
	sim = s
	_autosave_tick = s.tick
	_autosave_sig = _party_sig()
	craft_menu_open = false
	planner_open = false
	plan = {}
	craft_bench_i = 0
	_world.set_sim(s)
	tool = ""
	placing = ""
	menu_open = ""
	selection = {}
	_drag = {}


func _slot_path(n: int) -> String:
	return "%s/slot_%d.save" % [save_dir, n]


## For each slot: null when empty, {error} when it can't be loaded, else {summary, tick, saved_at}.
func read_slots() -> Array:
	var out: Array = []
	for n in range(1, SLOTS + 1):
		if not FileAccess.file_exists(_slot_path(n)):
			out.append(null)
			continue
		var r := SaveFormat.read(_slot_path(n))
		if r.has("error"):
			out.append({"error": r.error})
		else:
			var summary: String = r.data.summary
			if summary == "Founding complete":  # saved before #81: label it with the village's facts
				summary = Goals.village_text(Sim.from_state(r.data.state))
			out.append({"summary": summary, "tick": r.data.tick, "saved_at": r.data.saved_at})
	return out


func _save_data() -> Dictionary:
	return {"summary": Goals.progress_text(sim), "tick": sim.tick,
		"saved_at": int(Time.get_unix_time_from_system()), "state": sim.save_state(),
		"camera": _camera_state(), "speed": _menu_prev_speed}


## Saves to slot `n`. Returns "" on success, else a message for the player.
func save_slot(n: int) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))
	if not SaveFormat.write(_slot_path(n), _save_data()):
		return "Couldn’t save to slot %d. Check that the disk isn’t full, then try again." % n
	return ""


# ---------------------------------------------------------------- autosave (issue #295)

func _autosave_path() -> String:
	return "%s/autosave.save" % save_dir


## The parties' states, so a departure or a return can be told from the rest of the game.
func _party_sig() -> String:
	return str(sim.expeditions.values().map(func(e): return [e.get("state", ""), e.get("leg", "")]))


## Saves the game to its own file, quietly, apart from the five slots. It isn't done for a game younger than
## `AUTOSAVE_MIN_SECS`, so a new game never takes the place of a village's autosave. Returns whether it saved.
func autosave() -> bool:
	if sim == null or sim.tick < int(Tuning.AUTOSAVE_MIN_SECS * Tuning.TPS):
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))
	_autosave_tick = sim.tick
	_autosave_sig = _party_sig()
	return SaveFormat.write(_autosave_path(), _save_data())


## Whether it's time: `AUTOSAVE_SECS` of play since the last one, or a party has set out or come home.
func _autosave_due() -> bool:
	if _menu.visible or speed == 0:
		return false
	return sim.tick - _autosave_tick >= int(Tuning.AUTOSAVE_SECS * Tuning.TPS) or _party_sig() != _autosave_sig


## The autosave's label, like a slot's: null when there isn't one, {error} when it can't be read.
func read_autosave():
	if not FileAccess.file_exists(_autosave_path()):
		return null
	var r := SaveFormat.read(_autosave_path())
	if r.has("error"):
		return {"error": r.error}
	return {"summary": r.data.summary, "tick": r.data.tick, "saved_at": r.data.saved_at}


func load_autosave() -> String:
	return _load_path(_autosave_path(), "The autosave", "The autosave")


## Loads slot `n` and returns to the game. Returns "" on success, else a message for the player.
func load_slot(n: int) -> String:
	return _load_path(_slot_path(n), "Slot %d" % n, "Loaded slot %d." % n)


func _load_path(path: String, what: String, toast: String) -> String:
	var r := SaveFormat.read(path)
	if r.has("error"):
		return "%s couldn’t be loaded. %s" % [what, r.error]
	var data: Dictionary = r.data
	_use_sim(Sim.from_state(data.state))
	var cam: Dictionary = data.get("camera", {})
	_cams = cam.get("maps", {}).duplicate(true)
	view_map = cam.get("map", "village")
	if not sim.maps.has(view_map) or not _cams.has(view_map):
		view_map = "village"
	_world.map_id = view_map
	if _cams.has(view_map):
		_target = _cams[view_map].target
		_cam.size = _cams[view_map].size
	_place_camera()
	_menu_prev_speed = maxi(1, data.get("speed", 1))
	close_menu()
	_hud.add_toast({"text": toast, "res_id": 0, "site_id": 0})
	return ""


# ---------------------------------------------------------------- commands (also called by the HUD)

func set_speed(v: int) -> void:
	if v != 0 and not sim.pending.is_empty():
		return  # a choice is waiting for the player
	skipping = false  # picking a speed ends a skip
	if speed != 0:
		last_speed = speed
	speed = v
	if v == 0:
		_acc = 0.0  # no leftover time may tick the sim after pausing


# ---------------------------------------------------------------- skipping ahead (issue #299)

## Starts or ends a skip: the game runs fast until something needs the player (a choice, a message, a new problem,
## a party setting out or coming home) or `SKIP_MAX_SECS` pass, and then stops at the normal speed.
func set_skip(on: bool) -> void:
	if not on:
		if skipping:
			_end_skip("")
		return
	if _menu.visible or not sim.pending.is_empty():
		return
	if speed == 0:
		set_speed(maxi(1, last_speed))
	skipping = true
	_skip_from = sim.tick
	_skip_sig = _party_sig()
	_skip_problems = _problem_keys()
	_skip_decisions = _decision_keys()


## The problems on the list, not the waiting orders and not the choices: what a skip must not sleep through.
func _problem_keys() -> Dictionary:
	var out := {}
	for s in sim.stuck:
		if not s.hidden and not s.waiting:
			out[s.key] = true
	return out


## The decisions waiting on the player (a freight cart's say). One already waiting when a skip starts doesn't stop it.
func _decision_keys() -> Dictionary:
	var out := {}
	for s in sim.stuck:
		if s.get("decision", "") != "":
			out[s.key] = true
	return out


## Why the skip should stop now, or "".
func _skip_stop_reason() -> String:
	if not sim.pending.is_empty():
		return "a choice is waiting"
	if sim.events.any(func(e): return e.type == "toast"):
		return "there is a message"
	if _party_sig() != _skip_sig:
		return "a party set out or came home"
	for k in _problem_keys():
		if not _skip_problems.has(k):
			return "something got stuck"
	for k in _decision_keys():
		if not _skip_decisions.has(k):
			return "something needs your say"
	if sim.tick - _skip_from >= int(Tuning.SKIP_MAX_SECS * Tuning.TPS):
		return "ten minutes passed"
	return ""


func _end_skip(why: String) -> void:
	skipping = false
	_acc = 0.0
	if why != "":
		var secs := (sim.tick - _skip_from) / Tuning.TPS
		_hud.add_toast({"text": "Skipped ahead %d:%02d: %s." % [secs / 60, secs % 60, why], "res_id": 0, "site_id": 0})


## Finished benches and fireplaces, for the Craft panel.
func benches() -> Array:
	return sim.sites.filter(func(s): return s.done and Sim.is_station(s))


## The bench the Craft panel is showing, or null before any bench is finished.
func craft_bench():
	var list := benches()
	return null if list.is_empty() else list[craft_bench_i % list.size()]


func toggle_craft_menu() -> void:
	if craft_bench() == null:
		craft_menu_open = false
		return
	craft_menu_open = not craft_menu_open
	if craft_menu_open:
		menu_open = ""
		planner_open = false
		if tool == "build":
			tool = ""
			placing = ""


## Shows the i-th station in the Craft panel (its tab, issue #76).
func show_craft_bench(i: int) -> void:
	craft_bench_i = i


## Orders that only make sense in the village: painting stockpiles and farms, and placing buildings.
const VILLAGE_ONLY := ["stock", "farm", "area", "build", "claim", "bench", "house", "fireplace", "board", "chopping_block", "mason_bench", "toolsmith_bench", "composter", "lodge", "builder_table", "storehouse", "portal", "enchanting_workshop", "portal_station", "cache_sensor", "condition", "freight_loader", "dispatcher", "keep"]
## And at the meadow: painting pens (issue #139).
const MEADOW_ONLY := ["pen"]


## Whether an order or menu can be used on a map.
static func tool_fits(t: String, map: String) -> bool:
	if t == "paint":
		return map in ["village", Meadow.ID]
	if t in VILLAGE_ONLY:
		return map == "village"
	if t in MEADOW_ONLY:
		return map == Meadow.ID
	return true


func set_tool(t: String) -> void:
	if not tool_fits(t, view_map):
		return
	if t == "craft":
		toggle_craft_menu()
		return
	if t in ["gather", "paint", "build"]:  # the toolbar menus open and close
		craft_menu_open = false
		menu_open = "" if menu_open == t else t
		if t == "build" and menu_open == "build" and tool != "build":
			tool = ""
			placing = ""
		elif t == "build" and menu_open == "" and tool == "build":
			tool = ""
	elif t == "":
		tool = ""
		placing = ""
		menu_open = ""
	else:
		menu_open = ""
		tool = "" if tool == t else t
		placing = ""
	_drag = {}


## A mason's bench becomes a mineshaft (issue #204).
func upgrade_shaft(site: Dictionary) -> void:
	sim.upgrade_to_shaft(site)


## Paints a workstation's work area (issue #203): drag to add cells, start on a painted cell to erase.
func start_area(site: Dictionary) -> void:
	if tool == "area" and area_site == site.id:
		set_tool("")
		return
	menu_open = ""
	craft_menu_open = false
	placing = ""
	tool = "area"
	area_site = site.id
	_drag = {}


func _area_cells() -> Dictionary:
	var site := sim.site(area_site)
	return site.area if site.has("area") else {}


func _cells_out_of_reach(site: Dictionary, rect: Rect2i) -> int:
	var n := 0
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			if Vector2(Vector2i(x, y)).distance_to(Vector2(site.origin)) > Tuning.WORK_REACH:
				n += 1
	return n


## The work area's colour: green for the lumberjack's, stone for the mason's.
static func _area_color(tpl: String) -> Color:
	return {"chopping_block": Palette.GREEN, "mason_bench": Palette.CHALK}.get(tpl, Palette.CHALK)


## A work area as flat washes, one per row run, so it costs a handful of rects rather than a rect a cell.
static func _area_fills(cells: Dictionary, col: Color, alpha: float) -> Array:
	var rows := {}
	for c in cells:
		if not rows.has(c.y):
			rows[c.y] = []
		rows[c.y].append(c.x)
	var out: Array = []
	for y in rows:
		var xs: Array = rows[y]
		xs.sort()
		var start: int = xs[0]
		var prev: int = start
		for i in range(1, xs.size() + 1):
			if i == xs.size() or xs[i] != prev + 1:
				out.append({"rect": Rect2i(start, y, prev - start + 1, 1), "h": 0.02, "color": Color(col, alpha)})
				if i < xs.size():
					start = xs[i]
			if i < xs.size():
				prev = xs[i]
	return out


## Picks a row in a toolbar menu: switches its order on (or starts placing its building) and closes
## the menu. Unlike the direct keys, picking the order that's already on leaves it on.
func pick_order(menu: String, id: String) -> void:
	if menu == "build":
		if id == "claim":
			start_claiming()
		else:
			start_placing(id)
		return
	menu_open = ""
	craft_menu_open = false
	tool = id
	placing = ""
	_drag = {}


## What the sim's events change in the view, apart from toasts: a claim on the north or west edge moved
## the village's origin (issue #187), so the camera moves with it and stays on the same ground. Called
## every frame, and by the bots, which step the sim themselves.
func handle_view_events(events: Array) -> void:
	for ev in events:
		if ev.type == "map_grew":
			var by := Vector3(ev.shift.x, 0, ev.shift.y)
			if view_map == "village":
				_target += by
				_place_camera()
			elif _cams.has("village"):
				_cams.village.target += by


## The Claim land order (issue #187): the cursor's nearest edge is the strip on offer, and a click
## stakes it.
func start_claiming() -> void:
	if view_map != "village":
		return
	tool = "claim"
	placing = ""
	menu_open = ""
	craft_menu_open = false


## The edge nearest the cursor, found on the ground plane whether or not it's over the map.
func _claim_edge() -> String:
	var r := _ray(_mouse)
	if absf(r[1].y) < 1e-5:
		return "north"
	var p: Vector3 = r[0] + r[1] * (-r[0].y / r[1].y)
	var gap := {"north": p.z, "south": sim.h - p.z, "west": p.x, "east": sim.w - p.x}
	var best := "north"
	for e in gap:
		if gap[e] < gap[best]:
			best = e
	return best


func start_placing(tpl: String) -> void:
	if view_map != "village":
		return
	tool = "build"
	placing = tpl
	menu_open = ""


func zoom(f: float) -> void:
	_cam.size = clampf(_cam.size * f, 6.0, 32.0)


func clear_orders(r: Dictionary) -> void:
	sim.clear_orders(r)


func toggle_hunt(target: Dictionary) -> void:
	_in_view(func(): sim.designate_hunt(Rect2i(target.cell, Vector2i.ONE), target))


## Pins an item to the tally bar, or unpins it (issue #141). At most MAX_PINNED; saved with the keys.
func pin_item(type: String) -> void:
	if keys.pinned.has(type):
		keys.pinned.erase(type)
	elif keys.pinned.size() < Defs.MAX_PINNED:
		keys.pinned.append(type)
	keys.save_file()


func toggle_lead(target: Dictionary) -> void:
	_in_view(func(): sim.designate_lead(Rect2i(target.cell, Vector2i.ONE), target))


func remove_pen(p: Dictionary) -> void:
	_in_view(func(): sim.remove_pen(p))
	selection = {}


func remove_farm_plot(crop: Dictionary) -> void:
	_in_view(func(): sim.clear_farm(Rect2i(crop.cell, Vector2i.ONE)))
	selection = {}


func equip_tool(r: Dictionary, stack: Dictionary) -> void:
	sim.equip_order(r, stack)


func release_kept_tool(r: Dictionary, kind: String) -> void:
	sim.release_kept_tool(r, kind)


## A resident's one job, from the job dropdown (issue #134): one of Defs.JOBS, or "none".
func set_role(r: Dictionary, role: String) -> void:
	sim.set_role(r, role)


func toggle_jobs_board(open = null) -> void:
	var want: bool = (not jobs_board_open) if open == null else open
	if want or jobs_board_open:  # closing leaves the book alone when it's on another page
		open_book("jobs", want)


## Opens the village book on a page ("goals" or a page id), or closes it (issue #198).
func open_book(page := "goals", open := true) -> void:
	book_open = open
	if open:
		book_page = page


func set_keep_meals(f: Dictionary, on: bool) -> void:
	sim.set_keep_meals(f, on)


# ---------------------------------------------------------------- expeditions (issues #105-#107)

## Opens the expedition planner (selecting the board does this), with a fresh plan if there's none.
func open_planner() -> void:
	if sim.expedition_board().is_empty():
		return
	planner_open = true
	craft_menu_open = false
	menu_open = ""
	var busy: bool = not sim.expeditions[plan_slot()].is_empty()
	if busy and adventure != "" and not sim.adventures().any(func(a): return a.id == adventure):
		adventure = ""
	if not busy:
		var known := sim.adventures()
		if not known.any(func(a): return a.id == adventure):
			adventure = known[0].id if not known.is_empty() else ""
	if plan.is_empty() or busy or not plan_matches_adventure():
		plan = sim.new_plan(adventure if adventure != "" else OldMine.ID)


## Whether the plan is for the adventure chosen: the same place, or, for the Nether, any of its places (a gather at the quartz
## site is planned from the landing's row, issue #154).
func plan_matches_adventure() -> bool:
	return plan.dest == adventure or (Sim.realm_of(plan.dest) == "nether" and Sim.realm_of(adventure) == "nether")


## Picks a Nether objective (issue #154), keeping the party chosen. `pick` is one of its destinations, for a scout's route.
func plan_objective(obj: String, pick := {}) -> void:
	var p := sim.nether_plan(obj, pick)
	if p.is_empty():
		return
	p.party = plan.party.duplicate()
	plan = p


## The expedition slot the board is showing (issue #145): the one the chosen adventure belongs to, or, with none
## chosen, the first that has a party.
## Orders an enchantment at the workshop (issue #166); a refusal comes up as a toast.
func order_enchant(ench: String, item: String) -> void:
	var why := sim.order_enchant(ench, item)
	if why != "":
		_hud.add_toast({"text": why, "res_id": 0, "site_id": 0})


func cancel_enchant(i: int) -> void:
	sim.cancel_enchant(i)


func set_device_cfg(id: int, key: String, value) -> void:
	sim.set_device_cfg(id, key, value)


func set_freight_item(id: int, item: String, n: int) -> void:
	sim.set_freight_item(id, item, n)


func cut_wire(id: int) -> void:
	sim.cut_wire(id)


func toggle_redstone_overlay() -> void:
	_world.redstone_overlay = not _world.redstone_overlay


func order_wire(from_id: int, to_id: int) -> void:
	var why := sim.order_wire(from_id, to_id)
	if why != "":
		_hud.add_toast({"text": why, "res_id": 0, "site_id": 0})


func order_freight_cart() -> void:
	var why := sim.order_freight_cart()
	if why != "":
		_hud.add_toast({"text": why, "res_id": 0, "site_id": 0})


func decline_freight() -> void:
	var why := sim.decline_freight()
	if why != "":
		_hud.add_toast({"text": why, "res_id": 0, "site_id": 0})


func approve_freight() -> void:
	var why := sim.approve_freight()
	if why != "":
		_hud.add_toast({"text": why, "res_id": 0, "site_id": 0})


func cancel_freight_approval() -> void:
	sim.cancel_freight_approval()


func plan_slot() -> String:
	if not plan.is_empty() and plan.get("rescue", false):  # a rescue has a slot of its own (issue #158)
		return "rescue"
	if adventure != "":
		return Sim.slot_of_dest(adventure)
	for sl in Sim.SLOTS:
		if not sim.expeditions[sl].is_empty():
			return sl
	return "overworld"


## Opens the expedition board on one adventure (issue #136): its site report and planner. A signpost
## opens its own.
func open_adventure(id: String) -> void:
	if sim.expedition_board().is_empty():
		return
	adventure = id
	open_planner()


## Fills the plan in from the last trip to this place (issue #301), and says what's not the same.
func repeat_last_trip() -> void:
	var r := sim.repeat_plan(plan.dest if not plan.is_empty() else adventure)
	if r.is_empty():
		return
	plan = r.plan
	var text := "Repeating the last trip to the %s." % sim.get_map(plan.dest).name.to_lower()
	if not r.changes.is_empty():
		text += " " + "; ".join(r.changes) + "."
	_hud.add_toast({"text": text, "res_id": 0, "site_id": 0})


func close_planner() -> void:
	planner_open = false


## Adds a resident to the plan's party, or takes them off it.
func plan_toggle(id: int) -> void:
	if plan.party.has(id):
		plan.party.erase(id)
	elif plan.party.size() < Tuning.PARTY_MAX:
		plan.party.append(id)


## Changes one of the plan's numbers by `by`, kept at 0 or more (the target at 1 or more).
func plan_step(key: String, by: int) -> void:
	if key == "target":  # the herd size kept of each kind, when tending the pens
		plan.target.n = maxi(1, plan.target.n + by)
	else:
		plan[key] = maxi(0, plan[key] + by)


## Switches the plan to tending the pens (issue #139), or back to bringing things home.
func plan_target(item: String) -> void:
	if item == "pens":
		plan.target = {"item": "pens", "n": maxi(1, plan.target.n if plan.target.item == "pens" else 2)}
	else:
		_leave_tending()


## Back from tending the pens to the cargo list.
func _leave_tending() -> void:
	if plan.target.item == "pens":
		plan.target = {"item": "wool", "n": 1}
		Sim.sync_target(plan)


## Turns a row of the cargo priority list on or off (issue #185).
func plan_cargo_toggle(i: int) -> void:
	_leave_tending()
	plan.list[i].on = not plan.list[i].on
	Sim.sync_target(plan)


## Moves a row up (-1) or down (+1) the list: higher is brought back first.
func plan_cargo_move(i: int, by: int) -> void:
	var j := i + by
	if j < 0 or j >= plan.list.size():
		return
	_leave_tending()
	var row: Dictionary = plan.list[i]
	plan.list[i] = plan.list[j]
	plan.list[j] = row
	Sim.sync_target(plan)


## Changes how many of a row's item are wanted; 0 is as much as fits.
func plan_cargo_amount(i: int, by: int) -> void:
	_leave_tending()
	plan.list[i].n = maxi(0, plan.list[i].n + by)
	Sim.sync_target(plan)


## Clear the level (issue #188): the party works every block of what the list asks for, then digs to the door and
## goes down by itself, instead of bringing back set amounts. Not for the meadow.
func plan_clear_toggle() -> void:
	if plan.dest == Meadow.ID:
		return
	_leave_tending()
	plan.clear = not plan.get("clear", false)
	Sim.sync_target(plan)


## Which level of the old mine the plan is for (issue #132). Its list is the one that place last used.
func plan_dest(id: String) -> void:
	if Sim.realm_of(id) == "nether":  # the first crossing is a survey (issue #148)
		plan = sim.new_plan(id)
		adventure = id
		return
	var tending: bool = plan.target.item == "pens"
	plan.dest = id
	plan.list = sim.cargo_list_for(id)
	if id == Meadow.ID:
		plan.clear = false
	if not tending or id != Meadow.ID:
		plan.target = {"item": "coal", "n": 1}
		Sim.sync_target(plan)


## The door at the end of the level the party is working (issue #132).
func dig_to_door() -> String:
	return sim.dig_to_door(sim.expedition.get("dest", OldMine.ID))


func go_down() -> String:
	return sim.go_down()


func plan_policy(key: String) -> void:
	plan.policy[key] = not plan.policy[key]


func plan_spend_return() -> void:
	plan.spend_return = not plan.spend_return


## Start packing: the plan becomes the sim's expedition. Returns why it can't, or "".
func confirm_plan() -> String:
	var err := sim.plan_expedition(plan)
	if err == "":
		plan = {}
	return err


func depart() -> String:
	return sim.depart(plan_slot())


## Calls the party home from the site (issue #108).
func call_home() -> String:
	return sim.call_home(Sim.realm_of(view_map) if view_map != "village" else plan_slot())


## Answers the choice the game stopped for (issues #110, #111), and carries on at the speed it had.
func answer(option: String) -> void:
	sim.choose(option)
	if sim.pending.is_empty() and speed == 0:
		set_speed(last_speed if last_speed > 0 else 1)


func cancel_expedition() -> void:
	sim.cancel_expedition(plan_slot())
	adventure = ""
	plan = sim.new_plan()


## The road's work (issues #119, #121): the bridge, the cut and the line. Each returns why it can't, or "".
func plan_bridge() -> String:
	return sim.plan_bridge()


func clear_cut() -> String:
	return sim.clear_cut()


func plan_station(end: String) -> String:
	return sim.plan_station(end)


func plan_line() -> String:
	var why := sim.plan_line()
	if why == "":
		line_preview = false
	return why


func toggle_mine(target: Dictionary) -> void:
	_in_view(func(): sim.designate_mine(Rect2i(target.cell, Vector2i.ONE), target))


## Marks a tree or boulder Keep, or unmarks it (issue #177).
func toggle_keep(target: Dictionary) -> void:
	_in_view(func(): sim.designate_keep(Rect2i(target.cell, Vector2i.ONE), target))


## A workstation's keep-stock target (issue #177).
func set_keep_stock(s: Dictionary, n: int) -> void:
	sim.set_keep_stock(s, n)


func set_make_keep(s: Dictionary, n: int) -> void:
	sim.set_make_keep(s, n)


func set_wheat_keep(n: int) -> void:
	sim.set_wheat_keep(n)


func set_herd_floor(species: String, n: int) -> void:
	sim.set_herd_floor(species, n)


func cancel_site(s: Dictionary) -> void:
	sim.cancel_site(s)
	selection = {}


func queue_craft(s: Dictionary, recipe_id: String, times := 1) -> void:
	for i in times:
		sim.queue_add(s, recipe_id)


func unqueue_craft(s: Dictionary, i: int) -> void:
	sim.queue_remove(s, i)


## Moves the camera to a resident, building or boulder, switching to its map first (issue #101).
## `map` names the map for things that don't carry one (a boulder); residents and buildings do.
func focus_on(kind: String, id: int, map := "") -> void:
	match kind:
		"res": map = sim.resident(id).get("map", map)
		"site": map = sim.site(id).get("map", map)
	if map != "" and map != view_map and sim.maps.has(map):
		switch_map(map)
	_in_view(_focus_here.bind(kind, id))


func _focus_here(kind: String, id: int) -> void:
	var at := Vector3.ZERO
	match kind:
		"res":
			var r := sim.resident(id)
			if r.is_empty():
				return
			selection = {"kind": "res", "ids": [id]}
			at = Vector3(r.pos.x + 0.5, 0, r.pos.y + 0.5)
		"site":
			var s := sim.site(id)
			if s.is_empty():
				return
			selection = {"kind": "site", "id": id}
			at = Vector3(s.origin.x + s.size.x / 2.0, 0, s.origin.y + s.size.y / 2.0)
			if Sim.is_station(s) and s.done:
				open_craft_menu(s)
			elif s.tpl == "board" and s.done:
				open_planner()
		"boulder":
			for b in sim.boulders:
				if b.id == id:
					selection = {"kind": "boulder", "id": id}
					at = Vector3(b.cell.x + 0.5, 0, b.cell.y + 0.5)
		_:
			return
	_target = at
	_place_camera()


func _next_resident() -> void:
	var ids: Array = selection.get("ids", [])
	var cur: int = ids[0] if not ids.is_empty() else -1
	var i := -1
	for k in sim.residents.size():
		if sim.residents[k].id == cur:
			i = k
	focus_on("res", sim.residents[(i + 1) % sim.residents.size()].id)


func _next_stuck() -> void:
	var list := sim.stuck.filter(func(s): return not s.hidden and s.focus_kind != "")
	if list.is_empty():
		_hud.add_toast({"text": "Nothing is stuck.", "res_id": 0, "site_id": 0})
		return
	_stuck_i = (_stuck_i + 1) % list.size()
	focus_on(list[_stuck_i].focus_kind, list[_stuck_i].focus_id, list[_stuck_i].map)


# ---------------------------------------------------------------- maps (issue #101)

## The maps the switcher offers: the village, and each site map once it's known.
func known_maps() -> Array:
	var out: Array = sim.maps.keys().filter(func(id): return sim.maps[id].known)
	var rank := func(id: String) -> float:  # the village, the old mine and its levels in order, then the rest
		if id == "village":
			return 0.0
		if sim.maps[id].level > 0:
			return 1.0 + sim.maps[id].level / 100.0
		if id == Road.ID:  # each road after the place it leads to's neighbour: mine, its road, meadow, its road
			return 2.05
		if id == MeadowRoad.ID:
			return 2.15
		return 2.0 + Sim.ADVENTURES.find(id) / 10.0 if id in Sim.ADVENTURES else 2.0
	out.sort_custom(func(a, b2): return rank.call(a) < rank.call(b2))
	return out


## Shows another map. Each map keeps its own camera position and zoom; a map seen for the first
## time opens on its entrance. The selection clears, since it belongs to the map left behind.
func switch_map(id: String) -> void:
	if id == view_map or not sim.maps.has(id):
		return
	_cams[view_map] = {"target": _target, "size": _cam.size}
	view_map = id
	_world.map_id = id
	if _cams.has(id):
		_target = _cams[id].target
		_cam.size = _cams[id].size
	else:
		var mp := sim.get_map(id)
		var at := Vector2(mp.w / 2.0, mp.h / 2.0) if mp.kind == "village" else Vector2(mp.entrance) + Vector2(mp.w / 3.0, 0)
		_target = Vector3(at.x, 0, at.y)
	_place_camera()
	selection = {}
	_drag = {}
	_hover = null
	if not tool_fits(tool, id):
		set_tool("")  # paint and build orders are for the village, pens for the meadow
	if menu_open != "" and not tool_fits(menu_open, id):
		menu_open = ""


## The next known map after the one in view (Tab).
func next_map() -> void:
	var list := known_maps()
	if list.size() < 2:
		return
	switch_map(list[(list.find(view_map) + 1) % list.size()])


## The camera of every map, for saving.
func _camera_state() -> Dictionary:
	var cams := _cams.duplicate(true)
	cams[view_map] = {"target": _target, "size": _cam.size}
	return {"map": view_map, "maps": cams}



## A cell or area of the original 18×18 opening, in today's map (issue #52 moved it to the middle).
static func at(x: int, y: int) -> Vector2i:
	return Vector2i(x, y) + Tuning.OPENING_OFFSET


static func area(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(Vector2i(x, y) + Tuning.OPENING_OFFSET, Vector2i(w, h))


# ---------------------------------------------------------------- screenshot mode

func _screenshot_menu() -> void:
	var args := OS.get_cmdline_user_args()
	open_menu("keys" if "--keys" in args else ("main" if "--main" in args else "save"))
	for i in 20:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("user://screenshot_menu.png"))
	print("screenshot: menu")
	get_tree().quit()


## The Slice 6 scene (issue #15): a lit portal, the shelter, the portal line, a workshop and the chain's four devices wired and
## built, then one panel or view picked by `--s6-<which>`. Used to look at the new panels without clicking through the game.
func _screenshot_slice6(which: String) -> void:
	var ada: Dictionary = sim.residents[0]
	var near: Vector2i = Sim.rcell(ada)
	var spot := func(tpl: String, from: Vector2i) -> Vector2i:
		for d in range(0, 14):
			for dx in range(-d, d + 1):
				for dy in range(-d, d + 1):
					var o: Vector2i = from + Vector2i(dx, dy)
					if sim.placement_check(tpl, o) == "":
						return o
		return Vector2i(-1, -1)
	var done := func(st: Dictionary) -> Dictionary:
		st.stage = 1
		st.done = true
		return st
	var portal: Dictionary = done.call(sim.place_site("portal", spot.call("portal", near + Vector2i(4, 4))))
	portal.lit = true
	var shelter: Dictionary = sim.on_map(NetherLanding.ID, func(): return sim.place_site("shelter", NetherLanding.SHELTER_AT))
	done.call(shelter)
	shelter.store = {"bread": 3}
	sim.get_map(NetherLanding.ID).known = true
	sim.portal_line.laid = Tuning.PORTAL_LINE_RAILS
	sim.nline().stations.landing = true
	var station: Dictionary = done.call(sim.place_site("portal_station", spot.call("portal_station", portal.origin + Vector2i(0, 3))))
	var ld: Dictionary = done.call(sim.place_site("freight_loader", spot.call("freight_loader", station.plot.position)))
	var sens: Dictionary = done.call(sim.place_site("cache_sensor", spot.call("cache_sensor", station.origin + Vector2i(-4, 4))))
	var cond: Dictionary = done.call(sim.place_site("condition", spot.call("condition", station.origin + Vector2i(0, 5))))
	var disp: Dictionary = done.call(sim.place_site("dispatcher", spot.call("dispatcher", station.origin + Vector2i(3, 2))))
	var ws: Dictionary = done.call(sim.place_site("enchanting_workshop", spot.call("enchanting_workshop", near + Vector2i(-5, 2))))
	ws.known = ["efficiency", "unbreaking"]
	ws.orders = [{"ench": "efficiency", "item": "iron_pick"}]
	sim.drop_items(near + Vector2i(1, 1), "iron_pick", 1)
	var n := 0
	for pr in [[sens, cond], [cond, ld], [ld, disp]]:
		n += 1
		sim.order_wire(pr[0].id, pr[1].id)
		var w = sim.wires[n - 1]
		w.laid = w.cells.size()
	sim.freight = {"state": "home", "pos": 0.0, "load": {"bread": 10, "iron_ingot": 2}, "approved": false, "acc": 0.0, "request": true}
	sim._step_devices()
	sim.compute_stuck()
	var focus: Dictionary = {"workshop": ws, "station": station, "sensor": sens, "loader": ld, "dispatcher": disp, "overlay": cond, "landing": station}[which]
	selection = {"kind": "site", "id": focus.id}
	_target = Vector3(focus.origin.x + 0.5, 0, focus.origin.y + 0.5)
	_cam.size = 9.0
	if which == "overlay":
		_world.redstone_overlay = true
	if which == "landing":
		switch_map(NetherLanding.ID)
		_target = Vector3(NetherLanding.STATION_AT.x + 1.5, 0, NetherLanding.STATION_AT.y + 4.0)
		selection = {}
	_place_camera()
	sim.rev += 1


## `godot --path . -- --screenshot` plays a short scripted opening, saves a frame to
## user://screenshot.png and quits. Used to check the view without clicking through it.
func _screenshot_scene() -> void:
	sim.designate_mine(area(0, 8, 9, 10))
	var bench := sim.place_site("bench", at(8, 10))
	for i in 120 * Tuning.TPS:
		sim.step()
	for r in ["planks", "planks", "sticks", "wood_pick"]:
		sim.queue_add(bench, r)
	sim.paint_zone(area(10, 7, 4, 2))
	for i in 140 * Tuning.TPS:
		sim.step()
	sim.designate_mine(area(9, 0, 9, 18))
	var house := sim.place_site("house", at(11, 0))
	for i in 3:
		sim.queue_add(bench, "planks")
	for i in 210 * Tuning.TPS:
		sim.step()
	sim.events.clear()
	selection = {"kind": "site", "id": house.id}
	if "--tools" in OS.get_cmdline_user_args():
		_hud._drop_pinned = "tools"
	if "--mark-sheep" in OS.get_cmdline_user_args():
		var near = Sim.nearest(sim.sheep.filter(func(x): return x.alive), Sim.rcell(sim.residents[0]))
		if near != null:
			near.des = true
			_target = Vector3(near.pos.x + 0.5, 0, near.pos.y + 0.5)
			_place_camera()
	if "--bed" in OS.get_cmdline_user_args():
		house.store = {"plank": 99, "wool": 3, "log": 4}
		house.stage = 4
		house.done = true
		sim.rev += 1
		selection = {"kind": "site", "id": house.id}
		_target = Vector3(house.origin.x + 2.5, 0, house.origin.y + 2.5)
		_place_camera()
	if "--farm" in OS.get_cmdline_user_args():
		var fa := area(12, 12, 4, 3)
		for d in 10:  # the nearest spot where the whole plot is open grass
			var found := false
			for dx in range(-d, d + 1):
				for dy in range(-d, d + 1):
					var r := Rect2i(fa.position + Vector2i(dx, dy), fa.size)
					var ok := true
					for x in range(r.position.x, r.end.x):
						for y in range(r.position.y, r.end.y):
							ok = ok and sim.farm_blocked(Vector2i(x, y)) == ""
					if ok and not found:
						fa = r
						found = true
			if found:
				break
		sim.paint_farm(fa)
		var i := 0
		for k in sim.farm:  # one plot at each stage, from empty to ripe
			sim.farm[k].grow = [-1.0, 1.0, 50.0, 90.0, Tuning.WHEAT_GROW][i % 5]
			i += 1
		sim.rev += 1
		var crop = sim.farm.get(fa.position + Vector2i(1, 1))
		if crop != null:
			selection = {"kind": "crop", "id": crop.id}
		tool = "farm"
		_target = Vector3(fa.get_center().x, 0, fa.get_center().y)
		_place_camera()
	if "--fireplace" in OS.get_cmdline_user_args():
		for c in [at(12, 9), at(9, 8), at(6, 9), at(13, 5), at(9, 13)]:
			if sim.placement_check("fireplace", c) == "" and sim.walkable(c):
				var f := sim.place_site("fireplace", c)
				f.stage = 1
				f.done = true
				sim.queue_add(f, "bread")
				sim.rev += 1
				_select(f)
				_target = Vector3(c.x + 0.5, 0, c.y + 1.5)
				_place_camera()
				break
	if "--stations" in OS.get_cmdline_user_args():  # the house roofed and every workstation built, for the textures (issue #206)
		house.store = {}
		house.stage = 4
		house.done = true
		var near := at(6, 12)
		for tpl in ["chopping_block", "mason_bench", "toolsmith_bench", "composter", "lodge", "builder_table", "fireplace", "board", "portal"]:
			var spot = null
			for d in 12:
				for dx in range(-d, d + 1):
					for dy in range(-d, d + 1):
						var c := near + Vector2i(dx, dy)
						if spot == null and sim.placement_check(tpl, c) == "" and sim.walkable(c):
							spot = c
			if spot != null:
				var s := sim.place_site(tpl, spot)
				s.stage = Defs.TEMPLATES[tpl].stages.size() - 1
				s.done = true
				if tpl == "portal":
					s.lit = true
		sim.rev += 1
		selection = {}
		_target = Vector3(near.x + 0.5, 0, near.y + 0.5)
		_place_camera()
	if "--portal" in OS.get_cmdline_user_args():  # a lit portal in a cleared spot, for its model and glow (issue #147)
		var near := Sim.rcell(sim.residents[0]) + Vector2i(-3, 6)
		for t in sim.trees:
			if absi(t.cell.x - near.x) <= 5 and absi(t.cell.y - near.y) <= 4:
				t.alive = false
		sim._occ_dirty = true
		var p := sim.place_site("portal", near)
		p.stage = 1
		p.done = true
		p.lit = "--unlit" not in OS.get_cmdline_user_args()
		sim.rev += 1
		selection = {}
		_target = Vector3(near.x + 2.0, 0, near.y + 1.0)
		_cam.size = 9.0
		_place_camera()
	if "--nether" in OS.get_cmdline_user_args():  # the portal landing, seen from the arch, with a landmark surveyed (issue #148)
		var landing := sim.get_map(NetherLanding.ID)
		landing.known = true
		landing.visited = true
		landing.landmarks_seen = [landing.landmarks[0]]
		sim.move_to_map(sim.residents[0], NetherLanding.ID, landing.entrance + Vector2i(3, 0))
		sim.rev += 1
		switch_map(NetherLanding.ID)
		_cam.size = 14.0
	if "--nroute" in OS.get_cmdline_user_args():  # a Nether route, scouted as far as its third segment (issue #153)
		var rm := sim.get_map(NetherRoute.ROUTES.quartz.id)
		rm.known = true
		rm.seen = 3
		sim.get_map(NetherLanding.ID).known = true
		sim.rev += 1
		switch_map(rm.id)
		_target = Vector3(20, 0, 3)
		_cam.size = 12.0
		_place_camera()
	if "--creatures" in OS.get_cmdline_user_args():  # one of each creature on the landing, and a guard facing them (issue #151)
		var landing := sim.get_map(NetherLanding.ID)
		landing.known = true
		landing.visited = true
		var at := landing.entrance + Vector2i(5, 0)
		var k := 0
		for sp in Defs.CREATURES:
			var cr := sim.spawn_creature(NetherLanding.ID, sp, at + Vector2i(k * 2, k % 2 * 2))
			cr.engaged = false
			k += 1
		sim.move_to_map(sim.residents[0], NetherLanding.ID, landing.entrance + Vector2i(2, 0))
		sim.rev += 1
		switch_map(NetherLanding.ID)
		_cam.size = 9.0
	if "--select-bench" in OS.get_cmdline_user_args():
		_select(bench)
	if "--craft" in OS.get_cmdline_user_args():
		craft_menu_open = true
	if "--select-ada" in OS.get_cmdline_user_args():
		selection = {"kind": "res", "ids": [sim.residents[0].id]}
	if "--meadow" in OS.get_cmdline_user_args():  # the meadow signpost selected, before there's a board (issue #136)
		var sign := sim.meadow_sign()
		selection = {"kind": "meadow", "id": 0}
		_target = Vector3(sign.x + 4.0, 0, sign.y + 0.5)
		_place_camera()
	if "--equip" in OS.get_cmdline_user_args():  # spare axes about, and Ada's Equip list open
		var ada: Dictionary = sim.residents[0]
		sim.drop_items(Sim.rcell(ada) + Vector2i(2, 1), "stone_axe", 1)
		sim.drop_items(Sim.rcell(ada) + Vector2i(-1, 2), "wood_axe", 1, 4)
		selection = {"kind": "res", "ids": [ada.id]}
		_hud.equip_kind = "axe"
	if "--erase" in OS.get_cmdline_user_args():  # mid-drag, erasing half the stockpile (issue #63)
		var z := area(10, 7, 4, 2)
		set_tool("stock")
		_drag = {"kind": "rect", "a": z.position, "rect": Rect2i(z.position + Vector2i(2, 0), Vector2i(3, 2)), "start": Vector2.ZERO, "erase": true}
		_target = Vector3(z.get_center().x, 0, z.get_center().y)
		_place_camera()
		selection = {}
	if "--items" in OS.get_cmdline_user_args():  # every common loose item, in stacks of 1 and 16, for the item shapes (issue #206)
		var spots: Array[Vector2i] = []
		var from := Sim.rcell(sim.residents[0])
		for d in 14:  # open grass, nearest to Ada first
			for dx in range(-d, d + 1):
				for dy in range(-d, d + 1):
					var c := from + Vector2i(dx, dy)
					if maxi(absi(dx), absi(dy)) == d and sim.farm_blocked(c) == "" and sim.walkable(c) and not spots.any(func(o): return absi(o.x - c.x) < 2 and absi(o.y - c.y) < 2):
						spots.append(c)
		var k := 0
		for t in ["log", "plank", "cobble", "stick", "wheat", "coal", "iron_ore", "diamond", "sapling", "berries", "bread", "cooked_mutton", "wool", "leather", "chest", "stone_brick"]:
			if k < spots.size():
				sim.drop_items(spots[k], t, 16 if k % 2 == 0 else 3)
			k += 1
		_target = Vector3(Sim.rcell(sim.residents[0]).x + 0.5, 0, Sim.rcell(sim.residents[0]).y + 0.5)
		_cam.size = 9.0
		_place_camera()
	if "--food" in OS.get_cmdline_user_args():  # meals and raw mutton for the tally bar's Food group (issue #73)
		var z: Vector2i = area(10, 7, 4, 2).position
		sim.drop_items(z, "bread", 2)
		sim.drop_items(z + Vector2i(1, 0), "mutton", 3)
		sim.drop_items(Sim.rcell(sim.residents[0]) + Vector2i(1, 1), "cooked_mutton", 1)
	if "--gather" in OS.get_cmdline_user_args():  # the Gather menu open (issue #94)
		selection = {}
		set_tool("gather")
	if "--paint" in OS.get_cmdline_user_args():  # Farm plot on, and the Paint menu open (issue #93)
		selection = {}
		pick_order("paint", "farm")
		menu_open = "paint"
	if "--village" in OS.get_cmdline_user_args():  # Tomas and Mira beside Ada, Tomas selected (issues #77, #79)
		var ada: Dictionary = sim.residents[0]
		for k in 2:
			var who: Array = Sim.TRAVELERS[k]
			var c: Vector2i = sim.nearest_walkable(Sim.rcell(ada) + Vector2i(2 + k * 2, 1 - k))
			sim.add_resident(who[0], who[1], c)
		selection = {"kind": "res", "ids": [sim.residents[1].id]}
		_target = Vector3(ada.pos.x + 2.0, 0, ada.pos.y + 0.5)
		_place_camera()
		_hud.waiting_open = true
		if "--folded" in OS.get_cmdline_user_args():
			sim.compute_stuck()
			_hud.refresh(sim)  # what's stuck now counts as seen, so it stays folded
			_hud.stuck_open = false
	if "--jobs" in OS.get_cmdline_user_args():  # the Village jobs board (issues #78, #134); add --village for more rows
		sim.residents[0].jobs.mine.xp = 30
		for i in range(1, sim.residents.size()):
			sim.set_role(sim.residents[i], ["farm", "cook"][i % 2])
		jobs_board_open = true
		if "--job-menu" in OS.get_cmdline_user_args() and sim.residents.size() > 1:  # with Tomas's job dropdown open
			for i in 5:
				await get_tree().process_frame
			_hud.refresh(sim)
			await get_tree().process_frame
			for n in _hud._board.find_children("*", "Button", true, false):
				if n.get_meta("label", "") == "Job: " + sim.residents[1].name:
					n.pressed.emit()
	if "--board" in OS.get_cmdline_user_args():  # the expedition board and its planner (issues #105-#107); --packing while packing
		for k in 2:  # Tomas and Mira, to choose a party from
			var who: Array = Sim.TRAVELERS[k]
			sim.add_resident(who[0], who[1], sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(2 + k, 1)))
		var b := {}
		for c in [at(12, 9), at(9, 8), at(6, 9), at(13, 5), at(9, 13), at(4, 12)]:
			if sim.placement_check("board", c) == "" and sim.walkable(c):
				b = sim.place_site("board", c)
				break
		b.stage = 1
		b.done = true
		sim._on_site_done(b)
		sim.rev += 1
		_select(b)
		if "--plan" in OS.get_cmdline_user_args():  # past the adventures list, planning for the old mine (issue #136)
			open_adventure(OldMine.ID)
		elif "--plan-nether" in OS.get_cmdline_user_args():  # planning a Nether trip: the portal lit, the objective picker (issues #148, #154)
			var np := sim.place_site("portal", Sim.rcell(sim.residents[0]) + Vector2i(-2, 7))
			np.stage = 1
			np.done = true
			np.lit = true
			sim.get_map(NetherLanding.ID).known = true
			sim.get_map(NetherRoute.ROUTES.quartz.id).surveyed = true
			sim.get_map(NetherRoute.ROUTES.quartz.site).known = true
			open_adventure(NetherLanding.ID)
			plan = sim.nether_plan("scout")
		elif "--plan-meadow" in OS.get_cmdline_user_args():  # planning for the meadow (issue #137)
			sim.get_map(Meadow.ID).visited = true
			open_adventure(Meadow.ID)
		plan.party.append(sim.residents[1].id)
		if "--packing" in OS.get_cmdline_user_args():
			sim.drop_items(area(10, 7, 4, 2).position, "bread", 4)
			sim.drop_items(area(10, 7, 4, 2).position + Vector2i(1, 0), "stone_pick", 1)
			plan.meals = 3
			confirm_plan()
			for i in 12 * Tuning.TPS:
				sim.step()
		if "--road" in OS.get_cmdline_user_args():  # departed: carrying the packs to the signpost (issue #108)
			for i in 60 * Tuning.TPS:
				if sim.depart_blocker() == "":
					break
				sim.step()
			sim.depart()
			for i in int(0.4 * Tuning.TPS):
				sim.step()
			planner_open = false
			selection = {"kind": "route", "id": 0}
			sim.events.clear()
			var sign := sim.route_sign()
			var ada: Dictionary = sim.residents[0]
			_target = Vector3(ada.pos.x + 3.0, 0, ada.pos.y)
			_cam.size = 9.0
			var args := OS.get_cmdline_user_args()
			if "--walking" in args or "--line" in args:  # on the road to the mine, seen from there (issues #118-#121)
				for i in 60 * Tuning.TPS:
					sim.step()
					if ada.map == Road.ID and ada.pos.x > (14.0 if "--walking" in args else 46.0):
						break
				if "--line" in args:  # after the first trip: the bridge built, two segments of the line laid
					for i in 10 * Tuning.TPS:
						sim.step()
					sim.plan_bridge()
					sim.bridge().stage = 1
					sim.bridge().done = true
					if "--ride" in args:  # the whole line, both stations, and the party riding home with its cargo (issues #122-#124)
						for bl in sim.cut_boulders():
							bl.alive = false
						sim.road().occ_dirty = true
						sim.plan_line()
						for k in Road.segment_count():
							sim.track_site(k).stage = 1
							sim.track_site(k).done = true
						for end in ["village", "mine"]:
							sim.plan_station(end)
							sim.station(end).stage = 1
							sim.station(end).done = true
						sim.cart = {"at": "mine", "x": Sim.station_x("mine"), "state": "parked", "load": {}, "riders": [], "acc": 0.0}
						sim.expedition.cart = true
						sim.on_map(OldMine.ID, func(): sim.designate_mine(Rect2i(0, 0, 16, 16)))
						for i in 40 * Tuning.TPS:
							sim.step()
						sim.call_home()
						for i in 60 * Tuning.TPS:
							sim.step()
							if sim.cart.state == "moving" and sim.cart.x < 15.0:
								break
					elif "--preview" in args:
						line_preview = true
					else:
						sim.plan_line()
						for k in 2:
							sim.track_site(k).stage = 1
							sim.track_site(k).done = true
					sim.rev += 1
					sim.compute_stuck()
				switch_map(Road.ID)
				selection = {"kind": "route", "id": 0}
				var at: Vector2 = ada.pos if "--walking" in args or "--ride" in args else Vector2(18, 3)
				_target = Vector3(at.x + 2.0, 0, at.y)
				_cam.size = 10.0 if "--walking" in args else 13.0
				sim.events.clear()
			if "--arrived" in OS.get_cmdline_user_args():  # the party at work in the old mine, seen from there
				if "--door" in OS.get_cmdline_user_args():  # they stay, with pickaxes, until they reach the door
					sim.expedition.policy = {"target": false, "full": false, "low": false}
					for id in sim.expedition.party:
						sim.resident(id).pick = {"type": "stone_pick", "tier": 2, "dur": 25}
				for i in int((sim.route_walk_time() + 30) * Tuning.TPS):
					sim.step()
				if not "--door" in OS.get_cmdline_user_args():
					sim.on_map(OldMine.ID, func(): sim.designate_mine(Rect2i(0, 0, 16, 16)))
				for i in 10 * Tuning.TPS:
					sim.step()
				selection = {}
				switch_map(OldMine.ID)
				_cam.size = 14.0
				if "--find" in OS.get_cmdline_user_args():  # the iron discovery's choice (issue #111)
					sim.on_map(OldMine.ID, sim._check_find.bind(Vector2i(12, 12)))
				if "--hurt" in OS.get_cmdline_user_args():  # a serious injury's choice (issue #110)
					sim.on_map(OldMine.ID, sim.injure.bind(sim.residents[1], 2, "a cave-in"))
				if "--door" in OS.get_cmdline_user_args():  # the door down's choice (issue #132)
					sim.on_map(OldMine.ID, func():
						for bl in sim.boulders:
							bl.des = false)
					sim.dig_to_door(OldMine.ID)
					for i in 200 * Tuning.TPS:
						sim.step()
						if not sim.pending.is_empty():
							break
					_target = Vector3(12.0, 0, 8.5)
				sim.events.clear()
		else:
			_target = Vector3(b.origin.x + 4.5, 0, b.origin.y - 1.5)  # the board left of the planner
		sim.events.clear()
		_place_camera()
	if "--mine" in OS.get_cmdline_user_args():  # Ada at work in the old mine, seen from there (issues #101, #102)
		var mine := sim.get_map(OldMine.ID)
		mine.known = true
		mine.visited = true
		var ada: Dictionary = sim.residents[0]
		if ada.pick == null:
			ada.pick = {"type": "stone_pick", "tier": 2, "dur": 25}
		sim.move_to_map(ada, OldMine.ID, mine.entrance)
		sim.on_map(OldMine.ID, func(): sim.designate_mine(Rect2i(0, 0, mine.w, mine.h)))
		for i in 25 * Tuning.TPS:
			sim.step()
		sim.events.clear()
		switch_map(OldMine.ID)
		_cam.size = 14.0
		_target = Vector3(mine.w / 2.0, 0, mine.h / 2.0)
		_place_camera()
		if "--village-view" in OS.get_cmdline_user_args():  # back home, with the party line showing
			switch_map("village")
	var li := OS.get_cmdline_user_args().find("--level")
	if li >= 0:  # a level of the old mine, by number, to check each pattern family looks its own (issue #132)
		var n := int(OS.get_cmdline_user_args()[li + 1])
		sim.get_map(OldMine.ID).known = true
		for k in range(1, n):
			sim.open_door(MineLevels.level_id(k))
		var lv := sim.get_map(MineLevels.level_id(n))
		lv.visited = true
		var ada: Dictionary = sim.residents[0]
		sim.move_to_map(ada, lv.id, lv.entrance)
		sim.rev += 1
		selection = {}
		switch_map(lv.id)
		_cam.size = 15.0
		_target = Vector3(lv.w / 2.0, 0, lv.h / 2.0)
		_place_camera()
		print("level %d: %s" % [n, lv.pattern])
	if "--meadow-site" in OS.get_cmdline_user_args():  # the meadow, with a few animals marked to hunt (issue #137)
		var mead := sim.get_map(Meadow.ID)
		mead.known = true
		mead.visited = true
		var ada: Dictionary = sim.residents[0]
		sim.move_to_map(ada, Meadow.ID, mead.entrance + Vector2i(-2, 0))
		for sp in ["cow", "pig", "sheep"]:
			for a in mead.sheep:
				if a.species == sp:
					a.des = true
					break
		for i in 3 * Tuning.TPS:
			sim.step()
		sim.events.clear()
		selection = {}
		switch_map(Meadow.ID)
		_cam.size = 16.0
		_target = Vector3(mead.w / 2.0, 0, mead.h / 2.0)
		_place_camera()
	if "--pens" in OS.get_cmdline_user_args():  # the meadow's pens: one built with cows, a fed pair and a calf, one part-built, a cow marked to lead (issue #139)
		var mead := sim.get_map(Meadow.ID)
		mead.known = true
		mead.visited = true
		sim.on_map(Meadow.ID, func():
			sim.paint_pen(Rect2i(16, 9, 5, 5))
			sim.paint_pen(Rect2i(16, 16, 6, 5))
			var built: Dictionary = mead.pens[0]
			for c in Sim.pen_edge(built):
				sim._put_fence(built, c)
			var inside := Sim.pen_inside(built)
			var cows: Array = mead.sheep.filter(func(a): return a.alive and a.species == "cow")
			for i in 2:
				var c := inside.position + Vector2i(i * 2, 0)
				cows[i].cell = c
				cows[i].pos = Vector2(c)
				cows[i].pen = built.id
				cows[i].fed_at = sim.tick
			var calf := sim.add_animal(inside.position + Vector2i(1, 2), "cow")
			calf.pen = built.id
			calf.young = true
			calf.grown_at = sim.tick + 9999
			cows[2].lead = true
			var part: Dictionary = mead.pens[1]
			for c in Sim.pen_edge(part).slice(0, 7):
				sim._put_fence(part, c))
		sim.events.clear()
		switch_map(Meadow.ID)
		_cam.size = 11.0
		_target = Vector3(18.5, 0, 14.0)
		_place_camera()
		selection = {"kind": "pen", "id": mead.pens[0].id}
	if "--armor" in OS.get_cmdline_user_args():  # Ada in a full set of leather armor, selected; the Food dropdown open (issues #140, #141)
		var ada: Dictionary = sim.residents[0]
		for t in sim.trees:  # out in the open, so the armor shows rather than an x-ray through the trees
			t.alive = false
		sim._occ_dirty = true
		sim.rev += 1
		for slot in Defs.ARMOR_SLOTS:
			var t: String = {"head": "leather_cap", "chest": "leather_tunic", "legs": "leather_trousers", "feet": "leather_boots"}[slot]
			ada.armor[slot] = {"type": t, "dur": Tuning.ARMOR_USES - 2}
		sim.drop_items(Sim.rcell(ada) + Vector2i(2, 1), "beef", 2)
		sim.drop_items(Sim.rcell(ada) + Vector2i(2, 2), "cooked_beef", 1)
		selection = {"kind": "res", "ids": [ada.id]}
		_target = Vector3(ada.pos.x + 0.5, 0, ada.pos.y + 0.5)
		_cam.size = 8.0
		_place_camera()
		_hud._drop_pinned = "food"
	for which in ["workshop", "station", "sensor", "loader", "dispatcher", "overlay", "landing"]:  # Slice 6's panels and models, for the hand check (#15)
		if "--s6-" + which in OS.get_cmdline_user_args():
			_screenshot_slice6(which)
	if "--toast" in OS.get_cmdline_user_args():  # a short toast and one long enough to wrap (issue #71)
		_hud.add_toast({"text": "Tomas is now level 2 at Mine.", "res_id": 0, "site_id": 0})
		_hud.add_toast({"text": "A traveler, Mira, has arrived. She claims the new house and needs tools from the bench before she can mine.", "res_id": sim.residents[0].id, "site_id": 0})
		set_speed(0)
	for i in 30:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("user://screenshot.png")
	img.save_png(path)
	print("screenshot: ", path)
	get_tree().quit()


# ---------------------------------------------------------------- the radial Gather menu (issue #176)

const RADIAL_IN := 42.0    ## The radial's centre, in HUD pixels: a click there selects the target.
const RADIAL_OUT := 118.0  ## Its outer edge; a click beyond closes it.


## Opens the radial Gather menu on a tree, boulder or animal, centred at a screen point. `held` while
## the right button that opened it is still down, so a release on a wedge picks it.
func open_radial(target: Dictionary, at: Vector2, held := false) -> void:
	radial = {"target": target, "map": view_map, "center": at, "wedges": radial_wedges(target), "hover": -1, "held": held, "dragged": false}


func close_radial() -> void:
	radial = {}


## The wedges for a target, as [{id, label, mark, ok, why}]: mark it for anyone (Cancel once it's
## marked), order the selected residents now (only with some selected), and mark all nearby (not for
## animals). A "now" that can't happen is greyed, with its reason.
func radial_wedges(t: Dictionary) -> Array:
	var verb: String = {"tree": "Chop", "boulder": "Break", "animal": "Hunt"}[t.kind]
	var mark: String = {"tree": "chop", "boulder": "break", "animal": "hunt"}[t.kind]
	var out: Array = []
	out.append({"id": "cancel", "label": "Cancel", "mark": mark, "ok": true, "why": ""} if t.des else {"id": "mark", "label": verb, "mark": mark, "ok": true, "why": ""})
	var ids: Array = selection.get("ids", []) if selection.get("kind", "") == "res" else []
	if not ids.is_empty():
		var why := _now_blocker(ids, t)
		out.append({"id": "now", "label": verb + " now", "mark": mark, "ok": why == "", "why": "%s now: %s" % [verb, why] if why != "" else ""})
	if t.kind != "animal":
		out.append({"id": "nearby", "label": "Chop all trees nearby" if t.kind == "tree" else "Break all nearby", "mark": mark, "ok": true, "why": ""})
	return out


## Why none of these residents can take the order now, or "" when one can.
func _now_blocker(ids: Array, t: Dictionary) -> String:
	var why := ""
	for id in ids:
		var r := sim.resident(id)
		if r.is_empty():
			continue
		var w := ""
		if r.away or r.map != view_map:
			w = "%s is away" % r.name
		elif r.get("hunger", 100.0) <= 0.0:
			w = "%s is starving" % r.name
		elif t.kind != "animal" and r.get("hurt", 0) > 0:
			w = "%s is hurt" % r.name
		elif t.kind == "boulder" and r.pick == null and sim.tool_items("pick", 0).is_empty():
			w = "%s has no pickaxe" % r.name
		if w == "":
			return ""
		if why == "":
			why = w
	return why


## What the radial's centre says: "Tree · 4 logs".
func radial_title(t: Dictionary) -> String:
	match t.kind:
		"tree":
			return "Tree · %s" % Defs.words("log", t.get("logs", 4))
		"boulder":
			if t.has("ore"):
				return "%s · %s" % [Defs.ORES[t.ore].name, Defs.words(Defs.ORES[t.ore].item, 1)]
			return "Boulder · %s" % Defs.words("cobble", Tuning.BOULDER_COBBLE)
		"animal":
			return "%s · %s" % [Defs.SPECIES[t.species].name, Defs.drops_text(t.species)]
	return ""


## Which wedge a screen point is over, or -1 (the centre is -2, outside the ring -3).
func radial_at(p: Vector2) -> int:
	var d: Vector2 = p - radial.center
	if d.length() < RADIAL_IN:
		return -2
	if d.length() > RADIAL_OUT:
		return -3
	var n: int = radial.wedges.size()
	var span := TAU / n
	var a := fposmod(d.angle() + PI / 2 + span / 2, TAU)  # wedge 0 is centred straight up
	return mini(int(a / span), n - 1)


## Picks a wedge: a greyed one does nothing but say why.
func pick_radial(i: int) -> void:
	if radial.is_empty() or i < 0 or i >= radial.wedges.size():
		return
	var w: Dictionary = radial.wedges[i]
	if not w.ok:
		_hud.add_toast({"text": w.why + ".", "res_id": 0, "site_id": 0})
		return
	var t: Dictionary = radial.target
	var map: String = radial.map
	close_radial()
	sim.use_map(map)
	match w.id:
		"mark", "cancel":
			if t.kind == "animal":
				sim.designate_hunt(Rect2i(t.cell, Vector2i.ONE), t)
			else:
				sim.designate_mine(Rect2i(t.cell, Vector2i.ONE), t, [t.kind])
		"nearby":
			var n := Tuning.RADIAL_NEARBY
			sim.designate_mine(Rect2i(t.cell - Vector2i(n, n), Vector2i(n * 2 + 1, n * 2 + 1)), null, [t.kind])
		"now":
			for id in selection.get("ids", []):
				var r := sim.resident(id)
				if not r.is_empty() and _now_blocker([id], t) == "":
					sim.direct_order(r, t, t.cell)
	sim.use_map("village")


## Input while the radial is open; true when it took the event.
func _radial_input(event: InputEvent) -> bool:
	if radial.is_empty():
		return false
	if event is InputEventMouseMotion:
		var at := radial_at(event.position)
		radial.hover = at if at >= 0 else -1
		if radial.held and at >= 0:
			radial.dragged = true
		return true
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var at := radial_at(event.position)
		if event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			if radial.held and radial.dragged and at >= 0:  # press, drag to a wedge, release
				pick_radial(at)
			elif not radial.is_empty():
				radial.held = false
			return true
		if not event.pressed:
			return true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var hit = _pick(event.position, false)
			close_radial()
			if hit != null and hit.kind in ["tree", "boulder", "animal"] and not event.shift_pressed:
				open_radial(hit, event.position, true)
				return true
			return at != -3  # a right-click on empty ground just closes it
		if at >= 0:
			pick_radial(at)
		elif at == -2:
			var t: Dictionary = radial.target
			close_radial()
			_select(t)
		else:
			close_radial()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_radial()
			return true
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			pick_radial(event.keycode - KEY_1)
			return true
	return false
