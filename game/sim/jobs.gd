class_name Jobs
extends RefCounted
## Jobs: the step lists residents work through (issue #134 and on), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.


static func _goto(sim: Sim, cells: Array, adjacent: bool) -> Dictionary:
	return {"op": "goto", "cells": cells, "adj": adjacent, "planned": false}


## A stonemason digging 1 cobblestone at their mineshaft (issue #204).
static func _dig_job(sim: Sim, r: Dictionary, shaft: Dictionary) -> Job:
	var j := Job.new("gather", "Going to dig stone", "the mineshaft")
	j.work = "mason"
	var cur: int = r.pick.tier if r.pick != null else 0
	var better := sim.tool_items("pick", cur)
	if not better.is_empty() and not (r.kept.pick and r.pick != null):
		sim._fetch_tool(j, sim.nearest(better, sim.rcell(r)))
	j.step(sim._goto([shaft.origin], true))
	j.step({"op": "work", "what": "dig", "site": shaft, "tool": "pick", "label": "Digging stone"})
	return j


static func _gather_job(sim: Sim, r: Dictionary, target: Dictionary) -> Job:
	var is_tree: bool = target.kind == "tree"
	var kind := "axe" if is_tree else "pick"
	var j := Job.new("gather", "Going to chop a tree" if is_tree else "Going to break a boulder",
		"this tree" if is_tree else "this boulder")
	j.work = sim.gather_job_of(target)
	j.target = target
	target.claim = r.id
	j.hold({"t": "claim", "ent": target})
	var cur: int = r[kind].tier if r[kind] != null else 0
	var better := sim.tool_items(kind, cur)
	if better.is_empty() and r[kind] != null and not Defs.ITEMS[r[kind].type].has("ench"):  # an enchanted tool of the same tier is better (issue #166)
		better = sim.stacks_where(func(s): return Defs.ITEMS[s.type].get("tool", "") == kind and Defs.ITEMS[s.type].has("ench") and Defs.ITEMS[s.type].tier >= cur and sim.avail(s) > 0)
	if not better.is_empty() and not (r.kept[kind] and r[kind] != null):  # a tool you chose stays
		sim._fetch_tool(j, sim.nearest(better, sim.rcell(r)))
	j.step(sim._goto([target.cell], true))
	j.step({"op": "work", "what": "gather", "target": target, "tool": kind,
		"label": "Chopping a tree" if is_tree else "Breaking a boulder"})
	return j


## The player has opened a page of the Guide: it's no longer new (issue #348).
static func see_page(sim: Sim, id: String) -> void:
	var seen: Dictionary = sim.stats.get("guide_seen", {})
	if not seen.has(id) and Goals.pages(sim).any(func(p): return p.id == id):
		seen[id] = true
		sim.stats.guide_seen = seen


## Marks a berry bush to be dug up, or unmarks it (issue #344). The claimant stops if it's unmarked.
static func designate_bush(sim: Sim, b: Dictionary) -> void:
	if not sim.m.bushes.any(func(o): return is_same(o, b)):
		return
	b.des = not b.des
	if not b.des and b.claim != 0:
		var r := sim.resident(b.claim)
		if not r.is_empty() and r.job != null and is_same(r.job.target, b):
			sim.fail_job(r)
	sim.rev += 1


## A resident digs up a marked bush by hand and carries off the berries on it (issue #344).
static func _dig_bush_job(sim: Sim, r: Dictionary, bush: Dictionary) -> Job:
	var j := Job.new("gather", "Going to dig up a bush", "this bush")
	j.work = "lumber"
	j.target = bush
	bush.claim = r.id
	j.hold({"t": "claim", "ent": bush})
	j.step(sim._goto([bush.cell], true))
	j.step({"op": "work", "what": "dig_bush", "target": bush, "label": "Digging up a bush"})
	return j


## Food lying around or stockpiled, nearest first: {kind:"stack", stack} or {kind:"bush", bush}, or {}.
static func _nearest_food(sim: Sim, c: Vector2i) -> Dictionary:
	var best := {}
	var bd := 1 << 30
	var raw := {}
	for k in sim.m.items:
		var s: Dictionary = sim.m.items[k]
		if not Tuning.FOOD_VALUE.has(s.type) or sim.avail(s) <= 0:
			continue
		if Defs.RAW_MEATS.has(s.type):  # raw meat is for the fireplace; eaten only in a pinch
			if raw.is_empty() or sim.manhattan(s.cell, c) < sim.manhattan(raw.stack.cell, c):
				raw = {"kind": "stack", "stack": s}
			continue
		if sim.manhattan(s.cell, c) < bd:
			bd = sim.manhattan(s.cell, c)
			best = {"kind": "stack", "stack": s}
	for b in sim.m.bushes:
		if b.berries > 0 and sim.manhattan(b.cell, c) < bd:
			bd = sim.manhattan(b.cell, c)
			best = {"kind": "bush", "bush": b}
	return raw if best.is_empty() else best


static func food_available(sim: Sim) -> bool:
	return not sim._nearest_food(Vector2i.ZERO).is_empty()


## Go and eat (issue #44): pick up the nearest food and eat it, or eat berries off a bush until
## nearly full or the bush is bare.
static func _eat_job(sim: Sim, r: Dictionary):
	if sim.at_site(r) or sim.on_road(r) or (sim.expedition.get("state", "") == "out" and sim.expedition.party.has(r.id) and r.map != "village"):
		return sim._ration_job(r)
	var f := sim._nearest_food(sim.rcell(r))
	if f.is_empty():
		return null
	var j := Job.new("eat", "Going to eat", "the food")
	if f.kind == "bush":
		j.label = "Going to pick berries"
		j.step(sim._goto([f.bush.cell], false))
		j.step({"op": "work", "what": "graze", "target": f.bush, "label": "Eating berries"})
		return j
	var stack: Dictionary = f.stack
	stack.res += 1
	var hd := j.hold({"t": "stack", "stack": stack, "n": 1})
	j.step(sim._goto(sim.reach(stack.cell), false))
	j.step({"op": "pickup", "stack": stack, "n": 1, "hold": hd})
	j.step({"op": "work", "what": "eat", "label": "Eating %s" % Defs.ITEMS[stack.type].one})
	return j


## Whether the village has all the wheat it wants, so farmers leave the plots be (issue #269). Counts collected wheat.
static func wheat_enough(sim: Sim) -> bool:
	return sim.free_count("wheat") >= sim.wheat_keep


static func set_wheat_keep(sim: Sim, n: int) -> void:
	sim.wheat_keep = maxi(0, n)
	sim.rev += 1


## Plant an empty farm cell or harvest a ripe one (issue #45). Farmers stand on the cell.
static func _farm_job(sim: Sim, r: Dictionary, crop: Dictionary) -> Job:
	var ripe := sim.crop_ripe(crop)
	var j := Job.new("farm", "Going to harvest wheat" if ripe else "Going to plant wheat", "the farm plot")
	j.work = "farm"
	j.target = crop
	crop.claim = r.id
	j.hold({"t": "claim", "ent": crop})
	j.step(sim._goto([crop.cell], false))
	j.step({"op": "work", "what": "harvest" if ripe else "plant", "target": crop,
		"label": "Harvesting wheat" if ripe else "Planting wheat"})
	return j


