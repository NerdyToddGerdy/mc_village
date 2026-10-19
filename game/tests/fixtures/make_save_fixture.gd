extends SceneTree
## Writes tests/fixtures/save_v<VERSION>.save: a real save from the middle of the opening, taken
## while Tomas is walking in (a state that has to be rebuilt on load). Run it once per new save
## format version, from game/:
##   godot --headless --path . -s res://tests/fixtures/make_save_fixture.gd
## Never regenerate an existing fixture: old fixtures are what prove old saves still load.


func _initialize() -> void:
	var sim := Sim.new_game()
	sim.designate_mine(area(0, 0, 10, 18))
	var bench := sim.place_site("bench", at(8, 10))
	_run(sim, 120)
	for r in ["planks", "planks", "sticks", "wood_pick"]:
		sim.queue_add(bench, r)
	_run(sim, 120)
	sim.paint_zone(area(10, 7, 4, 2))
	sim.designate_mine(Rect2i(0, 0, sim.w, sim.h))
	_run(sim, 150)
	sim.place_site("house", at(11, 0))
	for i in 8:
		sim.queue_add(bench, "planks")
	_run(sim, 600)
	sim.place_site("house", at(1, 4), 1)
	for i in 8:
		sim.queue_add(bench, "planks")
	var walked := 0
	for i in 1200 * Tuning.TPS:
		sim.step()
		if sim.residents.size() == 2 and sim.residents[1].arriving:
			walked += 1
			if walked >= Tuning.TPS:  # a second into the walk
				break
	sim.queue_add(bench, "stone_axe")
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
	var path := "res://tests/fixtures/save_v%d.save" % SaveFormat.VERSION
	var data := {"summary": Goals.progress_text(sim), "tick": sim.tick, "saved_at": 1792440000,
		"state": sim.save_state(), "camera": {"target": Vector3(9, 0, 9), "size": 17.0}, "speed": 1}
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
