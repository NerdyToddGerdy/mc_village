class_name Sim
extends RefCounted
## The Slice 1 simulation: plain data plus fixed-tick logic. No Nodes, no rendering; runs headless.
##
## Views read the public state and call the command methods (designate_mine, place_site, ...).
## Commands apply immediately, so they work while paused. Each tick may append to `events`,
## which the host hands to views and then clears. `rev` increases whenever anything drawn as
## static geometry changes, so views know when to rebuild.

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var w := Tuning.MAP_W
var h := Tuning.MAP_H
var tick := 0
var next_id := 1
var trees: Array = []        ## {id, kind:"tree", cell, logs, alive, des, claim, unreach_until}
var boulders: Array = []     ## {id, kind:"boulder", cell, alive, des, claim, unreach_until}
var sheep: Array = []        ## {id, kind:"sheep", pos, cell, dest, wait, alive, des, claim, unreach_until}
var bushes: Array = []       ## {id, kind:"bush", cell, berries, regrow}: berry bushes (issue #44)
var rng := RandomNumberGenerator.new()  ## Seeded and saved, so a game replays exactly.
var items := {}              ## Vector2i -> {cell, type, n, res}
var zone := {}               ## Vector2i -> true: stockpile cells
var zone_res := {}           ## Vector2i -> resident id hauling into that cell
var farm := {}               ## Vector2i -> {id, kind:"crop", cell, grow, claim, unreach_until}: farm plots (issue #45)
var sites: Array = []        ## Construction sites and finished buildings.
var residents: Array = []
var stats := {"felled": 0, "broken_boulders": 0, "tools_broken": 0, "pick_crafted": false,
	"houses": 0, "traveler_home": false, "division": false}
var arrival_at := -1
var arrived := false
var auto_craft := false      ## Unlocked when the first house is finished.
var stuck: Array = []        ## {who, why, cell (Vector2), height, focus_kind, focus_id, hidden}
var events: Array = []       ## {type: "toast", text, res_id, site_id}
var rev := 0

var _occ := PackedByteArray()
var _occ_dirty := true


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
	s._occ.resize(s.w * s.h)
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
	s.add_resident("Ada", "3E6E7E", OPENING_START + o)
	return s


func add_bush(cell: Vector2i) -> Dictionary:
	var b := {"id": _id(), "kind": "bush", "cell": cell, "berries": Tuning.BUSH_MAX, "regrow": 0.0}
	bushes.append(b)
	return b


func add_sheep(cell: Vector2i) -> Dictionary:
	var sh := {"id": _id(), "kind": "sheep", "pos": Vector2(cell), "cell": cell, "dest": null, "wait": rng.randf_range(Tuning.SHEEP_PAUSE[0], Tuning.SHEEP_PAUSE[1]),
		"alive": true, "des": false, "claim": 0, "unreach_until": 0}
	sheep.append(sh)
	return sh


func _id() -> int:
	next_id += 1
	return next_id - 1


func add_resident(rname: String, shirt: String, cell: Vector2i) -> Dictionary:
	var r := {"id": _id(), "kind": "res", "name": rname, "shirt": shirt, "pos": Vector2(cell),
		"path": [], "job": null, "direct": null, "carry": null, "axe": null, "pick": null,
		"broken": {"axe": false, "pick": false}, "progress": -1.0, "note": null, "arriving": false,
		"orders": [], "hunger": 100.0}
	residents.append(r)
	return r


func resident(id: int) -> Dictionary:
	for r in residents:
		if r.id == id:
			return r
	return {}


func site(id: int) -> Dictionary:
	for s in sites:
		if s.id == id:
			return s
	return {}


# ---------------------------------------------------------------- grid and paths

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func _recompute_occ() -> void:
	_occ.fill(0)
	for t in trees:
		if t.alive:
			_occ[t.cell.y * w + t.cell.x] = 1
	for b in boulders:
		if b.alive:
			_occ[b.cell.y * w + b.cell.x] = 1
	for s in sites:
		if site_blocks(s):
			for c in site_cells(s):
				_occ[c.y * w + c.x] = 1
	_occ_dirty = false


