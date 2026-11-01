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


## The tally bar shows a total for each group of items, and hides groups nothing has turned up in
## (issues #73, #141). Each group opens a dropdown with every item's stockpiled and loose counts, and
## an item can be pinned to the bar on its own.
## The web build has no system fonts to fall back to, so every symbol the UI types must be in the UI font
## itself (issue #306). Looks at the strings in the view's code, comments left out.
func _test_glyphs() -> void:
	var font: FontFile = load("res://assets/fonts/BricolageGrotesque.ttf")
	var missing := {}
	for dir in ["res://view", "res://scenes"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			for line in FileAccess.get_file_as_string("%s/%s" % [dir, f]).split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
				var code := line.split("  #")[0]
				for i in code.length():
					if code.unicode_at(i) > 0xFF and not font.has_char(code.unicode_at(i)):
						missing[code[i]] = f
	check(missing.is_empty(), "every symbol the UI types is in its font (missing: %s)" % [missing])


func _test_tallies(game: Game) -> void:
	var hud: Hud = game._hud
	var sim := game.sim
	var shown := func() -> Array:
		hud.refresh(sim)
		return Defs.TALLY_GROUPS.map(func(g): return g[0]).filter(func(g): return hud._group_btns[g].visible)
	for k in sim.items.keys():  # an empty map: nothing has turned up in this game yet
		if not Defs.wears(sim.items[k].type):
			sim.items.erase(k)
	hud._tally_sim = 0
	var waiting_for := {}
	for site in sim.sites:
		if not site.done:
			for t in sim.current_stage(site).cost:
				waiting_for[t] = true
		for id in site.get("queue", []):
			for t in Defs.recipe(id).inp:
				waiting_for[t] = true
	var groups: Array = shown.call()
	var expect := ["tools"]
	for t in waiting_for:
		if not expect.has(Defs.ITEMS[t].group):
			expect.append(Defs.ITEMS[t].group)
	check(groups.size() == expect.size() and expect.all(func(g): return groups.has(g)), "with nothing about, the bar shows Tools and armor, and the groups of what's being waited for (%s)" % [groups])
	check(not groups.has("food") and not groups.has("ores"), "no Food or Ores before any turn up")
	sim.drop_items(Sim.rcell(sim.residents[0]), "bread", 1)
	sim.drop_items(Sim.rcell(sim.residents[0]) + Vector2i(2, 0), "beef", 2)
	check(shown.call().has("food"), "a loaf of bread brings in the Food group")
	var food: Button = hud._group_btns.food
	check(food.text.begins_with("Food  1 meal · 2 raw"), "Food counts meals on hand and raw meat to cook apart (%s)" % food.text)
	var low := 1 < sim.residents.size()
	check((food.get_theme_color("font_color") == Palette.YELLOW) == low, "Food is yellow only when meals are fewer than residents")
	check(("low" in food.text) == low, "and says \"low\" in words then too, not by colour alone (%s)" % food.text)
	sim.drop_items(Sim.rcell(sim.residents[0]), "wool", 2)
	check(shown.call().has("animal") and hud._group_btns.animal.text.begins_with("Animal goods  2"), "wool brings in Animal goods")
	for k in sim.items.keys():
		if sim.items[k].type == "wool":
			sim.items.erase(k)
	check(shown.call().has("animal") and hud._group_btns.animal.text.begins_with("Animal goods  0"), "and it stays, at 0, after it's used up")
	# Each group's dropdown lists its items with their counts (issue #141).
	for g in ["building", "food", "tools"]:
		hud._drop_pinned = g
		hud._process(0.0)
		hud.refresh(sim)
		check(hud._tools_drop.visible and hud._drop_group == g, "the %s dropdown opens" % g)
	hud._drop_pinned = "food"
	hud._process(0.0)
	hud.refresh(sim)
	var rows := hud._tools_list.find_children("*", "Button", true, false).filter(func(b): return not b.is_queued_for_deletion() and str(b.get_meta("label", "")).begins_with("Pin "))
	check(rows.any(func(b): return b.get_meta("label") == "Pin beef") and rows.any(func(b): return b.get_meta("label") == "Pin bread"), "the Food dropdown lists bread and raw beef, each with Pin")
	var labels := hud._tools_list.find_children("*", "Label", true, false).filter(func(l): return not l.is_queued_for_deletion()).map(func(l): return l.text)
	check(labels.has("Meals on hand") and labels.has("Raw meat to cook"), "and splits meals from raw meat")
	var keys_before: Array = game.keys.pinned.duplicate()
	game.pin_item("beef")
	hud.refresh(sim)
	var pinned := hud._tallies.get_children().filter(func(n): return n is VBoxContainer and not n.is_queued_for_deletion()).map(func(n): return n.get_child(0).get_child(0).text)
	check(pinned == ["Beef"] and game.keys.pinned == ["beef"], "pinning raw beef puts it in the bar on its own (%s)" % [pinned])
	var reread := KeyBindings.new(game.keys.path)
	check(reread.pinned == ["beef"], "pins are kept with the key bindings, not in game saves")
	game.pin_item("beef")
	check(game.keys.pinned == keys_before, "unpinning takes it out again")
	hud._close_tools()


## The main menu's Quit asks first; Cancel leaves the game running (issue #60). Confirming would end
## the test run, so it isn't pressed.
func _test_quit(game: Game, menu) -> void:
	game.open_menu("main")
	await process_frame
	var quit_btn: Array = _walk(menu).filter(func(n): return n is Button and n.text == "Quit" and not n.is_queued_for_deletion())
	check(quit_btn.size() == 1, "the main menu has a Quit button")
	if quit_btn.size() != 1:
		return
	quit_btn[0].pressed.emit()
	await process_frame
	check(not menu._confirm.is_empty() and menu._confirm.action == "quit" and "Quit Block Village?" in menu._confirm.text, "Quit asks first")
	var cancel: Array = _walk(menu).filter(func(n): return n is Button and n.text == "Cancel" and not n.is_queued_for_deletion())
	if cancel.size() == 1:
		cancel[0].pressed.emit()
	await process_frame
	check(menu._confirm.is_empty() and menu.visible and is_instance_valid(game), "Cancel leaves the game running, on the menu")
	game.close_menu()


## A long status moves below its title instead of running into it (issue #72).
func _test_headers(game: Game) -> void:
	var hud: Hud = game._hud
	var short := hud._head("Sheep meadow", "6 of 8 sheep")
	var long := hud._head("Farm plot", "Ripe wheat, waiting to be harvested")
	check(short is HBoxContainer and short.get_theme_constant("separation") >= 12, "a short status sits beside its title, with a gap")
	check(long is VBoxContainer and long.get_child_count() == 2, "a long status gets its own line below the title")
	short.free()
	long.free()


## Trees in front of a blueprint, or of a building that is stuck, fade without selecting it (issue #304).
func _test_fade_for_blueprints(game: Game) -> void:
	var sim := game.sim
	game.selection = {}
	var spot := Vector2i(sim.w / 2 + 6, sim.h / 2 - 6)
	var bp := sim.place_site("bench", spot)
	check(bp != null and not bp.done, "a blueprint is placed")
	game._update_focus(null)
	var near: Array = game._world.focus_points.filter(func(f): return absf(f[0].x - (spot.x + 0.5)) < 3.0 and absf(f[0].z - (spot.y + 0.5)) < 3.0)
	check(not near.is_empty(), "an unselected blueprint is a focus for the fade (%d points)" % near.size())
	bp.done = true
	game._update_focus(null)
	near = game._world.focus_points.filter(func(f): return absf(f[0].x - (spot.x + 0.5)) < 3.0 and absf(f[0].z - (spot.y + 0.5)) < 3.0)
	check(near.is_empty(), "a finished, unstuck building is not")
	sim.sites.erase(bp)
	sim.rev += 1


## Toasts are kept in a log that opens from a button, so a missed one can be read (issue #297).
func _test_message_log(game: Game) -> void:
	var hud: Hud = game._hud
	var base: int = hud._log.size()
	hud._log_unread = 0
	hud.add_toast({"text": "A traveler arrived at the first house.", "res_id": 0, "site_id": 0})
	hud.add_toast({"text": "The expedition board is up.", "res_id": 0, "site_id": 1})
	hud.refresh(game.sim)
	check(hud._log.size() == base + 2 and hud._log_btn.text == "Log  (2 new)", "two toasts are kept, and the button counts them (%s)" % hud._log_btn.text)
	hud._toggle_log()
	await game.get_tree().process_frame
	var all := _walk(hud._log_list).filter(func(n): return not n.is_queued_for_deletion())
	var texts: Array = all.filter(func(n): return n is Label and ("arrived at the first house" in n.text or "board is up" in n.text)).map(func(n): return n.text)
	check(hud._log_panel.visible and texts.size() == 2 and "board is up" in texts[0], "opening it lists them, newest first (%s)" % [texts])
	check(hud._log_btn.text == "Log" and hud._log_unread == 0, "and clears the count")
	check(hud.get_viewport().get_visible_rect().encloses(hud._log_panel.get_global_rect()), "the list lies inside the window")
	check(all.any(func(n): return n is Button and n.text == "Show"), "a message about a place has a button to it")
	for i in 80:
		hud.add_toast({"text": "Message %d" % i, "res_id": 0, "site_id": 0})
	check(hud._log.size() == Hud.LOG_MAX and hud._log.back().text == "Message 79", "it keeps the last %d" % Hud.LOG_MAX)
	hud._toggle_log()
	check(not hud._log_panel.visible, "the button closes it again")
	await game.get_tree().process_frame


## The stuck list sets the choices waiting for the player apart from what's wrong (issue #296).
func _test_needs_you(game: Game) -> void:
	var sim := game.sim
	var hud: Hud = game._hud
	var kept: Array = sim.stuck.duplicate(true)
	var entry := func(who: String, why: String, waiting: bool, decision: String) -> Dictionary:
		return {"who": who, "why": why, "map": "village", "cell": Vector2(5, 5), "height": 1.0, "focus_kind": "", "focus_id": 0, "hidden": false,
			"waiting": waiting or decision != "", "decision": decision, "key": who + why, "since": 0}
	sim.stuck = [entry.call("House", "Walls need 4 more planks", false, ""), entry.call("Freight cart", "waiting for approval", true, "freight"), entry.call("Fireplace", "short of logs", true, "")]
	hud.refresh(sim)
	await game.get_tree().process_frame
	var all := _walk(hud._stuck).filter(func(n): return not n.is_queued_for_deletion())
	var heads: Array = all.filter(func(n): return n is Label and n.text.begins_with("Needs you")).map(func(n): return n.text)
	check(heads == ["Needs you (1)"], "a \"Needs you\" heading counts the choices (%s)" % [heads])
	var stuck_head: Array = all.filter(func(n): return n is Button and n.text.begins_with("Stuck ("))
	check(stuck_head.size() == 1 and "(1)" in stuck_head[0].text, "the Stuck count has only the real problem")
	var approve: Array = all.filter(func(n): return n is Button and n.get_meta("label", "") == "Needs you: Approve departure")
	var decline: Array = all.filter(func(n): return n is Button and n.get_meta("label", "") == "Needs you: Decline")
	check(approve.size() == 1 and decline.size() == 1, "the list holds the buttons that answer it")
	var pos_need := -1
	var pos_stuck := -1
	for i in all.size():
		if pos_need < 0 and all[i] is Label and all[i].text.begins_with("Needs you"):
			pos_need = i
		if pos_stuck < 0 and all[i] is Button and all[i].text.begins_with("Stuck ("):
			pos_stuck = i
	check(pos_need >= 0 and pos_need < pos_stuck, "and it comes first")
	sim.stuck = [entry.call("Freight cart", "waiting for approval", true, "freight")]
	hud.refresh(sim)
	await game.get_tree().process_frame
	check(hud._stuck_panel.visible, "a choice alone still shows the panel")
	sim.stuck = kept
	hud.refresh(sim)
	await game.get_tree().process_frame


## The game saves itself now and then, to a file of its own (issue #295).
func _test_autosave(game: Game) -> void:
	var sim := game.sim
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game._autosave_path()))
	var menu: GameMenu = game._menu
	while sim.tick < int(Tuning.AUTOSAVE_MIN_SECS * Tuning.TPS) + 10:  # old enough to be worth saving
		sim.step()
	var was_tick := sim.tick
	check(game.read_autosave() == null, "there's no autosave to begin with")
	# A game younger than two minutes isn't autosaved: it would replace a village's.
	var young := Sim.new_game()
	var old_sim := game.sim
	game.sim = young
	check(not game.autosave() and game.read_autosave() == null, "a new game isn't autosaved")
	game.sim = old_sim
	game.speed = 1
	menu.visible = false
	game._autosave_tick = sim.tick
	game._autosave_sig = game._party_sig()
	check(not game._autosave_due(), "nothing is due just after one")
	game._autosave_tick = sim.tick - int(Tuning.AUTOSAVE_SECS * Tuning.TPS)
	check(game._autosave_due(), "after five minutes of play it's due")
	game.speed = 0
	check(not game._autosave_due(), "not while paused: nothing's changing")
	game.speed = 1
	check(game.autosave() and not game._autosave_due(), "saving clears it")
	var meta = game.read_autosave()
	check(meta != null and meta.tick == was_tick and meta.summary == Goals.progress_text(sim), "the autosave carries a label like a slot's (%s)" % [meta])
	var ex: Dictionary = sim.expeditions.overworld
	ex.state = "staging"
	check(game._autosave_due(), "a party packing, setting out or coming home makes one due")
	ex.erase("state")
	game._autosave_sig = game._party_sig()
	# The Load page lists it, above the slots; the Save page doesn't.
	menu.show_view("load")
	await game.get_tree().process_frame
	var rows := _walk(menu._box).filter(func(n): return n is Label and n.text == "Autosave" and not n.is_queued_for_deletion())
	check(rows.size() == 1, "the Load page has an Autosave row")
	menu.show_view("save")
	await game.get_tree().process_frame
	check(_walk(menu._box).filter(func(n): return n is Label and n.text == "Autosave" and not n.is_queued_for_deletion()).is_empty(), "the Save page doesn't")
	menu.show_view("main")
	await game.get_tree().process_frame
	check(_walk(menu._box).any(func(n): return n is Label and "autosave" in n.text and not n.is_queued_for_deletion()), "the main menu says there's one")
	menu.visible = false
	# Loading it brings the game back as it was.
	for i in 100:
		sim.step()
	check(game.load_autosave() == "" and game.sim.tick == was_tick, "loading it returns to the moment it was made")
	# Starting over keeps the village that was left.
	game.restart()
	check(game.sim.tick < 100 and game.read_autosave().tick == was_tick, "Start over leaves the old game as the autosave")
	check(not game.autosave() and game.read_autosave().tick == was_tick, "and the new, empty game doesn't replace it")
	menu.visible = false
	game.speed = 1


