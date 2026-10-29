class_name SaveFormat
extends RefCounted
## Reading, writing and upgrading save files.
##
## A save file is one `var_to_str` Dictionary:
##   {v, summary, tick, saved_at, state: Sim.save_state(), camera, speed}
## `v` is the save format version for the whole file.
##
## When the shape of saved data changes:
## 1. Bump VERSION.
## 2. Add an entry to upgrades() that turns a save of the previous version into the new shape.
## 3. Add tests/fixtures/save_v<N>.save (made with tests/fixtures/make_save_fixture.gd) and a test
##    that loads it, alongside the older fixtures, which must keep loading.

const VERSION := 49

## Version N -> the step that upgrades a version-N save to version N + 1. Each step takes the
## whole save Dictionary and returns it upgraded. Steps never need to set `v`; upgrade() does.
static func upgrades() -> Dictionary:
	return {1: _v1_to_v2, 2: _v2_to_v3, 3: _v3_to_v4, 4: _v4_to_v5, 5: _v5_to_v6, 6: _v6_to_v7, 7: _v7_to_v8, 8: _v8_to_v9, 9: _v9_to_v10, 10: _v10_to_v11, 11: _v11_to_v12, 12: _v12_to_v13, 13: _v13_to_v14, 14: _v14_to_v15, 15: _v15_to_v16, 16: _v16_to_v17, 17: _v17_to_v18, 18: _v18_to_v19, 19: _v19_to_v20, 20: _v20_to_v21, 21: _v21_to_v22, 22: _v22_to_v23, 23: _v23_to_v24, 24: _v24_to_v25, 25: _v25_to_v26, 26: _v26_to_v27, 27: _v27_to_v28, 28: _v28_to_v29, 29: _v29_to_v30, 30: _v30_to_v31, 31: _v31_to_v32, 32: _v32_to_v33, 33: _v33_to_v34, 34: _v34_to_v35, 35: _v35_to_v36, 36: _v36_to_v37, 37: _v37_to_v38, 38: _v38_to_v39, 39: _v39_to_v40, 40: _v40_to_v41, 41: _v41_to_v42, 42: _v42_to_v43, 43: _v43_to_v44, 44: _v44_to_v45, 45: _v45_to_v46, 46: _v46_to_v47, 47: _v47_to_v48, 48: _v48_to_v49}


## v49: the Nether line (issue #159). The quartz route map keeps its `line`: the rails laid in each segment, the bridges, the
## two stations and the cart, none in any older save. A trip carries `rails` and `minecarts` among its supplies.
static func _v48_to_v49(d: Dictionary) -> Dictionary:
	return d


## v48: stranding and rescue (issue #158). A third expedition slot, `rescue`, empty in every older save; a trip may carry `stranded`
## (why, where, the rescue window's end) and what it `abandoned`; a map keeps the cargo abandoned on it.
static func _v47_to_v48(d: Dictionary) -> Dictionary:
	var ex: Dictionary = d.state.get("expeditions", {})
	if not ex.has("rescue"):
		ex.rescue = {}
	return d


## v47: the fortress (issue #157). A save's empty room at the end of the fortress route becomes the hand-laid fortress when the
## game loads it, with its blazes and skeletons; it keeps `salvage_taken`, its creatures and what they've dropped.
static func _v46_to_v47(d: Dictionary) -> Dictionary:
	return d


## v46: the piglin camp (issue #156). A save's empty room at the end of the piglin route becomes the camp when the game loads
## it, with its piglins; a camp keeps `hostile`. A trip carries `gold` in its supplies, and what it `traded`.
static func _v45_to_v46(d: Dictionary) -> Dictionary:
	return d


## v45: the quartz site (issue #155). A save's empty room at the end of the quartz route becomes the hand-laid site when the
## game loads it (its `known` kept); the site keeps its mined-out blocks, and `visited`.
static func _v44_to_v45(d: Dictionary) -> Dictionary:
	return d