## The nearest farm cell that needs planting or harvesting, ripe ones first, or null.
static func _farm_work(sim: Sim, c: Vector2i):
	if sim.m.farm.is_empty() or sim.wheat_enough():  # enough wheat: the plots keep their crop (issue #269)
		return null
	var ripe: Array = []
	var empty: Array = []
	for k in sim.m.farm:
		var crop: Dictionary = sim.m.farm[k]
		if crop.claim != 0 or sim._cooling(crop) or not sim.walkable(crop.cell):
			continue
		if sim.crop_ripe(crop):
			ripe.append(crop)
		elif crop.grow < 0.0 and not sim.m.items.has(crop.cell):  # the last harvest is collected first
			empty.append(crop)
	if not ripe.is_empty():
		return sim.nearest(ripe, c)
	if not empty.is_empty():
		return sim.nearest(empty, c)
	return null


## Walk to a sheep, following it if it wanders, then hunt it.
static func _hunt_job(sim: Sim, r: Dictionary, target: Dictionary) -> Job:
	var one: String = Defs.SPECIES[target.species].one
	var j := Job.new("gather", "Going to hunt a %s" % one, "this %s" % one)
	j.work = "hunt"
	j.target = target
	target.claim = r.id
	j.hold({"t": "claim", "ent": target})
	j.step({"op": "chase", "target": target, "planned_for": null})
	j.step({"op": "work", "what": "hunt", "target": target, "label": "Hunting a %s" % one})
	return j


static func _fetch_tool(sim: Sim, j: Job, stack: Dictionary) -> void:
	stack.res += 1
	var hd := j.hold({"t": "stack", "stack": stack, "n": 1})
	j.step(sim._goto(sim.reach(stack.cell), false))
	j.step({"op": "pickup_tool", "stack": stack, "hold": hd})


static func _deliver_job(sim: Sim, dest: Dictionary, type: String, n: int, stack: Dictionary) -> Job:
	var dest_name: String = Defs.TEMPLATES[dest.tpl].name.to_lower()
	if dest.done and dest.tpl == "bench":
		dest_name = "bench"
	var j := Job.new("deliver", "Hauling %s to the %s" % [Defs.ITEMS[type].many, dest_name], "the " + dest_name)
	j.target = dest
	stack.res += n
	dest.incoming[type] = dest.incoming.get(type, 0) + n
	var sh := j.hold({"t": "stack", "stack": stack, "n": n})
	var ih := j.hold({"t": "incoming", "site": dest, "type": type, "n": n})
	j.step(sim._goto(sim.reach(stack.cell), false))
	j.step({"op": "pickup", "stack": stack, "n": n, "hold": sh})
	j.step(sim._goto(sim.site_cells(dest), true))
	j.step({"op": "deposit", "site": dest, "type": type, "n": n, "hold": ih})
	return j


## Lighting a finished portal (issue #147): fetch flint and steel from a stockpile, carry it to the frame and strike it.
static func _light_job(sim: Sim, r: Dictionary):
	var p: Dictionary = {}
	for s in sim.m.sites:
		if s.tpl == "portal" and s.done and not s.lit and s.builder == 0 and not sim._cooling(s):
			p = s
			break
	if p.is_empty():
		return null
	var lighters := sim.stacks_where(func(s): return s.type == "flint_and_steel" and sim.avail(s) > 0)
	if lighters.is_empty():
		return null
	var stack: Dictionary = sim.nearest(lighters, sim.rcell(r))
	var j := Job.new("build", "Going to light the portal", "the portal")
	j.work = "build"
	j.target = p
	p.builder = r.id
	j.hold({"t": "builder", "site": p})
	stack.res += 1
	var hd := j.hold({"t": "stack", "stack": stack, "n": 1})
	j.step(sim._goto(sim.reach(stack.cell), false))
	j.step({"op": "pickup_lighter", "stack": stack, "hold": hd})
	j.step(sim._goto(sim.site_cells(p), true))
	j.step({"op": "work", "what": "light", "site": p, "label": "Lighting the portal"})
	return j


static func _build_job(sim: Sim, r: Dictionary, s: Dictionary) -> Job:
	var j := Job.new("build", "Going to build", "the " + Defs.TEMPLATES[s.tpl].name.to_lower())
	j.work = "build"
	j.target = s
	s.builder = r.id
	j.hold({"t": "builder", "site": s})
	var label: String = "Building " + sim.current_stage(s).name.to_lower()
	if s.tpl == "bench":
		label = "Building the bench"
	elif s.tpl == "fireplace":
		label = "Building the fireplace"
	elif s.tpl in ["board", "chopping_block", "mason_bench", "toolsmith_bench", "composter", "lodge", "builder_table", "portal", "enchanting_workshop", "portal_station", "cache_sensor", "condition", "freight_loader", "dispatcher"]:
		label = "Building the " + Defs.TEMPLATES[s.tpl].name.to_lower()
	elif s.tpl == "bridge":
		label = "Building the bridge"
	elif s.tpl == "track":
		label = "Laying track"
	j.step(sim._goto(sim.site_cells(s), true))
	j.step({"op": "work", "what": "build", "site": s, "label": label})
	return j


static func _craft_job(sim: Sim, r: Dictionary, b: Dictionary, rec: Dictionary) -> Job:
	var where: String = "the bench" if b.tpl == "bench" else "the " + Defs.TEMPLATES[b.tpl].name.to_lower()
	var j := Job.new("craft", "Going to " + where, where)
	j.work = sim.recipe_job(rec)
	j.target = b
	b.crafter = r.id
	b.crafting = rec.name
	j.hold({"t": "crafter", "site": b})
	j.step(sim._goto(sim.site_cells(b), true))
	j.step({"op": "work", "what": "craft", "site": b, "recipe": rec, "label": rec.get("doing", "Crafting " + rec.name.to_lower())})
	return j


## Carrying a stack to a stockpile cell, or to a workstation's pile (`pile`, issue #177).
static func _haul_job(sim: Sim, r: Dictionary, stack: Dictionary, dest: Vector2i, n: int, pile := {}) -> Job:
	var where: String = "the storehouse" if sim.in_store(dest) else ("the stockpile" if sim.in_zone(dest) else "clear ground") if pile.is_empty() else "the " + Defs.TEMPLATES[pile.tpl].name.to_lower()
	var j := Job.new("haul", "Hauling %s to %s" % [Defs.ITEMS[stack.type].many, where], where)
	stack.res += n
	sim.m.zone_res[dest] = r.id
	var sh := j.hold({"t": "stack", "stack": stack, "n": n})
	var zh := j.hold({"t": "zone", "cell": dest})
	var drop := {"op": "haul_drop", "cell": dest, "type": stack.type, "n": n, "hold": zh}
	if not pile.is_empty():
		pile.incoming[stack.type] = pile.incoming.get(stack.type, 0) + n
		drop.pile_hold = j.hold({"t": "incoming", "site": pile, "type": stack.type, "n": n})
	j.step(sim._goto(sim.reach(stack.cell), false))
	j.step({"op": "pickup", "stack": stack, "n": n, "hold": sh})
	j.step(sim._goto(sim.reach(dest), false))
	j.step(drop)
	return j


static func _move_job(sim: Sim, c: Vector2i) -> Job:
	return Job.new("move", "Walking", "that spot").step(sim._goto([c], false))


