class_name Creatures
extends RefCounted
## creatures and combat (issue #151), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## Puts a creature of a species on a map, at a cell. Creatures live on one map and never leave it.
static func spawn_creature(sim: Sim, id: String, species: String, cell: Vector2i) -> Dictionary:
	var c := {"id": sim._id(), "kind": "creature", "species": species, "cell": cell, "pos": Vector2(cell), "alive": true,
		"hp": Defs.CREATURES[species].hp, "angry": false, "engaged": false, "cool": 0.0, "flash": 0, "acc": 0.0}
	sim.maps[id].creatures.append(c)
	sim.rev += 1
	return c


## Whether a creature is a danger to the party now: one that goes for people, or one that's been hit or has struck.
static func _dangerous(sim: Sim, x: Dictionary) -> bool:
	return x.alive and (Defs.CREATURES[x.species].notice > 0 or x.angry or x.engaged)


## One tick of the map's creatures: each notices the nearest resident in range (a neutral one only after it's been hit),
## closes in, and strikes when it's close enough and its blow is ready.
static func _step_creatures(sim: Sim) -> void:
	var folks := sim.here().filter(func(o): return not sim._riding(o))  # riders move too fast to be caught (issue #159)
	for x in sim.m.creatures:
		if not x.alive:
			continue
		x.cool = maxf(0.0, x.cool - Tuning.DT)
		var sp: Dictionary = Defs.CREATURES[x.species]
		var tgt = null
		var best := 999
		for r in folks:
			var d := Sim.manhattan(x.cell, Sim.rcell(r))
			if ((sp.notice > 0 and d <= sp.notice) or (x.angry and d <= 10)) and d < best:
				best = d
				tgt = r
		if tgt == null:
			continue
		x.engaged = true  # it's after someone: a guard goes for it
		if best <= sp.reach:
			if x.cool <= 0.0:
				x.cool = sp.cool
				x.flash = sim.tick + 6
				sim._hazard(tgt, sp.hit, sp.serious, "a " + sp.name.to_lower(), "creature")
			continue
		x.acc += Tuning.CREATURE_SPEED * Tuning.DT
		while x.acc >= 1.0:
			x.acc -= 1.0
			var at := Sim.rcell(tgt)
			var steps: Array = [Vector2i(signi(at.x - x.cell.x), 0), Vector2i(0, signi(at.y - x.cell.y))]
			if absi(at.y - x.cell.y) > absi(at.x - x.cell.x):
				steps.reverse()
			for st in steps:
				var n: Vector2i = x.cell + st
				if st != Vector2i.ZERO and sim.walkable(n) and not sim.m.creatures.any(func(o): return o.alive and o.cell == n):
					x.cell = n
					x.pos = Vector2(n)
					sim.rev += 1
					break


## A guard's blow (issue #151): it wears the sword, lands by chance (more often the higher the Guard level) and does
## more with a sword than without. The creature that's hit is angry; a creature brought down leaves its drops.
static func _strike(sim: Sim, r: Dictionary, cr: Dictionary) -> void:
	var dmg: int = Tuning.BARE_DAMAGE
	if r.sword != null:
		dmg = Tuning.SWORD_DAMAGE
		sim._wear(r, "sword")
	cr.flash = sim.tick + 6
	if cr.species == "piglin" and not sim.m.hostile:  # the rule shown up front is broken (issue #156)
		sim.m.hostile = true
		for x in sim.m.creatures:
			if x.species == "piglin":
				x.angry = true
		sim._toast("The piglins turn hostile.", r.id)
	if not sim._roll(Tuning.HIT_CHANCE + 0.08 * (mini(Sim.level(r, "guard"), Tuning.SKILL_CORE) - 1)):
		return
	cr.hp -= dmg
	cr.angry = true
	if cr.hp > 0:
		return
	cr.alive = false
	sim.stats.creatures_beaten = sim.stats.get("creatures_beaten", 0) + 1
	var sp: Dictionary = Defs.CREATURES[cr.species]
	for k in sp.drops:
		sim.drop_items(cr.cell, k, sp.drops[k])
		if not sim.m.drops_known.has(k):
			sim.m.drops_known.append(k)
	sim.gain_xp(r, "guard")
	sim.rev += 1
	sim._toast("%s brought down a %s." % [r.name, sp.name.to_lower()], r.id)


