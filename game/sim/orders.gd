class_name Orders
extends RefCounted
## Split out of sim.gd (#305). Every function takes the Sim it works on; Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## Right-click order for one resident: mine a tree or boulder, or walk to a cell. It replaces
## whatever they're doing and any queued orders.
static func direct_order(sim: Sim, r: Dictionary, target = null, cell = null) -> void:
	if r.map != sim.map_id:
		sim.on_map(r.map, sim.direct_order.bind(r, target, cell))
		return
	if r.arriving or r.away:
		return
	if r.job != null:
		sim.fail_job(r)
	r.note = null
	r.orders.clear()
	if target != null and (target.kind == "tree" or target.kind == "boulder"):
		target.des = true
		target.unreach_until = 0
		sim.rev += 1
		if target.claim != 0 and target.claim != r.id:
			var o := sim.resident(target.claim)
			if not o.is_empty() and o.job != null and is_same(o.job.target, target):
				sim.fail_job(o)
		if target.kind == "boulder" and r.pick == null and sim.tool_items("pick", 0).is_empty():
			r.note = {"text": "Needs a pickaxe", "until": sim.tick + 5 * Tuning.TPS}
			sim.compute_stuck()
			return
		if r.get("hurt", 0) > 0:
			r.note = {"text": "Injured: can't mine", "until": sim.tick + 5 * Tuning.TPS}
			sim.compute_stuck()
			return
		r.direct = sim._gather_job(r, target)
		r.direct.ordered = true
	elif target != null and target.kind == "animal":
		target.des = true
		target.unreach_until = 0
		sim.rev += 1
		if target.claim != 0 and target.claim != r.id:
			var o := sim.resident(target.claim)
			if not o.is_empty() and o.job != null and is_same(o.job.target, target):
				sim.fail_job(o)
		r.direct = sim._hunt_job(r, target)
		r.direct.ordered = true
	elif cell != null and sim.walkable(cell):
		r.direct = sim._move_job(cell)


## Shift + right-click: adds an order to the end of the resident's list. Orders run one after
## another once their current work is done, then the resident goes back to claiming jobs.
static func queue_order(sim: Sim, r: Dictionary, target = null, cell = null) -> void:
	if r.map != sim.map_id:
		sim.on_map(r.map, sim.queue_order.bind(r, target, cell))
		return
	if r.arriving or r.away:
		return
	if target != null and (target.kind == "tree" or target.kind == "boulder"):
		target.des = true
		target.unreach_until = 0
		sim.rev += 1
		r.orders.append({"kind": "mine", "target_kind": target.kind, "id": target.id})
	elif target != null and target.kind == "animal":
		target.des = true
		target.unreach_until = 0
		sim.rev += 1
		r.orders.append({"kind": "hunt", "id": target.id, "species": target.species})
	elif cell != null and sim.walkable(cell):
		r.orders.append({"kind": "move", "cell": cell})


## Equip order (resident panel): go and pick up this tool, dropping the one in hand where it lay.
## A tool chosen this way is kept until it breaks, instead of being swapped for a better one.
static func equip_order(sim: Sim, r: Dictionary, stack: Dictionary) -> void:
	if r.map != sim.map_id:
		sim.on_map(r.map, sim.equip_order.bind(r, stack))
		return
	if r.arriving or r.away or sim.avail(stack) < 1 or not Defs.is_tool_item(stack.type):
		return
	if r.job != null:
		sim.fail_job(r)
	r.note = null
	r.orders.clear()
	var it: Dictionary = Defs.ITEMS[stack.type]
	var j := Job.new("equip", "Going to get the %s" % it.one, "the %s" % it.one)
	j.ordered = true
	stack.res += 1
	var hd := j.hold({"t": "stack", "stack": stack, "n": 1})
	j.step(sim._goto(sim.reach(stack.cell), false))
	j.step({"op": "pickup_tool", "stack": stack, "hold": hd, "keep": true})
	r.direct = j


## Lets a resident swap a chosen tool for the best one about again.
static func release_kept_tool(sim: Sim, r: Dictionary, kind: String) -> void:
	r.kept[kind] = false
	sim.rev += 1


static func clear_orders(sim: Sim, r: Dictionary) -> void:
	r.orders.clear()


static func order_text(o: Dictionary) -> String:
	if o.kind == "move":
		return "Walk to a spot"
	if o.kind == "hunt":
		return "Hunt a %s" % Defs.SPECIES[o.get("species", "sheep")].one
	return "Mine a tree" if o.target_kind == "tree" else "Mine a boulder"


## Turns a queued order into a job, or returns null to skip it (its target is gone or taken, or a
## boulder needs a pickaxe nobody has).
static func _order_job(sim: Sim, r: Dictionary, o: Dictionary):
	if o.kind == "move":
		return sim._move_job(o.cell) if sim.walkable(o.cell) else null
	if o.kind == "hunt":
		for sh in sim.m.sheep:
			if sh.id == o.id:
				return sim._hunt_job(r, sh) if sh.alive and (sh.claim == 0 or sh.claim == r.id) else null
		return null
	var list := sim.m.trees if o.target_kind == "tree" else sim.m.boulders
	for t in list:
		if t.id != o.id:
			continue
		if not t.alive or (t.claim != 0 and t.claim != r.id) or r.get("hurt", 0) > 0:
			return null
		if t.kind == "boulder" and r.pick == null and sim.tool_items("pick", 0).is_empty():
			r.note = {"text": "Needs a pickaxe", "until": sim.tick + 5 * Tuning.TPS}
			return null
		return sim._gather_job(r, t)
	return null
