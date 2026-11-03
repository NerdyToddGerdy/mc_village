class_name Stuck
extends RefCounted
## Stuck reasons (issues #77, #296), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.


## `waiting` marks a standing order short of materials (issue #77): advice, not a blocker, so it
## gets no flag and sits in the stuck list's dim Waiting tier.
## `decision` names a choice the game is waiting on the player for ("freight"), shown apart from the blockers (issue #296). It is also `waiting`: no flag on the map.
static func _add_stuck(sim: Sim, who: String, why: String, at: Vector2, height: float, fk: String, fid: int, hidden := false, waiting := false, decision := "") -> void:
	# The same problem keeps its age while its count changes ("4 more planks" -> "3 more planks").
	var key := "%s|%s|%d|%s|%s" % [sim.map_id, fk, fid, who, _DIGITS.sub(why, "#", true)]
	if not sim._stuck_since.has(key):
		sim._stuck_since[key] = sim.tick
	sim.stuck.append({"who": who, "why": why, "map": sim.map_id, "cell": at, "height": height, "focus_kind": fk, "focus_id": fid, "hidden": hidden,
		"waiting": waiting or decision != "", "decision": decision, "key": key, "since": sim._stuck_since[key]})


static var _DIGITS := RegEx.create_from_string("\\d+")


## Works out every map's stuck reasons. Each carries its map, so focusing it can switch the view.
static func compute_stuck(sim: Sim) -> void:
	sim.stuck = []
	var prev := sim.map_id
	for id in sim.maps.keys():
		sim.use_map(id)
		sim._stuck_on_map()
	sim.use_map(prev)
	var now := {}
	for s in sim.stuck:
		now[s.key] = sim._stuck_since[s.key]
	sim._stuck_since = now


