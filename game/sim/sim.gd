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
	"meals_cooked": 0, "ore_home": false, "found": {}, "surveyed": {}}
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
	s.stats.day_zero = -int(Tuning.DUSK_SECONDS * Tuning.TPS)  # a game starts on a morning, just past the dawn light (issue #357)
	Goals.seed_seen(s)  # the pages open from the start aren't "new" (issue #348)
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
	for sid in Structures.IDS:  # the structure adventures: known once surveyed (Slice 7)
		if not maps.has(sid):
			maps[sid] = Structures.build(self, sid)
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
	var b := {"id": _id(), "kind": "bush", "cell": cell, "berries": Tuning.BUSH_MAX, "regrow": 0.0, "des": false, "claim": 0}
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
		"away": false, "back_at": 0, "trip": "", "map": map_id, "hurt": 0, "heal": 0.0, "armor": {}, "emeralds": 0}
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
		r.emeralds = r.get("emeralds", 0) + after - before  # an emerald for each level from 2 up (issue #346)
		_toast("%s is now level %d at %s." % [r.name, after, Defs.JOB_NAMES[job]], r.id)
		for h in m.sites:  # their home can grow now (issue #285)
			if h.tpl == "house" and h.owner == r.id and h.get("tier", 3) < 3 and h.done and r.emeralds == Tuning.EMERALD_COSTS[h.tier - 1]:
				_toast("%s has enough emeralds to upgrade their home. Select the house." % r.name, 0, h.id)
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
			var gate := house_gate(s)
			for c in site_cells(s):
				if c != gate:
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
	if not Defs.ITEMS[type].has("tier"):  # a torch carried to a door (issue #367)
		return 1
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


## What an idle resident's search found about the items, kept while nothing changes (issue #351): a search that finds
## nothing shouldn't walk hundreds of stacks again every tick. Valid for one map and one `rev`, and for a second at
## most, so a change that doesn't bump `rev` is only late, not lost. A caller still checks what it takes from it.
var _scans := {}
var _scan_rev := -1
var _scan_map := ""
var _scan_tick := 0


func _scans_fresh() -> void:
	if _scan_rev != rev or _scan_map != m.id or tick - _scan_tick >= Tuning.TPS or tick < _scan_tick:
		_scans.clear()
		_scan_rev = rev
		_scan_map = m.id
		_scan_tick = tick


## The stacks matching `pred`, worked out once while nothing changes, still in place when asked.
func stacks_cached(key: String, pred: Callable) -> Array:
	_scans_fresh()
	if not _scans.has(key):
		_scans[key] = stacks_where(pred)
	return _scans[key].filter(func(s): return is_same(m.items.get(s.cell), s))


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
	return stacks_cached("tool_" + kind, func(s): return Defs.ITEMS[s.type].get("tool", "") == kind).filter(func(s): return Defs.ITEMS[s.type].tier > min_tier and avail(s) > 0)


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
	return s.done or (s.tpl == "house" and (s.stage >= 1 or s.get("grow", false)))


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
	if Defs.TEMPLATES[tpl].size == Vector2i(3, 3):  # the storehouse widens to either side of its door's column (issue #318)
		var more := Tuning.STORE_WIDTH_MAX - Tuning.STORE_WIDTH_MIN
		if rot % 2 == 0:
			return Rect2i(origin + Vector2i(-more, 0), Vector2i(3 + 2 * more, 3))
		return Rect2i(origin + Vector2i(0, -more), Vector2i(3, 3 + 2 * more))
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
	if s.tpl == "store_room":  # a column costs the same however many go up together (issue #318)
		var cost := {}
		for k in Tuning.STORE_COLUMN_COST:
			cost[k] = Tuning.STORE_COLUMN_COST[k] * s.cols
		return {"name": "%d more %s" % [s.cols, "column" if s.cols == 1 else "columns"], "verb": "needs", "cost": cost}
	return stages_of(s)[s.stage]


## A site's stage list: a tiered house's current tier, else its template's (issue #285).
static func stages_of(s: Dictionary) -> Array:
	if s.tpl == "house" and s.has("tier"):
		return Defs.HOUSE_STAGES[s.tier]
	return Defs.TEMPLATES[s.tpl].stages


## The tier a house has been built to (1 tent, 2 house, 3 building), or 0 before it's finished. A house placed before tiers is the building.
static func house_tier(s: Dictionary) -> int:
	if not s.has("tier"):
		return 3
	return s.tier - 1 if s.get("grow", false) or not s.done else s.tier


## The part of a house's 5x5 plot that tier `tier` builds on (issue #285): 3 wide and 2 deep for the tent, 3x3 for the house and the whole
## plot for the building, against the side its door is on, centred across it.
static func house_rect(s: Dictionary, tier: int) -> Rect2i:
	var lat := 5 if tier >= 3 else 3
	var depth := 2 if tier <= 1 else (3 if tier == 2 else 5)
	var o: Vector2i = s.origin
	var off := (5 - lat) / 2
	match s.rot % 4:
		0: return Rect2i(o + Vector2i(off, 5 - depth), Vector2i(lat, depth))
		1: return Rect2i(o + Vector2i(5 - depth, off), Vector2i(depth, lat))
		2: return Rect2i(o + Vector2i(off, 0), Vector2i(lat, depth))
	return Rect2i(o + Vector2i(0, off), Vector2i(depth, lat))


