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
var meadow_sheep := Tuning.MEADOW_SHEEP  ## Sheep left in the meadow off the map (issue #50).
var meadow_regrow := 0.0     ## Seconds toward the meadow's next sheep.
var rng := RandomNumberGenerator.new()  ## Seeded and saved, so a game replays exactly.
var residents: Array = []    ## Everyone, on every map; each has the `map` they're on.
var stats := {"felled": 0, "broken_boulders": 0, "tools_broken": 0, "pick_crafted": false,
	"houses": 0, "traveler_home": false, "division": false}
var arrival_at := -1
var arrived := false
var auto_craft := false      ## Unlocked when the first house is finished.
## The planned expedition (issues #106, #107), or {} when there's none. One at a time (#25):
##   {dest, board (site id), party: [resident ids], target: {item, n}, meals, picks,
##    policy: {target, full, low}, spend_return, state: "staging" or "out", packed: {item: n}, tools: [{type, dur}],
##    leg: "out" or "home", provisions: {meal: n}, cargo: {item: n}, broken: n, hurt: {name: level},
##    survey: bool, home_why}
## `packed` is what was packed at the board, kept for the report. Once out, the packs hold `provisions`
## (meals left), `tools` (spare pickaxes left) and `cargo` (what's been mined), sharing PACK_CAPACITY
## each (issue #109). `leg` is which way the party is going (#108).
var expedition := {}
## Choices waiting for the player, oldest first (issues #110, #111): {kind, text, options, res_id, map}.
## The game pauses while there's one.
var pending: Array = []
## The line's one minecart once it's parked at a station (issue #123), or {}:
##   {at: "village" or "mine", x (along the line), state: "parked", "loading", "moving" or "unloading",
##    load: {item: n} (cargo in it), riders: [resident ids], acc (items toward the next one loaded)}
var cart := {}
var stuck: Array = []        ## {who, why, map, cell (Vector2), height, focus_kind, focus_id, hidden, waiting, since}
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


## Residents on the current map, not counting anyone away on a meadow trip.
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
## Six sheep around the opening (issue #42): wool for the two opening beds. Open ground, in map cells.
const START_SHEEP := [[21, 8], [12, 24], [24, 19], [8, 12], [22, 24], [20, 20]]
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
	s._add_site_maps()
	return s


## Adds any site map the sim doesn't have yet: a new game's, or one newer than a loaded save.
func _add_site_maps() -> void:
	if not maps.has(OldMine.ID):
		maps[OldMine.ID] = OldMine.build(self)
	if not maps.has(Road.ID):  # the road becomes known with the mine (issue #118)
		maps[Road.ID] = Road.build(self)
		road().known = maps[OldMine.ID].known


func add_bush(cell: Vector2i) -> Dictionary:
	var b := {"id": _id(), "kind": "bush", "cell": cell, "berries": Tuning.BUSH_MAX, "regrow": 0.0}
	m.bushes.append(b)
	return b


func add_sheep(cell: Vector2i) -> Dictionary:
	var sh := {"id": _id(), "kind": "sheep", "pos": Vector2(cell), "cell": cell, "dest": null, "wait": rng.randf_range(Tuning.SHEEP_PAUSE[0], Tuning.SHEEP_PAUSE[1]),
		"alive": true, "des": false, "claim": 0, "unreach_until": 0}
	m.sheep.append(sh)
	return sh


func _id() -> int:
	next_id += 1
	return next_id - 1


func add_resident(rname: String, shirt: String, cell: Vector2i) -> Dictionary:
	var r := {"id": _id(), "kind": "res", "name": rname, "shirt": shirt, "pos": Vector2(cell),
		"path": [], "job": null, "direct": null, "carry": null, "axe": null, "pick": null,
		"broken": {"axe": false, "pick": false}, "progress": -1.0, "note": null, "arriving": false,
		"orders": [], "hunger": 100.0, "jobs": default_jobs(), "kept": {"axe": false, "pick": false},
		"away": false, "back_at": 0, "trip": "", "map": map_id, "hurt": 0, "heal": 0.0}
	residents.append(r)
	return r


## Every job on at priority 2, except Toolsmith (spec §5, issue #91): the player employs a toolsmith
## by switching it on, since a toolsmith spends materials on spare tools unasked.
static func default_jobs() -> Dictionary:
	var out := {}
	for jb in Defs.JOBS:
		out[jb] = {"on": jb != "toolsmith", "pri": 2, "xp": 0}
	return out


## Which job a recipe's work belongs to: the fireplace's is Cook, the bench's tools are Toolsmith,
## and the rest (planks, sticks) is Craft.
static func recipe_job(rec: Dictionary) -> String:
	if rec.get("at", "bench") == "fireplace":
		return "cook"
	for o in rec.out:
		if Defs.is_tool_item(o):
			return "toolsmith"
	return "craft"


## A resident's level in a job, 1 to 5, from their experience (spec §5).
static func level(r: Dictionary, job: String) -> int:
	var xp: int = r.jobs[job].get("xp", 0)
	var lv := 1
	for need in Tuning.SKILL_LEVELS:
		if xp >= need:
			lv += 1
	return lv


## Progress from the current level to the next, 0..1 (1 at the top level).
static func level_progress(r: Dictionary, job: String) -> float:
	var lv := level(r, job)
	if lv > Tuning.SKILL_LEVELS.size():
		return 1.0
	var lo: int = 0 if lv == 1 else Tuning.SKILL_LEVELS[lv - 2]
	var hi: int = Tuning.SKILL_LEVELS[lv - 1]
	return float(r.jobs[job].get("xp", 0) - lo) / float(hi - lo)


## One finished task's worth of experience. Says so when it brings a new level.
func gain_xp(r: Dictionary, job: String) -> void:
	var before := level(r, job)
	r.jobs[job].xp = r.jobs[job].get("xp", 0) + 1
	var after := level(r, job)
	if after > before:
		_toast("%s is now level %d at %s." % [r.name, after, Defs.JOB_NAMES[job]], r.id)
		rev += 1


## How much faster a resident works at a job: 15% per level above 1.
static func skill_speed(r: Dictionary, job: String) -> float:
	return 1.0 + Tuning.SKILL_SPEED * (level(r, job) - 1)


## +1 at level 3 and +1 more at level 5: extra logs, cobblestone, wheat, and carry capacity.
static func skill_bonus(r: Dictionary, job: String) -> int:
	var lv := level(r, job)
	return (1 if lv >= 3 else 0) + (1 if lv >= 5 else 0)


## Items one trip can carry, with the Haul skill's bonus.
static func carry_cap(r: Dictionary) -> int:
	return Tuning.CARRY + skill_bonus(r, "haul")


## A recipe's inputs and outputs as this resident makes it: a level-4 cook bakes bread from 2
## wheat, and a level-4 crafter gets 5 planks from a log.
static func recipe_for(r: Dictionary, rec: Dictionary) -> Dictionary:
	var out := rec.duplicate(true)
	if r.is_empty():
		return out
	if rec.id == "bread" and level(r, "cook") >= 4:
		out.inp.wheat = 2
	if rec.id == "planks" and level(r, "craft") >= 4:
		out.out.plank = 5
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
		var d := manhattan(o.cell, c)
		if d < bd:
			bd = d
			best = o
	return best


# ---------------------------------------------------------------- items

## Uses a new tool of this type has.
static func full_uses(type: String) -> int:
	return Tuning.DURABILITY[Defs.ITEMS[type].tier]


## Places items on or near `c`, filling the cell and spreading outward over walkable cells.
## A tool keeps `uses` (its remaining uses); -1 means a new tool.
func drop_items(c: Vector2i, type: String, n: int, uses := -1) -> void:
	if _occ_dirty:
		_recompute_occ()
	var cap := Defs.stack_cap(type)
	var seen := {c: true}
	var queue: Array = [c]
	var qi := 0
	while n > 0 and qi < queue.size() and qi < 400:
		var cur: Vector2i = queue[qi]
		qi += 1
		if walkable(cur):
			var s = m.items.get(cur)
			if s == null:
				var put := mini(n, cap)
				m.items[cur] = {"cell": cur, "type": type, "n": put, "res": 0}
				if Defs.is_tool_item(type):
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
	return Defs.TEMPLATES[s.tpl].stages[s.stage]


func door_cell(origin: Vector2i, rot: int) -> Vector2i:
	match rot % 4:
		0: return origin + Vector2i(2, 4)
		1: return origin + Vector2i(4, 2)
		2: return origin + Vector2i(2, 0)
		_: return origin + Vector2i(0, 2)


func obstacles_in(rect: Rect2i) -> Dictionary:
	var out := {"trees": [], "boulders": []}
	for t in m.trees:
		if t.alive and rect.has_point(t.cell):
			out.trees.append(t)
	for b in m.boulders:
		if b.alive and rect.has_point(b.cell):
			out.boulders.append(b)
	return out


func site_obstacles(s: Dictionary) -> Dictionary:
	return obstacles_in(Rect2i(s.origin, s.size))


func footprint_clear(s: Dictionary) -> bool:
	var o := site_obstacles(s)
	return o.trees.is_empty() and o.boulders.is_empty()


static func clearing_text(o: Dictionary) -> String:
	var parts: PackedStringArray = []
	var t: int = o.trees.size()
	var b: int = o.boulders.size()
	if t:
		parts.append("%d %s" % [t, "tree" if t == 1 else "trees"])
	if b:
		parts.append("%d %s" % [b, "boulder" if b == 1 else "boulders"])
	return " and ".join(parts)


func _mark_obstacles(s: Dictionary) -> void:
	var o := site_obstacles(s)
	for t in o.trees + o.boulders:
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
	var exit: Vector2i = s.origin + Vector2i(s.size.x / 2, s.size.y)
	for c in site_cells(s):
		m.zone.erase(c)
		if m.items.has(c):
			var it: Dictionary = m.items[c]
			m.items.erase(c)
			drop_items(exit, it.type, it.n, it.get("dur", -1))
	m.bushes = m.bushes.filter(func(b): return not Rect2i(s.origin, s.size).has_point(b.cell))
	for r in residents + sheep:
		var c := rcell(r)
		if Rect2i(s.origin, s.size).has_point(c):
			var p = nearest_walkable(c)
			if p != null:
				r.pos = Vector2(p)
				if r.kind == "sheep":
					r.cell = p
					r.dest = null
				else:
					r.path = []


func _on_site_done(s: Dictionary) -> void:
	if s.tpl == "bench":
		_toast("The crafting bench is ready. Select it to queue crafts.", 0, s.id)
		return
	if s.tpl == "fireplace":
		_toast("The fireplace is lit. It keeps %d meals in stock when there's wheat or mutton." % Tuning.MEAL_STOCK, 0, s.id)
		return
	if s.tpl == "bridge":
		_toast("The bridge over the stream is built: no more wading, and track can cross.", 0, s.id)
		return
	if s.tpl == "station":
		_toast("The station at the %s end of the line is built." % s.end, 0, s.id)
		return
	if s.tpl == "track":
		if line_complete():
			_toast("The line to the mine is complete.", 0, s.id)
		else:
			_toast("Track is laid along %s." % Road.SEGMENTS[s.seg].name.to_lower(), 0, s.id)
		return
	if s.tpl == "board":  # it has word of the old mine, which the map switcher now shows (issue #105)
		maps[OldMine.ID].known = true
		road().known = true
		_toast("The expedition board is up, with word of an old mine to the east. Select it to plan an expedition.", 0, s.id)
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
		if not auto_craft:
			auto_craft = true
			_toast("The bench now makes the planks and sticks a recipe needs.")
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