static func _stuck_on_map(sim: Sim) -> void:
	var on_here := sim.here()
	var any_pick := not sim.tool_items("pick", 0).is_empty()
	for r in on_here:
		if r.pick != null:
			any_pick = true
	var first := true
	for b in sim.m.boulders:
		if b.alive and b.des and not any_pick:
			sim._add_stuck(sim.block_name(b), "Needs a pickaxe", Vector2(b.cell) + Vector2(0.5, 0.5), 1.1, "boulder", b.id, not first)
			first = false
	for s in sim.m.sites:
		var tpl: Dictionary = Defs.TEMPLATES[s.tpl]
		var mid := Vector2(s.origin) + Vector2(s.size) / 2.0
		if s.tpl == "portal" and s.done:  # the frame stands: it wants flint and steel (issue #147)
			if not s.lit and s.builder == 0 and sim.stacks_where(func(x): return x.type == "flint_and_steel" and sim.avail(x) > 0).is_empty():
				sim._add_stuck("Portal", "Needs flint and steel to light", mid, 2.9, "site", s.id)
			continue
		if s.tpl == "track":  # only the segment being laid speaks up; the rest wait their turn (issue #121)
			if s.done or s.seg != sim.next_track():
				continue
			var bl := sim.track_blocker(s.seg)
			if bl != "":
				sim._add_stuck(tpl.name, "Track: %s first" % bl.to_lower(), mid, 0.4, "site", s.id)
			elif not sim._staffed("build"):
				sim._add_stuck(tpl.name, "Track: no one is a builder", mid, 0.4, "site", s.id)
			elif sim.line_short() > 0:
				sim._add_stuck(tpl.name, "Track: needs %d more rails" % sim.line_short(), mid, 0.4, "site", s.id)
			continue
		if not s.done and not sim.footprint_clear(s):
			var ob := sim.site_obstacles(s)
			var nb: int = ob.boulders.size()
			if nb and not any_pick:
				sim._add_stuck(tpl.name, "Needs a pickaxe to clear " + ("a boulder" if nb == 1 else "%d boulders" % nb), mid, 0.6, "site", s.id)
			if not ob.items.is_empty():  # loose stacks to carry off (issue #205)
				var homeless: Array = ob.items.filter(func(st): return not sim._stack_has_home(st))
				if not homeless.is_empty():
					sim._add_stuck(tpl.name, "Clearing: no room in a stockpile for %s" % ", ".join(sim.stacks_text(homeless)), mid, 0.6, "site", s.id)
				else:
					sim._add_stuck(tpl.name, "Clearing: %s to move" % sim.clearing_text(ob), mid, 0.6, "site", s.id, false, true)
			continue
		var cost := {}
		var label := ""
		var verb := "needs"
		var standing := false
		if not s.done:
			var st := sim.current_stage(s)
			cost = st.cost
			label = "Bench" if s.tpl == "bench" else st.name
			verb = st.verb
		elif sim.is_station(s) and not s.queue.is_empty() and s.crafter == 0 and sim.bench_craftable(s).is_empty() and sim.bench_active(s) < 0:
			var rec := Defs.recipe(s.queue[0])
			cost = rec.inp
			label = rec.name
			standing = str(s.autoq[0]) != "false"  # the toolsmith's spare or the fireplace's meals
			if str(s.autoq[0]) == "toolsmith":
				label = "Toolsmith"
		else:
			continue
		var worst := ""
		var worst_n := 0
		for k in cost:
			var short: int = cost[k] - s.store.get(k, 0) - s.incoming.get(k, 0) - sim.free_count(k)
			if sim.m.kind == "route":  # the road is supplied from the village (issue #119)
				short -= sim.on_map("village", sim.free_count.bind(k))
			if short > worst_n:
				worst = k
				worst_n = short
		if worst_n > 0:
			var it: Dictionary = Defs.ITEMS[worst]
			var why := "%s %s %d more %s" % [label, verb, worst_n, it.one if worst_n == 1 else it.many]
			if label == "Bed":
				why = "House needs a bed: %d more %s" % [worst_n, it.one if worst_n == 1 else it.many]
			elif label == "Toolsmith":
				var kind: String = Defs.ITEMS[Defs.recipe(s.queue[0]).out.keys()[0]].tool
				why = "Toolsmith needs %d more %s for a spare %s" % [worst_n, it.one if worst_n == 1 else it.many, sim.TOOL_NAMES[kind]]
			sim._add_stuck(sim.station_name(s), why,
				mid, sim.site_height(s) + 0.4, "site", s.id, false, standing)
	sim._stuck_unstaffed()
	sim._stuck_workstations()
	sim._stuck_freight()
	sim._stuck_farm()
	for sl in sim.SLOTS:
		sim.on_slot(sl, sim._stuck_expedition)
	for sl in sim.SLOTS:
		if sim.SLOT_REALM[sl] == sim.realm_of(sim.map_id):
			sim.use_slot(sl)
			sim._stuck_site()
	sim.use_slot("overworld")
	var has_food: bool = sim.food_available() if sim.m.kind != "route" and sim.m.kind != "walk" else sim.on_map("village", sim.food_available)  # the road eats from home
	for r in on_here:
		var at: Vector2 = r.pos + Vector2(0.5, 0.5)
		if r.hunger <= 0.0 and not has_food:
			sim._add_stuck(r.name, "Starving: no food stored", at, 1.6, "res", r.id)
		elif r.hunger < Tuning.HUNGRY_BELOW and not has_food:
			sim._add_stuck(r.name, "Hungry: no food stored", at, 1.6, "res", r.id)
		for k in ["axe", "pick"]:
			if r.broken[k] and r[k] == null:
				var tname := "Axe" if k == "axe" else "Pickaxe"
				if sim._spare_queued(k):
					sim._add_stuck(r.name, "%s broke. Waiting for the toolsmith’s spare" % tname, at, 1.6, "res", r.id)
				elif not sim.has_toolsmith():
					sim._add_stuck(r.name, "%s broke. Craft one at the bench, or make someone the toolsmith" % tname, at, 1.6, "res", r.id)
				else:
					sim._add_stuck(r.name, "%s broke. Needs a new %s" % [tname, tname.to_lower()], at, 1.6, "res", r.id)
		if r.note != null and r.note.until > sim.tick:
			sim._add_stuck(r.name, r.note.text, at, 1.6, "res", r.id)
		if r.get("hurt", 0) > 0:  # issue #110: rest is a reason, not a blocker
			var left := ceili(r.heal / (1.0 if sim._has_bed(r) else Tuning.HEAL_NO_BED))
			var burned: bool = "burn" in str(r.get("hurt_cause", ""))  # the Nether's fire and lava say so (issue #149)
			var word := "Burned" if burned else "Injured"
			var why := "%s: can't mine, and works slower" % word if r.hurt == 1 else "Seriously %s: waiting at the entrance" % ("burned" if burned else "hurt")
			if sim.resting(r):
				why = "%s, resting in bed (%d s)" % [word if r.hurt == 1 else "Seriously " + ("burned" if burned else "hurt"), left] if sim._has_bed(r) else "%s, resting: no bed of their own, so it's slower (%d s)" % [word, left]
			elif r.map == NetherLanding.ID and sim.shelter_site().get("done", false):  # issue #152
				why = "%s, resting at the shelter (%d s)" % [word if r.hurt == 1 else "Seriously " + ("burned" if burned else "hurt"), ceili(r.heal / Tuning.HEAL_NO_BED)]
			sim._add_stuck(r.name, why, at, 1.6, "res", r.id, false, true)
	if sim.m.zone.is_empty() and not sim.m.sites.any(func(s): return s.tpl == "storehouse" and s.done and s.get("chests", 0) > 0):
		for k in sim.m.farm:  # nowhere to keep it: it's carried clear, and the plot waits for that (issue #318)
			if sim.m.farm[k].grow < 0.0 and sim.m.items.has(k) and sim._clear_spot(k, sim._clearing_cells()) == null:
				sim._add_stuck("Farm", "Harvested wheat has no open ground to be carried to before replanting", Vector2(k) + Vector2(0.5, 0.5), 0.6, "crop", sim.m.farm[k].id)
				break
	var stores := sim.m.sites.filter(func(s): return s.tpl == "storehouse" and s.done)
	for s in stores:  # issue #189
		var at := Vector2(s.origin) + Vector2(1.5, 1.5)
		if not sim.walkable(sim.store_door(s)):
			sim._add_stuck("Storehouse", "Can’t reach the storehouse: its door is blocked", at, 2.2, "site", s.id)
		elif s.get("chests", 0) == 0:
			sim._add_stuck("Storehouse", "No chests yet. Craft one at the bench (8 planks)", at, 2.2, "site", s.id)
	if not sim.m.zone.is_empty() or not stores.is_empty():
		var piles := sim.pile_map()
		var loose := sim.stacks_where(func(s): return sim.avail(s) > 0 and not sim.stored(s, piles) and s.type != "chest")
		var full := not loose.is_empty()
		var tried := {}
		for s in loose:
			if tried.has(s.type):
				continue
			tried[s.type] = true
			if sim.zone_dest(s.type) != null or sim.store_dest(s.type, s.cell) != null:
				full = false
				break
		if full:
			var room := stores.filter(func(s): return s.get("chests", 0) > 0 and sim.walkable(sim.store_door(s)))
			if not room.is_empty():
				sim._add_stuck("Storehouse", "The storehouse is full", Vector2(room[0].origin) + Vector2(1.5, 1.5), 2.2, "site", room[0].id)
			if not sim.m.zone.is_empty():
				sim._add_stuck("Stockpile", "Stockpile is full", Vector2(sim.m.zone.keys()[0]) + Vector2(0.5, 0.5), 0.6, "", 0)


