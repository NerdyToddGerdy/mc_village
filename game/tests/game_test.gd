extends SceneTree
## Runs the real game scene headlessly to check the menu, saving and loading. Uses its own save
## folder, so real saves are never touched. Run from game/:
##   godot --headless --path . -s res://tests/game_test.gd

var _failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL ", what)
	else:
		print("ok   ", what)


func _mouse(game: Game, kind: String, pos: Vector2, shift := false) -> void:
	var e: InputEvent
	if kind == "move":
		e = InputEventMouseMotion.new()
		e.relative = pos - game._mouse
	else:
		e = InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = kind == "down"
		e.shift_pressed = shift
	e.position = pos
	game._unhandled_input(e)


func _test_drag(game: Game) -> void:
	game.close_menu() if game._menu.visible else null
	game.set_tool("")
	var start := Vector2(1100, 650)  # empty ground near the map's front corner
	game.selection = {}
	var before: Vector3 = game._target
	_mouse(game, "move", start)
	_mouse(game, "down", start)
	_mouse(game, "move", start + Vector2(-60, -40))
	_mouse(game, "move", start + Vector2(-160, -90))
	_mouse(game, "up", start + Vector2(-160, -90))
	check(game._target.distance_to(before) > 1.0, "left-drag on the map pans the camera")
	check(game.selection.is_empty(), "panning doesn't select anything")
	var ada: Dictionary = game.sim.residents[0]
	var ada_screen: Vector2 = game._cam.unproject_position(Vector3(ada.pos.x + 0.5, 0.5, ada.pos.y + 0.5))
	var moved: Vector3 = game._target
	_mouse(game, "move", ada_screen)
	_mouse(game, "down", ada_screen)
	_mouse(game, "up", ada_screen)
	check(game.selection.get("ids", []) == [ada.id], "a click without dragging selects")
	check(game._target == moved, "a click doesn't pan")
	game.selection = {}
	var a := ada_screen - Vector2(40, 40)
	_mouse(game, "move", a)
	_mouse(game, "down", a, true)
	_mouse(game, "move", ada_screen + Vector2(40, 40))
	_mouse(game, "up", ada_screen + Vector2(40, 40), true)
	check(game.selection.get("ids", []) == [ada.id], "shift-drag box-selects residents")
	check(game._target == moved, "shift-drag doesn't pan")
	game.set_tool("mine")
	var t: Dictionary = game.sim.trees.filter(func(x): return x.alive)[0]
	t.des = false
	var ts: Vector2 = game._cam.unproject_position(Vector3(t.cell.x + 0.5, 0.0, t.cell.y + 0.5))
	_mouse(game, "move", ts)
	_mouse(game, "down", ts)
	_mouse(game, "move", ts + Vector2(30, 20))
	_mouse(game, "up", ts + Vector2(30, 20))
	check(t.des and game._target == moved, "with Mine active, dragging marks instead of panning")
	game.set_tool("")


func _test_fading(game: Game) -> void:
	var sim := game.sim
	var world: WorldView = game._world
	game._hover = null
	game.selection = {}
	await process_frame
	await process_frame
	var candidates := sim.trees.filter(func(t): return t.alive and sim.walkable(t.cell - Vector2i(2, 2)) and sim.site_at(t.cell - Vector2i(2, 2)) == null)
	check(not candidates.is_empty(), "a standing tree with open ground behind it")
	if candidates.is_empty():
		return
	var tree: Dictionary = candidates[0]
	check(not world.faded_trees.has(tree.id), "trees are solid when nothing is focused")
	# Something directly behind the tree, from the camera's point of view, two cells further back.
	var bench := sim.place_site("bench", tree.cell - Vector2i(2, 2))
	game.selection = {"kind": "site", "id": bench.id}
	await process_frame
	await process_frame
	check(world.faded_trees.has(tree.id), "selecting a bench behind a tree fades that tree")
	check(world.faded_trees.size() <= 2, "only trees in front of it fade (%d faded)" % world.faded_trees.size())
	game.selection = {}
	await process_frame
	await process_frame
	check(not world.faded_trees.has(tree.id), "the tree turns solid again when nothing behind it is focused")
	sim.cancel_site(bench)
	var house := sim.place_site("house", at(11, 0))
	house.stage = 4
	house.done = true
	sim.rev += 1
	await process_frame
	var roof_boxes: int = world._roofs.multimesh.instance_count
	check(roof_boxes > 0, "a finished house has a roof")
	game.selection = {"kind": "site", "id": house.id}
	await process_frame
	await process_frame
	check(world.open_roofs.has(house.id) and world._roofs.multimesh.instance_count == 0, "selecting the house cuts its roof away")
	game.selection = {}
	await process_frame
	await process_frame
	check(world._roofs.multimesh.instance_count == roof_boxes, "deselecting puts the roof back")
	sim.cancel_site(house)


