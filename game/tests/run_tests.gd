extends SceneTree
## Headless sim tests. Run from the game/ folder:
##   godot --headless --path . -s res://tests/run_tests.gd
## Exits with code 1 if any test fails.

var _failures := 0
var _checks := 0
var _current := ""


func _init() -> void:
	var tests := [
		"test_full_opening",
		"test_bench_skips_blocked_recipes_and_comes_before_building",
		"test_auto_ingredients_unlock_with_first_house",
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
		"test_jobs_on_off_and_priorities",
		"test_skills_rise_and_pay_off",
		"test_toolsmith_keeps_spares",
		"test_equip_a_chosen_tool",
		"test_meadow_trips",
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
	]
	for t in tests:
		_current = t
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


## Plays the founding moment the way a player would, end to end.
func play_opening(sim: Sim) -> Dictionary:
	sim.designate_mine(area(0, 0, 10, 18))
	sim.designate_hunt(whole_map())  # wool for the two beds
	var bench := sim.place_site("bench", at(8, 10))
	run(sim, 120)
	for r in ["planks", "planks", "sticks", "wood_pick"]:
		sim.queue_add(bench, r)
	run(sim, 120)
	sim.paint_zone(area(10, 7, 4, 2))
	sim.designate_mine(whole_map())
	run(sim, 150)
	var h1 := sim.place_site("house", at(11, 0))
	for i in 8:
		sim.queue_add(bench, "planks")
	run(sim, 600)
	var h2 := sim.place_site("house", at(1, 4), 1)
	for i in 8:
		sim.queue_add(bench, "planks")
	run(sim, 900)
	return {"bench": bench, "h1": h1, "h2": h2}


func test_full_opening() -> void:
	var sim := Sim.new_game()
	var s := play_opening(sim)
	check(s.bench.done, "bench is built")
	check(sim.stats.pick_crafted, "a pickaxe was crafted")
	check(sim.stats.broken_boulders > 0, "boulders were broken")
	check(s.h1.done and s.h2.done, "both houses are built")
	check(s.h1.owner == sim.residents[0].id, "Ada owns the first house")
	check(sim.residents.size() == 2 and sim.residents[1].name == "Tomas", "Tomas arrived")
	check(sim.stats.traveler_home, "Tomas moved in")
	check(s.h2.owner == sim.residents[1].id, "Tomas owns the second house")
	check(sim.auto_craft, "auto ingredients unlocked")
	# Skills (issue #48): Ada learned by doing, and Tomas arrived skilled in one job.
	check(Sim.level(sim.residents[0], "mine") >= 2, "Ada's Mine level rose with practice (level %d)" % Sim.level(sim.residents[0], "mine"))
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


func test_auto_ingredients_unlock_with_first_house() -> void:
	var sim := Sim.new_game()
	sim.designate_mine(area(0, 0, 10, 18))
	var bench := sim.place_site("bench", at(8, 10))
	run(sim, 120)
	for k in sim.items.keys():
		if sim.items[k].type != "log":
			sim.items.erase(k)
	sim.queue_add(bench, "wood_pick")
	run(sim, 1)
	check(bench.queue == ["wood_pick"], "no auto ingredients before the first house")
	check(stuck_text(sim).contains("Wooden pickaxe needs 3 more planks"), "blocked recipe reported: " + stuck_text(sim))
	sim.auto_craft = true
	sim.expand_queues()
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
	check(stuck_text(sim).contains("Axe broke. Needs a new axe"), "resident reports it: " + stuck_text(sim))
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
		check(size == (Vector2i(18, 18) if v < 4 else Vector2i(Tuning.MAP_W, Tuning.MAP_H)), "v%d: map size is %s" % [v, size])
		check(sim.residents.size() == 2 and sim.residents[1].arriving, "v%d: Tomas is walking in again after loading" % v)
		check(sim.sites.any(func(s): return s.tpl == "bench" and s.done and s.queue.has("stone_axe")), "v%d: the bench and its queue survive" % v)
		if v >= 3:
			check(sim.residents[0].orders.size() == 2, "v%d: Ada's queued orders survive" % v)
		else:
			check(sim.residents[0].orders == [], "v%d: residents get an empty order list" % v)
		if v >= 13:
			check(sim.meadow_sheep == 5 and sim.meadow_regrow > 0.0, "v%d: the meadow's sheep survive" % v)
		else:
			check(sim.meadow_sheep == Tuning.MEADOW_SHEEP and sim.residents.all(func(r): return not r.away), "v%d: older saves get a full meadow" % v)
		if v >= 12:
			check(sim.residents[0].kept.pick, "v%d: a chosen tool stays chosen" % v)
		else:
			check(sim.residents.all(func(r): return r.kept == {"axe": false, "pick": false}), "v%d: no tool was chosen in older saves" % v)
		if v >= 11:
			check(Sim.level(sim.residents[0], "build") == 3, "v%d: skills survive" % v)
		else:
			check(sim.residents[0].jobs.values().all(func(j): return j.xp == 0 or v >= 11), "v%d: older saves start at level 1" % v)
		if v >= 10:
			check(sim.residents[0].jobs.haul.pri == 1 and not sim.residents[0].jobs.hunt.on, "v%d: job toggles and priorities survive" % v)
		else:
			check(sim.residents.all(func(r): return r.jobs == Sim.default_jobs()), "v%d: residents get every job on at priority 2" % v)
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
	var tools: Array = r.data.state.items.values().filter(func(it): return Defs.is_tool_item(it.type))
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
	loaded.designate_mine(Rect2i(0, 0, loaded.w, loaded.h))
	for b in loaded.boulders:
		b.des = false
	for i in 60:
		run(loaded, 0.5)
		if bo.axe != null:
			break
	check(bo.axe != null and bo.axe.type == "wood_axe" and bo.axe.dur == 3, "the next resident picks it up with its 3 uses (%s)" % [bo.axe])


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
	check(a.sheep.size() == 6, "six sheep at the start")
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
	check(count(sim, "wool") == 6 and count(sim, "mutton") >= 5, "six sheep give 6 wool and 6 mutton, less any Ada ate (%d, %d)" % [count(sim, "wool"), count(sim, "mutton")])
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
	var sim := Sim.new_game()
	var s := play_opening(sim)
	check(s.h1.stage == 4 and s.h2.stage == 4, "both opening houses got their beds")
	check(sim.stats.get("sheep_hunted", 0) == 6, "the six sheep were hunted for wool")
	check(Goals.LIST[5].t == "Hunt sheep for wool" and Goals.done(sim, 5), "the founding goals include hunting for wool")
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
	check(up.data.state.sites.filter(func(x): return x.tpl == "house" and x.done).all(func(x): return x.stage == 4), "older saves' finished houses get a finished bed")


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