## Why a finished house can't be upgraded, or "" when it can: the tiers, its resident and their emeralds (issue #285).
func house_upgrade_check(s: Dictionary) -> String:
	if s.tpl != "house" or not s.has("tier") or not s.done:
		return "Only a finished house can be upgraded"
	if s.tier >= 3:
		return "It's the finished building"
	var who := resident(s.owner)
	if who.is_empty():
		return "Nobody lives here yet"
	var need: int = Tuning.EMERALD_COSTS[s.tier - 1]
	if who.get("emeralds", 0) < need:
		return "%s needs %d emeralds (has %d)" % [who.name, need, who.get("emeralds", 0)]
	return ""


## Starts a house's next tier: its resident spends the emeralds and builders bring the materials like any stage. Returns whether it began.
func upgrade_house(s: Dictionary) -> bool:
	if house_upgrade_check(s) != "":
		return false
	resident(s.owner).emeralds -= Tuning.EMERALD_COSTS[s.tier - 1]
	s.tier += 1
	s.grow = true
	s.done = false
	s.stage = 0
	s.store = {}
	s.incoming = {}
	s.builder = 0
	_occ_dirty = true
	rev += 1
	return true


func door_cell(origin: Vector2i, rot: int) -> Vector2i:
	match rot % 4:
		0: return origin + Vector2i(2, 4)
		1: return origin + Vector2i(4, 2)
		2: return origin + Vector2i(2, 0)
		_: return origin + Vector2i(0, 2)


## The cell in front of a house's door, outside its plot (issue #285): where residents come and go.
static func front_cell(origin: Vector2i, rot: int) -> Vector2i:
	match rot % 4:
		0: return origin + Vector2i(2, 5)
		1: return origin + Vector2i(5, 2)
		2: return origin + Vector2i(2, -1)
		_: return origin + Vector2i(-1, 2)


## A house placed before entrances (issue #285, #356) is an old house: it has no entrance, its residents take no jobs, and it shows
## as a blueprint until it's updated or moved.
static func is_old_house(s: Dictionary) -> bool:
	return s.tpl == "house" and s.get("old", false)


## The one cell of a house's plot residents can walk onto, its door, or (-1, -1) for anything else and for an old house.
func house_gate(s: Dictionary) -> Vector2i:
	if s.tpl != "house" or s.get("old", false):
		return Vector2i(-1, -1)
	return door_cell(s.origin, s.rot)


## Where a resident goes to be home: through the door, or beside an old house.
func home_goal(s: Dictionary) -> Dictionary:
	if is_old_house(s):
		return _goto(site_cells(s), true)
	return _goto([door_cell(s.origin, s.rot)], false)


## Whether the cell in front of a house's door can be walked from: in bounds, no water or fence, no building or reserved plot on it.
## `ignore` is a site that doesn't count (the one being moved). Trees and boulders there are cleared with the footprint.
func front_clear(front: Vector2i, ignore := 0) -> bool:
	if not m.in_bounds(front) or m.water.has(front) or m.rock.has(front) or m.fences.has(front):
		return false
	for s in m.sites:
		if s.id != ignore and (Rect2i(s.origin, s.size).has_point(front) or (s.get("plot") != null and s.plot.has_point(front))):
			return false
	return true


## Whether this resident's own house is an old one, so they take no jobs until it's updated (issue #356). Worked out once per change.
func waits_for_home(r: Dictionary) -> bool:
	if _old_owner_rev != rev:
		_old_owner_rev = rev
		_old_owners.clear()
		for s in maps.village.sites:
			if is_old_house(s) and s.owner != 0:
				_old_owners[s.owner] = true
	return _old_owners.has(r.id)


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
	return obstacles_for(s.tpl, s.origin, s.rot, s)


## What a building at `origin` has to clear: its footprint, and a house's front door step (issue #285).
func obstacles_for(tpl: String, origin: Vector2i, rot: int, s = null) -> Dictionary:
	var o := obstacles_in(Rect2i(origin, Defs.TEMPLATES[tpl].size if s == null else s.size))
	if tpl == "house" and (s == null or not is_old_house(s)):
		var f := obstacles_in(Rect2i(front_cell(origin, rot), Vector2i.ONE))
		for k in ["trees", "boulders"]:  # only what blocks walking: loose items and bushes can be stepped over
			o[k].append_array(f[k])
	return o


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
	if m.zone.is_empty():  # with nowhere painted to keep things, wheat lying on a plot is carried clear so it can be replanted (issue #318)
		for k in m.farm:
			if m.items.has(k):
				out[k] = true
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
		s.stage = stages_of(s).size()
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
	if s.stage >= stages_of(s).size():
		s.done = true
		s.store = {}
		s.incoming = {}
		if s.get("grow", false):  # a house has grown a tier (issue #285): it's no new home
			s.grow = false
			_toast("%s's home is now a %s." % [resident(s.owner).name, Defs.HOUSE_TIER_NAMES[s.tier - 1].to_lower()], 0, s.id)
		else:
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


## A finished pen blueprint in the village becomes a pen: fences all round, the gate in the middle of the side that faces the way
## it was turned, and the blueprint is taken away (issue #355).
func _make_village_pen(s: Dictionary) -> void:
	var rect := Rect2i(s.origin, s.size)
	var mid := rect.position + rect.size / 2
	var gates := [Vector2i(mid.x, rect.end.y - 1), Vector2i(rect.end.x - 1, mid.y), Vector2i(mid.x, rect.position.y), Vector2i(rect.position.x, mid.y)]
	var gate: Vector2i = gates[s.rot % 4]
	var p := {"id": _id(), "kind": "pen", "rect": rect, "gate": gate, "built": {}}
	for c in Pens.pen_edge(p):
		p.built[c] = true
		if c == gate:
			m.gates[c] = true
		else:
			m.fences[c] = true
	m.pens.append(p)
	m.sites.erase(s)
	_occ_dirty = true
	rev += 1
	_toast("A pen is finished in the village, with room for %d animals." % Pens.pen_room(p))