## v44: the Nether routes (issue #153). Three route strip maps and the three site maps at their ends are added to a save when
## it loads, unknown; a route keeps `seen` (the segments scouted) and `surveyed` (all of it), and its site `known`.
static func _v43_to_v44(d: Dictionary) -> Dictionary:
	return d


## v43: the shelter and supply cache on the Nether landing (issue #152). A landing's `sites` may hold the shelter, with its
## cache in the site's store; a trip carries `shelter`, `cobble`, `planks` and `stock`, none for every older trip.
static func _v42_to_v43(d: Dictionary) -> Dictionary:
	return d


## v42: creatures on the Nether's maps (issue #151). A map keeps its `creatures` (with their health) and `drops_known`;
## a plan carries `fight`, false for every older trip, which avoids combat.
static func _v41_to_v42(d: Dictionary) -> Dictionary:
	for sl in d.state.get("expeditions", {}):
		var ex: Dictionary = d.state.expeditions[sl]
		if not ex.is_empty():
			ex.fight = false
	return d


## v41: the Guard job and iron swords (issue #150). Every resident gets a sword slot (empty), and Guard at no experience.
static func _v40_to_v41(d: Dictionary) -> Dictionary:
	for r in d.state.get("residents", []):
		r.sword = null
		r.get("broken", {}).sword = false
		r.get("kept", {}).sword = false
		if not r.get("jobs", {}).has("guard"):
			r.get("jobs", {}).guard = {"xp": 0}
	return d


## v40: the Nether portal landing (issue #148). A save gets the landing map when it loads, unknown until a portal is lit;
## a pending choice and an expedition are unchanged. The landing keeps `landmarks`, `landmarks_seen` and `surveyed`.
static func _v39_to_v40(d: Dictionary) -> Dictionary:
	return d


## v39: the Nether portal (issue #147). A site of kind "portal" keeps `lit`; a village without one is as it was, and the
## Build menu offers the portal once obsidian has come home (`stats.obsidian_home`).
static func _v38_to_v39(d: Dictionary) -> Dictionary:
	return d


## v38: gold, gravel and flint, and obsidian beside lava pools on the deeper levels (issue #146). A level map keeps its
## `lava` cells, none until a level with a pool is made; levels already generated in an older save keep the layout they
## had, and every level made from now on holds the new materials.
static func _v37_to_v38(d: Dictionary) -> Dictionary:
	return d


## v37: two expeditions at once (issue #145). The one expedition becomes the Overworld's slot, and the Nether's is empty.
## An older pending choice belongs to the Overworld's.
static func _v36_to_v37(d: Dictionary) -> Dictionary:
	var ex: Dictionary = d.state.get("expedition", {})
	d.state.erase("expedition")
	d.state.expeditions = {"overworld": ex, "nether": {}}
	for p in d.state.get("pending", []):
		p.slot = "overworld"
	return d


## v36: diamonds on the deep levels (issue #186). A level map keeps `diamond_found`, false until someone finds the
## diamonds there; levels already generated in an older save keep the layout they had, with none, and every level
## made from now on has its own.
static func _v35_to_v36(d: Dictionary) -> Dictionary:
	return d


## v35: a trip can be to clear the level (issue #188). A plan, and so a trip in progress, carries `clear`; every
## older one is for what its list asks for, as before.
static func _v34_to_v35(d: Dictionary) -> Dictionary:
	var ex: Dictionary = d.state.get("expedition", {})
	if not ex.is_empty():
		ex.clear = false
	return d


