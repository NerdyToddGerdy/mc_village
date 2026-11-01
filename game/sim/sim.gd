class_name Sim
extends RefCounted
## The Slice 1 simulation: plain data plus fixed-tick logic. No Nodes, no rendering; runs headless.
##
## Views read the public state and call the command methods (designate_mine, place_site, ...).
## Commands apply immediately, so they work while paused. Each tick may append to `events`,
## which the host hands to views and then clears. `rev` increases whenever anything drawn as
## static geometry changes, so views know when to rebuild.

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Every map (issue #100): "village", plus site maps such as the old mine. Each map ticks every tick.
var maps := {}               ## id -> SimMap
## The map the per-map fields below read and write. It's the village except while the sim works on
## another map; `on_map` and `use_map` switch it. Commands work on the map that's current, and a
## command about a resident or a building switches to theirs first.
var map_id := "village"
var m: SimMap

# The current map's state (see SimMap for each field).
var w: int:
	get: return m.w
var h: int:
	get: return m.h
var trees: Array:
	get: return m.trees
	set(v): m.trees = v
var boulders: Array:
	get: return m.boulders
	set(v): m.boulders = v
var sheep: Array:
	get: return m.sheep
	set(v): m.sheep = v
var bushes: Array:
	get: return m.bushes
	set(v): m.bushes = v
var items: Dictionary:
	get: return m.items
	set(v): m.items = v
var zone: Dictionary:
	get: return m.zone
	set(v): m.zone = v
var zone_res: Dictionary:
	get: return m.zone_res
var farm: Dictionary:
	get: return m.farm
	set(v): m.farm = v
var sites: Array:
	get: return m.sites
	set(v): m.sites = v
var _occ_dirty: bool:
	get: return m.occ_dirty
	set(v): m.occ_dirty = v

var tick := 0
var next_id := 1
var rng := RandomNumberGenerator.new()  ## Seeded and saved, so a game replays exactly.
var seed := Tuning.SEED      ## The game's seed: the old mine's deeper levels are generated from it (issue #132).
var residents: Array = []    ## Everyone, on every map; each has the `map` they're on.
var stats := {"felled": 0, "broken_boulders": 0, "tools_broken": 0, "pick_crafted": false, "axe_crafted": false,
	"houses": 0, "traveler_home": false, "division": false, "built": {}, "meadow_wool": false,
	"meals_cooked": 0, "ore_home": false}
var arrival_at := -1
var arrived := false
var auto_craft := false      ## Unlocked when the first house is finished.
var wheat_keep := Tuning.WHEAT_KEEP  ## How much wheat the village keeps before farmers stop (issue #269).
var herd_floor := {}         ## Species -> how many wild animals hunters leave in the village (issue #183); unset is Tuning.HERD_FLOOR.
## The planned expedition (issues #106, #107), or {} when there's none. Two at once (#145): one Overworld and one Nether,
## in `expeditions`. `expedition` is the current slot's, like `m` is the current map's: it's the Overworld's at rest, and
## the tick switches it to whoever's turn it is (`use_slot`, `on_slot`):
##   {dest, board (site id), party: [resident ids], target: {item, n}, meals, picks,
##    policy: {target, full, low}, spend_return, state: "staging" or "out", packed: {item: n}, tools: [{type, dur}],
##    leg: "out" or "home", provisions: {meal: n}, cargo: {item: n}, broken: n, hurt: {name: level},
##    survey: bool, home_why}
## `packed` is what was packed at the board, kept for the report. Once out, the packs hold `provisions`
## (meals left), `tools` (spare pickaxes left) and `cargo` (what's been mined), sharing PACK_CAPACITY
## each (issue #109). `leg` is which way the party is going (#108).
var expedition: Dictionary:
	get:
		return expeditions[slot]
	set(v):
		expeditions[slot] = v
const SLOTS := ["overworld", "nether", "rescue"]
## Which realm each slot's party works in: a rescue is a Nether expedition of its own, out even when the Nether's is taken (issue #158).
const SLOT_REALM := {"overworld": "overworld", "nether": "nether", "rescue": "nether"}
var expeditions := {"overworld": {}, "nether": {}, "rescue": {}}
var slot := "overworld"   ## Which of `expeditions` is `expedition` now.
## Choices waiting for the player, oldest first (issues #110, #111): {kind, text, options, res_id, map}.
## The game pauses while there's one.
var pending: Array = []
## The line's one minecart once it's parked at a station (issue #123), or {}:
##   {at: "village" or "mine", x (along the line), state: "parked", "loading", "moving" or "unloading",
##    load: {item: n} (cargo in it), riders: [resident ids], acc (items toward the next one loaded)}
var cart := {}
## The portal line's Nether side (issue #168): `laid` rails of NetherLanding.TRACK, laid by a Build party. The village station is a
## site beside the portal; the landing station is the Nether line's, so the two lines share it.
var portal_line := {"laid": 0}
## The portal line's freight cart (issue #169), or {} until one is ordered:
##   {state: "ordered" (a hauler is bringing a minecart), "home", "going", "unloading" or "returning", pos (0 at the village station, 1 at
##    the landing station), load: {item: n}, approved, acc}
var freight := {}
## Dust lines between redstone devices (issue #170): {id, from, to (site ids), cells: [Vector2i], laid (cells so far)}. A line carries a
## signal once every cell is laid.
var wires: Array = []
var stuck: Array = []        ## {who, why, map, cell (Vector2), height, focus_kind, focus_id, hidden, waiting, since}
var _fence_claims := {}      ## Vector2i -> the resident putting up that pen fence (issue #139). Not saved.
var _plant_claims := {}      ## Vector2i -> the lumberjack going to plant a sapling there (issue #177). Not saved.
var _stuck_since := {}       ## A stuck entry's key -> the tick it first showed, to order the list (issue #77). Not saved.
var events: Array = []       ## {type: "toast", text, res_id, site_id, map}
var rev := 0


func _init() -> void:
	maps = {"village": SimMap.new()}
	use_map("village")


# ---------------------------------------------------------------- maps (issue #100)

## Makes `id` the current map. Returns the map that was current, to put back afterwards.
func use_map(id: String) -> String:
	var prev := map_id
	map_id = id
	m = maps[id]
	return prev


## Runs `f` with `id` as the current map, then puts the current map back. Returns what `f` returns.
func on_map(id: String, f: Callable):
	var prev := use_map(id)
	var out = f.call()
	use_map(prev)
	return out


func get_map(id: String) -> SimMap:
	return maps[id]


# ---------------------------------------------------------------- expedition slots (issue #145)

## Which realm a map is in: "nether" for the Nether's maps (their ids start with "nether"), else "overworld".
static func realm_of(id: String) -> String:
	return "nether" if id.begins_with("nether") else "overworld"


## Makes `id` ("overworld" or "nether") the current expedition slot. Returns the slot that was current.
func use_slot(id: String) -> String:
	var prev := slot
	slot = id
	return prev


## Runs `f` with slot `id` current, then puts the current slot back. Returns what `f` returns.
func on_slot(id: String, f: Callable):
	var prev := use_slot(id)
	var out = f.call()
	use_slot(prev)
	return out


## The one helper that walks the slots (issue #145): runs `f` for each slot that has an expedition.
func each_expedition(f: Callable) -> void:
	for sl in SLOTS:
		if not expeditions[sl].is_empty():
			on_slot(sl, f)


## The slot a destination's expedition goes in (a rescue's plan picks the rescue slot itself).
static func slot_of_dest(dest: String) -> String:
	return realm_of(dest)


## Whether the current slot is a party in the Nether, an ordinary one or a rescue.
func in_nether() -> bool:
	return SLOT_REALM[slot] == "nether"


## The slot a resident's party is in, else the slot of the realm they're in.
func slot_of(r: Dictionary) -> String:
	for sl in SLOTS:
		if expeditions[sl].get("party", []).has(r.id):
			return sl
	return realm_of(r.map)


## The expedition a resident is in the party of, or {}.
func expedition_of(r: Dictionary) -> Dictionary:
	for sl in SLOTS:
		if expeditions[sl].get("party", []).has(r.id):
			return expeditions[sl]
	return {}


## What the player calls a slot's party: "Overworld party", "Nether party".
static func party_name(sl: String) -> String:
	return "%s party" % sl.capitalize()


## Residents on the current map, not counting anyone away on the walk to or from the meadow.
func here() -> Array:
	return residents.filter(func(r): return r.map == map_id and not r.away)


## Moves a resident onto another map, at `cell`. This is the one way between maps, used by travel
## (#108): nothing walks from one grid to another. Their job ends first, on the map they leave.
func move_to_map(r: Dictionary, id: String, cell: Vector2i) -> void:
	if r.job != null:
		fail_job(r)
	r.direct = null
	r.orders.clear()
	r.map = id
	r.pos = Vector2(cell)
	r.path = []
	rev += 1


# ---------------------------------------------------------------- setup

## The opening's trees and boulders, as tuned on the original 18×18 map. They sit in the middle
## of the bigger clearing, shifted by Tuning.OPENING_OFFSET, so the opening plays as it always has.
const OPENING_TREES := [[2, 9], [3, 13], [12, 2], [2, 3], [6, 12], [15, 6], [9, 15], [15, 13], [6, 2], [16, 9], [13, 16], [1, 16], [9, 2], [4, 6]]
const OPENING_BOULDERS := [[11, 12], [14, 10], [7, 5], [10, 4], [16, 3], [7, 16]]
const OPENING_START := Vector2i(9, 9)
## The outer ring of the 32×32 clearing (issue #52), in map cells. Trees stay 3 cells apart so
## canopies don't merge, and the left edge from y 12 down is kept clear for travelers.
const RING_TREES := [[9, 2], [26, 2], [14, 3], [17, 3], [8, 5], [11, 5], [26, 7], [29, 8], [4, 10], [26, 11],
	[4, 16], [27, 17], [30, 17], [5, 20], [27, 21], [30, 23], [5, 25], [26, 25], [11, 27], [14, 27], [30, 27],
	[22, 28], [19, 29], [5, 30], [10, 30], [13, 30]]
const RING_BOULDERS := [[6, 7], [3, 8], [28, 11], [25, 13], [3, 14], [14, 25], [19, 26], [21, 26], [17, 30], [24, 30]]
## Three sheep around the opening (issues #42, #182): wool for Ada's bed. The second bed's comes from the
## meadow. Open ground, in map cells.
const START_SHEEP := [[21, 8], [12, 24], [24, 19]]
## Berry bushes, in opening coordinates (like OPENING_TREES): early food before farms (issue #44).
const START_BUSHES := [[5, 10], [12, 6], [4, 14], [13, 14], [8, 13], [16, 12]]


static func new_game() -> Sim:
	var s := Sim.new()
	var o := Tuning.OPENING_OFFSET
	var spots: Array = OPENING_TREES.map(func(p): return Vector2i(p[0], p[1]) + o) + RING_TREES.map(func(p): return Vector2i(p[0], p[1]))
	for i in spots.size():
		s.trees.append({"id": s._id(), "kind": "tree", "cell": spots[i], "logs": 4 + (i * 7) % 3,
			"alive": true, "des": false, "claim": 0, "unreach_until": 0})
	var rocks: Array = OPENING_BOULDERS.map(func(p): return Vector2i(p[0], p[1]) + o) + RING_BOULDERS.map(func(p): return Vector2i(p[0], p[1]))
	for c in rocks:
		s.boulders.append({"id": s._id(), "kind": "boulder", "cell": c,
			"alive": true, "des": false, "claim": 0, "unreach_until": 0})
	s.rng.seed = Tuning.SEED
	for p in START_BUSHES:
		s.add_bush(Vector2i(p[0], p[1]) + o)
	for p in START_SHEEP:
		s.add_sheep(Vector2i(p[0], p[1]))
	s.add_resident("Ada", ADA_TUNIC, OPENING_START + o)
	s.auto_craft = true  # the bench makes a recipe's planks and sticks from the start (issue #182)
	s._add_site_maps()
	return s


## Adds any site map the sim doesn't have yet: a new game's, or one newer than a loaded save.
func _add_site_maps() -> void:
	if not maps.has(OldMine.ID):
		maps[OldMine.ID] = OldMine.build(self)
	if not maps.has(Road.ID):  # the road becomes known with the mine (issue #118)
		maps[Road.ID] = Road.build(self)
		road().known = maps[OldMine.ID].known
	if not maps.has(Meadow.ID):  # so does the meadow, an adventure from the same board (issue #137)
		maps[Meadow.ID] = Meadow.build(self)
		maps[Meadow.ID].known = maps[OldMine.ID].known
	if not maps.has(MeadowRoad.ID):  # and the strip of road that leads to it (issue #210)
		maps[MeadowRoad.ID] = MeadowRoad.build(self)
		maps[MeadowRoad.ID].known = maps[Meadow.ID].known
	if not maps.has(NetherLanding.ID):  # the first Nether map: known once the portal is lit (issue #148)
		maps[NetherLanding.ID] = NetherLanding.build(self)
	for key in NetherRoute.ROUTES:  # the routes out of the landing, and the sites at their ends: known once scouted (issue #153)
		if not maps.has(NetherRoute.ROUTES[key].id):
			maps[NetherRoute.ROUTES[key].id] = NetherRoute.build(self, key)
			maps[NetherRoute.ROUTES[key].site] = NetherRoute.build_site(self, key)
		elif key in ["quartz", "piglin", "fortress"] and maps[NetherRoute.ROUTES[key].site].pattern == "":  # an older save's empty room becomes the site (issues #155, #156)
			var was_known: bool = maps[NetherRoute.ROUTES[key].site].known
			maps[NetherRoute.ROUTES[key].site] = NetherRoute.build_site(self, key)
			maps[NetherRoute.ROUTES[key].site].known = was_known


func add_bush(cell: Vector2i) -> Dictionary:
	var b := {"id": _id(), "kind": "bush", "cell": cell, "berries": Tuning.BUSH_MAX, "regrow": 0.0}
	m.bushes.append(b)
	return b


func add_sheep(cell: Vector2i) -> Dictionary:
	return add_animal(cell, "sheep")


## An animal of a species (issue #138) standing at `cell`.
func add_animal(cell: Vector2i, species: String) -> Dictionary:
	var sh := {"id": _id(), "kind": "animal", "species": species, "pos": Vector2(cell), "cell": cell, "dest": null, "wait": rng.randf_range(Tuning.SHEEP_PAUSE[0], Tuning.SHEEP_PAUSE[1]),
		"alive": true, "des": false, "claim": 0, "unreach_until": 0}
	m.sheep.append(sh)
	return sh


func _id() -> int:
	next_id += 1
	return next_id - 1


func add_resident(rname: String, shirt: String, cell: Vector2i) -> Dictionary:
	var r := {"id": _id(), "kind": "res", "name": rname, "shirt": shirt, "pos": Vector2(cell),
		"path": [], "job": null, "direct": null, "carry": null, "axe": null, "pick": null, "sword": null,
		"broken": {"axe": false, "pick": false, "sword": false}, "progress": -1.0, "note": null, "arriving": false,
		"orders": [], "hunger": 100.0, "role": "all" if residents.is_empty() else "none", "jobs": default_jobs(), "kept": {"axe": false, "pick": false, "sword": false},
		"away": false, "back_at": 0, "trip": "", "map": map_id, "hurt": 0, "heal": 0.0, "armor": {}}
	residents.append(r)
	return r


## Experience in every job, none yet (spec §5).
static func default_jobs() -> Dictionary:
	var out := {}
	for jb in Defs.JOBS:
		out[jb] = {"xp": 0}
	return out


## Whether a resident claims work of a job (issue #134): Ada ("all") claims every kind, and everyone
## else their one job, once they've claimed its workstation (issue #184), then hauling.
func works(r: Dictionary, job: String) -> bool:
	if r.role == "all" or job == "haul":
		return true
	if job == "guard":  # needs no workstation: guards fight on expeditions (issue #150)
		return r.role == "guard"
	return r.role == job and not claimed(r).is_empty()


## The jobs whose work a resident claims, in Defs.JOBS order.
func job_list(r: Dictionary) -> Array:
	return Defs.JOBS.filter(func(jb): return works(r, jb))


## The finished workstation a resident has claimed (issue #184), or {}. Ada claims none.
func claimed(r: Dictionary) -> Dictionary:
	if r.role == "all" or not Defs.JOB_STATIONS.has(r.role):
		return {}
	for st in maps.village.sites:
		if st.done and st.get("worker", 0) == r.id:
			return st
	return {}


## Whether a resident's job is waiting on a workstation: they have one that needs it, and none is theirs.
func needs_station(r: Dictionary) -> bool:
	return r.role != "all" and Defs.JOB_STATIONS.has(r.role) and claimed(r).is_empty()


## Hands out workstations (issue #184), one resident to each. A workstation whose resident is gone, has
## another job now, or which isn't finished is freed; then each resident whose job needs one and who has
## none claims the nearest free one.
func assign_workstations() -> void:
	var vm: SimMap = maps.village
	var changed := false
	for st in vm.sites:
		var wid: int = st.get("worker", 0)
		if wid == 0:
			continue
		var r := resident(wid)
		if r.is_empty() or not st.done or Defs.JOB_STATIONS.get(r.role, "") != st.tpl:
			st.worker = 0
			changed = true
	for r in residents:
		if not needs_station(r):
			continue
		var free: Array = vm.sites.filter(func(st): return st.done and st.tpl == Defs.JOB_STATIONS[r.role] and st.get("worker", 0) == 0)
		if free.is_empty():
			continue
		var best: Dictionary = _nearest_site(free, rcell(r))
		best.worker = r.id
		changed = true
	if changed:
		rev += 1


## "Farmer", or with no workstation of their own, "Farmer (no composter)".
func role_text(r: Dictionary) -> String:
	if needs_station(r):
		return "%s (no %s)" % [role_name(r), Defs.TEMPLATES[Defs.JOB_STATIONS[r.role]].name.to_lower()]
	return role_name(r)


## A workstation's name with its resident's: "Bram's composter", or just "Composter" while it's free.
func station_title(st: Dictionary) -> String:
	var r := resident(st.get("worker", 0))
	var tname: String = station_name(st)
	return tname if r.is_empty() else "%s's %s" % [r.name, tname.substr(0, 1).to_lower() + tname.substr(1)]


## "Farmer", "Everything" for Ada, or "No job".
static func role_name(r: Dictionary) -> String:
	match r.role:
		"all":
			return "Everything"
		"none":
			return "No job"
	return Defs.JOB_SKILLED[r.role].capitalize()


## Which job a recipe's work belongs to: the fireplace's is Cook, a workstation's is its gatherers'
## (issue #178), the bench's tools are Toolsmith, and the rest (planks, sticks) is Craft.
static func recipe_job(rec: Dictionary) -> String:
	var at: String = rec.get("at", "bench")
	if at == "fireplace":
		return "cook"
	if Defs.TEMPLATES[at].has("work"):
		return Defs.TEMPLATES[at].work.job
	for o in rec.out:
		if Defs.is_tool_item(o):
			return "toolsmith"
	return "craft"


## Total experience for a level. Levels 2 to 5 are the fixed table; past it the same gentle power
## curve carries on, so there's no top level (issue #236).
static func xp_for(lv: int) -> int:
	if lv <= 1:
		return 0
	if lv <= Tuning.SKILL_CORE:
		return Tuning.SKILL_LEVELS[lv - 2]
	return roundi(Tuning.SKILL_TAIL_XP * pow(lv - 1, Tuning.SKILL_TAIL_POWER))


## A resident's level in a job, from their experience (spec §5).
static func level(r: Dictionary, job: String) -> int:
	var xp: int = r.jobs[job].get("xp", 0)
	var lv := 1
	for need in Tuning.SKILL_LEVELS:
		if xp >= need:
			lv += 1
	if lv > Tuning.SKILL_CORE - 1:  # past the table, climb the curve
		while xp >= xp_for(lv + 1):
			lv += 1
	return lv


## Progress from the current level to the next, 0..1.
static func level_progress(r: Dictionary, job: String) -> float:
	var lv := level(r, job)
	var lo := xp_for(lv)
	return float(r.jobs[job].get("xp", 0) - lo) / float(xp_for(lv + 1) - lo)


## One finished task's worth of experience. Says so when it brings a new level.
func gain_xp(r: Dictionary, job: String) -> void:
	var before := level(r, job)
	r.jobs[job].xp = r.jobs[job].get("xp", 0) + 1
	var after := level(r, job)
	if after > before:
		_toast("%s is now level %d at %s." % [r.name, after, Defs.JOB_NAMES[job]], r.id)
		rev += 1


## How much faster a resident works at a job: 15% per level above 1 up to level 5, then a little
## less with every level, so the speed climbs towards a ceiling instead of running away.
static func skill_speed(r: Dictionary, job: String) -> float:
	var lv := level(r, job)
	var speed := 1.0 + Tuning.SKILL_SPEED * (mini(lv, Tuning.SKILL_CORE) - 1)
	if lv > Tuning.SKILL_CORE:
		speed += Tuning.SKILL_TAIL_SPEED * (1.0 - pow(Tuning.SKILL_TAIL_DECAY, lv - Tuning.SKILL_CORE)) / (1.0 - Tuning.SKILL_TAIL_DECAY)
	return speed


## The milestones past the core: one at level 10, another at 15, and so on.
static func tail_steps(lv: int) -> int:
	return lv / Tuning.SKILL_TAIL_STEP - 1 if lv >= 2 * Tuning.SKILL_TAIL_STEP else 0


## +1 at level 3 and +1 more at level 5, then +1 at every milestone from level 10: extra logs,
## cobblestone, wheat, and carry capacity.
static func skill_bonus(r: Dictionary, job: String) -> int:
	var lv := level(r, job)
	return (1 if lv >= 3 else 0) + (1 if lv >= 5 else 0) + tail_steps(lv)


## Items one trip can carry, with the Haul skill's bonus.
static func carry_cap(r: Dictionary) -> int:
	return Tuning.CARRY + skill_bonus(r, "haul")


## A recipe's inputs and outputs as this resident makes it: a level-4 cook bakes bread from 2
## wheat, a level-4 crafter gets 5 planks from a log, and a level-4 lumberjack saws 6 (issue #178).
static func recipe_for(r: Dictionary, rec: Dictionary) -> Dictionary:
	var out := rec.duplicate(true)
	if r.is_empty():
		return out
	if rec.id == "bread" and level(r, "cook") >= 4:
		out.inp.wheat = 2
	if rec.id == "planks" and level(r, "craft") >= 4:
		out.out.plank = 5
	if rec.id == "saw_planks" and level(r, "lumber") >= 4:
		out.out.plank = 6
	return out


func resident(id: int) -> Dictionary:
	for r in residents:
		if r.id == id:
			return r
	return {}


## A building on any map (each has the `map` it's on).
func site(id: int) -> Dictionary:
	for mp in maps.values():
		for s in mp.sites:
			if s.id == id:
				return s
	return {}


# ---------------------------------------------------------------- grid and paths

func in_bounds(c: Vector2i) -> bool:
	return m.in_bounds(c)


func _recompute_occ() -> void:
	var occ := m.occ
	occ.fill(0)
	for c in m.rock:
		occ[c.y * m.w + c.x] = 1
	for c in m.fences:
		occ[c.y * m.w + c.x] = 1
	if m.kind != "route":  # a pond or an underground stream is gone around; only the road's stream is forded
		for c in m.water:
			occ[c.y * m.w + c.x] = 1
	for t in m.trees:
		if t.alive:
			occ[t.cell.y * m.w + t.cell.x] = 1
	for b in m.boulders:
		if b.alive:
			occ[b.cell.y * m.w + b.cell.x] = 1
	for s in m.sites:
		if site_blocks(s):
			for c in site_cells(s):
				occ[c.y * m.w + c.x] = 1
	m.occ = occ
	m.occ_dirty = false


func walkable(c: Vector2i) -> bool:
	if not m.in_bounds(c):
		return false
	if m.occ_dirty:
		_recompute_occ()
	return m.occ[c.y * m.w + c.x] == 0


## Breadth-first path from `start` to the nearest cell in `goals` (a set: Vector2i -> true).
## Returns the cells to walk, excluding the start, or null when no goal can be reached.
func find_path(start: Vector2i, goals: Dictionary):
	if goals.has(start):
		return []
	if not m.wear.is_empty() or not m.heat().is_empty():
		return _find_path_weighted(start, goals)
	var prev := {start: start}
	var queue: Array = [start]
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		for d in DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not walkable(n):
				continue
			prev[n] = c
			if goals.has(n):
				var path: Array = []
				var p := n
				while p != start:
					path.push_front(p)
					p = prev[p]
				return path
			queue.append(n)
	return null


## The same, once the village has worn paths (issue #196): the quickest path, each step costing the time
## to cross the cell, so a path that's a little longer but quicker is chosen and busy routes reinforce
## themselves. A step costs 100 on grass and a little less on a path, so this is Dial's algorithm: buckets
## by cost, which is much cheaper than a heap and keeps the tick fast.
func _find_path_weighted(start: Vector2i, goals: Dictionary):
	if m.occ_dirty:
		_recompute_occ()
	var w := m.w
	var size := w * m.h
	var dist := PackedInt32Array()
	dist.resize(size)
	dist.fill(1 << 30)
	var prev := PackedInt32Array()
	prev.resize(size)
	var cost_by_stage := [100, 100, roundi(100.0 / Tuning.PATH_SPEED_DIRT), roundi(100.0 / Tuning.PATH_SPEED_PACKED)]
	var heat := m.heat()  # the way round lava and fire is dearer (issue #149)
	var span := maxi(101, Tuning.HEAT_STEP_COST + 1)
	var si := start.y * w + start.x
	dist[si] = 0
	prev[si] = si
	var buckets: Array = []
	for i in span:
		buckets.append([])
	buckets[0].append(si)
	var pending := 1
	var d := 0
	while pending > 0:
		var b: Array = buckets[d % span]
		if b.is_empty():
			d += 1
			continue
		buckets[d % span] = []
		pending -= b.size()
		for ci in b:
			if dist[ci] != d:
				continue  # a quicker way here was found since
			var cx: int = ci % w
			var cy: int = ci / w
			if goals.has(Vector2i(cx, cy)):
				var path: Array = []
				var p: int = ci
				while p != si:
					path.push_front(Vector2i(p % w, p / w))
					p = prev[p]
				return path
			for dir in DIRS:
				var nx: int = cx + dir.x
				var ny: int = cy + dir.y
				if nx < 0 or ny < 0 or nx >= w or ny >= m.h:
					continue
				var ni := ny * w + nx
				if m.occ[ni] != 0:
					continue
				var nd: int = d + (Tuning.HEAT_STEP_COST if heat.has(Vector2i(nx, ny)) else cost_by_stage[wear_stage(m.wear.get(Vector2i(nx, ny), 0))])
				if nd < dist[ni]:
					dist[ni] = nd
					prev[ni] = ci
					buckets[nd % span].append(ni)
					pending += 1
	return null


func cell_set(cells: Array) -> Dictionary:
	var s := {}
	for c in cells:
		if walkable(c):
			s[c] = true
	return s


func adj_set(cells: Array) -> Dictionary:
	var inside := {}
	for c in cells:
		inside[c] = true
	var s := {}
	for c in cells:
		for d in DIRS:
			var n: Vector2i = c + d
			if walkable(n) and not inside.has(n):
				s[n] = true
	return s


## The nearest walkable cell to `c`, searching outward (used to nudge things off new buildings).
func nearest_walkable(c: Vector2i):
	var seen := {c: true}
	var queue: Array = [c]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		if walkable(cur):
			return cur
		for d in DIRS:
			var n: Vector2i = cur + d
			if in_bounds(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return null


static func rcell(r: Dictionary) -> Vector2i:
	return Vector2i(roundi(r.pos.x), roundi(r.pos.y))


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## The entity in `list` (each with a "cell") closest to `c`.
static func nearest(list: Array, c: Vector2i):
	var best = null
	var bd := 1 << 30
	for o in list:
		var d := manhattan(o.at if o.has("at") else o.cell, c)  # a chest slot's stack is reached at its door (issue #189)
		if d < bd:
			bd = d
			best = o
	return best


# ---------------------------------------------------------------- items

## Uses a new tool of this type has.
static func full_uses(type: String) -> int:
	if Defs.ITEMS[type].has("uses"):  # a flint and steel (issue #146), an iron sword or chestplate (#150)
		return Defs.ITEMS[type].uses
	if Defs.is_armor(type):
		return Tuning.ARMOR_USES
	return Tuning.DURABILITY[Defs.ITEMS[type].tier]


## Places items on or near `c`, filling the cell and spreading outward over walkable cells.
## A tool keeps `uses` (its remaining uses); -1 means a new tool.
func drop_items(c: Vector2i, type: String, n: int, uses := -1) -> void:
	if _occ_dirty:
		_recompute_occ()
	var cap := Defs.stack_cap(type)
	var clearing := _clearing_cells()  # never onto a blueprint's footprint (issue #205)
	var seen := {c: true}
	var queue: Array = [c]
	var qi := 0
	while n > 0 and qi < queue.size() and qi < 400:
		var cur: Vector2i = queue[qi]
		qi += 1
		if walkable(cur) and not clearing.has(cur):
			var s = m.items.get(cur)
			if s == null:
				var put := mini(n, cap)
				m.items[cur] = {"cell": cur, "type": type, "n": put, "res": 0}
				if Defs.wears(type):
					m.items[cur].dur = full_uses(type) if uses < 0 else uses
				n -= put
			elif s.type == type and s.n < cap:
				var a := mini(n, cap - s.n)
				s.n += a
				n -= a
		for d in DIRS:
			var nc: Vector2i = cur + d
			if in_bounds(nc) and not seen.has(nc) and walkable(nc):
				seen[nc] = true
				queue.append(nc)
	rev += 1


func stacks_where(pred: Callable) -> Array:
	var out: Array = []
	for k in m.items:
		if pred.call(m.items[k]):
			out.append(m.items[k])
	return out


static func avail(s: Dictionary) -> int:
	return s.n - s.res


## Unreserved items of a type anywhere on the map.
func free_count(type: String) -> int:
	var n := 0
	for k in m.items:
		var s: Dictionary = m.items[k]
		if s.type == type:
			n += avail(s)
	return n


func tool_items(kind: String, min_tier: int) -> Array:
	return stacks_where(func(s): return Defs.ITEMS[s.type].get("tool", "") == kind and Defs.ITEMS[s.type].tier > min_tier and avail(s) > 0)


func in_zone(c: Vector2i) -> bool:
	return m.zone.has(c)


# ---------------------------------------------------------------- sites

func site_cells(s: Dictionary) -> Array:
	var out: Array = []
	for x in range(s.origin.x, s.origin.x + s.size.x):
		for y in range(s.origin.y, s.origin.y + s.size.y):
			out.append(Vector2i(x, y))
	return out


func site_blocks(s: Dictionary) -> bool:
	if Defs.TEMPLATES[s.tpl].get("walk", false):  # the bridge and track are walked over
		return false
	return s.done or (s.tpl == "house" and s.stage >= 1)


func site_at(c: Vector2i):
	for s in m.sites:
		if Rect2i(s.origin, s.size).has_point(c):
			return s
	return null


## Job buildings with a crafting queue: the bench and the fireplace.
static func is_station(s: Dictionary) -> bool:
	return Defs.TEMPLATES[s.tpl].get("station", false)


## The 3×3 a job building reserves to grow into (spec §8), with the building in the middle of its
## back wall. `rot` turns which side the plot opens toward. Null for buildings that don't grow.
static func plot_rect(tpl: String, origin: Vector2i, rot: int):
	if not Defs.TEMPLATES[tpl].has("plot"):
		return null
	if tpl == "portal":  # the frame, and two rows of staging area in front (issue #147)
		return Rect2i(origin + Vector2i(-1, 0), Vector2i(6, 3))
	if Defs.TEMPLATES[tpl].size == Vector2i(3, 3):  # the storehouse grows back from its door (issue #189)
		match rot % 4:
			0: return Rect2i(origin + Vector2i(0, -2), Vector2i(3, 5))
			1: return Rect2i(origin + Vector2i(-2, 0), Vector2i(5, 3))
			2: return Rect2i(origin, Vector2i(3, 5))
			_: return Rect2i(origin, Vector2i(5, 3))
	match rot % 4:
		0: return Rect2i(origin + Vector2i(-1, 0), Vector2i(3, 3))
		1: return Rect2i(origin + Vector2i(-2, -1), Vector2i(3, 3))
		2: return Rect2i(origin + Vector2i(-1, -2), Vector2i(3, 3))
		_: return Rect2i(origin + Vector2i(0, -1), Vector2i(3, 3))


## The site whose reserved plot covers `c` (not counting its own footprint), or null.
func reserved_at(c: Vector2i):
	for s in m.sites:
		var p = s.get("plot")
		if p != null and p.has_point(c) and not Rect2i(s.origin, s.size).has_point(c):
			return s
	return null


func current_stage(s: Dictionary) -> Dictionary:
	if s.get("upgrading", false):
		return {"name": "Mineshaft", "verb": "needs", "cost": Tuning.SHAFT_COST}
	return Defs.TEMPLATES[s.tpl].stages[s.stage]


func door_cell(origin: Vector2i, rot: int) -> Vector2i:
	match rot % 4:
		0: return origin + Vector2i(2, 4)
		1: return origin + Vector2i(4, 2)
		2: return origin + Vector2i(2, 0)
		_: return origin + Vector2i(0, 2)


## What's on a rect that a building put there has to clear (issue #205): trees and boulders to fell
## or break, and the debris: loose stacks and berry bushes.
func obstacles_in(rect: Rect2i) -> Dictionary:
	var out := {"trees": [], "boulders": [], "items": [], "bushes": []}
	for t in m.trees:
		if t.alive and rect.has_point(t.cell):
			out.trees.append(t)
	for b in m.boulders:
		if b.alive and rect.has_point(b.cell):
			out.boulders.append(b)
	if rect.get_area() <= m.items.size():
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				var it = m.items.get(Vector2i(x, y))
				if it != null:
					out.items.append(it)
	else:
		for k in m.items:
			if rect.has_point(k):
				out.items.append(m.items[k])
	for b in m.bushes:
		if rect.has_point(b.cell):
			out.bushes.append(b)
	return out


func site_obstacles(s: Dictionary) -> Dictionary:
	return obstacles_in(Rect2i(s.origin, s.size))


## Whether a blueprint's footprint is clear of trees, boulders and debris, so building can start.
func footprint_clear(s: Dictionary) -> bool:
	var o := site_obstacles(s)
	return o.trees.is_empty() and o.boulders.is_empty() and o.items.is_empty() and o.bushes.is_empty()


## "2 trees, 6 logs and a bush": what's in the way, for the placement hint and the blueprint's panel.
static func clearing_text(o: Dictionary) -> String:
	var parts: PackedStringArray = []
	var t: int = o.trees.size()
	var b: int = o.boulders.size()
	if t:
		parts.append("%d %s" % [t, "tree" if t == 1 else "trees"])
	if b:
		parts.append("%d %s" % [b, "boulder" if b == 1 else "boulders"])
	parts.append_array(stacks_text(o.get("items", [])))
	var bushes: int = o.get("bushes", []).size()
	if bushes:
		parts.append("a bush" if bushes == 1 else "%d bushes" % bushes)
	if parts.size() < 2:
		return "".join(parts)
	return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[-1]


## "6 logs", "3 wool": what the loose stacks add up to, a line a kind.
static func stacks_text(stacks: Array) -> PackedStringArray:
	var totals := {}
	for st in stacks:
		totals[st.type] = totals.get(st.type, 0) + st.n
	var out: PackedStringArray = []
	for k in totals:
		out.append(Defs.words(k, totals[k]))
	return out


## The cells of every unfinished blueprint on this map. Nothing is set down on them (issue #205): they're
## being cleared, and what lies there is carried off before building starts.
func _clearing_cells() -> Dictionary:
	var out := {}
	for s in m.sites:
		if not s.done:
			for c in site_cells(s):
				out[c] = true
	return out


func _mark_obstacles(s: Dictionary) -> void:
	var o := site_obstacles(s)
	for b in o.bushes:  # a bush on the footprint is dug up; its berries are carried off with the rest (issue #205)
		m.bushes.erase(b)
		if b.berries > 0:
			drop_items(b.cell, "berries", b.berries)
	for t in o.trees + o.boulders:
		if not grown(t):  # a sapling in the way is lifted, not felled (issue #177)
			t.alive = false
			_occ_dirty = true
			drop_items(t.cell, "sapling", 1)
			continue
		if not t.des:
			t.des = true
			t.unreach_until = 0
			rev += 1


static func has_all(store: Dictionary, need: Dictionary) -> bool:
	for k in need:
		if store.get(k, 0) < need[k]:
			return false
	return true


## The first queued recipe whose inputs exist somewhere. Blocked recipes are skipped (spec §6).
## `jobs`, when given, limits it to recipes of those jobs.
func bench_active(b: Dictionary, jobs := []) -> int:
	for i in b.queue.size():
		if not jobs.is_empty() and not jobs.has(recipe_job(Defs.recipe(b.queue[i]))):
			continue
		var inp: Dictionary = Defs.recipe(b.queue[i]).inp
		var ok := true
		for k in inp:
			if b.store.get(k, 0) + b.incoming.get(k, 0) + free_count(k) < inp[k]:
				ok = false
				break
		if ok:
			return i
	return -1


## A queued recipe whose inputs are already at the bench, or {}.
func bench_craftable(b: Dictionary, jobs := []) -> Dictionary:
	for id in b.queue:
		var rec := Defs.recipe(id)
		if not jobs.is_empty() and not jobs.has(recipe_job(rec)):
			continue
		if has_all(b.store, rec.inp):
			return rec
	return {}


## Materials a site (or a finished bench's active recipe) still needs delivered.
func stage_needs(s: Dictionary, jobs := []) -> Dictionary:
	var cost := {}
	if s.done:
		var ai := bench_active(s, jobs)
		if ai >= 0:
			cost = Defs.recipe(s.queue[ai]).inp
	elif s.tpl == "track":  # rails still to lay (issue #122)
		cost = {"rail": Tuning.RAILS_PER_SEGMENT - s.get("laid", 0)}
	else:
		cost = current_stage(s).cost
	var out := {}
	for k in cost:
		var r: int = cost[k] - s.store.get(k, 0) - s.incoming.get(k, 0)
		if r > 0:
			out[k] = r
	return out


func _complete_stage(s: Dictionary) -> void:
	var st := current_stage(s)
	for k in st.cost:
		s.store[k] -= st.cost[k]
	if s.get("upgrading", false):  # the bench has become a mineshaft (issue #204)
		s.upgrading = false
		s.shaft = true
		s.stage = Defs.TEMPLATES[s.tpl].stages.size()
		s.done = true
		s.store = {}
		s.incoming = {}
		_occ_dirty = true
		rev += 1
		_on_site_done(s)
		return
	s.stage += 1
	_occ_dirty = true
	rev += 1
	if s.stage >= Defs.TEMPLATES[s.tpl].stages.size():
		s.done = true
		s.store = {}
		s.incoming = {}
		_on_site_done(s)
	if site_blocks(s):
		_clear_footprint(s)


## Moves items, stockpile cells and residents off a footprint that has just become solid.
func _clear_footprint(s: Dictionary) -> void:
	_recompute_occ()
	for c in site_cells(s):
		m.zone.erase(c)  # nothing is left lying here to move: the footprint was cleared before building started (issue #205)
	for r in residents + sheep:
		var c := rcell(r)
		if Rect2i(s.origin, s.size).has_point(c):
			var p = nearest_walkable(c)
			if p != null:
				r.pos = Vector2(p)
				if r.kind == "animal":
					r.cell = p
					r.dest = null
				else:
					r.path = []


func _on_site_done(s: Dictionary) -> void:
	assign_workstations()
	if s.tpl == "claim_stakes":  # the strip joins the village between ticks (issue #187), with its own toast
		return
	if not stats.has("built"):
		stats.built = {}
	stats.built[s.tpl] = true  # for the founding goals (issue #182)
	if s.tpl in ["toolsmith_bench", "composter", "lodge", "builder_table"]:
		var job: String = Defs.JOB_STATIONS.find_key(s.tpl)
		var who := resident(s.get("worker", 0))
		_toast("The %s is ready. %s" % [Defs.TEMPLATES[s.tpl].name.to_lower(),
			"%s works from it as the %s." % [who.name, Defs.JOB_SKILLED[job]] if not who.is_empty() else "A %s can work from it." % Defs.JOB_SKILLED[job]], 0, s.id)
		return
	if s.tpl == "bench":
		_toast("The crafting bench is ready. Select it to queue crafts.", 0, s.id)
		return
	if s.tpl == "fireplace":
		_toast("The fireplace is lit. It keeps %d meals in stock when there's wheat or mutton." % Tuning.MEAL_STOCK, 0, s.id)
		return
	if s.get("shaft", false):
		_toast("The mineshaft is dug. Stonemasons dig cobblestone from it, slowly, until the village has %d." % s.keep, 0, s.id)
		return
	if not work_of(s).is_empty():
		var wk := work_of(s)
		_toast("The %s is ready. %ss %s in its area on their own, until the village has %d %s. Select it to paint the area." % [
			Defs.TEMPLATES[s.tpl].name.to_lower(), Defs.JOB_NAMES[wk.job], "fell trees" if wk.kind == "tree" else "break boulders",
			s.keep, Defs.ITEMS[wk.item].many], 0, s.id)
		return
	if s.tpl == "bridge":
		_toast("The bridge over the stream is built: no more wading, and track can cross.", 0, s.id)
		return
	if s.tpl == "station":
		_toast("The station at the %s end of the line is built." % s.end, 0, s.id)
		return
	if is_device(s):  # issue #170
		_toast("The %s is built. Wire it to another device from its panel." % Defs.TEMPLATES[s.tpl].name.to_lower(), 0, s.id)
		return
	if s.tpl == "portal_station":  # issue #168
		_toast("The portal station is built. A Build party lays the Nether side of the line.", 0, s.id)
		return
	if s.tpl == "track":
		if line_complete():
			_toast("The line to the mine is complete.", 0, s.id)
		else:
			_toast("Track is laid along %s." % Road.SEGMENTS[s.seg].name.to_lower(), 0, s.id)
		return
	if s.tpl == "storehouse":  # issue #189
		_toast("The storehouse is built. Craft a chest at the bench (%s): a hauler carries it in, and it holds %d stacks of anything." % [Defs.cost_text({"plank": 8}), Tuning.CHEST_STACKS], 0, s.id)
		return
	if s.tpl == "portal":  # issue #147
		_toast("The portal frame is built. It needs flint and steel to light.", 0, s.id)
		return
	if s.tpl == "enchanting_workshop":  # issue #165
		_toast("The enchanting workshop is built. An Enchanter carries enchanted books to it, and it learns their recipes for good.", 0, s.id)
		return
	if s.tpl == "board":  # it has word of the old mine and the meadow, which the map switcher now shows (issues #105, #136)
		maps[OldMine.ID].known = true
		road().known = true
		maps[Meadow.ID].known = true
		maps[MeadowRoad.ID].known = true
		_toast("The expedition board is up, with word of some old caves to the east and a meadow to the west. Select it to plan an adventure.", 0, s.id)
		return
	if s.tpl != "house":  # only a house is a home: anything else without its own case above does nothing more
		return
	stats.houses += 1
	var ada: Dictionary = residents[0]
	var ada_home := false
	for o in m.sites:
		if o.owner == ada.id:
			ada_home = true
	if not ada_home:
		s.owner = ada.id
		_toast("Ada’s house is finished.", 0, s.id)
	else:
		_toast("The house is finished, bed and all. Someone may come to live in it.", 0, s.id)


# ---------------------------------------------------------------- bench queue

func queue_add(b: Dictionary, recipe_id: String, auto := false, at := -1) -> void:
	if b.map != map_id:
		on_map(b.map, queue_add.bind(b, recipe_id, auto, at))
		return
	var i: int = b.queue.size() if at < 0 else at
	b.queue.insert(i, recipe_id)
	b.autoq.insert(i, auto)
	if auto_craft:
		expand_queues()


func queue_remove(b: Dictionary, i: int) -> void:
	if b.map != map_id:
		on_map(b.map, queue_remove.bind(b, i))
		return
	if i < 0 or i >= b.queue.size():
		return
	b.queue.remove_at(i)
	b.autoq.remove_at(i)
	if b.queue.is_empty():
		for r in residents:
			if r.job != null and is_same(r.job.target, b):
				fail_job(r)
		for k in b.store:
			if b.store[k] > 0:
				drop_items(b.origin + Vector2i(0, 1), k, b.store[k])
		b.store = {}


## Once unlocked, a queued recipe short of a bench-made ingredient gets that recipe queued ahead
## of it, repeatedly, so a pickaxe expands into sticks and the sticks into planks (spec §6).
func expand_queues() -> void:
	for b in m.sites:
		if not (b.done and is_station(b)) or b.queue.is_empty():
			continue
		for _guard in 12:
			if b.queue.size() >= 30:
				break
			var inserted := false
			for i in b.queue.size():
				var inp: Dictionary = Defs.recipe(b.queue[i]).inp
				for k in inp:
					var p := Defs.producer(k, b.tpl)
					if p.is_empty():
						continue
					var short: int = inp[k] - b.store.get(k, 0) - b.incoming.get(k, 0) - free_count(k)
					for j in i:
						short -= Defs.recipe(b.queue[j]).out.get(k, 0)
					if short <= 0:
						continue
					for _n in ceili(float(short) / p.out[k]):
						b.queue.insert(i, p.id)
						b.autoq.insert(i, true)
					inserted = true
					break
				if inserted:
					break
			if not inserted:
				break


const TOOL_NAMES := {"axe": "axe", "pick": "pickaxe"}


## Whether a resident's job is Toolsmith. Ada doesn't count: spares need a toolsmith of their own (issue #134).
func has_toolsmith() -> bool:
	return residents.any(func(r): return r.role == "toolsmith" and not claimed(r).is_empty())


## Whether a "(toolsmith)" entry for this tool kind is queued at any bench.
## Whether a guard needs a sword and has none to hand, for the planner (issue #150).
func needs_sword(r: Dictionary) -> bool:
	return r.role == "guard" and r.sword == null


## Warnings about a plan that don't stop it (issue #150): "No sword for Bram".
func plan_warnings(plan: Dictionary) -> Array:
	var out: Array = []
	for id in plan.party:
		var r := resident(id)
		if not r.is_empty() and needs_sword(r) and tool_items("sword", 0).is_empty():
			out.append("No sword for %s" % r.name)
	if plan.get("objective", "") == "fortress" and not plan.party.any(func(id): return resident(id).get("role", "") in ["guard", "all"]):
		out.append("No guard in the party: a fortress has blazes and skeletons")  # issue #157
	return out


func _spare_queued(kind: String) -> bool:
	for b in m.sites:
		if b.done and b.tpl == "bench":
			for i in b.queue.size():
				if str(b.autoq[i]) == "toolsmith" and Defs.ITEMS[Defs.recipe(b.queue[i]).out.keys()[0]].tool == kind:
					return true
	return false


## The toolsmith's standing order (spec §6): while a resident is the Toolsmith, keep one spare of each
## tool kind someone uses, of the best tier the bench can make from what's on hand: iron, then stone,
## then wood. Queued as
## "(toolsmith)" entries at the first finished bench, one per kind at a time.
func keep_tools_stocked() -> void:
	if not has_toolsmith():
		return
	var bench = null
	for b in m.sites:
		if b.done and b.tpl == "bench":
			bench = b
			break
	if bench == null:
		return
	if residents.any(func(r): return r.role == "guard" and (r.sword != null or r.broken.sword)) and tool_items("sword", 0).is_empty() and not bench.queue.has("iron_sword") and free_count("iron_ingot") >= Defs.recipe("iron_sword").inp.iron_ingot and free_count("stick") >= 1:
		bench.queue.append("iron_sword")  # a spare sword, like a spare tool (issue #150)
		bench.autoq.append("toolsmith")
		if auto_craft:
			expand_queues()
	for kind in ["axe", "pick"]:
		var used := residents.any(func(r): return r[kind] != null or r.broken[kind])
		if not used or not tool_items(kind, 0).is_empty() or _spare_queued(kind):
			continue
		var id: String = "wood_" + kind
		for tier in ["diamond_", "iron_", "stone_"]:  # the best tier there's material for (issues #104, #186)
			var rec := Defs.recipe(tier + kind)
			var mat: String = rec.inp.keys()[0]
			var have: int = free_count(mat)
			for b in m.sites:
				have += b.store.get(mat, 0) if b.done and b.tpl == "bench" else 0
			if have >= rec.inp[mat]:
				id = rec.id
				break
		bench.queue.append(id)
		bench.autoq.append("toolsmith")
		if auto_craft:
			expand_queues()


## The fireplace's standing order (spec §4): while stored meals are fewer than MEAL_STOCK, queue
## one meal whose inputs exist, bread first. One at a time, so it never queues what it can't make.
func keep_meals_stocked() -> void:
	var meals := -1  # counted once a fireplace needs it: every claim asks, with or without one
	for f in m.sites:
		if not (f.done and f.tpl == "fireplace" and f.get("keep_meals", true)):
			continue
		if meals < 0:
			meals = 0
			for meal in Defs.MEALS:
				meals += free_count(meal)
		if f.autoq.has(true):
			meals += 1  # already making one
			continue
		if meals >= Tuning.MEAL_STOCK:
			continue
		for id in Defs.MEALS.map(func(meal): return Defs.producer(meal, "fireplace").id):
			var inp: Dictionary = Defs.recipe(id).inp
			var ok := true
			for k in inp:
				if f.store.get(k, 0) + f.incoming.get(k, 0) + free_count(k) < inp[k]:
					ok = false
			if ok:
				f.queue.append(id)
				f.autoq.append(true)
				meals += 1
				break


## The workstations' standing orders (issue #178): while the village has fewer planks (or stone bricks)
## than a chopping block's (or mason's bench's) target, queue one batch whose inputs are on hand. One
## at a time, like the fireplace's meals.
func keep_made_stocked() -> void:
	for s in m.sites:
		if not s.done or s.get("make_keep", 0) <= 0 or s.autoq.has(true):
			continue
		var rec := Defs.recipe(Defs.TEMPLATES[s.tpl].get("makes", ""))
		if rec.is_empty() or free_count(rec.out.keys()[0]) >= s.make_keep:
			continue
		var ok := true
		for k in rec.inp:
			if s.store.get(k, 0) + s.incoming.get(k, 0) + free_count(k) < rec.inp[k]:
				ok = false
		if ok:
			s.queue.append(rec.id)
			s.autoq.append(true)


## Sets a workstation's standing order target (issue #178); 0 turns it off.
func set_make_keep(s: Dictionary, n: int) -> void:
	s.make_keep = maxi(0, n)
	rev += 1


# ---------------------------------------------------------------- storehouses (issue #189)

## Whether a stack's key is a chest slot in a storehouse rather than a cell on the map. Slots are
## keyed off the map, at (-1 - slot, -the storehouse's id), so nothing else mistakes them for ground.
static func in_store(c: Vector2i) -> bool:
	return c.x < 0


## The storehouse a chest slot belongs to, or {}.
func store_of(c: Vector2i) -> Dictionary:
	return site(-c.y)


## The cell in front of a storehouse's door, where residents put things in and take them out.
static func store_door(s: Dictionary) -> Vector2i:
	match s.rot % 4:
		0: return s.origin + Vector2i(1, 3)
		1: return s.origin + Vector2i(3, 1)
		2: return s.origin + Vector2i(1, -1)
		_: return s.origin + Vector2i(-1, 1)


## A storehouse's chest slots: CHEST_STACKS for each chest carried in.
static func store_slots(s: Dictionary) -> Array:
	var out: Array = []
	for i in s.get("chests", 0) * Tuning.CHEST_STACKS:
		out.append(Vector2i(-1 - i, -s.id))
	return out


## Where a resident stands to reach a stack: its storehouse's door for a chest slot, else its cell.
func reach(c: Vector2i) -> Array:
	if in_store(c):
		var s := store_of(c)
		if not s.is_empty():
			return [store_door(s)]
	return [c]


## The nearest storehouse to `c` with room for `type`, as {site, cell (a chest slot), room}, or null.
## A chest isn't stored in a chest: it's set in place.
func store_dest(type: String, c: Vector2i):
	if type == "chest":
		return null
	var cap := Defs.stack_cap(type)
	var best = null
	var bd := 1 << 30
	for s in m.sites:
		if s.tpl != "storehouse" or not s.done or s.get("chests", 0) == 0:
			continue
		var door := store_door(s)
		var d := manhattan(door, c)
		if d >= bd or not walkable(door):
			continue
		var found = null
		var empty = null
		for k in store_slots(s):
			if m.zone_res.has(k):
				continue
			var it = m.items.get(k)
			if it == null:
				if empty == null:
					empty = k
			elif it.type == type and it.n < cap:
				found = {"site": s, "cell": k, "room": cap - it.n}
				break
		if found == null and empty != null:
			found = {"site": s, "cell": empty, "room": cap}
		if found != null:
			best = found
			bd = d
	return best


## Puts carried items into a chest slot.
func _store_put(k: Vector2i, type: String, n: int, uses := -1) -> void:
	var it = m.items.get(k)
	if it == null:
		it = {"cell": k, "type": type, "n": 0, "res": 0, "at": store_door(store_of(k))}
		if Defs.wears(type):
			it.dur = full_uses(type) if uses < 0 else uses
		m.items[k] = it
	it.n += n
	rev += 1


## Chests carried into a storehouse are set in place.
func _set_chests() -> void:
	for s in m.sites:
		if s.tpl == "storehouse" and s.done and s.store.get("chest", 0) > 0:
			s.chests = mini(Tuning.CHESTS, s.get("chests", 0) + s.store.chest)
			s.store.chest = 0
			rev += 1


## A hauler's job carrying a chest into the nearest storehouse with room for one, or null.
func _chest_job(r: Dictionary, c: Vector2i):
	var want := m.sites.filter(func(s): return s.tpl == "storehouse" and s.done and not _cooling(s) and s.get("chests", 0) + s.store.get("chest", 0) + s.incoming.get("chest", 0) < Tuning.CHESTS)
	if want.is_empty():
		return null
	var chests := stacks_where(func(st): return st.type == "chest" and avail(st) > 0)
	if chests.is_empty():
		return null
	return _deliver_job(_nearest_site(want, c), "chest", 1, nearest(chests, c))


# ---------------------------------------------------------------- land claims (issue #187)

## Claims made so far: strips added to the village. Saved.
var claims_made := 0
var last_plans := {}                ## Destination -> the plan last packed for it, for "Repeat last trip" (issue #301).
var cargo_lists := {}               ## Destination -> its last cargo priority list, for the next plan to start from (issue #185).


## Boundary stakes still going in or standing ready to apply: they count against the claims available.
func claims_pending() -> int:
	return maps.village.sites.filter(func(s): return s.tpl == "claim_stakes").size()


## Land claims the village has earned and not used: one for every CLAIM_EVERY residents beyond the
## founding pair. Worked out from the residents, so an older save with a big village has them too.
func claims_available() -> int:
	return maxi(0, (residents.size() - 2) / Tuning.CLAIM_EVERY - claims_made - claims_pending())


## The residents the village needs for its next claim.
func claim_threshold() -> int:
	return 2 + (claims_made + claims_pending() + 1) * Tuning.CLAIM_EVERY


## Where the stakes for a claim on `edge` would go: the nearest open cell to the middle of that
## edge, or (-1, -1) when there's none within a few cells.
func claim_cell(edge: String) -> Vector2i:
	var v: SimMap = maps.village
	var mid := Vector2i(v.w / 2, v.h / 2)
	for d in 6:
		var c: Vector2i
		match edge:
			"north": c = Vector2i(mid.x, d)
			"south": c = Vector2i(mid.x, v.h - 1 - d)
			"west": c = Vector2i(d, mid.y)
			_: c = Vector2i(v.w - 1 - d, mid.y)
		if on_map("village", _stake_ok.bind(c)):
			return c
	return Vector2i(-1, -1)


func _stake_ok(c: Vector2i) -> bool:
	if placement_check("claim_stakes", c) != "" or not walkable(c) or m.items.has(c) or m.zone.has(c) or m.farm.has(c):
		return false
	var o := obstacles_in(Rect2i(c, Vector2i.ONE))
	return o.trees.is_empty() and o.boulders.is_empty()


## Why a claim on `edge` can't be made now, or "".
func claim_check(edge: String) -> String:
	var v: SimMap = maps.village
	if claims_available() <= 0:
		return "A claim is already staked" if claims_pending() > 0 else "The next land claim needs %d residents" % claim_threshold()
	if not Claims.fits(edge, v.w, v.h):
		return "The village is at its largest (%d cells a side)" % Tuning.MAP_MAX
	if claim_cell(edge) == Vector2i(-1, -1):
		return "No open ground for the stakes on that edge"
	return ""


## Stakes out a strip on `edge`: a small blueprint a builder finishes with a few sticks, after which
## the strip joins the village. Returns why it can't be, or "".
func place_claim(edge: String) -> String:
	var why := claim_check(edge)
	if why != "":
		return why
	on_map("village", func():
		var s := place_site("claim_stakes", claim_cell(edge))
		s.edge = edge)
	return ""


## Applies any finished boundary stakes. Between ticks, so no job is part-way through a step.
func _apply_claims() -> void:
	for s in maps.village.sites.filter(func(x): return x.tpl == "claim_stakes" and x.done):
		on_map("village", expand_village.bind(s))


## Adds the strip a finished set of stakes marks to the village, in one pass. A north or west claim
## moves the origin, so everything on the map moves with it (`SimMap.shift`), and the residents
## with it; their jobs end first, and are claimed again on the next tick. Sends a "map_grew" event
## carrying the shift, for the camera.
func expand_village(stakes: Dictionary) -> void:
	var edge: String = stakes.edge
	var vm: SimMap = maps.village
	vm.sites.erase(stakes)
	for r in residents:
		if r.map == "village":
			if r.arriving:  # a traveler still walking in: his walk is planned again below, as on loading
				r.job = null
				r.path = []
			else:
				fail_job(r)
			r.direct = null
	var signs := [meadow_sign(), route_sign()]  # where the signposts stand in the land, before it grows
	var strip := Claims.strip(edge, vm.w, vm.h)
	var lane := Rect2i()
	if edge in ["east", "west"]:  # the way out to the signpost stays clear
		lane = Rect2i(strip.position.x, vm.h / 2 - 1, strip.size.x, 3)
	var land := Claims.generate(seed, claims_made, strip, lane)
	var off := vm.grow(edge, Tuning.CLAIM_DEPTH)
	for r in residents:
		if r.map == "village":
			r.pos += Vector2(off)
			r.path = []
			for o in r.orders:
				if o.kind == "move":
					o.cell += off
	for r in residents:
		if r.map == "village" and r.arriving:
			walk_in(r)
	_plant_claims.clear()
	vm.zone_res.clear()
	var i := 0
	for c in land.trees:
		vm.trees.append({"id": _id(), "kind": "tree", "cell": c + off, "logs": 4 + (i * 7) % 3, "alive": true, "des": false, "claim": 0, "unreach_until": 0})
		i += 1
	for c in land.boulders:
		vm.boulders.append({"id": _id(), "kind": "boulder", "cell": c + off, "alive": true, "des": false, "claim": 0, "unreach_until": 0})
	for c in land.bushes:
		add_bush(c + off)
	for c in land.sheep:
		add_sheep(c + off)
	var now := [meadow_sign(), route_sign()]
	for k in 2:  # a signpost that moved to an edge cell with something there makes room for itself
		if now[k] != signs[k] + off:
			_clear_around(now[k])
	claims_made += 1
	_occ_dirty = true
	rev += 1
	events.append({"type": "map_grew", "shift": off})
	_toast("The village has grown: %d cells of new land to the %s." % [Tuning.CLAIM_DEPTH * (vm.h if edge in ["east", "west"] else vm.w), edge])


## Nothing grows or stands in the way of a signpost.
func _clear_around(c: Vector2i) -> void:
	var near := Rect2i(c - Vector2i.ONE, Vector2i(3, 3))
	m.trees = m.trees.filter(func(t): return not near.has_point(t.cell))
	m.boulders = m.boulders.filter(func(b): return not near.has_point(b.cell))
	m.bushes = m.bushes.filter(func(b): return not near.has_point(b.cell))


# ---------------------------------------------------------------- workstations (issue #177)

## Which job works a tree or a boulder: Lumberjack for trees, Stonemason for boulders and ore.
static func gather_job_of(target: Dictionary) -> String:
	return "lumber" if target.kind == "tree" else "mason"


## A building's name: the mineshaft a mason's bench has become, or is becoming (issue #204).
static func station_name(s: Dictionary) -> String:
	return "Mineshaft" if s.get("shaft", false) or s.get("upgrading", false) else Defs.TEMPLATES[s.tpl].name


## Why a mason's bench can't be upgraded into a mineshaft yet, or "" when it can (issue #204): only once
## every boulder on the village map is gone, and with the stone bricks it takes cut already, since the
## bench is the only place they're cut and it stands idle while it's rebuilt.
func shaft_check(s: Dictionary) -> String:
	if s.tpl != "mason_bench" or not s.done:
		return "Only a finished mason's bench can be dug out"
	if s.get("shaft", false):
		return "It's already a mineshaft"
	if m.kind != "village":
		return "Only in the village"
	var left := m.boulders.filter(func(b): return b.alive).size()
	if left > 0:
		return "Not while boulders are left on the map (%d)" % left
	var short: int = Tuning.SHAFT_COST.stone_brick - free_count("stone_brick")
	if short > 0:
		return "Cut %d more stone bricks at the bench first" % short
	return ""


## Starts rebuilding a mason's bench as a mineshaft: it keeps its worker, queue and work area, and builders
## bring the planks and stone bricks like any blueprint's stage. Returns whether it began.
func upgrade_to_shaft(s: Dictionary) -> bool:
	if shaft_check(s) != "":
		return false
	s.upgrading = true
	s.done = false
	s.stage = 0
	s.store = {}
	s.incoming = {}
	s.builder = 0
	_occ_dirty = true
	rev += 1
	return true


## A building's workstation: {job, kind, item}, or {} for a building that isn't one.
static func work_of(s: Dictionary) -> Dictionary:
	return Defs.TEMPLATES[s.tpl].get("work", {})


## Whether `c` is in a workstation's work area: the cells painted for it (issue #203).
static func in_area(s: Dictionary, c: Vector2i) -> bool:
	return s.area.has(c) if s.has("area") else Vector2(c).distance_to(Vector2(s.origin)) <= Tuning.WORK_START_RADIUS


## The workstation of the same kind that owns work-area cell `c`, other than `except`, or {}.
func _area_owner(tpl: String, c: Vector2i, except: Dictionary) -> Dictionary:
	for o in m.sites:
		if o.tpl == tpl and o.has("area") and not is_same(o, except) and o.area.has(c):
			return o
	return {}


## The cells a new workstation starts with (issue #203): the circle around it that it always worked,
## in bounds and not already another of its kind's.
func work_area_start(tpl: String, origin: Vector2i) -> Dictionary:
	var out := {}
	var rr := ceili(Tuning.WORK_START_RADIUS)
	for dx in range(-rr, rr + 1):
		for dy in range(-rr, rr + 1):
			var c := origin + Vector2i(dx, dy)
			if m.in_bounds(c) and Vector2(c).distance_to(Vector2(origin)) <= Tuning.WORK_START_RADIUS and _area_owner(tpl, c, {}).is_empty():
				out[c] = true
	return out


## Paints cells onto a workstation's work area, or erases them (issue #203). A cell belongs to at most one
## workstation of a kind, so painting one another owns moves it here. Cells past WORK_REACH of the
## workstation are left out; returns how many.
func paint_work_area(s: Dictionary, rect: Rect2i, erase := false) -> int:
	if not s.has("area"):
		return 0
	var out_of_reach := 0
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var c := Vector2i(x, y)
			if not m.in_bounds(c):
				continue
			if erase:
				s.area.erase(c)
			elif Vector2(c).distance_to(Vector2(s.origin)) > Tuning.WORK_REACH:
				out_of_reach += 1
			else:
				var o := _area_owner(s.tpl, c, s)
				if not o.is_empty():
					o.area.erase(c)
				s.area[c] = true
	return out_of_reach


## The two cells beside a workstation, inside its plot, where its pile goes.
static func pile_cells(s: Dictionary) -> Array:
	var side: Vector2i = [Vector2i(1, 0), Vector2i(0, 1)][int(s.get("rot", 0)) % 2]
	return [s.origin + side, s.origin - side]


## The finished workstation whose pile is on `c`, or null.
func pile_at(c: Vector2i):
	for s in m.sites:
		if s.done and not work_of(s).is_empty() and pile_cells(s).has(c):
			return s
	return null


## Logs or cobblestone in a workstation's pile.
func pile_count(s: Dictionary) -> int:
	var n := 0
	for c in pile_cells(s):
		var it = m.items.get(c)
		if it != null and it.type == work_of(s).item:
			n += it.n
	return n


## Every finished workstation's pile cells, as cell -> workstation: `pile_at` for many cells at once.
func pile_map() -> Dictionary:
	var out := {}
	for s in m.sites:
		if s.done and not work_of(s).is_empty():
			for c in pile_cells(s):
				if not out.has(c):
					out[c] = s
	return out


## Whether a stack is put away: in a stockpile, or in the pile of a workstation that keeps its type.
## A caller checking many stacks passes `pile_map()`, worked out once.
func stored(st: Dictionary, piles = null) -> bool:
	if in_zone(st.cell) or in_store(st.cell):
		return true
	var ws = pile_at(st.cell) if piles == null else piles.get(st.cell)
	return ws != null and work_of(ws).item == st.type


## The nearest workstation pile to `c` with room for `type`, as {site, cell, room}, or null.
func pile_dest(type: String, c: Vector2i):
	if _occ_dirty:
		_recompute_occ()
	var best = null
	var bd := 1 << 30
	for s in m.sites:
		if not s.done or work_of(s).get("item", "") != type or manhattan(s.origin, c) >= bd:
			continue
		var room: int = Tuning.WORK_STORE - pile_count(s) - s.incoming.get(type, 0)
		if room <= 0:
			continue
		for pc in pile_cells(s):
			var it = m.items.get(pc)
			if m.zone_res.has(pc) or not walkable(pc) or (it != null and (it.type != type or it.n >= Defs.stack_cap(type))):
				continue
			best = {"site": s, "cell": pc, "room": mini(room, Defs.stack_cap(type) - (it.n if it != null else 0))}
			bd = manhattan(s.origin, c)
			break
	return best


## Whether the land at `c` is kept from gatherers' own work and from planting: a building or its
## reserved plot, a stockpile, a farm or a pen, or beside a house's door.
func protected_cell(c: Vector2i) -> bool:
	if site_at(c) != null or reserved_at(c) != null or m.zone.has(c) or m.farm.has(c) or pen_at(c) != null:
		return true
	for s in m.sites:
		if s.tpl == "house":
			var d := door_cell(s.origin, s.rot)
			if absi(c.x - d.x) <= 1 and absi(c.y - d.y) <= 1:
				return true
	return false


## Whether a tree or boulder is kept from gatherers' own work: marked Keep, or on protected land.
func protected(t: Dictionary) -> bool:
	return t.get("keep", false) or protected_cell(t.cell)


## A full-grown tree, or any boulder. A sapling counts up its `grow` seconds; a full tree has none.
static func grown(t: Dictionary) -> bool:
	return t.get("grow", -1.0) < 0.0


## How grown a tree is: 0 a sapling, 1 a young tree, 2 full grown.
static func tree_stage(t: Dictionary) -> int:
	if grown(t):
		return 2
	return 0 if t.grow < Tuning.SAPLING_GROW / 2.0 else 1


## Unmarked trees or boulders gatherers take on their own: grown, not protected, and in the work area
## of one of `stations` whose keep-stock target the village hasn't reached.
func auto_targets(stations: Array) -> Array:
	var out: Array = []
	for s in stations:
		var w := work_of(s)
		if free_count(w.item) >= s.keep:
			continue
		for t in (m.trees if w.kind == "tree" else m.boulders):
			if t.alive and not t.des and t.claim == 0 and grown(t) and not t.get("hidden", false) and not _cooling(t) and in_area(s, t.cell) and not protected(t) and not out.any(func(o): return is_same(o, t)):
				out.append(t)
	return out


## A gatherer's own work at their job's workstations, once nothing marked is left: carry what lies in a
## work area to a pile, plant saplings (lumberjacks), then fell or break the nearest of auto_targets.
func _workstation_job(r: Dictionary, c: Vector2i):
	var job: String = r.role
	var own := claimed(r)  # their own workstation's area only (issue #184)
	if own.is_empty() or work_of(own).is_empty():
		return null
	var stations := [own]
	var item: String = work_of(stations[0]).item
	var piles := pile_map()
	var loose := stacks_where(func(st): return st.type == item and avail(st) > 0 and not stored(st, piles) and stations.any(func(s): return in_area(s, st.cell)))
	if not loose.is_empty():
		var ls: Dictionary = nearest(loose, c)
		var pd = pile_dest(item, ls.cell)
		if pd != null:
			return _tagged(_haul_job(r, ls, pd.cell, mini(mini(avail(ls), carry_cap(r)), pd.room), pd.site), job)
	if job == "lumber":
		var pj = _plant_job(r, c, stations)
		if pj != null:
			return pj
	if r.get("hurt", 0) > 0:
		return null
	if job == "lumber" and r.broken.axe and tool_items("axe", 0).is_empty():
		return null
	if job == "mason" and r.pick == null and tool_items("pick", 0).is_empty():
		return null
	if own.get("shaft", false):  # a mineshaft digs stone from where it stands (issue #204)
		if free_count(item) >= own.keep or pile_count(own) >= Tuning.WORK_STORE:
			return null
		return _tagged(_dig_job(r, own), job)
	var targets := auto_targets(stations)
	if targets.is_empty():
		return null
	return _gather_job(r, nearest(targets, c))


## The nearest cell to `c` where a lumberjack may plant a sapling: open grass in a chopping block's work
## area, off protected land and the map's edge, and clear of other trees' canopies. Null if none.
func plant_cell(stations: Array, c: Vector2i):
	if _occ_dirty:
		_recompute_occ()
	var best = null
	var bd := 1 << 30
	for s in stations:
		for p in s.area:
			var d := manhattan(p, c)
			if d >= bd or p.x < 1 or p.y < 1 or p.x >= w - 1 or p.y >= h - 1:
				continue
			if not walkable(p) or m.items.has(p) or _plant_claims.has(p) or p == meadow_sign() or p == route_sign() or protected_cell(p):
				continue
			if m.trees.any(func(t): return t.alive and absi(t.cell.x - p.x) <= 2 and absi(t.cell.y - p.y) <= 2):
				continue
			if m.boulders.any(func(b): return b.alive and absi(b.cell.x - p.x) <= 1 and absi(b.cell.y - p.y) <= 1):
				continue
			best = p
			bd = d
	return best


## Fetching a sapling and planting it in a chopping block's work area.
func _plant_job(r: Dictionary, c: Vector2i, stations: Array):
	var saps := stacks_where(func(st): return st.type == "sapling" and avail(st) > 0)
	if saps.is_empty():
		return null
	var cell = plant_cell(stations, c)
	if cell == null:
		return null
	var st: Dictionary = nearest(saps, c)
	var j := Job.new("plant", "Going to plant a sapling", "that spot")
	j.work = "lumber"
	st.res += 1
	var sh := j.hold({"t": "stack", "stack": st, "n": 1})
	_plant_claims[cell] = r.id
	j.hold({"t": "plant", "cell": cell})
	j.step(_goto(reach(st.cell), false))
	j.step({"op": "pickup", "stack": st, "n": 1, "hold": sh})
	j.step(_goto([cell], true))
	j.step({"op": "work", "what": "plant_tree", "cell": cell, "label": "Planting a sapling"})
	return j


## How many wild animals of a species hunters leave in the village (issue #183).
func floor_of(species: String) -> int:
	return herd_floor.get(species, Tuning.HERD_FLOOR)


## Sets how many wild animals of a species hunters leave: they never hunt below it on their own.
func set_herd_floor(species: String, n: int) -> void:
	herd_floor[species] = maxi(0, n)
	rev += 1


## Wild animals on this map nobody has marked or claimed, by species. Penned ones don't count (issue #139).
func free_herds() -> Dictionary:
	var out := {}
	for a in m.sheep:
		if a.alive and a.get("pen", 0) == 0 and not a.des and a.claim == 0:
			out[a.species] = out.get(a.species, 0) + 1
	return out


## The unmarked animals a hunter takes on their own (issue #183): wild ones of each species with more
## than its floor left, so they never hunt the last ones.
func auto_prey() -> Array:
	var herds := free_herds()
	return m.sheep.filter(func(a): return a.alive and a.get("pen", 0) == 0 and not a.des and a.claim == 0 and not _cooling(a) and herds.get(a.species, 0) > floor_of(a.species))


## Sets a workstation's keep-stock target: its gatherers stop once the village has this many.
func set_keep_stock(s: Dictionary, n: int) -> void:
	s.keep = maxi(0, n)
	rev += 1


## Marks trees and boulders in `rect` Keep: gatherers never take them on their own, though they're still
## worked when marked. A single click on a kept one (pass it as `single`) unmarks it instead.
func designate_keep(rect: Rect2i, single = null) -> void:
	var hit: Array = [single] if single != null else (m.trees + m.boulders).filter(func(o): return o.alive and not o.get("hidden", false) and rect.has_point(o.cell))
	var all_on := not hit.is_empty() and hit.all(func(o): return o.get("keep", false))
	for o in hit:
		o.keep = not (single != null and all_on)
		if o.keep and not o.des and o.claim != 0:  # a gatherer was on the way to it unasked
			var r := resident(o.claim)
			if not r.is_empty() and r.job != null and is_same(r.job.target, o):
				fail_job(r)
	rev += 1


# ---------------------------------------------------------------- jobs

func _goto(cells: Array, adjacent: bool) -> Dictionary:
	return {"op": "goto", "cells": cells, "adj": adjacent, "planned": false}


## A stonemason digging 1 cobblestone at their mineshaft (issue #204).
func _dig_job(r: Dictionary, shaft: Dictionary) -> Job:
	var j := Job.new("gather", "Going to dig stone", "the mineshaft")
	j.work = "mason"
	var cur: int = r.pick.tier if r.pick != null else 0
	var better := tool_items("pick", cur)
	if not better.is_empty() and not (r.kept.pick and r.pick != null):
		_fetch_tool(j, nearest(better, rcell(r)))
	j.step(_goto([shaft.origin], true))
	j.step({"op": "work", "what": "dig", "site": shaft, "tool": "pick", "label": "Digging stone"})
	return j


func _gather_job(r: Dictionary, target: Dictionary) -> Job:
	var is_tree: bool = target.kind == "tree"
	var kind := "axe" if is_tree else "pick"
	var j := Job.new("gather", "Going to chop a tree" if is_tree else "Going to break a boulder",
		"this tree" if is_tree else "this boulder")
	j.work = gather_job_of(target)
	j.target = target
	target.claim = r.id
	j.hold({"t": "claim", "ent": target})
	var cur: int = r[kind].tier if r[kind] != null else 0
	var better := tool_items(kind, cur)
	if better.is_empty() and r[kind] != null and not Defs.ITEMS[r[kind].type].has("ench"):  # an enchanted tool of the same tier is better (issue #166)
		better = stacks_where(func(s): return Defs.ITEMS[s.type].get("tool", "") == kind and Defs.ITEMS[s.type].has("ench") and Defs.ITEMS[s.type].tier >= cur and avail(s) > 0)
	if not better.is_empty() and not (r.kept[kind] and r[kind] != null):  # a tool you chose stays
		_fetch_tool(j, nearest(better, rcell(r)))
	j.step(_goto([target.cell], true))
	j.step({"op": "work", "what": "gather", "target": target, "tool": kind,
		"label": "Chopping a tree" if is_tree else "Breaking a boulder"})
	return j


## Food lying around or stockpiled, nearest first: {kind:"stack", stack} or {kind:"bush", bush}, or {}.
func _nearest_food(c: Vector2i) -> Dictionary:
	var best := {}
	var bd := 1 << 30
	var raw := {}
	for k in m.items:
		var s: Dictionary = m.items[k]
		if not Tuning.FOOD_VALUE.has(s.type) or avail(s) <= 0:
			continue
		if Defs.RAW_MEATS.has(s.type):  # raw meat is for the fireplace; eaten only in a pinch
			if raw.is_empty() or manhattan(s.cell, c) < manhattan(raw.stack.cell, c):
				raw = {"kind": "stack", "stack": s}
			continue
		if manhattan(s.cell, c) < bd:
			bd = manhattan(s.cell, c)
			best = {"kind": "stack", "stack": s}
	for b in m.bushes:
		if b.berries > 0 and manhattan(b.cell, c) < bd:
			bd = manhattan(b.cell, c)
			best = {"kind": "bush", "bush": b}
	return raw if best.is_empty() else best


func food_available() -> bool:
	return not _nearest_food(Vector2i.ZERO).is_empty()


## Go and eat (issue #44): pick up the nearest food and eat it, or eat berries off a bush until
## nearly full or the bush is bare.
func _eat_job(r: Dictionary):
	if at_site(r) or on_road(r) or (expedition.get("state", "") == "out" and expedition.party.has(r.id) and r.map != "village"):
		return _ration_job(r)
	var f := _nearest_food(rcell(r))
	if f.is_empty():
		return null
	var j := Job.new("eat", "Going to eat", "the food")
	if f.kind == "bush":
		j.label = "Going to pick berries"
		j.step(_goto([f.bush.cell], false))
		j.step({"op": "work", "what": "graze", "target": f.bush, "label": "Eating berries"})
		return j
	var stack: Dictionary = f.stack
	stack.res += 1
	var hd := j.hold({"t": "stack", "stack": stack, "n": 1})
	j.step(_goto(reach(stack.cell), false))
	j.step({"op": "pickup", "stack": stack, "n": 1, "hold": hd})
	j.step({"op": "work", "what": "eat", "label": "Eating %s" % Defs.ITEMS[stack.type].one})
	return j


## Whether the village has all the wheat it wants, so farmers leave the plots be (issue #269). Counts collected wheat.
func wheat_enough() -> bool:
	return free_count("wheat") >= wheat_keep


func set_wheat_keep(n: int) -> void:
	wheat_keep = maxi(0, n)
	rev += 1


## Plant an empty farm cell or harvest a ripe one (issue #45). Farmers stand on the cell.
func _farm_job(r: Dictionary, crop: Dictionary) -> Job:
	var ripe := crop_ripe(crop)
	var j := Job.new("farm", "Going to harvest wheat" if ripe else "Going to plant wheat", "the farm plot")
	j.work = "farm"
	j.target = crop
	crop.claim = r.id
	j.hold({"t": "claim", "ent": crop})
	j.step(_goto([crop.cell], false))
	j.step({"op": "work", "what": "harvest" if ripe else "plant", "target": crop,
		"label": "Harvesting wheat" if ripe else "Planting wheat"})
	return j


## The nearest farm cell that needs planting or harvesting, ripe ones first, or null.
func _farm_work(c: Vector2i):
	if m.farm.is_empty() or wheat_enough():  # enough wheat: the plots keep their crop (issue #269)
		return null
	var ripe: Array = []
	var empty: Array = []
	for k in m.farm:
		var crop: Dictionary = m.farm[k]
		if crop.claim != 0 or _cooling(crop) or not walkable(crop.cell):
			continue
		if crop_ripe(crop):
			ripe.append(crop)
		elif crop.grow < 0.0 and not m.items.has(crop.cell):  # the last harvest is collected first
			empty.append(crop)
	if not ripe.is_empty():
		return nearest(ripe, c)
	if not empty.is_empty():
		return nearest(empty, c)
	return null


static func crop_ripe(crop: Dictionary) -> bool:
	return crop.grow >= Tuning.WHEAT_GROW


## 0 for an empty plot, 1 to 3 while wheat grows, 4 when it's ripe.
static func crop_stage(crop: Dictionary) -> int:
	if crop.grow < 0.0:
		return 0
	if crop.grow >= Tuning.WHEAT_GROW:
		return 4
	return 1 + mini(2, int(crop.grow / Tuning.WHEAT_GROW * 3.0))


## Walk to a sheep, following it if it wanders, then hunt it.
func _hunt_job(r: Dictionary, target: Dictionary) -> Job:
	var one: String = Defs.SPECIES[target.species].one
	var j := Job.new("gather", "Going to hunt a %s" % one, "this %s" % one)
	j.work = "hunt"
	j.target = target
	target.claim = r.id
	j.hold({"t": "claim", "ent": target})
	j.step({"op": "chase", "target": target, "planned_for": null})
	j.step({"op": "work", "what": "hunt", "target": target, "label": "Hunting a %s" % one})
	return j


func _fetch_tool(j: Job, stack: Dictionary) -> void:
	stack.res += 1
	var hd := j.hold({"t": "stack", "stack": stack, "n": 1})
	j.step(_goto(reach(stack.cell), false))
	j.step({"op": "pickup_tool", "stack": stack, "hold": hd})


func _deliver_job(dest: Dictionary, type: String, n: int, stack: Dictionary) -> Job:
	var dest_name: String = Defs.TEMPLATES[dest.tpl].name.to_lower()
	if dest.done and dest.tpl == "bench":
		dest_name = "bench"
	var j := Job.new("deliver", "Hauling %s to the %s" % [Defs.ITEMS[type].many, dest_name], "the " + dest_name)
	j.target = dest
	stack.res += n
	dest.incoming[type] = dest.incoming.get(type, 0) + n
	var sh := j.hold({"t": "stack", "stack": stack, "n": n})
	var ih := j.hold({"t": "incoming", "site": dest, "type": type, "n": n})
	j.step(_goto(reach(stack.cell), false))
	j.step({"op": "pickup", "stack": stack, "n": n, "hold": sh})
	j.step(_goto(site_cells(dest), true))
	j.step({"op": "deposit", "site": dest, "type": type, "n": n, "hold": ih})
	return j


## Lighting a finished portal (issue #147): fetch flint and steel from a stockpile, carry it to the frame and strike it.
func _light_job(r: Dictionary):
	var p: Dictionary = {}
	for s in m.sites:
		if s.tpl == "portal" and s.done and not s.lit and s.builder == 0 and not _cooling(s):
			p = s
			break
	if p.is_empty():
		return null
	var lighters := stacks_where(func(s): return s.type == "flint_and_steel" and avail(s) > 0)
	if lighters.is_empty():
		return null
	var stack: Dictionary = nearest(lighters, rcell(r))
	var j := Job.new("build", "Going to light the portal", "the portal")
	j.work = "build"
	j.target = p
	p.builder = r.id
	j.hold({"t": "builder", "site": p})
	stack.res += 1
	var hd := j.hold({"t": "stack", "stack": stack, "n": 1})
	j.step(_goto(reach(stack.cell), false))
	j.step({"op": "pickup_lighter", "stack": stack, "hold": hd})
	j.step(_goto(site_cells(p), true))
	j.step({"op": "work", "what": "light", "site": p, "label": "Lighting the portal"})
	return j


func _build_job(r: Dictionary, s: Dictionary) -> Job:
	var j := Job.new("build", "Going to build", "the " + Defs.TEMPLATES[s.tpl].name.to_lower())
	j.work = "build"
	j.target = s
	s.builder = r.id
	j.hold({"t": "builder", "site": s})
	var label: String = "Building " + current_stage(s).name.to_lower()
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
	j.step(_goto(site_cells(s), true))
	j.step({"op": "work", "what": "build", "site": s, "label": label})
	return j


func _craft_job(r: Dictionary, b: Dictionary, rec: Dictionary) -> Job:
	var where: String = "the bench" if b.tpl == "bench" else "the " + Defs.TEMPLATES[b.tpl].name.to_lower()
	var j := Job.new("craft", "Going to " + where, where)
	j.work = recipe_job(rec)
	j.target = b
	b.crafter = r.id
	b.crafting = rec.name
	j.hold({"t": "crafter", "site": b})
	j.step(_goto(site_cells(b), true))
	j.step({"op": "work", "what": "craft", "site": b, "recipe": rec, "label": rec.get("doing", "Crafting " + rec.name.to_lower())})
	return j


## Carrying a stack to a stockpile cell, or to a workstation's pile (`pile`, issue #177).
func _haul_job(r: Dictionary, stack: Dictionary, dest: Vector2i, n: int, pile := {}) -> Job:
	var where: String = "the storehouse" if in_store(dest) else ("the stockpile" if in_zone(dest) else "clear ground") if pile.is_empty() else "the " + Defs.TEMPLATES[pile.tpl].name.to_lower()
	var j := Job.new("haul", "Hauling %s to %s" % [Defs.ITEMS[stack.type].many, where], where)
	stack.res += n
	m.zone_res[dest] = r.id
	var sh := j.hold({"t": "stack", "stack": stack, "n": n})
	var zh := j.hold({"t": "zone", "cell": dest})
	var drop := {"op": "haul_drop", "cell": dest, "type": stack.type, "n": n, "hold": zh}
	if not pile.is_empty():
		pile.incoming[stack.type] = pile.incoming.get(stack.type, 0) + n
		drop.pile_hold = j.hold({"t": "incoming", "site": pile, "type": stack.type, "n": n})
	j.step(_goto(reach(stack.cell), false))
	j.step({"op": "pickup", "stack": stack, "n": n, "hold": sh})
	j.step(_goto(reach(dest), false))
	j.step(drop)
	return j


func _move_job(c: Vector2i) -> Job:
	return Job.new("move", "Walking", "that spot").step(_goto([c], false))


func _release(r: Dictionary, j: Job) -> void:
	for hd in j.holds:
		match hd.t:
			"stack": hd.stack.res -= hd.n
			"incoming": hd.site.incoming[hd.type] -= hd.n
			"zone":
				var zm: SimMap = maps[hd.get("map", map_id)]
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
				if _fence_claims.get(hd.cell, 0) == r.id:
					_fence_claims.erase(hd.cell)
			"plant":
				if _plant_claims.get(hd.cell, 0) == r.id:
					_plant_claims.erase(hd.cell)
			"builder":
				if hd.site.builder == r.id:
					hd.site.builder = 0
			"crafter":
				if hd.site.crafter == r.id:
					hd.site.crafter = 0
					hd.site.crafting = ""
			"arriving": r.arriving = false
	j.holds.clear()


func fail_job(r: Dictionary, why := "") -> void:
	if r.map != map_id:
		on_map(r.map, fail_job.bind(r, why))
		return
	var j = r.job
	if j == null:
		return
	r.job = null
	r.progress = -1.0
	r.path = []
	_release(r, j)
	if r.carry != null:
		drop_items(rcell(r), r.carry.type, r.carry.n, r.carry.get("dur", -1))
		r.carry = null
	var until := tick + int(Tuning.UNREACHABLE_COOLDOWN * Tuning.TPS)
	if why == "unreachable":
		r.note = {"text": "Can’t reach " + j.what, "until": until}
		if j.target != null:
			j.target.unreach_until = until
	elif why == "needs_pick":
		var ore: String = j.target.get("ore", "") if j.target != null else ""
		var diamond: bool = Tuning.ORE_PICK_TIER.has(ore)
		r.note = {"text": pick_need_text(ore) if diamond else "Needs a pickaxe", "until": tick + 4 * Tuning.TPS}
		if diamond:
			j.target.unreach_until = tick + int(Tuning.UNREACHABLE_COOLDOWN * Tuning.TPS)


## How much faster a resident works with the tool in their hand: Efficiency (issue #167).
func tool_speed(r: Dictionary, kind: String) -> float:
	var t = r.get(kind)
	if t != null and Defs.ITEMS[t.type].get("ench", "") == "efficiency":
		return Tuning.EFFICIENCY_SPEED
	return 1.0


## Takes a use off an item (issue #167): an Unbreaking one only loses every other use, kept in a running count so a game replays
## the same. Returns whether a use was taken.
static func _use_up(t: Dictionary) -> bool:
	if Defs.ITEMS[t.type].get("ench", "") == "unbreaking":
		t.acc = t.get("acc", 0.0) + Tuning.UNBREAKING_WEAR
		if t.acc < 1.0:
			return false
		t.acc -= 1.0
	t.dur -= 1
	return true


func _wear(r: Dictionary, kind: String) -> void:
	var t = r[kind]
	if t == null:
		return
	if not _use_up(t):
		return
	if t.dur <= 0:
		r[kind] = null
		r.broken[kind] = true
		r.kept[kind] = false
		stats.tools_broken += 1
		if kind == "pick" and expedition.get("state", "") == "out" and expedition.party.has(r.id):
			expedition.broken = expedition.get("broken", 0) + 1
		_toast("%s’s %s broke." % [r.name, Defs.ITEMS[t.type].one], r.id)


## Runs the resident's current step. Returns true when the step finished, false to continue next
## tick, or a String naming why the job failed.
func _run_step(r: Dictionary, j: Job, st: Dictionary):
	match st.op:
		"chase":
			var t: Dictionary = st.target
			if not t.alive:
				return "gone"
			if manhattan(rcell(r), t.cell) <= 1:
				r.path = []
				r.pos = Vector2(rcell(r))
				return true
			if st.planned_for != t.cell or r.path.is_empty():
				var goals := adj_set([t.cell])
				goals[t.cell] = true
				var p = find_path(rcell(r), goals)
				if p == null:
					return "unreachable"
				r.path = p
				st.planned_for = t.cell
			var nxt: Vector2i = r.path[0]
			var to: Vector2 = Vector2(nxt) - r.pos
			var dist: float = to.length()
			var step_len := Tuning.WALK * Tuning.DT * hurt_speed(r) * ground_speed(rcell(r))
			if dist <= step_len:
				r.pos = Vector2(nxt)
				r.path.pop_front()
				_wear_step(nxt)
			else:
				r.pos += to / dist * step_len
			return false
		"goto":
			if not st.planned:
				var goals := adj_set(st.cells) if st.adj else cell_set(st.cells)
				if goals.is_empty():
					return "unreachable"
				var p = find_path(rcell(r), goals)
				if p == null:
					return "unreachable"
				r.path = p
				st.planned = true
			if r.path.is_empty():
				r.pos = Vector2(rcell(r))
				return true
			var nxt: Vector2i = r.path[0]
			if not walkable(nxt):
				st.planned = false
				r.path = []
				return false
			var to: Vector2 = Vector2(nxt) - r.pos
			var dist: float = to.length()
			var step_len := Tuning.WALK * Tuning.DT * hurt_speed(r) * ground_speed(rcell(r))
			if dist <= step_len:
				r.pos = Vector2(nxt)
				r.path.pop_front()
				_wear_step(nxt)
				if m.kind == "route":
					_reveal(nxt)
				if m.kind == "site":
					_ledge_step(r, nxt)
					if r.job != j:
						return false  # a fall ended the job
				return r.path.is_empty()
			r.pos += to / dist * step_len
			return false
		"pickup":
			var s = m.items.get(st.stack.cell)
			if not is_same(s, st.stack) or s.n < st.n:
				return "gone"
			s.n -= st.n
			s.res -= st.n
			j.holds.erase(st.hold)
			if s.n <= 0:
				m.items.erase(s.cell)
			r.carry = {"type": s.type, "n": st.n}
			if s.has("dur"):
				r.carry.dur = s.dur
			rev += 1
			return true
		"pickup_armor":  # put on a piece of armor (issue #140)
			var s = m.items.get(st.stack.cell)
			if not is_same(s, st.stack) or s.n < 1:
				return "gone"
			s.n -= 1
			s.res -= 1
			j.holds.erase(st.hold)
			if s.n <= 0:
				m.items.erase(s.cell)
			var slot: String = Defs.ITEMS[s.type].armor
			var old = r.armor.get(slot)
			if old != null:
				drop_items(s.cell, old.type, 1, old.dur)
			r.armor[slot] = {"type": s.type, "dur": s.dur}
			rev += 1
			return true
		"pickup_lighter":  # flint and steel in the hand, for the portal (issue #147)
			var ls = m.items.get(st.stack.cell)
			if not is_same(ls, st.stack) or ls.n < 1:
				return "gone"
			ls.n -= 1
			ls.res -= 1
			j.holds.erase(st.hold)
			if ls.n <= 0:
				m.items.erase(ls.cell)
			r.carry = {"type": ls.type, "n": 1, "dur": ls.get("dur", full_uses(ls.type))}
			rev += 1
			return true
		"pickup_tool":
			var s = m.items.get(st.stack.cell)
			if not is_same(s, st.stack) or s.n < 1:
				return "gone"
			s.n -= 1
			s.res -= 1
			j.holds.erase(st.hold)
			if s.n <= 0:
				m.items.erase(s.cell)
			var it: Dictionary = Defs.ITEMS[s.type]
			var old = r[it.tool]
			if old != null:
				drop_items(s.cell, old.type, 1, old.dur)
			r[it.tool] = {"type": s.type, "tier": it.tier, "dur": s.dur}
			r.broken[it.tool] = false
			r.kept[it.tool] = st.get("keep", false)
			rev += 1
			return true
		"deposit":
			var dest: Dictionary = st.site
			dest.incoming[st.type] -= st.n
			dest.store[st.type] = dest.store.get(st.type, 0) + st.n
			if r.carry.has("dur"):  # a spare tool packed at the expedition board keeps its wear
				dest.tools = dest.get("tools", []) + [{"type": st.type, "dur": r.carry.dur}]
			j.holds.erase(st.hold)
			r.carry = null
			rev += 1
			return true
		"haul_drop":
			m.zone_res.erase(st.cell)
			if r.carry == null:
				return "gone"
			j.holds.erase(st.hold)
			if st.has("pile_hold"):
				st.pile_hold.site.incoming[st.type] -= st.n
				j.holds.erase(st.pile_hold)
			if in_store(st.cell):  # into a chest (issue #189)
				_store_put(st.cell, st.type, st.n, r.carry.get("dur", -1))
			else:
				drop_items(st.cell, st.type, st.n, r.carry.get("dur", -1))
			if st.type == "iron_ore" and m.kind == "village":  # a village-book goal (issue #198)
				stats.ore_home = true
			r.carry = null
			return true
		"depart":  # off the edge of the map: onto the road map (#118), or the walk to or from the meadow (#137)
			var to: String = st.to
			if realm_of(expedition.get("dest", "")) == "nether":  # through the portal, which has to be lit (issue #148)
				if to != "village" and not portal_lit():
					return false
				_cross_portal(r, to)
				return true
			_onto_road(r, to)
			return true
		"descend":  # through the door to the level below (issue #132)
			if m.door_state != "open":
				open_door(map_id)
			_enter_level(r, MineLevels.level_id(m.level + 1))
			return true
		"ascend":  # up from a level's entrance to the door of the level above
			var up := MineLevels.level_id(m.level - 1)
			var at = on_map(up, nearest_walkable.bind(MineLevels.door_front(maps[up])))
			move_to_map(r, up, at if at != null else maps[up].entrance)
			return true
		"at_door":  # the party has reached the door at the end of the level
			if m.door_state == "closed":
				_find_door(r)
			return true
		"railhead_drop":  # rails set down at the railhead pile (issue #122)
			if r.carry == null:
				return "gone"
			drop_items(_railhead_spot(), r.carry.type, r.carry.n)
			r.carry = null
			return true
		"dock":  # the minecart parked at the village station (issue #123)
			if r.carry == null or not cart.is_empty():
				return "gone"
			r.carry = null
			cart = {"at": "village", "x": station_x("village"), "state": "parked", "load": {}, "riders": [], "acc": 0.0}
			rev += 1
			_toast("The minecart is parked at the village station.", r.id)
			return true
		"load_cart":  # goods set on the freight cart (issue #172)
			if r.carry == null or r.carry.type != st.type or freight.get("state", "") != "home":
				return "gone"
			freight.load[st.type] = freight.load.get(st.type, 0) + r.carry.n
			r.carry = null
			rev += 1
			return true
		"freight_dock":  # the freight cart parked at the portal station (issue #169)
			if r.carry == null or freight.get("state", "") != "ordered":
				return "gone"
			r.carry = null
			freight.state = "home"
			rev += 1
			_toast("The freight cart is parked at the portal station.", r.id)
			return true
		"board":  # into the cart (issue #124)
			if cart.is_empty():
				return true
			if not cart.riders.has(r.id):
				cart.riders.append(r.id)
			j.label = st.riding
			return true
		"ride":
			if cart.is_empty() or not cart.riders.has(r.id):
				return true
			r.pos = _seat(r)
			r.path = []
			if cart.state == "parked" and cart.at == st.to:
				cart.riders.erase(r.id)
				r.pos = Vector2(_off_cart_cell())
				return true
			return false
		"unload_wait":  # the party unloading its packs at the signpost (issue #123)
			return not expedition.get("unloading", false)
		"road_end":  # the far end of the road: into the site, or home (issue #118)
			var leg: String = "road_" + expedition.get("leg", "out")
			if expedition.has(leg):
				expedition[leg][1] = tick
			if r.trip == "village":
				_arrive_home(r)
			else:
				_arrive_at_site(r)
			return true
		"cross":  # between the village and the road, for work out there (issues #119, #121)
			r.map = st.to
			var at = Road.VILLAGE_END
			if st.to == "village":
				at = on_map("village", nearest_walkable.bind(route_sign()))
				at = at if at != null else route_sign()
			r.pos = Vector2(at)
			r.path = []
			rev += 1
			if st.to == Road.ID:
				_reveal(at)
			return true
		"ration":  # a meal out of the packs (issue #109)
			if spendable_meals() <= 0:
				return "gone"
			var prov: Dictionary = expedition.provisions
			var meal: String = prov.keys().filter(func(k): return prov[k] > 0)[0]
			prov[meal] -= 1
			if prov[meal] <= 0:
				prov.erase(meal)
			r.carry = {"type": meal, "n": 1}
			rev += 1
			return true
		"stow":  # what's carried goes into the packs: meals, spare tools or cargo (issue #109)
			if r.carry == null:
				return "gone"
			if st.has("swap") and cargo_have(st.swap) > 0:  # a better item swaps out the lowest cargo, left here (issue #185)
				var freed := mini(st.n, cargo_have(st.swap))
				expedition.cargo[st.swap] -= freed
				if expedition.cargo[st.swap] <= 0:
					expedition.cargo.erase(st.swap)
				drop_items(m.entrance, st.swap, freed)
			var over: int = r.carry.n - maxi(0, pack_room())
			if over > 0:  # the packs filled up on the way: the rest is set down here
				drop_items(rcell(r), r.carry.type, over, r.carry.get("dur", -1))
				r.carry.n -= over
				if r.carry.n <= 0:
					r.carry = null
					return true
			if r.carry.type in PEN_SUPPLIES:  # sticks or wheat set down at the meadow (issue #139)
				if not expedition.has("supplies"):
					expedition.supplies = {}
				expedition.supplies[r.carry.type] = expedition.supplies.get(r.carry.type, 0) + r.carry.n
			elif Defs.MEALS.has(r.carry.type):
				expedition.provisions[r.carry.type] = expedition.provisions.get(r.carry.type, 0) + r.carry.n
			elif r.carry.has("dur"):
				expedition.tools.append({"type": r.carry.type, "dur": r.carry.dur})
			else:
				expedition.cargo[r.carry.type] = expedition.cargo.get(r.carry.type, 0) + r.carry.n
				_note_book(r.carry.type, r)
			r.carry = null
			rev += 1
			return true
		"take_supply":  # sticks or wheat out of the packs, for the pens (issue #139)
			var sup: Dictionary = expedition.get("supplies", {})
			var n: int = mini(st.n, sup.get(st.type, 0))
			if n <= 0:
				return "gone"
			sup[st.type] -= n
			if sup[st.type] <= 0:
				sup.erase(st.type)
			r.carry = {"type": st.type, "n": n}
			rev += 1
			return true
		"put_back":  # what's left of them goes back into the packs
			if r.carry != null and r.carry.type == st.type:
				expedition.supplies[st.type] = expedition.supplies.get(st.type, 0) + r.carry.n
				r.carry = null
				rev += 1
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
			if not a.alive or not m.pens.any(func(x): return is_same(x, pn)):
				return "gone"
			var inside := pen_inside(pn)
			var to := Vector2i(clampi(rcell(r).x, inside.position.x, inside.end.x - 1), clampi(rcell(r).y, inside.position.y, inside.end.y - 1))
			a.pen = pn.id
			a.lead = false
			a.led_by = 0
			a.led_to = 0
			a.cell = to
			a.pos = Vector2(to)
			a.dest = null
			rev += 1
			return true
		"take_tool":  # the best spare pickaxe in the packs
			var tools: Array = expedition.get("tools", [])
			if tools.is_empty() or r.pick != null:
				return "gone"
			tools.sort_custom(func(a, b): return Defs.ITEMS[a.type].tier > Defs.ITEMS[b.type].tier or (a.type == b.type and a.dur > b.dur))
			var t: Dictionary = tools.pop_front()
			r.pick = {"type": t.type, "tier": Defs.ITEMS[t.type].tier, "dur": t.dur}
			r.broken.pick = false
			rev += 1
			return true
		"rest_site":  # seriously hurt at the site: waits at the entrance until the party goes home
			if not at_site(r) or r.get("hurt", 0) < 2:
				return true
			if r.hunger < Tuning.EAT_BELOW and spendable_meals() > 0:
				return true
			r.pos = Vector2(rcell(r))
			return false
		"rest":  # healing at home (issue #110)
			if r.get("hurt", 0) == 0:
				return true
			if r.hunger < Tuning.EAT_BELOW and food_available():
				return true
			if not st.bed and tick % Tuning.TPS == 0 and map_id == "village" and _has_bed(r):
				return true  # a bed of their own now: go and rest in it
			r.heal -= Tuning.DT * (1.0 if st.bed else Tuning.HEAL_NO_BED)
			r.pos = Vector2(rcell(r))
			if r.heal <= 0.0:
				r.hurt = 0
				r.heal = 0.0
				rev += 1
				_toast("%s has healed and is back at work." % r.name, r.id)
				return true
			return false
		"fight":  # blows at a creature, one every HIT_TIME, until it's down or out of reach (issue #151)
			var cr: Dictionary = st.target
			if not cr.alive:
				return true
			if manhattan(rcell(r), cr.cell) > 1:
				return "gone"
			r.pos = Vector2(rcell(r))
			j.label = "Fighting the %s" % Defs.CREATURES[cr.species].name.to_lower()
			st.t = st.get("t", 0.0) + Tuning.DT
			if st.t >= Tuning.HIT_TIME / skill_speed(r, "guard"):
				st.t = 0.0
				_strike(r, cr)
			return not cr.alive
		"enter_route":  # out of the landing onto a route's west end (issue #153)
			var def: Dictionary = NetherRoute.ROUTES[st.route]
			maps[def.id].known = true
			move_to_map(r, def.id, maps[def.id].entrance)
			_toast("%s set out along the %s." % [r.name, def.name.substr(8).to_lower()], r.id)
			return true
		"reach_segment":  # a segment of the route is seen: its terrain and dangers are known (issue #153)
			if m.seen < st.idx + 1:
				m.seen = st.idx + 1
				rev += 1
				var rd: Dictionary = NetherRoute.ROUTES[NetherRoute.route_of(map_id)]
				_toast("The scouts reached %s." % rd.segments[st.idx].name.to_lower(), r.id)
			return true
		"route_end":  # the far end: the route is scouted, and so is its site (issue #153)
			if not m.surveyed:
				m.surveyed = true
				var rk := NetherRoute.route_of(map_id)
				var site: SimMap = maps[NetherRoute.ROUTES[rk].site]
				site.known = true
				rev += 1
				_toast("The route is scouted. The %s is known now." % site.name.substr(8).to_lower(), r.id)
				if expedition.get("leg", "out") == "out":
					_head_home("the route is scouted")
			return true
		"to_site":  # the route's far end: onto the site (issue #155)
			var tk := dest_route(expedition.get("dest", ""))
			_enter_level(r, NetherRoute.ROUTES[tk].site)
			return true
		"leave_site":  # off a site, back onto the route's far end (issue #155)
			var lk := NetherRoute.site_key(map_id)
			move_to_map(r, NetherRoute.ROUTES[lk].id, Vector2i(NetherRoute.W - 1, NetherRoute.LINE_ROW))
			return true
		"leave_route":  # back onto the landing, at the edge the route leaves from (issue #153)
			var back: Dictionary = NetherRoute.ROUTES[NetherRoute.route_of(map_id)]
			move_to_map(r, NetherLanding.ID, back.exit)
			return true
		"learn_book":  # the book is read into the workshop: its recipe is known for good, and the book is used up (issue #165)
			var ws: Dictionary = st.site
			var ench: String = Defs.ITEMS[st.book].book
			ws.store[st.book] = ws.store.get(st.book, 0) - 1
			if ws.store[st.book] <= 0:
				ws.store.erase(st.book)
			if not ws.known.has(ench):
				ws.known.append(ench)
				stats.enchants_learned = stats.get("enchants_learned", 0) + 1
				_toast("The enchanting workshop learned %s." % Defs.ENCHANTS[ench].name, r.id, ws.id)
			rev += 1
			return true
		"cache_stock":  # meals set down in the cache, above what the party keeps for the way home (issue #152)
			var cache := shelter_site()
			var moved := 0
			for k in expedition.get("provisions", {}).keys():
				while moved < expedition.get("stock", 0) and expedition.provisions[k] > 0 and _pack_spendable() > 0:
					expedition.provisions[k] -= 1
					cache.store[k] = cache.store.get(k, 0) + 1
					moved += 1
				if expedition.provisions[k] <= 0:
					expedition.provisions.erase(k)
			expedition.stock = 0
			rev += 1
			if moved > 0:
				_toast("%d %s left in the cache." % [moved, "meal" if moved == 1 else "meals"], r.id)
			return true
		"cache_take":  # a meal from the cache into the packs, to eat (issue #152)
			var from := shelter_site()
			for k in from.get("store", {}):
				if Defs.MEALS.has(k) and from.store[k] > 0:
					from.store[k] -= 1
					if from.store[k] <= 0:
						from.store.erase(k)
					expedition.provisions[k] = expedition.get("provisions", {}).get(k, 0) + 1
					rev += 1
					return true
			return "gone"
		"wait_stranded":  # sheltering until the rescue (or the window) ends it (issue #158)
			if not expedition.has("stranded"):
				return true
			j.label = "Sheltering, waiting for a rescue"
			r.pos = Vector2(rcell(r))
			return false
		"rescue_reach":  # the stranded are reached: they get what the rescue carries, and everyone heads home (issue #158)
			var lost: Dictionary = expeditions.nether
			if not lost.has("stranded"):
				return true
			var spare := _pack_spendable()
			if spare > 0:  # the meals past its own walk home
				for k in expedition.get("provisions", {}).keys():
					while spare > 0 and expedition.provisions[k] > 0:
						expedition.provisions[k] -= 1
						lost.provisions[k] = lost.get("provisions", {}).get(k, 0) + 1
						spare -= 1
			if lost.get("lighter", {}).is_empty() and not expedition.get("lighter", {}).is_empty():
				lost.lighter = expedition.lighter.duplicate()
			lost.erase("stranded")
			lost.leg = "home"
			lost.home_why = "rescued"
			for id in lost.party:
				var lr := resident(id)
				if not lr.is_empty():
					fail_job(lr)
			expedition.leg = "home"
			expedition.home_why = "the stranded party is reached"
			for id in expedition.party:
				fail_job(resident(id))
			stats.rescues = stats.get("rescues", 0) + 1
			rev += 1
			_toast("The stranded party is rescued. Everyone heads home.", r.id)
			return true
		"open_salvage":  # the chest at the far end, and the sealed way beside it: the game stops once for the choice (issue #157)
			if m.salvage_taken or not pending.filter(func(p): return p.kind == "fortress").is_empty():
				return true
			if not m.surveyed:
				m.surveyed = true
				_ask("fortress", "The party reached a salvage chest at the far end of the fortress. Beside it a sealed way leads deeper, which a later expedition could open.", [
					{"id": "take", "label": "Take it and return", "cost": "The party takes the salvage (%s) and heads home." % ", ".join(Defs.FORTRESS_SALVAGE.keys().map(func(k): return Defs.words(k, Defs.FORTRESS_SALVAGE[k]))) },
					{"id": "press", "label": "Take it and press on", "cost": "The party takes the salvage and stays to clear the halls of blazes and skeletons, for more blaze rods. The way deeper stays sealed."},
				], r.id)
			return true
		"trade":  # every trade the gold pays for, down the table; goods go into the packs (issue #156)
			if m.hostile:
				return "gone"
			var made := 0
			var counts := {}
			while true:
				var ti := _next_trade()
				if ti < 0:
					break
				counts[ti] = counts.get(ti, 0) + 1
				var t: Dictionary = Defs.TRADES[ti]
				for k in t.give:
					expedition.supplies[k] -= t.give[k]
					if expedition.supplies[k] <= 0:
						expedition.supplies.erase(k)
				for k in t.get:
					expedition.cargo[k] = expedition.cargo.get(k, 0) + t.get[k]
					_note_book(k, r)
				made += 1
			for ti in counts:
				expedition.traded = expedition.get("traded", []) + [Defs.trade_text(Defs.TRADES[ti]) + (" ×%d" % counts[ti] if counts[ti] > 1 else "")]
			expedition.trade_done = true
			rev += 1
			if made > 0:
				_toast("The party traded with the piglins: %s." % "; ".join(expedition.traded), r.id)
			return true
		"mark_seen":  # a landmark is seen; the last one surveys the landing (issue #148)
			if not m.landmarks_seen.has(st.cell):
				m.landmarks_seen.append(st.cell)
				rev += 1
				if m.landmarks_seen.size() >= m.landmarks.size() and not m.surveyed:
					m.surveyed = true
					_toast("The landing is surveyed: %d landmarks seen." % m.landmarks.size(), r.id)
			return true
		"wait_portal":  # the portal has gone out, and nobody carries flint and steel: waits for the village to light it
			if portal_lit():
				return true
			j.label = "Waiting at the dark portal"
			r.pos = Vector2(rcell(r))
			return false
		"wait_board":  # waits at the board until the party departs (issue #107)
			if expedition.get("state", "") != "staging" or not expedition.party.has(r.id):
				return true
			if r.hunger < Tuning.EAT_BELOW and food_available():
				return true  # goes to eat, then comes back
			j.label = "Waiting at the expedition board"
			r.pos = Vector2(rcell(r))
			return false
		"move_in":
			st.site.owner = r.id
			r.arriving = false
			j.holds.clear()
			stats.traveler_home = true
			_toast("%s moved into the new house." % r.name, r.id)
			return true
		"work":
			if not st.has("total"):
				var total := _work_time(r, st)
				if total < 0.0:
					return "needs_pick"
				if st.what != "eat" and st.what != "graze" and r.hunger < Tuning.HUNGRY_BELOW:
					total /= Tuning.HUNGRY_SPEED
				if j.work != "":
					total /= skill_speed(r, j.work)
				if st.what != "eat":
					total /= hurt_speed(r)
					if m.is_dark(rcell(r)):  # unlit tunnels are slow going (issue #110)
						total /= Tuning.DARK_WORK
				st.total = total
				st.t = 0.0
				j.label = st.label
			st.t += Tuning.DT
			r.progress = minf(1.0, st.t / st.total)
			if st.t >= st.total:
				r.progress = -1.0
				return _finish_work(r, st)
			return false
	return "gone"


func _work_time(r: Dictionary, st: Dictionary) -> float:
	match st.what:
		"gather":
			var tier: int = r[st.tool].tier if r[st.tool] != null else 0
			if st.tool == "axe":
				return Tuning.CHOP_TIME[tier] / tool_speed(r, "axe")
			if st.target.get("ore", "") == "glowstone":  # it breaks by hand (issue #155)
				return Tuning.GLOWSTONE_TIME
			if tier < Tuning.ORE_PICK_TIER.get(st.target.get("ore", ""), 0):  # diamonds want an iron pickaxe (issue #186), obsidian a diamond one (#146)
				return -1.0
			return Tuning.BREAK_TIME[tier] / tool_speed(r, "pick") if tier > 0 else -1.0
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


func _finish_work(r: Dictionary, st: Dictionary):
	match st.what:
		"gather":
			var t: Dictionary = st.target
			if not t.alive:
				return "gone"
			t.alive = false
			t.des = false
			_occ_dirty = true
			if t.kind == "tree":
				drop_items(t.cell, "log", t.logs + skill_bonus(r, "lumber"))
				var saplings := Tuning.SAPLINGS + (1 if rng.randf() < Tuning.SAPLING_EXTRA else 0)
				drop_items(t.cell, "sapling", saplings)  # issue #177
				stats.felled += 1
			elif t.has("ore"):  # an ore block (issue #103); it never comes back (issue #102)
				if t.ore == "gravel":  # sometimes a flint, else nothing (issue #146)
					if rng.randf() < Tuning.GRAVEL_FLINT_CHANCE:
						drop_items(t.cell, "flint", 1)
				elif t.ore == "chest":  # the book inside (issue #164)
					drop_items(t.cell, t.book, 1)
				else:
					drop_items(t.cell, Defs.ORES[t.ore].item, Tuning.ORE_YIELD[t.ore] + skill_bonus(r, "mason"))
				stats.ore_mined = stats.get("ore_mined", 0) + 1
			else:
				drop_items(t.cell, "cobble", Tuning.BOULDER_COBBLE + skill_bonus(r, "mason"))
				stats.broken_boulders += 1
			_wear(r, st.tool)
			if t.get("loose", false):  # issue #110
				_hazard(r, cave_in_chance(m.level), Tuning.CAVE_IN_SERIOUS, "a cave-in")
			_check_find(t.cell)  # issue #111
			_check_find_diamond(t.cell)  # issue #186
		"light":  # the frame is lit, and the flint and steel goes back with a use less (issue #147)
			var portal: Dictionary = st.site
			if portal.lit:
				return "gone"
			portal.lit = true
			portal.builder = 0
			maps[NetherLanding.ID].known = true  # the board has word of it now (issue #148)
			if r.carry != null and r.carry.type == "flint_and_steel":
				var left: int = r.carry.dur - 1
				if left > 0:
					drop_items(rcell(r), "flint_and_steel", 1, left)
				else:
					_toast("%s’s flint and steel is spent." % r.name, r.id)
				r.carry = null
			rev += 1
			_toast("The portal is lit.", r.id, portal.id)
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
			drop_items(ew.origin, ord.item + "+" + ord.ench, 1, held[0].dur)
			stats.enchanted = stats.get("enchanted", 0) + 1
			rev += 1
			_toast("%s enchanted: %s." % [r.name, Defs.ITEMS[ord.item + "+" + ord.ench].one], r.id, ew.id)
		"nline":  # a piece of the Nether line (issue #159)
			_finish_line_task(st.task, r)
		"lay_dust":  # one cell of a dust line (issue #170)
			var w = wire_by_id(st.wire)
			if w == null or w.laid >= w.cells.size() or r.carry == null or r.carry.type != "redstone":
				return "gone"
			w.laid += 1
			if w.laid >= w.cells.size() or w.laid % Tuning.DUST_PER_REDSTONE == 0:
				r.carry.n -= 1
				if r.carry.n <= 0:
					r.carry = null
			rev += 1
			if w.laid >= w.cells.size():
				_toast("A dust line is laid.", r.id, w.to)
		"pline":  # a piece of the portal line (issue #168)
			_finish_pline_task(st.task, r)
		"shelter":  # the party's cobblestone and planks go into the walls (issue #152)
			var shelter: Dictionary = st.site
			shelter.builder = 0
			if shelter.done or not _supplies_cover(Tuning.SHELTER_COST):
				return "gone"
			for k in Tuning.SHELTER_COST:
				expedition.supplies[k] -= Tuning.SHELTER_COST[k]
				if expedition.supplies[k] <= 0:
					expedition.supplies.erase(k)
			shelter.stage = 1
			shelter.done = true
			_occ_dirty = true
			rev += 1
			_toast("The shelter is built. Injured residents rest in it, and meals left in its cache feed later parties.", r.id)
		"relight":  # the party's own flint and steel, from the packs (issue #148)
			var vp := village_portal()
			if not vp.is_empty():
				vp.lit = true
			var lighter: Dictionary = expedition.get("lighter", {})
			if not lighter.is_empty():
				lighter.dur -= 1
				if lighter.dur <= 0:
					expedition.erase("lighter")
					_toast("%s’s flint and steel is spent." % r.name, r.id)
			rev += 1
			_toast("The portal is lit again.", r.id)
		"dig":
			var shaft: Dictionary = st.site
			if not shaft.get("shaft", false):
				return "gone"
			var at: Vector2i = shaft.origin
			for pc in pile_cells(shaft):  # onto the pile beside it, when there's room
				var there = m.items.get(pc)
				if there == null or (there.type == "cobble" and there.n < Defs.stack_cap("cobble")):
					at = pc
					break
			drop_items(at, "cobble", 1)
			shaft.digs = shaft.get("digs", 0) + 1
			stats.stone_dug = stats.get("stone_dug", 0) + 1
			if shaft.digs % Tuning.SHAFT_WEAR_EVERY == 0:
				_wear(r, "pick")
		"eat":
			if r.carry == null:
				return "gone"
			r.hunger = minf(100.0, r.hunger + Tuning.FOOD_VALUE.get(r.carry.type, 0.0))
			r.carry = null
		"graze":
			var bush: Dictionary = st.target
			if bush.berries <= 0 or not m.bushes.has(bush):
				return true
			bush.berries -= 1
			r.hunger = minf(100.0, r.hunger + Tuning.FOOD_VALUE.berries)
			rev += 1
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
				drop_items(sh.cell, k, Tuning.ANIMAL_DROPS[sh.species][k])
			if sh.species == "sheep":
				stats.sheep_hunted = stats.get("sheep_hunted", 0) + 1
			stats.hunted = stats.get("hunted", 0) + 1
			if sh.species == "cow" and m.id == Meadow.ID:  # issue #137: never serious
				_hazard(r, Tuning.BULL_CHANCE, 0.0, "an angry bull")
			rev += 1
		"plant":
			var crop: Dictionary = st.target
			if not is_same(m.farm.get(crop.cell), crop) or crop.grow >= 0.0 or m.items.has(crop.cell):
				return "gone"
			crop.grow = 0.0
			stats.planted = stats.get("planted", 0) + 1
			rev += 1
		"plant_tree":  # issue #177
			var pc: Vector2i = st.cell
			if r.carry == null or r.carry.type != "sapling" or not walkable(pc) or m.items.has(pc) or residents.any(func(o): return o.map == map_id and rcell(o) == pc) or m.sheep.any(func(a): return a.alive and a.cell == pc):
				return "gone"
			r.carry = null
			m.trees.append({"id": _id(), "kind": "tree", "cell": pc, "logs": 4 + (next_id * 7) % 3, "alive": true, "des": false,
				"claim": 0, "unreach_until": 0, "grow": 0.0})
			_occ_dirty = true
			stats.trees_planted = stats.get("trees_planted", 0) + 1
			rev += 1
		"harvest":
			var crop: Dictionary = st.target
			if not is_same(m.farm.get(crop.cell), crop) or not crop_ripe(crop):
				return "gone"
			crop.grow = -1.0
			drop_items(crop.cell, "wheat", Tuning.WHEAT_YIELD + skill_bonus(r, "farm"))
			stats.harvested = stats.get("harvested", 0) + 1
			rev += 1
		"survey":  # issue #111
			for i in Tuning.SURVEY_USES:
				_wear(r, "pick")
			survey(map_id)
			expedition.survey = false
			_toast("%s surveyed the vein: about %d iron ore. Iron can be an expedition's target now." % [r.name, ore_left(map_id, "iron") * Tuning.ORE_YIELD.iron], r.id)
		"fence":  # issue #139
			var pn: Dictionary = st.pen
			if not m.pens.any(func(x): return is_same(x, pn)) or pn.built.has(st.cell) or r.carry == null or r.carry.type != "stick" or r.carry.n < Tuning.FENCE_STICKS:
				return "gone"
			r.carry.n -= Tuning.FENCE_STICKS
			if r.carry.n <= 0:
				r.carry = null
			_fence_claims.erase(st.cell)
			_put_fence(pn, st.cell)
		"feed":
			var pair: Array = st.pair
			if r.carry == null or r.carry.type != "wheat" or r.carry.n < 2 * Tuning.FEED_WHEAT or not pair.all(func(a): return a.alive and a.get("pen", 0) == pair[0].pen):
				return "gone"
			r.carry.n -= 2 * Tuning.FEED_WHEAT
			if r.carry.n <= 0:
				r.carry = null
			for a in pair:
				a.fed_at = tick
			stats.fed = stats.get("fed", 0) + 1
			rev += 1
		"build":
			if st.site.tpl == "track":
				_lay_rail(st.site)
			else:
				_complete_stage(st.site)
		"craft":
			var b: Dictionary = st.site
			var rec := recipe_for(r, st.recipe)
			var qi: int = b.queue.find(rec.id)
			if qi < 0 or not has_all(b.store, rec.inp):
				return "gone"
			for k in rec.inp:
				b.store[k] -= rec.inp[k]
			b.queue.remove_at(qi)
			b.autoq.remove_at(qi)
			for o in rec.out:
				var uses := -1
				if Defs.is_tool_item(o):  # Toolsmith: +20% uses per level above 1
					uses = roundi(full_uses(o) * (1.0 + Tuning.TOOLSMITH_USES * (mini(level(r, "toolsmith"), Tuning.SKILL_CORE) - 1 + tail_steps(level(r, "toolsmith")))))
				drop_items(rcell(r), o, rec.out[o], uses)
				if Defs.MEALS.has(o):  # a village-book goal (issue #198)
					stats.meals_cooked = stats.get("meals_cooked", 0) + rec.out[o]
				if Defs.ITEMS[o].get("tool", "") == "pick":
					stats.pick_crafted = true
				if Defs.ITEMS[o].get("tool", "") == "axe":
					stats.axe_crafted = true
			if b.queue.is_empty():  # a skilled cook's spare wheat goes back out
				for k in b.store:
					if b.store[k] > 0:
						drop_items(b.origin + Vector2i(0, 1), k, b.store[k])
				b.store = {}
	return true


# ---------------------------------------------------------------- claiming work

## Picks the resident's next job. Priority (spec §5): craft > deliver to a bench > build >
## deliver to a site > mine > haul.
func _claim(r: Dictionary) -> void:
	# Starving residents only eat (spec §4); hungry ones eat after any orders you've given them.
	if r.hunger <= 0.0:
		var ej = _eat_job(r)
		if ej != null:
			r.job = ej
		return
	if r.direct != null:
		r.job = r.direct
		r.direct = null
		return
	while not r.orders.is_empty():
		var j = _order_job(r, r.orders.pop_front())
		if j != null:
			j.ordered = true
			r.job = j
			return
	if r.hunger < Tuning.EAT_BELOW:
		var ej = _eat_job(r)
		if ej != null:
			r.job = ej
			return
	var c := rcell(r)
	if in_staging_party(r):  # the party packs, then gathers at the board (issue #107)
		var pj = _pack_job(r, c)
		r.job = pj if pj != null else _stage_job()
		return
	if expedition.get("unloading", false) and expedition.party.has(r.id) and r.map == "village":
		var u := Job.new("unload", "Unloading the packs", "the signpost")
		u.step(_goto([sign_for(expedition.dest)], true))
		u.step({"op": "unload_wait"})
		r.job = u
		return
	if realm_of(map_id) == "nether" and expedition_of(r).has("stranded"):  # sheltering, waiting for a rescue (issue #158)
		r.job = _stranded_job(r)
		return
	if on_the_way(r):  # out of village labor: off to the signpost, or home from the site (issue #108)
		r.job = _road_job()
		return
	if on_road(r):  # walking the road map (issue #118)
		r.job = _road_walk_job(r)
		return
	if realm_of(map_id) == "nether" and not expedition_of(r).is_empty() and not at_site(r):  # on the way across the Nether (issues #153, #155)
		r.job = _nether_transit_job(r)
		return
	if map_id == Road.ID:  # out on the road for work there (issues #119, #121)
		r.job = _claim_on_road(r)
		return
	if at_site(r):  # the party works the site by its orders (issue #109)
		r.job = _site_job(r)
		return
	if resting(r):  # hurt: rest in bed until healed (issue #110)
		r.job = _rest_job(r)
		return
	var dj = _dress_job(r, c)  # armor lying about for a slot they haven't filled (issue #140)
	if dj != null:
		r.job = dj
		return
	var aj = _arm_job(r, c)  # a guard takes a sword (issue #150)
	if aj != null:
		r.job = aj
		return
	if auto_craft:
		expand_queues()
	keep_meals_stocked()
	keep_made_stocked()
	keep_tools_stocked()
	# Their job's work, then hauling; Ada everything, in Slice 1's order (spec §5, issue #134).
	var jobs := job_list(r)
	for kind in CLAIM_ORDER:
		var j = _claim_kind(r, c, kind, jobs)
		if j != null:
			r.job = j
			return


## The kinds of work, in the order a resident looks for them. Hauling comes last, so a resident's
## own job always comes before it.
const CLAIM_ORDER := ["station", "enchant", "build", "farm", "gather", "haul"]


## A job of this kind for `r`, using only the jobs in `jobs`, or null.
func _claim_kind(r: Dictionary, c: Vector2i, kind: String, jobs: Array):
	match kind:
		"station":
			var st_jobs: Array = jobs.filter(func(jb): return jb in ["craft", "toolsmith", "cook", "lumber", "mason"])
			if st_jobs.is_empty():
				return null
			var benches := m.sites.filter(func(s): return s.done and is_station(s) and not s.queue.is_empty() and s.crafter == 0 and not bench_craftable(s, st_jobs).is_empty() and not _cooling(s))
			if not benches.is_empty():
				var own := claimed(r)  # their own station first, then any free one (issue #184)
				var b: Dictionary = own if benches.any(func(x): return is_same(x, own)) else _nearest_site(benches, c)
				var rec := bench_craftable(b, st_jobs)
				return _tagged(_craft_job(r, b, rec), recipe_job(rec))
			var dj = _try_deliver(r, c, m.sites.filter(func(s): return s.done and is_station(s) and not s.queue.is_empty()), st_jobs)
			if dj != null:
				return _tagged(dj, recipe_job(Defs.recipe(dj.target.queue[bench_active(dj.target, st_jobs)])))
		"enchant":  # the Enchanter: carry a book to the workshop, or work an order (issues #165, #166)
			if not jobs.has("enchant"):
				return null
			return _enchant_claim(r, c)
		"build":
			if not jobs.has("build"):
				return null
			var ready := m.sites.filter(func(s): return site_ready(s))
			if not ready.is_empty():
				return _tagged(_build_job(r, _nearest_site(ready, c)), "build")
			var dj = _try_deliver(r, c, m.sites.filter(func(s): return not s.done and site_open(s) and footprint_clear(s)))
			if dj != null:
				return _tagged(dj, "build")
			var lj = _light_job(r)
			if lj != null:
				return _tagged(lj, "build")
			var wj = _wire_job(r, c)
			if wj != null:
				return _tagged(wj, "build")
			return _road_claim(r, "build", jobs)
		"farm":
			if not jobs.has("farm"):
				return null
			var crop = _farm_work(c)
			if crop != null:
				return _tagged(_farm_job(r, crop), "farm")
		"gather":
			var targets: Array = []
			var can_gather: bool = r.get("hurt", 0) == 0  # the injured can't chop or mine (issue #110)
			if jobs.has("lumber") and can_gather:
				if not r.broken.axe or not tool_items("axe", 0).is_empty():
					for t in m.trees:
						if t.alive and t.des and t.claim == 0 and not _cooling(t):
							targets.append(t)
			if jobs.has("mason") and can_gather:
				if r.pick != null or not tool_items("pick", 0).is_empty():
					for b in m.boulders:
						if b.alive and b.des and b.claim == 0 and not _cooling(b):
							targets.append(b)
			if jobs.has("hunt"):
				for sh in m.sheep:
					if sh.alive and sh.des and sh.claim == 0 and not _cooling(sh):
						targets.append(sh)
			if not targets.is_empty():
				var t: Dictionary = nearest(targets, c)
				return _tagged(_hunt_job(r, t), "hunt") if t.kind == "animal" else _gather_job(r, t)
			var rj = _road_claim(r, "gather", jobs)
			if rj != null:
				return rj
			if r.role != "all":  # a gatherer's own work at their workstation; never Ada's (issue #177)
				var wj = _workstation_job(r, c)
				if wj != null:
					return wj
			if r.role == "hunt" and m.kind == "village" and not claimed(r).is_empty():  # down to the herd floor (issue #183)
				var prey := auto_prey()
				if not prey.is_empty():
					return _tagged(_hunt_job(r, nearest(prey, c)), "hunt")
		"haul":
			if not jobs.has("haul"):
				return null
			var pj = _pack_job(r, c)  # packing for an expedition comes before the stockpile
			if pj != null:
				return _tagged(pj, "haul")
			var cj = _chest_job(r, c)  # a chest for a storehouse (issue #189)
			if cj != null:
				return _tagged(cj, "haul")
			var ldj = _loader_job(r, c)  # the freight cart, while the loader is powered (issue #172)
			if ldj != null:
				return _tagged(ldj, "haul")
			var hs = _haul_source(c, carry_cap(r))
			if hs != null:
				return _tagged(_haul_job(r, hs.stack, hs.dest, hs.n, hs.get("pile", {})), "haul")
			return _road_claim(r, "haul", jobs)
	return null


func _tagged(j: Job, work: String) -> Job:
	j.work = work
	return j


## The nearest loose stack that has room in a stockpile (unloaded cargo first), as {stack, dest, n}, or null.
func _haul_source(c: Vector2i, carry := Tuning.CARRY):
	var piles := pile_map()
	var loose := stacks_where(func(s): return avail(s) > 0 and not stored(s, piles))
	# Where a type can go is worked out once a type, not once a stack, and before sorting: an idle
	# hauler with a full stockpile asks every tick, so finding nowhere to go has to cost little.
	var dests := {}  # type -> a stockpile cell with room for it, or null
	var piled := {}  # type -> whether a workstation's pile keeps it with room (issue #177)
	var stores := {}  # type -> whether a storehouse has room for it (issue #189)
	var anywhere := false
	for ls in loose:
		if not dests.has(ls.type):
			dests[ls.type] = zone_dest(ls.type)
			piled[ls.type] = pile_dest(ls.type, c) != null
			stores[ls.type] = store_dest(ls.type, c) != null
			anywhere = anywhere or dests[ls.type] != null or piled[ls.type] or stores[ls.type]
	var clearing := _clearing_cells()
	var bare: bool = m.zone.is_empty() and piles.is_empty() and not m.sites.any(func(s): return s.tpl == "storehouse" and s.done)
	if not anywhere and (not bare or clearing.is_empty() or not loose.any(func(s): return clearing.has(s.cell))):
		return null
	# An expedition's unloaded cargo goes first (issue #112), then what lies on a blueprint's footprint
	# (issue #205), then the nearest.
	loose.sort_custom(func(a, b):
		var ca: bool = a.get("cargo", false)
		var cb: bool = b.get("cargo", false)
		if ca != cb:
			return ca
		var fa: bool = clearing.has(a.cell)
		var fb: bool = clearing.has(b.cell)
		if fa != fb:
			return fa
		return manhattan(a.cell, c) < manhattan(b.cell, c))
	for ls in loose:
		var pd = pile_dest(ls.type, ls.cell) if piled[ls.type] else null  # a workstation's pile before the stockpile
		if pd != null:
			return {"stack": ls, "dest": pd.cell, "n": mini(mini(avail(ls), carry), pd.room), "pile": pd.site}
		var sd = store_dest(ls.type, ls.cell) if stores[ls.type] else null  # the nearest storehouse, then the stockpile
		if sd != null:
			return {"stack": ls, "dest": sd.cell, "n": mini(mini(avail(ls), carry), sd.room)}
		var dest = dests[ls.type]
		if dest == null:
			if bare and clearing.has(ls.cell):  # no storage at all: carried clear of the building, not teleported
				var spot = _clear_spot(ls.cell, clearing)
				if spot != null:
					return {"stack": ls, "dest": spot, "n": mini(avail(ls), carry)}
			continue
		var cap := Defs.stack_cap(ls.type)
		var here = m.items.get(dest)
		var room: int = cap - (here.n if here != null else 0)
		return {"stack": ls, "dest": dest, "n": mini(mini(avail(ls), carry), room)}
	return null


## Whether a loose stack has somewhere to be carried: a stockpile, a pile or a storehouse with room, or,
## with no storage at all, open ground beside the building.
func _stack_has_home(st: Dictionary) -> bool:
	if zone_dest(st.type) != null or pile_dest(st.type, st.cell) != null or store_dest(st.type, st.cell) != null:
		return true
	return m.zone.is_empty() and pile_map().is_empty() and not m.sites.any(func(s): return s.tpl == "storehouse" and s.done)


## The nearest open cell to `c` outside every footprint being cleared, for a stack that has no storage
## to go to yet (issue #205), or null.
func _clear_spot(c: Vector2i, clearing: Dictionary):
	for d in range(1, 9):
		for dx in range(-d, d + 1):
			for dy in range(-d, d + 1):
				if maxi(absi(dx), absi(dy)) != d:
					continue
				var p := c + Vector2i(dx, dy)
				if walkable(p) and not clearing.has(p) and not m.items.has(p) and not m.zone_res.has(p) and reserved_at(p) == null:
					return p
	return null


## A delivery to one of `dests` that still needs materials, or null. `jobs` limits a station's
## deliveries to recipes of those jobs.
func _try_deliver(r: Dictionary, c: Vector2i, dests: Array, jobs := []):
	for s in dests:
		if _cooling(s):
			continue
		var need := stage_needs(s, jobs)
		for t in need:
			var src := stacks_where(func(st): return st.type == t and avail(st) > 0 and not _on_finished_bench(st, s))
			if src.is_empty():
				continue
			var st: Dictionary = nearest(src, c)
			return _deliver_job(s, t, mini(mini(need[t], carry_cap(r)), avail(st)), st)
	return null


## A finished bench drops its crafts on its own cell; those aren't fed back in.
func _on_finished_bench(st: Dictionary, s: Dictionary) -> bool:
	return s.done and Rect2i(s.origin, s.size).has_point(st.cell)


func _nearest_site(list: Array, c: Vector2i) -> Dictionary:
	var best: Dictionary = list[0]
	for s in list:
		if manhattan(s.origin, c) < manhattan(best.origin, c):
			best = s
	return best


func _cooling(e: Dictionary) -> bool:
	return e.get("unreach_until", 0) > tick


func zone_dest(type: String):
	var cap := Defs.stack_cap(type)
	var empty = null
	for c in m.zone:
		if m.zone_res.has(c) or not walkable(c):
			continue
		var it = m.items.get(c)
		if it != null and it.type == type and it.n < cap:
			return c
		if it == null and empty == null:
			empty = c
	return empty


# ---------------------------------------------------------------- tick

func step() -> void:
	tick += 1
	var hunger_drop := 100.0 / Tuning.HUNGER_EMPTY_TIME * Tuning.DT
	for r in residents:
		if not r.get("away", false):
			r.hunger = maxf(0.0, r.hunger - hunger_drop)
	var prev := map_id
	for id in maps.keys():  # every map ticks, whether or not anyone is looking at it
		use_map(id)
		_step_map()
	use_map("village")
	use_slot("overworld")
	_step_arrivals()
	_apply_claims()
	if tick % 10 == 0:
		assign_workstations()
	use_map(prev)
	var kinds := {}
	var working := 0
	for r in residents:
		if r.job != null and not (r.job.kind in ["move", "arrive", "stage", "road", "rest", "hurt", "commute", "unload"]):
			kinds[r.job.kind] = true
			working += 1
	if working >= 2 and kinds.size() >= 2:
		stats.division = true
	_step_freight()
	if tick % 10 == 5:
		_step_devices()
	if tick % 10 == 0 and not expeditions.nether.is_empty():  # a party in trouble in the Nether (issue #158)
		on_slot("nether", _check_stranded)
	if tick % 5 == 0:
		compute_stuck()


## One tick of the current map: what grows, the sheep, and the residents on it.
func _step_map() -> void:
	if m.kind == "village" and tick % int(Tuning.WEAR_DECAY_SECS * Tuning.TPS) == 0 and not m.wear.is_empty():
		_decay_wear()
	for b in m.bushes:
		if b.berries < Tuning.BUSH_MAX:
			b.regrow += Tuning.DT
			if b.regrow >= Tuning.BUSH_REGROW:
				b.regrow = 0.0
				b.berries += 1
				rev += 1
	for k in m.farm:
		var crop: Dictionary = m.farm[k]
		if crop.grow >= 0.0 and crop.grow < Tuning.WHEAT_GROW:
			var before := crop_stage(crop)
			crop.grow = minf(Tuning.WHEAT_GROW, crop.grow + Tuning.DT)
			if crop_stage(crop) != before:
				rev += 1
	for t in m.trees:  # saplings grow into trees (issue #177)
		if t.alive and not grown(t):
			var before := tree_stage(t)
			t.grow += Tuning.DT
			if t.grow >= Tuning.SAPLING_GROW:
				t.grow = -1.0
			if tree_stage(t) != before:
				rev += 1
	for sh in m.sheep:
		if sh.alive:
			_step_sheep(sh)
	if m.id == Meadow.ID:
		_regrow_herds()
	if not m.pens.is_empty():
		_step_pens()
	if not m.creatures.is_empty():
		_step_creatures()
	for r in residents:
		if r.map != map_id:
			continue
		use_slot(slot_of(r))
		if r.away:
			if tick >= r.back_at:
				if r.trip == "village":
					_arrive_home(r)
				else:
					_arrive_at_site(r)
			continue
		_step_resident(r)
	for sl in SLOTS:  # each party of this map's realm (issue #158)
		if SLOT_REALM[sl] == realm_of(map_id):
			use_slot(sl)
			_step_site()
	use_slot(realm_of(map_id))
	if map_id == "village":
		for sl in SLOTS:
			if expeditions[sl].get("unloading", false):
				on_slot(sl, _step_unload)
	elif map_id == Road.ID:
		_step_cart()
	use_slot("overworld")
	if auto_craft and tick % 10 == 0:
		expand_queues()
	if tick % 10 == 0:
		_set_chests()
		keep_meals_stocked()
		keep_made_stocked()
		keep_tools_stocked()
	if tick % 10 == 0:
		for s in m.sites:
			if not s.done and s.tpl != "track":  # the cut is cleared by the player's order (issue #119)
				_mark_obstacles(s)


## Where an animal may wander (issue #139): never through a gate; a penned one stays inside its pen,
## and a wild one keeps out of pens it isn't already in.
func _grazes(a: Dictionary, n: Vector2i) -> bool:
	if m.pens.is_empty():
		return true
	if m.gates.has(n):
		return false
	if a.get("pen", 0) != 0:
		var p := pen(a.pen)
		return p.is_empty() or pen_inside(p).has_point(n)
	var at = pen_at(n)
	return at == null or Rect2i(at.rect).has_point(a.cell)


## Sheep wander one cell at a time with pauses, staying on walkable ground. A sheep being hunted
## stands still once its hunter is next to it.
func _step_sheep(sh: Dictionary) -> void:
	if sh.get("led_by", 0) != 0:  # led to a pen: it follows a step behind (issue #139)
		var lr := resident(sh.led_by)
		if lr.is_empty() or lr.map != map_id or lr.job == null or lr.job.kind != "lead":
			sh.led_by = 0
			return
		var gap: Vector2 = lr.pos - sh.pos
		if gap.length() > 1.0:
			sh.pos += gap.normalized() * minf(gap.length() - 1.0, Tuning.WALK * Tuning.DT)
			sh.cell = Vector2i(roundi(sh.pos.x), roundi(sh.pos.y))
		sh.dest = null
		return
	if sh.claim != 0:
		var hunter := resident(sh.claim)
		if not hunter.is_empty() and hunter.pos.distance_to(sh.pos) <= 1.5:
			return
	if sh.dest == null:
		sh.wait -= Tuning.DT
		if sh.wait > 0.0:
			return
		var dirs: Array = DIRS.duplicate()
		for i in range(dirs.size() - 1, 0, -1):
			var k := rng.randi_range(0, i)
			var tmp = dirs[i]
			dirs[i] = dirs[k]
			dirs[k] = tmp
		for d in dirs:
			var n: Vector2i = sh.cell + d
			if walkable(n) and _grazes(sh, n):
				sh.dest = n
				break
		if sh.dest == null:
			sh.wait = Tuning.SHEEP_PAUSE[0]
		return
	var dest: Vector2i = sh.dest
	if not walkable(dest):
		sh.dest = null
		return
	var to: Vector2 = Vector2(dest) - sh.pos
	var step_len := Tuning.SHEEP_WALK * Tuning.DT
	if to.length() <= step_len:
		sh.pos = Vector2(dest)
		sh.cell = dest
		sh.dest = null
		sh.wait = rng.randf_range(Tuning.SHEEP_PAUSE[0], Tuning.SHEEP_PAUSE[1])
	else:
		sh.pos += to.normalized() * step_len
		sh.cell = Vector2i(roundi(sh.pos.x), roundi(sh.pos.y))


func _step_resident(r: Dictionary) -> void:
	if r.get("burn", 0.0) > 0.0:
		_burn_step(r)
	if r.hunger <= 0.0 and r.job != null and r.job.kind != "eat":
		fail_job(r)  # starving: drop everything and go eat
	if r.job == null:
		if r.arriving:
			return
		_claim(r)
		if r.job == null:
			return
	var j: Job = r.job
	if j.i >= j.steps.size():
		r.job = null
		return
	var res = _run_step(r, j, j.steps[j.i])
	if res is bool and res:
		j.i += 1
		if j.i >= j.steps.size():
			r.job = null
			r.progress = -1.0
			_release(r, j)
			if j.work != "":
				gain_xp(r, j.work)
	elif res is String:
		fail_job(r, res)


# ---------------------------------------------------------------- the meadow (issues #50, #137)
# The rules live in meadow_trip.gd (#305); these forward to them.

func meadow_sign() -> Vector2i:
	return MeadowTrip.meadow_sign(self)


func sign_for(dest: String) -> Vector2i:
	return MeadowTrip.sign_for(self, dest)


func village_portal() -> Dictionary:
	return MeadowTrip.village_portal(self)


func portal_lit() -> bool:
	return MeadowTrip.portal_lit(self)


func _regrow_herds() -> void:
	MeadowTrip._regrow_herds(self)


func herds(id := Meadow.ID) -> Dictionary:
	return MeadowTrip.herds(self, id)


func back_in(r: Dictionary) -> float:
	return MeadowTrip.back_in(self, r)


# ---------------------------------------------------------------- pens and breeding (issue #139)
# The rules live in pens.gd (#305); these forward to them.

static func pen_edge(p: Dictionary) -> Array:
	return Pens.pen_edge(p)


static func pen_inside(p: Dictionary) -> Rect2i:
	return Pens.pen_inside(p)


static func pen_done(p: Dictionary) -> bool:
	return Pens.pen_done(p)


static func pen_room(p: Dictionary) -> int:
	return Pens.pen_room(p)


func pen(id: int) -> Dictionary:
	return Pens.pen(self, id)


func pen_at(c: Vector2i):
	return Pens.pen_at(self, c)


func penned(p: Dictionary) -> Array:
	return Pens.penned(self, p)


func pen_free(p: Dictionary) -> int:
	return Pens.pen_free(self, p)


func pen_check(rect: Rect2i) -> String:
	return Pens.pen_check(self, rect)


func paint_pen(rect: Rect2i) -> String:
	return Pens.paint_pen(self, rect)


func remove_pen(p: Dictionary) -> void:
	Pens.remove_pen(self, p)


func fence_left(id := Meadow.ID) -> int:
	return Pens.fence_left(self, id)


func feed_pairs(p: Dictionary) -> Array:
	return Pens.feed_pairs(self, p)


func wheat_wanted(id := Meadow.ID) -> int:
	return Pens.wheat_wanted(self, id)


func tending() -> bool:
	return Pens.tending(self)


const PEN_SUPPLIES = Pens.PEN_SUPPLIES

# ---------------------------------------------------------------- mission types (issue #154)

## The objectives a Nether plan can have (brief §8, Missions), in the planner's order: what it is, and when the party comes home
## by default.
const OBJECTIVES := {
	"survey": {"name": "Survey", "sub": "The first crossing: walk the landing's landmarks and build the shelter.", "returns": "the landing is surveyed and the shelter built"},
	"scout": {"name": "Scout", "sub": "Walk a route out of the landing and reveal it, with the site at its end.", "returns": "the route is scouted"},
	"gather": {"name": "Gather", "sub": "Bring back a material from a scouted site.", "returns": "the cargo target is reached"},
	"trade": {"name": "Trade", "sub": "Carry gold to the piglins, from the table shown first.", "returns": "the trades are made"},
	"build": {"name": "Build", "sub": "Raise a shelter, a crossing or a depot with materials the party carries.", "returns": "the building is done"},
	"fortress": {"name": "Fortress", "sub": "Delve the fortress entrance for blaze rods and rare salvage.", "returns": "the delve is done, or the party is hurt"},
	"rescue": {"name": "Rescue", "sub": "Reach a stranded party and bring them home.", "returns": "the stranded party is reached"},
}


## The destinations an objective can use now, as [{dest, label, route}], and why there are none when there aren't:
## a scouted route's site for a gather, trade or fortress mission, an unscouted route to scout, the landing to survey or build on.
func objective_destinations(obj: String) -> Array:
	var out: Array = []
	match obj:
		"survey":
			if not maps[NetherLanding.ID].surveyed and maps[NetherLanding.ID].known:
				out.append({"dest": NetherLanding.ID, "label": "The portal landing", "route": ""})
		"scout":
			if maps[NetherLanding.ID].known:
				for rk in NetherRoute.ROUTES:
					if not maps[NetherRoute.ROUTES[rk].id].surveyed:
						out.append({"dest": NetherLanding.ID, "label": NetherRoute.ROUTES[rk].name.substr(8), "route": rk})
		"gather", "trade", "fortress":
			var rk: String = {"gather": "quartz", "trade": "piglin", "fortress": "fortress"}[obj]
			if maps[NetherRoute.ROUTES[rk].site].known:
				out.append({"dest": NetherRoute.ROUTES[rk].site, "label": NetherRoute.ROUTES[rk].site_name.substr(8), "route": ""})
		"build":
			var sh := shelter_site()
			if maps[NetherLanding.ID].known and not sh.get("done", false):
				out.append({"dest": NetherLanding.ID, "label": "A shelter on the landing", "route": ""})
			if maps[NetherRoute.ROUTES.quartz.id].surveyed and maps[NetherRoute.ROUTES.quartz.site].known and not nline_complete():  # issue #159
				out.append({"dest": NetherRoute.ROUTES.quartz.site, "label": "The Nether line to the quartz site", "route": "", "line": true})
			if maps[NetherLanding.ID].known and not portal_station().is_empty() and not pline_nether_done():  # issue #168
				out.append({"dest": NetherLanding.ID, "label": "The portal line from the landing", "route": "", "pline": true})
		"rescue":  # a stranded party, if no rescue is already out (issue #158)
			var lost: Dictionary = expeditions.nether
			if lost.has("stranded") and expeditions.rescue.is_empty():
				out.append({"dest": lost.stranded.at, "label": "Rescue the party at the %s" % maps[lost.stranded.at].name.substr(8).to_lower(), "route": ""})
	return out


## Why an objective has nowhere to go, in the player's words.
func objective_why_none(obj: String) -> String:
	if not maps[NetherLanding.ID].known:
		return "Light the portal first"
	match obj:
		"survey":
			return "The landing is already surveyed"
		"scout":
			return "Every route is scouted"
		"gather":
			return "No site to gather from: scout the route to the quartz site first"
		"trade":
			return "No one to trade with: scout the route to the piglin camp first"
		"fortress":
			return "No fortress to delve: scout the route to the fortress first"
		"build":
			return "Nothing to build yet: the shelter stands"
		"rescue":
			return "A rescue party is already out" if not expeditions.rescue.is_empty() else "No one is stranded"
	return ""


## A Nether plan for an objective, with its defaults, or {} when it has no destination (issue #154). `pick` is one of the
## objective's destinations; the first if left out.
func nether_plan(obj: String, pick := {}) -> Dictionary:
	var dests := objective_destinations(obj)
	if dests.is_empty():
		return {}
	if pick.is_empty():
		pick = dests[0]
	var plan := new_plan(pick.dest)
	plan.objective = obj
	plan.shelter = false
	plan.cobble = 0
	plan.planks = 0
	match obj:
		"survey":
			var build_it: bool = not shelter_site().get("done", false)
			plan.shelter = build_it
			plan.cobble = Tuning.SHELTER_COST.cobble if build_it else 0
			plan.planks = Tuning.SHELTER_COST.plank if build_it else 0
		"scout":
			plan.target = {"item": "scout", "n": 1, "route": pick.route}
		"build":
			plan.target = {"item": "build", "n": 1}
			plan.shelter = true
			plan.cobble = Tuning.SHELTER_COST.cobble
			plan.planks = Tuning.SHELTER_COST.plank
			if pick.get("line", false):  # the Nether line: what's left to build, as much as three can carry (issue #159)
				plan.target = {"item": "line", "n": 1}
				plan.shelter = false
				_line_supplies(plan)
			if pick.get("pline", false):  # the portal line's Nether side (issue #168)
				plan.target = {"item": "pline", "n": 1}
				plan.shelter = false
				_pline_supplies(plan)
		"gather":  # the first thing the site gives, as much as 8, with a spare pickaxe (issue #155)
			plan.picks = 1
			var first: Array = plan_targets(plan.dest)
			if not first.is_empty():
				aim_plan(plan, first[0].item, 8)
		"trade":  # the gold the village has, up to what the packs take (issue #156)
			plan.target = {"item": "trade", "n": 1}
			plan.gold = mini(free_count("gold_ingot"), 6)
		"fortress":
			plan.target = {"item": "fortress", "n": 1}
		"rescue":  # extra meals and a flint and steel (carried automatically) for the stranded; sets out with both slots taken (issue #158)
			plan.target = {"item": "rescue", "n": 1}
			plan.rescue = true
			plan.meals = 6
	return plan


## What a party is told before it commits (brief §8): the dangers known where it's going, the creatures about, the risks of
## the crossing, and what the objective needs. Lines of text.
func plan_briefing(plan: Dictionary) -> Array:
	var out: Array = []
	var obj: String = plan.get("objective", "survey")
	var dest: String = plan.dest
	var rk: String = plan.target.get("route", "") if plan.target.item == "scout" else ""
	var rep := site_report(NetherRoute.ROUTES[rk].id if rk != "" else dest)
	if rep.hazards.is_empty():
		out.append("No dangers are known there yet" if not rep.visited else "No dangers known")
	for hz in rep.hazards:
		out.append("Danger: " + hz)
	if plan.party.any(func(id): return needs_sword(resident(id))) or not plan.party.any(func(id): return resident(id).role in ["guard", "all"]):
		out.append("Risk: no one in the party can fight")
	if realm_of(dest) == "nether" and tool_items("sword", 0).is_empty() and not plan.party.any(func(id): return resident(id).get("sword") != null):
		out.append("Risk: no sword in the village")
	if stacks_where(func(s): return s.type == "flint_and_steel" and avail(s) > 0).is_empty():
		out.append("Risk: no flint and steel to carry, so if the portal goes out the party waits for the village to light it")
	if plan.target.item == "line":  # issue #159
		out.append(nline_text())
	if plan.target.item == "pline":  # issue #168
		out.append(pline_text())
	if obj == "trade":  # the fixed table and the rule, before the party commits (issue #156)
		for t in Defs.TRADES:
			out.append("Trade: " + Defs.trade_text(t))
		out.append("Rule: " + Defs.PIGLIN_RULE)
	if obj == "rescue":
		out.append("A rescue may set out even when both parties are out")
	out.append("Comes home when %s" % OBJECTIVES[obj].returns)
	return out


## Whether the party is out to trade with the piglins (issue #156).
func trading() -> bool:
	return expedition.get("target", {}).get("item", "") == "trade"


## Whether the party is out to scout a route (issue #153).
func scouting() -> bool:
	return expedition.get("target", {}).get("item", "") == "scout"


## A plan to scout one of the routes out of the landing: "quartz", "piglin" or "fortress".
func scout_plan(route: String) -> Dictionary:
	var plan := new_plan(NetherLanding.ID)
	plan.target = {"item": "scout", "n": 1, "route": route}
	return plan


## Whether the party is out to survey a place rather than to bring something back (issue #148).
func surveying() -> bool:
	return expedition.get("target", {}).get("item", "") == "survey"


## Penned animals over the herd size the party keeps of each kind, when tending the pens: grown ones
## that aren't waiting to breed.
func pen_surplus() -> Array:
	var by := {}
	for a in m.sheep:
		if a.alive and a.get("pen", 0) != 0:
			if not by.has(a.species):
				by[a.species] = []
			by[a.species].append(a)
	var out: Array = []
	for sp in by:
		var grown: Array = by[sp].filter(func(a): return not a.get("young", false) and a.get("fed_at", -1) < 0)
		out.append_array(grown.slice(0, maxi(0, by[sp].size() - expedition.target.n)))
	return out


## Whether the party can still do something for the pens: build a fence with the sticks it has, lead
## a marked animal into a pen with room, or feed a pair with the wheat it has.
func pen_work() -> bool:
	var sup: Dictionary = expedition.get("supplies", {})
	if sup.get("stick", 0) >= Tuning.FENCE_STICKS and m.pens.any(func(p): return not pen_done(p)):
		return true
	if m.sheep.any(func(a): return a.alive and a.get("lead", false) and a.get("pen", 0) == 0) and m.pens.any(func(p): return pen_done(p) and pen_free(p) > 0):
		return true
	return sup.get("wheat", 0) >= 2 * Tuning.FEED_WHEAT and m.pens.any(func(p): return not feed_pairs(p).is_empty())


## Marks animals to be led into a pen (the Lead order), or unmarks them. Penned animals are left alone.
func designate_lead(rect: Rect2i, single = null) -> void:
	var hit: Array = [single] if single != null else m.sheep.filter(func(a): return a.alive and rect.has_point(a.cell))
	hit = hit.filter(func(a): return a.get("pen", 0) == 0)
	var all_on := not hit.is_empty() and hit.all(func(a): return a.get("lead", false))
	for a in hit:
		a.lead = not (single != null and all_on)
		a.unreach_until = 0
		if a.lead and a.des:
			a.des = false
			if a.claim != 0:
				var r := resident(a.claim)
				if not r.is_empty() and r.job != null and r.job.kind == "gather" and is_same(r.job.target, a):
					fail_job(r)
	rev += 1


## Building a pen's fences: sticks from the packs at the entrance, then a fence at a time, nearest
## first, and any sticks left over back into the packs.
func _fence_job(r: Dictionary, c: Vector2i):
	var have: int = expedition.get("supplies", {}).get("stick", 0)
	var n := mini(carry_cap(r), have / Tuning.FENCE_STICKS)
	if n <= 0:
		return null
	var todo: Array = []
	for p in m.pens:
		for e in pen_edge(p):
			if not p.built.has(e) and not _fence_claims.has(e):
				todo.append({"cell": e, "pen": p})
	if todo.is_empty():
		return null
	var picked: Array = []
	var at := m.entrance
	while picked.size() < n and not todo.is_empty():
		var best := 0
		for i in todo.size():
			if manhattan(todo[i].cell, at) < manhattan(todo[best].cell, at):
				best = i
		at = todo[best].cell
		picked.append(todo.pop_at(best))
	var j := Job.new("fence", "Building a pen", "the pen")
	j.target = picked[0].pen
	j.work = "build"
	j.step(_goto([m.entrance], false))
	j.step({"op": "take_supply", "type": "stick", "n": picked.size() * Tuning.FENCE_STICKS})
	for t in picked:
		_fence_claims[t.cell] = r.id
		j.hold({"t": "fence", "cell": t.cell})
		j.step(_goto([t.cell], true))
		j.step({"op": "work", "what": "fence", "pen": t.pen, "cell": t.cell, "label": "Building a pen"})
	j.step(_goto([m.entrance], false))
	j.step({"op": "put_back", "type": "stick"})
	return j


## A fence or the gate goes up. Any animal standing there steps aside; once the last one is up, the
## animals inside are penned.
func _put_fence(p: Dictionary, c: Vector2i) -> void:
	p.built[c] = true
	if c == p.gate:
		m.gates[c] = true
	else:
		m.fences[c] = true
	_occ_dirty = true
	var inside := pen_inside(p)
	for a in m.sheep:
		if a.alive and a.cell == c:
			var to := c
			for d in DIRS:
				var n: Vector2i = c + d
				if walkable(n) and not m.gates.has(n) and (inside.has_point(n) or to == c):
					to = n
			a.cell = to
			a.pos = Vector2(to)
			a.dest = null
	if pen_done(p):
		for a in m.sheep:
			if a.alive and a.get("pen", 0) == 0 and inside.has_point(a.cell):
				a.pen = p.id
				a.lead = false
		stats.pens = stats.get("pens", 0) + 1
		_toast("A pen is finished, with room for %d animals." % pen_room(p))
	rev += 1


## Leading a marked animal into a pen with room (issue #139): catch it, walk it to the gate, and let
## it in.
func _lead_job(r: Dictionary, c: Vector2i):
	var leads := m.sheep.filter(func(a): return a.alive and a.get("lead", false) and a.get("pen", 0) == 0 and a.claim == 0 and not _cooling(a))
	if leads.is_empty():
		return null
	var a: Dictionary = nearest(leads, c)
	var pens := m.pens.filter(func(p): return pen_done(p) and pen_free(p) > 0)
	if pens.is_empty():
		return null
	pens.sort_custom(func(x, y): return manhattan(x.gate, a.cell) < manhattan(y.gate, a.cell))
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
	j.step(_goto([p.gate], false))
	j.step({"op": "pen_in", "target": a, "pen": p})
	return j


## Feeding a pair in a pen (issue #139): wheat from the packs, one for each, and a young one follows.
func _feed_job(r: Dictionary, c: Vector2i):
	if expedition.get("supplies", {}).get("wheat", 0) < 2 * Tuning.FEED_WHEAT:
		return null
	var pens: Array = m.pens.duplicate()
	pens.sort_custom(func(x, y): return manhattan(x.gate, c) < manhattan(y.gate, c))
	for p in pens:
		var pairs := feed_pairs(p)
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
		j.step(_goto([m.entrance], false))
		j.step({"op": "take_supply", "type": "wheat", "n": 2 * Tuning.FEED_WHEAT})
		j.step({"op": "chase", "target": pair[0], "planned_for": null})
		j.step({"op": "work", "what": "feed", "pair": pair, "label": "Feeding the %s" % many})
		return j
	return null


## Each tick on a map with pens: fed pairs have their young, and the young grow up.
func _step_pens() -> void:
	for a in m.sheep:
		if a.alive and a.get("young", false) and tick >= a.grown_at:
			a.young = false
			rev += 1
	for p in m.pens:
		var ready := {}
		for a in penned(p):
			if a.get("fed_at", -1) >= 0 and tick >= a.fed_at + int(Tuning.BREED_TIME * Tuning.TPS):
				if not ready.has(a.species):
					ready[a.species] = []
				ready[a.species].append(a)
		for sp in ready:
			var l: Array = ready[sp]
			for i in range(0, l.size() - 1, 2):
				_breed(p, l[i], l[i + 1])


func _breed(p: Dictionary, a: Dictionary, b: Dictionary) -> void:
	for x in [a, b]:
		x.fed_at = -1
		x.cool_until = tick + int(Tuning.BREED_COOLDOWN * Tuning.TPS)
	var kid := add_animal(a.cell, a.species)
	kid.pen = p.id
	kid.young = true
	kid.grown_at = tick + int(Tuning.GROW_TIME * Tuning.TPS)
	stats.bred = stats.get("bred", 0) + 1
	rev += 1
	_toast("A %s was born in the pen." % Defs.SPECIES[a.species].young)


## Travelers, in the order they arrive. The first is always Tomas.
## Each traveler's name and tunic (issue #79): hues far apart from each other, from the grass and
## from the chalk marks, so residents can be told apart on the map. A tenth resident repeats Tomas's.
const ADA_TUNIC := "2E8C9E"
const TRAVELERS := [["Tomas", "A8457A"], ["Mira", "D9792B"], ["Jonas", "3C5DB0"], ["Elsa", "7B52B8"],
	["Bram", "8E2F3E"], ["Ines", "2A9A78"], ["Otto", "A9AEB8"], ["Lena", "E58AA8"]]


## A finished house whose bed nobody sleeps in yet, or null.
func free_house():
	for s in m.sites:
		if s.tpl == "house" and s.done and s.owner == 0:
			return s
	return null


## No free bed, no arrival (spec §7): while a finished house has a free bed, a traveler comes after
## the arrival delay. One walks in at a time.
func _step_arrivals() -> void:
	if residents.any(func(r): return r.arriving):
		return
	if arrival_at < 0:
		if free_house() != null:
			arrival_at = tick + int(Tuning.ARRIVAL_DELAY * Tuning.TPS)
	elif tick >= arrival_at:
		arrival_at = -1
		if free_house() != null:
			_arrive()


func _arrive() -> void:
	arrived = true
	var spawn := Vector2i(0, h - 1)
	if not walkable(spawn):
		spawn = nearest_walkable(spawn)
	var n := residents.size() - 1
	var who: Array = TRAVELERS[n % TRAVELERS.size()]
	var t := add_resident(who[0] if n < TRAVELERS.size() else "%s %d" % [who[0], n / TRAVELERS.size() + 1], who[1], spawn)
	var skill: String = Defs.SKILL_POOL[rng.randi_range(0, Defs.SKILL_POOL.size() - 1)]
	if n == 0:
		skill = "lumber"  # the first traveler fells trees from the chopping block the founding ends on (issue #182)
	t.jobs[skill].xp = Tuning.SKILL_LEVELS[Tuning.ARRIVAL_LEVEL - 2]
	t.role = skill  # an arrival starts with the job they're skilled in (issue #134)
	walk_in(t)
	_toast("%s, a skilled %s, has arrived." % [t.name, Defs.JOB_SKILLED[skill]], t.id)


func walk_in(t: Dictionary) -> void:
	t.arriving = false
	for s in m.sites:
		if s.tpl == "house" and s.done and s.owner == 0:
			t.arriving = true
			var j := Job.new("arrive", "Walking to the new house", "the new house")
			j.hold({"t": "arriving"})
			j.step(_goto(site_cells(s), true))
			j.step({"op": "move_in", "site": s})
			t.job = j
			return


func _toast(text: String, res_id := 0, site_id := 0) -> void:
	events.append({"type": "toast", "text": text, "res_id": res_id, "site_id": site_id, "map": map_id})


# ---------------------------------------------------------------- stuck reasons

## `waiting` marks a standing order short of materials (issue #77): advice, not a blocker, so it
## gets no flag and sits in the stuck list's dim Waiting tier.
## `decision` names a choice the game is waiting on the player for ("freight"), shown apart from the blockers (issue #296). It is also `waiting`: no flag on the map.
func _add_stuck(who: String, why: String, at: Vector2, height: float, fk: String, fid: int, hidden := false, waiting := false, decision := "") -> void:
	# The same problem keeps its age while its count changes ("4 more planks" -> "3 more planks").
	var key := "%s|%s|%d|%s|%s" % [map_id, fk, fid, who, _DIGITS.sub(why, "#", true)]
	if not _stuck_since.has(key):
		_stuck_since[key] = tick
	stuck.append({"who": who, "why": why, "map": map_id, "cell": at, "height": height, "focus_kind": fk, "focus_id": fid, "hidden": hidden,
		"waiting": waiting or decision != "", "decision": decision, "key": key, "since": _stuck_since[key]})


static var _DIGITS := RegEx.create_from_string("\\d+")


## Works out every map's stuck reasons. Each carries its map, so focusing it can switch the view.
func compute_stuck() -> void:
	stuck = []
	var prev := map_id
	for id in maps.keys():
		use_map(id)
		_stuck_on_map()
	use_map(prev)
	var now := {}
	for s in stuck:
		now[s.key] = _stuck_since[s.key]
	_stuck_since = now


func _stuck_on_map() -> void:
	var on_here := here()
	var any_pick := not tool_items("pick", 0).is_empty()
	for r in on_here:
		if r.pick != null:
			any_pick = true
	var first := true
	for b in m.boulders:
		if b.alive and b.des and not any_pick:
			_add_stuck(block_name(b), "Needs a pickaxe", Vector2(b.cell) + Vector2(0.5, 0.5), 1.1, "boulder", b.id, not first)
			first = false
	for s in m.sites:
		var tpl: Dictionary = Defs.TEMPLATES[s.tpl]
		var mid := Vector2(s.origin) + Vector2(s.size) / 2.0
		if s.tpl == "portal" and s.done:  # the frame stands: it wants flint and steel (issue #147)
			if not s.lit and s.builder == 0 and stacks_where(func(x): return x.type == "flint_and_steel" and avail(x) > 0).is_empty():
				_add_stuck("Portal", "Needs flint and steel to light", mid, 2.9, "site", s.id)
			continue
		if s.tpl == "track":  # only the segment being laid speaks up; the rest wait their turn (issue #121)
			if s.done or s.seg != next_track():
				continue
			var bl := track_blocker(s.seg)
			if bl != "":
				_add_stuck(tpl.name, "Track: %s first" % bl.to_lower(), mid, 0.4, "site", s.id)
			elif not _staffed("build"):
				_add_stuck(tpl.name, "Track: no one is a builder", mid, 0.4, "site", s.id)
			elif line_short() > 0:
				_add_stuck(tpl.name, "Track: needs %d more rails" % line_short(), mid, 0.4, "site", s.id)
			continue
		if not s.done and not footprint_clear(s):
			var ob := site_obstacles(s)
			var nb: int = ob.boulders.size()
			if nb and not any_pick:
				_add_stuck(tpl.name, "Needs a pickaxe to clear " + ("a boulder" if nb == 1 else "%d boulders" % nb), mid, 0.6, "site", s.id)
			if not ob.items.is_empty():  # loose stacks to carry off (issue #205)
				var homeless: Array = ob.items.filter(func(st): return not _stack_has_home(st))
				if not homeless.is_empty():
					_add_stuck(tpl.name, "Clearing: no room in a stockpile for %s" % ", ".join(stacks_text(homeless)), mid, 0.6, "site", s.id)
				else:
					_add_stuck(tpl.name, "Clearing: %s to move" % clearing_text(ob), mid, 0.6, "site", s.id, false, true)
			continue
		var cost := {}
		var label := ""
		var verb := "needs"
		var standing := false
		if not s.done:
			var st := current_stage(s)
			cost = st.cost
			label = "Bench" if s.tpl == "bench" else st.name
			verb = st.verb
		elif is_station(s) and not s.queue.is_empty() and s.crafter == 0 and bench_craftable(s).is_empty() and bench_active(s) < 0:
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
			var short: int = cost[k] - s.store.get(k, 0) - s.incoming.get(k, 0) - free_count(k)
			if m.kind == "route":  # the road is supplied from the village (issue #119)
				short -= on_map("village", free_count.bind(k))
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
				why = "Toolsmith needs %d more %s for a spare %s" % [worst_n, it.one if worst_n == 1 else it.many, TOOL_NAMES[kind]]
			_add_stuck(station_name(s), why,
				mid, site_height(s) + 0.4, "site", s.id, false, standing)
	_stuck_unstaffed()
	_stuck_workstations()
	_stuck_freight()
	_stuck_farm()
	for sl in SLOTS:
		on_slot(sl, _stuck_expedition)
	for sl in SLOTS:
		if SLOT_REALM[sl] == realm_of(map_id):
			use_slot(sl)
			_stuck_site()
	use_slot("overworld")
	var has_food: bool = food_available() if m.kind != "route" and m.kind != "walk" else on_map("village", food_available)  # the road eats from home
	for r in on_here:
		var at: Vector2 = r.pos + Vector2(0.5, 0.5)
		if r.hunger <= 0.0 and not has_food:
			_add_stuck(r.name, "Starving: no food stored", at, 1.6, "res", r.id)
		elif r.hunger < Tuning.HUNGRY_BELOW and not has_food:
			_add_stuck(r.name, "Hungry: no food stored", at, 1.6, "res", r.id)
		for k in ["axe", "pick"]:
			if r.broken[k] and r[k] == null:
				var tname := "Axe" if k == "axe" else "Pickaxe"
				if _spare_queued(k):
					_add_stuck(r.name, "%s broke. Waiting for the toolsmith’s spare" % tname, at, 1.6, "res", r.id)
				elif not has_toolsmith():
					_add_stuck(r.name, "%s broke. Craft one at the bench, or make someone the toolsmith" % tname, at, 1.6, "res", r.id)
				else:
					_add_stuck(r.name, "%s broke. Needs a new %s" % [tname, tname.to_lower()], at, 1.6, "res", r.id)
		if r.note != null and r.note.until > tick:
			_add_stuck(r.name, r.note.text, at, 1.6, "res", r.id)
		if r.get("hurt", 0) > 0:  # issue #110: rest is a reason, not a blocker
			var left := ceili(r.heal / (1.0 if _has_bed(r) else Tuning.HEAL_NO_BED))
			var burned: bool = "burn" in str(r.get("hurt_cause", ""))  # the Nether's fire and lava say so (issue #149)
			var word := "Burned" if burned else "Injured"
			var why := "%s: can't mine, and works slower" % word if r.hurt == 1 else "Seriously %s: waiting at the entrance" % ("burned" if burned else "hurt")
			if resting(r):
				why = "%s, resting in bed (%d s)" % [word if r.hurt == 1 else "Seriously " + ("burned" if burned else "hurt"), left] if _has_bed(r) else "%s, resting: no bed of their own, so it's slower (%d s)" % [word, left]
			elif r.map == NetherLanding.ID and shelter_site().get("done", false):  # issue #152
				why = "%s, resting at the shelter (%d s)" % [word if r.hurt == 1 else "Seriously " + ("burned" if burned else "hurt"), ceili(r.heal / Tuning.HEAL_NO_BED)]
			_add_stuck(r.name, why, at, 1.6, "res", r.id, false, true)
	if m.zone.is_empty():
		for k in m.farm:
			if m.farm[k].grow < 0.0 and m.items.has(k):
				_add_stuck("Farm", "Harvested wheat needs a stockpile before replanting", Vector2(k) + Vector2(0.5, 0.5), 0.6, "crop", m.farm[k].id)
				break
	var stores := m.sites.filter(func(s): return s.tpl == "storehouse" and s.done)
	for s in stores:  # issue #189
		var at := Vector2(s.origin) + Vector2(1.5, 1.5)
		if not walkable(store_door(s)):
			_add_stuck("Storehouse", "Can’t reach the storehouse: its door is blocked", at, 2.2, "site", s.id)
		elif s.get("chests", 0) == 0:
			_add_stuck("Storehouse", "No chests yet. Craft one at the bench (8 planks)", at, 2.2, "site", s.id)
	if not m.zone.is_empty() or not stores.is_empty():
		var piles := pile_map()
		var loose := stacks_where(func(s): return avail(s) > 0 and not stored(s, piles) and s.type != "chest")
		var full := not loose.is_empty()
		var tried := {}
		for s in loose:
			if tried.has(s.type):
				continue
			tried[s.type] = true
			if zone_dest(s.type) != null or store_dest(s.type, s.cell) != null:
				full = false
				break
		if full:
			var room := stores.filter(func(s): return s.get("chests", 0) > 0 and walkable(store_door(s)))
			if not room.is_empty():
				_add_stuck("Storehouse", "The storehouse is full", Vector2(room[0].origin) + Vector2(1.5, 1.5), 2.2, "site", room[0].id)
			if not m.zone.is_empty():
				_add_stuck("Stockpile", "Stockpile is full", Vector2(m.zone.keys()[0]) + Vector2(0.5, 0.5), 0.6, "", 0)


## "No one is a farmer" (spec §9): there's work of a job, nobody but Ada has it, and Ada can't see
## to it, being away, hurt or packing for an expedition (issue #134).
func _stuck_unstaffed() -> void:
	if here().is_empty() or m.kind == "site":  # a party works a site whatever its jobs (issue #109)
		return
	for jb in Defs.JOBS:
		if _staffed(jb):
			continue
		var at = _work_at(jb)
		if at != null:
			_add_stuck(Defs.JOB_NAMES[jb], "No one is %s %s" % ["an" if Defs.JOB_SKILLED[jb][0] in "aeiou" else "a", Defs.JOB_SKILLED[jb]], Vector2(at) + Vector2(0.5, 0.5), 0.8, "", 0)


## What holds up a chopping block or mason's bench (issue #177), and a stonemason with no pickaxe.
## A target reached or a full pile is waiting, not stuck: the overflow goes to the stockpile.
## Farmers resting because the village has enough wheat: a waiting reason, not a stall (issue #269).
func _stuck_farm() -> void:
	if map_id != "village" or m.farm.is_empty() or not wheat_enough():
		return
	var plot: Dictionary = m.farm.values()[0]
	if m.farm.values().any(func(k): return k.claim == 0 and (crop_ripe(k) or k.grow < 0.0)):
		_add_stuck("Farm", "enough wheat (%d)" % wheat_keep, Vector2(plot.cell) + Vector2(0.5, 0.5), 0.8, "", 0, false, true)


func _stuck_workstations() -> void:
	var ws := enchanting_workshop()  # a book nobody is about to carry (issue #165)
	if not ws.is_empty() and not _staffed("enchant"):
		for b in learnable_books():
			_add_stuck("Book", "waiting to be carried to the workshop", Vector2(b.cell) + Vector2(0.5, 0.5), 0.6, "", 0, false, true)
			break
	if not ws.is_empty() and map_id == "village":  # an order short of something (issue #166)
		var miss := enchant_missing(ws)
		for k in miss:
			var item: Dictionary = Defs.ITEMS[k]
			_add_stuck("Enchant", "needs %s" % Defs.words(k, miss[k]), Vector2(ws.origin) + Vector2(0.5, 0.5), 1.4, "site", ws.id)
			break
	for s in m.sites:
		var wk := work_of(s)
		if not s.done or wk.is_empty():
			continue
		var tname: String = station_name(s)
		var at := Vector2(s.origin) + Vector2(0.5, 0.5)
		var h := site_height(s) + 0.4
		var item: Dictionary = Defs.ITEMS[wk.item]
		if s.get("worker", 0) == 0:
			_add_stuck(tname, "No %s to work it" % Defs.JOB_SKILLED[wk.job], at, h, "site", s.id, false, true)
		elif free_count(wk.item) >= s.keep:
			_add_stuck(tname, "Target reached (%d %s)" % [s.keep, item.many], at, h, "site", s.id, false, true)
		else:
			var pool: Array = m.trees if wk.kind == "tree" else m.boulders
			var left := pool.filter(func(t): return t.alive and not t.get("hidden", false) and in_area(s, t.cell) and not protected(t))
			if not s.get("shaft", false):  # a mineshaft digs where it stands: nothing needs to be in its area (issue #204)
				if left.is_empty():
					var why := "No trees in the chopping block's area. Plant saplings, or paint more ground" if wk.kind == "tree" else "No boulders in the mason's bench's area"
					_add_stuck(tname, why, at, h, "site", s.id)
				elif not left.any(func(t): return grown(t)):
					_add_stuck(tname, "Saplings growing: no grown trees in its area yet", at, h, "site", s.id, false, true)
		if pile_count(s) >= Tuning.WORK_STORE:
			_add_stuck(tname, "Full (%d %s)" % [Tuning.WORK_STORE, item.many], at, h, "site", s.id, false, true)
	var any_pick := not tool_items("pick", 0).is_empty()
	for r in here():
		if r.role == "mason" and r.pick == null and not any_pick and not r.broken.pick:
			_add_stuck(r.name, "Stonemason: no pickaxe", r.pos + Vector2(0.5, 0.5), 1.6, "res", r.id)
		if r.role == "hunt" and m.kind == "village" and not claimed(r).is_empty() and auto_prey().is_empty() and not m.sheep.any(func(a): return a.alive and a.des):
			var herds := free_herds()
			var left: Array = []
			for sp in herds:
				left.append("%d %s" % [herds[sp], Defs.SPECIES[sp].one if herds[sp] == 1 else Defs.SPECIES[sp].many])
			_add_stuck(r.name, "Hunter: herd at its floor (%s)" % ", ".join(left) if not left.is_empty() else "Hunter: no animals to hunt", r.pos + Vector2(0.5, 0.5), 1.6, "res", r.id, false, true)
		if needs_station(r) and m.kind == "village":  # issue #184: they haul till there's one
			_add_stuck(r.name, "Build a %s to start work" % Defs.TEMPLATES[Defs.JOB_STATIONS[r.role]].name.to_lower(), r.pos + Vector2(0.5, 0.5), 1.6, "res", r.id)


## Whether someone sees to a job's work: a resident whose job it is (or anyone, for hauling), or Ada
## while she's about the village or the road, well and not packing. Builders and haulers walk out from
## the village to work the road, so village residents count there too.
func _staffed(jb: String) -> bool:
	for r in residents:
		if r.role == jb:
			return true
		var about: bool = not r.away and maps[r.map].kind != "site"
		if about and jb == "haul":
			return true
		if about and r.role == "all" and not resting(r) and not in_staging_party(r):
			return true
	return false


## A cell where work of this job is waiting, or null when there's none.
func _work_at(jb: String):
	match jb:
		"lumber", "mason":
			for o in (m.trees if jb == "lumber" else m.boulders):
				if o.alive and o.des:
					return o.cell
		"hunt":
			for sh in m.sheep:
				if sh.alive and sh.des:
					return sh.cell
		"farm":
			var crop = _farm_work(Vector2i.ZERO)
			if crop != null:
				return crop.cell
		"build":
			for st in m.sites:
				if not st.done or (st.tpl == "portal" and not st.lit):  # a finished frame still wants lighting (issue #147)
					return st.origin
		"enchant":  # a book to learn, or an order (issues #165, #166)
			var ew := enchanting_workshop()
			if not ew.is_empty() and (not learnable_books().is_empty() or not ew.orders.is_empty()):
				return ew.origin
		"haul":
			if not m.zone.is_empty():
				var hs = _haul_source(Vector2i.ZERO)
				if hs != null:
					return hs.stack.cell
		_:
			for st in m.sites:
				if st.done and is_station(st) and st.queue.any(func(id): return recipe_job(Defs.recipe(id)) == jb):
					return st.origin
	return null


func site_height(s: Dictionary) -> float:
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
	if is_device(s):
		return 0.5 if s.done else 0.2
	if s.tpl in ["bridge", "track", "station", "portal_station"]:
		return 0.2 if not s.tpl.ends_with("station") or not s.done else 0.9
	return [0.2, 0.5, 2.5, 4.0, 4.0][mini(s.stage, 4)]


# ---------------------------------------------------------------- commands

## Marks every tree and boulder in `rect` to be mined; `kinds` can limit it to "tree" or "boulder"
## (issue #7). A single click on an already-marked one (pass it as `single`) unmarks it instead.
func designate_mine(rect: Rect2i, single = null, kinds := ["tree", "boulder"]) -> void:
	var hit: Array = []
	if single != null:
		hit = [single] if grown(single) else []
	else:
		var pool: Array = (m.trees if kinds.has("tree") else []) + (m.boulders if kinds.has("boulder") else [])
		for o in pool:
			if o.alive and not o.get("hidden", false) and grown(o) and rect.has_point(o.cell):
				hit.append(o)
	var all_on := not hit.is_empty() and hit.all(func(o): return o.des)
	for o in hit:
		o.des = not (single != null and all_on)
		o.unreach_until = 0
		if not o.des and o.claim != 0:
			var r := resident(o.claim)
			if not r.is_empty() and r.job != null and is_same(r.job.target, o):
				fail_job(r)
	rev += 1


## Marks animals in `rect` to be hunted (Hunt order, issues #42, #138); `species` limits it to one
## kind. A single click on an already-marked one (pass it as `single`) unmarks it instead.
func designate_hunt(rect: Rect2i, single = null, species := "") -> void:
	var hit: Array = [single] if single != null else m.sheep.filter(func(sh): return sh.alive and rect.has_point(sh.cell) and (species == "" or sh.species == species))
	hit = hit.filter(func(sh): return not sh.get("young", false))  # the young can't be hunted (issue #139)
	var all_on := not hit.is_empty() and hit.all(func(o): return o.des)
	for o in hit:
		o.des = not (single != null and all_on)
		o.unreach_until = 0
		if o.des and o.get("lead", false):
			o.lead = false
			if o.claim != 0:
				var lr := resident(o.claim)
				if not lr.is_empty() and lr.job != null and lr.job.kind == "lead":
					fail_job(lr)
		if not o.des and o.claim != 0:
			var r := resident(o.claim)
			if not r.is_empty() and r.job != null and is_same(r.job.target, o):
				fail_job(r)
	rev += 1


func paint_zone(rect: Rect2i) -> void:
	if m.kind != "village":
		return  # an expedition packs what it gathers instead (#109)
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var c := Vector2i(x, y)
			if walkable(c) and site_at(c) == null and not m.farm.has(c) and reserved_at(c) == null and c != meadow_sign() and c != route_sign():
				m.zone[c] = true
				_clear_wear(c)
	rev += 1


## Erases the stockpile cells in `rect` (Stockpile order, issue #63). Stacks on them stay put and
## count as loose, so they're hauled to the cells that are left. A haul on its way to an erased cell
## heads for another cell, or ends if none has room. Returns how many cells were erased.
func erase_zone(rect: Rect2i) -> int:
	var n := 0
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var c := Vector2i(x, y)
			if not m.zone.has(c):
				continue
			m.zone.erase(c)
			n += 1
			var rid: int = m.zone_res.get(c, 0)
			m.zone_res.erase(c)
			if rid != 0:
				_retarget_haul(resident(rid), c)
	rev += 1
	return n


## Points a haul bound for the erased stockpile cell `old` at another cell with room, or ends it.
func _retarget_haul(r: Dictionary, old: Vector2i) -> void:
	if r.is_empty() or r.job == null or r.job.kind != "haul":
		return
	var j: Job = r.job
	var at := -1
	for k in j.steps.size():
		if j.steps[k].op == "haul_drop" and j.steps[k].cell == old:
			at = k
	if at < 0:
		return
	var dest = zone_dest(j.steps[at].type)
	if dest == null:
		fail_job(r)  # nowhere left to put it: whatever's carried is set down here, loose
		return
	j.steps[at].cell = dest
	m.zone_res[dest] = r.id
	for hd in j.holds:
		if hd.t == "zone" and hd.cell == old:
			hd.cell = dest
	var walk: Dictionary = j.steps[at - 1]
	if walk.op == "goto":
		walk.cells = [dest]
		walk.planned = false
		if j.i == at - 1:
			r.path = []


## Why a cell can't be a farm plot, or "" when it can: farms go on open grass only (issue #45).
func farm_blocked(c: Vector2i) -> String:
	if m.kind != "village":
		return "the " + m.name.to_lower()
	if not walkable(c):
		return "not open ground"
	if site_at(c) != null:
		return "a building"
	if m.farm.has(c):
		return "a farm plot"
	if c == meadow_sign() or c == route_sign():
		return "the signpost"
	if m.zone.has(c):
		return "a stockpile"
	if reserved_at(c) != null:
		return "a reserved plot"
	for b in m.bushes:
		if b.cell == c:
			return "a bush"
	return ""


## Paints farm plots over the open grass in `rect` (Farm order, issue #45). Returns how many cells
## were added.
func paint_farm(rect: Rect2i) -> int:
	var n := 0
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var c := Vector2i(x, y)
			if farm_blocked(c) != "":
				continue
			m.farm[c] = {"id": _id(), "kind": "crop", "cell": c, "grow": -1.0, "claim": 0, "unreach_until": 0}
			_clear_wear(c)
			n += 1
	rev += 1
	return n


## Removes farm plots in `rect`; anything growing there is lost.
func clear_farm(rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			_drop_crop(Vector2i(x, y))
	rev += 1


func _drop_crop(c: Vector2i) -> void:
	var crop = m.farm.get(c)
	if crop == null:
		return
	if crop.claim != 0:
		var r := resident(crop.claim)
		if not r.is_empty() and r.job != null and is_same(r.job.target, crop):
			fail_job(r)
	m.farm.erase(c)


## Why a blueprint can't go here, or "" when it can. Trees, boulders, stockpile cells and farm plots
## don't block placement: the blueprint clears them (spec §8). Reserved plots do, and a job
## building's own plot needs room too (Slice 2 spec §8).
func placement_check(tpl: String, origin: Vector2i, rot := 0) -> String:
	if m.kind != "village":
		return "Buildings go in the village"
	if tpl == "portal":
		rot = 0
	var size: Vector2i = Defs.TEMPLATES[tpl].size
	var foot := Rect2i(origin, size)
	if origin.x < 0 or origin.y < 0 or origin.x + size.x > w or origin.y + size.y > h:
		return "Too close to the edge"
	if foot.has_point(meadow_sign()):
		return "The meadow signpost is in the way"
	if foot.has_point(route_sign()):
		return "The signpost to the old caves is in the way"
	if tpl == "dispatcher":  # beside the village station (issue #173)
		var pst := portal_station()
		if not pst.get("done", false):
			return "Build the portal station first"
		if maps.village.sites.any(func(x): return x.tpl == "dispatcher"):
			return "There's a dispatcher already"
		if not Rect2i(pst.origin, pst.size).grow(Tuning.DISPATCHER_REACH).encloses(foot):
			return "The dispatcher stands beside the station"
	if tpl == "freight_loader":  # on the plot the portal station reserved (issue #172)
		var ps := portal_station()
		if not ps.get("done", false):
			return "Build the portal station first"
		if maps.village.sites.any(func(x): return x.tpl == "freight_loader"):
			return "There's a freight loader already"
		if not ps.plot.encloses(foot):
			return "The loader goes on the station's plot"
	for s in m.sites:
		if Rect2i(s.origin, s.size).intersects(foot):
			return "Overlaps another building"
	for s in m.sites:
		if s.get("plot") != null and s.plot.intersects(foot) and not (tpl == "freight_loader" and s.tpl == "portal_station"):
			return "Overlaps a reserved plot"
	if tpl == "portal_station":  # beside the portal (issue #168)
		var pf := village_portal()
		if pf.is_empty():
			return "Build the portal first"
		if not portal_station().is_empty():
			return "The portal station is already planned"
		var gap := Rect2i(pf.origin, pf.size).grow(Tuning.PORTAL_STATION_REACH)
		if not gap.encloses(foot):
			return "The station stands beside the portal"
	var plot = plot_rect(tpl, origin, rot)
	if plot != null:
		var no_room := "Not enough room to grow into a %s" % Defs.TEMPLATES[tpl].plot
		if not Rect2i(0, 0, w, h).encloses(plot):
			return no_room
		for s in m.sites:
			if Rect2i(s.origin, s.size).intersects(plot) or (s.get("plot") != null and s.plot.intersects(plot)):
				return no_room
	return ""


func place_site(tpl: String, origin: Vector2i, rot := 0) -> Dictionary:
	if tpl == "portal":
		rot = 0
	var s := {"id": _id(), "kind": "site", "tpl": tpl, "origin": origin, "size": Defs.TEMPLATES[tpl].size,
		"rot": rot, "stage": 0, "store": {}, "incoming": {}, "builder": 0, "crafter": 0, "crafting": "",
		"done": false, "owner": 0, "queue": [], "autoq": [], "unreach_until": 0,
		"plot": plot_rect(tpl, origin, rot), "map": map_id, "worker": 0}
	if tpl == "fireplace":
		s.keep_meals = true
	if tpl == "portal":
		s.lit = false
	if Defs.TEMPLATES[tpl].has("device"):  # a redstone device (issue #170)
		s.cfg = device_default_cfg(Defs.TEMPLATES[tpl].device)
		s.out = false  # whether it's on, and why
		s.why = "Off: not built yet"
	if tpl == "enchanting_workshop":
		s.known = []   # the recipes its books have taught it (issue #165)
		s.orders = []  # enchantments ordered, in turn (issue #166)
	if not work_of(s).is_empty():
		s.keep = Tuning.KEEP_STOCK
	if Defs.TEMPLATES[tpl].has("makes"):
		s.make_keep = Tuning.MAKE_KEEP[tpl]
	if not work_of(s).is_empty():
		s.area = work_area_start(tpl, origin)  # painted from here on (issue #203)
	m.sites.append(s)
	_occ_dirty = true
	for c in site_cells(s):
		m.zone.erase(c)
		_drop_crop(c)
		_clear_wear(c)
	if s.plot != null:  # the reserved plot is kept clear of stockpiles and farms
		for x in range(s.plot.position.x, s.plot.end.x):
			for y in range(s.plot.position.y, s.plot.end.y):
				m.zone.erase(Vector2i(x, y))
				_drop_crop(Vector2i(x, y))
	_mark_obstacles(s)
	rev += 1
	return s


## Gives a resident their one job (issue #134): one of Defs.JOBS, or "none" to only haul. A new job
## stops work of the old one. Ada does everything, so hers doesn't change.
func set_role(r: Dictionary, role: String) -> void:
	if r.role == "all" or r.role == role:
		return
	if r.map != map_id:
		on_map(r.map, set_role.bind(r, role))
		return
	var old: String = r.role
	r.role = role
	if r.job != null and r.job.work == old and old != "haul" and not r.job.ordered:
		fail_job(r)
	assign_workstations()  # the old job's workstation is freed, and the new one's claimed (issue #184)
	rev += 1


## Turns the fireplace's "Keep meals in stock" standing order on or off.
func set_keep_meals(f: Dictionary, on: bool) -> void:
	if f.map != map_id:
		on_map(f.map, set_keep_meals.bind(f, on))
		return
	f.keep_meals = on
	if not on:
		for i in range(f.queue.size() - 1, -1, -1):
			if f.autoq[i]:
				queue_remove(f, i)
	rev += 1


func cancel_site(s: Dictionary) -> void:
	if s.map != map_id:
		on_map(s.map, cancel_site.bind(s))
		return
	if expedition.get("board", 0) == s.id and expedition.state == "staging":
		cancel_expedition()
	for r in residents:
		if r.job != null and is_same(r.job.target, s):
			fail_job(r)
	for k in s.store:
		if s.store[k] > 0:
			drop_items(s.origin + Vector2i(0, s.size.y), k, s.store[k])
	m.sites.erase(s)
	wires = wires.filter(func(w): return w.from != s.id and w.to != s.id)  # dust to a device that's gone (issue #170)
	_occ_dirty = true
	assign_workstations()  # its resident claims another free one, or hauls (issue #184)
	rev += 1


## Right-click order for one resident: mine a tree or boulder, or walk to a cell. It replaces
## whatever they're doing and any queued orders.
func direct_order(r: Dictionary, target = null, cell = null) -> void:
	if r.map != map_id:
		on_map(r.map, direct_order.bind(r, target, cell))
		return
	if r.arriving or r.away:
		return
	if r.job != null:
		fail_job(r)
	r.note = null
	r.orders.clear()
	if target != null and (target.kind == "tree" or target.kind == "boulder"):
		target.des = true
		target.unreach_until = 0
		rev += 1
		if target.claim != 0 and target.claim != r.id:
			var o := resident(target.claim)
			if not o.is_empty() and o.job != null and is_same(o.job.target, target):
				fail_job(o)
		if target.kind == "boulder" and r.pick == null and tool_items("pick", 0).is_empty():
			r.note = {"text": "Needs a pickaxe", "until": tick + 5 * Tuning.TPS}
			compute_stuck()
			return
		if r.get("hurt", 0) > 0:
			r.note = {"text": "Injured: can't mine", "until": tick + 5 * Tuning.TPS}
			compute_stuck()
			return
		r.direct = _gather_job(r, target)
		r.direct.ordered = true
	elif target != null and target.kind == "animal":
		target.des = true
		target.unreach_until = 0
		rev += 1
		if target.claim != 0 and target.claim != r.id:
			var o := resident(target.claim)
			if not o.is_empty() and o.job != null and is_same(o.job.target, target):
				fail_job(o)
		r.direct = _hunt_job(r, target)
		r.direct.ordered = true
	elif cell != null and walkable(cell):
		r.direct = _move_job(cell)


## Shift + right-click: adds an order to the end of the resident's list. Orders run one after
## another once their current work is done, then the resident goes back to claiming jobs.
func queue_order(r: Dictionary, target = null, cell = null) -> void:
	if r.map != map_id:
		on_map(r.map, queue_order.bind(r, target, cell))
		return
	if r.arriving or r.away:
		return
	if target != null and (target.kind == "tree" or target.kind == "boulder"):
		target.des = true
		target.unreach_until = 0
		rev += 1
		r.orders.append({"kind": "mine", "target_kind": target.kind, "id": target.id})
	elif target != null and target.kind == "animal":
		target.des = true
		target.unreach_until = 0
		rev += 1
		r.orders.append({"kind": "hunt", "id": target.id, "species": target.species})
	elif cell != null and walkable(cell):
		r.orders.append({"kind": "move", "cell": cell})


## Equip order (resident panel): go and pick up this tool, dropping the one in hand where it lay.
## A tool chosen this way is kept until it breaks, instead of being swapped for a better one.
func equip_order(r: Dictionary, stack: Dictionary) -> void:
	if r.map != map_id:
		on_map(r.map, equip_order.bind(r, stack))
		return
	if r.arriving or r.away or avail(stack) < 1 or not Defs.is_tool_item(stack.type):
		return
	if r.job != null:
		fail_job(r)
	r.note = null
	r.orders.clear()
	var it: Dictionary = Defs.ITEMS[stack.type]
	var j := Job.new("equip", "Going to get the %s" % it.one, "the %s" % it.one)
	j.ordered = true
	stack.res += 1
	var hd := j.hold({"t": "stack", "stack": stack, "n": 1})
	j.step(_goto(reach(stack.cell), false))
	j.step({"op": "pickup_tool", "stack": stack, "hold": hd, "keep": true})
	r.direct = j


## Lets a resident swap a chosen tool for the best one about again.
func release_kept_tool(r: Dictionary, kind: String) -> void:
	r.kept[kind] = false
	rev += 1


func clear_orders(r: Dictionary) -> void:
	r.orders.clear()


static func order_text(o: Dictionary) -> String:
	if o.kind == "move":
		return "Walk to a spot"
	if o.kind == "hunt":
		return "Hunt a %s" % Defs.SPECIES[o.get("species", "sheep")].one
	return "Mine a tree" if o.target_kind == "tree" else "Mine a boulder"


## Turns a queued order into a job, or returns null to skip it (its target is gone or taken, or a
## boulder needs a pickaxe nobody has).
func _order_job(r: Dictionary, o: Dictionary):
	if o.kind == "move":
		return _move_job(o.cell) if walkable(o.cell) else null
	if o.kind == "hunt":
		for sh in m.sheep:
			if sh.id == o.id:
				return _hunt_job(r, sh) if sh.alive and (sh.claim == 0 or sh.claim == r.id) else null
		return null
	var list := m.trees if o.target_kind == "tree" else m.boulders
	for t in list:
		if t.id != o.id:
			continue
		if not t.alive or (t.claim != 0 and t.claim != r.id) or r.get("hurt", 0) > 0:
			return null
		if t.kind == "boulder" and r.pick == null and tool_items("pick", 0).is_empty():
			r.note = {"text": "Needs a pickaxe", "until": tick + 5 * Tuning.TPS}
			return null
		return _gather_job(r, t)
	return null


# ---------------------------------------------------------------- expeditions (issues #105-#107)

## The village's finished expedition board, or {}.
func expedition_board() -> Dictionary:
	for s in maps.village.sites:
		if s.tpl == "board" and s.done:
			return s
	return {}


## The cells in front of a board, where the party gathers to leave (issue #105): the row of its
## reserved plot next to it. Supplies are packed into crates on the row beyond.
static func staging_cells(b: Dictionary) -> Array:
	if b.tpl == "portal":  # in front of the frame, which is four wide (issue #147)
		return [b.origin + Vector2i(1, 1), b.origin + Vector2i(2, 1), b.origin + Vector2i(3, 1)]
	var front: Vector2i = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)][int(b.rot) % 4]
	var side := Vector2i(front.y, front.x)
	return [b.origin + front - side, b.origin + front, b.origin + front + side]


## Whether a resident is in the party that's packing to leave.
func in_staging_party(r: Dictionary) -> bool:
	var ex := expedition_of(r)
	return ex.get("state", "") == "staging" and r.map == "village"


## Why a resident can't join a party, or "" when they can (issue #106).
func cant_join(r: Dictionary) -> String:
	if r.arriving:
		return "Still walking in"
	var ex := expedition_of(r)
	if r.away:
		return "On the way to or from the meadow" if ex.get("dest", "") == Meadow.ID else "On the road"
	if r.get("hurt", 0) > 0:
		return "Injured, resting" if r.hurt == 1 else "Seriously hurt, resting"
	if ex.get("state", "") == "out":
		return "Out with the party"
	if not ex.is_empty():
		return "Packing with a party"
	if r.map != "village":
		return "At the " + maps[r.map].name.to_lower()
	return ""


## A new plan: the first resident who can go, a load of coal, and supplies for the trip.
func new_plan(dest := OldMine.ID) -> Dictionary:
	var party: Array = []
	for r in residents:
		if cant_join(r) == "":
			party.append(r.id)
			break
	if realm_of(dest) == "nether":  # the first crossing: survey the landing (issue #148)
		var build_it: bool = shelter_site().is_empty() or not shelter_site().done  # the first crossing builds the shelter (issue #152)
		return {"dest": dest, "party": party, "target": {"item": "survey", "n": 1}, "meals": 3, "picks": 0, "sticks": 0, "wheat": 0,
			"list": cargo_list_for(dest) if NetherRoute.site_key(dest) != "" else [],
			"shelter": build_it, "cobble": Tuning.SHELTER_COST.cobble if build_it else 0, "planks": Tuning.SHELTER_COST.plank if build_it else 0, "stock": 0,
			"policy": {"target": true, "full": true, "low": true}, "spend_return": false, "cart_cap": false, "clear": false, "fight": false}
	var ad := Adventures.def(dest)  # issue #137: wool, and no pickaxes, for the meadow
	var sticks := fence_left() if ad.pens else 0  # issue #139: what the pens need
	var wheat := wheat_wanted() if ad.pens else 0
	var plan := {"dest": dest, "party": party, "target": {"item": ad.target[0], "n": ad.target[1]}, "meals": 3, "picks": ad.picks,
		"sticks": sticks, "wheat": wheat,
		"policy": {"target": true, "full": true, "low": true}, "spend_return": false, "cart_cap": cart_adds_room(), "clear": false}
	plan.list = cargo_list_for(dest)
	sync_target(plan)
	return plan


# ---------------------------------------------------------------- the cargo priority list (issue #185)

## A plan's list of what to bring back, best first: rows {item, on, n} (n: how many are wanted, 0 for as much as
## fits), and `new` on one the village has just learned the place gives. The old single `target` is kept as the
## first row that's on, for what shows only one item.
static func cargo_rows(plan: Dictionary) -> Array:
	if plan.target.item == "pens":  # tending the pens brings back whatever's hunted, with no list
		return []
	var rows: Array = plan.get("list", []).filter(func(r): return r.on)
	if plan.get("clear", false):  # clearing the level wants all of it: every amount is "as much as fits" (issue #188)
		return rows.map(func(r): return {"item": r.item, "on": true, "n": 0})
	return rows


## Keeps `target` in step with the list: its first row that's on, preferring one with an amount. Tending the
## pens isn't a list, so it's left alone.
static func sync_target(plan: Dictionary) -> void:
	if plan.target.item in ["pens", "survey", "scout", "build", "trade", "fortress", "rescue", "line", "pline"]:
		return
	var rows := cargo_rows(plan)
	var pick: Dictionary = {}
	for r in rows:
		if r.n > 0:
			pick = r
			break
	if pick.is_empty() and not rows.is_empty():
		pick = rows[0]
	if not pick.is_empty():
		plan.target = {"item": pick.item, "n": maxi(1, pick.n)}


## The last trip packed for `dest`, as a new plan (issue #301): the same objective, list, meals, policy and party. A
## member who can't go now is left out, and the next resident who can goes in their place; pens' sticks and wheat and
## the Nether's building stock are worked out afresh, since what's needed has changed. Returns {plan, changes}, where
## `changes` says in words what is not the same, or {} when there is no last trip.
func repeat_plan(dest: String) -> Dictionary:
	if not last_plans.has(dest):
		return {}
	var last: Dictionary = last_plans[dest]
	var plan := new_plan(dest)
	for k in last:
		if not k in ["party", "sticks", "wheat", "shelter", "cobble", "planks", "stock"]:
			plan[k] = last[k].duplicate(true) if last[k] is Dictionary or last[k] is Array else last[k]
	var changes: Array = []
	var party: Array = []
	var left_out: Array = []
	for id in last.party:
		var r := resident(id)
		if r.is_empty():
			continue
		var why := cant_join(r)
		if why == "":
			party.append(id)
		else:
			left_out.append("%s (%s)" % [r.name, why.to_lower()])
	for name in left_out:
		var sub: Dictionary = {}
		for r in residents:
			if cant_join(r) == "" and not party.has(r.id) and not last.party.has(r.id):
				sub = r
				break
		if sub.is_empty():
			changes.append("%s can't go, and nobody can take their place" % name)
		else:
			party.append(sub.id)
			changes.append("%s can't go; %s goes instead" % [name, sub.name])
	plan.party = party
	if party.is_empty():
		changes.append("nobody can go")
	return {"plan": plan, "changes": changes}


## Sets a plan's (or an expedition's) list to one wanted item first, then everything else its place gives as much
## as fits: the old single objective, for plans made in code.
func aim_plan(plan: Dictionary, item: String, n: int) -> void:
	var rows: Array = [{"item": item, "on": true, "n": n}]
	var known: Array = plan_targets(plan.dest).map(func(x): return x.item)
	var others: Array = Adventures.def(plan.dest).others
	for o in others:
		if o != item and known.has(o):
			rows.append({"item": o, "on": true, "n": 0})
	plan.list = rows
	plan.target = {"item": item, "n": n}


## The list a new plan for `dest` starts with: the last one used there, kept to the items the village knows the
## place gives, with newly known ones added at the bottom marked New (issue #185).
func cargo_list_for(dest: String) -> Array:
	var known: Array = plan_targets(dest).map(func(x): return x.item)
	var out: Array = []
	var kept: Array = cargo_lists.get(dest, [])
	for r in kept:
		if known.has(r.item):
			out.append({"item": r.item, "on": r.on, "n": r.n})
	if kept.is_empty():  # never planned here: the defaults, in their order
		for d in Tuning.CARGO_DEFAULTS[Adventures.def(dest).cargo]:
			if known.has(d[0]):
				out.append({"item": d[0], "on": true, "n": d[1]})
	for item in known:
		if not out.any(func(r): return r.item == item):
			out.append({"item": item, "on": true, "n": 0, "new": not kept.is_empty()})
	return out


## Where an item stands in the party's list, from 0 (the best) among the rows that are on, or -1 when it isn't
## wanted at all: off, or not listed.
static func cargo_rank(plan: Dictionary, item: String) -> int:
	var i := 0
	for r in cargo_rows(plan):
		if r.item == item:
			return i
		i += 1
	return -1


## How many of a row's item the packs hold.
func cargo_have(item: String) -> int:
	return expedition.get("cargo", {}).get(item, 0)


## How many of a row's amount is still to pack; a row for as much as fits is never done.
func row_left(row: Dictionary) -> int:
	return maxi(0, row.n - cargo_have(row.item)) if row.n > 0 else 1 << 20


## Whether every row with an amount has its amount packed (and there is one): the policy "Target reached".
func objective_met() -> bool:
	var rows := cargo_rows(expedition).filter(func(r): return r.n > 0)
	return not rows.is_empty() and rows.all(func(r): return cargo_have(r.item) >= r.n)


## What's still to pack for the rows with an amount, together; as-much-as-fits rows don't count.
func objective_left() -> int:
	if tending():
		return 0
	var n := 0
	for r in cargo_rows(expedition):
		if r.n > 0:
			n += maxi(0, r.n - cargo_have(r.item))
	return n


## Room the packs should keep for the rows above an item's, which come first.
func _reserve_above(item: String) -> int:
	var n := 0
	for r in cargo_rows(expedition):
		if r.item == item:
			break
		if r.n > 0:
			n += maxi(0, r.n - cargo_have(r.item))
	return n


## Whether a block or an animal gives any item on the list (issue #185).
func gives_wanted(b: Dictionary) -> bool:
	return cargo_rows(expedition).any(func(r): return gives(b, r.item) and can_mine_item(r.item))


## Whether someone in the party, or a spare in the packs, has the iron pickaxe diamond ore needs (issue #186).
func can_mine_diamond() -> bool:
	return can_mine_ore("diamond")


## Whether the party has a pickaxe good enough for an ore: iron for diamonds (issue #186), a diamond one for obsidian (#146).
func can_mine_ore(ore: String) -> bool:
	var need: int = Tuning.ORE_PICK_TIER.get(ore, 0)
	if need == 0:
		return true
	for id in expedition.get("party", []):
		var r := resident(id)
		if not r.is_empty() and r.pick != null and r.pick.tier >= need and r.get("hurt", 0) == 0:
			return true
	return expedition.get("tools", []).any(func(t): return Defs.ITEMS[t.type].tier >= need)


## Whether the party could mine what gives this item: true unless it comes from an ore that needs a better pickaxe.
func can_mine_item(item: String) -> bool:
	for ore in Tuning.ORE_PICK_TIER:
		if Defs.ORES[ore].item == item:
			return can_mine_ore(ore)
	return true


## What a block that needs a better pickaxe says when nobody has one.
static func pick_need_text(ore: String) -> String:
	if ore == "obsidian":
		return "Obsidian: needs a diamond pickaxe"
	return "%s needs an %s pickaxe" % [Defs.ORES[ore].name, Defs.TIER_NAMES[Tuning.ORE_PICK_TIER[ore]].to_lower()]


## "3 coal and 2 iron ore", or "what's on the list": what a plan or the party is out for, in words.
static func list_text(plan: Dictionary) -> String:
	if plan.get("clear", false):
		return "clear the level"
	var parts: PackedStringArray = []
	for r in cargo_rows(plan):
		if r.n > 0:
			parts.append(Defs.words(r.item, r.n))
	return " and ".join(parts) if not parts.is_empty() else "what's on the list"


func objective_text() -> String:
	return "what clears the level" if expedition.get("clear", false) else list_text(expedition)


## A loose stack at the site that outranks something in the packs, with the cargo it would swap out: the
## lowest-priority item held, as {stack, drop}, or {}.
func swap_candidate() -> Dictionary:
	var rows := cargo_rows(expedition)
	var held: Array = rows.filter(func(r): return cargo_have(r.item) > 0)
	if held.is_empty():
		return {}
	var worst: Dictionary = held[-1]
	var worst_rank := cargo_rank(expedition, worst.item)
	var best := {}
	var best_rank := worst_rank
	for st in stacks_where(func(s): return avail(s) > 0):
		var rk := cargo_rank(expedition, st.type)
		if rk >= 0 and rk < best_rank:
			best = st
			best_rank = rk
	return {} if best.is_empty() else {"stack": best, "drop": worst.item}


## The party's packs: each member carries PACK_CAPACITY items, shared by supplies and cargo.
static func pack_capacity(plan: Dictionary) -> int:
	return plan.party.size() * Tuning.PACK_CAPACITY + (Tuning.CART_CAPACITY if plan.get("cart_cap", false) else 0)


## Room the supplies take: a meal, a spare pickaxe, a stick or a wheat is one item each.
static func plan_supplies(plan: Dictionary) -> int:
	return plan.meals + plan.picks + plan.get("sticks", 0) + plan.get("wheat", 0) + plan.get("cobble", 0) + plan.get("planks", 0) + plan.get("gold", 0) + plan.get("rails", 0) + plan.get("minecarts", 0)


## Room left in the packs for what the party brings back.
static func cargo_room(plan: Dictionary) -> int:
	return pack_capacity(plan) - plan_supplies(plan)


## Meals kept for the walk home (brief §8): one each, unless the plan says they may be spent.
static func return_meals(plan: Dictionary) -> int:
	return plan.party.size() * Tuning.RETURN_MEALS


## About how many minutes the provisions feed the party at the site, leaving the return food alone
## unless the plan lets them spend it.
static func site_minutes(plan: Dictionary) -> float:
	var n: int = plan.party.size()
	if n == 0:
		return 0.0
	var meals: int = plan.meals - (0 if plan.spend_return else return_meals(plan))
	return maxf(0.0, meals * Tuning.MEAL_FOOD / (n * 100.0 / Tuning.HUNGER_EMPTY_TIME)) / 60.0


## What a party can be sent to bring back: the resources the village knows the site has.
func plan_targets(dest: String) -> Array:
	return site_report(dest).resources.filter(func(x): return x.known)


## What stops a plan being confirmed, in the player's words; empty when it can be.
func plan_problems(plan: Dictionary) -> Array:
	var out: Array = []
	var sl := slot_of_dest(plan.dest)  # a rescue sets out even when its slot is taken (issue #145)
	if plan.get("rescue", false):
		sl = "rescue"
	if not expeditions[sl].is_empty():
		out.append("%s %s is already out" % ["An" if sl == "overworld" else "A", party_name(sl)])
	if expedition_board().is_empty():
		out.append("Build an expedition board first")
	if plan.target.item == "trade" and plan.get("gold", 0) <= 0:  # nothing to trade with (issue #156)
		out.append("Take some gold to trade")
	if plan.target.item == "scout":  # which route, and not one already scouted (issue #153)
		var rk: String = plan.target.get("route", "")
		if not NetherRoute.ROUTES.has(rk):
			out.append("Choose a route to scout")
		elif maps[NetherRoute.ROUTES[rk].id].surveyed:
			out.append("That route is already scouted")
	if NetherRoute.site_ids().has(plan.dest) and not maps[plan.dest].known:  # an unscouted site can't be a destination (issue #153)
		out.append("Nobody has scouted the way there yet")
	if SLOT_REALM[sl] == "nether":  # a crossing needs the portal built and lit (issue #148)
		if village_portal().is_empty():
			out.append("Build the portal first")
		elif not portal_lit():
			out.append("The portal isn't lit")
	if plan.party.is_empty():
		out.append("Choose who goes")
	elif plan.party.size() > Tuning.PARTY_MAX:
		out.append("At most %d can go" % Tuning.PARTY_MAX)
	for id in plan.party:
		var r := resident(id)
		var why := "Gone" if r.is_empty() else cant_join(r)
		if why != "":
			out.append("%s can’t go: %s" % [r.get("name", "Someone"), why.to_lower()])
	if not plan.party.is_empty():
		if plan.meals < return_meals(plan):
			out.append("Pack at least %d %s for the walk home" % [return_meals(plan), "meal" if return_meals(plan) == 1 else "meals"])
		var room := cargo_room(plan)
		if room < 1:
			out.append("The supplies fill the packs. Take fewer, or more people")
		elif not plan.target.item in ["pens", "survey", "scout", "build", "trade", "fortress", "rescue", "line", "pline"]:
			var wanted := 0
			for r in cargo_rows(plan):
				wanted += r.n
			if cargo_rows(plan).is_empty():
				out.append("Choose something to bring back")
			elif wanted > room:
				out.append("The packs only have room for %d of what's wanted" % room)
	if plan.get("stock", 0) > 0 and plan.get("stock", 0) > maxi(0, plan.meals - return_meals(plan)):
		out.append("Meals for the cache come out of the meals taken, past the walk home")
	if not plan.policy.values().has(true):
		out.append("Choose when the party comes home")
	return out


## Confirms a plan (issue #106): packing starts at the board. Nobody leaves until Depart.
## Returns why it can't, or "".
func plan_expedition(plan: Dictionary) -> String:
	var problems := plan_problems(plan)
	if not problems.is_empty():
		return problems[0]
	if not plan.target.item in ["pens", "survey", "scout", "build", "trade", "fortress", "rescue", "line", "pline"]:  # each place keeps its last list (issue #185)
		cargo_lists[plan.dest] = plan.get("list", []).map(func(r): return {"item": r.item, "on": r.on, "n": r.n})
	if not plan.get("rescue", false):
		last_plans[plan.dest] = plan.duplicate(true)
	use_slot("rescue" if plan.get("rescue", false) else slot_of_dest(plan.dest))
	expedition = plan.duplicate(true)
	expedition.board = village_portal().id if in_nether() else expedition_board().id  # a Nether party packs at the portal (issue #148)
	expedition.state = "staging"
	expedition.packed = {}
	expedition.tools = []
	rev += 1
	_toast("Packing for the %s has started. The party gathers at the board." % maps[plan.dest].name.to_lower(), 0, expedition.board)
	use_slot("overworld")
	return ""


## Meals and spare pickaxes at the board so far, plus those on their way there when `incoming`.
func packed(incoming := false) -> Dictionary:
	var out := {"meals": 0, "picks": 0, "wheat": 0, "sticks": 0, "cobble": 0, "planks": 0, "gold": 0, "rails": 0, "minecarts": 0}
	var b := site(expedition.get("board", 0))
	if b.is_empty():
		return out
	for src in ([b.store, b.incoming] if incoming else [b.store]):
		for k in src:
			if Defs.MEALS.has(k):
				out.meals += src[k]
			elif Defs.ITEMS[k].get("tool", "") == "pick":
				out.picks += src[k]
			elif k == "wheat":
				out.wheat += src[k]
			elif k == "stick":
				out.sticks += src[k]
			elif k == "cobble":
				out.cobble += src[k]
			elif k == "plank":
				out.planks += src[k]
			elif k == "gold_ingot":
				out.gold += src[k]
			elif k == "rail":
				out.rails += src[k]
			elif k == "minecart":
				out.minecarts += src[k]
	return out


## What's still to be packed, less what's on its way: {meals, picks, wheat, sticks}.
func pack_needs() -> Dictionary:
	if expedition.get("state", "") != "staging":
		return {"meals": 0, "picks": 0, "wheat": 0, "sticks": 0, "cobble": 0, "planks": 0, "gold": 0, "rails": 0, "minecarts": 0}
	var p := packed(true)
	return {"meals": maxi(0, expedition.meals - p.meals), "picks": maxi(0, expedition.picks - p.picks),
		"wheat": maxi(0, expedition.get("wheat", 0) - p.wheat), "sticks": maxi(0, expedition.get("sticks", 0) - p.sticks),
		"cobble": maxi(0, expedition.get("cobble", 0) - p.cobble), "planks": maxi(0, expedition.get("planks", 0) - p.planks),
		"gold": maxi(0, expedition.get("gold", 0) - p.gold), "rails": maxi(0, expedition.get("rails", 0) - p.rails),
		"minecarts": maxi(0, expedition.get("minecarts", 0) - p.minecarts)}


## What a plan can ask to have packed besides meals and spare pickaxes: [the plan's key, the item].
const SUPPLY_KINDS := [["wheat", "wheat"], ["sticks", "stick"], ["cobble", "cobble"], ["planks", "plank"], ["gold", "gold_ingot"], ["rails", "rail"], ["minecarts", "minecart"]]


## A delivery of supplies to the board (issue #107): meals first, then spare pickaxes, the best first.
func _pack_job(r: Dictionary, c: Vector2i):
	if expedition.get("state", "") != "staging" or map_id != "village":
		return null
	var b := site(expedition.board)
	if b.is_empty() or _cooling(b):
		return null
	var need := pack_needs()
	if need.meals > 0:
		var src := stacks_where(func(st): return Defs.MEALS.has(st.type) and avail(st) > 0)
		if not src.is_empty():
			var st: Dictionary = nearest(src, c)
			return _deliver_job(b, st.type, mini(mini(need.meals, carry_cap(r)), avail(st)), st)
	if need.picks > 0:
		var picks := tool_items("pick", 0)
		if not picks.is_empty():
			picks.sort_custom(func(a, x): return Defs.ITEMS[a.type].tier > Defs.ITEMS[x.type].tier or (a.type == x.type and a.dur > x.dur))
			return _deliver_job(b, picks[0].type, 1, picks[0])
	for k in SUPPLY_KINDS:  # for the pens (issue #139) and the landing's shelter (issue #152)
		if need[k[0]] > 0:
			var src := stacks_where(func(st): return st.type == k[1] and avail(st) > 0)
			if not src.is_empty():
				var st: Dictionary = nearest(src, c)
				return _deliver_job(b, st.type, mini(mini(need[k[0]], carry_cap(r)), avail(st)), st)
	return null


## A party member walks to the board and waits there to leave.
func _stage_job() -> Job:
	var b := site(expedition.board)
	var j := Job.new("stage", "Going to the expedition board", "the expedition board")
	j.step(_goto(staging_cells(b), false))
	j.step({"op": "wait_board"})
	return j


## Whether a party member is waiting at the board.
func at_board(r: Dictionary) -> bool:
	return not r.is_empty() and r.job != null and r.job.kind == "stage" and r.job.i >= 1


## Why the party can't leave yet, or "" when Depart can go ahead (issue #107).
func depart_blocker(slot_id := "") -> String:
	if slot_id != "" and slot_id != slot:
		return on_slot(slot_id, depart_blocker)
	if expedition.get("state", "") != "staging":
		return "Nothing is being packed"
	if in_nether() and not portal_lit():
		return "The portal isn't lit"
	if NetherRoute.site_ids().has(expedition.get("dest", "")) and maps[expedition.dest].pattern == "":  # scouted, but not built yet
		return "The way to the %s isn't built yet" % maps[expedition.dest].name.to_lower()
	var p := packed()
	var meals: int = expedition.meals - p.meals
	if meals > 0:
		return "Waiting for %d %s to pack" % [meals, "meal" if meals == 1 else "meals"]
	var picks: int = expedition.picks - p.picks
	if picks > 0:
		return "Waiting for %d spare %s to pack" % [picks, "pickaxe" if picks == 1 else "pickaxes"]
	for k in SUPPLY_KINDS:
		var n: int = expedition.get(k[0], 0) - p[k[0]]
		if n > 0:
			return "Waiting for %s to pack" % Defs.words(k[1], n)
	for id in expedition.party:
		var r := resident(id)
		if not at_board(r):
			return "Waiting for %s" % r.get("name", "someone")
	return ""


## Depart (issue #107): the party leaves with what was packed, and is out of village labor from now on.
## Departure is always the player's call. Returns why it can't go, or "".
func depart(slot_id := "") -> String:
	if slot_id != "" and slot_id != slot:
		return on_slot(slot_id, depart)
	var why := depart_blocker()
	if why != "":
		return why
	var b := site(expedition.board)
	for k in b.store:
		if b.store[k] > 0 and not Defs.is_tool_item(k):
			expedition.packed[k] = b.store[k]
	expedition.tools = b.get("tools", []).duplicate(true)
	b.store = {}
	b.tools = []
	if in_nether():  # the party carries a flint and steel, if the village has one, to relight the portal (issue #148)
		var ls := stacks_where(func(s): return s.type == "flint_and_steel" and avail(s) > 0)
		if not ls.is_empty():
			var stk: Dictionary = ls[0]
			expedition.lighter = {"type": "flint_and_steel", "dur": stk.get("dur", full_uses("flint_and_steel"))}
			stk.n -= 1
			if stk.n <= 0:
				m.items.erase(stk.cell)
	expedition.state = "out"
	expedition.leg = "out"
	expedition.cart = cart_ready()  # the party rides the line if there's a cart at the village station (issue #124)
	expedition.cart_cap = cart_adds_room()
	expedition.broken = 0
	expedition.provisions = {}  # the meals in the packs (issue #109)
	expedition.supplies = {}  # sticks and wheat for the pens (issue #139)
	for k in expedition.packed:
		expedition["provisions" if Defs.MEALS.has(k) else "supplies"][k] = expedition.packed[k]
	expedition.cargo = {}
	expedition.hurt = {}
	var names: Array = []
	for id in expedition.party:  # each walks to the signpost with the packs, then takes the road (issue #108)
		var r := resident(id)
		fail_job(r)
		r.direct = null
		r.orders.clear()
		r.note = null
		names.append(r.name)
	rev += 1
	_toast("%s set off for the %s." % [names_text(names), maps[expedition.dest].name.to_lower()], 0, b.id)
	return ""


## "Ada", "Ada and Tomas", "Ada, Tomas and Mira".
static func names_text(names: Array) -> String:
	if names.size() < 2:
		return "".join(names)
	return ", ".join(names.slice(0, -1)) + " and " + names[-1]


## A party member at the end of the road: they appear at the site's entrance, with the packs.
## A party member steps through the portal, either way (issue #148): the one way between the village and the
## Nether, where they arrive on the far side or at the staging area.
func _cross_portal(r: Dictionary, to: String) -> void:
	if to == "village":
		_arrive_home(r)
	else:
		_enter_level(r, NetherLanding.ID)  # every Nether place is reached by way of the landing (issue #155)


func _arrive_at_site(r: Dictionary) -> void:
	var id: String = r.trip
	if MineLevels.level_of(id) > 1:  # bound for a deeper level: in at the top, then down (issue #132)
		id = OldMine.ID
	r.away = false
	r.trip = ""
	_enter_level(r, id)


## A party member comes into a site map at its entrance: the end of the road, or through a door from
## the level above. The first of the party into the one they're bound for says so.
func _enter_level(r: Dictionary, id: String) -> void:
	var mp: SimMap = maps[id]
	if id == NetherLanding.ID and shelter_site().is_empty():  # the blueprint the first party builds (issue #152)
		on_map(id, func(): place_site("shelter", NetherLanding.SHELTER_AT))
	move_to_map(r, id, mp.entrance)
	mp.known = true
	mp.visited = true
	if id != expedition.get("dest", "") or expedition.get("reached", "") == id:
		return
	expedition.reached = id
	var prev := use_map(id)
	_toast("The party reached the %s." % mp.name.to_lower(), r.id)
	use_map(prev)


## Calls off an expedition that hasn't left (issue #107). What was packed is set down by the board,
## loose, and hauled back to the stockpile.
func cancel_expedition(slot_id := "") -> void:
	if slot_id != "" and slot_id != slot:
		on_slot(slot_id, cancel_expedition)
		return
	if expedition.get("state", "") != "staging":
		return
	if map_id != "village":
		on_map("village", cancel_expedition)
		return
	var b := site(expedition.board)
	var party: Array = expedition.party
	expedition = {}
	for r in residents:
		if r.job != null and ((r.job.kind == "stage" and party.has(r.id)) or (r.job.kind == "deliver" and is_same(r.job.target, b))):
			fail_job(r)
	if not b.is_empty():
		var spot: Vector2i = staging_cells(b)[1]
		for k in b.store:
			if b.store[k] > 0 and not Defs.is_tool_item(k):
				drop_items(spot, k, b.store[k])
		for t in b.get("tools", []):
			drop_items(spot, t.type, 1, t.dur)
		b.store = {}
		b.tools = []
	rev += 1
	_toast("The expedition is called off. What was packed goes back to the stockpile.", 0, b.get("id", 0))


## The board's stuck reasons while packing (issue #107). Progress waits in the dim tier; nothing to
## pack is a blocker, with the fix.
func _stuck_expedition() -> void:
	if building_line() and expedition.get("state", "") == "out" and map_id == NetherRoute.ROUTES.quartz.id:  # the track waits on a bridge (issue #159)
		var l := nline()
		for i in Road.segment_count():
			if l.laid[i] < Tuning.RAILS_PER_SEGMENT:
				if nline_obstacle(i) and not l.bridged.has(i) and expedition.get("supplies", {}).get("plank", 0) < Tuning.NETHER_BRIDGE_PLANKS:
					_add_stuck("Track", "needs %s bridged first" % NetherRoute.ROUTES.quartz.segments[i].name.to_lower(), Vector2(Road.SEGMENTS[i].x + 2, NetherRoute.LINE_ROW) + Vector2(0.5, 0.5), 0.6, "", 0)
				break
	if expedition.has("stranded"):  # waiting for a rescue (issue #158)
		var lost: Dictionary = expedition
		_add_stuck(party_name(slot), "stranded: %s" % lost.stranded.why, Vector2(maps[lost.stranded.at].entrance) + Vector2(0.5, 0.5), 1.9, "", 0, false, true)
	if expedition.get("state", "") != "staging":
		return
	var b := site(expedition.board)
	if b.is_empty() or b.map != map_id:
		return
	var who := "Expedition" if slot == "overworld" else party_name(slot)  # the Nether's names its party (issue #145)
	var at := Vector2(b.origin) + Vector2(0.5, 0.5)
	var p := packed()
	var need := pack_needs()
	var meals: int = expedition.meals - p.meals
	if meals > 0:
		if need.meals > 0 and stacks_where(func(st): return Defs.MEALS.has(st.type) and avail(st) > 0).is_empty():
			_add_stuck(who, "No meals to pack. Cooks make them at the fireplace, or plan fewer", at, 1.9, "site", b.id)
		else:
			_add_stuck(who, "Waiting for %d %s to pack" % [meals, "meal" if meals == 1 else "meals"], at, 1.9, "site", b.id, false, true)
	var picks: int = expedition.picks - p.picks
	if picks > 0:
		if need.picks > 0 and tool_items("pick", 0).is_empty():
			_add_stuck(who, "No spare pickaxes to pack. Craft one at the bench, or plan fewer", at, 1.9, "site", b.id)
		else:
			_add_stuck(who, "Waiting for %d spare %s to pack" % [picks, "pickaxe" if picks == 1 else "pickaxes"], at, 1.9, "site", b.id, false, true)
	for id in expedition.party:
		var r := resident(id)
		if not r.is_empty() and not at_board(r):
			_add_stuck(who, "Waiting for %s" % r.name, at, 1.9, "res", r.id, false, true)


# ---------------------------------------------------------------- travel and the return (issues #108, #112)

## The signpost on the village's east edge where the road to the old mine starts and ends.
func route_sign() -> Vector2i:
	var v: SimMap = maps.village
	return Vector2i(v.w - 1, v.h / 2)


## Seconds on the way to `to`, or home from it: the road to the meadow, or the road to the mine.
func trip_time(to: String) -> float:
	var dest: String = expedition.get("dest", "") if to == "village" else to
	return MeadowRoad.walk_time() if Adventures.road_of(dest) == MeadowRoad.ID else route_walk_time()


## Whether a party member is on their way: walking to the signpost to leave the village, or to the
## site's entrance to come home. Either way, they're out of the work where they are.
func on_the_way(r: Dictionary) -> bool:
	if expedition.get("state", "") != "out" or not expedition.party.has(r.id) or r.away:
		return false
	if expedition.get("leg", "out") == "out":  # in the village, or on a level above the one they're bound for (issue #132)
		return r.map == "village" or (MineLevels.level_of(r.map) > 0 and MineLevels.level_of(r.map) < MineLevels.level_of(expedition.dest))
	return r.map == expedition.dest or MineLevels.level_of(r.map) > 0


## Whether a party member is carrying the packs through the village, on the way out (drawn as packs).
func carrying_packs(r: Dictionary) -> bool:
	return (on_the_way(r) and r.map != expedition.dest) or on_road(r)


## The walk to where the road starts: the village signpost, or the site's entrance on the way home.
func _road_job() -> Job:
	if map_id == "village":
		var dest: String = expedition.dest
		var j := Job.new("road", "Heading for the %s" % maps[dest].name.to_lower(), "the signpost")
		j.step(_goto([sign_for(dest)], true))
		j.step({"op": "depart", "to": dest})
		return j
	if expedition.get("leg", "out") == "out":  # down through the door to the level below (issue #132)
		var d := Job.new("road", "Heading down to level %d" % (m.level + 1), "the door")
		d.step(_goto([m.door], true))
		d.step({"op": "descend"})
		return d
	var h := Job.new("road", "Heading home", "the entrance")
	h.step(_goto([m.entrance], false))
	if realm_of(map_id) == "nether":  # back through the portal, relighting it first if it's gone out (issue #148)
		h.label = "Heading for the portal"
		if not portal_lit():
			if expedition.get("lighter", {}).is_empty():
				h.step({"op": "wait_portal"})
			else:
				h.step({"op": "work", "what": "relight", "label": "Relighting the portal"})
		h.step({"op": "depart", "to": "village"})
		return h
	if m.level > 1:  # up to the level above, then on up
		h.label = "Heading up to level %d" % (m.level - 1) if m.level > 2 else "Heading up to the old caves"
		h.step({"op": "ascend"})
		return h
	h.step({"op": "depart", "to": "village"})
	return h


## Why the party can't be called home yet, or "" when it can.
func call_home_blocker(slot_id := "") -> String:
	if slot_id != "" and slot_id != slot:
		return on_slot(slot_id, call_home_blocker)
	if expedition.get("state", "") != "out":
		return "No party is out"
	if expedition.get("leg", "out") == "home":
		return "The party is already heading home"
	for id in expedition.party:
		var r := resident(id)
		if r.map != expedition.dest or r.away:
			return "The party isn't at the %s yet" % maps[expedition.dest].name.to_lower()
	return ""


## Calls the party home now, whatever its return policy says: they walk to the entrance with the
## packs and set off. Returns why it can't, or "".
func call_home(slot_id := "") -> String:
	if slot_id != "" and slot_id != slot:
		return on_slot(slot_id, call_home)
	var why := call_home_blocker()
	if why != "":
		return why
	expedition.leg = "home"
	expedition.home_why = "called home"
	for id in expedition.party:
		var r := resident(id)
		fail_job(r)
		r.direct = null
		r.orders.clear()
	_toast("The party is heading home from the %s." % maps[expedition.dest].name.to_lower(), expedition.party[0])
	return ""


## A party member back at the village signpost. When the last one is back, the packs are unloaded
## there as stacks, which haulers carry to the stockpile, and the board is free again (issue #112).
func _arrive_home(r: Dictionary) -> void:
	r.away = false
	r.trip = ""
	var sign := sign_for(expedition.get("dest", ""))
	var spot = on_map("village", nearest_walkable.bind(sign))
	move_to_map(r, "village", spot if spot != null else sign)
	if expedition.party.all(func(id): return resident(id).map == "village" and not resident(id).away):
		_start_unloading()


## The party unpacks at the signpost by hand (issue #123): cargo first, unless it came off the cart at
## the station, then meals, then spare tools, at HAND_RATE an item a second each.
func _start_unloading() -> void:
	var ex := expedition
	var left := {}
	if not ex.get("cargo_unloaded", false):
		for k in ex.get("cargo", {}):
			left[k] = left.get(k, 0) + ex.cargo[k]
	for src in [ex.get("provisions", {}), ex.get("supplies", {})]:
		for k in src:
			left[k] = left.get(k, 0) + src[k]
	ex.unpack = left
	ex.unpack_tools = ex.get("tools", []).duplicate(true)
	if ex.has("lighter"):
		ex.unpack_tools.append({"type": "flint_and_steel", "dur": ex.lighter.dur})
	ex.unloading = true
	ex.unload_acc = 0.0
	if left.is_empty() and ex.unpack_tools.is_empty():
		on_map("village", _finish_return)


## One tick of unpacking at the signpost.
func _step_unload() -> void:
	var ex := expedition
	if not ex.get("unloading", false):
		return
	var hands: int = ex.party.filter(func(id): return resident(id).map == "village").size()
	ex.unload_acc += Tuning.HAND_RATE * maxi(1, hands) * Tuning.DT
	var spot = nearest_walkable(sign_for(ex.dest))
	spot = spot if spot != null else sign_for(ex.dest)
	while ex.unload_acc >= 1.0:
		ex.unload_acc -= 1.0
		if not ex.unpack.is_empty():
			var k: String = ex.unpack.keys()[0]
			_drop_cargo(spot, k, 1)
			ex.unpack[k] -= 1
			if ex.unpack[k] <= 0:
				ex.unpack.erase(k)
		elif not ex.unpack_tools.is_empty():
			var t: Dictionary = ex.unpack_tools.pop_front()
			_drop_cargo(spot, t.type, 1, t.dur)
		if ex.unpack.is_empty() and ex.unpack_tools.is_empty():
			_finish_return()
			return


## Sets items down as stacks that are hauled before anything else (issue #112).
func _drop_cargo(spot: Vector2i, type: String, n: int, dur := -1) -> void:
	if type == "obsidian":
		stats.obsidian_home = true  # the portal can be planned (issue #147)
	var before := {}
	for k in m.items:
		before[k] = true
	drop_items(spot, type, n, dur)
	for k in m.items:
		if not before.has(k):
			m.items[k].cargo = true


## Everything's unpacked: the report, and the board is free again.
func _finish_return() -> void:
	var ex := expedition
	var report := expedition_report(ex)
	var b := site(ex.board)
	if not b.is_empty():
		b.report = report
	if realm_of(ex.dest) == "nether" and not expedition_board().is_empty():  # the board shows the last report (issue #148)
		expedition_board().report = report
	if ex.dest == Meadow.ID and ex.get("cargo", {}).get("wool", 0) > 0:
		stats.meadow_wool = true  # a founding goal (issue #182)
	expedition = {}
	stats.expeditions = stats.get("expeditions", 0) + 1
	rev += 1
	_toast(". ".join(report) + ".", 0, b.get("id", 0))


## What an expedition brought back and what it cost, for the toast and the board (issue #112):
## ["Back from the old mine: 18 cobblestone, 9 coal", "3 meals eaten, 1 pickaxe broken", "Tomas injured"].
func expedition_report(ex: Dictionary) -> Array:
	var cargo: Dictionary = ex.get("cargo", {})
	var got: PackedStringArray = []
	var meals_back := 0
	for k in cargo:
		got.append(Defs.words(k, cargo[k]))
	for k in ex.get("provisions", {}):
		meals_back += ex.provisions[k]
	var name: String = maps[ex.dest].name.to_lower()
	var lines: Array = ["Back from the %s: %s" % [name, ", ".join(got)] if not got.is_empty() else "Back from the %s with nothing %s" % [name, Adventures.def(ex.dest).got]]
	var meals_packed := 0
	for k in ex.get("packed", {}):
		if Defs.MEALS.has(k):
			meals_packed += ex.packed[k]
	var eaten := maxi(0, meals_packed - meals_back)
	var broken: int = ex.get("broken", 0)
	var cost := "%d %s eaten" % [eaten, "meal" if eaten == 1 else "meals"]
	if broken > 0:
		cost += ", %d %s broken" % [broken, "pickaxe" if broken == 1 else "pickaxes"]
	lines.append(cost)
	if not ex.get("abandoned", []).is_empty():  # issue #158
		lines.append("Left behind: " + ", ".join(ex.abandoned))
	if not ex.get("traded", []).is_empty():  # issue #156
		lines.append("Traded: " + "; ".join(ex.traded))
	if ex.get("cart", false) and ex.has("road_out") and ex.has("road_home"):  # issue #124
		var took: float = float(ex.road_out[1] - ex.road_out[0] + ex.road_home[1] - ex.road_home[0]) / Tuning.TPS
		lines.append("By cart: %d s on the road there and back, about %d s saved" % [roundi(took), maxi(0, roundi(2.0 * route_walk_time() - took))])
	var hurt: PackedStringArray = []
	for who in ex.get("hurt", {}):
		hurt.append("%s %s" % [who, "injured" if ex.hurt[who] == 1 else "seriously injured"])
	if not hurt.is_empty():
		lines.append(", ".join(hurt))
	return lines


# ---------------------------------------------------------------- the road to the mine (issues #118-#121)
# The rules live in road_work.gd (#305); these forward to them.

func road() -> SimMap:
	return RoadWork.road(self)


func on_road(r: Dictionary) -> bool:
	return RoadWork.on_road(self, r)


static func road_map_for(dest: String) -> String:
	return RoadWork.road_map_for(dest)


func _onto_road(r: Dictionary, to: String) -> void:
	RoadWork._onto_road(self, r, to)


func _road_walk_job(r: Dictionary) -> Job:
	return RoadWork._road_walk_job(self, r)


func road_eta(r: Dictionary) -> float:
	return RoadWork.road_eta(self, r)


func ground_speed(c: Vector2i) -> float:
	return RoadWork.ground_speed(self, c)


static func wear_stage(wear: int) -> int:
	return RoadWork.wear_stage(wear)


func path_stage(c: Vector2i) -> int:
	return RoadWork.path_stage(self, c)


func path_speed(c: Vector2i) -> float:
	return RoadWork.path_speed(self, c)


func _wear_step(c: Vector2i) -> void:
	RoadWork._wear_step(self, c)


func _decay_wear() -> void:
	RoadWork._decay_wear(self)


func _clear_wear(c: Vector2i) -> void:
	RoadWork._clear_wear(self, c)


func bridged(c: Vector2i) -> bool:
	return RoadWork.bridged(self, c)


func _reveal(c: Vector2i) -> void:
	RoadWork._reveal(self, c)


func route_surveyed() -> bool:
	return RoadWork.route_surveyed(self)


func route_walk_time() -> float:
	return RoadWork.route_walk_time(self)


func bridge() -> Dictionary:
	return RoadWork.bridge(self)


func cut_boulders() -> Array:
	return RoadWork.cut_boulders(self)


func route_report() -> Dictionary:
	return RoadWork.route_report(self)


func plan_bridge() -> String:
	return RoadWork.plan_bridge(self)


func clear_cut() -> String:
	return RoadWork.clear_cut(self)


static func _seg_of(obstacle: String) -> int:
	return RoadWork._seg_of(obstacle)


func track_site(i: int) -> Dictionary:
	return RoadWork.track_site(self, i)


func track_state(i: int) -> String:
	return RoadWork.track_state(self, i)


func track_blocker(i: int) -> String:
	return RoadWork.track_blocker(self, i)


func next_track() -> int:
	return RoadWork.next_track(self)


func site_open(st: Dictionary) -> bool:
	return RoadWork.site_open(self, st)


func line_complete() -> bool:
	return RoadWork.line_complete(self)


func line_cost() -> Dictionary:
	return RoadWork.line_cost(self)


func plan_line_blocker() -> String:
	return RoadWork.plan_line_blocker(self)


func plan_line() -> String:
	return RoadWork.plan_line(self)


func _road_claim(r: Dictionary, kind: String, jobs: Array):
	return RoadWork._road_claim(self, r, kind, jobs)


func _claim_on_road(r: Dictionary) -> Job:
	return RoadWork._claim_on_road(self, r)


func site_ready(st: Dictionary) -> bool:
	return RoadWork.site_ready(self, st)


func _lay_rail(st: Dictionary) -> void:
	RoadWork._lay_rail(self, st)


func _railhead_spot() -> Vector2i:
	return RoadWork._railhead_spot(self)


func railhead_rails() -> int:
	return RoadWork.railhead_rails(self)


func line_short() -> int:
	return RoadWork.line_short(self)


func station(end: String) -> Dictionary:
	return RoadWork.station(self, end)


static func station_x(end: String) -> float:
	return RoadWork.station_x(end)


func plan_station(end: String) -> String:
	return RoadWork.plan_station(self, end)


func cart_ready() -> bool:
	return RoadWork.cart_ready(self)


func cart_adds_room() -> bool:
	return RoadWork.cart_adds_room(self)


func _seat(r: Dictionary) -> Vector2:
	return RoadWork._seat(self, r)


func _off_cart_cell() -> Vector2i:
	return RoadWork._off_cart_cell(self)


func _step_cart() -> void:
	RoadWork._step_cart(self)


# ---------------------------------------------------------------- the party at the site (issue #109)
# The rules live in party_work.gd (#305); these forward to them.

func at_site(r: Dictionary) -> bool:
	return PartyWork.at_site(self, r)


func pack_load() -> int:
	return PartyWork.pack_load(self)


func pack_room() -> int:
	return PartyWork.pack_room(self)


func _room_to_promise() -> int:
	return PartyWork._room_to_promise(self)


func spendable_meals() -> int:
	return PartyWork.spendable_meals(self)


func _pack_spendable() -> int:
	return PartyWork._pack_spendable(self)


func objective_packed() -> int:
	return PartyWork.objective_packed(self)


static func block_yield(item: String) -> int:
	return PartyWork.block_yield(item)


static func gives(b: Dictionary, item: String) -> bool:
	return PartyWork.gives(b, item)


func _ration_job(r: Dictionary):
	return PartyWork._ration_job(self, r)


func _site_job(r: Dictionary):
	return PartyWork._site_job(self, r)


func shelter_site() -> Dictionary:
	return PartyWork.shelter_site(self)


func cache_meals() -> int:
	return PartyWork.cache_meals(self)


func _supplies_cover(cost: Dictionary) -> bool:
	return PartyWork._supplies_cover(self, cost)


static func dest_route(dest: String) -> String:
	return PartyWork.dest_route(dest)


func _nether_transit_job(r: Dictionary) -> Job:
	return PartyWork._nether_transit_job(self, r)


# ---------------------------------------------------------------- the Nether line (issue #159)
# The rules live in nether_line.gd (#305); these forward to them.

func nline() -> Dictionary:
	return NetherLine.nline(self)


static func nline_obstacle(seg: int) -> bool:
	return NetherLine.nline_obstacle(seg)


func nline_complete() -> bool:
	return NetherLine.nline_complete(self)


func nline_remaining() -> Dictionary:
	return NetherLine.nline_remaining(self)


func nline_task(where: String, who := 0) -> Dictionary:
	return NetherLine.nline_task(self, where, who)


func _line_supplies(plan: Dictionary) -> void:
	NetherLine._line_supplies(self, plan)


func nline_text() -> String:
	return NetherLine.nline_text(self)


func building_line() -> bool:
	return NetherLine.building_line(self)


func _line_job(task: Dictionary, who := 0) -> Job:
	return NetherLine._line_job(self, task, who)


func _finish_line_task(task: Dictionary, r: Dictionary) -> void:
	NetherLine._finish_line_task(self, task, r)


func _riding(r: Dictionary) -> bool:
	return NetherLine._riding(self, r)


static func nline_times() -> Dictionary:
	return NetherLine.nline_times()


# ---------------------------------------------------------------- the portal line (issue #168)
# The rules live in portal_line.gd (#305); these forward to them.

func portal_station() -> Dictionary:
	return PortalLine.portal_station(self)


func pline_nether_done() -> bool:
	return PortalLine.pline_nether_done(self)


func pline_complete() -> bool:
	return PortalLine.pline_complete(self)


func building_pline() -> bool:
	return PortalLine.building_pline(self)


func pline_task(who := 0) -> Dictionary:
	return PortalLine.pline_task(self, who)


func _pline_job(task: Dictionary, who := 0) -> Job:
	return PortalLine._pline_job(self, task, who)


func _finish_pline_task(task: Dictionary, r: Dictionary) -> void:
	PortalLine._finish_pline_task(self, task, r)


func _pline_supplies(plan: Dictionary) -> void:
	PortalLine._pline_supplies(self, plan)


func pline_text() -> String:
	return PortalLine.pline_text(self)


# ---------------------------------------------------------------- redstone devices and dust (issues #170, #171)
# The rules live in redstone.gd (#305); these forward to them.

static func device_default_cfg(kind: String) -> Dictionary:
	return Redstone.device_default_cfg(kind)


static func is_device(s: Dictionary) -> bool:
	return Redstone.is_device(s)


func device_by_id(id: int) -> Dictionary:
	return Redstone.device_by_id(self, id)


func wire_by_id(id: int):
	return Redstone.wire_by_id(self, id)


static func wire_complete(w: Dictionary) -> bool:
	return Redstone.wire_complete(w)


func wire_cells(a: Dictionary, b: Dictionary) -> Array[Vector2i]:
	return Redstone.wire_cells(self, a, b)


func order_wire(from_id: int, to_id: int) -> String:
	return Redstone.order_wire(self, from_id, to_id)


func cut_wire(id: int) -> void:
	Redstone.cut_wire(self, id)


func _wire_job(r: Dictionary, c: Vector2i):
	return Redstone._wire_job(self, r, c)


func _step_devices() -> void:
	Redstone._step_devices(self)


func condition_fact(fact: String) -> Dictionary:
	return Redstone.condition_fact(self, fact)


func cache_count(item: String) -> int:
	return Redstone.cache_count(self, item)


func freight_loader() -> Dictionary:
	return Redstone.freight_loader(self)


func loader_powered(s: Dictionary) -> bool:
	return Redstone.loader_powered(self, s)


func freight_missing(s: Dictionary) -> Dictionary:
	return Redstone.freight_missing(self, s)


static func freight_list_text(list: Dictionary) -> String:
	return Redstone.freight_list_text(list)


func _loading_en_route(item: String) -> int:
	return Redstone._loading_en_route(self, item)


func _loader_job(r: Dictionary, c: Vector2i):
	return Redstone._loader_job(self, r, c)


func set_freight_item(id: int, item: String, n: int) -> void:
	Redstone.set_freight_item(self, id, item, n)


func set_device_cfg(id: int, key: String, value) -> void:
	Redstone.set_device_cfg(self, id, key, value)


const CONDITION_FACTS = Redstone.CONDITION_FACTS

# ---------------------------------------------------------------- the freight cart (issue #169)
# The rules live in freight.gd (#305); these forward to them.

func order_freight_cart_blocker() -> String:
	return Freight.order_freight_cart_blocker(self)


func order_freight_cart() -> String:
	return Freight.order_freight_cart(self)


func _freight_dock_job(r: Dictionary, c: Vector2i):
	return Freight._freight_dock_job(self, r, c)


func approve_freight() -> String:
	return Freight.approve_freight(self)


func dispatcher() -> Dictionary:
	return Freight.dispatcher(self)


func decline_freight() -> String:
	return Freight.decline_freight(self)


func cancel_freight_approval() -> void:
	Freight.cancel_freight_approval(self)


func cache_items() -> int:
	return Freight.cache_items(self)


func _step_freight() -> void:
	Freight._step_freight(self)


func freight_place() -> Dictionary:
	return Freight.freight_place(self)


func _stuck_freight() -> void:
	Freight._stuck_freight(self)


# ---------------------------------------------------------------- enchanting (issues #165-#167)
# The rules live in enchanting.gd (#305); these forward to them.

static func item_title(type: String) -> String:
	return Enchanting.item_title(type)


static func enchant_text(ench: String) -> String:
	return Enchanting.enchant_text(ench)


func enchanting_workshop() -> Dictionary:
	return Enchanting.enchanting_workshop(self)


func enchant_known(ench: String) -> bool:
	return Enchanting.enchant_known(self, ench)


func learnable_books() -> Array:
	return Enchanting.learnable_books(self)


func _enchant_claim(r: Dictionary, c: Vector2i):
	return Enchanting._enchant_claim(self, r, c)


func enchantable_types(ench: String) -> Array:
	return Enchanting.enchantable_types(self, ench)


func order_enchant(ench: String, item: String) -> String:
	return Enchanting.order_enchant(self, ench, item)


func cancel_enchant(i: int) -> void:
	Enchanting.cancel_enchant(self, i)


func enchant_missing(ws: Dictionary) -> Dictionary:
	return Enchanting.enchant_missing(self, ws)



# ---------------------------------------------------------------- stranding and rescue (issue #158)
# The rules live in stranding.gd (#305); these forward to them.

func _check_stranded() -> void:
	Stranding._check_stranded(self)


func _abandon(why: String) -> void:
	Stranding._abandon(self, why)


func stranded_text(ex: Dictionary) -> String:
	return Stranding.stranded_text(self, ex)


func _stranded_job(r: Dictionary) -> Job:
	return Stranding._stranded_job(self, r)


func _rescue_job(r: Dictionary, c: Vector2i):
	return Stranding._rescue_job(self, r, c)


func delving() -> bool:
	return Stranding.delving(self)


func _delve_job(r: Dictionary, c: Vector2i):
	return Stranding._delve_job(self, r, c)


func _note_book(item: String, r: Dictionary) -> void:
	Stranding._note_book(self, item, r)


func _take_salvage() -> void:
	Stranding._take_salvage(self)


func _camp_job(r: Dictionary, c: Vector2i):
	return Stranding._camp_job(self, r, c)


func _next_trade() -> int:
	return Stranding._next_trade(self)


func _landing_job(r: Dictionary, c: Vector2i):
	return Stranding._landing_job(self, r, c)


# ---------------------------------------------------------------- creatures and combat (issue #151)
# The rules live in creatures.gd (#305); these forward to them.

func spawn_creature(id: String, species: String, cell: Vector2i) -> Dictionary:
	return Creatures.spawn_creature(self, id, species, cell)


func _dangerous(x: Dictionary) -> bool:
	return Creatures._dangerous(self, x)


func _step_creatures() -> void:
	Creatures._step_creatures(self)


func _strike(r: Dictionary, cr: Dictionary) -> void:
	Creatures._strike(self, r, cr)


func _fight_job(r: Dictionary, c: Vector2i):
	return Creatures._fight_job(self, r, c)


func _meadow_job(r: Dictionary, c: Vector2i):
	return Creatures._meadow_job(self, r, c)


func _drop_unused(r: Dictionary, j) -> void:
	Creatures._drop_unused(self, r, j)


func _priority_stack(st: Dictionary) -> bool:
	return Creatures._priority_stack(self, st)


func _stow_job(r: Dictionary, c: Vector2i):
	return Creatures._stow_job(self, r, c)


func _mark_objective() -> void:
	Creatures._mark_objective(self)


func _way_through(to: Vector2i, allow_loose := false) -> Array:
	return Creatures._way_through(self, to, allow_loose)


func _nothing_left() -> bool:
	return Creatures._nothing_left(self)


func level_left() -> int:
	return Creatures.level_left(self)


func _head_home(why: String) -> void:
	Creatures._head_home(self, why)


func _step_site() -> void:
	Creatures._step_site(self)


func _stuck_site() -> void:
	Creatures._stuck_site(self)


# ---------------------------------------------------------------- choices that stop the game (issues #110, #111)

## Asks the player to choose (brief §5): the game pauses until they do. Each option: {id, label, cost}.
func _ask(kind: String, text: String, options: Array, res_id := 0) -> void:
	pending.append({"kind": kind, "text": text, "options": options, "res_id": res_id, "map": map_id, "slot": slot})
	events.append({"type": "pause"})
	rev += 1


## Answers the first pending choice with one of its options.
func choose(option: String) -> void:
	if pending.is_empty():
		return
	var p: Dictionary = pending.pop_front()
	var prev := use_map(p.map)
	var prev_slot := use_slot(p.get("slot", "overworld"))
	match [p.kind, option]:
		["injury", "retreat"]:
			if expedition.get("leg", "out") == "out":
				_head_home("retreat, %s is seriously hurt" % resident(p.res_id).get("name", "someone"))
		["injury", "press_on"]:
			pass  # the hurt one waits at the entrance (see _site_job)
		["discovery", "keep"]:
			pass  # the vein stays marked on the site map
		["discovery", "investigate"]:
			expedition.survey = true
		["discovery", "return"]:
			if expedition.get("leg", "out") == "out":
				_head_home("the iron is marked to come back for")
		["door", "down"]:
			go_down()
		["door", "later"]:
			if expedition.get("leg", "out") == "out":
				_head_home("the door is marked for another trip")
		["door", "keep"]:
			pass  # the door stays marked; the next trip can be planned for the level below
		["stranded", "wait"]:
			pass  # they shelter; the window runs
		["stranded", "walk"]:
			_abandon("the party set out on its own")
		["book", "ok"]:
			pass
		["fortress", "take"]:
			_take_salvage()
			if expedition.get("leg", "out") == "out":
				_head_home("the salvage is taken")
		["fortress", "press"]:
			_take_salvage()
			expedition.fight = true  # the guards go after what's left (issue #157)
			expedition.pressing = true
	use_slot(prev_slot)
	use_map(prev)
	rev += 1


# ---------------------------------------------------------------- hazards and injuries (issue #110)
# The rules live in hazards.gd (#305); these forward to them.

func injure(r: Dictionary, level: int, cause: String) -> void:
	Hazards.injure(self, r, level, cause)


func _roll(chance: float) -> bool:
	return Hazards._roll(self, chance)


func _hazard(r: Dictionary, chance: float, serious: float, cause: String, kind := "") -> void:
	Hazards._hazard(self, r, chance, serious, cause, kind)


static func armor_ench_count(r: Dictionary, ench: String) -> int:
	return Hazards.armor_ench_count(r, ench)


static func armor_worn(r: Dictionary) -> Dictionary:
	return Hazards.armor_worn(r)


static func protection(r: Dictionary) -> float:
	return Hazards.protection(r)


func _wear_armor(r: Dictionary) -> void:
	Hazards._wear_armor(self, r)


func _arm_job(r: Dictionary, c: Vector2i):
	return Hazards._arm_job(self, r, c)


func _dress_job(r: Dictionary, c: Vector2i):
	return Hazards._dress_job(self, r, c)


func _dress(r: Dictionary, stack: Dictionary) -> Job:
	return Hazards._dress(self, r, stack)


func _burn_step(r: Dictionary) -> void:
	Hazards._burn_step(self, r)


func _ledge_step(r: Dictionary, c: Vector2i) -> void:
	Hazards._ledge_step(self, r, c)


static func cave_in_chance(level: int) -> float:
	return Hazards.cave_in_chance(level)


static func fall_chance(level: int) -> float:
	return Hazards.fall_chance(level)


static func hurt_speed(r: Dictionary) -> float:
	return Hazards.hurt_speed(r)


func _rest_job(r: Dictionary) -> Job:
	return Hazards._rest_job(self, r)


func _has_bed(r: Dictionary) -> bool:
	return Hazards._has_bed(self, r)


func resting(r: Dictionary) -> bool:
	return Hazards.resting(self, r)


# ---------------------------------------------------------------- the iron discovery (issue #111)
# The rules live in iron_discovery.gd (#305); these forward to them.

func _check_find(c: Vector2i) -> void:
	IronDiscovery._check_find(self, c)


func _check_find_diamond(c: Vector2i) -> void:
	IronDiscovery._check_find_diamond(self, c)


func _find_vein() -> void:
	IronDiscovery._find_vein(self)


func _survey_job(r: Dictionary):
	return IronDiscovery._survey_job(self, r)


func survey(id: String) -> void:
	IronDiscovery.survey(self, id)


# ---------------------------------------------------------------- the old mine's levels (issue #132)

## The old mine's levels that exist so far, top down: "old_mine", "old_mine_2", ...
func mine_levels() -> Array:
	var out: Array = []
	var n := 1
	while maps.has(MineLevels.level_id(n)):
		out.append(MineLevels.level_id(n))
		n += 1
	return out


## The level a map is on, or 0 for a map that isn't part of the old mine.
func level_of(id: String) -> int:
	return maps[id].level if maps.has(id) else 0


## Someone has reached the door at the end of the level: it's marked, the level below is made ready
## (unknown until it's opened), and, with the party working here, the game stops for the player.
func _find_door(r: Dictionary) -> void:
	m.door_state = "found"
	var below := MineLevels.level_id(m.level + 1)
	if not maps.has(below):
		maps[below] = MineLevels.build(self, m.level + 1)
	rev += 1
	_toast("%s reached the door at the end of the %s." % [r.name, m.name.to_lower()], r.id)
	if not at_site(r):
		return
	if expedition.get("clear", false):  # a cleared level: down it goes, with no pause for the choice (issue #188)
		go_down()
		return
	_ask("door", "%s reached a heavy door at the far end of the %s. Below it lies level %d." % [r.name, m.name.to_lower(), m.level + 1], [
		{"id": "down", "label": "Go down now", "cost": "The party opens it and works level %d instead: richer and riskier. What they mine comes back up the same way." % (m.level + 1)},
		{"id": "later", "label": "Mark it for later", "cost": "The party heads home now, with what it has packed. Level %d can be planned at the board." % (m.level + 1)},
		{"id": "keep", "label": "Keep mining here", "cost": "Carry on for %s. The door stays marked." % objective_text()},
	], r.id)


## Opens a level's door: the level below appears on the map switcher.
func open_door(id: String) -> void:
	var mp: SimMap = maps[id]
	var below := MineLevels.level_id(mp.level + 1)
	if not maps.has(below):
		maps[below] = MineLevels.build(self, mp.level + 1)
	mp.door_state = "open"
	maps[below].known = true
	rev += 1


## Go down now: the party at the door's level takes it, and works the level below from now on. Their
## packs go with them. Returns why it can't, or "".
func go_down() -> String:
	var ex := expedition
	if ex.get("state", "") != "out" or ex.get("leg", "out") != "out" or level_of(ex.dest) == 0:
		return "The party isn't working the old caves"
	var mp: SimMap = maps[ex.dest]
	if mp.door_state == "closed":
		return "Nobody has reached the door yet"
	var prev := use_map(ex.dest)
	open_door(ex.dest)
	ex.dest = MineLevels.level_id(mp.level + 1)
	for id in ex.party:
		fail_job(resident(id))
	_toast("The party opens the door and heads down to level %d." % (mp.level + 1), ex.party[0])
	use_map(prev)
	return ""


## Marks the blocks between the party and the door on a level, so they mine their way to it. Loose
## ceilings on the way are marked too: the player chose the way. Returns why it can't, or "".
func dig_to_door(id: String) -> String:
	var mp: SimMap = maps[id]
	if mp.door_state != "closed":
		return "The door is already reached"
	var prev := use_map(id)
	var way := _way_through(MineLevels.door_front(mp), true)
	if way.is_empty() and walkable(MineLevels.door_front(mp)):
		use_map(prev)
		return "The way to the door is open"
	for b in way:
		b.des = true
		b.unreach_until = 0
	rev += 1
	use_map(prev)
	return "" if not way.is_empty() else "There's no way through to the door"


## Seconds to walk down through the levels above this one: entrance to door on each (issue #132).
func level_walk(id: String) -> float:
	var t := 0.0
	for n in range(1, level_of(id)):
		var mp: SimMap = maps[MineLevels.level_id(n)]
		var prev := use_map(mp.id)
		var p = find_path(mp.entrance, adj_set([mp.door]))
		use_map(prev)
		t += (p.size() if p != null else Sim.manhattan(mp.entrance, mp.door)) / Tuning.WALK
	return t


# ---------------------------------------------------------------- site maps (issue #102)

## "Boulder", "Coal ore" or "Iron ore".
static func block_name(b: Dictionary) -> String:
	return Defs.ORES[b.ore].name if b.has("ore") else "Boulder"


## Ore blocks of this kind left on a site map, counting hidden ones only once they're found.
func ore_left(id: String, ore: String) -> int:
	var mp: SimMap = maps[id]
	return mp.boulders.filter(func(b): return b.alive and b.get("ore", "") == ore and (mp.discovered or not b.get("hidden", false)) and not (ore == "diamond" and b.get("hidden", false))).size()


## The site report (brief §8) the expedition board shows before departure:
##   {name, told, visited, travel (seconds), resources: [{item, name, reserve, known}], hazards, access, finds}
## A reserve is the estimated items still to be mined, or -1 for "?". Before anyone has been there,
## the report has only what the village has been told: names, no estimates and no known hazards.
## The iron shows as "?" until it's found, and has no estimate until it's surveyed (issue #111).
func site_report(id: String) -> Dictionary:
	if NetherRoute.site_key(id) != "" and maps[id].pattern != "":  # a built site (issues #155-#157)
		return _nether_site_report(id)
	if NetherRoute.route_of(id) != "" or NetherRoute.site_key(id) != "":
		return _nether_route_report(id)
	if id == Meadow.ID:
		return _meadow_report()
	if id == NetherLanding.ID:
		return _landing_report()
	var mp: SimMap = maps[id]
	var stone := mp.boulders.filter(func(b): return b.alive and not b.has("ore")).size()
	var res: Array = [
		{"item": "cobble", "name": "Stone", "reserve": stone * Tuning.BOULDER_COBBLE if mp.visited else -1},
		{"item": "coal", "name": "Coal", "reserve": ore_left(id, "coal") * Tuning.ORE_YIELD.coal if mp.visited else -1},
	]
	for x in res:
		x.known = true
	if mp.discovered:
		res.append({"item": "iron_ore", "name": "Iron", "reserve": ore_left(id, "iron") * Tuning.ORE_YIELD.iron, "known": true})
	elif mp.found:
		res.append({"item": "iron_ore", "name": "Iron", "reserve": -1, "known": false})
	elif mp.visited:
		res.append({"item": "iron_ore", "name": "?", "reserve": -1, "known": false})
	if mp.diamond_found:  # a known resource of this level once someone has found it (issue #186)
		res.append({"item": "diamond", "name": "Diamond", "reserve": ore_left(id, "diamond") * Tuning.ORE_YIELD.diamond, "known": true})
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
				"reserve": ore_left(id, ore) * Tuning.ORE_YIELD[ore], "known": true})
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
	for lid in mine_levels():  # every level known so far (issue #132)
		var lm: SimMap = maps[lid]
		var left: int = lm.boulders.filter(func(b): return b.alive and b.has("ore") and (lm.discovered or not b.get("hidden", false)) and not (b.get("ore", "") == "diamond" and b.get("hidden", false))).size()
		var door: String = {"open": "door open", "found": "door found"}.get(lm.door_state, "door not reached")
		levels.append({"id": lid, "level": lm.level, "pattern": MineLevels.FAMILY_NAMES.get(lm.pattern, ""), "ore": left if lm.visited else -1, "door": door, "visited": lm.visited})
	var travel := route_walk_time() + level_walk(id) if route_surveyed() else -1.0
	return {"name": mp.name, "told": told, "visited": mp.visited, "travel": travel, "level": mp.level, "pattern": MineLevels.FAMILY_NAMES.get(mp.pattern, ""),
		"biome": MineLevels.BIOMES[MineLevels.biome(mp.level)] if mp.level > 0 else "", "resources": res, "hazards": hazards, "access": (MineLevels.ACCESS.get(mp.pattern, []) + [MineLevels.BIOME_NOTES[MineLevels.biome(mp.level)]]) if mp.visited else [], "finds": finds,
		"levels": levels if mp.level > 0 else [], "door": mp.door_state}