## Whether anyone has the Toolsmith job switched on.
func has_toolsmith() -> bool:
	return residents.any(func(r): return r.jobs.toolsmith.on)


## Whether a "(toolsmith)" entry for this tool kind is queued at any bench.
func _spare_queued(kind: String) -> bool:
	for b in m.sites:
		if b.done and b.tpl == "bench":
			for i in b.queue.size():
				if str(b.autoq[i]) == "toolsmith" and Defs.ITEMS[Defs.recipe(b.queue[i]).out.keys()[0]].tool == kind:
					return true
	return false


## The toolsmith's standing order (spec §6): while anyone has Toolsmith on, keep one spare of each
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
	for kind in ["axe", "pick"]:
		var used := residents.any(func(r): return r[kind] != null or r.broken[kind])
		if not used or not tool_items(kind, 0).is_empty() or _spare_queued(kind):
			continue
		var id: String = "wood_" + kind
		for tier in ["iron_", "stone_"]:  # the best tier there's material for (issue #104)
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
	var meals := 0
	for meal in Defs.MEALS:
		meals += free_count(meal)
	for f in m.sites:
		if not (f.done and f.tpl == "fireplace" and f.get("keep_meals", true)):
			continue
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


# ---------------------------------------------------------------- jobs

func _goto(cells: Array, adjacent: bool) -> Dictionary:
	return {"op": "goto", "cells": cells, "adj": adjacent, "planned": false}


func _gather_job(r: Dictionary, target: Dictionary) -> Job:
	var is_tree: bool = target.kind == "tree"
	var kind := "axe" if is_tree else "pick"
	var j := Job.new("gather", "Going to chop a tree" if is_tree else "Going to break a boulder",
		"this tree" if is_tree else "this boulder")
	j.work = "mine"
	j.target = target
	target.claim = r.id
	j.hold({"t": "claim", "ent": target})
	var cur: int = r[kind].tier if r[kind] != null else 0
	var better := tool_items(kind, cur)
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
		if s.type == "mutton":  # raw mutton is for the fireplace; eaten only in a pinch
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
	if at_site(r) or on_road(r):
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
	j.step(_goto([stack.cell], false))
	j.step({"op": "pickup", "stack": stack, "n": 1, "hold": hd})
	j.step({"op": "work", "what": "eat", "label": "Eating %s" % Defs.ITEMS[stack.type].one})
	return j


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
	var j := Job.new("gather", "Going to hunt a sheep", "this sheep")
	j.work = "hunt"
	j.target = target
	target.claim = r.id
	j.hold({"t": "claim", "ent": target})
	j.step({"op": "chase", "target": target, "planned_for": null})
	j.step({"op": "work", "what": "hunt", "target": target, "label": "Hunting a sheep"})
	return j


func _fetch_tool(j: Job, stack: Dictionary) -> void:
	stack.res += 1
	var hd := j.hold({"t": "stack", "stack": stack, "n": 1})
	j.step(_goto([stack.cell], false))
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
	j.step(_goto([stack.cell], false))
	j.step({"op": "pickup", "stack": stack, "n": n, "hold": sh})
	j.step(_goto(site_cells(dest), true))
	j.step({"op": "deposit", "site": dest, "type": type, "n": n, "hold": ih})
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
	elif s.tpl == "board":
		label = "Building the expedition board"
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


func _haul_job(r: Dictionary, stack: Dictionary, dest: Vector2i, n: int) -> Job:
	var j := Job.new("haul", "Hauling %s to the stockpile" % Defs.ITEMS[stack.type].many, "the stockpile")
	stack.res += n
	m.zone_res[dest] = r.id
	var sh := j.hold({"t": "stack", "stack": stack, "n": n})
	var zh := j.hold({"t": "zone", "cell": dest})
	j.step(_goto([stack.cell], false))
	j.step({"op": "pickup", "stack": stack, "n": n, "hold": sh})
	j.step(_goto([dest], false))
	j.step({"op": "haul_drop", "cell": dest, "type": stack.type, "n": n, "hold": zh})
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
		r.note = {"text": "Needs a pickaxe", "until": tick + 4 * Tuning.TPS}


func _wear(r: Dictionary, kind: String) -> void:
	var t = r[kind]
	if t == null:
		return
	t.dur -= 1
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
			drop_items(st.cell, st.type, st.n, r.carry.get("dur", -1))
			r.carry = null
			return true
		"depart":  # off the edge of the map: to the meadow (issue #50), or onto the road map (#118)
			var to: String = st.get("to", "meadow")
			if to != "meadow":
				_onto_road(r, to)
				return true
			r.away = true
			r.trip = to
			r.back_at = tick + int(trip_time(to) * Tuning.TPS)
			r.path = []
			r.progress = -1.0
			rev += 1
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
			var over: int = r.carry.n - maxi(0, pack_room())
			if over > 0:  # the packs filled up on the way: the rest is set down here
				drop_items(rcell(r), r.carry.type, over, r.carry.get("dur", -1))
				r.carry.n -= over
				if r.carry.n <= 0:
					r.carry = null
					return true
			if Defs.MEALS.has(r.carry.type):
				expedition.provisions[r.carry.type] = expedition.provisions.get(r.carry.type, 0) + r.carry.n
			elif r.carry.has("dur"):
				expedition.tools.append({"type": r.carry.type, "dur": r.carry.dur})
			else:
				expedition.cargo[r.carry.type] = expedition.cargo.get(r.carry.type, 0) + r.carry.n
			r.carry = null
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
			if not st.bed and tick % Tuning.TPS == 0 and _has_bed(r):
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
				return Tuning.CHOP_TIME[tier]
			return Tuning.BREAK_TIME[tier] if tier > 0 else -1.0
		"build":
			return Tuning.LAY_TIME if st.site.tpl == "track" else Tuning.STAGE_TIME
		"hunt":
			return Tuning.HUNT_TIME
		"plant":
			return Tuning.PLANT_TIME
		"harvest":
			return Tuning.HARVEST_TIME
		"eat", "graze":
			return Tuning.EAT_TIME
		"survey":
			return Tuning.SURVEY_TIME
		_:
			match st.get("recipe", {}).get("id", ""):
				"bread": return Tuning.BAKE_TIME
				"cooked_mutton": return Tuning.COOK_TIME
				"smelt_iron": return Tuning.SMELT_TIME
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
				drop_items(t.cell, "log", t.logs + skill_bonus(r, "mine"))
				stats.felled += 1
			elif t.has("ore"):  # an ore block (issue #103); it never comes back (issue #102)
				drop_items(t.cell, Defs.ORES[t.ore].item, Tuning.ORE_YIELD[t.ore] + skill_bonus(r, "mine"))
				stats.ore_mined = stats.get("ore_mined", 0) + 1
			else:
				drop_items(t.cell, "cobble", Tuning.BOULDER_COBBLE + skill_bonus(r, "mine"))
				stats.broken_boulders += 1
			_wear(r, st.tool)
			if t.get("loose", false) and _roll(Tuning.CAVE_IN_CHANCE):  # issue #110
				injure(r, 2 if _roll(Tuning.CAVE_IN_SERIOUS) else 1, "a cave-in")
			_check_find(t.cell)  # issue #111
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
			drop_items(sh.cell, "wool", 1)
			drop_items(sh.cell, "mutton", 1)
			stats.sheep_hunted = stats.get("sheep_hunted", 0) + 1
			rev += 1
		"plant":
			var crop: Dictionary = st.target
			if not is_same(m.farm.get(crop.cell), crop) or crop.grow >= 0.0 or m.items.has(crop.cell):
				return "gone"
			crop.grow = 0.0
			stats.planted = stats.get("planted", 0) + 1
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
					uses = roundi(full_uses(o) * (1.0 + Tuning.TOOLSMITH_USES * (level(r, "toolsmith") - 1)))
				drop_items(rcell(r), o, rec.out[o], uses)
				if Defs.ITEMS[o].get("tool", "") == "pick":
					stats.pick_crafted = true
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
		u.step(_goto([route_sign()], true))
		u.step({"op": "unload_wait"})
		r.job = u
		return
	if on_the_way(r):  # out of village labor: off to the signpost, or home from the site (issue #108)
		r.job = _road_job()
		return
	if on_road(r):  # walking the road map (issue #118)
		r.job = _road_walk_job(r)
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
	if auto_craft:
		expand_queues()
	keep_meals_stocked()
	keep_tools_stocked()
	# Jobs switched on, priority 1 first; within a priority, Slice 1's order (spec §5).
	for p in [1, 2, 3]:
		var jobs: Array = Defs.JOBS.filter(func(jb): return r.jobs[jb].on and r.jobs[jb].pri == p)
		if jobs.is_empty():
			continue
		for kind in CLAIM_ORDER:
			var j = _claim_kind(r, c, kind, jobs)
			if j != null:
				r.job = j
				return


## The kinds of work, in the order a resident looks for them within one priority.
const CLAIM_ORDER := ["station", "build", "farm", "gather", "haul"]


## A job of this kind for `r`, using only the jobs in `jobs`, or null.
func _claim_kind(r: Dictionary, c: Vector2i, kind: String, jobs: Array):
	match kind:
		"station":
			var st_jobs: Array = jobs.filter(func(jb): return jb in ["craft", "toolsmith", "cook"])
			if st_jobs.is_empty():
				return null
			var benches := m.sites.filter(func(s): return s.done and is_station(s) and not s.queue.is_empty() and s.crafter == 0 and not bench_craftable(s, st_jobs).is_empty() and not _cooling(s))
			if not benches.is_empty():
				var b: Dictionary = _nearest_site(benches, c)
				var rec := bench_craftable(b, st_jobs)
				return _tagged(_craft_job(r, b, rec), recipe_job(rec))
			var dj = _try_deliver(r, c, m.sites.filter(func(s): return s.done and is_station(s) and not s.queue.is_empty()), st_jobs)
			if dj != null:
				return _tagged(dj, recipe_job(Defs.recipe(dj.target.queue[bench_active(dj.target, st_jobs)])))
		"build":
			if not jobs.has("build"):
				return null
			var ready := m.sites.filter(func(s): return site_ready(s))
			if not ready.is_empty():
				return _tagged(_build_job(r, _nearest_site(ready, c)), "build")
			var dj = _try_deliver(r, c, m.sites.filter(func(s): return not s.done and site_open(s) and footprint_clear(s)))
			if dj != null:
				return _tagged(dj, "build")
			return _road_claim(r, "build", jobs)
		"farm":
			if not jobs.has("farm"):
				return null
			var crop = _farm_work(c)
			if crop != null:
				return _tagged(_farm_job(r, crop), "farm")
		"gather":
			var targets: Array = []
			if jobs.has("mine") and r.get("hurt", 0) == 0:  # the injured can't mine (issue #110)
				if not r.broken.axe or not tool_items("axe", 0).is_empty():
					for t in m.trees:
						if t.alive and t.des and t.claim == 0 and not _cooling(t):
							targets.append(t)
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
				return _tagged(_hunt_job(r, t), "hunt") if t.kind == "sheep" else _tagged(_gather_job(r, t), "mine")
			var rj = _road_claim(r, "gather", jobs)
			if rj != null:
				return _tagged(rj, "mine")
		"haul":
			if not jobs.has("haul"):
				return null
			var pj = _pack_job(r, c)  # packing for an expedition comes before the stockpile
			if pj != null:
				return _tagged(pj, "haul")
			if m.zone.is_empty():
				return _road_claim(r, "haul", jobs)
			var hs = _haul_source(c, carry_cap(r))
			if hs != null:
				return _tagged(_haul_job(r, hs.stack, hs.dest, hs.n), "haul")
			return _road_claim(r, "haul", jobs)
	return null


