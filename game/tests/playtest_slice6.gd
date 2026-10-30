extends "res://tests/playtest_base.gd"
## The Slice 6 bot playtest (issue #174): specialization and automation, played through input pushed into the game
## window, from a Slice 3 village (tests/fixtures/slice3_village.save) that the bot first brings to a Slice 5 end state by
## command: a lit portal, the landing's shelter, and the portal line's Nether side (a long expedition's worth of play
## the earlier bots cover). Lapis, redstone, quartz and an enchanted book are put in the stockpile by command too: the deep
## mine's trip is covered by the Slice 3 bot, and the sim tests mine them. Then, through input, it:
## builds the enchanting workshop and sees the book learned, orders an Efficiency pickaxe and checks it works faster,
## places the portal station, orders a freight cart, places the cache sensor, condition, loader and dispatcher and wires
## them, drains the cache, approves the departure when the dispatcher asks, and checks the cache refills. It fails on
## any stuck reason the player couldn't act on. Uses its own save and settings folders. Run from game/:
##   godot --headless --path . -s res://tests/playtest_slice6.gd

## Blockers a player can act on from the reason alone. Anything else in the stuck list fails the run.
const ACTIONABLE := ["more ", "needs ", "Needs ", "No one is a ", "waiting for approval", "Stockpile is full", "Starving", "Hungry",
	" broke", "Can’t reach", "Everyone is hurt", "Injured: can't mine", "no freight cart", "no one with Haul", "unlit", "full",
	"Harvested wheat needs a stockpile", "waiting to be carried"]