## The meadow's site report (issue #137): what each herd would give if it were all hunted, the herds
## themselves, and its mild hazards.
func _meadow_report() -> Dictionary:
	var mp: SimMap = maps[Meadow.ID]
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
		"door": "", "herds": herds() if mp.visited else {}}


## A Nether route's report, or that of the site at its end (issue #153): what's known of the terrain, the dangers and the
## travel, segment by segment as far as scouts have seen. The site's resources wait for the issues that build it.
func _nether_route_report(id: String) -> Dictionary:
	var rk := NetherRoute.route_of(id)
	var is_route := rk != ""
	if not is_route:
		rk = NetherRoute.site_key(id)
	var def: Dictionary = NetherRoute.ROUTES[rk]
	var rm: SimMap = maps[def.id]
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
		var ln := nline()
		var laid := 0
		for n in ln.laid:
			laid += 1 if n >= Tuning.RAILS_PER_SEGMENT else 0
		line_text = "Line: %d of %d segments laid, %d of 2 bridges, %d of 2 stations, %s" % [laid, Road.segment_count(), ln.bridged.size(), (1 if ln.stations.landing else 0) + (1 if ln.stations.site else 0), "cart parked" if ln.cart else "no cart"]
	return {"name": name, "told": def.told, "line": line_text, "visited": rm.seen > 1 or rm.surveyed, "travel": walk if rm.surveyed else -1.0, "level": 0, "pattern": "",
		"resources": [], "hazards": hazards, "access": ["A narrow way beside the lava: bridges and cuts come with the line"] if rm.surveyed else [], "finds": [], "levels": [], "door": "",
		"segments": segs, "scouted": rm.surveyed, "seen": rm.seen}


