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
var items := {}              ## Vector2i -> {cell, type, n, res}
var zone := {}               ## Vector2i -> true: stockpile cells
var zone_res := {}           ## Vector2i -> resident id hauling into that cell
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

static func new_game() -> Sim:
	var s := Sim.new()
	s._occ.resize(s.w * s.h)
	var tree_spots := [[2, 9], [3, 13], [12, 2], [2, 3], [6, 12], [15, 6], [9, 15], [15, 13], [6, 2], [16, 9], [13, 16], [1, 16], [9, 2], [4, 6]]
	for i in tree_spots.size():
		var p: Array = tree_spots[i]
		s.trees.append({"id": s._id(), "kind": "tree", "cell": Vector2i(p[0], p[1]), "logs": 4 + (i * 7) % 3,
			"alive": true, "des": false, "claim": 0, "unreach_until": 0})
	for p in [[11, 12], [14, 10], [7, 5], [10, 4], [16, 3], [7, 16]]:
		s.boulders.append({"id": s._id(), "kind": "boulder", "cell": Vector2i(p[0], p[1]),
			"alive": true, "des": false, "claim": 0, "unreach_until": 0})
	s.add_resident("Ada", "3E6E7E", Vector2i(9, 9))
	return s


func _id() -> int:
	next_id += 1
	return next_id - 1


func add_resident(rname: String, shirt: String, cell: Vector2i) -> Dictionary:
	var r := {"id": _id(), "kind": "res", "name": rname, "shirt": shirt, "pos": Vector2(cell),
		"path": [], "job": null, "direct": null, "carry": null, "axe": null, "pick": null,
		"broken": {"axe": false, "pick": false}, "progress": -1.0, "note": null, "arriving": false}
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

## Places items on or near `c`, filling the cell and spreading outward over walkable cells.
func drop_items(c: Vector2i, type: String, n: int) -> void:
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
			drop_items(exit, it.type, it.n)
	for r in residents:
		var c := rcell(r)
		if Rect2i(s.origin, s.size).has_point(c):
			var p = nearest_walkable(c)
			if p != null:
				r.pos = Vector2(p)
				r.path = []


func _on_site_done(s: Dictionary) -> void:
	if s.tpl == "bench":
		_toast("The crafting bench is ready. Select it to queue crafts.", 0, s.id)
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
	elif not arrived and arrival_at < 0:
		arrival_at = tick + int(Tuning.ARRIVAL_DELAY * Tuning.TPS)
		_toast("The second house is finished. Someone may come to live in it.", 0, s.id)


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
		if not (b.done and b.tpl == "bench") or b.queue.is_empty():
			continue
		for _guard in 12:
			if b.queue.size() >= 30:
				break
			var inserted := false
			for i in b.queue.size():
				var inp: Dictionary = Defs.recipe(b.queue[i]).inp
				for k in inp:
					var p := Defs.producer(k)
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


func _fetch_tool(j: Job, stack: Dictionary) -> void:
	stack.res += 1
	var hd := j.hold({"t": "stack", "stack": stack, "n": 1})
	j.step(_goto([stack.cell], false))
	j.step({"op": "pickup_tool", "stack": stack, "hold": hd})


func _deliver_job(dest: Dictionary, type: String, n: int, stack: Dictionary) -> Job:
	var dest_name: String = "bench" if dest.done else Defs.TEMPLATES[dest.tpl].name.to_lower()
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
	var label: String = "Building the bench" if s.tpl == "bench" else "Building " + current_stage(s).name.to_lower()
	j.step(_goto(site_cells(s), true))
	j.step({"op": "work", "what": "build", "site": s, "label": label})
	return j


func _craft_job(r: Dictionary, b: Dictionary, rec: Dictionary) -> Job:
	var j := Job.new("craft", "Going to the bench", "the bench")
	j.target = b
	b.crafter = r.id
	b.crafting = rec.name
	j.hold({"t": "crafter", "site": b})
	j.step(_goto(site_cells(b), true))
	j.step({"op": "work", "what": "craft", "site": b, "recipe": rec, "label": "Crafting " + rec.name.to_lower()})
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
		drop_items(rcell(r), r.carry.type, r.carry.n)
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
				drop_items(s.cell, old.type, 1)
			r[it.tool] = {"type": s.type, "tier": it.tier, "dur": Tuning.DURABILITY[it.tier]}
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
			drop_items(st.cell, st.type, st.n)
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
		_:
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
	if r.direct != null:
		r.job = r.direct
		r.direct = null
		return
	var c := rcell(r)
	if auto_craft:
		expand_queues()
	var benches := sites.filter(func(s): return s.done and s.tpl == "bench" and not s.queue.is_empty() and s.crafter == 0 and not bench_craftable(s).is_empty() and not _cooling(s))
	if not benches.is_empty():
		var b: Dictionary = _nearest_site(benches, c)
		r.job = _craft_job(r, b, bench_craftable(b))
		return
	if _try_deliver(r, c, sites.filter(func(s): return s.done and s.tpl == "bench" and not s.queue.is_empty())):
		return
	var ready := sites.filter(func(s): return not s.done and s.builder == 0 and has_all(s.store, current_stage(s).cost) and not _cooling(s) and footprint_clear(s))
	if not ready.is_empty():
		r.job = _build_job(r, _nearest_site(ready, c))
		return
	if _try_deliver(r, c, sites.filter(func(s): return not s.done and footprint_clear(s))):
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
	if not targets.is_empty():
		r.job = _gather_job(r, nearest(targets, c))
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
	for r in residents:
		_step_resident(r)
	if arrival_at >= 0 and not arrived and tick >= arrival_at:
		_arrive()
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
		for s in sites:
			if not s.done:
				_mark_obstacles(s)
	if tick % 5 == 0:
		compute_stuck()