func _on_site_done(s: Dictionary) -> void:
	if s.tpl == "store_room":
		_merge_store_room(s)
		return
	assign_workstations()
	if s.tpl == "claim_stakes":  # the strip joins the village between ticks (issue #187), with its own toast
		return
	if not stats.has("built"):
		stats.built = {}
	stats.built[s.tpl] = true  # for the founding goals (issue #182)
	if s.tpl == "village_pen":  # the blueprint becomes a pen with all its fences up (issue #355)
		_make_village_pen(s)
		return
	if s.tpl == "composter":
		_start_plots(s)  # a new composter starts with plots round it (issue #319)
	if s.tpl in ["toolsmith_bench", "composter", "lodge", "builder_table", "cartographer_table"]:
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
		if not Survey.enabled or Survey.found(self, "old_mine"):  # otherwise the Cartographer finds the caves (issue #321)
			maps[OldMine.ID].known = true
			road().known = true
		maps[Meadow.ID].known = true
		maps[MeadowRoad.ID].known = true
		_toast("The expedition board is up, with word of a meadow to the west%s. Select it to plan an adventure." % (" and some old caves to the east" if maps[OldMine.ID].known else ""), 0, s.id)
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


## The way a storehouse widens: along x when its door faces north or south, else along y (issue #318).
static func store_axis(s: Dictionary) -> Vector2i:
	return Vector2i(1, 0) if s.rot % 2 == 0 else Vector2i(0, 1)


## How wide a storehouse is, in cells (3 to 7). Its depth is always 3.
static func store_width(s: Dictionary) -> int:
	return s.size.x if s.rot % 2 == 0 else s.size.y


## Its chests: one in every cell but the door's column, which is the aisle (issue #318). A 3-wide holds 6.
static func store_chest_cap(s: Dictionary) -> int:
	return 3 * store_width(s) - 3


## Which column of the building, counted along its width from the left in its own frame, is the door's.
static func store_door_col(s: Dictionary) -> int:
	var d := store_door(s)
	var w := store_width(s)
	match s.rot % 4:
		0: return d.x - s.origin.x
		1: return d.y - s.origin.y
		2: return w - 1 - (d.x - s.origin.x)
	return w - 1 - (d.y - s.origin.y)


## The cell in front of a storehouse's door, where residents put things in and take them out. It stays put as
## the building widens, so it's kept on the site once it has (issue #318).
static func store_door(s: Dictionary) -> Vector2i:
	if s.has("door"):
		return s.door
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
			s.chests = mini(store_chest_cap(s), s.get("chests", 0) + s.store.chest)
			s.store.chest = 0
			rev += 1


## A hauler's job carrying a chest into the nearest storehouse with room for one, or null.
func _chest_job(r: Dictionary, c: Vector2i):
	var want := m.sites.filter(func(s): return s.tpl == "storehouse" and s.done and not _cooling(s) and s.get("chests", 0) + s.store.get("chest", 0) + s.incoming.get("chest", 0) < store_chest_cap(s))
	if want.is_empty():
		return null
	var chests := stacks_where(func(st): return st.type == "chest" and avail(st) > 0)
	if chests.is_empty():
		return null
	return _deliver_job(_nearest_site(want, c), "chest", 1, nearest(chests, c))


## The cells of the next column to the left (-1) or the right (+1) of a storehouse, k columns out, in order away from the door's column.
func store_column(s: Dictionary, side: int, k: int) -> Array:
	var ax := store_axis(s)
	var down := Vector2i(ax.y, ax.x)  # across the depth
	var out: Array = []
	var base: Vector2i = s.origin - ax * k if side < 0 else s.origin + ax * (store_width(s) + k - 1)
	for i in 3:
		out.append(base + down * i)
	return out


## Why painted cells can't be built as more room for a storehouse, or "" when they can, with `cols` the whole columns they make
## on each side: {-1: n, 1: n} (issue #318). Only whole columns of three count, from the building's edge outward, and the
## width stops at STORE_WIDTH_MAX.
func store_room_check(s: Dictionary, painted: Dictionary) -> Dictionary:
	var out := {"why": "", "cols": {-1: 0, 1: 0}}
	if m.kind != "village" or s.tpl != "storehouse" or not s.done:
		out.why = "Build the storehouse first"
		return out
	var going := 0
	for x in m.sites:
		if x.tpl == "store_room" and x.get("parent", 0) == s.id:
			going += x.cols
	var left: int = Tuning.STORE_WIDTH_MAX - store_width(s) - going
	if left <= 0:
		out.why = "It's as wide as it gets (%d)" % Tuning.STORE_WIDTH_MAX
		return out
	for side in [-1, 1]:
		if m.sites.any(func(x): return x.tpl == "store_room" and x.get("parent", 0) == s.id and x.side == side):
			continue  # one column going up at a time on a side
		var k := 1
		while out.cols[-1] + out.cols[1] < left:
			var cells := store_column(s, side, k)
			if not cells.all(func(c): return painted.has(c)):
				break
			var why := _room_cell_blocked(s, cells)
			if why != "":
				out.why = why
				break
			out.cols[side] += 1
			k += 1
	if out.cols[-1] + out.cols[1] == 0 and out.why == "":
		out.why = "Paint a whole column of three beside the storehouse"
	return out


