class_name Game
extends Node3D
## Hosts the sim at a fixed tick rate, owns the camera and selection, and turns input into sim
## commands. Views never change the sim directly; they call the methods here.

const ISO_DIR := Vector3(1, 1, 1)      ## True isometric: camera looks down (-1, -1, -1).
const ELEVATION_SIN := 0.57735         ## sin(35.26°), for converting screen drags to ground moves.

var sim: Sim
var speed := 1
var last_speed := 1
var tool := ""                          ## "", "mine", "stock" or "build"
var placing := ""                       ## Template being placed while tool == "build".
var rot := 0
var build_menu_open := false
var selection := {}                     ## {} | {kind:"res", ids:[...]} | {kind:"tree"/"boulder"/"site", id}

var _acc := 0.0
var _hud_t := 0.0
var _cam := Camera3D.new()
var _target := Vector3(9, 0, 9)
var _world := WorldView.new()
var _hud := Hud.new()
var _drag := {}
var _hover = null                       ## Ground cell under the mouse, or null.
var _mouse := Vector2.ZERO
var _stuck_i := -1
var _menu := GameMenu.new()
var _menu_prev_speed := 1

var save_dir := "user://saves"  ## Tests point this elsewhere so they never touch real saves.
const SLOTS := 5


func _ready() -> void:
	sim = Sim.new_game()
	_setup_scene()
	_world.sim = sim
	add_child(_world)
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
		sim.step()
		_acc -= Tuning.DT
		n += 1
	for ev in sim.events:
		if ev.type == "toast":
			_hud.add_toast(ev)
	sim.events.clear()
	_update_live_overlays()
	_world.selected_ids = selection.get("ids", [])
	_hud_t += delta
	if _hud_t > 0.15:
		_hud_t = 0.0
		_hud.refresh(sim)