func _tagged(j: Job, work: String) -> Job:
	j.work = work
	return j


## The nearest loose stack that has room in a stockpile (unloaded cargo first), as {stack, dest, n}, or null.
func _haul_source(c: Vector2i, carry := Tuning.CARRY):
	var loose := stacks_where(func(s): return avail(s) > 0 and not in_zone(s.cell))
	# An expedition's unloaded cargo goes first (issue #112), then the nearest.
	loose.sort_custom(func(a, b): return a.get("cargo", false) and not b.get("cargo", false) or (a.get("cargo", false) == b.get("cargo", false) and manhattan(a.cell, c) < manhattan(b.cell, c)))
	for ls in loose:
		var dest = zone_dest(ls.type)
		if dest == null:
			continue
		var cap := Defs.stack_cap(ls.type)
		var here = m.items.get(dest)
		var room: int = cap - (here.n if here != null else 0)
		return {"stack": ls, "dest": dest, "n": mini(mini(avail(ls), carry), room)}
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
	if meadow_sheep < Tuning.MEADOW_SHEEP:
		meadow_regrow += Tuning.DT
		if meadow_regrow >= Tuning.MEADOW_REGROW:
			meadow_regrow = 0.0
			meadow_sheep += 1
	var prev := map_id
	for id in maps:  # every map ticks, whether or not anyone is looking at it
		use_map(id)
		_step_map()
	use_map("village")
	_step_arrivals()
	use_map(prev)
	var kinds := {}
	var working := 0
	for r in residents:
		if r.job != null and not (r.job.kind in ["move", "arrive", "stage", "road", "rest", "hurt", "commute", "unload"]):
			kinds[r.job.kind] = true
			working += 1
	if working >= 2 and kinds.size() >= 2:
		stats.division = true
	if tick % 5 == 0:
		compute_stuck()


## One tick of the current map: what grows, the sheep, and the residents on it.
func _step_map() -> void:
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
	for sh in m.sheep:
		if sh.alive:
			_step_sheep(sh)
	for r in residents:
		if r.map != map_id:
			continue
		if r.away:
			if tick >= r.back_at:
				if r.get("trip", "meadow") in ["", "meadow"]:
					_return_from_meadow(r)
				elif r.trip == "village":
					_arrive_home(r)
				else:
					_arrive_at_site(r)
			continue
		_step_resident(r)
	_step_site()
	if map_id == "village":
		_step_unload()
	elif map_id == Road.ID:
		_step_cart()
	if auto_craft and tick % 10 == 0:
		expand_queues()
	if tick % 10 == 0:
		keep_meals_stocked()
		keep_tools_stocked()
	if tick % 10 == 0:
		for s in m.sites:
			if not s.done and s.tpl != "track":  # the cut is cleared by the player's order (issue #119)
				_mark_obstacles(s)


## Sheep wander one cell at a time with pauses, staying on walkable ground. A sheep being hunted
## stands still once its hunter is next to it.
func _step_sheep(sh: Dictionary) -> void:
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
			if walkable(n):
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


# ---------------------------------------------------------------- the sheep meadow (issue #50)

## The signpost at the map's left edge, where trips to the meadow leave and come back.
func meadow_sign() -> Vector2i:
	return Vector2i(0, h / 2)


## Sends a resident to the meadow: they walk to the signpost, then are away for the trip.
func send_to_meadow(r: Dictionary) -> void:
	if r.map != map_id:
		on_map(r.map, send_to_meadow.bind(r))
		return
	if r.arriving or r.away:
		return
	if r.job != null:
		fail_job(r)
	r.note = null
	r.orders.clear()
	var j := Job.new("trip", "Heading to the meadow", "the meadow signpost")
	j.ordered = true
	j.step(_goto([meadow_sign()], true))
	j.step({"op": "depart"})
	r.direct = j


func _return_from_meadow(r: Dictionary) -> void:
	r.away = false
	var c = nearest_walkable(meadow_sign())
	r.pos = Vector2(c if c != null else meadow_sign())
	r.path = []
	var take := mini(Tuning.MEADOW_TAKE, meadow_sheep)
	meadow_sheep -= take
	if take > 0:
		drop_items(rcell(r), "wool", take)
		drop_items(rcell(r), "mutton", take)
		stats.meadow_trips = stats.get("meadow_trips", 0) + 1
		_toast("%s is back from the meadow with %d wool and %d raw mutton." % [r.name, take, take], r.id)
	else:
		_toast("%s is back from the meadow with nothing: no sheep were left." % r.name, r.id)
	rev += 1


## Seconds until an away resident is back.
func back_in(r: Dictionary) -> float:
	return maxf(0.0, float(r.back_at - tick) / Tuning.TPS)


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
	var skill: String = Defs.JOBS[rng.randi_range(0, Defs.JOBS.size() - 1)]
	t.jobs[skill].xp = Tuning.SKILL_LEVELS[Tuning.ARRIVAL_LEVEL - 2]
	t.jobs[skill].on = true  # a skilled toolsmith arrives at work (issue #91)
	walk_in(t)
	_toast("A traveler named %s has arrived, a skilled %s." % [t.name, Defs.JOB_SKILLED[skill]], t.id)


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
func _add_stuck(who: String, why: String, at: Vector2, height: float, fk: String, fid: int, hidden := false, waiting := false) -> void:
	# The same problem keeps its age while its count changes ("4 more planks" -> "3 more planks").
	var key := "%s|%s|%d|%s|%s" % [map_id, fk, fid, who, _DIGITS.sub(why, "#", true)]
	if not _stuck_since.has(key):
		_stuck_since[key] = tick
	stuck.append({"who": who, "why": why, "map": map_id, "cell": at, "height": height, "focus_kind": fk, "focus_id": fid, "hidden": hidden,
		"waiting": waiting, "key": key, "since": _stuck_since[key]})


static var _DIGITS := RegEx.create_from_string("\\d+")


## Works out every map's stuck reasons. Each carries its map, so focusing it can switch the view.
func compute_stuck() -> void:
	stuck = []
	var prev := map_id
	for id in maps:
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
		if s.tpl == "track":  # only the segment being laid speaks up; the rest wait their turn (issue #121)
			if s.done or s.seg != next_track():
				continue
			var bl := track_blocker(s.seg)
			if bl != "":
				_add_stuck(tpl.name, "Track: %s first" % bl.to_lower(), mid, 0.4, "site", s.id)
			elif not residents.any(func(o): return o.jobs.build.on):
				_add_stuck(tpl.name, "Track: no one with Build on", mid, 0.4, "site", s.id)
			elif line_short() > 0:
				_add_stuck(tpl.name, "Track: needs %d more rails" % line_short(), mid, 0.4, "site", s.id)
			continue
		if not s.done and not footprint_clear(s):
			var ob := site_obstacles(s)
			var nb: int = ob.boulders.size()
			if nb and not any_pick:
				_add_stuck(tpl.name, "Needs a pickaxe to clear " + ("a boulder" if nb == 1 else "%d boulders" % nb), mid, 0.6, "site", s.id)
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
			_add_stuck(tpl.name, why,
				mid, site_height(s) + 0.4, "site", s.id, false, standing)
	_stuck_unstaffed()
	_stuck_expedition()
	_stuck_site()
	if meadow_sheep == 0:
		for r in on_here:
			if r.job != null and r.job.kind == "trip":
				_add_stuck("Meadow", "Meadow has no sheep left", Vector2(meadow_sign()) + Vector2(0.5, 0.5), 1.4, "res", r.id)
				break
	var has_food: bool = food_available() if m.kind != "route" else on_map("village", food_available)  # the road eats from home
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
					_add_stuck(r.name, "%s broke. Craft one at the bench, or switch Toolsmith on for someone" % tname, at, 1.6, "res", r.id)
				else:
					_add_stuck(r.name, "%s broke. Needs a new %s" % [tname, tname.to_lower()], at, 1.6, "res", r.id)
		if r.note != null and r.note.until > tick:
			_add_stuck(r.name, r.note.text, at, 1.6, "res", r.id)
		if r.get("hurt", 0) > 0:  # issue #110: rest is a reason, not a blocker
			var left := ceili(r.heal / (1.0 if _has_bed(r) else Tuning.HEAL_NO_BED))
			var why := "Injured: can't mine, and works slower" if r.hurt == 1 else "Seriously hurt: waiting at the entrance"
			if resting(r):
				why = "%s, resting in bed (%d s)" % ["Injured" if r.hurt == 1 else "Seriously hurt", left] if _has_bed(r) else "Injured, resting: no bed of their own, so it's slower (%d s)" % left
			_add_stuck(r.name, why, at, 1.6, "res", r.id, false, true)
	if m.zone.is_empty():
		for k in m.farm:
			if m.farm[k].grow < 0.0 and m.items.has(k):
				_add_stuck("Farm", "Harvested wheat needs a stockpile before replanting", Vector2(k) + Vector2(0.5, 0.5), 0.6, "crop", m.farm[k].id)
				break
	if not m.zone.is_empty():
		var loose := stacks_where(func(s): return avail(s) > 0 and not in_zone(s.cell))
		var full := not loose.is_empty()
		for s in loose:
			if zone_dest(s.type) != null:
				full = false
				break
		if full:
			_add_stuck("Stockpile", "Stockpile is full", Vector2(m.zone.keys()[0]) + Vector2(0.5, 0.5), 0.6, "", 0)


## "No one does Farm" (spec §9): there's work of a job and every resident has that job off.
func _stuck_unstaffed() -> void:
	if here().is_empty() or m.kind == "site":  # a party works a site whatever its jobs (issue #109)
		return
	for jb in Defs.JOBS:
		if residents.any(func(r): return r.jobs[jb].on):
			continue
		var at = _work_at(jb)
		if at != null:
			_add_stuck(Defs.JOB_NAMES[jb], "No one does %s" % Defs.JOB_NAMES[jb], Vector2(at) + Vector2(0.5, 0.5), 0.8, "", 0)


## A cell where work of this job is waiting, or null when there's none.
func _work_at(jb: String):
	match jb:
		"mine":
			for o in m.trees + boulders:
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
				if not st.done:
					return st.origin
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
	if s.tpl == "bench":
		return 0.75 if s.done else 0.2
	if s.tpl == "fireplace":
		return 0.7 if s.done else 0.2
	if s.tpl == "board":
		return 1.5 if s.done else 0.2
	if s.tpl in ["bridge", "track", "station"]:
		return 0.2 if s.tpl != "station" or not s.done else 0.9
	return [0.2, 0.5, 2.5, 4.0, 4.0][mini(s.stage, 4)]


# ---------------------------------------------------------------- commands