## What a party member does about creatures (issue #151). A guard (or Ada) goes for what threatens the party, or, when the
## party doesn't avoid combat, anything near; anyone else moves away from what's dangerous and goes back to work.
static func _fight_job(sim: Sim, r: Dictionary, c: Vector2i):
	if sim.m.creatures.is_empty() or r.get("hurt", 0) >= 2:
		return null
	var guard: bool = r.role == "guard" or r.role == "all"
	var party := sim.here().filter(func(o): return not sim.expedition_of(o).is_empty())
	var foe: Dictionary = {}
	var best := 999
	for x in sim.m.creatures:
		if not x.alive or x.get("unreach_until", 0) > sim.tick:
			continue
		var d := Sim.manhattan(x.cell, c)
		if guard:
			var near_us: bool = party.any(func(o): return Sim.manhattan(x.cell, Sim.rcell(o)) <= Tuning.SELF_DEFENSE_RANGE)
			var wanted: bool = (_dangerous(sim, x) and (x.engaged or near_us)) or (sim.expedition.get("fight", false) and d <= Tuning.ENGAGE_RANGE) or (near_us and _dangerous(sim, x))
			if wanted and d < best:
				best = d
				foe = x
		elif _dangerous(sim, x) and d <= Tuning.AVOID_RANGE and d < best:
			best = d
			foe = x
	if foe.is_empty():
		return null
	var name: String = Defs.CREATURES[foe.species].name.to_lower()
	if guard:
		var j := Job.new("fight", "Going for the %s" % name, "the " + name)
		j.target = foe
		j.step({"op": "chase", "target": foe, "planned_for": null})
		j.step({"op": "fight", "target": foe})
		return j
	var away = _clear_of(sim, c, foe.cell)
	if away == null or away == c:
		return null
	var f := Job.new("flee", "Moving away from the %s" % name, "away")
	f.step(sim._goto([away], true))
	return f


## A cell a few steps off that's further from `from`, or null.
static func _clear_of(sim: Sim, c: Vector2i, from: Vector2i):
	var seen := {c: true}
	var queue: Array = [c]
	var qi := 0
	var best = null
	var best_d := Sim.manhattan(c, from)
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		if Sim.manhattan(cur, from) > best_d:
			best = cur
			best_d = Sim.manhattan(cur, from)
		if Sim.manhattan(cur, c) >= 6:
			continue
		for d in sim.DIRS:
			var n: Vector2i = cur + d
			if sim.in_bounds(n) and not seen.has(n) and sim.walkable(n) and not sim.m.heat().has(n):
				seen[n] = true
				queue.append(n)
	return best


## What a party member does at the meadow (issues #137, #139): pack what the objective still needs,
## build the pens, lead marked animals in, feed pairs, hunt what's marked, then pack the rest.
static func _meadow_job(sim: Sim, r: Dictionary, c: Vector2i):
	var pk = _stow_job(sim, r, c)
	if pk != null and (_priority_stack(sim, pk.target) or sim.pack_load() + 4 >= Sim.pack_capacity(sim.expedition)):
		return pk
	for f in [sim._fence_job, sim._lead_job, sim._feed_job]:
		var j = f.call(r, c)
		if j != null:
			_drop_unused(sim, r, pk)
			return j
	var prey := sim.m.sheep.filter(func(a): return a.alive and a.des and a.claim == 0 and not sim._cooling(a))
	if not prey.is_empty():
		_drop_unused(sim, r, pk)
		return sim._tagged(sim._hunt_job(r, Sim.nearest(prey, c)), "hunt")
	return pk