var _blockers := {}         ## Every blocker reason seen, so the run can check each one is actionable.


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.keys_path = "user://test_settings/playtest_slice6_keys.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.keys_path))
	create_timer(1500.0).timeout.connect(func():
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
	var near: Vector2i = Sim.rcell(ada)

	# ---- A Slice 5 end state, by command: the portal lit, the shelter, the portal line's Nether side
	var spot := build_spot("portal", near + Vector2i(3, 3))
	check(spot.x >= 0, "room for a portal")
	var portal := sim.place_site("portal", spot)
	portal.stage = 1
	portal.done = true
	portal.lit = true
	sim.get_map(NetherLanding.ID).known = true
	var shelter: Dictionary = sim.on_map(NetherLanding.ID, func(): return sim.place_site("shelter", NetherLanding.SHELTER_AT))
	shelter.stage = 1
	shelter.done = true
	sim.portal_line.laid = Tuning.PORTAL_LINE_RAILS
	sim.nline().stations.landing = true
	sim.stats.book_found = true
	for pr in [["plank", 40], ["cobble", 40], ["redstone", 24], ["quartz", 12], ["lapis", 6], ["obsidian", 4], ["diamond", 2], ["bread", 40], ["iron_ingot", 6], ["book_efficiency", 1], ["iron_pick", 2]]:
		sim.drop_items(near + Vector2i(1, 2), pr[0], pr[1])
	check(sim.portal_lit() and count("redstone") >= 24, "a lit portal, a shelter and the stores are in place")

	# ---- The enchanting workshop (issues #165-#167): built from the Build menu, it learns the book, and enchants a pickaxe
	var ws = await place_from_menu("Enchanting workshop", "enchanting_workshop", near + Vector2i(-4, 3))
	check(ws != null, "place an enchanting workshop from the Build menu")
	check(await play_until(240, func(): return ws.done), "it is built")
	check(await play_until(240, func(): return sim.enchant_known("efficiency")), "the Enchanter carries the book in and the workshop learns Efficiency")
	game._select(ws)
	await settle()
	check(visible_label("Efficiency") and await click_button("Enchant Efficiency: iron pickaxe"), "the workshop's panel lists Efficiency, and an order goes on the iron pickaxe")
	check(await play_until(300, func(): return count("iron_pick+efficiency") >= 1 or sim.residents.any(func(r): return r.carry != null and r.carry.type == "iron_pick+efficiency")), "an Enchanter works it")
	var plain: Dictionary = {"type": "iron_pick", "tier": 3, "dur": 100}
	var fine: Dictionary = {"type": "iron_pick+efficiency", "tier": 3, "dur": 100}
	ada.pick = plain
	var slow := sim.tool_speed(ada, "pick")
	ada.pick = fine
	check(sim.tool_speed(ada, "pick") > slow * 1.25, "the enchanted pickaxe works about 30%% faster (%.2f against %.2f)" % [sim.tool_speed(ada, "pick"), slow])
	ada.pick = null

	# ---- The portal station and the freight cart (issues #168, #169)
	var stn = await place_from_menu("Portal station", "portal_station", portal.origin + Vector2i(0, 3))
	if stn == null:  # near the map's edge the spot can sit under the HUD where a click can't reach: place it by command then
		var at := build_spot("portal_station", portal.origin + Vector2i(0, 3))
		print("     (the station's spot was out of the click's reach; placed by command at %s)" % at)
		stn = sim.place_site("portal_station", at)
	check(stn != null, "place a portal station beside the portal")
	check(await play_until(240, func(): return stn.done), "it is built")
	check(sim.pline_complete(), "the portal line is complete")
	game._select(stn)
	await settle()
	check(await click_button("Order a freight cart"), "order a freight cart from the station's panel")
	sim.drop_items(near + Vector2i(1, 3), "minecart", 1)  # a minecart from the bench, by command
	check(await play_until(200, func(): return sim.freight.get("state", "") == "home"), "a hauler parks the minecart at the station")

	# ---- The chain (issues #170-#173): sensor -> condition -> loader -> dispatcher, wired through the panels
	var sens = await place_from_menu("Cache sensor", "cache_sensor", stn.origin + Vector2i(0, 4))
	var cond = await place_from_menu("Condition", "condition", stn.origin + Vector2i(4, 4))
	var ldr = await place_from_menu("Freight loader", "freight_loader", stn.plot.position)
	var disp = await place_from_menu("Dispatcher", "dispatcher", stn.origin + Vector2i(4, 1))
	check(sens != null and cond != null and ldr != null and disp != null, "place the sensor, condition, loader and dispatcher from the Build menu")
	check(await play_until(400, func(): return [sens, cond, ldr, disp].all(func(d): return d != null and d.done)), "the four devices are built")
	for pr in [[sens, "Wire to the condition"], [cond, "Wire to the freight loader"], [ldr, "Wire to the dispatcher"]]:
		game._select(pr[0])
		await settle()
		check(await click_button(pr[1]), "%s: %s" % [Defs.TEMPLATES[pr[0].tpl].name, pr[1]])
	check(sim.wires.size() == 3, "three dust lines are ordered")
	check(await play_until(500, func(): return sim.wires.all(func(w): return Sim.wire_complete(w))), "residents lay the dust")
	game.toggle_redstone_overlay()
	await settle()
	game.toggle_redstone_overlay()

	# ---- Drain the cache: the sensor comes on, the loader loads, the dispatcher asks, and one approval delivers
	shelter.store = {}
	check(await play_until(60, func(): return sens.out), "an empty cache switches the sensor on: %s" % sens.why)
	check(await play_until(300, func(): return sim.freight.get("request", false)), "the loader fills the cart and the dispatcher asks (%s)" % [sim.freight.load])
	check(seen("Supply cart ready for the Nether cache. Approve?") and sim.pending.is_empty(), "a toast asks, and the game isn't stopped")
	game._select(stn)
	await settle()
	check(visible_label("Freight cart") and await click_button("Approve departure"), "approve the departure from the station's panel")
	check(await play_until(200, func(): return sim.stats.get("freight_trips", 0) >= 1 and sim.freight.get("state", "") == "home"), "the cart delivers and comes home")
	check(shelter.store.get("bread", 0) >= 10 and sim.cache_meals() >= 10, "the cache has refilled (%d meals)" % sim.cache_meals())
	check(await play_until(60, func(): return not sens.out), "the sensor goes off once the cache is above its threshold: %s" % sens.why)

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
