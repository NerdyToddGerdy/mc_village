class_name Redstone
extends RefCounted
## redstone devices and dust (issues #170, #171), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## The settings a new device starts with, by kind.
static func device_default_cfg(kind: String) -> Dictionary:
	match kind:
		"sensor":
			return {"item": "food", "below": Tuning.SENSOR_BELOW}
		"condition":
			return {"fact": "portal_lit"}
		"loader":
			return {"list": Tuning.FREIGHT_LIST.duplicate()}
		"dispatcher":
			return {}
	return {}


## The facts a condition can check, in the order the panel offers them.
const CONDITION_FACTS := ["portal_lit", "cart_home", "loader_idle"]


static func is_device(s: Dictionary) -> bool:
	return Defs.TEMPLATES[s.tpl].has("device")


static func device_by_id(sim: Sim, id: int) -> Dictionary:
	for s in sim.maps.village.sites:
		if s.id == id and is_device(s):
			return s
	return {}


static func wire_by_id(sim: Sim, id: int):
	for w in sim.wires:
		if w.id == id:
			return w
	return null


static func wire_complete(w: Dictionary) -> bool:
	return w.laid >= w.cells.size()


## The finished devices that feed `s`: the other ends of its fully laid dust lines.
static func device_inputs(sim: Sim, s: Dictionary) -> Array:
	var out: Array = []
	for w in sim.wires:
		if w.to == s.id and wire_complete(w):
			var src := device_by_id(sim, w.from)
			if not src.is_empty() and src.done:
				out.append(src)
	return out