## Skipping ahead runs fast until something needs the player (issue #299).
func _test_skip_ahead(game: Game) -> void:
	var sim := game.sim
	game._menu.visible = false
	game.set_speed(1)
	sim.events.clear()
	game.set_skip(true)
	await game.get_tree().process_frame
	game._hud.refresh(sim)
	check(game.skipping and game._hud._skip_btn.button_pressed, "Skip starts a skip, and its button shows it")
	check(game._skip_stop_reason() == "", "nothing needs the player right after it starts")
	var t0 := sim.tick
	game._process(0.1)
	check(sim.tick - t0 >= 20 and sim.tick - t0 <= 30, "a skip runs faster than 1× (%d ticks in a tenth of a second)" % (sim.tick - t0))
	sim.events.append({"type": "toast", "text": "x"})
	check(game._skip_stop_reason() == "there is a message", "a message stops it")
	sim.events.clear()
	var kept: Array = sim.stuck.duplicate(true)
	sim.stuck.append({"who": "Z", "why": "needs a thing", "map": "village", "cell": Vector2.ZERO, "height": 1.0, "focus_kind": "", "focus_id": 0, "hidden": false, "waiting": false, "decision": "", "key": "z|new", "since": 0})
	check(game._skip_stop_reason() == "something got stuck", "a new problem stops it")
	sim.stuck = kept
	var dec := {"who": "Cart", "why": "needs your say", "map": "village", "cell": Vector2.ZERO, "height": 1.0, "focus_kind": "", "focus_id": 0, "hidden": false, "waiting": true, "decision": "freight", "key": "d|cart", "since": 0}
	sim.stuck.append(dec)
	check(game._skip_stop_reason() == "something needs your say", "a new decision stops it")
	game._skip_decisions = game._decision_keys()
	check(game._skip_stop_reason() == "", "a decision already waiting when it started doesn't")
	sim.stuck = kept
	sim.expeditions.overworld["state"] = "staging"
	check(game._skip_stop_reason() == "a party set out or came home", "a party setting out stops it")
	sim.expeditions.overworld.erase("state")
	game._skip_from = sim.tick - int(Tuning.SKIP_MAX_SECS * Tuning.TPS)
	check(game._skip_stop_reason() == "ten minutes passed", "ten minutes of nothing ends it")
	game._skip_from = sim.tick - 400  # 20 s
	var toasts: int = game._hud._toast_list.size()
	game._end_skip("something got stuck")
	check(not game.skipping and game._hud._toast_list.size() >= mini(toasts + 1, 3), "ending it says why in a toast")
	game.set_skip(true)
	game.set_speed(2)
	check(not game.skipping and game.speed == 2, "picking a speed ends a skip")
	game.set_speed(1)


## Toasts sit in the gap below the tally bar, clear of the goals panel and the stuck list (issue #71).
func _test_toasts(game: Game) -> void:
	var hud: Hud = game._hud
	hud.add_toast({"text": "Tomas is now level 2 at Mine.", "res_id": 0, "site_id": 0})
	hud.add_toast({"text": "A traveler, Mira, has arrived. She claims the new house and needs tools from the bench before she can mine anything.", "res_id": game.sim.residents[0].id, "site_id": 0})
	for i in 3:
		await process_frame
	var clear := true
	var inside := true
	var overlaps := []  # what overlapped, so a failure says where (issue #309)
	var view := Rect2(Vector2.ZERO, hud._root.size)
	for p in hud._toasts.get_children():
		if not (p as Control).visible or p.is_queued_for_deletion():
			continue
		var r := (p as Control).get_global_rect()
		inside = inside and view.encloses(r)
		for other in [hud._tally_panel, hud._goals_panel, hud._stuck_panel]:
			if (other as Control).visible and r.intersects((other as Control).get_global_rect()):
				clear = false
				overlaps.append("%s %s over %s %s" % [p.name, r, (other as Control).name, (other as Control).get_global_rect()])
	check(clear, "toasts don't cover the tally bar, the goals panel or the stuck list (%s; toasts at %s %s)" % [overlaps, hud._toasts.position, hud._toasts.size])
	check(inside, "toasts fit on screen, wrapping when long")


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
	check(world.faded_trees.has(tree.id), "an unfinished blueprint keeps the tree in front of it faded, selected or not (issue #304)")
	bench.done = true
	sim.rev += 1
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
## The keycaps on a toolbar menu's row: its number, then its direct key if it has one.
func _menu_caps(game: Game, menu: String, row: String) -> Array:
	for b in game._hud._menus[menu].get_children():
		if b is Button and not b.is_queued_for_deletion() and b.get_meta("label", "") == row:
			return _walk(b).filter(func(n): return n is Label and n.get_parent() is PanelContainer).map(func(l): return l.text)
	return []


## Issue #204: the mason's bench offers a mineshaft once every boulder is gone and the bricks are cut.
func _test_mineshaft_button(game: Game) -> void:
	var sim := game.sim
	var hud: Hud = game._hud
	game.set_tool("")
	var at: Vector2i = sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(-3, 3))
	var bench: Dictionary = sim.place_site("mason_bench", at)
	bench.stage = Defs.TEMPLATES["mason_bench"].stages.size()
	bench.done = true
	sim._occ_dirty = true
	game.selection = {"kind": "site", "id": bench.id}
	hud.refresh(sim)
	await _frames()
	var btn: Array = _walk(hud._sel).filter(func(n): return n is Button and n.text == "Dig out a mineshaft" and not n.is_queued_for_deletion())
	check(btn.size() == 1 and btn[0].disabled, "a mason's bench has a Dig out a mineshaft button, off while boulders are left")
	check(_walk(hud._sel).any(func(n): return n is Label and n.text.begins_with("Not while boulders are left") and not n.is_queued_for_deletion()), "and it says why")
	for b in sim.boulders:
		b.alive = false
	sim._occ_dirty = true
	sim.drop_items(sim.nearest_walkable(at + Vector2i(2, 0)), "stone_brick", Tuning.SHAFT_COST.stone_brick)
	hud.refresh(sim)
	await _frames()
	btn = _walk(hud._sel).filter(func(n): return n is Button and n.text == "Dig out a mineshaft" and not n.is_queued_for_deletion())
	check(btn.size() == 1 and not btn[0].disabled, "with the boulders gone and the bricks cut, it's on")
	btn[0].pressed.emit()
	check(bench.get("upgrading", false) and not bench.done, "pressing it starts the rebuild")
	hud.refresh(sim)
	await _frames()
	check(_walk(hud._sel).any(func(n): return n is Label and n.text == "Mineshaft" and not n.is_queued_for_deletion()) or _walk(hud._sel).any(func(n): return n is Label and "Digging it out" in n.text and not n.is_queued_for_deletion()), "and its panel calls it a mineshaft")
	game.selection = {}