## A built Nether site's report (issues #155-#157): what's there and how much is left, its dangers, the time to get there from
## the landing, and what the site has room for.
func _nether_site_report(id: String) -> Dictionary:
	var mp: SimMap = maps[id]
	var rk := NetherRoute.site_key(id)
	var def: Dictionary = NetherRoute.ROUTES[rk]
	var res: Array = []
	for ore in ["quartz", "glowstone"]:
		if mp.boulders.any(func(b): return b.get("ore", "") == ore):
			res.append({"item": Defs.ORES[ore].item, "name": Defs.ITEMS[Defs.ORES[ore].item].label, "reserve": ore_left(id, ore) * Tuning.ORE_YIELD[ore] if mp.visited else -1, "known": true})
	if rk_of_site(id) == "fortress":  # what the halls give, known from the start (issue #157)
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
		"access": [rk_access(rk)] if mp.visited else [], "finds": [], "levels": [], "door": ""}
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
func _landing_report() -> Dictionary:
	var mp: SimMap = maps[NetherLanding.ID]
	var routes: Array = []
	for rk in NetherRoute.ROUTES:
		var rmap: SimMap = maps[NetherRoute.ROUTES[rk].id]
		routes.append({"key": rk, "name": NetherRoute.ROUTES[rk].name.substr(8), "state": "scouted" if rmap.surveyed else ("partly scouted" if rmap.seen > 1 else "unknown"), "told": NetherRoute.ROUTES[rk].told})
	var shelter := shelter_site()
	var cache := ""
	if shelter.get("done", false):
		cache = "Shelter built. Cache: %s" % ("empty" if cache_meals() == 0 else "%d %s" % [cache_meals(), "meal" if cache_meals() == 1 else "meals"])
	return {"name": mp.name, "told": NetherLanding.TOLD, "visited": mp.visited, "travel": 0.0, "level": 0, "pattern": "", "cache": cache, "routes": routes,
		"resources": mp.drops_known.map(func(k): return {"item": k, "name": Defs.ITEMS[k].label, "reserve": -1, "known": true}),
		"hazards": NetherLanding.HAZARDS.duplicate() if mp.visited else [], "access": NetherLanding.ACCESS.duplicate() if mp.visited else [],
		"finds": [], "levels": [], "door": "", "landmarks": mp.landmarks_seen.size(), "landmark_total": mp.landmarks.size()}


