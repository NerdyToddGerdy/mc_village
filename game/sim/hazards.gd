class_name Hazards
extends RefCounted
## hazards and injuries (issue #110), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## Ada, the founder (the PC): she can be hurt, but never seriously (brief §8).
static func is_pc(sim: Sim, r: Dictionary) -> bool:
	return not sim.residents.is_empty() and sim.residents[0].id == r.id


## Hurts a resident: 1 injured, 2 seriously. A serious injury on an expedition stops the game for the
## player: retreat, or press on without them.
static func injure(sim: Sim, r: Dictionary, level: int, cause: String) -> void:
	if is_pc(sim, r):
		level = mini(level, 1)
	if level <= r.get("hurt", 0):
		return
	r.hurt = level
	r.hurt_cause = cause
	r.heal = Tuning.HEAL_TIME[level]
	if r.job != null:
		sim.fail_job(r)
	sim.stats.injuries = sim.stats.get("injuries", 0) + 1
	if sim.expedition.get("state", "") == "out" and sim.expedition.party.has(r.id):
		sim.expedition.hurt = sim.expedition.get("hurt", {})
		sim.expedition.hurt[r.name] = maxi(sim.expedition.hurt.get(r.name, 0), level)
	sim.rev += 1
	if level == 1:
		sim._toast("%s was hurt in %s. Injured, %s can't mine and works slower." % [r.name, cause, "she" if is_pc(sim, r) else "they"], r.id)
		return
	sim._toast("%s is seriously hurt in %s." % [r.name, cause], r.id)
	if sim.at_site(r):
		sim._ask("injury", "%s is seriously hurt in %s and can't work." % [r.name, cause], [
			{"id": "retreat", "label": "Retreat", "cost": "The party heads home now, with what it has packed."},
			{"id": "press_on", "label": "Press on", "cost": "%s waits at the entrance while the rest keep working." % r.name},
		], r.id)


## A hazard roll, from the sim's seeded random numbers, so a game replays the same.
static func _roll(sim: Sim, chance: float) -> bool:
	return sim.rng.randf() < chance


## A hazard strikes someone with `chance` (issues #110, #140). Armor takes the blow and wears, and
## turns some injuries aside; a full set makes a serious one less likely. `serious` is the chance an
## injury is serious, 0 for one that never is.
static func _hazard(sim: Sim, r: Dictionary, chance: float, serious: float, cause: String, kind := "") -> void:
	if kind == "creature":  # Protection armor, a piece at a time (issue #167)
		chance *= pow(1.0 - Tuning.PROTECTION_CUT, armor_ench_count(r, "protection"))
	elif kind == "fire":  # Fire protection (issue #167)
		chance *= pow(1.0 - Tuning.FIRE_PROTECTION_CUT, armor_ench_count(r, "fire_protection"))
	if not _roll(sim, chance):
		return
	var guard := protection(r)
	var full := armor_worn(r).size() == Defs.ARMOR_SLOTS.size()
	if guard > 0.0:
		_wear_armor(sim, r)
		if _roll(sim, guard):
			sim.stats.turned_aside = sim.stats.get("turned_aside", 0) + 1
			sim._toast("%s's armor turned aside %s." % [r.name, cause], r.id)
			return
	var level := 1
	if serious > 0.0 and _roll(sim, serious * (Tuning.FULL_SET_SERIOUS if full else 1.0)):
		level = 2
	injure(sim, r, level, cause)


## How many pieces someone wears with an enchantment.
static func armor_ench_count(r: Dictionary, ench: String) -> int:
	var n := 0
	var worn := armor_worn(r)
	for slot in worn:
		if Defs.ITEMS[worn[slot].type].get("ench", "") == ench:
			n += 1
	return n


## The armor someone has on: slot -> {type, dur}.
static func armor_worn(r: Dictionary) -> Dictionary:
	var out := {}
	for slot in r.get("armor", {}):
		if r.armor[slot] != null:
			out[slot] = r.armor[slot]
	return out


## The share of hazard injuries someone's armor turns aside (issue #140).
static func protection(r: Dictionary) -> float:
	var g := 0.0
	var worn := armor_worn(r)
	for slot in worn:
		g += Defs.ITEMS[worn[slot].type].get("guard", Tuning.ARMOR_GUARD[slot])  # iron turns more aside (issue #150)
	return g


## Every piece worn takes the blow: a use each, and one used up wears out.
static func _wear_armor(sim: Sim, r: Dictionary) -> void:
	for slot in armor_worn(r):
		var a: Dictionary = r.armor[slot]
		if not Sim._use_up(a):
			continue
		if a.dur <= 0:
			r.armor[slot] = null
			sim.stats.armor_worn_out = sim.stats.get("armor_worn_out", 0) + 1
			sim._toast("%s's %s wore out." % [r.name, Defs.ITEMS[a.type].one], r.id)
	sim.rev += 1


## A guard without a sword takes one lying about, and keeps it (issue #150).
static func _arm_job(sim: Sim, r: Dictionary, c: Vector2i):
	if sim.map_id != "village" or r.role != "guard" or r.sword != null or r.get("hurt", 0) > 0:
		return null
	var swords := sim.tool_items("sword", 0)
	if swords.is_empty():
		return null
	var st: Dictionary = Sim.nearest(swords, c)
	var it: Dictionary = Defs.ITEMS[st.type]
	var j := Job.new("equip", "Going to get the %s" % it.one, "the %s" % it.one)
	st.res += 1
	var hd := j.hold({"t": "stack", "stack": st, "n": 1})
	j.step(sim._goto(sim.reach(st.cell), false))
	j.step({"op": "pickup_tool", "stack": st, "hold": hd, "keep": true})
	return j