static func _release(sim: Sim, r: Dictionary, j: Job) -> void:
	for hd in j.holds:
		match hd.t:
			"stack": hd.stack.res -= hd.n
			"incoming": hd.site.incoming[hd.type] -= hd.n
			"zone":
				var zm: SimMap = sim.maps[hd.get("map", sim.map_id)]
				if zm.zone_res.get(hd.cell, 0) == r.id:
					zm.zone_res.erase(hd.cell)
			"claim":
				if hd.ent.claim == r.id:
					hd.ent.claim = 0
			"lead":
				if hd.ent.get("led_by", 0) in [0, r.id]:
					hd.ent.led_by = 0
					hd.ent.led_to = 0
			"fence":
				if sim._fence_claims.get(hd.cell, 0) == r.id:
					sim._fence_claims.erase(hd.cell)
			"plant":
				if sim._plant_claims.get(hd.cell, 0) == r.id:
					sim._plant_claims.erase(hd.cell)
			"builder":
				if hd.site.builder == r.id:
					hd.site.builder = 0
			"crafter":
				if hd.site.crafter == r.id:
					hd.site.crafter = 0
					hd.site.crafting = ""
			"arriving": r.arriving = false
	j.holds.clear()


static func fail_job(sim: Sim, r: Dictionary, why := "") -> void:
	if r.map != sim.map_id:
		sim.on_map(r.map, sim.fail_job.bind(r, why))
		return
	var j = r.job
	if j == null:
		return
	r.job = null
	r.progress = -1.0
	r.path = []
	sim._release(r, j)
	if r.carry != null:
		sim.drop_items(sim.rcell(r), r.carry.type, r.carry.n, r.carry.get("dur", -1))
		r.carry = null
	var until := sim.tick + int(Tuning.UNREACHABLE_COOLDOWN * Tuning.TPS)
	if why == "unreachable":
		r.note = {"text": "Can’t reach " + j.what, "until": until}
		if j.target != null:
			j.target.unreach_until = until
	elif why == "needs_pick":
		var ore: String = j.target.get("ore", "") if j.target != null else ""
		var diamond: bool = Tuning.ORE_PICK_TIER.has(ore)
		r.note = {"text": sim.pick_need_text(ore) if diamond else "Needs a pickaxe", "until": sim.tick + 4 * Tuning.TPS}
		if diamond:
			j.target.unreach_until = sim.tick + int(Tuning.UNREACHABLE_COOLDOWN * Tuning.TPS)


## How much faster a resident works with the tool in their hand: Efficiency (issue #167).
static func tool_speed(sim: Sim, r: Dictionary, kind: String) -> float:
	var t = r.get(kind)
	if t != null and Defs.ITEMS[t.type].get("ench", "") == "efficiency":
		return Tuning.EFFICIENCY_SPEED
	return 1.0


static func _wear(sim: Sim, r: Dictionary, kind: String) -> void:
	var t = r[kind]
	if t == null:
		return
	if not sim._use_up(t):
		return
	if t.dur <= 0:
		r[kind] = null
		r.broken[kind] = true
		r.kept[kind] = false
		sim.stats.tools_broken += 1
		if kind == "pick" and sim.expedition.get("state", "") == "out" and sim.expedition.party.has(r.id):
			sim.expedition.broken = sim.expedition.get("broken", 0) + 1
		sim._toast("%s’s %s broke." % [r.name, Defs.ITEMS[t.type].one], r.id)