## v34: a cargo priority list for an expedition (issue #185). A trip in progress has its old single target turned
## into a one-row list, with the other things its place gives at "As much as fits"; each place starts with no
## remembered list, so its next plan starts from the defaults.
static func _v33_to_v34(d: Dictionary) -> Dictionary:
	var st: Dictionary = d.state
	st.cargo_lists = {}
	var ex: Dictionary = st.get("expedition", {})
	if not ex.is_empty() and not ex.has("list") and ex.has("target") and ex.target.item != "pens":
		var item: String = ex.target.item
		var rows: Array = [{"item": item, "on": true, "n": ex.target.n}]
		var others: Array = ["wool", "mutton", "leather", "beef", "porkchop"] if ex.get("dest", "") == "meadow" else ["iron_ore", "coal", "cobble"]
		for o in others:
			if o != item:
				rows.append({"item": o, "on": true, "n": 0})
		ex.list = rows
	return d


## v33: a mason's bench can be dug out into a mineshaft (issue #204). A site may carry `upgrading` while
## it's rebuilt and `shaft` once it is; neither exists yet, so nothing in an older save changes.
static func _v32_to_v33(d: Dictionary) -> Dictionary:
	return d


## v32: a workstation's work area is painted (issue #203). Every standing chopping block and mason's
## bench gets the circle it always worked, so nothing changes for an old village. Where two of a kind
## overlapped, the older one keeps the shared cells.
static func _v31_to_v32(d: Dictionary) -> Dictionary:
	var sites: Array = d.state.maps.village.sites
	var w: int = d.state.maps.village.w
	var h: int = d.state.maps.village.h
	var owned := {}
	for s in sites:
		if s.tpl not in ["chopping_block", "mason_bench"]:
			continue
		var area := {}
		var rr := 8
		for dx in range(-rr, rr + 1):
			for dy in range(-rr, rr + 1):
				var c: Vector2i = s.origin + Vector2i(dx, dy)
				if c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and Vector2(c).distance_to(Vector2(s.origin)) <= 8.0 and not owned.has([s.tpl, c]):
					area[c] = true
					owned[[s.tpl, c]] = true
		s.area = area
	return d


## v31: worn paths (issue #196). The village map keeps how worn each cell is. An old village starts with
## no wear, grass everywhere, and its paths form as it's played.
static func _v30_to_v31(d: Dictionary) -> Dictionary:
	d.state.maps.village.wear = {}
	return d


## v30: the village chapter of the founding book (issue #198) counts meals cooked and iron ore brought
## home. An old village isn't asked to do what it already has: any cook's experience or meal on hand
## means a meal was cooked, and iron ore or ingots in the village mean ore came home.
static func _v29_to_v30(d: Dictionary) -> Dictionary:
	var st: Dictionary = d.state
	var meals := 0
	for r in st.residents:
		if r.jobs.get("cook", {}).get("xp", 0) > 0:
			meals = 1
	var ore := false
	for id in st.maps:
		for it in st.maps[id].items.values():
			if it.type in ["bread", "cooked_mutton", "cooked_beef", "cooked_porkchop"]:
				meals = 1
			if id == "village" and it.type in ["iron_ore", "iron_ingot"]:
				ore = true
	st.stats.meals_cooked = meals
	st.stats.ore_home = ore
	return d


## v29: land claims (issue #187). The village can grow by strips at its edges: the map's size is
## already saved with it, and what a claim has made lies in its own lists. Claims available are
## worked out from the residents, so an older save keeps its size, with none made.
static func _v28_to_v29(d: Dictionary) -> Dictionary:
	d.state.claims_made = 0
	return d


## v28: storehouses with chests (issue #189). A storehouse keeps its chest count, and what's in its
## chests is saved with the map's items, keyed by chest slot. Older saves have no storehouses, so
## nothing in them changes.
static func _v27_to_v28(d: Dictionary) -> Dictionary:
	return d