func test_jobs_on_off_and_priorities() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	check(ada.jobs == Sim.default_jobs() and ada.jobs.size() == 8, "Ada starts with all 8 jobs on at priority 2")
	# Haul off: loose logs are never hauled, and the stuck list says no one does it.
	sim.paint_zone(open_rect(sim, Vector2i(2, 1)))
	sim.drop_items(Sim.rcell(ada) + Vector2i(1, 0), "log", 4)
	sim.set_job_on(ada, "haul", false)
	var hauled := false
	for i in 20 * Tuning.TPS:
		sim.step()
		if ada.job != null and ada.job.kind == "haul":
			hauled = true
	check(not hauled and count(sim, "log") == 4, "with Haul off, Ada never hauls")
	check(stuck_text(sim).contains("No one does Haul"), "and the stuck list says no one does Haul: " + stuck_text(sim))
	sim.set_job_on(ada, "haul", true)
	run(sim, 20)
	check(sim.items.values().all(func(it): return sim.in_zone(it.cell)), "Haul back on: the logs are hauled")
	check(not stuck_text(sim).contains("No one does"), "and the reason goes away")
	# Priority 1 work comes before priority 2, against Slice 1's order (mining before hauling).
	var sim2 := Sim.new_game()
	var a2: Dictionary = sim2.residents[0]
	sim2.paint_zone(open_rect(sim2, Vector2i(2, 1)))
	sim2.drop_items(Sim.rcell(a2) + Vector2i(0, 1), "cobble", 4)
	sim2.designate_mine(whole_map())
	run(sim2, 1)
	check(a2.job != null and a2.job.work == "mine", "at equal priorities, mining comes before hauling (%s)" % (a2.job.work if a2.job else "idle"))
	sim2.set_job_priority(a2, "haul", 1)
	check(a2.job != null and a2.job.work == "mine", "changing a priority doesn't interrupt the current job")
	sim2.fail_job(a2)
	run(sim2, 0.1)
	check(a2.job != null and a2.job.work == "haul", "with Haul at priority 1, she hauls first (%s)" % (a2.job.work if a2.job else "idle"))
	# Switching off the job she's doing stops it.
	sim2.set_job_on(a2, "haul", false)
	check(a2.job == null or a2.job.work != "haul", "switching a job off stops it")
	# Direct orders still work with every job off.
	for jb in Defs.JOBS:
		sim2.set_job_on(a2, jb, false)
	run(sim2, 2)
	check(a2.job == null, "with every job off, she claims nothing")
	var tree: Dictionary = Sim.nearest(sim2.trees.filter(func(t): return t.alive and t.claim == 0), Sim.rcell(a2))
	sim2.direct_order(a2, tree)
	run(sim2, 1)
	check(a2.job != null and is_same(a2.job.target, tree), "a direct order still works with every job off")
	check(stuck_text(sim2).contains("No one does Mine"), "and the other marked trees say no one mines: " + stuck_text(sim2))
	# Eating comes before jobs, and is never switched off.
	a2.hunger = 30.0
	sim2.fail_job(a2)
	run(sim2, 0.1)
	check(a2.job != null and a2.job.kind == "eat", "a hungry resident eats even with every job off")
	# Station work is split by job: with Toolsmith off, Ada makes planks but not the pickaxe.
	var sim3 := Sim.new_game()
	var a3: Dictionary = sim3.residents[0]
	var bench := sim3.place_site("bench", open_rect(sim3, Vector2i(3, 3)).position + Vector2i(1, 0))
	bench.stage = 1
	bench.done = true
	sim3.drop_items(Sim.rcell(a3) + Vector2i(1, 0), "log", 4)
	sim3.set_job_on(a3, "toolsmith", false)
	for r in ["planks", "planks", "sticks", "wood_pick"]:
		sim3.queue_add(bench, r)
	run(sim3, 60)
	check(bench.queue == ["wood_pick"], "with Toolsmith off, the pickaxe waits (%s)" % [bench.queue])
	check(stuck_text(sim3).contains("No one does Toolsmith"), "and says why: " + stuck_text(sim3))
	sim3.set_job_on(a3, "toolsmith", true)
	run(sim3, 20)
	check(sim3.stats.pick_crafted, "Toolsmith on: the pickaxe is made")
	# Jobs survive a save.
	var loaded := Sim.from_state(str_to_var(var_to_str(sim2.save_state())))
	check(loaded.residents[0].jobs == a2.jobs, "job settings survive a save")