## Issues #168-#171: the portal station's freight panel, a device's panel with its Wire and settings buttons, and the redstone overlay.
func _test_redstone_panels(game: Game) -> void:
	var sim := game.sim
	var hud: Hud = game._hud
	game.set_tool("")
	if game._menu.visible:
		game.close_menu()
	var base: Vector2i = sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(0, 5))
	var a: Dictionary = sim.place_site("cache_sensor", base)
	var b: Dictionary = sim.place_site("condition", sim.nearest_walkable(base + Vector2i(4, 0)))
	for d in [a, b]:
		d.stage = 1
		d.done = true
	sim._step_devices()
	game.selection = {"kind": "site", "id": a.id}
	game.focus_on("site", a.id)
	hud.refresh(sim)
	await _frames()
	var texts: Array = _walk(hud._sel).filter(func(n): return n is Button and not n.is_queued_for_deletion()).map(func(n): return n.text)
	check(texts.has("Wire to the condition") and texts.has("+"), "a sensor's panel offers Wire and a threshold")
	var wire_btn: Array = _walk(hud._sel).filter(func(n): return n is Button and n.text == "Wire to the condition" and not n.is_queued_for_deletion())
	wire_btn[0].pressed.emit()
	check(sim.wires.size() == 1 and sim.wires[0].from == a.id, "pressing it orders the dust line")
	game.set_device_cfg(a.id, "below", 4)
	check(a.cfg.below == 4, "the threshold changes")
	game.toggle_redstone_overlay()
	hud.refresh(sim)
	await _frames()
	check(game._world.redstone_overlay, "the redstone overlay turns on")
	game.toggle_redstone_overlay()
	sim.cut_wire(sim.wires[0].id)
	sim.freight = {"state": "home", "pos": 0.0, "load": {"bread": 3}, "approved": false, "acc": 0.0}
	var ps: Dictionary = sim.place_site("portal_station", sim.nearest_walkable(base + Vector2i(0, 4)))
	ps.stage = 1
	ps.done = true
	game.selection = {"kind": "site", "id": ps.id}
	game.focus_on("site", ps.id)
	hud.refresh(sim)
	await _frames()
	var pbtns: Array = _walk(hud._sel).filter(func(n): return n is Button and not n.is_queued_for_deletion()).map(func(n): return n.text)
	check(pbtns.has("Approve departure"), "the portal station's panel has Approve departure for a loaded cart")
	var lo := Vector2i(-1, -1)
	for dy in range(0, 3):
		for dx in range(0, 3):
			var cand: Vector2i = ps.plot.position + Vector2i(dx, dy)
			if lo.x < 0 and sim.placement_check("freight_loader", cand) == "":
				lo = cand
	var ld: Dictionary = sim.place_site("freight_loader", lo)
	ld.stage = 1
	ld.done = true
	sim._step_devices()
	game.selection = {"kind": "site", "id": ld.id}
	game.focus_on("site", ld.id)
	hud.refresh(sim)
	await _frames()
	var lbtns: Array = _walk(hud._sel).filter(func(n): return n is Button and not n.is_queued_for_deletion())
	check(lo.x >= 0 and lbtns.size() >= 8, "the loader's panel has a freight list to change")
	sim.maps.village.sites.erase(ld)
	sim.freight = {}
	sim.wires.clear()
	sim.maps.village.sites.erase(a)
	sim.maps.village.sites.erase(b)
	sim.maps.village.sites.erase(ps)
	sim._occ_dirty = true
	game.selection = {}
	hud.refresh(sim)


## Issue #203: select a workstation, Paint area, then drag to add cells and drag from a painted one to erase.
func _test_work_area_painting(game: Game) -> void:
	var sim := game.sim
	var hud: Hud = game._hud
	game.set_tool("")
	if game._menu.visible:
		game.close_menu()
	var at: Vector2i = sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(2, 2))
	var block: Dictionary = sim.place_site("chopping_block", at)
	block.stage = Defs.TEMPLATES["chopping_block"].stages.size()
	block.done = true
	sim._occ_dirty = true
	game.selection = {"kind": "site", "id": block.id}
	game.focus_on("site", block.id)
	hud.refresh(sim)
	await _frames()
	var btns: Array = _walk(hud._sel).filter(func(n): return n is Button and n.text == "Paint area" and not n.is_queued_for_deletion())
	check(btns.size() == 1, "a chopping block's panel has Paint area")
	btns[0].pressed.emit()
	check(game.tool == "area" and game.area_site == block.id, "it switches the area-painting tool on")
	hud.refresh(sim)
	await _frames()
	check(_walk(hud._sel).any(func(n): return n is Button and n.text == "Done painting" and not n.is_queued_for_deletion()), "and the button reads Done painting")
	# Erase by dragging from a painted cell, then paint the cells back by dragging from an unpainted one.
	var a: Vector2i = block.origin + Vector2i(3, 0)
	var b: Vector2i = block.origin + Vector2i(5, 1)
	check(block.area.has(a) and block.area.has(b), "the cells to drag over start painted")
	var pa: Vector2 = game._cam.unproject_position(Vector3(a.x + 0.5, 0.0, a.y + 0.5))
	var pb: Vector2 = game._cam.unproject_position(Vector3(b.x + 0.5, 0.0, b.y + 0.5))
	_mouse(game, "move", pa)
	_mouse(game, "down", pa)
	_mouse(game, "move", pb)
	_mouse(game, "up", pb)
	check(not block.area.has(a) and not block.area.has(b) and not block.area.has(a + Vector2i(1, 0)), "a drag from a painted cell erases the cells it covers")
	_mouse(game, "move", pa)
	_mouse(game, "down", pa)
	_mouse(game, "move", pb)
	_mouse(game, "up", pb)
	check(block.area.has(a) and block.area.has(b) and block.area.has(a + Vector2i(1, 0)), "a drag from an unpainted cell paints them again")
	game.set_tool("")
	check(game.tool == "" and game.selection.get("id", 0) == block.id, "Esc puts the tool away and keeps the selection")


## The key shown on a button's keycap, or "".
func _cap_text(b: Button) -> String:
	var cap = b.get_meta("keycap", null)
	if cap == null:
		return ""
	return (cap.get_child(0) as Label).text


## Issue #197: the selection panel's buttons have keys Q E R Z X C V, and 1–9 pick a list's entries.
func _test_panel_keys(game: Game) -> void:
	var hud: Hud = game._hud
	var sim := game.sim
	game.keys.reset()
	game.set_tool("")
	game.craft_menu_open = false
	game.jobs_board_open = false
	game.book_open = false
	if game._menu.visible:
		game.close_menu()
	# The bindings: Selection keys share keys with orders and the speed keys, and with nothing else.
	var kb: KeyBindings = game.keys
	var x := InputEventKey.new()
	x.keycode = KEY_X
	check(kb.action_for(x) == "mine" and kb.panel_index(x) == 4, "X is both the Mine order and Panel action 5, told apart by context")
	check(kb.used_by(KEY_Q, "mine") == "" and kb.used_by(KEY_1, "list1") == "" and kb.used_by(KEY_W, "panel1") == "pan_up", "a Selection key may share with an order or a speed key, not with panning (%s)" % kb.used_by(KEY_W, "panel1"))
	check(kb.used_by(KEY_Q, "panel2") == "panel1", "two Selection keys can't share")
	# A tree: Q marks it to mine, and again unmarks it; E keeps it.
	var tree: Dictionary = sim.trees.filter(func(t): return t.alive and Sim.grown(t) and not t.des and not t.get("keep", false))[0]
	game.selection = {"kind": "tree", "id": tree.id}
	hud.refresh(sim)
	await _frames()
	check(hud._panel_btns.size() >= 2 and hud._panel_btns[0].text == "Mine" and _cap_text(hud._panel_btns[0]) == "Q", "a tree's Mine button shows Q (%s)" % [hud._panel_btns.map(func(b): return b.text)])
	check(_cap_text(hud._panel_btns[1]) == "E", "and the next button shows E")
	_key(game, KEY_Q)
	check(tree.des, "Q marks the selected tree to mine")
	hud.refresh(sim)
	await _frames()
	check(hud._panel_btns[0].text == "Cancel mining" and game.selection.get("id", 0) == tree.id, "the selection stays, and the button now reads Cancel mining")
	_key(game, KEY_Q)
	check(not tree.des, "Q again unmarks it")
	hud.refresh(sim)
	await _frames()
	_key(game, KEY_E)
	check(tree.get("keep", false) and game.menu_open == "", "E keeps it, and doesn't open the gather menu")
	_key(game, KEY_E)
	# A sheep: Q marks it to hunt.
	var sheep: Dictionary = sim.sheep.filter(func(a): return a.alive)[0]
	game.selection = {"kind": "animal", "id": sheep.id}
	hud.refresh(sim)
	await _frames()
	var before: Variant = sheep.des
	_key(game, KEY_Q)
	check(sheep.des != before, "Q marks the selected sheep to hunt")
	# A resident: a key opens the job dropdown, then a number picks a job, and the speed is untouched.
	var res: Dictionary = sim.residents.filter(func(r): return r.role != "all")[0] if sim.residents.any(func(r): return r.role != "all") else sim.add_resident("Tester", Sim.TRAVELERS[0][1], sim.nearest_walkable(Vector2i(8, 8)))
	game.selection = {"kind": "res", "ids": [res.id]}
	hud.refresh(sim)
	await _frames()
	var drop_i := -1
	for i in hud._panel_btns.size():
		if "↓" in hud._panel_btns[i].text:
			drop_i = i
	check(drop_i >= 0, "the resident's job dropdown has a panel key (%s)" % [hud._panel_btns.map(func(b): return b.text)])
	var speed_before := game.speed
	_key(game, game.keys.keys["panel%d" % (drop_i + 1)][0])
	hud.refresh(sim)
	await _frames()
	check(hud.list_open(), "its key opens the list")
	var entries: Array = hud.list_entries()
	var second_job: String = ""
	for jb in Defs.JOBS + ["none"]:
		if entries.size() > 1 and entries[1].get_meta("label", "").contains("Job choice: " + ("No job" if jb == "none" else Defs.JOB_NAMES[jb])):
			second_job = jb
	var old_role: String = res.role
	_key(game, KEY_2)
	check(game.speed == speed_before and res.role != old_role, "2 picks the list's second entry (%s to %s), not 2× speed" % [old_role, res.role])
	hud.refresh(sim)
	await _frames()
	check(not hud.list_open(), "the list closes after a pick")
	# F still cycles residents while one is selected.
	if sim.residents.size() > 1:
		game.selection = {"kind": "res", "ids": [sim.residents[0].id]}
		_key(game, KEY_F)
		check(game.selection.get("ids", []) != [sim.residents[0].id], "F selects the next resident")
	# A farm plot: the Remove key arms it, another key disarms it, and twice removes it.
	var farm_at: Vector2i = sim.nearest_walkable(Vector2i(14, 14))
	sim.paint_farm(Rect2i(farm_at, Vector2i(1, 1)))
	var crop: Dictionary = sim.farm[farm_at] if sim.farm.has(farm_at) else sim.farm.values()[0]
	game.selection = {"kind": "crop", "id": crop.id}
	hud.refresh(sim)
	await _frames()
	var rm_i := -1
	for i in hud._panel_btns.size():
		if hud._panel_btns[i].text == "Remove this plot":
			rm_i = i
	check(rm_i >= 0, "a farm plot's panel has Remove this plot with a key")
	var rm_key: Key = game.keys.keys["panel%d" % (rm_i + 1)][0]
	_key(game, rm_key)
	check(sim.farm.has(crop.cell) and hud._panel_btns[rm_i].text.begins_with("Click again"), "the first press only arms it")
	_key(game, KEY_W)
	check(hud._panel_btns[rm_i].text == "Remove this plot", "another key disarms it")
	_key(game, rm_key)
	_key(game, rm_key)
	check(not sim.farm.has(crop.cell), "the same key twice removes it")
	# A bench: its key opens the craft menu.
	var bench: Dictionary = sim.sites.filter(func(st): return st.tpl == "bench" and st.done)[0] if sim.sites.any(func(st): return st.tpl == "bench" and st.done) else {}
	if not bench.is_empty():
		game.selection = {"kind": "site", "id": bench.id}
		hud.refresh(sim)
		await _frames()
		var cm_i := -1
		for i in hud._panel_btns.size():
			if hud._panel_btns[i].text == "Open the craft menu":
				cm_i = i
		check(cm_i >= 0, "a bench's panel has the craft menu button with a key")
		_key(game, game.keys.keys["panel%d" % (cm_i + 1)][0])
		check(game.craft_menu_open, "its key opens the craft menu")
		game.craft_menu_open = false
	# Nothing selected: the order keys keep their meanings. Esc clears a selection.
	game.selection = {"kind": "tree", "id": tree.id}
	_key(game, KEY_ESCAPE)
	check(game.selection.is_empty() and not game._menu.visible, "Esc clears the selection first")
	_key(game, KEY_X)
	check(game.tool == "mine", "with nothing selected, X picks Mine")
	game.set_tool("")
	_key(game, KEY_E)
	check(game.menu_open == "gather", "and E opens the gather menu")
	game.set_tool("")
	# Rebinding Panel action 1 moves the badge and the key.
	game.keys.assign("panel1", KEY_T)
	hud._keys_sig = ""
	game.selection = {"kind": "tree", "id": tree.id}
	hud.refresh(sim)
	await _frames()
	check(_cap_text(hud._panel_btns[0]) == "T", "after rebinding Panel action 1, the badge shows T")
	_key(game, KEY_T)
	check(tree.des and game.tool == "", "and T marks the tree, not placing a bench")
	_key(game, KEY_T)
	game.keys.reset()
	hud._keys_sig = ""
	game.selection = {}