func walkable(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	if _occ_dirty:
		_recompute_occ()
	return _occ[c.y * w + c.x] == 0


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
	var cap := 1 if Defs.is_tool_item(type) else Tuning.STACK
	var seen := {c: true}
	var queue: Array = [c]
	var qi := 0
	while n > 0 and qi < queue.size() and qi < 400:
		var cur: Vector2i = queue[qi]
		qi += 1
		if walkable(cur):
			var s = items.get(cur)
			if s == null:
				var m := mini(n, cap)
				items[cur] = {"cell": cur, "type": type, "n": m, "res": 0}
				if cap == 1:
					items[cur].dur = full_uses(type) if uses < 0 else uses
				n -= m
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
	for k in items:
		if pred.call(items[k]):
			out.append(items[k])
	return out


static func avail(s: Dictionary) -> int:
	return s.n - s.res


## Unreserved items of a type anywhere on the map.
func free_count(type: String) -> int:
	var n := 0
	for k in items:
		var s: Dictionary = items[k]
		if s.type == type:
			n += avail(s)
	return n


func tool_items(kind: String, min_tier: int) -> Array:
	return stacks_where(func(s): return Defs.ITEMS[s.type].get("tool", "") == kind and Defs.ITEMS[s.type].tier > min_tier and avail(s) > 0)


func in_zone(c: Vector2i) -> bool:
	return zone.has(c)


# ---------------------------------------------------------------- sites

func site_cells(s: Dictionary) -> Array:
	var out: Array = []
	for x in range(s.origin.x, s.origin.x + s.size.x):
		for y in range(s.origin.y, s.origin.y + s.size.y):
			out.append(Vector2i(x, y))
	return out


func site_blocks(s: Dictionary) -> bool:
	return s.done or (s.tpl == "house" and s.stage >= 1)


func site_at(c: Vector2i):
	for s in sites:
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
	for s in sites:
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
	for t in trees:
		if t.alive and rect.has_point(t.cell):
			out.trees.append(t)
	for b in boulders:
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
func bench_active(b: Dictionary) -> int:
	for i in b.queue.size():
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
func bench_craftable(b: Dictionary) -> Dictionary:
	for id in b.queue:
		var rec := Defs.recipe(id)
		if has_all(b.store, rec.inp):
			return rec
	return {}


## Materials a site (or a finished bench's active recipe) still needs delivered.
func stage_needs(s: Dictionary) -> Dictionary:
	var cost := {}
	if s.done:
		var ai := bench_active(s)
		if ai >= 0:
			cost = Defs.recipe(s.queue[ai]).inp
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
		zone.erase(c)
		if items.has(c):
			var it: Dictionary = items[c]
			items.erase(c)
			drop_items(exit, it.type, it.n, it.get("dur", -1))
	bushes = bushes.filter(func(b): return not Rect2i(s.origin, s.size).has_point(b.cell))
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
	stats.houses += 1
	var ada: Dictionary = residents[0]
	var ada_home := false
	for o in sites:
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
	var i: int = b.queue.size() if at < 0 else at
	b.queue.insert(i, recipe_id)
	b.autoq.insert(i, auto)
	if auto_craft:
		expand_queues()


func queue_remove(b: Dictionary, i: int) -> void:
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
	for b in sites:
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


## The fireplace's standing order (spec §4): while stored meals are fewer than MEAL_STOCK, queue
## one meal whose inputs exist, bread first. One at a time, so it never queues what it can't make.
func keep_meals_stocked() -> void:
	var meals := 0
	for m in Defs.MEALS:
		meals += free_count(m)
	for f in sites:
		if not (f.done and f.tpl == "fireplace" and f.get("keep_meals", true)):
			continue
		if f.autoq.has(true):
			meals += 1  # already making one
			continue
		if meals >= Tuning.MEAL_STOCK:
			continue
		for id in Defs.MEALS.map(func(m): return Defs.producer(m, "fireplace").id):
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
	j.target = target
	target.claim = r.id
	j.hold({"t": "claim", "ent": target})
	var cur: int = r[kind].tier if r[kind] != null else 0
	var better := tool_items(kind, cur)
	if not better.is_empty():
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
	for k in items:
		var s: Dictionary = items[k]
		if not Tuning.FOOD_VALUE.has(s.type) or avail(s) <= 0:
			continue
		if s.type == "mutton":  # raw mutton is for the fireplace; eaten only in a pinch
			if raw.is_empty() or manhattan(s.cell, c) < manhattan(raw.stack.cell, c):
				raw = {"kind": "stack", "stack": s}
			continue
		if manhattan(s.cell, c) < bd:
			bd = manhattan(s.cell, c)
			best = {"kind": "stack", "stack": s}
	for b in bushes:
		if b.berries > 0 and manhattan(b.cell, c) < bd:
			bd = manhattan(b.cell, c)
			best = {"kind": "bush", "bush": b}
	return raw if best.is_empty() else best


func food_available() -> bool:
	return not _nearest_food(Vector2i.ZERO).is_empty()


## Go and eat (issue #44): pick up the nearest food and eat it, or eat berries off a bush until
## nearly full or the bush is bare.
func _eat_job(r: Dictionary):
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
	for k in farm:
		var crop: Dictionary = farm[k]
		if crop.claim != 0 or _cooling(crop) or not walkable(crop.cell):
			continue
		if crop_ripe(crop):
			ripe.append(crop)
		elif crop.grow < 0.0 and not items.has(crop.cell):  # the last harvest is collected first
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
	j.target = s
	s.builder = r.id
	j.hold({"t": "builder", "site": s})
	var label: String = "Building " + current_stage(s).name.to_lower()
	if s.tpl == "bench":
		label = "Building the bench"
	elif s.tpl == "fireplace":
		label = "Building the fireplace"
	j.step(_goto(site_cells(s), true))
	j.step({"op": "work", "what": "build", "site": s, "label": label})
	return j


func _craft_job(r: Dictionary, b: Dictionary, rec: Dictionary) -> Job:
	var where: String = "the bench" if b.tpl == "bench" else "the " + Defs.TEMPLATES[b.tpl].name.to_lower()
	var j := Job.new("craft", "Going to " + where, where)
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
	zone_res[dest] = r.id
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
				if zone_res.get(hd.cell, 0) == r.id:
					zone_res.erase(hd.cell)
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
		stats.tools_broken += 1
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
			var step_len := Tuning.WALK * Tuning.DT
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
			var step_len := Tuning.WALK * Tuning.DT
			if dist <= step_len:
				r.pos = Vector2(nxt)
				r.path.pop_front()
				return r.path.is_empty()
			r.pos += to / dist * step_len
			return false
		"pickup":
			var s = items.get(st.stack.cell)
			if not is_same(s, st.stack) or s.n < st.n:
				return "gone"
			s.n -= st.n
			s.res -= st.n
			j.holds.erase(st.hold)
			if s.n <= 0:
				items.erase(s.cell)
			r.carry = {"type": s.type, "n": st.n}
			if s.has("dur"):
				r.carry.dur = s.dur
			rev += 1
			return true
		"pickup_tool":
			var s = items.get(st.stack.cell)
			if not is_same(s, st.stack) or s.n < 1:
				return "gone"
			s.n -= 1
			s.res -= 1
			j.holds.erase(st.hold)
			if s.n <= 0:
				items.erase(s.cell)
			var it: Dictionary = Defs.ITEMS[s.type]
			var old = r[it.tool]
			if old != null:
				drop_items(s.cell, old.type, 1, old.dur)
			r[it.tool] = {"type": s.type, "tier": it.tier, "dur": s.dur}
			r.broken[it.tool] = false
			rev += 1
			return true
		"deposit":
			var dest: Dictionary = st.site
			dest.incoming[st.type] -= st.n
			dest.store[st.type] = dest.store.get(st.type, 0) + st.n
			j.holds.erase(st.hold)
			r.carry = null
			return true
		"haul_drop":
			zone_res.erase(st.cell)
			j.holds.erase(st.hold)
			drop_items(st.cell, st.type, st.n, r.carry.get("dur", -1))
			r.carry = null
			return true
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
			return Tuning.STAGE_TIME
		"hunt":
			return Tuning.HUNT_TIME
		"plant":
			return Tuning.PLANT_TIME
		"harvest":
			return Tuning.HARVEST_TIME
		"eat", "graze":
			return Tuning.EAT_TIME
		_:
			match st.get("recipe", {}).get("id", ""):
				"bread": return Tuning.BAKE_TIME
				"cooked_mutton": return Tuning.COOK_TIME
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
				drop_items(t.cell, "log", t.logs)
				stats.felled += 1
			else:
				drop_items(t.cell, "cobble", Tuning.BOULDER_COBBLE)
				stats.broken_boulders += 1
			_wear(r, st.tool)
		"eat":
			if r.carry == null:
				return "gone"
			r.hunger = minf(100.0, r.hunger + Tuning.FOOD_VALUE.get(r.carry.type, 0.0))
			r.carry = null
		"graze":
			var bush: Dictionary = st.target
			if bush.berries <= 0 or not bushes.has(bush):
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
			if not is_same(farm.get(crop.cell), crop) or crop.grow >= 0.0 or items.has(crop.cell):
				return "gone"
			crop.grow = 0.0
			stats.planted = stats.get("planted", 0) + 1
			rev += 1
		"harvest":
			var crop: Dictionary = st.target
			if not is_same(farm.get(crop.cell), crop) or not crop_ripe(crop):
				return "gone"
			crop.grow = -1.0
			drop_items(crop.cell, "wheat", Tuning.WHEAT_YIELD)
			stats.harvested = stats.get("harvested", 0) + 1
			rev += 1
		"build":
			_complete_stage(st.site)
		"craft":
			var b: Dictionary = st.site
			var rec: Dictionary = st.recipe
			var qi: int = b.queue.find(rec.id)
			if qi < 0 or not has_all(b.store, rec.inp):
				return "gone"
			for k in rec.inp:
				b.store[k] -= rec.inp[k]
			b.queue.remove_at(qi)
			b.autoq.remove_at(qi)
			for o in rec.out:
				drop_items(rcell(r), o, rec.out[o])
				if Defs.ITEMS[o].get("tool", "") == "pick":
					stats.pick_crafted = true
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
			r.job = j
			return
	if r.hunger < Tuning.EAT_BELOW:
		var ej = _eat_job(r)
		if ej != null:
			r.job = ej
			return
	var c := rcell(r)
	if auto_craft:
		expand_queues()
	keep_meals_stocked()
	var benches := sites.filter(func(s): return s.done and is_station(s) and not s.queue.is_empty() and s.crafter == 0 and not bench_craftable(s).is_empty() and not _cooling(s))
	if not benches.is_empty():
		var b: Dictionary = _nearest_site(benches, c)
		r.job = _craft_job(r, b, bench_craftable(b))
		return
	if _try_deliver(r, c, sites.filter(func(s): return s.done and is_station(s) and not s.queue.is_empty())):
		return
	var ready := sites.filter(func(s): return not s.done and s.builder == 0 and has_all(s.store, current_stage(s).cost) and not _cooling(s) and footprint_clear(s))
	if not ready.is_empty():
		r.job = _build_job(r, _nearest_site(ready, c))
		return
	if _try_deliver(r, c, sites.filter(func(s): return not s.done and footprint_clear(s))):
		return
	var crop = _farm_work(c)
	if crop != null:
		r.job = _farm_job(r, crop)
		return
	var targets: Array = []
	if not r.broken.axe or not tool_items("axe", 0).is_empty():
		for t in trees:
			if t.alive and t.des and t.claim == 0 and not _cooling(t):
				targets.append(t)
	if r.pick != null or not tool_items("pick", 0).is_empty():
		for b in boulders:
			if b.alive and b.des and b.claim == 0 and not _cooling(b):
				targets.append(b)
	for sh in sheep:
		if sh.alive and sh.des and sh.claim == 0 and not _cooling(sh):
			targets.append(sh)
	if not targets.is_empty():
		var t: Dictionary = nearest(targets, c)
		r.job = _hunt_job(r, t) if t.kind == "sheep" else _gather_job(r, t)
		return
	if zone.is_empty():
		return
	var loose := stacks_where(func(s): return avail(s) > 0 and not in_zone(s.cell))
	loose.sort_custom(func(a, b): return manhattan(a.cell, c) < manhattan(b.cell, c))
	for ls in loose:
		var dest = zone_dest(ls.type)
		if dest == null:
			continue
		var cap := 1 if Defs.is_tool_item(ls.type) else Tuning.STACK
		var here = items.get(dest)
		var room: int = cap - (here.n if here != null else 0)
		r.job = _haul_job(r, ls, dest, mini(mini(avail(ls), Tuning.CARRY), room))
		return


func _try_deliver(r: Dictionary, c: Vector2i, dests: Array) -> bool:
	for s in dests:
		if _cooling(s):
			continue
		var need := stage_needs(s)
		for t in need:
			var src := stacks_where(func(st): return st.type == t and avail(st) > 0 and not _on_finished_bench(st, s))
			if src.is_empty():
				continue
			var st: Dictionary = nearest(src, c)
			r.job = _deliver_job(s, t, mini(mini(need[t], Tuning.CARRY), avail(st)), st)
			return true
	return false


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
	var cap := 1 if Defs.is_tool_item(type) else Tuning.STACK
	var empty = null
	for c in zone:
		if zone_res.has(c) or not walkable(c):
			continue
		var it = items.get(c)
		if it != null and it.type == type and it.n < cap:
			return c
		if it == null and empty == null:
			empty = c
	return empty


# ---------------------------------------------------------------- tick

func step() -> void:
	tick += 1
	for b in bushes:
		if b.berries < Tuning.BUSH_MAX:
			b.regrow += Tuning.DT
			if b.regrow >= Tuning.BUSH_REGROW:
				b.regrow = 0.0
				b.berries += 1
				rev += 1
	for k in farm:
		var crop: Dictionary = farm[k]
		if crop.grow >= 0.0 and crop.grow < Tuning.WHEAT_GROW:
			var before := crop_stage(crop)
			crop.grow = minf(Tuning.WHEAT_GROW, crop.grow + Tuning.DT)
			if crop_stage(crop) != before:
				rev += 1
	var hunger_drop := 100.0 / Tuning.HUNGER_EMPTY_TIME * Tuning.DT
	for r in residents:
		if not r.get("away", false):
			r.hunger = maxf(0.0, r.hunger - hunger_drop)
	for sh in sheep:
		if sh.alive:
			_step_sheep(sh)
	for r in residents:
		_step_resident(r)
	_step_arrivals()
	var kinds := {}
	var working := 0
	for r in residents:
		if r.job != null and r.job.kind != "move" and r.job.kind != "arrive":
			kinds[r.job.kind] = true
			working += 1
	if working >= 2 and kinds.size() >= 2:
		stats.division = true
	if auto_craft and tick % 10 == 0:
		expand_queues()
	if tick % 10 == 0:
		keep_meals_stocked()
	if tick % 10 == 0:
		for s in sites:
			if not s.done:
				_mark_obstacles(s)
	if tick % 5 == 0:
		compute_stuck()


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
	elif res is String:
		fail_job(r, res)


## Travelers, in the order they arrive. The first is always Tomas.
const TRAVELERS := [["Tomas", "8C4F6B"], ["Mira", "6B7F3A"], ["Jonas", "8A6A2E"], ["Elsa", "4F6A8C"],
	["Bram", "7A4A6E"], ["Ines", "3E7E6A"], ["Otto", "8C5A3E"], ["Lena", "5E5A8C"]]


## A finished house whose bed nobody sleeps in yet, or null.
func free_house():
	for s in sites:
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
	walk_in(t)
	_toast("A traveler named %s has arrived." % t.name, t.id)


func walk_in(t: Dictionary) -> void:
	t.arriving = false
	for s in sites:
		if s.tpl == "house" and s.done and s.owner == 0:
			t.arriving = true
			var j := Job.new("arrive", "Walking to the new house", "the new house")
			j.hold({"t": "arriving"})
			j.step(_goto(site_cells(s), true))
			j.step({"op": "move_in", "site": s})
			t.job = j
			return


func _toast(text: String, res_id := 0, site_id := 0) -> void:
	events.append({"type": "toast", "text": text, "res_id": res_id, "site_id": site_id})


# ---------------------------------------------------------------- stuck reasons

func _add_stuck(who: String, why: String, at: Vector2, height: float, fk: String, fid: int, hidden := false) -> void:
	stuck.append({"who": who, "why": why, "cell": at, "height": height, "focus_kind": fk, "focus_id": fid, "hidden": hidden})


func compute_stuck() -> void:
	stuck = []
	var any_pick := not tool_items("pick", 0).is_empty()
	for r in residents:
		if r.pick != null:
			any_pick = true
	var first := true
	for b in boulders:
		if b.alive and b.des and not any_pick:
			_add_stuck("Boulder", "Needs a pickaxe", Vector2(b.cell) + Vector2(0.5, 0.5), 1.1, "boulder", b.id, not first)
			first = false
	for s in sites:
		var tpl: Dictionary = Defs.TEMPLATES[s.tpl]
		var mid := Vector2(s.origin) + Vector2(s.size) / 2.0
		if not s.done and not footprint_clear(s):
			var ob := site_obstacles(s)
			var nb: int = ob.boulders.size()
			if nb and not any_pick:
				_add_stuck(tpl.name, "Needs a pickaxe to clear " + ("a boulder" if nb == 1 else "%d boulders" % nb), mid, 0.6, "site", s.id)
			continue
		var cost := {}
		var label := ""
		var verb := "needs"
		if not s.done:
			var st := current_stage(s)
			cost = st.cost
			label = "Bench" if s.tpl == "bench" else st.name
			verb = st.verb
		elif is_station(s) and not s.queue.is_empty() and s.crafter == 0 and bench_craftable(s).is_empty() and bench_active(s) < 0:
			var rec := Defs.recipe(s.queue[0])
			cost = rec.inp
			label = rec.name
		else:
			continue
		var worst := ""
		var worst_n := 0
		for k in cost:
			var short: int = cost[k] - s.store.get(k, 0) - s.incoming.get(k, 0) - free_count(k)
			if short > worst_n:
				worst = k
				worst_n = short
		if worst_n > 0:
			var it: Dictionary = Defs.ITEMS[worst]
			var why := "%s %s %d more %s" % [label, verb, worst_n, it.one if worst_n == 1 else it.many]
			if label == "Bed":
				why = "House needs a bed: %d more %s" % [worst_n, it.one if worst_n == 1 else it.many]
			_add_stuck(tpl.name, why,
				mid, site_height(s) + 0.4, "site", s.id)
	var has_food := food_available()
	for r in residents:
		var at: Vector2 = r.pos + Vector2(0.5, 0.5)
		if r.hunger <= 0.0 and not has_food:
			_add_stuck(r.name, "Starving: no food stored", at, 1.6, "res", r.id)
		elif r.hunger < Tuning.HUNGRY_BELOW and not has_food:
			_add_stuck(r.name, "Hungry: no food stored", at, 1.6, "res", r.id)
		for k in ["axe", "pick"]:
			if r.broken[k] and r[k] == null:
				var tname := "Axe" if k == "axe" else "Pickaxe"
				_add_stuck(r.name, "%s broke. Needs a new %s" % [tname, tname.to_lower()], at, 1.6, "res", r.id)
		if r.note != null and r.note.until > tick:
			_add_stuck(r.name, r.note.text, at, 1.6, "res", r.id)
	if zone.is_empty():
		for k in farm:
			if farm[k].grow < 0.0 and items.has(k):
				_add_stuck("Farm", "Harvested wheat needs a stockpile before replanting", Vector2(k) + Vector2(0.5, 0.5), 0.6, "crop", farm[k].id)
				break
	if not zone.is_empty():
		var loose := stacks_where(func(s): return avail(s) > 0 and not in_zone(s.cell))
		var full := not loose.is_empty()
		for s in loose:
			if zone_dest(s.type) != null:
				full = false
				break
		if full:
			_add_stuck("Stockpile", "Stockpile is full", Vector2(zone.keys()[0]) + Vector2(0.5, 0.5), 0.6, "", 0)


func site_height(s: Dictionary) -> float:
	if s.tpl == "bench":
		return 0.75 if s.done else 0.2
	if s.tpl == "fireplace":
		return 0.7 if s.done else 0.2
	return [0.2, 0.5, 2.5, 4.0, 4.0][mini(s.stage, 4)]


# ---------------------------------------------------------------- commands

## Marks every tree and boulder in `rect` to be mined; `kinds` can limit it to "tree" or "boulder"
## (issue #7). A single click on an already-marked one (pass it as `single`) unmarks it instead.
func designate_mine(rect: Rect2i, single = null, kinds := ["tree", "boulder"]) -> void:
	var hit: Array = []
	if single != null:
		hit = [single]
	else:
		var pool: Array = (trees if kinds.has("tree") else []) + (boulders if kinds.has("boulder") else [])
		for o in pool:
			if o.alive and rect.has_point(o.cell):
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
	var hit: Array = [single] if single != null else sheep.filter(func(sh): return sh.alive and rect.has_point(sh.cell))
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
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var c := Vector2i(x, y)
			if walkable(c) and site_at(c) == null and not farm.has(c) and reserved_at(c) == null:
				zone[c] = true
	rev += 1


## Why a cell can't be a farm plot, or "" when it can: farms go on open grass only (issue #45).
func farm_blocked(c: Vector2i) -> String:
	if not walkable(c):
		return "not open ground"
	if site_at(c) != null:
		return "a building"
	if farm.has(c):
		return "a farm plot"
	if zone.has(c):
		return "a stockpile"
	if reserved_at(c) != null:
		return "a reserved plot"
	for b in bushes:
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
			farm[c] = {"id": _id(), "kind": "crop", "cell": c, "grow": -1.0, "claim": 0, "unreach_until": 0}
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
	var crop = farm.get(c)
	if crop == null:
		return
	if crop.claim != 0:
		var r := resident(crop.claim)
		if not r.is_empty() and r.job != null and is_same(r.job.target, crop):
			fail_job(r)
	farm.erase(c)


## Why a blueprint can't go here, or "" when it can. Trees, boulders, stockpile cells and farm plots
## don't block placement: the blueprint clears them (spec §8). Reserved plots do, and a job
## building's own plot needs room too (Slice 2 spec §8).
func placement_check(tpl: String, origin: Vector2i, rot := 0) -> String:
	var size: Vector2i = Defs.TEMPLATES[tpl].size
	var foot := Rect2i(origin, size)
	if origin.x < 0 or origin.y < 0 or origin.x + size.x > w or origin.y + size.y > h:
		return "Too close to the edge"
	for s in sites:
		if Rect2i(s.origin, s.size).intersects(foot):
			return "Overlaps another building"
	for s in sites:
		if s.get("plot") != null and s.plot.intersects(foot):
			return "Overlaps a reserved plot"
	var plot = plot_rect(tpl, origin, rot)
	if plot != null:
		var no_room := "Not enough room to grow into a %s" % Defs.TEMPLATES[tpl].plot
		if not Rect2i(0, 0, w, h).encloses(plot):
			return no_room
		for s in sites:
			if Rect2i(s.origin, s.size).intersects(plot) or (s.get("plot") != null and s.plot.intersects(plot)):
				return no_room
	return ""


func place_site(tpl: String, origin: Vector2i, rot := 0) -> Dictionary:
	var s := {"id": _id(), "kind": "site", "tpl": tpl, "origin": origin, "size": Defs.TEMPLATES[tpl].size,
		"rot": rot, "stage": 0, "store": {}, "incoming": {}, "builder": 0, "crafter": 0, "crafting": "",
		"done": false, "owner": 0, "queue": [], "autoq": [], "unreach_until": 0,
		"plot": plot_rect(tpl, origin, rot)}
	if tpl == "fireplace":
		s.keep_meals = true
	sites.append(s)
	_occ_dirty = true
	for c in site_cells(s):
		zone.erase(c)
		_drop_crop(c)
	if s.plot != null:  # the reserved plot is kept clear of stockpiles and farms
		for x in range(s.plot.position.x, s.plot.end.x):
			for y in range(s.plot.position.y, s.plot.end.y):
				zone.erase(Vector2i(x, y))
				_drop_crop(Vector2i(x, y))
	_mark_obstacles(s)
	rev += 1
	return s


## Turns the fireplace's "Keep meals in stock" standing order on or off.
func set_keep_meals(f: Dictionary, on: bool) -> void:
	f.keep_meals = on
	if not on:
		for i in range(f.queue.size() - 1, -1, -1):
			if f.autoq[i]:
				queue_remove(f, i)
	rev += 1


func cancel_site(s: Dictionary) -> void:
	for r in residents:
		if r.job != null and is_same(r.job.target, s):
			fail_job(r)
	for k in s.store:
		if s.store[k] > 0:
			drop_items(s.origin + Vector2i(0, s.size.y), k, s.store[k])
	sites.erase(s)
	_occ_dirty = true
	rev += 1


## Right-click order for one resident: mine a tree or boulder, or walk to a cell. It replaces
## whatever they're doing and any queued orders.
func direct_order(r: Dictionary, target = null, cell = null) -> void:
	if r.arriving:
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
		r.direct = _gather_job(r, target)
	elif target != null and target.kind == "sheep":
		target.des = true
		target.unreach_until = 0
		rev += 1
		if target.claim != 0 and target.claim != r.id:
			var o := resident(target.claim)
			if not o.is_empty() and o.job != null and is_same(o.job.target, target):
				fail_job(o)
		r.direct = _hunt_job(r, target)
	elif cell != null and walkable(cell):
		r.direct = _move_job(cell)


## Shift + right-click: adds an order to the end of the resident's list. Orders run one after
## another once their current work is done, then the resident goes back to claiming jobs.
func queue_order(r: Dictionary, target = null, cell = null) -> void:
	if r.arriving:
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
		for sh in sheep:
			if sh.id == o.id:
				return _hunt_job(r, sh) if sh.alive and (sh.claim == 0 or sh.claim == r.id) else null
		return null
	var list := trees if o.target_kind == "tree" else boulders
	for t in list:
		if t.id != o.id:
			continue
		if not t.alive or (t.claim != 0 and t.claim != r.id):
			return null
		if t.kind == "boulder" and r.pick == null and tool_items("pick", 0).is_empty():
			r.note = {"text": "Needs a pickaxe", "until": tick + 5 * Tuning.TPS}
			return null
		return _gather_job(r, t)
	return null


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
	var items_out := {}
	for k in items:
		var it: Dictionary = items[k].duplicate()
		it.res = 0
		items_out[k] = it
	var sites_out: Array = []
	for s in sites:
		var c: Dictionary = s.duplicate(true)
		c.incoming = {}
		c.builder = 0
		c.crafter = 0
		c.crafting = ""
		sites_out.append(c)
	return {"w": w, "h": h, "tick": tick, "next_id": next_id, "trees": trees.duplicate(true), "boulders": boulders.duplicate(true),
		"items": items_out, "zone": zone.duplicate(), "sites": sites_out, "residents": res_out,
		"stats": stats.duplicate(), "arrival_at": arrival_at, "arrived": arrived, "auto_craft": auto_craft,
		"sheep": sheep.duplicate(true), "rng_state": rng.state, "bushes": bushes.duplicate(true),
		"farm": farm.duplicate(true)}


static func from_state(d: Dictionary) -> Sim:
	var s := Sim.new()
	s.w = d.w
	s.h = d.h
	s._occ.resize(s.w * s.h)
	s.tick = d.tick
	s.next_id = d.next_id
	s.trees = d.trees.duplicate(true)
	s.boulders = d.boulders.duplicate(true)
	s.items = d.items.duplicate(true)
	s.zone = d.zone.duplicate()
	s.sites = d.sites.duplicate(true)
	s.stats = d.stats.duplicate()
	s.arrival_at = d.arrival_at
	s.arrived = d.arrived
	s.auto_craft = d.auto_craft
	s.sheep = d.sheep.duplicate(true)
	# Bushes added to older saves (v7) may sit where something now stands; drop those.
	s.bushes = d.bushes.duplicate(true).filter(func(b):
		for o in s.trees + s.boulders:
			if o.alive and o.cell == b.cell:
				return false
		for st in s.sites:
			if Rect2i(st.origin, st.size).has_point(b.cell):
				return false
		return true)
	s.rng.state = d.rng_state
	s.farm = d.farm.duplicate(true)
	for o in s.trees + s.boulders + s.sheep + s.farm.values():
		o.claim = 0
		o.unreach_until = 0
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
		if r.carry != null:
			s.drop_items(rcell(r), r.carry.type, r.carry.n, r.carry.get("dur", -1))
			r.carry = null
		if r.arriving:
			s.walk_in(r)
	s.compute_stuck()
	return s
