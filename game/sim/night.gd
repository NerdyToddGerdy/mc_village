class_name Night
extends RefCounted
## Night at the village (issues #66, #357-#360): the day's clock, the night's mobs, the iron golem that keeps them off,
## and how residents fight back. Every function takes the Sim it works on; Sim keeps forwarders where others call in.

## Tests and the bots switch the night's mobs off, so a long run isn't broken into by a wave.
static var enabled := true


# ---------------------------------------------------------------- the day's clock (issue #357)

## Seconds since this morning began. `stats.day_zero` is the tick a morning began on, a dawn's length before a new game starts or an older save loads, so the light has already come up.
static func clock(sim: Sim) -> float:
	var t := float(sim.tick - int(sim.stats.get("day_zero", 0))) / Tuning.TPS
	return fposmod(t, Tuning.DAY_SECONDS)


static func day_number(sim: Sim) -> int:
	return 1 + floori(float(sim.tick - int(sim.stats.get("day_zero", 0))) / Tuning.TPS / Tuning.DAY_SECONDS)


static func is_night(sim: Sim) -> bool:
	return clock(sim) >= Tuning.NIGHT_AT


## How dark it is, 0 (day) to 1 (full night), easing in at dusk and out at dawn.
static func night_level(sim: Sim) -> float:
	var c := clock(sim)
	if c >= Tuning.NIGHT_AT:
		return minf(1.0, (c - Tuning.NIGHT_AT) / Tuning.DUSK_SECONDS)
	return maxf(0.0, 1.0 - c / Tuning.DUSK_SECONDS)


# ---------------------------------------------------------------- the night's tick (issues #358, #359)

static func _hostile(x: Dictionary) -> bool:
	return x.alive and x.species != "golem"


static func threats(sim: Sim) -> Array:
	return sim.m.creatures.filter(func(x): return _hostile(x))


## Once a second, on the village: dusk and dawn, the golem at the third resident, and a wave of mobs each night.
static func step(sim: Sim) -> void:
	if sim.tick % Tuning.TPS != 0:
		return
	var night := is_night(sim)
	if night != sim.stats.get("was_night", false):
		sim.stats.was_night = night
		if enabled:
			sim._toast("Night falls." if night else "Morning.")
		if enabled and not night:
			var left := threats(sim)
			for x in left:  # the dawn sends what's left of them off
				x.alive = false
			if not left.is_empty():
				sim.rev += 1
				sim._toast("The night's mobs slink away.")
	if not enabled:
		return
	if sim.residents.size() >= Tuning.GOLEM_AT and not sim.m.creatures.any(func(x): return x.alive and x.species == "golem"):
		_spawn_golem(sim)
	if night:
		if sim.residents.size() >= Tuning.NIGHT_FROM and int(sim.stats.get("wave_day", 0)) != day_number(sim):
			_spawn_wave(sim)
	if sim.m.creatures.any(func(x): return not x.alive):
		sim.m.creatures = sim.m.creatures.filter(func(x): return x.alive)
		sim.rev += 1


static func _spawn_golem(sim: Sim) -> void:
	var c = sim.nearest_walkable(Vector2i(sim.w / 2, sim.h / 2))
	if c == null:
		return
	var g := Creatures.spawn_creature(sim, "village", "golem", c)
	g.patrol = c
	if not sim.stats.get("golem_seen", false):
		sim.stats.golem_seen = true
		sim._toast("An iron golem has appeared. It keeps watch over the village.")


static func wave_size(sim: Sim) -> int:
	var guards := sim.residents.filter(func(r): return r.role == "guard").size()
	var n: int = Tuning.WAVE_BASE + (sim.residents.size() - Tuning.NIGHT_FROM) / Tuning.WAVE_PER_RESIDENTS + guards
	return mini(Tuning.WAVE_MAX, n)


## A small wave comes in from the village's edge, zombies, skeletons and spiders, each heading for a resident.
static func _spawn_wave(sim: Sim) -> void:
	sim.stats.wave_day = day_number(sim)
	var kinds := ["zombie", "zombie", "skeleton", "spider"]
	var n := wave_size(sim)
	for i in n:
		var c = sim.nearest_walkable(_edge_cell(sim))
		if c == null:
			continue
		var mob := Creatures.spawn_creature(sim, "village", kinds[i % kinds.size()], c)
		mob.hunt = true
		if mob.species == "skeleton":
			mob.drops = {"bone": 1, "arrow": 2}
	sim._toast("%d mobs come out of the dark." % n)