## v27: the founding is reworked (issue #182). The bench makes a recipe's planks and sticks from the
## start, and the goals read new stats. A village keeps its progress: what's built is recorded, the
## pickaxe goal covers the new tools goal, a second house covers the fireplace, board and meadow steps
## it skipped, and a founding that was complete stays complete.
static func _v26_to_v27(d: Dictionary) -> Dictionary:
	var st: Dictionary = d.state
	st.auto_craft = true
	var stats: Dictionary = st.stats
	var built := {}
	for s in st.maps.village.sites:
		if s.done:
			built[s.tpl] = true
	var two_houses: bool = stats.get("houses", 0) >= 2
	if two_houses:
		built.fireplace = true
		built.board = true
	if stats.get("division", false):
		built.chopping_block = true
	stats.built = built
	stats.axe_crafted = stats.get("pick_crafted", false)
	stats.meadow_wool = two_houses
	return d


## v26: chopping blocks saw planks and mason's benches cut stone bricks (issue #178). Each standing
## workstation gets the standing order a new one has: keep 20 planks, or 10 stone bricks.
static func _v25_to_v26(d: Dictionary) -> Dictionary:
	for id in d.state.maps:
		for s in d.state.maps[id].sites:
			if s.tpl in V26_MAKE_KEEP:
				s.make_keep = V26_MAKE_KEEP[s.tpl]
	return d


## The standing order targets when v26 came in (issue #178).
const V26_MAKE_KEEP := {"chopping_block": 20, "mason_bench": 10}


## v25: hunters hunt on their own down to a herd floor per species (issue #183). Every species starts at
## the default floor, which an empty table means.
static func _v24_to_v25(d: Dictionary) -> Dictionary:
	d.state.herd_floor = {}
	return d


## v24: a resident works their job only from a workstation they've claimed (issue #184). Finished
## benches, fireplaces, chopping blocks and mason's benches go to residents whose jobs match, first come
## first served; the rest haul until one is built. Nothing else is claimed.
static func _v23_to_v24(d: Dictionary) -> Dictionary:
	var st: Dictionary = d.state
	var sites: Array = st.maps.village.sites
	for s in sites:
		s.worker = 0
	for r in st.residents:
		var tpl: String = V24_STATIONS.get(r.role, "")
		for s in sites:
			if s.tpl == tpl and s.done and s.worker == 0:
				s.worker = r.id
				break
	return d


## The workstations that existed when v24 came in (issue #184), by job.
const V24_STATIONS := {"craft": "bench", "cook": "fireplace", "lumber": "chopping_block", "mason": "mason_bench"}


## v23: Lumberjack and Stonemason replace Mine (issue #177). A miner becomes a lumberjack: nobody's
## trees and boulders were counted apart, so it's the tie rule. Mine's experience carries over to both.
## No village has a workstation yet, no tree is a sapling or kept, and Ada's "all" is unchanged.
static func _v22_to_v23(d: Dictionary) -> Dictionary:
	for r in d.state.residents:
		var xp: int = r.jobs.get("mine", {}).get("xp", 0)
		r.jobs.erase("mine")
		r.jobs["lumber"] = {"xp": xp}
		r.jobs["mason"] = {"xp": xp}
		if r.role == "mine":
			r.role = "lumber"
	return d


## The jobs as they were up to v22, before Lumberjack and Stonemason replaced Mine (issue #177).
const V22_JOBS := ["mine", "haul", "build", "craft", "toolsmith", "farm", "cook", "hunt"]


## v22: one job per resident (issue #134). Ada does everything. Everyone else gets their switched-on
## job with the best priority, ties broken by level, then the job list's order, or Haul if all were
## off. The switches and priorities go. (Saves from before v10 get every job on at priority 2, then
## Toolsmith off, as v10 and #91 gave them.)
static func _v21_to_v22(d: Dictionary) -> Dictionary:
	var st: Dictionary = d.state
	for i in st.residents.size():
		var r: Dictionary = st.residents[i]
		var best := ""
		var best_pri := 0
		var best_lv := 0
		for jb in V22_JOBS:
			var j: Dictionary = r.jobs[jb]
			if j.get("on", jb != "toolsmith"):
				var pri: int = j.get("pri", 2)
				var lv := Sim.level(r, jb)
				if best == "" or pri < best_pri or (pri == best_pri and lv > best_lv):
					best = jb
					best_pri = pri
					best_lv = lv
			r.jobs[jb] = {"xp": j.get("xp", 0)}
		r.role = "all" if i == 0 else (best if best != "" else "haul")
	return d


