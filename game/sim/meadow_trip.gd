class_name MeadowTrip
extends RefCounted
## the meadow (issues #50, #137), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## The signpost on the village's west edge, where the walk to the meadow starts and ends.
static func meadow_sign(sim: Sim) -> Vector2i:
	return Vector2i(0, sim.maps.village.h / 2)


## The signpost a destination's party leaves from and comes home to: west for the meadow, east for
## the old mine (issue #136).
static func sign_for(sim: Sim, dest: String) -> Vector2i:
	if Sim.realm_of(dest) == "nether":  # a Nether party gathers in front of the portal (issue #148)
		var p := village_portal(sim)
		return Sim.staging_cells(p)[1] if not p.is_empty() else sim.route_sign()
	return meadow_sign(sim) if Adventures.def(dest).sign == "west" else sim.route_sign()


## The village's finished portal, or {} (issue #148).
static func village_portal(sim: Sim) -> Dictionary:
	for s in sim.maps.village.sites:
		if s.tpl == "portal" and s.done:
			return s
	return {}


static func portal_lit(sim: Sim) -> bool:
	return village_portal(sim).get("lit", false)


## Each species at the meadow grows back on its own, one animal at a time, up to its herd (issue #137).
## New animals wander in at the far west edge.
static func _regrow_herds(sim: Sim) -> void:
	var herd := Meadow.herd()
	var wild := {}  # pens don't count (issue #139)
	for a in sim.m.sheep:
		if a.alive and a.get("pen", 0) == 0:
			wild[a.species] = wild.get(a.species, 0) + 1
	for sp in herd:
		if wild.get(sp, 0) >= herd[sp]:
			sim.m.regrow.erase(sp)
			continue
		sim.m.regrow[sp] = sim.m.regrow.get(sp, 0.0) + Tuning.DT
		if sim.m.regrow[sp] < Tuning.MEADOW_REGROW[sp]:
			continue
		sim.m.regrow[sp] = 0.0
		for i in 20:
			var c := Vector2i(sim.rng.randi_range(0, 2), sim.rng.randi_range(1, sim.m.h - 2))
			if sim.walkable(c):
				sim.m.sheep = sim.m.sheep.filter(func(a): return a.alive or a.claim != 0)  # the hunted are gone for good
				sim.add_animal(c, sp)
				sim.rev += 1
				break


## What's at the meadow now: animals of each species, alive.
static func herds(sim: Sim, id := Meadow.ID) -> Dictionary:
	var out := {}
	for a in sim.maps[id].sheep:
		if a.alive:
			out[a.species] = out.get(a.species, 0) + 1
	return out


## Seconds until an away resident is back.
static func back_in(sim: Sim, r: Dictionary) -> float:
	return maxf(0.0, float(r.back_at - sim.tick) / Tuning.TPS)