## Issue #216: a Menu button on the HUD opens the Esc menu, shows the menu key and follows a rebind.
func _test_menu_button(game: Game) -> void:
	var hud: Hud = game._hud
	game.set_tool("")
	if game._menu.visible:
		game.close_menu()
	hud.refresh(game.sim)
	var b: Button = hud._menu_btn
	check(b.is_visible_in_tree() and b.text == "Menu", "the HUD has a Menu button")
	check(hud._menu_cap_label.text == game.keys.first("menu"), "it shows the menu key (%s)" % hud._menu_cap_label.text)
	var r := b.get_global_rect()
	check(get_root().get_visible_rect().encloses(r), "it's on screen")
	for other in [hud._speed_panel, hud._stuck_panel, hud._tally_panel]:
		check(not other.visible or not other.get_global_rect().intersects(hud._menu_panel.get_global_rect()), "it covers neither the speed buttons, the stuck list nor the tally bar")
	for m in hud._maps.get_children():  # the map switcher runs along the top (the slice 3.5 bot's Meadow button)
		check(not m is Button or not m.is_visible_in_tree() or not m.get_global_rect().intersects(hud._menu_panel.get_global_rect()), "nor the %s button of the map switcher" % m.name)
	b.pressed.emit()
	check(game._menu.visible and game._menu.view == "main", "clicking it opens the main menu")
	game.toggle_menu()
	check(not game._menu.visible, "clicking it again closes the menu, as Esc does")
	game.keys.assign("menu", KEY_F2)
	hud._keys_sig = ""
	hud.refresh(game.sim)
	check(hud._menu_cap_label.text == "F2" and "F2" in b.tooltip_text, "the badge and tooltip follow a rebound key")
	game.keys.reset()
	hud._keys_sig = ""
	hud.refresh(game.sim)


## Issues #93, #94: Gather and Paint menus in the toolbar, picked by click or by 1–9 while open.
func _test_order_menus(game: Game) -> void:
	var hud: Hud = game._hud
	var sim := game.sim
	game.set_tool("")
	game.craft_menu_open = false
	hud.refresh(sim)
	check(hud._tool_btns.keys() == ["gather", "paint", "build", "craft"], "the toolbar is Gather, Paint, Build and Craft (%s)" % [hud._tool_btns.keys()])
	check(hud._tool_btns.gather.text == "Gather  →" and hud._tool_btns.paint.text == "Paint  →", "with no order on, the menu buttons say so with →")
	_key(game, KEY_Z)
	hud.refresh(sim)
	check(game.menu_open == "paint" and hud._menu_panels.paint.visible, "Z opens the Paint menu")
	var rows: Array = hud._menus.paint.get_children().filter(func(n): return not n.is_queued_for_deletion())
	check(rows.map(func(r): return r.get_meta("label", "")) == ["Stockpile", "Farm plot"], "it lists Stockpile and Farm plot")
	_key(game, KEY_1)
	check(game.tool == "stock" and game.menu_open == "", "1 picks Stockpile and closes the menu")
	_key(game, KEY_E)
	hud.refresh(sim)
	check(game.menu_open == "gather" and game.tool == "stock", "E opens the Gather menu, leaving Stockpile on until you pick")
	var names: Array = hud._menus.gather.get_children().filter(func(n): return not n.is_queued_for_deletion()).map(func(b): return b.get_meta("label", ""))
	var sheep := sim.sheep.any(func(sh): return sh.alive)
	check(names.slice(0, 3) == ["Mine", "Chop trees", "Break boulders"] and names.has("Hunt") == sheep, "Gather lists Mine, Chop trees, Break boulders, and Hunt while there are sheep (%s)" % [names])
	hud._menus.gather.get_children().filter(func(b): return b.get_meta("label", "") == "Chop trees")[0].pressed.emit()
	check(game.tool == "chop" and game.order_kinds(false, true) == ["tree"], "Chop trees marks trees only, whatever the modifiers")
	hud.refresh(sim)
	check(hud._tool_btns.gather.text == "Gather: Chop trees" and hud._tool_btns.gather.button_pressed, "the Gather button names the order that's on")
	game.set_tool("break")
	check(game.order_kinds(true, false) == ["boulder"], "Break boulders marks boulders only")
	_key(game, KEY_X)
	check(game.tool == "mine" and game.menu_open == "" and game.order_kinds(true, false) == ["tree"], "X still switches Mine on directly, Shift still limits it to trees")
	_key(game, KEY_G)
	check(game.tool == "hunt", "G still switches Hunt on directly")
	_key(game, KEY_ESCAPE)
	check(game.tool == "", "Esc puts the order away")
	_key(game, KEY_B)
	_key(game, KEY_2)
	check(game.tool == "build" and game.placing == "house", "B then 2 places a house, as the Build menu's second row")
	_key(game, KEY_ESCAPE)
	_key(game, KEY_Z)
	_key(game, KEY_ESCAPE)
	check(game.menu_open == "", "Esc closes an open menu")
	# A drag that starts on a farm plot erases plots instead of painting (issue #93, like #63's stockpile).
	var spot := Vector2i(-1, -1)
	for c in sim.farm:
		spot = c
		break
	if spot.x < 0:
		for d in range(2, 12):
			var c: Vector2i = Sim.rcell(sim.residents[0]) + Vector2i(d, d)
			if sim.farm_blocked(c) == "":
				sim.paint_farm(Rect2i(c, Vector2i.ONE))
				spot = c
				break
	game.pick_order("paint", "farm")
	var at: Vector2 = game._cam.unproject_position(Vector3(spot.x + 0.5, 0.0, spot.y + 0.5))
	_mouse(game, "move", at)
	_mouse(game, "down", at)
	check(game._drag.get("erase", false), "starting a Farm drag on a plot erases")
	_mouse(game, "up", at)
	check(not sim.farm.has(spot), "and releasing removes the plot")
	game.set_tool("")


