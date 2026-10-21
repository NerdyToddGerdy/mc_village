class_name Game
extends Node3D
## Hosts the sim at a fixed tick rate, owns the camera and selection, and turns input into sim
## commands. Views never change the sim directly; they call the methods here.

const ISO_DIR := Vector3(1, 1, 1)      ## True isometric: camera looks down (-1, -1, -1).
const ELEVATION_SIN := 0.57735         ## sin(35.26°), for converting screen drags to ground moves.

var sim: Sim
var speed := 1
var last_speed := 1
var tool := ""                          ## "", "mine", "hunt", "stock", "farm" or "build"
var placing := ""                       ## Template being placed while tool == "build".
var rot := 0
var build_menu_open := false
var craft_menu_open := false            ## The Craft panel above the toolbar (issue #57).
var craft_bench_i := 0                  ## Which finished bench the Craft panel shows.
var selection := {}                     ## {} | {kind:"res", ids:[...]} | {kind:"tree"/"boulder"/"site", id}

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

var save_dir := "user://saves"  ## Tests point this elsewhere so they never touch real saves.
const SLOTS := 5


func _ready() -> void:
	keys = KeyBindings.new(keys_path)
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
	_target.x = clampf(_target.x, -2, sim.w + 2)
	_target.z = clampf(_target.z, -2, sim.h + 2)
	_cam.position = _target + ISO_DIR.normalized() * 60.0
	_cam.look_at(_target, Vector3.UP)


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	_pan_with_keys(delta)
	_acc += minf(delta, 0.1) * speed
	var n := 0
	while _acc >= Tuning.DT and n < 30:
		_world.remember_positions()
		sim.step()
		_acc -= Tuning.DT
		n += 1
	# How far the game is into the next tick, for drawing residents between ticks (issue #4).
	# Paused, they're drawn exactly where they are.
	_world.tick_fraction = 1.0 if speed == 0 else clampf(_acc / Tuning.DT, 0.0, 1.0)
	for ev in sim.events:
		if ev.type == "toast":
			_hud.add_toast(ev)
	sim.events.clear()
	_update_live_overlays()
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
		if _drag.get("erase", false):  # erasing stockpile cells: a red outline, and a red fill on each cell that goes
			outlines.append({"rect": _drag.rect, "h": 0.03, "color": Palette.RED, "dashed": true})
			for x in range(_drag.rect.position.x, _drag.rect.end.x):
				for y in range(_drag.rect.position.y, _drag.rect.end.y):
					if sim.zone.has(Vector2i(x, y)):
						fills.append({"rect": Rect2i(x, y, 1, 1), "h": 0.02, "color": Color(Palette.RED, 0.45)})
			hint = "Release to erase these stockpile cells. Anything on them stays and is hauled to the rest."
			hint_col = Palette.RED
		else:
			outlines.append({"rect": _drag.rect, "h": 0.03, "color": {"stock": Palette.GREEN, "farm": Palette.WHEAT}.get(tool, Palette.RED), "dashed": true})
	elif tool in ["mine", "stock", "hunt", "farm"] and _hover != null:
		outlines.append({"rect": Rect2i(_hover, Vector2i.ONE), "h": 0.03, "color": Palette.CHALK, "dashed": false})
	if tool == "build" and placing != "" and _hover != null:
		var origin := _placement_origin()
		var size: Vector2i = Defs.TEMPLATES[placing].size
		var err := sim.placement_check(placing, origin, rot)
		var plot = Sim.plot_rect(placing, origin, rot)
		if plot != null:
			outlines.append({"rect": plot, "h": 0.02, "color": Color(Palette.RED if err != "" else Palette.CHALK, 0.6), "dashed": true})
		outlines.append({"rect": Rect2i(origin, size), "h": 0.03, "color": Palette.RED if err != "" else Palette.BLUE, "dashed": true})
		if err == "" and placing == "house":
			fills.append({"rect": Rect2i(sim.door_cell(origin, rot), Vector2i.ONE), "h": 0.02, "color": Color(Palette.BLUE, 0.55)})
		if err != "":
			hint = err
			hint_col = Palette.YELLOW
		else:
			var clr := Sim.clearing_text(sim.obstacles_in(Rect2i(origin, size)))
			var turn := keys.first("rotate")
			var names := {"house": "house", "bench": "crafting bench", "fireplace": "fireplace"}
			var turns := {"house": "the door", "bench": "its workshop plot", "fireplace": "its kitchen plot"}
			hint = "Place %s." % names[placing] + (" %s turns %s." % [turn, turns[placing]] if turn != "" else "") + (" Clears %s." % clr if clr != "" else "")
	var sel = selected_entity()
	if sel != null and sel.kind in ["tree", "boulder", "sheep", "bush", "crop", "meadow"]:
		outlines.append({"rect": Rect2i(sel.cell, Vector2i.ONE), "h": 0.03, "color": Palette.CHALK, "dashed": false})
	elif sel != null and sel.kind == "site":
		outlines.append({"rect": Rect2i(sel.origin, sel.size), "h": 0.04, "color": Palette.CHALK, "dashed": false})
	if hint == "" and tool == "mine" and _hover != null:
		var kinds := mine_kinds(_mods.shift, _mods.alt)
		if kinds.size() == 1:
			hint = "Marking trees only" if kinds[0] == "tree" else "Marking boulders only"
		elif _drag.is_empty():
			hint = "Drag to mark trees and boulders. Shift: trees only. Alt/Option: boulders only."
	if hint == "" and tool == "stock" and _hover != null and _drag.is_empty():
		hint = "Click or drag from a stockpile cell to erase." if sim.zone.has(_hover) else "Drag over open ground to paint a stockpile. Start on a stockpile to erase instead."
	if hint == "" and tool == "hunt" and _hover != null and _drag.is_empty():
		hint = "Click or drag over sheep to hunt them."
	if hint == "" and tool == "farm" and _hover != null and _drag.is_empty():
		var why := sim.farm_blocked(_hover)
		if sim.farm.has(_hover):
			hint = "Already a farm plot."
		elif why != "":
			hint = "Farms go on open grass, not on %s." % why
			hint_col = Palette.YELLOW
		else:
			hint = "Drag over open grass to paint a farm."
	if hint == "" and tool == "" and _drag.is_empty() and selection.get("kind", "") == "res":
		var hit = _pick(_mouse, false)
		if hit != null and hit.kind in ["tree", "boulder"]:
			hint = "Right-click: Mine. Shift queues it."
		elif hit != null and hit.kind == "sheep":
			hint = "Right-click: Hunt. Shift queues it."
	_world.live_outlines = outlines
	_world.live_fills = fills
	_hud.show_hint(hint, _mouse, hint_col)
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
		else:
			pts.append([Vector3(sel.cell.x + 0.5, 0.5, sel.cell.y + 0.5), sel.id])
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