## Marks every tree and boulder in `rect` to be mined; `kinds` can limit it to "tree" or "boulder"
## (issue #7). A single click on an already-marked one (pass it as `single`) unmarks it instead.
func designate_mine(rect: Rect2i, single = null, kinds := ["tree", "boulder"]) -> void:
	var hit: Array = []
	if single != null:
		hit = [single]
	else:
		var pool: Array = (m.trees if kinds.has("tree") else []) + (m.boulders if kinds.has("boulder") else [])
		for o in pool:
			if o.alive and not o.get("hidden", false) and rect.has_point(o.cell):
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


## Marks sheep in `rect` to be hunted (Hunt order, issue #42). A single click on an already-marked
## sheep (pass it as `single`) unmarks it instead.
func designate_hunt(rect: Rect2i, single = null) -> void:
	var hit: Array = [single] if single != null else m.sheep.filter(func(sh): return sh.alive and rect.has_point(sh.cell))
	var all_on := not hit.is_empty() and hit.all(func(o): return o.des)
	for o in hit:
		o.des = not (single != null and all_on)
		o.unreach_until = 0
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
	var size: Vector2i = Defs.TEMPLATES[tpl].size
	var foot := Rect2i(origin, size)
	if origin.x < 0 or origin.y < 0 or origin.x + size.x > w or origin.y + size.y > h:
		return "Too close to the edge"
	if foot.has_point(meadow_sign()):
		return "The meadow signpost is in the way"
	if foot.has_point(route_sign()):
		return "The signpost to the old mine is in the way"
	for s in m.sites:
		if Rect2i(s.origin, s.size).intersects(foot):
			return "Overlaps another building"
	for s in m.sites:
		if s.get("plot") != null and s.plot.intersects(foot):
			return "Overlaps a reserved plot"
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
	var s := {"id": _id(), "kind": "site", "tpl": tpl, "origin": origin, "size": Defs.TEMPLATES[tpl].size,
		"rot": rot, "stage": 0, "store": {}, "incoming": {}, "builder": 0, "crafter": 0, "crafting": "",
		"done": false, "owner": 0, "queue": [], "autoq": [], "unreach_until": 0,
		"plot": plot_rect(tpl, origin, rot), "map": map_id}
	if tpl == "fireplace":
		s.keep_meals = true
	m.sites.append(s)
	_occ_dirty = true
	for c in site_cells(s):
		m.zone.erase(c)
		_drop_crop(c)
	if s.plot != null:  # the reserved plot is kept clear of stockpiles and farms
		for x in range(s.plot.position.x, s.plot.end.x):
			for y in range(s.plot.position.y, s.plot.end.y):
				m.zone.erase(Vector2i(x, y))
				_drop_crop(Vector2i(x, y))
	_mark_obstacles(s)
	rev += 1
	return s


## Switches a job on or off for a resident (spec §5). Switching off the job they're doing stops it.
func set_job_on(r: Dictionary, job: String, on: bool) -> void:
	if r.map != map_id:
		on_map(r.map, set_job_on.bind(r, job, on))
		return
	r.jobs[job].on = on
	if not on and r.job != null and r.job.work == job and not r.job.ordered:
		fail_job(r)
	rev += 1


## Sets a job's priority, 1 (first) to 3.
func set_job_priority(r: Dictionary, job: String, pri: int) -> void:
	r.jobs[job].pri = clampi(pri, 1, 3)
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
	_occ_dirty = true
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
	elif target != null and target.kind == "sheep":
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
	elif target != null and target.kind == "sheep":
		target.des = true
		target.unreach_until = 0
		rev += 1
		r.orders.append({"kind": "hunt", "id": target.id})
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
	j.step(_goto([stack.cell], false))
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
		return "Hunt a sheep"
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
	var front: Vector2i = [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)][int(b.rot) % 4]
	var side := Vector2i(front.y, front.x)
	return [b.origin + front - side, b.origin + front, b.origin + front + side]


## Whether a resident is in the party that's packing to leave.
func in_staging_party(r: Dictionary) -> bool:
	return expedition.get("state", "") == "staging" and expedition.party.has(r.id) and r.map == "village"


## Why a resident can't join a party, or "" when they can (issue #106).
func cant_join(r: Dictionary) -> String:
	if r.arriving:
		return "Still walking in"
	if r.away:
		return "Away at the meadow" if r.get("trip", "meadow") in ["", "meadow"] else "On the road"
	if r.get("hurt", 0) > 0:
		return "Injured, resting" if r.hurt == 1 else "Seriously hurt, resting"
	if expedition.get("state", "") == "out" and expedition.party.has(r.id):
		return "Out with the party"
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
	return {"dest": dest, "party": party, "target": {"item": "coal", "n": 8}, "meals": 3, "picks": 1,
		"policy": {"target": true, "full": true, "low": true}, "spend_return": false, "cart_cap": cart_adds_room()}


## The party's packs: each member carries PACK_CAPACITY items, shared by supplies and cargo.
static func pack_capacity(plan: Dictionary) -> int:
	return plan.party.size() * Tuning.PACK_CAPACITY + (Tuning.CART_CAPACITY if plan.get("cart_cap", false) else 0)


## Room the supplies take: a meal or a spare pickaxe is one item each.
static func plan_supplies(plan: Dictionary) -> int:
	return plan.meals + plan.picks


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
	if not expedition.is_empty():
		out.append("One expedition at a time")
	if expedition_board().is_empty():
		out.append("Build an expedition board first")
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
		elif plan.target.n > room:
			out.append("The packs only have room for %s" % Defs.words(plan.target.item, room))
	if not plan.policy.values().has(true):
		out.append("Choose when the party comes home")
	return out


## Confirms a plan (issue #106): packing starts at the board. Nobody leaves until Depart.
## Returns why it can't, or "".
func plan_expedition(plan: Dictionary) -> String:
	var problems := plan_problems(plan)
	if not problems.is_empty():
		return problems[0]
	expedition = plan.duplicate(true)
	expedition.board = expedition_board().id
	expedition.state = "staging"
	expedition.packed = {}
	expedition.tools = []
	rev += 1
	_toast("Packing for the %s has started. The party gathers at the board." % maps[plan.dest].name.to_lower(), 0, expedition.board)
	return ""


## Meals and spare pickaxes at the board so far, plus those on their way there when `incoming`.
func packed(incoming := false) -> Dictionary:
	var out := {"meals": 0, "picks": 0}
	var b := site(expedition.get("board", 0))
	if b.is_empty():
		return out
	for src in ([b.store, b.incoming] if incoming else [b.store]):
		for k in src:
			if Defs.MEALS.has(k):
				out.meals += src[k]
			elif Defs.ITEMS[k].get("tool", "") == "pick":
				out.picks += src[k]
	return out


## What's still to be packed, less what's on its way: {meals, picks}.
func pack_needs() -> Dictionary:
	if expedition.get("state", "") != "staging":
		return {"meals": 0, "picks": 0}
	var p := packed(true)
	return {"meals": maxi(0, expedition.meals - p.meals), "picks": maxi(0, expedition.picks - p.picks)}


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
func depart_blocker() -> String:
	if expedition.get("state", "") != "staging":
		return "Nothing is being packed"
	var p := packed()
	var meals: int = expedition.meals - p.meals
	if meals > 0:
		return "Waiting for %d %s to pack" % [meals, "meal" if meals == 1 else "meals"]
	var picks: int = expedition.picks - p.picks
	if picks > 0:
		return "Waiting for %d spare %s to pack" % [picks, "pickaxe" if picks == 1 else "pickaxes"]
	for id in expedition.party:
		var r := resident(id)
		if not at_board(r):
			return "Waiting for %s" % r.get("name", "someone")
	return ""


## Depart (issue #107): the party leaves with what was packed, and is out of village labor from now on.
## Departure is always the player's call. Returns why it can't go, or "".
func depart() -> String:
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
	expedition.state = "out"
	expedition.leg = "out"
	expedition.cart = cart_ready()  # the party rides the line if there's a cart at the village station (issue #124)
	expedition.cart_cap = cart_adds_room()
	expedition.broken = 0
	expedition.provisions = expedition.packed.duplicate()  # the meals in the packs (issue #109)
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
func _arrive_at_site(r: Dictionary) -> void:
	var id: String = r.trip
	var mp: SimMap = maps[id]
	r.away = false
	r.trip = ""
	move_to_map(r, id, mp.entrance)
	mp.known = true
	mp.visited = true
	if expedition.get("dest", "") != id or expedition.get("unpacked", false):
		return
	expedition.unpacked = true
	var prev := use_map(id)
	_toast("The party reached the %s." % mp.name.to_lower(), r.id)
	use_map(prev)


## Calls off an expedition that hasn't left (issue #107). What was packed is set down by the board,
## loose, and hauled back to the stockpile.
func cancel_expedition() -> void:
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
	if expedition.get("state", "") != "staging":
		return
	var b := site(expedition.board)
	if b.is_empty() or b.map != map_id:
		return
	var at := Vector2(b.origin) + Vector2(0.5, 0.5)
	var p := packed()
	var need := pack_needs()
	var meals: int = expedition.meals - p.meals
	if meals > 0:
		if need.meals > 0 and stacks_where(func(st): return Defs.MEALS.has(st.type) and avail(st) > 0).is_empty():
			_add_stuck("Expedition", "No meals to pack. Cooks make them at the fireplace, or plan fewer", at, 1.9, "site", b.id)
		else:
			_add_stuck("Expedition", "Waiting for %d %s to pack" % [meals, "meal" if meals == 1 else "meals"], at, 1.9, "site", b.id, false, true)
	var picks: int = expedition.picks - p.picks
	if picks > 0:
		if need.picks > 0 and tool_items("pick", 0).is_empty():
			_add_stuck("Expedition", "No spare pickaxes to pack. Craft one at the bench, or plan fewer", at, 1.9, "site", b.id)
		else:
			_add_stuck("Expedition", "Waiting for %d spare %s to pack" % [picks, "pickaxe" if picks == 1 else "pickaxes"], at, 1.9, "site", b.id, false, true)
	for id in expedition.party:
		var r := resident(id)
		if not r.is_empty() and not at_board(r):
			_add_stuck("Expedition", "Waiting for %s" % r.name, at, 1.9, "res", r.id, false, true)


# ---------------------------------------------------------------- travel and the return (issues #108, #112)

## The signpost on the village's east edge where the road to the old mine starts and ends.
func route_sign() -> Vector2i:
	var v: SimMap = maps.village
	return Vector2i(v.w - 1, v.h / 2)


## Seconds on the road to `to`, and back: the meadow's trip, or the walk to and from a site.
func trip_time(to: String) -> float:
	return Tuning.MEADOW_TRIP if to in ["", "meadow"] else route_walk_time()


## Whether a party member is on their way: walking to the signpost to leave the village, or to the
## site's entrance to come home. Either way, they're out of the work where they are.
func on_the_way(r: Dictionary) -> bool:
	if expedition.get("state", "") != "out" or not expedition.party.has(r.id) or r.away:
		return false
	if expedition.get("leg", "out") == "out":
		return r.map == "village"
	return r.map == expedition.dest


## Whether a party member is carrying the packs through the village, on the way out (drawn as packs).
func carrying_packs(r: Dictionary) -> bool:
	return (on_the_way(r) and r.map == "village") or on_road(r)


## The walk to where the road starts: the village signpost, or the site's entrance on the way home.
func _road_job() -> Job:
	if map_id == "village":
		var dest: String = expedition.dest
		var j := Job.new("road", "Heading for the %s" % maps[dest].name.to_lower(), "the signpost")
		j.step(_goto([route_sign()], true))
		j.step({"op": "depart", "to": dest})
		return j
	var h := Job.new("road", "Heading home", "the entrance")
	h.step(_goto([m.entrance], false))
	h.step({"op": "depart", "to": "village"})
	return h


