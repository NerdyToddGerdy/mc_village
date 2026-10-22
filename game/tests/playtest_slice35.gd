extends "res://tests/playtest_base.gd"
## The Slice 3.5 bot playtest (issue #142): the meadow adventure, played through input pushed into the
## game window, from a Slice 3 village (tests/fixtures/slice3_village.save). It paints a pen at the
## meadow and marks two cows to lead into it, opens the adventures list and picks the meadow, plans a
## trip with sticks and wheat, packs and departs. At the meadow the party builds the pen, leads the
## cows in and feeds them, and hunts cows and a pig the player marks. Home again, it unloads, cooks
## beef, crafts a leather tunic and sees it worn, then plans a mine trip and checks the planner's
## protection line, and runs it. On the way it opens each tally group's dropdown and checks its counts
## (#141). It fails on any stuck reason the player couldn't act on. Uses its own save and settings
## folders. Run from game/:
##   godot --headless --path . -s res://tests/playtest_slice35.gd

## Blockers a player can act on from the reason alone. Anything else in the stuck list fails the run.
const ACTIONABLE := ["more ", "Needs a pickaxe", "No one does ", "Stockpile is full", "Starving", "Hungry",
	" broke", "Can’t reach", "No meals to pack", "No spare pickaxes to pack", "No pickaxe left",
	"Everyone is hurt", "Harvested wheat needs a stockpile", "Injured: can't mine", "Track: needs",
	"No sticks to pack", "No wheat to pack"]