## Older key settings: Z moves from Stockpile to the new Paint menu; a new default that the player
## already uses for something else isn't taken from them.
func _test_key_migration() -> void:
	var path := "user://test_settings/old_keys.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var cfg := ConfigFile.new()
	for a in KeyBindings.ACTIONS:
		if a[0] not in ["gather", "paint", "chop", "break"]:
			cfg.set_value("keys", a[0], a[3])
	cfg.set_value("keys", "next_res", [KEY_E])
	cfg.save(path)
	var k := KeyBindings.new(path)
	check(k.keys.paint == [KEY_Z] and k.keys.stock.is_empty(), "an old settings file hands Z from Stockpile to Paint")
	check(k.keys.gather.is_empty() and k.keys.next_res == [KEY_E], "a player's own use of E keeps it; Gather goes without a key")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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
	check(game._hud._tool_btns.gather.text == "Gather: Mine", "the Gather button names the order that's on")
	game.set_tool("gather")
	game._hud.refresh(game.sim)
	check(_menu_caps(game, "gather", "Mine") == ["1", "Q"], "the Gather menu's Mine row shows the new key (%s)" % [_menu_caps(game, "gather", "Mine")])
	game.set_tool("")
	game.open_menu("keys")
	menu._listen("stock")
	_key(game, KEY_Q)
	check(not menu._confirm.is_empty() and "Mine trees and boulders" in menu._confirm.text, "taking Mine's key asks first")
	check(game.keys.keys.stock.is_empty(), "nothing changes until you confirm")
	menu._do_confirmed()
	check(game.keys.keys.stock == [KEY_Q] and game.keys.keys.mine.is_empty(), "confirming moves Q to Stockpile and leaves Mine without a key")
	game._hud.refresh(game.sim)
	game.set_tool("paint")
	game._hud.refresh(game.sim)
	check(_menu_caps(game, "paint", "Stockpile") == ["1", "Q"], "Stockpile's row shows Q (%s)" % [_menu_caps(game, "paint", "Stockpile")])
	game.set_tool("gather")
	game._hud.refresh(game.sim)
	check(_menu_caps(game, "gather", "Mine") == ["1"], "Mine's row has only its number now")
	game.set_tool("")
	menu._listen("mine")
	_key(game, KEY_W)
	check(not menu._confirm.is_empty() and "Pan up" in menu._confirm.text, "using W warns that it pans the camera")
	menu.back()
	menu._listen("speed1")
	_key(game, KEY_ESCAPE)
	check(menu.listening == "" and game.keys.keys.speed1 == [KEY_1], "Esc cancels waiting for a key")
	menu._reset_keys()
	check(game.keys.keys.mine == [KEY_X] and game.keys.keys.paint == [KEY_Z] and game.keys.keys.stock.is_empty(), "Reset to defaults restores every key")
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
		if n is Button and n.text == "Queue 1":  # the chosen recipe's (the first, Planks)
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
	check(left_queue.is_empty() and right_queue.size() == 1, "the recipes are only on the right (%d left, %d right)" % [left_queue.size(), right_queue.size()])
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
	# Issue #176: right-click on a tree opens the radial Gather menu, with or without residents.
	var ids := func() -> Array: return game.radial.get("wedges", []).map(func(w): return w.id)
	game.selection = {"kind": "res", "ids": [ada.id]}
	game.set_tool("mine")
	_right(game, at)
	check(ids.call() == ["mark", "now", "nearby"] and game.radial.wedges[1].label == "Chop now", "with Ada selected and Mine on, right-click opens the radial: Chop, Chop now, Chop all trees nearby (%s)" % [ids.call()])
	check(game.radial_title(tree).begins_with("Tree · ") and game.radial_title(tree).ends_with("logs"), "its middle names the tree and its logs (%s)" % game.radial_title(tree))
	game.pick_radial(1)
	check(game.radial.is_empty() and ada.direct != null and is_same(ada.direct.target, tree), "Chop now orders Ada to chop it, and closes the radial")
	check(game.tool == "mine", "and the Mine tool stays on")
	game.set_tool("")
	sim.fail_job(ada)
	ada.direct = null
	tree.des = false
	game.selection = {"kind": "tree", "id": tree.id}
	_right(game, at)
	check(ids.call() == ["mark", "nearby"], "with nobody selected, it has no Chop now (%s)" % [ids.call()])
	game.pick_radial(0)
	check(tree.des and ada.direct == null, "Chop marks the tree for anyone")
	_right(game, at)
	check(ids.call()[0] == "cancel", "once it's marked, Cancel takes Chop's place")
	_key(game, KEY_1)
	check(not tree.des and game.radial.is_empty(), "1 picks it: the mark is gone")
	_right(game, at)
	_key(game, KEY_ESCAPE)
	check(game.radial.is_empty() and not game._menu.visible, "Esc closes the radial, and doesn't open the menu")
	# Placing a building: right-click cancels the placement, as before.
	game.selection = {"kind": "res", "ids": [ada.id]}
	game.start_placing("house")
	_right(game, at)
	check(game.tool == "" and game.radial.is_empty() and ada.direct == null, "while placing a building, right-click cancels the placement")
	# Starving: Chop now is greyed, with the reason, and picking it says so.
	ada.hunger = 0.0
	_right(game, at)
	var now: Dictionary = game.radial.wedges[1] if game.radial.get("wedges", []).size() > 1 else {}
	check(not now.is_empty() and not now.ok and now.why == "Chop now: Ada is starving", "a starving resident's Chop now is greyed, with why (%s)" % [now])
	var toasts := game._hud._toast_list.size()
	game.pick_radial(1)
	check(ada.direct == null and game._hud._toast_list.size() == toasts + 1, "picking it explains why it won't happen")
	game.close_radial()
	ada.hunger = 100.0
	# Shift + right-click skips the radial and queues the order.
	_right(game, at, true)
	check(game.radial.is_empty() and (ada.orders.size() == 1 or ada.direct != null), "Shift + right-click skips the radial and gives the order")
	sim.fail_job(ada)
	ada.direct = null
	ada.orders.clear()


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
	check(hud._tool_btns.paint.button_pressed and hud._tool_btns.paint.text == "Paint: Farm plot", "and the Paint button shows Farm plot is on")
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
		check(sim.farm.has(rect.position) and remove[0].text == "Click again to remove the plot", "the first click only asks to confirm")
		check(remove[0].theme_type_variation == "Destructive", "removing a plot is styled as destructive")
		hud.refresh(sim)
		await process_frame
		var again: Array = _walk(hud._sel).filter(func(n): return n is Button and not n.is_queued_for_deletion() and n.text == "Click again to remove the plot")
		check(again.size() == 1, "and stays armed across a panel rebuild")
		if again.size() == 1:
			again[0].pressed.emit()
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
	var rows := _walk(hud._craft_box).filter(func(n): return n is Button and n.get_meta("label", "") in ["Bread", "Cooked mutton"])
	check(rows.size() == 2, "it lists its two recipes, bread and cooked mutton (%d)" % rows.size())
	var keep: Array = _walk(hud._craft_box).filter(func(n): return n is Button and n.text.begins_with("Keep 6 meals"))
	check(keep.size() == 1 and keep[0].text.ends_with("on"), "the standing order shows, on by default")
	if keep.size() == 1:
		keep[0].pressed.emit()
	check(not f.keep_meals, "clicking it turns the standing order off")
	await _test_station_tabs(game, f)
	_key(game, KEY_ESCAPE)


## Issue #76: one tab per station, the queue first, and recipe rows with inputs and a counted Queue.
func _test_station_tabs(game: Game, f: Dictionary) -> void:
	var hud: Hud = game._hud
	var sim := game.sim
	if not game.benches().any(func(b): return b.tpl == "bench"):  # a second station, for tabs
		for d in range(3, 15):
			var c: Vector2i = f.origin + Vector2i(d, 0)
			if sim.placement_check("bench", c) == "":
				var b := sim.place_site("bench", c)
				b.stage = 1
				b.done = true
				break
	game.open_craft_menu(f)
	hud.refresh(sim)
	await process_frame
	var tabs := func() -> Array: return _walk(hud._craft_box).filter(func(n): return n is Button and n.toggle_mode and n.text in ["Bench", "Fireplace"])
	check(tabs.call().size() == 2 and tabs.call().filter(func(t): return t.button_pressed).map(func(t): return t.text) == ["Fireplace"], "a tab for each station, the fireplace's pressed")
	tabs.call().filter(func(t): return t.text == "Bench")[0].pressed.emit()
	hud.refresh(sim)
	await process_frame
	check(game.craft_bench().tpl == "bench" and tabs.call().filter(func(t): return t.button_pressed).map(func(t): return t.text) == ["Bench"], "clicking the Bench tab shows the bench")
	# Issue #95: a recipe book, a crafting grid in the recipe's pattern, an arrow and the result.
	var book := func(name: String) -> Button:
		return _walk(hud._craft_box).filter(func(n): return n is Button and n.get_meta("label", "") == name).front()
	check(Defs.recipes_at("bench").all(func(r): return book.call(r.name) != null), "the recipe book has a slot for every bench recipe")
	check(book.call("Planks").button_pressed, "the first recipe is shown to start with")
	book.call("Wooden pickaxe").pressed.emit()
	hud.refresh(sim)
	await process_frame
	var grid: GridContainer = _walk(hud._craft_box).filter(func(n): return n is GridContainer and n.columns == 3).front()
	var filled: Array = grid.get_children().map(func(slot): return slot.get_child_count() > 0)
	check(filled == [true, true, true, false, true, false, false, true, false], "picking the pickaxe lays out its pattern on the 3×3 grid (%s)" % [filled])
	var yellow: Array = grid.get_children().filter(func(slot): return (slot.get_theme_stylebox("panel") as StyleBoxFlat).border_color == Palette.YELLOW)
	var short_items: Array = Defs.recipe("wood_pick").inp.keys().filter(func(k): return hud._have(sim, game.craft_bench(), k) < Defs.recipe("wood_pick").inp[k])
	var want := 0
	for k in short_items:
		want += Defs.recipe("wood_pick").inp[k]
	check(yellow.size() == want, "slots the village is short of are outlined yellow (%d of %d)" % [yellow.size(), want])
	check(_walk(hud._craft_box).any(func(n): return n is Label and n.text == "Wooden pickaxe"), "the result names the recipe")
	var bench: Dictionary = game.craft_bench()
	var before: int = bench.queue.size()
	book.call("Planks").pressed.emit()
	hud.refresh(sim)
	await process_frame
	var plus: Button = _walk(hud._craft_box).filter(func(n): return n is Button and n.text == "+").front()
	plus.pressed.emit()
	plus.pressed.emit()
	var q: Button = _walk(hud._craft_box).filter(func(n): return n is Button and n.text.begins_with("Queue ")).front()
	check(q.text == "Queue 3", "+ raises the count on the Queue button (%s)" % q.text)
	q.pressed.emit()
	check(bench.queue.size() == before + 3, "Queue 3 queues three planks")
	hud.refresh(sim)
	await process_frame
	var slots: Array = _walk(hud._craft_box).filter(func(n): return n is Button and n.get_meta("label", "") == "queued Planks")
	check(slots.size() >= 3, "the queue's hotbar shows them")
	slots[0].pressed.emit()
	check(bench.queue.size() == before + 2, "clicking a hotbar slot removes it")
	check(_walk(hud._craft_box).any(func(n): return n is Label and n.text == "On hand"), "what's on hand is shown")
	check(not tabs.call().filter(func(t): return t.text == "Fireplace" and t.icon != null).is_empty() == sim.stuck.any(func(x): return not x.waiting and x.focus_id == f.id), "the fireplace tab carries a flag exactly when it's stuck")
	# The fireplace is a furnace: what's cooked, a flame, and the fuel.
	tabs.call().filter(func(t): return t.text == "Fireplace")[0].pressed.emit()
	hud.refresh(sim)
	await process_frame
	book.call("Cooked mutton").pressed.emit()
	hud.refresh(sim)
	await process_frame
	var fuel: Array = _walk(hud._craft_box).filter(func(n): return n is PanelContainer and n.tooltip_text == "Fuel: 1 log")
	check(fuel.size() == 1, "the fireplace shows cooked mutton's fuel slot (a log)")
	check(_walk(hud._craft_box).filter(func(n): return n is GridContainer and n.columns == 3).is_empty(), "and no crafting grid")