## "No one is a farmer" (spec §9): there's work of a job, nobody but Ada has it, and Ada can't see
## to it, being away, hurt or packing for an expedition (issue #134).
static func _stuck_unstaffed(sim: Sim) -> void:
	if sim.here().is_empty() or sim.m.kind == "site":  # a party works a site whatever its jobs (issue #109)
		return
	for jb in Defs.JOBS:
		if sim._staffed(jb):
			continue
		var at = sim._work_at(jb)
		if at != null:
			sim._add_stuck(Defs.JOB_NAMES[jb], "No one is %s %s" % ["an" if Defs.JOB_SKILLED[jb][0] in "aeiou" else "a", Defs.JOB_SKILLED[jb]], Vector2(at) + Vector2(0.5, 0.5), 0.8, "", 0)


## What holds up a chopping block or mason's bench (issue #177), and a stonemason with no pickaxe.
## A target reached or a full pile is waiting, not stuck: the overflow goes to the stockpile.
## Farmers resting because the village has enough wheat: a waiting reason, not a stall (issue #269).
static func _stuck_farm(sim: Sim) -> void:
	if sim.map_id != "village" or sim.m.farm.is_empty() or not sim.wheat_enough():
		return
	var plot: Dictionary = sim.m.farm.values()[0]
	if sim.m.farm.values().any(func(k): return k.claim == 0 and (sim.crop_ripe(k) or k.grow < 0.0)):
		sim._add_stuck("Farm", "enough wheat (%d)" % sim.wheat_keep, Vector2(plot.cell) + Vector2(0.5, 0.5), 0.8, "", 0, false, true)