## Experience that puts a resident at `lv` in a job.
func set_level(r: Dictionary, job: String, lv: int) -> void:
	r.jobs[job].xp = 0 if lv <= 1 else Tuning.SKILL_LEVELS[lv - 2]


func test_skills_rise_and_pay_off() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	# Levels rise at 8, 25, 50 and 90 points and stop at 5.
	check(Sim.level(ada, "mine") == 1, "everyone starts at level 1")
	for i in 7:
		sim.gain_xp(ada, "mine")
	check(Sim.level(ada, "mine") == 1 and is_equal_approx(Sim.level_progress(ada, "mine"), 7.0 / 8.0), "7 points: still level 1, most of the way to 2")
	sim.events.clear()
	sim.gain_xp(ada, "mine")
	check(Sim.level(ada, "mine") == 2, "8 points: level 2")
	check(sim.events.any(func(e): return e.text == "Ada is now level 2 at Mine."), "a new level gets a toast")
	for pair in [[24, 2], [25, 3], [49, 3], [50, 4], [89, 4], [90, 5], [500, 5]]:
		ada.jobs.mine.xp = pair[0]
		check(Sim.level(ada, "mine") == pair[1], "%d points is level %d" % pair)
	# Each finished task gives a point in its job.
	var sim2 := Sim.new_game()
	var a2: Dictionary = sim2.residents[0]
	var tree: Dictionary = Sim.nearest(sim2.trees, Sim.rcell(a2))
	sim2.direct_order(a2, tree)
	run(sim2, 40)
	check(a2.jobs.mine.xp == 1, "felling a tree, even by direct order, gives 1 Mine point")
	# Faster: each level above 1 is 15% faster. Better: level 3 drops an extra log.
	var sim3 := Sim.new_game()
	var a3: Dictionary = sim3.residents[0]
	set_level(a3, "mine", 3)
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
	set_level(a3, "mine", 5)
	check(Sim.skill_bonus(a3, "mine") == 2, "level 5 gets 2 extra")
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
	sim2.direct_order(a2, t8)
	run(sim2, 0.1)
	sim2.set_job_on(a2, "mine", false)
	check(a2.job != null and is_same(a2.job.target, t8), "switching Mine off doesn't cancel a direct mining order")