## A job that was drawn up but not taken: what it reserved is free again.
static func _drop_unused(sim: Sim, r: Dictionary, j) -> void:
	if j != null:
		sim._release(r, j)


## Whether a stack is one a row with an amount still wants: packed before more mining (issue #185).
static func _priority_stack(sim: Sim, st: Dictionary) -> bool:
	for r in Sim.cargo_rows(sim.expedition):
		if r.item == st.type:
			return r.n > 0 and sim.cargo_have(r.item) < r.n
	return false


## Whether anything lying at the site can still go into the packs: an item on the list while there's room
## (the room kept for the rows above it aside), or one that outranks something in the packs.
static func _stowable(sim: Sim) -> bool:
	if sim.tending():  # whatever the herd Sim.gives, in the room there is
		return sim.pack_room() > 0 and not sim.stacks_where(func(s): return Sim.avail(s) > 0).is_empty()
	if not sim.swap_candidate().is_empty():
		return true
	var room := sim.pack_room()
	return not sim.stacks_where(func(s): return Sim.avail(s) > 0 and Sim.cargo_rank(sim.expedition, s.type) >= 0 and room - sim._reserve_above(s.type) > 0).is_empty()


## Carrying a loose stack at the site into the packs at the entrance (issue #185): the items on the list, best
## first, the packs keeping room for the rows above each; when they're full, a better item swaps out the
## lowest-priority cargo, which is left here as a stack.
static func _stow_job(sim: Sim, r: Dictionary, c: Vector2i):
	var room := sim._room_to_promise()
	var swap := {}
	if room <= 0:
		swap = sim.swap_candidate()
		if swap.is_empty():
			return null
	# An amount already packed is only topped up once nothing else is marked to mine, so the packs keep
	# room for what's still to come.
	var working := sim.m.boulders.any(func(b): return b.alive and b.des) or sim.m.sheep.any(func(a): return a.alive and a.des)
	var loose: Array = [swap.stack] if not swap.is_empty() else sim.stacks_where(func(s):
		if Sim.avail(s) <= 0:
			return false
		if sim.tending():
			return true
		for row in Sim.cargo_rows(sim.expedition):
			if row.item == s.type:
				return row.n <= 0 or sim.cargo_have(s.type) < row.n or not working
		return false)
	if loose.is_empty():
		return null
	loose.sort_custom(func(a, b): return Sim.cargo_rank(sim.expedition, a.type) < Sim.cargo_rank(sim.expedition, b.type) or (Sim.cargo_rank(sim.expedition, a.type) == Sim.cargo_rank(sim.expedition, b.type) and Sim.manhattan(a.cell, c) < Sim.manhattan(b.cell, c)))
	var st: Dictionary = loose[0]
	var n: int = mini(Sim.avail(st), Sim.carry_cap(r))
	if swap.is_empty():
		n = mini(n, room - sim._reserve_above(st.type))
	else:
		n = mini(n, sim.cargo_have(swap.drop))
	if n <= 0:
		return null
	var j := Job.new("stow", "Packing %s" % Defs.ITEMS[st.type].many, "the packs")
	j.target = st
	j.work = "haul"
	st.res += n
	var hd := j.hold({"t": "stack", "stack": st, "n": n})
	j.step(sim._goto(sim.reach(st.cell), false))
	j.step({"op": "pickup", "stack": st, "n": n, "hold": hd})
	j.step(sim._goto([sim.m.entrance], false))
	var stow := {"op": "stow", "n": n}
	if not swap.is_empty():
		stow.swap = swap.drop
	j.step(stow)
	return j


## An item the party learns the place gives while it's there (the iron vein, surveyed) joins its list at the
## bottom, marked New, and a toast says so (issue #185).
static func _learn_items(sim: Sim) -> void:
	if sim.tending() or not sim.expedition.has("list"):
		return
	for x in sim.plan_targets(sim.expedition.dest):
		if not sim.expedition.list.any(func(r): return r.item == x.item):
			sim.expedition.list.append({"item": x.item, "on": true, "n": 0, "new": true})
			sim._toast("%s is known in the %s now. It joins the list of what to bring back." % [Defs.ITEMS[x.item].label, sim.maps[sim.expedition.dest].name.to_lower()], sim.expedition.party[0])