var _blockers := {}         ## Every blocker reason seen, so the run can check each one is actionable.


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.keys_path = "user://test_settings/playtest_slice35_keys.cfg"
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
	var mead := sim.get_map(Meadow.ID)
	check(not sim.expedition_board().is_empty() and mead.known, "a Slice 3 village: the board is built, and the meadow is known")

	# ---- The tally bar's groups (issue #141): each dropdown lists its items with the sim's counts
	await tally_dropdowns(sim)

	# ---- A pen at the meadow (issue #139): the Paint menu's Pen, dragged out near the entrance
	check(await click_button("Meadow") and game.view_map == Meadow.ID, "the map switcher shows the meadow")
	await look_at(mead.entrance + Vector2i(-5, 0))
	check(await click_button("Paint") and await click_button("Pen"), "pick Pen in the Paint menu")
	check(game.tool == "pen", "Pen is on")
	var spot: Rect2i = sim.on_map(Meadow.ID, func(): return pen_spot(sim))
	check(spot.position.x >= 0, "room for a 4×4 pen on screen (%s)" % spot)
	await drag(screen(spot.position), screen(spot.end - Vector2i.ONE))
	check(mead.pens.size() == 1 and Rect2i(mead.pens[0].rect) == spot, "dragging paints a 4×4 pen (%s)" % [mead.pens.map(func(p): return p.rect)])
	var pen: Dictionary = mead.pens[0]
	await look_at(pen.gate)
	await click(screen(pen.gate, 0.4))
	await settle()
	check(game.selection.get("kind", "") == "pen" and visible_label("room for 4") and visible_label("12 sticks more"), "clicking a fence selects the pen: room for 4, 12 sticks to go")
	# Two cows marked to lead in, with Gather ▸ Lead to a pen.
	check(await click_button("Gather") and await click_button("Lead to a pen"), "pick Lead to a pen in the Gather menu")
	var cows: Array = []
	for i in 2:
		var cow = Sim.nearest(mead.sheep.filter(func(a): return a.alive and a.species == "cow" and not a.get("lead", false)), pen.gate)
		await look_at(cow.cell)
		await click(screen(cow.cell, 0.4))
		cows.append(cow)
	await key(KEY_ESCAPE)
	check(cows.all(func(a): return a.get("lead", false)), "clicking two cows marks them to lead into a pen")
	await click(screen(cows[0].cell, 0.4))
	await settle()
	check(visible_label("Marked to lead into a pen"), "a marked cow's panel says so")

	# ---- Supplies for the pen: sticks from the bench, wheat from the farms
	check(await click_button("Village"), "back to the village")
	if count("stick") < 12:
		check(await open_bench_panel() and await queue_recipe("Sticks", 3), "queue sticks for the fences")
		await key(KEY_ESCAPE)
		check(await play_until(120, func(): return count("stick") >= 12), "12 sticks are made (%d)" % count("stick"))
	if count("wheat") < 2:  # set up by command: the fixture's farms may have just been harvested into bread
		sim.drop_items(Sim.rcell(ada) + Vector2i(0, 2), "wheat", 2)
	check(count("wheat") >= 2, "2 wheat in the village")

	# ---- The adventures list (issue #136): pick the meadow, plan, pack and depart
	check(await open_adventures(sim), "the meadow signpost's planner leads back to all the adventures")
	check(await click_button("Adventure: Meadow"), "the adventures list: pick the meadow")
	await settle()
	check(game.adventure == Meadow.ID and game.plan.sticks == 12, "a meadow plan packs the pen's 12 sticks (%s)" % game.plan.get("sticks", -1))
	var other: Dictionary = sim.residents.filter(func(r): return r.id != ada.id and sim.cant_join(r) == "")[0]
	if not game.plan.party.has(other.id):
		check(await click_button(other.name), "add %s" % other.name)
	check(await click_button("Beef"), "send them for beef")
	check(await click_button("wheat more") and await click_button("wheat more"), "and 2 wheat to feed the cows")
	for i in 3:
		await click_button("meals more")
	check(await click_button("Target reached"), "home when the packs are full, or nothing's left")
	check(visible_label("Armor against the hazards"), "the planner shows the party's armor")
	var plan: Dictionary = game.plan
	check(plan.target.item == "beef" and plan.wheat == 2 and plan.sticks == 12 and plan.party.size() == 2, "the plan: two of them, beef, 12 sticks and 2 wheat (%s)" % [plan])
	check(await click_button("Start packing"), "click Start packing")
	check(await play_until(240, func(): return sim.depart_blocker() == ""), "the meals, sticks and wheat are packed (%s)" % sim.depart_blocker())
	check(await click_button("Depart"), "click Depart")
	var party: Array = sim.expedition.party.map(func(id): return sim.resident(id))
	check(await play_until(120, func(): return party.all(func(r): return sim.at_site(r))), "they reach the meadow")

	# ---- At the meadow: a pig marked to hunt; the pen built, the cows led in and fed
	check(await click_button("Meadow") and game.view_map == Meadow.ID, "show the meadow")
	await key(KEY_G)
	var pig = Sim.nearest(mead.sheep.filter(func(a): return a.alive and a.species == "pig"), mead.entrance)
	await look_at(pig.cell)
	await click(screen(pig.cell, 0.3))
	await key(KEY_ESCAPE)
	check(pig.des, "G, then click: a pig is marked to hunt")
	check(await play_until(200, func(): return Sim.pen_done(pen)), "the party builds the pen with the sticks it packed")
	check(seen("A pen is finished"), "a toast says the pen is finished")
	check(await play_until(150, func(): return cows.all(func(a): return a.get("pen", 0) == pen.id)), "they lead the two cows into the pen")
	check(await play_until(120, func(): return cows.all(func(a): return a.get("fed_at", -1) >= 0 or a.get("cool_until", 0) > 0)), "and feed them wheat")
	check(await play_until(200, func(): return not pig.alive), "they hunt the marked pig")
	check(await play_until(400, func(): return sim.expedition.get("leg", "") == "home"), "and hunt cows for beef until they head home (%s)" % sim.expedition.get("home_why", ""))
	check(await play_until(120, func(): return mead.sheep.any(func(a): return a.alive and a.get("young", false) and a.pen == pen.id)), "a calf is born in the pen")
	check(seen("A calf was born in the pen"), "a toast says so")

	# ---- Home: unloading, and cooking beef
	check(await click_button("Village"), "back to the village")
	check(await play_until(200, func(): return sim.expedition.is_empty()), "the party gets home and unpacks")
	check(seen("Back from the meadow: ") and _seen.any(func(t): return t.begins_with("Back from the meadow") and "raw beef" in t and "leather" in t and "porkchop" in t), "the report lists beef, leather and porkchops")
	var fire = null
	for s in sim.sites:
		if s.tpl == "fireplace" and s.done:
			fire = s
	game._select(fire)
	check(game.craft_menu_open and await queue_recipe("Cooked beef"), "queue Cooked beef at the fireplace")
	await key(KEY_ESCAPE)
	check(await play_until(200, func(): return count("cooked_beef") >= 1 or sim.residents.any(func(r): return r.carry != null and r.carry.type == "cooked_beef")), "beef is cooked")

	# ---- A leather tunic (issue #140): crafted at the bench, and worn
	if count("leather") < 8:  # set up by command: a tunic takes more leather than one trip's cows give
		sim.drop_items(Sim.rcell(ada) + Vector2i(1, 2), "leather", 8 - count("leather"))
	check(await open_bench_panel() and await queue_recipe("Leather tunic"), "queue a leather tunic at the bench")
	await key(KEY_ESCAPE)
	check(await play_until(200, func(): return sim.residents.any(func(r): return Sim.armor_worn(r).has("chest"))), "the tunic is crafted and someone puts it on")
	var wearer: Dictionary = sim.residents.filter(func(r): return Sim.armor_worn(r).has("chest"))[0]
	await frames(2)
	check((game._world._people[wearer.id].get_node("Body/Shirt") as MeshInstance3D).material_override.albedo_color == Palette.ITEM_COLORS.leather, "%s is drawn in it" % wearer.name)
	await select_resident(wearer)
	check(visible_label("15% guard"), "%s's panel shows the tunic's guard" % wearer.name)

	# ---- A mine trip with the tunic on: the planner's protection line
	check(await open_adventures(sim), "back to the adventures list")
	check(await click_button("Adventure: Old mine"), "the adventures list: pick the old mine")
	await settle()
	for id in game.plan.party.duplicate():
		if id != wearer.id:
			check(await click_button(sim.resident(id).name), "take %s off the party" % sim.resident(id).name)
	if not game.plan.party.has(wearer.id):
		check(await click_button(wearer.name), "send %s" % wearer.name)
	await settle()
	check(visible_label("Armor against the hazards: %s 15%%" % wearer.name), "the planner shows %s's armor against the mine's hazards" % wearer.name)
	if wearer.pick == null:  # set up by command: whoever wears the tunic may have no pickaxe of their own
		wearer.pick = {"type": "stone_pick", "tier": 2, "dur": 25}
	check(await click_button("Coal") and await click_button("Start packing"), "send them for coal")
	check(await play_until(240, func(): return sim.depart_blocker() == ""), "packed (%s)" % sim.depart_blocker())
	check(await click_button("Depart"), "click Depart")
	for i in 3:  # a serious injury on the way is luck: answered with Retreat
		if await play_until(300, func(): return sim.expedition.is_empty() or not sim.pending.is_empty()) and not sim.pending.is_empty():
			await click_button("Retreat")
			await key(KEY_QUOTELEFT)
	check(await play_until(300, func(): return sim.expedition.is_empty()), "the mine trip comes home")
	check(seen("Back from the old mine"), "with its report")

	# ---- Every stall had a reason the player could act on
	var unknown: Array = _blockers.keys().filter(func(why): return not ACTIONABLE.any(func(a): return a in why))
	check(unknown.is_empty(), "every blocker named its fix (%d seen; unclear: %s)" % [_blockers.size(), unknown])

	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	print("\n%s" % ("PLAYTEST PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures else 0)


## A 4×4 pen near the meadow's entrance, where one can go and both corners are on screen.
func pen_spot(sim: Sim) -> Rect2i:
	var e: Vector2i = sim.m.entrance
	for d in range(3, 12):
		for dy in range(-d, d + 1):
			var r := Rect2i(e + Vector2i(-d - 3, dy), Vector2i(4, 4))
			if sim.pen_check(r) == "" and in_middle(screen(r.position)) and in_middle(screen(r.end - Vector2i.ONE)):
				return r
	return Rect2i(-1, -1, 0, 0)


## Opens the adventures list through the meadow signpost: its planner's "All adventures". The fixture's
## board stands behind a house, where the fixed camera can't see it to click.
func open_adventures(sim: Sim) -> bool:
	if game.view_map != "village" and not await click_button("Village"):
		return false
	var sign := sim.meadow_sign()
	await look_at(sign)
	await click(screen(sign, 1.2))
	await settle()
	if not await click_button("Plan a trip to the meadow"):
		return false
	await settle()
	var ok := await click_button("All adventures")
	await settle()
	return ok


## Hovers each tally group's button and checks its dropdown's counts against the sim (issue #141).
func tally_dropdowns(sim: Sim) -> void:
	var hud = game._hud
	hud.refresh(sim)  # the HUD refreshes every 0.15 s; the loaded village's groups show on the first
	await frames(2)
	for g in ["building", "food", "tools"]:
		var b: Button = hud._group_btns[g]
		if not b.is_visible_in_tree():
			continue
		await move(b.get_global_rect().get_center())
		await frames(2)
		hud.refresh(sim)
		await frames(2)
		check(hud._tools_drop.visible and hud._drop_group == g, "hovering %s opens its dropdown" % b.get_meta("name"))
		if g == "building":
			var logs := 0
			for k in sim.items:
				if sim.items[k].type == "log":
					logs += sim.items[k].n
			var row := find_button("Pin log")
			check(row != null and row.get_parent().get_children().any(func(n): return n is Label and n.text == str(logs)), "it lists logs with the sim's count (%d)" % logs)
		if g == "food":
			check(visible_label("Meals on hand") and visible_label("Raw meat to cook"), "Food splits meals from raw meat")
	await move(Vector2(640, 400))
	await frames(2)
	check(not hud._tools_drop.visible, "moving away closes it")
	await move(hud._group_btns.building.get_global_rect().get_center())
	await frames(2)
	check(await click_button("Pin log"), "pin logs from the Building dropdown")
	await move(Vector2(640, 400))
	await frames(2)
	hud.refresh(sim)
	check(game.keys.pinned == ["log"] and hud._tallies.get_children().any(func(n): return n is VBoxContainer and n.get_child(0).get_child(0).text == "Logs"), "logs show in the bar on their own")


## Steps like play(), noting every blocker the stuck list shows.
func play(seconds: float) -> void:
	await super(seconds)
	for s in game.sim.stuck:
		if not s.waiting and not s.hidden:
			_blockers[s.why] = true
