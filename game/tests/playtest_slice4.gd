extends "res://tests/playtest_base.gd"
## The Slice 4 bot playtest (issue #125): route investment, played through input pushed into the game
## window, from a Slice 3 village with iron on hand (tests/fixtures/slice3_village.save). A first trip
## to the old mine surveys the road on foot. Then, from the signpost and the bench: the bridge, the
## cut, both stations, rails and a minecart, and the line, laid by the village's track crew. A second
## trip rides the cart. The round trip must be shorter than on foot and mining at the mine no faster,
## and every stall must name its fix. Uses its own save and settings folders. Run from game/:
##   godot --headless --path . -s res://tests/playtest_slice4.gd

## Blockers a player can act on from the reason alone. Anything else in the stuck list fails the run.
const ACTIONABLE := ["more ", "Needs a pickaxe", "No one is a ", "Stockpile is full", "Starving", "Hungry",
	" broke", "Can’t reach", "No meals to pack", "No spare pickaxes to pack", "No pickaxe left",
	"Everyone is hurt", "Harvested wheat needs a stockpile", "Meadow has no sheep left", "Injured: can't mine",
	"Track: needs", "Track: no one is a builder"]
var _blockers := {}         ## Every blocker reason seen, so the run can check each one is actionable.


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.keys_path = "user://test_settings/playtest_slice4_keys.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.keys_path))
	create_timer(1200.0).timeout.connect(func():
		printerr("FAIL the playtest stopped (a script error?) and timed out")
		quit(1))
	root.add_child(game)
	await frames(3)
	game.save_dir = "user://playtest_saves"
	check(await click_button("Play"), "click Play")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(game.save_dir))
	var slot := game._slot_path(1)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/fixtures/slice3_village.save"), ProjectSettings.globalize_path(slot))
	check(game.load_slot(1) == "", "load the Slice 3 village")
	await frames(3)
	await key(KEY_QUOTELEFT)  # paused throughout: only play() moves time on
	var sim := game.sim
	var ada: Dictionary = sim.residents[0]
	check(count("iron_ingot") >= 11 and sim.road().known and not sim.route_surveyed(), "a Slice 3 village: iron on hand, the road known but not walked")

	# ---- The first trip, on foot: it surveys the road (issues #118, #119)
	var foot := await trip(sim, ada)
	check(foot.road > 0.0, "Ada walks to the old mine and back (%.0f s on the road)" % foot.road)
	check(sim.route_surveyed(), "the first trip surveys the road")
	check(seen("The road to the mine is surveyed"), "a toast says so, with the walking time")

	# ---- The signpost: the route report, the bridge, the cut and the stations (issues #119, #123)
	await open_signpost(sim)
	check(visible_label("A stream: people wade across slowly") and visible_label("A rocky cut: 3 boulders"), "the route report names the stream and the cut")
	check(visible_label("about %d s on foot each way" % roundi(sim.route_walk_time())), "and the walk's estimate")
	check(await click_button("Build the bridge") and not sim.bridge().is_empty(), "click Build the bridge")
	check(await click_button("Clear the cut") and sim.cut_boulders().all(func(b): return b.des), "click Clear the cut")
	check(await click_button("Build the village station") and await click_button("Build the mine station"), "click Build the village station and the mine station")
	# ---- Rails and a minecart at the bench (issue #120)
	check(await open_bench_panel() and await queue_recipe("Rails"), "queue rails at the bench")
	check(await queue_recipe("Minecart"), "queue a minecart")
	await key(KEY_ESCAPE)
	check(await play_until(200, func(): return count("rail") + sim.railhead_rails() >= 16 or sim.road().sites.any(func(s): return s.tpl == "track")), "16 rails are crafted")
	check(await play_until(200, func(): return count("minecart") >= 1 or not sim.cart.is_empty()), "and a minecart")
	# ---- Plan the line (issue #121)
	await open_signpost(sim)
	check(await click_button("Plan the line"), "click Plan the line")
	game._hud.refresh(sim)
	await frames(2)
	check(visible_label("12 rails, with") and visible_label("Saves about"), "the preview shows the rails it takes and the time it saves")
	check(await click_button("Lay track") and range(Road.segment_count()).all(func(i): return sim.track_state(i) != "none"), "Lay track plans the line")
	# ---- The crew lays it (issue #122), and the cart is parked (issue #123)
	check(await play_until(900, func(): return sim.bridge().get("done", false) and sim.cut_boulders().is_empty()), "the village builds the bridge and clears the cut")
	check(await play_until(900, func(): return sim.station("village").get("done", false) and sim.station("mine").get("done", false)), "and builds both stations")
	check(await play_until(900, func(): return sim.line_complete()), "the track crew lays the whole line (%d of 6)" % range(Road.segment_count()).filter(func(i): return sim.track_state(i) == "built").size())
	check(seen("Carrying rails to the railhead") and seen("Laying track"), "rails go out to the railhead, then are laid")
	check(await play_until(300, func(): return sim.cart_ready()), "the minecart is hauled out and parked at the village station")
	for i in 3:  # Tab through the maps to the road
		if game.view_map != Road.ID:
			await key(KEY_TAB)
	check(game.view_map == Road.ID, "Tab: the road to the mine")
	await look_at(Vector2i(Road.STATIONS.village.x + 1, Road.STATIONS.village.y))
	await click(screen(Vector2i(Road.STATIONS.village.x + 1, Road.STATIONS.village.y), 0.3))
	game._hud.refresh(sim)
	await frames(2)
	check(visible_label("The cart is parked at the village end") and visible_label("6 of 6 segments laid"), "the village station shows the cart parked and the line laid (view %s, selected %s)" % [game.view_map, game.selection])
	await click_button("Village")

	# ---- The second trip, by cart (issue #124)
	var cart := await trip(sim, ada, true)
	check(cart.rode, "Ada rides the cart both ways")
	check(cart.road < foot.road, "the round trip on the road is shorter by cart (%.0f s, against %.0f s on foot)" % [cart.road, foot.road])
	check(cart.mining > 0.0 and foot.mining > 0.0 and absf(cart.mining - foot.mining) / foot.mining < 0.1, "mining at the mine is no faster (%.2f s a block, against %.2f s, each for a level-1 miner in the light)" % [cart.mining, foot.mining])
	check(cart.platform, "the cargo is unloaded onto the village station's platform")
	check(seen("By cart: "), "the report gives the time on the road and the time saved")
	check(await play_until(200, func(): return sim.road().items.values().all(func(st): return not st.get("cargo", false))), "the cargo is hauled from the platform to the stockpile")

	# ---- Every stall had a reason the player could act on
	var unknown: Array = _blockers.keys().filter(func(why): return not ACTIONABLE.any(func(a): return a in why))
	check(unknown.is_empty(), "every blocker named its fix (%d seen; unclear: %s)" % [_blockers.size(), unknown])

	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	print("\n%s" % ("PLAYTEST PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures else 0)


## Selects the signpost on the village's east edge, which shows the route.
func open_signpost(sim: Sim) -> void:
	if game.view_map != "village":
		await click_button("Village")
	game.selection = {}
	await look_at(sim.route_sign())
	await click(screen(sim.route_sign(), 1.4))
	game._hud.refresh(sim)
	await frames(2)
	check(game.selection.get("kind", "") == "route", "the signpost shows the road to the old mine")


## Plans and sends Ada alone to the old mine for 3 coal, through the planner, and plays until she's
## home and unpacked. Returns how long she spent on the road there and back, whether she rode, whether
## cargo came off at the village platform, and her mining time a block, normalised to a level-1 miner
## in the light, with a full belly.
func trip(sim: Sim, ada: Dictionary, by_cart := false) -> Dictionary:
	var board = null
	for s in sim.sites:
		if s.tpl == "board" and s.done:
			board = s
	check(await play_until(120, func(): return sim.cant_join(ada) == ""), "Ada is free to go (%s)" % sim.cant_join(ada))
	game.selection = {}
	await look_at(board.origin)
	await click(screen(board.origin, 1.0))
	if not game.planner_open:  # the board is small: select it as a click on its panel would
		game._select(board)
	game._hud.refresh(sim)
	await frames(2)
	check(game.planner_open, "selecting the board opens the planner")
	check(await click_button("Adventure: Old mine"), "pick the old mine from the adventures list")
	await settle()
	game.plan = sim.new_plan()
	game._hud.refresh(sim)
	await frames(2)
	await click_button("Coal")
	for i in 10:
		if game.plan.target.n <= 3:
			break
		await click_button("target less")
	check(game.plan.party == [ada.id] and game.plan.target == {"item": "coal", "n": 3}, "the plan: Ada for 3 coal (%s)" % [game.plan])
	if by_cart:
		check(visible_label("Includes the cart's %d" % Tuning.CART_CAPACITY), "the packs include the cart's room")
	check(await click_button("Start packing"), "click Start packing")
	check(await play_until(240, func(): return sim.depart_blocker() == ""), "the supplies are packed (%s)" % sim.depart_blocker())
	check(await click_button("Depart"), "click Depart")
	var out := {"road": 0.0, "rode": false, "platform": false, "mining": 0.0}
	var work_ticks := 0.0
	var blocks := 0
	var started := -1
	var norm := 1.0
	var target = null
	for i in 400 * Tuning.TPS:
		sim.step()
		for r in sim.residents:
			if r.job != null and not _seen.has(r.job.label):
				_seen.append(r.job.label)
		for ev in sim.events:
			if ev.type == "toast":
				_seen.append(ev.text)
		sim.events.clear()
		if not sim.pending.is_empty():  # a find or an injury: carry on mining
			sim.choose(sim.pending[0].options[0].id)
		if ada.map == Road.ID and not sim.expedition.is_empty():
			out.road += 1.0 / Tuning.TPS
			if sim.cart.get("riders", []).has(ada.id):
				out.rode = true
		if sim.cart.get("state", "") == "unloading" and sim.cart.at == "village":
			out.platform = true
		# Mining at the mine: each block's work, from the first stroke until it's broken.
		if ada.map == OldMine.ID and ada.job != null and ada.job.kind == "gather" and ada.progress >= 0.0:
			if started < 0:
				started = sim.tick
				target = ada.job.target
				norm = Sim.skill_speed(ada, "mason") * Sim.hurt_speed(ada) * (Tuning.DARK_WORK if sim.on_map(OldMine.ID, sim.get_map(OldMine.ID).is_dark.bind(Sim.rcell(ada))) else 1.0) * (Tuning.HUNGRY_SPEED if ada.hunger < Tuning.HUNGRY_BELOW else 1.0)
		elif started >= 0 and target != null and not target.alive:
			work_ticks += float(sim.tick - started) * norm
			blocks += 1
			started = -1
		elif started >= 0 and (ada.job == null or ada.job.kind != "gather"):
			started = -1
		if i % Tuning.TPS == 0:
			for s in sim.stuck:
				if not s.waiting and not s.hidden:
					_blockers[s.why] = true
		if sim.expedition.is_empty() and ada.map == "village":
			break
	check(sim.expedition.is_empty(), "the trip is over (%s)" % sim.expedition.get("leg", ""))
	out.mining = work_ticks / Tuning.TPS / maxi(1, blocks)
	game._hud.refresh(sim)
	await frames(3)
	return out