## Why the party can't be called home yet, or "" when it can.
func call_home_blocker() -> String:
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
func call_home() -> String:
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
	var spot = on_map("village", nearest_walkable.bind(route_sign()))
	move_to_map(r, "village", spot if spot != null else route_sign())
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
	for k in ex.get("provisions", {}):
		left[k] = left.get(k, 0) + ex.provisions[k]
	ex.unpack = left
	ex.unpack_tools = ex.get("tools", []).duplicate(true)
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
	var spot = nearest_walkable(route_sign())
	spot = spot if spot != null else route_sign()
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
	var lines: Array = ["Back from the %s: %s" % [name, ", ".join(got)] if not got.is_empty() else "Back from the %s with nothing mined" % name]
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

func road() -> SimMap:
	return maps[Road.ID]


## Whether a party member is walking the road map (issue #118), out or home. One who's already home
## and out there for other work isn't.
func on_road(r: Dictionary) -> bool:
	return expedition.get("state", "") == "out" and expedition.party.has(r.id) and r.map == Road.ID and r.trip != ""


## Onto the road map at the end they're leaving from, heading for `to` (a site, or "village").
func _onto_road(r: Dictionary, to: String) -> void:
	move_to_map(r, Road.ID, Road.VILLAGE_END if to != "village" else Road.MINE_END)
	r.trip = to
	if expedition.get("state", "") == "out":  # when the leg started, for the report (issue #124)
		var leg: String = "road_" + expedition.get("leg", "out")
		if not expedition.has(leg):
			expedition[leg] = [tick, tick]
	road().known = true
	_reveal(rcell(r))


## A party member's walk along the road, to the far end, where they step off it.
func _road_walk_job(r: Dictionary) -> Job:
	var home: bool = r.trip == "village"
	var j := Job.new("road", "On the road home" if home else "On the road to the %s" % maps[expedition.dest].name.to_lower(), "the end of the road")
	var from := "mine" if home else "village"
	var to := "village" if home else "mine"
	if expedition.get("cart", false) and not cart.is_empty() and (cart.riders.has(r.id) or (cart.state == "parked" and cart.at == from)):
		j.label = ("Riding home" if home else "Riding to the %s" % maps[expedition.dest].name.to_lower()) + " by cart"
		if not cart.riders.has(r.id):  # walk to the cart and get in
			j.step(_goto([Vector2i(roundi(cart.x), Road.LINE_ROW)], true))
			j.step({"op": "board", "riding": j.label})
			j.label = "Getting into the cart"
		j.step({"op": "ride", "to": to})
	j.step(_goto([Road.VILLAGE_END if home else Road.MINE_END], false))
	j.step({"op": "road_end"})
	return j


## About how many seconds a party member has left on the road.
func road_eta(r: Dictionary) -> float:
	var end := Road.VILLAGE_END if r.trip == "village" else Road.MINE_END
	return absf(r.pos.x - end.x) / (Tuning.WALK * hurt_speed(r))


## Walking speed on a cell, as a share of WALK: wading the stream is slow until it's bridged.
func ground_speed(c: Vector2i) -> float:
	return Tuning.FORD_SPEED if m.water.has(c) and not bridged(c) else 1.0


func bridged(c: Vector2i) -> bool:
	return m.sites.any(func(s): return s.tpl == "bridge" and s.done and Rect2i(s.origin, s.size).has_point(c))


## Someone on the road reaches a new segment: the fog lifts off it (issue #119).
func _reveal(c: Vector2i) -> void:
	var rd := road()
	var seg := Road.segment_at(c.x)
	if seg < rd.seen:
		return
	rd.seen = seg + 1
	rev += 1
	if rd.seen >= Road.segment_count():
		var prev := use_map(Road.ID)
		_toast("The road to the mine is surveyed: about %d s on foot. Select the signpost for the route." % roundi(route_walk_time()))
		use_map(prev)


func route_surveyed() -> bool:
	return road().seen >= Road.segment_count()


## The walk from end to end along the line, fording the stream until it's bridged.
func route_walk_time() -> float:
	var t := 0.0
	var rd := road()
	var prev := use_map(Road.ID)
	for x in range(Road.VILLAGE_END.x, Road.MINE_END.x):
		t += 1.0 / (Tuning.WALK * ground_speed(Vector2i(x, Road.LINE_ROW)))
	use_map(prev)
	return t


## The ride from end to end once the line is complete.
static func route_cart_time() -> float:
	return float(Road.MINE_END.x - Road.VILLAGE_END.x) / Tuning.CART_SPEED


## What stands in the way on a segment, in the player's words, or "".
func obstacle_text(i: int) -> String:
	match Road.SEGMENTS[i].obstacle:
		"stream":
			var b := bridge()
			if not b.is_empty() and b.done:
				return "Bridged"
			if not b.is_empty():
				return "A bridge is planned. Until it's built, people wade across slowly"
			return "A stream: people wade across slowly. Track needs a plank bridge (%s)" % Defs.cost_text(Defs.TEMPLATES.bridge.stages[0].cost)
		"cut":
			var n := cut_boulders().size()
			if n == 0:
				return "Cleared"
			return "A rocky cut: %d %s on the line to mine before track can go down" % [n, "boulder" if n == 1 else "boulders"]
	return ""


## The bridge over the stream, planned or built, or {}.
func bridge() -> Dictionary:
	for st in road().sites:
		if st.tpl == "bridge":
			return st
	return {}


## Boulders still standing on the line in the rocky cut.
func cut_boulders() -> Array:
	var line := {}
	for i in Road.segment_count():
		if Road.SEGMENTS[i].obstacle == "cut":
			for c in Road.line_cells(i):
				line[c] = true
	return road().boulders.filter(func(b): return b.alive and line.has(b.cell))


## The route report (issue #119), for the signpost and the expedition board: each segment, and the
## journey on foot and by cart.
func route_report() -> Dictionary:
	var rd := road()
	var segs: Array = []
	for i in Road.segment_count():
		var sg: Dictionary = Road.SEGMENTS[i]
		if i >= rd.seen:
			segs.append({"name": "Not walked yet", "known": false, "len": Road.seg_len(i)})
			continue
		segs.append({"name": sg.name, "known": true, "len": Road.seg_len(i), "terrain": sg.terrain,
			"obstacle": obstacle_text(i), "track": track_state(i)})
	return {"segments": segs, "surveyed": route_surveyed(), "walk": route_walk_time(), "cart": route_cart_time(), "cart_now": route_cart_now()}


## Places the plank bridge over the stream (issue #119). Returns why it can't, or "".
func plan_bridge() -> String:
	if road().seen <= _seg_of("stream"):
		return "Nobody has seen the stream yet"
	if not bridge().is_empty():
		return "The bridge is already planned"
	var prev := use_map(Road.ID)
	var b := place_site("bridge", Road.BRIDGE_AT)
	use_map(prev)
	b.plot = null
	return ""


## Marks the cut's boulders on the line to be mined (issue #119). Returns why it can't, or "".
func clear_cut() -> String:
	if road().seen <= _seg_of("cut"):
		return "Nobody has seen the cut yet"
	var left := cut_boulders()
	if left.is_empty():
		return "The cut is already clear"
	for b in left:
		b.des = true
		b.unreach_until = 0
	rev += 1
	return ""


static func _seg_of(obstacle: String) -> int:
	for i in Road.segment_count():
		if Road.SEGMENTS[i].obstacle == obstacle:
			return i
	return -1


# The line (issue #121): one point-to-point line along the road, a track blueprint per segment.

## A segment's track site, or {}.
func track_site(i: int) -> Dictionary:
	for st in road().sites:
		if st.tpl == "track" and st.seg == i:
			return st
	return {}


## "none", "planned" or "built".
func track_state(i: int) -> String:
	var t := track_site(i)
	return "none" if t.is_empty() else ("built" if t.done else "planned")


## What stops a segment's track going down, in the player's words, or "".
func track_blocker(i: int) -> String:
	match Road.SEGMENTS[i].obstacle:
		"stream":
			var b := bridge()
			if b.is_empty() or not b.done:
				return "Needs the bridge"
		"cut":
			if not cut_boulders().is_empty():
				return "Needs the cut cleared"
	return ""


## The segment being laid now: the first unbuilt one from the village end, or -1.
func next_track() -> int:
	for i in Road.segment_count():
		var t := track_site(i)
		if not t.is_empty() and not t.done:
			return i
	return -1


## Whether a site on the road can be worked now: track only on the next segment, once it's clear.
func site_open(st: Dictionary) -> bool:
	if st.tpl != "track":
		return true
	return st.seg == next_track() and track_blocker(st.seg) == ""


func line_complete() -> bool:
	return range(Road.segment_count()).all(func(i): return track_state(i) == "built")


## What the line costs, for the preview (issue #121): the rails it needs that aren't laid or delivered,
## the iron ingots to craft those beyond the rails on hand, and the seconds a round trip saves.
func line_cost() -> Dictionary:
	var rails := 0
	for i in Road.segment_count():
		var t := track_site(i)
		if t.is_empty():
			rails += Tuning.RAILS_PER_SEGMENT
		elif not t.done:
			rails += Tuning.RAILS_PER_SEGMENT - t.store.get("rail", 0)
	var on_hand: int = on_map("village", free_count.bind("rail"))
	var crafts := ceili(maxi(0, rails - on_hand) / 16.0)
	var ingots: int = crafts * int(Defs.recipe("rails").inp.iron_ingot)
	return {"rails": rails, "on_hand": on_hand, "ingots": ingots, "saved": 2.0 * (route_walk_time() - route_cart_time())}


## Why the line can't be planned, or "".
func plan_line_blocker() -> String:
	if not route_surveyed():
		return "Walk the road first: nobody knows the way past the fog"
	if range(Road.segment_count()).all(func(i): return track_state(i) != "none"):
		return "The whole line is planned"
	return ""


## Plans the line (issue #121): a track blueprint on every segment that has none, from the village end
## to the mine. One point-to-point line, with no switches or branches (#29). Returns why it can't, or "".
func plan_line() -> String:
	var why := plan_line_blocker()
	if why != "":
		return why
	var prev := use_map(Road.ID)
	for i in Road.segment_count():
		if track_state(i) != "none":
			continue
		var t := {"id": _id(), "kind": "site", "tpl": "track", "origin": Vector2i(Road.SEGMENTS[i].x, Road.LINE_ROW),
			"size": Vector2i(Road.seg_len(i), 1), "rot": 0, "stage": 0, "store": {}, "incoming": {}, "builder": 0,
			"crafter": 0, "crafting": "", "done": false, "owner": 0, "queue": [], "autoq": [], "unreach_until": 0,
			"plot": null, "map": Road.ID, "seg": i}
		m.sites.append(t)
	_occ_dirty = true
	rev += 1
	use_map(prev)
	return ""


# Work on the road (issues #119, #121): village residents walk out to build, deliver and clear there.

## Into the road from the village, before step `at` of a job made for the road.
func _via_road(j: Job, at: int) -> Job:
	j.steps.insert(at, _goto([route_sign()], true))
	j.steps.insert(at + 1, {"op": "cross", "to": Road.ID})
	return j


