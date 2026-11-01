class_name PartyWork
extends RefCounted
## the party at the site (issue #109), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## Whether a party member is at the site, working it (not on their way home).
static func at_site(sim: Sim, r: Dictionary) -> bool:
	return sim.expedition.get("state", "") == "out" and sim.expedition.get("leg", "out") == "out" and sim.expedition.party.has(r.id) and r.map == sim.expedition.dest and not r.away


## The packs: what's in them, against what they hold. Meals and spare pickaxes count, as does cargo.
static func pack_load(sim: Sim) -> int:
	var n: int = sim.expedition.get("tools", []).size()
	for src in [sim.expedition.get("provisions", {}), sim.expedition.get("cargo", {}), sim.expedition.get("supplies", {})]:
		for k in src:
			n += src[k]
	return n


static func pack_room(sim: Sim) -> int:
	return Sim.pack_capacity(sim.expedition) - pack_load(sim)


## Room in the packs not yet promised to someone on their way to pack something.
static func _room_to_promise(sim: Sim) -> int:
	var n := pack_room(sim)
	for r in sim.residents:
		if r.job != null and r.job.kind == "stow":
			n -= r.job.steps[-1].n
	return n


## Meals in the packs the party may eat: all of them if the plan spends the return food, else what's
## left above it.
static func spendable_meals(sim: Sim) -> int:
	return _pack_spendable(sim) + (cache_meals(sim) if sim.m.id == NetherLanding.ID else 0)  # the landing's cache feeds the party (issue #152)


## Meals in the packs alone that may be eaten.
static func _pack_spendable(sim: Sim) -> int:
	var n := 0
	for k in sim.expedition.get("provisions", {}):
		n += sim.expedition.provisions[k]
	return n if sim.expedition.get("spend_return", false) else maxi(0, n - Sim.return_meals(sim.expedition))


## How much of the objective's resource is in the packs.
static func objective_packed(sim: Sim) -> int:
	return sim.expedition.get("cargo", {}).get(sim.expedition.target.item, 0)


## Items a block of this resource gives when mined, or an animal when it's hunted (issue #138).
static func block_yield(item: String) -> int:
	for sp in Tuning.ANIMAL_DROPS:
		if Tuning.ANIMAL_DROPS[sp].has(item):
			return Tuning.ANIMAL_DROPS[sp][item]
	return {"cobble": Tuning.BOULDER_COBBLE, "coal": Tuning.ORE_YIELD.coal, "iron_ore": Tuning.ORE_YIELD.iron, "diamond": Tuning.ORE_YIELD.diamond,
		"gold_ore": Tuning.ORE_YIELD.gold, "obsidian": Tuning.ORE_YIELD.obsidian, "lapis": Tuning.ORE_YIELD.lapis, "redstone": Tuning.ORE_YIELD.redstone, "quartz": Tuning.ORE_YIELD.quartz, "glowstone": Tuning.ORE_YIELD.glowstone}.get(item, 1)


## Whether a block gives the objective's resource (stone, coal or iron ore), or an animal does when
## it's hunted (wool, leather or meat).
static func gives(b: Dictionary, item: String) -> bool:
	if b.get("kind", "") == "animal":  # the young can't be hunted, nor can one being led to a sim.pen (issue #139)
		return Tuning.ANIMAL_DROPS[b.species].has(item) and not b.get("young", false) and not b.get("lead", false)
	match item:
		"cobble": return not b.has("ore")
		"coal": return b.get("ore", "") == "coal"
		"iron_ore": return b.get("ore", "") == "iron"
		"diamond": return b.get("ore", "") == "diamond"
		"gold_ore": return b.get("ore", "") == "gold"
		"obsidian": return b.get("ore", "") == "obsidian"
		"flint": return b.get("ore", "") == "gravel"
		"book_efficiency", "book_unbreaking", "book_protection", "book_fire_protection": return b.get("ore", "") == "chest" and b.get("book", "") == item
		"lapis": return b.get("ore", "") == "lapis"
		"redstone": return b.get("ore", "") == "redstone"
		"quartz": return b.get("ore", "") == "quartz"
		"glowstone": return b.get("ore", "") == "glowstone"
	return false


## Eating at the site: a meal from the packs, keeping the return food unless it may be spent.
static func _ration_job(sim: Sim, r: Dictionary):
	if spendable_meals(sim) <= 0:
		return null
	var j := Job.new("eat", "Going to eat from the packs", "the packs")
	if _pack_spendable(sim) <= 0 and sim.m.id == NetherLanding.ID:  # the cache has them (issue #152)
		j.label = "Taking a meal from the cache"
		j.step(sim._goto(sim.site_cells(shelter_site(sim)), true))
		j.step({"op": "cache_take"})
	elif not sim.on_road(r):  # on the sim.road, they carry the packs
		j.step(sim._goto([sim.m.entrance], false))
	j.step({"op": "ration"})
	j.step({"op": "work", "what": "eat", "label": "Eating from the packs"})
	return j


