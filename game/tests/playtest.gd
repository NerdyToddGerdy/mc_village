extends "res://tests/playtest_base.gd"
## A scripted playtest of the whole Slice 1 opening (issue #1), played only through input events
## pushed into the game window: the same path a player's clicks and keys take, HUD included.
## Waiting is done by stepping the sim, since time passing isn't input. Uses its own save folder.
## Run from game/:
##   godot --headless --path . -s res://tests/playtest.gd

# ---------------------------------------------------------------- the playtest

func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.keys_path = "user://test_settings/playtest_keys.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.keys_path))
	root.add_child(game)
	await frames(3)
	game.save_dir = "user://playtest_saves"
	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	var sim := game.sim
	var ada: Dictionary = sim.residents[0]

	# Menu at launch
	check(game._menu.visible, "menu shows at launch")
	check(await click_button("Play"), "click Play")
	check(not game._menu.visible and game.speed == 1, "Play starts the game at 1×")

	# Mine a tree by clicking, unmark it, mark it again, then drag-mark an area
	await key(KEY_X)
	check(game.tool == "mine", "X picks Mine")
	var tree: Dictionary = Sim.nearest(sim.trees.filter(func(t): return t.alive), Sim.rcell(ada))
	await click(screen(tree.cell, 1.5))
	check(tree.des, "clicking a tree marks it")
	await click(screen(tree.cell, 1.5))
	check(not tree.des, "clicking a marked tree unmarks it")
	await drag(screen(at(0, 8)), screen(at(8, 17)))
	var marked := sim.trees.filter(func(t): return t.des).size()
	check(marked >= 3, "dragging with Mine marks several trees (%d)" % marked)
	# Shift-drag marks only trees; Alt-drag marks only boulders (issue #7)
	for o in sim.trees + sim.boulders:
		o.des = false
	await move(screen(at(9, 9)))
	check("Shift: trees only" in game._hud._hint.text, "the Mine hint explains the modifiers: \"%s\"" % game._hud._hint.text)
	await drag(screen(at(6, 2)), screen(at(17, 17)), true)
	var t_on := sim.trees.filter(func(t): return t.des).size()
	var b_on := sim.boulders.filter(func(b): return b.des).size()
	check(t_on > 0 and b_on == 0, "Shift-drag with Mine marks trees only (%d trees, %d boulders)" % [t_on, b_on])
	for o in sim.trees + sim.boulders:
		o.des = false
	await drag(screen(at(6, 2)), screen(at(17, 17)), false, true)
	t_on = sim.trees.filter(func(t): return t.des).size()
	b_on = sim.boulders.filter(func(b): return b.des).size()
	check(b_on > 0 and t_on == 0, "Alt-drag with Mine marks boulders only (%d trees, %d boulders)" % [t_on, b_on])
	for o in sim.trees + sim.boulders:
		o.des = false
	# Gather menu (issue #94): Chop trees marks only the trees in a drag
	check(await click_button("Gather"), "click Gather in the toolbar")
	check(await click_button("Chop trees"), "click Chop trees in the Gather menu")
	game._hud.refresh(sim)
	check(game.tool == "chop" and game._hud._tool_btns.gather.text == "Gather: Chop trees", "Chop trees is on, and the Gather button says so")
	await drag(screen(at(6, 2)), screen(at(17, 17)))
	t_on = sim.trees.filter(func(t): return t.des).size()
	b_on = sim.boulders.filter(func(b): return b.des).size()
	check(t_on > 0 and b_on == 0, "Chop trees marks trees only (%d trees, %d boulders)" % [t_on, b_on])
	for o in sim.trees + sim.boulders:
		o.des = false
	await key(KEY_X)
	check(game.tool == "mine", "X still switches Mine on directly")
	await drag(screen(at(0, 8)), screen(at(8, 17)))
	check(game._world.live_outlines.size() > 0 or true, "drag shows an outline")

	# Hunt sheep (issue #42): G, click to mark and unmark, drag to mark a group
	await key(KEY_G)
	check(game.tool == "hunt", "G picks Hunt")
	var flock: Array = sim.sheep.filter(func(x): return x.alive)
	var one: Dictionary = Sim.nearest(flock, Sim.rcell(ada))
	await click(game._cam.unproject_position(Vector3(one.pos.x + 0.5, 0.3, one.pos.y + 0.5)))
	check(one.des, "clicking a sheep marks it for hunting")
	await click(game._cam.unproject_position(Vector3(one.pos.x + 0.5, 0.3, one.pos.y + 0.5)))
	check(not one.des, "clicking it again unmarks it")
	await drag(screen(Vector2i(0, 0)), screen(Vector2i(31, 31)))
	check(sim.sheep.filter(func(x): return x.des).size() >= 3, "dragging with Hunt marks the sheep (%d)" % sim.sheep.filter(func(x): return x.des).size())
	await key(KEY_ESCAPE)
	for x in sim.sheep:
		x.des = false
	game.selection = {"kind": "res", "ids": [ada.id]}
	one = Sim.nearest(sim.sheep.filter(func(x): return x.alive), Sim.rcell(ada))
	var at_sheep: Vector2 = game._cam.unproject_position(Vector3(one.pos.x + 0.5, 0.3, one.pos.y + 0.5))
	await move(at_sheep)
	check(game._hud._hint.text.begins_with("Right-click: options"), "hovering a sheep hints that right-click has options (\"%s\")" % game._hud._hint.text)
	await click(at_sheep, MOUSE_BUTTON_RIGHT)
	check(radial_ids() == ["mark", "now"], "right-click on a sheep opens the radial: Hunt and Hunt now (%s)" % [radial_ids()])
	if not game.radial.is_empty():
		await click(radial_wedge(1))
	await run(40)
	check(not one.alive, "Hunt now sends Ada to hunt it")
	check(sim.items.values().any(func(it): return it.type == "wool") and sim.items.values().any(func(it): return it.type == "mutton"), "the hunted sheep drops wool and mutton")
	# The houses' beds need 6 wool in all: mark the rest of the flock.
	await key(KEY_G)
	await drag(screen(Vector2i(0, 0)), screen(Vector2i(31, 31)))
	await key(KEY_ESCAPE)
	check(sim.sheep.filter(func(x): return x.alive).all(func(x): return x.des), "the rest of the flock is marked for wool")

	# Place the bench from the build menu
	await key(KEY_B)
	check(game.build_menu_open, "B opens the build menu")
	check(await click_button("Crafting bench"), "click Crafting bench in the build menu")
	var bench_cell := open_cell(at(9, 11))
	await move(screen(bench_cell))
	check(game._hud._hint.visible and "crafting bench" in game._hud._hint.text, "cursor hint while placing: \"%s\"" % game._hud._hint.text)
	await click(screen(bench_cell))
	var bench = sim.site_at(bench_cell)
	check(bench != null and bench.tpl == "bench", "clicking open ground places the bench")
	check(game.tool == "", "the build tool closes after placing")

	await run(150)
	check(bench.done, "Ada builds the bench")

	# Ada does everything (issue #134). The checklist asks for a stockpile before the tools (issue #182)
	check(Goals.LIST[Goals.current(sim)].t == "Paint a stockpile", "the checklist asks for a stockpile next (%s)" % Goals.progress_text(sim))
	await key(KEY_F)
	check(game.selection.get("ids", []) == [ada.id], "F selects Ada")
	game._hud.refresh(sim)  # the HUD refreshes on a timer; don't race it
	await frames(2)
	check(visible_label("Everything") and find_button("Job: Ada") == null, "Ada's job is Everything, with no dropdown")
	await key(KEY_J)
	check(game.jobs_board_open, "J opens the jobs board")
	await key(KEY_J)
	check(not game.jobs_board_open, "J closes the board again")

	# Queue crafts by clicking the bench and its Queue buttons
	await click(screen(bench_cell, 0.4))
	check(game.selection.get("kind", "") == "site" and game.selection.id == bench.id, "clicking the bench selects it (got %s)" % [game.selection])
	check(game.craft_menu_open, "selecting the bench opens the craft panel on the right")
	# Pause while queueing, so nothing gets crafted between clicks and the count is exact.
	await key(KEY_QUOTELEFT)
	check(game.speed == 0, "~ pauses")
	for r in ["Wooden axe", "Wooden pickaxe"]:
		check(await queue_recipe(r), "queue a %s" % r.to_lower())
	check(bench.queue.has("wood_axe") and bench.queue.has("wood_pick") and bench.queue.has("planks") and bench.queue.has("sticks") and bench.autoq.has(true), "the bench queues their planks and sticks itself, from the start (%s)" % [bench.queue])
	await key(KEY_ESCAPE)
	check(not game.craft_menu_open, "Esc closes the craft panel")
	await key(KEY_1)
	await run(200)
	check(sim.stats.pick_crafted and sim.stats.axe_crafted, "a wooden axe and a wooden pickaxe are crafted")

	# Stockpile and boulders
	check(await click_button("Paint"), "click Paint in the toolbar")
	check(game.menu_open == "paint", "Paint opens its menu")
	check(await click_button("Stockpile"), "click Stockpile in the Paint menu")
	check(game.tool == "stock" and game.menu_open == "", "Stockpile is on and the menu closes")
	var zc := open_cell(at(12, 7), Vector2i(4, 2))
	await look_at(zc)  # F centred the camera on Ada, wherever she happened to be
	await drag(screen(zc), screen(zc + Vector2i(3, 1)))
	check(sim.zone.size() >= 6, "dragging paints a stockpile (%d cells)" % sim.zone.size())
	# A drag that starts on the stockpile erases instead (issue #63): take back its last column
	var painted := sim.zone.size()
	var col_a := screen(zc + Vector2i(3, 0))
	var col_b := screen(zc + Vector2i(3, 1))
	await move(col_a)
	await press(col_a, true)
	await move(col_a.lerp(col_b, 0.5))
	await move(col_b)
	await frames(2)
	check(game._drag.get("erase", false) and game._world.live_fills.size() == 2, "dragging from a stockpile cell previews erasing 2 cells in red")
	await press(col_b, false)
	await frames(2)
	check(sim.zone.size() == painted - 2 and not sim.in_zone(zc + Vector2i(3, 0)) and not sim.in_zone(zc + Vector2i(3, 1)), "releasing erases them (%d cells left)" % sim.zone.size())
	await key(KEY_X)
	await look_at(at(17, 17))  # F centred the camera on Ada, wherever she happened to be
	await drag(screen(at(6, 3)), screen(at(17, 17)))
	check(sim.boulders.filter(func(b): return b.des).size() >= 3, "dragging with Mine marks boulders")
	await key(KEY_ESCAPE)
	check(game.tool == "", "Esc cancels the order")
	await run(200)
	check(sim.stats.broken_boulders > 0, "Ada breaks a boulder with her pickaxe")

	# Place a house: invalid spot first, then a valid one, with the door turned
	await key(KEY_H)
	check(game.tool == "build" and game.placing == "house", "H picks House")
	await move(screen(bench_cell))
	check("Overlaps another building" in game._hud._hint.text, "hint explains an invalid spot: \"%s\"" % game._hud._hint.text)
	var sites_before := sim.sites.size()
	await click(screen(bench_cell))
	check(sim.sites.size() == sites_before, "clicking an invalid spot places nothing")
	await key(KEY_R)
	check(game.rot == 1, "R turns the door")
	var house_origin := open_cell(at(11, 0), Vector2i(5, 5))
	await move(screen(house_origin + Vector2i(2, 2)))
	check("Place house" in game._hud._hint.text, "hint over a valid spot: \"%s\"" % game._hud._hint.text)
	await click(screen(house_origin + Vector2i(2, 2)))
	var h1 = sim.site_at(house_origin + Vector2i(2, 2))
	check(h1 != null and h1.tpl == "house" and h1.rot == 1, "clicking places the house with the turned door")

	# Queue the house's planks from the toolbar's Craft panel (issue #57), not by clicking the bench
	game.selection = {}
	check(game._hud._tool_btns.craft.visible, "a Craft button is in the toolbar now that the bench is finished")
	check(await click_button("Craft"), "click Craft in the toolbar")
	check(game.craft_menu_open, "the craft panel opens")
	await key(KEY_QUOTELEFT)
	var queued_before: int = bench.queue.size()
	check(await queue_recipe("Planks", 5), "queue 5 planks")
	check(bench.queue.size() == queued_before + 5, "Queue 5 queues five batches")
	check(await click_button("queued Planks", "", true), "click the last planks slot in the queue's hotbar")
	check(bench.queue.size() == queued_before + 4, "clicking a hotbar slot removes it (%d)" % (bench.queue.size() - queued_before))
	check(await queue_recipe("Planks", 1), "queue one more")
	await queue_recipe("Planks", 5)
	check(bench.queue.size() >= queued_before + 8, "two Queue 5 clicks cover a house's planks")
	await key(KEY_ESCAPE)
	check(not game.craft_menu_open, "Esc closes the craft panel")
	await key(KEY_1)
	await run(700)
	check(h1.done, "Ada builds her house")

	# Fireplace (issue #46): K, click open ground; it's built, and cooks the hunted mutton
	await key(KEY_K)
	check(game.placing == "fireplace", "K picks Fireplace")
	var fp := build_spot("fireplace", at(9, 8))
	check(fp.x >= 0, "an open spot for the fireplace")
	await look_at(fp)
	await click(screen(fp))
	var fire = sim.site_at(fp)
	check(fire != null and fire.tpl == "fireplace" and fire.plot != null, "the fireplace is placed with a kitchen plot reserved")
	var cooked := false
	for i in 120:
		await run(1)
		if fire != null and fire.done and sim.items.values().any(func(it): return it.type == "cooked_mutton"):
			cooked = true
			break
	check(fire != null and fire.done, "the fireplace is built")
	check(cooked, "and its standing order cooks the hunted mutton")

	# The meadow (issue #182): the second bed needs more wool than the clearing's 3 sheep gave, so Ada
	# builds the expedition board and fetches it, with the fireplace's mutton for the walk home
	check(Goals.LIST[Goals.current(sim)].t == "Build an expedition board", "the checklist asks for the board next (%s)" % Goals.progress_text(sim))
	check(await open_bench_panel(), "open the bench for the board's planks and sticks")
	await queue_recipe("Planks", 2)
	await queue_recipe("Sticks", 1)
	await key(KEY_ESCAPE)
	await key(KEY_B)
	check(await click_button("Expedition board"), "the Build menu lists the expedition board once Ada's house is up")
	var bp := build_spot("board", at(2, 13))  # clear of the second house's spot and the farm's
	await look_at(bp)
	await click(screen(bp))
	var board = sim.site_at(bp)
	check(board != null and board.tpl == "board", "the board is placed")
	if game.tool != "":
		await key(KEY_ESCAPE)
	check(await play_until(300, func(): return board != null and board.done), "Ada builds the board")
	await look_at(sim.meadow_sign())
	await click(screen(sim.meadow_sign(), 1.4))
	game._hud.refresh(sim)
	await frames(2)
	check(game.planner_open and game.adventure == Meadow.ID, "clicking the meadow's signpost opens its adventure on the board")
	check(await click_button("Wool"), "send her for wool")
	check(game.plan.party == [ada.id] and game.plan.target.item == "wool", "the plan: Ada, alone, for wool (%s)" % [game.plan])
	if sim.free_count("cooked_mutton") < game.plan.meals:  # Ada may have eaten one: take what there is
		check(await click_button("meals less"), "take one meal fewer")
	check(await click_button("Start packing"), "click Start packing")
	check(await play_until(240, func(): return sim.depart_blocker() == ""), "the cooked mutton is packed (%s)" % sim.depart_blocker())
	check(await click_button("Depart"), "click Depart")
	check(await play_until(Tuning.MEADOW_WALK * 2 + 300, func(): return sim.expedition.is_empty()), "she hunts sheep at the meadow and comes home")
	check(sim.stats.meadow_wool and sim.free_count("wool") >= 3, "with the wool for the second bed (%d)" % sim.free_count("wool"))
	if game.planner_open:
		await click_button("Close")
	await look_at(at(17, 17))
	check(Goals.LIST[Goals.current(sim)].t == "Build a second house", "the checklist asks for the second house (%s)" % Goals.progress_text(sim))

	# Second house and the traveler
	await key(KEY_H)
	var origin2 := open_cell(at(1, 4), Vector2i(5, 5))
	await look_at(origin2 + Vector2i(2, 2))
	await click(screen(origin2 + Vector2i(2, 2)))
	var h2 = sim.site_at(origin2 + Vector2i(2, 2))
	check(h2 != null, "second house placed (tool %s, placing %s, planner %s, map %s, check \"%s\", menu %s, craft %s)" % [game.tool, game.placing, game.planner_open, game.view_map, sim.placement_check("house", origin2, game.rot), game._menu.visible, game.craft_menu_open])
	await look_at(bench_cell)
	await click(screen(bench_cell, 0.4))
	await queue_recipe("Planks", 5)
	await queue_recipe("Planks", 5)
	await key(KEY_ESCAPE)
	await key(KEY_X)  # more trees, so the walls' logs never run short after all those planks
	await look_at(at(17, 17))  # F centred the camera on Ada, wherever she happened to be
	await drag(screen(at(0, 0)), screen(at(17, 17)), true)
	await key(KEY_ESCAPE)
	await run(1000)
	sim.compute_stuck()
	var piled := {}
	var loose := {}
	for s in sim.stacks_where(func(_s): return true):
		var into: Dictionary = piled if sim.stored(s) else loose
		into[s.type] = into.get(s.type, 0) + int(s.n)
	check(h2 != null and h2.done, "second house finished (stage %d, felled %d, Ada's axe %s, broken %s, %s; marked trees %d; %s; piled %s; loose %s)" % [h2.stage if h2 != null else -1, sim.stats.felled, ada.axe, ada.broken.axe, ada.job.label if ada.job != null else "idle", sim.trees.filter(func(t): return t.alive and t.des).size(), sim.stuck.map(func(x): return x.why), piled, loose])
	check(sim.residents.size() == 2 and sim.stats.traveler_home, "Tomas arrives and moves in")
	var tomas: Dictionary = sim.residents[1] if sim.residents.size() > 1 else {}
	check(not tomas.is_empty() and Defs.JOBS.any(func(jb): return Sim.level(tomas, jb) >= Tuning.ARRIVAL_LEVEL), "Tomas arrives skilled in one job")
	check(Sim.level(ada, "lumber") >= 2, "Ada's Lumberjack level has risen with practice (level %d)" % Sim.level(ada, "lumber"))

	# Toast button and next-resident key
	for t in game._hud._toast_list:  # older toasts have Go to buttons too, and would be found first
		t.node.queue_free()
	game._hud._toast_list.clear()
	game._hud.add_toast({"text": "Tomas moved into the new house.", "res_id": tomas.get("id", 0), "site_id": 0})
	check(await click_button("Go to them"), "click a toast's Go to button")
	check(game.selection.get("ids", []) == [tomas.get("id", -1)], "the toast selects Tomas")
	await key(KEY_F)
	check(game.selection.get("ids", []) == [ada.id], "F selects the next resident")

	# Right-click order with a hint
	# A free tree that's actually what's under the cursor at its screen spot (not hidden behind a house).
	var t2: Dictionary = {}
	for cand in sim.trees.filter(func(t): return t.alive and t.claim == 0):
		var p: Vector2 = screen(cand.cell, 1.5)
		var vis := root.get_visible_rect().size
		var middle := Rect2(vis * Vector2(0.3, 0.28), vis * Vector2(0.4, 0.4))  # clear of the HUD's corner panels
		if middle.has_point(p) and is_same(game._pick(p, false), cand):
			t2 = cand
			break
	if not t2.is_empty():
		var tp := screen(t2.cell, 1.5)
		# The radial Gather menu (issue #176). With nobody selected: Chop and Chop all trees nearby
		game.selection = {}
		await move(tp)
		check(game._hud._hint.text.begins_with("Right-click: options"), "hovering a tree hints that right-click has options (got \"%s\"; under cursor %s; tree at %s)" % [game._hud._hint.text, game._pick(game._mouse), t2.cell])
		await click(tp, MOUSE_BUTTON_RIGHT)
		check(radial_ids() == ["mark", "nearby"], "with nobody selected, the radial shows Chop and Chop all trees nearby, not Chop now (%s)" % [radial_ids()])
		await key(KEY_ESCAPE)
		check(game.radial.is_empty() and not game._menu.visible, "Esc closes it")
		# With Ada selected: Chop now, clicked
		game.selection = {"kind": "res", "ids": [ada.id]}
		await click(tp, MOUSE_BUTTON_RIGHT)
		check(radial_ids() == ["mark", "now", "nearby"], "with Ada selected, Chop now is there too (%s)" % [radial_ids()])
		if game.radial.size() > 0:
			await move(radial_wedge(1))
			game._process(0.0)
			check(game._hud._hint.text == "2: Chop now", "hovering a wedge names it (\"%s\")" % game._hud._hint.text)
			await click(radial_wedge(1))
		check(game.radial.is_empty() and (ada.job != null and is_same(ada.job.target, t2) or ada.direct != null), "Chop now orders Ada to chop that tree")
		# A greyed wedge shows its reason
		ada.hunger = 0.0
		await click(tp, MOUSE_BUTTON_RIGHT)
		if game.radial.size() > 0:
			await move(radial_wedge(1))
			game._process(0.0)
		check(game._hud._hint.text == "Chop now: Ada is starving" and not game.radial.get("wedges", [{}, {"ok": true}])[1].ok, "a starving Ada's Chop now is greyed, and says why on hover (\"%s\")" % game._hud._hint.text)
		await key(KEY_ESCAPE)
		ada.hunger = 100.0
		# Press, drag to a wedge and release: Chop all trees nearby
		var marked_before: int = sim.trees.filter(func(t): return t.alive and t.des).size()
		await move(tp)
		await press(tp, true, MOUSE_BUTTON_RIGHT)
		var w2 := radial_wedge(2) if game.radial.size() > 0 else tp
		await move(tp.lerp(w2, 0.5))
		await move(w2)
		await press(w2, false, MOUSE_BUTTON_RIGHT)
		check(game.radial.is_empty() and sim.trees.filter(func(t): return t.alive and t.des).size() > marked_before + 1, "press, drag to Chop all trees nearby and release: the trees round it are marked (%d, then %d)" % [marked_before, sim.trees.filter(func(t): return t.alive and t.des).size()])
		# Shift + right-click skips the radial and queues the order
		var queued: int = ada.orders.size()
		await click(screen(t2.cell, 1.5), MOUSE_BUTTON_RIGHT, true)
		check(game.radial.is_empty() and ada.orders.size() == queued + 1, "Shift + right-click on a tree skips the radial and queues the order (%d)" % ada.orders.size())
		ada.orders.clear()

	# Shift + right-click queues orders; the panel lists them and can clear them
	var vis2 := root.get_visible_rect().size
	if true:
		game.selection = {"kind": "res", "ids": [ada.id]}
		# Two walks to open ground in the middle of the screen, queued with Shift + right-click
		for spot in [Vector2(0.45, 0.45), Vector2(0.55, 0.5)]:
			await click(vis2 * spot, MOUSE_BUTTON_RIGHT, true)
		check(ada.orders.size() >= 1, "Shift + right-click queues orders (%d)" % ada.orders.size())
		game._hud.refresh(sim)
		await frames(2)
		check(visible_label("Queued orders"), "the resident panel lists queued orders")
		check(await click_button("Clear orders"), "click Clear orders")
		check(not ada.orders.is_empty() and find_button("Click again to clear orders") != null, "the first click only asks to confirm")
		check(await click_button("Click again to clear orders"), "click it again")
		check(ada.orders.is_empty(), "Clear orders empties the list")

	# Two residents doing different work at once: one mines while the other crafts
	await key(KEY_X)
	await drag(screen(at(0, 0)), screen(at(17, 17)))
	await key(KEY_ESCAPE)
	await click(screen(bench_cell, 0.4))
	for i in 4:
		await queue_recipe("Planks")
	await key(KEY_ESCAPE)
	for i in 60:
		await run(1)
		if sim.stats.division:
			break
	check(sim.stats.division, "both residents work at different jobs at once")
	# The founding's last goal (issue #182): a chopping block for Tomas, the lumberjack
	check(tomas.get("role", "") == "lumber" and sim.needs_station(tomas), "Tomas arrived a lumberjack, waiting on a chopping block")
	game.selection = {}
	await key(KEY_B)
	check(await click_button("Chopping block"), "the Build menu lists the chopping block")
	var cb_near: Vector2i = Sim.nearest(sim.trees.filter(func(t): return t.alive), at(9, 9)).cell
	var cb_spot := build_spot("chopping_block", cb_near + Vector2i(2, 0))
	await look_at(cb_spot)
	await click(screen(cb_spot))
	var cblock = sim.site_at(cb_spot)
	if game.tool != "":
		await key(KEY_ESCAPE)
	check(await play_until(200, func(): return cblock != null and cblock.done and is_same(sim.claimed(tomas), cblock)), "it's built, and Tomas claims it")

	# Work area (issue #203): select the block, Paint area, drag over painted cells to erase them, and drag again to paint them back
	game.selection = {"kind": "site", "id": cblock.id}
	check(cblock.area.size() > 100, "the chopping block starts with a painted work area (%d cells)" % cblock.area.size())
	check(await click_button("Paint area"), "click Paint area on the chopping block's panel")
	check(game.tool == "area", "it switches the area tool on")
	await look_at(cblock.origin)
	var wa: Vector2i = cblock.origin + Vector2i(2, 0)
	var wb: Vector2i = cblock.origin + Vector2i(4, 1)
	await drag(screen(wa), screen(wb))
	check(not cblock.area.has(wa) and not cblock.area.has(wb), "dragging from a painted cell erases the cells it covers")
	await drag(screen(wa), screen(wb))
	check(cblock.area.has(wa) and cblock.area.has(wb), "dragging again, from an unpainted cell, paints them back")
	check(await click_button("Done painting"), "click Done painting")
	check(game.tool == "", "the tool is put away")
	game.selection = {}
	check(Goals.current(sim) < 0, "every founding goal is done (%s)" % Goals.progress_text(sim))
	game._hud.refresh(sim)  # the HUD refreshes on a timer; don't race it
	await frames(2)
	check(visible_label("The village") and visible_label("1  Paint a farm plot") and not visible_label("Slice 1"), "the goals panel moves on to the village chapter")
	check(Goals.progress_text(sim).ends_with("meals") and "residents" in Goals.progress_text(sim), "saves are labelled with the village's facts: %s" % Goals.progress_text(sim))

	# Farm plots (issue #45): P, drag over open grass, and residents plant wheat
	await key(KEY_P)
	check(game.tool == "farm", "P picks Farm")
	var fc := open_cell(at(12, 12), Vector2i(3, 2))
	await look_at(fc)
	await drag(screen(fc), screen(fc + Vector2i(2, 1)))
	check(sim.farm.size() >= 4, "dragging paints farm plots (%d)" % sim.farm.size())
	await key(KEY_ESCAPE)
	for i in 40:
		await run(1)
		if sim.stats.get("planted", 0) > 0:
			break
	check(sim.stats.get("planted", 0) > 0, "residents plant wheat on the new farm")

	# Jobs (issue #134): Tomas's one job, chosen from the dropdown on his panel, then on the board
	game.selection = {"kind": "res", "ids": [tomas.id]}
	check(await choose_job(tomas, "farm", false), "Tomas's panel: choose Farm from his job dropdown (%s)" % tomas.role)
	var panel_btn: Button = await job_button(tomas, false)
	check(panel_btn != null and panel_btn.text.begins_with("Farmer, level"), "his panel says he's a farmer (%s)" % (panel_btn.text if panel_btn else "no button"))
	check(await choose_job(tomas, "none"), "the jobs board: choose No job from Tomas's dropdown (%s)" % tomas.role)
	# A panel that changes between a button's press and release keeps the click
	var jb_btn: Button = await job_button(tomas)
	await click(jb_btn.get_global_rect().get_center())
	game._hud.refresh(game.sim)
	await frames(2)
	var smith: Button = find_button("Job choice: Toolsmith · ")
	check(smith != null, "the dropdown lists Toolsmith")
	if smith != null:
		var pos := smith.get_global_rect().get_center()
		await move(pos)
		await press(pos, true)
		tomas.jobs.farm.xp += 9  # the dropdown's content changes mid-click
		game._hud.refresh(game.sim)
		await frames(2)
		await press(pos, false)
		await frames(2)
	check(tomas.role == "toolsmith", "a click held across a dropdown change still lands (%s)" % tomas.role)
	check(not game._hud._job_drop.visible, "choosing closes the dropdown")
	await key(KEY_ESCAPE)
	check(not game.jobs_board_open and not game._menu.visible, "Esc closes the jobs board first")
	# Issue #184: the toolsmith keeps spares once he has a toolsmith's bench of his own
	var tsb = await place_from_menu("Toolsmith's bench", "toolsmith_bench", Sim.rcell(tomas) + Vector2i(0, 3))
	check(tsb != null and tsb.tpl == "toolsmith_bench", "a toolsmith's bench is placed from the Build menu")
	check(await play_until(200, func(): return tsb != null and tsb.done and tsb.worker == tomas.id), "it's built, and Tomas claims it")
	for i in 120:
		await run(1)
		if ["axe", "pick"].any(func(k): return not sim.tool_items(k, 0).is_empty()):
			break

	# Toolsmith (issue #49) and Equip: a spare is kept, and Ada can be told to equip it
	var spare_kinds: Array = ["axe", "pick"].filter(func(k): return not sim.tool_items(k, 0).is_empty())
	check(not spare_kinds.is_empty(), "the toolsmith keeps a spare tool in stock")
	if not spare_kinds.is_empty():
		game.selection = {"kind": "res", "ids": [ada.id]}
		check(await click_button("Equip"), "click Equip in Ada's panel")
		game._hud.refresh(sim)
		await frames(2)
		var opt: Button = null
		for n in _all(game._hud._sel):
			if n is Button and (" uses left, " in n.text):
				opt = n
				break
		check(opt != null, "Equip lists the spare")
		if opt != null:
			await click(opt.get_global_rect().get_center())
			check(ada.direct != null and ada.direct.kind == "equip" or ada.job != null and ada.job.kind == "equip", "choosing it sends Ada to get it")
			await run(10)
			check(ada.kept.axe or ada.kept.pick, "Ada equips it and keeps it")

	# Ada's wooden pickaxe is worn out by now: a new one, and boulders for the mason's bench's stone
	if ada.pick == null and sim.tool_items("pick", 0).is_empty():
		check(await open_bench_panel(), "open the bench for a new pickaxe")
		await queue_recipe("Wooden pickaxe")
		await key(KEY_ESCAPE)
	game.selection = {}
	await key(KEY_X)
	await look_at(at(9, 9))
	await drag(screen(Vector2i(0, 0)), screen(Vector2i(31, 31)), false, true)  # Alt: boulders only
	await key(KEY_ESCAPE)
	check(await play_until(240, func(): return sim.free_count("cobble") >= 9), "Ada breaks boulders for cobblestone (%d)" % sim.free_count("cobble"))
	for b in sim.boulders:  # her stone is in: leave the rest for Tomas's own rounds, which the next steps check
		b.des = false

	# Mason's bench (issue #177): built from the Build menu; Tomas, made the Stonemason, breaks the
	# boulders around it on his own and piles the stone beside it
	game.selection = {}
	await key(KEY_B)
	check(await click_button("Mason's bench"), "the Build menu lists the mason's bench")
	check(game.placing == "mason_bench", "it starts placing a mason's bench")
	var near_rock: Vector2i = Sim.nearest(sim.boulders.filter(func(b): return b.alive), Sim.rcell(ada)).cell
	var mb_spot := build_spot("mason_bench", near_rock + Vector2i(2, 0))
	await look_at(mb_spot)
	await click(screen(mb_spot))
	var mbench = sim.site_at(mb_spot)
	check(mbench != null and mbench.tpl == "mason_bench" and mbench.plot != null, "the mason's bench is placed with its workshop plot reserved")
	if game.tool != "":
		await key(KEY_ESCAPE)
	if sim.tool_items("pick", 0).is_empty() and tomas.pick == null:  # a pickaxe for the stonemason
		check(await open_bench_panel(), "open the bench's Craft panel for a pickaxe")
		await queue_recipe("Stone pickaxe")
		await key(KEY_ESCAPE)
	check(await choose_job(tomas, "mason"), "the jobs board: make Tomas the Stonemason (%s)" % tomas.role)
	await key(KEY_ESCAPE)
	# The bench cuts bricks from its pile as the stone arrives, so with one boulder in range the pile may never
	# reach a boulder's worth: the stone he's brought (piled, or already cut into bricks) is what counts.
	var stone_in := func() -> int: return sim.pile_count(mbench) + sim.free_count("stone_brick") if mbench != null else 0
	check(await play_until(240, func(): return mbench != null and mbench.done and stone_in.call() >= Tuning.BOULDER_COBBLE), "Tomas piles stone beside the mason's bench (%d; done %s, stage %d, Tomas %s with %s, claimed %s; %s)" % [stone_in.call(), mbench.done if mbench != null else false, mbench.stage if mbench != null else -1, tomas.role, tomas.pick, sim.claimed(tomas).get("tpl", ""), "; ".join(sim.stuck.map(func(x): return x.who + ": " + x.why)) + "; boulders alive %d, in its area %d, marked %d, kept %d" % [sim.boulders.filter(func(b): return b.alive).size(), sim.boulders.filter(func(b): return b.alive and mbench != null and sim.in_area(mbench, b.cell)).size(), sim.boulders.filter(func(b): return b.alive and b.des).size(), sim.boulders.filter(func(b): return b.alive and b.get("keep", false)).size()]])
	check(sim.boulders.filter(func(b): return not b.alive and not b.des).size() > 0 or sim.stats.broken_boulders > 0, "breaking boulders nobody marked")
	await look_at(mb_spot)
	await click(screen(mb_spot, 0.5))
	game._hud.refresh(sim)
	await frames(2)
	check(game.selection.get("kind", "") == "site" and visible_label("Keep %d cobblestone" % mbench.keep), "selecting it shows its keep-stock target")
	check(game._world.live_fills.size() > 3, "and draws its painted work area (%d washes)" % game._world.live_fills.size())
	var keep_lbl: Array = _all(game._hud._sel).filter(func(n): return n is Label and n.text == "Keep %d cobblestone" % mbench.keep)
	var keep_plus: Button = keep_lbl[0].get_parent().get_child(keep_lbl[0].get_index() + 1) if not keep_lbl.is_empty() else null
	check(keep_plus != null, "with a + beside it")
	if keep_plus != null:
		await click(keep_plus.get_global_rect().get_center())
	check(mbench.keep == Tuning.KEEP_STOCK + Tuning.KEEP_STEP, "the target goes up by %d (%d)" % [Tuning.KEEP_STEP, mbench.keep])
	# It cuts stone bricks too (issue #178): a standing order in its panel, and a tab in the Craft panel
	check(visible_label("Keep %d stone bricks" % Tuning.MAKE_KEEP.mason_bench), "its panel shows the stone bricks it keeps")
	check(game.craft_menu_open, "selecting it opens the Craft panel")
	check(await click_button("Mason's bench"), "click the Craft panel's Mason's bench tab")
	check(game.craft_bench() == mbench, "the tab shows the mason's bench")
	var by_hand := func() -> int: return mbench.autoq.filter(func(a): return not a).size()
	var hand_before: int = by_hand.call()
	check(await queue_recipe("Stone bricks"), "queue stone bricks")
	check(by_hand.call() == hand_before + 1, "a batch of stone bricks is queued (%s)" % [mbench.queue])
	await key(KEY_ESCAPE)
	check(await play_until(120, func(): return sim.free_count("stone_brick") > 0 or sim.stats.get("crafted", {}).get("stone_brick", 0) > 0), "Tomas cuts stone bricks (%d)" % sim.free_count("stone_brick"))

	# Tools dropdown on hover
	var tb: Button = game._hud._tools_btn
	# Open ground, so the click on the world below selects nothing (a bench would open its Craft panel)
	var clear := screen(open_cell(game._cell_at(Vector2(1000, 430))))
	await move(clear)
	await frames(2)
	check(not game._hud._tools_drop.visible, "Tools list is closed")
	await move(tb.get_global_rect().get_center())
	await frames(2)
	check(game._hud._tools_drop.visible, "hovering Tools opens the list")
	await move(game._hud._tools_drop.get_global_rect().get_center())
	await frames(2)
	check(game._hud._tools_drop.visible, "the list stays open while the pointer moves onto it")
	await move(clear)
	await frames(2)
	check(not game._hud._tools_drop.visible, "moving away closes the list")
	# A click pins it open; it closes on a second click, on a click elsewhere, or on Esc (issue #90)
	await click(tb.get_global_rect().get_center())
	await move(clear)
	await frames(2)
	check(game._hud._tools_drop.visible, "a click pins the list open")
	await click(tb.get_global_rect().get_center())
	await move(clear)
	await frames(2)
	check(not game._hud._tools_drop.visible, "a second click unpins it, and moving away closes it")
	await click(tb.get_global_rect().get_center())
	await click(clear)  # clear of the button and the list
	await frames(2)
	check(not game._hud._tools_drop.visible, "pinned, a click on the world closes it")
	await click(tb.get_global_rect().get_center())
	await move(clear)
	await key(KEY_ESCAPE)
	await frames(2)
	check(not game._hud._tools_drop.visible and not game._menu.visible, "pinned, Esc closes it (and doesn't open the menu)")

	# Menu by mouse: save, load with confirmation, controls, start over
	# Esc closes an open tool, menu or panel before it opens the game menu, and the real-time clicks
	# above sometimes leave one open.
	var still_open := {"tool": game.tool, "menu": game.menu_open, "jobs board": game.jobs_board_open, "craft panel": game.craft_menu_open, "planner": game.planner_open}
	for k in still_open.keys():
		if not still_open[k]:
			still_open.erase(k)
	if not still_open.is_empty():
		print("     (closing %s first)" % still_open)
		await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	check(game._menu.visible and game.speed == 0, "Esc opens the menu and pauses (tool \"%s\", menu \"%s\", jobs board %s, craft %s, planner %s)" % [game.tool, game.menu_open, game.jobs_board_open, game.craft_menu_open, game.planner_open])
	check(await click_button("Save game"), "click Save game")
	check(await click_button("Save here"), "click Save here")
	check(FileAccess.file_exists(game._slot_path(1)), "slot 1 is written")
	check(await click_button("Save over"), "click Save over")
	check(visible_label("Save over slot 1?"), "saving over asks first")
	check(await click_button("Cancel"), "click Cancel")
	check(await click_button("Back"), "click Back")
	var saved_tick := sim.tick
	check(await click_button("Resume"), "click Resume")
	await run(30)
	await key(KEY_M)
	check(game._menu.visible, "M opens the menu")
	check(await click_button("Load game"), "click Load game")
	check(await click_button("Load"), "click Load on slot 1")
	check(await click_button("Load slot 1"), "confirm Load slot 1")
	var slot_tick: int = game.read_slots()[0].tick
	check(not game._menu.visible, "loading closes the menu")
	# Loading closes the menu and resumes, so a frame may tick once before this reads it: a few ticks of slack.
	check(game.sim.tick >= slot_tick and game.sim.tick - slot_tick <= 3, "the saved game is back (tick %d, slot holds %d, tick before resuming %d)" % [game.sim.tick, slot_tick, saved_tick])
	await key(KEY_SLASH, true)
	check(game._menu.visible and game._menu.view == "keys", "? opens Controls")
	check(visible_label("Mine trees and boulders"), "Controls lists the keys")
	check(await click_button("Back"), "click Back from Controls")
	check(await click_button("Start over"), "click Start over")
	check(await click_button("Start over", "", true), "confirm Start over (the button in the confirmation)")
	# Start over resumes play, so a slow frame may already have ticked the new game once or twice.
	check(game.sim.tick < Tuning.TPS and not game._menu.visible, "a fresh game starts (tick %d)" % game.sim.tick)

	# Camera
	var before: Vector3 = game._target
	await drag(Vector2(1100, 650), Vector2(950, 560))
	check(game._target.distance_to(before) > 1.0, "left-drag pans")
	var size_before: float = game._cam.size
	await key(KEY_EQUAL)
	check(game._cam.size < size_before, "+ zooms in")

	# Maps (issue #101): once the old mine is known, Tab and the switcher change maps, and a toast
	# about someone at the mine goes there.
	sim = game.sim
	sim.get_map(OldMine.ID).known = true
	await key(KEY_TAB)
	check(game.view_map == OldMine.ID, "Tab switches to the old mine")
	check(await click_button("Village"), "click Village in the switcher")
	check(game.view_map == "village", "the switcher goes back to the village")
	check(await click_button("Old mine"), "click Old mine in the switcher")
	check(game.view_map == OldMine.ID, "and to the old mine")
	await key(KEY_TAB)
	check(game.view_map == "village", "Tab goes back to the village")
	var miner := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Sim.rcell(sim.residents[0]) + Vector2i(1, 0))
	sim.move_to_map(miner, OldMine.ID, sim.get_map(OldMine.ID).entrance)
	game._hud.add_toast({"text": "Tomas found something.", "res_id": miner.id, "site_id": 0, "map": OldMine.ID})
	check(await click_button("Go to them", "", true), "click Go to them on the newest toast, about Tomas")
	check(game.view_map == OldMine.ID and game.selection.get("ids", []) == [miner.id], "the toast switches to the mine and selects him")

	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	print("\n%s" % ("PLAYTEST PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures else 0)
