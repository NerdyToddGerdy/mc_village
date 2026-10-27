extends "res://tests/playtest_base.gd"
## The Slice 3 bot playtest (issue #113): the first expedition, played through input pushed into the
## game window, from a Slice 2 village (tests/fixtures/slice2_village.save) so the founding isn't
## replayed. It builds the expedition board, plans a trip for Ada and Tomas, packs and departs,
## works the old mine, answers the iron discovery with Investigate and a serious injury with Retreat,
## watches the return and unloading, then smelts iron and crafts an iron pickaxe. On the way it walks
## the road to the mine (Slice 4, #118), then builds the bridge, clears the cut, plans the line and
## builds both stations from the signpost (#119, #121, #123). Last, a second trip digs to the door at
## the end of the old mine and goes down to mine on Level 2 (#132). It fails on any
## stuck reason the player couldn't act on. Uses its own save and settings folders. Run from game/:
##   godot --headless --path . -s res://tests/playtest_slice3.gd

## Blockers a player can act on from the reason alone. Anything else in the stuck list fails the run.
const ACTIONABLE := ["more ", "Needs a pickaxe", "No one is a ", "Stockpile is full", "Starving", "Hungry",
	" broke", "Can’t reach", "No meals to pack", "No spare pickaxes to pack", "No pickaxe left",
	"Everyone is hurt", "Investigating the vein needs", "Harvested wheat needs a stockpile",
	"Injured: can't mine", "Track: needs"]