static func _edge_cell(sim: Sim) -> Vector2i:
	match sim.rng.randi_range(0, 3):
		0: return Vector2i(sim.rng.randi_range(1, sim.w - 2), 1)
		1: return Vector2i(sim.rng.randi_range(1, sim.w - 2), sim.h - 2)
		2: return Vector2i(1, sim.rng.randi_range(1, sim.h - 2))
	return Vector2i(sim.w - 2, sim.rng.randi_range(1, sim.h - 2))


# ---------------------------------------------------------------- the golem (issue #359)

## One tick of the golem: it goes for the nearest mob and knocks it out, and otherwise patrols near the village's middle.
## It never hurts a resident, and nothing hurts it.
static func step_golem(sim: Sim, x: Dictionary) -> void:
	x.cool = maxf(0.0, x.cool - Tuning.DT)
	var foe = null
	var best := Tuning.GOLEM_SIGHT + 1
	for o in sim.m.creatures:
		if _hostile(o):
			var d := Sim.manhattan(x.cell, o.cell)
			if d < best:
				best = d
				foe = o
	var goal: Vector2i
	if foe != null:
		if best <= 1:
			if x.cool <= 0.0:
				x.cool = Tuning.GOLEM_HIT
				x.flash = sim.tick + 6
				foe.flash = sim.tick + 6
				foe.hp -= Tuning.GOLEM_DAMAGE
				foe.angry = true
				if foe.hp <= 0:
					Creatures._down(sim, foe)
					sim._toast("The golem knocked out a %s." % Defs.CREATURES[foe.species].name.to_lower())
			return
		goal = foe.cell
	else:
		if x.get("patrol") == null or x.cell == x.patrol or sim.tick % (20 * Tuning.TPS) == 0:
			var mid := Vector2i(sim.w / 2, sim.h / 2)
			var spot = sim.nearest_walkable(mid + Vector2i(sim.rng.randi_range(-Tuning.PATROL_RADIUS, Tuning.PATROL_RADIUS), sim.rng.randi_range(-Tuning.PATROL_RADIUS, Tuning.PATROL_RADIUS)))
			x.patrol = spot if spot != null else x.cell
		goal = x.patrol
	x.acc += Tuning.GOLEM_SPEED * Tuning.DT
	while x.acc >= 1.0:
		x.acc -= 1.0
		var steps: Array = [Vector2i(signi(goal.x - x.cell.x), 0), Vector2i(0, signi(goal.y - x.cell.y))]
		if absi(goal.y - x.cell.y) > absi(goal.x - x.cell.x):
			steps.reverse()
		steps.append_array([Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)])  # round an obstacle
		for st in steps:
			var n: Vector2i = x.cell + st
			if st != Vector2i.ZERO and sim.walkable(n) and not sim.m.creatures.any(func(o): return o.alive and o.cell == n):
				x.cell = n
				x.pos = Vector2(n)
				sim.rev += 1
				break


# ---------------------------------------------------------------- residents fight back (issue #360)

## What a resident does about a mob near them at the village: a guard (and Ada) go after it, anyone else hits back a
## little when it's close, slowly. The injured rest instead. Null when there's nothing to do about it.
static func defend_job(sim: Sim, r: Dictionary, c: Vector2i):
	if sim.m.kind != "village" or r.map != "village" or r.away or r.get("hurt", 0) > 0:
		return null
	var guard: bool = r.role == "guard" or r.role == "all"
	var reach: int = Tuning.GUARD_DEFEND_RANGE if guard else Tuning.FIGHT_BACK_RANGE
	var foe = null
	var best := reach + 1
	for x in sim.m.creatures:
		if _hostile(x):
			var d := Sim.manhattan(x.cell, c)
			if d < best:
				best = d
				foe = x
	if foe == null:
		return null
	var name: String = Defs.CREATURES[foe.species].name.to_lower()
	var j := Job.new("fight", "Going for the %s" % name if guard else "Fighting back against the %s" % name, "the " + name)
	j.target = foe
	j.step({"op": "chase", "target": foe, "planned_for": null})
	var blow := {"op": "fight", "target": foe}
	if not guard:
		blow.slow = Tuning.FIGHT_BACK_SLOW
	j.step(blow)
	return j
