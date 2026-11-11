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


## Penned animals over the herd size the party keeps of each kind, when tending the pens: grown ones
## that aren't waiting to breed.
static func pen_surplus(sim: Sim) -> Array:
	var by := {}
	for a in sim.m.sheep:
		if a.alive and a.get("pen", 0) != 0:
			if not by.has(a.species):
				by[a.species] = []
			by[a.species].append(a)
	var out: Array = []
	for sp in by:
		var grown: Array = by[sp].filter(func(a): return not a.get("young", false) and a.get("fed_at", -1) < 0)
		out.append_array(grown.slice(0, maxi(0, by[sp].size() - sim.expedition.target.n)))
	return out


## Whether the party can still do something for the pens: build a fence with the sticks it has, lead
## a marked animal into a pen with room, or feed a pair with the wheat it has.
static func pen_work(sim: Sim) -> bool:
	var sup: Dictionary = sim.expedition.get("supplies", {})
	if sup.get("stick", 0) >= Tuning.FENCE_STICKS and sim.m.pens.any(func(p): return not sim.pen_done(p)):
		return true
	if sim.m.sheep.any(func(a): return a.alive and a.get("lead", false) and a.get("pen", 0) == 0) and sim.m.pens.any(func(p): return sim.pen_done(p) and sim.pen_free(p) > 0):
		return true
	return sup.get("wheat", 0) >= 2 * Tuning.FEED_WHEAT and sim.m.pens.any(func(p): return not sim.feed_pairs(p).is_empty())


## Marks animals to be led into a pen (the Lead order), or unmarks them. Penned animals are left alone.
static func designate_lead(sim: Sim, rect: Rect2i, single = null) -> void:
	var hit: Array = [single] if single != null else sim.m.sheep.filter(func(a): return a.alive and rect.has_point(a.cell))
	hit = hit.filter(func(a): return a.get("pen", 0) == 0)
	var all_on := not hit.is_empty() and hit.all(func(a): return a.get("lead", false))
	for a in hit:
		a.lead = not (single != null and all_on)
		a.unreach_until = 0
		if a.lead and a.des:
			a.des = false
			if a.claim != 0:
				var r := sim.resident(a.claim)
				if not r.is_empty() and r.job != null and r.job.kind == "gather" and is_same(r.job.target, a):
					sim.fail_job(r)
	sim.rev += 1


## Building a pen's fences: sticks from the packs at the entrance, then a fence at a time, nearest
## first, and any sticks left over back into the packs.
static func _fence_job(sim: Sim, r: Dictionary, c: Vector2i):
	var have: int = sim.expedition.get("supplies", {}).get("stick", 0)
	var n := mini(sim.carry_cap(r), have / Tuning.FENCE_STICKS)
	if n <= 0:
		return null
	var todo: Array = []
	for p in sim.m.pens:
		for e in sim.pen_edge(p):
			if not p.built.has(e) and not sim._fence_claims.has(e):
				todo.append({"cell": e, "pen": p})
	if todo.is_empty():
		return null
	var picked: Array = []
	var at := sim.m.entrance
	while picked.size() < n and not todo.is_empty():
		var best := 0
		for i in todo.size():
			if sim.manhattan(todo[i].cell, at) < sim.manhattan(todo[best].cell, at):
				best = i
		at = todo[best].cell
		picked.append(todo.pop_at(best))
	var j := Job.new("fence", "Building a pen", "the pen")
	j.target = picked[0].pen
	j.work = "build"
	j.step(sim._goto([sim.m.entrance], false))
	j.step({"op": "take_supply", "type": "stick", "n": picked.size() * Tuning.FENCE_STICKS})
	for t in picked:
		sim._fence_claims[t.cell] = r.id
		j.hold({"t": "fence", "cell": t.cell})
		j.step(sim._goto([t.cell], true))
		j.step({"op": "work", "what": "fence", "pen": t.pen, "cell": t.cell, "label": "Building a pen"})
	j.step(sim._goto([sim.m.entrance], false))
	j.step({"op": "put_back", "type": "stick"})
	return j


## A fence or the gate goes up. Any animal standing there steps aside; once the last one is up, the
## animals inside are penned.
static func _put_fence(sim: Sim, p: Dictionary, c: Vector2i) -> void:
	p.built[c] = true
	if c == p.gate:
		sim.m.gates[c] = true
	else:
		sim.m.fences[c] = true
	sim._occ_dirty = true
	var inside := sim.pen_inside(p)
	for a in sim.m.sheep:
		if a.alive and a.cell == c:
			var to := c
			for d in sim.DIRS:
				var n: Vector2i = c + d
				if sim.walkable(n) and not sim.m.gates.has(n) and (inside.has_point(n) or to == c):
					to = n
			a.cell = to
			a.pos = Vector2(to)
			a.dest = null
	if sim.pen_done(p):
		for a in sim.m.sheep:
			if a.alive and a.get("pen", 0) == 0 and inside.has_point(a.cell):
				a.pen = p.id
				a.lead = false
		sim.stats.pens = sim.stats.get("pens", 0) + 1
		sim._toast("A pen is finished, with room for %d animals." % sim.pen_room(p))
	sim.rev += 1