## Marks what the list asks for, going down it (issue #185): the first row that still wants more gets its
## nearest blocks marked, nearest the entrance first, a block at a time, until what's packed, lying about and
## marked will make its amount (an as-much-as-fits row always wants more). At the meadow an animal is hunted
## for the highest row among what it drops. Blocks under a known loose ceiling are left for the player to choose.
static func _mark_objective(sim: Sim) -> void:
	if sim.tending():  # the sim.penned animals over the herd size kept (issue #139)
		for a in sim.pen_surplus():
			if not a.des:
				a.des = true
				a.unreach_until = 0
				sim.rev += 1
		return
	var party_size: int = sim.expedition.party.size()
	for row in Sim.cargo_rows(sim.expedition):
		var item: String = row.item
		if not sim.can_mine_item(item):  # nobody could mine it: left to the sim.stuck list to say so
			continue
		var have := sim.cargo_have(item)
		for st in sim.m.items.values():
			if st.type == item:
				have += st.n
		if sim.m.sheep.any(func(a): return a.alive and Sim.gives(a, item)):  # the meadow: the animals that give it (issue #137)
			var hunted := sim.m.sheep.filter(func(a): return a.alive and a.des and Sim.gives(a, item))
			if row.n > 0 and sim.cargo_have(item) >= row.n:
				continue  # that amount is sim.packed: on to the next row
			if row.n > 0 and have + hunted.size() * Sim.block_yield(item) >= row.n:
				return  # enough is marked or lying about: the next row waits until it's sim.packed
			if sim.m.sheep.filter(func(a): return a.alive and a.des).size() >= party_size:
				return
			var herd := sim.m.sheep.filter(func(a): return a.alive and not a.des and a.get("pen", 0) == 0 and Sim.gives(a, item))  # pens are the player's (issue #139)
			if herd.is_empty():
				if row.n > 0:
					return  # a row with an amount holds the rows below it back until it's sim.packed
				continue
			var a: Dictionary = Sim.nearest(herd, sim.m.entrance)
			a.des = true
			a.unreach_until = 0
			sim.rev += 1
			return
		var marked := sim.m.boulders.filter(func(b): return b.alive and b.des and Sim.gives(b, item))
		if row.n > 0 and sim.cargo_have(item) >= row.n:
			continue  # that amount is sim.packed: on to the next row
		if row.n > 0 and have + marked.size() * Sim.block_yield(item) >= row.n:
			return  # enough is marked or lying about: the next row waits until it's sim.packed
		if sim.m.boulders.filter(func(b): return b.alive and b.des).size() >= party_size:
			return
		var door := MineLevels.door_front(sim.m) if sim.m.door_state == "closed" else Vector2i(-1, -1)  # digging to the door is the player's call (#132)
		var free := sim.m.boulders.filter(func(b): return b.alive and not b.des and not b.get("hidden", false) and not b.get("loose", false) and Sim.gives(b, item) and b.cell != door)
		if free.is_empty():
			if row.n > 0:
				return
			continue
		var b: Dictionary = Sim.nearest(free, sim.m.entrance)
		var way := _way_through(sim, b.cell)
		if way.is_empty():
			if row.n > 0:
				return
			continue
		b = way[0]  # the block itself, or the first boulder in the way to it
		b.des = true
		b.unreach_until = 0
		sim.rev += 1
		return


