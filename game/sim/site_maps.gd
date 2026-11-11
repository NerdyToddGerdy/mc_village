class_name SiteMaps
extends RefCounted
## Split out of sim.gd (#305). Every function takes the Sim it works on; Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## "Boulder", "Coal ore" or "Iron ore".
static func block_name(b: Dictionary) -> String:
	return Defs.ORES[b.ore].name if b.has("ore") else "Boulder"


## Ore blocks of this kind left on a site map, counting hidden ones only once they're found.
static func ore_left(sim: Sim, id: String, ore: String) -> int:
	var mp: SimMap = sim.maps[id]
	return mp.boulders.filter(func(b): return b.alive and b.get("ore", "") == ore and (mp.discovered or not b.get("hidden", false)) and not (ore == "diamond" and b.get("hidden", false))).size()


## The site report (brief §8) the expedition board shows before departure:
##   {name, told, visited, travel (seconds), resources: [{item, name, reserve, known}], hazards, access, finds}
## A reserve is the estimated items still to be mined, or -1 for "?". Before anyone has been there,
## the report has only what the village has been told: names, no estimates and no known hazards.
## The iron shows as "?" until it's found, and has no estimate until it's surveyed (issue #111).
static func site_report(sim: Sim, id: String) -> Dictionary:
	if NetherRoute.site_key(id) != "" and sim.maps[id].pattern != "":  # a built site (issues #155-#157)
		return sim._nether_site_report(id)
	if NetherRoute.route_of(id) != "" or NetherRoute.site_key(id) != "":
		return sim._nether_route_report(id)
	if id == Meadow.ID:
		return sim._meadow_report()
	if id == NetherLanding.ID:
		return sim._landing_report()
	var mp: SimMap = sim.maps[id]
	var stone := mp.boulders.filter(func(b): return b.alive and not b.has("ore")).size()
	var res: Array = [
		{"item": "cobble", "name": "Stone", "reserve": stone * Tuning.BOULDER_COBBLE if mp.visited else -1},
		{"item": "coal", "name": "Coal", "reserve": sim.ore_left(id, "coal") * Tuning.ORE_YIELD.coal if mp.visited else -1},
	]
	for x in res:
		x.known = true
	if mp.discovered:
		res.append({"item": "iron_ore", "name": "Iron", "reserve": sim.ore_left(id, "iron") * Tuning.ORE_YIELD.iron, "known": true})
	elif mp.found:
		res.append({"item": "iron_ore", "name": "Iron", "reserve": -1, "known": false})
	elif mp.visited:
		res.append({"item": "iron_ore", "name": "?", "reserve": -1, "known": false})
	if mp.diamond_found:  # a known resource of this level once someone has found it (issue #186)
		res.append({"item": "diamond", "name": "Diamond", "reserve": sim.ore_left(id, "diamond") * Tuning.ORE_YIELD.diamond, "known": true})
	if mp.visited:  # a chest in the rock holds a book (issue #164)
		var books := {}
		for b in mp.boulders:
			if b.alive and b.get("ore", "") == "chest":
				books[b.book] = books.get(b.book, 0) + 1
		for k in books:
			res.append({"item": k, "name": Defs.ITEMS[k].label, "reserve": books[k], "known": true})
	for ore in ["gold", "obsidian", "gravel", "lapis", "redstone"]:  # what the deeper levels hold once someone has seen them (issues #146, #163)
		if mp.visited and mp.boulders.any(func(b): return b.get("ore", "") == ore):
			res.append({"item": Defs.ORES[ore].item, "name": {"gold": "Gold", "obsidian": "Obsidian", "gravel": "Flint", "lapis": "Lapis", "redstone": "Redstone"}[ore],
				"reserve": sim.ore_left(id, ore) * Tuning.ORE_YIELD[ore], "known": true})
	var hazards: Array = []
	if mp.visited and not mp.lava.is_empty():  # issue #149
		hazards.append("Lava pools in the rock: someone beside one can be burned")
	if mp.visited:
		var dark := 0
		for x in mp.w:
			for y in mp.h:
				if mp.is_dark(Vector2i(x, y)):
					dark += 1
		if dark > 0:
			hazards.append("Dark tunnels past the torches: work there is slower")
		var deeper := " (likelier this deep)" if mp.level > 1 else ""
		if mp.boulders.any(func(b): return b.alive and b.get("loose", false)):
			hazards.append("Loose ceilings: mining under one can bring it down" + deeper)
		if mp.ledges.size() == 1:
			hazards.append("A ledge in the dark: someone could fall" + deeper)
		elif mp.ledges.size() > 1:
			hazards.append("%d ledges in the dark: someone could fall%s" % [mp.ledges.size(), deeper])
	var finds: Array = []
	if mp.found and not mp.discovered:
		finds.append("Iron vein found, not surveyed")
	if mp.water.size() > 0 and mp.visited:
		hazards.append("An underground stream: the way goes around it")
	var told: String = OldMine.TOLD if mp.level <= 1 else "Behind the door at the far end of level %d. Nobody has been down." % (mp.level - 1)
	if mp.level > 1 and mp.level - 1 == 1:
		told = "Behind the door at the far end of the old caves. Nobody has been down."
	var levels: Array = []
	for lid in sim.mine_levels():  # every level known so far (issue #132)
		var lm: SimMap = sim.maps[lid]
		var left: int = lm.boulders.filter(func(b): return b.alive and b.has("ore") and (lm.discovered or not b.get("hidden", false)) and not (b.get("ore", "") == "diamond" and b.get("hidden", false))).size()
		var door: String = {"open": "door open", "found": "door found"}.get(lm.door_state, "door not reached")
		levels.append({"id": lid, "level": lm.level, "pattern": MineLevels.FAMILY_NAMES.get(lm.pattern, ""), "ore": left if lm.visited else -1, "door": door, "visited": lm.visited})
	var travel := sim.route_walk_time() + sim.level_walk(id) if sim.route_surveyed() else -1.0
	return {"name": mp.name, "told": told, "visited": mp.visited, "travel": travel, "level": mp.level, "pattern": MineLevels.FAMILY_NAMES.get(mp.pattern, ""),
		"biome": MineLevels.BIOMES[MineLevels.biome(mp.level)] if mp.level > 0 else "", "resources": res, "hazards": hazards, "access": (MineLevels.ACCESS.get(mp.pattern, []) + [MineLevels.BIOME_NOTES[MineLevels.biome(mp.level)]]) if mp.visited else [], "finds": finds,
		"levels": levels if mp.level > 0 else [], "door": mp.door_state}