func _pan_with_keys(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
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
		outlines.append({"rect": _drag.rect, "h": 0.03, "color": Palette.GREEN if tool == "stock" else Palette.RED, "dashed": true})
	elif tool in ["mine", "stock"] and _hover != null:
		outlines.append({"rect": Rect2i(_hover, Vector2i.ONE), "h": 0.03, "color": Palette.CHALK, "dashed": false})
	if tool == "build" and placing != "" and _hover != null:
		var origin := _placement_origin()
		var size: Vector2i = Defs.TEMPLATES[placing].size
		var err := sim.placement_check(placing, origin)
		outlines.append({"rect": Rect2i(origin, size), "h": 0.03, "color": Palette.RED if err != "" else Palette.BLUE, "dashed": true})
		if err == "" and placing == "house":
			fills.append({"rect": Rect2i(sim.door_cell(origin, rot), Vector2i.ONE), "h": 0.02, "color": Color(Palette.BLUE, 0.55)})
		if err != "":
			hint = err
			hint_col = Palette.YELLOW
		else:
			var clr := Sim.clearing_text(sim.obstacles_in(Rect2i(origin, size)))
			hint = ("Place house. R turns the door." if placing == "house" else "Place crafting bench.") + (" Clears %s." % clr if clr != "" else "")
	var sel = selected_entity()
	if sel != null and sel.kind in ["tree", "boulder"]:
		outlines.append({"rect": Rect2i(sel.cell, Vector2i.ONE), "h": 0.03, "color": Palette.CHALK, "dashed": false})
	elif sel != null and sel.kind == "site":
		outlines.append({"rect": Rect2i(sel.origin, sel.size), "h": 0.04, "color": Palette.CHALK, "dashed": false})
	if hint == "" and tool == "" and _drag.is_empty() and selection.get("kind", "") == "res":
		var hit = _pick(_mouse)
		if hit != null and hit.kind in ["tree", "boulder"]:
			hint = "Right-click: Mine. Shift queues it."
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
		"site":
			var s := sim.site(selection.id)
			return null if s.is_empty() else s
	return null


func _select(hit) -> void:
	if hit == null:
		selection = {}
	elif hit.kind == "res":
		selection = {"kind": "res", "ids": [hit.id]}
	else:
		selection = {"kind": hit.kind, "id": hit.id}


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
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
		if tool != "" or build_menu_open:
			set_tool("")
			return
		if selection.get("kind", "") != "res":
			return
		var hit = _pick(e.position)
		var cell = _cell_at(e.position)
		for id in selection.ids:
			var r := sim.resident(id)
			if not r.is_empty():
				var target = hit if hit != null and hit.kind in ["tree", "boulder"] else null
				if e.shift_pressed:
					sim.queue_order(r, target, cell)
				else:
					sim.direct_order(r, target, cell)
	elif e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_left_down(e)
		else:
			_left_up(e)


func _left_down(e: InputEventMouseButton) -> void:
	var c = _cell_at(e.position)
	if tool == "build":
		if placing != "" and c != null:
			var origin := _placement_origin()
			if sim.placement_check(placing, origin) == "":
				var s := sim.place_site(placing, origin, rot)
				selection = {"kind": "site", "id": s.id}
				if not e.shift_pressed:
					set_tool("")
		return
	if tool in ["mine", "stock"] and c != null:
		_drag = {"kind": "rect", "a": c, "rect": Rect2i(c, Vector2i.ONE), "start": e.position}
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
			if tool == "stock":
				sim.paint_zone(d.rect)
			else:
				var hit = _pick(e.position, false) if small else null
				sim.designate_mine(d.rect, hit if hit != null and hit.kind in ["tree", "boulder"] else null)
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
		match e.keycode:
			KEY_ESCAPE: _menu.back()
			KEY_M:
				if _menu.view == "main":
					close_menu()
			KEY_SLASH, KEY_QUESTION: _menu.show_view("main" if _menu.view == "keys" else "keys")
			_: return
		get_viewport().set_input_as_handled()
		return
	match e.keycode:
		KEY_ESCAPE:
			if tool != "" or build_menu_open:
				set_tool("")
			else:
				open_menu("main")
		KEY_M: open_menu("main")
		KEY_SLASH, KEY_QUESTION:
			if e.shift_pressed or e.keycode == KEY_QUESTION:
				open_menu("keys")
		KEY_SPACE: set_speed(last_speed if speed == 0 else 0)
		KEY_QUOTELEFT, KEY_ASCIITILDE: set_speed(0)
		KEY_1: set_speed(1)
		KEY_2: set_speed(2)
		KEY_3: set_speed(3)
		KEY_X: set_tool("mine")
		KEY_Z: set_tool("stock")
		KEY_B: set_tool("build")
		KEY_T: start_placing("bench")
		KEY_H: start_placing("house")
		KEY_R:
			if tool == "build":
				rot = (rot + 1) % 4
		KEY_F: _next_resident()
		KEY_N: _next_stuck()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: zoom(1 / 1.15)
		KEY_MINUS, KEY_KP_SUBTRACT: zoom(1.15)
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


func restart() -> void:
	_use_sim(Sim.new_game())
	_target = Vector3(9, 0, 9)
	_cam.size = 17.0
	_place_camera()
	selection = {"kind": "res", "ids": [sim.residents[0].id]}
	_menu_prev_speed = 1
	close_menu()


func _use_sim(s: Sim) -> void:
	sim = s
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


func set_tool(t: String) -> void:
	if t == "build":
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


# ---------------------------------------------------------------- screenshot mode

func _screenshot_menu() -> void:
	open_menu("save")
	for i in 20:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("user://screenshot_menu.png"))
	print("screenshot: menu")
	get_tree().quit()


## `godot --path . -- --screenshot` plays a short scripted opening, saves a frame to
## user://screenshot.png and quits. Used to check the view without clicking through it.
func _screenshot_scene() -> void:
	sim.designate_mine(Rect2i(0, 8, 9, 10))
	var bench := sim.place_site("bench", Vector2i(8, 10))
	for i in 120 * Tuning.TPS:
		sim.step()
	for r in ["planks", "planks", "sticks", "wood_pick"]:
		sim.queue_add(bench, r)
	sim.paint_zone(Rect2i(10, 7, 4, 2))
	for i in 140 * Tuning.TPS:
		sim.step()
	sim.designate_mine(Rect2i(9, 0, 9, 18))
	var house := sim.place_site("house", Vector2i(11, 0))
	for i in 3:
		sim.queue_add(bench, "planks")
	for i in 210 * Tuning.TPS:
		sim.step()
	sim.events.clear()
	selection = {"kind": "site", "id": house.id}
	if "--tools" in OS.get_cmdline_user_args():
		_hud._tools_pinned = true
	if "--select-ada" in OS.get_cmdline_user_args():
		selection = {"kind": "res", "ids": [sim.residents[0].id]}
	for i in 30:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("user://screenshot.png")
	img.save_png(path)
	print("screenshot: ", path)
	get_tree().quit()