func _room_cell_blocked(s: Dictionary, cells: Array) -> String:
	for c in cells:
		if not m.in_bounds(c):
			return "That's past the edge of the village"
		if c == meadow_sign() or c == route_sign():
			return "A signpost is in the way"
		var other = site_at(c)
		if other != null and other.id != s.id:
			return "Another building is in the way"
		var rs = reserved_at(c)
		if rs != null and rs.id != s.id:
			return "Another building has reserved that ground"
	return ""


## Marks cells beside a storehouse to be built as more room: each whole column, up to 7 wide, becomes a blueprint that builders
## raise like any stage (2 cobblestone and 6 planks a column) and that joins the storehouse when it's done (issue #318).
## Returns "" or why nothing was planned.
func paint_store_room(s: Dictionary, rect: Rect2i) -> String:
	if s.map != map_id:
		return on_map(s.map, paint_store_room.bind(s, rect))
	var painted := {}
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			painted[Vector2i(x, y)] = true
	var chk := store_room_check(s, painted)
	if chk.cols[-1] + chk.cols[1] == 0:
		return chk.why
	for side in [-1, 1]:
		var n: int = chk.cols[side]
		if n == 0:
			continue
		var ax := store_axis(s)
		var first := store_column(s, side, 1)
		var last := store_column(s, side, n)
		var lo := Vector2i(mini(first[0].x, last[0].x), mini(first[0].y, last[0].y))
		var size := Vector2i(n, 3) if ax.x == 1 else Vector2i(3, n)
		var r := {"id": _id(), "kind": "site", "tpl": "store_room", "origin": lo, "size": size, "rot": s.rot, "stage": 0, "store": {}, "incoming": {},
			"builder": 0, "crafter": 0, "crafting": "", "done": false, "owner": 0, "queue": [], "autoq": [], "unreach_until": 0, "plot": null,
			"map": map_id, "worker": 0, "parent": s.id, "side": side, "cols": n}
		m.sites.append(r)
		for c in site_cells(r):
			m.zone.erase(c)
			_drop_crop(c)
			_clear_wear(c)
		_mark_obstacles(r)
	_occ_dirty = true
	rev += 1
	return ""


## A column of room is built: the storehouse takes it in and grows (issue #318).
func _merge_store_room(r: Dictionary) -> void:
	var s := site(r.get("parent", 0))
	m.sites.erase(r)
	_occ_dirty = true
	rev += 1
	if s.is_empty():
		return
	var ax := store_axis(s)
	if r.side < 0:
		s.origin -= ax * r.cols
	s.size += Vector2i(ax.x, ax.y) * r.cols
	_toast("The storehouse is %d wide now: room for %d chests." % [store_width(s), store_chest_cap(s)], 0, s.id)


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


## The player has opened a page of the Guide: it's no longer new (issue #348).
func see_page(id: String) -> void:
	var seen: Dictionary = stats.get("guide_seen", {})
	if not seen.has(id) and Goals.pages(self).any(func(p): return p.id == id):
		seen[id] = true
		stats.guide_seen = seen


## Marks a berry bush to be dug up, or unmarks it (issue #344). The claimant stops if it's unmarked.
func designate_bush(b: Dictionary) -> void:
	if not m.bushes.any(func(o): return is_same(o, b)):
		return
	b.des = not b.des
	if not b.des and b.claim != 0:
		var r := resident(b.claim)
		if not r.is_empty() and r.job != null and is_same(r.job.target, b):
			fail_job(r)
	rev += 1


## A resident digs up a marked bush by hand and carries off the berries on it (issue #344).
func _dig_bush_job(r: Dictionary, bush: Dictionary) -> Job:
	var j := Job.new("gather", "Going to dig up a bush", "this bush")
	j.work = "lumber"
	j.target = bush
	bush.claim = r.id
	j.hold({"t": "claim", "ent": bush})
	j.step(_goto([bush.cell], true))
	j.step({"op": "work", "what": "dig_bush", "target": bush, "label": "Digging up a bush"})
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
		if crop.claim != 0 or _cooling(crop) or not walkable(crop.cell) or crop.has("dying"):
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
	elif s.tpl in ["board", "chopping_block", "mason_bench", "toolsmith_bench", "composter", "lodge", "builder_table", "cartographer_table", "portal", "enchanting_workshop", "portal_station", "cache_sensor", "condition", "freight_loader", "dispatcher"]:
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
		"place_torch":  # a torch at a building's door (issue #367)
			var ts: Dictionary = st.site
			var tc := torch_cell(ts)
			if tc.x < 0 or ts.get("torch", false) or r.carry == null or r.carry.type != "torch":
				return "gone"
			m.add_torch(tc)
			ts.torch = true
			r.carry = null
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
		"lead_end":  # the hunter at an end of the meadow's strip (issue #355)
			LeadHome.reached_end(self, r)
			return true
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
			if st.t >= Tuning.HIT_TIME / skill_speed(r, "guard") * st.get("slow", 1.0):
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
			if tick % Tuning.TPS == 0 and _can_pack_more():
				return true  # something to carry has turned up: pack it, then come back
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
					if dark_here(rcell(r)):  # unlit tunnels and the village's unlit night are slow going (issues #110, #367)
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
		"dig_bush":
			var dug: Dictionary = st.target
			if not m.bushes.any(func(o): return is_same(o, dug)):
				return "gone"
			if dug.berries > 0:
				drop_items(dug.cell, "berries", dug.berries)
			m.bushes = m.bushes.filter(func(o): return not is_same(o, dug))
			_occ_dirty = true
			rev += 1
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
	if r.get("trip", "") in ["lead_out", "lead_back"] and r.map == MeadowRoad.ID:  # the hunter walking animals home (issue #355)
		r.job = LeadHome.walk_job(self, r)
		return
	# Starving residents only eat (spec §4); hungry ones eat after any orders you've given them.
	if r.hunger <= 0.0:
		var ej = _eat_job(r)
		if ej != null:
			r.job = ej
		return
	if map_id == "village" and waits_for_home(r):  # an old house: no jobs till it's updated or moved (issue #356)
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
	if m.kind == "village" and not m.creatures.is_empty():
		var dj = Night.defend_job(self, r, c)
		if dj != null:
			r.job = dj
			return
	if in_staging_party(r):  # the party packs, then gathers at the board (issue #107)
		var pj = _pack_job(r, c)
		if pj == null:
			pj = _prep_job(r, c)  # nothing to carry yet: help make what's missing, before waiting at the board
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
	# Nothing to do: after a while, go home and wait there (issue #345). Asked once every ten seconds of an idle spell, so the check is cheap.
	var idle: int = _idle_ticks.get(r.id, 0) + 1
	_idle_ticks[r.id] = idle
	var after := int(Tuning.IDLE_HOME_AFTER * Tuning.TPS)
	if idle >= after and (idle - after) % (10 * Tuning.TPS) == 0:
		r.job = _torch_job(r)  # a torch that's due comes before going home
		if r.job == null:
			r.job = _home_job(r)