## v21: pens and breeding at the meadow (issue #139), and leather armor (issue #140). No map has a pen
## yet and nobody wears armor; an expedition already planned or out packs no sticks or wheat.
static func _v20_to_v21(d: Dictionary) -> Dictionary:
	var st: Dictionary = d.state
	for id in st.maps:
		st.maps[id].pens = st.maps[id].get("pens", [])
		st.maps[id].gates = st.maps[id].get("gates", {})
	for r in st.residents:
		if not r.has("armor"):
			r.armor = {}
	var ex: Dictionary = st.get("expedition", {})
	if not ex.is_empty():
		ex.sticks = ex.get("sticks", 0)
		ex.wheat = ex.get("wheat", 0)
		if ex.has("provisions") and not ex.has("supplies"):
			ex.supplies = {}
	return d


## v20: the old mine's deeper levels (issue #132), and cows and pigs (issue #138). The game keeps its
## seed, which deeper levels are made from. The old mine is Level 1, with its door at the far end,
## behind a block of stone the party has to mine; nobody has reached it yet. Every animal so far is a
## sheep.
static func _v19_to_v20(d: Dictionary) -> Dictionary:
	var st: Dictionary = d.state
	if not st.has("seed"):
		st.seed = Tuning.SEED
	_meadow_trips_home(st)
	for id in st.maps:  # issue #138: the animals so far are all sheep
		for sh in st.maps[id].get("sheep", []):
			sh.kind = "animal"
			if not sh.has("species"):
				sh.species = "sheep"
	var mine: Dictionary = st.maps.get(OldMine.ID, {})
	if not mine.is_empty() and not mine.has("door"):
		mine.level = 1
		mine.pattern = "workings"
		mine.door = Vector2i(15, 8)
		mine.door_state = "closed"
		mine.rock[mine.door] = true
		mine.rock.erase(Vector2i(13, 7))  # a way round the loose ceiling at (12, 8) to the door
		var front := Vector2i(14, 8)
		if mine.rock.has(front):
			mine.rock.erase(front)
			mine.boulders.append({"id": st.next_id, "kind": "boulder", "cell": front, "alive": true, "des": false, "claim": 0, "unreach_until": 0})
			st.next_id += 1
	return d


## Slice 2's timed meadow trip is gone (issue #137): anyone away on one is home at the meadow signpost,
## with the wool and raw mutton they'd have brought back, set down beside it. What's left of the old
## meadow's sheep (`meadow_sheep`) stays in the save, and the new meadow map keeps that many when it's
## made on loading.
static func _meadow_trips_home(st: Dictionary) -> void:
	var village: Dictionary = st.maps.village
	var sign := Vector2i(0, int(village.h) / 2)
	var taken := {}
	for o in village.trees + village.boulders:
		if o.alive:
			taken[o.cell] = true
	for r in st.residents:
		if not r.get("away", false) or not r.get("trip", "") in ["", "meadow"]:
			continue
		r.away = false
		r.trip = ""
		r.back_at = 0
		r.pos = Vector2(sign)
		var take := mini(OLD_MEADOW_TAKE, int(st.get("meadow_sheep", OLD_MEADOW_SHEEP)))
		st.meadow_sheep = st.get("meadow_sheep", OLD_MEADOW_SHEEP) - take
		if take <= 0:
			continue
		st.stats.meadow_trips = st.stats.get("meadow_trips", 0) + 1
		for type in ["wool", "mutton"]:
			var c := sign + Vector2i(1, 0)
			while village.items.has(c) or taken.has(c):
				c.x += 1
			village.items[c] = {"cell": c, "type": type, "n": take, "res": 0}
	st.erase("meadow_regrow")