## What a Mine drag marks: Shift limits it to trees, Alt (Option on a Mac) to boulders (issue #7).
static func mine_kinds(shift: bool, alt: bool) -> Array:
	if shift and not alt:
		return ["tree"]
	if alt and not shift:
		return ["boulder"]
	return ["tree", "boulder"]


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
	match selection.get("kind", ""):
		"tree":
			for t in sim.trees:
				if t.id == selection.id and t.alive:
					return t
		"boulder":
			for b in sim.boulders:
				if b.id == selection.id and b.alive:
					return b
		"sheep":
			for sh in sim.sheep:
				if sh.id == selection.id and sh.alive:
					return sh
		"bush":
			for b in sim.bushes:
				if b.id == selection.id:
					return b
		"meadow":
			return {"kind": "meadow", "id": 0, "cell": sim.meadow_sign()}
		"crop":
			for c in sim.farm.values():
				if c.id == selection.id:
					return c
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


## Opens the Craft panel on a particular bench (selecting a bench does this).
func open_craft_menu(bench: Dictionary) -> void:
	var i := benches().find(bench)
	if i < 0:
		return
	craft_bench_i = i
	craft_menu_open = true
	build_menu_open = false


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventWithModifiers:
		_mods.shift = event.shift_pressed
		_mods.alt = event.alt_pressed
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


## Right-click orders the selected residents. It never fails silently: placing a building, it
## cancels the placement; with Mine, Hunt or Stockpile on, it still gives the order and leaves the
## tool on; with nobody selected, or someone starving, it says why nothing happened.
func _right_click(e: InputEventMouseButton) -> void:
	var has_residents: bool = selection.get("kind", "") == "res" and not selection.ids.is_empty()
	if build_menu_open or tool == "build" or (tool != "" and not has_residents):
		set_tool("")
		return
	if not has_residents:
		var key := keys.first("next_res")
		_hud.add_toast({"text": "Select a resident first." + (" %s selects the next one." % key if key != "" else ""), "res_id": 0, "site_id": 0})
		return
	# Residents aren't order targets, so look past anyone standing in front of the tree or sheep.
	var hit = _pick(e.position, false)
	var cell = _cell_at(e.position)
	for id in selection.ids:
		var r := sim.resident(id)
		if r.is_empty():
			continue
		if r.away:
			_hud.add_toast({"text": "%s is away at the meadow." % r.name, "res_id": r.id, "site_id": 0})
			continue
		if r.get("hunger", 100.0) <= 0.0:
			_hud.add_toast({"text": "%s is starving and won’t work until fed." % r.name, "res_id": r.id, "site_id": 0})
			continue
		var target = hit if hit != null and hit.kind in ["tree", "boulder", "sheep"] else null
		if e.shift_pressed:
			sim.queue_order(r, target, cell)
		else:
			sim.direct_order(r, target, cell)