## Issue #134: the resident panel's job line and the Village jobs board, with a job dropdown per
## resident and Ada doing everything.
func _test_jobs_grid(game: Game) -> void:
	game.restart()
	var sim := game.sim
	var hud: Hud = game._hud
	var ada: Dictionary = sim.residents[0]
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], sim.nearest_walkable(Sim.rcell(ada) + Vector2i(2, 0)))
	sim.set_role(tomas, "farm")
	tomas.jobs.cook.xp = 30  # level 3 at cooking
	game.selection = {"kind": "res", "ids": [ada.id]}
	hud.refresh(sim)
	await process_frame
	check(_walk(hud._sel).any(func(n): return n is Label and n.text == "Everything"), "Ada's panel says her job is Everything")
	check(not _walk(hud._sel).any(func(n): return n is Button and n.get_meta("label", "") == "Job: Ada"), "with no dropdown")
	var open_btn: Array = _walk(hud._sel).filter(func(n): return n is Button and n.text.begins_with("Jobs board"))
	check(open_btn.size() == 1, "with a button to the jobs board")
	open_btn[0].pressed.emit()
	hud.refresh(sim)
	await process_frame
	check(game.jobs_board_open and hud._board_panel.visible and hud._jobs_btn.button_pressed, "it opens the board, and the Jobs button shows it")
	check(_walk(hud._board).filter(func(n): return n.has_meta("cell") and not n.is_queued_for_deletion()).size() == Defs.JOBS.size() * sim.residents.size(), "a level cell per resident and job")
	var nobody: Array = _walk(hud._board).filter(func(n): return n is Label and n.text == "nobody" and not n.is_queued_for_deletion())
	check(nobody.filter(func(l): return l.get_theme_color("font_color") == Palette.YELLOW).size() == Defs.JOBS.size() - 2, "the jobs nobody has say so in yellow, Haul and Farm aside (%d)" % nobody.size())
	# Herd floors (issue #183): how many wild sheep hunters leave, with a stepper
	var floor_lbl := func() -> Label:
		return _walk(hud._board).filter(func(n): return n is Label and n.text.ends_with(" sheep") and n.get_parent() is HBoxContainer and not n.is_queued_for_deletion()).front()
	check(_walk(hud._board).any(func(n): return n is Label and n.text == "Hunters leave") and floor_lbl.call().text == "%d sheep" % Tuning.HERD_FLOOR, "the board shows how many sheep hunters leave (%s)" % floor_lbl.call().text)
	var plus: Button = floor_lbl.call().get_parent().get_child(floor_lbl.call().get_index() + 1)
	plus.pressed.emit()
	hud.refresh(sim)
	await process_frame
	check(sim.floor_of("sheep") == Tuning.HERD_FLOOR + 1 and floor_lbl.call().text == "%d sheep" % (Tuning.HERD_FLOOR + 1), "+ leaves one more")
	var pick := func() -> Button:
		return _walk(hud._board).filter(func(n): return n is Button and n.get_meta("label", "") == "Job: Tomas" and not n.is_queued_for_deletion()).front()
	check(pick.call().text.begins_with("Farmer, level 1 (no composter)"), "Tomas's row shows his job and level, and that he has no composter (%s)" % pick.call().text)
	pick.call().pressed.emit()
	hud.refresh(sim)
	await process_frame
	var choices: Array = _walk(hud._job_list).filter(func(n): return n is Button and not n.is_queued_for_deletion())
	check(hud._job_drop.visible and choices.size() == Defs.JOBS.size() + 1, "his dropdown lists every job and No job (%d)" % choices.size())
	check(choices[0].text.begins_with("Cook · level 3"), "best level first (%s)" % choices[0].text)
	check(choices.any(func(b): return b.text == "Farm · level 1 · 1 farmer · no composter" and b.button_pressed), "his own job is lit, with how many have it, and that there's no composter (issue #184)")
	choices.filter(func(b): return b.text.begins_with("Toolsmith"))[0].pressed.emit()
	hud.refresh(sim)
	await process_frame
	check(tomas.role == "toolsmith" and not hud._job_drop.visible, "choosing Toolsmith gives him the job and closes the dropdown")
	check(pick.call().text.begins_with("Toolsmith, level 1"), "and his row says so")
	pick.call().pressed.emit()
	hud.refresh(sim)
	await process_frame
	check(hud._job_drop.visible, "it opens again")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	hud._input(esc)  # the HUD sees keys before the game does
	check(not hud._job_drop.visible and game.jobs_board_open, "Esc closes the dropdown, and leaves the board open")
	_key(game, KEY_J)
	check(not game.jobs_board_open, "J closes the board")
	_key(game, KEY_J)
	_key(game, KEY_ESCAPE)
	check(not game.jobs_board_open and not game._menu.visible, "Esc closes the board before opening the menu")


## Issue #187: land claims. A chip in the top bar, an order in the Build menu, the edge nearest the
## cursor on offer (the cursor may be off the map), and the camera following a claim on the west.
func _test_land_claims(game: Game) -> void:
	game.restart()
	var sim := game.sim
	var hud: Hud = game._hud
	var ada: Dictionary = sim.residents[0]
	hud.refresh(sim)
	await _frames()
	check(not hud._claim_btn.visible, "with one resident there's no claim chip")
	check(not OrderMenus.entries("build", sim).any(func(e): return e.id == "claim"), "and the Build menu doesn't list Claim land")
	for i in 3:
		sim.add_resident("R%d" % i, Sim.TRAVELERS[i][1], sim.nearest_walkable(Sim.rcell(ada) + Vector2i(i + 1, 2)))
	hud.refresh(sim)
	await _frames()
	check(hud._claim_btn.visible and hud._claim_btn.text == "1 land claim", "four residents show \"1 land claim\" (%s)" % hud._claim_btn.text)
	check(OrderMenus.entries("build", sim).any(func(e): return e.id == "claim"), "and the Build menu lists Claim land")
	game.pick_order("build", "claim")
	check(game.tool == "claim", "picking it starts the claim order")
	game._mouse = game._cam.unproject_position(Vector3(sim.w + 3.0, 0, sim.h / 2.0))
	check(game._claim_edge() == "east", "a cursor past the east edge picks the east strip (%s)" % game._claim_edge())
	game._mouse = game._cam.unproject_position(Vector3(-3.0, 0, sim.h / 2.0))
	check(game._claim_edge() == "west", "and one past the west edge, the west")
	game._update_live_overlays()
	check(game._world.live_outlines.size() == 4 and game._hud._hint.text.begins_with("Claim 256 cells of new land to the west"), "all four strips are outlined, and the hint says what a claim gives (%s)" % game._hud._hint.text)
	var w0: int = sim.w
	var before: Vector3 = game._target
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = game._mouse
	game._left_down(e)
	check(game.tool == "" and sim.claims_pending() == 1 and game.selection.get("kind", "") == "site", "a click stakes the strip, and selects the stakes")
	hud.refresh(sim)
	await _frames()
	check(hud._claim_btn.text == "Staking land" and hud._claim_btn.disabled, "the chip says a builder is on it")
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 0), "stick", Tuning.CLAIM_STAKES)
	for i in 90 * Tuning.TPS:
		sim.step()
		if sim.claims_made == 1:
			break
	game._process(0.0)
	check(sim.w == w0 + Tuning.CLAIM_DEPTH and sim.claims_made == 1, "the stakes go in and the village grows west (%d wide)" % sim.w)
	check(is_equal_approx(game._target.x, before.x + Tuning.CLAIM_DEPTH) and is_equal_approx(game._target.z, before.z), "the camera moves with the land: the view stays on the same ground (%s to %s)" % [before, game._target])
	hud.refresh(sim)
	await _frames()
	check(not hud._claim_btn.visible, "the chip goes once the claim is used")
	game.set_tool("")


## Equip in the resident panel lists tools lying about and sends the resident for the chosen one.
func _test_equip(game: Game) -> void:
	game.restart()
	var sim := game.sim
	var hud: Hud = game._hud
	var ada: Dictionary = sim.residents[0]
	game._select(ada)
	hud.refresh(sim)
	await process_frame
	check(not _walk(hud._sel).any(func(n): return n is Button and n.text == "Equip"), "no Equip button while there's no tool to equip")
	var c := Sim.rcell(ada) + Vector2i(1, 0)
	sim.drop_items(c, "stone_pick", 1)
	hud.refresh(sim)
	await process_frame
	var eq: Array = _walk(hud._sel).filter(func(n): return n is Button and n.text == "Equip")
	check(eq.size() == 1, "a pickaxe on the ground brings an Equip button on the Pickaxe row")
	if eq.is_empty():
		return
	eq[0].pressed.emit()
	hud.refresh(sim)
	await process_frame
	var choice: Array = _walk(hud._sel).filter(func(n): return n is Button and n.text.begins_with("Stone pickaxe"))
	check(choice.size() == 1 and choice[0].text.ends_with("on the ground"), "Equip lists it, with its uses and where it is")
	if choice.is_empty():
		return
	choice[0].pressed.emit()
	check(ada.direct != null and ada.direct.kind == "equip", "choosing it sends Ada to get it")
	for i in 5 * Tuning.TPS:
		sim.step()
	check(ada.pick != null and ada.pick.type == "stone_pick" and ada.kept.pick, "she equips it and keeps it")


## The meadow's signpost (issues #136, #137): with no board it says one would know what's past it;
## with one, clicking it opens the meadow's adventure on the board, and the board opens on the
## adventures list. Nobody is sent off the map from their own panel any more.
func _test_meadow(game: Game) -> void:
	game.restart()
	var sim := game.sim
	var hud: Hud = game._hud
	var ada: Dictionary = sim.residents[0]
	var sign := sim.meadow_sign()
	var p: Vector2 = game._cam.unproject_position(Vector3(sign.x + 0.3, 1.0, sign.y + 0.5))
	var hit = game._pick(p)
	check(hit != null and hit.kind == "meadow", "the signpost can be clicked")
	game._select(hit)
	hud.refresh(sim)
	await process_frame
	check(_walk(hud._sel).any(func(n): return n is Label and n.text.begins_with("An expedition board would have word")), "with no board, its panel says a board would know what's past it")
	check(not game.planner_open, "and there's no planner to open")
	game._select(ada)
	hud.refresh(sim)
	await process_frame
	check(not _walk(hud._sel).any(func(n): return n is Button and n.text.contains("to the meadow")), "Ada's panel has no Send to the meadow")
	var spot := Vector2i(sim.w / 2 + 3, sim.h / 2 + 3)
	var b := sim.place_site("board", spot)
	b.stage = 1
	b.done = true
	sim._on_site_done(b)
	sim.rev += 1
	game._select(game._pick(p))
	hud.refresh(sim)
	await process_frame
	check(game.planner_open and game.adventure == Meadow.ID and game.plan.dest == Meadow.ID, "with a board, clicking the signpost opens the meadow's adventure")
	check(_walk(hud._plan_box).any(func(n): return n is Label and n.text == "Meadow"), "its site report and planner")
	var loc: Array = _walk(hud._plan_box).filter(func(n): return n is Button and n.get_meta("label", "").begins_with("Location: "))
	check(loc.size() == 1 and "Meadow" in loc[0].text, "the board has a Location dropdown showing the meadow (%s)" % [loc.map(func(n): return n.text)])
	if loc.is_empty():
		return
	loc[0].pressed.emit()
	hud.refresh(sim)
	await process_frame
	var rows: Array = _walk(hud._loc_list).filter(func(n): return n is Button and n.has_meta("label") and not n.is_queued_for_deletion())
	check(rows.map(func(n): return n.get_meta("label")) == ["Adventure: Old mine", "Adventure: Meadow"], "its list has both destinations (%s)" % [rows.map(func(n): return n.get_meta("label"))])
	var view := hud.get_viewport().get_visible_rect()
	check(view.encloses(hud._loc_drop.get_global_rect()), "the open list lies inside the window (%s in %s)" % [hud._loc_drop.get_global_rect(), view])
	for far in [Vector2(-500, -500), Vector2(view.end.x + 500, view.end.y + 500)]:
		hud._place_drop(hud._loc_drop, far)
		check(view.encloses(Rect2(hud._loc_drop.position, hud._loc_drop.get_combined_minimum_size())), "a list put at %s is pulled back inside the window" % [far])
	hud.refresh(sim)
	rows[0].pressed.emit()
	hud.refresh(sim)
	await process_frame
	check(game.adventure == OldMine.ID and game.plan.dest == OldMine.ID and not hud._loc_drop.visible, "choosing the old mine shows its planner and closes the list")
	# The cargo priority list (issue #185): rows to turn on and off, reorder and set amounts.
	var by_label := func(label: String) -> Button:
		for n in _walk(hud._plan_box):
			if n is Button and n.get_meta("label", "") == label and not n.is_queued_for_deletion():
				return n
		return null
	check(game.plan.list.map(func(r): return r.item) == ["coal", "cobble"] and by_label.call("Bring back: Coal") != null, "the planner lists the old mine's cargo: coal, then cobblestone")
	by_label.call("Cobblestone up").pressed.emit()
	check(game.plan.list.map(func(r): return r.item) == ["cobble", "coal"], "↑ moves cobblestone above coal")
	hud.refresh(sim)
	await process_frame
	by_label.call("Cobblestone more").pressed.emit()
	check(game.plan.list[0].n == 1 and game.plan.target == {"item": "cobble", "n": 1}, "+ sets an amount, and the old target follows the list")
	by_label.call("Cobblestone less").pressed.emit()
	check(game.plan.list[0].n == 0, "− back to as much as fits")
	hud.refresh(sim)
	await process_frame
	by_label.call("Bring back: Cobblestone").pressed.emit()
	check(not game.plan.list[0].on and game.plan.target.item == "coal", "a row can be turned off")
	hud.refresh(sim)
	await process_frame
	check(_walk(hud._plan_box).any(func(n): return n is Label and n.text == "Max" and not n.is_queued_for_deletion()), "a row with no amount reads Max")
	# Clear the level (issue #188): a toggle that makes every amount Max.
	var cl: Array = _walk(hud._plan_box).filter(func(n): return n is Button and n.text == "Clear the level" and not n.is_queued_for_deletion())
	check(cl.size() == 1 and not game.plan.clear, "the old mine's planner has a Clear the level toggle, off at first")
	cl[0].pressed.emit()
	hud.refresh(sim)
	await process_frame
	check(game.plan.clear and Sim.list_text(game.plan) == "clear the level", "turning it on makes the plan clear the level")
	check(_walk(hud._plan_box).filter(func(n): return n is Button and n.text == "+" and n.get_meta("label", "") in ["Coal more", "Cobblestone more"] and not n.is_queued_for_deletion()).all(func(n): return n.disabled), "and the amounts are fixed at Max")
	game.plan_clear_toggle()