## Whether work at `c` is slowed by the dark: an unlit tunnel, or the village by night with no torch near (issue #367).
func dark_here(c: Vector2i) -> bool:
	if m.kind == "village":
		return Night.enabled and Night.is_night(self) and not m.is_lit(c)  # tests and bots that switch the night off keep their day's pace
	return m.is_dark(c)


## The cell a building's torch stands on, its front door step, or (-1, -1) for a building with none (issue #367). Only a house with an
## entrance has one for now; an old building gets nothing.
func torch_cell(s: Dictionary) -> Vector2i:
	if s.tpl == "house" and s.done and not s.get("old", false):
		return front_cell(s.origin, s.rot)
	return Vector2i(-1, -1)


## An idle resident takes a torch from the stockpile to the first building that has none, setting it down at its door (issue #367).
func _torch_job(r: Dictionary):
	if map_id != "village" or free_count("torch") <= 0:
		return null
	var need = null
	for s in m.sites:
		if torch_cell(s).x >= 0 and not s.get("torch", false):
			need = s
			break
	if need == null:
		return null
	var stacks := stacks_where(func(x): return x.type == "torch" and avail(x) > 0)
	if stacks.is_empty():
		return null
	var stack: Dictionary = nearest(stacks, rcell(r))
	var j := Job.new("haul", "Going to set down a torch", "a torch")
	stack.res += 1
	var hd := j.hold({"t": "stack", "stack": stack, "n": 1})
	j.step(_goto(reach(stack.cell), false))
	j.step({"op": "pickup_lighter", "stack": stack, "hold": hd})
	j.step(_goto([torch_cell(need)], false))
	j.step({"op": "place_torch", "site": need})
	return j


## A walk to the resident's own house, or null when they have none, are away from the village or are already by it (issue #345).
func _home_job(r: Dictionary):
	if map_id != "village" or r.away or r.get("hurt", 0) > 0 or Goals.current(self) >= 0:  # the founding is the guided opening: nobody goes home till it's done
		return null
	for s in m.sites:
		if s.tpl == "house" and s.done and s.owner == r.id:
			var near := 1 << 30
			for hc in site_cells(s):
				near = mini(near, manhattan(rcell(r), hc))
			if near <= Tuning.HOME_NEAR:
				return null
			var j := Job.new("home", "Heading home", "their house")
			j.step(home_goal(s))
			return j
	return null


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
				for b in m.bushes:  # a bush marked to be dug up (issue #344): by hand, no axe needed
					if b.des and b.claim == 0:
						targets.append(b)
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
				if t.kind == "bush":
					return _dig_bush_job(r, t)
				return _tagged(_hunt_job(r, t), "hunt") if t.kind == "animal" else _gather_job(r, t)
			var rj = _road_claim(r, "gather", jobs)
			if rj != null:
				return rj
			if r.role != "all":  # a gatherer's own work at their workstation; never Ada's (issue #177)
				var wj = _workstation_job(r, c)
				if wj != null:
					return wj
			if r.role == "hunt" and m.kind == "village":  # the lodge's hunter feeds the village pens' pairs (issue #355)
				var fj = _village_feed_job(r, c)
				if fj != null:
					return _tagged(fj, "hunt")
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
	_scans_fresh()
	if _scans.get("haul_none", false):  # nothing could be carried anywhere a moment ago, and nothing has changed
		return null
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
	var bare: bool = m.zone.is_empty() and piles.is_empty() and not m.sites.any(func(s): return s.tpl == "storehouse" and s.done and s.get("chests", 0) > 0)  # a storehouse with no chest keeps nothing yet (issue #318)
	if not anywhere and (not bare or clearing.is_empty() or not loose.any(func(s): return clearing.has(s.cell))):
		_scans["haul_none"] = true
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
	return m.zone.is_empty() and pile_map().is_empty() and not m.sites.any(func(s): return s.tpl == "storehouse" and s.done and s.get("chests", 0) > 0)  # a storehouse with no chest keeps nothing yet (issue #318)


