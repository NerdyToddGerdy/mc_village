class_name Pens
extends RefCounted
## pens and breeding (issue #139), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## What the party packs for the pens: sticks for fences, wheat to feed pairs.
const PEN_SUPPLIES := ["stick", "wheat"]


## The cells round a pen's edge: its fences and its gate.
static func pen_edge(p: Dictionary) -> Array:
	var r: Rect2i = p.rect
	var out: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1:
				out.append(Vector2i(x, y))
	return out


## The cells inside a pen's fences.
static func pen_inside(p: Dictionary) -> Rect2i:
	return Rect2i(p.rect).grow(-1)


## Whether every fence and the gate are up.
static func pen_done(p: Dictionary) -> bool:
	return p.built.size() >= pen_edge(p).size()


## How many animals a pen holds: one for each cell inside it.
static func pen_room(p: Dictionary) -> int:
	return pen_inside(p).get_area()


static func pen(sim: Sim, id: int) -> Dictionary:
	for p in sim.m.pens:
		if p.id == id:
			return p
	return {}


## The pen whose fences or inside cover a cell, or null.
static func pen_at(sim: Sim, c: Vector2i):
	for p in sim.m.pens:
		if Rect2i(p.rect).has_point(c):
			return p
	return null


## The animals in a pen.
static func penned(sim: Sim, p: Dictionary) -> Array:
	return sim.m.sheep.filter(func(a): return a.alive and a.get("pen", 0) == p.id)


## Room left in a pen, less the animals on their way in.
static func pen_free(sim: Sim, p: Dictionary) -> int:
	var n := penned(sim, p).size()
	for a in sim.m.sheep:
		if a.alive and a.get("led_to", 0) == p.id:
			n += 1
	return pen_room(p) - n


## Why a pen can't be painted over `rect`, or "" when it can.
static func pen_check(sim: Sim, rect: Rect2i) -> String:
	if sim.m.id != Meadow.ID:
		return "Pens go at the meadow"
	if mini(rect.size.x, rect.size.y) < Tuning.PEN_MIN:
		return "A pen needs at least %d×%d, fences included" % [Tuning.PEN_MIN, Tuning.PEN_MIN]
	if maxi(rect.size.x, rect.size.y) > Tuning.PEN_MAX:
		return "A pen is at most %d×%d" % [Tuning.PEN_MAX, Tuning.PEN_MAX]
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			if not sim.m.in_bounds(c):
				return "Pens go on the meadow, not past its edge"
			if sim.m.water.has(c) or sim.m.banks.has(c):
				return "Pens can't go on the pond"
			if sim.m.fences.has(c) and pen_at(sim, c) == null:
				return "Pens can't go on the old fences"
			if sim.m.trees.any(func(t): return t.alive and t.cell == c):
				return "Pens can't go on a tree"
			if c == sim.m.entrance:
				return "Pens can't go on the way in"
			if pen_at(sim, c) != null:
				return "Pens can't overlap"
	return ""


## Paints a pen (issue #139): fences round the edge, with the gate in the middle of the side nearest
## the entrance. The party builds it with the sticks it packs. Returns why it can't, or "".
static func paint_pen(sim: Sim, rect: Rect2i) -> String:
	var why := pen_check(sim, rect)
	if why != "":
		return why
	var mid := rect.position + rect.size / 2
	var gates := [Vector2i(rect.end.x - 1, mid.y), Vector2i(mid.x, rect.position.y), Vector2i(mid.x, rect.end.y - 1), Vector2i(rect.position.x, mid.y)]
	var gate: Vector2i = gates[0]
	for g in gates:
		if Sim.manhattan(g, sim.m.entrance) < Sim.manhattan(gate, sim.m.entrance):
			gate = g
	sim.m.pens.append({"id": sim._id(), "kind": "pen", "rect": rect, "gate": gate, "built": {}})
	sim.rev += 1
	return ""


## Takes a pen down: its fences come down and its animals go free.
static func remove_pen(sim: Sim, p: Dictionary) -> void:
	for r in sim.residents:
		if r.job != null and r.map == sim.map_id and (is_same(r.job.target, p) or r.job.steps.any(func(s): return is_same(s.get("pen"), p))):
			sim.fail_job(r)
	for c in p.built:
		sim.m.fences.erase(c)
		sim.m.gates.erase(c)
	for a in sim.m.sheep:
		if a.get("pen", 0) == p.id:
			a.pen = 0
	sim.m.pens.erase(p)
	sim._occ_dirty = true
	sim.rev += 1


## Sticks still needed for the fences of the pens painted on a map.
static func fence_left(sim: Sim, id := Meadow.ID) -> int:
	if not sim.maps.has(id):
		return 0
	var n := 0
	for p in sim.maps[id].pens:
		n += pen_edge(p).size() - p.built.size()
	return n * Tuning.FENCE_STICKS


## Pairs in a pen that can be fed now: two grown animals of a kind, neither fed nor resting from
## breeding, with room in the pen for the young one.
static func feed_pairs(sim: Sim, p: Dictionary) -> Array:
	var out: Array = []
	if not pen_done(p):
		return out
	var by := {}
	var fed := 0
	for a in penned(sim, p):
		if a.get("fed_at", -1) >= 0:
			fed += 1
		elif not a.get("young", false) and a.get("cool_until", 0) <= sim.tick and not a.des and a.claim == 0:
			if not by.has(a.species):
				by[a.species] = []
			by[a.species].append(a)
	var free := pen_free(sim, p) - (fed + 1) / 2
	for sp in by:
		var l: Array = by[sp]
		var i := 0
		while i + 1 < l.size() and out.size() < free:
			out.append([l[i], l[i + 1]])
			i += 2
	return out


## Wheat to feed every pair that could be fed in a map's pens now.
static func wheat_wanted(sim: Sim, id := Meadow.ID) -> int:
	if not sim.maps.has(id):
		return 0
	return sim.on_map(id, func():
		var n := 0
		for p in sim.m.pens:
			n += feed_pairs(sim, p).size()
		return n * 2 * Tuning.FEED_WHEAT)


## Whether the party is tending the pens (issue #139) rather than bringing something back.
static func tending(sim: Sim) -> bool:
	return sim.expedition.get("target", {}).get("item", "") == "pens"