## Back to the village from the road.
func _back_job() -> Job:
	var j := Job.new("commute", "Heading back to the village", "the village")
	j.step(_goto([Road.VILLAGE_END], false))
	j.step({"op": "cross", "to": "village"})
	return j


## Work of this kind out on the road, for a village resident with nothing of it to do at home: build
## or supply the bridge and the line, or mine what's marked there. Null when there's none.
func _road_claim(r: Dictionary, kind: String, jobs: Array):
	if map_id != "village" or not maps.has(Road.ID) or not road().known:
		return null
	var c := rcell(r)
	var has_pick: bool = r.pick != null or not tool_items("pick", 0).is_empty()
	var prev := use_map(Road.ID)
	var j = null
	match kind:
		"build":
			if jobs.has("build"):
				var ready := m.sites.filter(func(st): return site_ready(st))
				if not ready.is_empty():
					j = _via_road(_tagged(_build_job(r, _nearest_site(ready, Road.VILLAGE_END)), "build"), 0)
				else:
					for st in m.sites:
						if st.done or not site_open(st) or _cooling(st) or not footprint_clear(st):
							continue
						var need := stage_needs(st)
						for t in need:
							var here_src: Array = m.items.values().filter(func(x): return x.type == t and avail(x) > 0)
							if not here_src.is_empty():  # already out on the road: rails at the railhead
								var at_road: Dictionary = nearest(here_src, Road.VILLAGE_END)
								j = _via_road(_tagged(_deliver_job(st, t, mini(mini(need[t], carry_cap(r)), avail(at_road)), at_road), "build"), 0)
								break
							if st.tpl == "track":  # rails go out to the railhead first (issue #122)
								continue
							var src: Array = maps.village.items.values().filter(func(x): return x.type == t and avail(x) > 0)
							if src.is_empty():
								continue
							var from: Dictionary = nearest(src, c)
							j = _via_road(_tagged(_deliver_job(st, t, mini(mini(need[t], carry_cap(r)), avail(from)), from), "build"), 2)
							break
						if j != null:
							break
					if j == null:
						j = _railhead_job(r, c)
		"haul":
			if jobs.has("haul"):
				j = _dock_job(r, c)
				if j == null:
					j = _platform_haul(r, true)
		"gather":
			if jobs.has("mine") and r.get("hurt", 0) == 0:
				var targets: Array = m.trees.filter(func(t): return t.alive and t.des and t.claim == 0 and not _cooling(t))
				if has_pick:
					targets += m.boulders.filter(func(b): return b.alive and b.des and b.claim == 0 and not _cooling(b))
				if not targets.is_empty():
					var t: Dictionary = nearest(targets, Road.VILLAGE_END)
					use_map("village")
					j = _gather_job(r, t)  # a better tool is fetched in the village first
					use_map(Road.ID)
					_via_road(j, j.steps.size() - 2)
	use_map(prev)
	return j


## What someone out on the road does next: more work there, or back to the village to eat, fetch
## materials or find other work.
func _claim_on_road(r: Dictionary) -> Job:
	if r.hunger < Tuning.EAT_BELOW:
		return _back_job()
	var c := rcell(r)
	for p in [1, 2, 3]:
		var jobs: Array = Defs.JOBS.filter(func(jb): return r.jobs[jb].on and r.jobs[jb].pri == p)
		for kind in ["build", "gather"]:
			var j = _claim_kind(r, c, kind, jobs)
			if j != null:
				return j
		if jobs.has("haul"):
			var hj = _platform_haul(r, false)
			if hj != null:
				return hj
	return _back_job()


# Laying the line (issue #122): rails go out to the railhead, then to the segment being laid, rail by rail.

## Whether a site can be built now: a track segment with a rail to lay, or a stage with all it needs.
func site_ready(st: Dictionary) -> bool:
	if st.done or st.builder != 0 or not site_open(st) or _cooling(st) or not footprint_clear(st):
		return false
	if st.tpl == "track":
		return st.store.get("rail", 0) > 0
	return has_all(st.store, current_stage(st).cost)


## One rail laid: the segment fills in rail by rail, and is usable once complete.
func _lay_rail(st: Dictionary) -> void:
	if st.store.get("rail", 0) <= 0:
		return
	st.store.rail -= 1
	st.laid = st.get("laid", 0) + 1
	rev += 1
	if st.laid >= Tuning.RAILS_PER_SEGMENT:
		st.stage = 1
		st.done = true
		st.store = {}
		st.incoming = {}
		_on_site_done(st)


func _railhead_spot() -> Vector2i:
	return Road.RAILHEAD


## Rails at the railhead (and anywhere else on the road) that nobody has claimed yet.
func railhead_rails() -> int:
	var n := 0
	for st in road().items.values():
		if st.type == "rail":
			n += avail(st)
	return n


## Rails on their way out to the railhead.
func _rails_inflight() -> int:
	var n := 0
	for r in residents:
		if r.job != null and r.job.kind == "railhead":
			n += r.job.steps[-1].n
	return n


## Rails the planned line still needs laid, less those delivered or on their way to a segment.
func _line_rails_owed() -> int:
	var n := 0
	for i in Road.segment_count():
		var t := track_site(i)
		if not t.is_empty() and not t.done:
			n += Tuning.RAILS_PER_SEGMENT - t.get("laid", 0) - t.store.get("rail", 0) - t.incoming.get("rail", 0)
	return maxi(0, n)


## Rails still to carry out to the railhead.
func railhead_need() -> int:
	return maxi(0, _line_rails_owed() - railhead_rails() - _rails_inflight())


## Rails the line still needs that don't exist anywhere yet.
func line_short() -> int:
	var have: int = railhead_rails() + _rails_inflight() + on_map("village", free_count.bind("rail"))
	return maxi(0, _line_rails_owed() - have)


## A load of rails from the village out to the railhead pile, or null.
func _railhead_job(r: Dictionary, c: Vector2i):
	var need := railhead_need()
	if need <= 0:
		return null
	var src: Array = maps.village.items.values().filter(func(x): return x.type == "rail" and avail(x) > 0)
	if src.is_empty():
		return null
	var from: Dictionary = nearest(src, c)
	var n := mini(mini(need, carry_cap(r)), avail(from))
	var j := Job.new("railhead", "Carrying rails to the railhead", "the railhead")
	j.work = "build"
	from.res += n
	var sh := j.hold({"t": "stack", "stack": from, "n": n})
	j.step(_goto([from.cell], false))
	j.step({"op": "pickup", "stack": from, "n": n, "hold": sh})
	j.step(_goto([route_sign()], true))
	j.step({"op": "cross", "to": Road.ID})
	j.step(_goto([_railhead_spot()], false))
	j.step({"op": "railhead_drop", "n": n})
	return j


# Stations and the cart (issue #123).

## The station at "village" or "mine" end, planned or built, or {}.
func station(end: String) -> Dictionary:
	for st in road().sites:
		if st.tpl == "station" and st.end == end:
			return st
	return {}


## Where the cart stops at a station, along the line.
static func station_x(end: String) -> float:
	return Road.STATIONS[end].x + 1.0


## Places a station at one end of the road (issue #123). Returns why it can't, or "".
func plan_station(end: String) -> String:
	if not station(end).is_empty():
		return "That station is already planned"
	if road().seen <= Road.segment_at(Road.STATIONS[end].x):
		return "Nobody has walked that far yet"
	var prev := use_map(Road.ID)
	var st := place_site("station", Road.STATIONS[end])
	use_map(prev)
	st.end = end
	st.plot = Rect2i(Road.STATIONS[end], Vector2i(3, 3))  # room to grow into a loading station
	return ""


## The minecart on its way to the village station, by someone hauling it.
func _docking() -> bool:
	return residents.any(func(r): return r.job != null and r.job.steps.any(func(x): return x.op == "dock"))


## A finished minecart from the village, hauled out to the village station and parked there.
func _dock_job(r: Dictionary, c: Vector2i):
	var vs := station("village")
	if vs.is_empty() or not vs.done or not cart.is_empty() or _docking():
		return null
	var carts: Array = maps.village.items.values().filter(func(x): return x.type == "minecart" and avail(x) > 0)
	if carts.is_empty():
		return null
	var from: Dictionary = nearest(carts, c)
	var j := Job.new("haul", "Hauling the minecart to the station", "the station")
	j.work = "haul"
	from.res += 1
	var sh := j.hold({"t": "stack", "stack": from, "n": 1})
	j.step(_goto([from.cell], false))
	j.step({"op": "pickup", "stack": from, "n": 1, "hold": sh})
	j.step(_goto([route_sign()], true))
	j.step({"op": "cross", "to": Road.ID})
	j.step(_goto(site_cells(vs), true))
	j.step({"op": "dock"})
	return j


## Cargo set down on a station's platform, hauled back along the road to the village stockpile.
func _platform_haul(r: Dictionary, from_village: bool):
	var src: Array = road().items.values().filter(func(x): return x.get("cargo", false) and avail(x) > 0)
	if src.is_empty():
		return null
	var st: Dictionary = nearest(src, Road.VILLAGE_END)
	var vm: SimMap = maps.village
	var dest = on_map("village", zone_dest.bind(st.type))
	if dest == null:
		return null
	var there = vm.items.get(dest)
	var n := mini(mini(avail(st), carry_cap(r)), Defs.stack_cap(st.type) - (there.n if there != null else 0))
	if n <= 0:
		return null
	vm.zone_res[dest] = r.id
	var j := Job.new("haul", "Hauling %s from the station" % Defs.ITEMS[st.type].many, "the stockpile")
	j.work = "haul"
	st.res += n
	var sh := j.hold({"t": "stack", "stack": st, "n": n})
	var zh := j.hold({"t": "zone", "cell": dest, "map": "village"})
	if from_village:
		j.step(_goto([route_sign()], true))
		j.step({"op": "cross", "to": Road.ID})
	j.step(_goto([st.cell], false))
	j.step({"op": "pickup", "stack": st, "n": n, "hold": sh})
	j.step(_goto([Road.VILLAGE_END], false))
	j.step({"op": "cross", "to": "village"})
	j.step(_goto([dest], false))
	j.step({"op": "haul_drop", "cell": dest, "type": st.type, "n": n, "hold": zh})
	return j


## Whether a party leaving now would ride: the cart waits at the village station, both stations are
## built, and nothing stands on the line in the cut.
func cart_ready() -> bool:
	if cart.is_empty() or cart.state != "parked" or cart.at != "village":
		return false
	var vs := station("village")
	var ms := station("mine")
	return not vs.is_empty() and vs.done and not ms.is_empty() and ms.done and cut_boulders().is_empty()


## The cart adds its room to the packs while the whole line is laid (issue #123).
func cart_adds_room() -> bool:
	return maps.has(Road.ID) and line_complete() and cart_ready()


## Where a rider sits in the cart: side by side along it.
func _seat(r: Dictionary) -> Vector2:
	var i: int = cart.riders.find(r.id)
	return Vector2(cart.x + (i - (cart.riders.size() - 1) / 2.0) * 0.3, Road.LINE_ROW)


## Where a rider steps off the cart.
func _off_cart_cell() -> Vector2i:
	return Vector2i(roundi(cart.x), Road.LINE_ROW)