## v19: the track crew, stations and the cart (issues #122-#124). No cart is on the line yet, and a
## segment's laid rails start at none (rails already delivered to it stay in its store).
static func _v18_to_v19(d: Dictionary) -> Dictionary:
	if not d.state.has("cart"):
		d.state.cart = {}
	var road: Dictionary = d.state.maps.get(Road.ID, {})
	for st in road.get("sites", []):
		if st.tpl == "track" and not st.has("laid"):
			st.laid = Tuning.RAILS_PER_SEGMENT if st.done else 0
	return d


## Slice 2's off-map meadow (v19 and earlier): the sheep it held, and the sheep's worth of wool and raw
## mutton each resident brought back from a trip.
const OLD_MEADOW_SHEEP := 8
const OLD_MEADOW_TAKE := 2


## The walk between the village and the old mine in v17 and earlier, a timer off the map.
const OLD_MINE_TRIP := 60.0


## v18: the road to the mine (issues #118-#121). The road is a map of its own now, added when the save
## loads (known if the old mine is). A party member saved on the road, away and due at a time, is
## placed at the matching point along it, still heading the same way.
static func _v17_to_v18(d: Dictionary) -> Dictionary:
	var st: Dictionary = d.state
	var span: int = Road.MINE_END.x - Road.VILLAGE_END.x
	var blocked: Array = []
	for y in Road.LAYOUT.size():
		for x in Road.LAYOUT[y].length():
			if Road.LAYOUT[y][x] != ".":
				blocked.append(Vector2i(x, y))
	for r in st.residents:
		if not r.get("away", false) or r.get("trip", "") in ["", "meadow"]:
			continue
		var left := clampf(float(r.back_at - st.tick) / Tuning.TPS / OLD_MINE_TRIP, 0.0, 1.0)
		var x: int = Road.MINE_END.x - roundi(left * span) if r.trip != "village" else Road.VILLAGE_END.x + roundi(left * span)
		var c := Vector2i(x, Road.LINE_ROW)
		while c in blocked:  # not on a boulder or in the stream
			c.x += 1 if r.trip != "village" else -1
		r.away = false
		r.map = Road.ID
		r.pos = Vector2(c)
	return d


## v17: the party works the site, hazards and injuries, and the iron discovery (issues #109-#111).
## Nobody is hurt and no choice is waiting. The old mine gets its loose ceilings and ledge, and its
## vein counts as found if it was discovered. A party already out keeps its meals in the packs; one
## that had set its supplies down at the entrance finds them there, and packs them again.
static func _v16_to_v17(d: Dictionary) -> Dictionary:
	var st: Dictionary = d.state
	for r in st.residents:
		if not r.has("hurt"):
			r.hurt = 0
			r.heal = 0.0
	if not st.has("pending"):
		st.pending = []
	var mine: Dictionary = st.maps.get(OldMine.ID, {})
	if not mine.is_empty() and not mine.has("ledges"):
		mine.found = mine.get("discovered", false)
		mine.ledges = OldMine.LEDGES.duplicate()
		for b in mine.boulders:
			if b.cell in OldMine.LOOSE:
				b.loose = true
	var ex: Dictionary = st.get("expedition", {})
	if ex.get("state", "") == "out" and not ex.has("provisions"):
		ex.provisions = {} if ex.get("unpacked", false) else ex.get("packed", {}).duplicate()
		if ex.get("unpacked", false):
			ex.tools = []
		ex.cargo = ex.get("cargo", {})
		ex.hurt = {}
	return d


## v16: expeditions (issues #106, #107). Older saves have none planned, and a resident who's away is
## at the meadow, the only trip there was.
static func _v15_to_v16(d: Dictionary) -> Dictionary:
	if not d.state.has("expedition"):
		d.state.expedition = {}
	for r in d.state.residents:
		if not r.has("trip"):
			r.trip = "meadow" if r.get("away", false) else ""
	return d