## Runs the resident's current step. Returns true when the step finished, false to continue next
## tick, or a String naming why the job failed.
static func _run_step(sim: Sim, r: Dictionary, j: Job, st: Dictionary):
	match st.op:
		"chase":
			var t: Dictionary = st.target
			if not t.alive:
				return "gone"
			if sim.manhattan(sim.rcell(r), t.cell) <= 1:
				r.path = []
				r.pos = Vector2(sim.rcell(r))
				return true
			if st.planned_for != t.cell or r.path.is_empty():
				var goals := sim.adj_set([t.cell])
				goals[t.cell] = true
				var p = sim.find_path(sim.rcell(r), goals)
				if p == null:
					return "unreachable"
				r.path = p
				st.planned_for = t.cell
			var nxt: Vector2i = r.path[0]
			var to: Vector2 = Vector2(nxt) - r.pos
			var dist: float = to.length()
			var step_len := Tuning.WALK * Tuning.DT * sim.hurt_speed(r) * sim.ground_speed(sim.rcell(r))
			if dist <= step_len:
				r.pos = Vector2(nxt)
				r.path.pop_front()
				sim._wear_step(nxt)
			else:
				r.pos += to / dist * step_len
			return false
		"goto":
			if not st.planned:
				var goals := sim.adj_set(st.cells) if st.adj else sim.cell_set(st.cells)
				if goals.is_empty():
					return "unreachable"
				var p = sim.find_path(sim.rcell(r), goals)
				if p == null:
					return "unreachable"
				r.path = p
				st.planned = true
			if r.path.is_empty():
				r.pos = Vector2(sim.rcell(r))
				return true
			var nxt: Vector2i = r.path[0]
			if not sim.walkable(nxt):
				st.planned = false
				r.path = []
				return false
			var to: Vector2 = Vector2(nxt) - r.pos
			var dist: float = to.length()
			var step_len := Tuning.WALK * Tuning.DT * sim.hurt_speed(r) * sim.ground_speed(sim.rcell(r))
			if dist <= step_len:
				r.pos = Vector2(nxt)
				r.path.pop_front()
				sim._wear_step(nxt)
				if sim.m.kind == "route":
					sim._reveal(nxt)
				if sim.m.kind == "site":
					sim._ledge_step(r, nxt)
					if r.job != j:
						return false  # a fall ended the job
				return r.path.is_empty()
			r.pos += to / dist * step_len
			return false
		"pickup":
			var s = sim.m.items.get(st.stack.cell)
			if not is_same(s, st.stack) or s.n < st.n:
				return "gone"
			s.n -= st.n
			s.res -= st.n
			j.holds.erase(st.hold)
			if s.n <= 0:
				sim.m.items.erase(s.cell)
			r.carry = {"type": s.type, "n": st.n}
			if s.has("dur"):
				r.carry.dur = s.dur
			sim.rev += 1
			return true
		"pickup_armor":  # put on a piece of armor (issue #140)
			var s = sim.m.items.get(st.stack.cell)
			if not is_same(s, st.stack) or s.n < 1:
				return "gone"
			s.n -= 1
			s.res -= 1
			j.holds.erase(st.hold)
			if s.n <= 0:
				sim.m.items.erase(s.cell)
			var slot: String = Defs.ITEMS[s.type].armor
			var old = r.armor.get(slot)
			if old != null:
				sim.drop_items(s.cell, old.type, 1, old.dur)
			r.armor[slot] = {"type": s.type, "dur": s.dur}
			sim.rev += 1
			return true
		"pickup_lighter":  # flint and steel in the hand, for the portal (issue #147)
			var ls = sim.m.items.get(st.stack.cell)
			if not is_same(ls, st.stack) or ls.n < 1:
				return "gone"
			ls.n -= 1
			ls.res -= 1
			j.holds.erase(st.hold)
			if ls.n <= 0:
				sim.m.items.erase(ls.cell)
			r.carry = {"type": ls.type, "n": 1, "dur": ls.get("dur", sim.full_uses(ls.type))}
			sim.rev += 1
			return true
		"pickup_tool":
			var s = sim.m.items.get(st.stack.cell)
			if not is_same(s, st.stack) or s.n < 1:
				return "gone"
			s.n -= 1
			s.res -= 1
			j.holds.erase(st.hold)
			if s.n <= 0:
				sim.m.items.erase(s.cell)
			var it: Dictionary = Defs.ITEMS[s.type]
			var old = r[it.tool]
			if old != null:
				sim.drop_items(s.cell, old.type, 1, old.dur)
			r[it.tool] = {"type": s.type, "tier": it.tier, "dur": s.dur}
			r.broken[it.tool] = false
			r.kept[it.tool] = st.get("keep", false)
			sim.rev += 1
			return true
		"deposit":
			var dest: Dictionary = st.site
			dest.incoming[st.type] -= st.n
			dest.store[st.type] = dest.store.get(st.type, 0) + st.n
			if r.carry.has("dur"):  # a spare tool packed at the expedition board keeps its wear
				dest.tools = dest.get("tools", []) + [{"type": st.type, "dur": r.carry.dur}]
			j.holds.erase(st.hold)
			r.carry = null
			sim.rev += 1
			return true
		"haul_drop":
			sim.m.zone_res.erase(st.cell)
			if r.carry == null:
				return "gone"
			j.holds.erase(st.hold)
			if st.has("pile_hold"):
				st.pile_hold.site.incoming[st.type] -= st.n
				j.holds.erase(st.pile_hold)
			if sim.in_store(st.cell):  # into a chest (issue #189)
				sim._store_put(st.cell, st.type, st.n, r.carry.get("dur", -1))
			else:
				sim.drop_items(st.cell, st.type, st.n, r.carry.get("dur", -1))
			if st.type == "iron_ore" and sim.m.kind == "village":  # a village-book goal (issue #198)
				sim.stats.ore_home = true
			r.carry = null
			return true
		"depart":  # off the edge of the map: onto the road map (#118), or the walk to or from the meadow (#137)
			var to: String = st.to
			if sim.realm_of(sim.expedition.get("dest", "")) == "nether":  # through the portal, which has to be lit (issue #148)
				if to != "village" and not sim.portal_lit():
					return false
				sim._cross_portal(r, to)
				return true
			sim._onto_road(r, to)
			return true
		"descend":  # through the door to the level below (issue #132)
			if sim.m.door_state != "open":
				sim.open_door(sim.map_id)
			sim._enter_level(r, MineLevels.level_id(sim.m.level + 1))
			return true
		"ascend":  # up from a level's entrance to the door of the level above
			var up := MineLevels.level_id(sim.m.level - 1)
			var at = sim.on_map(up, sim.nearest_walkable.bind(MineLevels.door_front(sim.maps[up])))
			sim.move_to_map(r, up, at if at != null else sim.maps[up].entrance)
			return true
		"at_door":  # the party has reached the door at the end of the level
			if sim.m.door_state == "closed":
				sim._find_door(r)
			return true
		"railhead_drop":  # rails set down at the railhead pile (issue #122)
			if r.carry == null:
				return "gone"
			sim.drop_items(sim._railhead_spot(), r.carry.type, r.carry.n)
			r.carry = null
			return true
		"dock":  # the minecart parked at the village station (issue #123)
			if r.carry == null or not sim.cart.is_empty():
				return "gone"
			r.carry = null
			sim.cart = {"at": "village", "x": sim.station_x("village"), "state": "parked", "load": {}, "riders": [], "acc": 0.0}
			sim.rev += 1
			sim._toast("The minecart is parked at the village station.", r.id)
			return true
		"load_cart":  # goods set on the freight cart (issue #172)
			if r.carry == null or r.carry.type != st.type or sim.freight.get("state", "") != "home":
				return "gone"
			sim.freight.load[st.type] = sim.freight.load.get(st.type, 0) + r.carry.n
			r.carry = null
			sim.rev += 1
			return true
		"freight_dock":  # the freight cart parked at the portal station (issue #169)
			if r.carry == null or sim.freight.get("state", "") != "ordered":
				return "gone"
			r.carry = null
			sim.freight.state = "home"
			sim.rev += 1
			sim._toast("The freight cart is parked at the portal station.", r.id)
			return true
		"board":  # into the cart (issue #124)
			if sim.cart.is_empty():
				return true
			if not sim.cart.riders.has(r.id):
				sim.cart.riders.append(r.id)
			j.label = st.riding
			return true
		"ride":
			if sim.cart.is_empty() or not sim.cart.riders.has(r.id):
				return true
			r.pos = sim._seat(r)
			r.path = []
			if sim.cart.state == "parked" and sim.cart.at == st.to:
				sim.cart.riders.erase(r.id)
				r.pos = Vector2(sim._off_cart_cell())
				return true
			return false
		"unload_wait":  # the party unloading its packs at the signpost (issue #123)
			return not sim.expedition.get("unloading", false)
		"road_end":  # the far end of the road: into the site, or home (issue #118)
			var leg: String = "road_" + sim.expedition.get("leg", "out")
			if sim.expedition.has(leg):
				sim.expedition[leg][1] = sim.tick
			if r.trip == "village":
				sim._arrive_home(r)
			else:
				sim._arrive_at_site(r)
			return true
		"cross":  # between the village and the road, for work out there (issues #119, #121)
			r.map = st.to
			var at = Road.VILLAGE_END
			if st.to == "village":
				at = sim.on_map("village", sim.nearest_walkable.bind(sim.route_sign()))
				at = at if at != null else sim.route_sign()
			r.pos = Vector2(at)
			r.path = []
			sim.rev += 1
			if st.to == Road.ID:
				sim._reveal(at)
			return true
		"ration":  # a meal out of the packs (issue #109)
			if sim.spendable_meals() <= 0:
				return "gone"
			var prov: Dictionary = sim.expedition.provisions
			var meal: String = prov.keys().filter(func(k): return prov[k] > 0)[0]
			prov[meal] -= 1
			if prov[meal] <= 0:
				prov.erase(meal)
			r.carry = {"type": meal, "n": 1}
			sim.rev += 1
			return true
		"stow":  # what's carried goes into the packs: meals, spare tools or cargo (issue #109)
			if r.carry == null:
				return "gone"
			if st.has("swap") and sim.cargo_have(st.swap) > 0:  # a better item swaps out the lowest cargo, left here (issue #185)
				var freed := mini(st.n, sim.cargo_have(st.swap))
				sim.expedition.cargo[st.swap] -= freed
				if sim.expedition.cargo[st.swap] <= 0:
					sim.expedition.cargo.erase(st.swap)
				sim.drop_items(sim.m.entrance, st.swap, freed)
			var over: int = r.carry.n - maxi(0, sim.pack_room())
			if over > 0:  # the packs filled up on the way: the rest is set down here
				sim.drop_items(sim.rcell(r), r.carry.type, over, r.carry.get("dur", -1))
				r.carry.n -= over
				if r.carry.n <= 0:
					r.carry = null
					return true
			if r.carry.type in sim.PEN_SUPPLIES:  # sticks or wheat set down at the meadow (issue #139)
				if not sim.expedition.has("supplies"):
					sim.expedition.supplies = {}
				sim.expedition.supplies[r.carry.type] = sim.expedition.supplies.get(r.carry.type, 0) + r.carry.n
			elif Defs.MEALS.has(r.carry.type):
				sim.expedition.provisions[r.carry.type] = sim.expedition.provisions.get(r.carry.type, 0) + r.carry.n
			elif r.carry.has("dur"):
				sim.expedition.tools.append({"type": r.carry.type, "dur": r.carry.dur})
			else:
				sim.expedition.cargo[r.carry.type] = sim.expedition.cargo.get(r.carry.type, 0) + r.carry.n
				sim._note_book(r.carry.type, r)
			r.carry = null
			sim.rev += 1
			return true
		"take_supply":  # sticks or wheat out of the packs, for the pens (issue #139)
			var sup: Dictionary = sim.expedition.get("supplies", {})
			var n: int = mini(st.n, sup.get(st.type, 0))
			if n <= 0:
				return "gone"
			sup[st.type] -= n
			if sup[st.type] <= 0:
				sup.erase(st.type)
			r.carry = {"type": st.type, "n": n}
			sim.rev += 1
			return true
		"put_back":  # what's left of them goes back into the packs
			if r.carry != null and r.carry.type == st.type:
				sim.expedition.supplies[st.type] = sim.expedition.supplies.get(st.type, 0) + r.carry.n
				r.carry = null
				sim.rev += 1
			return true
		"leash":  # the animal follows its leader to the pen
			if not st.target.alive:
				return "gone"
			st.target.led_by = r.id
			j.label = st.label
			return true
		"pen_in":
			var a: Dictionary = st.target
			var pn: Dictionary = st.pen
			if not a.alive or not sim.m.pens.any(func(x): return is_same(x, pn)):
				return "gone"
			var inside := sim.pen_inside(pn)
			var to := Vector2i(clampi(sim.rcell(r).x, inside.position.x, inside.end.x - 1), clampi(sim.rcell(r).y, inside.position.y, inside.end.y - 1))
			a.pen = pn.id
			a.lead = false
			a.led_by = 0
			a.led_to = 0
			a.cell = to
			a.pos = Vector2(to)
			a.dest = null
			sim.rev += 1
			return true
		"take_tool":  # the best spare pickaxe in the packs
			var tools: Array = sim.expedition.get("tools", [])
			if tools.is_empty() or r.pick != null:
				return "gone"
			tools.sort_custom(func(a, b): return Defs.ITEMS[a.type].tier > Defs.ITEMS[b.type].tier or (a.type == b.type and a.dur > b.dur))
			var t: Dictionary = tools.pop_front()
			r.pick = {"type": t.type, "tier": Defs.ITEMS[t.type].tier, "dur": t.dur}
			r.broken.pick = false
			sim.rev += 1
			return true
		"rest_site":  # seriously hurt at the site: waits at the entrance until the party goes home
			if not sim.at_site(r) or r.get("hurt", 0) < 2:
				return true
			if r.hunger < Tuning.EAT_BELOW and sim.spendable_meals() > 0:
				return true
			r.pos = Vector2(sim.rcell(r))
			return false
		"rest":  # healing at home (issue #110)
			if r.get("hurt", 0) == 0:
				return true
			if r.hunger < Tuning.EAT_BELOW and sim.food_available():
				return true
			if not st.bed and sim.tick % Tuning.TPS == 0 and sim.map_id == "village" and sim._has_bed(r):
				return true  # a bed of their own now: go and rest in it
			r.heal -= Tuning.DT * (1.0 if st.bed else Tuning.HEAL_NO_BED)
			r.pos = Vector2(sim.rcell(r))
			if r.heal <= 0.0:
				r.hurt = 0
				r.heal = 0.0
				sim.rev += 1
				sim._toast("%s has healed and is back at work." % r.name, r.id)
				return true
			return false
		"fight":  # blows at a creature, one every HIT_TIME, until it's down or out of reach (issue #151)
			var cr: Dictionary = st.target
			if not cr.alive:
				return true
			if sim.manhattan(sim.rcell(r), cr.cell) > 1:
				return "gone"
			r.pos = Vector2(sim.rcell(r))
			j.label = "Fighting the %s" % Defs.CREATURES[cr.species].name.to_lower()
			st.t = st.get("t", 0.0) + Tuning.DT
			if st.t >= Tuning.HIT_TIME / sim.skill_speed(r, "guard") * st.get("slow", 1.0):
				st.t = 0.0
				sim._strike(r, cr)
			return not cr.alive
		"enter_route":  # out of the landing onto a route's west end (issue #153)
			var def: Dictionary = NetherRoute.ROUTES[st.route]
			sim.maps[def.id].known = true
			sim.move_to_map(r, def.id, sim.maps[def.id].entrance)
			sim._toast("%s set out along the %s." % [r.name, def.name.substr(8).to_lower()], r.id)
			return true
		"reach_segment":  # a segment of the route is seen: its terrain and dangers are known (issue #153)
			if sim.m.seen < st.idx + 1:
				sim.m.seen = st.idx + 1
				sim.rev += 1
				var rd: Dictionary = NetherRoute.ROUTES[NetherRoute.route_of(sim.map_id)]
				sim._toast("The scouts reached %s." % rd.segments[st.idx].name.to_lower(), r.id)
			return true
		"route_end":  # the far end: the route is scouted, and so is its site (issue #153)
			if not sim.m.surveyed:
				sim.m.surveyed = true
				var rk := NetherRoute.route_of(sim.map_id)
				var site: SimMap = sim.maps[NetherRoute.ROUTES[rk].site]
				site.known = true
				sim.rev += 1
				sim._toast("The route is scouted. The %s is known now." % site.name.substr(8).to_lower(), r.id)
				if sim.expedition.get("leg", "out") == "out":
					sim._head_home("the route is scouted")
			return true
		"to_site":  # the route's far end: onto the site (issue #155)
			var tk := sim.dest_route(sim.expedition.get("dest", ""))
			sim._enter_level(r, NetherRoute.ROUTES[tk].site)
			return true
		"leave_site":  # off a site, back onto the route's far end (issue #155)
			var lk := NetherRoute.site_key(sim.map_id)
			sim.move_to_map(r, NetherRoute.ROUTES[lk].id, Vector2i(NetherRoute.W - 1, NetherRoute.LINE_ROW))
			return true
		"leave_route":  # back onto the landing, at the edge the route leaves from (issue #153)
			var back: Dictionary = NetherRoute.ROUTES[NetherRoute.route_of(sim.map_id)]
			sim.move_to_map(r, NetherLanding.ID, back.exit)
			return true
		"learn_book":  # the book is read into the workshop: its recipe is known for good, and the book is used up (issue #165)
			var ws: Dictionary = st.site
			var ench: String = Defs.ITEMS[st.book].book
			ws.store[st.book] = ws.store.get(st.book, 0) - 1
			if ws.store[st.book] <= 0:
				ws.store.erase(st.book)
			if not ws.known.has(ench):
				ws.known.append(ench)
				sim.stats.enchants_learned = sim.stats.get("enchants_learned", 0) + 1
				sim._toast("The enchanting workshop learned %s." % Defs.ENCHANTS[ench].name, r.id, ws.id)
			sim.rev += 1
			return true
		"cache_stock":  # meals set down in the cache, above what the party keeps for the way home (issue #152)
			var cache := sim.shelter_site()
			var moved := 0
			for k in sim.expedition.get("provisions", {}).keys():
				while moved < sim.expedition.get("stock", 0) and sim.expedition.provisions[k] > 0 and sim._pack_spendable() > 0:
					sim.expedition.provisions[k] -= 1
					cache.store[k] = cache.store.get(k, 0) + 1
					moved += 1
				if sim.expedition.provisions[k] <= 0:
					sim.expedition.provisions.erase(k)
			sim.expedition.stock = 0
			sim.rev += 1
			if moved > 0:
				sim._toast("%d %s left in the cache." % [moved, "meal" if moved == 1 else "meals"], r.id)
			return true
		"cache_take":  # a meal from the cache into the packs, to eat (issue #152)
			var from := sim.shelter_site()
			for k in from.get("store", {}):
				if Defs.MEALS.has(k) and from.store[k] > 0:
					from.store[k] -= 1
					if from.store[k] <= 0:
						from.store.erase(k)
					sim.expedition.provisions[k] = sim.expedition.get("provisions", {}).get(k, 0) + 1
					sim.rev += 1
					return true
			return "gone"
		"wait_stranded":  # sheltering until the rescue (or the window) ends it (issue #158)
			if not sim.expedition.has("stranded"):
				return true
			j.label = "Sheltering, waiting for a rescue"
			r.pos = Vector2(sim.rcell(r))
			return false
		"rescue_reach":  # the stranded are reached: they get what the rescue carries, and everyone heads home (issue #158)
			var lost: Dictionary = sim.expeditions.nether
			if not lost.has("stranded"):
				return true
			var spare := sim._pack_spendable()
			if spare > 0:  # the meals past its own walk home
				for k in sim.expedition.get("provisions", {}).keys():
					while spare > 0 and sim.expedition.provisions[k] > 0:
						sim.expedition.provisions[k] -= 1
						lost.provisions[k] = lost.get("provisions", {}).get(k, 0) + 1
						spare -= 1
			if lost.get("lighter", {}).is_empty() and not sim.expedition.get("lighter", {}).is_empty():
				lost.lighter = sim.expedition.lighter.duplicate()
			lost.erase("stranded")
			lost.leg = "home"
			lost.home_why = "rescued"
			for id in lost.party:
				var lr := sim.resident(id)
				if not lr.is_empty():
					sim.fail_job(lr)
			sim.expedition.leg = "home"
			sim.expedition.home_why = "the stranded party is reached"
			for id in sim.expedition.party:
				sim.fail_job(sim.resident(id))
			sim.stats.rescues = sim.stats.get("rescues", 0) + 1
			sim.rev += 1
			sim._toast("The stranded party is rescued. Everyone heads home.", r.id)
			return true
		"open_salvage":  # the chest at the far end, and the sealed way beside it: the game stops once for the choice (issue #157)
			if sim.m.salvage_taken or not sim.pending.filter(func(p): return p.kind == "fortress").is_empty():
				return true
			if not sim.m.surveyed:
				sim.m.surveyed = true
				sim._ask("fortress", "The party reached a salvage chest at the far end of the fortress. Beside it a sealed way leads deeper, which a later expedition could open.", [
					{"id": "take", "label": "Take it and return", "cost": "The party takes the salvage (%s) and heads home." % ", ".join(Defs.FORTRESS_SALVAGE.keys().map(func(k): return Defs.words(k, Defs.FORTRESS_SALVAGE[k]))) },
					{"id": "press", "label": "Take it and press on", "cost": "The party takes the salvage and stays to clear the halls of blazes and skeletons, for more blaze rods. The way deeper stays sealed."},
				], r.id)
			return true
		"trade":  # every trade the gold pays for, down the table; goods go into the packs (issue #156)
			if sim.m.hostile:
				return "gone"
			var made := 0
			var counts := {}
			while true:
				var ti := sim._next_trade()
				if ti < 0:
					break
				counts[ti] = counts.get(ti, 0) + 1
				var t: Dictionary = Defs.TRADES[ti]
				for k in t.give:
					sim.expedition.supplies[k] -= t.give[k]
					if sim.expedition.supplies[k] <= 0:
						sim.expedition.supplies.erase(k)
				for k in t.get:
					sim.expedition.cargo[k] = sim.expedition.cargo.get(k, 0) + t.get[k]
					sim._note_book(k, r)
				made += 1
			for ti in counts:
				sim.expedition.traded = sim.expedition.get("traded", []) + [Defs.trade_text(Defs.TRADES[ti]) + (" ×%d" % counts[ti] if counts[ti] > 1 else "")]
			sim.expedition.trade_done = true
			sim.rev += 1
			if made > 0:
				sim._toast("The party traded with the piglins: %s." % "; ".join(sim.expedition.traded), r.id)
			return true
		"mark_seen":  # a landmark is seen; the last one surveys the landing (issue #148)
			if not sim.m.landmarks_seen.has(st.cell):
				sim.m.landmarks_seen.append(st.cell)
				sim.rev += 1
				if sim.m.landmarks_seen.size() >= sim.m.landmarks.size() and not sim.m.surveyed:
					sim.m.surveyed = true
					sim._toast("The landing is surveyed: %d landmarks seen." % sim.m.landmarks.size(), r.id)
			return true
		"wait_portal":  # the portal has gone out, and nobody carries flint and steel: waits for the village to light it
			if sim.portal_lit():
				return true
			j.label = "Waiting at the dark portal"
			r.pos = Vector2(sim.rcell(r))
			return false
		"wait_board":  # waits at the board until the party departs (issue #107)
			if sim.expedition.get("state", "") != "staging" or not sim.expedition.party.has(r.id):
				return true
			if r.hunger < Tuning.EAT_BELOW and sim.food_available():
				return true  # goes to eat, then comes back
			if sim.tick % Tuning.TPS == 0 and sim._can_pack_more():
				return true  # something to carry has turned up: pack it, then come back
			j.label = "Waiting at the expedition board"
			r.pos = Vector2(sim.rcell(r))
			return false
		"move_in":
			st.site.owner = r.id
			r.arriving = false
			j.holds.clear()
			sim.stats.traveler_home = true
			sim._toast("%s moved into the new house." % r.name, r.id)
			return true
		"work":
			if not st.has("total"):
				var total := sim._work_time(r, st)
				if total < 0.0:
					return "needs_pick"
				if st.what != "eat" and st.what != "graze" and r.hunger < Tuning.HUNGRY_BELOW:
					total /= Tuning.HUNGRY_SPEED
				if j.work != "":
					total /= sim.skill_speed(r, j.work)
				if st.what != "eat":
					total /= sim.hurt_speed(r)
					if sim.m.is_dark(sim.rcell(r)):  # unlit tunnels are slow going (issue #110)
						total /= Tuning.DARK_WORK
				st.total = total
				st.t = 0.0
				j.label = st.label
			st.t += Tuning.DT
			r.progress = minf(1.0, st.t / st.total)
			if st.t >= st.total:
				r.progress = -1.0
				return sim._finish_work(r, st)
			return false
	return "gone"