static func _stuck_workstations(sim: Sim) -> void:
	var ws := sim.enchanting_workshop()  # a book nobody is about to carry (issue #165)
	if not ws.is_empty() and not sim._staffed("enchant"):
		for b in sim.learnable_books():
			sim._add_stuck("Book", "waiting to be carried to the workshop", Vector2(b.cell) + Vector2(0.5, 0.5), 0.6, "", 0, false, true)
			break
	if not ws.is_empty() and sim.map_id == "village":  # an order short of something (issue #166)
		var miss := sim.enchant_missing(ws)
		for k in miss:
			var item: Dictionary = Defs.ITEMS[k]
			sim._add_stuck("Enchant", "needs %s" % Defs.words(k, miss[k]), Vector2(ws.origin) + Vector2(0.5, 0.5), 1.4, "site", ws.id)
			break
	for s in sim.m.sites:
		var wk := sim.work_of(s)
		if not s.done or wk.is_empty():
			continue
		var tname: String = sim.station_name(s)
		var at := Vector2(s.origin) + Vector2(0.5, 0.5)
		var h := sim.site_height(s) + 0.4
		var item: Dictionary = Defs.ITEMS[wk.item]
		if s.get("worker", 0) == 0:
			sim._add_stuck(tname, "No %s to work it" % Defs.JOB_SKILLED[wk.job], at, h, "site", s.id, false, true)
		elif sim.free_count(wk.item) >= s.keep:
			sim._add_stuck(tname, "Target reached (%d %s)" % [s.keep, item.many], at, h, "site", s.id, false, true)
		else:
			var pool: Array = sim.m.trees if wk.kind == "tree" else sim.m.boulders
			var left := pool.filter(func(t): return t.alive and not t.get("hidden", false) and sim.in_area(s, t.cell) and not sim.protected(t))
			if not s.get("shaft", false):  # a mineshaft digs where it stands: nothing needs to be in its area (issue #204)
				if left.is_empty():
					var why := "No trees in the chopping block's area. Plant saplings, or paint more ground" if wk.kind == "tree" else "No boulders in the mason's bench's area"
					sim._add_stuck(tname, why, at, h, "site", s.id)
				elif not left.any(func(t): return sim.grown(t)):
					sim._add_stuck(tname, "Saplings growing: no grown trees in its area yet", at, h, "site", s.id, false, true)
		if sim.pile_count(s) >= Tuning.WORK_STORE:
			sim._add_stuck(tname, "Full (%d %s)" % [Tuning.WORK_STORE, item.many], at, h, "site", s.id, false, true)
	var any_pick := not sim.tool_items("pick", 0).is_empty()
	for r in sim.here():
		if r.role == "mason" and r.pick == null and not any_pick and not r.broken.pick:
			sim._add_stuck(r.name, "Stonemason: no pickaxe", r.pos + Vector2(0.5, 0.5), 1.6, "res", r.id)
		if r.role == "hunt" and sim.m.kind == "village" and not sim.claimed(r).is_empty() and sim.auto_prey().is_empty() and not sim.m.sheep.any(func(a): return a.alive and a.des):
			var herds := sim.free_herds()
			var left: Array = []
			for sp in herds:
				left.append("%d %s" % [herds[sp], Defs.SPECIES[sp].one if herds[sp] == 1 else Defs.SPECIES[sp].many])
			sim._add_stuck(r.name, "Hunter: herd at its floor (%s)" % ", ".join(left) if not left.is_empty() else "Hunter: no animals to hunt", r.pos + Vector2(0.5, 0.5), 1.6, "res", r.id, false, true)
		if sim.needs_station(r) and sim.m.kind == "village":  # issue #184: they haul till there's one
			sim._add_stuck(r.name, "Build a %s to start work" % Defs.TEMPLATES[Defs.JOB_STATIONS[r.role]].name.to_lower(), r.pos + Vector2(0.5, 0.5), 1.6, "res", r.id)


