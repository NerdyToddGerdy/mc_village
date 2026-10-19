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
		"test_mine_marks_trees_and_boulders",
		"test_save_and_load_mid_game",
		"test_tool_breaks_and_resident_reports",
	]
	for t in tests:
		_current = t
		call(t)
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


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
	sim.designate_mine(Rect2i(0, 0, 10, 18))
	var bench := sim.place_site("bench", Vector2i(8, 10))
	run(sim, 120)
	for r in ["planks", "planks", "sticks", "wood_pick"]:
		sim.queue_add(bench, r)
	run(sim, 120)
	sim.paint_zone(Rect2i(10, 7, 4, 2))
	sim.designate_mine(whole_map())
	run(sim, 150)
	var h1 := sim.place_site("house", Vector2i(11, 0))
	for i in 8:
		sim.queue_add(bench, "planks")
	run(sim, 600)
	var h2 := sim.place_site("house", Vector2i(1, 4), 1)
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


func test_bench_skips_blocked_recipes_and_comes_before_building() -> void:
	var sim := Sim.new_game()
	sim.designate_mine(Rect2i(0, 0, 10, 18))
	var bench := sim.place_site("bench", Vector2i(8, 10))
	run(sim, 120)
	check(bench.done, "bench built")
	var house := sim.place_site("house", Vector2i(11, 4))
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
	sim.designate_mine(Rect2i(0, 0, 10, 18))
	var bench := sim.place_site("bench", Vector2i(8, 10))
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
	check(sim.placement_check("bench", Vector2i(4, 6)) == "", "tree doesn't block placement")
	var bench := sim.place_site("bench", Vector2i(4, 6))
	var tree: Dictionary = sim.trees.filter(func(t): return t.cell == Vector2i(4, 6))[0]
	check(tree.des, "tree under the blueprint is marked")
	run(sim, 120)
	check(not tree.alive and bench.done, "tree cleared and bench built from its logs")
	var house := sim.place_site("house", Vector2i(5, 3))
	var boulder: Dictionary = sim.boulders.filter(func(b): return b.cell == Vector2i(7, 5))[0]
	check(boulder.des, "boulder under the blueprint is marked")
	run(sim, 1)
	check(stuck_text(sim).contains("Needs a pickaxe to clear a boulder"), "house says what it's waiting for: " + stuck_text(sim))
	check(house.store.is_empty(), "no deliveries while the ground isn't clear")
	check(sim.placement_check("house", Vector2i(3, 3)) == "Overlaps another building", "buildings still can't overlap")


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
	sim.designate_mine(Rect2i(0, 0, 10, 18))
	var bench := sim.place_site("bench", Vector2i(8, 10))
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
	loaded.paint_zone(Rect2i(10, 7, 4, 2))
	loaded.designate_mine(whole_map())
	run(loaded, 150)
	var h := loaded.place_site("house", Vector2i(11, 0))
	for i in 8:
		loaded.queue_add(b2, "planks")
	run(loaded, 600)
	check(h.done, "loaded game can still build a house")


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