## What a party member does at the site, by its orders and without the player: take a spare pickaxe
## from the packs if theirs broke, investigate the vein if that's been chosen, mine what's marked,
## and carry what's mined into the packs. The seriously hurt wait at the entrance.
static func _site_job(sim: Sim, r: Dictionary):
	var c := Sim.rcell(r)
	if sim.m.id == NetherLanding.ID and r.get("hurt", 0) > 0 and shelter_site(sim).get("done", false):  # the fallback: slower than a bed (issue #152)
		var rj := Job.new("rest", "Resting at the shelter", "the shelter")
		rj.step(sim._goto(sim.site_cells(shelter_site(sim)), true))
		rj.step({"op": "rest", "bed": false})
		return rj
	if r.get("hurt", 0) >= 2:
		var w := Job.new("hurt", "Waiting at the entrance, seriously hurt", "the entrance")
		w.step(sim._goto([sim.m.entrance], false))
		w.step({"op": "rest_site"})
		return w
	var fj = sim._fight_job(r, c)  # a guard fights what threatens the party (issue #151)
	if fj != null:
		return fj
	if sim.expedition.get("rescue", false):  # a rescue party looks for the stranded (issue #158)
		return sim._rescue_job(r, c)
	if sim.m.id == Meadow.ID:
		return sim._meadow_job(r, c)
	if sim.m.id == NetherLanding.ID:
		return sim._landing_job(r, c)
	if sim.building_line() and sim.m.id == NetherRoute.ROUTES.quartz.site:  # the far sim.station and the sim.cart (issue #159)
		var st := sim.nline_task("site", r.id)
		if not st.is_empty():
			return sim._line_job(st, r.id)
	if sim.m.id == NetherRoute.ROUTES.piglin.site:
		return sim._camp_job(r, c)
	if sim.m.id == NetherRoute.ROUTES.fortress.site:
		return sim._delve_job(r, c)
	var can_mine: bool = r.get("hurt", 0) == 0
	if can_mine and r.pick == null and not sim.expedition.get("tools", []).is_empty():
		var t := Job.new("equip", "Taking a spare pickaxe from the packs", "the packs")
		t.step(sim._goto([sim.m.entrance], false))
		t.step({"op": "take_tool"})
		return t
	var pj = sim._stow_job(r, c)
	if pj != null and (not can_mine or r.pick == null or sim._priority_stack(pj.target) or pack_load(sim) + 4 >= Sim.pack_capacity(sim.expedition)):
		return pj
	if can_mine and r.pick != null and sim.expedition.get("survey", false) and not sim.residents.any(func(o): return o.job != null and o.job.kind == "survey"):
		var sj = sim._survey_job(r)
		if sj != null:
			sim._drop_unused(r, pj)
			return sj
	if sim.m.door_state == "closed" and sim.walkable(MineLevels.door_front(sim.m)) and (not sim.expedition.get("clear", false) or sim._nothing_left()) and not sim.residents.any(func(o): return o.job != null and o.job.kind == "door"):
		var dj := Job.new("door", "Going to the door", "the door")  # the way is open: someone goes to look (issue #132)
		dj.step(sim._goto([sim.m.door], true))
		dj.step({"op": "at_door"})
		if sim.find_path(c, sim.adj_set([sim.m.door])) != null:
			sim._drop_unused(r, pj)
			return dj
	if can_mine:  # glowstone breaks by hand, so no pickaxe is needed for it (issue #155)
		var targets := sim.m.boulders.filter(func(b): return b.alive and b.des and b.claim == 0 and not sim._cooling(b) and (r.pick != null or b.get("ore", "") == "glowstone"))
		if not targets.is_empty():
			sim._drop_unused(r, pj)
			return sim._gather_job(r, Sim.nearest(targets, c))
	return pj


## The landing's shelter site, or {} (issue #152).
static func shelter_site(sim: Sim) -> Dictionary:
	for s in sim.maps[NetherLanding.ID].sites:
		if s.tpl == "shelter":
			return s
	return {}


## Meals in the shelter's cache.
static func cache_meals(sim: Sim) -> int:
	var n := 0
	var sh := shelter_site(sim)
	for k in sh.get("store", {}):
		if Defs.MEALS.has(k):
			n += sh.store[k]
	return n