## The meadow's site report (issue #137): what each herd would give if it were all hunted, the herds
## themselves, and its mild hazards.
static func _meadow_report(sim: Sim) -> Dictionary:
	var mp: SimMap = sim.maps[Meadow.ID]
	var res: Array = []
	for item in ["wool", "mutton", "leather", "beef", "porkchop"]:
		var n := 0
		for a in mp.sheep:
			if a.alive:
				n += Tuning.ANIMAL_DROPS[a.species].get(item, 0)
		res.append({"item": item, "name": Defs.ITEMS[item].label, "reserve": n if mp.visited else -1, "known": true})
	var hazards: Array = []
	if mp.visited:
		hazards = ["An angry bull: hunting a cow can get someone hurt", "A slippery pond bank: someone can slip and get hurt"]
	return {"name": mp.name, "told": Meadow.TOLD, "visited": mp.visited, "travel": MeadowRoad.walk_time(), "level": 0, "pattern": "",
		"resources": res, "hazards": hazards, "access": Meadow.ACCESS.duplicate() if mp.visited else [], "finds": [], "levels": [],
		"door": "", "herds": sim.herds() if mp.visited else {}}


## A Nether route's report, or that of the site at its end (issue #153): what's known of the terrain, the dangers and the
## travel, segment by segment as far as scouts have seen. The site's resources wait for the issues that build it.
static func _nether_route_report(sim: Sim, id: String) -> Dictionary:
	var rk := NetherRoute.route_of(id)
	var is_route := rk != ""
	if not is_route:
		rk = NetherRoute.site_key(id)
	var def: Dictionary = NetherRoute.ROUTES[rk]
	var rm: SimMap = sim.maps[def.id]
	var segs: Array = []
	var hazards: Array = []
	for i in def.segments.size():
		var sg: Dictionary = def.segments[i]
		var seen: bool = i < rm.seen
		segs.append({"name": sg.name if seen else "Not scouted", "terrain": sg.terrain if seen else "unknown", "obstacle": sg.obstacle if seen else "", "known": seen})
		if seen:
			for hz in sg.hazards:
				if not hazards.has(hz):
					hazards.append(hz)
	var kinds: Dictionary = {}
	for cr in rm.creatures:
		if cr.alive and rm.seen >= Road.segment_at(cr.cell.x) + 1:
			kinds[Defs.CREATURES[cr.species].name] = true
	for k in kinds:
		hazards.append("%s about" % k)
	var walk: float = Road.SEGMENTS.size() * 8.0 / Tuning.WALK
	var name: String = def.name if is_route else def.site_name
	var line_text := ""
	if rk == "quartz" and rm.surveyed:  # the Nether line's progress (issue #159)
		var ln := sim.nline()
		var laid := 0
		for n in ln.laid:
			laid += 1 if n >= Tuning.RAILS_PER_SEGMENT else 0
		line_text = "Line: %d of %d segments laid, %d of 2 bridges, %d of 2 stations, %s" % [laid, Road.BASE_SEGMENTS, ln.bridged.size(), (1 if ln.stations.landing else 0) + (1 if ln.stations.site else 0), "cart parked" if ln.cart else "no cart"]
	return {"name": name, "told": def.told, "line": line_text, "visited": rm.seen > 1 or rm.surveyed, "travel": walk if rm.surveyed else -1.0, "level": 0, "pattern": "",
		"resources": [], "hazards": hazards, "access": ["A narrow way beside the lava: bridges and cuts come with the line"] if rm.surveyed else [], "finds": [], "levels": [], "door": "",
		"segments": segs, "scouted": rm.surveyed, "seen": rm.seen}


