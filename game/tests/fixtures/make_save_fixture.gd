extends SceneTree
## Writes tests/fixtures/save_v<VERSION>.save: a real save from the middle of the opening, taken
## while Tomas is walking in (a state that has to be rebuilt on load). Run it once per new save
## format version, from game/:
##   godot --headless --path . -s res://tests/fixtures/make_save_fixture.gd
## Never regenerate an existing fixture: old fixtures are what prove old saves still load.


func _initialize() -> void:
	var sim := Sim.new_game()
	# v15 to v21 switched Ada's Toolsmith on here (#91); from v22 Ada does everything (#134).
	sim.designate_mine(area(0, 0, 10, 18))
	if SaveFormat.VERSION >= 6:
		sim.designate_hunt(Rect2i(0, 0, sim.w, sim.h))  # wool for the beds
	var bench := sim.place_site("bench", at(8, 10))
	_run(sim, 120)
	for r in ["planks", "planks", "sticks", "wood_pick"]:
		sim.queue_add(bench, r)
	if SaveFormat.VERSION >= 27:  # the founding's tools goal is an axe and a pickaxe (#182)
		sim.queue_add(bench, "wood_axe")
	_run(sim, 120)
	sim.paint_zone(area(10, 7, 4, 2))
	sim.designate_mine(Rect2i(0, 0, sim.w, sim.h))
	_run(sim, 150)
	sim.place_site("house", at(11, 0))
	for i in 8:
		sim.queue_add(bench, "planks")
	_run(sim, 600)
	if SaveFormat.VERSION >= 27:  # 3 sheep from #182: the second bed's wool, as if fetched from the meadow
		sim.drop_items(at(10, 6), "wool", 3)
	sim.place_site("house", at(1, 4), 1)
	if SaveFormat.VERSION >= 8:
		sim.paint_farm(area(15, 15, 2, 2))  # wheat planted and growing when saved
	if SaveFormat.VERSION >= 9:  # a fireplace blueprint with its reserved kitchen plot
		for c in [at(14, 9), at(4, 12), at(2, 1), at(15, 2)]:
			if sim.placement_check("fireplace", c) == "":
				sim.place_site("fireplace", c)
				break
	for i in 8:
		sim.queue_add(bench, "planks")
	if SaveFormat.VERSION >= 22:  # with no toolsmith keeping spares (#134), Ada makes her next pickaxe herself
		sim.queue_add(bench, "stone_pick")
	var walked := 0
	for i in 1200 * Tuning.TPS:
		sim.step()
		if sim.residents.size() == 2 and sim.residents[1].arriving:
			walked += 1
			if walked >= Tuning.TPS:  # a second into the walk
				break
	sim.queue_add(bench, "stone_axe")
	# v10 to v21 saved Ada with Haul at priority 1 and Hunt off; from v22 each resident has one job (#134).
	if SaveFormat.VERSION >= 22:
		sim.set_role(sim.residents[1], "farm")  # not the job Tomas arrived with, unless he's a farmer
	if SaveFormat.VERSION >= 11:
		sim.residents[0].jobs.build.xp = 30  # a level-3 builder
	# v13 to v19 saved a meadow part-way to regaining a sheep (meadow_sheep 5, meadow_regrow 60); from
	# v20 the meadow is a map of its own (below).
	if SaveFormat.VERSION >= 23 and sim.residents[0].pick == null:  # saplings (#177) change the random numbers: she still has one to keep
		sim.residents[0].pick = {"type": "stone_pick", "tier": 2, "dur": 20}
	if SaveFormat.VERSION >= 23 and sim.residents[0].pick == null:  # saplings (#177) change the random numbers: she still has one to keep
		sim.residents[0].pick = {"type": "stone_pick", "tier": 2, "dur": 20}
	if SaveFormat.VERSION >= 12 and sim.residents[0].pick != null:
		sim.residents[0].kept.pick = true  # a pickaxe she was told to equip
	if SaveFormat.VERSION >= 3:
		var ada: Dictionary = sim.residents[0]
		var tree = Sim.nearest(sim.trees.filter(func(t): return t.alive), Sim.rcell(ada))
		if tree != null:
			sim.queue_order(ada, tree)
		else:
			sim.queue_order(ada, null, Sim.rcell(ada) + Vector2i(1, 0))
		sim.queue_order(ada, null, Sim.rcell(ada))
	if not (sim.residents.size() == 2 and sim.residents[1].arriving):
		printerr("Tomas isn't walking in; the fixture would miss that case.")
		quit(1)
		return
	var camera := {"target": Vector3(9, 0, 9), "size": 17.0}
	if SaveFormat.VERSION >= 15:  # Mira at the old mine, mining, with the mine in view (issues #100-#102)
		var mine := sim.get_map(OldMine.ID)
		mine.known = true
		mine.visited = true
		var mira := sim.add_resident("Mira", Sim.TRAVELERS[1][1], Vector2i(0, 0))
		mira.pick = {"type": "stone_pick", "tier": 2, "dur": 20}
		if SaveFormat.VERSION >= 22:
			sim.set_role(mira, "mine" if SaveFormat.VERSION == 22 else "mason")  # one job each (#134): added by hand, she'd have none; Mine split in two in v23 (#177)
		if SaveFormat.VERSION >= 24:  # a stonemason works from her mason's bench (#184)
			for c in [at(16, 12), at(1, 14), at(14, 14), at(12, 16), at(16, 16)]:
				if sim.placement_check("mason_bench", c) == "":
					var mb := sim.place_site("mason_bench", c)
					mb.stage = 1
					mb.done = true
					break
			sim.assign_workstations()
		sim.move_to_map(mira, OldMine.ID, mine.entrance)
		sim.on_map(OldMine.ID, func(): sim.designate_mine(Rect2i(0, 0, mine.w, mine.h)))
		sim.use_map(OldMine.ID)
		for i in 40 * Tuning.TPS:  # only the mine moves on, so Tomas is still mid-walk in the village
			sim.tick += 1
			sim._step_map()
		sim.use_map("village")
		camera = {"map": OldMine.ID, "maps": {"village": camera, OldMine.ID: {"target": Vector3(6, 0, 8), "size": 14.0}}}
	if SaveFormat.VERSION == 16:  # Ada packing to leave for the old mine, part-packed (issues #105-#107)
		var board := {}
		for c in [at(14, 9), at(4, 12), at(2, 1), at(15, 2), at(16, 12), at(1, 14)]:
			if sim.placement_check("board", c) == "":
				board = sim.place_site("board", c)
				break
		board.stage = 1
		board.done = true
		var plan := sim.new_plan()
		plan.party = [sim.residents[0].id]
		plan.target = {"item": "coal", "n": 6}
		plan.meals = 2
		plan.picks = 1
		var err := sim.plan_expedition(plan)
		if err != "":
			printerr("The expedition couldn't be planned: ", err)
			quit(1)
			return
		board.store = {"bread": 1, "stone_pick": 1}
		board.tools = [{"type": "stone_pick", "dur": 7}]
	if SaveFormat.VERSION >= 17:  # Mira's expedition at the old mine: packs part-full, Mira hurt, iron found (#109-#111)
		var board := {}
		for c in [at(14, 9), at(4, 12), at(2, 1), at(15, 2), at(16, 12), at(1, 14)]:
			if sim.placement_check("board", c) == "":
				board = sim.place_site("board", c)
				break
		board.stage = 1
		board.done = true
		var mira: Dictionary = sim.residents[2]
		sim.expedition = {"dest": OldMine.ID, "board": board.id, "party": [mira.id], "target": {"item": "coal", "n": 6},
			"meals": 3, "picks": 1, "policy": {"target": true, "full": true, "low": true}, "spend_return": false,
			"state": "out", "leg": "out", "packed": {"bread": 3}, "tools": [{"type": "stone_pick", "dur": 7}],
			"provisions": {"bread": 2}, "cargo": {"coal": 3}, "broken": 0, "hurt": {"Mira": 1}, "unpacked": true}
		mira.hurt = 1
		mira.heal = Tuning.HEAL_TIME[1]
		sim.on_map(OldMine.ID, func(): sim._find_vein())
		sim.on_map(OldMine.ID, func(): sim._ask("discovery", "The party found an iron vein in the old mine.", [
			{"id": "keep", "label": "Keep mining", "cost": "Carry on."}, {"id": "investigate", "label": "Investigate", "cost": "Survey it."},
			{"id": "return", "label": "Mark it and return later", "cost": "Head home now."}]))
		sim.events.clear()
	if SaveFormat.VERSION >= 18:  # the road walked, the bridge part-supplied, the line planned and its first segment laid (#118-#121)
		var rd := sim.road()
		rd.known = true
		rd.seen = Road.segment_count()
		sim.plan_bridge()
		sim.bridge().store = {"plank": 4}
		sim.plan_line()
		var first := sim.track_site(0)
		first.stage = 1
		first.done = true
		first.laid = Tuning.RAILS_PER_SEGMENT
	if SaveFormat.VERSION >= 19:  # a half-laid segment, rails at the railhead, the village station built and the cart parked (#122-#124)
		var second := sim.track_site(1)
		second.laid = 1
		sim.on_map(Road.ID, sim.drop_items.bind(Road.RAILHEAD, "rail", 3))
		sim.plan_station("village")
		sim.station("village").stage = 1
		sim.station("village").done = true
		sim.plan_station("mine")
		sim.cart = {"at": "village", "x": Sim.station_x("village"), "state": "parked", "load": {}, "riders": [], "acc": 0.0}
	if SaveFormat.VERSION >= 20:  # Level 2 open, a block mined there; the meadow visited, a cow and a pig hunted, pigs growing back (#132, #137, #138)
		var mine := sim.get_map(OldMine.ID)
		sim.on_map(OldMine.ID, sim.open_door.bind(OldMine.ID))
		var two := sim.get_map(MineLevels.level_id(2))
		two.visited = true
		two.boulders[0].alive = false
		var mead := sim.get_map(Meadow.ID)
		mead.known = true
		mead.visited = true
		for sp in ["cow", "pig"]:
			for a in mead.sheep:
				if a.species == sp:
					a.alive = false
					break
		mead.regrow = {"pig": 60.0}
		var crop: Dictionary = sim.farm.values()[0]  # the meadow's animals change the village's random numbers: make sure wheat grows
		if crop.grow < 0.0 and not sim.items.has(crop.cell):
			crop.grow = 30.0
		if mine.door_state != "open":
			printerr("Level 1's door didn't open.")
			quit(1)
			return
	if SaveFormat.VERSION >= 21:  # pens at the meadow: one built, with a fed pair of cows and a calf, one part-built; Mira in a leather tunic and boots, a cap lying in the village (#139, #140)
		var mead := sim.get_map(Meadow.ID)
		sim.on_map(Meadow.ID, func():
			for r in [Rect2i(16, 16, 6, 5), Rect2i(17, 6, 5, 5)]:
				var why := sim.paint_pen(r)
				if why != "":
					printerr("A pen couldn't be painted: ", why)
			var built: Dictionary = mead.pens[0]
			for c in Sim.pen_edge(built):
				sim._put_fence(built, c)
			var inside := Sim.pen_inside(built)
			var cows: Array = mead.sheep.filter(func(a): return a.alive and a.species == "cow").slice(0, 2)
			for i in cows.size():
				var c := inside.position + Vector2i(i, 0)
				cows[i].cell = c
				cows[i].pos = Vector2(c)
				cows[i].dest = null
				cows[i].pen = built.id
				cows[i].fed_at = sim.tick - 10 * Tuning.TPS
			var calf := sim.add_animal(inside.position + Vector2i(1, 1), "cow")
			calf.pen = built.id
			calf.young = true
			calf.grown_at = sim.tick + 100 * Tuning.TPS
			var part: Dictionary = mead.pens[1]
			for c in Sim.pen_edge(part).slice(0, 5):
				sim._put_fence(part, c))
		var mira: Dictionary = sim.residents[2]
		mira.armor = {"chest": {"type": "leather_tunic", "dur": 5}, "feet": {"type": "leather_boots", "dur": Tuning.ARMOR_USES}}
		sim.drop_items(Sim.rcell(sim.residents[0]) + Vector2i(1, 0), "leather_cap", 1)
		sim.expedition.sticks = 0
		sim.expedition.wheat = 0
		sim.expedition.supplies = {}
		sim.events.clear()
	if SaveFormat.VERSION >= 23:  # a chopping block with logs in its pile, a sapling growing, a tree kept, saplings lying about (#177)
		var block := {}
		for c in [at(4, 12), at(2, 1), at(15, 2), at(16, 12), at(1, 14), at(14, 14)]:
			if sim.placement_check("chopping_block", c) == "":
				block = sim.place_site("chopping_block", c)
				break
		block.stage = 1
		block.done = true
		block.keep = 25
		var pile: Vector2i = Sim.pile_cells(block)[0]
		sim.items.erase(pile)
		sim.drop_items(pile, "log", 6)
		var spot = sim.plant_cell([block], block.origin)
		sim.trees.append({"id": sim._id(), "kind": "tree", "cell": spot, "logs": 5, "alive": true, "des": false,
			"claim": 0, "unreach_until": 0, "grow": 90.0})
		var kept = Sim.nearest(sim.trees.filter(func(t): return t.alive and Sim.grown(t)), block.origin)
		kept.keep = true
		sim.drop_items(Sim.rcell(sim.residents[0]) + Vector2i(0, 1), "sapling", 2)
		sim.set_role(sim.residents[1], "lumber")
		sim.events.clear()
	if SaveFormat.VERSION >= 24:  # Tomas claims the chopping block; a composter stands free, with nobody farming (#184)
		for c in [at(2, 1), at(15, 2), at(16, 12), at(1, 14), at(14, 14), at(12, 16)]:
			if sim.placement_check("composter", c) == "":
				var comp := sim.place_site("composter", c)
				comp.stage = 1
				comp.done = true
				break
		sim.assign_workstations()
		if not sim.sites.any(func(st): return st.tpl == "chopping_block" and st.worker == sim.residents[1].id):
			printerr("Tomas didn't claim the chopping block.")
			quit(1)
			return
		sim.events.clear()
	if SaveFormat.VERSION >= 25:  # the village keeps 4 sheep from its hunters (#183)
		sim.set_herd_floor("sheep", 4)
	if SaveFormat.VERSION >= 26:  # the chopping block keeps 15 planks, and has a batch queued by hand (#178)
		var block: Dictionary = sim.sites.filter(func(st): return st.tpl == "chopping_block")[0]
		sim.set_make_keep(block, 15)
		sim.queue_add(block, "saw_planks")
	if SaveFormat.VERSION >= 28:  # a storehouse with 2 chests, holding logs and a pickaxe (#189)
		for c in [at(14, 12), at(2, 13), at(13, 14), at(0, 12)]:
			if sim.placement_check("storehouse", c) == "":
				var sh := sim.place_site("storehouse", c)
				sh.stage = 2
				sh.done = true
				sh.chests = 2
				sim._occ_dirty = true
				var slots := Sim.store_slots(sh)
				sim._store_put(slots[0], "log", 12)
				sim._store_put(slots[9], "stone_pick", 1, 17)
				break
	var path := "res://tests/fixtures/save_v%d.save" % SaveFormat.VERSION
	var data := {"summary": Goals.progress_text(sim), "tick": sim.tick, "saved_at": 1792440000,
		"state": sim.save_state(), "camera": camera, "speed": 1}
	if SaveFormat.write(ProjectSettings.globalize_path(path), data):
		print("wrote ", path, " at tick ", sim.tick)
		quit(0)
	else:
		quit(1)


func _run(sim: Sim, seconds: float) -> void:
	for i in int(seconds * Tuning.TPS):
		sim.step()


## A cell or area of the original 18×18 opening, in today's map (issue #52 moved it to the middle).
static func at(x: int, y: int) -> Vector2i:
	return Vector2i(x, y) + Tuning.OPENING_OFFSET


static func area(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(Vector2i(x, y) + Tuning.OPENING_OFFSET, Vector2i(w, h))