## The way from the entrance to a block, as the blocks to mine to get there: the first boulder in
## the way and so on, ending with the block itself. Empty when rock or a loose ceiling bars it, or
## another marked block is already being mined toward it.
static func _way_through(sim: Sim, to: Vector2i, allow_loose := false) -> Array:
	var blocks := {}
	for b in sim.m.boulders:
		if b.alive and not b.get("hidden", false):
			blocks[b.cell] = b
	var prev := {sim.m.entrance: sim.m.entrance}
	var queue: Array = [sim.m.entrance]
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		if c == to:
			var path: Array = []
			var p := c
			while p != sim.m.entrance:
				if blocks.has(p):
					path.push_front(blocks[p])
				p = prev[p]
			if path.is_empty():
				return []
			var first: Dictionary = path[0]
			if (first.get("loose", false) and not allow_loose) or (first.des and first.cell != to):
				return []
			return path
		for d in sim.DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not sim.m.in_bounds(n) or sim.m.rock.has(n):
				continue
			if blocks.has(n) and n != to and blocks[n].get("loose", false) and not allow_loose:
				continue
			prev[n] = c
			queue.append(n)
	return []


## Why the party should head home now, by its return policy (issue #109), or "". A pending choice
## waits for the player first.
static func policy_met(sim: Sim) -> String:
	var ex := sim.expedition
	if not sim.pending.is_empty():
		return ""
	if ex.get("rescue", false):  # a rescue party comes home once it has reached them, which sends it (issue #158)
		return ""
	if sim.building_pline():  # home once the rails and the sim.station are down, or the supplies are used (issue #168)
		return "the portal line work is done" if sim.pline_task(-1).is_empty() else ""
	if sim.building_line():  # home once the line work at the far end is done (issue #159)
		return "the line work is done" if sim.nline_task("site", -1).is_empty() else ""
	if sim.delving():  # home once the salvage is taken and the halls are clear, if they pressed on (issue #157)
		if sim.m.salvage_taken and ex.get("pressing", false) and not sim.m.creatures.any(func(x): return x.alive and Defs.CREATURES[x.species].notice > 0):
			return "the halls are cleared"
		return "provisions low" if ex.policy.get("low", false) and sim.spendable_meals() <= 0 else ""
	if sim.trading():  # the trades are made, or the piglins have turned (issue #156)
		if ex.get("trade_done", false) or sim.m.hostile:
			return "the piglins turned hostile" if sim.m.hostile else "the trades are made"
		return "provisions low" if ex.policy.get("low", false) and sim.spendable_meals() <= 0 else ""
	if sim.scouting():  # a scout comes home when the route is walked, which sends them (issue #153)
		return "provisions low" if ex.policy.get("low", false) and sim.spendable_meals() <= 0 else ""
	if sim.surveying():  # the landing: home once every landmark has been seen (issue #148)
		if sim.m.surveyed and (not ex.get("shelter", false) or sim.shelter_site().get("done", false)):
			return "the landing is surveyed" if not ex.get("shelter", false) else "the landing is surveyed and the shelter built"
		if ex.policy.get("low", false) and sim.spendable_meals() <= 0:
			return "provisions low"
		return ""
	if ex.policy.get("target", false) and not sim.tending() and sim.objective_met():
		return "target reached"
	if ex.policy.get("full", false) and sim.pack_room() <= 0 and sim.swap_candidate().is_empty():  # a better find would swap in (issue #185)
		return "packs full"
	if ex.policy.get("low", false) and sim.spendable_meals() <= 0:
		return "provisions low"
	if _nothing_left(sim) and not ex.get("survey", false):
		if sim.tending():
			return "the pens are tended"
		if ex.get("clear", false) and sim.level_of(ex.dest) > 0:
			return "the level is cleared"
		return Adventures.def(sim.m.id).left
	return ""