static func _work_time(sim: Sim, r: Dictionary, st: Dictionary) -> float:
	match st.what:
		"gather":
			var tier: int = r[st.tool].tier if r[st.tool] != null else 0
			if st.tool == "axe":
				return Tuning.CHOP_TIME[tier] / sim.tool_speed(r, "axe")
			if st.target.get("ore", "") == "glowstone":  # it breaks by hand (issue #155)
				return Tuning.GLOWSTONE_TIME
			if tier < Tuning.ORE_PICK_TIER.get(st.target.get("ore", ""), 0):  # diamonds want an iron pickaxe (issue #186), obsidian a diamond one (#146)
				return -1.0
			return Tuning.BREAK_TIME[tier] / sim.tool_speed(r, "pick") if tier > 0 else -1.0
		"dig":
			return Tuning.SHAFT_DIG if r.pick != null and r.pick.tier > 0 else -1.0
		"build":
			return Tuning.LAY_TIME if st.site.tpl == "track" else Tuning.STAGE_TIME
		"light", "relight":
			return Tuning.PORTAL_LIGHT_TIME
		"enchant":
			return Tuning.ENCHANT_TIME
		"lay_dust":
			return Tuning.DUST_TIME
		"pline":
			return Tuning.LAY_TIME if st.task.kind == "rail" else Tuning.STAGE_TIME
		"nline":
			return {"bridge": Tuning.NETHER_BRIDGE_TIME, "rail": Tuning.LAY_TIME, "station": Tuning.STAGE_TIME, "cart": 4.0}[st.task.kind]
		"shelter":
			return Tuning.SHELTER_BUILD_TIME
		"hunt":
			return Tuning.HUNT_TIME
		"dig_bush":
			return Tuning.BUSH_DIG_TIME
		"plant":
			return Tuning.PLANT_TIME
		"plant_tree":
			return Tuning.PLANT_TREE_TIME
		"harvest":
			return Tuning.HARVEST_TIME
		"eat", "graze":
			return Tuning.EAT_TIME
		"survey":
			return Tuning.SURVEY_TIME
		"fence":
			return Tuning.FENCE_TIME
		"feed":
			return Tuning.FEED_TIME
		_:
			match st.get("recipe", {}).get("id", ""):
				"bread": return Tuning.BAKE_TIME
				"cooked_mutton", "cooked_beef", "cooked_porkchop": return Tuning.COOK_TIME
				"smelt_iron", "smelt_gold": return Tuning.SMELT_TIME
			return Tuning.CRAFT_TIME