## One tick of the cart (issues #123, #124): it waits for the whole party, is loaded at the mine end,
## rides the line (pushed at walking pace where there's no track yet), and is unloaded onto the
## village platform.
func _step_cart() -> void:
	if cart.is_empty():
		return
	var ex := expedition
	match cart.state:
		"parked":
			if ex.get("state", "") != "out" or not ex.get("cart", false):
				return
			var home: bool = ex.get("leg", "out") == "home"
			if cart.at != ("mine" if home else "village") or not ex.party.all(func(id): return cart.riders.has(id)):
				return
			if home and not ex.get("cart_loaded", false):
				cart.state = "loading"
				cart.acc = 0.0
				ex.to_load = ex.get("cargo", {}).duplicate()
				return
			cart.state = "moving"
		"loading":
			cart.acc += Tuning.LOAD_RATE * Tuning.DT
			while cart.acc >= 1.0 and not ex.get("to_load", {}).is_empty():
				cart.acc -= 1.0
				var k: String = ex.to_load.keys()[0]
				cart.load[k] = cart.load.get(k, 0) + 1
				ex.to_load[k] -= 1
				if ex.to_load[k] <= 0:
					ex.to_load.erase(k)
				rev += 1
			if ex.get("to_load", {}).is_empty():
				ex.cart_loaded = true
				cart.state = "moving"
		"moving":
			var dir := 1.0 if ex.get("leg", "out") == "out" else -1.0
			var dest := "mine" if dir > 0.0 else "village"
			var c := Vector2i(roundi(cart.x), Road.LINE_ROW)
			var speed := Tuning.CART_SPEED if track_state(Road.segment_at(c.x)) == "built" else Tuning.WALK * ground_speed(c)
			cart.x += dir * speed * Tuning.DT
			var tx := station_x(dest)
			if (dir > 0.0 and cart.x >= tx) or (dir < 0.0 and cart.x <= tx):
				cart.x = tx
				cart.at = dest
				cart.state = "unloading" if dest == "village" and not cart.load.is_empty() else "parked"
				cart.acc = 0.0
				rev += 1
			for id in cart.riders:
				resident(id).pos = _seat(resident(id))
		"unloading":
			cart.acc += Tuning.LOAD_RATE * Tuning.DT
			var spot: Vector2i = Road.STATIONS[cart.at] + Vector2i(1, 0)
			while cart.acc >= 1.0 and not cart.load.is_empty():
				cart.acc -= 1.0
				var k: String = cart.load.keys()[0]
				_drop_cargo(spot, k, 1)
				cart.load[k] -= 1
				if cart.load[k] <= 0:
					cart.load.erase(k)
			if cart.load.is_empty():
				cart.state = "parked"
				ex.cargo_unloaded = true
				rev += 1


## The journey from end to end by cart as the line stands now: a walk to the cart, the ride (pushed at
## walking pace over segments without track), and a walk from it (issue #124).
func route_cart_now() -> float:
	var t := float(Road.STATIONS.village.x + 1 - Road.VILLAGE_END.x) / Tuning.WALK + float(Road.MINE_END.x - Road.STATIONS.mine.x - 1) / Tuning.WALK
	var prev := use_map(Road.ID)
	for x in range(int(station_x("village")), int(station_x("mine"))):
		var c := Vector2i(x, Road.LINE_ROW)
		t += 1.0 / (Tuning.CART_SPEED if track_state(Road.segment_at(x)) == "built" else Tuning.WALK * ground_speed(c))
	use_map(prev)
	return t


# ---------------------------------------------------------------- the party at the site (issue #109)

## Whether a party member is at the site, working it (not on their way home).
func at_site(r: Dictionary) -> bool:
	return expedition.get("state", "") == "out" and expedition.get("leg", "out") == "out" and expedition.party.has(r.id) and r.map == expedition.dest and not r.away


## The packs: what's in them, against what they hold. Meals and spare pickaxes count, as does cargo.
func pack_load() -> int:
	var n: int = expedition.get("tools", []).size()
	for src in [expedition.get("provisions", {}), expedition.get("cargo", {})]:
		for k in src:
			n += src[k]
	return n


func pack_room() -> int:
	return pack_capacity(expedition) - pack_load()


## Room in the packs not yet promised to someone on their way to pack something.
func _room_to_promise() -> int:
	var n := pack_room()
	for r in residents:
		if r.job != null and r.job.kind == "stow":
			n -= r.job.steps[-1].n
	return n


## Meals in the packs the party may eat: all of them if the plan spends the return food, else what's
## left above it.
func spendable_meals() -> int:
	var n := 0
	for k in expedition.get("provisions", {}):
		n += expedition.provisions[k]
	return n if expedition.get("spend_return", false) else maxi(0, n - return_meals(expedition))


## How much of the objective's resource is in the packs.
func objective_packed() -> int:
	return expedition.get("cargo", {}).get(expedition.target.item, 0)


## Items a block of this resource gives when mined.
static func block_yield(item: String) -> int:
	return {"cobble": Tuning.BOULDER_COBBLE, "coal": Tuning.ORE_YIELD.coal, "iron_ore": Tuning.ORE_YIELD.iron}.get(item, 1)


## Whether a block gives the objective's resource: stone, coal or iron ore.
static func gives(b: Dictionary, item: String) -> bool:
	match item:
		"cobble": return not b.has("ore")
		"coal": return b.get("ore", "") == "coal"
		"iron_ore": return b.get("ore", "") == "iron"
	return false


## Eating at the site: a meal from the packs, keeping the return food unless it may be spent.
func _ration_job(r: Dictionary):
	if spendable_meals() <= 0:
		return null
	var j := Job.new("eat", "Going to eat from the packs", "the packs")
	if not on_road(r):  # on the road, they carry the packs
		j.step(_goto([m.entrance], false))
	j.step({"op": "ration"})
	j.step({"op": "work", "what": "eat", "label": "Eating from the packs"})
	return j


## What a party member does at the site, by its orders and without the player: take a spare pickaxe
## from the packs if theirs broke, investigate the vein if that's been chosen, mine what's marked,
## and carry what's mined into the packs. The seriously hurt wait at the entrance.
func _site_job(r: Dictionary):
	var c := rcell(r)
	if r.get("hurt", 0) >= 2:
		var w := Job.new("hurt", "Waiting at the entrance, seriously hurt", "the entrance")
		w.step(_goto([m.entrance], false))
		w.step({"op": "rest_site"})
		return w
	var can_mine: bool = r.get("hurt", 0) == 0
	if can_mine and r.pick == null and not expedition.get("tools", []).is_empty():
		var t := Job.new("equip", "Taking a spare pickaxe from the packs", "the packs")
		t.step(_goto([m.entrance], false))
		t.step({"op": "take_tool"})
		return t
	var pj = _stow_job(r, c)
	if pj != null and (not can_mine or r.pick == null or (pj.target.type == expedition.target.item and objective_packed() < expedition.target.n) or pack_load() + 4 >= pack_capacity(expedition)):
		return pj
	if can_mine and r.pick != null and expedition.get("survey", false) and not residents.any(func(o): return o.job != null and o.job.kind == "survey"):
		var sj = _survey_job(r)
		if sj != null:
			return sj
	if can_mine and r.pick != null:
		var targets := m.boulders.filter(func(b): return b.alive and b.des and b.claim == 0 and not _cooling(b))
		if not targets.is_empty():
			return _tagged(_gather_job(r, nearest(targets, c)), "mine")
	return pj


## Carrying a loose stack at the site into the packs at the entrance.
func _stow_job(r: Dictionary, c: Vector2i):
	var room := _room_to_promise()
	if room <= 0:
		return null
	# The objective's resource until there's enough of it, then anything else mined, then more of it,
	# but only once nothing else is marked to mine, so the packs keep room for what's still to come.
	var item: String = expedition.target.item
	var short: bool = objective_packed() < expedition.target.n
	var working := m.boulders.any(func(b): return b.alive and b.des)
	var loose := stacks_where(func(s): return avail(s) > 0 and (short or s.type != item or not working))
	if loose.is_empty():
		return null
	var rank := func(st: Dictionary) -> int: return (0 if short else 2) if st.type == item else 1
	loose.sort_custom(func(a, b): return rank.call(a) < rank.call(b) or (rank.call(a) == rank.call(b) and manhattan(a.cell, c) < manhattan(b.cell, c)))
	var st: Dictionary = loose[0]
	var n: int = mini(mini(avail(st), carry_cap(r)), room)
	var j := Job.new("stow", "Packing %s" % Defs.ITEMS[st.type].many, "the packs")
	j.target = st
	j.work = "haul"
	st.res += n
	var hd := j.hold({"t": "stack", "stack": st, "n": n})
	j.step(_goto([st.cell], false))
	j.step({"op": "pickup", "stack": st, "n": n, "hold": hd})
	j.step(_goto([m.entrance], false))
	j.step({"op": "stow", "n": n})
	return j


## Marks the objective's resource for mining, nearest the entrance first, a block at a time, until
## what's packed, lying about and marked will make the target (issue #109). Blocks under a known
## loose ceiling are left for the player to choose.
func _mark_objective() -> void:
	var item: String = expedition.target.item
	var have := objective_packed()
	for st in m.items.values():
		if st.type == item:
			have += st.n
	var marked := m.boulders.filter(func(b): return b.alive and b.des and gives(b, item))
	if have + marked.size() * block_yield(item) >= expedition.target.n or marked.size() >= expedition.party.size():
		return
	var free := m.boulders.filter(func(b): return b.alive and not b.des and not b.get("hidden", false) and not b.get("loose", false) and gives(b, item))
	if free.is_empty():
		return
	var b: Dictionary = nearest(free, m.entrance)
	var way := _way_through(b.cell)
	if way.is_empty():
		return
	b = way[0]  # the block itself, or the first boulder in the way to it
	b.des = true
	b.unreach_until = 0
	rev += 1


## The way from the entrance to a block, as the blocks to mine to get there: the first boulder in
## the way and so on, ending with the block itself. Empty when rock or a loose ceiling bars it, or
## another marked block is already being mined toward it.
func _way_through(to: Vector2i) -> Array:
	var blocks := {}
	for b in m.boulders:
		if b.alive and not b.get("hidden", false):
			blocks[b.cell] = b
	var prev := {m.entrance: m.entrance}
	var queue: Array = [m.entrance]
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		if c == to:
			var path: Array = []
			var p := c
			while p != m.entrance:
				if blocks.has(p):
					path.push_front(blocks[p])
				p = prev[p]
			var first: Dictionary = path[0]
			if first.get("loose", false) or (first.des and first.cell != to):
				return []
			return path
		for d in DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not m.in_bounds(n) or m.rock.has(n):
				continue
			if blocks.has(n) and n != to and blocks[n].get("loose", false):
				continue
			prev[n] = c
			queue.append(n)
	return []


## Why the party should head home now, by its return policy (issue #109), or "". A pending choice
## waits for the player first.
func policy_met() -> String:
	var ex := expedition
	if not pending.is_empty():
		return ""
	if ex.policy.get("target", false) and objective_packed() >= ex.target.n:
		return "target reached"
	if ex.policy.get("full", false) and pack_room() <= 0:
		return "packs full"
	if ex.policy.get("low", false) and spendable_meals() <= 0:
		return "provisions low"
	var party: Array = ex.party.map(func(id): return resident(id))
	var busy := party.any(func(r): return r.job != null and r.job.kind in ["gather", "stow", "survey", "eat", "equip"])
	var to_mine := m.boulders.any(func(b): return b.alive and not b.get("hidden", false) and ((b.des and not _cooling(b)) or (not b.get("loose", false) and gives(b, ex.target.item) and not _way_through(b.cell).is_empty())))
	var loose := not stacks_where(func(s): return avail(s) > 0).is_empty() and pack_room() > 0
	if not busy and not to_mine and not loose and not ex.get("survey", false):
		return "nothing left to mine"
	return ""