## The cells a dust line takes between two devices: along the first one's row, then down the second one's column, leaving out
## the devices' own cells and anything built.
static func wire_cells(sim: Sim, a: Dictionary, b: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var at: Vector2i = a.origin
	var to: Vector2i = b.origin
	while at != to:
		if at.x != to.x:
			at.x += signi(to.x - at.x)
		else:
			at.y += signi(to.y - at.y)
		if at != to and sim.site_at(at) == null:
			out.append(at)
	return out


## Draws a dust line from one device's output to another's input (the Wire order). Returns why it can't, or "".
static func order_wire(sim: Sim, from_id: int, to_id: int) -> String:
	var a := device_by_id(sim, from_id)
	var b := device_by_id(sim, to_id)
	if a.is_empty() or b.is_empty():
		return "Wire: pick two devices"
	if from_id == to_id:
		return "Wire: a device can't feed itself"
	if not a.done or not b.done:
		return "Wire: both devices have to be built"
	if Defs.TEMPLATES[b.tpl].device == "sensor":
		return "Wire: a sensor has no input"
	if sim.wires.any(func(w): return w.from == from_id and w.to == to_id):
		return "Wire: they're joined already"
	sim.wires.append({"id": sim._id(), "from": from_id, "to": to_id, "cells": wire_cells(sim, a, b), "laid": 0})
	sim.rev += 1
	return ""


## Takes a dust line up (the redstone is lost); the signal stops.
static func cut_wire(sim: Sim, id: int) -> void:
	for r in sim.residents:
		if r.job != null and r.job.target != null and r.job.target.has("from") and r.job.target.get("id", 0) == id:
			sim.fail_job(r)
	sim.wires = sim.wires.filter(func(w): return w.id != id)
	_step_devices(sim)
	sim.rev += 1


## Whether someone is already laying this line.
static func _wire_busy(sim: Sim, w: Dictionary) -> bool:
	return sim.residents.any(func(r): return r.job != null and r.job.target != null and r.job.target is Dictionary and r.job.target.get("id", -1) == w.id and r.job.target.has("cells"))


static func _wire_dust_needed(sim: Sim, w: Dictionary) -> int:
	return ceili(float(w.cells.size() - w.laid) / Tuning.DUST_PER_REDSTONE)


## A resident lays the first unfinished dust line: fetch the redstone it takes, then walk the cells and lay each.
static func _wire_job(sim: Sim, r: Dictionary, c: Vector2i):
	for w in sim.wires:
		if wire_complete(w) or _wire_busy(sim, w):
			continue
		var need := _wire_dust_needed(sim, w)
		var src := sim.stacks_where(func(s): return s.type == "redstone" and Sim.avail(s) >= need)
		if src.is_empty():
			continue
		var stack: Dictionary = Sim.nearest(src, c)
		var j := Job.new("build", "Laying redstone dust", "the dust line")
		j.work = "build"
		j.target = w
		stack.res += need
		var sh := j.hold({"t": "stack", "stack": stack, "n": need})
		j.step(sim._goto(sim.reach(stack.cell), false))
		j.step({"op": "pickup", "stack": stack, "n": need, "hold": sh})
		for i in range(w.laid, w.cells.size()):
			j.step(sim._goto([w.cells[i]], true))
			j.step({"op": "work", "what": "lay_dust", "wire": w.id, "label": "Laying redstone dust"})
		return j
	return null


## The signal of every device, a few passes so a chain settles (issue #170). Redraws when anything flips.
static func _step_devices(sim: Sim) -> void:
	var devs: Array = sim.maps.village.sites.filter(func(s): return is_device(s))
	if devs.is_empty():
		return
	var changed := false
	for pass_i in mini(devs.size(), 4):
		for s in devs:
			var res := _eval_device(sim, s)
			if s.out != res.out or s.why != res.why:
				s.out = res.out
				s.why = res.why
				changed = true
	if changed:
		sim.rev += 1


## One device's output and the reason for it, from its settings and its inputs.
static func _eval_device(sim: Sim, s: Dictionary) -> Dictionary:
	if not s.done:
		return {"out": false, "why": "Off: not built yet"}
	match Defs.TEMPLATES[s.tpl].device:
		"sensor":
			var cache := sim.shelter_site()
			if not cache.get("done", false):
				return {"out": false, "why": "Off: no shelter on the landing to read"}
			var n := cache_count(sim, s.cfg.item)
			var label: String = "Cache " + ("food" if s.cfg.item == "food" else Defs.ITEMS[s.cfg.item].many)
			if n < s.cfg.below:
				return {"out": true, "why": "On: %s %d < %d" % [label, n, s.cfg.below]}
			return {"out": false, "why": "Off: %s %d is not below %d" % [label, n, s.cfg.below]}
		"condition":
			var ins := device_inputs(sim, s)
			if ins.is_empty():
				return {"out": false, "why": "Off: nothing wired in"}
			var live := ins.filter(func(i): return i.out)
			var fact := condition_fact(sim, s.cfg.fact)
			if live.is_empty():
				return {"out": false, "why": "Off: its input is off (%s)" % ins[0].why.trim_prefix("Off: ")}
			if not fact.holds:
				return {"out": false, "why": "Off: %s" % fact.no}
			return {"out": true, "why": "On: %s, and %s" % [live[0].why.trim_prefix("On: "), fact.yes]}
		"dispatcher":
			var dins := device_inputs(sim, s)
			if dins.is_empty():
				return {"out": false, "why": "Off: nothing wired in"}
			var dlive := dins.filter(func(i): return i.out)
			if dlive.is_empty():
				return {"out": false, "why": "Off: its input is off (%s)" % dins[0].why.trim_prefix("Off: ")}
			if sim.freight.get("declined", false):
				return {"out": false, "why": "Off: the last request was declined; it waits for the signal to drop"}
			if sim.freight.get("request", false):
				return {"out": true, "why": "On: asking you to approve the departure (%s)" % dlive[0].why.trim_prefix("On: ")}
			if sim.freight.get("state", "") != "home" or sim.freight.get("load", {}).is_empty():
				return {"out": false, "why": "Off: no loaded cart at the station"}
			return {"out": true, "why": "On: %s" % dlive[0].why.trim_prefix("On: ")}
		"loader":
			var ins := device_inputs(sim, s)
			if ins.is_empty():
				return {"out": false, "why": "Off: unpowered, nothing wired in"}
			var live := ins.filter(func(i): return i.out)
			if live.is_empty():
				return {"out": false, "why": "Off: unpowered, its input is off (%s)" % ins[0].why.trim_prefix("Off: ")}
			if sim.freight.get("state", "") != "home":
				return {"out": false, "why": "Off: no freight cart at the station"}
			var miss := freight_missing(sim, s)
			if not miss.is_empty():
				var k: String = miss.keys()[0]
				return {"out": false, "why": "Off: loading, %s more %s to go" % [miss[k], Defs.ITEMS[k].one if miss[k] == 1 else Defs.ITEMS[k].many]}
			return {"out": true, "why": "On: loaded, %s; powered because %s" % [freight_list_text(s.cfg.list), live[0].why.trim_prefix("On: ")]}
	return {"out": false, "why": "Off"}


## What a condition checks: {holds, yes, no}, the phrases for either answer.
static func condition_fact(sim: Sim, fact: String) -> Dictionary:
	match fact:
		"portal_lit":
			return {"holds": sim.portal_lit(), "yes": "the portal is lit", "no": "the portal isn't lit"}
		"cart_home":
			var home: bool = sim.freight.get("state", "") == "home"
			return {"holds": home, "yes": "the freight cart is home", "no": "the freight cart isn't home"}
		"loader_idle":
			var idle := not freight_loader_busy(sim)
			return {"holds": idle, "yes": "the loader is idle", "no": "the loader is busy"}
	return {"holds": false, "yes": "", "no": ""}


## Items of one kind in the shelter's cache; "food" is every meal.
static func cache_count(sim: Sim, item: String) -> int:
	if item == "food":
		return sim.cache_meals()
	return sim.shelter_site().get("store", {}).get(item, 0)


## The village's finished freight loader, or {} (issue #172).
static func freight_loader(sim: Sim) -> Dictionary:
	for s in sim.maps.village.sites:
		if s.tpl == "freight_loader" and s.done:
			return s
	return {}


## Whether the loader has power: some input of it is on.
static func loader_powered(sim: Sim, s: Dictionary) -> bool:
	return device_inputs(sim, s).any(func(i): return i.out)


## What the cart still lacks of the loader's freight list, as {item: n}.
static func freight_missing(sim: Sim, s: Dictionary) -> Dictionary:
	var out := {}
	for k in s.cfg.list:
		var need: int = s.cfg.list[k] - sim.freight.get("load", {}).get(k, 0)
		if need > 0:
			out[k] = need
	return out


## "10 bread, 2 iron ingots".
static func freight_list_text(list: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in list:
		parts.append(Defs.words(k, list[k]))
	return ", ".join(parts) if not parts.is_empty() else "nothing"


## Whether the loader is at work on the cart: powered, the cart at the station and not full yet.
static func freight_loader_busy(sim: Sim) -> bool:
	if sim.freight.get("state", "") != "home" or sim.freight.get("declined", false):  # the common case, so the idle search stays cheap
		return false
	var ld := freight_loader(sim)
	return not ld.is_empty() and loader_powered(sim, ld) and not freight_missing(sim, ld).is_empty()


## How many of an item are on their way to the cart in residents' hands.
static func _loading_en_route(sim: Sim, item: String) -> int:
	var n := 0
	for r in sim.residents:
		if r.job != null:
			for x in r.job.steps:
				if x.op == "load_cart" and x.type == item:
					n += x.n
	return n


## A hauler carries what the cart lacks from the stockpile onto the cart, when the loader is powered.
static func _loader_job(sim: Sim, r: Dictionary, c: Vector2i):
	if not freight_loader_busy(sim):
		return null
	var ld := freight_loader(sim)
	var miss := freight_missing(sim, ld)
	for k in miss:
		var need: int = miss[k] - _loading_en_route(sim, k)
		if need <= 0:
			continue
		var src := sim.stacks_where(func(s): return s.type == k and Sim.avail(s) > 0)
		if src.is_empty():
			continue
		var st: Dictionary = Sim.nearest(src, c)
		var n := mini(mini(need, Sim.avail(st)), Sim.carry_cap(r))
		var j := Job.new("haul", "Loading the freight cart", "the freight cart")
		j.work = "haul"
		st.res += n
		var sh := j.hold({"t": "stack", "stack": st, "n": n})
		j.step(sim._goto(sim.reach(st.cell), false))
		j.step({"op": "pickup", "stack": st, "n": n, "hold": sh})
		j.step(sim._goto(sim.site_cells(sim.portal_station()), true))
		j.step({"op": "load_cart", "type": k, "n": n})
		return j
	return null


## Changes how many of an item the loader puts on the cart (the freight list); the whole list fits the cart.
static func set_freight_item(sim: Sim, id: int, item: String, n: int) -> void:
	var s := device_by_id(sim, id)
	if s.is_empty() or Defs.TEMPLATES[s.tpl].device != "loader" or not Tuning.SENSOR_ITEMS.has(item) or item == "food":
		return
	var total := 0
	for k in s.cfg.list:
		if k != item:
			total += s.cfg.list[k]
	n = clampi(n, 0, Tuning.FREIGHT_CAPACITY - total)
	if n == 0:
		s.cfg.list.erase(item)
	else:
		s.cfg.list[item] = n
	_step_devices(sim)
	sim.rev += 1


## Changes a device's setting (issues #170, #171): a sensor's item and threshold, a condition's fact.
static func set_device_cfg(sim: Sim, id: int, key: String, value) -> void:
	var s := device_by_id(sim, id)
	if s.is_empty() or not s.cfg.has(key):
		return
	if key == "item" and not Tuning.SENSOR_ITEMS.has(value):
		return
	if key == "fact" and not CONDITION_FACTS.has(value):
		return
	if key == "below":
		value = clampi(int(value), 1, Tuning.CACHE_CAPACITY)
	s.cfg[key] = value
	_step_devices(sim)
	sim.rev += 1