static func _finish_work(sim: Sim, r: Dictionary, st: Dictionary):
	match st.what:
		"gather":
			var t: Dictionary = st.target
			if not t.alive:
				return "gone"
			t.alive = false
			t.des = false
			sim._occ_dirty = true
			if t.kind == "tree":
				sim.drop_items(t.cell, "log", t.logs + sim.skill_bonus(r, "lumber"))
				var saplings := Tuning.SAPLINGS + (1 if sim.rng.randf() < Tuning.SAPLING_EXTRA else 0)
				sim.drop_items(t.cell, "sapling", saplings)  # issue #177
				sim.stats.felled += 1
			elif t.has("ore"):  # an ore block (issue #103); it never comes back (issue #102)
				if t.ore == "gravel":  # sometimes a flint, else nothing (issue #146)
					if sim.rng.randf() < Tuning.GRAVEL_FLINT_CHANCE:
						sim.drop_items(t.cell, "flint", 1)
				elif t.ore == "chest":  # the book inside (issue #164)
					sim.drop_items(t.cell, t.book, 1)
				else:
					sim.drop_items(t.cell, Defs.ORES[t.ore].item, Tuning.ORE_YIELD[t.ore] + sim.skill_bonus(r, "mason"))
				sim.stats.ore_mined = sim.stats.get("ore_mined", 0) + 1
			else:
				sim.drop_items(t.cell, "cobble", Tuning.BOULDER_COBBLE + sim.skill_bonus(r, "mason"))
				sim.stats.broken_boulders += 1
			sim._wear(r, st.tool)
			if t.get("loose", false):  # issue #110
				sim._hazard(r, sim.cave_in_chance(sim.m.level), Tuning.CAVE_IN_SERIOUS, "a cave-in")
			sim._check_find(t.cell)  # issue #111
			sim._check_find_diamond(t.cell)  # issue #186
		"light":  # the frame is lit, and the flint and steel goes back with a use less (issue #147)
			var portal: Dictionary = st.site
			if portal.lit:
				return "gone"
			portal.lit = true
			portal.builder = 0
			sim.maps[NetherLanding.ID].known = true  # the board has word of it now (issue #148)
			if r.carry != null and r.carry.type == "flint_and_steel":
				var left: int = r.carry.dur - 1
				if left > 0:
					sim.drop_items(sim.rcell(r), "flint_and_steel", 1, left)
				else:
					sim._toast("%s’s flint and steel is spent." % r.name, r.id)
				r.carry = null
			sim.rev += 1
			sim._toast("The portal is lit.", r.id, portal.id)
		"enchant":  # the item takes its enchantment: it keeps its wear, and the lapis and ingredient are used up (issue #166)
			var ew: Dictionary = st.site
			ew.crafter = 0
			ew.crafting = ""
			if ew.orders.is_empty() or not is_same(ew.orders[0], st.order):
				return "gone"
			var ord: Dictionary = st.order
			var cost: Dictionary = Defs.ENCHANTS[ord.ench].cost
			for k in cost:
				if ew.store.get(k, 0) < cost[k]:
					return "gone"
			var held: Array = ew.get("tools", []).filter(func(t): return t.type == ord.item)
			if held.is_empty():
				return "gone"
			for k in cost:
				ew.store[k] -= cost[k]
				if ew.store[k] <= 0:
					ew.store.erase(k)
			ew.tools.erase(held[0])
			ew.store[ord.item] = ew.store.get(ord.item, 0) - 1
			if ew.store[ord.item] <= 0:
				ew.store.erase(ord.item)
			ew.orders.pop_front()
			sim.drop_items(ew.origin, ord.item + "+" + ord.ench, 1, held[0].dur)
			sim.stats.enchanted = sim.stats.get("enchanted", 0) + 1
			sim.rev += 1
			sim._toast("%s enchanted: %s." % [r.name, Defs.ITEMS[ord.item + "+" + ord.ench].one], r.id, ew.id)
		"nline":  # a piece of the Nether line (issue #159)
			sim._finish_line_task(st.task, r)
		"lay_dust":  # one cell of a dust line (issue #170)
			var w = sim.wire_by_id(st.wire)
			if w == null or w.laid >= w.cells.size() or r.carry == null or r.carry.type != "redstone":
				return "gone"
			w.laid += 1
			if w.laid >= w.cells.size() or w.laid % Tuning.DUST_PER_REDSTONE == 0:
				r.carry.n -= 1
				if r.carry.n <= 0:
					r.carry = null
			sim.rev += 1
			if w.laid >= w.cells.size():
				sim._toast("A dust line is laid.", r.id, w.to)
		"pline":  # a piece of the portal line (issue #168)
			sim._finish_pline_task(st.task, r)
		"shelter":  # the party's cobblestone and planks go into the walls (issue #152)
			var shelter: Dictionary = st.site
			shelter.builder = 0
			if shelter.done or not sim._supplies_cover(Tuning.SHELTER_COST):
				return "gone"
			for k in Tuning.SHELTER_COST:
				sim.expedition.supplies[k] -= Tuning.SHELTER_COST[k]
				if sim.expedition.supplies[k] <= 0:
					sim.expedition.supplies.erase(k)
			shelter.stage = 1
			shelter.done = true
			sim._occ_dirty = true
			sim.rev += 1
			sim._toast("The shelter is built. Injured residents rest in it, and meals left in its cache feed later parties.", r.id)
		"relight":  # the party's own flint and steel, from the packs (issue #148)
			var vp := sim.village_portal()
			if not vp.is_empty():
				vp.lit = true
			var lighter: Dictionary = sim.expedition.get("lighter", {})
			if not lighter.is_empty():
				lighter.dur -= 1
				if lighter.dur <= 0:
					sim.expedition.erase("lighter")
					sim._toast("%s’s flint and steel is spent." % r.name, r.id)
			sim.rev += 1
			sim._toast("The portal is lit again.", r.id)
		"dig":
			var shaft: Dictionary = st.site
			if not shaft.get("shaft", false):
				return "gone"
			var at: Vector2i = shaft.origin
			for pc in sim.pile_cells(shaft):  # onto the pile beside it, when there's room
				var there = sim.m.items.get(pc)
				if there == null or (there.type == "cobble" and there.n < Defs.stack_cap("cobble")):
					at = pc
					break
			sim.drop_items(at, "cobble", 1)
			shaft.digs = shaft.get("digs", 0) + 1
			sim.stats.stone_dug = sim.stats.get("stone_dug", 0) + 1
			if shaft.digs % Tuning.SHAFT_WEAR_EVERY == 0:
				sim._wear(r, "pick")
		"eat":
			if r.carry == null:
				return "gone"
			r.hunger = minf(100.0, r.hunger + Tuning.FOOD_VALUE.get(r.carry.type, 0.0))
			r.carry = null
		"dig_bush":
			var dug: Dictionary = st.target
			if not sim.m.bushes.any(func(o): return is_same(o, dug)):
				return "gone"
			if dug.berries > 0:
				sim.drop_items(dug.cell, "berries", dug.berries)
			sim.m.bushes = sim.m.bushes.filter(func(o): return not is_same(o, dug))
			sim._occ_dirty = true
			sim.rev += 1
		"graze":
			var bush: Dictionary = st.target
			if bush.berries <= 0 or not sim.m.bushes.has(bush):
				return true
			bush.berries -= 1
			r.hunger = minf(100.0, r.hunger + Tuning.FOOD_VALUE.berries)
			sim.rev += 1
			if bush.berries > 0 and r.hunger < Tuning.EAT_UNTIL:
				st.erase("total")  # eat another berry
				return false
		"hunt":
			var sh: Dictionary = st.target
			if not sh.alive:
				return "gone"
			sh.alive = false
			sh.des = false
			for k in Tuning.ANIMAL_DROPS[sh.species]:  # issue #138
				sim.drop_items(sh.cell, k, Tuning.ANIMAL_DROPS[sh.species][k])
			if sh.species == "sheep":
				sim.stats.sheep_hunted = sim.stats.get("sheep_hunted", 0) + 1
			sim.stats.hunted = sim.stats.get("hunted", 0) + 1
			if sh.species == "cow" and sim.m.id == Meadow.ID:  # issue #137: never serious
				sim._hazard(r, Tuning.BULL_CHANCE, 0.0, "an angry bull")
			sim.rev += 1
		"plant":
			var crop: Dictionary = st.target
			if not is_same(sim.m.farm.get(crop.cell), crop) or crop.grow >= 0.0 or sim.m.items.has(crop.cell):
				return "gone"
			crop.grow = 0.0
			sim.stats.planted = sim.stats.get("planted", 0) + 1
			sim.rev += 1
		"plant_tree":  # issue #177
			var pc: Vector2i = st.cell
			if r.carry == null or r.carry.type != "sapling" or not sim.walkable(pc) or sim.m.items.has(pc) or sim.residents.any(func(o): return o.map == sim.map_id and sim.rcell(o) == pc) or sim.m.sheep.any(func(a): return a.alive and a.cell == pc):
				return "gone"
			r.carry = null
			sim.m.trees.append({"id": sim._id(), "kind": "tree", "cell": pc, "logs": 4 + (sim.next_id * 7) % 3, "alive": true, "des": false,
				"claim": 0, "unreach_until": 0, "grow": 0.0})
			sim._occ_dirty = true
			sim.stats.trees_planted = sim.stats.get("trees_planted", 0) + 1
			sim.rev += 1
		"harvest":
			var crop: Dictionary = st.target
			if not is_same(sim.m.farm.get(crop.cell), crop) or not sim.crop_ripe(crop):
				return "gone"
			crop.grow = -1.0
			sim.drop_items(crop.cell, "wheat", Tuning.WHEAT_YIELD + sim.skill_bonus(r, "farm"))
			sim.stats.harvested = sim.stats.get("harvested", 0) + 1
			sim.rev += 1
		"survey":  # issue #111
			for i in Tuning.SURVEY_USES:
				sim._wear(r, "pick")
			sim.survey(sim.map_id)
			sim.expedition.survey = false
			sim._toast("%s surveyed the vein: about %d iron ore. Iron can be an expedition's target now." % [r.name, sim.ore_left(sim.map_id, "iron") * Tuning.ORE_YIELD.iron], r.id)
		"fence":  # issue #139
			var pn: Dictionary = st.pen
			if not sim.m.pens.any(func(x): return is_same(x, pn)) or pn.built.has(st.cell) or r.carry == null or r.carry.type != "stick" or r.carry.n < Tuning.FENCE_STICKS:
				return "gone"
			r.carry.n -= Tuning.FENCE_STICKS
			if r.carry.n <= 0:
				r.carry = null
			sim._fence_claims.erase(st.cell)
			sim._put_fence(pn, st.cell)
		"feed":
			var pair: Array = st.pair
			if r.carry == null or r.carry.type != "wheat" or r.carry.n < 2 * Tuning.FEED_WHEAT or not pair.all(func(a): return a.alive and a.get("pen", 0) == pair[0].pen):
				return "gone"
			r.carry.n -= 2 * Tuning.FEED_WHEAT
			if r.carry.n <= 0:
				r.carry = null
			for a in pair:
				a.fed_at = sim.tick
			sim.stats.fed = sim.stats.get("fed", 0) + 1
			sim.rev += 1
		"build":
			if st.site.tpl == "track":
				sim._lay_rail(st.site)
			else:
				sim._complete_stage(st.site)
		"craft":
			var b: Dictionary = st.site
			var rec := sim.recipe_for(r, st.recipe)
			var qi: int = b.queue.find(rec.id)
			if qi < 0 or not sim.has_all(b.store, rec.inp):
				return "gone"
			for k in rec.inp:
				b.store[k] -= rec.inp[k]
			b.queue.remove_at(qi)
			b.autoq.remove_at(qi)
			for o in rec.out:
				var uses := -1
				if Defs.is_tool_item(o):  # Toolsmith: +20% uses per level above 1
					uses = roundi(sim.full_uses(o) * (1.0 + Tuning.TOOLSMITH_USES * (mini(sim.level(r, "toolsmith"), Tuning.SKILL_CORE) - 1 + sim.tail_steps(sim.level(r, "toolsmith")))))
				sim.drop_items(sim.rcell(r), o, rec.out[o], uses)
				if Defs.MEALS.has(o):  # a village-book goal (issue #198)
					sim.stats.meals_cooked = sim.stats.get("meals_cooked", 0) + rec.out[o]
				if Defs.ITEMS[o].get("tool", "") == "pick":
					sim.stats.pick_crafted = true
				if Defs.ITEMS[o].get("tool", "") == "axe":
					sim.stats.axe_crafted = true
			if b.queue.is_empty():  # a skilled cook's spare wheat goes back out
				for k in b.store:
					if b.store[k] > 0:
						sim.drop_items(b.origin + Vector2i(0, 1), k, b.store[k])
				b.store = {}
	return true