## The nearest open cell to `c` outside every footprint being cleared, for a stack that has no storage
## to go to yet (issue #205), or null.
func _clear_spot(c: Vector2i, clearing: Dictionary):
	for d in range(1, 9):
		for dx in range(-d, d + 1):
			for dy in range(-d, d + 1):
				if maxi(absi(dx), absi(dy)) != d:
					continue
				var p := c + Vector2i(dx, dy)
				if walkable(p) and not clearing.has(p) and not m.farm.has(p) and not m.items.has(p) and not m.zone_res.has(p) and reserved_at(p) == null:
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
		if not stats.get("founding_done", false) and Goals.first_open(self) < 0:
			stats.founding_done = true  # once the founding is done it stays done (issue #318)
	use_map(prev)
	var kinds := {}
	var working := 0
	for r in residents:
		if r.job != null and not (r.job.kind in ["move", "arrive", "stage", "road", "rest", "hurt", "commute", "unload", "home"]):
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
	if m.kind == "village" and tick % Tuning.TPS == 0:
		_step_plots()
	for k in m.farm:
		var crop: Dictionary = m.farm[k]
		if crop.grow >= 0.0 and crop.grow < Tuning.WHEAT_GROW and not crop.has("dying"):
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
	if m.kind == "village":
		LeadHome.step(self)  # the lodge's hunter fetching marked animals from the meadow (issue #355)
		Night.step(self)  # dusk and dawn, the golem and the night's mobs (issues #357-#359)
	if not m.creatures.is_empty():
		_step_creatures()
	for r in residents:
		if r.map != map_id:
			continue
		use_slot(slot_of(r))
		if r.away:
			if tick >= r.back_at:
				if r.trip == "survey":  # the Cartographer's survey (issue #321)
					Survey.arrive(self, r)
				elif r.trip == "lead_home":  # the hunter leading animals home (issue #355)
					LeadHome.arrive(self, r)
				elif r.trip == "village":
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


var _old_owners := {}  ## Resident id -> true for those whose own house is an old one (issue #356); worked out per `rev`, not saved.
var _old_owner_rev := -1
var _idle_ticks := {}  ## Resident id -> ticks they've gone without work (issue #345); not saved.


func _step_resident(r: Dictionary) -> void:
	if r.get("burn", 0.0) > 0.0:
		_burn_step(r)
	if r.hunger <= 0.0 and r.job != null and r.job.kind != "eat":
		fail_job(r)  # starving: drop everything and go eat
	if r.job != null and m.kind == "village" and not m.creatures.is_empty() and not r.job.kind in ["fight", "eat", "rest", "hurt"]:
		var dj = Night.defend_job(self, r, rcell(r))  # a mob near them turns them from their work (issue #360)
		if dj != null:
			fail_job(r)
			r.job = dj
	if r.job != null and r.job.kind == "home":  # work that turns up takes them from the walk home at once (issue #345)
		var walk: Job = r.job
		r.job = null
		_claim(r)
		if r.job == null:
			r.job = walk
		else:
			_idle_ticks.erase(r.id)
	if r.job == null:
		if r.arriving:
			return
		_claim(r)
		if r.job == null:
			return
		if r.job.kind != "home":
			_idle_ticks.erase(r.id)
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

# The rules live in missions.gd (#305); these forward to them.


const OBJECTIVES = Missions.OBJECTIVES


func objective_destinations(obj: String) -> Array:
	return Missions.objective_destinations(self, obj)


func objective_why_none(obj: String) -> String:
	return Missions.objective_why_none(self, obj)


func nether_plan(obj: String, pick := {}) -> Dictionary:
	return Missions.nether_plan(self, obj, pick)


func plan_briefing(plan: Dictionary) -> Array:
	return Missions.plan_briefing(self, plan)


func trading() -> bool:
	return Missions.trading(self)


func scouting() -> bool:
	return Missions.scouting(self)


func scout_plan(route: String) -> Dictionary:
	return Missions.scout_plan(self, route)


func surveying() -> bool:
	return Missions.surveying(self)


# The rules live in pens.gd (#305); these forward to them.

func pen_surplus() -> Array:
	return Pens.pen_surplus(self)


func pen_work() -> bool:
	return Pens.pen_work(self)


func designate_lead(rect: Rect2i, single = null) -> void:
	Pens.designate_lead(self, rect, single)


func _fence_job(r: Dictionary, c: Vector2i):
	return Pens._fence_job(self, r, c)


func _put_fence(p: Dictionary, c: Vector2i) -> void:
	Pens._put_fence(self, p, c)


func _lead_job(r: Dictionary, c: Vector2i):
	return Pens._lead_job(self, r, c)


func _feed_job(r: Dictionary, c: Vector2i):
	return Pens._feed_job(self, r, c)


func _village_feed_job(r: Dictionary, c: Vector2i):
	return Pens._village_feed_job(self, r, c)


func _step_pens() -> void:
	Pens._step_pens(self)


func _breed(p: Dictionary, a: Dictionary, b: Dictionary) -> void:
	Pens._breed(self, p, a, b)


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
# The rules live in stuck.gd (#305); these forward to them.

func _add_stuck(who: String, why: String, at: Vector2, height: float, fk: String, fid: int, hidden := false, waiting := false, decision := "") -> void:
	Stuck._add_stuck(self, who, why, at, height, fk, fid, hidden, waiting, decision)


func compute_stuck() -> void:
	Stuck.compute_stuck(self)


func _stuck_on_map() -> void:
	Stuck._stuck_on_map(self)


func _stuck_unstaffed() -> void:
	Stuck._stuck_unstaffed(self)


