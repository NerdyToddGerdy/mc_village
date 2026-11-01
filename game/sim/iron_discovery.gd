class_name IronDiscovery
extends RefCounted
## the iron discovery (issue #111), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## Mining near the hidden vein finds it: it's revealed, and the game stops for the player to choose.
static func _check_find(sim: Sim, c: Vector2i) -> void:
	if sim.m.found or sim.m.kind != "site":
		return
	if not sim.m.boulders.any(func(b): return b.alive and b.get("hidden", false) and Sim.manhattan(b.cell, c) <= Tuning.FIND_RADIUS):
		return
	_find_vein(sim)
	sim._toast("The party found iron in the %s." % sim.m.name.to_lower())
	if sim.expedition.get("state", "") == "out" and sim.expedition.dest == sim.map_id:
		sim._ask("discovery", "The party found an iron vein in the %s." % sim.m.name.to_lower(), [
			{"id": "keep", "label": "Keep mining", "cost": "Carry on for %s. The vein stays marked." % sim.objective_text()},
			{"id": "investigate", "label": "Investigate", "cost": "Someone spends about %d s and %d pickaxe uses surveying it. Iron becomes a resource you can send a party for." % [int(Tuning.SURVEY_TIME), Tuning.SURVEY_USES]},
			{"id": "return", "label": "Mark it and return later", "cost": "The party heads home now, with what it has packed."},
		])


## Mining next to a hidden diamond finds the level's diamonds (issue #186): they're revealed, diamonds become
## a known resource of the level, and, with the party working here, the game stops for the player.
static func _check_find_diamond(sim: Sim, c: Vector2i) -> void:
	if sim.m.diamond_found or sim.m.kind != "site":
		return
	if not sim.m.boulders.any(func(b): return b.alive and b.get("ore", "") == "diamond" and b.get("hidden", false) and Sim.manhattan(b.cell, c) <= Tuning.FIND_RADIUS):
		return
	sim.m.diamond_found = true
	for b in sim.m.boulders:
		if b.get("ore", "") == "diamond":
			b.erase("hidden")
	sim.rev += 1
	sim._toast("The party found diamonds on level %d." % sim.m.level)
	if sim.expedition.get("state", "") == "out" and sim.expedition.dest == sim.map_id:
		sim._ask("discovery", "The party found diamonds on level %d of the old mine." % sim.m.level, [
			{"id": "keep", "label": "Keep mining", "cost": "Carry on for %s. Diamonds can only be mined with an iron pickaxe." % sim.objective_text()},
			{"id": "return", "label": "Mark it and return later", "cost": "The party heads home now, with what it has packed."},
		])


## The vein is revealed: it can be seen, marked and mined, though its size isn't known yet.
static func _find_vein(sim: Sim) -> void:
	sim.m.found = true
	for b in sim.m.boulders:
		if b.get("ore", "") != "diamond":  # diamonds have a find of their own (issue #186)
			b.erase("hidden")
	sim.rev += 1


## Walking to the vein and surveying it, at the cost of time and pickaxe uses.
static func _survey_job(sim: Sim, r: Dictionary):
	var vein := sim.m.boulders.filter(func(b): return b.alive and b.get("ore", "") == "iron")
	if vein.is_empty():
		sim.expedition.survey = false
		return null
	var j := Job.new("survey", "Going to investigate the vein", "the iron vein")
	j.work = "mason"
	j.step(sim._goto(vein.map(func(b): return b.cell), true))
	j.step({"op": "work", "what": "survey", "label": "Investigating the vein"})
	return j


## The vein is surveyed: iron is a known resource, with an estimate.
static func survey(sim: Sim, id: String) -> void:
	var mp: SimMap = sim.maps[id]
	mp.found = true
	mp.discovered = true
	for b in mp.boulders:
		b.erase("hidden")
	sim.rev += 1