func _test_smooth_movement(game: Game) -> void:
	var sim := game.sim
	var world: WorldView = game._world
	var ada: Dictionary = sim.residents[0]
	sim.fail_job(ada)
	var c := Sim.rcell(ada)
	var goal := c + Vector2i(4, 0) if sim.walkable(c + Vector2i(4, 0)) else c - Vector2i(4, 0)
	sim.direct_order(ada, null, goal)
	game.set_speed(1)
	game._acc = 0.0
	game._process(Tuning.DT * 3.0)   # a few whole ticks to get her walking
	game._process(Tuning.DT * 0.5)   # then half a tick
	var drawn := world.drawn_pos(ada)
	var prev: Vector2 = world._prev_pos[ada.id]
	check(prev != ada.pos, "Ada is walking")
	check(drawn.is_equal_approx(prev.lerp(ada.pos, world.tick_fraction)) and world.tick_fraction > 0.3 and world.tick_fraction < 0.7,
		"halfway between ticks she's drawn halfway between positions (fraction %.2f)" % world.tick_fraction)
	var lifts: Array = []
	for i in 20:
		game._process(0.033)
		world._process(0.033)
		lifts.append((world._people[ada.id].get_node("Body") as Node3D).position.y)
	check(lifts.max() > 0.05 and lifts.max() <= WorldView.HOP_HEIGHT + 0.001, "she hops while walking (highest %.3f)" % lifts.max())
	check(lifts.min() < 0.03, "and comes back down between hops (lowest %.3f)" % lifts.min())
	check(world._people[ada.id].get_node("Ring").position.y < 0.05, "her selection ring stays on the ground")
	game.set_speed(0)
	game._process(0.016)
	check(world.drawn_pos(ada) == ada.pos, "paused, she's drawn exactly where she is")
	for i in 10:
		game._process(0.1)
		world._process(0.1)
	check(is_zero_approx((world._people[ada.id].get_node("Body") as Node3D).position.y), "standing still, she settles back to the ground")
	world._prev_pos[ada.id] = ada.pos + Vector2(5, 0)
	game.set_speed(1)
	check(world.drawn_pos(ada) == ada.pos, "a jump of more than a cell snaps instead of gliding")
	game.set_speed(1)