func _stuck_farm() -> void:
	Stuck._stuck_farm(self)


func _stuck_workstations() -> void:
	Stuck._stuck_workstations(self)


func _staffed(jb: String) -> bool:
	return Stuck._staffed(self, jb)


func _work_at(jb: String):
	return Stuck._work_at(self, jb)


func site_height(s: Dictionary) -> float:
	return Stuck.site_height(self, s)


# ---------------------------------------------------------------- commands

## Sends the Cartographer to survey a sector's ring (issue #321). Returns whether they went.
func start_survey(sector: String, ring: int) -> bool:
	return Survey.start(self, sector, ring)



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


# ---------------------------------------------------------------- a composter's plots (issue #319)

# The rules live in farm_plots.gd (#305); these forward to them.

static func composter_reaches(s: Dictionary, c: Vector2i) -> bool:
	return FarmPlots.composter_reaches(s, c)


func composters() -> Array:
	return FarmPlots.composters(self)


func composter_plots(s: Dictionary) -> Array:
	return FarmPlots.composter_plots(self, s)


static func plot_dying(crop: Dictionary) -> float:
	return FarmPlots.plot_dying(crop)


func paint_plots(s: Dictionary, rect: Rect2i, erase := false) -> int:
	return FarmPlots.paint_plots(self, s, rect, erase)


func _start_plots(s: Dictionary) -> void:
	FarmPlots._start_plots(self, s)


func _step_plots() -> void:
	FarmPlots._step_plots(self)


func clear_farm(rect: Rect2i) -> void:
	FarmPlots.clear_farm(self, rect)


func _drop_crop(c: Vector2i) -> void:
	FarmPlots._drop_crop(self, c)

	m.farm.erase(c)


# The rules live in site_commands.gd (#305); these forward to them.

func placement_check(tpl: String, origin: Vector2i, rot := 0, ignore := 0) -> String:  # `ignore`: the site being moved, which isn't in its own way
	return SiteCommands.placement_check(self, tpl, origin, rot, ignore)


## Buildings that can't move: the portal and the three that stand by it (issues #168, #172, #173) are placed
## relative to each other, so one can't be lifted without the rest.
const UNMOVABLE := ["portal", "portal_station", "dispatcher", "freight_loader"]


func move_check(s: Dictionary, origin: Vector2i, rot := 0) -> String:
	return SiteCommands.move_check(self, s, origin, rot)


func move_site(s: Dictionary, origin: Vector2i, rot := 0) -> String:
	return SiteCommands.move_site(self, s, origin, rot)


func house_update_in_place(s: Dictionary) -> bool:
	return SiteCommands.house_update_in_place(self, s)


func update_house(s: Dictionary) -> String:
	return SiteCommands.update_house(self, s)


func place_site(tpl: String, origin: Vector2i, rot := 0) -> Dictionary:
	return SiteCommands.place_site(self, tpl, origin, rot)


func set_role(r: Dictionary, role: String) -> void:
	SiteCommands.set_role(self, r, role)


func set_keep_meals(f: Dictionary, on: bool) -> void:
	SiteCommands.set_keep_meals(self, f, on)


func cancel_site(s: Dictionary) -> void:
	SiteCommands.cancel_site(self, s)



# The rules live in orders.gd (#305); these forward to them.

func direct_order(r: Dictionary, target = null, cell = null) -> void:
	Orders.direct_order(self, r, target, cell)


func queue_order(r: Dictionary, target = null, cell = null) -> void:
	Orders.queue_order(self, r, target, cell)


func equip_order(r: Dictionary, stack: Dictionary) -> void:
	Orders.equip_order(self, r, stack)


func release_kept_tool(r: Dictionary, kind: String) -> void:
	Orders.release_kept_tool(self, r, kind)


func clear_orders(r: Dictionary) -> void:
	Orders.clear_orders(self, r)


static func order_text(o: Dictionary) -> String:
	return Orders.order_text(o)


func _order_job(r: Dictionary, o: Dictionary):
	return Orders._order_job(self, r, o)



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

# The rules live in packing.gd (#305); these forward to them.

static func cargo_rows(plan: Dictionary) -> Array:
	return Packing.cargo_rows(plan)


static func sync_target(plan: Dictionary) -> void:
	Packing.sync_target(plan)


func repeat_plan(dest: String) -> Dictionary:
	return Packing.repeat_plan(self, dest)


func aim_plan(plan: Dictionary, item: String, n: int) -> void:
	Packing.aim_plan(self, plan, item, n)


func cargo_list_for(dest: String) -> Array:
	return Packing.cargo_list_for(self, dest)


static func cargo_rank(plan: Dictionary, item: String) -> int:
	return Packing.cargo_rank(plan, item)


func cargo_have(item: String) -> int:
	return Packing.cargo_have(self, item)


func row_left(row: Dictionary) -> int:
	return Packing.row_left(self, row)


func objective_met() -> bool:
	return Packing.objective_met(self)


func objective_left() -> int:
	return Packing.objective_left(self)


func _reserve_above(item: String) -> int:
	return Packing._reserve_above(self, item)


func gives_wanted(b: Dictionary) -> bool:
	return Packing.gives_wanted(self, b)


func can_mine_diamond() -> bool:
	return Packing.can_mine_diamond(self)


func can_mine_ore(ore: String) -> bool:
	return Packing.can_mine_ore(self, ore)


func can_mine_item(item: String) -> bool:
	return Packing.can_mine_item(self, item)


static func pick_need_text(ore: String) -> String:
	return Packing.pick_need_text(ore)