func _step_resident(r: Dictionary) -> void:
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


func _arrive() -> void:
	arrived = true
	var spawn := Vector2i(0, h - 1)
	if not walkable(spawn):
		spawn = nearest_walkable(spawn)
	var t := add_resident("Tomas", "8C4F6B", spawn)
	walk_in(t)
	_toast("A traveler named Tomas has arrived.", t.id)


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
		elif s.tpl == "bench" and not s.queue.is_empty() and s.crafter == 0 and bench_craftable(s).is_empty() and bench_active(s) < 0:
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
			_add_stuck("Crafting bench" if s.done else tpl.name,
				"%s %s %d more %s" % [label, verb, worst_n, it.one if worst_n == 1 else it.many],
				mid, site_height(s) + 0.4, "site", s.id)
	for r in residents:
		var at: Vector2 = r.pos + Vector2(0.5, 0.5)
		for k in ["axe", "pick"]:
			if r.broken[k] and r[k] == null:
				var tname := "Axe" if k == "axe" else "Pickaxe"
				_add_stuck(r.name, "%s broke. Needs a new %s" % [tname, tname.to_lower()], at, 1.6, "res", r.id)
		if r.note != null and r.note.until > tick:
			_add_stuck(r.name, r.note.text, at, 1.6, "res", r.id)
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
	return [0.2, 0.5, 2.5, 4.0][mini(s.stage, 3)]


# ---------------------------------------------------------------- commands

## Marks every tree and boulder in `rect` to be mined. A single click on an already-marked one
## (pass it as `single`) unmarks it instead.
func designate_mine(rect: Rect2i, single = null) -> void:
	var hit: Array = []
	if single != null:
		hit = [single]
	else:
		for o in trees + boulders:
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


func paint_zone(rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var c := Vector2i(x, y)
			if walkable(c) and site_at(c) == null:
				zone[c] = true
	rev += 1


## Why a blueprint can't go here, or "" when it can. Trees, boulders and stockpile cells don't
## block placement: the blueprint clears them (spec §8).
func placement_check(tpl: String, origin: Vector2i) -> String:
	var size: Vector2i = Defs.TEMPLATES[tpl].size
	if origin.x < 0 or origin.y < 0 or origin.x + size.x > w or origin.y + size.y > h:
		return "Too close to the edge"
	for x in range(origin.x, origin.x + size.x):
		for y in range(origin.y, origin.y + size.y):
			if site_at(Vector2i(x, y)) != null:
				return "Overlaps another building"
	return ""


func place_site(tpl: String, origin: Vector2i, rot := 0) -> Dictionary:
	var s := {"id": _id(), "kind": "site", "tpl": tpl, "origin": origin, "size": Defs.TEMPLATES[tpl].size,
		"rot": rot, "stage": 0, "store": {}, "incoming": {}, "builder": 0, "crafter": 0, "crafting": "",
		"done": false, "owner": 0, "queue": [], "autoq": [], "unreach_until": 0}
	sites.append(s)
	_occ_dirty = true
	for c in site_cells(s):
		zone.erase(c)
	_mark_obstacles(s)
	rev += 1
	return s


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


## Right-click order for one resident: mine a tree or boulder, or walk to a cell.
func direct_order(r: Dictionary, target = null, cell = null) -> void:
	if r.arriving:
		return
	if r.job != null:
		fail_job(r)
	r.note = null
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
	elif cell != null and walkable(cell):
		r.direct = _move_job(cell)


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
	return {"v": 1, "tick": tick, "next_id": next_id, "trees": trees.duplicate(true), "boulders": boulders.duplicate(true),
		"items": items_out, "zone": zone.duplicate(), "sites": sites_out, "residents": res_out,
		"stats": stats.duplicate(), "arrival_at": arrival_at, "arrived": arrived, "auto_craft": auto_craft}


static func from_state(d: Dictionary) -> Sim:
	var s := Sim.new()
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
	for o in s.trees + s.boulders:
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
			s.drop_items(rcell(r), r.carry.type, r.carry.n)
			r.carry = null
		if r.arriving:
			s.walk_in(r)
	s.compute_stuck()
	return s