func test_toolsmith_keeps_spares() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
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
	check(bench.queue.has("wood_axe"), "the toolsmith queues the next spare")
	# The best tier the bench can make: stone once there's cobblestone.
	var sim2 := Sim.new_game()
	var a2: Dictionary = sim2.residents[0]
	var b2 := sim2.place_site("bench", open_rect(sim2, Vector2i(3, 3)).position + Vector2i(1, 0))
	b2.stage = 1
	b2.done = true
	a2.pick = {"type": "wood_pick", "tier": 1, "dur": 5}
	sim2.drop_items(Sim.rcell(a2) + Vector2i(1, 0), "cobble", 3)
	run(sim2, 1)
	check(b2.queue.has("stone_pick"), "with cobblestone about, the spare is a stone pickaxe (%s)" % [b2.queue])
	check(stuck_text(sim2).contains("Toolsmith needs 2 more sticks for a spare pickaxe"), "short of sticks, it says so: " + stuck_text(sim2))
	# No toolsmith: Slice 1's rule. Nothing is queued, and a broken tool stops the resident.
	var sim3 := Sim.new_game()
	var a3: Dictionary = sim3.residents[0]
	var b3 := sim3.place_site("bench", open_rect(sim3, Vector2i(3, 3)).position + Vector2i(1, 0))
	b3.stage = 1
	b3.done = true
	sim3.set_job_on(a3, "toolsmith", false)
	a3.axe = {"type": "wood_axe", "tier": 1, "dur": 1}
	sim3.drop_items(Sim.rcell(a3) + Vector2i(1, 0), "plank", 6)
	sim3.drop_items(Sim.rcell(a3) + Vector2i(-1, 0), "stick", 4)
	var t3: Dictionary = Sim.nearest(sim3.trees, Sim.rcell(a3))
	sim3.direct_order(a3, t3)
	run(sim3, 30)
	check(b3.queue.is_empty(), "with no toolsmith, no spares are queued")
	check(a3.axe == null and stuck_text(sim3).contains("Axe broke. Needs a new axe"), "and a broken axe stops and reports: " + stuck_text(sim3))


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


func test_meadow_trips() -> void:
	var sim := Sim.new_game()
	var ada: Dictionary = sim.residents[0]
	check(sim.meadow_sheep == 8, "the meadow starts with 8 sheep")
	sim.designate_mine(whole_map())
	sim.send_to_meadow(ada)
	run(sim, 0.1)
	check(ada.job != null and ada.job.kind == "trip", "Send to the meadow: Ada heads for the signpost")
	until_away(sim, ada)
	check(ada.away, "she walks off the map and is away")
	var hunger: float = ada.hunger
	check(absf(sim.back_in(ada) - Tuning.MEADOW_TRIP) < 0.5, "back in about %d seconds (%.1f)" % [int(Tuning.MEADOW_TRIP), sim.back_in(ada)])
	run(sim, 45)
	check(ada.away and ada.job == null and ada.hunger == hunger, "while away she doesn't work or get hungry")
	sim.direct_order(ada, null, Sim.rcell(ada) + Vector2i(1, 0))
	check(ada.direct == null, "orders can't reach her while she's away")
	# Saving mid-trip keeps her away.
	var loaded := Sim.from_state(str_to_var(var_to_str(sim.save_state())))
	var la: Dictionary = loaded.residents[0]
	check(la.away and la.back_at == ada.back_at, "saving mid-trip keeps her away, due back at the same time")
	run(sim, Tuning.MEADOW_TRIP - 45 + 1)
	check(not ada.away, "she's back after the trip")
	check(count(sim, "wool") == 2 and count(sim, "mutton") == 2, "with 2 wool and 2 raw mutton (%d, %d)" % [count(sim, "wool"), count(sim, "mutton")])
	check(sim.meadow_sheep == 6, "the meadow has 6 sheep left")
	run(loaded, Tuning.MEADOW_TRIP)
	check(not la.away and loaded.meadow_sheep == 6, "the loaded game's trip comes back too")
	# Two at once, then the meadow runs out.
	var tomas := sim.add_resident("Tomas", "8C4F6B", Sim.rcell(ada))
	sim.meadow_sheep = 3
	sim.send_to_meadow(ada)
	sim.send_to_meadow(tomas)
	until_away(sim, tomas)
	run(sim, Tuning.MEADOW_TRIP + 1)
	check(sim.meadow_sheep == 0 and count(sim, "wool") == 2 + 3, "two residents bring back what the meadow had: 3 sheep (%d wool)" % count(sim, "wool"))
	sim.meadow_regrow = 0.0
	sim.send_to_meadow(ada)
	run(sim, 0.5)
	check(stuck_text(sim).contains("Meadow has no sheep left"), "planning a trip to an empty meadow says so: " + stuck_text(sim))
	until_away(sim, ada)
	run(sim, Tuning.MEADOW_TRIP + 1)
	check(count(sim, "wool") == 5, "and the trip comes back with nothing")
	# The meadow regains a sheep every 4 minutes, up to 8.
	sim.meadow_sheep = 0
	sim.meadow_regrow = 0.0
	run(sim, Tuning.MEADOW_REGROW + 1)
	check(sim.meadow_sheep == 1, "the meadow regains a sheep after %d seconds" % int(Tuning.MEADOW_REGROW))
	sim.meadow_sheep = 8
	run(sim, Tuning.MEADOW_REGROW + 1)
	check(sim.meadow_sheep == 8, "and never more than 8")
	check(sim.placement_check("bench", sim.meadow_sign()) == "The meadow signpost is in the way", "nothing can be built on the signpost")
