extends "res://tests/playtest_base.gd"
## The Slice 2 bot playtest (issue #51): from the founding to a working village, played through
## input pushed into the game window. The founding itself is set up with sim commands, since
## playtest.gd already plays it through input; everything Slice 2 adds is then played by keys,
## clicks and drags. Each section ends on one of slice-2-spec.md's done criteria. Uses its own save
## and settings folders. Run from game/:
##   godot --headless --path . -s res://tests/playtest_village.gd


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.keys_path = "user://test_settings/playtest_village_keys.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.keys_path))
	# A script error stops this function without quitting; don't hang forever if that happens.
	create_timer(900.0).timeout.connect(func():
		printerr("FAIL the playtest stopped (a script error?) and timed out")
		quit(1))
	root.add_child(game)
	await frames(3)
	game.save_dir = "user://playtest_saves"
	check(await click_button("Play"), "click Play")
	# Paused (~) throughout, so only play() advances time and every toast is seen.
	await key(KEY_QUOTELEFT)
	check(game.speed == 0, "~ pauses")
	var sim := game.sim
	var ada: Dictionary = sim.residents[0]

	# ---- The founding (set up by command; playtest.gd plays it through input). Only the opening's
	# 18×18 is mined, so the ring of trees and boulders around it is left for the village.
	sim.designate_mine(area(0, 0, 10, 18))
	sim.designate_hunt(Rect2i(0, 0, sim.w, sim.h))
	var bench := sim.place_site("bench", at(8, 10))
	await play(120)
	for r in ["planks", "planks", "sticks", "wood_pick"]:
		sim.queue_add(bench, r)
	await play(120)
	sim.paint_zone(area(10, 7, 4, 2))
	sim.designate_mine(area(0, 0, 18, 18))
	await play(150)
	var h1 := sim.place_site("house", at(11, 0))
	for i in 8:
		sim.queue_add(bench, "planks")
	await play(600)
	var h2 := sim.place_site("house", at(1, 4), 1)
	for i in 8:
		sim.queue_add(bench, "planks")
	check(await play_until(1200, func(): return sim.stats.get("traveler_home", false)), "founding: Tomas has moved in")
	var tomas: Dictionary = sim.residents[1] if sim.residents.size() > 1 else {}
	check(h1.done and h2.done and h1.stage == 4 and h2.stage == 4, "both houses are finished with their beds")
	check(sim.stats.get("sheep_hunted", 0) >= 6, "the clearing's sheep were hunted for wool and mutton (%d)" % sim.stats.get("sheep_hunted", 0))
	check(not tomas.is_empty() and seen("a skilled"), "Tomas arrived skilled in a job")

	# ---- A bigger stockpile, by drag: Z opens the Paint menu, 1 picks Stockpile (issue #93)
	await look_at(at(9, 9))
	await key(KEY_Z)
	await key(KEY_1)
	check(game.tool == "stock", "Z then 1 picks Stockpile")
	var zr := open_rect_on_screen(at(9, 9), 4, 3, func(p): return sim.walkable(p) and sim.site_at(p) == null and sim.reserved_at(p) == null and not sim.in_zone(p) and not sim.items.has(p) and p != sim.meadow_sign())
	if zr.position.x >= 0:
		await drag(screen(zr.position), screen(zr.end - Vector2i.ONE))
	check(sim.zone.size() >= 16, "Z: a bigger stockpile is painted (%d cells)" % sim.zone.size())
	await key(KEY_ESCAPE)

	# ---- Farm: paint plots, picked in the Paint menu; wheat is planted, grows and is harvested
	check(await click_button("Paint") and await click_button("Farm plot"), "pick Farm plot in the Paint menu")
	game._hud.refresh(sim)
	check(game.tool == "farm" and game._hud._tool_btns.paint.text == "Paint: Farm plot", "Farm plot is on, and the Paint button says so")
	var fr := open_rect_on_screen(at(9, 9), 3, 2, func(p): return sim.farm_blocked(p) == "")
	check(fr.position.x >= 0, "open grass on screen for a farm")
	await drag(screen(fr.position), screen(fr.end - Vector2i.ONE))
	await key(KEY_ESCAPE)
	check(sim.farm.size() == 6, "P: dragging paints 6 farm plots (%d)" % sim.farm.size())
	check(await play_until(60, func(): return sim.stats.get("planted", 0) >= 6), "the plots are planted")
	check(await play_until(Tuning.WHEAT_GROW + 90, func(): return sim.stats.get("harvested", 0) >= 3), "the wheat grows and is harvested")
	check(await play_until(90, func(): return sim.items.values().any(func(it): return it.type == "wheat" and sim.in_zone(it.cell))), "harvested wheat is hauled to the stockpile")
	check(seen("Planting wheat") and seen("Harvesting wheat"), "residents were seen planting and harvesting")

	# ---- Fireplace (K): placed with its kitchen plot; the standing order bakes bread
	await key(KEY_K)
	var fp := build_spot("fireplace", at(9, 9))
	check(fp.x >= 0, "room for a fireplace and its kitchen plot")
	await look_at(fp)
	await click(screen(fp))
	var fire = sim.site_at(fp)
	check(fire != null and fire.tpl == "fireplace" and fire.plot != null, "K: the fireplace is placed with a kitchen plot reserved")
	check(await play_until(240, func(): return fire != null and fire.done and count("bread") + count("cooked_mutton") > 0), "the fireplace is built and bakes or cooks a meal")
	check(seen("Baking bread") or seen("Cooking mutton"), "residents were seen cooking")
	game._select(fire)
	game._hud.refresh(sim)
	await frames(2)
	check(visible_label("Keep 6 meals in stock") or find_button("Keep 6 meals in stock") != null, "the fireplace panel shows its standing order")
	await key(KEY_ESCAPE)

	# ---- Hunger: residents get hungry, fetch food and eat
	check(await play_until(400, func(): return seen("Eating")), "a hungry resident fetches food and eats (%s)" % [_seen.filter(func(t): return "Eat" in t)])

	# ---- A third house, placed now so there's building to do while trying out the Jobs grid
	await key(KEY_H)
	var hc := build_spot("house", at(9, 9))
	check(hc.x >= 0, "room for a third house")
	await look_at(hc + Vector2i(2, 2))
	await click(screen(hc + Vector2i(2, 2)))
	var h3 = sim.site_at(hc + Vector2i(2, 2))
	check(h3 != null and h3.tpl == "house", "H: a third house is placed")
	check(not game._menu.visible, "placing it leaves the menu closed")

	# ---- Jobs board (issue #134): Tomas's one job, from the dropdown; the columns count who has each
	check(await choose_job(tomas, "farm"), "the jobs board: make Tomas a farmer (%s)" % tomas.role)
	check(visible_label("nobody"), "a job nobody has says so")
	check(await choose_job(tomas, "build"), "then a builder, for the third house (%s)" % tomas.role)
	await key(KEY_ESCAPE)
	# Planks for the house, from the toolbar's Craft panel
	check(await open_bench_panel(), "open the Craft panel on the bench")
	await key(KEY_QUOTELEFT)
	for i in 3:
		await queue_recipe("Planks", 5)
	await key(KEY_ESCAPE)

	# ---- Skills: levels rise with work
	var levels: int = 0
	for r in sim.residents:
		for jb in Defs.JOBS:
			levels = maxi(levels, Sim.level(r, jb))
	check(levels >= 2 and seen("is now level"), "skill levels rise with work, with a toast (best level %d)" % levels)
	await select_resident(ada)
	check(visible_label("Everything"), "Ada's panel says she does everything")
	var best_cell: Control = await job_cell(ada, "mine")
	check(best_cell != null and best_cell.find_children("*", "Label", true, false).any(func(l): return "Lv " in l.text), "the jobs board shows levels")
	await key(KEY_ESCAPE)

	# ---- Toolsmith: an axe is made, a spare is kept, and a broken axe is replaced from it
	check(await open_bench_panel(), "open the bench's Craft panel again")
	check(await queue_recipe("Wooden axe"), "queue a wooden axe")
	await key(KEY_ESCAPE)
	await look_at(at(9, 9))
	await key(KEY_X)
	await drag(screen(Vector2i(1, 1)), screen(Vector2i(sim.w - 2, sim.h - 2)))
	await key(KEY_ESCAPE)
	var holder: Array = [null]
	check(await play_until(300, func():
		for r in sim.residents:
			if r.axe != null:
				holder[0] = r
		return holder[0] != null and not sim.tool_items("axe", 0).is_empty()), "an axe is in use and the toolsmith keeps a spare")
	if holder[0] != null:
		# Wear every axe in use down to its last use, to see one break without waiting an hour.
		var users: Array = sim.residents.filter(func(r): return r.axe != null)
		for r in users:
			r.axe.dur = 1
		check(await play_until(300, func(): return sim.stats.tools_broken > 0), "an axe breaks (%s)" % [_seen.filter(func(t): return "broke" in t)])
		check(await play_until(90, func(): return users.all(func(r): return r.axe != null and not r.broken.axe)), "whoever's axe broke fetches the spare instead of stopping")
		await play(1)
		check(find_button("Needs a new axe") == null, "and no \"Needs a new axe\" report is left")

	# ---- The meadow (issues #136, #137): an expedition board, then an adventure there for wool
	check(await open_bench_panel(), "open the bench for the board's planks and sticks")
	await queue_recipe("Planks", 2)
	await queue_recipe("Sticks", 1)
	await key(KEY_ESCAPE)
	check(await click_button("Build") and await click_button("Expedition board"), "pick Expedition board in the Build menu")
	var bp := build_spot("board", at(9, 9))
	check(bp.x >= 0, "room for the board")
	await look_at(bp)
	await click(screen(bp))
	var board = sim.site_at(bp)
	check(await play_until(300, func(): return board != null and board.done), "the board is built")
	await look_at(sim.meadow_sign())
	await click(screen(sim.meadow_sign(), 1.4))
	game._hud.refresh(sim)
	await frames(2)
	check(game.planner_open and game.adventure == Meadow.ID and visible_label("Meadow"), "clicking the meadow's signpost opens its adventure on the board")
	check(await click_button("All adventures"), "back to the adventures list")
	await settle()
	check(find_button("Adventure: Old mine") != null and find_button("Adventure: Meadow") != null, "the board lists the old mine and the meadow")
	check(await click_button("Adventure: Meadow"), "pick the meadow")
	check(await click_button("Tomas"), "add Tomas")
	check(await click_button("Wool"), "send them for wool")
	var plan: Dictionary = game.plan
	check(plan.dest == Meadow.ID and plan.party.size() == 2 and plan.target.item == "wool" and plan.picks == 0, "the plan: two of them to the meadow, for wool (%s)" % [plan])
	check(await click_button("Start packing"), "click Start packing")
	check(await play_until(240, func(): return sim.depart_blocker() == ""), "the meals are packed and the party waits at the board (%s)" % sim.depart_blocker())
	check(await click_button("Depart"), "click Depart")
	var party: Array = sim.expedition.get("party", []).map(func(id): return sim.resident(id))
	check(await play_until(90, func(): return party.all(func(r): return r.away)), "they carry the packs off the west edge")
	check(await play_until(Tuning.MEADOW_WALK + 10, func(): return party.all(func(r): return sim.at_site(r))), "they reach the meadow")
	check(await click_button("Close") and not game.planner_open, "close the board")
	for i in 5:
		if game.view_map == Meadow.ID:
			break
		await key(KEY_TAB)
	check(game.view_map == Meadow.ID, "Tab reaches the meadow on the map switcher")
	game._world._update_sheep()
	check(game._world._sheep_nodes.size() >= Meadow.herd().cow, "its herds are drawn")
	check(await play_until(300, func(): return sim.expedition.is_empty()), "they hunt sheep for the wool and come home")
	check(seen("Back from the meadow: ") and seen("wool"), "the report says what came back")
	await key(KEY_TAB)
	while game.view_map != "village":
		await key(KEY_TAB)

	# ---- The third house gets its bed, and a new traveler arrives
	for i in 6:
		if h3 != null and h3.done:
			break
		if await open_bench_panel():
			await key(KEY_QUOTELEFT)
			await queue_recipe("Planks", 5)
			await key(KEY_ESCAPE)
		await play_until(300, func(): return h3 != null and h3.done)
	check(h3 != null and h3.done and h3.stage == 4, "the third house is finished, bed and all")
	check(await play_until(Tuning.ARRIVAL_DELAY + 120, func(): return sim.residents.size() == 3 and not sim.residents[2].arriving), "a third traveler arrives and moves in")
	check(sim.residents.size() == 3 and sim.residents[2].name == "Mira" and seen("Mira"), "it's Mira, with a toast")

	# ---- Smelting and iron tools (issue #104): ore and coal from the mine, smelted at the fireplace
	var zc: Vector2i = sim.zone.keys()[0]
	sim.drop_items(zc, "iron_ore", 3)
	sim.drop_items(zc, "coal", 3)
	game._select(fire)
	check(game.craft_menu_open and await queue_recipe("Smelt iron", 3), "queue 3 Smelt iron at the fireplace")
	await key(KEY_ESCAPE)
	check(await play_until(150, func(): return count("iron_ingot") >= 3), "3 iron ore and 3 coal are smelted into 3 ingots (%d)" % count("iron_ingot"))
	check(seen("Smelting iron"), "a resident was seen smelting")
	check(await open_bench_panel() and await queue_recipe("Iron pickaxe"), "queue an iron pickaxe at the bench")
	await key(KEY_ESCAPE)
	check(await play_until(150, func(): return sim.residents.any(func(r): return r.pick != null and r.pick.type == "iron_pick") or not sim.tool_items("pick", 2).is_empty()), "an iron pickaxe is made")

	# ---- The expedition board (issue #105), built for the meadow above, with its map room plot
	check(board != null and board.tpl == "board" and board.plot != null, "the board has its map room plot reserved")
	check(seen("expedition board is up") and game.known_maps().has(OldMine.ID), "it brought word of the old mine, which the switcher shows")

	# ---- Planning (issue #106): select the board, pick the old mine, read its site report, and fill in the plan
	await look_at(bp)
	await click(screen(bp, 1.0))
	game._hud.refresh(sim)
	await frames(2)
	check(game.planner_open and find_button("Adventure: Old mine") != null, "selecting the board opens the adventures list")
	check(await click_button("Adventure: Old mine"), "pick the old mine")
	await settle()
	check(game.adventure == OldMine.ID and visible_label("Old mine"), "its report and planner open")
	check(visible_label("“%s”" % OldMine.TOLD), "the report says what the village has been told")
	check(await click_button("Tomas"), "add Tomas to the party")
	check(await click_button("Coal"), "send them for coal")
	check(await click_button("meals more"), "take one more meal")
	check(game.plan.party == [ada.id, tomas.id] and game.plan.meals == 4 and game.plan.target.item == "coal", "the plan is Ada and Tomas, 4 meals, for coal (%s)" % [game.plan])
	check(await click_button("Start packing"), "click Start packing")
	check(sim.expedition.get("state", "") == "staging", "packing starts")

	# ---- Staging and departure (issue #107): supplies are packed at the board, then Depart
	check(await play_until(240, func(): return sim.depart_blocker() == ""), "the supplies are packed and the party gathers at the board (%s)" % sim.depart_blocker())
	check(sim.packed().meals == 4, "4 meals are packed")
	check(await click_button("Depart"), "click Depart")
	check(sim.carrying_packs(ada) and sim.carrying_packs(tomas), "Ada and Tomas carry the packs to the signpost")
	check(await play_until(60, func(): return ada.map == Road.ID and tomas.map == Road.ID), "they set off from the signpost onto the road (issues #108, #118)")
	check(ada.trip == OldMine.ID, "for the old mine")
	await play(2)
	check(visible_label("on the road to the old mine") or find_button("Party on the road to the old mine") != null, "the board and the party line say they're on the road")
	# The signpost shows who's on the road.
	await look_at(sim.route_sign())
	await click(screen(sim.route_sign(), 1.4))
	game._hud.refresh(sim)
	await frames(2)
	check(game.selection.get("kind", "") == "route" and visible_label("Road to the old mine"), "clicking the signpost shows the road to the old mine")
	check(await play_until(40, func(): return ada.map == OldMine.ID and tomas.map == OldMine.ID), "they walk the road and reach the old mine")
	await key(KEY_TAB)
	check(game.view_map == OldMine.ID, "Tab shows them at the old mine")
	# Mine the coal nearest the entrance, then call them home from the party line.
	var mine := sim.get_map(OldMine.ID)
	sim.on_map(OldMine.ID, func():
		var coal: Array = sim.boulders.filter(func(b): return b.get("ore", "") == "coal")
		coal.sort_custom(func(a, b): return Sim.manhattan(a.cell, mine.entrance) < Sim.manhattan(b.cell, mine.entrance))
		sim.designate_mine(Rect2i(coal[0].cell, Vector2i.ONE)))
	check(await play_until(150, func(): return sim.expedition.get("cargo", {}).get("coal", 0) >= 1), "the party mines coal and packs it (issue #109)")
	game.selection = {}
	check(await click_button("Call the party home"), "click Call the party home, beside the party line at the mine")
	check(sim.expedition.get("leg", "") == "home", "the party heads home")
	await key(KEY_TAB)
	await key(KEY_TAB)
	await key(KEY_TAB)
	check(game.view_map == "village", "Tab, past the road and the meadow, back to the village")

	# ---- Return and unloading (issue #112): the cargo is set down at the signpost and hauled away
	var coal_before := count("coal")
	if not sim.pending.is_empty():  # someone seriously hurt at the mine: the game waits for a choice
		check(await click_button("Retreat"), "answer the injury with Retreat")
		await key(KEY_QUOTELEFT)  # answering carries on at speed: pause again, so only play() moves time
		check(game.speed == 0, "~ pauses again")
	check(await play_until(150, func(): return sim.expedition.is_empty()), "the party gets home, the hurt walking slower (%s, unloading %s)" % [sim.expedition.get("party", []).map(func(id): return [sim.resident(id).map, sim.resident(id).job.label if sim.resident(id).job != null else "idle", sim.resident(id).hurt, sim.resident(id).pos, sim.resident(id).path.size(), sim.resident(id).job.i if sim.resident(id).job != null else -1, sim.resident(id).trip, sim.cart]), sim.expedition.get("unloading", false)])
	check(seen("Back from the old mine: ") and seen("coal"), "a toast reports what came back")
	check(ada.map == "village" and tomas.map == "village" and not ada.away, "Ada and Tomas are back in the village")
	if true:  # room for the cargo: the stockpile is nearly full by now, so paint more, as a player would
		await look_at(at(9, 9))
		await key(KEY_Z)
		await key(KEY_1)
		var more := open_rect_on_screen(at(9, 9), 4, 3, func(p): return sim.farm_blocked(p) == "" and not sim.items.has(p))
		check(more.position.x >= 0, "open ground on screen for more stockpile")
		var cells_before := sim.zone.size()
		await drag(screen(more.position), screen(more.end - Vector2i.ONE))
		await key(KEY_ESCAPE)
		check(sim.zone.size() > cells_before, "more stockpile is painted (%d → %d cells, tool %s)" % [cells_before, sim.zone.size(), game.tool])
	check(await play_until(400, func(): return count("coal") > coal_before and sim.stacks_where(func(st): return st.type == "coal" and not sim.in_zone(st.cell)).is_empty()), "the coal is hauled to the stockpile, behind the village's other hauling (%s)" % [sim.stacks_where(func(st): return st.type == "coal").map(func(st): return [st.cell, st.n, sim.in_zone(st.cell)])])
	await look_at(bp)
	await click(screen(bp, 1.0))
	game._hud.refresh(sim)
	await frames(2)
	check(game.planner_open and visible_label("Last expedition") and find_button("Start packing") != null or visible_label("Last expedition"), "the board shows the last expedition and is ready to plan the next")
	await key(KEY_ESCAPE)

	# ---- Every stall has a reason: anything in the stuck list carries one
	check(sim.stuck.all(func(s): return s.why != ""), "every stuck item says why")

	print("\n%s" % ("PLAYTEST PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures else 0)