func _left_down(e: InputEventMouseButton) -> void:
	var c = _cell_at(e.position)
	if tool == "build":
		if placing != "" and c != null:
			var origin := _placement_origin()
			if sim.placement_check(placing, origin, rot) == "":
				var s := sim.place_site(placing, origin, rot)
				selection = {"kind": "site", "id": s.id}
				if not e.shift_pressed:
					set_tool("")
		return
	if tool in ["mine", "stock", "hunt", "farm"] and c != null:
		_drag = {"kind": "rect", "a": c, "rect": Rect2i(c, Vector2i.ONE), "start": e.position, "erase": tool == "stock" and sim.zone.has(c)}
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
			elif tool == "farm":
				sim.paint_farm(d.rect)
			elif tool == "hunt":
				var hit = _pick(e.position, false) if small else null
				sim.designate_hunt(d.rect, hit if hit != null and hit.kind == "sheep" else null)
			else:
				var hit = _pick(e.position, false) if small else null
				sim.designate_mine(d.rect, hit if hit != null and hit.kind in ["tree", "boulder"] else null, mine_kinds(e.shift_pressed, e.alt_pressed))
		"box":
			if small:
				_select(_pick(e.position))
				return
			var r := Rect2(d.start, Vector2.ZERO).expand(e.position)
			var ids: Array = []
			for res in sim.residents:
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
	if e.keycode == KEY_ESCAPE:
		if tool != "" or build_menu_open:
			set_tool("")
		elif craft_menu_open:
			craft_menu_open = false
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
		"craft": toggle_craft_menu()
		"hunt": set_tool("hunt")
		"stock": set_tool("stock")
		"farm": set_tool("farm")
		"build": set_tool("build")
		"bench": start_placing("bench")
		"house": start_placing("house")
		"fireplace": start_placing("fireplace")
		"rotate":
			if tool == "build":
				rot = (rot + 1) % 4
		"next_res": _next_resident()
		"next_stuck": _next_stuck()
		"zoom_in": zoom(1 / 1.15)
		"zoom_out": zoom(1.15)
		_: return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- menu, saving and loading

func open_menu(view: String) -> void:
	if not _menu.visible:
		_menu_prev_speed = speed if speed != 0 else last_speed
		speed = 0
		_acc = 0.0
		set_tool("")
	_menu.show_view(view)


func close_menu() -> void:
	_menu.visible = false
	speed = 1 if _menu.first else _menu_prev_speed
	_menu.first = false


## Quits the game (the menu's Quit, after it confirms).
func quit_game() -> void:
	get_tree().quit()


func restart() -> void:
	_use_sim(Sim.new_game())
	_look_at_first_resident()
	_cam.size = 17.0
	_place_camera()
	selection = {"kind": "res", "ids": [sim.residents[0].id]}
	_menu_prev_speed = 1
	close_menu()


func _use_sim(s: Sim) -> void:
	sim = s
	craft_menu_open = false
	craft_bench_i = 0
	_world.set_sim(s)
	tool = ""
	placing = ""
	build_menu_open = false
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
			out.append({"summary": r.data.summary, "tick": r.data.tick, "saved_at": r.data.saved_at})
	return out


## Saves to slot `n`. Returns "" on success, else a message for the player.
func save_slot(n: int) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))
	var data := {"summary": Goals.progress_text(sim), "tick": sim.tick,
		"saved_at": int(Time.get_unix_time_from_system()), "state": sim.save_state(),
		"camera": {"target": _target, "size": _cam.size}, "speed": _menu_prev_speed}
	if not SaveFormat.write(_slot_path(n), data):
		return "Couldn’t save to slot %d. Check that the disk isn’t full, then try again." % n
	return ""