func _frames(n := 3) -> void:
	for i in n:
		await process_frame


func _stuck_buttons(hud: Hud) -> Array:
	return _walk(hud._stuck).filter(func(n): return n is Button and not n.is_queued_for_deletion())


## Issue #77: the stuck list's two tiers, folding, and opening again for a new blocker.
func _test_stuck_list(game: Game) -> void:
	var sim := game.sim
	var hud: Hud = game._hud
	var world: WorldView = game._world
	game.set_speed(0)
	var ada: Dictionary = sim.residents[0]
	var bench := sim.place_site("bench", Sim.rcell(ada) + Vector2i(3, 0))
	bench.stage = 1
	bench.done = true
	ada.pick = {"type": "wood_pick", "tier": 1, "dur": 5}
	var smith := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], sim.nearest_walkable(Sim.rcell(ada) + Vector2i(-2, 0)))
	sim.set_role(smith, "toolsmith")  # a toolsmith keeps spares (issues #91, #134)
	var tsb := sim.place_site("toolsmith_bench", Sim.rcell(ada) + Vector2i(-3, 3))  # from his own bench (issue #184)
	tsb.stage = 1
	tsb.done = true
	sim.assign_workstations()
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 1), "cobble", 3)
	for i in Tuning.TPS:
		sim.step()
	hud.refresh(sim)
	await _frames()
	var texts: Array = _stuck_buttons(hud).map(func(b): return b.text)
	check(hud._stuck_panel.visible and texts.any(func(t): return t.begins_with("1 waiting")), "a short standing order shows as one waiting line: %s" % [texts])
	check(not texts.any(func(t): return "Stuck" in t or "Planks needs" in t), "with nothing blocked there's no Stuck header, and the waiting tier starts closed")
	check(world._flags.get_child_count() == 0, "a waiting order raises no flag on the map")
	_stuck_buttons(hud).filter(func(b): return "waiting" in b.text)[0].pressed.emit()
	hud.refresh(sim)
	await _frames()
	var spare: Array = _stuck_buttons(hud).filter(func(b): return "Planks needs" in b.text)  # the spare's sticks' planks, made automatically (issue #182)
	check(spare.size() == 1 and spare[0].icon == null, "the waiting line opens to its entries, dim and without a flag")
	var spot := Vector2i(-1, -1)
	for d in range(4, 20):  # open ground for a house, so its walls are what it's missing
		for c in [Sim.rcell(ada) + Vector2i(-d, -d), Sim.rcell(ada) + Vector2i(d, -d), Sim.rcell(ada) + Vector2i(-d, d)]:
			if spot.x < 0 and sim.placement_check("house", c) == "":
				var open := true
				for x in range(-1, 6):
					for y in range(-1, 6):
						var p: Vector2i = c + Vector2i(x, y)
						open = open and sim.walkable(p) and not sim.items.has(p)
				if open:
					spot = c
	var house := sim.place_site("house", spot)
	house.stage = 1
	sim.compute_stuck()
	hud.refresh(sim)
	await _frames()
	var heads: Array = _stuck_buttons(hud).filter(func(b): return b.text.begins_with("Stuck (1)"))
	check(heads.size() == 1, "a blocker brings the Stuck header")
	check(_stuck_buttons(hud).any(func(b): return "Walls need" in b.text and b.icon == MarkTextures.flag()), "a blocker's entry carries the yellow flag")
	check(world._flags.get_child_count() == 1, "and one flag on the map")
	heads[0].pressed.emit()
	hud.refresh(sim)
	await _frames()
	check(not hud.stuck_open and _stuck_buttons(hud).size() == 1 and hud._stuck_panel.get_global_rect().size.x < 250, "the header folds the list into a small chip")
	sim.compute_stuck()
	hud.refresh(sim)
	await _frames()
	check(not hud.stuck_open, "it stays folded while nothing new gets stuck")
	ada.note = {"text": "Can’t reach the stockpile", "until": sim.tick + 1000}
	sim.compute_stuck()
	hud.refresh(sim)
	await _frames()
	check(hud.stuck_open, "a new blocker opens it again")
	var starving: Array = _stuck_buttons(hud).filter(func(b): return "Can’t reach" in b.text)
	check(starving.size() == 1 and starving[0].icon == hud._swatch_tex(ada.shirt), "a resident's entry carries their tunic swatch")
	# A site's entry made later goes below Ada's, though the sim lists sites before residents.
	for i in 5:
		sim.step()
	ada.note = {"text": "Can’t reach the stockpile", "until": sim.tick + 1000}
	house.stage = 2
	sim.compute_stuck()
	hud.refresh(sim)
	await _frames()
	var order: Array = _stuck_buttons(hud).map(func(b): return b.text)
	var at_ada := order.find(order.filter(func(t): return "Can’t reach" in t)[0])
	var at_house := order.find(order.filter(func(t): return t.begins_with("House")).back())
	check(at_ada < at_house, "the longest-stuck entry comes first: %s" % [order])
	ada.note = null


## Issue #79: residents told apart by tunic, with a name tag, a heavier ring and swatches.
func _test_resident_marks(game: Game) -> void:
	var sim := game.sim
	var hud: Hud = game._hud
	var world: WorldView = game._world
	var ada: Dictionary = sim.residents[0]
	check(ada.shirt == Sim.ADA_TUNIC, "Ada wears her tunic")
	var node: Node3D = world._people[ada.id]
	var tag: Label3D = node.get_node("Body/Tag")
	game.selection = {}
	game._mouse = Vector2(-100, -100)
	await _frames()
	check(not tag.visible, "no name tag on an unselected resident away from the mouse")
	game._mouse = game._cam.unproject_position(Vector3(ada.pos.x + 0.5, 0.6, ada.pos.y + 0.5))
	await _frames()
	check(tag.visible and tag.text == "Ada" and tag.no_depth_test, "hovering a resident shows their name over everything")
	game._mouse = Vector2(-100, -100)
	game.selection = {"kind": "res", "ids": [ada.id]}
	hud.refresh(sim)
	await _frames()
	check(tag.visible, "a selected resident keeps their name tag")
	var ring: Node3D = node.get_node("Ring")
	check(ring.visible and ring.get_child_count() == 2, "the selection ring is a chalk band on a dark under-stroke")
	check(_walk(hud._sel).any(func(n): return n is TextureRect and n.texture == hud._swatch_tex(ada.shirt)), "the resident panel shows Ada's swatch beside her name")
	hud.add_toast({"text": "Ada is now level 2 at Mine.", "res_id": ada.id, "site_id": 0})
	var toast: Control = hud._toasts.get_child(hud._toasts.get_child_count() - 1)
	check(toast.get_child(0).get_child(0) is TextureRect, "a toast about a resident starts with their swatch")
	var tunics := {}
	for t in Sim.TRAVELERS:
		tunics[t[1]] = true
	tunics[Sim.ADA_TUNIC] = true
	check(tunics.size() == Sim.TRAVELERS.size() + 1, "every resident's tunic is different")


