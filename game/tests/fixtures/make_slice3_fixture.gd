extends SceneTree
## Writes tests/fixtures/slice3_village.save: a Slice 3 village at its end state (issue #125), for the
## Slice 4 bot playtest to start from. It's the Slice 2 village after its first expedition: the
## expedition board built, the old mine visited and its iron vein mined out, with the iron smelted
## into ingots and an iron pickaxe made. The road to the mine is known but not walked yet. Run once,
## from game/:
##   godot --headless --path . -s res://tests/fixtures/make_slice3_fixture.gd
## Like the save fixtures, don't regenerate it: later save versions upgrade it on load.


func _initialize() -> void:
	var r := SaveFormat.read("res://tests/fixtures/slice2_village.save")
	if r.has("error"):
		printerr(r.error)
		quit(1)
		return
	var sim := Sim.from_state(r.data.state)
	# The expedition board, beside the stockpile.
	var board := {}
	for c in [Vector2i(16, 9), Vector2i(9, 20), Vector2i(20, 16), Vector2i(6, 6), Vector2i(24, 8)]:
		if sim.placement_check("board", c) == "" and sim.walkable(c):
			board = sim.place_site("board", c)
			break
	board.stage = 1
	board.done = true
	sim._on_site_done(board)
	board.report = ["Back from the old mine: 16 iron ore, 6 coal", "4 meals eaten", "Tomas seriously injured"]
	# The old mine after the first expedition: visited, the vein found, surveyed and mined out.
	var mine := sim.get_map(OldMine.ID)
	mine.visited = true
	sim.discover(OldMine.ID)
	for b in mine.boulders:
		if b.get("ore", "") == "iron":
			b.alive = false
	mine.occ_dirty = true
	sim.stats.expeditions = 1
	# What came home, smelted and stockpiled: ingots for the line, coal, and building stock.
	var z: Vector2i = sim.zone.keys()[0]
	sim.drop_items(z, "iron_ingot", 13)
	sim.drop_items(z, "coal", 2)
	sim.drop_items(z, "plank", 30)
	sim.drop_items(z, "stick", 6)
	sim.drop_items(z, "cobble", 16)
	sim.drop_items(z, "bread", 8)
	var ada: Dictionary = sim.residents[0]
	ada.pick = {"type": "iron_pick", "tier": 3, "dur": 52}
	for i in 5 * Tuning.TPS:
		sim.step()
	sim.events.clear()
	var path := "res://tests/fixtures/slice3_village.save"
	var data := {"summary": "Slice 3 done: the old mine's iron is home", "tick": sim.tick, "saved_at": 1792440000, "state": sim.save_state(),
		"camera": {"map": "village", "maps": {"village": {"target": Vector3(16, 0, 14), "size": 17.0}}}, "speed": 1}
	if SaveFormat.write(ProjectSettings.globalize_path(path), data):
		print("wrote ", path, " at tick ", sim.tick)
		quit(0)
	else:
		quit(1)
