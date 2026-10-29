extends SceneTree
## Headless sim tests. Run from the game/ folder:
##   godot --headless --path . -s res://tests/run_tests.gd
## Words after `--` run only the tests whose names contain one of them:
##   godot --headless --path . -s res://tests/run_tests.gd -- farm fireplace
## Exits with code 1 if any test fails, or if no test matches.

var _failures := 0
var _checks := 0
var _current := ""
var _opening = null  ## The played opening's save and its sites' ids, played once for every test that needs it.
## Seconds to allow for walking the road to the mine, one way (issue #118).
const ROAD := 30.0


func _init() -> void:
	var tests := [
		"test_full_opening",
		"test_founding_goals",
		"test_bench_skips_blocked_recipes_and_comes_before_building",
		"test_auto_ingredients_from_the_start",
		"test_blueprint_clears_trees_and_boulders",
		"test_bigger_clearing",
		"test_sheep_wander_and_replay",
		"test_hunting_sheep",
		"test_beds_and_free_bed_arrivals",
		"test_hunger_and_eating",
		"test_farm_plant_grow_harvest",
		"test_farm_plots_need_open_grass",
		"test_fireplace_reserves_a_kitchen_plot",
		"test_fireplace_cooks_and_keeps_meals_stocked",
		"test_one_job_each",
		"test_skills_rise_and_pay_off",
		"test_toolsmith_keeps_spares",
		"test_equip_a_chosen_tool",
		"test_mine_marks_trees_and_boulders",
		"test_save_and_load_mid_game",
		"test_tool_breaks_and_resident_reports",
		"test_every_save_fixture_still_loads",
		"test_v1_tools_get_full_uses_when_upgraded",
		"test_dropped_tools_keep_their_wear",
		"test_queued_orders_run_in_turn",
		"test_mine_drag_limited_to_one_kind",
		"test_upgrades_run_in_order",
		"test_newer_or_damaged_saves_are_refused",
		"test_save_file_round_trip",
		"test_erasing_stockpile_cells",
		"test_standing_orders_wait_rather_than_block",
		"test_craft_patterns_match_their_recipes",
		"test_spares_need_a_resident_toolsmith",
		"test_residents_only_work_on_their_own_map",
		"test_save_and_load_two_maps",
		"test_old_mine_layout_and_ore",
		"test_site_report_and_depletion",
		"test_mine_items_are_hauled_and_counted",
		"test_smelting_and_iron_tools",
		"test_expedition_board",
		"test_planning_an_expedition",
		"test_staging_and_departure",
		"test_travel_to_the_mine_and_back",
		"test_return_and_unloading",
		"test_party_works_the_site",
		"test_hazards_and_injuries",
		"test_iron_discovery",
		"test_slice2_fixture_loads",
		"test_deep_mine_materials",
		"test_the_portal",
		"test_the_guard_and_iron_gear",
		"test_the_nether_landing",
		"test_nether_hazards",
		"test_auto_combat",
		"test_the_shelter_and_cache",
		"test_scouting_the_routes",
		"test_mission_types",
		"test_the_quartz_site",
		"test_nether_and_overworld_together",
		"test_the_portal_goes_out",
		"test_expedition_slots",
		"test_old_expedition_moves_to_the_overworld_slot",
		"test_road_to_the_mine",
		"test_survey_and_obstacles",
		"test_rails_and_minecarts",
		"test_plan_the_line",
		"test_track_crew_and_railhead",
		"test_stations_and_the_cart",
		"test_ride_the_line",
		"test_mine_levels_are_generated",
		"test_the_door_down_and_back",
		"test_cows_and_pigs",
		"test_adventures_list",
		"test_meadow_expedition",
		"test_old_meadow_trips_come_home",
		"test_pens_and_breeding",
		"test_leather_armor",
		"test_lumberjacks_and_stonemasons",
		"test_saplings_and_replanting",
		"test_jobs_need_their_workstation",
		"test_hunters_keep_a_herd_floor",
		"test_workstations_process_materials",
		"test_storehouse_chests",
		"test_land_claims",
		"test_blueprints_clear_their_footprint",
		"test_diamonds_deep_in_the_mine",
		"test_clear_the_level",
		"test_cargo_priority_list_plans",
		"test_cargo_priority_list_at_the_site",
		"test_mason_bench_becomes_a_mineshaft",
		"test_work_areas_are_painted",
		"test_work_areas_saved",
		"test_worn_paths_wear_and_regrow",
		"test_worn_paths_pathing_and_speed",
		"test_worn_paths_saved",
		"test_founding_book_chapter_and_pages",
		"test_founding_book_save_upgrade",
	]
	var only := Array(OS.get_cmdline_user_args())
	if not only.is_empty():
		tests = tests.filter(func(t): return only.any(func(w): return w in t))
		print("%d of the tests match %s" % [tests.size(), " ".join(only)])
	for t in tests:
		_current = t
		if OS.get_environment("TEST_TRACE") != "":
			print("... %s (%d ms)" % [t, Time.get_ticks_msec()])
		call(t)
	print("\n%d checks, %d failed" % [_checks, _failures])
	# No checks means the tests never ran (for example, a script failed to compile).
	quit(1 if _failures > 0 or _checks == 0 else 0)


func check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL [%s] %s" % [_current, what])


func run(sim: Sim, seconds: float) -> void:
	for i in int(seconds * Tuning.TPS):
		sim.step()


func whole_map() -> Rect2i:
	return Rect2i(0, 0, Tuning.MAP_W, Tuning.MAP_H)


func count(sim: Sim, type: String) -> int:
	var n := 0
	for k in sim.items:
		if sim.items[k].type == type:
			n += sim.items[k].n
	return n


func stuck_text(sim: Sim) -> String:
	var parts: PackedStringArray = []
	for s in sim.stuck:
		parts.append("%s: %s" % [s.who, s.why])
	return " | ".join(parts)


## The founding moment, played: a fresh copy of it for each test, as {sim, bench, h1, h2}. It's
## played once and loaded from its save after that, because it's 1,900 seconds of play.
var _goal_trace: Array = []  ## Goals.current() after each step of the played opening (issue #182).


func opening() -> Dictionary:
	if _opening == null:
		var sim := Sim.new_game()
		var s := play_opening(sim)
		_opening = {"save": var_to_str(sim.save_state()), "ids": {}}
		for k in s:
			_opening.ids[k] = s[k].id
	var copy := Sim.from_state(str_to_var(_opening.save))
	var out := {"sim": copy}
	for k in _opening.ids:
		out[k] = copy.sites.filter(func(x): return x.id == _opening.ids[k])[0]
	return out


## Plays the founding moment the way a player would, end to end (issue #182): a stockpile, the bench,
## an axe and a pickaxe, the clearing's sheep for Ada's bed, a fireplace for the trip's meals, the
## board, the meadow for the second bed's wool, then the second house.
func play_opening(sim: Sim) -> Dictionary:
	sim.designate_mine(area(0, 0, 10, 18))
	sim.designate_hunt(whole_map())  # wool for Ada's bed
	sim.paint_zone(area(10, 7, 4, 2))
	var bench := sim.place_site("bench", at(8, 10))
	run(sim, 120)
	_goal_trace.append(Goals.current(sim))
	for r in ["wood_axe", "wood_pick"]:
		sim.queue_add(bench, r)
	run(sim, 120)
	_goal_trace.append(Goals.current(sim))
	sim.designate_mine(whole_map())
	run(sim, 150)
	_goal_trace.append(Goals.current(sim))
	var h1 := sim.place_site("house", at(11, 0))
	for i in 8:
		sim.queue_add(bench, "planks")
	run(sim, 600)
	_goal_trace.append(Goals.current(sim))
	var fire := sim.place_site("fireplace", spot(sim, "fireplace", at(6, 12)))
	var board := sim.place_site("board", spot(sim, "board", at(4, 9)))
	for r in ["sticks", "planks", "planks"]:  # the board's 4 sticks and 6 planks
		sim.queue_add(bench, r)
	run_until(sim, 400, func(): return board.done and fire.done and sim.free_count("cooked_mutton") >= 3)
	_goal_trace.append(Goals.current(sim))
	var plan := sim.new_plan(Meadow.ID)
	sim.plan_expedition(plan)
	run_until(sim, 200, func(): return sim.depart_blocker() == "")
	_goal_trace.append(Goals.current(sim))
	sim.depart()
	run_until(sim, 400, func(): return sim.expedition.is_empty())
	_goal_trace.append(Goals.current(sim))
	var h2 := sim.place_site("house", at(1, 4), 1)
	for i in 9:
		sim.queue_add(bench, "planks")
	for r in ["stone_pick", "stone_axe"]:  # her wooden tools are worn out by now
		sim.queue_add(bench, r)
	run(sim, 900)
	_goal_trace.append(Goals.current(sim))
	return {"bench": bench, "h1": h1, "h2": h2, "fire": fire, "board": board}


## Runs until `cond` holds, for at most `seconds`.
func run_until(sim: Sim, seconds: float, cond: Callable) -> void:
	for i in int(seconds * Tuning.TPS):
		if i % Tuning.TPS == 0 and cond.call():
			return
		sim.step()


## Open ground for a building of `tpl` near `near`, clear of the stockpile, farms and loose items.
func spot(sim: Sim, tpl: String, near: Vector2i) -> Vector2i:
	var size: Vector2i = Defs.TEMPLATES[tpl].size
	for d in range(0, 12):
		for dx in range(-d, d + 1):
			for dy in range(-d, d + 1):
				var o := near + Vector2i(dx, dy)
				if sim.placement_check(tpl, o) != "":
					continue
				var ok := true
				for x in size.x:
					for y in size.y:
						var c := o + Vector2i(x, y)
						ok = ok and sim.walkable(c) and not sim.items.has(c) and not sim.in_zone(c) and not sim.farm.has(c)
				if ok:
					return o
	return near


## Issue #182: a new game's founding, and finished villages from older saves stay finished.
func test_founding_goals() -> void:
	var sim := Sim.new_game()
	check(sim.sheep.size() == 3 and sim.auto_craft and Goals.current(sim) == 0, "a new game: 3 sheep, auto ingredients on, the first goal")
	var s := opening()
	check(_goal_trace.size() > 3 and range(_goal_trace.size() - 1).all(func(i): return _goal_trace[i] <= _goal_trace[i + 1]), "the founding's goals complete in order (%s)" % [_goal_trace])
	check(_goal_trace.back() == Goals.LIST.size() - 1, "and it ends on the chopping block")
	var town: Sim = s.sim
	town.place_site("chopping_block", spot(town, "chopping_block", at(2, 14)))
	run(town, 120)
	check(Goals.current(town) == -1 and Goals.progress_text(town).contains("resident"), "the chopping block finishes the founding: %s" % Goals.progress_text(town))
	for f in ["slice2_village", "slice3_village"]:
		var r := SaveFormat.read("res://tests/fixtures/%s.save" % f)
		var v := Sim.from_state(r.data.state)
		check(Goals.current(v) == -1, "%s: a finished founding stays finished (%s)" % [f, Goals.progress_text(v)])


func test_full_opening() -> void:
	var s := opening()
	var sim: Sim = s.sim
	check(s.bench.done, "bench is built")
	check(sim.stats.pick_crafted, "a pickaxe was crafted")
	check(sim.stats.broken_boulders > 0, "boulders were broken")
	check(s.h1.done and s.h2.done, "both houses are built")
	check(s.h1.owner == sim.residents[0].id, "Ada owns the first house")
	check(sim.residents.size() == 2 and sim.residents[1].name == "Tomas", "Tomas arrived")
	check(sim.stats.traveler_home, "Tomas moved in")
	check(s.h2.owner == sim.residents[1].id, "Tomas owns the second house")
	check(sim.auto_craft, "auto ingredients are on")
	check(sim.stats.axe_crafted and s.fire.done and s.board.done and sim.stats.meadow_wool, "an axe, the fireplace, the board, and wool from the meadow (%s)" % [sim.stats])
	check(Goals.current(sim) == Goals.LIST.size() - 1, "the founding is at its last goal, the chopping block (%d: %s)" % [Goals.current(sim), Goals.progress_text(sim)])
	if sim.residents.size() == 2:
		check(sim.residents[1].role == "lumber", "the first traveler is a lumberjack (%s)" % sim.residents[1].role)
	# Skills (issue #48): Ada learned by doing, and Tomas arrived skilled in one job.
	check(Sim.level(sim.residents[0], "lumber") >= 2, "Ada's Lumberjack level rose with practice (level %d)" % Sim.level(sim.residents[0], "lumber"))
	if sim.residents.size() == 2:
		var tomas: Dictionary = sim.residents[1]
		var skilled: Array = Defs.JOBS.filter(func(jb): return Sim.level(tomas, jb) >= Tuning.ARRIVAL_LEVEL)
		check(skilled.size() >= 1, "Tomas arrived skilled in a job (%s)" % [skilled])


func test_bench_skips_blocked_recipes_and_comes_before_building() -> void:
	var sim := Sim.new_game()
	sim.designate_mine(area(0, 0, 10, 18))
	var bench := sim.place_site("bench", at(8, 10))
	run(sim, 120)
	check(bench.done, "bench built")
	var house := sim.place_site("house", at(11, 4))
	house.stage = 1  # foundation already down, so the house wants planks and logs
	sim._occ_dirty = true
	for r in ["wood_axe", "planks", "planks", "sticks"]:
		sim.queue_add(bench, r)
	var labels: PackedStringArray = []
	for i in 60:
		run(sim, 2)
		var j = sim.residents[0].job
		var l: String = j.label if j != null else "Idle"
		if labels.is_empty() or labels[-1] != l:
			labels.append(l)
	var seq := " > ".join(labels)
	check(bench.queue.is_empty(), "whole queue crafted, axe included (queue left: %s)" % [bench.queue])
	var axe_at := seq.find("Crafting wooden axe")
	var house_at := seq.find("to the house")
	check(axe_at >= 0, "axe crafted after its planks and sticks")
	check(house_at < 0 or house_at > axe_at, "nothing hauled to the house before the bench queue was done: " + seq)


func test_auto_ingredients_from_the_start() -> void:
	var sim := Sim.new_game()
	check(sim.auto_craft, "a new game makes a recipe's planks and sticks automatically (issue #182)")
	sim.designate_mine(area(0, 0, 10, 18))
	var bench := sim.place_site("bench", at(8, 10))
	run(sim, 120)
	for k in sim.items.keys():
		if sim.items[k].type != "log":
			sim.items.erase(k)
	sim.queue_add(bench, "wood_pick")
	check(bench.queue.has("planks") and bench.queue.has("sticks"), "planks and sticks queued automatically: %s" % [bench.queue])
	check(bench.autoq.has(true), "auto entries are marked")
	run(sim, 80)
	check(bench.queue.is_empty(), "pickaxe made from logs alone")
	check(count(sim, "wood_pick") + (1 if sim.residents[0].pick != null else 0) >= 1, "a wooden pickaxe exists")


func test_blueprint_clears_trees_and_boulders() -> void:
	var sim := Sim.new_game()
	check(sim.placement_check("bench", at(4, 6)) == "", "tree doesn't block placement")
	var bench := sim.place_site("bench", at(4, 6))
	var tree: Dictionary = sim.trees.filter(func(t): return t.cell == at(4, 6))[0]
	check(tree.des, "tree under the blueprint is marked")
	run(sim, 120)
	check(not tree.alive and bench.done, "tree cleared and bench built from its logs")
	var house := sim.place_site("house", at(5, 3))
	var boulder: Dictionary = sim.boulders.filter(func(b): return b.cell == at(7, 5))[0]
	check(boulder.des, "boulder under the blueprint is marked")
	run(sim, 1)
	check(stuck_text(sim).contains("Needs a pickaxe to clear a boulder"), "house says what it's waiting for: " + stuck_text(sim))
	check(house.store.is_empty(), "no deliveries while the ground isn't clear")
	check(sim.placement_check("house", at(3, 3)) == "Overlaps another building", "buildings still can't overlap")


func test_bigger_clearing() -> void:
	var sim := Sim.new_game()
	check(sim.w == 32 and sim.h == 32, "a new game is 32×32")
	check(sim.trees.size() == 40 and sim.boulders.size() == 16, "40 trees and 16 boulders")
	check(Sim.rcell(sim.residents[0]) == at(9, 9), "Ada starts where the opening expects, near the middle")
	var cells := {}
	for o in sim.trees + sim.boulders:
		check(sim.in_bounds(o.cell) and not cells.has(o.cell), "%s at %s is on the map and alone" % [o.kind, o.cell])
		cells[o.cell] = true
	check(sim.walkable(Vector2i(0, sim.h - 1)), "travelers can walk in at the bottom-left corner")


func test_mine_marks_trees_and_boulders() -> void:
	var sim := Sim.new_game()
	sim.designate_mine(whole_map())
	check(sim.trees.all(func(t): return t.des), "drag marks every tree")
	check(sim.boulders.all(func(b): return b.des), "drag marks every boulder")
	var t: Dictionary = sim.trees[0]
	sim.designate_mine(Rect2i(t.cell, Vector2i.ONE), t)
	check(not t.des, "clicking a marked tree unmarks it")
	run(sim, 1)
	check(stuck_text(sim).contains("Boulder: Needs a pickaxe"), "boulders without a pickaxe are flagged")


func test_save_and_load_mid_game() -> void:
	var sim := Sim.new_game()
	sim.designate_mine(area(0, 0, 10, 18))
	sim.designate_hunt(whole_map())
	var bench := sim.place_site("bench", at(8, 10))
	run(sim, 120)
	for r in ["planks", "planks", "sticks", "wood_pick"]:
		sim.queue_add(bench, r)
	run(sim, 37.3)
	var text := var_to_str(sim.save_state())
	var loaded := Sim.from_state(str_to_var(text))
	check(loaded.tick == sim.tick, "tick restored")
	check(loaded.residents[0].job == null, "jobs are rebuilt, not saved")
	check(loaded.items.values().all(func(s): return s.res == 0), "no stale reservations")
	var b2: Dictionary = loaded.sites.filter(func(s): return s.tpl == "bench")[0]
	run(loaded, 200)
	check(b2.queue.is_empty() and loaded.stats.pick_crafted, "loaded game carries on crafting")
	loaded.paint_zone(area(10, 7, 4, 2))
	loaded.designate_mine(whole_map())
	run(loaded, 150)
	var h := loaded.place_site("house", at(11, 0))
	for i in 8:
		loaded.queue_add(b2, "planks")
	run(loaded, 900)
	check(h.done, "loaded game can still build a house (stage %d; %s)" % [h.stage, stuck_text(loaded)])


func test_tool_breaks_and_resident_reports() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	ada.axe = {"type": "wood_axe", "tier": 1, "dur": 1}
	var t: Dictionary = sim.trees[13]
	sim.direct_order(ada, t)
	run(sim, 30)
	check(not t.alive, "tree felled")
	check(ada.axe == null and ada.broken.axe, "axe broke after its last use")
	check(stuck_text(sim).contains("Axe broke. Craft one at the bench, or make someone the toolsmith"), "with no toolsmith, the report says how to fix it: " + stuck_text(sim))
	sim.designate_mine(Rect2i(sim.trees[0].cell, Vector2i.ONE))
	run(sim, 5)
	check(ada.job == null or ada.job.kind != "gather", "resident stops chopping until a new axe exists")


## Every fixture in tests/fixtures must keep loading after any change to the save format.
func test_every_save_fixture_still_loads() -> void:
	for v in range(1, SaveFormat.VERSION + 1):
		var path := "res://tests/fixtures/save_v%d.save" % v
		var r := SaveFormat.read(path)
		check(not r.has("error"), "v%d fixture reads: %s" % [v, r.get("error", "")])
		if r.has("error"):
			continue
		check(r.data.v == SaveFormat.VERSION, "v%d fixture is upgraded to the current version" % v)
		var sim := Sim.from_state(r.data.state)
		check(sim.tick == r.data.tick, "v%d: tick restored" % v)
		var size := Vector2i(sim.w, sim.h)
		var want := Vector2i(18, 18) if v < 4 else Vector2i(Tuning.MAP_W, Tuning.MAP_H) + (Vector2i(Tuning.CLAIM_DEPTH, 0) if v >= 29 else Vector2i.ZERO)  # v29's village has one claim
		check(size == want, "v%d: map size is %s" % [v, size])
		check(sim.residents.size() == (3 if v >= 15 else 2) and sim.residents[1].arriving, "v%d: Tomas is walking in again after loading" % v)
		if v < 27:  # upgraded from before the founding's rework (issue #182): two houses cover the steps it added
			check(Goals.current(sim) == Goals.LIST.size() - 2 and sim.auto_craft, "v%d: the founding lands on Welcome a traveler, with auto ingredients on (%s)" % [v, Goals.progress_text(sim)])
		var mine := sim.get_map(OldMine.ID)
		if v >= 15:  # issues #100-#102: Mira at the old mine, with coal she's mined
			var mira: Dictionary = sim.residents[2]
			check(mira.map == OldMine.ID and mine.visited and mine.known, "v%d: Mira is still at the old mine" % v)
			check(sim.on_map(OldMine.ID, count.bind(sim, "coal")) > 0 and count(sim, "coal") == 0, "v%d: the mine's coal stays at the mine" % v)
			check(OldMine.LAYOUT.size() == mine.h and sim.ore_left(OldMine.ID, "coal") < 6, "v%d: the mine's mined-out coal stays mined" % v)
			if v >= 17:  # issues #109-#111: Mira's expedition at the mine, hurt, with the iron found and a choice waiting
				var ex: Dictionary = sim.expedition
				check(ex.get("state", "") == "out" and ex.party == [sim.residents[2].id] and ex.provisions == {"bread": 2} and ex.cargo == {"coal": 3}, "v%d: the party's packs survive" % v)
				check(sim.residents[2].hurt == 1 and sim.residents[2].heal > 0.0, "v%d: Mira is still hurt" % v)
				check(mine.found and not mine.discovered and sim.pending.size() == 1 and sim.pending[0].kind == "discovery", "v%d: the find and the waiting choice survive" % v)
			elif v >= 16:  # issues #105-#107: Ada packing at the board, part-packed
				var bd := sim.expedition_board()
				check(sim.expedition.get("state", "") == "staging" and sim.expedition.party == [sim.residents[0].id], "v%d: the expedition is still packing, with Ada" % v)
				check(bd.store.get("bread", 0) == 1 and bd.tools.size() == 1 and bd.tools[0].dur == 7, "v%d: what's packed stays packed, a tool with its wear" % v)
			else:
				check(sim.expedition.is_empty(), "v%d: no expedition in an older save" % v)
		else:  # issue #100: an older save is all village, and gets an unvisited old mine
			check(sim.residents.all(func(r): return r.map == "village") and sim.sites.all(func(s): return s.map == "village"), "v%d: everyone and everything is on the village map" % v)
			check(not mine.known and not mine.visited and sim.ore_left(OldMine.ID, "coal") == 6, "v%d: an unvisited old mine is added" % v)
			check(mine.boulders.all(func(b): return sim.maps.village.boulders.all(func(o): return o.id != b.id) and b.id < sim.next_id), "v%d: the mine's ids don't clash with the village's" % v)
		if v < 16:
			check(sim.residents.all(func(r): return r.trip == ("meadow" if r.away else "")), "v%d: anyone away is at the meadow" % v)
		var rd := sim.road()
		if v >= 18:  # issues #118-#121: the road walked, the bridge part-supplied, the line planned with one segment laid
			check(rd.known and sim.route_surveyed() and sim.bridge().store == {"plank": 4} and not sim.bridge().done, "v%d: the survey and the part-supplied bridge survive" % v)
			check(sim.track_state(0) == "built" and range(1, 6).all(func(i): return sim.track_state(i) == "planned"), "v%d: the planned line survives" % v)
			check(sim.track_site(0).laid == Tuning.RAILS_PER_SEGMENT, "v%d: a laid segment counts its rails laid" % v)
		if v >= 19:  # issues #122-#124: a half-laid segment, the railhead pile, a station and the parked cart
			check(sim.track_site(1).laid == 1 and sim.railhead_rails() == 3, "v%d: the half-laid segment and the railhead pile survive" % v)
			check(sim.station("village").done and not sim.station("mine").done and sim.cart.at == "village", "v%d: the stations and the parked cart survive" % v)
		elif v == 18:
			check(sim.cart.is_empty() and sim.station("village").is_empty(), "v%d: no cart or stations yet" % v)
		else:  # an older save gets the road, unwalked, known if the old mine is
			check(rd.known == mine.known and rd.seen == 1 and rd.sites.is_empty(), "v%d: the road to the mine is added, unwalked" % v)
		var two_id := MineLevels.level_id(2)
		if v >= 20:  # issues #132, #137: Level 2 open with a block mined; the meadow's hunted animals and regrowth
			check(sim.maps.has(two_id) and mine.door_state == "open" and sim.get_map(two_id).pattern == MineLevels.family(sim.seed, 2), "v%d: Level 2 and the open door survive" % v)
			check(not sim.get_map(two_id).boulders[0].alive and sim.get_map(two_id).known, "v%d: what's mined on Level 2 stays mined" % v)
			var mead := sim.get_map(Meadow.ID)
			var calves := 1 if v >= 21 else 0  # v21 adds a calf in a pen
			check(mead.visited and mead.regrow.get("pig", 0.0) == 60.0 and sim.herds().pig == Meadow.herd().pig - 1 and sim.herds().cow == Meadow.herd().cow - 1 + calves, "v%d: the meadow's herds and regrowth survive" % v)
		else:  # issue #132: the old mine is Level 1, its door not reached, with a boulder in front of it
			check(mine.level == 1 and mine.door == Vector2i(15, 8) and mine.door_state == "closed" and not sim.maps.has(two_id), "v%d: the old mine gets its door, not yet reached" % v)
			check(mine.boulders.any(func(b): return b.cell == Vector2i(14, 8)) and not sim.on_map(OldMine.ID, sim.walkable.bind(Vector2i(14, 8))) and sim.seed == Tuning.SEED, "v%d: with a boulder in front of it, and the game's seed" % v)
			check(sim.get_map(Meadow.ID).known == mine.known, "v%d: the meadow is known if the old mine is" % v)
		if v >= 21:  # issues #139, #140: a built pen with a fed pair and a calf, a part-built one; Mira's armor
			var mead := sim.get_map(Meadow.ID)
			check(mead.pens.size() == 2 and Sim.pen_done(mead.pens[0]) and mead.pens[1].built.size() == 5 and mead.gates.has(mead.pens[0].gate), "v%d: the pens and their fences survive" % v)
			var penned: Array = mead.sheep.filter(func(a): return a.alive and a.get("pen", 0) == mead.pens[0].id)
			check(penned.filter(func(a): return a.get("fed_at", -1) >= 0).size() == 2 and penned.filter(func(a): return a.get("young", false)).size() == 1, "v%d: the fed pair and the calf survive" % v)
			check(Sim.armor_worn(sim.residents[2]).size() == 2 and sim.residents[2].armor.chest.dur == 5, "v%d: Mira's tunic and boots survive, with their wear" % v)
			check(sim.stacks_where(func(st): return st.type == "leather_cap").size() == 1, "v%d: the cap lying in the village survives" % v)
		check(sim.maps.village.sheep.all(func(a): return a.kind == "animal" and a.species == "sheep"), "v%d: the village's animals are sheep" % v)
		if v < 17:  # issues #109-#111: nobody hurt, no choice waiting, and the mine gets its hazards
			check(sim.residents.all(func(r): return r.hurt == 0) and sim.pending.is_empty(), "v%d: nobody is hurt and no choice waits" % v)
			check(mine.ledges == OldMine.LEDGES and mine.boulders.filter(func(b): return b.get("loose", false)).size() == OldMine.LOOSE.size(), "v%d: the old mine gets its loose ceilings and ledge" % v)
		check(sim.sites.any(func(s): return s.tpl == "bench" and s.done and s.queue.has("stone_axe")), "v%d: the bench and its queue survive" % v)
		if v >= 3:
			check(sim.residents[0].orders.size() == 2, "v%d: Ada's queued orders survive" % v)
		else:
			check(sim.residents[0].orders == [], "v%d: residents get an empty order list" % v)
		if v < 14:
			check(sim.residents[0].shirt == Sim.ADA_TUNIC and sim.residents[1].shirt == Sim.TRAVELERS[0][1], "v%d: residents get the new tunics" % v)
		else:
			check(sim.residents[0].shirt == Sim.ADA_TUNIC, "v%d: tunics survive" % v)
		var meadow_sheep: int = sim.get_map(Meadow.ID).sheep.filter(func(a): return a.alive and a.species == "sheep").size()
		if v >= 20:
			check(meadow_sheep > 0, "v%d: the meadow's herds survive" % v)
		elif v >= 13:  # issue #137: the old off-map meadow's sheep carry over to the meadow map
			check(meadow_sheep == 5 and sim.get_map(Meadow.ID).sheep.any(func(a): return a.species == "cow"), "v%d: the meadow's sheep survive, on the meadow map with its cows and pigs" % v)
		else:
			check(meadow_sheep == SaveFormat.OLD_MEADOW_SHEEP and sim.residents.all(func(r): return not r.away), "v%d: older saves get a full meadow" % v)
		if v >= 12:
			check(sim.residents[0].kept.pick, "v%d: a chosen tool stays chosen" % v)
		else:
			check(sim.residents.all(func(r): return r.kept == {"axe": false, "pick": false, "sword": false}), "v%d: no tool was chosen in older saves" % v)
		if v >= 11:
			check(Sim.level(sim.residents[0], "build") == 3, "v%d: skills survive" % v)
		else:
			check(sim.residents[0].jobs.values().all(func(j): return j.xp == 0 or v >= 11), "v%d: older saves start at level 1" % v)
		check(sim.residents[0].role == "all" and sim.residents.slice(1).all(func(r): return r.role in Defs.JOBS), "v%d: Ada does everything, and everyone else has one job" % v)
		check(sim.residents.all(func(r): return r.jobs.values().all(func(j): return j.keys() == ["xp"])), "v%d: the job switches and priorities are gone" % v)
		if v >= 23:
			check(sim.residents[1].role == "lumber", "v%d: a resident's job survives" % v)
			if v == 23:  # issue #184: the chopping block goes to the lumberjack
				check(sim.sites.any(func(st): return st.tpl == "chopping_block" and st.worker == sim.residents[1].id), "v23: Tomas claims the chopping block on upgrade")
			if v >= 24:
				check(sim.sites.any(func(st): return st.tpl == "composter" and st.worker == 0), "v%d: a free composter stays free" % v)
			var blocks: Array = sim.sites.filter(func(st): return st.tpl == "chopping_block")
			check(blocks.size() == 1 and blocks[0].keep == 25 and sim.pile_count(blocks[0]) > 0, "v%d: the chopping block, its target and its pile survive" % v)
			check(sim.trees.any(func(t): return t.alive and not Sim.grown(t)) and sim.trees.any(func(t): return t.get("keep", false)), "v%d: a growing sapling and a kept tree survive" % v)
		elif v == 22:
			check(sim.residents[1].role == "farm", "v%d: a resident's job survives" % v)
			var mira: Dictionary = sim.residents[2]
			check(mira.role == "lumber" and mira.jobs.lumber.xp == mira.jobs.mason.xp and not mira.jobs.has("mine"), "v22: a miner becomes a lumberjack, with Mine's experience in both new jobs (issue #177)")
		elif sim.residents.size() >= 2:  # every job on at priority 2: the best level wins, then the first job
			var t: Dictionary = sim.residents[1]
			var skilled: Array = Defs.JOBS.filter(func(jb): return t.jobs[jb].xp > 0)
			check(t.role == (skilled[0] if not skilled.is_empty() else "lumber"), "v%d: Tomas gets the job he's best at (%s)" % [v, t.role])
		var fires: Array = sim.sites.filter(func(s): return s.tpl == "fireplace")
		if v >= 9:
			check(fires.size() == 1 and fires[0].plot is Rect2i, "v%d: the fireplace and its reserved plot survive" % v)
		else:
			check(sim.sites.all(func(s): return s.plot == null), "v%d: older buildings reserve no plot" % v)
		if v >= 8:
			check(not sim.farm.is_empty() and sim.farm.values().any(func(c): return c.grow >= 0.0 or sim.items.has(c.cell)), "v%d: farm plots and their wheat survive" % v)
		else:
			check(sim.farm.is_empty(), "v%d: older saves start with no farms" % v)
		run(sim, 60)
		check(sim.stats.traveler_home, "v%d: Tomas finishes moving in after loading" % v)


func test_v1_tools_get_full_uses_when_upgraded() -> void:
	var raw = str_to_var(FileAccess.get_file_as_string("res://tests/fixtures/save_v1.save"))
	var had_tools: bool = raw.state.items.values().any(func(it): return Defs.is_tool_item(it.type))
	var r := SaveFormat.read("res://tests/fixtures/save_v1.save")
	var tools: Array = r.data.state.maps.village.items.values().filter(func(it): return Defs.is_tool_item(it.type))
	check(tools.all(func(it): return it.get("dur", -1) == Sim.full_uses(it.type)), "loose tools from a v1 save get full uses (%d tools; v1 had tools: %s)" % [tools.size(), had_tools])


## Issue #5: a tool keeps its remaining uses when dropped, stockpiled, saved and picked up again.
func test_dropped_tools_keep_their_wear() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	ada.axe = {"type": "wood_axe", "tier": 1, "dur": 3}
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 0), "stone_axe", 1)
	var tree: Dictionary = Sim.nearest(sim.trees, Sim.rcell(ada))
	sim.direct_order(ada, tree)
	run(sim, 20)
	check(ada.axe != null and ada.axe.type == "stone_axe", "Ada swaps to the better stone axe")
	var worn: Array = sim.stacks_where(func(s): return s.type == "wood_axe")
	check(worn.size() == 1 and worn[0].dur == 3, "the wooden axe she put down still has 3 uses, not a new 10")
	sim.paint_zone(area(0, 0, 3, 3))
	run(sim, 40)
	worn = sim.stacks_where(func(s): return s.type == "wood_axe")
	check(worn.size() == 1 and sim.in_zone(worn[0].cell) and worn[0].dur == 3, "hauled to the stockpile with its wear")
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	worn = loaded.stacks_where(func(s): return s.type == "wood_axe")
	check(worn.size() == 1 and worn[0].dur == 3, "wear survives a save and load")
	var bo := loaded.add_resident("Bo", "8C4F6B", at(1, 1))
	loaded.set_role(bo, "lumber")
	give_station(loaded, bo)  # issue #184: a job needs its workstation
	loaded.designate_mine(Rect2i(0, 0, loaded.w, loaded.h))
	for b in loaded.boulders:
		b.des = false
	for i in 60:
		run(loaded, 0.5)
		if bo.axe != null:
			break
	check(bo.axe != null and bo.axe.type == "wood_axe" and bo.axe.dur == 3, "the next resident picks it up with its 3 uses (%s)" % [bo.axe])


## Erasing stockpile cells (issue #63): stacks left on them are re-hauled to the cells that are left,
## a haul on its way to an erased cell goes to another one, and erasing every cell stops hauling.
## Issue #95: a bench recipe's crafting-grid pattern shows exactly its inputs, and a fireplace
## recipe's fuel is one of its inputs. The patterns are display only.
func test_craft_patterns_match_their_recipes() -> void:
	for rec in Defs.RECIPES:
		if rec.get("at", "bench") == "bench":
			var counts := {}
			check(rec.has("pattern") and rec.pattern.size() == 3 and rec.pattern.all(func(row): return row.length() == 3), "%s has a 3×3 pattern" % rec.name)
			for row in rec.get("pattern", []):
				for ch in row:
					if ch != " ":
						var item: String = Defs.PATTERN_KEYS.get(ch, "?")
						counts[item] = counts.get(item, 0) + 1
			check(counts == rec.inp, "%s's pattern uses its inputs (%s vs %s)" % [rec.name, counts, rec.inp])
		else:
			check(not rec.has("fuel") or rec.inp.has(rec.fuel), "%s's fuel is one of its inputs" % rec.name)


## Issue #77: a standing order short of materials is listed as waiting, not stuck, and every entry
## remembers when it first showed, so the list can put the longest-stuck first.
func test_standing_orders_wait_rather_than_block() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	hire_toolsmith(sim)
	var bench := sim.place_site("bench", open_rect(sim, Vector2i(3, 3)).position + Vector2i(1, 0))
	bench.stage = 1
	bench.done = true
	ada.pick = {"type": "wood_pick", "tier": 1, "dur": 5}
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 0), "cobble", 3)
	run(sim, 1)
	var spare: Array = sim.stuck.filter(func(s): return s.focus_kind == "site" and s.focus_id == bench.id)  # the spare's sticks, waiting on a log
	check(spare.size() == 1 and spare[0].waiting, "the toolsmith's spare waits: " + stuck_text(sim))
	var house := sim.place_site("house", open_rect(sim, Vector2i(7, 7)).position + Vector2i(1, 1))
	house.stage = 1  # walls, with no planks anywhere
	sim.compute_stuck()
	var walls: Array = sim.stuck.filter(func(s): return s.focus_kind == "site" and s.focus_id == house.id)
	check(walls.size() == 1 and not walls[0].waiting, "a house short of planks is stuck: " + stuck_text(sim))
	check(walls[0].since > spare[0].since, "the walls showed later than the spare (%d, %d)" % [walls[0].since, spare[0].since])
	var since: int = walls[0].since
	var why: String = walls[0].why
	house.store.plank = house.store.get("plank", 0) + 2  # fewer missing, same problem (dropped ones would go to the spare's sticks)
	run(sim, 2)
	walls = sim.stuck.filter(func(s): return s.focus_kind == "site" and s.focus_id == house.id)
	check(walls.size() == 1 and walls[0].why != why and walls[0].since == since, "a changing count keeps the entry's age (%s, %s)" % [walls[0].why if walls.size() else "", walls[0].since if walls.size() else -1])
	house.stage = 4
	house.done = true
	run(sim, 1)
	house.done = false
	house.stage = 1
	sim.compute_stuck()
	walls = sim.stuck.filter(func(s): return s.focus_kind == "site" and s.focus_id == house.id)
	check(walls.size() == 1 and walls[0].since > since, "an entry that clears and comes back starts over")


func test_erasing_stockpile_cells() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	ada.hunger = 100.0
	var rect := open_rect(sim, Vector2i(4, 1))
	sim.paint_zone(rect)
	check(sim.zone.size() == 4, "a 4-cell stockpile")
	var first := rect.position
	sim.drop_items(first, "log", 3)  # already stockpiled
	check(sim.erase_zone(Rect2i(first, Vector2i.ONE)) == 1 and not sim.in_zone(first), "erasing one cell takes just that cell")
	check(sim.items.has(first) and sim.items[first].n == 3, "the logs on it stay where they are")
	run(sim, 40)
	check(not sim.items.has(first) and count(sim, "log") == 3 and sim.items.values().all(func(st): return sim.in_zone(st.cell)), "and are hauled to the cells that are left")
	# A haul on its way to a cell that's erased heads for another one.
	sim.drop_items(Sim.rcell(ada) + Vector2i(0, 2) if sim.walkable(Sim.rcell(ada) + Vector2i(0, 2)) else Sim.rcell(ada), "plank", 2)
	var dest = null
	for i in 400:
		sim.step()
		if ada.job != null and ada.job.kind == "haul" and ada.carry != null:
			for st in ada.job.steps:
				if st.op == "haul_drop":
					dest = st.cell
			break
	check(dest != null, "Ada is carrying planks to a stockpile cell")
	if dest != null:
		sim.erase_zone(Rect2i(dest, Vector2i.ONE))
		check(ada.job != null and ada.job.kind == "haul" and ada.carry != null, "erasing that cell doesn't drop her load")
		var new_dest = null
		for st in ada.job.steps:
			if st.op == "haul_drop":
				new_dest = st.cell
		check(new_dest != null and new_dest != dest and sim.in_zone(new_dest) and sim.zone_res.get(new_dest, 0) == ada.id, "she heads for another cell instead")
		run(sim, 30)
		var planks: Array = sim.stacks_where(func(st): return st.type == "plank")
		check(planks.size() == 1 and sim.in_zone(planks[0].cell) and ada.carry == null, "and puts the planks there")
		check(not sim.zone_res.has(dest), "nothing is left holding the erased cell")
	# Erasing every cell: stacks stay where they are and nothing more is hauled.
	sim.erase_zone(Rect2i(0, 0, sim.w, sim.h))
	check(sim.zone.is_empty() and sim.zone_res.is_empty(), "erasing a big rectangle takes every stockpile cell")
	var before := sim.items.duplicate()
	run(sim, 20)
	check(sim.items.keys() == before.keys() and (ada.job == null or ada.job.kind != "haul"), "with no stockpile, nothing is hauled and the stacks stay put")


func test_upgrades_run_in_order() -> void:
	var order: Array = []
	var steps := {
		1: func(d):
			order.append(1)
			d.state.renamed = d.state.get("old", 0)
			return d,
		2: func(d):
			order.append(2)
			d.state.extra = true
			return d,
	}
	var r := SaveFormat.upgrade({"v": 1, "state": {"old": 7}}, steps, 3)
	check(not r.has("error"), "a v1 save upgrades to v3 through two steps")
	check(order == [1, 2], "steps run oldest first: %s" % [order])
	check(r.data.v == 3 and r.data.state.renamed == 7 and r.data.state.extra, "each step's change is kept")
	var gap := SaveFormat.upgrade({"v": 1, "state": {}}, {2: steps[2]}, 3)
	check(gap.has("error"), "a missing step is refused instead of loading half-upgraded")
	var same := SaveFormat.upgrade({"v": 3, "state": {}}, steps, 3)
	check(not same.has("error") and same.data.v == 3, "a current save passes through unchanged")


func test_newer_or_damaged_saves_are_refused() -> void:
	var newer := SaveFormat.upgrade({"v": SaveFormat.VERSION + 1, "state": {}})
	check(newer.get("error", "").contains("newer version"), "a save from a newer game version is refused with a clear reason")
	check(SaveFormat.parse("not a save").has("error"), "garbage is refused")
	check(SaveFormat.parse(var_to_str({"tick": 1})).has("error"), "a dictionary without a version is refused")


func test_save_file_round_trip() -> void:
	var sim := Sim.new_game()
	sim.designate_mine(area(0, 0, 10, 18))
	run(sim, 30)
	var path := "user://test_saves/round_trip.save"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://test_saves"))
	check(SaveFormat.write(path, {"summary": "x", "tick": sim.tick, "saved_at": 0, "state": sim.save_state(), "camera": {}, "speed": 1}), "save written")
	var r := SaveFormat.read(path)
	check(not r.has("error") and r.data.v == SaveFormat.VERSION, "save read back at the current version")
	check(Sim.from_state(r.data.state).tick == sim.tick, "state survives the file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Issue #2: Shift + right-click queues orders that run one after another, after current work.
func test_queued_orders_run_in_turn() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var start := Sim.rcell(ada)
	var spot := start + Vector2i(3, 0)
	var tree: Dictionary = Sim.nearest(sim.trees, start)
	var back := start + Vector2i(0, 2)
	sim.queue_order(ada, null, spot)
	sim.queue_order(ada, tree)
	sim.queue_order(ada, null, back)
	check(ada.orders.size() == 3 and Sim.order_text(ada.orders[1]) == "Mine a tree", "three orders queued")
	check(tree.des, "a queued tree is marked for mining")
	var visited_spot := -1
	var felled := -1
	var back_at := -1
	for i in 60 * Tuning.TPS:
		sim.step()
		if visited_spot < 0 and Sim.rcell(ada) == spot:
			visited_spot = i
		if felled < 0 and not tree.alive:
			felled = i
		if back_at < 0 and felled >= 0 and Sim.rcell(ada) == back:
			back_at = i
	check(visited_spot >= 0 and felled > visited_spot and back_at > felled, "orders run in turn: walk, then mine, then walk (%d, %d, %d)" % [visited_spot, felled, back_at])
	check(ada.orders.is_empty(), "the list empties as orders run")
	sim.queue_order(ada, null, spot)
	sim.queue_order(ada, null, back)
	sim.direct_order(ada, null, start)
	check(ada.orders.is_empty(), "a plain right-click replaces the queued orders")
	var boulder: Dictionary = sim.boulders[0]
	sim.queue_order(ada, boulder)
	sim.queue_order(ada, null, spot)
	run(sim, 1)
	check(ada.orders.is_empty() and ada.job != null and ada.job.kind == "move", "a boulder order without a pickaxe is skipped and the next order runs")
	sim.queue_order(ada, null, back)
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(loaded.residents[0].orders.size() == 1, "queued orders survive a save and load")
	sim.clear_orders(ada)
	check(ada.orders.is_empty(), "Clear orders empties the list")


## Issue #7: a Mine drag can be limited to trees or to boulders.
func test_mine_drag_limited_to_one_kind() -> void:
	var sim := Sim.new_game()
	sim.designate_mine(whole_map(), null, ["tree"])
	check(sim.trees.all(func(t): return t.des) and sim.boulders.all(func(b): return not b.des), "trees only marks every tree and no boulder")
	var sim2 := Sim.new_game()
	sim2.designate_mine(whole_map(), null, ["boulder"])
	check(sim2.boulders.all(func(b): return b.des) and sim2.trees.all(func(t): return not t.des), "boulders only marks every boulder and no tree")
	check(Game.mine_kinds(true, false) == ["tree"] and Game.mine_kinds(false, true) == ["boulder"], "Shift means trees, Alt means boulders")
	check(Game.mine_kinds(false, false).size() == 2 and Game.mine_kinds(true, true).size() == 2, "no modifier, or both, marks both kinds")


## A cell or area of the original 18×18 opening, in today's map (issue #52 moved it to the middle).
static func at(x: int, y: int) -> Vector2i:
	return Vector2i(x, y) + Tuning.OPENING_OFFSET


static func area(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(Vector2i(x, y) + Tuning.OPENING_OFFSET, Vector2i(w, h))


## Issue #42: sheep wander on open ground, and the same game wanders the same way every time.
func test_sheep_wander_and_replay() -> void:
	var a := Sim.new_game()
	var b := Sim.new_game()
	check(a.sheep.size() == 3, "three sheep at the start (issue #182)")
	var start: Array = a.sheep.map(func(sh): return sh.cell)
	for i in 60 * Tuning.TPS:
		a.step()
		b.step()
		for sh in a.sheep:
			if not a.in_bounds(sh.cell) or not a.walkable(sh.cell):
				check(false, "sheep %d left open ground at %s" % [sh.id, sh.cell])
				return
	check(a.sheep.map(func(sh): return sh.cell) != start, "sheep wander")
	check(a.sheep.map(func(sh): return sh.pos) == b.sheep.map(func(sh): return sh.pos), "two games from the same seed wander identically")
	var loaded := Sim.from_state(str_to_var(var_to_str(a.save_state())))
	for i in 20 * Tuning.TPS:
		a.step()
		loaded.step()
	check(a.sheep.map(func(sh): return sh.pos) == loaded.sheep.map(func(sh): return sh.pos), "a saved game keeps wandering exactly as it would have")


func test_hunting_sheep() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var sh: Dictionary = Sim.nearest(sim.sheep, Sim.rcell(ada))
	sim.designate_hunt(Rect2i(sh.cell, Vector2i.ONE))
	check(sh.des, "marking a sheep for hunting")
	sim.designate_hunt(Rect2i(sh.cell, Vector2i.ONE), sh)
	check(not sh.des, "clicking a marked sheep unmarks it")
	sim.designate_hunt(Rect2i(0, 0, sim.w, sim.h))
	check(sim.sheep.all(func(x): return x.des), "a drag over the whole map marks every sheep")
	for i in 120 * Tuning.TPS:
		sim.step()
		if not sh.alive:
			break
	check(not sh.alive, "Ada follows and hunts the nearest sheep")
	check(count(sim, "wool") >= 1 and count(sim, "mutton") >= 1, "a hunted sheep drops wool and raw mutton")
	run(sim, 300)
	check(sim.sheep.all(func(x): return not x.alive), "she hunts every marked sheep")
	check(count(sim, "wool") == 3 and count(sim, "mutton") >= 2, "three sheep give 3 wool and 3 mutton, less any Ada ate (%d, %d)" % [count(sim, "wool"), count(sim, "mutton")])
	var sim2 := Sim.new_game()
	var ada2: Dictionary = sim2.residents[0]
	var far: Dictionary = sim2.sheep[0]
	sim2.direct_order(ada2, far)
	check(ada2.direct != null and far.des, "right-clicking a sheep orders a hunt")
	sim2.queue_order(ada2, sim2.sheep[1])
	check(Sim.order_text(ada2.orders[0]) == "Hunt a sheep", "Shift + right-click queues a hunt")
	run(sim2, 120)
	check(not far.alive and not sim2.sheep[1].alive, "both ordered hunts happen")


## Issue #43: a bed is a house's last stage, and travelers come only for free beds.
func test_beds_and_free_bed_arrivals() -> void:
	var s := opening()
	var sim: Sim = s.sim
	check(s.h1.stage == 4 and s.h2.stage == 4, "both opening houses got their beds")
	check(sim.stats.get("sheep_hunted", 0) >= 3 and sim.sheep.all(func(x): return not x.alive), "the clearing's three sheep were hunted for wool, and more at the meadow (%d)" % sim.stats.get("sheep_hunted", 0))
	var wool: int = Goals.LIST.map(func(g): return g.t).find("Hunt sheep for wool")
	check(wool >= 0 and Goals.done(sim, wool), "the founding goals include hunting for wool")
	# A house with no wool for its bed: finished up to the roof, never done, and nobody comes.
	var bench: Dictionary = s.bench
	for k in sim.items.keys():
		if sim.items[k].type == "wool":
			sim.items.erase(k)
	var h3 := sim.place_site("house", at(11, 11))
	for i in 8:
		sim.queue_add(bench, "planks")
	sim.designate_mine(whole_map())
	run(sim, 900)
	check(h3.stage == 3 and not h3.done, "without wool the third house stops at its bed stage (stage %d)" % h3.stage)
	check(stuck_text(sim).contains("House needs a bed: 3 more wool"), "it says why: " + stuck_text(sim))
	check(sim.residents.size() == 2, "no free bed, no arrival")
	# Wool arrives (as from the meadow, #50): the bed gets built and a third resident comes.
	sim.drop_items(Sim.rcell(sim.residents[0]), "wool", 3)
	run(sim, 200)
	check(h3.done, "with wool the bed is built")
	check(sim.residents.size() == 3 and sim.residents[2].name == "Mira", "a third traveler, Mira, arrives for the free bed")
	run(sim, 60)
	check(h3.owner == sim.residents[2].id, "and moves into it")
	# An older save: finished houses had three stages and get a finished bed.
	var raw = str_to_var(FileAccess.get_file_as_string("res://tests/fixtures/save_v5.save"))
	var up := SaveFormat.upgrade(raw)
	check(up.data.state.maps.village.sites.filter(func(x): return x.tpl == "house" and x.done).all(func(x): return x.stage == 4), "older saves' finished houses get a finished bed")


## Issue #44: hunger drops, residents eat before they starve, and starving ones stop and recover.
func test_hunger_and_eating() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	check(ada.hunger == 100.0 and sim.bushes.size() == 6, "Ada starts full, with six berry bushes about")
	run(sim, 60)
	check(absf(ada.hunger - (100.0 - 60.0 * 100.0 / Tuning.HUNGER_EMPTY_TIME)) < 0.5, "hunger drops steadily (%.1f after a minute)" % ada.hunger)
	# Hungry: she goes to the nearest bush and eats berries until nearly full.
	ada.hunger = 35.0
	var labels: Array = []
	for i in 30 * Tuning.TPS:
		sim.step()
		if ada.job != null and not labels.has(ada.job.label):
			labels.append(ada.job.label)
	check(labels.has("Eating berries"), "a hungry resident picks berries (%s)" % [labels])
	var eaten: Array = sim.bushes.filter(func(b): return b.berries < Tuning.BUSH_MAX)
	check(eaten.size() == 1 and eaten[0].berries == 0, "she eats until the bush is bare (3 berries, up to 45 food)")
	check(ada.hunger > 35.0 + 2 * Tuning.FOOD_VALUE.berries, "she's well fed again (%.1f)" % ada.hunger)
	ada.hunger = 100.0
	run(sim, Tuning.BUSH_REGROW * Tuning.BUSH_MAX + 1)
	check(not eaten.is_empty() and eaten[0].berries == Tuning.BUSH_MAX, "the bare bush grows its berries back")
	# Food on the ground is eaten too, by its value.
	for b in sim.bushes:
		b.berries = 0
		b.regrow = -9999.0
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 0), "mutton", 1)
	ada.hunger = 30.0
	run(sim, 10)
	check(count(sim, "mutton") == 0 and absf(ada.hunger - (30.0 + 20.0 - 10.0 * 100.0 / Tuning.HUNGER_EMPTY_TIME)) < 2.0, "raw mutton on the ground is eaten for 20 (%.1f)" % ada.hunger)
	# Hungry work is slower.
	var sim2 := Sim.new_game()
	var a2: Dictionary = sim2.residents[0]
	for b in sim2.bushes:
		b.berries = 0
		b.regrow = -9999.0
	a2.hunger = 20.0
	var tree: Dictionary = Sim.nearest(sim2.trees, Sim.rcell(a2))
	sim2.direct_order(a2, tree)
	var chop_ticks := 0
	for i in 60 * Tuning.TPS:
		sim2.step()
		if a2.job != null and a2.job.label == "Chopping a tree":
			chop_ticks += 1
		if not tree.alive:
			break
	check(absf(chop_ticks - Tuning.CHOP_TIME[0] / Tuning.HUNGRY_SPEED * Tuning.TPS) <= 2, "a hungry resident chops 25%% slower (%d ticks)" % chop_ticks)
	# Starving: stops working, says why, and recovers once there's food.
	a2.hunger = 0.0
	sim2.designate_mine(whole_map())
	run(sim2, 5)
	check(a2.job == null, "a starving resident with no food stops working")
	check(stuck_text(sim2).contains("Starving: no food stored"), "and the stuck list says why: " + stuck_text(sim2))
	sim2.drop_items(Sim.rcell(a2), "mutton", 2)
	run(sim2, 6)
	check(a2.hunger > 0.0 and not stuck_text(sim2).contains("Starving"), "food appears and she eats and recovers (%.1f)" % a2.hunger)



## An open rect of grass near Ada, `size` cells, where a farm plot can go.
func open_rect(sim: Sim, size: Vector2i) -> Rect2i:
	var start := Sim.rcell(sim.residents[0])
	for d in range(1, 12):
		for x in range(start.x - d, start.x + d):
			for y in range(start.y - d, start.y + d):
				var r := Rect2i(Vector2i(x, y), size)
				var ok := true
				for cx in range(r.position.x, r.end.x):
					for cy in range(r.position.y, r.end.y):
						if sim.farm_blocked(Vector2i(cx, cy)) != "":
							ok = false
				if ok:
					return r
	return Rect2i()


func test_farm_plant_grow_harvest() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	ada.hunger = 100.0
	var rect := open_rect(sim, Vector2i(3, 2))
	check(rect.size != Vector2i.ZERO, "found open grass for a farm")
	check(sim.paint_farm(rect) == 6 and sim.farm.size() == 6, "Farm paints six plots")
	# Ada plants every empty cell, 2 seconds each, without seeds.
	var labels: Array = []
	for i in 30 * Tuning.TPS:
		sim.step()
		if ada.job != null and not labels.has(ada.job.label):
			labels.append(ada.job.label)
	check(labels.has("Planting wheat"), "Ada plants wheat (%s)" % [labels])
	check(sim.farm.values().all(func(c): return c.grow >= 0.0), "every plot is planted")
	check(sim.stats.get("planted", 0) == 6, "six cells planted, once each")
	var stages := {}
	for c in sim.farm.values():
		stages[Sim.crop_stage(c)] = true
	check(stages.has(1) and not stages.has(4), "young wheat is at its first stage")
	# It grows through visible stages over 2 minutes.
	var crop: Dictionary = sim.farm.values()[0]
	var seen := {}
	while not Sim.crop_ripe(crop):
		seen[Sim.crop_stage(crop)] = true
		sim.step()
	check(seen.has(1) and seen.has(2) and seen.has(3), "wheat shows three growing stages (%s)" % [seen.keys()])
	# Ripe wheat is harvested for 2 wheat each, and the plot is empty again (then replanted).
	labels.clear()
	for i in 40 * Tuning.TPS:
		sim.step()
		if ada.job != null and not labels.has(ada.job.label):
			labels.append(ada.job.label)
	check(labels.has("Harvesting wheat"), "Ada harvests ripe wheat (%s)" % [labels])
	check(sim.stats.get("harvested", 0) == 6, "all six cells harvested (%d)" % sim.stats.get("harvested", 0))
	check(count(sim, "wheat") == 6 * Tuning.WHEAT_YIELD, "each harvest gives %d wheat (%d)" % [Tuning.WHEAT_YIELD, count(sim, "wheat")])
	# The harvest is collected before a plot is replanted: with no stockpile, it waits and says why.
	check(sim.stats.get("planted", 0) == 6, "plots with wheat lying on them aren't replanted")
	check(stuck_text(sim).contains("Harvested wheat needs a stockpile"), "and the stuck list says why: " + stuck_text(sim))
	sim.paint_zone(open_rect(sim, Vector2i(2, 1)))
	run(sim, 60)
	check(sim.farm.keys().all(func(k): return not sim.items.has(k)), "once there's a stockpile, the wheat is hauled off the plots")
	check(sim.stats.get("planted", 0) == 12, "and the empty plots are planted again (%d)" % sim.stats.get("planted", 0))
	# Ripe wheat waits: with nobody to harvest it, it stays ripe and doesn't spoil.
	var sim2 := Sim.new_game()
	sim2.residents[0].hunger = 100.0
	sim2.paint_farm(open_rect(sim2, Vector2i.ONE))
	var c2: Dictionary = sim2.farm.values()[0]
	c2.grow = Tuning.WHEAT_GROW
	sim2.residents.clear()
	run(sim2, 300)
	check(Sim.crop_ripe(c2) and sim2.farm.has(c2.cell), "ripe wheat waits without spoiling")
	# Farm plots and growth survive a save.
	var saved := Sim.from_state(sim.save_state())
	check(saved.farm.size() == 6, "farm plots survive a save")
	var grows: Array = sim.farm.keys().map(func(k): return sim.farm[k].grow)
	var loaded: Array = sim.farm.keys().map(func(k): return saved.farm[k].grow)
	check(grows == loaded, "and so does each cell's growth")
	check(saved.farm.values().all(func(c): return c.claim == 0), "claims are cleared on load")


func test_farm_plots_need_open_grass() -> void:
	var sim := Sim.new_game()
	var tree: Dictionary = sim.trees[0]
	check(sim.paint_farm(Rect2i(tree.cell, Vector2i.ONE)) == 0, "no farm on a tree")
	var bush: Dictionary = sim.bushes[0]
	check(sim.paint_farm(Rect2i(bush.cell, Vector2i.ONE)) == 0, "no farm on a berry bush")
	var house_rect := open_rect(sim, Vector2i(5, 5))
	var house := sim.place_site("house", house_rect.position)
	check(sim.paint_farm(house_rect) == 0, "no farm over a building")
	var free := open_rect(sim, Vector2i(2, 1))
	sim.paint_zone(free)
	check(sim.paint_farm(free) == 0 and sim.farm_blocked(free.position) == "a stockpile", "no farm over a stockpile")
	var plot := open_rect(sim, Vector2i(2, 1))
	check(sim.paint_farm(plot) == 2, "farm on open grass")
	sim.paint_zone(plot)
	check(not sim.zone.has(plot.position), "and a stockpile can't be painted over a farm")
	# A building placed over a farm clears it, like a stockpile.
	sim.cancel_site(house)
	sim.place_site("house", plot.position)
	check(sim.farm.is_empty(), "a building placed on plots clears them")
	sim.cancel_site(sim.sites[-1])
	sim.paint_farm(plot)
	sim.clear_farm(Rect2i(plot.position, Vector2i(2, 1)))
	check(sim.farm.is_empty(), "plots can be removed")


## A finished fireplace, skipping its construction.
func lit_fireplace(sim: Sim, origin: Vector2i) -> Dictionary:
	var f := sim.place_site("fireplace", origin)
	f.stage = 1
	f.done = true
	sim.rev += 1
	return f


func test_fireplace_reserves_a_kitchen_plot() -> void:
	var sim := Sim.new_game()
	var spot := open_rect(sim, Vector2i(3, 3))
	var o := spot.position + Vector2i(1, 0)  # the fireplace sits in the middle of the plot's back wall
	check(sim.placement_check("fireplace", o) == "", "a fireplace fits on open grass")
	var zone_cell := o + Vector2i(0, 2)
	sim.paint_zone(Rect2i(zone_cell, Vector2i.ONE))
	var f := sim.place_site("fireplace", o)
	check(f.plot == Rect2i(o + Vector2i(-1, 0), Vector2i(3, 3)), "it reserves the 3×3 kitchen plot (%s)" % [f.plot])
	check(not sim.zone.has(zone_cell), "stockpile cells on the new plot are cleared")
	var inside := o + Vector2i(1, 1)
	check(sim.placement_check("bench", inside) == "Overlaps a reserved plot", "nothing can be built on the plot")
	check(sim.placement_check("house", o + Vector2i(-5, 1)) == "Overlaps a reserved plot", "not even partly")
	sim.paint_zone(f.plot)
	check(not sim.zone.has(inside), "nothing can be stockpiled on it")
	check(sim.farm_blocked(inside) == "a reserved plot" and sim.paint_farm(f.plot) == 0, "nor farmed")
	check(sim.walkable(inside), "residents can still walk across it")
	# Its own plot needs room: not off the map, not over a building or another plot.
	check(sim.placement_check("fireplace", Vector2i(0, 5)) == "Not enough room to grow into a kitchen", "a plot can't run off the map edge")
	check(sim.placement_check("bench", Vector2i(0, 5)) == "Not enough room to grow into a workshop", "benches placed now reserve a workshop plot too")
	check(sim.placement_check("fireplace", o + Vector2i(0, -2)) == "Not enough room to grow into a kitchen", "or overlap another plot")
	check(sim.placement_check("fireplace", o + Vector2i(0, -1), 2) == "", "turned to face away, a fireplace fits right behind it")
	var bench := sim.place_site("bench", open_rect(sim, Vector2i(3, 3)).position + Vector2i(1, 0))
	check(bench.plot != null, "a newly placed bench reserves a plot")
	# Trees on a plot are left alone until the upgrade needs the space.
	var t2: Dictionary = {}
	for t in sim.trees:
		var fo: Vector2i = t.cell - Vector2i(0, 1)
		if sim.placement_check("fireplace", fo) == "" and sim.site_at(fo) == null and sim.walkable(fo):
			t2 = t
			sim.place_site("fireplace", fo)
			break
	check(not t2.is_empty() and not t2.des, "a tree on the reserved plot isn't marked for mining")
	# Plots and the standing order survive a save.
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	var lf: Dictionary = loaded.site(f.id)
	check(lf.plot == f.plot and lf.keep_meals, "the plot and standing order survive a save")


func test_fireplace_cooks_and_keeps_meals_stocked() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var spot := open_rect(sim, Vector2i(3, 3))
	var f := lit_fireplace(sim, spot.position + Vector2i(1, 0))
	var near := spot.position + Vector2i(1, 3)
	sim.drop_items(near, "wheat", 6)
	sim.drop_items(near + Vector2i(1, 0), "mutton", 1)
	sim.drop_items(near + Vector2i(-1, 0), "log", 2)
	var labels: Array = []
	for i in 90 * Tuning.TPS:
		sim.step()
		if ada.job != null and not labels.has(ada.job.label):
			labels.append(ada.job.label)
	check(labels.has("Baking bread") and labels.has("Cooking mutton"), "the standing order bakes and cooks (%s)" % [labels])
	check(count(sim, "bread") == 2 and count(sim, "wheat") == 0, "3 wheat makes each bread (%d bread)" % count(sim, "bread"))
	check(count(sim, "cooked_mutton") == 1 and count(sim, "mutton") == 0, "raw mutton is cooked")
	check(count(sim, "log") == 1, "cooking burns one log as fuel (%d left)" % count(sim, "log"))
	check(f.queue.is_empty(), "with no inputs left, nothing more is queued")
	check(not stuck_text(sim).contains("Fireplace"), "the standing order never leaves the fireplace stuck")
	# It stops at 6 meals.
	sim.drop_items(near, "wheat", 16)
	sim.drop_items(near + Vector2i(1, 0), "wheat", 14)
	run(sim, 150)
	var meals := count(sim, "bread") + count(sim, "cooked_mutton")
	check(meals == Tuning.MEAL_STOCK, "it keeps %d meals in stock, no more (%d)" % [Tuning.MEAL_STOCK, meals])
	# Off: nothing is queued automatically. A manual order that can't be made says why.
	for it in sim.items.values().filter(func(x): return x.type == "bread"):
		sim.items.erase(it.cell)
	sim.set_keep_meals(f, false)
	for it in sim.items.values().filter(func(x): return x.type == "wheat"):
		sim.items.erase(it.cell)
	run(sim, 5)
	check(f.queue.is_empty(), "with the standing order off, nothing is queued")
	sim.queue_add(f, "bread")
	run(sim, 1)
	check(stuck_text(sim).contains("Fireplace: Bread needs 3 more wheat"), "a blocked bread order says what's missing: " + stuck_text(sim))
	# Raw mutton is eaten only in a pinch: with berries about, it's kept for cooking.
	var sim2 := Sim.new_game()
	var a2: Dictionary = sim2.residents[0]
	sim2.drop_items(Sim.rcell(a2) + Vector2i(1, 0), "mutton", 1)
	a2.hunger = 35.0
	run(sim2, 20)
	check(count(sim2, "mutton") == 1 and a2.hunger > 50.0, "a hungry resident eats berries and leaves raw mutton for cooking")


## Issue #134: every resident but Ada has one job. They claim only its work, and haul when there's
## none. Ada does everything.
func test_one_job_each() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	check(ada.role == "all" and ada.jobs == Sim.default_jobs(), "Ada does everything, at level 1 in each job")
	sim.set_role(ada, "farm")
	check(ada.role == "all", "Ada's job can't be changed")
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], sim.nearest_walkable(Sim.rcell(ada) + Vector2i(2, 0)))
	check(tomas.role == "none" and Sim.role_name(tomas) == "No job", "a resident added by hand has no job")
	sim.set_role(tomas, "farm")
	sim.paint_zone(open_rect(sim, Vector2i(2, 1)))
	sim.drop_items(Sim.rcell(tomas) + Vector2i(1, 0), "log", 4)
	sim.designate_mine(whole_map())
	var mined := false
	var hauled := false
	for i in 10 * Tuning.TPS:
		sim.step()
		if tomas.job != null:
			mined = mined or tomas.job.work == "lumber"
			hauled = hauled or tomas.job.work == "haul"
	check(not mined and hauled, "a farmer with nothing to farm never mines marked trees, and hauls instead")
	# A new job takes over, and stops work of the old one.
	sim.set_role(tomas, "lumber")
	give_station(sim, tomas)  # issue #184: a job needs its workstation
	sim.fail_job(tomas)
	run(sim, 0.1)
	check(tomas.job != null and tomas.job.work == "lumber", "made a lumberjack, he chops (%s)" % (tomas.job.work if tomas.job else "idle"))
	sim.set_role(tomas, "cook")
	check(tomas.job == null or tomas.job.work != "lumber", "a new job stops work of the old one")
	check(sim.job_list(tomas) == ["haul"] and sim.job_list(ada) == Defs.JOBS, "his work is his job and hauling; Ada's is everything")
	# No job: hauls only. Direct orders still work, and eating comes first.
	sim.set_role(tomas, "none")
	var tree: Dictionary = Sim.nearest(sim.trees.filter(func(t): return t.alive and t.claim == 0), Sim.rcell(tomas))
	sim.direct_order(tomas, tree)
	run(sim, 1)
	check(tomas.job != null and is_same(tomas.job.target, tree), "a direct order works whatever the job")
	tomas.hunger = 30.0
	sim.fail_job(tomas)
	run(sim, 0.1)
	check(tomas.job != null and tomas.job.kind == "eat", "a hungry resident eats first")
	# "No one is a lumberjack" once nobody has the job and Ada can't see to it.
	sim.compute_stuck()
	check(not stuck_text(sim).contains("No one is a"), "while Ada's about, nothing is unstaffed: " + stuck_text(sim))
	ada.away = true
	sim.compute_stuck()
	check(stuck_text(sim).contains("No one is a lumberjack"), "with Ada away, marked trees say no one is a lumberjack: " + stuck_text(sim))
	sim.set_role(tomas, "lumber")
	sim.compute_stuck()
	check(not stuck_text(sim).contains("No one is a lumberjack"), "and the reason goes once someone is: " + stuck_text(sim))
	ada.away = false
	# Jobs survive a save.
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(loaded.residents[0].role == "all" and loaded.residents[1].role == "lumber", "jobs survive a save")


## Issue #134 (and #91): Ada makes tools queued by hand, but spare tools are made only while a
## resident's job is Toolsmith. A traveler arrives with the job they're skilled in.
func test_spares_need_a_resident_toolsmith() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var bench := sim.place_site("bench", open_rect(sim, Vector2i(3, 3)).position + Vector2i(1, 0))
	bench.stage = 1
	bench.done = true
	ada.axe = {"type": "wood_axe", "tier": 1, "dur": 5}
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 0), "plank", 6)
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 1), "stick", 4)
	run(sim, 2)
	check(not bench.autoq.has("toolsmith") and not sim.has_toolsmith(), "Ada alone queues no spares (%s)" % [bench.queue])
	sim.queue_add(bench, "wood_pick")
	run(sim, 30)
	check(sim.stats.pick_crafted, "Ada makes a pickaxe queued by hand")
	check(Goals.LIST.all(func(g): return not g.t.contains("toolsmith")), "the checklist no longer asks for a toolsmith")
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], sim.nearest_walkable(Sim.rcell(ada) + Vector2i(2, 0)))
	sim.set_role(tomas, "toolsmith")
	give_station(sim, tomas)  # issue #184: a job needs its workstation
	sim.drop_items(Sim.rcell(ada) + Vector2i(0, 1), "plank", 6)
	sim.drop_items(Sim.rcell(ada) + Vector2i(0, 2), "stick", 4)
	run(sim, 2)
	check(sim.has_toolsmith() and bench.autoq.has("toolsmith"), "with a resident toolsmith, a spare is queued (%s)" % [bench.queue])
	# Travelers arrive at work in the job they're skilled in.
	var seen := {}
	for seed in 40:
		var t := Sim.new_game()
		t.rng.seed = seed
		t._arrive()
		var tr: Dictionary = t.residents.back()
		var skill: String = Defs.JOBS.filter(func(jb): return tr.jobs[jb].xp > 0)[0]
		check(tr.role == skill, "an arrival skilled at %s has that job (%s)" % [skill, tr.role])
		check(skill == "lumber", "the first traveler is always a lumberjack (issue #182)")
		t._arrive()
		tr = t.residents.back()
		skill = Defs.JOBS.filter(func(jb): return tr.jobs[jb].xp > 0)[0]
		check(tr.role == skill, "a later arrival skilled at %s has that job (%s)" % [skill, tr.role])
		seen[skill] = true
	check(seen.has("toolsmith"), "for some seed, the second traveler is a skilled toolsmith")


## Experience that puts a resident at `lv` in a job.
func set_level(r: Dictionary, job: String, lv: int) -> void:
	r.jobs[job].xp = 0 if lv <= 1 else Tuning.SKILL_LEVELS[lv - 2]


func test_skills_rise_and_pay_off() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	# Levels rise at 8, 25, 50 and 90 points and stop at 5.
	check(Sim.level(ada, "lumber") == 1, "everyone starts at level 1")
	for i in 7:
		sim.gain_xp(ada, "lumber")
	check(Sim.level(ada, "lumber") == 1 and is_equal_approx(Sim.level_progress(ada, "lumber"), 7.0 / 8.0), "7 points: still level 1, most of the way to 2")
	sim.events.clear()
	sim.gain_xp(ada, "lumber")
	check(Sim.level(ada, "lumber") == 2, "8 points: level 2")
	check(sim.events.any(func(e): return e.text == "Ada is now level 2 at Lumberjack."), "a new level gets a toast")
	for pair in [[24, 2], [25, 3], [49, 3], [50, 4], [89, 4], [90, 5], [500, 5]]:
		ada.jobs.lumber.xp = pair[0]
		check(Sim.level(ada, "lumber") == pair[1], "%d points is level %d" % pair)
	# Each finished task gives a point in its job.
	var sim2 := Sim.new_game()
	var a2: Dictionary = sim2.residents[0]
	var tree: Dictionary = Sim.nearest(sim2.trees, Sim.rcell(a2))
	sim2.direct_order(a2, tree)
	run(sim2, 40)
	check(a2.jobs.lumber.xp == 1, "felling a tree, even by direct order, gives 1 Lumberjack point")
	# Faster: each level above 1 is 15% faster. Better: level 3 drops an extra log.
	var sim3 := Sim.new_game()
	var a3: Dictionary = sim3.residents[0]
	set_level(a3, "lumber", 3)
	var t3: Dictionary = Sim.nearest(sim3.trees, Sim.rcell(a3))
	var logs: int = t3.logs
	sim3.direct_order(a3, t3)
	var ticks := 0
	for i in 60 * Tuning.TPS:
		sim3.step()
		if a3.job != null and a3.job.label == "Chopping a tree":
			ticks += 1
		if not t3.alive:
			break
	check(absf(ticks - Tuning.CHOP_TIME[0] / 1.3 * Tuning.TPS) <= 2, "level 3 chops 30%% faster (%d ticks)" % ticks)
	check(count(sim3, "log") == logs + 1, "and gets 1 extra log (%d)" % count(sim3, "log"))
	set_level(a3, "lumber", 5)
	check(Sim.skill_bonus(a3, "lumber") == 2, "level 5 gets 2 extra")
	# Farm: extra wheat at level 3.
	var sim4 := Sim.new_game()
	var a4: Dictionary = sim4.residents[0]
	set_level(a4, "farm", 3)
	sim4.paint_farm(open_rect(sim4, Vector2i.ONE))
	sim4.farm.values()[0].grow = Tuning.WHEAT_GROW
	run(sim4, 15)
	check(count(sim4, "wheat") == Tuning.WHEAT_YIELD + 1, "a level-3 farmer harvests 1 extra wheat (%d)" % count(sim4, "wheat"))
	# Cook: bread from 2 wheat at level 4; the spare wheat goes back out.
	var sim5 := Sim.new_game()
	var a5: Dictionary = sim5.residents[0]
	set_level(a5, "cook", 4)
	var spot := open_rect(sim5, Vector2i(3, 3))
	var f := lit_fireplace(sim5, spot.position + Vector2i(1, 0))
	sim5.set_keep_meals(f, false)
	sim5.drop_items(spot.position + Vector2i(1, 3), "wheat", 3)
	sim5.queue_add(f, "bread")
	run(sim5, 30)
	check(count(sim5, "bread") == 1 and count(sim5, "wheat") == 1, "a level-4 cook bakes bread from 2 wheat (%d wheat left)" % count(sim5, "wheat"))
	# Craft: 5 planks from a log at level 4. Toolsmith: +20% uses per level above 1.
	var sim6 := Sim.new_game()
	var a6: Dictionary = sim6.residents[0]
	set_level(a6, "craft", 4)
	set_level(a6, "toolsmith", 2)
	var bench := sim6.place_site("bench", open_rect(sim6, Vector2i(3, 3)).position + Vector2i(1, 0))
	bench.stage = 1
	bench.done = true
	sim6.drop_items(Sim.rcell(a6) + Vector2i(1, 0), "log", 1)
	sim6.queue_add(bench, "planks")
	run(sim6, 30)
	check(count(sim6, "plank") == 5, "a level-4 crafter gets 5 planks from a log (%d)" % count(sim6, "plank"))
	sim6.drop_items(Sim.rcell(a6) + Vector2i(1, 0), "plank", 3)
	sim6.drop_items(Sim.rcell(a6) + Vector2i(-1, 0), "stick", 2)
	sim6.queue_add(bench, "wood_pick")
	run(sim6, 40)
	var picks: Array = sim6.items.values().filter(func(it): return it.type == "wood_pick")
	var held = a6.pick
	var uses: int = picks[0].dur if not picks.is_empty() else (held.dur if held != null else -1)
	check(uses == roundi(Tuning.DURABILITY[1] * 1.2), "a level-2 toolsmith's pickaxe has 20%% more uses (%d)" % uses)
	# Haul: carries 1 more at level 3.
	var sim7 := Sim.new_game()
	var a7: Dictionary = sim7.residents[0]
	set_level(a7, "haul", 3)
	check(Sim.carry_cap(a7) == Tuning.CARRY + 1, "a level-3 hauler carries %d" % (Tuning.CARRY + 1))
	sim7.paint_zone(open_rect(sim7, Vector2i(2, 1)))
	sim7.drop_items(Sim.rcell(a7) + Vector2i(1, 0), "cobble", 8)
	var most := 0
	for i in 20 * Tuning.TPS:
		sim7.step()
		if a7.carry != null:
			most = maxi(most, a7.carry.n)
	check(most == Tuning.CARRY + 1, "and does (%d per trip)" % most)
	# Skills survive a save; a direct order isn't stopped by switching its job off.
	var loaded := Sim.from_state(str_to_var(var_to_str(sim7.save_state())))
	check(Sim.level(loaded.residents[0], "haul") == 3, "skills survive a save")
	var t8: Dictionary = Sim.nearest(sim2.trees.filter(func(t): return t.alive), Sim.rcell(a2))
	var bo := sim2.add_resident("Bo", Sim.TRAVELERS[0][1], sim2.nearest_walkable(Sim.rcell(a2) + Vector2i(1, 0)))
	sim2.set_role(bo, "lumber")
	sim2.direct_order(bo, t8)
	run(sim2, 0.1)
	sim2.set_role(bo, "cook")
	check(bo.job != null and is_same(bo.job.target, t8), "a new job doesn't cancel a direct mining order")


## A resident whose job is Toolsmith, so spare tools are kept (issues #91, #134). Ada doesn't count.
func hire_toolsmith(sim: Sim) -> Dictionary:
	var t := sim.add_resident("Bram", Sim.TRAVELERS[4][1], sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(0, 3)))
	sim.set_role(t, "toolsmith")
	give_station(sim, t)  # issue #184: a job needs its workstation
	return t


func test_toolsmith_keeps_spares() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	hire_toolsmith(sim)
	var bench := sim.place_site("bench", open_rect(sim, Vector2i(3, 3)).position + Vector2i(1, 0))
	bench.stage = 1
	bench.done = true
	ada.axe = {"type": "wood_axe", "tier": 1, "dur": 1}
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 0), "plank", 6)
	sim.drop_items(Sim.rcell(ada) + Vector2i(-1, 0), "stick", 4)
	run(sim, 1)
	check(bench.queue.has("wood_axe") and bench.autoq.has("toolsmith"), "with an axe in use, the toolsmith queues a spare (%s %s)" % [bench.queue, bench.autoq])
	check(not bench.queue.has("wood_pick") and not bench.queue.has("stone_pick"), "no spare pickaxe while nobody uses one")
	run(sim, 20)
	check(sim.tool_items("axe", 0).size() == 1, "the spare axe is made and waits")
	run(sim, 5)
	check(bench.queue.is_empty(), "one spare is enough")
	# The axe breaks: Ada fetches the spare instead of stopping.
	var tree: Dictionary = Sim.nearest(sim.trees, Sim.rcell(ada))
	sim.direct_order(ada, tree)
	for i in 30 * Tuning.TPS:
		sim.step()
		if not tree.alive:
			break
	check(ada.axe == null and ada.broken.axe, "the old axe breaks")
	sim.designate_mine(whole_map(), null, ["tree"])  # more to chop, so she needs an axe
	run(sim, 20)
	check(ada.axe != null and not ada.broken.axe, "she picks up the spare (%s)" % [ada.axe])
	check(not stuck_text(sim).contains("Axe broke"), "and the report clears: " + stuck_text(sim))
	check(bench.queue.has("wood_axe") or sim.tool_items("axe", 0).size() == 1, "the toolsmith queues the next spare, or has made it (%s)" % [bench.queue])
	# The best tier the bench can make: stone once there's cobblestone.
	var sim2 := Sim.new_game()
	var a2: Dictionary = sim2.residents[0]
	hire_toolsmith(sim2)
	var b2 := sim2.place_site("bench", open_rect(sim2, Vector2i(3, 3)).position + Vector2i(1, 0))
	b2.stage = 1
	b2.done = true
	a2.pick = {"type": "wood_pick", "tier": 1, "dur": 5}
	sim2.drop_items(Sim.rcell(a2) + Vector2i(1, 0), "cobble", 3)
	run(sim2, 1)
	check(b2.queue.has("stone_pick"), "with cobblestone about, the spare is a stone pickaxe (%s)" % [b2.queue])
	check(stuck_text(sim2).contains("Planks needs 1 more log"), "short of sticks, the bench queues them and says what their planks need: " + stuck_text(sim2))
	# No toolsmith: Slice 1's rule. Nothing is queued, and a broken tool stops the resident.
	var sim3 := Sim.new_game()
	var a3: Dictionary = sim3.residents[0]
	var b3 := sim3.place_site("bench", open_rect(sim3, Vector2i(3, 3)).position + Vector2i(1, 0))
	b3.stage = 1
	b3.done = true
	a3.axe = {"type": "wood_axe", "tier": 1, "dur": 1}
	sim3.drop_items(Sim.rcell(a3) + Vector2i(1, 0), "plank", 6)
	sim3.drop_items(Sim.rcell(a3) + Vector2i(-1, 0), "stick", 4)
	var t3: Dictionary = Sim.nearest(sim3.trees, Sim.rcell(a3))
	sim3.direct_order(a3, t3)
	run(sim3, 30)
	check(b3.queue.is_empty(), "with no toolsmith, no spares are queued")
	check(a3.axe == null and stuck_text(sim3).contains("Axe broke. Craft one at the bench, or make someone the toolsmith"), "and a broken axe stops and reports: " + stuck_text(sim3))


func test_equip_a_chosen_tool() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var c := Sim.rcell(ada)
	sim.drop_items(c + Vector2i(2, 0), "stone_axe", 1)
	sim.drop_items(c + Vector2i(-2, 0), "wood_axe", 1)
	var wood: Dictionary = sim.items[c + Vector2i(-2, 0)]
	sim.equip_order(ada, wood)
	run(sim, 5)
	check(ada.axe != null and ada.axe.type == "wood_axe" and ada.kept.axe, "Equip: Ada fetches the wooden axe and keeps it")
	# A kept tool isn't swapped for a better one lying about.
	var tree: Dictionary = Sim.nearest(sim.trees, Sim.rcell(ada))
	sim.direct_order(ada, tree)
	run(sim, 20)
	check(not tree.alive and ada.axe.type == "wood_axe", "she chops with it rather than fetching the stone axe")
	# Equip another: the one in hand is dropped where the new one lay.
	var stone: Dictionary = sim.items[c + Vector2i(2, 0)]
	sim.equip_order(ada, stone)
	run(sim, 8)
	check(ada.axe.type == "stone_axe" and sim.items.has(c + Vector2i(2, 0)) and sim.items[c + Vector2i(2, 0)].type == "wood_axe", "equipping the stone axe leaves the wooden one in its place")
	sim.equip_order(ada, sim.items[c + Vector2i(2, 0)])
	run(sim, 8)
	check(ada.axe.type == "wood_axe" and ada.kept.axe, "she can be told to take the wooden one back")
	# "Use the best": back to swapping for a better tool when she next works.
	sim.release_kept_tool(ada, "axe")
	var t2: Dictionary = Sim.nearest(sim.trees.filter(func(t): return t.alive), Sim.rcell(ada))
	sim.direct_order(ada, t2)
	run(sim, 20)
	check(ada.axe.type == "stone_axe", "released, she picks up the better axe for her next tree")
	# A kept tool that breaks is forgotten.
	ada.kept.axe = true
	ada.axe.dur = 1
	var t3: Dictionary = Sim.nearest(sim.trees.filter(func(t): return t.alive), Sim.rcell(ada))
	sim.direct_order(ada, t3)
	run(sim, 20)
	check(not ada.kept.axe, "a kept tool that breaks is forgotten")
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(loaded.residents[0].has("kept"), "the choice is saved")


## Runs until `r` is away on a trip (or `seconds` pass).
func until_away(sim: Sim, r: Dictionary, seconds := 30.0) -> void:
	for i in int(seconds * Tuning.TPS):
		sim.step()
		if r.away:
			return


# ---------------------------------------------------------------- Slice 3: maps (issues #100-#103)

## A resident with a stone pickaxe, moved onto the old mine at its entrance.
func send_to_mine(sim: Sim, r: Dictionary) -> void:
	sim.set_role(r, "mason")  # one job each (issue #134): the one sent to dig is a stonemason (issue #177)
	give_station(sim, r)  # issue #184: a job needs its workstation
	r.pick = {"type": "stone_pick", "tier": 2, "dur": 99}
	sim.get_map(OldMine.ID).visited = true
	sim.move_to_map(r, OldMine.ID, sim.get_map(OldMine.ID).entrance)


## Issue #100: a resident only claims work on the map they're on, every map ticks, and the village's
## tallies leave out what lies on another map.
func test_residents_only_work_on_their_own_map() -> void:
	var sim := Sim.new_game()
	check(sim.maps.keys() == ["village", OldMine.ID, Road.ID, Meadow.ID, NetherLanding.ID] + NetherRoute.map_ids() and sim.map_id == "village", "a new game has the village, the old mine, the road between them, the meadow and the Nether landing, with the village current")
	var ada: Dictionary = sim.residents[0]
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Sim.rcell(ada) + Vector2i(1, 0))
	check(ada.map == "village" and tomas.map == "village", "residents start on the village map")
	send_to_mine(sim, tomas)
	check(tomas.map == OldMine.ID and sim.here().has(ada) and not sim.here().has(tomas), "travel moves Tomas onto the old mine")
	sim.designate_mine(whole_map())  # village trees and boulders: Ada's work, never Tomas's
	sim.on_map(OldMine.ID, func(): sim.designate_mine(Rect2i(0, 0, 16, 16)))
	var village_ids := {}
	for o in sim.trees + sim.boulders:
		village_ids[o.id] = true
	var crossed := false
	var mined_here := false
	for i in 90 * Tuning.TPS:
		sim.step()
		if tomas.job != null and tomas.job.target != null and village_ids.has(tomas.job.target.id):
			crossed = true
		if ada.job != null and ada.job.target != null and not village_ids.has(ada.job.target.id) and ada.job.target.get("kind", "") in ["tree", "boulder"]:
			crossed = true
		mined_here = mined_here or (tomas.job != null and tomas.job.work == "mason")
	check(sim.map_id == "village", "the sim is back on the village after ticking")
	check(not crossed, "nobody claims a job on another map")
	check(mined_here and sim.on_map(OldMine.ID, func(): return count(sim, "cobble") + count(sim, "coal")) > 0, "Tomas mines the old mine while nobody looks at it")
	check(sim.stats.felled > 0, "and Ada works the village meanwhile")
	# The village's counts leave out the mine's items.
	sim.on_map(OldMine.ID, func(): sim.drop_items(sim.get_map(OldMine.ID).entrance + Vector2i(1, 0), "coal", 5))
	check(sim.free_count("coal") == 0 and count(sim, "coal") == 0, "coal at the mine isn't in the village's counts")
	check(sim.on_map(OldMine.ID, sim.free_count.bind("coal")) >= 5, "it's counted at the mine")
	check(not Goals.village_text(sim).is_empty() and sim.map_id == "village", "the village's summary reads the village")
	# Commands about a resident act on the resident's map, whatever map is current.
	sim.fail_job(tomas)
	sim.direct_order(tomas, null, sim.get_map(OldMine.ID).entrance + Vector2i(2, 0))
	sim.step()
	check(tomas.job != null and tomas.job.kind == "move", "an order to walk is given on Tomas's own map")
	tomas.carry = {"type": "coal", "n": 2}
	var before: int = sim.on_map(OldMine.ID, func(): return count(sim, "coal"))
	sim.fail_job(tomas)
	check(sim.on_map(OldMine.ID, func(): return count(sim, "coal")) == before + 2 and count(sim, "coal") == 0, "what Tomas carried is set down at the mine, not in the village")
	# Stuck reasons carry their map.
	tomas.note = {"text": "Can’t reach this boulder", "until": sim.tick + 100}
	sim.compute_stuck()
	var entry = sim.stuck.filter(func(x): return x.focus_id == tomas.id)
	check(not entry.is_empty() and entry[0].map == OldMine.ID, "a stuck reason on the old mine says so")


## Issue #100: saving and loading keeps both maps and who is on which.
func test_save_and_load_two_maps() -> void:
	var sim := Sim.new_game()
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Sim.rcell(sim.residents[0]) + Vector2i(1, 0))
	send_to_mine(sim, tomas)
	sim.on_map(OldMine.ID, func(): sim.designate_mine(Rect2i(0, 0, 16, 16)))
	run(sim, 40)
	var mine_items: int = sim.get_map(OldMine.ID).items.size()
	var coal_left := sim.ore_left(OldMine.ID, "coal")
	var path := "user://test_two_maps.save"
	check(SaveFormat.write(path, {"summary": "x", "tick": sim.tick, "saved_at": 0, "state": sim.save_state(), "camera": {}, "speed": 1}), "saved")
	var r := SaveFormat.read(path)
	var loaded := Sim.from_state(r.data.state)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var mine := loaded.get_map(OldMine.ID)
	check(loaded.residents[1].map == OldMine.ID and loaded.residents[0].map == "village", "who is on which map survives")
	check(mine.items.size() >= mine_items and loaded.ore_left(OldMine.ID, "coal") == coal_left, "the mine's items and mined-out ore survive")
	check(mine.visited and mine.rock.size() == sim.get_map(OldMine.ID).rock.size() and mine.entrance == sim.get_map(OldMine.ID).entrance, "the mine's layout survives")
	check(loaded.maps.keys() == sim.maps.keys() and loaded.map_id == "village", "both maps load, with the village current")
	run(loaded, 20)
	check(loaded.residents[1].map == OldMine.ID, "Tomas keeps working at the mine after loading")


## Issue #102: the hand-laid old mine, with coal, stone and a hidden iron vein.
func test_old_mine_layout_and_ore() -> void:
	var sim := Sim.new_game()
	var mine := sim.get_map(OldMine.ID)
	check(OldMine.LAYOUT.all(func(row): return row.length() == 16) and mine.w == 16 and mine.h == 16, "the old mine is 16×16")
	check(mine.kind == "site" and not mine.known and not mine.visited and not mine.discovered, "it starts unknown and unvisited")
	check(mine.entrance == Vector2i(0, 8) and sim.on_map(OldMine.ID, sim.walkable.bind(mine.entrance)), "the party arrives at the entrance on the west edge")
	var ores := {}
	for b in mine.boulders:
		ores[b.get("ore", "stone")] = ores.get(b.get("ore", "stone"), 0) + 1
	check(ores == {"stone": 6, "coal": 6, "iron": 4}, "6 boulders (one before the door down), 6 coal ore and a 4-block iron vein (%s)" % ores)
	check(mine.boulders.filter(func(b): return b.get("ore", "") == "iron").all(func(b): return b.hidden), "the iron vein is hidden")
	check(not mine.is_dark(mine.entrance + Vector2i(1, 0)) and mine.is_dark(Vector2i(13, 13)), "torches light the entrance; the deep tunnel is dark")
	check(not sim.maps.village.is_dark(Vector2i(5, 5)), "nothing in the village is dark")
	# Every open cell is reachable from the entrance once the boulders and ore are mined.
	var open := 0
	for y in 16:
		for x in 16:
			if OldMine.LAYOUT[y][x] in [".", "o", "c", "E"]:
				open += 1
	var reach := {mine.entrance: true}
	var queue: Array = [mine.entrance]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in Sim.DIRS:
			var n: Vector2i = c + d
			if mine.in_bounds(n) and not reach.has(n) and OldMine.LAYOUT[n.y][n.x] in [".", "o", "c", "E"]:
				reach[n] = true
				queue.append(n)
	check(reach.size() == open, "every tunnel connects to the entrance (%d of %d)" % [reach.size(), open])
	# The hidden vein can't be marked or walked through; mining coal drops coal (issue #103).
	sim.on_map(OldMine.ID, func(): sim.designate_mine(Rect2i(0, 0, 16, 16)))
	check(mine.boulders.all(func(b): return b.des != b.get("hidden", false)), "Mine marks everything but the hidden vein")
	check(not sim.on_map(OldMine.ID, sim.walkable.bind(Vector2i(14, 13))), "the hidden vein is solid rock")
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Vector2i(16, 16))
	send_to_mine(sim, tomas)
	run(sim, 120)
	check(sim.stats.get("ore_mined", 0) > 0 and sim.on_map(OldMine.ID, func(): return count(sim, "coal")) >= Tuning.ORE_YIELD.coal, "mining coal ore drops coal")
	check(sim.on_map(OldMine.ID, func(): return count(sim, "iron_ore")) == 0, "no iron before the vein is found")
	sim.discover(OldMine.ID)
	check(mine.discovered and mine.boulders.all(func(b): return not b.has("hidden")), "discovering the vein reveals it")
	check(sim.on_map(OldMine.ID, sim.walkable.bind(Vector2i(14, 13))) == false, "the revealed vein is ore, still solid until mined")


## Issue #102: the site report, before and after a visit, and reserves that only go down.
func test_site_report_and_depletion() -> void:
	var sim := Sim.new_game()
	var rep := sim.site_report(OldMine.ID)
	check(rep.told == OldMine.TOLD and not rep.visited and rep.travel == -1.0, "before a visit: what the village was told, and no journey estimate until the road is walked")
	check(rep.resources.map(func(x): return x.name) == ["Stone", "Coal"] and rep.resources.all(func(x): return x.reserve == -1), "stone and coal, no estimates yet")
	check(rep.hazards.is_empty() and rep.access.is_empty(), "no hazards or access notes known yet")
	sim.get_map(OldMine.ID).visited = true
	rep = sim.site_report(OldMine.ID)
	check(rep.resources[0].reserve == 6 * Tuning.BOULDER_COBBLE and rep.resources[1].reserve == 6 * Tuning.ORE_YIELD.coal, "after a visit: estimated reserves (%s)" % [rep.resources])
	check(rep.resources.size() == 3 and rep.resources[2].name == "?" and rep.resources[2].reserve == -1, "iron shows as ? until it's found")
	check(rep.hazards.has("Dark tunnels past the torches: work there is slower") and rep.access == OldMine.ACCESS, "the dark tunnels and narrow access are reported")
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Vector2i(16, 16))
	send_to_mine(sim, tomas)
	sim.on_map(OldMine.ID, func():
		var coal: Dictionary = Sim.nearest(sim.boulders.filter(func(b): return b.get("ore", "") == "coal"), sim.m.entrance)
		sim.designate_mine(Rect2i(coal.cell, Vector2i.ONE)))
	var lowest: int = rep.resources[1].reserve
	var rose := false
	for i in 120 * Tuning.TPS:
		sim.step()
		if i % 20 == 0:
			var now: int = sim.site_report(OldMine.ID).resources[1].reserve
			rose = rose or now > lowest
			lowest = mini(lowest, now)
	check(lowest == 5 * Tuning.ORE_YIELD.coal and not rose, "mining a coal block lowers the coal estimate, and it never grows back")
	sim.discover(OldMine.ID)
	rep = sim.site_report(OldMine.ID)
	check(rep.resources[2].name == "Iron" and rep.resources[2].reserve == 4 * Tuning.ORE_YIELD.iron, "once found, the iron's reserve shows")


## Issue #103: coal, iron ore and iron ingots are hauled and counted like any other item.
func test_mine_items_are_hauled_and_counted() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	for t in ["coal", "iron_ore", "iron_ingot"]:
		check(Defs.ITEMS.has(t) and Defs.ITEMS[t].group == "ores" and Palette.ITEM_COLORS.has(t), "%s has a definition, a tally group and a colour" % t)
		check(ItemIcons.icon(t).get_width() == 64, "%s has an icon" % t)
	var cols := ["coal", "iron_ore", "iron_ingot"].map(func(t): return Palette.ITEM_COLORS[t])
	for c in cols:
		check(c.to_html() != Palette.ITEM_COLORS.cobble.to_html() and c.to_html() != Palette.ITEM_COLORS.log.to_html(), "its colour is distinct from cobblestone and logs")
	sim.paint_zone(Rect2i(Sim.rcell(ada) + Vector2i(2, -1), Vector2i(3, 2)))
	sim.drop_items(Sim.rcell(ada) + Vector2i(-2, 1), "coal", 6)
	sim.drop_items(Sim.rcell(ada) + Vector2i(-2, 2), "iron_ore", 3)
	sim.drop_items(Sim.rcell(ada) + Vector2i(-3, 2), "iron_ingot", 2)
	run(sim, 60)
	for t in {"coal": 6, "iron_ore": 3, "iron_ingot": 2}:
		var stored := sim.stacks_where(func(s): return s.type == t and sim.in_zone(s.cell))
		var n := 0
		for st in stored:
			n += st.n
		check(n == {"coal": 6, "iron_ore": 3, "iron_ingot": 2}[t] and sim.free_count(t) == n, "%d %s hauled to the stockpile and counted" % [n, t])


# ---------------------------------------------------------------- Slice 3: expeditions (issues #104-#107)

## Issue #104: the fireplace smelts iron ore with coal, iron tools are the best, and the toolsmith
## makes iron spares once there are ingots.
func test_smelting_and_iron_tools() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var spot := open_rect(sim, Vector2i(3, 3))
	var f := lit_fireplace(sim, spot.position + Vector2i(1, 0))
	sim.set_keep_meals(f, false)
	var near := spot.position + Vector2i(1, 3)
	sim.drop_items(near, "iron_ore", 2)
	sim.drop_items(near + Vector2i(1, 0), "coal", 3)
	sim.queue_add(f, "smelt_iron")
	sim.queue_add(f, "smelt_iron")
	var labels: Array = []
	for i in 40 * Tuning.TPS:
		sim.step()
		if ada.job != null and not labels.has(ada.job.label):
			labels.append(ada.job.label)
	check(labels.has("Smelting iron"), "Ada smelts at the fireplace (%s)" % [labels])
	check(count(sim, "iron_ingot") == 2 and count(sim, "iron_ore") == 0 and count(sim, "coal") == 1, "1 ore and 1 coal make each ingot (%d ingots, %d coal left)" % [count(sim, "iron_ingot"), count(sim, "coal")])
	check(Sim.recipe_job(Defs.recipe("smelt_iron")) == "cook" and Defs.recipe("smelt_iron").fuel == "coal", "smelting is Cook work, with coal as the fuel")
	# Iron tools: more uses and faster than stone.
	for kind in ["axe", "pick"]:
		var it: Dictionary = Defs.ITEMS["iron_" + kind]
		check(it.tool == kind and it.tier == 3 and Sim.full_uses("iron_" + kind) > Sim.full_uses("stone_" + kind), "an iron %s lasts longer than stone" % kind)
	check(Tuning.CHOP_TIME[3] < Tuning.CHOP_TIME[2] and Tuning.BREAK_TIME[3] < Tuning.BREAK_TIME[2], "and works faster")
	var bench := sim.place_site("bench", open_rect(sim, Vector2i(3, 3)).position + Vector2i(1, 0))
	bench.stage = 1
	bench.done = true
	sim.drop_items(Sim.rcell(ada) + Vector2i(-1, 1), "iron_ingot", 1)
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 1), "stick", 2)
	sim.queue_add(bench, "iron_pick")
	run(sim, 30)
	check(sim.tool_items("pick", 2).any(func(st): return st.type == "iron_pick" and st.dur == Sim.full_uses("iron_pick")), "3 ingots and 2 sticks make an iron pickaxe")
	check(ada.pick == null or ada.pick.type == "iron_pick", "a resident who picks up a pickaxe takes the iron one")
	# The toolsmith's spare is iron when there are ingots, before stone and wood.
	var sim2 := Sim.new_game()
	var a2: Dictionary = sim2.residents[0]
	hire_toolsmith(sim2)
	var b2 := sim2.place_site("bench", open_rect(sim2, Vector2i(3, 3)).position + Vector2i(1, 0))
	b2.stage = 1
	b2.done = true
	a2.pick = {"type": "stone_pick", "tier": 2, "dur": 5}
	sim2.drop_items(Sim.rcell(a2) + Vector2i(1, 0), "cobble", 3)
	sim2.drop_items(Sim.rcell(a2) + Vector2i(-1, 0), "iron_ingot", 3)
	run(sim2, 1)
	check(b2.queue.has("iron_pick") and not b2.queue.has("stone_pick"), "with ingots about, the spare is an iron pickaxe (%s)" % [b2.queue])


## A finished expedition board in an open spot, skipping its construction.
func built_board(sim: Sim) -> Dictionary:
	var spot := open_rect(sim, Vector2i(3, 3))
	var b := sim.place_site("board", spot.position + Vector2i(1, 0))
	b.stage = 1
	b.done = true
	sim._on_site_done(b)
	sim.rev += 1
	return b


## Issue #105: the expedition board is built like the bench, reserves its map room plot, and tells
## the village about the old mine.
func test_expedition_board() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	check(not sim.get_map(OldMine.ID).known, "nobody knows of the old mine before there's a board")
	var spot := open_rect(sim, Vector2i(3, 3))
	var o := spot.position + Vector2i(1, 0)
	check(sim.placement_check("board", o) == "", "a board fits on open grass")
	var b := sim.place_site("board", o)
	check(b.plot == Rect2i(o + Vector2i(-1, 0), Vector2i(3, 3)), "it reserves the 3×3 plot for a map room")
	check(sim.placement_check("bench", o + Vector2i(1, 1)) == "Overlaps a reserved plot", "nothing can be built on its plot")
	check(sim.placement_check("board", Vector2i(0, 5)) == "Not enough room to grow into a map room", "its plot needs room too")
	check(Sim.staging_cells(b).all(func(c): return b.plot.has_point(c) and c != o), "the party gathers on the plot in front of it")
	run(sim, 1)
	check(stuck_text(sim).contains("Expedition board: Expedition board needs 6 more planks"), "it says what it needs: " + stuck_text(sim))
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 0), "plank", 6)
	sim.drop_items(Sim.rcell(ada) + Vector2i(-1, 0), "stick", 4)
	var toast := false
	for i in 60 * Tuning.TPS:
		sim.step()
		for e in sim.events:
			toast = toast or e.text.contains("expedition board is up")
		sim.events.clear()
		if b.done:
			break
	check(b.done and toast, "it's built from 6 planks and 4 sticks, and says so")
	check(sim.get_map(OldMine.ID).known and not sim.get_map(OldMine.ID).visited, "the old mine is known now, though nobody has been")
	check(sim.expedition_board() == b and not sim.walkable(o), "the finished board stands in its cell")


## Issue #106: planning a party, its provisions and cargo, which share the packs.
func test_planning_an_expedition() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Sim.rcell(ada) + Vector2i(1, 0))
	var plan := sim.new_plan()
	check(plan.party == [ada.id] and plan.dest == OldMine.ID, "a new plan starts with Ada, for the old mine")
	check(sim.plan_problems(plan).has("Build an expedition board first"), "it needs a board")
	built_board(sim)
	check(sim.plan_targets(OldMine.ID).map(func(x): return x.item) == ["cobble", "coal"], "before a visit, the party can be sent for stone or coal")
	# Supplies and cargo share the packs: PACK_CAPACITY per member.
	plan.meals = 3
	plan.picks = 1
	check(Sim.pack_capacity(plan) == Tuning.PACK_CAPACITY and Sim.cargo_room(plan) == Tuning.PACK_CAPACITY - 4, "one member's packs: 4 supplies leave %d for cargo" % Sim.cargo_room(plan))
	sim.aim_plan(plan, "coal", Sim.cargo_room(plan) + 1)
	check(sim.plan_problems(plan).has("The packs only have room for %d of what's wanted" % Sim.cargo_room(plan)), "a target bigger than the packs says so: %s" % [sim.plan_problems(plan)])
	plan.meals += 2
	check(Sim.cargo_room(plan) == Tuning.PACK_CAPACITY - 6, "more provisions leave less room for cargo")
	plan.party.append(tomas.id)
	check(Sim.pack_capacity(plan) == 2 * Tuning.PACK_CAPACITY, "each member adds to the packs")
	# The return food is kept unless the plan says it may be spent.
	plan.meals = 1
	check(sim.plan_problems(plan).has("Pack at least 2 meals for the walk home"), "two need a meal each for the walk home")
	plan.meals = 4
	var kept := Sim.site_minutes(plan)
	plan.spend_return = true
	check(Sim.site_minutes(plan) > kept and kept > 0.0, "spending the return food stretches the time on site (%.1f → %.1f min)" % [kept, Sim.site_minutes(plan)])
	plan.spend_return = false
	sim.aim_plan(plan, plan.target.item, 6)
	for k in plan.policy:
		plan.policy[k] = false
	check(sim.plan_problems(plan).has("Choose when the party comes home"), "a plan needs a return policy")
	plan.policy.full = true
	check(sim.plan_problems(plan).is_empty(), "a full plan has no problems: %s" % [sim.plan_problems(plan)])
	# Arriving residents can't be picked, and the list says why.
	tomas.arriving = true
	check(sim.cant_join(tomas) == "Still walking in" and sim.plan_problems(plan).has("Tomas can’t go: still walking in"), "a resident still walking in can't go")
	tomas.arriving = false
	check(sim.cant_join(tomas) == "", "once he's here, he can")
	plan.party.append(sim.add_resident("Mira", Sim.TRAVELERS[1][1], Sim.rcell(ada)).id)
	plan.party.append(sim.add_resident("Jonas", Sim.TRAVELERS[2][1], Sim.rcell(ada)).id)
	check(sim.plan_problems(plan).has("At most 3 can go"), "at most 3 go")
	plan.party.resize(2)
	# Confirming starts packing; it doesn't send anyone. One expedition at a time.
	check(sim.plan_expedition(plan) == "" and sim.expedition.state == "staging", "confirming the plan starts packing")
	check(ada.map == "village" and not ada.away, "nobody leaves yet")
	check(sim.plan_expedition(sim.new_plan()) == "An Overworld party is already out", "a second Overworld plan can't be made while one is under way")
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(loaded.expedition.state == "staging" and loaded.expedition.party == plan.party and loaded.expedition.meals == 4, "the plan is saved")


## Issue #107: supplies are packed at the board by haulers, the party gathers there, and Depart
## sends them off, out of village labor. Cancelling unpacks everything back to the stockpile.
func test_staging_and_departure() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Sim.rcell(ada) + Vector2i(1, 0))
	var b := built_board(sim)
	var zone := open_rect(sim, Vector2i(3, 2))
	sim.paint_zone(zone)
	var plan := sim.new_plan()
	plan.party = [ada.id]
	plan.meals = 2
	plan.picks = 1
	sim.aim_plan(plan, plan.target.item, 6)
	check(sim.plan_expedition(plan) == "", "planned")
	run(sim, 1)
	check(stuck_text(sim).contains("Expedition: No meals to pack. Cooks make them at the fireplace, or plan fewer"), "with no meals, it says so and how to fix it: " + stuck_text(sim))
	check(stuck_text(sim).contains("Expedition: No spare pickaxes to pack"), "and the same for pickaxes")
	check(sim.depart() != "" and ada.map == "village" and not ada.away, "Depart does nothing until everything is packed")
	sim.drop_items(zone.position, "bread", 3)
	sim.drop_items(zone.position + Vector2i(1, 0), "stone_pick", 1, 9)
	var tomas_packed := false
	var ada_village_work := false
	for i in 40 * Tuning.TPS:
		sim.step()
		if tomas.job != null and tomas.job.kind == "deliver" and is_same(tomas.job.target, b):
			tomas_packed = true
		if ada.job != null and not (ada.job.kind in ["deliver", "stage", "eat"]):
			ada_village_work = true
		if i == 2 * Tuning.TPS:
			check(stuck_text(sim).contains("Expedition: Waiting for"), "while packing, the wait shows: " + stuck_text(sim))
	check(tomas_packed, "village residents pack the supplies (Haul)")
	check(not ada_village_work, "the party only packs and waits; it takes no other village work")
	check(sim.packed() == {"meals": 2, "picks": 1, "wheat": 0, "sticks": 0, "cobble": 0, "planks": 0} and b.tools.size() == 1 and b.tools[0].dur == 9, "2 meals and the spare pickaxe are packed, with its wear (%s)" % [sim.packed()])
	check(count(sim, "bread") == 1, "packed meals leave the stockpile")
	check(sim.at_board(ada) and Sim.staging_cells(b).has(Sim.rcell(ada)), "Ada waits at the board")
	check(sim.depart_blocker() == "", "everything is ready: %s" % sim.depart_blocker())
	# Saving while packed keeps it packed.
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(loaded.packed() == {"meals": 2, "picks": 1, "wheat": 0, "sticks": 0, "cobble": 0, "planks": 0} and loaded.site(b.id).tools[0].dur == 9, "what's packed survives a save")
	run(loaded, 10)
	check(loaded.at_board(loaded.residents[0]), "and Ada goes back to the board after loading")
	# Cancelling on the copy: the supplies go back through haul jobs.
	loaded.cancel_expedition()
	check(loaded.expedition.is_empty() and loaded.packed() == {"meals": 0, "picks": 0, "wheat": 0, "sticks": 0, "cobble": 0, "planks": 0}, "cancelling unpacks the board")
	run(loaded, 40)
	var stored := loaded.stacks_where(func(st): return st.type in ["bread", "stone_pick"] and loaded.in_zone(st.cell))
	check(stored.map(func(st): return st.type).count("stone_pick") == 1 and count(loaded, "bread") == 3, "the meals and the pickaxe are hauled back to the stockpile")
	check(loaded.residents[0].job == null or loaded.residents[0].job.kind != "stage", "and Ada goes back to work")
	# Depart: the party leaves with the packed supplies and is out of village labor.
	check(sim.depart() == "", "Depart sends the party off")
	check(sim.expedition.state == "out" and sim.expedition.packed == {"bread": 2} and sim.expedition.tools.size() == 1, "the expedition carries what was packed")
	check(b.store.is_empty() and sim.cant_join(ada) == "Out with the party", "the board is empty again")
	run(sim, 0.5)
	check(ada.job != null and ada.job.kind == "road" and sim.carrying_packs(ada), "Ada carries the packs to the signpost")
	until_on_road(sim, ada)
	check(sim.on_road(ada) and ada.trip == OldMine.ID and not ada.away and not sim.here().has(ada), "then she's on the road, not in the village's labor")
	var road := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(road.residents[0].map == Road.ID and road.residents[0].trip == OldMine.ID, "saving on the road keeps her on the road")
	until_at_site(sim, [ada])
	run(sim, 2)
	var mine := sim.get_map(OldMine.ID)
	check(ada.map == OldMine.ID and not ada.away and mine.visited and mine.known, "after the walk, Ada is at the old mine")
	check(sim.expedition.provisions == {"bread": 2} and sim.on_map(OldMine.ID, func(): return sim.items.is_empty()), "with the supplies in the packs (%s)" % [sim.expedition.provisions])
	check(sim.expedition.tools.is_empty() and ada.pick != null and ada.pick.dur == 9, "Ada, who had no pickaxe, takes the spare from the packs")
	check(tomas.map == "village", "Tomas keeps the village going")



## A party of Ada and Tomas, packed and sent off for 6 coal from the old mine with 4 bread (2 of them
## the return food) and a spare pickaxe.
## Returns {ada, tomas, board}, as they step onto the road.
func send_party(sim: Sim) -> Dictionary:
	var ada: Dictionary = sim.residents[0]
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Sim.rcell(ada) + Vector2i(1, 0))
	for r in [ada, tomas]:
		r.pick = {"type": "stone_pick", "tier": 2, "dur": 99}
	var b := built_board(sim)
	var plan := sim.new_plan()
	plan.party = [ada.id, tomas.id]
	plan.meals = 4
	plan.picks = 1
	sim.aim_plan(plan, "coal", 6)
	sim.plan_expedition(plan)
	b.store = {"bread": 4, "stone_pick": 1}
	b.tools = [{"type": "stone_pick", "dur": 9}]
	for i in 30 * Tuning.TPS:
		sim.step()
		if sim.depart_blocker() == "":
			break
	sim.depart()
	return {"ada": ada, "tomas": tomas, "board": b}


## Issues #108, #118: the party walks to the signpost on the east edge, onto the road map, along it
## and into the mine at its far end, and back the same way; a trip survives saving in either direction.
func test_travel_to_the_mine_and_back() -> void:
	var sim := Sim.new_game()
	var sign := sim.route_sign()
	check(sign == Vector2i(sim.w - 1, sim.h / 2) and sim.walkable(sign), "the signpost to the old mine stands on the east edge")
	check(sim.farm_blocked(sign) == "the signpost" and sim.placement_check("bench", sign) == "The signpost to the old mine is in the way", "nothing is built, farmed or stockpiled on it")
	var p := send_party(sim)
	var ada: Dictionary = p.ada
	var tomas: Dictionary = p.tomas
	check(sim.call_home() != "", "the party can't be called home before it gets there")
	until_on_road(sim, ada, 60)
	var left_at := sim.tick
	check(Sim.rcell(ada) == Road.VILLAGE_END and ada.trip == OldMine.ID and not ada.away, "Ada steps onto the road at its village end")
	check(sim.road().known and (ada.job == null or ada.job.kind == "road"), "and walks it")
	var arrived := -1
	var arrived_at := Vector2i(-9, -9)
	for i in int(ROAD * Tuning.TPS):
		sim.step()
		if arrived < 0 and ada.map == OldMine.ID:
			arrived = sim.tick
			arrived_at = Sim.rcell(ada)
	var walked := float(arrived - left_at) / Tuning.TPS
	check(arrived > 0 and absf(walked - sim.route_walk_time()) < 3.0, "the walk takes about the road's estimate (%.1f s, estimated %.1f s)" % [walked, sim.route_walk_time()])
	check(ada.map == OldMine.ID and tomas.map == OldMine.ID and arrived_at == sim.get_map(OldMine.ID).entrance, "at the mine's entrance")
	run(sim, 5)
	# The way home: the party walks to the entrance, then back along the road.
	check(sim.call_home() == "" and sim.expedition.leg == "home", "Call the party home")
	check(sim.call_home() == "The party is already heading home", "only once")
	until_on_road(sim, ada, 30)
	check(sim.on_road(ada) and ada.trip == "village" and Sim.rcell(ada) == Road.MINE_END, "they step onto the road at the mine end, heading home")
	run(sim, 3)
	var mid := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(mid.residents[0].map == Road.ID and mid.residents[0].trip == "village" and mid.expedition.leg == "home", "saving on the road home keeps them on it")
	run(sim, ROAD)
	check(ada.map == "village" and not ada.away and Sim.manhattan(Sim.rcell(ada), sim.route_sign()) <= 1, "they come back at the village signpost")
	run(mid, ROAD)
	check(mid.residents[0].map == "village" and mid.expedition.is_empty(), "and the loaded game's party gets home too")


func until_on_road(sim: Sim, r: Dictionary, seconds := 30.0) -> void:
	for i in int(seconds * Tuning.TPS):
		sim.step()
		if r.map == Road.ID:
			return


## Issue #112: back at the signpost, the cargo and leftover meals are set down as stacks and hauled
## to the stockpile; a report says what came back and what it cost; the board is free again.
func test_return_and_unloading() -> void:
	var sim := Sim.new_game()
	var zone := open_rect(sim, Vector2i(4, 3))
	sim.paint_zone(zone)
	var p := send_party(sim)
	var ada: Dictionary = p.ada
	var tomas: Dictionary = p.tomas
	check(sim.plan_problems(sim.new_plan()).has("An Overworld party is already out"), "the board is locked while the party is out")
	for i in int((ROAD + 40) * Tuning.TPS):
		sim.step()
		if sim.at_site(ada) and sim.at_site(tomas):
			break
	ada.hunger = 30.0  # she eats a meal from the packs
	tomas.pick.dur = 1  # his pickaxe breaks, and he takes the spare from the packs
	for i in int((ROAD + 240) * Tuning.TPS):
		sim.step()
		if sim.expedition.is_empty():
			break
	check(sim.expedition.is_empty() and ada.map == "village" and tomas.map == "village", "the party mines its 6 coal, comes home and the expedition is over")
	var near_sign := sim.stacks_where(func(st): return Sim.manhattan(st.cell, sim.route_sign()) <= 3)
	check(near_sign.any(func(st): return st.type == "coal"), "the cargo is set down at the signpost as stacks")
	var b: Dictionary = p.board
	check(b.report.size() == 2 and b.report[0].begins_with("Back from the old mine: ") and "coal" in b.report[0], "the board has the report: %s" % [b.report])
	check(b.report[1].contains("meal") and b.report[1].ends_with("1 pickaxe broken") and not b.report[1].begins_with("0 meals"), "with what it cost: %s" % b.report[1])
	check(sim.plan_problems(sim.new_plan()).filter(func(x): return x == "One expedition at a time").is_empty() and sim.cant_join(ada) == "", "the board is free for the next expedition")
	var coal_home := 0
	for st in near_sign:
		coal_home += st.n if st.type == "coal" else 0
	run(sim, 60)
	var stored := 0
	for st in sim.stacks_where(func(st): return st.type == "coal" and sim.in_zone(st.cell)):
		stored += st.n
	check(stored == coal_home and coal_home >= 6, "the coal is hauled to the stockpile (%d of %d)" % [stored, coal_home])
	check(sim.stats.get("expeditions", 0) == 1, "the village counts its expeditions")


## Steps until a party member is at the site, working it.
func until_at_site(sim: Sim, rs: Array, seconds := ROAD + 40) -> void:
	for i in int(seconds * Tuning.TPS):
		if rs.all(func(r): return sim.at_site(r)):
			return
		sim.step()


## Issue #109: the party works the site by its orders: it marks and mines the objective, packs what
## it mines, eats from the packs (keeping the return food), replaces a broken pickaxe from the packs,
## and heads home when its return policy is met.
func test_party_works_the_site() -> void:
	var sim := Sim.new_game()
	var p := send_party(sim)
	var ada: Dictionary = p.ada
	var tomas: Dictionary = p.tomas
	until_at_site(sim, [ada, tomas])
	check(sim.expedition.provisions == {"bread": 4} and sim.expedition.tools.size() == 1 and sim.pack_load() == 5, "the packs hold 4 meals and a spare pickaxe (%d of %d)" % [sim.pack_load(), Sim.pack_capacity(sim.expedition)])
	check(sim.on_map(OldMine.ID, func(): return sim.items.is_empty()), "nothing is set down at the entrance")
	sim.step()
	run(sim, 1)
	var marked: Array = sim.get_map(OldMine.ID).boulders.filter(func(b): return b.des)
	check(marked.any(func(b): return b.get("ore", "") == "coal") and marked.all(func(b): return b.get("ore", "") == "coal" or not b.has("ore")), "the objective's coal is marked by itself, with any boulder in the way (%d blocks)" % marked.size())
	check(marked.all(func(b): return not b.get("loose", false)), "but never a block under a loose ceiling")
	# Mining fills the packs, the objective first; a broken pickaxe is replaced from the packs.
	tomas.pick.dur = 1
	var took_spare := false
	for i in 120 * Tuning.TPS:
		sim.step()
		took_spare = took_spare or (tomas.pick != null and tomas.pick.dur == 9)
		if sim.expedition.get("leg", "") == "home":
			break
	check(took_spare and sim.expedition.tools.is_empty(), "Tomas's pickaxe broke and he took the spare from the packs")
	check(sim.expedition.home_why == "target reached" and sim.objective_packed() >= 6, "with 6 coal packed, the party heads home: target reached (%s, %d)" % [sim.expedition.get("home_why", ""), sim.objective_packed()])
	# Provisions: the hungry eat from the packs, but not the return food.
	var sim2 := Sim.new_game()
	var p2 := send_party(sim2)
	until_at_site(sim2, [p2.ada, p2.tomas])
	sim2.expedition.policy = {"target": false, "full": false, "low": false}
	sim2.aim_plan(sim2.expedition, sim2.expedition.target.item, 99)
	p2.ada.hunger = 30.0
	p2.tomas.hunger = 30.0
	run(sim2, 5)
	check(sim2.expedition.provisions.get("bread", 0) == 2 and p2.ada.hunger > 40.0 and p2.tomas.hunger > 40.0, "both eat a meal from the packs (%s)" % [sim2.expedition.provisions])
	p2.ada.hunger = 30.0
	run(sim2, 5)
	check(sim2.expedition.provisions.get("bread", 0) == 2 and p2.ada.hunger < 40.0, "the last 2 meals are the return food: Ada goes hungry rather than eat them")
	check(sim2.spendable_meals() == 0, "nothing left to spend")
	sim2.expedition.spend_return = true
	run(sim2, 15)  # once she's done with the block she's on
	check(sim2.expedition.provisions.get("bread", 0) == 1, "with Spend it chosen, she eats the return food")
	# The policies: food runs low once only the return food is left.
	sim2.expedition.spend_return = false
	sim2.expedition.policy.low = true
	run(sim2, 1)
	check(sim2.expedition.get("home_why", "") == "provisions low", "provisions low sends them home (%s)" % sim2.expedition.get("home_why", ""))
	# Packs full: cargo stops at capacity.
	var sim3 := Sim.new_game()
	var p3 := send_party(sim3)
	until_at_site(sim3, [p3.ada, p3.tomas])
	sim3.expedition.policy = {"target": false, "full": true, "low": false}
	sim3.aim_plan(sim3.expedition, "cobble", 99)
	sim3.expedition.cargo = {"cobble": Sim.pack_capacity(sim3.expedition) - sim3.pack_load() - 3}  # nearly full already
	for i in 300 * Tuning.TPS:
		sim3.step()
		if sim3.expedition.get("leg", "") == "home":
			break
	check(sim3.expedition.get("home_why", "") == "packs full" and sim3.pack_load() == Sim.pack_capacity(sim3.expedition), "full packs send them home: %d of %d (%s)" % [sim3.pack_load(), Sim.pack_capacity(sim3.expedition), sim3.expedition.get("home_why", "")])
	check(sim3.on_map(OldMine.ID, func(): return count(sim3, "cobble")) > 0, "what didn't fit stays at the mine")
	# A save at the site keeps the packs.
	var loaded := Sim.from_state(str_to_var(var_to_str(sim2.save_state())))
	check(loaded.expedition.provisions == sim2.expedition.provisions and loaded.expedition.cargo == sim2.expedition.cargo, "the packs survive a save")


## Issue #110: hazards hurt; the injured can't mine; a serious injury stops the game with a choice;
## Ada is never seriously hurt; healing takes the tuned time in bed, longer without one.
func test_hazards_and_injuries() -> void:
	var sim := Sim.new_game()
	var mine := sim.get_map(OldMine.ID)
	check(mine.boulders.filter(func(b): return b.get("loose", false)).size() == OldMine.LOOSE.size() and mine.ledges == OldMine.LEDGES, "the old mine has its loose ceilings and its ledge")
	check(OldMine.LEDGES.all(func(c): return mine.is_dark(c)), "the ledge is in the dark")
	mine.visited = true
	var hz: Array = sim.site_report(OldMine.ID).hazards
	check(hz.size() == 3 and hz.any(func(h): return h.begins_with("Loose ceilings")) and hz.any(func(h): return h.begins_with("A ledge")), "the site report lists every hazard: %s" % [hz])
	# A cave-in: mining loose ceilings, with the sim's seeded random numbers, hurts someone.
	var hurt_by_cave_in := false
	for seed in range(1, 12):
		var s2 := Sim.new_game()
		s2.rng.seed = seed
		var t := s2.add_resident("Tomas", Sim.TRAVELERS[0][1], Vector2i(16, 16))
		send_to_mine(s2, t)
		s2.on_map(OldMine.ID, func():
			for b in s2.boulders:
				b.des = b.get("loose", false) or b.cell == Vector2i(6, 8) or b.cell == Vector2i(10, 9))
		for i in 200 * Tuning.TPS:
			s2.step()
			if t.hurt > 0:
				break
		if t.hurt > 0 and s2.stats.get("injuries", 0) > 0:
			hurt_by_cave_in = true
			break
	check(hurt_by_cave_in, "mining a loose ceiling can bring it down on the miner")
	# The injured can't mine, and walk and work slower.
	var p := send_party(sim)
	var ada: Dictionary = p.ada
	var tomas: Dictionary = p.tomas
	until_at_site(sim, [ada, tomas])
	sim.injure(tomas, 1, "a test")
	run(sim, 20)
	check(tomas.hurt == 1 and not (tomas.job != null and tomas.job.kind == "gather"), "injured, Tomas doesn't mine (%s)" % (tomas.job.label if tomas.job != null else "idle"))
	check(Sim.hurt_speed(tomas) == Tuning.INJURED_SPEED, "and moves at %d%%" % int(Tuning.INJURED_SPEED * 100))
	# Ada is protected: never seriously hurt.
	sim.injure(ada, 2, "a test")
	check(ada.hurt == 1 and sim.pending.is_empty(), "Ada can be hurt, but never seriously")
	# A serious injury stops the game for the player: retreat or press on.
	sim.events.clear()
	sim.injure(tomas, 2, "a fall in the dark")
	check(sim.pending.size() == 1 and sim.pending[0].kind == "injury" and sim.events.any(func(e): return e.type == "pause"), "a serious injury raises a choice and pauses the game")
	check(sim.pending[0].options.map(func(o): return o.id) == ["retreat", "press_on"], "Retreat or Press on")
	var pressed := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(pressed.pending.size() == 1, "the choice survives a save")
	pressed.choose("press_on")
	run(pressed, 30)
	var lt: Dictionary = pressed.residents[1]
	check(pressed.expedition.leg == "out" and lt.job != null and lt.job.kind == "hurt" and Sim.manhattan(Sim.rcell(lt), pressed.get_map(OldMine.ID).entrance) <= 1, "Press on: Tomas waits at the entrance while the rest work")
	sim.choose("retreat")
	check(sim.pending.is_empty() and sim.expedition.leg == "home" and sim.expedition.home_why.begins_with("retreat"), "Retreat: the party heads home (%s)" % sim.expedition.home_why)
	for i in int((ROAD + 180) * Tuning.TPS):
		sim.step()
		if sim.expedition.is_empty():
			break
	check(sim.expedition.is_empty() and p.board.report.size() == 3 and "Ada injured" in p.board.report[2] and "Tomas seriously injured" in p.board.report[2], "the report names who was hurt: %s" % [p.board.report])
	# Home: healing in bed takes HEAL_TIME; Tomas has no bed of his own, so he heals slower.
	var house := sim.place_site("house", open_rect(sim, Vector2i(5, 5)).position)
	house.stage = 4
	house.done = true
	house.owner = ada.id
	sim.rev += 1
	var healed_at := -1.0
	for i in int((Tuning.HEAL_TIME[1] + 60) * Tuning.TPS):
		sim.step()
		if ada.hurt == 0:
			healed_at = float(i) / Tuning.TPS
			break
	check(healed_at > Tuning.HEAL_TIME[1] - 10.0 and healed_at < Tuning.HEAL_TIME[1] + 30.0, "Ada heals in her bed in about %d s (%.0f s; %s, hurt %d heal %.0f, %s)" % [int(Tuning.HEAL_TIME[1]), healed_at, ada.job.label if ada.job != null else "idle", ada.hurt, ada.heal, ada.map])
	check(tomas.hurt == 2 and tomas.job != null and tomas.job.kind == "rest", "Tomas, with no bed, is still resting")
	check(stuck_text(sim).contains("Tomas: Injured, resting: no bed of their own, so it's slower"), "and says why: " + stuck_text(sim))


## Issue #111: mining near the hidden vein finds it, and the game stops for a choice: keep mining,
## investigate, or mark it and go home.
func test_iron_discovery() -> void:
	var sims := {}
	for choice in ["keep", "investigate", "return"]:
		var sim := Sim.new_game()
		var p := send_party(sim)
		until_at_site(sim, [p.ada, p.tomas])
		sim.expedition.policy = {"target": false, "full": false, "low": false}
		var mine := sim.get_map(OldMine.ID)
		check(not sim.on_map(OldMine.ID, func(): return mine.boulders.any(func(b): return b.get("ore", "") == "iron" and not b.get("hidden", false))), "the iron is hidden before it's found")
		sim.on_map(OldMine.ID, func():
			for b in sim.boulders:
				b.des = not b.has("ore") and not b.cell in [Vector2i(12, 8), Vector2i(14, 8)]  # the stone, which opens the way to the rubble (not the door's)
			)
		for i in 300 * Tuning.TPS:
			sim.step()
			if not sim.pending.is_empty():
				break
		check(mine.found and not mine.discovered and sim.pending.size() == 1 and sim.pending[0].kind == "discovery", "%s: mining the rubble finds the vein, and the game stops for a choice" % choice)
		check(sim.pending[0].options.map(func(o): return o.id) == ["keep", "investigate", "return"] and sim.pending[0].options.all(func(o): return o.cost != ""), "three choices, each with its cost")
		check(sim.site_report(OldMine.ID).finds == ["Iron vein found, not surveyed"] and not sim.plan_targets(OldMine.ID).any(func(x): return x.item == "iron_ore"), "the report shows the vein, not yet a target")
		sim.choose(choice)
		sims[choice] = [sim, p]
	# Keep mining: the vein stays marked and can be mined.
	var keep: Sim = sims.keep[0]
	keep.on_map(OldMine.ID, func(): keep.designate_mine(Rect2i(0, 0, 16, 16)))
	var iron_marked: bool = keep.get_map(OldMine.ID).boulders.any(func(b): return b.get("ore", "") == "iron" and b.des)
	check(iron_marked and keep.expedition.leg == "out", "Keep mining: the vein can be marked and mined, and the party stays")
	# Investigate: someone spends time and pickaxe uses, then iron is a known resource.
	var inv: Sim = sims.investigate[0]
	var uses_before: int = sims.investigate[1].ada.pick.dur + sims.investigate[1].tomas.pick.dur
	var surveyed := false
	for i in 120 * Tuning.TPS:
		inv.step()
		if inv.get_map(OldMine.ID).discovered:
			surveyed = true
			break
	check(surveyed and inv.plan_targets(OldMine.ID).any(func(x): return x.item == "iron_ore"), "Investigate: the vein is surveyed and iron can be a target")
	check(inv.site_report(OldMine.ID).resources[2].reserve == 4 * Tuning.ORE_YIELD.iron and inv.site_report(OldMine.ID).finds.is_empty(), "with its size known")
	check(sims.investigate[1].ada.pick.dur + sims.investigate[1].tomas.pick.dur <= uses_before - Tuning.SURVEY_USES, "at the cost of %d pickaxe uses" % Tuning.SURVEY_USES)
	# Mark it and return later: the party heads home now.
	var ret: Sim = sims["return"][0]
	check(ret.expedition.leg == "home" and ret.get_map(OldMine.ID).found, "Mark it and return later: the party heads home, the vein remembered")
	var loaded := Sim.from_state(str_to_var(var_to_str(ret.save_state())))
	check(loaded.get_map(OldMine.ID).found and not loaded.get_map(OldMine.ID).discovered and loaded.get_map(OldMine.ID).boulders.any(func(b): return b.get("ore", "") == "iron" and not b.has("hidden")), "the find survives a save")


## Issue #113: the Slice 2 end-state save the Slice 3 bot starts from still loads, upgraded.
func test_slice2_fixture_loads() -> void:
	var r := SaveFormat.read("res://tests/fixtures/slice2_village.save")
	check(not r.has("error"), "the Slice 2 village reads: %s" % r.get("error", ""))
	if r.has("error"):
		return
	var sim := Sim.from_state(r.data.state)
	check(sim.residents.size() == 3 and Goals.current(sim) < 0, "three residents, and the founding done")
	check(sim.sites.any(func(s): return s.tpl == "fireplace" and s.done) and sim.free_count("bread") >= 6 and sim.free_count("plank") >= 6, "a fireplace, meals and planks to start Slice 3 with")


## Issue #118: the road between the village and the old mine is a map of its own, known with the mine,
## and an old save's party on the road is placed at the matching point along it.
func test_road_to_the_mine() -> void:
	var sim := Sim.new_game()
	var rd := sim.road()
	check(rd.kind == "route" and rd.w == 48 and rd.h == 7 and rd.name == "Road to the mine", "the road is a 48×7 map of its own")
	check(not rd.known, "nobody knows it before the expedition board")
	var p := send_party(sim)
	check(rd.known and sim.get_map(OldMine.ID).known, "the board brings word of the mine and the road to it")
	check(Road.segment_count() == 6 and range(6).all(func(i): return Road.seg_len(i) == 8), "6 segments of 8 cells")
	var through: bool = sim.on_map(Road.ID, func(): return sim.find_path(Road.VILLAGE_END, sim.cell_set([Road.MINE_END])) != null)
	check(through, "the road can be walked end to end, around the cut's boulders")
	var walk := sim.route_walk_time()
	check(walk > 12.0 and walk < 25.0, "walking it takes about %.0f s" % walk)
	# A party saved on the road by an older version is placed along it, still heading the same way.
	until_on_road(sim, p.ada)
	var d := {"v": 17, "state": str_to_var(var_to_str(sim.save_state()))}
	d.state.maps.erase(Road.ID)
	var old: Dictionary = d.state.residents[0]
	old.map = "village"
	old.away = true
	old.trip = OldMine.ID
	old.back_at = d.state.tick + 15 * Tuning.TPS  # a quarter of the old 60 s walk left
	SaveFormat._v17_to_v18(d)
	var up := Sim.from_state(d.state)
	var ua: Dictionary = up.residents[0]
	check(ua.map == Road.ID and not ua.away and Sim.rcell(ua) == Vector2i(35, Road.LINE_ROW), "a v17 party three quarters of the way there is placed three quarters along the road (%s)" % Sim.rcell(ua))
	check(up.road().known, "and the road is known")
	run(up, ROAD)
	check(ua.map == OldMine.ID, "and walks on to the mine")


## Issue #119: the first trip reveals the road's segments; the stream is forded slowly until a plank
## bridge is built; the cut's boulders are mined to clear it; the report and estimates follow.
func test_survey_and_obstacles() -> void:
	var sim := Sim.new_game()
	var p := send_party(sim)
	var rd := sim.road()
	check(rd.seen == 1 and not sim.route_surveyed(), "only the first segment is known before anyone walks the road")
	var rep := sim.route_report()
	check(rep.segments[0].known and not rep.segments[1].known and rep.segments[1].name == "Not walked yet", "the report shows the rest as not walked")
	check(sim.plan_bridge() != "" and sim.clear_cut() != "", "nothing to bridge or clear before anyone has seen it")
	until_at_site(sim, [p.ada, p.tomas])
	check(sim.route_surveyed() and rd.seen == 6, "the first trip reveals every segment")
	rep = sim.route_report()
	check(rep.segments[2].obstacle.begins_with("A stream") and rep.segments[4].obstacle.begins_with("A rocky cut: 3 boulders"), "the report names the stream and the cut: %s, %s" % [rep.segments[2].obstacle, rep.segments[4].obstacle])
	check(rep.cart < rep.walk and rep.segments.all(func(x): return x.len == 8), "with each segment's length, and a cart estimate quicker than walking")
	# Wading is slower than walking.
	var on_grass := walk_ticks(Vector2i(2, 1), Vector2i(10, 1))
	var wading := walk_ticks(Vector2i(17, 1), Vector2i(25, 1))
	check(wading > on_grass + Tuning.TPS / 2, "crossing the stream is slower than grass (%d ticks, against %d)" % [wading, on_grass])
	# The bridge: planks from the village, carried out and built by a village resident.
	var walk_before := sim.route_walk_time()
	check(sim.plan_bridge() == "" and sim.plan_bridge() != "", "Build the bridge places one blueprint")
	var mira := sim.add_resident("Mira", Sim.TRAVELERS[1][1], sim.route_sign() + Vector2i(-3, 0))
	sim.set_role(mira, "build")
	give_station(sim, mira)  # issue #184: a job needs its workstation
	mira.pick = {"type": "stone_pick", "tier": 2, "dur": 99}
	sim.drop_items(sim.route_sign() + Vector2i(-4, 2), "plank", 12)
	var labels: Array = []
	for i in 150 * Tuning.TPS:
		sim.step()
		if mira.job != null and not labels.has(mira.job.label):
			labels.append(mira.job.label)
		if sim.bridge().done:
			break
	check(sim.bridge().done and labels.has("Hauling planks to the bridge") and labels.has("Building the bridge"), "Mira carries the planks out and builds the bridge (%s)" % [labels])
	sim.use_map(Road.ID)
	check(sim.ground_speed(Vector2i(20, 3)) == 1.0 and sim.walkable(Vector2i(20, 3)), "the bridge takes away the wading, and is walked over")
	sim.use_map("village")
	check(sim.route_walk_time() < walk_before and rep.segments[2].obstacle != sim.route_report().segments[2].obstacle, "the walk is quicker, and the report says it's bridged")
	# The cut: its boulders on the line are marked, then mined from the village.
	check(sim.clear_cut() == "" and sim.cut_boulders().all(func(b): return b.des), "Clear the cut marks its boulders")
	for i in 150 * Tuning.TPS:
		sim.step()
		if sim.cut_boulders().is_empty():
			break
	check(sim.cut_boulders().is_empty() and sim.route_report().segments[4].obstacle == "Cleared", "Mira walks out and mines them")
	run(sim, 20)
	check(mira.map == "village", "then walks back to the village")
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(loaded.route_surveyed() and loaded.bridge().done and loaded.cut_boulders().is_empty(), "the survey, the bridge and the cleared cut are saved")


## Ticks a lone resident takes to walk between two road cells.
func walk_ticks(from: Vector2i, to: Vector2i) -> int:
	var sim := Sim.new_game()
	var r: Dictionary = sim.residents[0]
	sim.move_to_map(r, Road.ID, from)
	r.direct = sim._move_job(to)
	for i in 30 * Tuning.TPS:
		sim.step()
		if Sim.rcell(r) == to and r.pos == Vector2(to):
			return i
	return 9999


## Issue #120: rails and minecarts are crafted at the bench from iron, and hauled and counted.
func test_rails_and_minecarts() -> void:
	var rails := Defs.recipe("rails")
	var cart := Defs.recipe("minecart")
	check(rails.inp == {"iron_ingot": 6, "stick": 1} and rails.out == {"rail": 16}, "6 iron ingots and a stick make 16 rails")
	check(cart.inp == {"iron_ingot": 5} and cart.out == {"minecart": 1}, "5 iron ingots make a minecart")
	check(Sim.recipe_job(rails) == "craft" and Sim.recipe_job(cart) == "craft", "both are Craft work: nobody carries them as tools")
	check(Defs.ITEMS.rail.group == "building" and Defs.ITEMS.minecart.group == "building" and Defs.stack_cap("rail") == Tuning.STACK and Defs.stack_cap("minecart") == 1, "they're counted under Building; rails stack, a minecart has a cell to itself")
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var bench := sim.place_site("bench", open_rect(sim, Vector2i(3, 3)).position + Vector2i(1, 0))
	bench.stage = 1
	bench.done = true
	sim.drop_items(Sim.rcell(ada) + Vector2i(-1, 1), "iron_ingot", 11)
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 1), "stick", 1)
	sim.queue_add(bench, "rails")
	sim.queue_add(bench, "minecart")
	run(sim, 60)
	check(count(sim, "rail") == 16 and count(sim, "minecart") == 1 and count(sim, "iron_ingot") == 0, "Ada crafts 16 rails and a minecart (%d rails, %d carts)" % [count(sim, "rail"), count(sim, "minecart")])
	sim.paint_zone(open_rect(sim, Vector2i(3, 3)))
	run(sim, 60)
	var stored := sim.stacks_where(func(st): return st.type in ["rail", "minecart"] and sim.in_zone(st.cell))
	check(stored.size() == 2 and stored.any(func(st): return st.type == "rail" and st.n == 16) and stored.any(func(st): return st.type == "minecart" and st.n == 1), "both are hauled to the stockpile (%s)" % [stored.map(func(st): return "%d %s" % [st.n, st.type])])


## Issue #121: planning the line puts a track blueprint on each segment, shows its cost and the time it
## saves, waits on the bridge and the cut, is laid from the village end, and cancels cleanly.
func test_plan_the_line() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	built_board(sim)
	check(sim.plan_line_blocker().begins_with("Walk the road first") and sim.plan_line() != "", "the line can't be planned before the road is walked")
	sim.road().seen = Road.segment_count()
	var before := sim.line_cost()
	check(before.rails == 12 and before.ingots == 6 and before.saved > 10.0, "the preview: 12 rails, the 6 iron ingots to craft them, and %.0f s saved a round trip" % before.saved)
	check(sim.plan_line() == "", "once surveyed, the line can be planned")
	var tracks: Array = sim.road().sites.filter(func(st): return st.tpl == "track")
	check(tracks.size() == 6 and range(6).all(func(i): return tracks[i].seg == i and tracks[i].origin == Vector2i(Road.SEGMENTS[i].x, Road.LINE_ROW) and tracks[i].size == Vector2i(8, 1)), "one track blueprint per segment, along the line")
	check(sim.plan_line() == "The whole line is planned", "one line, planned once")
	check(sim.on_map(Road.ID, sim.walkable.bind(Vector2i(5, Road.LINE_ROW))), "blueprints don't block the road")
	check(sim.next_track() == 0 and sim.track_blocker(2) == "Needs the bridge" and sim.track_blocker(4) == "Needs the cut cleared" and sim.track_blocker(0) == "", "the stream and the cut block their segments")
	# Rails in the village are carried out and laid from the village end, up to the stream.
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 1), "rail", 6)
	for i in 120 * Tuning.TPS:
		sim.step()
		if sim.track_state(1) == "built":
			break
	check(sim.track_state(0) == "built" and sim.track_state(1) == "built", "Ada lays the first two segments")
	run(sim, 20)
	check(sim.track_state(2) == "planned" and tracks[2].store.is_empty(), "the stream's segment waits for the bridge")
	sim.compute_stuck()
	check(sim.stuck.any(func(x): return x.why == "Track: needs the bridge first" and x.focus_id == tracks[2].id), "and says so: %s" % stuck_text(sim))
	check(sim.line_cost().rails == 8, "the preview counts only what's still to lay (%d)" % sim.line_cost().rails)
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(loaded.track_state(1) == "built" and loaded.track_state(2) == "planned" and loaded.track_site(3).seg == 3, "the planned line is saved")
	# Cancelling a segment sets down the rails delivered to it.
	tracks[3].store = {"rail": 1}
	sim.cancel_site(tracks[3])
	var back: int = sim.on_map(Road.ID, func(): return sim.items.values().filter(func(st): return st.type == "rail").reduce(func(a, st): return a + st.n, 0))
	check(sim.track_state(3) == "none" and back >= 1, "cancelling a segment returns its rails as a stack (%d)" % back)
	check(sim.plan_line() == "" and sim.track_state(3) == "planned", "and planning again fills the gap")



## A road ready for the cart: walked, bridged, the cut cleared, both stations built and the cart parked
## at the village station, with track laid on the segments in `built`.
func ready_line(sim: Sim, built: Array) -> void:
	var rd := sim.road()
	rd.known = true
	rd.seen = Road.segment_count()
	sim.plan_bridge()
	sim.bridge().stage = 1
	sim.bridge().done = true
	for b in sim.cut_boulders():
		b.alive = false
	rd.occ_dirty = true
	for end in ["village", "mine"]:
		sim.plan_station(end)
		sim.station(end).stage = 1
		sim.station(end).done = true
	sim.plan_line()
	for i in built:
		var t := sim.track_site(i)
		t.stage = 1
		t.done = true
		t.laid = Tuning.RAILS_PER_SEGMENT
	sim.cart = {"at": "village", "x": Sim.station_x("village"), "state": "parked", "load": {}, "riders": [], "acc": 0.0}
	sim.rev += 1


## Issue #122: rails go out to a railhead pile, then to the segment being laid, which fills in rail by
## rail; the crew's stuck reasons say what's missing.
func test_track_crew_and_railhead() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	built_board(sim)
	var rd := sim.road()
	rd.seen = Road.segment_count()
	sim.plan_bridge()
	sim.bridge().stage = 1
	sim.bridge().done = true
	for b in sim.cut_boulders():
		b.alive = false
	rd.occ_dirty = true
	sim.plan_line()
	sim.compute_stuck()
	check(sim.stuck.any(func(x): return x.why == "Track: needs 12 more rails"), "with no rails, the track says how many it needs: %s" % stuck_text(sim))
	ada.away = true
	sim.compute_stuck()
	check(sim.stuck.any(func(x): return x.why == "Track: no one is a builder"), "and, with Ada away and no builder, that nobody lays track")
	ada.away = false
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 1), "rail", 12)
	var labels: Array = []
	var half := false
	var at_railhead := false
	for i in 500 * Tuning.TPS:
		sim.step()
		if ada.job != null and not labels.has(ada.job.label):
			labels.append(ada.job.label)
		if sim.track_site(0).get("laid", 0) == 1 and not sim.track_site(0).done:
			half = true
		if sim.railhead_rails() > 0:
			at_railhead = true
		if sim.line_complete():
			break
	check(labels.has("Carrying rails to the railhead") and labels.has("Hauling rails to the track") and labels.has("Laying track"), "Ada carries rails to the railhead, then to the track, and lays it (%s)" % [labels])
	check(at_railhead, "the rails pile up at the railhead on the road's village end")
	check(half, "a segment fills in rail by rail")
	check(sim.line_complete() and sim.railhead_rails() == 0, "the whole line is laid, using all 12 rails")
	check(sim.stuck.all(func(x): return not x.why.begins_with("Track")), "and the track's reasons are gone")
	# Progress and the railhead pile survive a save.
	var sim2 := Sim.new_game()
	built_board(sim2)
	sim2.road().seen = Road.segment_count()
	sim2.plan_line()
	sim2.track_site(0).store = {"rail": 1}
	sim2.track_site(0).laid = 1
	sim2.on_map(Road.ID, sim2.drop_items.bind(Road.RAILHEAD, "rail", 5))
	var loaded := Sim.from_state(str_to_var(var_to_str(sim2.save_state())))
	check(loaded.track_site(0).laid == 1 and loaded.track_site(0).store.rail == 1 and loaded.railhead_rails() == 5, "a half-laid segment and the railhead pile are saved")


## Issue #123: a station at each end, built from the village; a minecart hauled out and parked at the
## village station; the cart adds its room to the packs once the line is complete.
func test_stations_and_the_cart() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	built_board(sim)
	check(sim.plan_station("mine") == "Nobody has walked that far yet" and sim.plan_station("village") == "", "the village station can go down before the road is walked, the mine's can't")
	sim.road().seen = Road.segment_count()
	check(sim.plan_station("mine") == "" and sim.plan_station("mine") != "", "one station at each end")
	var vs := sim.station("village")
	check(vs.size == Vector2i(3, 1) and vs.plot == Rect2i(Road.STATIONS.village, Vector2i(3, 3)), "a 1×3 platform, with room kept for a loading station")
	check(sim.on_map(Road.ID, sim.walkable.bind(Road.STATIONS.village)), "the platform is walked on")
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 1), "plank", 12)
	sim.drop_items(Sim.rcell(ada) + Vector2i(-1, 1), "cobble", 8)
	for i in 300 * Tuning.TPS:
		sim.step()
		if vs.done and sim.station("mine").done:
			break
	check(vs.done and sim.station("mine").done, "Ada carries the materials out and builds both stations")
	# The minecart is hauled out and parked.
	ada.hunger = 100.0  # no food in a new game: keep her from starving
	sim.drop_items(sim.route_sign() + Vector2i(-3, 2), "minecart", 1)  # Ada may be out on the road
	var docked := false
	for i in 120 * Tuning.TPS:
		sim.step()
		if not sim.cart.is_empty():
			docked = true
			break
	check(docked and sim.cart.at == "village" and sim.cart.state == "parked" and count(sim, "minecart") == 0, "the minecart is hauled out and parked at the village station")
	check(not sim.cart_ready(), "it can't be ridden while the cut blocks the line")
	for b in sim.cut_boulders():
		b.alive = false
	sim.road().occ_dirty = true
	check(sim.cart_ready() and not sim.cart_adds_room(), "with the cut clear it's ready, but adds no room until the line is laid")
	sim.plan_line()
	for i in Road.segment_count():
		sim.track_site(i).stage = 1
		sim.track_site(i).done = true
	var plan := sim.new_plan()
	plan.party = [ada.id]
	check(plan.cart_cap and Sim.pack_capacity(plan) == Tuning.PACK_CAPACITY + Tuning.CART_CAPACITY, "with the line complete, the cart's room is added to the packs (%d)" % Sim.pack_capacity(plan))
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(loaded.cart.at == "village" and loaded.station("mine").done, "the stations and the parked cart are saved")


## Issue #124: the party and its cargo ride the line both ways; a partial line is between riding and
## walking; mining at the site is no faster; the cargo comes off at the village station.
func test_ride_the_line() -> void:
	var times := {}
	var mining := {}
	for kind in ["walk", "partial", "full"]:
		var sim := Sim.new_game()
		sim.paint_zone(open_rect(sim, Vector2i(4, 3)))
		if kind != "walk":
			ready_line(sim, [0, 1, 2] if kind == "partial" else range(Road.segment_count()))
		else:
			sim.road().seen = Road.segment_count()
		var p := send_party(sim)
		until_at_site(sim, [p.ada, p.tomas], 60)
		var ex: Dictionary = sim.expedition
		times[kind] = float(ex.road_out[1] - ex.road_out[0]) / Tuning.TPS
		check(ex.cart == (kind != "walk"), "%s: the party rides only when there's a cart" % kind)
		# Mining at the site: the time from arriving to the first 2 coal packed.
		var start := sim.tick
		for i in 120 * Tuning.TPS:
			sim.step()
			if sim.expedition.cargo.get("coal", 0) >= 2:
				break
		mining[kind] = sim.tick - start
		if kind == "full":
			var mid := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
			check(sim.call_home() == "", "call the party home")
			var rode := false
			var saved_mid := false
			var unloading := false
			for i in 90 * Tuning.TPS:
				sim.step()
				if sim.cart.state == "moving" and not sim.cart.riders.is_empty():
					rode = true
					if not saved_mid:
						saved_mid = true
						mid = Sim.from_state(str_to_var(var_to_str(sim.save_state())))
				if sim.cart.state == "unloading":
					unloading = true
				if sim.expedition.is_empty():
					break
			check(rode and sim.expedition.is_empty(), "they ride home too")
			check(unloading and sim.cart.at == "village" and sim.cart.load.is_empty(), "the cart is unloaded at the village station")
			check(p.board.report.any(func(x): return x.begins_with("By cart:")), "the report gives the time on the road and the time saved: %s" % [p.board.report])
			run(sim, 60)
			check(sim.road().items.values().filter(func(st): return st.type == "coal").is_empty() and count(sim, "coal") >= 2, "the coal is hauled from the platform to the stockpile")
			run(mid, 90)
			check(mid.expedition.is_empty() and mid.residents[0].map == "village", "a game saved mid-ride gets home too")
	check(times.full < times.partial and times.partial < times.walk, "riding beats walking, and a partial line is in between (%.1f s, %.1f s, %.1f s)" % [times.full, times.partial, times.walk])
	check(absi(mining.walk - mining.full) <= 2 and absi(mining.walk - mining.partial) <= 2, "mining at the site takes the same with or without the line (%s)" % [mining])


# ---------------------------------------------------------------- the old mine's deeper levels (issue #132)

## Issue #132: every level has its door at the far end and a minable way to it, plus some ore; deeper
## levels come from the seed, each from a pattern family the mine hasn't used yet, never the same
## family twice in a row; deeper is richer and riskier.
func test_mine_levels_are_generated() -> void:
	var sim := Sim.new_game()
	var top := sim.get_map(OldMine.ID)
	check(top.level == 1 and top.pattern == "workings" and top.door == Vector2i(15, 8) and top.door_state == "closed", "Level 1 is the old workings, with its door at the far end")
	check(MineLevels.minable_path(top) and not sim.on_map(OldMine.ID, sim.walkable.bind(MineLevels.door_front(top))), "a minable way runs to it, with a block of stone in front of the door")
	var all_ok := true
	var ore_ok := true
	for seed in 25:
		sim.seed = seed
		for n in range(2, 10):
			var lv := MineLevels.build(sim, n)
			all_ok = all_ok and lv.entrance.x == 0 and lv.door.x == lv.w - 1 and MineLevels.minable_path(lv)
			ore_ok = ore_ok and lv.boulders.any(func(b): return b.get("ore", "") == "coal") and lv.boulders.any(func(b): return b.get("ore", "") == "iron")
	check(all_ok, "every generated level has the entrance on the west edge, the door on the east, and a minable way between")
	check(ore_ok, "and some coal and iron")
	sim.seed = Tuning.SEED
	var a := MineLevels.layout(sim.seed, 2)
	check(a == MineLevels.layout(sim.seed, 2) and a != MineLevels.layout(sim.seed + 1, 2), "a level comes out the same from the same seed, and differently from another")
	var fams: Array = range(2, 7).map(func(n): return MineLevels.family(sim.seed, n))
	var distinct := {}
	for f in fams:
		distinct[f] = true
	check(distinct.size() == 5, "the first five levels down each use a different pattern family (%s)" % [fams])
	var repeats := false
	for n in range(3, 30):
		repeats = repeats or MineLevels.family(sim.seed, n) == MineLevels.family(sim.seed, n - 1)
	check(not repeats, "no two levels in a row share a family")
	var back := MineLevels.family(sim.seed, 7)
	var first: int = fams.find(back) + 2
	check(MineLevels.layout(sim.seed, 7).rows != MineLevels.layout(sim.seed, first).rows, "a family that comes back (%s, on levels %d and 7) looks different" % [back, first])
	var two := MineLevels.build(sim, 2)
	var ores := func(mp: SimMap, ore: String) -> int: return mp.boulders.filter(func(b): return b.get("ore", "") == ore).size()
	check(ores.call(two, "coal") > ores.call(top, "coal") and ores.call(two, "iron") > ores.call(top, "iron"), "Level 2 has more coal and iron than Level 1 (%d/%d against %d/%d)" % [ores.call(two, "coal"), ores.call(two, "iron"), ores.call(top, "coal"), ores.call(top, "iron")])
	check(Sim.cave_in_chance(2) > Sim.cave_in_chance(1) and Sim.fall_chance(2) > Sim.fall_chance(1) and two.torches.size() < top.torches.size() + 1, "and higher cave-in and fall chances, and no more torches")
	check(two.name == "Old mine, level 2" and two.kind == "site" and not two.known and two.found and two.discovered, "Level 2 is a site map named for its level, its ore all in plain sight")


## Issue #132: the party mines its way to the door, the game stops for a choice, the door opens onto
## Level 2 (made the same way from the seed), the party works it and brings its cargo home up through
## Level 1; two levels save and load; the other choices head home or carry on.
func test_the_door_down_and_back() -> void:
	var sims := {}
	for choice in ["down", "later", "keep"]:
		var sim := Sim.new_game()
		var zone := open_rect(sim, Vector2i(4, 3))
		sim.paint_zone(zone)
		var p := send_party(sim)
		until_at_site(sim, [p.ada, p.tomas])
		sim.expedition.policy = {"target": false, "full": false, "low": false}
		check(sim.dig_to_door(OldMine.ID) == "" and sim.get_map(OldMine.ID).boulders.any(func(b): return b.cell == Vector2i(14, 8) and b.des), "%s: Dig to the door marks the stone in front of it" % choice)
		for i in 200 * Tuning.TPS:
			sim.step()
			if not sim.pending.is_empty():
				break
		var mine := sim.get_map(OldMine.ID)
		check(sim.pending.size() == 1 and sim.pending[0].kind == "door" and mine.door_state == "found", "%s: reaching the door stops the game for a choice" % choice)
		if sim.pending.is_empty():
			return
		check(sim.pending[0].options.map(func(o): return o.id) == ["down", "later", "keep"] and sim.pending[0].options.all(func(o): return o.cost != ""), "Go down now, Mark it for later or Keep mining here, each with its cost")
		var two_id := MineLevels.level_id(2)
		check(sim.maps.has(two_id) and not sim.get_map(two_id).known, "the level below is ready, not yet on the map switcher")
		sim.choose(choice)
		sims[choice] = [sim, p]
	# Mark it for later: home now, the door remembered. Keep mining: the party stays.
	var later: Sim = sims.later[0]
	check(later.expedition.leg == "home" and later.get_map(OldMine.ID).door_state == "found", "Mark it for later: the party heads home and the door stays marked")
	var keep: Sim = sims.keep[0]
	check(keep.expedition.leg == "out" and keep.expedition.dest == OldMine.ID, "Keep mining here: the party carries on with Level 1")
	# Go down now: the door opens and the party works Level 2.
	var sim: Sim = sims.down[0]
	var ada: Dictionary = sims.down[1].ada
	var tomas: Dictionary = sims.down[1].tomas
	var two_id := MineLevels.level_id(2)
	var two := sim.get_map(two_id)
	check(sim.get_map(OldMine.ID).door_state == "open" and two.known and sim.expedition.dest == two_id, "Go down now: the door opens, Level 2 is on the switcher and the party is bound for it")
	var fresh := Sim.new_game()
	fresh.open_door(OldMine.ID)
	var same := fresh.get_map(two_id).boulders.map(func(b): return b.cell) == two.boulders.map(func(b): return b.cell) and fresh.get_map(two_id).rock == two.rock
	check(same and two.pattern == MineLevels.family(sim.seed, 2), "Level 2 is made from the seed: the same in any game with that seed")
	until_at_site(sim, [ada, tomas], 60)
	check(ada.map == two_id and tomas.map == two_id and sim.at_site(ada) and two.visited, "the party walks down through the door into Level 2")
	check(Sim.rcell(ada).x <= 3, "in at its entrance")
	sim.expedition.policy = {"target": true, "full": true, "low": false}
	sim.aim_plan(sim.expedition, "coal", sim.objective_packed() + 6)  # 6 more, from Level 2
	run(sim, 5)
	var mid := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(mid.maps.has(two_id) and mid.get_map(two_id).pattern == two.pattern and mid.get_map(two_id).level == 2 and mid.residents[0].map == two_id, "saving with two levels keeps both, and the party down on Level 2")
	check(mid.get_map(OldMine.ID).door_state == "open" and mid.seed == sim.seed, "with the door open and the seed")
	check(sim.site_report(two_id).levels.size() == 2 and sim.site_report(two_id).levels[1].pattern == MineLevels.FAMILY_NAMES[two.pattern], "the site report lists both levels, with Level 2's pattern")
	var went_up := false
	for i in 400 * Tuning.TPS:
		sim.step()
		went_up = went_up or (sim.expedition.get("leg", "") == "home" and ada.map == OldMine.ID)
		if sim.expedition.is_empty():
			break
	check(went_up and sim.expedition.is_empty() and ada.map == "village", "the party heads home up through Level 1 and the road")
	var b: Dictionary = sims.down[1].board
	check(b.report[0].begins_with("Back from the old mine, level 2: ") and "coal" in b.report[0], "the report says what came back from Level 2: %s" % [b.report])
	run(sim, 120)
	check(count(sim, "coal") >= 6 and sim.stacks_where(func(st): return st.type == "coal" and sim.in_zone(st.cell)).size() > 0, "Level 2's coal reaches the village, and is hauled to the stockpile (%d)" % count(sim, "coal"))
	# Planning a trip straight to Level 2: its walk includes Level 1's.
	var plan := sim.new_plan(two_id)
	check(sim.site_report(two_id).travel > sim.site_report(OldMine.ID).travel and sim.plan_targets(two_id).any(func(x): return x.item == "iron_ore"), "Level 2 can be planned: a longer walk, and iron in plain sight")
	check(plan.dest == two_id and plan.party.size() == 1, "a plan for Level 2")


# ---------------------------------------------------------------- the meadow adventure (Slice 3.5)

## Issue #138: cows and pigs are hunted like sheep, each dropping its own items; Hunt can mark one kind
## only; beef and porkchops cook at the fireplace and are meals; raw meat is eaten only in a pinch; an
## old save's sheep are sheep.
func test_cows_and_pigs() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	for sh in sim.sheep:
		sh.alive = false
	var spot := open_rect(sim, Vector2i(4, 3))
	var cow := sim.add_animal(spot.position, "cow")
	var pig := sim.add_animal(spot.position + Vector2i(3, 2), "pig")
	check(cow.kind == "animal" and cow.species == "cow" and pig.species == "pig", "cows and pigs are animals of their species")
	sim.designate_hunt(Rect2i(0, 0, sim.w, sim.h), null, "pig")
	check(pig.des and not cow.des, "Hunt can mark one kind only")
	sim.designate_hunt(Rect2i(0, 0, sim.w, sim.h))
	check(cow.des and pig.des, "and every kind at once")
	sim.queue_order(ada, cow)
	check(Sim.order_text(ada.orders[0]) == "Hunt a cow", "a queued hunt names the animal")
	ada.orders.clear()
	run(sim, 120)
	check(not cow.alive and not pig.alive, "Ada hunts both")
	check(count(sim, "leather") == 1 and count(sim, "beef") == 2, "a cow drops 1 leather and 2 raw beef")
	check(count(sim, "porkchop") == 2, "a pig drops 2 raw porkchops")
	check(Defs.drops_text("cow") == "1 leather and 2 raw beef" and Defs.drops_text("pig") == "2 raw porkchops", "their drops read in the player's words")
	# Cooking: beef and porkchops cook with a log each, and count as meals.
	var sim2 := Sim.new_game()
	var a2: Dictionary = sim2.residents[0]
	var spot2 := open_rect(sim2, Vector2i(3, 3))
	lit_fireplace(sim2, spot2.position + Vector2i(1, 0))
	var near := spot2.position + Vector2i(1, 3)
	sim2.drop_items(near, "beef", 1)
	sim2.drop_items(near + Vector2i(1, 0), "porkchop", 1)
	sim2.drop_items(near + Vector2i(-1, 0), "log", 2)
	var labels: Array = []
	for i in 60 * Tuning.TPS:
		sim2.step()
		if a2.job != null and not labels.has(a2.job.label):
			labels.append(a2.job.label)
	check(labels.has("Cooking beef") and labels.has("Cooking a porkchop"), "the fireplace's standing order cooks them (%s)" % [labels])
	check(count(sim2, "cooked_beef") == 1 and count(sim2, "cooked_porkchop") == 1 and count(sim2, "log") == 0, "a log each")
	check(Defs.MEALS.has("cooked_beef") and Defs.MEALS.has("cooked_porkchop"), "both are meals")
	a2.hunger = 30.0
	var before := count(sim2, "cooked_beef") + count(sim2, "cooked_porkchop")
	run(sim2, 15)
	check(count(sim2, "cooked_beef") + count(sim2, "cooked_porkchop") == before - 1 and a2.hunger > 30.0 + Tuning.FOOD_VALUE.cooked_beef - 10.0, "and a hungry resident eats one (%.0f)" % a2.hunger)
	# Raw beef and porkchops wait for the fireplace while there are berries.
	var sim3 := Sim.new_game()
	var a3: Dictionary = sim3.residents[0]
	sim3.drop_items(Sim.rcell(a3) + Vector2i(1, 0), "beef", 1)
	sim3.drop_items(Sim.rcell(a3) + Vector2i(-1, 0), "porkchop", 1)
	a3.hunger = 35.0
	run(sim3, 20)
	check(count(sim3, "beef") == 1 and count(sim3, "porkchop") == 1 and a3.hunger > 50.0, "raw beef and porkchops are left for cooking while there are berries")
	# An old save's sheep are sheep.
	var old := SaveFormat.read("res://tests/fixtures/save_v19.save")
	var loaded := Sim.from_state(old.data.state)
	var animals: Array = loaded.maps.village.sheep
	check(not animals.is_empty() and animals.all(func(x): return x.kind == "animal" and x.species == "sheep"), "an old save's animals come back as sheep (%d)" % animals.size())


## Packs and sends a party (Ada, and Tomas unless `solo`) to `dest` with `meals` meals, for `target`.
func send_party_to(sim: Sim, dest: String, target: Dictionary, meals := 4, solo := false) -> Dictionary:
	var ada: Dictionary = sim.residents[0]
	var tomas := {} if solo else sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Sim.rcell(ada) + Vector2i(1, 0))
	var b := built_board(sim)
	var plan := sim.new_plan(dest)
	plan.party = [ada.id] if solo else [ada.id, tomas.id]
	plan.meals = meals
	if target.item == "pens":
		plan.target = target
	else:
		sim.aim_plan(plan, target.item, target.n)
	var err := sim.plan_expedition(plan)
	b.store = {"bread": meals}
	for i in 30 * Tuning.TPS:
		sim.step()
		if sim.depart_blocker() == "":
			break
	err += sim.depart()
	return {"ada": ada, "tomas": tomas, "board": b, "err": err}


## Issue #136: the expedition board lists every known destination, from data, each with its travel time,
## what's there, its hazards and its status; a signpost leads to each; while a party is out, planning is
## locked and every row says where they are.
func test_adventures_list() -> void:
	var sim := Sim.new_game()
	check(sim.adventures().is_empty(), "with no board, nobody knows of anywhere to go")
	check(sim.sign_for(Meadow.ID) == sim.meadow_sign() and sim.meadow_sign().x == 0 and sim.sign_for(OldMine.ID) == sim.route_sign() and sim.route_sign().x == sim.w - 1, "a signpost per destination, on the matching edge: the meadow west, the mine east")
	var b := built_board(sim)
	var rows := sim.adventures()
	check(rows.map(func(a): return a.id) == [OldMine.ID, Meadow.ID] and sim.get_map(Meadow.ID).known, "the board lists the old mine and the meadow")
	check(rows.all(func(a): return a.status == "Not yet visited" and not a.locked and a.hazards.is_empty()), "neither visited yet, no hazards known")
	check(rows[1].travel == Tuning.MEADOW_WALK and rows[0].travel == -1.0 and rows[1].what == "Sheep, cows and pigs, they say", "the meadow's walk and what's said of it; the road isn't walked yet")
	var plan := sim.new_plan(Meadow.ID)
	check(plan.dest == Meadow.ID and plan.target.item == "wool" and plan.picks == 0, "a plan for the meadow brings back wool and packs no pickaxes")
	check(sim.plan_targets(Meadow.ID).map(func(x): return x.item) == ["wool", "mutton", "leather", "beef", "porkchop"], "it can bring back wool, leather or meat")
	sim.residents[0].pick = null
	plan.party = [sim.residents[0].id]
	plan.meals = 2
	sim.plan_expedition(plan)
	rows = sim.adventures()
	check(rows[1].status == "Packing to go" and rows[1].here and rows[0].locked and rows[0].status == "Locked: packing for the meadow", "while packing, the meadow's row says so and the mine's is locked")
	check(sim.plan_problems(sim.new_plan(OldMine.ID)).has("An Overworld party is already out"), "planning is locked")
	b.store = {"bread": 2}
	for i in 30 * Tuning.TPS:
		sim.step()
		if sim.depart_blocker() == "":
			break
	check(sim.depart() == "", "the party departs for the meadow")
	var ada: Dictionary = sim.residents[0]
	until_away(sim, ada, 60)
	check(ada.away and ada.trip == Meadow.ID and Sim.manhattan(Sim.rcell(ada), sim.meadow_sign()) <= 1, "Ada leaves by the meadow's signpost, off the west edge")
	check(sim.adventures()[1].status == "Party on the way" and sim.adventures()[0].status == "Locked: the party is at the meadow", "every row says where the party is")
	run(sim, Tuning.MEADOW_WALK + 2)
	check(ada.map == Meadow.ID and sim.adventures()[1].status == "Party there now", "and once she's there, the meadow's row says so")
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(loaded.get_map(Meadow.ID).known and loaded.get_map(Meadow.ID).visited and not loaded.get_map(OldMine.ID).visited, "known destinations and visited flags are saved")
	check(loaded.adventures()[1].what.begins_with("Cows, pigs, sheep · "), "a visited meadow's row counts its animals: %s" % loaded.adventures()[1].what)


## Issue #137: the meadow is an expedition site with its own map: herds of sheep, cows and pigs, a pond,
## trees and fences. A party walks there past the west signpost, hunts what's marked for its objective,
## packs the drops and brings home a full load; each species grows back on its own; its hazards are mild.
func test_meadow_expedition() -> void:
	var sim := Sim.new_game()
	var mp := sim.get_map(Meadow.ID)
	check(mp.w == 24 and mp.h == 24 and mp.kind == "site" and mp.name == "Meadow", "the meadow is a 24×24 site map")
	check(sim.herds() == Meadow.herd() and Meadow.herd().has("cow") and Meadow.herd().has("pig") and Meadow.herd().has("sheep"), "herds of sheep, cows and pigs (%s)" % [sim.herds()])
	check(not mp.water.is_empty() and not sim.on_map(Meadow.ID, sim.walkable.bind(mp.water.keys()[0])), "the pond is walked around, not through")
	check(not mp.fences.is_empty() and not sim.on_map(Meadow.ID, sim.walkable.bind(mp.fences.keys()[0])) and not mp.banks.is_empty(), "with fences, and a muddy bank around the pond")
	check(mp.entrance.x == mp.w - 1 and not mp.trees.is_empty(), "the party arrives on the east edge, the village's side; there are trees")
	var p := send_party_to(sim, Meadow.ID, {"item": "beef", "n": 12}, 2, true)
	var ada: Dictionary = p.ada
	check(p.err == "", "Ada is packed and sent off for 12 beef: %s" % p.err)
	sim.expedition.policy = {"target": true, "full": true, "low": false}
	until_away(sim, ada, 60)
	check(ada.away and absf(sim.back_in(ada) - Tuning.MEADOW_WALK) < 0.5, "the walk to the meadow takes %d s" % int(Tuning.MEADOW_WALK))
	until_at_site(sim, [ada], Tuning.MEADOW_WALK + 5)
	check(sim.at_site(ada) and ada.map == Meadow.ID and Sim.rcell(ada) == mp.entrance, "she arrives at the meadow's entrance")
	var hunted_cows := false
	var hurt := 0
	var home := false
	for i in 600 * Tuning.TPS:
		sim.step()
		hunted_cows = hunted_cows or mp.sheep.any(func(a): return a.species == "cow" and not a.alive)
		hurt = maxi(hurt, ada.hurt)
		if sim.expedition.is_empty():
			home = true
			break
	check(hunted_cows and mp.sheep.all(func(a): return a.species == "cow" or a.alive), "the party hunts the cows for the beef, and leaves the rest")
	check(hurt <= 1 and sim.pending.is_empty(), "the meadow's hazards are mild: never a serious injury, never a stop")
	check(home and ada.map == "village" and Sim.manhattan(Sim.rcell(ada), sim.meadow_sign()) <= 2, "she comes home by the meadow's signpost")
	var b: Dictionary = p.board
	check(b.report[0].begins_with("Back from the meadow: ") and "beef" in b.report[0] and "leather" in b.report[0], "with beef and leather: %s" % [b.report])
	var cargo := 0
	for st in sim.stacks_where(func(st): return st.get("cargo", false)):
		cargo += st.n
	check(cargo >= Tuning.PACK_CAPACITY - 2, "a full pack's worth, far more than the old trip's 2 wool and 2 mutton (%d)" % cargo)
	# Each species grows back on its own, up to its herd.
	var pigs: Array = mp.sheep.filter(func(a): return a.species == "pig")
	for a in pigs:
		a.alive = false
	run(sim, Tuning.MEADOW_REGROW.pig + 1)
	check(sim.herds().get("pig", 0) == 1, "the pigs come back one at a time (%d after %d s)" % [sim.herds().get("pig", 0), int(Tuning.MEADOW_REGROW.pig)])
	run(sim, Tuning.MEADOW_REGROW.pig * (Meadow.herd().pig + 2))
	check(sim.herds().pig == Meadow.herd().pig and sim.herds().sheep == Meadow.herd().sheep, "up to their herd, and no more")
	run(sim, Tuning.MEADOW_REGROW.cow * Meadow.herd().cow)  # however many the party took
	check(sim.herds().get("cow", 0) == Meadow.herd().cow, "the cows grew back too, at their own pace (%d of %d)" % [sim.herds().get("cow", 0), Meadow.herd().cow])
	# The hazards: an angry bull and the pond bank, which hurt, but never seriously.
	sim.on_map(Meadow.ID, func():
		var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], mp.banks[0] + Vector2i(1, 0))
		tomas.map = Meadow.ID
		for i in 400:
			sim._ledge_step(tomas, mp.banks[0])
		check(tomas.hurt == 1, "slipping on the pond bank hurts, but never seriously"))
	check(sim.site_report(Meadow.ID).hazards.size() == 2 and sim.site_report(Meadow.ID).hazards[0].contains("bull"), "the site report lists the bull and the bank")


## Issue #137: someone away on Slice 2's timed meadow trip in an old save comes home, with what they'd
## have brought back; the old meadow's sheep carry over to the meadow map.
func test_old_meadow_trips_come_home() -> void:
	var r := SaveFormat.read("res://tests/fixtures/save_v19.save")
	var raw: Dictionary = str_to_var(FileAccess.get_file_as_string("res://tests/fixtures/save_v19.save"))
	var tomas: Dictionary = raw.state.residents[1]
	tomas.away = true
	tomas.trip = "meadow"
	tomas.back_at = raw.state.tick + 40 * Tuning.TPS
	tomas.arriving = false
	raw.state.meadow_sheep = 5
	var up := SaveFormat.upgrade(raw)
	check(not up.has("error"), "an old save with someone away at the meadow upgrades")
	var sim := Sim.from_state(up.data.state)
	var t: Dictionary = sim.residents[1]
	check(not t.away and t.trip == "" and t.map == "village" and Sim.manhattan(Sim.rcell(t), sim.meadow_sign()) <= 1, "Tomas is home at the meadow signpost")
	var wool := sim.stacks_where(func(st): return st.type == "wool" and Sim.manhattan(st.cell, sim.meadow_sign()) <= 4)
	var mutton := sim.stacks_where(func(st): return st.type == "mutton" and Sim.manhattan(st.cell, sim.meadow_sign()) <= 4)
	check(not wool.is_empty() and wool[0].n == SaveFormat.OLD_MEADOW_TAKE and not mutton.is_empty() and mutton[0].n == SaveFormat.OLD_MEADOW_TAKE, "with the 2 wool and 2 raw mutton he'd have brought back")
	check(sim.herds().get("sheep", 0) == 5 - SaveFormat.OLD_MEADOW_TAKE, "the meadow map keeps the old meadow's sheep, less his (%d)" % sim.herds().get("sheep", 0))
	check(not r.has("error"), "the plain v19 fixture still reads")


## Issue #139: a pen is painted at the meadow and built by the party with packed sticks; marked
## animals are led in; a pair fed wheat has a young one, which grows up and can't be hunted till
## then; tending the pens hunts only what's over the herd size kept. Pens are saved.
func test_pens_and_breeding() -> void:
	var sim := Sim.new_game()
	var mp := sim.get_map(Meadow.ID)
	var rect := Rect2i(16, 16, 6, 5)
	sim.on_map(Meadow.ID, func():
		check(sim.pen_check(Rect2i(16, 16, 3, 5)) != "" and sim.pen_check(Rect2i(14, 14, 9, 9)) != "", "a pen is %d×%d to %d×%d" % [Tuning.PEN_MIN, Tuning.PEN_MIN, Tuning.PEN_MAX, Tuning.PEN_MAX])
		check(sim.pen_check(Rect2i(5, 7, 5, 5)) != "", "not on the pond")
		check(sim.paint_pen(rect) == "", "a 6×5 pen is painted on open grass")
		check(sim.pen_check(Rect2i(18, 18, 4, 4)) != "", "pens can't overlap"))
	check(sim.pen_check(rect) == "Pens go at the meadow", "and only at the meadow")
	var pen: Dictionary = mp.pens[0]
	check(pen.gate == Vector2i(21, 18) and Sim.pen_room(pen) == 12 and not Sim.pen_done(pen), "its gate faces the entrance, with room for 12 inside")
	check(sim.fence_left() == 18 * Tuning.FENCE_STICKS, "its 18 fences need %d sticks" % sim.fence_left())
	var cows: Array = mp.sheep.filter(func(a): return a.species == "cow").slice(0, 2)
	sim.on_map(Meadow.ID, func():
		for a in cows:
			sim.designate_lead(Rect2i(a.cell, Vector2i.ONE), a))
	check(cows.all(func(a): return a.lead and not a.des), "two cows are marked to lead into a pen")
	# The party packs sticks and wheat, builds the pen, leads the cows in and feeds them.
	var ada: Dictionary = sim.residents[0]
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Sim.rcell(ada) + Vector2i(1, 0))
	var b := built_board(sim)
	var plan := sim.new_plan(Meadow.ID)
	check(plan.sticks == 18 and plan.wheat == 0, "a meadow plan packs the sticks the pens need (%d)" % plan.sticks)
	plan.party = [ada.id, tomas.id]
	plan.meals = 4
	plan.wheat = 4
	plan.target = {"item": "pens", "n": 2}
	check(sim.plan_problems(plan).is_empty(), "tending the pens needs no cargo room: %s" % [sim.plan_problems(plan)])
	check(sim.plan_expedition(plan) == "", "the plan is confirmed")
	sim.drop_items(Sim.rcell(ada) + Vector2i(0, 2), "stick", 18)
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 2), "wheat", 4)
	b.store = {"bread": 4}
	for i in 90 * Tuning.TPS:
		sim.step()
		if sim.depart_blocker() == "":
			break
	check(sim.packed().sticks == 18 and sim.packed().wheat == 4, "the sticks and wheat are packed at the board (%s)" % [sim.packed()])
	check(sim.depart() == "", "the party departs")
	check(sim.expedition.provisions == {"bread": 4} and sim.expedition.supplies == {"stick": 18, "wheat": 4}, "meals are provisions; sticks and wheat are supplies (%s)" % [sim.expedition.supplies])
	until_at_site(sim, [ada, tomas], Tuning.MEADOW_WALK + 40)
	var fed_at := -1
	var why := ""
	var saved := {}
	for i in 600 * Tuning.TPS:
		sim.step()
		if fed_at < 0 and cows.all(func(a): return a.get("fed_at", -1) >= 0):
			fed_at = sim.tick
			saved = sim.save_state()
		if sim.expedition.get("leg", "") == "home":
			why = sim.expedition.home_why
			break
	check(Sim.pen_done(pen) and mp.gates.has(pen.gate) and mp.fences.has(Vector2i(16, 16)), "the pen is built: fences round it, a gate in front")
	check(not sim.on_map(Meadow.ID, sim.walkable.bind(Vector2i(16, 16))) and sim.on_map(Meadow.ID, sim.walkable.bind(pen.gate)), "people walk through the gate, not the fences")
	check(cows.all(func(a): return a.get("pen", 0) == pen.id and Sim.pen_inside(pen).has_point(a.cell)), "both cows are led into the pen")
	check(fed_at > 0 and sim.stats.get("fed", 0) == 1, "and fed as a pair")
	check(why == "the pens are tended", "with nothing left to do, the party heads home: %s" % why)
	check(sim.expedition.supplies.get("wheat", 0) == 2 and not sim.expedition.supplies.has("stick"), "2 wheat fed the pair, 18 sticks built the fences (%s)" % [sim.expedition.supplies])
	# A young one follows, grows up, and can't be hunted till then.
	var calf: Dictionary = {}
	for i in int(Tuning.BREED_TIME + 5) * Tuning.TPS:
		sim.step()
		var kids: Array = mp.sheep.filter(func(a): return a.get("young", false))
		if not kids.is_empty():
			calf = kids[0]
			break
	check(not calf.is_empty() and calf.species == "cow" and calf.pen == pen.id, "a calf is born in the pen")
	check(sim.tick - fed_at <= int((Tuning.BREED_TIME + 0.1) * Tuning.TPS) and sim.tick - fed_at >= int(Tuning.BREED_TIME * Tuning.TPS), "%d s after they were fed" % int(Tuning.BREED_TIME))
	check(cows.all(func(a): return a.fed_at < 0 and a.cool_until > sim.tick) and sim.on_map(Meadow.ID, sim.feed_pairs.bind(pen)).is_empty(), "the pair can't be fed again for a while")
	sim.on_map(Meadow.ID, func(): sim.designate_hunt(Rect2i(16, 16, 6, 5)))
	check(not calf.des and cows.all(func(a): return a.des) and not Sim.gives(calf, "beef"), "the calf can't be hunted")
	sim.on_map(Meadow.ID, func(): sim.designate_hunt(Rect2i(16, 16, 6, 5)))
	for a in cows:
		a.des = false
	var wild_cows: int = mp.sheep.filter(func(a): return a.alive and a.species == "cow" and a.get("pen", 0) == 0).size()
	run(sim, Tuning.GROW_TIME + 1)
	check(not calf.young and sim.on_map(Meadow.ID, sim.penned.bind(pen)).filter(func(a): return a.species == "cow").size() == 3, "it grows up in the pen")
	check(mp.sheep.filter(func(a): return a.alive and a.species == "cow" and a.get("pen", 0) == 0).size() == wild_cows or wild_cows < Meadow.herd().cow, "the wild cows regrow apart from the pens")
	# Saved and loaded mid-breeding: the pen, its fences and gate, the fed pair.
	var loaded := Sim.from_state(str_to_var(var_to_str(saved)))
	var lmp := loaded.get_map(Meadow.ID)
	check(lmp.pens.size() == 1 and Sim.pen_done(lmp.pens[0]) and lmp.gates.has(pen.gate) and lmp.fences.has(Vector2i(16, 16)), "pens and their fences are saved")
	check(lmp.sheep.filter(func(a): return a.get("pen", 0) == pen.id and a.get("fed_at", -1) >= 0).size() == 2, "and the fed pair")
	for i in int(Tuning.BREED_TIME + 1) * Tuning.TPS:
		loaded.step()
	check(lmp.sheep.any(func(a): return a.alive and a.get("young", false)), "which has its calf after loading too")
	# Tending the pens again: the party hunts only what's over the herd size it keeps.
	for i in 120 * Tuning.TPS:
		sim.step()
		if sim.expedition.is_empty():
			break
	check(sim.expedition.is_empty(), "the first trip is home and unpacked")
	var plan2 := sim.new_plan(Meadow.ID)
	check(plan2.sticks == 0 and plan2.wheat == 0, "with the pen built and the pair resting, a new plan packs no sticks or wheat")
	plan2.party = [ada.id, tomas.id]
	plan2.meals = 4
	plan2.target = {"item": "pens", "n": 2}
	sim.plan_expedition(plan2)
	b.store = {"bread": 4}
	for i in 60 * Tuning.TPS:
		sim.step()
		if sim.depart_blocker() == "":
			break
	check(sim.depart() == "", "a second party sets off to tend the pens, keeping 2 of each")
	var wild: Array = mp.sheep.filter(func(a): return a.alive and a.species == "cow" and a.get("pen", 0) == 0)
	why = ""
	for i in 400 * Tuning.TPS:
		sim.step()
		if sim.expedition.get("leg", "") == "home":
			why = sim.expedition.home_why
			break
	var in_pen: Array = sim.on_map(Meadow.ID, sim.penned.bind(pen))
	check(in_pen.filter(func(a): return a.species == "cow").size() == 2, "it hunts the one cow over the herd size, and keeps 2")
	check(wild.all(func(a): return a.alive), "and leaves the wild cows alone")
	check(why == "the pens are tended" and sim.expedition.cargo.get("beef", 0) == 2 and sim.expedition.cargo.get("leather", 0) == 1, "it packs the surplus cow's beef and leather: %s %s" % [why, sim.expedition.cargo])


## Issue #140: leather armor is crafted at the bench from leather, put on by residents like tools,
## turns aside a share of hazard injuries (a full set also makes serious ones rarer), and wears out.
func test_leather_armor() -> void:
	for k in [["leather_cap", 5, "head"], ["leather_tunic", 8, "chest"], ["leather_trousers", 7, "legs"], ["leather_boots", 4, "feet"]]:
		var rec := Defs.recipe(k[0])
		check(rec.inp == {"leather": k[1]} and rec.out == {k[0]: 1} and Defs.ITEMS[k[0]].armor == k[2] and Sim.recipe_job(rec) == "craft", "a %s takes %d leather at the bench, as Craft work" % [Defs.ITEMS[k[0]].one, k[1]])
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var bench := sim.place_site("bench", open_rect(sim, Vector2i(3, 3)).position + Vector2i(1, 0))
	bench.stage = 1
	bench.done = true
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 1), "leather", 8)
	sim.queue_add(bench, "leather_tunic")
	run(sim, 40)
	check(ada.armor.get("chest") != null and ada.armor.chest.type == "leather_tunic" and ada.armor.chest.dur == Tuning.ARMOR_USES, "Ada crafts a leather tunic and puts it on (%s)" % [ada.armor])
	check(count(sim, "leather") == 0 and is_equal_approx(Sim.protection(ada), Tuning.ARMOR_GUARD.chest), "it took the 8 leather, and guards her against %d%% of hazard injuries" % roundi(Tuning.ARMOR_GUARD.chest * 100))
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Sim.rcell(ada) + Vector2i(2, 0))
	sim.drop_items(Sim.rcell(ada) + Vector2i(0, 2), "leather_tunic", 1)
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 2), "leather_boots", 1)
	run(sim, 20)
	var worn: int = Sim.armor_worn(ada).size() + Sim.armor_worn(tomas).size()
	check(worn == 3 and Sim.armor_worn(ada).has("chest") and Sim.armor_worn(tomas).has("chest"), "residents put on armor lying about for a slot they haven't filled, one piece each slot")
	# A seeded run of hazard rolls: armor turns injuries aside, and a full set makes them less serious.
	var bare := sim.add_resident("Mira", Sim.TRAVELERS[1][1], Vector2i(4, 4))
	var clad := sim.add_resident("Jonas", Sim.TRAVELERS[2][1], Vector2i(5, 4))
	sim.rng.seed = 7
	var hurt := {"bare": 0, "clad": 0}
	var serious := {"bare": 0, "clad": 0}
	for i in 2000:
		for who in [["bare", bare], ["clad", clad]]:
			var r: Dictionary = who[1]
			for slot in Defs.ARMOR_SLOTS:
				if who[0] == "clad":
					r.armor[slot] = {"type": "leather_" + {"head": "cap", "chest": "tunic", "legs": "trousers", "feet": "boots"}[slot], "dur": 99}
			r.hurt = 0
			sim._hazard(r, 0.5, 0.5, "a test")
			if r.hurt > 0:
				hurt[who[0]] += 1
			if r.hurt == 2:
				serious[who[0]] += 1
	var guard := Sim.protection(clad)
	check(is_equal_approx(guard, 0.35), "a full set guards against 35%% of hazard injuries (%.2f)" % guard)
	check(hurt.clad < hurt.bare * 0.75 and hurt.clad > hurt.bare * 0.55, "armored, Jonas is hurt about 35%% less often (%d against %d)" % [hurt.clad, hurt.bare])
	check(float(serious.clad) / hurt.clad < float(serious.bare) / hurt.bare * 0.7, "and a full set makes an injury serious less often (%d of %d against %d of %d)" % [serious.clad, hurt.clad, serious.bare, hurt.bare])
	# Every hazard that strikes wears each piece a use; a piece used up wears out.
	clad.armor = {"chest": {"type": "leather_tunic", "dur": 2}}
	sim._hazard(clad, 1.0, 0.0, "a test")
	check(clad.armor.chest != null and clad.armor.chest.dur == 1, "a hazard that strikes wears the tunic a use")
	sim._hazard(clad, 1.0, 0.0, "a test")
	check(clad.armor.chest == null and Sim.protection(clad) == 0.0 and sim.stats.get("armor_worn_out", 0) == 1, "and the tunic wears out")
	# Saved, and old saves get no armor.
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(loaded.residents[0].armor.chest.type == "leather_tunic", "what each resident wears is saved")
	var up := SaveFormat.upgrade(str_to_var(FileAccess.get_file_as_string("res://tests/fixtures/save_v20.save")))
	check(not up.has("error") and up.data.state.residents.all(func(r): return r.armor == {}), "residents in an older save wear nothing")


# ---------------------------------------------------------------- workstations (issue #177)

## A finished workstation for a resident's job, near them, which they claim (issue #184).
func give_station(sim: Sim, r: Dictionary) -> Dictionary:
	var st := place_done(sim, Defs.JOB_STATIONS[r.role], Sim.rcell(r) + Vector2i(0, 3) if r.map == "village" else Vector2i(16, 16))
	return st


## A finished building of `tpl` on open ground near the middle of the village, or {}.
func place_done(sim: Sim, tpl: String, near := Vector2i(16, 16)) -> Dictionary:
	for d in range(0, 12):
		for x in range(near.x - d, near.x + d + 1):
			for y in range(near.y - d, near.y + d + 1):
				var c := Vector2i(x, y)
				if sim.placement_check(tpl, c) == "" and sim.walkable(c) and sim.obstacles_in(Rect2i(c, Defs.TEMPLATES[tpl].size)).trees.is_empty() and sim.obstacles_in(Rect2i(c, Defs.TEMPLATES[tpl].size)).boulders.is_empty():
					var s := sim.place_site(tpl, c)
					s.stage = Defs.TEMPLATES[tpl].stages.size()
					s.done = true
					sim._occ_dirty = true
					sim.assign_workstations()
					return s
	return {}


func test_lumberjacks_and_stonemasons() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var block := place_done(sim, "chopping_block")
	check(not block.is_empty() and block.keep == Tuning.KEEP_STOCK, "a chopping block keeps %d logs by default" % Tuning.KEEP_STOCK)
	block.make_keep = 0  # gathering and piles only here: no sawing (issue #178)
	run(sim, 30)
	check(sim.stats.felled == 0, "Ada never fells trees on her own, even with a chopping block")
	sim.compute_stuck()
	check(stuck_text(sim).contains("Chopping block: No lumberjack to work it"), "the block says it has nobody to work it: " + stuck_text(sim))
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], sim.nearest_walkable(block.origin + Vector2i(0, 2)))
	sim.set_role(tomas, "lumber")
	tomas.axe = {"type": "stone_axe", "tier": 2, "dur": 999}
	# Keep: the nearest tree in range. Protected: a tree in a fireplace's reserved plot.
	var in_range := sim.trees.filter(func(t): return t.alive and Sim.in_area(block, t.cell))
	in_range.sort_custom(func(a, b): return Sim.manhattan(a.cell, block.origin) < Sim.manhattan(b.cell, block.origin))
	var kept: Dictionary = in_range[0]
	sim.designate_keep(Rect2i(kept.cell, Vector2i.ONE))
	check(kept.keep, "a tree can be marked Keep")
	var plotted := {}
	for t in in_range.slice(1):
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				var o: Vector2i = t.cell + Vector2i(dx, dy)
				var plot = Sim.plot_rect("fireplace", o, 0)
				if plotted.is_empty() and plot.has_point(t.cell) and o != t.cell and sim.placement_check("fireplace", o) == "" and sim.obstacles_in(Rect2i(o, Vector2i.ONE)).trees.is_empty() and sim.obstacles_in(Rect2i(o, Vector2i.ONE)).boulders.is_empty():
					sim.place_site("fireplace", o)
					plotted = t
	check(not plotted.is_empty() and sim.protected(plotted), "a tree in a reserved plot is protected")
	block.keep = 8
	var max_pile := 0
	for i in 120 * Tuning.TPS:
		sim.step()
		max_pile = maxi(max_pile, sim.pile_count(block))
	var felled: Array = sim.trees.filter(func(t): return not t.alive)
	check(felled.size() >= 2, "a lumberjack fells unmarked trees on his own (%d)" % felled.size())
	check(felled.all(func(t): return Sim.in_area(block, t.cell)), "only inside the chopping block's work area")
	check(kept.alive and plotted.alive, "never a tree marked Keep, or one on protected land")
	check(sim.pile_count(block) > 0 and sim.items.get(Sim.pile_cells(block)[0], {}).get("type", "log") == "log", "his logs go to the block's pile (%d)" % sim.pile_count(block))
	check(sim.free_count("log") >= 8, "he stocks the village up to its target (%d logs)" % sim.free_count("log"))
	var at_target: int = sim.stats.felled
	run(sim, 60)
	check(sim.stats.felled <= at_target + 1, "then stops felling (%d, then %d)" % [at_target, sim.stats.felled])
	sim.compute_stuck()
	check(stuck_text(sim).contains("Chopping block: Target reached (8 logs)") and sim.stuck.any(func(x): return x.why.begins_with("Target reached") and x.waiting), "a target reached is waiting, not stuck: " + stuck_text(sim))
	# Marked trees are still worked, Keep or not.
	sim.designate_mine(Rect2i(kept.cell, Vector2i.ONE), kept)
	run(sim, 30)
	check(not kept.alive, "a kept tree is felled once it's marked")
	# Overflow: the pile holds WORK_STORE, the rest goes to the stockpile.
	sim.paint_zone(open_rect(sim, Vector2i(3, 3)))
	block.keep = 100
	for i in 240 * Tuning.TPS:
		sim.step()
		max_pile = maxi(max_pile, sim.pile_count(block))
		if sim.pile_count(block) >= Tuning.WORK_STORE and sim.stacks_where(func(st): return st.type == "log" and sim.in_zone(st.cell)).size() > 0:
			break
	check(max_pile <= Tuning.WORK_STORE, "the pile never holds more than %d (%d)" % [Tuning.WORK_STORE, max_pile])
	check(sim.pile_count(block) == Tuning.WORK_STORE, "the pile fills (%d)" % sim.pile_count(block))
	check(sim.stacks_where(func(st): return st.type == "log" and sim.in_zone(st.cell)).size() > 0, "and the overflow goes to the stockpile")
	sim.compute_stuck()
	check(stuck_text(sim).contains("Chopping block: Full (%d logs)" % Tuning.WORK_STORE), "a full pile says so: " + stuck_text(sim))
	# Builders take from the pile like a stockpile.
	block.keep = 0
	for k in sim.items.keys():
		if sim.items[k].type == "log" and sim.pile_at(k) == null:
			sim.items.erase(k)
	run(sim, 10)
	var before := sim.pile_count(block)
	var bench := sim.place_site("bench", Sim.rcell(ada) + Vector2i(0, -2) if sim.placement_check("bench", Sim.rcell(ada) + Vector2i(0, -2)) == "" else block.origin + Vector2i(0, 4))
	run(sim, 60)
	check(bench.done and sim.pile_count(block) <= before - 4, "a builder takes the bench's logs from the pile (%d, then %d)" % [before, sim.pile_count(block)])
	# A save keeps the target and the Keep marks.
	block.keep = 15
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	var lb: Dictionary = loaded.site(block.id)
	check(lb.keep == 15 and loaded.trees.filter(func(t): return t.get("keep", false)).size() == 1, "the keep-stock target and Keep marks survive a save")
	# Stonemason: needs a pickaxe, then breaks boulders in the mason's bench's area into its pile.
	var mira := sim.add_resident("Mira", Sim.TRAVELERS[1][1], sim.nearest_walkable(block.origin + Vector2i(2, 0)))
	sim.set_role(mira, "mason")
	for k in sim.items.keys():
		if Defs.ITEMS[sim.items[k].type].get("tool", "") == "pick":
			sim.items.erase(k)
	ada.pick = null
	sim.compute_stuck()
	check(stuck_text(sim).contains("Mira: Stonemason: no pickaxe"), "a stonemason with no pickaxe says so: " + stuck_text(sim))
	var mbench := place_done(sim, "mason_bench", Vector2i(8, 8))
	mira.pick = {"type": "stone_pick", "tier": 2, "dur": 999}
	run(sim, 120)
	var broken: Array = sim.boulders.filter(func(b): return not b.alive)
	check(not broken.is_empty() and broken.all(func(b): return Sim.in_area(mbench, b.cell)), "a stonemason breaks boulders in the mason's bench's area on his own (%d)" % broken.size())
	check(sim.pile_count(mbench) > 0, "into the bench's pile (%d cobblestone)" % sim.pile_count(mbench))
	for b in sim.boulders:
		if Sim.in_area(mbench, b.cell):
			b.alive = false
	sim._occ_dirty = true
	sim.compute_stuck()
	check(stuck_text(sim).contains("Mason's bench: No boulders in the mason's bench's area") or stuck_text(sim).contains("Mason's bench: Target reached"), "with none left in its area, the bench says so: " + stuck_text(sim))


func test_saplings_and_replanting() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var tree: Dictionary = Sim.nearest(sim.trees, Sim.rcell(ada))
	sim.direct_order(ada, tree)
	run(sim, 30)
	check(not tree.alive and count(sim, "sapling") >= Tuning.SAPLINGS, "a felled tree drops a sapling (%d)" % count(sim, "sapling"))
	var block := place_done(sim, "chopping_block")
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], sim.nearest_walkable(block.origin + Vector2i(0, 2)))
	sim.set_role(tomas, "lumber")
	block.keep = 0  # no felling: only planting
	var n := sim.trees.size()
	run(sim, 60)
	var planted: Array = sim.trees.slice(n)
	check(not planted.is_empty() and planted.all(func(t): return not Sim.grown(t) and Sim.in_area(block, t.cell) and not sim.protected_cell(t.cell)), "a lumberjack plants saplings in the block's work area, off protected land (%d)" % planted.size())
	check(planted.all(func(t): return not sim.walkable(t.cell)), "a sapling stands in the way like a tree")
	var sap: Dictionary = planted[0]
	sim.designate_mine(Rect2i(sap.cell, Vector2i.ONE))
	check(not sap.des, "a sapling can't be marked to chop")
	check(Sim.tree_stage(sap) == 0, "it starts as a sapling")
	run(sim, Tuning.SAPLING_GROW / 2.0 + 1.0)
	check(Sim.tree_stage(sap) == 1, "then a young tree")
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(loaded.trees.any(func(t): return t.id == sap.id and Sim.tree_stage(t) == 1), "growth survives a save")
	run(sim, Tuning.SAPLING_GROW / 2.0)
	check(Sim.grown(sap), "and grows into a full tree in %d seconds" % int(Tuning.SAPLING_GROW))
	block.keep = 100
	sim.designate_keep(Rect2i(sap.cell, Vector2i.ONE))  # keep it, so it's still standing below
	# A blueprint over a sapling lifts it.
	var young := sim.trees.filter(func(t): return t.alive and not Sim.grown(t))
	if not young.is_empty():
		var y: Dictionary = young[0]
		var before := count(sim, "sapling")
		sim.place_site("bench", y.cell)
		check(not y.alive and count(sim, "sapling") == before + 1, "a blueprint over a sapling lifts it back into a sapling")
	# No trees left in range.
	for t in sim.trees:
		if Sim.in_area(block, t.cell):
			t.alive = false
	sim._occ_dirty = true
	sim.compute_stuck()
	check(stuck_text(sim).contains("Chopping block: No trees in the chopping block's area. Plant saplings, or paint more ground"), "with none left in its area, the block says so: " + stuck_text(sim))


# ---------------------------------------------------------------- workstations claimed (issue #184)

func test_hunters_keep_a_herd_floor() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	for i in 3:  # six in all: a new game has only 3 (issue #182)
		sim.add_sheep(sim.nearest_walkable(Sim.rcell(ada) + Vector2i(4 + i * 2, 4)))
	var wild := func() -> int: return sim.sheep.filter(func(a): return a.alive and a.get("pen", 0) == 0).size()
	var flock: int = wild.call()
	run(sim, 30)
	check(wild.call() == flock, "Ada never hunts on her own (%d sheep)" % flock)
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], sim.nearest_walkable(Sim.rcell(ada) + Vector2i(2, 0)))
	sim.set_role(tomas, "hunt")
	run(sim, 20)
	check(wild.call() == flock, "a hunter with no lodge doesn't hunt")
	var lodge := give_station(sim, tomas)
	check(is_same(sim.claimed(tomas), lodge), "Tomas claims the hunter's lodge")
	check(sim.floor_of("sheep") == Tuning.HERD_FLOOR, "the herd floor starts at %d" % Tuning.HERD_FLOOR)
	var keep := flock - 2
	sim.set_herd_floor("sheep", keep)
	run(sim, 150)
	check(wild.call() == keep, "he hunts on his own down to the floor and no further (%d of %d left, floor %d)" % [wild.call(), flock, keep])
	sim.compute_stuck()
	check(stuck_text(sim).contains("Tomas: Hunter: herd at its floor (%d sheep)" % keep) and sim.stuck.any(func(x): return x.why.begins_with("Hunter: herd") and x.waiting), "the stuck list says the herd is at its floor, waiting: " + stuck_text(sim))
	# Marks come first, and a marked animal is hunted even below the floor.
	ada.away = true  # off at the meadow, so the marks are Tomas's
	ada.back_at = 1 << 30
	var near: Dictionary = Sim.nearest(sim.sheep.filter(func(a): return a.alive), Sim.rcell(tomas))
	var far: Dictionary = sim.sheep.filter(func(a): return a.alive and not is_same(a, near)).reduce(func(best, a): return a if Sim.manhattan(a.cell, Sim.rcell(tomas)) > Sim.manhattan(best.cell, Sim.rcell(tomas)) else best)
	sim.set_herd_floor("sheep", 0)
	far.des = true
	sim.fail_job(tomas)
	var first = null
	for i in 10 * Tuning.TPS:
		sim.step()
		if tomas.job != null and tomas.job.work == "hunt":
			first = tomas.job.target
			break
	check(first != null and is_same(first, far), "with the floor lowered, he hunts the marked sheep before a nearer unmarked one")
	sim.set_herd_floor("sheep", 50)
	var before: int = wild.call()
	var other: Dictionary = sim.sheep.filter(func(a): return a.alive and not a.des and a.claim == 0)[0]
	other.des = true
	run(sim, 60)
	check(not other.alive and wild.call() < before, "a marked sheep is hunted even at the floor")
	sim.set_herd_floor("sheep", -3)
	check(sim.floor_of("sheep") == 0, "the floor never goes below 0")
	# Saved with the game.
	sim.set_herd_floor("cow", 5)
	var back := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(back.floor_of("cow") == 5 and back.floor_of("pig") == Tuning.HERD_FLOOR, "herd floors are saved, unset ones at the default")


func test_workstations_process_materials() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	ada.away = true  # off at the meadow: the workstations' own gatherers do the work
	ada.back_at = 1 << 30
	var logs_before: int = sim.stats.felled
	var block := place_done(sim, "chopping_block")
	check(block.make_keep == 20 and Sim.is_station(block), "a chopping block is a station that keeps 20 planks by default")
	block.keep = 0  # no felling: just the logs set down for it
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], sim.nearest_walkable(block.origin + Vector2i(0, 2)))
	sim.set_role(tomas, "lumber")
	check(is_same(sim.claimed(tomas), block), "Tomas claims the chopping block")
	sim.set_make_keep(block, 12)
	sim.drop_items(sim.nearest_walkable(block.origin + Vector2i(2, 2)), "log", 4)
	run(sim, 4)
	check(block.queue == ["saw_planks"] and block.autoq == [true], "under its target, the standing order queues sawn planks (%s)" % [block.queue])
	run(sim, 90)
	check(sim.free_count("plank") == 15 and sim.free_count("log") == 1, "he saws 5 planks a log, up to the target, then stops (%d planks, %d logs left)" % [sim.free_count("plank"), sim.free_count("log")])
	check(sim.stats.felled == logs_before and tomas.jobs.lumber.xp > 0, "sawing is Lumberjack work (%d xp)" % tomas.jobs.lumber.xp)
	check(Sim.recipe_for(tomas, Defs.recipe("saw_planks")).out.plank == 5, "a level-1 lumberjack saws 5 planks")
	tomas.jobs.lumber.xp = Tuning.SKILL_LEVELS[2]
	check(Sim.recipe_for(tomas, Defs.recipe("saw_planks")).out.plank == 6, "a level-4 lumberjack saws 6")
	check(Defs.recipe("planks").out.plank == 4 and Defs.recipe("planks").get("at", "bench") == "bench", "the bench's Planks recipe stays, at 4 a log")
	# The mason's bench cuts stone bricks.
	var mb := place_done(sim, "mason_bench", block.origin + Vector2i(6, 0))
	check(mb.make_keep == 10, "a mason's bench keeps 10 stone bricks by default")
	mb.keep = 0
	var mira := sim.add_resident("Mira", Sim.TRAVELERS[1][1], sim.nearest_walkable(mb.origin + Vector2i(0, 2)))
	sim.set_role(mira, "mason")
	sim.set_make_keep(mb, 4)
	sim.drop_items(sim.nearest_walkable(mb.origin + Vector2i(2, 2)), "cobble", 7)
	run(sim, 90)
	check(sim.free_count("stone_brick") == 4 and sim.free_count("cobble") == 3, "she cuts 2 cobblestone into 2 stone bricks, up to the target (%d bricks, %d cobblestone left)" % [sim.free_count("stone_brick"), sim.free_count("cobble")])
	check(mira.jobs.mason.xp > 0, "cutting is Stonemason work")
	# Queued by hand, past the target; a target of 0 turns the standing order off.
	sim.set_make_keep(mb, 0)
	sim.queue_add(mb, "stone_bricks")
	run(sim, 30)
	check(sim.free_count("stone_brick") == 6 and mb.queue.is_empty(), "a batch queued by hand is cut regardless (%d)" % sim.free_count("stone_brick"))
	var back := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(back.sites.any(func(st): return st.tpl == "chopping_block" and st.make_keep == 12), "standing orders are saved")


func test_storehouse_chests() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var sh := place_done(sim, "storehouse", Sim.rcell(ada) + Vector2i(0, 5))
	check(not sh.is_empty() and sh.plot.size == Vector2i(3, 5), "a storehouse is 3×3, with its upgrade's plot behind it")
	var houses_before: int = sim.stats.houses
	sim._on_site_done(sh)
	check(sim.stats.houses == houses_before and sh.owner == 0 and sim.events.any(func(ev): return ev.type == "toast" and ev.text.begins_with("The storehouse is built")), "finishing a storehouse isn't a house: it counts as none, has no owner, and says what to do next")
	sim.events.clear()
	sim.compute_stuck()
	check(stuck_text(sim).contains("Storehouse: No chests yet"), "with no chests it says so: " + stuck_text(sim))
	# A chest from the bench is carried in and set in place: 9 stacks of room.
	check(Defs.recipe("chest").inp == {"plank": 8}, "a chest is 8 planks at the bench")
	sim.drop_items(Sim.rcell(ada) + Vector2i(2, 0), "chest", 1)
	run(sim, 40)
	check(sh.chests == 1 and Sim.store_slots(sh).size() == Tuning.CHEST_STACKS and sim.free_count("chest") == 0, "a hauler carries the chest in (%d chests)" % sh.chests)
	# Haulers fill the chests first; the stockpile takes what's left over.
	var slots := Sim.store_slots(sh)
	var cap := Defs.stack_cap("log")
	for i in Tuning.CHEST_STACKS - 1:
		sim._store_put(slots[i], "cobble", Defs.stack_cap("cobble"))
	sim.paint_zone(open_rect(sim, Vector2i(2, 1)))
	sim.drop_items(Sim.rcell(ada) + Vector2i(3, 1), "log", cap + 3)
	run(sim, 90)
	var last = sim.items.get(slots[-1])
	check(last != null and last.type == "log" and last.n == cap, "the chests fill up to their capacity (%s)" % [last])
	var piled := sim.stacks_where(func(st): return st.type == "log" and sim.in_zone(st.cell))
	check(piled.size() == 1 and piled[0].n == 3, "and only the overflow goes to the stockpile (%s)" % [piled.map(func(st): return st.n)])
	sim.drop_items(Sim.rcell(ada) + Vector2i(3, 1), "wool", 2 * Defs.stack_cap("wool") + 1)
	run(sim, 90)
	sim.compute_stuck()
	check(stuck_text(sim).contains("The storehouse is full") and stuck_text(sim).contains("Stockpile is full"), "with no room anywhere, the storehouse and the stockpile say they're full: " + stuck_text(sim))
	# Crafting fetches from the chests.
	var bench := place_done(sim, "bench", Sim.rcell(ada) + Vector2i(-3, 0))
	for k in sim.items.keys():
		if sim.items[k].type == "log" and not Sim.in_store(k):
			sim.items.erase(k)
	sim.queue_add(bench, "planks")
	run(sim, 30)
	check(bench.queue.is_empty() and sim.items.get(slots[-1], {}).get("n", 0) == cap - 1, "the bench's log comes out of a chest")
	# The nearest storehouse with room fills first.
	var far := place_done(sim, "storehouse", Sim.rcell(ada) + Vector2i(14, 0))
	far.chests = 1
	var near_door := Sim.store_door(far)
	sim.drop_items(near_door + Vector2i(0, 1), "stick", 4)
	run(sim, 40)
	check(sim.stacks_where(func(st): return st.type == "stick" and Sim.in_store(st.cell) and is_same(sim.store_of(st.cell), far)).size() == 1, "sticks dropped by the far storehouse go into its chest")
	# Packing for an expedition fetches from the chests too.
	sim.residents[0].hunger = 100.0
	for k in Sim.store_slots(far):
		if not sim.items.has(k):
			sim._store_put(k, "bread", 3)
			break
	var board := place_done(sim, "board", Sim.rcell(ada) + Vector2i(-4, 4))
	var plan := sim.new_plan(Meadow.ID)
	plan.meals = 3
	check(sim.plan_expedition(plan) == "", "a meadow trip is planned")
	var packed := false
	for i in 120 * Tuning.TPS:
		sim.step()
		if sim.depart_blocker() == "":
			packed = true
			break
	check(packed, "its bread is packed from the far storehouse's chest (%s)" % sim.depart_blocker())
	# Saved with the game.
	var back := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	var bsh: Dictionary = back.sites.filter(func(st): return st.id == sh.id)[0]
	check(bsh.chests == 1 and back.items.has(slots[0]) and back.items[slots[0]].type == "cobble", "chests and what's in them are saved")
	check(board.done, "")


## Everything with a cell in the village, as strings, so two copies can be compared. Chest slots keep
## their keys and only their door moves (issue #187).
func village_cells(sim: Sim) -> Dictionary:
	var m: SimMap = sim.maps.village
	var out := {"tree": [], "boulder": [], "bush": [], "sheep": [], "item": [], "chest": [], "zone": [], "farm": [], "site": [], "plot": [], "pen": [], "res": []}
	for t in m.trees:
		out.tree.append(t.cell)
	for b in m.boulders:
		out.boulder.append(b.cell)
	for b in m.bushes:
		out.bush.append(b.cell)
	for a in m.sheep:
		out.sheep.append(a.cell)
	for k in m.items:
		if k.x < 0:
			out.chest.append(m.items[k].at)
		else:
			out.item.append(m.items[k].cell)
	out.zone = m.zone.keys()
	out.farm = m.farm.keys()
	for st in m.sites:
		out.site.append(st.origin)
		if st.get("plot") != null:
			out.plot.append(st.plot.position)
	for p in m.pens:
		out.pen.append(p.rect.position)
	for r in sim.residents:
		out.res.append(Vector2i(r.pos))
	return out


func test_land_claims() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	sim.add_resident("Tomas", Sim.TRAVELERS[0][1], sim.nearest_walkable(Sim.rcell(ada) + Vector2i(2, 0)))
	sim.add_resident("Mira", Sim.TRAVELERS[1][1], sim.nearest_walkable(Sim.rcell(ada) + Vector2i(-2, 0)))
	check(sim.claims_available() == 0 and sim.claim_check("east").contains("needs 4 residents"), "three residents have no claim yet: " + sim.claim_check("east"))
	sim.add_resident("Bram", Sim.TRAVELERS[2][1], sim.nearest_walkable(Sim.rcell(ada) + Vector2i(0, 2)))
	check(sim.claims_available() == 1 and sim.claim_check("east") == "", "the fourth resident unlocks one")
	var w0: int = sim.w
	var h0: int = sim.h
	# A claim east: stake it, and a builder plants the stakes.
	var before := village_cells(sim)
	check(sim.place_claim("east") == "" and sim.claims_available() == 0, "staking an edge uses the claim")
	check(sim.claim_check("north") == "A claim is already staked", "and only one at a time: " + sim.claim_check("north"))
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 1), "stick", Tuning.CLAIM_STAKES)
	run(sim, 90)
	check(sim.w == w0 + Tuning.CLAIM_DEPTH and sim.h == h0 and sim.claims_made == 1, "the stakes go in and the village grows east (%d×%d)" % [sim.w, sim.h])
	check(sim.sites.all(func(st): return st.tpl != "claim_stakes"), "the stakes are gone")
	check(sim.stats.houses == 0 and not sim.events.any(func(ev): return ev.type == "toast" and ev.text.contains("house")), "and they didn't count as a house")
	var after := village_cells(sim)
	check(after.tree.size() > before.tree.size() and before.tree.all(func(c): return after.tree.has(c)), "every old tree is where it was, and the new land has more")
	check(sim.route_sign() == Vector2i(sim.w - 1, sim.h / 2) and sim.walkable(sim.route_sign()), "the signpost to the mine moves out to the new east edge")
	check(sim.meadow_sign() == Vector2i(0, sim.h / 2), "and the meadow's, on the west edge, stays")
	# North and west shift everything, and nothing is left behind.
	for edge in ["north", "west", "south"]:
		var t := Sim.new_game()
		var a: Dictionary = t.residents[0]
		for i in 3:
			t.add_resident("R%d" % i, Sim.TRAVELERS[i][1], t.nearest_walkable(Sim.rcell(a) + Vector2i(i - 1, 2)))
		var house := place_done(t, "house", Vector2i(12, 12))
		var block := place_done(t, "chopping_block", Vector2i(18, 12))
		var store := place_done(t, "storehouse", Vector2i(12, 20))
		store.chests = 1
		var slots := Sim.store_slots(store)
		t._store_put(slots[0], "log", 7)
		t.paint_zone(open_rect(t, Vector2i(3, 2)))
		t.paint_farm(open_rect(t, Vector2i(2, 2)))
		t.drop_items(Sim.rcell(a) + Vector2i(3, 3), "cobble", 5)
		var animal := t.add_sheep(t.nearest_walkable(Sim.rcell(a) + Vector2i(4, 0)))
		animal.dest = animal.cell + Vector2i(1, 0)  # on its way somewhere when the land is claimed
		t.m.pens.append({"id": t._id(), "kind": "pen", "rect": Rect2i(Vector2i(20, 20), Vector2i(3, 3)), "gate": Vector2i(20, 21), "built": {Vector2i(20, 20): true}})
		t.direct_order(a, null, Vector2i(5, 5))
		var was := village_cells(t)
		var walk := {}
		for x in t.w:
			for y in t.h:
				walk[Vector2i(x, y)] = t.walkable(Vector2i(x, y))
		var stakes := t.place_site("claim_stakes", t.claim_cell(edge))
		stakes.edge = edge
		stakes.stage = 1
		stakes.done = true
		t._occ_dirty = true
		t.compute_stuck()
		t._apply_claims()
		var off := Vector2i(Tuning.CLAIM_DEPTH, 0) if edge == "west" else (Vector2i(0, Tuning.CLAIM_DEPTH) if edge == "north" else Vector2i.ZERO)
		var now := village_cells(t)
		var drift := 0
		for k in was:
			if k == "item" or k == "chest" or k == "tree" or k == "boulder" or k == "bush" or k == "sheep":
				continue  # the new land adds more of these; theirs are checked below
			var moved: Array = was[k].map(func(c): return c + off)
			if k == "site":
				moved = moved.filter(func(c): return c != stakes.origin + off)
			for c in moved:
				if not now[k].has(c):
					drift += 1
		check(drift == 0, "%s claim: every site, plot, stockpile cell, farm plot, pen and resident moved by (%s) and none was left behind (%d off)" % [edge, off, drift])
		check(was.item.all(func(c): return now.item.has(c + off)) and was.tree.all(func(c): return now.tree.has(c + off)) and was.boulder.all(func(c): return now.boulder.has(c + off)), "%s claim: the loose stacks, trees and boulders too" % edge)
		check(was.chest.all(func(c): return now.chest.has(c + off)) and t.items.has(slots[0]) and t.items[slots[0]].n == 7, "%s claim: a chest slot keeps its key, its door moves with the building" % edge)
		check(walk.keys().all(func(c): return walk[c] == t.walkable(c + off) or c == stakes.origin), "%s claim: every old cell is as walkable as before" % edge)
		check(is_same(t.site_at(house.origin), house) and house.done and block.done, "%s claim: buildings are intact" % edge)
		check(animal.cell == Vector2i(animal.pos) and t.in_bounds(animal.cell) and animal.dest == animal.cell + Vector2i(1, 0), "%s claim: animals stand on the map, with their destination" % edge)
		# On with the show: hauling goes to the shifted stockpile and the village still works.
		t.drop_items(t.nearest_walkable(Sim.rcell(a) + Vector2i(1, 4)), "plank", 6)
		run(t, 60)
		check(t.stacks_where(func(st): return st.type == "plank" and (t.in_zone(st.cell) or Sim.in_store(st.cell))).size() > 0, "%s claim: haulers still carry things to storage" % edge)
	# A traveler still walking in when the land is claimed carries on to his house.
	var w := Sim.new_game()
	var home := place_done(w, "house", Vector2i(12, 12))
	home.stage = 4
	w._arrive()
	var walker: Dictionary = w.residents[-1]
	check(walker.arriving and walker.job != null, "a traveler walks in")
	var ws := w.place_site("claim_stakes", w.claim_cell("west"))
	ws.edge = "west"
	ws.stage = 1
	ws.done = true
	w._apply_claims()
	check(walker.arriving and walker.job != null and walker.job.kind == "arrive", "a claim made meanwhile doesn't stop him: he walks on, to the house where it now stands")
	run(w, 60)
	check(not walker.arriving and home.owner == walker.id, "and moves in (%s)" % [walker.job])
	# Deterministic: the same seed and claim number give the same land.
	var u := Sim.new_game()
	var v := Sim.new_game()
	var st_u := u.place_site("claim_stakes", u.claim_cell("north"))
	var st_v := v.place_site("claim_stakes", v.claim_cell("north"))
	for pair in [[u, st_u], [v, st_v]]:
		pair[1].edge = "north"
		pair[1].stage = 1
		pair[1].done = true
		pair[0]._apply_claims()
	check(village_cells(u).tree == village_cells(v).tree and village_cells(u).boulder == village_cells(v).boulder, "new land is generated the same way from the same seed")
	var seeded := Sim.new_game()
	seeded.seed = 99
	var st_s := seeded.place_site("claim_stakes", seeded.claim_cell("north"))
	st_s.edge = "north"
	st_s.stage = 1
	st_s.done = true
	seeded._apply_claims()
	check(village_cells(seeded).tree != village_cells(u).tree, "and differently from another seed")
	# The size never passes the maximum.
	var big := Sim.new_game()
	for i in 6:
		big.add_resident("R%d" % i, Sim.TRAVELERS[i % 5][1], big.nearest_walkable(Vector2i(10 + i, 10)))
	big.maps.village.grow("east", Tuning.MAP_MAX - Tuning.CLAIM_DEPTH + 1 - big.w)
	check(big.claim_check("east").contains("at its largest") and big.claim_check("south") == "", "the village stops growing at %d cells a side, per direction (%s)" % [Tuning.MAP_MAX, big.claim_check("east")])
	# Older saves: the size is kept and claims come from the residents.
	var raw := SaveFormat.read("res://tests/fixtures/save_v24.save")
	var old := Sim.from_state(raw.data.state)
	check(old.w == Tuning.MAP_W and old.claims_made == 0 and old.claims_available() == maxi(0, (old.residents.size() - 2) / Tuning.CLAIM_EVERY), "an older save keeps its size, with claims for its residents (%d)" % old.claims_available())
	var back := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(back.w == sim.w and back.claims_made == 1, "the grown size and the claims made are saved")


## Issue #205: a building's debris is carried off before building starts, and nothing jumps.
func test_blueprints_clear_their_footprint() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	sim.paint_zone(open_rect(sim, Vector2i(4, 2)))
	var spot := open_cell_for(sim, Vector2i(3, 3))
	# A tree felled on a blueprint: its logs land beside it and are carried to the stockpile.
	var tree := {"id": sim._id(), "kind": "tree", "cell": spot + Vector2i(1, 1), "logs": 9, "alive": true, "des": false, "claim": 0, "unreach_until": 0}
	sim.trees.append(tree)
	var house := sim.place_site("bench", tree.cell)
	check(tree.des, "a tree under a blueprint is marked to fell")
	var on_footprint := 0
	for i in 40 * Tuning.TPS:
		sim.step()
		if not tree.alive and sim.items.has(tree.cell):
			on_footprint += 1
	check(not tree.alive and on_footprint == 0, "its logs never land on the footprint (%d ticks with a stack there)" % on_footprint)
	run(sim, 40)
	check(sim.stacks_where(func(st): return st.type == "log" and sim.in_zone(st.cell)).size() > 0 and house.done, "they're carried to the stockpile, and the building goes up (done %s, logs %s, stuck %s)" % [house.done, sim.stacks_where(func(st): return st.type == "log").map(func(st): return [st.cell, st.n, sim.in_zone(st.cell)]), stuck_text(sim)])
	# A stack lying on a blueprint: building waits until it's hauled off, and nothing jumps.
	var sim2 := Sim.new_game()
	sim2.paint_zone(open_rect(sim2, Vector2i(4, 2)))
	var cell := open_cell_for(sim2, Vector2i(1, 1))
	sim2.drop_items(cell, "log", 6)
	sim2.drop_items(Sim.rcell(sim2.residents[0]) + Vector2i(0, 1), "log", 8)
	check(sim2.items.has(cell), "a stack is lying where the blueprint goes")
	var bench := sim2.place_site("bench", cell)
	check(not sim2.footprint_clear(bench) and not sim2.site_ready(bench), "the blueprint can't start with it there")
	check(Sim.clearing_text(sim2.obstacles_in(Rect2i(cell, Vector2i.ONE))) == "6 logs", "and the hint names it (%s)" % Sim.clearing_text(sim2.obstacles_in(Rect2i(cell, Vector2i.ONE))))
	sim2.compute_stuck()
	check(stuck_text(sim2).contains("Clearing: 6 logs to move"), "the stuck list says so: " + stuck_text(sim2))
	var started_early := false
	for i in 60 * Tuning.TPS:
		sim2.step()
		if sim2.items.has(cell) and (bench.builder != 0 or not bench.store.is_empty() or bench.stage > 0):
			started_early = true
	check(not started_early and not sim2.items.has(cell) and bench.done, "it's hauled off first, then the bench is built (done %s)" % bench.done)
	var logs := 0
	for st in sim2.stacks_where(func(x): return x.type == "log"):
		logs += st.n
	check(logs >= 6 and sim2.stacks_where(func(st): return st.type == "log" and sim2.in_zone(st.cell)).size() > 0, "the logs were carried, not lost (%d)" % logs)
	check(not sim2.items.has(cell) and not sim2.items.has(cell + Vector2i(0, 1)), "none jumped to the door of the finished bench")
	# A berry bush: dug up, its berries carried off.
	var sim3 := Sim.new_game()
	sim3.paint_zone(open_rect(sim3, Vector2i(4, 2)))
	var bcell := open_cell_for(sim3, Vector2i(1, 1))
	var bush := sim3.add_bush(bcell)
	check(Sim.clearing_text(sim3.obstacles_in(Rect2i(bcell, Vector2i.ONE))) == "a bush", "the hint names a bush")
	sim3.drop_items(Sim.rcell(sim3.residents[0]) + Vector2i(1, 1), "log", 4)  # the bench's logs
	var b3 := sim3.place_site("bench", bcell)
	check(not sim3.bushes.has(bush) and not sim3.items.has(bcell), "a bush under a blueprint is dug up, its berries set beside it")
	run(sim3, 60)
	check(sim3.stacks_where(func(st): return st.type == "berries" and sim3.in_zone(st.cell)).size() > 0, "and carried to the stockpile")
	check(b3.done, "the building goes up")
	# Somewhere to put it: with no room, the blueprint says so; with no storage at all, it's carried clear.
	var sim4 := Sim.new_game()
	var zc := open_cell_for(sim4, Vector2i(1, 1))
	sim4.paint_zone(Rect2i(zc, Vector2i.ONE))
	sim4.drop_items(zc, "cobble", Defs.stack_cap("cobble"))  # a full stockpile
	var c4 := open_cell_for(sim4, Vector2i(1, 1))
	sim4.drop_items(c4, "log", 6)
	sim4.place_site("bench", c4)
	sim4.compute_stuck()
	check(stuck_text(sim4).contains("Clearing: no room in a stockpile for 6 logs"), "a full stockpile: " + stuck_text(sim4))
	var sim5 := Sim.new_game()
	var c5 := open_cell_for(sim5, Vector2i(1, 1))
	sim5.drop_items(c5, "log", 6)
	sim5.drop_items(Sim.rcell(sim5.residents[0]) + Vector2i(1, 2), "log", 4)
	var b5 := sim5.place_site("bench", c5)
	run(sim5, 60)
	check(not sim5.items.has(c5) and b5.done and sim5.free_count("log") >= 6, "no storage at all: the logs are carried to open ground beside it and the bench goes up (%d logs about)" % sim5.free_count("log"))
	# A walked-over building clears its footprint too.
	var sim6 := Sim.new_game()
	sim6.paint_zone(open_rect(sim6, Vector2i(4, 2)))
	var c6 := open_cell_for(sim6, Vector2i(1, 1))
	sim6.drop_items(c6, "cobble", 5)
	var stakes := sim6.place_site("claim_stakes", c6)
	check(not sim6.footprint_clear(stakes), "boundary stakes wait for the ground to be cleared too")


## An open cell for a `size` building near the middle of the village, with nothing on it.
func open_cell_for(sim: Sim, size: Vector2i) -> Vector2i:
	var start := Sim.rcell(sim.residents[0]) + Vector2i(5, 5)
	for d in range(0, 14):
		for x in range(start.x - d, start.x + d + 1):
			for y in range(start.y - d, start.y + d + 1):
				var r := Rect2i(Vector2i(x, y), size)
				var ok := true
				for cx in range(r.position.x - 1, r.end.x + 1):
					for cy in range(r.position.y - 1, r.end.y + 1):
						var c := Vector2i(cx, cy)
						if not sim.walkable(c) or sim.in_zone(c) or sim.items.has(c) or sim.farm_blocked(c) != "" or sim.reserved_at(c) != null:
							ok = false
				if ok:
					return r.position
	return start


func test_jobs_need_their_workstation() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], sim.nearest_walkable(Sim.rcell(ada) + Vector2i(2, 0)))
	sim.set_role(tomas, "farm")
	sim.paint_farm(open_rect(sim, Vector2i(2, 2)))
	ada.away = true  # off at the meadow, so the plots are Tomas's to farm
	ada.back_at = 1 << 30
	var farmed := false
	for i in 15 * Tuning.TPS:
		sim.step()
		farmed = farmed or (tomas.job != null and tomas.job.work == "farm")
	check(not farmed and not sim.works(tomas, "farm"), "a farmer with no composter doesn't farm")
	check(sim.role_text(tomas) == "Farmer (no composter)", "his job reads \"Farmer (no composter)\" (%s)" % sim.role_text(tomas))
	sim.compute_stuck()
	check(stuck_text(sim).contains("Tomas: Build a composter to start work"), "the stuck list says so: " + stuck_text(sim))
	var comp := place_done(sim, "composter", Sim.rcell(tomas) + Vector2i(0, 3))
	check(comp.worker == tomas.id and is_same(sim.claimed(tomas), comp), "building a composter: Tomas claims it")
	check(sim.station_title(comp) == "Tomas's composter" and sim.role_text(tomas) == "Farmer", "\"Tomas's composter\", and his job reads Farmer")
	sim.fail_job(tomas)
	farmed = false
	for i in 20 * Tuning.TPS:
		sim.step()
		farmed = farmed or (tomas.job != null and tomas.job.work == "farm")
	check(farmed, "and he farms")
	ada.away = false
	# One resident to a workstation.
	var bram := sim.add_resident("Bram", Sim.TRAVELERS[2][1], sim.nearest_walkable(Sim.rcell(ada) + Vector2i(-2, 0)))
	sim.set_role(bram, "farm")
	check(comp.worker == tomas.id and sim.needs_station(bram), "a second farmer doesn't share Tomas's composter")
	var comp2 := place_done(sim, "composter", Sim.rcell(bram) + Vector2i(0, -3))
	check(comp2.worker == bram.id, "a second composter goes to him")
	# Ada works anywhere and claims nothing.
	check(sim.claimed(ada).is_empty() and sim.job_list(ada) == Defs.JOBS, "Ada claims no workstation and does every job")
	# A new job frees the old workstation; tearing one down hands its resident another, or leaves them hauling.
	sim.set_role(bram, "cook")
	check(comp2.worker == 0 and sim.needs_station(bram), "a new job frees the old workstation")
	sim.cancel_site(comp)
	check(comp2.worker == tomas.id, "with his composter gone, Tomas claims the free one")
	sim.cancel_site(comp2)
	check(sim.needs_station(tomas) and sim.job_list(tomas) == ["haul"], "with none left, he hauls")
	# Toolsmith's spares need a resident toolsmith with a toolsmith's bench.
	sim.set_role(bram, "toolsmith")
	check(not sim.has_toolsmith(), "a toolsmith with no toolsmith's bench keeps no spares")
	var tbench := place_done(sim, "toolsmith_bench", Sim.rcell(bram) + Vector2i(3, 0))
	check(tbench.worker == bram.id and sim.has_toolsmith(), "with one, he does")
	# Crafters use their own bench first.
	var b1 := place_done(sim, "bench", Vector2i(6, 6))
	var b2 := place_done(sim, "bench", Vector2i(24, 24))
	sim.set_role(tomas, "craft")
	var own := sim.claimed(tomas)
	check(not own.is_empty() and (is_same(own, b1) or is_same(own, b2)), "a crafter claims a bench")
	for b in [b1, b2]:
		sim.queue_add(b, "planks")
	sim.drop_items(own.origin + Vector2i(0, 1), "log", 2)
	sim.drop_items((b2 if is_same(own, b1) else b1).origin + Vector2i(0, 1), "log", 2)
	sim.fail_job(tomas)
	var at_own := false
	var elsewhere := false
	for i in 10 * Tuning.TPS:
		sim.step()
		if tomas.job != null and tomas.job.target != null and tomas.job.target.get("tpl", "") == "bench":
			at_own = at_own or is_same(tomas.job.target, own)
			elsewhere = elsewhere or (not at_own and not is_same(tomas.job.target, own))
	check(at_own and not elsewhere, "and works at his own first")
	# Saved and loaded, workstations keep their residents.
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(loaded.site(tbench.id).worker == bram.id and not loaded.claimed(loaded.resident(bram.id)).is_empty(), "claims survive a save")


## Issue #198: every founding goal says why, the village chapter follows in order, and a page shows
## once its building is known.
func test_founding_book_chapter_and_pages() -> void:
	for g in Goals.LIST:
		check(g.get("w", "") != "", "founding goal \"%s\" has a why" % g.t)
	for g in Goals.VILLAGE:
		check(g.get("h", "") != "" and g.get("w", "") != "", "village goal \"%s\" has a hint and a why" % g.t)
	check(Goals.VILLAGE[-1].t.begins_with("Bring iron ore"), "the mine trip is the chapter's last task")
	var ids := {}
	for p in Goals.PAGES:
		for k in ["title", "what", "who", "grows", "without"]:
			check(p.get(k, "") != "", "page %s has %s" % [p.id, k])
		check(not ids.has(p.id), "page id %s is unique" % p.id)
		ids[p.id] = true
		check(p.get("tpl", "") == "" or Defs.TEMPLATES.has(p.tpl), "page %s names a real building" % p.id)
	for e in OrderMenus.MENUS.build.entries:
		if e.id != "claim":
			check(not Goals.page_for(e.id).is_empty(), "the Build menu's %s has a page" % e.id)
	# The chapter, in order.
	var sim := Sim.new_game()
	check(Goals.village_current(sim) == 0, "a new village starts at the farm")
	sim.paint_farm(open_rect(sim, Vector2i(2, 2)))
	check(Goals.village_current(sim) == 1, "a farm plot is goal 1")
	sim.stats.meals_cooked = 1
	check(Goals.village_current(sim) == 2, "a cooked meal is goal 2")
	var picked := 0
	for tpl in ["chopping_block", "mason_bench"]:
		var st := sim.place_site(tpl, open_cell_for(sim, Vector2i(1, 1)))
		st.done = true
		st.worker = sim.residents[0].id
		picked += 1
		check(Goals.village_current(sim) == (2 if picked < 2 else 3), "%d workstation(s) with a worker: goal %d" % [picked, Goals.village_current(sim)])
	sim.stats.ore_home = true
	check(Goals.village_current(sim) == -1, "iron ore home finishes the chapter")
	# Pages wait for their building.
	var fresh := Sim.new_game()
	var shown := Goals.pages(fresh).map(func(p): return p.id)
	check(not "board" in shown and not "pen" in shown and not "road" in shown and "bench" in shown, "a new village's book has no board, pen or road page (%s)" % [shown])
	fresh.stats.houses = 1
	check(Goals.pages(fresh).any(func(p): return p.id == "board"), "the board's page shows once Ada's house is up")
	fresh.stats.built.board = true
	check(Goals.pages(fresh).any(func(p): return p.id == "pen"), "the pen's page shows once the board is built")
	fresh.get_map("old_mine").visited = true
	check(Goals.pages(fresh).any(func(p): return p.id == "road"), "the road's page shows once the party has been to the mine")
	# The counters.
	var cook := Sim.new_game()
	cook.stats.meals_cooked = 0
	var bench := cook.place_site("fireplace", open_cell_for(cook, Vector2i(1, 1)))
	check(not cook.stats.ore_home and cook.stats.meals_cooked == 0, "a new game has cooked nothing and brought nothing home")


## Issue #198: an old village isn't asked to do what it already has.
func test_founding_book_save_upgrade() -> void:
	var raw: Dictionary = str_to_var(FileAccess.get_file_as_string("res://tests/fixtures/save_v29.save"))
	var plain := SaveFormat.upgrade(raw.duplicate(true))
	check(plain.data.state.stats.meals_cooked == 1 and plain.data.state.stats.ore_home == false, "the opening-stage save has meals and Ada's cooking, but no ore home")
	var bare: Dictionary = raw.duplicate(true)
	for r in bare.state.residents:
		r.jobs.cook.xp = 0
	for k in bare.state.maps.village.items.keys():
		if bare.state.maps.village.items[k].type in Defs.MEALS:
			bare.state.maps.village.items.erase(k)
	var none := SaveFormat.upgrade(bare)
	check(none.data.state.stats.meals_cooked == 0 and none.data.state.stats.ore_home == false, "with no cooking and no meals, nothing is counted")
	var rich: Dictionary = raw.duplicate(true)
	rich.state.maps.village.items[Vector2i(0, 0)] = {"cell": Vector2i(0, 0), "type": "iron_ingot", "n": 2, "res": 0}
	rich.state.maps.village.items[Vector2i(1, 0)] = {"cell": Vector2i(1, 0), "type": "bread", "n": 3, "res": 0}
	var up := SaveFormat.upgrade(rich)
	check(up.data.state.stats.meals_cooked == 1 and up.data.state.stats.ore_home == true, "a village with iron and bread on hand counts as having cooked and brought ore home")
	var sim := Sim.from_state(up.data.state)
	check(Goals.village_done(sim, 1) and Goals.village_done(sim, 3), "so those two chapter goals are done")


## Issue #196: walking packs the village's ground into paths, which grow back when nobody walks them.
func test_worn_paths_wear_and_regrow() -> void:
	var sim := Sim.new_game()
	var c: Vector2i = sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(3, 3))
	var rev := sim.rev
	for i in Tuning.WEAR_WORN - 1:
		sim._wear_step(c)
	check(sim.path_stage(c) == 0 and sim.rev == rev, "%d steps leave it grass, and the ground isn't redrawn (rev %d)" % [Tuning.WEAR_WORN - 1, sim.rev - rev])
	sim._wear_step(c)
	check(sim.path_stage(c) == 1 and sim.rev == rev + 1, "step %d makes it worn grass, and redraws once" % Tuning.WEAR_WORN)
	for i in Tuning.WEAR_DIRT - Tuning.WEAR_WORN:
		sim._wear_step(c)
	check(sim.path_stage(c) == 2 and absf(sim.path_speed(c) - Tuning.PATH_SPEED_DIRT) < 0.001, "%d wear is a dirt path, a little quicker" % Tuning.WEAR_DIRT)
	for i in Tuning.WEAR_PACKED - Tuning.WEAR_DIRT:
		sim._wear_step(c)
	check(sim.path_stage(c) == 3 and absf(sim.path_speed(c) - Tuning.PATH_SPEED_PACKED) < 0.001, "%d wear is a packed path, quicker still" % Tuning.WEAR_PACKED)
	for i in 200:
		sim._wear_step(c)
	check(sim.m.wear[c] == Tuning.WEAR_CAP, "wear stops at the cap (%d)" % sim.m.wear[c])
	# A cell nobody walks on loses wear, never below zero; one that's walked holds.
	var other: Vector2i = c + Vector2i(1, 0) if sim.walkable(c + Vector2i(1, 0)) else c + Vector2i(0, 1)
	sim._wear_step(other)
	sim.m.wear_touched = {}
	sim._wear_step(c)  # walked this pass, so it holds
	sim._decay_wear()
	check(sim.m.wear[c] == Tuning.WEAR_CAP and not sim.m.wear.has(other), "a walked cell holds, an unwalked one with 1 wear is gone")
	sim._decay_wear()
	check(sim.m.wear[c] == Tuning.WEAR_CAP - 1, "and once nobody walks it, it loses 1 a pass")
	for i in 150:
		sim._decay_wear()
	check(not sim.m.wear.has(c) and sim.path_stage(c) == 0, "it grows back to grass and is forgotten, never below zero")
	# The decay runs by itself.
	sim._wear_step(c)
	sim.m.wear_touched = {}
	var every := int(Tuning.WEAR_DECAY_SECS * Tuning.TPS)
	sim.tick = every - 1
	sim.step()
	check(not sim.m.wear.has(c), "the sim decays wear every %d s" % int(Tuning.WEAR_DECAY_SECS))
	# What doesn't wear: a stockpile, a farm, a building; building on a path clears it.
	var z: Vector2i = sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(5, 0))
	sim.m.zone[z] = true
	sim._wear_step(z)
	check(not sim.m.wear.has(z), "a stockpile cell doesn't wear")
	var f: Vector2i = sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(0, 6))
	sim.paint_farm(Rect2i(f, Vector2i.ONE))
	sim._wear_step(f)
	check(not sim.m.wear.has(f), "a farm plot doesn't wear")
	var spot := open_cell_for(sim, Vector2i(1, 1))
	for i in 40:
		sim._wear_step(spot)
	check(sim.path_stage(spot) == 2, "a path forms")
	var rev2 := sim.rev
	sim.place_site("bench", spot)
	check(not sim.m.wear.has(spot) and sim.rev > rev2, "putting a building on it clears the wear under it")
	var zr := open_cell_for(sim, Vector2i(1, 1))
	for i in 12:
		sim._wear_step(zr)
	sim.paint_zone(Rect2i(zr, Vector2i.ONE))
	check(not sim.m.wear.has(zr), "so does painting a stockpile over it")
	# Only the village wears: site maps and the road don't.
	var mine_worn: bool = sim.on_map("old_mine", func():
		sim._wear_step(Vector2i(1, 1))
		return not sim.m.wear.is_empty())
	check(not mine_worn, "the old mine doesn't wear")
	var road_worn: bool = sim.on_map(Road.ID, func():
		sim._wear_step(Vector2i(2, Road.LINE_ROW))
		return not sim.m.wear.is_empty())
	check(not road_worn, "nor does the road")
	# Walking does it: a resident who walks about wears the ground.
	var walk := Sim.new_game()
	walk.designate_mine(Rect2i(0, 0, walk.w, walk.h))
	run(walk, 120.0)
	check(not walk.m.wear.is_empty(), "two minutes of the opening leave worn ground (%d cells)" % walk.m.wear.size())


## Issue #196: residents prefer a path that's a little longer but quicker, and a worn path walks faster.
func test_worn_paths_pathing_and_speed() -> void:
	var sim := _bare_ground()
	var a := Vector2i(8, 8)
	var b := a + Vector2i(8, 0)
	var straight: Array = sim.find_path(a, {b: true})
	check(straight.size() == 8 and straight.all(func(c): return c.y == a.y), "on bare grass the shortest path is straight (%d steps)" % straight.size())
	# A packed row one cell off the line: two steps longer, but quicker.
	for x in range(a.x, b.x + 1):
		sim.m.wear[Vector2i(x, a.y + 1)] = Tuning.WEAR_CAP
	var via: Array = sim.find_path(a, {b: true})
	check(via.size() == 10 and via.any(func(c): return c.y == a.y + 1), "a path two steps longer but packed is taken (%d steps)" % via.size())
	var cost := 0.0
	for c in via:
		cost += 1.0 / sim.path_speed(c)
	check(cost < 8.0, "and it really is quicker (%.2f against 8)" % cost)
	# Too long a detour isn't worth it.
	sim.m.wear.clear()
	for x in range(a.x, b.x + 1):
		sim.m.wear[Vector2i(x, a.y + 2)] = Tuning.WEAR_CAP
	var far: Array = sim.find_path(a, {b: true})
	check(far.size() == 8 and far.all(func(c): return c.y == a.y), "a detour of four more steps stays on the grass (%d steps)" % far.size())
	check(sim.find_path(a, {a: true}).is_empty(), "no path is needed to where you stand")
	var shut := Sim.new_game()
	check(shut.find_path(Sim.rcell(shut.residents[0]), {Vector2i(-5, -5): true}) == null, "an unreachable goal is still null, worn paths or not")
	# Walking speed multiplies: a path on the ford is still slow, but quicker than the ford alone.
	var ford := a
	sim.m.water[ford] = true
	check(absf(sim.ground_speed(ford) - Tuning.FORD_SPEED) < 0.001, "wading is slow")
	sim.m.wear[ford] = Tuning.WEAR_CAP
	check(absf(sim.ground_speed(ford) - Tuning.FORD_SPEED * Tuning.PATH_SPEED_PACKED) < 0.001, "path speed multiplies with the ford's")
	# The same walk takes fewer ticks on a path.
	var s1 := _bare_ground()
	var s2 := _bare_ground()
	var from := Vector2i(6, 8)
	var to := from + Vector2i(13, 0)
	for x in range(from.x, to.x + 1):
		s2.m.wear[Vector2i(x, from.y)] = Tuning.WEAR_CAP
	var t1 := _ticks_to_walk(s1, from, to)
	var t2 := _ticks_to_walk(s2, from, to)
	check(t2 < t1 and float(t2) / t1 < 0.9, "a packed path is walked in fewer ticks (%d against %d)" % [t2, t1])


## A new game with every tree and boulder cleared, for tests that need open ground.
func _bare_ground() -> Sim:
	var sim := Sim.new_game()
	sim.m.trees = []
	sim.m.boulders = []
	sim.m.bushes = []
	sim.m.occ_dirty = true
	return sim


func _ticks_to_walk(sim: Sim, from: Vector2i, to: Vector2i) -> int:
	var ada: Dictionary = sim.residents[0]
	ada.pos = Vector2(from)
	var job := Job.new("move", "Walking", "")
	job.step({"op": "goto", "cells": [to], "adj": false, "planned": false})
	ada.job = job
	ada.hunger = 100.0
	var n := 0
	while ada.job == job and n < 2000:
		sim.step()
		ada.hunger = 100.0
		n += 1
	return n


## Issue #196: the wear is saved with the village, and older saves start on bare grass.
func test_worn_paths_saved() -> void:
	var sim := Sim.new_game()
	var c: Vector2i = sim.nearest_walkable(Sim.rcell(sim.residents[0]) + Vector2i(3, 3))
	for i in 35:
		sim._wear_step(c)
	var back := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(back.m.wear.get(c, 0) == 35 and back.path_stage(c) == 2, "the wear is saved and loaded (%d)" % back.m.wear.get(c, 0))
	var raw: Dictionary = str_to_var(FileAccess.get_file_as_string("res://tests/fixtures/save_v30.save"))
	var up := SaveFormat.upgrade(raw)
	check(not up.has("error") and up.data.state.maps.village.wear.is_empty(), "an older save starts on bare grass")
	var old := Sim.from_state(up.data.state)
	check(old.m.wear.is_empty(), "and loads")
	# A claim on the north or west edge moves the wear with everything else.
	var big := Sim.new_game()
	big.m.wear[Vector2i(4, 5)] = 50
	big.m.grow("north", 8)
	check(big.m.wear.has(Vector2i(4, 13)) and not big.m.wear.has(Vector2i(4, 5)), "growing the map shifts the wear")


## Issue #203: a workstation's work area is painted cells, which start as the old circle.
func test_work_areas_are_painted() -> void:
	var sim := Sim.new_game()
	var block := place_done(sim, "chopping_block")
	block.make_keep = 0
	var circle := 0
	var all_in := true
	for x in sim.w:
		for y in sim.h:
			var c := Vector2i(x, y)
			var near := Vector2(c).distance_to(Vector2(block.origin)) <= Tuning.WORK_START_RADIUS
			circle += 1 if near else 0
			all_in = all_in and (near == block.area.has(c))
	check(all_in and block.area.size() == circle and circle > 100, "a new workstation starts with the old circle (%d cells)" % block.area.size())
	# Reach: cells past WORK_REACH stay unpainted, and the count says how many.
	var far: Vector2i = block.origin + Vector2i(int(Tuning.WORK_REACH) + 1, 0)
	var near_edge: Vector2i = block.origin + Vector2i(int(Tuning.WORK_REACH) - 1, 0)
	if sim.m.in_bounds(far) and sim.m.in_bounds(near_edge):
		var left := sim.paint_work_area(block, Rect2i(near_edge, Vector2i(3, 1)))
		check(block.area.has(near_edge) and not block.area.has(far) and left >= 1, "a cell past %d cells away isn't painted (%d left out)" % [int(Tuning.WORK_REACH), left])
	# Gatherers read the painted cells: a tree just outside is left alone, and felled once it's painted.
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], sim.nearest_walkable(block.origin + Vector2i(0, 2)))
	sim.set_role(tomas, "lumber")
	tomas.axe = {"type": "stone_axe", "tier": 2, "dur": 999}
	var trees: Array = sim.trees.filter(func(t): return t.alive and Sim.in_area(block, t.cell) and Sim.grown(t) and not sim.protected(t))
	check(trees.size() >= 2, "there are trees in the starting area (%d)" % trees.size())
	var t0: Dictionary = trees[0]
	sim.paint_work_area(block, Rect2i(t0.cell, Vector2i.ONE), true)
	check(not Sim.in_area(block, t0.cell) and not sim.auto_targets([block]).any(func(t): return is_same(t, t0)), "a tree just outside the painted area isn't a target")
	sim.paint_work_area(block, Rect2i(t0.cell, Vector2i.ONE))
	check(sim.auto_targets([block]).any(func(t): return is_same(t, t0)), "and is again once its cell is painted")
	# Erase the whole area: nothing to do, and the stuck list says so.
	sim.paint_work_area(block, Rect2i(0, 0, sim.w, sim.h), true)
	check(block.area.is_empty() and sim.auto_targets([block]).is_empty(), "with the area erased there are no targets")
	sim.compute_stuck()
	check(stuck_text(sim).contains("No trees in the chopping block's area"), "and the stuck list says so: " + stuck_text(sim))
	# Saplings are planted only in the painted cells.
	var spot: Vector2i = sim.nearest_walkable(block.origin + Vector2i(2, 2))
	sim.paint_work_area(block, Rect2i(spot, Vector2i(2, 2)))
	var planted = sim.plant_cell([block], spot)
	check(planted == null or Sim.in_area(block, planted), "a sapling goes only in the painted cells (%s)" % [planted])
	# One owner per kind: a second block starts without the first's cells, and painting takes them.
	check(block.area.has(spot), "(the painted cell is the first block's)")
	var second := place_done(sim, "chopping_block")
	check(second.area.keys().all(func(c): return not block.area.has(c)), "a second chopping block starts without the first one's cells")
	var shared := spot
	sim.paint_work_area(second, Rect2i(shared, Vector2i.ONE))
	check(second.area.has(shared) and not block.area.has(shared), "painting a cell another block owns moves it")
	# A different kind of station may overlap: a mason's bench keeps its own.
	var mason := place_done(sim, "mason_bench")
	sim.paint_work_area(mason, Rect2i(shared, Vector2i.ONE))
	check(mason.area.has(shared) and second.area.has(shared), "a mason's bench can share a cell with a chopping block")
	# A painted area may lie over a stockpile: lumberjacks still plant nothing there.
	sim.paint_zone(Rect2i(shared, Vector2i.ONE))
	check(sim.protected_cell(shared) and second.area.has(shared), "a work area can lie over a stockpile, which stays protected")


## Issue #203: a work area is saved with its workstation, and older saves get the circle they worked.
func test_work_areas_saved() -> void:
	var sim := Sim.new_game()
	var block := place_done(sim, "chopping_block")
	sim.paint_work_area(block, Rect2i(block.origin, Vector2i(1, 1)), true)
	var back := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	var again: Dictionary = back.sites.filter(func(st): return st.tpl == "chopping_block")[0]
	check(again.area.size() == block.area.size() and not again.area.has(block.origin), "the painted area is saved and loaded (%d cells)" % again.area.size())
	var raw := {"state": {"maps": {"village": {"w": 32, "h": 32, "sites": [
		{"tpl": "chopping_block", "origin": Vector2i(10, 10)},
		{"tpl": "chopping_block", "origin": Vector2i(15, 10)},
		{"tpl": "mason_bench", "origin": Vector2i(10, 10)},
		{"tpl": "bench", "origin": Vector2i(2, 2)}]}}}}
	var up := SaveFormat._v31_to_v32(raw)
	var sites: Array = up.state.maps.village.sites
	var circle := 0
	for x in range(2, 19):
		for y in range(2, 19):
			circle += 1 if Vector2(x, y).distance_to(Vector2(10, 10)) <= 8.0 else 0
	check(sites[0].area.size() == circle and sites[2].area.size() == circle and not sites[3].has("area"), "an older village's blocks and benches get their old circle (%d cells)" % sites[0].area.size())
	check(sites[1].area.keys().all(func(c): return not sites[0].area.has(c)) and sites[1].area.size() > 0, "an overlap stays with the older block")
	# Growing the map shifts the areas with it.
	var big := Sim.new_game()
	var b2 := place_done(big, "chopping_block")
	var c0: Vector2i = b2.origin
	big.m.grow("north", 8)
	check(b2.area.has(b2.origin) and b2.origin == c0 + Vector2i(0, 8), "growing the map shifts the area with its station")


## Issue #204: once every boulder on the village map is gone, a mason's bench is dug out into a
## mineshaft, which digs cobblestone slowly from where it stands.
func test_mason_bench_becomes_a_mineshaft() -> void:
	var sim := Sim.new_game()
	var bench := place_done(sim, "mason_bench")
	check(Sim.station_name(bench) == "Mason's bench" and bench.get("shaft", null) == null, "a new mason's bench is a bench")
	check(sim.shaft_check(bench).begins_with("Not while boulders are left"), "not while boulders are left: " + sim.shaft_check(bench))
	check(not sim.upgrade_to_shaft(bench) and bench.done, "so the upgrade doesn't start")
	# Every boulder on the map gone: the bricks are what's left to ask for.
	for b in sim.boulders:
		b.alive = false
	sim._occ_dirty = true
	check(sim.shaft_check(bench).begins_with("Cut %d more stone bricks" % Tuning.SHAFT_COST.stone_brick), "then it asks for the stone bricks first: " + sim.shaft_check(bench))
	sim.paint_zone(open_rect(sim, Vector2i(4, 4)))
	var zc: Vector2i = sim.zone.keys()[0]
	sim.drop_items(zc, "stone_brick", Tuning.SHAFT_COST.stone_brick)
	sim.drop_items(sim.zone.keys()[1], "plank", Tuning.SHAFT_COST.plank + 4)
	check(sim.shaft_check(bench) == "", "with the bricks in stock it can start")
	var queue_before: Array = bench.queue.duplicate()
	check(sim.upgrade_to_shaft(bench) and not bench.done and bench.upgrading and Sim.station_name(bench) == "Mineshaft", "the upgrade starts, and the bench is rebuilt as a mineshaft")
	check(sim.current_stage(bench).cost == Tuning.SHAFT_COST, "it asks for the planks and stone bricks of the upgrade")
	run(sim, 150.0)
	check(bench.done and bench.get("shaft", false) and not bench.get("upgrading", false), "builders finish it (done %s)" % bench.done)
	check(bench.queue == queue_before and bench.has("area"), "it keeps its queue and its work area")
	check(sim.shaft_check(bench) == "It's already a mineshaft", "and can't be dug out twice")
	# A stonemason digs: slowly, a cobblestone at a time, onto the pile beside it.
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], sim.nearest_walkable(bench.origin + Vector2i(0, 2)))
	sim.set_role(tomas, "mason")
	tomas.pick = {"type": "stone_pick", "tier": 2, "dur": 999}
	bench.make_keep = 0
	bench.keep = 40
	for s in sim.sites:  # nothing else keeps him busy
		if s.has("worker") and not is_same(s, bench) and s.worker == tomas.id:
			s.worker = 0
	sim.assign_workstations()
	var cobble_before: int = sim.free_count("cobble")
	run(sim, 120.0)
	var dug: int = sim.free_count("cobble") - cobble_before
	var most: int = int(120.0 / Tuning.SHAFT_DIG)
	check(dug >= most / 2 and dug <= most, "he digs about one cobblestone every %d s (%d in 2 minutes)" % [int(Tuning.SHAFT_DIG), dug])
	check(float(dug) / 120.0 < float(Tuning.BOULDER_COBBLE) / Tuning.BREAK_TIME[2] / 2.0, "which is a floor, much slower than breaking boulders")
	check(sim.pile_count(bench) > 0, "onto the pile beside the shaft (%d)" % sim.pile_count(bench))
	check(tomas.pick.dur < 999, "digging wears his pickaxe")
	# Stops at the target.
	bench.keep = sim.free_count("cobble")
	var held := sim.free_count("cobble")
	run(sim, 60.0)
	check(sim.free_count("cobble") <= held + 1, "he stops when the village has what it keeps (%d, then %d)" % [held, sim.free_count("cobble")])
	# Saved with the bench.
	var back := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	var again: Dictionary = back.sites.filter(func(st): return st.tpl == "mason_bench")[0]
	check(again.get("shaft", false) and Sim.station_name(again) == "Mineshaft", "a mineshaft is saved and loaded")
	var raw: Dictionary = str_to_var(FileAccess.get_file_as_string("res://tests/fixtures/save_v32.save"))
	check(not SaveFormat.upgrade(raw).has("error"), "a v32 save upgrades")


## Issue #185: a plan carries a ranked list of what to bring back; each place starts from its defaults and
## then remembers the last list used.
func test_cargo_priority_list_plans() -> void:
	var sim := Sim.new_game()
	var board := built_board(sim)
	var plan := sim.new_plan(OldMine.ID)
	var items: Array = plan.list.map(func(r): return r.item)
	check(items == ["coal", "cobble"] and plan.list[0].n == 8 and plan.list[1].n == 0, "the old mine starts with coal then cobblestone as much as fits, iron unknown yet (%s)" % [items])
	var mead := sim.new_plan(Meadow.ID)
	check(mead.list.map(func(r): return r.item) == ["wool", "leather", "beef", "porkchop", "mutton"] and mead.list[0].n == 6, "the meadow starts with wool, leather, then meat")
	check(plan.target == {"item": "coal", "n": 8}, "the old single target is the first row with an amount")
	# A row can be turned off, and an amount of 0 is as much as fits.
	plan.list[0].on = false
	Sim.sync_target(plan)
	check(Sim.cargo_rows(plan).map(func(r): return r.item) == ["cobble"] and plan.target.item == "cobble", "an item that's off is left, and the target follows the list")
	plan.list[1].on = false
	plan.party = [sim.residents[0].id]
	check(sim.plan_problems(plan).has("Choose something to bring back"), "with nothing on, the plan says so: %s" % [sim.plan_problems(plan)])
	# Reordering, then confirming: the next plan for the place starts from that list.
	plan.list[0].on = true
	plan.list[1].on = true
	var first: Dictionary = plan.list[0]
	plan.list[0] = plan.list[1]
	plan.list[1] = first
	plan.list[0].n = 5
	plan.list[1].n = 6
	Sim.sync_target(plan)
	plan.picks = 0
	var confirmed := sim.plan_expedition(plan)
	check(confirmed == "", "the plan is confirmed (%s)" % confirmed)
	check(sim.cargo_lists[OldMine.ID].map(func(r): return r.item) == ["cobble", "coal"] and sim.cargo_lists[OldMine.ID][0].n == 5, "the place remembers the list")
	sim.expedition = {}
	var again := sim.new_plan(OldMine.ID)
	check(again.list.map(func(r): return r.item) == ["cobble", "coal"] and again.list[0].n == 5, "and the next plan starts from it")
	# A newly known item joins at the bottom, marked New.
	sim.get_map(OldMine.ID).discovered = true
	var learned := sim.new_plan(OldMine.ID)
	check(learned.list.map(func(r): return r.item) == ["cobble", "coal", "iron_ore"] and learned.list[2].get("new", false) and learned.list[2].n == 0, "iron, once known, joins at the bottom marked New (%s)" % [learned.list.map(func(r): return r.item)])
	# Target reached counts only the rows with an amount that are on.
	sim.expedition = {"target": {"item": "coal", "n": 3}, "cargo": {"coal": 3}, "list": [{"item": "coal", "on": true, "n": 3}, {"item": "cobble", "on": true, "n": 0}, {"item": "iron_ore", "on": false, "n": 5}]}
	check(sim.objective_met(), "target reached once the rows with an amount are packed, whatever as-much rows hold or off rows want")
	sim.expedition.cargo = {"coal": 2}
	check(not sim.objective_met(), "not before")
	sim.expedition.list = [{"item": "coal", "on": true, "n": 0}]
	check(not sim.objective_met(), "a list of as-much-as-fits rows is never reached: the packs filling is what ends it")
	sim.expedition = {}
	# An old save's trip in progress turns its single target into a one-row list.
	var raw := {"state": {"expedition": {"dest": "old_mine", "state": "out", "target": {"item": "coal", "n": 5}}}}
	var up := SaveFormat._v33_to_v34(raw)
	check(up.state.expedition.list == [{"item": "coal", "on": true, "n": 5}, {"item": "iron_ore", "on": true, "n": 0}, {"item": "cobble", "on": true, "n": 0}] and up.state.cargo_lists == {}, "an old trip's target becomes a one-row list with the rest as much as fits (%s)" % [up.state.expedition.get("list")])
	var pens := {"state": {"expedition": {"dest": "meadow", "state": "out", "target": {"item": "pens", "n": 2}}}}
	check(not SaveFormat._v33_to_v34(pens).state.expedition.has("list"), "and a pen-tending trip needs none")
	var back := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(back.cargo_lists == sim.cargo_lists, "the remembered lists are saved")


## Issue #185: at the site the party packs by the list, swaps a better find in for the lowest cargo, never packs
## what's off, and marks down the list.
func test_cargo_priority_list_at_the_site() -> void:
	var sim := Sim.new_game()
	var p := send_party(sim)
	until_at_site(sim, [p.ada, p.tomas])
	var ex: Dictionary = sim.expedition
	ex.policy = {"target": false, "full": false, "low": false}
	# Packing follows the order: cobblestone before coal, and the packs full of coal.
	ex.list = [{"item": "cobble", "on": true, "n": 0}, {"item": "coal", "on": true, "n": 0}]
	Sim.sync_target(ex)
	ex.cargo = {"coal": sim.pack_room()}
	check(sim.pack_room() == 0 and not sim.swap_candidate().is_empty() == false, "the packs are full of coal")
	sim.on_map(OldMine.ID, func(): sim.drop_items(sim.nearest_walkable(sim.m.entrance + Vector2i(2, 0)), "cobble", 3))
	var swap: Dictionary = sim.on_map(OldMine.ID, func(): return sim.swap_candidate())
	check(not swap.is_empty() and swap.drop == "coal" and swap.stack.type == "cobble", "a better find would swap out the lowest cargo (%s)" % [swap.get("drop", "")])
	run(sim, 90.0)
	check(ex.cargo.get("cobble", 0) >= 3, "the party packs the cobblestone (%s)" % [ex.cargo])
	check(sim.on_map(OldMine.ID, func(): return count(sim, "coal")) > 0, "and the coal it swapped out is left at the site as a stack")
	# What's off is never packed, and several on are all packed.
	var sim2 := Sim.new_game()
	var p2 := send_party(sim2)
	until_at_site(sim2, [p2.ada, p2.tomas])
	var ex2: Dictionary = sim2.expedition
	ex2.policy = {"target": false, "full": false, "low": false}
	ex2.list = [{"item": "coal", "on": true, "n": 2}, {"item": "cobble", "on": false, "n": 0}, {"item": "iron_ore", "on": true, "n": 2}]
	Sim.sync_target(ex2)
	sim2.on_map(OldMine.ID, func():
		sim2.drop_items(sim2.nearest_walkable(sim2.m.entrance + Vector2i(2, 0)), "cobble", 3)
		sim2.drop_items(sim2.nearest_walkable(sim2.m.entrance + Vector2i(3, 1)), "coal", 2)
		sim2.drop_items(sim2.nearest_walkable(sim2.m.entrance + Vector2i(4, 0)), "iron_ore", 2)
		for b in sim2.boulders:
			b.des = false)
	ex2.cargo = {}
	run(sim2, 60.0)
	check(ex2.cargo.get("coal", 0) >= 2 and ex2.cargo.get("iron_ore", 0) >= 2, "several rows on are all packed (%s)" % [ex2.cargo])
	check(ex2.cargo.get("cobble", 0) == 0, "an item that's off is never packed (%s)" % [ex2.cargo])
	# Marking goes down the list: the row with an amount first, the next once it's packed.
	var sim3 := Sim.new_game()
	var p3 := send_party(sim3)
	until_at_site(sim3, [p3.ada, p3.tomas])
	var ex3: Dictionary = sim3.expedition
	ex3.list = [{"item": "coal", "on": true, "n": 3}, {"item": "cobble", "on": true, "n": 0}]
	Sim.sync_target(ex3)
	ex3.cargo = {}
	sim3.on_map(OldMine.ID, func():
		for b in sim3.boulders:
			b.des = false
		sim3._mark_objective())
	var marked_a: Array = sim3.on_map(OldMine.ID, func(): return sim3.boulders.filter(func(b): return b.alive and b.des))
	check(not marked_a.is_empty() and marked_a.any(func(b): return b.get("ore", "") == "coal" or not b.has("ore")), "with coal short, what's marked is toward the coal (%d marked)" % marked_a.size())
	ex3.cargo = {"coal": 3}
	sim3.on_map(OldMine.ID, func():
		for b in sim3.boulders:
			b.des = false
		sim3._mark_objective())
	var marked_b: Array = sim3.on_map(OldMine.ID, func(): return sim3.boulders.filter(func(b): return b.alive and b.des))
	check(not marked_b.is_empty() and marked_b.all(func(b): return not b.has("ore")), "with the coal packed, the next row's stone is what's marked (%d)" % marked_b.size())


## Issue #188: a "Clear the level" trip works every block of what's on the list, then digs to the door by itself and
## goes down with no pause, the objective carried over.
func test_clear_the_level() -> void:
	var sim := Sim.new_game()
	var plan := sim.new_plan(OldMine.ID)
	check(plan.clear == false and Sim.list_text(plan) == "8 coal", "a new plan isn't a clearing one (%s)" % Sim.list_text(plan))
	plan.clear = true
	check(Sim.list_text(plan) == "clear the level" and Sim.cargo_rows(plan).all(func(r): return r.n == 0), "clearing wants all of it: every amount is as much as fits")
	var p := send_party(sim)
	until_at_site(sim, [p.ada, p.tomas])
	var ex: Dictionary = sim.expedition
	ex.clear = true
	ex.policy = {"target": false, "full": false, "low": false}
	check(not sim.objective_met() and sim.objective_left() == 0, "there's no target to reach")
	# With coal already packed, an ordinary trip moves on down its list; a clearing one keeps going for coal.
	ex.cargo = {"coal": 99}
	sim.on_map(OldMine.ID, func():
		for b in sim.boulders:
			b.des = false
		sim._mark_objective())
	var marked: Array = sim.on_map(OldMine.ID, func(): return sim.boulders.filter(func(b): return b.alive and b.des))
	check(not marked.is_empty() and marked.any(func(b): return b.get("ore", "") == "coal"), "clearing keeps marking coal past any amount (%d marked)" % marked.size())
	check(marked.all(func(b): return not b.get("loose", false)), "and never a block under a known loose ceiling")
	var left: int = sim.on_map(OldMine.ID, func(): return sim.level_left())
	check(left > 0 and left == sim.on_map(OldMine.ID, func(): return sim.boulders.filter(func(b): return b.alive and not b.get("hidden", false) and not b.get("loose", false)).size()), "the blocks left on the level are the ones the list asks for (%d)" % left)
	# The level is cleared: no pause for the door, the party goes down with its packs.
	sim.on_map(OldMine.ID, func():
		for b in sim.boulders:
			if not b.get("loose", false):
				b.alive = false
		sim._occ_dirty = true)
	ex.cargo = {}
	run(sim, 120.0)
	var down := MineLevels.level_id(2)
	check(sim.pending.is_empty() and ex.dest == down, "a cleared level goes down with no choice to make (dest %s, pending %d)" % [ex.dest, sim.pending.size()])
	check(ex.get("clear", false) and ex.get("leg", "out") == "out", "and carries on, still clearing")
	var back := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	check(back.expedition.get("clear", false), "a clearing trip is saved")

	# The packs, not the level, end it: full packs still send them home.
	sim.on_map(down, func():
		sim.m.known = true)
	ex.policy.full = true
	ex.cargo = {"coal": sim.pack_room()}
	run(sim, 150.0)  # once they're all down on the new level
	check(ex.get("leg", "") == "home" and ex.get("home_why", "") == "packs full", "full packs still bring them home (%s)" % ex.get("home_why", ""))
	# Without it, the door still asks.
	var sim2 := Sim.new_game()
	var p2 := send_party(sim2)
	until_at_site(sim2, [p2.ada, p2.tomas])
	sim2.expedition.policy = {"target": false, "full": false, "low": false}
	sim2.on_map(OldMine.ID, func():
		for b in sim2.boulders:
			if not b.get("loose", false):
				b.alive = false
		sim2._occ_dirty = true)
	run(sim2, 120.0)
	check(not sim2.pending.is_empty() and sim2.pending[0].kind == "door", "an ordinary trip still stops for the door choice")
	# Saving: an older save's trip isn't a clearing one.
	var up := SaveFormat._v34_to_v35({"state": {"expedition": {"dest": "old_mine"}}})
	check(up.state.expedition.clear == false, "an older save's trip isn't a clearing one")


## Issue #186: diamond ore on the deep levels, hidden until someone mines next to it, mined only with an iron
## pickaxe, made into the best tools.
func test_diamonds_deep_in_the_mine() -> void:
	var sim := Sim.new_game()
	for n in range(1, 4):
		check(MineLevels.deep_ore_count(n, "diamond") == 0 and not "".join(MineLevels.layout(sim.seed, n).rows).contains("d"), "no diamond ore on level %d" % n)
	check(MineLevels.deep_ore_count(4, "diamond") == 1 and MineLevels.deep_ore_count(6, "diamond") == 2 and MineLevels.deep_ore_count(20, "diamond") == 3, "from level 4: 1 block, more the deeper, 3 at most")
	for n in range(4, 9):
		var a: Dictionary = MineLevels.layout(sim.seed, n)
		var b: Dictionary = MineLevels.layout(sim.seed, n)
		var count: int = "".join(a.rows).count("d")
		check(count == MineLevels.deep_ore_count(n, "diamond") and a.rows == b.rows, "level %d has its %d diamonds, the same every time" % [n, count])
	var lvl: SimMap = MineLevels.build(sim, 4)
	var rocks: Array = lvl.boulders.filter(func(x): return x.get("ore", "") == "diamond")
	check(rocks.size() == 1 and rocks.all(func(x): return x.get("hidden", false)), "level 4's diamond is hidden like the vein")
	sim.maps[lvl.id] = lvl
	lvl.visited = true
	check(not sim.site_report(lvl.id).resources.any(func(x): return x.item == "diamond"), "and not in the site report until it's found")
	check(sim.get_map(lvl.id).level == 4, "(level 4)")
	# An iron pickaxe is needed.
	var ada: Dictionary = sim.residents[0]
	var block: Dictionary = rocks[0]
	var st := {"what": "gather", "tool": "pick", "target": block}
	ada.pick = {"type": "stone_pick", "tier": 2, "dur": 10}
	check(sim._work_time(ada, st) < 0.0, "a stone pickaxe can't mine diamond ore")
	ada.pick = {"type": "iron_pick", "tier": 3, "dur": 10}
	check(absf(sim._work_time(ada, st) - Tuning.BREAK_TIME[3]) < 0.01, "an iron pickaxe can")
	ada.pick = {"type": "diamond_pick", "tier": 4, "dur": 10}
	check(sim._work_time(ada, st) < Tuning.BREAK_TIME[3], "and a diamond one is quicker")
	# The first find: revealed, a known resource of the level, and the game stops.
	sim.expedition = {"state": "out", "leg": "out", "dest": lvl.id, "party": [ada.id], "target": {"item": "coal", "n": 1}, "list": [{"item": "coal", "on": true, "n": 1}], "cargo": {}, "policy": {"target": true, "full": true, "low": true}}
	var near: Vector2i = block.cell + Vector2i(0, 1)
	sim.on_map(lvl.id, func(): sim._check_find_diamond(near))
	check(not sim.pending.is_empty() and sim.pending[0].kind == "discovery" and "diamonds on level 4" in sim.pending[0].text, "the first find stops the game: %s" % [sim.pending[0].text if not sim.pending.is_empty() else ""])
	check(lvl.diamond_found and not block.get("hidden", false), "the diamond is revealed")
	check(sim.site_report(lvl.id).resources.any(func(x): return x.item == "diamond" and x.known) and sim.plan_targets(lvl.id).any(func(x): return x.item == "diamond"), "diamonds are a known resource of the level, a row for the cargo list")
	sim.pending.clear()
	sim.on_map(lvl.id, func(): sim._check_find_diamond(near))
	check(sim.pending.is_empty(), "it only stops for the first")
	# Nobody with an iron pickaxe: it's said, and nothing is marked for diamonds.
	sim.expedition.list = [{"item": "diamond", "on": true, "n": 0}]
	ada.pick = {"type": "stone_pick", "tier": 2, "dur": 10}
	check(not sim.can_mine_diamond(), "no iron pickaxe in the party")
	sim.on_map(lvl.id, func():
		sim.compute_stuck()
		for sx in sim.stuck:
			pass)
	ada.map = lvl.id
	ada.arriving = false
	sim.on_map(lvl.id, func(): sim._stuck_site())
	check(sim.stuck.any(func(x): return x.why == "Diamond ore needs an iron pickaxe"), "the stuck list says what's missing: " + stuck_text(sim))
	ada.pick = {"type": "iron_pick", "tier": 3, "dur": 10}
	check(sim.can_mine_diamond(), "with an iron pickaxe it can be mined")
	sim.expedition = {}
	# A party on level 4 with an iron pickaxe mines the diamond and packs it.
	ada.pick = {"type": "iron_pick", "tier": 3, "dur": 40}
	sim._enter_level(ada, lvl.id)
	sim.expedition = {"state": "out", "leg": "out", "dest": lvl.id, "party": [ada.id], "target": {"item": "diamond", "n": 1}, "list": [{"item": "diamond", "on": true, "n": 1}],
		"cargo": {}, "provisions": {"bread": 3}, "tools": [], "supplies": {}, "meals": 3, "picks": 0, "sticks": 0, "wheat": 0,
		"policy": {"target": false, "full": false, "low": false}, "spend_return": false, "cart_cap": false, "board": 0, "clear": false}
	for i in 240 * Tuning.TPS:
		sim.step()
		if sim.expedition.get("cargo", {}).get("diamond", 0) >= 1:
			break
	check(sim.expedition.get("cargo", {}).get("diamond", 0) >= 1, "with an iron pickaxe the party mines the diamond and packs it (%s)" % [sim.expedition.get("cargo", {})])
	sim.expedition = {}
	# The recipes, the best tier.
	check(Defs.recipe("diamond_pick").inp == {"diamond": 3, "stick": 2} and Defs.ITEMS.diamond_pick.tier == 4 and Defs.recipe("diamond_axe").inp == {"diamond": 3, "stick": 2}, "diamond tools: 3 diamonds and 2 sticks")
	check(Sim.full_uses("diamond_pick") > Sim.full_uses("iron_pick") and Tuning.BREAK_TIME[4] < Tuning.BREAK_TIME[3], "the most uses and the most speed")
	var vil := Sim.new_game()
	var bench := vil.place_site("bench", open_rect(vil, Vector2i(3, 3)).position + Vector2i(1, 0))
	bench.stage = 1
	bench.done = true
	var cook: Dictionary = vil.residents[0]
	vil.drop_items(Sim.rcell(cook) + Vector2i(1, 0), "diamond", 3)
	vil.drop_items(Sim.rcell(cook) + Vector2i(-1, 0), "stick", 2)
	vil.queue_add(bench, "diamond_pick")
	run(vil, 60.0)
	var made := vil.tool_items("pick", 3)
	check(made.any(func(t): return t.type == "diamond_pick" and t.dur == Sim.full_uses("diamond_pick")), "the bench makes a diamond pickaxe (%s)" % [made.map(func(t): return t.type)])
	# The toolsmith prefers diamond when there's enough.
	var ts := Sim.new_game()
	hire_toolsmith(ts)
	var b2 := ts.place_site("bench", open_rect(ts, Vector2i(3, 3)).position + Vector2i(1, 0))
	b2.stage = 1
	b2.done = true
	ts.residents[0].pick = {"type": "wood_pick", "tier": 1, "dur": 1}
	ts.drop_items(Sim.rcell(ts.residents[0]) + Vector2i(1, 0), "iron_ingot", 3)
	ts.drop_items(Sim.rcell(ts.residents[0]) + Vector2i(-1, 0), "stick", 4)
	ts.drop_items(Sim.rcell(ts.residents[0]) + Vector2i(2, 0), "diamond", 3)
	run(ts, 1)
	check(b2.queue.has("diamond_pick") and not b2.queue.has("iron_pick"), "the toolsmith queues a diamond pickaxe over an iron one (%s)" % [b2.queue])
	var ts2 := Sim.new_game()
	hire_toolsmith(ts2)
	var b3 := ts2.place_site("bench", open_rect(ts2, Vector2i(3, 3)).position + Vector2i(1, 0))
	b3.stage = 1
	b3.done = true
	ts2.residents[0].pick = {"type": "wood_pick", "tier": 1, "dur": 1}
	ts2.drop_items(Sim.rcell(ts2.residents[0]) + Vector2i(1, 0), "iron_ingot", 3)
	ts2.drop_items(Sim.rcell(ts2.residents[0]) + Vector2i(-1, 0), "stick", 4)
	ts2.drop_items(Sim.rcell(ts2.residents[0]) + Vector2i(2, 0), "diamond", 2)
	run(ts2, 1)
	check(b3.queue.has("iron_pick") and not b3.queue.has("diamond_pick"), "with fewer than 3 diamonds it's iron (%s)" % [b3.queue])


## Two expeditions at once (issue #145): a slot for each realm.
func test_expedition_slots() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var other := sim.add_resident("Tomas", "7A5C8F", Sim.rcell(ada) + Vector2i(1, 0))
	check(sim.slot == "overworld" and sim.expedition.is_empty() and sim.expeditions.keys() == ["overworld", "nether"], "two empty slots, the Overworld's current at rest")
	check(Sim.slot_of_dest(OldMine.ID) == "overworld" and Sim.slot_of_dest(MineLevels.level_id(2)) == "overworld" and Sim.slot_of_dest("nether_landing") == "nether", "a destination's realm decides its slot")
	# The current slot is the one `expedition` reads and writes.
	sim.expeditions.nether = {"state": "out", "dest": "nether_landing", "party": [other.id]}
	sim.expedition = {"state": "out", "dest": OldMine.ID, "party": [ada.id]}
	check(sim.on_slot("nether", func(): return sim.expedition.dest) == "nether_landing" and sim.expedition.dest == OldMine.ID, "on_slot reads the other slot and puts the current one back")
	check(sim.slot_of(ada) == "overworld" and sim.slot_of(other) == "nether", "a resident's slot is their party's")
	var seen := []
	sim.each_expedition(func(): seen.append(sim.slot))
	check(seen == ["overworld", "nether"] and sim.slot == "overworld", "each_expedition walks the slots that have a party")
	# A taken slot refuses a plan, with its reason; the other realm's slot is free.
	var plan := {"dest": OldMine.ID, "party": [], "policy": {"target": true}, "target": {"item": "coal", "n": 1}}
	check(sim.plan_problems(plan).has("An Overworld party is already out"), "a second Overworld expedition is refused with a reason")
	plan.dest = "nether_landing"
	check(sim.plan_problems(plan).has("A Nether party is already out"), "and so is a second Nether one")
	plan.rescue = true
	check(not sim.plan_problems(plan).has("A Nether party is already out"), "a rescue sets out although its slot is taken")
	# A resident is in one party only.
	check(sim.cant_join(ada) == "Out with the party" and sim.cant_join(other) == "Out with the party", "residents in a party can't join another")
	# A choice names its expedition, and answering it works that slot.
	sim.on_slot("nether", func(): sim._ask("injury", "Someone is hurt.", [{"id": "press_on", "label": "Press on", "cost": ""}], other.id))
	check(sim.pending[0].slot == "nether", "a pending choice names its slot")
	sim.choose("press_on")
	check(sim.pending.is_empty() and sim.slot == "overworld", "answering it puts the slot back")
	# Saving keeps both.
	var back := Sim.from_state(sim.save_state())
	check(back.expeditions.nether.dest == "nether_landing" and back.expeditions.overworld.dest == OldMine.ID, "both slots survive a save")


## An older save's expedition moves into the Overworld slot (issue #145).
func test_old_expedition_moves_to_the_overworld_slot() -> void:
	var raw := {"v": 36, "state": {"expedition": {"dest": "old_mine", "state": "out", "party": [1]}, "pending": [{"kind": "door", "text": "", "options": [], "res_id": 0, "map": "old_mine"}]}}
	var up: Dictionary = SaveFormat.upgrade(raw).data
	check(up.state.expeditions.overworld.dest == "old_mine" and up.state.expeditions.nether.is_empty() and not up.state.has("expedition"), "the trip is the Overworld's, the Nether's empty")
	check(up.state.pending[0].slot == "overworld", "and so is a waiting choice")
	var fixture := SaveFormat.read("res://tests/fixtures/save_v36.save")
	check(not fixture.has("error") and fixture.data.state.expeditions.nether.is_empty(), "the v36 fixture loads with its expedition in the Overworld slot")


## Gold, gravel and flint, and obsidian beside lava on the deeper levels; flint and steel (issue #146).
func test_deep_mine_materials() -> void:
	var sim := Sim.new_game()
	for ore in ["gold", "gravel", "obsidian"]:
		var ch: String = MineLevels.DEEP_CHARS[ore]
		var first: int = MineLevels.DEEP_ORES[ore].from
		for n in range(1, first):
			check(MineLevels.deep_ore_count(n, ore) == 0 and not "".join(MineLevels.layout(sim.seed, n).rows).contains(ch), "no %s on level %d" % [ore, n])
		for n in range(first, first + 3):
			var rows: Array = MineLevels.layout(sim.seed, n).rows
			var found: int = "".join(rows).count(ch)  # a wide level has little rock beside its floor, so it can hold fewer
			check(found >= 1 and found <= MineLevels.deep_ore_count(n, ore) and rows == MineLevels.layout(sim.seed, n).rows, "level %d has %s, the same every time (%d)" % [n, ore, found])
	check(MineLevels.DEEP_ORES.gold.from == 2 and MineLevels.DEEP_ORES.gravel.from == 3 and MineLevels.DEEP_ORES.obsidian.from == 5, "gold from level 2, gravel from 3, obsidian from 5")
	# The diamonds are where they were: gold, gravel and obsidian leave their layout alone.
	var with_all := "".join(MineLevels.layout(sim.seed, 6).rows).replace("g", "#").replace("v", "#").replace("b", "#").replace("L", "#")
	check(with_all.count("d") == MineLevels.deep_ore_count(6, "diamond"), "level 6 keeps its diamonds")
	# Obsidian has lava beside it, and lava is rock to walk: a pool nobody enters.
	var lvl: SimMap = MineLevels.build(sim, 5)
	for n in range(5, 9):  # a level with a pool: the walls behind the obsidian decide
		lvl = MineLevels.build(sim, n)
		if not lvl.lava.is_empty():
			break
	sim.maps[lvl.id] = lvl
	var obs: Array = lvl.boulders.filter(func(x): return x.get("ore", "") == "obsidian")
	check(obs.size() >= 1 and obs.all(func(x): return not x.get("hidden", false)), "the obsidian is in plain sight")
	var pools := 0
	for lc in lvl.lava:
		pools += 1
		check(lvl.rock.has(lc) and not sim.on_map(lvl.id, func(): return sim.walkable(lc)), "a lava pool is not walkable")
		check(Sim.DIRS.any(func(d): return obs.any(func(x): return x.cell == lc + d)), "and has obsidian beside it")
	check(pools > 0, "a deep level has a lava pool (%d)" % pools)
	var saved := SimMap.from_save(lvl.save())
	check(saved.lava == lvl.lava, "the pools are saved")
	# Obsidian needs a diamond pickaxe; gold only a pickaxe.
	var ada: Dictionary = sim.residents[0]
	var st := {"what": "gather", "tool": "pick", "target": obs[0]}
	ada.pick = {"type": "iron_pick", "tier": 3, "dur": 10}
	check(sim._work_time(ada, st) < 0.0, "an iron pickaxe can't break obsidian")
	ada.pick = {"type": "diamond_pick", "tier": 4, "dur": 10}
	check(sim._work_time(ada, st) > 0.0, "a diamond pickaxe can")
	sim.expedition = {"state": "out", "leg": "out", "dest": lvl.id, "party": [ada.id], "target": {"item": "obsidian", "n": 1}, "list": [{"item": "obsidian", "on": true, "n": 1}],
		"cargo": {}, "tools": [], "policy": {"target": true, "full": true, "low": true}}
	ada.pick = {"type": "iron_pick", "tier": 3, "dur": 10}
	ada.map = lvl.id
	ada.arriving = false
	check(not sim.can_mine_ore("obsidian") and sim.can_mine_ore("gold") and sim.can_mine_ore("gravel"), "only obsidian wants the better pickaxe")
	sim.on_map(lvl.id, func(): sim._stuck_site())
	check(sim.stuck.any(func(x): return x.why == "Obsidian: needs a diamond pickaxe"), "the stuck list says so: " + stuck_text(sim))
	ada.pick = {"type": "diamond_pick", "tier": 4, "dur": 10}
	check(sim.can_mine_ore("obsidian"), "with a diamond pickaxe it can")
	sim.expedition = {}
	# The report lists what the level holds, once it's been seen, as cargo targets.
	lvl.visited = true
	var items: Array = sim.site_report(lvl.id).resources.map(func(x): return x.item)
	check(items.has("gold_ore") and items.has("obsidian") and items.has("flint"), "the site report lists gold, obsidian and flint (%s)" % [items])
	check(sim.plan_targets(lvl.id).any(func(x): return x.item == "obsidian"), "obsidian is a cargo target")
	# Gravel gives a flint, sometimes.
	var gravel: Dictionary = {}
	for n in range(3, 7):
		var gl: SimMap = MineLevels.build(sim, n)
		for b in gl.boulders:
			if b.get("ore", "") == "gravel" and gravel.is_empty():
				gravel = b
				sim.maps[gl.id] = gl
				lvl = gl
	check(not gravel.is_empty(), "there is gravel to break")
	var flints := 0
	for i in 40:
		var before: int = sim.on_map(lvl.id, func(): return sim.items.values().filter(func(x): return x.type == "flint").map(func(x): return x.n).reduce(func(a, b): return a + b, 0))
		gravel.alive = true
		sim.on_map(lvl.id, func():
			sim.rng.seed = i + 1
			sim._finish_work(ada, {"what": "gather", "tool": "pick", "target": gravel}))
		flints += sim.on_map(lvl.id, func(): return sim.items.values().filter(func(x): return x.type == "flint").map(func(x): return x.n).reduce(func(a, b): return a + b, 0)) - before
	check(flints > 5 and flints < 35, "about half the gravel breaks to a flint (%d of 40)" % flints)
	# Smelting gold, and flint and steel.
	check(Defs.recipe("smelt_gold").inp == {"gold_ore": 1, "coal": 1} and Defs.recipe("smelt_gold").out == {"gold_ingot": 1} and Defs.recipe("smelt_gold").at == "fireplace", "gold ore smelts with coal at the fireplace")
	check(Defs.recipe("flint_and_steel").inp == {"flint": 1, "iron_ingot": 1}, "flint and steel is a flint and an iron ingot")
	check(Sim.full_uses("flint_and_steel") == Tuning.FLINT_STEEL_USES and Defs.stack_cap("flint_and_steel") == 1, "it wears: one to a cell, a few uses")
	check(["gold_ore", "gold_ingot", "obsidian", "flint"].all(func(i): return Defs.ITEMS[i].group == "ores"), "the tally bar groups them with the other ores")
	var vil := Sim.new_game()
	var bench := vil.place_site("bench", open_rect(vil, Vector2i(3, 3)).position + Vector2i(1, 0))
	bench.stage = 1
	bench.done = true
	var cook: Dictionary = vil.residents[0]
	vil.drop_items(Sim.rcell(cook) + Vector2i(1, 0), "flint", 1)
	vil.drop_items(Sim.rcell(cook) + Vector2i(-1, 0), "iron_ingot", 1)
	vil.queue_add(bench, "flint_and_steel")
	run(vil, 60.0)
	var lit: Array = vil.stacks_where(func(x): return x.type == "flint_and_steel")
	check(lit.size() == 1 and lit[0].dur == Tuning.FLINT_STEEL_USES, "the bench makes flint and steel (%d)" % lit.size())


## The portal: an obsidian frame carried in and built, lit only with flint and steel (issue #147).
func test_the_portal() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var spot := open_rect(sim, Vector2i(6, 3)).position + Vector2i(1, 0)
	check(sim.placement_check("portal", spot) == "", "a portal can be placed on open ground")
	var portal := sim.place_site("portal", spot, 2)
	check(portal.rot == 0 and portal.size == Vector2i(4, 1) and portal.plot == Rect2i(spot + Vector2i(-1, 0), Vector2i(6, 3)) and not portal.lit, "it never turns, reserves its staging area and starts unlit")
	check(Defs.TEMPLATES.portal.stages[0].cost == {"obsidian": Tuning.PORTAL_OBSIDIAN}, "the frame costs %d obsidian" % Tuning.PORTAL_OBSIDIAN)
	check(Sim.staging_cells(portal).all(func(c): return portal.plot.has_point(c) and not Rect2i(portal.origin, portal.size).has_point(c)), "its staging area is in front of the frame")
	sim.paint_zone(open_rect(sim, Vector2i(2, 2)))
	sim.drop_items(Sim.rcell(ada) + Vector2i(3, 2), "obsidian", 4)
	run(sim, 20)
	sim.compute_stuck()
	check(stuck_text(sim).contains("Portal frame needs 6 more obsidian"), "short of obsidian it says how much: " + stuck_text(sim))
	# Built from the delivered obsidian.
	sim.drop_items(Sim.rcell(ada) + Vector2i(3, 3), "obsidian", 6)
	run(sim, 120)
	check(portal.done and not portal.lit and sim.free_count("obsidian") == 0, "the frame is built from the obsidian carried to it")
	check(sim.events.any(func(ev): return ev.type == "toast" and ev.text.begins_with("The portal frame is built")), "and says what's next")
	check(sim._work_at("build") == portal.origin, "a finished but unlit frame still counts as work for a builder")
	# It lights only with flint and steel.
	run(sim, 20)
	sim.compute_stuck()
	check(not portal.lit and stuck_text(sim).contains("Portal: Needs flint and steel to light"), "without flint and steel it waits: " + stuck_text(sim))
	sim.drop_items(Sim.rcell(ada) + Vector2i(-2, 1), "flint_and_steel", 1)
	run(sim, 60)
	check(portal.lit and portal.builder == 0, "with flint and steel someone lights it")
	var back := sim.stacks_where(func(x): return x.type == "flint_and_steel")
	check(back.size() == 1 and back[0].dur == Tuning.FLINT_STEEL_USES - 1, "the flint and steel is put back with a use fewer (%s)" % [back.map(func(x): return x.dur)])
	sim.compute_stuck()
	check(not stuck_text(sim).contains("Portal"), "a lit portal is not stuck")
	check(Sim.from_state(sim.save_state()).maps.village.sites.any(func(x): return x.tpl == "portal" and x.lit), "the lit state is saved")
	# A spent flint and steel is gone.
	var sim2 := Sim.new_game()
	var p2 := sim2.place_site("portal", open_rect(sim2, Vector2i(6, 3)).position + Vector2i(1, 0))
	p2.stage = 1
	p2.done = true
	sim2.drop_items(Sim.rcell(sim2.residents[0]) + Vector2i(-2, 1), "flint_and_steel", 1, 1)
	run(sim2, 60)
	check(p2.lit and sim2.stacks_where(func(x): return x.type == "flint_and_steel").is_empty(), "a spent flint and steel is used up")
	var fixture := SaveFormat.read("res://tests/fixtures/save_v39.save")
	check(not fixture.has("error") and Sim.from_state(fixture.data.state).maps.village.sites.any(func(x): return x.tpl == "portal" and x.lit), "the v39 fixture loads with its lit portal")
	# The Build menu offers it once obsidian has come home.
	check(not OrderMenus.unlocked({"unlock": "portal"}, Sim.new_game()) and OrderMenus.unlocked({"unlock": "portal"}, sim), "the Build menu lists the portal once obsidian has come home or a portal stands")


## A world with a board, a lit portal, and a second resident (issue #148).
func nether_world() -> Dictionary:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var tomas := sim.add_resident("Tomas", Sim.TRAVELERS[0][1], Sim.rcell(ada) + Vector2i(1, 0))
	var board := built_board(sim)
	var portal := place_done(sim, "portal", Sim.rcell(ada) + Vector2i(0, 8))
	return {"sim": sim, "ada": ada, "tomas": tomas, "board": board, "portal": portal}


## The portal landing (issue #148): planned at the board, packed at the portal, crossed to and back.
func test_the_nether_landing() -> void:
	var w := nether_world()
	var sim: Sim = w.sim
	var ada: Dictionary = w.ada
	var portal: Dictionary = w.portal
	var landing: SimMap = sim.get_map(NetherLanding.ID)
	check(landing.w == 24 and landing.h == 24 and landing.id.begins_with("nether") and not landing.known and landing.landmarks.size() == 3 and not landing.lava.is_empty(), "the landing is a 24×24 Nether map with lava and three landmarks, unknown at first")
	check(landing.name == "Nether: portal landing" and landing.entrance == Vector2i(0, 12) and sim.on_map(NetherLanding.ID, func(): return sim.walkable(landing.entrance)), "it's the switcher's 'Nether: portal landing', entered on its west edge")
	var plan := sim.new_plan(NetherLanding.ID)
	plan.party = [ada.id]
	check(plan.target.item == "survey" and plan.picks == 0 and Sim.cargo_rows(plan).is_empty(), "a Nether plan is to survey the landing, with no cargo")
	portal.lit = false
	check(sim.plan_problems(plan).has("The portal isn't lit"), "an unlit portal can't be crossed")
	var bare := Sim.new_game()
	var bare_plan := bare.new_plan(NetherLanding.ID)
	check(bare.plan_problems(bare_plan).has("Build the portal first"), "with no portal, the plan says to build one")
	portal.lit = true
	sim.maps[NetherLanding.ID].known = true
	check(sim.adventures().any(func(a): return a.id == NetherLanding.ID and a.name == "Nether: portal landing"), "the board lists the landing once it's known")
	check(sim.plan_expedition(plan) == "" and sim.expeditions.nether.state == "staging" and sim.expeditions.nether.board == portal.id and sim.expeditions.overworld.is_empty(), "the plan goes in the Nether's slot, packed at the portal")
	check(plan.shelter and plan.cobble == Tuning.SHELTER_COST.cobble and plan.planks == Tuning.SHELTER_COST.plank, "the first crossing plan carries the shelter's cobblestone and planks")
	portal.store = {"bread": 3, "cobble": 4, "plank": 6}
	sim.drop_items(Sim.rcell(ada) + Vector2i(-2, 0), "flint_and_steel", 1)
	for i in 40 * Tuning.TPS:
		sim.step()
		if sim.depart_blocker("nether") == "":
			break
	check(sim.depart_blocker("nether") == "", "the party gathers at the staging area")
	check(Sim.staging_cells(portal).any(func(c): return Sim.manhattan(Sim.rcell(ada), c) <= 1), "(in front of the portal)")
	check(sim.depart("nether") == "" and sim.expeditions.nether.state == "out" and sim.expeditions.nether.has("lighter"), "they set off with a flint and steel to relight the portal")
	# Through the portal, and only there.
	var last_village := Vector2i.ZERO
	for i in 90 * Tuning.TPS:
		if ada.map == "village":
			last_village = Sim.rcell(ada)
		sim.step()
		if ada.map == NetherLanding.ID:
			break
	check(ada.map == NetherLanding.ID and not ada.away, "Ada crosses to the landing")
	check(Sim.manhattan(last_village, sim.sign_for(NetherLanding.ID)) <= 1, "from the staging area, the one way through (%s)" % [last_village])
	check(Sim.rcell(ada) == landing.entrance and landing.known and landing.visited, "arriving on its west edge, which makes it known and visited")
	# The survey: every landmark.
	for i in 120 * Tuning.TPS:
		sim.step()
		if landing.surveyed:
			break
	check(landing.surveyed and landing.landmarks_seen.size() == 3, "the party surveys the landing, one landmark after another")
	for i in 120 * Tuning.TPS:
		sim.step()
		if sim.shelter_site().get("done", false):
			break
	check(sim.shelter_site().get("done", false) and sim.expeditions.nether.supplies.is_empty() and landing.sites.size() == 1, "the party builds the shelter from the cobblestone and planks it carried")
	for i in 120 * Tuning.TPS:
		sim.step()
		if sim.expeditions.nether.is_empty():
			break
	check(sim.expeditions.nether.is_empty() and ada.map == "village" and sim.stats.expeditions == 1, "once surveyed it heads home through the portal, unpacks, and the slot is free (%s)" % [sim.expeditions.nether.get("home_why", "")])
	check(sim.stacks_where(func(x): return x.type == "flint_and_steel").size() == 1, "and the flint and steel comes home")
	check(sim.expedition_board().get("report", []).size() > 0, "the board shows the report")
	# Older saves get the landing when they load, unknown.
	var old := SaveFormat.read("res://tests/fixtures/save_v38.save")
	var oldsim := Sim.from_state(old.data.state)
	check(oldsim.maps.has(NetherLanding.ID) and not oldsim.get_map(NetherLanding.ID).known and oldsim.expeditions.nether.is_empty(), "an older save loads with the landing, unknown")
	# The surveyed landing is remembered, and saved.
	var back := Sim.from_state(sim.save_state())
	check(back.get_map(NetherLanding.ID).surveyed and back.get_map(NetherLanding.ID).visited and back.get_map(NetherLanding.ID).landmarks_seen.size() == 3, "the survey is saved")


## An Overworld party and a Nether party out together, each from its own packs (issue #145).
func test_nether_and_overworld_together() -> void:
	var w := nether_world()
	var sim: Sim = w.sim
	var ada: Dictionary = w.ada
	var tomas: Dictionary = w.tomas
	var portal: Dictionary = w.portal
	var board: Dictionary = w.board
	portal.lit = true
	sim.maps[NetherLanding.ID].known = true
	var nplan := sim.new_plan(NetherLanding.ID)
	nplan.party = [tomas.id]
	nplan.meals = 3
	nplan.shelter = false
	nplan.cobble = 0
	nplan.planks = 0
	check(sim.plan_expedition(nplan) == "", "the Nether party is planned")
	portal.store = {"bread": 3}
	var oplan := sim.new_plan(Meadow.ID)
	oplan.party = [ada.id]
	oplan.meals = 2
	sim.aim_plan(oplan, "wool", 2)
	check(sim.plan_expedition(oplan) == "" and sim.expeditions.overworld.state == "staging" and sim.expeditions.nether.state == "staging", "and the Overworld party, while it's packing")
	check(sim.plan_expedition(sim.new_plan(Meadow.ID)).contains("is already out") and sim.plan_expedition(sim.new_plan(NetherLanding.ID)).contains("is already out"), "a third is refused for either slot")
	board.store = {"bread": 2}
	for i in 40 * Tuning.TPS:
		sim.step()
		if sim.depart_blocker("overworld") == "" and sim.depart_blocker("nether") == "":
			break
	check(sim.depart("overworld") == "" and sim.depart("nether") == "", "both depart")
	check(sim.expeditions.nether.provisions == {"bread": 3} and sim.expeditions.overworld.provisions == {"bread": 2}, "each from its own packs (%s, %s)" % [sim.expeditions.nether.provisions, sim.expeditions.overworld.provisions])
	var both := false
	for i in 150 * Tuning.TPS:
		sim.step()
		if tomas.map == NetherLanding.ID and ada.away:
			both = true
			break
	check(both, "Tomas is on the Nether landing while Ada is away at the meadow")
	check(sim.slot == "overworld" and sim.expeditions.nether.dest == NetherLanding.ID and sim.expeditions.overworld.dest == Meadow.ID, "each keeps its own destination")
	for i in 400 * Tuning.TPS:
		sim.step()
		if sim.expeditions.nether.is_empty() and sim.expeditions.overworld.is_empty():
			break
	check(sim.expeditions.nether.is_empty() and sim.expeditions.overworld.is_empty() and sim.stats.expeditions == 2, "both come home and unpack (%d)" % sim.stats.expeditions)


## The portal can go out while a party is through it (issue #148): a party with flint and steel relights it, and one
## without waits for the village.
func test_the_portal_goes_out() -> void:
	for with_lighter in [true, false]:
		var w := nether_world()
		var sim: Sim = w.sim
		var ada: Dictionary = w.ada
		var portal: Dictionary = w.portal
		portal.lit = false
		var landing: SimMap = sim.get_map(NetherLanding.ID)
		landing.known = true
		landing.visited = true
		landing.surveyed = true
		sim.expeditions.nether = {"state": "out", "leg": "home", "dest": NetherLanding.ID, "party": [ada.id], "board": portal.id,
			"target": {"item": "survey", "n": 1}, "list": [], "meals": 1, "picks": 0, "policy": {"target": true, "full": true, "low": true}, "spend_return": false,
			"provisions": {"bread": 1}, "cargo": {}, "supplies": {}, "tools": [], "packed": {}, "cart": false, "cart_cap": false, "hurt": {}, "broken": 0, "clear": false, "home_why": "the landing is surveyed"}
		if with_lighter:
			sim.expeditions.nether.lighter = {"type": "flint_and_steel", "dur": 5}
		sim.move_to_map(ada, NetherLanding.ID, landing.entrance)
		var label := "with flint and steel" if with_lighter else "without"
		if with_lighter:
			for i in 60 * Tuning.TPS:
				sim.step()
				if portal.lit:
					break
			check(portal.lit, "%s: the party relights the portal" % label)
			check(sim.expeditions.nether.get("lighter", {}).get("dur", 0) == 4 or sim.expeditions.nether.is_empty(), "%s: using a use of the flint and steel" % label)
			for i in 90 * Tuning.TPS:
				sim.step()
				if sim.expeditions.nether.is_empty():
					break
			check(sim.expeditions.nether.is_empty() and ada.map == "village", "%s: and comes home" % label)
		else:
			run(sim, 30)
			sim.compute_stuck()
			check(ada.map == NetherLanding.ID and not portal.lit and stuck_text(sim).contains("The portal has gone out and no one has flint and steel"), "%s: the party waits, and the list says why: %s" % [label, stuck_text(sim)])
			sim.drop_items(Sim.rcell(ada), "flint_and_steel", 1)  # (lying on the landing, out of the village's reach)
			portal.lit = true  # the village lights it
			for i in 90 * Tuning.TPS:
				sim.step()
				if sim.expeditions.nether.is_empty():
					break
			check(sim.expeditions.nether.is_empty() and ada.map == "village", "%s: once it's lit again they come home" % label)


## Fire, lava and falls on the Nether's maps (issue #149).
func test_nether_hazards() -> void:
	var w := nether_world()
	var sim: Sim = w.sim
	var tomas: Dictionary = w.tomas
	var ada: Dictionary = w.ada
	var landing: SimMap = sim.get_map(NetherLanding.ID)
	landing.visited = true
	check(not landing.fire.is_empty() and not landing.ledges.is_empty() and not landing.lava.is_empty(), "the landing has fire, ledges and lava")
	sim.move_to_map(tomas, NetherLanding.ID, landing.entrance + Vector2i(1, 0))
	sim.use_map(NetherLanding.ID)
	# Beside lava: a burn now and then.
	var beside: Vector2i = landing.lava.keys().filter(func(c): return sim.walkable(c + Vector2i(0, 1)))[0] + Vector2i(0, 1)
	check(landing.beside_lava(beside), "(a cell beside lava)")
	var burns := 0
	for i in 400:
		tomas.hurt = 0
		sim._ledge_step(tomas, beside)
		burns += 1 if tomas.hurt > 0 else 0
	check(burns > 3 and burns < 45, "stepping beside lava burns about %d%% of the time (%d of 400)" % [roundi(Tuning.LAVA_CHANCE * 100), burns])
	check(str(tomas.hurt_cause).contains("burn"), "and the cause is a burn")
	# Falls: a ledge on the Nether needs no dark.
	var ledge: Vector2i = landing.ledges[0]
	var falls := 0
	for i in 600:
		tomas.hurt = 0
		sim._ledge_step(tomas, ledge)
		falls += 1 if tomas.hurt > 0 else 0
	check(falls > 5 and falls < 70, "a ledge drops someone now and then, dark or not (%d of 600)" % falls)
	# Fire: stepping onto it sets someone alight and hurts; leaving it, the burning stops.
	var fire: Vector2i = landing.fire.keys()[0]
	var hurts := 0
	for i in 60:
		tomas.hurt = 0
		tomas.burn = 0.0
		tomas.pos = Vector2(fire)
		tomas.path = []
		sim._ledge_step(tomas, fire)
		check(tomas.burn == Tuning.FIRE_BURN_TIME, "")
		for k in int(Tuning.FIRE_BURN_TIME + 3.0) * Tuning.TPS:
			if tomas.get("burn", 0.0) <= 0.0 and k > 0:
				break
			sim._step_resident(tomas)
		hurts += 1 if tomas.hurt > 0 else 0
		check(not landing.fire.has(Sim.rcell(tomas)), "")
	check(hurts > 15, "someone on fire is hurt, often (%d of 60)" % hurts)
	sim.use_map("village")
	tomas.hurt = 0
	tomas.burn = 0.0
	tomas.job = null
	tomas.pos = Vector2(landing.entrance + Vector2i(1, 0))
	var before: int = sim.stats.get("injuries", 0)
	run(sim, 15)
	check(sim.stats.get("injuries", 0) == before and tomas.get("burn", 0.0) <= 0.0, "away from the fire the burning has stopped")
	# Paths go round the lava where they can.
	sim.use_map(NetherLanding.ID)
	var path = sim.find_path(Vector2i(1, 3), {Vector2i(6, 3): true})
	var hot: Dictionary = landing.heat()
	check(path != null and not path.any(func(c): return hot.has(c)), "a path round the pool keeps off the cells beside lava (%s)" % [path.filter(func(c): return hot.has(c)) if path != null else "none"])
	var tight = sim.find_path(Vector2i(1, 3), {Vector2i(5, 3): true})  # the goal is itself beside the pool
	check(tight != null and tight.size() > 0, "and one to a cell beside it still finds it")
	sim.use_map("village")
	# The PC is never seriously hurt; a serious burn on an expedition stops the game and offers the retreat.
	sim.injure(ada, 2, "burning")
	check(ada.hurt == 1, "Ada can be burned, but never seriously")
	ada.hurt = 0
	sim.move_to_map(ada, NetherLanding.ID, landing.entrance + Vector2i(2, 0))
	sim.expeditions.nether = {"state": "out", "leg": "out", "dest": NetherLanding.ID, "party": [tomas.id, ada.id], "board": w.portal.id,
		"target": {"item": "survey", "n": 1}, "list": [], "meals": 1, "picks": 0, "policy": {"target": true, "full": true, "low": true}, "spend_return": false,
		"provisions": {"bread": 1}, "cargo": {}, "supplies": {}, "tools": [], "packed": {}, "cart": false, "cart_cap": false, "hurt": {}, "broken": 0, "clear": false}
	tomas.hurt = 0
	sim.on_slot("nether", func(): sim.on_map(NetherLanding.ID, func(): sim.injure(tomas, 2, "burning")))
	check(not sim.pending.is_empty() and sim.pending[0].kind == "injury" and sim.pending[0].slot == "nether" and "burning" in sim.pending[0].text, "a serious burn stops the game for the retreat")
	sim.choose("retreat")
	check(sim.expeditions.nether.leg == "home" and sim.expeditions.nether.home_why.contains("seriously hurt"), "retreat sends the party home (%s)" % sim.expeditions.nether.get("home_why", ""))
	# The stuck list says what happened, and the report lists the dangers.
	tomas.hurt = 1
	tomas.hurt_cause = "burning"
	tomas.heal = 30.0
	sim.compute_stuck()
	check(stuck_text(sim).contains("Burned"), "the stuck list says someone is burned: " + stuck_text(sim))
	var hazards: Array = sim.site_report(NetherLanding.ID).hazards
	check(hazards.any(func(h): return h.contains("Lava")) and hazards.any(func(h): return h.contains("fire")) and hazards.any(func(h): return h.contains("Ledges")), "the site report lists lava, fire and ledges (%s)" % [hazards])
	check(Sim.from_state(sim.save_state()).get_map(NetherLanding.ID).fire == landing.fire, "the fire is saved")


## The Guard job, iron swords and the iron chestplate (issue #150).
func test_the_guard_and_iron_gear() -> void:
	check(Defs.recipe("iron_sword").inp == {"iron_ingot": 2, "stick": 1} and Defs.recipe("iron_chestplate").inp == {"iron_ingot": 8}, "the recipes: a sword is 2 ingots and a stick, a chestplate 8 ingots")
	check(Defs.JOBS.has("guard") and Defs.JOB_NAMES.guard == "Guard" and not Defs.JOB_STATIONS.has("guard") and not Defs.SKILL_POOL.has("guard"), "Guard is a job with no workstation, and no traveler arrives as one")
	check(Sim.full_uses("iron_sword") == Tuning.SWORD_USES and Sim.full_uses("iron_chestplate") == Tuning.IRON_ARMOR_USES and Defs.stack_cap("iron_sword") == 1, "they wear: a sword's uses, a chestplate's")
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	var bram := sim.add_resident("Bram", "7A5C8F", Sim.rcell(ada) + Vector2i(1, 0))
	check(bram.jobs.guard.xp == 0 and Sim.level(bram, "guard") == 1 and bram.sword == null, "a new resident has Guard at its start and no sword")
	sim.set_role(bram, "guard")
	check(sim.works(bram, "guard") and not sim.works(bram, "lumber") and sim.works(bram, "haul") and sim.works(ada, "guard"), "a guard works the Guard job and hauls; Ada does everything")
	# A guard takes a sword that lies about, and keeps it.
	sim.drop_items(Sim.rcell(ada) + Vector2i(2, 2), "iron_sword", 1)
	run(sim, 30)
	check(bram.sword != null and bram.sword.type == "iron_sword" and bram.sword.dur == Sim.full_uses("iron_sword") and bram.kept.sword, "a guard with no sword picks one up and keeps it")
	ada.sword = null
	sim.drop_items(Sim.rcell(ada) + Vector2i(3, 3), "iron_sword", 1)
	run(sim, 30)
	check(ada.sword == null, "only a guard arms himself")
	# The planner warns about a guard with no sword; it doesn't stop the plan.
	var tomas := sim.add_resident("Tomas", "7A5C8F", Sim.rcell(ada) + Vector2i(-1, 0))
	sim.set_role(tomas, "guard")
	var plan := sim.new_plan()
	plan.party = [tomas.id]
	for s in sim.stacks_where(func(x): return x.type == "iron_sword"):
		sim.items.erase(s.cell)
	check(sim.plan_warnings(plan) == ["No sword for Tomas"], "the planner warns: %s" % [sim.plan_warnings(plan)])
	plan.party = [bram.id]
	check(sim.plan_warnings(plan).is_empty(), "no warning for a guard with a sword")
	# Iron armor turns more aside than leather, and wears.
	var leather := {"armor": {"chest": {"type": "leather_tunic", "dur": 8}}}
	var iron := {"armor": {"chest": {"type": "iron_chestplate", "dur": 20}}}
	check(Sim.protection(iron) > Sim.protection(leather) and absf(Sim.protection(iron) - Tuning.IRON_GUARD) < 0.001, "an iron chestplate turns aside %d%% against a tunic's %d%%" % [roundi(Tuning.IRON_GUARD * 100), roundi(Tuning.ARMOR_GUARD.chest * 100)])
	var hurt_plain := 0
	var hurt_iron := 0
	for i in 600:
		for pair in [[hurt_plain, {}], [hurt_iron, iron.armor]]:
			pass
		var a := {"id": 9000 + i, "name": "A", "armor": {}, "hurt": 0, "job": null, "heal": 0.0}
		var b := {"id": 9500 + i, "name": "B", "armor": iron.armor.duplicate(true), "hurt": 0, "job": null, "heal": 0.0}
		sim._hazard(a, 0.5, 0.0, "a test")
		sim._hazard(b, 0.5, 0.0, "a test")
		hurt_plain += 1 if a.hurt > 0 else 0
		hurt_iron += 1 if b.hurt > 0 else 0
	check(hurt_iron < hurt_plain - 60, "armor lowers the injury chance (%d hurt bare, %d in iron, of 600)" % [hurt_plain, hurt_iron])
	# The toolsmith keeps a spare sword once a guard has one.
	var ts := Sim.new_game()
	hire_toolsmith(ts)
	var bench := ts.place_site("bench", open_rect(ts, Vector2i(3, 3)).position + Vector2i(1, 0))
	bench.stage = 1
	bench.done = true
	var g := ts.add_resident("Bram", "7A5C8F", Sim.rcell(ts.residents[0]) + Vector2i(1, 0))
	ts.set_role(g, "guard")
	g.sword = {"type": "iron_sword", "tier": 3, "dur": 5}
	ts.drop_items(Sim.rcell(ts.residents[0]) + Vector2i(1, 1), "iron_ingot", 2)
	ts.drop_items(Sim.rcell(ts.residents[0]) + Vector2i(-1, 1), "stick", 1)
	run(ts, 1)
	check(bench.queue.has("iron_sword"), "the toolsmith queues a spare sword (%s)" % [bench.queue])
	# An old save's residents have no sword and Guard at the start.
	var fixture := SaveFormat.read("res://tests/fixtures/save_v40.save")
	var old := Sim.from_state(fixture.data.state)
	check(old.residents.all(func(r): return r.sword == null and r.broken.sword == false and r.jobs.guard.xp == 0), "an older save loads with no sword and Guard at 0")
	var f41 := SaveFormat.read("res://tests/fixtures/save_v41.save")
	var s41 := Sim.from_state(f41.data.state)
	check(s41.residents[0].sword.type == "iron_sword" and s41.residents[0].jobs.guard.xp == 10 and s41.residents[0].armor.chest.type == "iron_chestplate", "the v41 fixture loads its sword, Guard practice and chestplate")


## A party at the landing, Tomas a guard with an iron sword and Mira an ordinary resident (issue #151).
func fight_world() -> Dictionary:
	var w := nether_world()
	var sim: Sim = w.sim
	var tomas: Dictionary = w.tomas
	var mira := sim.add_resident("Mira", Sim.TRAVELERS[1][1], Sim.rcell(w.ada) + Vector2i(-1, 0))
	sim.set_role(tomas, "guard")
	tomas.sword = {"type": "iron_sword", "tier": 3, "dur": Sim.full_uses("iron_sword")}
	var landing: SimMap = sim.get_map(NetherLanding.ID)
	landing.known = true
	landing.visited = true
	landing.fire.clear()  # these fights are about creatures
	landing.landmarks = []  # and nobody surveys, so the party stays
	landing._heat_ready = false
	landing._heat.clear()
	sim.expeditions.nether = {"state": "out", "leg": "out", "dest": NetherLanding.ID, "party": [tomas.id, mira.id], "board": w.portal.id,
		"target": {"item": "survey", "n": 1}, "list": [], "meals": 3, "picks": 0, "policy": {"target": true, "full": true, "low": true}, "spend_return": false,
		"provisions": {"bread": 3}, "cargo": {}, "supplies": {}, "tools": [], "packed": {}, "cart": false, "cart_cap": false, "hurt": {}, "broken": 0, "clear": false, "fight": false, "reached": NetherLanding.ID}
	for r in [tomas, mira]:
		sim.move_to_map(r, NetherLanding.ID, landing.entrance + Vector2i(2 + (0 if r == tomas else 1), 0))
	w.mira = mira
	w.landing = landing
	return w


## Fights on a Nether map (issue #151): creatures notice and strike, guards fight, others move away, nobody dies.
func test_auto_combat() -> void:
	var w := fight_world()
	var sim: Sim = w.sim
	var tomas: Dictionary = w.tomas
	var mira: Dictionary = w.mira
	var landing: SimMap = w.landing
	check(Defs.CREATURES.keys() == ["magma_cube", "zombified_piglin", "skeleton", "blaze"], "four creatures")
	# A guard defeats a magma cube, which leaves its cream.
	var cube := sim.spawn_creature(NetherLanding.ID, "magma_cube", Sim.rcell(tomas) + Vector2i(5, 0))
	var xp: int = tomas.jobs.guard.xp
	var fought := false
	for i in 60 * Tuning.TPS:
		sim.step()
		if not sim.pending.is_empty():
			sim.choose("press_on")
		fought = fought or (tomas.job != null and tomas.job.kind == "fight")
		if not cube.alive:
			break
	check(fought and not cube.alive, "a guard goes for the magma cube and brings it down")
	check(sim.on_map(NetherLanding.ID, func(): return sim.items.values().any(func(it): return it.type == "magma_cream")) and landing.drops_known == ["magma_cream"], "it leaves magma cream, which the landing now lists")
	check(tomas.jobs.guard.xp == xp + 1 and tomas.sword.dur < Sim.full_uses("iron_sword"), "the guard gains practice and the sword wears")
	check(sim.plan_targets(NetherLanding.ID).any(func(x): return x.item == "magma_cream"), "and magma cream is a cargo target now")
	# Nobody died: the guard may be hurt, never gone.
	check(sim.resident(tomas.id).name == "Tomas" and sim.resident(mira.id).name == "Mira", "nobody is lost")
	# Someone who isn't a guard moves away from a hostile creature.
	var cube2 := sim.spawn_creature(NetherLanding.ID, "magma_cube", Sim.rcell(mira) + Vector2i(3, 0))
	tomas.role = "none"  # nobody here can fight it
	tomas.sword = null
	var fled := false
	var said := ""
	for i in 12 * Tuning.TPS:
		sim.step()
		if not sim.pending.is_empty():
			sim.choose("press_on")
		if mira.job != null and mira.job.kind == "flee" and not fled:
			fled = true
			sim.compute_stuck()
			said = stuck_text(sim)
	check(fled, "a resident who isn't a guard moves away from the creature")
	check(said.contains("Nether party: fighting"), "the stuck list says the party is fighting: " + said)
	cube2.alive = false
	# A neutral zombified piglin leaves them alone unless it's hit.
	tomas.role = "guard"
	tomas.sword = {"type": "iron_sword", "tier": 3, "dur": 30}
	var pig := sim.spawn_creature(NetherLanding.ID, "zombified_piglin", Sim.rcell(tomas) + Vector2i(3, 0))
	mira.hurt = 0
	tomas.hurt = 0
	for i in 20 * Tuning.TPS:
		sim.step()
		if not sim.pending.is_empty():
			sim.choose("press_on")
	check(pig.alive and not pig.angry and mira.hurt == 0 and tomas.hurt == 0, "a zombified piglin that isn't hit leaves them alone")
	sim.expeditions.nether.fight = true  # now the party doesn't avoid combat
	for i in 60 * Tuning.TPS:
		sim.step()
		if not sim.pending.is_empty():
			sim.choose("press_on")
		if not pig.alive:
			break
	check(not pig.alive, "when the party doesn't avoid combat, the guard goes after it (and it fights back)")
	# A knocked-down resident is seriously hurt, the game stops for the retreat, and nobody dies.
	sim.pending.clear()
	mira.hurt = 0
	sim.on_slot("nether", func(): sim.on_map(NetherLanding.ID, func(): sim.injure(mira, 2, "a magma cube")))
	check(mira.hurt == 2 and not sim.pending.is_empty() and sim.pending[0].kind == "injury" and sim.pending[0].slot == "nether", "a knocked-down resident is seriously hurt and the game stops for the retreat")
	sim.choose("retreat")
	check(sim.expeditions.nether.leg == "home" and sim.resident(mira.id).hurt == 2, "the retreat policy applies; she's hurt, not dead")
	# The PC is never seriously hurt.
	var ada: Dictionary = w.ada
	sim.injure(ada, 2, "a magma cube")
	check(ada.hurt == 1, "Ada is never seriously hurt")
	# Armor lowers the chance of being hit.
	var plain := 0
	var armored := 0
	for i in 800:
		var a := {"id": 7000 + i, "name": "A", "armor": {}, "hurt": 0, "job": null, "heal": 0.0}
		var b := {"id": 8000 + i, "name": "B", "armor": {"chest": {"type": "iron_chestplate", "dur": 99}}, "hurt": 0, "job": null, "heal": 0.0}
		sim._hazard(a, Defs.CREATURES.magma_cube.hit, 0.0, "a magma cube")
		sim._hazard(b, Defs.CREATURES.magma_cube.hit, 0.0, "a magma cube")
		plain += 1 if a.hurt > 0 else 0
		armored += 1 if b.hurt > 0 else 0
	check(armored < plain - 40, "armor lowers the injuries from creatures (%d bare, %d armored of 800)" % [plain, armored])
	# Creatures stay on their map and are saved with their health.
	check(sim.maps.village.creatures.is_empty() and sim.maps[OldMine.ID].creatures.is_empty(), "no creature ever turns up in the village or the mine")
	var live := sim.spawn_creature(NetherLanding.ID, "blaze", landing.entrance + Vector2i(15, 3))
	live.hp = 4
	for i in 400:
		sim.step()
		if not sim.pending.is_empty():
			sim.choose("press_on")
	check(landing.in_bounds(live.cell) and not landing.rock.has(live.cell), "a creature stays on its map, on open ground")
	var back := Sim.from_state(sim.save_state())
	var saved: Array = back.get_map(NetherLanding.ID).creatures.filter(func(x): return x.id == live.id)
	check(saved.size() == 1 and saved[0].hp == live.hp and saved[0].species == "blaze", "creatures are saved with their health")
	var f42 := SaveFormat.read("res://tests/fixtures/save_v42.save")
	var s42 := Sim.from_state(f42.data.state)
	check(s42.get_map(NetherLanding.ID).creatures.size() == 1 and s42.get_map(NetherLanding.ID).creatures[0].hp == 5, "the v42 fixture loads its hurt magma cube")
	var f41 := SaveFormat.read("res://tests/fixtures/save_v41.save")
	check(Sim.from_state(f41.data.state).get_map(NetherLanding.ID).creatures.is_empty(), "an older save has no creatures")


## The unstaffed shelter and supply cache at the landing (issue #152).
func test_the_shelter_and_cache() -> void:
	var w := fight_world()
	var sim: Sim = w.sim
	var tomas: Dictionary = w.tomas
	var mira: Dictionary = w.mira
	var landing: SimMap = w.landing
	landing.landmarks = []
	sim._enter_level(tomas, NetherLanding.ID)  # (arriving again puts the blueprint down)
	var sh := sim.shelter_site()
	check(not sh.is_empty() and sh.tpl == "shelter" and sh.origin == NetherLanding.SHELTER_AT and not sh.done and sh.map == NetherLanding.ID, "the first crossing puts the shelter's blueprint on the landing")
	check(Defs.TEMPLATES.shelter.stages[0].cost == Tuning.SHELTER_COST and sim.maps.village.sites.all(func(x): return x.tpl != "shelter"), "it costs %s, and isn't a village building" % [Tuning.SHELTER_COST])
	# Short of supplies, the stuck list says how much.
	sim.expeditions.nether.shelter = true
	sim.expeditions.nether.supplies = {"cobble": 4, "plank": 4}
	sim.compute_stuck()
	check(stuck_text(sim).contains("Shelter: needs 2 more planks"), "short of planks it says so: " + stuck_text(sim))
	run(sim, 30)
	check(not sh.done, "and the party doesn't start without all of it")
	sim.expeditions.nether.supplies = {"cobble": 4, "plank": 6}
	for i in 60 * Tuning.TPS:
		sim.step()
		if not sim.pending.is_empty():
			sim.choose("press_on")
		if sh.done:
			break
	check(sh.done and sim.expeditions.nether.supplies.is_empty(), "with it all they build the shelter from what they carried")
	check(sim.shelter_site().done and not sim.on_map(NetherLanding.ID, func(): return sim.walkable(sh.origin)), "it's a solid building on the landing")
	# The cache is empty, and says so.
	sim.compute_stuck()
	check(stuck_text(sim).contains("Cache: empty"), "an empty cache is named: " + stuck_text(sim))
	check(sim.site_report(NetherLanding.ID).cache == "Shelter built. Cache: empty", "the site report shows the cache")
	# A party leaves meals in it.
	sim.expeditions.nether.provisions = {"bread": 4}
	sim.expeditions.nether.stock = 2
	for i in 40 * Tuning.TPS:
		sim.step()
		if sim.pending.size() > 0:
			sim.choose("press_on")
		if sim.cache_meals() > 0:
			break
	check(sim.cache_meals() == 2 and sim.expeditions.nether.provisions == {"bread": 2} and sim.expeditions.nether.stock == 0, "the party leaves the meals it planned to in the cache (%d)" % sim.cache_meals())
	check(sim.site_report(NetherLanding.ID).cache == "Shelter built. Cache: 2 meals", "and the report counts them")
	check(Sim.from_state(sim.save_state()).shelter_site().store == sh.store and Sim.from_state(sim.save_state()).shelter_site().done, "the shelter and its cache are saved")
	# Later, a party with no food of its own eats from the cache, without going home.
	sim.expeditions.nether.provisions = {"bread": 1}  # only the walk home
	tomas.hunger = 20.0
	var before := sim.cache_meals()
	for i in 40 * Tuning.TPS:
		sim.step()
		if sim.pending.size() > 0:
			sim.choose("press_on")
		if sim.cache_meals() < before:
			break
	check(sim.cache_meals() < before, "a party short of food takes a meal from the cache")
	for i in 20 * Tuning.TPS:
		sim.step()
	check(tomas.hunger > 30.0 and sim.expeditions.nether.get("leg", "") == "out", "and eats it, staying on (hunger %d)" % int(tomas.hunger))
	# The injured rest there, more slowly than in a bed.
	mira.hurt = 1
	mira.heal = 10.0
	mira.job = null
	sim.compute_stuck()
	check(stuck_text(sim).contains("resting at the shelter"), "the stuck list says who rests at the shelter: " + stuck_text(sim))
	var ticks := 0
	while mira.hurt > 0 and ticks < 60 * Tuning.TPS:
		sim.step()
		if sim.pending.size() > 0:
			sim.choose("press_on")
		ticks += 1
	check(mira.hurt == 0 and ticks > 15 * Tuning.TPS and ticks < 40 * Tuning.TPS, "she heals there, but slower than in a bed: %d s for 10 s of healing" % (ticks / Tuning.TPS))
	var bed_ticks := 0
	var home := Sim.new_game()
	home.add_resident("Tomas", "7A5C8F", Sim.rcell(home.residents[0]) + Vector2i(1, 0))
	var homebody: Dictionary = home.residents[1]
	homebody.hurt = 1
	homebody.heal = 10.0
	homebody.arriving = false
	while homebody.hurt > 0 and bed_ticks < 60 * Tuning.TPS:
		home.step()
		bed_ticks += 1
	check(ticks > bed_ticks, "slower than at home with no bed of their own at least (%d s against %d s)" % [ticks / Tuning.TPS, bed_ticks / Tuning.TPS])
	var f43 := SaveFormat.read("res://tests/fixtures/save_v43.save")
	var s43 := Sim.from_state(f43.data.state)
	check(s43.shelter_site().done and s43.cache_meals() == 2, "the v43 fixture loads its shelter and cache")
	var f42 := SaveFormat.read("res://tests/fixtures/save_v42.save")
	check(Sim.from_state(f42.data.state).shelter_site().is_empty(), "an older save has no shelter")
	# Older plans pack no shelter supplies.
	check(Sim.plan_supplies({"meals": 3, "picks": 0}) == 3, "a plan with no shelter asks for no cobblestone or planks")


## Scouting the routes out of the landing (issue #153).
func test_scouting_the_routes() -> void:
	var w := nether_world()
	var sim: Sim = w.sim
	var ada: Dictionary = w.ada
	var portal: Dictionary = w.portal
	portal.lit = true
	var landing: SimMap = sim.get_map(NetherLanding.ID)
	landing.known = true
	landing.visited = true
	check(NetherRoute.ROUTES.keys() == ["quartz", "piglin", "fortress"], "three routes: the quartz site, the piglin camp and the fortress entrance")
	for rk in NetherRoute.ROUTES:
		var def: Dictionary = NetherRoute.ROUTES[rk]
		var rm: SimMap = sim.get_map(def.id)
		check(rm.kind == "route" and rm.w == 48 and rm.seen == 1 and not rm.known and not rm.surveyed and sim.get_map(def.site).kind == "site" and not sim.get_map(def.site).known, "route %s is a strip map with its site beyond it, both unknown" % rk)
		check(def.segments.size() == Road.segment_count() and landing.in_bounds(def.exit) and sim.on_map(NetherLanding.ID, func(): return sim.walkable(def.exit)), "%s has six segments and leaves the landing by an open gap in its edge" % rk)
		check(rm.lava.size() > 0 or rm.rock.size() > 0, "")
	# An unscouted site can't be a destination.
	var site_plan := sim.new_plan("nether_quartz")
	site_plan.party = [ada.id]
	check(sim.plan_problems(site_plan).has("Nobody has scouted the way there yet"), "an unscouted site can't be the target of a mission")
	var bad := sim.scout_plan("nowhere")
	bad.party = [ada.id]
	check(sim.plan_problems(bad).has("Choose a route to scout"), "a scout plan names a route")
	# A scouting party walks the quartz route.
	var plan := sim.scout_plan("quartz")
	plan.party = [ada.id]
	plan.shelter = false
	plan.cobble = 0
	plan.planks = 0
	check(plan.target == {"item": "scout", "n": 1, "route": "quartz"} and sim.plan_problems(plan).is_empty(), "a scout plan for the quartz route is fine (%s)" % [sim.plan_problems(plan)])
	check(sim.plan_expedition(plan) == "", "planned")
	portal.store = {"bread": 3}
	sim.drop_items(Sim.rcell(ada) + Vector2i(-2, 0), "flint_and_steel", 1)  # in case the portal goes out
	for i in 40 * Tuning.TPS:
		sim.step()
		if sim.depart_blocker("nether") == "":
			break
	check(sim.depart("nether") == "", "and sent")
	var rm: SimMap = sim.get_map(NetherRoute.ROUTES.quartz.id)
	var on_route := false
	var seen_max := 1
	for i in 400 * Tuning.TPS:
		sim.step()
		if not sim.pending.is_empty():
			sim.choose("press_on")
		on_route = on_route or ada.map == rm.id
		seen_max = maxi(seen_max, rm.seen)
		if sim.expeditions.nether.is_empty():
			break
	check(on_route and rm.known and seen_max == Road.segment_count(), "Ada walks out along the route, revealing its segments one by one (%d of %d)" % [seen_max, Road.segment_count()])
	check(rm.surveyed and sim.get_map("nether_quartz").known, "at its end the route is scouted, and so is the quartz site")
	check(sim.expeditions.nether.is_empty() and ada.map == "village" and sim.stats.expeditions == 1, "the party comes home through the landing and the portal (%s, %s, leg %s, job %s, lit %s)" % [ada.map, sim.expeditions.nether.keys().size(), sim.expeditions.nether.get("leg", ""), ada.job.kind if ada.job != null else "none", portal.lit])
	var rep := sim.site_report(NetherRoute.ROUTES.quartz.id)
	check(rep.segments.all(func(sg): return sg.known) and rep.hazards.any(func(h): return h.contains("Lava")) and rep.travel > 0.0, "the route's report lists every segment, its dangers and its travel time")
	var unseen := sim.site_report(NetherRoute.ROUTES.piglin.id)
	check(unseen.segments.filter(func(sg): return sg.known).size() == 1 and unseen.travel < 0.0 and unseen.hazards.is_empty(), "an unscouted route shows only its first segment and no dangers")
	var lrep := sim.site_report(NetherLanding.ID)
	check(lrep.routes.filter(func(x): return x.state == "scouted").map(func(x): return x.key) == ["quartz"] and lrep.routes.filter(func(x): return x.state == "unknown").size() == 2, "the landing's report shows the quartz route scouted and the others unknown")
	check(sim.plan_problems(sim.scout_plan("quartz")).has("That route is already scouted"), "a scouted route can't be scouted again")
	# The scouted site is a destination (it can't be reached until it's built, #155).
	site_plan = sim.new_plan("nether_quartz")
	site_plan.party = [ada.id]
	check(not sim.plan_problems(site_plan).has("Nobody has scouted the way there yet"), "a scouted site passes that check")
	# Saved: which routes are revealed.
	var back := Sim.from_state(sim.save_state())
	check(back.get_map(NetherRoute.ROUTES.quartz.id).surveyed and back.get_map("nether_quartz").known and not back.get_map(NetherRoute.ROUTES.piglin.id).surveyed, "which routes are revealed is saved")
	var f44 := Sim.from_state(SaveFormat.read("res://tests/fixtures/save_v44.save").data.state)
	check(f44.get_map("nether_route_quartz").surveyed and f44.get_map("nether_quartz").known and f44.get_map("nether_route_piglin").seen == 3, "the v44 fixture loads its scouted routes")
	var old := Sim.from_state(SaveFormat.read("res://tests/fixtures/save_v43.save").data.state)
	check(old.maps.has("nether_route_quartz") and not old.get_map("nether_route_quartz").surveyed, "an older save gets the routes, unscouted")


## The objective picker for Nether plans (issue #154).
func test_mission_types() -> void:
	var w := nether_world()
	var sim: Sim = w.sim
	var ada: Dictionary = w.ada
	var portal: Dictionary = w.portal
	check(Sim.OBJECTIVES.keys() == ["survey", "scout", "gather", "trade", "build", "fortress", "rescue"], "the objectives: survey (the first crossing), then scout, gather, trade, build, fortress and rescue")
	for obj in Sim.OBJECTIVES:
		check(sim.objective_destinations(obj).is_empty() and sim.objective_why_none(obj) == "Light the portal first" and sim.nether_plan(obj).is_empty(), "%s: with the portal dark there is nowhere to go, and it says why" % obj)
	portal.lit = true
	sim.get_map(NetherLanding.ID).known = true
	var dests := func(o: String) -> Array: return sim.objective_destinations(o).map(func(d): return d.dest + ":" + d.route)
	check(dests.call("survey") == ["nether_landing:"] and dests.call("build") == ["nether_landing:"], "survey and build can use the landing")
	check(dests.call("scout") == ["nether_landing:quartz", "nether_landing:piglin", "nether_landing:fortress"], "scout offers the three unscouted routes")
	for o in ["gather", "trade", "fortress", "rescue"]:
		check(dests.call(o).is_empty() and sim.objective_why_none(o) != "", "%s has no valid destination yet, and explains why (%s)" % [o, sim.objective_why_none(o)])
	check(sim.objective_why_none("gather").contains("scout the route to the quartz site"), "gather says to scout the quartz route first")
	var empty := sim.nether_plan("gather")
	check(empty.is_empty(), "a plan with no valid destination is empty")
	# Each objective's defaults.
	var survey := sim.nether_plan("survey")
	check(survey.target.item == "survey" and survey.shelter and survey.cobble == Tuning.SHELTER_COST.cobble and survey.fight == false and survey.objective == "survey", "survey: the landing, the shelter's materials, avoiding combat")
	var scout := sim.nether_plan("scout", sim.objective_destinations("scout")[1])
	check(scout.target == {"item": "scout", "n": 1, "route": "piglin"} and not scout.shelter and scout.cobble == 0, "scout: the chosen route, no shelter materials")
	var build := sim.nether_plan("build")
	check(build.target.item == "build" and build.shelter and build.planks == Tuning.SHELTER_COST.plank, "build: carries the materials")
	check(Sim.OBJECTIVES.scout.returns == "the route is scouted" and Sim.OBJECTIVES.gather.returns == "the cargo target is reached" and Sim.OBJECTIVES.rescue.returns == "the stranded party is reached", "defaults for coming home: a scout when the route is scouted, a gather at its target, a rescue when the party is reached")
	# What a scout plan lists is only what it can use: a scouted route drops out.
	sim.get_map(NetherRoute.ROUTES.quartz.id).surveyed = true
	sim.get_map("nether_quartz").known = true
	check(dests.call("scout") == ["nether_landing:piglin", "nether_landing:fortress"], "a scouted route drops off the scout list")
	check(dests.call("gather") == ["nether_quartz:"] and dests.call("trade").is_empty() and dests.call("fortress").is_empty(), "the quartz site can be gathered from; the piglins and fortress still can't")
	var gather := sim.nether_plan("gather")
	check(gather.dest == "nether_quartz" and gather.target == {"item": "quartz", "n": 8} and gather.objective == "gather" and gather.picks == 1, "a gather plan for the quartz site wants 8 quartz, with a spare pickaxe")
	gather.party = [ada.id]
	check(not sim.plan_problems(gather).has("Choose something to bring back"), "its cargo list is the site's quartz and glowstone")
	sim.get_map(NetherLanding.ID).surveyed = true
	check(dests.call("survey").is_empty() and sim.objective_why_none("survey") == "The landing is already surveyed", "a surveyed landing needs no more survey")
	var shelter: Dictionary = sim.on_map(NetherLanding.ID, func(): return sim.place_site("shelter", NetherLanding.SHELTER_AT))
	shelter.stage = 1
	shelter.done = true
	check(dests.call("build").is_empty() and sim.objective_why_none("build") == "Nothing to build yet: the shelter stands", "a standing shelter leaves nothing to build")
	# The briefing: dangers, risks and when they come home.
	var plan := sim.nether_plan("scout")
	plan.party = [ada.id]
	var lines := sim.plan_briefing(plan)
	check(lines.any(func(l): return l.begins_with("Risk: no flint and steel")) and lines[-1] == "Comes home when the route is scouted", "the briefing names the risk of a dark portal, and when they come home (%s)" % [lines])
	sim.get_map(NetherRoute.ROUTES.piglin.id).seen = 4
	var lines2 := sim.plan_briefing(sim.nether_plan("scout"))
	check(lines2.any(func(l): return l.begins_with("Danger: ")), "dangers known on the way are listed")
	var sword_less := sim.add_resident("Bram", "7A5C8F", Sim.rcell(ada) + Vector2i(1, 0))
	sim.set_role(sword_less, "guard")
	var p2 := sim.nether_plan("scout")
	p2.party = [sword_less.id]
	check(sim.plan_briefing(p2).any(func(l): return l.begins_with("Risk: no one in the party can fight")), "a guard with no sword is a risk")
	# Overworld plans keep their form.
	var old := sim.new_plan(OldMine.ID)
	check(not old.has("objective") and old.target.item == "coal", "an Overworld plan is still a gather at the old mine")


## The quartz site and the gather mission to it (issue #155).
func test_the_quartz_site() -> void:
	var w := nether_world()
	var sim: Sim = w.sim
	var ada: Dictionary = w.ada
	var portal: Dictionary = w.portal
	var site: SimMap = sim.get_map("nether_quartz")
	var quartz: Array = site.boulders.filter(func(b): return b.ore == "quartz")
	var glow: Array = site.boulders.filter(func(b): return b.ore == "glowstone")
	check(site.pattern == "hand_laid" and site.w == 20 and site.h == 14 and quartz.size() == 8 and glow.size() == 5 and site.lava.size() == 4 and site.entrance == Vector2i(0, 7), "a hand-laid 20×14 site with 8 quartz, 5 glowstone and a lava pool")
	check(Rect2i(0, 0, 20, 14).encloses(NetherRoute.QUARTZ_STATION_PLOT) and sim.on_map("nether_quartz", func(): return NetherRoute.QUARTZ_STATION_PLOT.size.x == 5 and range(14, 19).all(func(x): return sim.walkable(Vector2i(x, 12)))), "it keeps room clear for the Nether line's far station")
	check(Defs.ITEMS.quartz.group == "ores" and Defs.ITEMS.glowstone.group == "ores" and Defs.ORES.quartz.item == "quartz", "quartz and glowstone are ores to the tally bar")
	# Glowstone breaks by hand; quartz needs a pickaxe.
	ada.pick = null
	var bare := {"what": "gather", "tool": "pick", "target": glow[0]}
	check(absf(sim._work_time(ada, bare) - Tuning.GLOWSTONE_TIME) < 0.01, "glowstone breaks by hand in %d s" % Tuning.GLOWSTONE_TIME)
	check(sim._work_time(ada, {"what": "gather", "tool": "pick", "target": quartz[0]}) < 0.0, "quartz can't")
	ada.pick = {"type": "stone_pick", "tier": 2, "dur": 50}
	check(sim._work_time(ada, {"what": "gather", "tool": "pick", "target": quartz[0]}) > 0.0, "with a pickaxe it can")
	# A report before and after a visit.
	portal.lit = true
	sim.get_map(NetherLanding.ID).known = true
	sim.get_map(NetherRoute.ROUTES.quartz.id).surveyed = true
	site.known = true
	var rep := sim.site_report("nether_quartz")
	check(rep.resources.map(func(x): return x.item) == ["quartz", "glowstone"] and rep.resources.all(func(x): return x.reserve == -1) and rep.travel > 0.0, "before anyone's been there the report names the finds, reserves unknown")
	# The gather mission, through the portal, along the route and back.
	var plan := sim.nether_plan("gather")
	plan.party = [ada.id]
	sim.aim_plan(plan, "quartz", 4)
	plan.policy = {"target": true, "full": true, "low": true}
	check(sim.plan_problems(plan).is_empty(), "the plan is fine (%s)" % [sim.plan_problems(plan)])
	check(sim.plan_expedition(plan) == "", "planned")
	portal.store = {"bread": 3}
	sim.drop_items(Sim.rcell(ada) + Vector2i(-2, 0), "flint_and_steel", 1)
	sim.drop_items(Sim.rcell(ada) + Vector2i(-2, 1), "stone_pick", 1)
	for i in 40 * Tuning.TPS:
		sim.step()
		if sim.depart_blocker("nether") == "":
			break
	check(sim.depart("nether") == "", "and sent")
	var maps_seen := {}
	var left := site.boulders.filter(func(b): return b.alive and b.ore == "quartz").size()
	for i in 900 * Tuning.TPS:
		sim.step()
		if not sim.pending.is_empty():
			sim.choose("press_on")
		maps_seen[ada.map] = true
		ada.hurt = 0  # the lava and creatures on the way aren't what's tested here: she mines
		if sim.expeditions.nether.is_empty():
			break
	check(maps_seen.has(NetherLanding.ID) and maps_seen.has(NetherRoute.ROUTES.quartz.id) and maps_seen.has("nether_quartz"), "Ada crosses the landing and walks the route to the site (%s)" % [maps_seen.keys()])
	check(sim.expeditions.nether.is_empty() and ada.map == "village" and sim.stats.expeditions == 1, "and comes home the same way")
	var brought := 0
	for st in sim.stacks_where(func(x): return x.type == "quartz"):
		brought += st.n
	var mined := left - site.boulders.filter(func(b): return b.alive and b.ore == "quartz").size()
	check(brought >= 4 and mined * Tuning.ORE_YIELD.quartz == brought, "she brings back the quartz she mined (%d from %d blocks)" % [brought, mined])
	var rep2 := sim.site_report("nether_quartz")
	var q: Dictionary = rep2.resources.filter(func(x): return x.item == "quartz")[0]
	check(site.visited and q.reserve == (quartz.size() - mined) * Tuning.ORE_YIELD.quartz, "the reserve ran down by what was mined (%d left)" % q.reserve)
	# Deposits don't come back, and it's saved.
	var back := Sim.from_state(sim.save_state())
	check(back.ore_left("nether_quartz", "quartz") == quartz.size() - mined and back.get_map("nether_quartz").visited, "the mined-out blocks stay gone, saved")
	var f45 := Sim.from_state(SaveFormat.read("res://tests/fixtures/save_v45.save").data.state)
	check(f45.ore_left("nether_quartz", "quartz") == 6 and f45.get_map("nether_quartz").visited, "the v45 fixture loads the quartz site with two blocks mined")
	# An older save's empty room becomes the quartz site on loading.
	var f44 := SaveFormat.read("res://tests/fixtures/save_v44.save")
	check(Sim.from_state(f44.data.state).get_map("nether_quartz").boulders.size() == 13 and Sim.from_state(f44.data.state).get_map("nether_quartz").known, "an older save's empty room becomes the quartz site, still known")