## Loads slot `n` and returns to the game. Returns "" on success, else a message for the player.
func load_slot(n: int) -> String:
	var r := SaveFormat.read(_slot_path(n))
	if r.has("error"):
		return "Slot %d couldn’t be loaded. %s" % [n, r.error]
	var data: Dictionary = r.data
	_use_sim(Sim.from_state(data.state))
	_target = data.camera.target
	_cam.size = data.camera.size
	_place_camera()
	_menu_prev_speed = maxi(1, data.get("speed", 1))
	close_menu()
	_hud.add_toast({"text": "Loaded slot %d." % n, "res_id": 0, "site_id": 0})
	return ""


# ---------------------------------------------------------------- commands (also called by the HUD)

func set_speed(v: int) -> void:
	if speed != 0:
		last_speed = speed
	speed = v
	if v == 0:
		_acc = 0.0  # no leftover time may tick the sim after pausing


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
		build_menu_open = false
		if tool == "build":
			tool = ""
			placing = ""


func next_craft_bench() -> void:
	craft_bench_i += 1


func set_tool(t: String) -> void:
	if t == "craft":
		toggle_craft_menu()
		return
	if t == "build":
		craft_menu_open = false
		build_menu_open = not build_menu_open
		if build_menu_open and tool != "build":
			tool = ""
			placing = ""
		elif not build_menu_open and tool == "build":
			tool = ""
	elif t == "":
		tool = ""
		placing = ""
		build_menu_open = false
	else:
		build_menu_open = false
		tool = "" if tool == t else t
		placing = ""
	_drag = {}


func start_placing(tpl: String) -> void:
	tool = "build"
	placing = tpl
	build_menu_open = false


func zoom(f: float) -> void:
	_cam.size = clampf(_cam.size * f, 6.0, 32.0)


func clear_orders(r: Dictionary) -> void:
	sim.clear_orders(r)


func toggle_hunt(target: Dictionary) -> void:
	sim.designate_hunt(Rect2i(target.cell, Vector2i.ONE), target)


func remove_farm_plot(crop: Dictionary) -> void:
	sim.clear_farm(Rect2i(crop.cell, Vector2i.ONE))
	selection = {}


func send_to_meadow(ids: Array) -> void:
	for id in ids:
		var r := sim.resident(id)
		if not r.is_empty():
			sim.send_to_meadow(r)


func equip_tool(r: Dictionary, stack: Dictionary) -> void:
	sim.equip_order(r, stack)


func release_kept_tool(r: Dictionary, kind: String) -> void:
	sim.release_kept_tool(r, kind)


func toggle_job(r: Dictionary, job: String) -> void:
	sim.set_job_on(r, job, not r.jobs[job].on)


## Priority 1 → 2 → 3 → 1.
func cycle_job_priority(r: Dictionary, job: String) -> void:
	sim.set_job_priority(r, job, r.jobs[job].pri % 3 + 1)


func set_keep_meals(f: Dictionary, on: bool) -> void:
	sim.set_keep_meals(f, on)


func toggle_mine(target: Dictionary) -> void:
	sim.designate_mine(Rect2i(target.cell, Vector2i.ONE), target)


func cancel_site(s: Dictionary) -> void:
	sim.cancel_site(s)
	selection = {}


func queue_craft(s: Dictionary, recipe_id: String, times := 1) -> void:
	for i in times:
		sim.queue_add(s, recipe_id)


func unqueue_craft(s: Dictionary, i: int) -> void:
	sim.queue_remove(s, i)


func focus_on(kind: String, id: int) -> void:
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
	focus_on(list[_stuck_i].focus_kind, list[_stuck_i].focus_id)



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
		_hud._tools_pinned = true
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
	if "--select-bench" in OS.get_cmdline_user_args():
		_select(bench)
	if "--craft" in OS.get_cmdline_user_args():
		craft_menu_open = true
	if "--select-ada" in OS.get_cmdline_user_args():
		selection = {"kind": "res", "ids": [sim.residents[0].id]}
	if "--meadow" in OS.get_cmdline_user_args():  # the signpost selected, with Ada away on a trip
		var sign := sim.meadow_sign()
		var ada: Dictionary = sim.residents[0]
		sim.fail_job(ada)
		ada.away = true
		ada.back_at = sim.tick + 50 * Tuning.TPS
		sim.meadow_sheep = 6
		sim.meadow_regrow = 100.0
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
	if "--food" in OS.get_cmdline_user_args():  # meals and raw mutton for the tally bar's Food group (issue #73)
		var z: Vector2i = area(10, 7, 4, 2).position
		sim.drop_items(z, "bread", 2)
		sim.drop_items(z + Vector2i(1, 0), "mutton", 3)
		sim.drop_items(Sim.rcell(sim.residents[0]) + Vector2i(1, 1), "cooked_mutton", 1)
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