## Putting on armor lying about (issue #140): the nearest piece for a slot they haven't filled.
## Like tools, residents take it themselves; only in the village.
static func _dress_job(sim: Sim, r: Dictionary, c: Vector2i):
	if sim.map_id != "village":
		return null
	var pieces := sim.stacks_where(func(s): return Defs.is_armor(s.type) and Sim.avail(s) > 0 and r.get("armor", {}).get(Defs.ITEMS[s.type].armor) == null)
	if pieces.is_empty():
		return null
	return _dress(sim, r, Sim.nearest(pieces, c))


static func _dress(sim: Sim, r: Dictionary, stack: Dictionary) -> Job:
	if not r.has("armor"):
		r.armor = {}
	var it: Dictionary = Defs.ITEMS[stack.type]
	var j := Job.new("dress", "Going to put on the %s" % it.one, "the %s" % it.one)
	stack.res += 1
	var hd := j.hold({"t": "stack", "stack": stack, "n": 1})
	j.step(sim._goto(sim.reach(stack.cell), false))
	j.step({"op": "pickup_armor", "stack": stack, "hold": hd})
	return j


## The nearest walkable cell that isn't on fire, within a few steps, or null.
static func _clear_ground(sim: Sim, c: Vector2i):
	var seen := {c: true}
	var queue: Array = [c]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		if sim.walkable(cur) and not sim.m.fire.has(cur):
			return cur
		if Sim.manhattan(cur, c) >= 4:
			continue
		for d in sim.DIRS:
			var n: Vector2i = cur + d
			if sim.in_bounds(n) and not seen.has(n) and sim.walkable(n):
				seen[n] = true
				queue.append(n)
	return null


## Someone alight (issue #149): they burn for a few seconds after leaving the fire, each second a chance of a burn, and
## step off a fire at once. Reaching clear ground and waiting it out stops it.
static func _burn_step(sim: Sim, r: Dictionary) -> void:
	var c := Sim.rcell(r)
	if sim.m.fire.has(c):
		r.burn = Tuning.FIRE_BURN_TIME
		var out = _clear_ground(sim, c)
		if out != null and out != c:
			r.pos = Vector2(out)
			r.path = []
			if r.job != null:
				sim.fail_job(r)
	else:
		r.burn = maxf(0.0, r.burn - Tuning.DT)
	r.burn_acc = r.get("burn_acc", 0.0) + Tuning.DT
	if r.burn_acc >= 1.0:
		r.burn_acc -= 1.0
		_hazard(sim, r, Tuning.FIRE_CHANCE, Tuning.FIRE_SERIOUS, "burning", "fire")
	if r.burn <= 0.0:
		r.burn_acc = 0.0


## Stepping onto a ledge in the dark can be a fall.
static func _ledge_step(sim: Sim, r: Dictionary, c: Vector2i) -> void:
	if sim._riding(r):
		return
	if sim.m.fire.has(c):  # stepping onto a fire sets someone alight (issue #149)
		r.burn = Tuning.FIRE_BURN_TIME
		_hazard(sim, r, Tuning.FIRE_CHANCE, Tuning.FIRE_SERIOUS, "burning", "fire")
		return
	if sim.m.beside_lava(c):
		_hazard(sim, r, Tuning.LAVA_CHANCE, Tuning.LAVA_SERIOUS, "a burn beside lava", "fire")
	if c in sim.m.ledges and (sim.m.is_dark(c) or Sim.realm_of(sim.map_id) == "nether"):  # the Nether's drops need no dark (issue #149)
		_hazard(sim, r, fall_chance(sim.m.level), Tuning.FALL_SERIOUS, "a fall from a ledge")
	elif c in sim.m.banks:  # the meadow's pond bank (issue #137): never serious
		_hazard(sim, r, Tuning.SLIP_CHANCE, 0.0, "a slip on the pond bank")


## The chance a loose ceiling comes down, and of a fall from a ledge in the dark: higher on each level
## down (issue #132).
static func cave_in_chance(level: int) -> float:
	return minf(0.95, Tuning.CAVE_IN_CHANCE * (1.0 + Tuning.LEVEL_RISK * maxi(0, level - 1)))


static func fall_chance(level: int) -> float:
	return minf(0.95, Tuning.FALL_CHANCE * (1.0 + Tuning.LEVEL_RISK * maxi(0, level - 1)))


## How much slower a resident walks and works: injured, and (for work) in the dark.
static func hurt_speed(r: Dictionary) -> float:
	return Tuning.INJURED_SPEED if r.get("hurt", 0) > 0 else 1.0


## Resting to heal at home: in their own bed, or slower without one.
static func _rest_job(sim: Sim, r: Dictionary) -> Job:
	var bed = null
	for s in sim.m.sites:
		if s.tpl == "house" and s.done and s.owner == r.id:
			bed = s
	var j := Job.new("rest", "Resting in bed" if bed != null else "Resting, with no bed of their own", "their bed")
	if bed != null:
		j.step(sim._goto(sim.site_cells(bed), true))
	j.step({"op": "rest", "bed": bed != null})
	return j


## Whether a resident is home and hurt, so resting.
static func _has_bed(sim: Sim, r: Dictionary) -> bool:
	return sim.maps.village.sites.any(func(s): return s.tpl == "house" and s.done and s.owner == r.id)


static func resting(sim: Sim, r: Dictionary) -> bool:
	return r.get("hurt", 0) > 0 and r.map == "village" and not r.away and not sim.on_the_way(r) and not sim.in_staging_party(r)