## A built Nether site's report (issues #155-#157): what's there and how much is left, its dangers, the time to get there from
## the landing, and what the site has room for.
static func _nether_site_report(sim: Sim, id: String) -> Dictionary:
	var mp: SimMap = sim.maps[id]
	var rk := NetherRoute.site_key(id)
	var def: Dictionary = NetherRoute.ROUTES[rk]
	var res: Array = []
	for ore in ["quartz", "glowstone"]:
		if mp.boulders.any(func(b): return b.get("ore", "") == ore):
			res.append({"item": Defs.ORES[ore].item, "name": Defs.ITEMS[Defs.ORES[ore].item].label, "reserve": sim.ore_left(id, ore) * Tuning.ORE_YIELD[ore] if mp.visited else -1, "known": true})
	if sim.rk_of_site(id) == "fortress":  # what the halls give, known from the start (issue #157)
		for k in ["blaze_rod", "bone"]:
			res.append({"item": k, "name": Defs.ITEMS[k].label, "reserve": -1, "known": true})
	for k in mp.drops_known:
		if not res.any(func(x): return x.item == k):
			res.append({"item": k, "name": Defs.ITEMS[k].label, "reserve": -1, "known": true})
	var hazards: Array = []
	if mp.visited and not mp.lava.is_empty():
		hazards.append("Lava pools in the rock: someone beside one can be burned")
	var walk: float = (Road.SEGMENTS.size() * 8.0 + NetherLanding.LAYOUT[0].length() / 2.0) / Tuning.WALK
	var out := {"name": def.site_name, "told": def.told, "visited": mp.visited, "travel": walk, "level": 0, "pattern": "", "resources": res, "hazards": hazards,
		"access": [sim.rk_access(rk)] if mp.visited else [], "finds": [], "levels": [], "door": ""}
	if rk == "fortress":  # issue #157
		if mp.visited:
			out.hazards.append("Blazes and skeletons in the halls")
			out.hazards.append("A sealed way leads deeper: a later expedition")
		out.salvage = "A salvage chest at the far end" if not mp.salvage_taken else "The salvage has been taken"
	if rk == "piglin":  # the table and the rule are shown before a party commits (issue #156)
		out.trades = Defs.TRADES.map(func(t): return Defs.trade_text(t))
		out.rule = Defs.PIGLIN_RULE
		out.hostile = mp.hostile
		if mp.hostile:
			out.hazards.append("The piglins are hostile")
	return out


static func rk_of_site(id: String) -> String:
	return NetherRoute.site_key(id)


## What a site has room for, by its route.
static func rk_access(rk: String) -> String:
	return {"quartz": "Room beside the far wall for the Nether line's station", "fortress": "Halls, narrow in places"}.get(rk, "Room for the party")


## The portal landing's report (issue #148): nothing to bring back yet, a survey to make, and what's known of its dangers.
static func _landing_report(sim: Sim) -> Dictionary:
	var mp: SimMap = sim.maps[NetherLanding.ID]
	var routes: Array = []
	for rk in NetherRoute.ROUTES:
		var rmap: SimMap = sim.maps[NetherRoute.ROUTES[rk].id]
		routes.append({"key": rk, "name": NetherRoute.ROUTES[rk].name.substr(8), "state": "scouted" if rmap.surveyed else ("partly scouted" if rmap.seen > 1 else "unknown"), "told": NetherRoute.ROUTES[rk].told})
	var shelter := sim.shelter_site()
	var cache := ""
	if shelter.get("done", false):
		cache = "Shelter built. Cache: %s" % ("empty" if sim.cache_meals() == 0 else "%d %s" % [sim.cache_meals(), "meal" if sim.cache_meals() == 1 else "meals"])
	return {"name": mp.name, "told": NetherLanding.TOLD, "visited": mp.visited, "travel": 0.0, "level": 0, "pattern": "", "cache": cache, "routes": routes,
		"resources": mp.drops_known.map(func(k): return {"item": k, "name": Defs.ITEMS[k].label, "reserve": -1, "known": true}),
		"hazards": NetherLanding.HAZARDS.duplicate() if mp.visited else [], "access": NetherLanding.ACCESS.duplicate() if mp.visited else [],
		"finds": [], "levels": [], "door": "", "landmarks": mp.landmarks_seen.size(), "landmark_total": mp.landmarks.size()}