## Whether the party's packs hold what a cost asks for.
static func _supplies_cover(sim: Sim, cost: Dictionary) -> bool:
	var sup: Dictionary = sim.expedition.get("supplies", {})
	for k in cost:
		if sup.get(k, 0) < cost[k]:
			return false
	return true


## The route key ("quartz"...) a Nether destination is on: a site's, or a route's own.
static func dest_route(dest: String) -> String:
	var k := NetherRoute.site_key(dest)
	return k if k != "" else NetherRoute.route_of(dest)


## A party member on the way across the Nether (issue #155): the landing is the hub. Out to a site they cross the landing to its route,
## walk the route east and step onto the site; home they come back the same way, then through the portal. A creature that
## threatens them is dealt with first.
static func _nether_transit_job(sim: Sim, r: Dictionary) -> Job:
	var c := Sim.rcell(r)
	var fj = sim._fight_job(r, c)
	if fj != null:
		return fj
	var home: bool = sim.expedition.get("leg", "out") == "home"
	if sim.map_id == NetherLanding.ID:
		if home or dest_route(sim.expedition.get("dest", "")) == "":
			return _portal_home_job(sim)
		if sim.building_line():  # the landing's sim.station before setting out (issue #159)
			var lt := sim.nline_task("landing", r.id)
			if not lt.is_empty():
				return sim._line_job(lt, r.id)
		var rk := dest_route(sim.expedition.dest)
		var ej := Job.new("road", "Setting out for the %s" % sim.maps[sim.expedition.dest].name.substr(8).to_lower(), "the way out")
		ej.step(sim._goto([NetherRoute.ROUTES[rk].exit], true))
		ej.step({"op": "enter_route", "route": rk})
		return ej
	if sim.m.kind == "route":
		if sim.scouting() and not home and not sim.m.surveyed and r.get("hurt", 0) < 2:
			return _route_scout_job(sim, r)
		if home or r.get("hurt", 0) >= 2 or sim.m.surveyed and sim.scouting():
			var hj := Job.new("road", "Heading back to the landing", "the landing")
			hj.step(sim._goto([sim.m.entrance], false))
			hj.step({"op": "leave_route"})
			return hj
		if sim.building_line() and sim.map_id == NetherRoute.ROUTES.quartz.id:  # bridges and track on the way east (issue #159)
			var rt := sim.nline_task("route", r.id)
			if not rt.is_empty():
				return sim._line_job(rt, r.id)
		var oj := Job.new("road", "%s the route to the %s" % ["Riding" if sim.nline_complete() and sim.map_id == NetherRoute.ROUTES.quartz.id else "Walking", sim.maps[sim.expedition.dest].name.substr(8).to_lower()], "the far end")
		oj.step(sim._goto([Vector2i(NetherRoute.W - 1, NetherRoute.LINE_ROW)], false))
		oj.step({"op": "to_site"})
		return oj
	var sj := Job.new("road", "Heading back along the route", "the route")  # a sim.site, on the way home
	sj.step(sim._goto([sim.m.entrance], false))
	sj.step({"op": "leave_site"})
	return sj


## Back through the portal: to its far side, relighting it first if it's gone out (issue #148).
static func _portal_home_job(sim: Sim) -> Job:
	var h := Job.new("road", "Heading for the portal", "the portal")
	h.step(sim._goto([sim.m.entrance], false))
	if not sim.portal_lit():
		if sim.expedition.get("lighter", {}).is_empty():
			h.step({"op": "wait_portal"})
		else:
			h.step({"op": "work", "what": "relight", "label": "Relighting the portal"})
	h.step({"op": "depart", "to": "village"})
	return h


## A scout on a route (issue #153): walk east, segment by segment, to its end, then come back. A creature that threatens
## them is dealt with first, and a seriously hurt scout turns back.
static func _route_scout_job(sim: Sim, r: Dictionary) -> Job:
	var c := Sim.rcell(r)
	var fj = sim._fight_job(r, c)
	if fj != null:
		return fj
	if sim.expedition.get("leg", "out") == "home" or sim.m.surveyed or r.get("hurt", 0) >= 2:
		var hj := Job.new("road", "Heading back to the landing", "the landing")
		hj.step(sim._goto([sim.m.entrance], false))
		hj.step({"op": "leave_route"})
		return hj
	var idx: int = sim.m.seen
	var j := Job.new("scout", "Scouting the route", "the way ahead")
	if idx < Road.segment_count():
		j.step(sim._goto([Vector2i(Road.SEGMENTS[idx].x, NetherRoute.LINE_ROW)], true))
		j.step({"op": "reach_segment", "idx": idx})
	else:
		j.step(sim._goto([Vector2i(NetherRoute.W - 1, NetherRoute.LINE_ROW)], true))
		j.step({"op": "route_end"})
	return j
