class_name LeadHome
extends RefCounted
## The hunter leads animals home from the meadow (issues #355, #275). A hunter who works a finished lodge, with a pen standing in the
## village that has room, goes to the meadow on their own and brings back up to three animals the player marked to be led, one trip at a
## time, at walking pace: gone for the walk there and back. The animals are taken off the meadow when the hunter sets out and are in
## `stats.lead_home` while they walk (so a save in the middle keeps them), and are penned in the village when the hunter returns.
## Every function takes the Sim it works on.

const MAX_LED := 3  ## animals on a lead at once (issue #355)


## A finished village pen with room for `n` more, or {}.
static func pen_with_room(sim: Sim, n: int) -> Dictionary:
	for p in sim.maps.village.pens:
		if Pens.pen_done(p):
			var penned: int = sim.maps.village.sheep.filter(func(a): return a.alive and a.get("pen", 0) == p.id).size()
			if Pens.pen_room(p) - penned >= n:
				return p
	return {}


## The lodge's hunter: a resident working a finished lodge, at home and fit, or {}.
static func hunter(sim: Sim) -> Dictionary:
	for s in sim.maps.village.sites:
		if s.tpl == "lodge" and s.done and s.get("worker", 0) != 0:
			var r := sim.resident(s.worker)
			if not r.is_empty() and not r.away and r.map == "village" and r.get("hurt", 0) == 0 and sim.expedition_of(r).is_empty():
				return r
	return {}


## The meadow's animals marked to be led home that nobody has taken, nearest the way home first.
static func marked(sim: Sim) -> Array:
	var out: Array = []
	if not sim.maps[Meadow.ID].known:
		return out
	for a in sim.maps[Meadow.ID].sheep:
		if a.alive and a.get("lead", false) and a.get("pen", 0) == 0 and a.claim == 0:
			out.append(a)
	out.sort_custom(func(x, y): return x.cell.x < y.cell.x)
	return out


## Why the hunter can't set out now, or "" when they can.
static func check(sim: Sim) -> String:
	if not sim.stats.get("lead_home", {}).is_empty():
		return "A hunter is already out"
	if hunter(sim).is_empty():
		return "Nobody works the lodge"
	if marked(sim).is_empty():
		return "No animal at the meadow is marked to lead home"
	if pen_with_room(sim, 1).is_empty():
		return "The village has no pen with room"
	return ""


## Seconds for the walk there and back.
static func seconds(sim: Sim) -> float:
	return 2.0 * float(sim.site_report(Meadow.ID).travel)


## Looks once a second for a trip to make. The hunter takes as many marked animals as fit a pen, up to MAX_LED.
static func step(sim: Sim) -> void:
	if sim.tick % Tuning.TPS != 0 or sim.map_id != "village" or check(sim) != "":
		return
	var r := hunter(sim)
	var leads := marked(sim)
	var pen := pen_with_room(sim, 1)
	var room := mini(MAX_LED, leads.size())
	while room > 1 and pen_with_room(sim, room).is_empty():
		room -= 1
	pen = pen_with_room(sim, room)
	var taken: Array = []
	for a in leads.slice(0, room):
		sim.maps[Meadow.ID].sheep.erase(a)
		a.lead = false
		a.claim = 0
		taken.append(a)
	if r.job != null:
		sim.fail_job(r)
	r.away = true
	r.trip = "lead_home"
	r.back_at = sim.tick + int(seconds(sim) * Tuning.TPS)
	r.path = []
	sim.stats.lead_home = {"who": r.id, "animals": taken, "pen": pen.id}
	sim.maps[Meadow.ID].known = true
	sim.rev += 1
	sim._toast("%s sets out for the meadow to lead %s home." % [r.name, Defs.animals(taken[0].species, taken.size()) if taken.all(func(x): return x.species == taken[0].species) else "%d animals" % taken.size()], r.id)


## The hunter is home: the animals go into the pen.
static func arrive(sim: Sim, r: Dictionary) -> void:
	var trip: Dictionary = sim.stats.get("lead_home", {})
	sim.stats.erase("lead_home")
	r.away = false
	r.trip = ""
	var lodge: Dictionary = {}
	for s in sim.maps.village.sites:
		if s.tpl == "lodge" and s.get("worker", 0) == r.id:
			lodge = s
	var spot = sim.nearest_walkable(lodge.origin if not lodge.is_empty() else Vector2i(sim.w / 2, sim.h / 2))
	sim.move_to_map(r, "village", spot if spot != null else Vector2i(sim.w / 2, sim.h / 2))
	sim.rev += 1
	if trip.is_empty():
		return
	var pen: Dictionary = {}
	for p in sim.maps.village.pens:
		if p.id == trip.pen:
			pen = p
	sim.on_map("village", func():
		var inside := Pens.pen_inside(pen) if not pen.is_empty() else Rect2i()
		var cells: Array[Vector2i] = []
		for y in range(inside.position.y, inside.end.y):
			for x in range(inside.position.x, inside.end.x):
				cells.append(Vector2i(x, y))
		var used := {}
		for a in sim.m.sheep:
			if a.alive:
				used[a.cell] = true
		for a in trip.animals:
			var c: Vector2i = Vector2i(sim.w / 2, sim.h / 2)
			for k in cells:
				if not used.has(k):
					c = k
					break
			used[c] = true
			a.cell = c
			a.pos = Vector2(c)
			a.dest = null
			a.pen = pen.id if not pen.is_empty() else 0
			a.map = "village"
			sim.m.sheep.append(a))
	sim.gain_xp(r, "hunt")
	sim.stats.led_home = sim.stats.get("led_home", 0) + trip.animals.size()
	sim._toast("%s is home with %d animals, penned in the village." % [r.name, trip.animals.size()], r.id)