func _key(game: Game, code: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	game._unhandled_input(e)


## Issue #8: keys can be rebound on the Controls page, with conflict warnings and a reset.
func _test_rebinding(game: Game) -> void:
	var menu: GameMenu = game._menu
	game.set_tool("")
	game.open_menu("keys")
	menu._listen("mine")
	_key(game, KEY_Q)
	check(game.keys.keys.mine == [KEY_Q], "Mine rebound to Q on the Controls page")
	check(KeyBindings.new(game.keys_path).keys.mine == [KEY_Q], "the new key is saved to the settings file")
	game.close_menu()
	await process_frame
	_key(game, KEY_X)
	check(game.tool == "", "X no longer picks Mine")
	_key(game, KEY_Q)
	check(game.tool == "mine", "Q picks Mine")
	game._hud.refresh(game.sim)
	check(game._hud._tool_btns.mine.text == "Mine  Q", "the toolbar badge shows the new key")
	game.set_tool("")
	game.open_menu("keys")
	menu._listen("stock")
	_key(game, KEY_Q)
	check(not menu._confirm.is_empty() and "Mine trees and boulders" in menu._confirm.text, "taking Mine's key asks first")
	check(game.keys.keys.stock == [KEY_Z], "nothing changes until you confirm")
	menu._do_confirmed()
	check(game.keys.keys.stock == [KEY_Q] and game.keys.keys.mine.is_empty(), "confirming moves Q to Stockpile and leaves Mine without a key")
	menu._listen("mine")
	_key(game, KEY_W)
	check(not menu._confirm.is_empty() and "Pan up" in menu._confirm.text, "using W warns that it pans the camera")
	menu.back()
	menu._listen("speed1")
	_key(game, KEY_ESCAPE)
	check(menu.listening == "" and game.keys.keys.speed1 == [KEY_1], "Esc cancels waiting for a key")
	menu._reset_keys()
	check(game.keys.keys.mine == [KEY_X] and game.keys.keys.stock == [KEY_Z], "Reset to defaults restores every key")
	check(KeyBindings.new(game.keys_path).keys.mine == [KEY_X], "the reset is saved too")
	game.close_menu()
	_key(game, KEY_SLASH, true)
	check(menu.visible and menu.view == "keys", "? (Shift + /) still opens Controls")
	game.close_menu()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.keys_path))


## Issue #57: a Craft button in the toolbar opens the bench panel once a bench is finished.
func _test_craft_menu(game: Game) -> void:
	game.restart()
	var hud: Hud = game._hud
	hud.refresh(game.sim)
	await process_frame
	check(not hud._tool_btns.craft.visible, "no Craft button before there's a bench")
	_key(game, KEY_C)
	check(not game.craft_menu_open, "C does nothing without a bench")
	var bench := game.sim.place_site("bench", Sim.rcell(game.sim.residents[0]) + Vector2i(2, 0))
	bench.stage = 1
	bench.done = true
	game.sim.rev += 1
	hud.refresh(game.sim)
	await process_frame
	check(hud._tool_btns.craft.visible, "the Craft button appears once a bench is finished")
	_key(game, KEY_C)
	hud.refresh(game.sim)
	await process_frame
	check(game.craft_menu_open and hud._craft_panel.visible, "C opens the craft panel above the toolbar")
	var queue_btn: Button = null
	for n in _walk(hud._craft_box):
		if n is Button and n.text == "Queue":
			queue_btn = n
			break
	check(queue_btn != null, "the panel lists recipes with Queue buttons")
	if queue_btn != null:
		queue_btn.pressed.emit()
		check(bench.queue.size() == 1, "Queue in the craft panel queues a craft at the bench")
	_key(game, KEY_ESCAPE)
	check(not game.craft_menu_open and not game._menu.visible, "Esc closes the craft panel first")
	# Selecting the bench opens the Craft panel; the recipes appear only there, not on the left.
	game._select(bench)
	hud.refresh(game.sim)
	await process_frame
	check(game.craft_menu_open, "selecting the bench opens the craft panel")
	var left_queue := _walk(hud._sel).filter(func(n): return n is Button and n.text.begins_with("Queue"))
	var right_queue := _walk(hud._craft_box).filter(func(n): return n is Button and n.text.begins_with("Queue"))
	check(left_queue.is_empty() and right_queue.size() == 2 * Defs.recipes_at("bench").size(), "the recipe list is only on the right (%d left, %d right)" % [left_queue.size(), right_queue.size()])
	check(_walk(hud._sel).any(func(n): return n is Label and n.text == "Crafting bench"), "the left panel still names the bench and its status")
	_key(game, KEY_ESCAPE)