# ---------------------------------------------------------------- the adventures list (issue #136)

## The destinations the expedition board offers, in order. A later one (the Nether, an outpost) is a
## new row here.
const ADVENTURES := Adventures.IDS


## The adventures list: one row per known destination, with where it is, what's there, its hazards
## and what's happening there. While a party is out, planning is locked and every row says where they are.
##   [{id, name, travel, what, hazards: [text], status, here (the party's destination), locked}]
func adventures() -> Array:
	var out: Array = []
	for id in ADVENTURES:
		if not maps.has(id) or not maps[id].known:
			continue
		var ex: Dictionary = expeditions[slot_of_dest(id)]  # each realm has its own party out (issue #145)
		var rep := site_report(id)
		var what := ""
		if id == NetherLanding.ID:
			what = "Netherrack and lava · %d of %d landmarks surveyed" % [rep.landmarks, rep.landmark_total] if rep.visited else "A burning country past the portal"
		elif id == Meadow.ID:
			var hs: Dictionary = rep.herds
			var n := 0
			for k in hs:
				n += hs[k]
			what = "Cows, pigs, sheep · %d animals" % n if rep.visited else "Sheep, cows and pigs, they say"
			var pens: Array = maps[id].pens
			if not pens.is_empty():  # issue #139
				var penned: int = maps[id].sheep.filter(func(a): return a.alive and a.get("pen", 0) != 0).size()
				what += " · %d %s, %d penned" % [pens.size(), "pen" if pens.size() == 1 else "pens", penned]
		else:
			var names: Array = rep.resources.filter(func(x): return x.known).map(func(x): return x.name)
			what = ", ".join(names)
			var open := mine_levels().filter(func(l): return level_of(l) > 1 and maps[l].known)
			if not open.is_empty():
				what += " · Level %d open" % level_of(open[-1])
		var here: bool = not ex.is_empty() and (ex.dest == id or (id == OldMine.ID and level_of(ex.dest) > 0))
		var status := "Not yet visited" if not rep.visited else "Visited"
		if here:
			status = {"staging": "Packing to go"}.get(ex.state, "")
			if status == "":
				var party: Array = ex.party.map(func(rid): return resident(rid))
				if ex.get("leg", "out") == "home":
					status = "Party heading home"
				elif party.all(func(r): return at_site(r)):
					status = "Party there now"
				else:
					status = "Party on the way"
		elif not ex.is_empty():
			status = "Locked: the party is at the %s" % maps[ex.dest].name.to_lower() if ex.get("state", "") == "out" else "Locked: packing for the %s" % maps[ex.dest].name.to_lower()
		out.append({"id": id, "name": rep.name if id != OldMine.ID else OldMine.NAME, "travel": rep.travel, "what": what,
			"hazards": rep.hazards if rep.visited else [], "status": status, "here": here, "locked": not ex.is_empty()})
	return out


