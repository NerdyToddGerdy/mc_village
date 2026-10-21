extends SceneTree
## Writes tests/fixtures/slice2_village.save: a Slice 2 village at its end state (issue #113), for the
## Slice 3 bot playtest to start from without replaying the founding. Ada, Tomas and Mira, three
## houses, the bench and the fireplace, a stockpile with meals, planks, sticks and a spare pickaxe,
## and the founding done. Run once, from game/:
##   godot --headless --path . -s res://tests/fixtures/make_slice2_fixture.gd
## Like the save fixtures, don't regenerate it: later save versions upgrade it on load.


func _initialize() -> void:
	var sim := Sim.new_game()
	sim.residents[0].jobs.toolsmith.on = true
	sim.designate_mine(area(0, 0, 10, 18))
	sim.designate_hunt(Rect2i(0, 0, sim.w, sim.h))
	var bench := sim.place_site("bench", at(8, 10))
	_run(sim, 120)
	for r in ["planks", "planks", "sticks", "wood_pick"]:
		sim.queue_add(bench, r)
	_run(sim, 120)
	sim.paint_zone(area(10, 7, 4, 2))
	sim.designate_mine(area(0, 0, 18, 18))
	_run(sim, 150)
	sim.place_site("house", at(11, 0))
	for i in 8:
		sim.queue_add(bench, "planks")
	_run(sim, 600)
	sim.place_site("house", at(1, 4), 1)
	for i in 8:
		sim.queue_add(bench, "planks")
	for i in 1500 * Tuning.TPS:
		sim.step()
		if sim.stats.traveler_home and Goals.current(sim) < 0:
			break
	# The rest of a Slice 2 village: a fireplace, a third house (so Mira comes), and a bigger stockpile.
	for c in [at(13, 9), at(4, 12), at(15, 13), at(2, 14), at(9, 15)]:
		if sim.placement_check("fireplace", c) == "":
			var f := sim.place_site("fireplace", c)
			f.stage = 1
			f.done = true
			break
	var h3 := {}
	for c in [Vector2i(20, 20), Vector2i(19, 4), Vector2i(4, 20), Vector2i(21, 12)]:
		if sim.placement_check("house", c) == "":
			h3 = sim.place_site("house", c)
			h3.stage = 4
			h3.done = true
			sim._on_site_done(h3)
			break
	sim.rev += 1
	for i in 600 * Tuning.TPS:
		sim.step()
		if sim.residents.size() == 3 and not sim.residents[2].arriving:
			break
	sim.paint_zone(area(10, 5, 5, 6))
	var z: Vector2i = sim.zone.keys()[0]
	sim.drop_items(z, "bread", 8)
	sim.drop_items(z, "plank", 10)
	sim.drop_items(z, "stick", 6)
	sim.drop_items(z, "stone_pick", 1)
	for r in sim.residents:
		if r.pick == null:
			r.pick = {"type": "stone_pick", "tier": 2, "dur": 25}
	_run(sim, 5)
	sim.events.clear()
	if sim.residents.size() != 3 or Goals.current(sim) >= 0:
		printerr("Not a Slice 2 village yet: %d residents, founding step %d" % [sim.residents.size(), Goals.current(sim)])
		quit(1)
		return
	var path := "res://tests/fixtures/slice2_village.save"
	var data := {"summary": Goals.progress_text(sim), "tick": sim.tick, "saved_at": 1792440000, "state": sim.save_state(),
		"camera": {"map": "village", "maps": {"village": {"target": Vector3(16, 0, 14), "size": 17.0}}}, "speed": 1}
	if SaveFormat.write(ProjectSettings.globalize_path(path), data):
		print("wrote ", path, " at tick ", sim.tick, ": ", Goals.progress_text(sim))
		quit(0)
	else:
		quit(1)


func _run(sim: Sim, seconds: float) -> void:
	for i in int(seconds * Tuning.TPS):
		sim.step()


static func at(x: int, y: int) -> Vector2i:
	return Vector2i(x, y) + Tuning.OPENING_OFFSET


static func area(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(Vector2i(x, y) + Tuning.OPENING_OFFSET, Vector2i(w, h))