## Whether the party has nothing left to do here: no one busy, nothing marked or worth marking that can be reached,
## and nothing lying about that would go into the packs.
static func _nothing_left(sim: Sim) -> bool:
	var ex := sim.expedition
	var party: Array = ex.party.map(func(id): return sim.resident(id))
	var busy := party.any(func(r): return r.job != null and r.job.kind in ["gather", "stow", "survey", "eat", "equip", "door", "fence", "lead", "feed"])
	var to_mine := sim.m.boulders.any(func(b): return b.alive and not b.get("hidden", false) and ((b.des and not sim._cooling(b)) or (not b.get("loose", false) and sim.gives_wanted(b) and not _way_through(sim, b.cell).is_empty())))
	to_mine = to_mine or sim.m.sheep.any(func(a): return a.alive and ((a.des and not sim._cooling(a)) or (a.get("pen", 0) == 0 and sim.gives_wanted(a))))
	if sim.m.id == Meadow.ID and sim.tending():  # issue #139
		to_mine = to_mine or sim.pen_work() or not sim.pen_surplus().is_empty()
	return not busy and not to_mine and not _stowable(sim)


## How many blocks of what the party is after are left to mine on the level being worked, out of the loose ceilings'
## reach (issue #188).
static func level_left(sim: Sim) -> int:
	var map_here: SimMap = sim.maps[sim.expedition.dest] if sim.expedition.get("dest", "") != "" and sim.maps.has(sim.expedition.dest) else sim.m
	return map_here.boulders.filter(func(b): return b.alive and not b.get("hidden", false) and not b.get("loose", false) and Sim.cargo_rows(sim.expedition).any(func(r): return Sim.gives(b, r.item))).size()


## A cleared level (issue #188): with nothing left to mine on it, the party digs to the door itself and goes down, the
## objective carried over. Returns whether it's busy with that, so the party isn't sent home for having nothing to mine.
static func _clear_step(sim: Sim) -> bool:
	var ex := sim.expedition
	if not ex.get("clear", false) or sim.level_of(ex.dest) == 0 or not sim.pending.is_empty() or not _nothing_left(sim):
		return false
	if sim.m.door_state != "closed":  # the door's been reached: through it
		sim.go_down()
		return true
	var front := MineLevels.door_front(sim.m)
	var way := _way_through(sim, front)  # never through a loose ceiling: that's the player's call
	if way.is_empty():
		return sim.walkable(front)  # open to the door: someone is on their way to look; blocked: home it is
	for b in way:
		b.des = true
		b.unreach_until = 0
	sim.rev += 1
	return true


## Sends the party home from the site, saying why ("target reached", "retreat"...).
static func _head_home(sim: Sim, why: String) -> void:
	sim.expedition.leg = "home"
	sim.expedition.home_why = why
	for id in sim.expedition.party:
		var r := sim.resident(id)
		sim.fail_job(r)
		r.direct = null
		r.orders.clear()
	sim._toast("Heading home: %s." % why, sim.expedition.party[0])
	if sim.in_nether() and sim.portal_lit() and sim.rng.randf() < Tuning.PORTAL_GUTTER_CHANCE:  # a hazard: the portal goes out (issue #148)
		sim.village_portal().lit = false
		sim.rev += 1
		sim._toast("The portal has gone out behind the party.", sim.expedition.party[0])


## Each tick at the site: mark the objective, and check the return policy once the whole party is there.
static func _step_site(sim: Sim) -> void:
	if sim.expedition.get("state", "") != "out" or sim.expedition.dest != sim.map_id or sim.expedition.get("leg", "out") != "out":
		return
	if not sim.expedition.party.all(func(id): return sim.at_site(sim.resident(id))):
		return
	if sim.tick % 10 == 0:
		_learn_items(sim)
		_mark_objective(sim)
		var why := policy_met(sim)
		if why == "the level is cleared" and _clear_step(sim):  # the packs, food and injuries still come first (issue #188)
			return
		if why != "":
			_head_home(sim, why)