## Reveals and surveys a site's hidden find at once, without a party there (for tests and setup).
func discover(id: String) -> void:
	survey(id)


# ---------------------------------------------------------------- saving

## Everything needed to resume, as plain data. Jobs, paths and reservations aren't saved: they're
## rebuilt on load (spec §2, Saving).
func save_state() -> Dictionary:
	var res_out: Array = []
	for r in residents:
		var c: Dictionary = r.duplicate(true)
		for k in ["job", "direct", "path", "progress", "note"]:
			c.erase(k)
		res_out.append(c)
	var maps_out := {}
	for id in maps:
		maps_out[id] = maps[id].save()
	return {"tick": tick, "next_id": next_id, "maps": maps_out, "residents": res_out,
		"stats": stats.duplicate(true), "arrival_at": arrival_at, "arrived": arrived, "auto_craft": auto_craft, "claims_made": claims_made, "cargo_lists": cargo_lists.duplicate(true), "last_plans": last_plans.duplicate(true),
		"herd_floor": herd_floor.duplicate(), "wheat_keep": wheat_keep, "rng_state": rng.state, "seed": seed,
		"expeditions": expeditions.duplicate(true), "pending": pending.duplicate(true), "cart": cart.duplicate(true),
		"portal_line": portal_line.duplicate(true), "freight": freight.duplicate(true), "wires": wires.duplicate(true)}