## Whether someone sees to a job's work: a resident whose job it is (or anyone, for hauling), or Ada
## while she's about the village or the road, well and not packing. Builders and haulers walk out from
## the village to work the road, so village residents count there too.
static func _staffed(sim: Sim, jb: String) -> bool:
	for r in sim.residents:
		if r.role == jb:
			return true
		var about: bool = not r.away and sim.maps[r.map].kind != "site"
		if about and jb == "haul":
			return true
		if about and r.role == "all" and not sim.resting(r) and not sim.in_staging_party(r):
			return true
	return false


## A cell where work of this job is waiting, or null when there's none.
static func _work_at(sim: Sim, jb: String):
	match jb:
		"lumber", "mason":
			for o in (sim.m.trees if jb == "lumber" else sim.m.boulders):
				if o.alive and o.des:
					return o.cell
		"hunt":
			for sh in sim.m.sheep:
				if sh.alive and sh.des:
					return sh.cell
		"farm":
			var crop = sim._farm_work(Vector2i.ZERO)
			if crop != null:
				return crop.cell
		"build":
			for st in sim.m.sites:
				if not st.done or (st.tpl == "portal" and not st.lit):  # a finished frame still wants lighting (issue #147)
					return st.origin
		"enchant":  # a book to learn, or an order (issues #165, #166)
			var ew := sim.enchanting_workshop()
			if not ew.is_empty() and (not sim.learnable_books().is_empty() or not ew.orders.is_empty()):
				return ew.origin
		"haul":
			if not sim.m.zone.is_empty():
				var hs = sim._haul_source(Vector2i.ZERO)
				if hs != null:
					return hs.stack.cell
		_:
			for st in sim.m.sites:
				if st.done and sim.is_station(st) and st.queue.any(func(id): return sim.recipe_job(Defs.recipe(id)) == jb):
					return st.origin
	return null


static func site_height(sim: Sim, s: Dictionary) -> float:
	if s.tpl == "enchanting_workshop":
		return 1.1 if s.done else 0.2
	if s.tpl == "bench":
		return 0.75 if s.done else 0.2
	if s.tpl == "fireplace":
		return 0.7 if s.done else 0.2
	if s.tpl == "board":
		return 1.5 if s.done else 0.2
	if s.tpl == "portal":
		return 2.4 if s.done else 0.2
	if s.tpl == "chopping_block":
		return 0.55 if s.done else 0.2
	if s.tpl == "mason_bench":
		return 0.8 if s.done else 0.2
	if s.tpl in ["toolsmith_bench", "composter", "lodge", "builder_table"]:
		return 0.9 if s.done else 0.2
	if sim.is_device(s):
		return 0.5 if s.done else 0.2
	if s.tpl in ["bridge", "track", "station", "portal_station"]:
		return 0.2 if not s.tpl.ends_with("station") or not s.done else 0.9
	return [0.2, 0.5, 2.5, 4.0, 4.0][mini(s.stage, 4)]