## Issue #81: once the founding is done the goals panel folds to a chip, and saves are labelled
## with village facts, including saves made before, which said only "Founding complete".
func _test_after_the_founding(game: Game) -> void:
	var sim := game.sim
	var hud: Hud = game._hud
	hud.refresh(sim)
	await _frames()
	check(_walk(hud._goals).any(func(n): return n is Label and n.text == "The founding"), "during the founding the goals panel shows the checklist")
	var saved := sim.stats.duplicate(true)
	sim.stats.felled = 1
	sim.stats.pick_crafted = true
	sim.stats.axe_crafted = true
	sim.stats.meadow_wool = true
	sim.stats.built = {"bench": true, "fireplace": true, "board": true, "chopping_block": true}
	sim.stats.broken_boulders = 1
	sim.stats.sheep_hunted = 1
	sim.stats.houses = 2
	sim.stats.traveler_home = true
	sim.stats.division = true
	sim.zone[sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(2, 2))] = true
	var bench := sim.place_site("bench", sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(4, -3)))
	bench.stage = 1
	bench.done = true
	check(Goals.current(sim) < 0, "every founding step is done")
	hud.refresh(sim)
	await _frames()
	var labels: Array = _walk(hud._goals).filter(func(n): return n is Label and not n.is_queued_for_deletion()).map(func(l): return l.text)
	check(labels.size() == 5 and labels[0] == "The village" and labels[2] == "1  Paint a farm plot", "the village chapter follows the founding, with a why (%s)" % [labels])
	# The book opens from the panel's Book button, shows a building's page, and the "?" on a bench opens it (issue #198).
	var book_btn: Array = _walk(hud._goals).filter(func(n): return n is Button and n.text == "Book" and not n.is_queued_for_deletion())
	check(book_btn.size() == 1, "the goals panel has a Book button")
	book_btn[0].pressed.emit()
	hud.refresh(sim)
	await _frames()
	check(game.book_open and hud._book_panel.visible and not hud._goals_panel.visible, "it opens the book in the goals panel's place")
	var tabs: Array = _walk(hud._book).filter(func(n): return n is Button and not n.is_queued_for_deletion()).map(func(b): return b.text)
	check("Goals" in tabs and "Crafting bench" in tabs and "Fireplace" in tabs and "Expedition board" in tabs, "with a page for each building known (%s)" % [tabs])
	check(not "The road" in tabs, "and none for the road before a party has been to the mine")
	game.open_book("bench")
	hud.refresh(sim)
	await _frames()
	var text: Array = _walk(hud._book).filter(func(n): return n is Label and not n.is_queued_for_deletion()).map(func(l): return l.text)
	check("Crafting bench" in text and "Who works it" in text and "A crafter, or Ada" in text, "the bench's page says who works it")
	game.open_book("goals", false)
	game.selection = {"kind": "site", "id": bench.id}
	hud.refresh(sim)
	await _frames()
	var about: Array = _walk(hud._sel).filter(func(n): return n is Button and n.text.begins_with("?") and not n.is_queued_for_deletion())
	check(about.size() == 1, "a selected bench has a ? button")
	about[0].pressed.emit()
	check(game.book_open and game.book_page == "bench", "it opens the bench's page")
	game.open_book("goals", false)
	game.selection = {}
	# Chapter two done: the chip.
	sim.stats.meals_cooked = 1
	sim.stats.ore_home = true
	sim.paint_farm(Rect2i(sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(-6, 6)), Vector2i(2, 2)))
	for st in sim.sites:
		if st.tpl == "bench":
			st.done = true
	var made := 0
	for tpl in ["chopping_block", "mason_bench"]:
		var s2 := sim.place_site(tpl, sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(6 + made * 2, 4)))
		s2.done = true
		s2.worker = sim.residents[0].id
		made += 1
	check(Goals.village_current(sim) < 0, "every village step is done")
	hud.refresh(sim)
	await _frames()
	labels = _walk(hud._goals).filter(func(n): return n is Button and not n.is_queued_for_deletion()).map(func(l): return l.text)
	check(labels == ["The village  √"] and hud._goals_panel.get_global_rect().size.x < 200, "afterwards it folds to a small chip that opens the book (%s)" % [labels])
	check(Goals.progress_text(sim) == Goals.village_text(sim) and Goals.village_text(sim).begins_with("%d resident" % sim.residents.size()), "the save label is the village's facts: %s" % Goals.progress_text(sim))
	check(game.save_slot(3) == "" and game.read_slots()[2].summary == Goals.village_text(sim), "a new save carries that label")
	var old: Dictionary = SaveFormat.read(game._slot_path(3)).data
	old.summary = "Founding complete"
	SaveFormat.write(game._slot_path(3), old)
	check(game.read_slots()[2].summary == Goals.village_text(sim), "an older \"Founding complete\" save is listed by its facts too")
	sim.stats = saved
	sim.zone.clear()


## Issue #80: no HUD text is smaller than the type scale's caption, and the interface size setting
## cycles 90 → 100 → 115 → 130%, scales the HUD and is saved beside the key bindings.
func _test_type_and_ui_scale(game: Game) -> void:
	var hud: Hud = game._hud
	game.jobs_board_open = true
	game.craft_menu_open = game.craft_bench() != null
	game.selection = {"kind": "res", "ids": [game.sim.residents[0].id]}
	hud.refresh(game.sim)
	await _frames()
	var small: Array = _walk(hud._root).filter(func(n): return n is Label and n.is_visible_in_tree() and n.get_theme_font_size("font_size") < Palette.CAPTION)
	check(small.is_empty(), "no HUD text is under %d px (%s)" % [Palette.CAPTION, small.map(func(l): return "%s=%d" % [l.text.left(12), l.get_theme_font_size("font_size")])])
	var sizes := {}
	for n in _walk(hud._root):
		if n is Label and n.is_visible_in_tree():
			sizes[n.get_theme_font_size("font_size")] = true
	check(sizes.keys().all(func(z): return z in [Palette.CAPTION, Palette.BODY, Palette.HEADING, Palette.TITLE]), "every size is on the type scale (%s)" % [sizes.keys()])
	game.jobs_board_open = false
	game.craft_menu_open = false
	check(game.ui_scale == 1.0 and game.get_window().content_scale_factor == 1.0, "the interface starts at 100%")
	game.open_menu("main")
	var size_btn: Array = _walk(game._menu).filter(func(n): return n is Button and n.text.begins_with("Interface size") and not n.is_queued_for_deletion())
	check(size_btn.size() == 1 and size_btn[0].text == "Interface size: 100%", "the menu offers the interface size")
	size_btn[0].pressed.emit()
	check(game.ui_scale == 1.15 and is_equal_approx(game.get_window().content_scale_factor, 1.15), "clicking it goes to 115%, and the HUD is drawn bigger")
	var cfg := ConfigFile.new()
	check(cfg.load(game._ui_settings_path()) == OK and cfg.get_value("ui", "scale") == 1.15, "the size is saved with the settings")
	check(game._ui_settings_path().begins_with(game.keys_path.get_base_dir()), "in the test settings folder, beside the keys")
	for i in 3:
		game.set_ui_scale(game.next_ui_scale())
	check(game.ui_scale == 1.0, "it cycles 130% round to 90% and back to 100%")
	game.close_menu()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game._ui_settings_path()))


## Issue #101: switching between the village and the old mine, with a camera for each map that
## survives saving and loading; orders go to the map in view, and other-map reasons switch to it.
func _test_maps(game: Game) -> void:
	game.restart()
	var sim := game.sim
	var hud: Hud = game._hud
	var mine := sim.get_map(OldMine.ID)
	hud.refresh(sim)
	check(not hud._maps.visible and game.known_maps() == ["village"], "no switcher until a site is known")
	_key(game, KEY_TAB)
	check(game.view_map == "village", "Tab does nothing with only the village known")
	mine.known = true
	hud.refresh(sim)
	await _frames()
	var names: Array = hud._maps.get_children().filter(func(b): return b is Button and not b.is_queued_for_deletion()).map(func(b): return b.text)
	check(hud._maps.visible and names == ["Village", "Old mine"], "the switcher shows Village and Old mine (%s)" % [names])
	var village_cam: Vector3 = game._target
	game.selection = {"kind": "res", "ids": [sim.residents[0].id]}
	_key(game, KEY_TAB)
	check(game.view_map == OldMine.ID and game._world.map_id == OldMine.ID, "Tab switches to the old mine")
	check(game.selection.is_empty(), "switching clears the selection")
	check(Vector2(game._target.x, game._target.z).distance_to(Vector2(mine.entrance)) < 8.0, "the mine opens near its entrance")
	await _frames()
	hud.refresh(sim)
	check(game._world._built_map == OldMine.ID, "the world view draws the mine")
	check(not hud._tool_btns.paint.visible and not hud._tool_btns.build.visible and hud._tool_btns.gather.visible, "on the mine, the toolbar offers Gather but not Paint or Build")
	game.set_tool("stock")
	check(game.tool == "", "stockpile painting is for the village")
	game._target = Vector3(9, 0, 9)
	game._place_camera()
	var mine_cam: Vector3 = game._target
	_key(game, KEY_TAB)
	check(game.view_map == "village" and game._target == village_cam, "back in the village, its camera is where it was left")
	_key(game, KEY_TAB)
	check(game.view_map == OldMine.ID and game._target == mine_cam, "and the mine's camera is where it was left")
	# Orders given on the mine's view go to the mine.
	game.set_tool("mine")
	var a: Vector2 = game._cam.unproject_position(Vector3(4, 0, 6))
	var b: Vector2 = game._cam.unproject_position(Vector3(9, 0, 10))
	_mouse(game, "move", a)
	_mouse(game, "down", a)
	_mouse(game, "move", b)
	_mouse(game, "up", b)
	game.set_tool("")
	check(mine.boulders.any(func(o): return o.des) and sim.maps.village.boulders.all(func(o): return not o.des) and sim.map_id == "village", "a Mine drag on the mine's view marks the mine, not the village")
	# Save on the mine; each camera comes back.
	check(game.save_slot(1) == "", "saved with the mine in view")
	game.switch_map("village")
	game._target = Vector3(20, 0, 20)
	check(game.load_slot(1) == "", "and loaded")
	check(game.view_map == OldMine.ID and game._target == mine_cam, "loading brings back the mine's view and camera")
	game.switch_map("village")
	check(game._target == village_cam, "and the village's camera")
	# A party on the other map: the dim line, and reasons and toasts that jump there.
	sim = game.sim
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Sim.rcell(sim.residents[0]) + Vector2i(1, 0))
	sim.move_to_map(tomas, OldMine.ID, sim.get_map(OldMine.ID).entrance)
	hud.refresh(sim)
	check(hud._party_panel.visible and hud._party.text.begins_with("Party at the old mine: "), "a dim line says the party is at the old mine (%s)" % hud._party.text)
	hud._party.pressed.emit()
	check(game.view_map == OldMine.ID, "clicking it switches to the mine")
	game.switch_map("village")
	game.focus_on("res", tomas.id)
	check(game.view_map == OldMine.ID and game.selection.get("ids", []) == [tomas.id], "going to a resident on the mine switches there first")
	game.switch_map("village")
	tomas.note = {"text": "Can’t reach this boulder", "until": sim.tick + 200}
	sim.compute_stuck()
	hud.refresh(sim)
	await _frames()
	var entry: Array = _stuck_buttons(hud).filter(func(x): return "Tomas" in x.text)
	check(not entry.is_empty(), "Tomas's reason is in the stuck list")
	if not entry.is_empty():
		entry[0].pressed.emit()
		check(game.view_map == OldMine.ID, "clicking it switches to the mine")
	game.switch_map("village")
	sim.move_to_map(tomas, "village", Sim.rcell(sim.residents[0]) + Vector2i(1, 0))
	tomas.note = null


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
	_test_order_menus(game)
	_test_menu_button(game)
	await _test_work_area_painting(game)
	await _test_redstone_panels(game)
	await _test_panel_keys(game)
	await _test_mineshaft_button(game)
	_test_key_migration()
	await _test_craft_menu(game)
	await _test_right_click_never_silent(game)
	await _test_farm_tool(game)
	await _test_fireplace(game)
	await _test_jobs_grid(game)
	await _test_land_claims(game)
	await _test_equip(game)
	await _test_toasts(game)
	_test_headers(game)
	await _test_skip_ahead(game)
	await _test_message_log(game)
	_test_fade_for_blueprints(game)
	await _test_needs_you(game)
	await _test_autosave(game)
	_test_glyphs()
	_test_tallies(game)
	await _test_meadow(game)
	await _test_quit(game, menu)
	game.open_menu("main")
	game.restart()
	check(game.sim.tick == 0 and game.sim.residents.size() == 1 and not menu.visible, "Start over begins a fresh game")
	await _test_stuck_list(game)
	await _test_resident_marks(game)
	await _test_after_the_founding(game)
	await _test_type_and_ui_scale(game)
	await _test_maps(game)
	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	print("%s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures else 0)


## A cell or area of the original 18×18 opening, in today's map (issue #52 moved it to the middle).
static func at(x: int, y: int) -> Vector2i:
	return Vector2i(x, y) + Tuning.OPENING_OFFSET


static func area(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(Vector2i(x, y) + Tuning.OPENING_OFFSET, Vector2i(w, h))