static func from_state(d: Dictionary) -> Sim:
	var s := Sim.new()
	s.tick = d.tick
	s.next_id = d.next_id
	s.maps = {}
	# Maps tick in the order a game makes them, so a loaded game replays as the saved one would have:
	# the village, the old mine, the road, the meadow, then the levels below the mine as they opened.
	var order := ["village", OldMine.ID, Road.ID, Meadow.ID, MeadowRoad.ID, NetherLanding.ID] + NetherRoute.map_ids()
	var ids: Array = d.maps.keys()
	ids.sort_custom(func(a, b): return [order.find(a) if a in order else 9, MineLevels.level_of(a)] < [order.find(b) if b in order else 9, MineLevels.level_of(b)])
	for id in ids:
		s.maps[id] = SimMap.from_save(d.maps[id])
		if MineLevels.level_of(id) > 0:  # an older save names it "Old mine" (issue #238): the name is display only
			s.maps[id].name = MineLevels.level_name(MineLevels.level_of(id))
	s.use_map("village")
	s.stats = d.stats.duplicate(true)
	s.arrival_at = d.arrival_at
	s.arrived = d.arrived
	s.auto_craft = d.auto_craft
	s.claims_made = d.get("claims_made", 0)
	s.cargo_lists = d.get("cargo_lists", {}).duplicate(true)
	s.last_plans = d.get("last_plans", {}).duplicate(true)
	s.herd_floor = d.herd_floor.duplicate()
	s.wheat_keep = d.get("wheat_keep", Tuning.WHEAT_KEEP)
	# Bushes added to older saves (v7) may sit where something now stands; drop those.
	s.bushes = s.bushes.filter(func(b):
		for o in s.trees + s.boulders:
			if o.alive and o.cell == b.cell:
				return false
		for st in s.sites:
			if Rect2i(st.origin, st.size).has_point(b.cell):
				return false
		return true)
	s.rng.state = d.rng_state
	s.seed = d.get("seed", Tuning.SEED)
	if d.has("expeditions"):
		s.expeditions = d.expeditions.duplicate(true)
	else:  # a state from before the slots (issue #145)
		s.expeditions = {"overworld": d.get("expedition", {}).duplicate(true), "nether": {}, "rescue": {}}
	if not s.expeditions.has("rescue"):  # a state from before the rescue slot (issue #158)
		s.expeditions.rescue = {}
	s.pending = d.get("pending", []).duplicate(true)
	s.cart = d.get("cart", {}).duplicate(true)
	s.portal_line = d.get("portal_line", {"laid": 0}).duplicate(true)
	s.freight = d.get("freight", {}).duplicate(true)
	s.wires = d.get("wires", []).duplicate(true)
	var new_meadow := not s.maps.has(Meadow.ID)
	s._add_site_maps()
	if new_meadow and d.has("meadow_sheep"):  # an older save's off-map meadow: its sheep count carries over (issue #137)
		var left: int = d.meadow_sheep
		for a in s.maps[Meadow.ID].sheep:
			if a.species == "sheep":
				a.alive = left > 0
				left -= 1
		s.maps[Meadow.ID].sheep = s.maps[Meadow.ID].sheep.filter(func(a): return a.alive)
		s.maps[Meadow.ID].visited = d.stats.get("meadow_trips", 0) > 0
	for rd in d.residents:
		var r: Dictionary = rd.duplicate(true)
		r.job = null
		r.direct = null
		r.path = []
		r.progress = -1.0
		r.note = null
		r.pos = Vector2(rcell(r))
		s.residents.append(r)
	for r in s.residents:
		s.use_map(r.map)
		if r.carry != null:
			s.drop_items(rcell(r), r.carry.type, r.carry.n, r.carry.get("dur", -1))
			r.carry = null
		if r.arriving:
			s.walk_in(r)
	s.use_map("village")
	s.compute_stuck()
	return s