## The site's stuck reasons (issue #109), which carry its map.
static func _stuck_site(sim: Sim) -> void:
	if sim.expedition.get("state", "") != "out" or sim.expedition.dest != sim.map_id:
		return
	if Sim.realm_of(sim.map_id) == "nether" and sim.expedition.get("leg", "out") == "home" and not sim.portal_lit() and sim.expedition.get("lighter", {}).is_empty():
		sim._add_stuck(sim.m.name, "The portal has gone out and no one has flint and steel", Vector2(sim.m.entrance) + Vector2(0.5, 0.5), 1.6, "", 0)
	var party: Array = sim.expedition.party.map(func(id): return sim.resident(id)).filter(func(r): return sim.at_site(r))
	if party.is_empty():
		return
	var at := Vector2(sim.m.entrance) + Vector2(0.5, 0.5)
	if party.any(func(r): return r.job != null and r.job.kind in ["fight", "flee"]):  # issue #151
		sim._add_stuck(Sim.party_name(sim.slot), "fighting", at, 1.6, "", 0, false, true)
	if sim.m.id == NetherLanding.ID:  # the shelter and its cache (issue #152)
		var shelter := sim.shelter_site()
		if not shelter.is_empty() and not shelter.done and sim.expedition.get("shelter", false):
			for k in Tuning.SHELTER_COST:
				var short: int = Tuning.SHELTER_COST[k] - sim.expedition.get("supplies", {}).get(k, 0)
				if short > 0:
					sim._add_stuck("Shelter", "needs %d more %s" % [short, Defs.ITEMS[k].one if short == 1 else Defs.ITEMS[k].many], Vector2(shelter.origin) + Vector2(1.5, 1.5), 1.6, "", 0)
					break
		elif shelter.get("done", false) and sim.cache_meals() == 0:
			sim._add_stuck("Cache", "empty", Vector2(shelter.origin) + Vector2(1.5, 1.5), 1.6, "", 0, false, true)
	var to_mine := sim.m.boulders.any(func(b): return b.alive and b.des)
	if to_mine and party.all(func(r): return r.get("hurt", 0) > 0):
		sim._add_stuck(sim.m.name, "Everyone is hurt, so nobody can mine. Call them home", at, 1.6, "", 0)
	elif to_mine and not party.any(func(r): return r.pick != null and r.get("hurt", 0) == 0) and sim.expedition.get("tools", []).is_empty():
		sim._add_stuck(sim.m.name, "No pickaxe left. The party can only pack what's mined; call them home", at, 1.6, "", 0)
	if sim.pack_room() <= 0 and not sim.stacks_where(func(s): return Sim.avail(s) > 0).is_empty() and not sim.expedition.policy.get("full", false):
		sim._add_stuck(sim.m.name, "The packs are full", at, 1.6, "", 0, false, true)
	if sim.expedition.get("survey", false) and not party.any(func(r): return r.pick != null and r.get("hurt", 0) == 0):
		sim._add_stuck(sim.m.name, "Investigating the vein needs someone with a pickaxe", at, 1.6, "", 0)
	for ore in Tuning.ORE_PICK_TIER:  # a block that needs a better pickaxe than anyone has (issues #186, #146)
		var wanted := Sim.cargo_rows(sim.expedition).any(func(r): return r.item == Defs.ORES[ore].item) or sim.m.boulders.any(func(b): return b.alive and b.des and b.get("ore", "") == ore)
		if wanted and sim.m.boulders.any(func(b): return b.alive and not b.get("hidden", false) and b.get("ore", "") == ore) and not sim.can_mine_ore(ore):
			sim._add_stuck(sim.m.name, Sim.pick_need_text(ore), at, 1.6, "", 0)
	var sticks: int = sim.expedition.get("supplies", {}).get("stick", 0)
	if sim.fence_left(sim.map_id) > 0 and sticks < Tuning.FENCE_STICKS and not party.any(func(r): return r.job != null and r.job.kind == "fence"):
		sim._add_stuck(sim.m.name, "The pens need %s more. Pack them next time" % Defs.words("stick", sim.fence_left(sim.map_id)), at, 1.6, "", 0, false, true)
	if sim.m.sheep.any(func(a): return a.alive and a.get("lead", false) and a.get("pen", 0) == 0) and not sim.m.pens.any(func(p): return Sim.pen_done(p) and sim.pen_free(p) > 0):
		sim._add_stuck(sim.m.name, "No finished pen has room for the animals marked to lead", at, 1.6, "", 0, false, true)