static func list_text(plan: Dictionary) -> String:
	return Packing.list_text(plan)


func objective_text() -> String:
	return Packing.objective_text(self)


func swap_candidate() -> Dictionary:
	return Packing.swap_candidate(self)


static func pack_capacity(plan: Dictionary) -> int:
	return Packing.pack_capacity(plan)


static func plan_supplies(plan: Dictionary) -> int:
	return Packing.plan_supplies(plan)


static func cargo_room(plan: Dictionary) -> int:
	return Packing.cargo_room(plan)


static func return_meals(plan: Dictionary) -> int:
	return Packing.return_meals(plan)


static func site_minutes(plan: Dictionary) -> float:
	return Packing.site_minutes(plan)


func plan_targets(dest: String) -> Array:
	return Packing.plan_targets(self, dest)


func plan_problems(plan: Dictionary) -> Array:
	return Packing.plan_problems(self, plan)


func plan_expedition(plan: Dictionary) -> String:
	return Packing.plan_expedition(self, plan)


func packed(incoming := false) -> Dictionary:
	return Packing.packed(self, incoming)


func pack_needs() -> Dictionary:
	return Packing.pack_needs(self)


const SUPPLY_KINDS = Packing.SUPPLY_KINDS


func _pack_job(r: Dictionary, c: Vector2i):
	return Packing._pack_job(self, r, c)


const PREP_JOBS = Packing.PREP_JOBS


func _prep_job(r: Dictionary, c: Vector2i):
	return Packing._prep_job(self, r, c)


func _can_pack_more() -> bool:
	return Packing._can_pack_more(self)


func _stage_job() -> Job:
	return Packing._stage_job(self)


func at_board(r: Dictionary) -> bool:
	return Packing.at_board(self, r)


func depart_blocker(slot_id := "") -> String:
	return Packing.depart_blocker(self, slot_id)


func depart(slot_id := "") -> String:
	return Packing.depart(self, slot_id)


static func names_text(names: Array) -> String:
	return Packing.names_text(names)


func _cross_portal(r: Dictionary, to: String) -> void:
	Packing._cross_portal(self, r, to)


func _arrive_at_site(r: Dictionary) -> void:
	Packing._arrive_at_site(self, r)


func _enter_level(r: Dictionary, id: String) -> void:
	Packing._enter_level(self, r, id)


func cancel_expedition(slot_id := "") -> void:
	Packing.cancel_expedition(self, slot_id)


func _stuck_expedition() -> void:
	Packing._stuck_expedition(self)



# ---------------------------------------------------------------- travel and the return (issues #108, #112)

# The rules live in travel.gd (#305); these forward to them.

func route_sign() -> Vector2i:
	return Travel.route_sign(self)


func trip_time(to: String) -> float:
	return Travel.trip_time(self, to)


func on_the_way(r: Dictionary) -> bool:
	return Travel.on_the_way(self, r)


func carrying_packs(r: Dictionary) -> bool:
	return Travel.carrying_packs(self, r)


func _road_job() -> Job:
	return Travel._road_job(self)


func call_home_blocker(slot_id := "") -> String:
	return Travel.call_home_blocker(self, slot_id)


func call_home(slot_id := "") -> String:
	return Travel.call_home(self, slot_id)


func _arrive_home(r: Dictionary) -> void:
	Travel._arrive_home(self, r)


func _start_unloading() -> void:
	Travel._start_unloading(self)


func _step_unload() -> void:
	Travel._step_unload(self)


func _drop_cargo(spot: Vector2i, type: String, n: int, dur := -1) -> void:
	Travel._drop_cargo(self, spot, type, n, dur)


func _finish_return() -> void:
	Travel._finish_return(self)


func expedition_report(ex: Dictionary) -> Array:
	return Travel.expedition_report(self, ex)


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

# The rules live in site_maps.gd (#305); these forward to them.

static func block_name(b: Dictionary) -> String:
	return SiteMaps.block_name(b)


func ore_left(id: String, ore: String) -> int:
	return SiteMaps.ore_left(self, id, ore)


func site_report(id: String) -> Dictionary:
	return SiteMaps.site_report(self, id)


func _meadow_report() -> Dictionary:
	return SiteMaps._meadow_report(self)


func _nether_route_report(id: String) -> Dictionary:
	return SiteMaps._nether_route_report(self, id)


func _nether_site_report(id: String) -> Dictionary:
	return SiteMaps._nether_site_report(self, id)


static func rk_of_site(id: String) -> String:
	return SiteMaps.rk_of_site(id)


static func rk_access(rk: String) -> String:
	return SiteMaps.rk_access(rk)


func _landing_report() -> Dictionary:
	return SiteMaps._landing_report(self)


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
	var order := ["village", OldMine.ID, Road.ID, Meadow.ID, MeadowRoad.ID] + Structures.IDS + [NetherLanding.ID] + NetherRoute.map_ids()
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
	if not s.stats.has("found"):  # a village from before surveys has found everything it has (issue #321)
		s.stats.found = {"old_mine": true, "ruined_portal": true}
	if not s.stats.has("founding_done") and Goals.legacy_done(s):  # a village from before the composter and storehouse goals (issue #318)
		s.stats.founding_done = true
	if not s.stats.has("day_zero"):  # an older save has no day: it starts on a morning when it loads (issue #357)
		s.stats.day_zero = s.tick - int(Tuning.DUSK_SECONDS * Tuning.TPS)
	if not s.stats.has("guide_seen"):  # an older save: every page it already knows counts as seen (issue #348)
		Goals.seed_seen(s)
	s.compute_stuck()
	return s