## v15: more than one map (issues #100, #101, #102). The village's trees, items, buildings and the
## rest move into `maps.village`, and everyone and every building is on the village map. The old
## mine isn't in older saves: it's added, unvisited, when the save loads. The camera remembers a
## position for each map, and which map was in view.
static func _v14_to_v15(d: Dictionary) -> Dictionary:
	var st: Dictionary = d.state
	if not st.has("maps"):
		var village := {"id": "village", "kind": "village", "name": "Village"}
		for k in ["w", "h", "trees", "boulders", "sheep", "bushes", "items", "zone", "farm", "sites"]:
			village[k] = st[k]
			st.erase(k)
		st.maps = {"village": village}
	for r in st.residents:
		if not r.has("map"):
			r.map = "village"
	for s in st.maps.village.sites:
		if not s.has("map"):
			s.map = "village"
	var cam: Dictionary = d.get("camera", {})
	if cam.has("target") and not cam.has("maps"):
		d.camera = {"map": "village", "maps": {"village": {"target": cam.target, "size": cam.size}}}
	return d


## v14: brighter tunics that read on grass and under a canopy (issue #79). Residents in older saves
## swap their old tunic for the new one in the same place on the list; any other colour stays.
static func _v13_to_v14(d: Dictionary) -> Dictionary:
	var old := ["3E6E7E", "8C4F6B", "6B7F3A", "8A6A2E", "4F6A8C", "7A4A6E", "3E7E6A", "8C5A3E", "5E5A8C"]
	var now: Array = [Sim.ADA_TUNIC] + Sim.TRAVELERS.map(func(t): return t[1])
	for r in d.state.residents:
		var i := old.find(r.shirt)
		if i >= 0:
			r.shirt = now[i]
	return d


## v13: the sheep meadow (issue #50). Older saves get a full meadow, and nobody is away.
static func _v12_to_v13(d: Dictionary) -> Dictionary:
	if not d.state.has("meadow_sheep"):
		d.state.meadow_sheep = OLD_MEADOW_SHEEP
		d.state.meadow_regrow = 0.0
	for r in d.state.residents:
		if not r.has("away"):
			r.away = false
			r.back_at = 0
	return d


## v12: residents remember a tool they were told to equip, and keep it until it breaks. Nothing
## was chosen in older saves.
static func _v11_to_v12(d: Dictionary) -> Dictionary:
	for r in d.state.residents:
		if not r.has("kept"):
			r.kept = {"axe": false, "pick": false}
	return d


## v11: experience in each job (issue #48). Everyone in an older save starts at level 1.
static func _v10_to_v11(d: Dictionary) -> Dictionary:
	for r in d.state.residents:
		for jb in r.jobs:
			if not r.jobs[jb].has("xp"):
				r.jobs[jb].xp = 0
	return d


## v10: residents' jobs, each on or off with a priority (issue #47). Everyone starts with every
## job on at priority 2, which is how they worked before.
static func _v9_to_v10(d: Dictionary) -> Dictionary:
	for r in d.state.residents:
		if not r.has("jobs"):
			r.jobs = {}
			for jb in V22_JOBS:  # the jobs of the time, which later steps upgrade
				r.jobs[jb] = {"on": jb != "toolsmith", "pri": 2, "xp": 0}
	return d


## v9: reserved plots for job buildings, and the fireplace's standing order (issue #46). Benches
## from older saves reserve nothing.
static func _v8_to_v9(d: Dictionary) -> Dictionary:
	for s in d.state.sites:
		if not s.has("plot"):
			s.plot = null
	return d


## v8: farm plots and growing wheat (issue #45). Older saves have no farms.
static func _v7_to_v8(d: Dictionary) -> Dictionary:
	if not d.state.has("farm"):
		d.state.farm = {}
	return d