## Leading a marked animal into a pen with room (issue #139): catch it, walk it to the gate, and let
## it in.
static func _lead_job(sim: Sim, r: Dictionary, c: Vector2i):
	var leads := sim.m.sheep.filter(func(a): return a.alive and a.get("lead", false) and a.get("pen", 0) == 0 and a.claim == 0 and not sim._cooling(a))
	if leads.is_empty():
		return null
	var a: Dictionary = sim.nearest(leads, c)
	var pens := sim.m.pens.filter(func(p): return sim.pen_done(p) and sim.pen_free(p) > 0)
	if pens.is_empty():
		return null
	pens.sort_custom(func(x, y): return sim.manhattan(x.gate, a.cell) < sim.manhattan(y.gate, a.cell))
	var p: Dictionary = pens[0]
	var one: String = Defs.SPECIES[a.species].one
	var j := Job.new("lead", "Going to lead a %s to the pen" % one, "this %s" % one)
	j.work = "hunt"
	j.target = a
	a.claim = r.id
	a.led_to = p.id
	j.hold({"t": "claim", "ent": a})
	j.hold({"t": "lead", "ent": a})
	j.step({"op": "chase", "target": a, "planned_for": null})
	j.step({"op": "leash", "target": a, "label": "Leading a %s to the pen" % one})
	j.step(sim._goto([p.gate], false))
	j.step({"op": "pen_in", "target": a, "pen": p})
	return j


## Feeding a pair in a pen (issue #139): wheat from the packs, one for each, and a young one follows.
static func _feed_job(sim: Sim, r: Dictionary, c: Vector2i):
	if sim.expedition.get("supplies", {}).get("wheat", 0) < 2 * Tuning.FEED_WHEAT:
		return null
	var pens: Array = sim.m.pens.duplicate()
	pens.sort_custom(func(x, y): return sim.manhattan(x.gate, c) < sim.manhattan(y.gate, c))
	for p in pens:
		var pairs := sim.feed_pairs(p)
		if pairs.is_empty():
			continue
		var pair: Array = pairs[0]
		var many: String = Defs.SPECIES[pair[0].species].many
		var j := Job.new("feed", "Going to feed a pair of %s" % many, "the pen")
		j.work = "farm"
		j.target = pair[0]
		for a in pair:
			a.claim = r.id
			j.hold({"t": "claim", "ent": a})
		j.step(sim._goto([sim.m.entrance], false))
		j.step({"op": "take_supply", "type": "wheat", "n": 2 * Tuning.FEED_WHEAT})
		j.step({"op": "chase", "target": pair[0], "planned_for": null})
		j.step({"op": "work", "what": "feed", "pair": pair, "label": "Feeding the %s" % many})
		return j
	return null


## The lodge's hunter feeding a pair in a village pen (issue #355): wheat from a stack at home, as the party feeds with the packs'.
## The young one comes after BREED_TIME, so the village herd grows by itself once it has a grown pair.
static func _village_feed_job(sim: Sim, r: Dictionary, c: Vector2i):
	var need := 2 * Tuning.FEED_WHEAT
	var stacks := sim.stacks_where(func(s): return s.type == "wheat" and sim.avail(s) >= need)
	if stacks.is_empty():
		return null
	var stack: Dictionary = sim.nearest(stacks, c)
	var pens: Array = sim.m.pens.duplicate()
	pens.sort_custom(func(x, y): return sim.manhattan(x.gate, c) < sim.manhattan(y.gate, c))
	for p in pens:
		var pairs := sim.feed_pairs(p)
		if pairs.is_empty():
			continue
		var pair: Array = pairs[0]
		var many: String = Defs.SPECIES[pair[0].species].many
		var j := Job.new("feed", "Going to feed a pair of %s" % many, "the pen")
		j.work = "hunt"
		j.target = pair[0]
		stack.res += need
		var hd := j.hold({"t": "stack", "stack": stack, "n": need})
		for a in pair:
			a.claim = r.id
			j.hold({"t": "claim", "ent": a})
		j.step(sim._goto(sim.reach(stack.cell), false))
		j.step({"op": "pickup", "stack": stack, "n": need, "hold": hd})
		j.step(sim._goto([p.gate], false))
		j.step({"op": "chase", "target": pair[0], "planned_for": null})
		j.step({"op": "work", "what": "feed", "pair": pair, "label": "Feeding the %s" % many})
		return j
	return null


## Each tick on a map with pens: fed pairs have their young, and the young grow up.
static func _step_pens(sim: Sim) -> void:
	for a in sim.m.sheep:
		if a.alive and a.get("young", false) and sim.tick >= a.grown_at:
			a.young = false
			sim.rev += 1
	for p in sim.m.pens:
		var ready := {}
		for a in sim.penned(p):
			if a.get("fed_at", -1) >= 0 and sim.tick >= a.fed_at + int(Tuning.BREED_TIME * Tuning.TPS):
				if not ready.has(a.species):
					ready[a.species] = []
				ready[a.species].append(a)
		for sp in ready:
			var l: Array = ready[sp]
			for i in range(0, l.size() - 1, 2):
				sim._breed(p, l[i], l[i + 1])


static func _breed(sim: Sim, p: Dictionary, a: Dictionary, b: Dictionary) -> void:
	for x in [a, b]:
		x.fed_at = -1
		x.cool_until = sim.tick + int(Tuning.BREED_COOLDOWN * Tuning.TPS)
	var kid := sim.add_animal(a.cell, a.species)
	kid.pen = p.id
	kid.young = true
	kid.grown_at = sim.tick + int(Tuning.GROW_TIME * Tuning.TPS)
	sim.stats.bred = sim.stats.get("bred", 0) + 1
	sim.rev += 1
	sim._toast("A %s was born in the pen." % Defs.SPECIES[a.species].young)