func _right(game: Game, pos: Vector2, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	e.shift_pressed = shift
	e.position = pos
	game._unhandled_input(e)


## A right-click either gives the order or says why it didn't.
func _test_right_click_never_silent(game: Game) -> void:
	game.restart()
	var sim := game.sim
	var ada: Dictionary = sim.residents[0]
	var tree: Dictionary = {}
	var at := Vector2.ZERO
	for t in sim.trees:
		var p: Vector2 = game._cam.unproject_position(Vector3(t.cell.x + 0.5, 1.5, t.cell.y + 0.5))
		if Rect2(Vector2(200, 150), Vector2(880, 420)).has_point(p) and is_same(game._pick(p, false), t):
			tree = t
			at = p
			break
	check(not tree.is_empty(), "a tree in view to right-click")
	if tree.is_empty():
		return
	# Mine tool on, Ada selected: the order still goes through, and the tool stays on.
	game.selection = {"kind": "res", "ids": [ada.id]}
	game.set_tool("mine")
	_right(game, at)
	check(ada.direct != null and is_same(ada.direct.target, tree), "with Mine on, right-click still orders Ada to mine the tree")
	check(game.tool == "mine", "and the Mine tool stays on")
	game.set_tool("")
	# Something else selected: nothing silent, a message instead.
	sim.fail_job(ada)
	ada.direct = null
	game.selection = {"kind": "tree", "id": tree.id}
	var toasts := game._hud._toast_list.size()
	_right(game, at)
	check(ada.direct == null and game._hud._toast_list.size() == toasts + 1, "with no resident selected, right-click says to select one")
	# Placing a building: right-click cancels the placement, as before.
	game.selection = {"kind": "res", "ids": [ada.id]}
	game.start_placing("house")
	_right(game, at)
	check(game.tool == "" and ada.direct == null, "while placing a building, right-click cancels the placement")
	# Starving: says so instead of ignoring the order.
	ada.hunger = 0.0
	toasts = game._hud._toast_list.size()
	_right(game, at)
	check(ada.direct == null and game._hud._toast_list.size() == toasts + 1, "a starving resident's order explains why it won't happen")
	ada.hunger = 100.0


## P picks the Farm tool, dragging paints plots, and a plot can be selected and removed (issue #45).
func _test_farm_tool(game: Game) -> void:
	game.restart()
	var sim := game.sim
	var hud: Hud = game._hud
	var start := Sim.rcell(sim.residents[0])
	var rect := Rect2i()
	for d in range(2, 10):
		for c in [start + Vector2i(d, 0), start + Vector2i(0, d), start - Vector2i(d, 0), start - Vector2i(0, d)]:
			var r := Rect2i(c, Vector2i(2, 2))
			if [r.position, r.position + Vector2i(1, 0), r.position + Vector2i(0, 1), r.end - Vector2i.ONE].all(func(x): return sim.farm_blocked(x) == ""):
				rect = r
				break
		if rect.size != Vector2i.ZERO:
			break
	check(rect.size != Vector2i.ZERO, "open grass near Ada for a farm")
	_key(game, KEY_P)
	check(game.tool == "farm", "P picks the Farm tool")
	hud.refresh(sim)
	check(hud._tool_btns.farm.button_pressed, "and the Farm button shows it's on")
	var a: Vector2 = game._cam.unproject_position(Vector3(rect.position.x + 0.5, 0.0, rect.position.y + 0.5))
	var b: Vector2 = game._cam.unproject_position(Vector3(rect.end.x - 0.5, 0.0, rect.end.y - 0.5))
	_mouse(game, "move", a)
	_mouse(game, "down", a)
	_mouse(game, "move", b)
	_mouse(game, "up", b)
	check(sim.farm.size() == 4, "dragging paints a 2×2 farm (%d plots)" % sim.farm.size())
	_key(game, KEY_ESCAPE)
	check(game.tool == "", "Esc puts the Farm tool away")
	var crop: Dictionary = sim.farm[rect.position]
	crop.grow = Tuning.WHEAT_GROW * 0.5
	game._select(game._pick(a))
	check(game.selection.get("kind", "") == "crop", "clicking a plot selects it")
	hud.refresh(sim)
	await process_frame
	check(_walk(hud._sel).any(func(n): return n is Label and n.text.begins_with("Wheat growing")), "its panel shows the wheat growing")
	var remove: Array = _walk(hud._sel).filter(func(n): return n is Button and n.text == "Remove this plot")
	check(remove.size() == 1, "with a button to remove it")
	if remove.size() == 1:
		remove[0].pressed.emit()
	check(sim.farm.size() == 3 and not sim.farm.has(rect.position), "removing takes away just that plot")


## K places a fireplace with its kitchen plot shown; selecting it opens its own recipes and the
## standing order (issue #46).
func _test_fireplace(game: Game) -> void:
	game.restart()
	var sim := game.sim
	var hud: Hud = game._hud
	_key(game, KEY_K)
	check(game.tool == "build" and game.placing == "fireplace", "K picks the fireplace")
	var ada_cell := Sim.rcell(sim.residents[0])
	var spot := Vector2i(-1, -1)
	for d in range(2, 10):
		for c in [ada_cell + Vector2i(d, 0), ada_cell + Vector2i(0, d), ada_cell - Vector2i(d, 0), ada_cell - Vector2i(0, d)]:
			if sim.placement_check("fireplace", c) == "" and sim.walkable(c):
				spot = c
				break
		if spot.x >= 0:
			break
	var p: Vector2 = game._cam.unproject_position(Vector3(spot.x + 0.5, 0.0, spot.y + 0.5))
	_mouse(game, "move", p)
	game._update_live_overlays()
	check(game._world.live_outlines.any(func(o): return o.rect == Sim.plot_rect("fireplace", spot, game.rot)), "placing shows the kitchen plot it reserves")
	check(game._hud._hint.text.begins_with("Place fireplace."), "with a hint: \"%s\"" % game._hud._hint.text)
	_mouse(game, "down", p)
	var f = sim.site_at(spot)
	check(f != null and f.tpl == "fireplace" and f.plot != null, "clicking places the fireplace with its plot")
	if f == null:
		return
	f.stage = 1
	f.done = true
	sim.rev += 1
	game._select(f)
	hud.refresh(sim)
	await process_frame
	check(game.craft_menu_open, "selecting the fireplace opens its menu")
	var rows := _walk(hud._craft_box).filter(func(n): return n is Button and n.text == "Queue")
	check(rows.size() == 2, "it lists its two recipes, bread and cooked mutton (%d)" % rows.size())
	var keep: Array = _walk(hud._craft_box).filter(func(n): return n is Button and n.text.begins_with("Keep 6 meals"))
	check(keep.size() == 1 and keep[0].text.ends_with("on"), "the standing order shows, on by default")
	if keep.size() == 1:
		keep[0].pressed.emit()
	check(not f.keep_meals, "clicking it turns the standing order off")
	_key(game, KEY_ESCAPE)


## The resident panel's Jobs grid switches jobs and cycles priorities (issue #47).
func _test_jobs_grid(game: Game) -> void:
	game.restart()
	var sim := game.sim
	var hud: Hud = game._hud
	var ada: Dictionary = sim.residents[0]
	game.selection = {"kind": "res", "ids": [ada.id]}
	hud.refresh(sim)
	await process_frame
	var haul: Array = _walk(hud._sel).filter(func(n): return n is Button and n.text == "Haul")
	check(haul.size() == 1 and haul[0].button_pressed, "the Jobs grid shows Haul, switched on")
	if haul.size() == 1:
		haul[0].pressed.emit()
	check(not ada.jobs.haul.on, "clicking Haul switches it off")
	hud.refresh(sim)
	await process_frame
	var buttons: Array = _walk(hud._sel).filter(func(n): return n is Button)
	var mine_i := buttons.find(buttons.filter(func(b): return b.text == "Mine")[0])
	var pri: Button = buttons[mine_i + 1]
	check(pri.text == "2", "Mine shows priority 2")
	pri.pressed.emit()
	check(ada.jobs.mine.pri == 3, "clicking the number cycles it to 3")
	game.cycle_job_priority(ada, "mine")
	check(ada.jobs.mine.pri == 1, "and round to 1")
	ada.jobs.farm.xp = 30
	hud.refresh(sim)
	await process_frame
	var levels: Array = _walk(hud._sel).filter(func(n): return n is Label and n.text.begins_with("Lv "))
	check(levels.size() == 8, "each job shows its level (%d)" % levels.size())
	check(levels.any(func(l): return l.text == "Lv 3"), "a level-3 farmer shows Lv 3")


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for ch in n.get_children():
		out.append_array(_walk(ch))
	return out


func _initialize() -> void:
	var game: Game = load("res://scenes/main.tscn").instantiate()
	game.keys_path = "user://test_settings/game_test_keys.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.keys_path))
	root.add_child(game)
	await process_frame
	game.save_dir = "user://test_saves"
	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	var menu: GameMenu = game._menu
	check(menu.visible and menu.first and game.speed == 0, "menu opens at launch, paused, with Play")
	game.close_menu()
	check(not menu.visible and game.speed == 1, "Play closes the menu and runs at 1×")
	game.sim.designate_mine(area(0, 0, 10, 18))
	game.sim.place_site("bench", at(8, 10))
	for i in 60 * Tuning.TPS:
		game.sim.step()
	game.set_speed(3)
	game.open_menu("main")
	check(game.speed == 0, "opening the menu pauses")
	check(game.read_slots().all(func(s): return s == null), "all 5 slots start empty")
	check(game.save_slot(2) == "", "saving to slot 2 works")
	var saved_tick := game.sim.tick
	var slots := game.read_slots()
	check(slots[1] != null and slots[1].tick == saved_tick and slots[1].summary.begins_with("Next:"), "slot 2 shows a summary and time")
	game.close_menu()
	check(game.speed == 3, "closing the menu restores the previous speed")
	for i in 30 * Tuning.TPS:
		game.sim.step()
	var felled_later: int = game.sim.stats.felled
	game.open_menu("load")
	check(game.load_slot(2) == "", "loading slot 2 works")
	check(game.sim.tick == saved_tick, "the loaded game is back at the saved moment")
	check(game.sim.stats.felled <= felled_later, "progress after the save is gone")
	check(not menu.visible and game.speed == 3, "loading returns to the game at the saved speed")
	for i in 30 * Tuning.TPS:
		game.sim.step()
	check(game.sim.tick > saved_tick, "the loaded game keeps running")
	check(game.load_slot(4) != "", "an empty slot can't be loaded")
	var f := FileAccess.open(game._slot_path(4), FileAccess.WRITE)
	f.store_string("this is not a save")
	f.close()
	f = FileAccess.open(game._slot_path(5), FileAccess.WRITE)
	f.store_string(var_to_str({"v": SaveFormat.VERSION + 1, "state": {}, "summary": "", "tick": 0, "saved_at": 0}))
	f.close()
	var listed := game.read_slots()
	check(listed[3] != null and listed[3].has("error"), "a damaged slot is listed as unreadable, not empty")
	check(listed[4] != null and "newer version" in listed[4].get("error", ""), "a newer save says why it can't load")
	check("newer version" in game.load_slot(5), "loading a newer save explains why it failed")
	_test_drag(game)
	await _test_fading(game)
	_test_smooth_movement(game)
	await _test_rebinding(game)
	await _test_craft_menu(game)
	await _test_right_click_never_silent(game)
	await _test_farm_tool(game)
	await _test_fireplace(game)
	await _test_jobs_grid(game)
	game.open_menu("main")
	game.restart()
	check(game.sim.tick == 0 and game.sim.residents.size() == 1 and not menu.visible, "Start over begins a fresh game")
	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	print("%s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures else 0)


## A cell or area of the original 18×18 opening, in today's map (issue #52 moved it to the middle).
static func at(x: int, y: int) -> Vector2i:
	return Vector2i(x, y) + Tuning.OPENING_OFFSET


static func area(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(Vector2i(x, y) + Tuning.OPENING_OFFSET, Vector2i(w, h))
