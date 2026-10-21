extends "res://tests/playtest_base.gd"
## The Slice 3 bot playtest (issue #113): the first expedition, played through input pushed into the
## game window, from a Slice 2 village (tests/fixtures/slice2_village.save) so the founding isn't
## replayed. It builds the expedition board, plans a trip for Ada and Tomas, packs and departs,
## works the old mine, answers the iron discovery with Investigate and a serious injury with Retreat,
## watches the return and unloading, then smelts iron and crafts an iron pickaxe. It fails on any
## stuck reason the player couldn't act on. Uses its own save and settings folders. Run from game/:
##   godot --headless --path . -s res://tests/playtest_slice3.gd

## Blockers a player can act on from the reason alone. Anything else in the stuck list fails the run.
const ACTIONABLE := ["more ", "Needs a pickaxe", "No one does ", "Stockpile is full", "Starving", "Hungry",
	" broke", "Can’t reach", "No meals to pack", "No spare pickaxes to pack", "No pickaxe left",
	"Everyone is hurt", "Investigating the vein needs", "Harvested wheat needs a stockpile",
	"Meadow has no sheep left", "Injured: can't mine"]
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
	check(game.planner_open and visible_label("Old mine"), "selecting the board opens the planner")
	check(await click_button("Tomas"), "add Tomas")
	check(await click_button("Stone"), "send them for stone")
	for i in 2:
		await click_button("target more")
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
	check(await play_until(90, func(): return ada.away and tomas.away), "they carry the packs to the signpost and take the road")
	var mira: Dictionary = sim.residents[2]
	check(await play_until(Tuning.MINE_TRIP + 30, func(): return sim.at_site(ada) and sim.at_site(tomas)), "they reach the old mine")
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
	# Mark two iron blocks and two coal blocks, clear of the loose ceilings.
	await key(KEY_X)
	for c in [Vector2i(12, 14), Vector2i(13, 14), Vector2i(5, 10), Vector2i(12, 5)]:
		await look_at(c)
		await click(screen(c, 0.5))
	await key(KEY_ESCAPE)
	check(await play_ticks_until(400, func(): return sim.expedition.get("cargo", {}).get("iron_ore", 0) >= 3 and sim.expedition.cargo.get("coal", 0) >= 3), "the party mines and packs iron ore and coal (%s, %s)" % [sim.expedition.get("cargo", {}), _seen.filter(func(t): return "Heading home" in t or "Back from" in t or "hurt" in t)])

	# ---- A serious injury (issue #110): triggered here, then answered with Retreat
	sim.on_map(OldMine.ID, sim.injure.bind(tomas, 2, "a cave-in"))
	await play(1)
	await frames(3)
	check(not sim.pending.is_empty() and sim.pending[0].kind == "injury" and game.speed == 0, "a serious injury stops the game (pending %s, speed %d, tomas hurt %d at_site %s leg %s seen %s)" % [sim.pending, game.speed, tomas.hurt, sim.at_site(tomas), sim.expedition.get("leg", ""), _seen.filter(func(t): return "hurt" in t or "Heading" in t)])
	check(await click_button("Retreat"), "click Retreat")
	check(sim.expedition.get("leg", "") == "home" and sim.expedition.home_why.begins_with("retreat"), "the party heads home")
	await key(KEY_QUOTELEFT)
	await key(KEY_TAB)

	# ---- Return and unloading (issue #112)
	check(await play_until(Tuning.MINE_TRIP + 90, func(): return sim.expedition.is_empty()), "the party gets home")
	check(seen("Back from the old mine: ") and seen("Tomas seriously injured"), "the report says what came back and who was hurt")
	check(await play_until(240, func(): return sim.stacks_where(func(st): return st.get("cargo", false)).is_empty() and count("iron_ore") >= 3), "the cargo is hauled to the stockpile")
	check(tomas.hurt == 2 and tomas.job != null and tomas.job.kind == "rest", "Tomas rests in bed to heal")

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
	check(await play_until(Tuning.HEAL_TIME[2] * 2 + 60, func(): return tomas.hurt == 0), "Tomas heals and goes back to work")

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