var _blockers := {}         ## Every blocker reason seen, so the run can check each one is actionable.


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.keys_path = "user://test_settings/playtest_slice3_keys.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.keys_path))
	create_timer(900.0).timeout.connect(func():
		printerr("FAIL the playtest stopped (a script error?) and timed out")
		quit(1))
	root.add_child(game)
	await frames(3)
	game.save_dir = "user://playtest_saves"
	check(await click_button("Play"), "click Play")
	# A Slice 2 village, loaded the way a saved game is.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(game.save_dir))
	var slot := game._slot_path(1)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/fixtures/slice2_village.save"), ProjectSettings.globalize_path(slot))
	check(game.load_slot(1) == "", "load the Slice 2 village")
	await frames(3)
	await key(KEY_QUOTELEFT)  # paused throughout: only play() moves time on
	var sim := game.sim
	check(sim.residents.size() == 3 and Goals.current(sim) < 0, "a Slice 2 village: three residents, the founding done")
	var ada: Dictionary = sim.residents[0]
	var tomas: Dictionary = sim.residents[1]

	# ---- A chopping block, for whoever stays home as the lumberjack (issues #177, #184): Ada builds it
	var block = await place_from_menu("Chopping block", "chopping_block", Sim.nearest(sim.trees.filter(func(t): return t.alive), at(9, 9)).cell + Vector2i(2, 0))
	check(block != null and block.tpl == "chopping_block", "a chopping block is placed from the Build menu")
	check(await play_until(120, func(): return block != null and block.done), "and built")

	# ---- The expedition board (issue #105), from the Build menu
	check(await click_button("Build") and await click_button("Expedition board"), "pick Expedition board in the Build menu")
	var bp := build_spot("board", at(9, 9))
	check(bp.x >= 0, "room for the board")
	await look_at(bp)
	await click(screen(bp))
	var board = sim.site_at(bp)
	check(board != null and board.tpl == "board", "the board is placed")
	check(await play_until(300, func(): return board != null and board.done), "the board is built")
	check(game.known_maps().has(OldMine.ID), "the village has word of the old mine")

	# ---- Plan (issue #106): Ada and Tomas, for 10 cobblestone, with 6 meals they may all eat. They
	# come home when the packs are full; here, the injury brings them home first.
	await look_at(bp)
	await click(screen(bp, 1.0))
	game._hud.refresh(sim)
	await frames(2)
	check(game.planner_open and find_button("Location") != null, "selecting the board opens the planner with its Location dropdown")
	check(await click_button("Location"), "open the dropdown")
	game._hud.refresh(sim)
	await frames(2)
	check(find_button("Adventure: Old mine") != null and find_button("Adventure: Meadow") != null, "it lists the old mine and the meadow")
	check(await click_button("Adventure: Old mine"), "pick the old mine")
	await settle()
	check(game.adventure == OldMine.ID and visible_label("Old mine"), "its site report and planner open (%s)" % game.adventure)
	check(await click_button("Tomas"), "add Tomas")
	check(await plan_wants("Cobblestone", 10), "send them for 10 cobblestone")
	check(await click_button("picks less"), "no spare pickaxe: both have their own")
	for i in 3:
		await click_button("meals more")
	check(await click_button("Spend it"), "let them eat the return food")
	check(await click_button("Target reached") and await click_button("Food runs low"), "come home only when the packs are full")
	var plan: Dictionary = game.plan
	check(plan.party == [ada.id, tomas.id] and plan.target == {"item": "cobble", "n": 10} and plan.meals == 6 and plan.picks == 0 and plan.spend_return, "the plan: Ada and Tomas, 10 cobblestone, 6 meals (%s)" % [plan])
	check(plan.policy == {"target": false, "full": true, "low": false}, "home when the packs are full (%s)" % [plan.policy])
	check(await click_button("Start packing"), "click Start packing")

	# ---- Staging and departure (issues #107, #108)
	check(await play_until(240, func(): return sim.depart_blocker() == ""), "the meals are packed and the party waits at the board (%s)" % sim.depart_blocker())
	# Something for the village to do while they're away: trees to fell.
	await look_at(at(9, 9))
	await key(KEY_X)
	await drag(screen(Vector2i(1, 1)), screen(Vector2i(sim.w - 2, sim.h - 2)), true)
	await key(KEY_ESCAPE)
	check(await click_button("Depart"), "click Depart")
	check(await play_until(90, func(): return ada.map == Road.ID and tomas.map == Road.ID), "they carry the packs to the signpost and onto the road")
	var mira: Dictionary = sim.residents[2]
	# ---- The road to the mine (issues #118, #119): watch them walk it, surveying as they go
	check(await click_button("Road to the mine"), "the map switcher shows the road")
	check(game.view_map == Road.ID and game._world._people[ada.id].visible, "the party is drawn walking the road")
	await play_until(20, func(): return ada.job == null or not ada.job.label.begins_with("Eating"))  # a meal on the way shows instead
	await look_at(Sim.rcell(ada))
	await click(screen(Sim.rcell(ada), 0.8))
	game._hud.refresh(sim)
	await frames(2)
	# The party line ("Ada and Tomas are on the road to the old mine"), not Ada's own job: she may be eating from the packs just then.
	check(game.selection.get("kind", "") == "res" and visible_label("on the road to the old mine"), "Ada can be selected on the road, and says where she's going (%s; %s)" % [game.selection, ada.job.label if ada.job != null else "idle"])
	check(await play_until(40, func(): return sim.at_site(ada) and sim.at_site(tomas)), "they reach the old mine")
	check(sim.route_surveyed(), "walking it surveyed the road")
	check(await click_button("Village"), "back to the village")
	# Mira stays home: made a lumberjack (one job each, issue #134; #177), with the village's trees marked for her
	check(await choose_job(mira, "lumber"), "the jobs board: Mira, staying home, is made a lumberjack (%s)" % mira.role)
	await key(KEY_ESCAPE)
	await look_at(Sim.rcell(mira))
	await key(KEY_X)
	await drag(screen(Vector2i(1, 1)), screen(Vector2i(sim.w - 2, sim.h - 2)))
	await key(KEY_ESCAPE)
	check(await play_until(30, func(): return mira.map == "village" and mira.job != null and mira.job.work != ""), "Mira keeps the village working (%s)" % (mira.job.label if mira.job != null else "idle"))

	# ---- The party works the site (issue #109); the player marks the rubble at the tunnel's end
	await key(KEY_TAB)
	check(game.view_map == OldMine.ID, "Tab: the old mine")
	await key(KEY_X)
	var rubble := Vector2i(12, 12)
	await look_at(rubble)
	await click(screen(rubble, 0.5))
	await key(KEY_ESCAPE)
	game._hud.refresh(sim)
	await frames(2)
	var rb: Array = sim.get_map(OldMine.ID).boulders.filter(func(b): return b.cell == rubble)
	check(not rb.is_empty() and rb[0].des, "X, then click: the rubble at the end of the tunnel is marked")
	check(find_button("The party is here") != null and visible_label("Bring back cobblestone"), "the party panel shows the party at work and its objective")

	# ---- The iron discovery (issue #111): the game stops; Investigate
	check(await play_until(400, func(): return not sim.pending.is_empty()), "mining near the vein finds it, and the game stops")
	await frames(3)
	check(not sim.pending.is_empty() and sim.pending[0].kind == "discovery" and game.speed == 0, "a discovery choice, with the game paused")
	check(visible_label("The game is paused until you choose."), "the choice says the game waits for it")
	check(await click_button("Investigate"), "click Investigate")
	check(sim.pending.is_empty() and sim.expedition.get("survey", false), "someone goes to survey the vein")
	await key(KEY_QUOTELEFT)
	check(await play_until(120, func(): return sim.get_map(OldMine.ID).discovered), "the vein is surveyed")
	check(sim.plan_targets(OldMine.ID).any(func(x): return x.item == "iron_ore"), "iron is a known resource now")
	# Mark an iron block and a coal block, clear of the loose ceilings: 4 iron ore and 3 coal.
	await key(KEY_X)
	for c in [Vector2i(12, 14), Vector2i(5, 10)]:
		await look_at(c)
		await click(screen(c, 0.5))
	await key(KEY_ESCAPE)
	check(await play_ticks_until(400, func(): return sim.expedition.get("cargo", {}).get("iron_ore", 0) >= 3 and sim.expedition.cargo.get("coal", 0) >= 3), "the party mines and packs iron ore and coal (%s, load %d of %d, %s)" % [sim.expedition.get("cargo", {}), sim.pack_load(), Sim.pack_capacity(sim.expedition), _seen.filter(func(t): return "Heading home" in t or "Back from" in t or "hurt" in t)])

	# ---- A serious injury (issue #110): triggered here, then answered with Retreat
	sim.on_map(OldMine.ID, sim.injure.bind(tomas, 2, "a cave-in"))
	await play(1)
	await frames(3)
	check(not sim.pending.is_empty() and sim.pending[0].kind == "injury" and game.speed == 0, "a serious injury stops the game (pending %s, speed %d, tomas hurt %d at_site %s leg %s seen %s)" % [sim.pending, game.speed, tomas.hurt, sim.at_site(tomas), sim.expedition.get("leg", ""), _seen.filter(func(t): return "hurt" in t or "Heading" in t)])
	check(await click_button("Retreat"), "click Retreat")
	check(sim.expedition.get("leg", "") == "home" and sim.expedition.home_why.begins_with("retreat"), "the party heads home")
	await key(KEY_QUOTELEFT)
	await key(KEY_TAB)
	await key(KEY_TAB)
	await key(KEY_TAB)
	check(game.view_map == "village", "Tab, past the road and the meadow, back to the village")

	# ---- Return and unloading (issue #112)
	check(await play_until(120, func(): return sim.expedition.is_empty()), "the party gets home")
	check(seen("Back from the old mine: ") and seen("Tomas seriously injured"), "the report says what came back and who was hurt")
	check(await play_until(20, func(): return tomas.job != null and tomas.job.kind == "rest"), "Tomas rests in bed to heal (hurt %d, %s)" % [tomas.hurt, tomas.job.kind if tomas.job != null else "idle"])
	check(tomas.hurt == 2, "still seriously hurt while he rests")
	check(await play_until(400, func(): return sim.stacks_where(func(st): return st.get("cargo", false)).is_empty() and count("iron_ore") >= 3), "the cargo is hauled to the stockpile (left %s, iron ore %d)" % [sim.stacks_where(func(st): return st.get("cargo", false)).map(func(st): return [st.type, st.n]), count("iron_ore")] + " zone %d free %s jobs %s" % [sim.zone.size(), sim.zone_dest("cobble"), sim.residents.map(func(r): return [r.name, r.map, r.job.label if r.job != null else "idle", r.role])])

	# ---- Smelting and an iron pickaxe (issue #104)
	var fire = null
	for s in sim.sites:
		if s.tpl == "fireplace" and s.done:
			fire = s
	game._select(fire)
	check(game.craft_menu_open and await queue_recipe("Smelt iron", 3), "queue 3 Smelt iron at the fireplace")
	await key(KEY_ESCAPE)
	check(await play_until(200, func(): return count("iron_ingot") >= 3), "3 iron ingots are smelted")
	check(await open_bench_panel() and await queue_recipe("Iron pickaxe"), "queue an iron pickaxe")
	await key(KEY_ESCAPE)
	check(await play_until(200, func(): return sim.residents.any(func(r): return r.pick != null and r.pick.type == "iron_pick") or not sim.tool_items("pick", 2).is_empty()), "an iron pickaxe is made")
	# ---- The road's work (issues #119, #121), from the signpost: the bridge, the cut, and the line
	await look_at(sim.route_sign())
	await click(screen(sim.route_sign(), 1.4))
	game._hud.refresh(sim)
	await frames(2)
	check(game.selection.get("kind", "") == "route" and visible_label("A stream: people wade across slowly") and visible_label("A rocky cut: 3 boulders"), "the signpost's route report names the stream and the cut")
	if count("plank") < 12:  # the bridge's planks: queued at the bench, as a player would
		check(await open_bench_panel() and await queue_recipe("Planks", 3), "queue planks for the bridge")
		await key(KEY_ESCAPE)
		await look_at(sim.route_sign())
		await click(screen(sim.route_sign(), 1.4))
	check(await click_button("Build the bridge") and not sim.bridge().is_empty(), "click Build the bridge")
	check(await click_button("Clear the cut") and sim.cut_boulders().all(func(b): return b.des), "click Clear the cut")
	check(await play_until(400, func(): return sim.bridge().get("done", false) and sim.cut_boulders().is_empty()), "villagers carry planks out to build the bridge, and mine the cut (%s planks)" % count("plank"))
	check(seen("The bridge over the stream is built"), "a toast says the bridge is built")
	check(await click_button("Plan the line"), "click Plan the line")
	game._hud.refresh(sim)
	await frames(2)
	check(visible_label("12 rails") and visible_label("Saves about"), "it shows the rails the line takes and the time it saves")
	check(await click_button("Lay track") and range(Road.segment_count()).all(func(i): return sim.track_state(i) == "planned"), "Lay track plans a track blueprint on every segment")
	# ---- The stations (issue #123), one at each end of the road
	if count("plank") < 12:
		check(await open_bench_panel() and await queue_recipe("Planks", 3), "queue planks for the stations")
		await key(KEY_ESCAPE)
	await look_at(sim.route_sign())
	await click(screen(sim.route_sign(), 1.4))
	check(await click_button("Build the village station") and await click_button("Build the mine station"), "click Build the village station, then the mine station")
	check(await play_until(400, func(): return sim.station("village").get("done", false) and sim.station("mine").get("done", false)), "villagers carry planks and cobblestone out and build both stations (%s planks, %s cobblestone)" % [count("plank"), count("cobble")])
	check(seen("The station at the village end of the line is built"), "a toast says so")
	check(await play_until(Tuning.HEAL_TIME[2] * 2 + 60, func(): return tomas.hurt == 0), "Tomas heals and goes back to work")

	# ---- Deeper levels (issue #132): a second trip, to dig to the door at the end of the old mine,
	# go down and mine on Level 2
	await look_at(board.origin)
	await click(screen(board.origin, 1.0))
	game._hud.refresh(sim)
	await frames(2)
	check(await pick_location("Old mine"), "the board: pick the old mine again")
	check(await plan_wants("Coal", 0, true), "send the party for coal")
	check(await click_button("picks less"), "no spare pickaxe")
	var goer0 := sim.resident(game.plan.party[0])
	if goer0.pick == null:  # set up by command: whoever's free first may have lost theirs on the last trip
		goer0.pick = {"type": "stone_pick", "tier": 2, "dur": 25}
	check(goer0.pick != null, "whoever goes has a pickaxe")
	check(await click_button("Start packing"), "click Start packing")
	check(await play_until(240, func(): return sim.depart_blocker() == ""), "packed again (%s)" % sim.depart_blocker())
	check(await click_button("Depart"), "click Depart")
	var goer: Dictionary = sim.resident(sim.expedition.party[0])
	check(await play_until(120, func(): return sim.at_site(goer)), "%s reaches the old mine" % goer.name)
	sim.expedition.policy = {"target": false, "full": true, "low": true}
	check(await click_button("Old mine") and game.view_map == OldMine.ID, "show the old mine")
	check(await click_button("Dig to the door"), "click Dig to the door in the party panel")
	for i in 4:  # a fall or a cave-in on the way is luck: healed by command, so the door still gets tested
		if await play_until(60, func(): return not sim.pending.is_empty() or goer.hurt > 0) and goer.hurt > 0:
			if not sim.pending.is_empty() and sim.pending[0].kind == "injury":
				sim.choose("press_on")  # a serious one too: pressed on, then healed
			if sim.pending.is_empty():
				goer.hurt = 0
				goer.heal = 0.0
	check(await play_until(60, func(): return not sim.pending.is_empty()), "the party mines its way to the door, and the game stops (%s)" % [[goer.map, goer.job.label if goer.job != null else "idle", goer.pick, goer.hurt, sim.get_map(OldMine.ID).door_state, sim.get_map(OldMine.ID).boulders.filter(func(b): return b.alive and b.des).map(func(b): return b.cell), sim.expedition.get("leg", ""), sim.expedition.get("home_why", ""), sim.pack_load()]])
	await frames(3)
	check(not sim.pending.is_empty() and sim.pending[0].kind == "door" and visible_label("A door down"), "a choice: the door down")
	check(await click_button("Go down now"), "click Go down now")
	await key(KEY_QUOTELEFT)
	var two_id := MineLevels.level_id(2)
	check(await play_until(60, func(): return goer.map == two_id and sim.at_site(goer)), "%s walks through the door into Level 2" % goer.name)
	check(await click_button("Old mine, level 2") and game.view_map == two_id, "the map switcher shows Level 2")
	var packed_before: int = sim.pack_load()
	check(await play_until(120, func(): return sim.pack_load() > packed_before), "the party mines and packs on Level 2")
	if sim.expedition.get("leg", "") != "home":  # unless its return policy already sent it
		check(await click_button("Call the party home"), "call the party home")
	check(await play_until(200, func(): return sim.expedition.is_empty()), "home up through Level 1 and the road")
	check(seen("Back from the old mine, level 2: "), "the report is from Level 2")

	# ---- Every stall had a reason the player could act on
	var unknown: Array = _blockers.keys().filter(func(why): return not ACTIONABLE.any(func(a): return a in why))
	check(unknown.is_empty(), "every blocker named its fix (%d seen; unclear: %s)" % [_blockers.size(), unknown])

	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	print("\n%s" % ("PLAYTEST PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures else 0)


## Steps like play(), noting every blocker the stuck list shows.
func play(seconds: float) -> void:
	await super(seconds)
	for s in game.sim.stuck:
		if not s.waiting and not s.hidden:
			_blockers[s.why] = true


## Like play_until, but checks after every tick, to act at a precise moment: here, before the
## party packs its spare stone and fills the packs.
func play_ticks_until(seconds: float, cond: Callable) -> bool:
	for i in int(seconds * Tuning.TPS):
		if cond.call():
			break
		game.sim.step()
		for ev in game.sim.events:
			if ev.type == "toast":
				_seen.append(ev.text)
		game.sim.events.clear()
	await play(0)
	return cond.call()