## Sends the party home from the site, saying why ("target reached", "retreat"...).
func _head_home(why: String) -> void:
	expedition.leg = "home"
	expedition.home_why = why
	for id in expedition.party:
		var r := resident(id)
		fail_job(r)
		r.direct = null
		r.orders.clear()
	_toast("Heading home: %s." % why, expedition.party[0])


## Each tick at the site: mark the objective, and check the return policy once the whole party is there.
func _step_site() -> void:
	if expedition.get("state", "") != "out" or expedition.dest != map_id or expedition.get("leg", "out") != "out":
		return
	if not expedition.party.all(func(id): return at_site(resident(id))):
		return
	if tick % 10 == 0:
		_mark_objective()
		var why := policy_met()
		if why != "":
			_head_home(why)


## The site's stuck reasons (issue #109), which carry its map.
func _stuck_site() -> void:
	if expedition.get("state", "") != "out" or expedition.dest != map_id:
		return
	var party: Array = expedition.party.map(func(id): return resident(id)).filter(func(r): return at_site(r))
	if party.is_empty():
		return
	var at := Vector2(m.entrance) + Vector2(0.5, 0.5)
	var to_mine := m.boulders.any(func(b): return b.alive and b.des)
	if to_mine and party.all(func(r): return r.get("hurt", 0) > 0):
		_add_stuck(m.name, "Everyone is hurt, so nobody can mine. Call them home", at, 1.6, "", 0)
	elif to_mine and not party.any(func(r): return r.pick != null and r.get("hurt", 0) == 0) and expedition.get("tools", []).is_empty():
		_add_stuck(m.name, "No pickaxe left. The party can only pack what's mined; call them home", at, 1.6, "", 0)
	if pack_room() <= 0 and not stacks_where(func(s): return avail(s) > 0).is_empty() and not expedition.policy.get("full", false):
		_add_stuck(m.name, "The packs are full", at, 1.6, "", 0, false, true)
	if expedition.get("survey", false) and not party.any(func(r): return r.pick != null and r.get("hurt", 0) == 0):
		_add_stuck(m.name, "Investigating the vein needs someone with a pickaxe", at, 1.6, "", 0)


# ---------------------------------------------------------------- choices that stop the game (issues #110, #111)

## Asks the player to choose (brief §5): the game pauses until they do. Each option: {id, label, cost}.
func _ask(kind: String, text: String, options: Array, res_id := 0) -> void:
	pending.append({"kind": kind, "text": text, "options": options, "res_id": res_id, "map": map_id})
	events.append({"type": "pause"})
	rev += 1


## Answers the first pending choice with one of its options.
func choose(option: String) -> void:
	if pending.is_empty():
		return
	var p: Dictionary = pending.pop_front()
	var prev := use_map(p.map)
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
	use_map(prev)
	rev += 1


# ---------------------------------------------------------------- hazards and injuries (issue #110)

## Ada, the founder (the PC): she can be hurt, but never seriously (brief §8).
func is_pc(r: Dictionary) -> bool:
	return not residents.is_empty() and residents[0].id == r.id


## Hurts a resident: 1 injured, 2 seriously. A serious injury on an expedition stops the game for the
## player: retreat, or press on without them.
func injure(r: Dictionary, level: int, cause: String) -> void:
	if is_pc(r):
		level = mini(level, 1)
	if level <= r.get("hurt", 0):
		return
	r.hurt = level
	r.heal = Tuning.HEAL_TIME[level]
	if r.job != null:
		fail_job(r)
	stats.injuries = stats.get("injuries", 0) + 1
	if expedition.get("state", "") == "out" and expedition.party.has(r.id):
		expedition.hurt = expedition.get("hurt", {})
		expedition.hurt[r.name] = maxi(expedition.hurt.get(r.name, 0), level)
	rev += 1
	if level == 1:
		_toast("%s was hurt in %s. Injured, %s can't mine and works slower." % [r.name, cause, "she" if is_pc(r) else "they"], r.id)
		return
	_toast("%s is seriously hurt in %s." % [r.name, cause], r.id)
	if at_site(r):
		_ask("injury", "%s is seriously hurt in %s and can't work." % [r.name, cause], [
			{"id": "retreat", "label": "Retreat", "cost": "The party heads home now, with what it has packed."},
			{"id": "press_on", "label": "Press on", "cost": "%s waits at the entrance while the rest keep working." % r.name},
		], r.id)


## A hazard roll, from the sim's seeded random numbers, so a game replays the same.
func _roll(chance: float) -> bool:
	return rng.randf() < chance


## Stepping onto a ledge in the dark can be a fall.
func _ledge_step(r: Dictionary, c: Vector2i) -> void:
	if c in m.ledges and m.is_dark(c) and _roll(Tuning.FALL_CHANCE):
		injure(r, 2 if _roll(Tuning.FALL_SERIOUS) else 1, "a fall in the dark")


## How much slower a resident walks and works: injured, and (for work) in the dark.
static func hurt_speed(r: Dictionary) -> float:
	return Tuning.INJURED_SPEED if r.get("hurt", 0) > 0 else 1.0


## Resting to heal at home: in their own bed, or slower without one.
func _rest_job(r: Dictionary) -> Job:
	var bed = null
	for s in m.sites:
		if s.tpl == "house" and s.done and s.owner == r.id:
			bed = s
	var j := Job.new("rest", "Resting in bed" if bed != null else "Resting, with no bed of their own", "their bed")
	if bed != null:
		j.step(_goto(site_cells(bed), true))
	j.step({"op": "rest", "bed": bed != null})
	return j


## Whether a resident is home and hurt, so resting.
func _has_bed(r: Dictionary) -> bool:
	return maps.village.sites.any(func(s): return s.tpl == "house" and s.done and s.owner == r.id)


func resting(r: Dictionary) -> bool:
	return r.get("hurt", 0) > 0 and r.map == "village" and not r.away and not on_the_way(r) and not in_staging_party(r)


# ---------------------------------------------------------------- the iron discovery (issue #111)

## Mining near the hidden vein finds it: it's revealed, and the game stops for the player to choose.
func _check_find(c: Vector2i) -> void:
	if m.found or m.kind != "site":
		return
	if not m.boulders.any(func(b): return b.alive and b.get("hidden", false) and manhattan(b.cell, c) <= Tuning.FIND_RADIUS):
		return
	_find_vein()
	_toast("The party found iron in the %s." % m.name.to_lower())
	if expedition.get("state", "") == "out" and expedition.dest == map_id:
		_ask("discovery", "The party found an iron vein in the %s." % m.name.to_lower(), [
			{"id": "keep", "label": "Keep mining", "cost": "Carry on for %s. The vein stays marked." % Defs.words(expedition.target.item, expedition.target.n)},
			{"id": "investigate", "label": "Investigate", "cost": "Someone spends about %d s and %d pickaxe uses surveying it. Iron becomes a resource you can send a party for." % [int(Tuning.SURVEY_TIME), Tuning.SURVEY_USES]},
			{"id": "return", "label": "Mark it and return later", "cost": "The party heads home now, with what it has packed."},
		])


## The vein is revealed: it can be seen, marked and mined, though its size isn't known yet.
func _find_vein() -> void:
	m.found = true
	for b in m.boulders:
		b.erase("hidden")
	rev += 1


## Walking to the vein and surveying it, at the cost of time and pickaxe uses.
func _survey_job(r: Dictionary):
	var vein := m.boulders.filter(func(b): return b.alive and b.get("ore", "") == "iron")
	if vein.is_empty():
		expedition.survey = false
		return null
	var j := Job.new("survey", "Going to investigate the vein", "the iron vein")
	j.work = "mine"
	j.step(_goto(vein.map(func(b): return b.cell), true))
	j.step({"op": "work", "what": "survey", "label": "Investigating the vein"})
	return j


## The vein is surveyed: iron is a known resource, with an estimate.
func survey(id: String) -> void:
	var mp: SimMap = maps[id]
	mp.found = true
	mp.discovered = true
	for b in mp.boulders:
		b.erase("hidden")
	rev += 1


# ---------------------------------------------------------------- site maps (issue #102)

## "Boulder", "Coal ore" or "Iron ore".
static func block_name(b: Dictionary) -> String:
	return Defs.ORES[b.ore].name if b.has("ore") else "Boulder"


## Ore blocks of this kind left on a site map, counting hidden ones only once they're found.
func ore_left(id: String, ore: String) -> int:
	var mp: SimMap = maps[id]
	return mp.boulders.filter(func(b): return b.alive and b.get("ore", "") == ore and (mp.discovered or not b.get("hidden", false))).size()


## The site report (brief §8) the expedition board shows before departure:
##   {name, told, visited, travel (seconds), resources: [{item, name, reserve, known}], hazards, access, finds}
## A reserve is the estimated items still to be mined, or -1 for "?". Before anyone has been there,
## the report has only what the village has been told: names, no estimates and no known hazards.
## The iron shows as "?" until it's found, and has no estimate until it's surveyed (issue #111).
func site_report(id: String) -> Dictionary:
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
	var hazards: Array = []
	if mp.visited:
		var dark := 0
		for x in mp.w:
			for y in mp.h:
				if mp.is_dark(Vector2i(x, y)):
					dark += 1
		if dark > 0:
			hazards.append("Dark tunnels past the torches: work there is slower")
		if mp.boulders.any(func(b): return b.alive and b.get("loose", false)):
			hazards.append("Loose ceilings: mining under one can bring it down")
		if not mp.ledges.is_empty():
			hazards.append("A ledge in the dark: someone could fall")
	var finds: Array = []
	if mp.found and not mp.discovered:
		finds.append("Iron vein found, not surveyed")
	return {"name": mp.name, "told": OldMine.TOLD, "visited": mp.visited, "travel": route_walk_time() if route_surveyed() else -1.0,
		"resources": res, "hazards": hazards, "access": OldMine.ACCESS.duplicate() if mp.visited else [], "finds": finds}


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
		"stats": stats.duplicate(), "arrival_at": arrival_at, "arrived": arrived, "auto_craft": auto_craft,
		"rng_state": rng.state, "meadow_sheep": meadow_sheep, "meadow_regrow": meadow_regrow,
		"expedition": expedition.duplicate(true), "pending": pending.duplicate(true), "cart": cart.duplicate(true)}


static func from_state(d: Dictionary) -> Sim:
	var s := Sim.new()
	s.tick = d.tick
	s.next_id = d.next_id
	s.maps = {}
	for id in ["village"] + d.maps.keys().filter(func(k): return k != "village"):  # the village ticks first
		s.maps[id] = SimMap.from_save(d.maps[id])
	s.use_map("village")
	s.stats = d.stats.duplicate()
	s.arrival_at = d.arrival_at
	s.arrived = d.arrived
	s.auto_craft = d.auto_craft
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
	s.meadow_sheep = d.meadow_sheep
	s.meadow_regrow = d.meadow_regrow
	s.expedition = d.get("expedition", {}).duplicate(true)
	s.pending = d.get("pending", []).duplicate(true)
	s.cart = d.get("cart", {}).duplicate(true)
	s._add_site_maps()
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