## v7: hunger and berry bushes (issue #44). Residents start full. Older saves get the same berry
## bushes as a new game, placed relative to the opening (shifted on 32×32 maps); any that land on a
## tree, boulder or building are dropped when the save loads.
static func _v6_to_v7(d: Dictionary) -> Dictionary:
	for r in d.state.residents:
		if not r.has("hunger"):
			r.hunger = 100.0
	if not d.state.has("bushes"):
		var o: Vector2i = Tuning.OPENING_OFFSET if int(d.state.w) > 18 else Vector2i.ZERO
		var next_id: int = d.state.next_id
		var list: Array = []
		for p in Sim.START_BUSHES:
			list.append({"id": next_id, "kind": "bush", "cell": Vector2i(p[0], p[1]) + o, "berries": Tuning.BUSH_MAX, "regrow": 0.0})
			next_id += 1
		d.state.bushes = list
		d.state.next_id = next_id
	return d


## v6: houses have a fourth stage, the bed (issue #43). A finished house in an older save gets a
## finished bed, so its resident stays housed.
static func _v5_to_v6(d: Dictionary) -> Dictionary:
	for s in d.state.sites:
		if s.tpl == "house" and s.done and s.stage < 4:
			s.stage = 4
	return d


## v5: sheep and the sim's random-number state (issue #42). Older saves are past the opening, so
## they get no sheep; their random numbers start from the game's seed.
static func _v4_to_v5(d: Dictionary) -> Dictionary:
	if not d.state.has("sheep"):
		d.state.sheep = []
	if not d.state.has("rng_state"):
		var g := RandomNumberGenerator.new()
		g.seed = Tuning.SEED
		d.state.rng_state = g.state
	return d


## v4: the map size is saved (issue #52). Everything before v4 was played on the 18×18 map.
static func _v3_to_v4(d: Dictionary) -> Dictionary:
	if not d.state.has("w"):
		d.state.w = 18
		d.state.h = 18
	return d


## v3: residents have a list of queued orders (Shift + right-click, issue #2).
static func _v2_to_v3(d: Dictionary) -> Dictionary:
	for r in d.state.residents:
		if not r.has("orders"):
			r.orders = []
	return d


## v2: tool items remember their remaining uses (issue #5). In v1 a dropped tool always came back
## new, so give every loose or carried tool full uses.
static func _v1_to_v2(d: Dictionary) -> Dictionary:
	for k in d.state.items:
		var it: Dictionary = d.state.items[k]
		if Defs.is_tool_item(it.type) and not it.has("dur"):
			it.dur = Sim.full_uses(it.type)
	for r in d.state.residents:
		if r.get("carry") != null and Defs.is_tool_item(r.carry.type) and not r.carry.has("dur"):
			r.carry.dur = Sim.full_uses(r.carry.type)
	return d


## Reads a save file. Returns {"data": Dictionary} upgraded to the current version, or
## {"error": text for the player} when the file can't be used.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "This slot is empty."}
	return parse(FileAccess.get_file_as_string(path))


static func parse(text: String) -> Dictionary:
	var data = str_to_var(text)
	if not (data is Dictionary) or not data.has("v") or not data.has("state"):
		return {"error": "This save is damaged and can’t be loaded."}
	return upgrade(data)


## Runs `data` through each upgrade step from its version up to `target`, in order. `steps` and
## `target` default to the real ones; tests pass their own to check the chain.
static func upgrade(data: Dictionary, steps = null, target := VERSION) -> Dictionary:
	if steps == null:
		steps = upgrades()
	var v: int = int(data.v)
	if v > target:
		return {"error": "This save is from a newer version of the game."}
	while v < target:
		if not steps.has(v):
			return {"error": "This save is from an old version that can’t be upgraded."}
		data = (steps[v] as Callable).call(data)
		v += 1
		data.v = v
	return {"data": data}


static func write(path: String, data: Dictionary) -> bool:
	data.v = VERSION
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(var_to_str(data))
	f.close()
	return true
