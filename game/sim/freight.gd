class_name Freight
extends RefCounted
## the freight cart (issue #169), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## Why a freight cart can't be ordered, or "".
static func order_freight_cart_blocker(sim: Sim) -> String:
	if not sim.freight.is_empty():
		return "There's a freight cart already"
	if not sim.pline_complete():
		return "Finish the portal line first"
	return ""


## Orders the line's freight cart: a hauler brings a minecart from the village to the portal station. Returns why it can't, or "".
static func order_freight_cart(sim: Sim) -> String:
	var why := order_freight_cart_blocker(sim)
	if why != "":
		return why
	sim.freight = {"state": "ordered", "pos": 0.0, "load": {}, "approved": false, "acc": 0.0}
	sim.rev += 1
	return ""


## A finished minecart from the stockpile, hauled to the portal station and parked as the freight cart.
static func _freight_dock_job(sim: Sim, r: Dictionary, c: Vector2i):
	if sim.freight.get("state", "") != "ordered" or sim.residents.any(func(o): return o.job != null and o.job.steps.any(func(x): return x.op == "freight_dock")):
		return null
	var carts: Array = sim.maps.village.items.values().filter(func(x): return x.type == "minecart" and Sim.avail(x) > 0)
	if carts.is_empty():
		return null
	var from: Dictionary = Sim.nearest(carts, c)
	var j := Job.new("haul", "Hauling the minecart to the portal station", "the portal station")
	j.work = "haul"
	from.res += 1
	var sh := j.hold({"t": "stack", "stack": from, "n": 1})
	j.step(sim._goto(sim.reach(from.cell), false))
	j.step({"op": "pickup", "stack": from, "n": 1, "hold": sh})
	j.step(sim._goto(sim.site_cells(sim.portal_station()), true))
	j.step({"op": "freight_dock"})
	return j


## The player's go-ahead for the cart's departure (issue #169). Returns why it can't, or "".
static func approve_freight(sim: Sim) -> String:
	if sim.freight.get("state", "") != "home":
		return "There's no freight cart at the station"
	if sim.freight.load.is_empty():
		return "The freight cart is empty"
	sim.freight.approved = true
	sim.rev += 1
	return ""


## The dispatcher raises the departure request: powered, with a loaded cart at the station. It is only a request: the game
## runs on, and nothing leaves until the player approves (issue #173).
static func _dispatch_request(sim: Sim) -> void:
	var d := dispatcher(sim)
	if d.is_empty():
		return
	var ld0 := sim.freight_loader()
	if not sim.loader_powered(ld0 if not ld0.is_empty() else d):  # the signal that starts it all (the loader's power), not "loaded"
		sim.freight.erase("declined")
		sim.freight.erase("request")
		return
	if not sim.loader_powered(d) or sim.freight.get("request", false) or sim.freight.get("declined", false) or sim.freight.approved or sim.freight.load.is_empty():
		return
	var ld := sim.freight_loader()
	if not ld.is_empty() and not sim.freight_missing(ld).is_empty():
		return
	sim.freight.request = true
	sim._toast("Supply cart ready for the Nether cache. Approve?", 0, sim.portal_station().get("id", 0))
	sim._step_devices()
	sim.rev += 1


static func dispatcher(sim: Sim) -> Dictionary:
	for s in sim.maps.village.sites:
		if s.tpl == "dispatcher" and s.done:
			return s
	return {}


## Turns the request down: the load goes back to the stockpile, and the dispatcher waits for its signal to drop before asking again.
static func decline_freight(sim: Sim) -> String:
	if sim.freight.get("state", "") != "home" or sim.freight.load.is_empty():
		return "There's no loaded cart at the station"
	var ps := sim.portal_station()
	for k in sim.freight.load:
		sim.drop_items(ps.origin + Vector2i(0, 1), k, sim.freight.load[k])
	sim.freight.load = {}
	sim.freight.approved = false
	sim.freight.erase("request")
	sim.freight.declined = true
	sim._step_devices()
	sim.rev += 1
	return ""


static func cancel_freight_approval(sim: Sim) -> void:
	if sim.freight.get("state", "") == "home" and sim.freight.approved:
		sim.freight.approved = false
		sim.rev += 1


## Items in the shelter's cache, all kinds.
static func cache_items(sim: Sim) -> int:
	var n := 0
	var sh := sim.shelter_site()
	for k in sh.get("store", {}):
		n += sh.store[k]
	return n


static func cache_room(sim: Sim) -> int:
	return maxi(0, Tuning.CACHE_CAPACITY - cache_items(sim)) if sim.shelter_site().get("done", false) else 0


## Why the freight cart can't go on now, or "": the portal's out when it's at the crossing, or the cache has no room.
static func freight_block(sim: Sim) -> String:
	var st: String = sim.freight.get("state", "")
	if st == "ordered":
		return "needs a minecart from the village"
	if st == "home" and not sim.freight.load.is_empty() and not sim.freight.approved:
		return "waiting for approval" if not sim.freight.get("request", false) else "waiting for approval: the dispatcher asks you to approve"
	var at_portal: bool = (st == "home" and sim.freight.approved) or (st in ["going", "returning"] and absf(sim.freight.pos - Tuning.FREIGHT_CROSS) < 0.0001)
	if at_portal and not sim.portal_lit():
		return "the portal is unlit"
	if st == "unloading" and cache_room(sim) <= 0:
		return "the cache is full" if sim.shelter_site().get("done", false) else "there's no shelter to unload into"
	return ""


static func _step_freight(sim: Sim) -> void:
	if sim.freight.is_empty() or sim.freight.state == "ordered":
		return
	var step := Tuning.DT / Tuning.FREIGHT_TRIP_TIME
	match sim.freight.state:
		"home":
			if sim.tick % 10 == 7:
				_dispatch_request(sim)
			if sim.freight.approved and sim.portal_lit() and not sim.freight.load.is_empty():
				sim.freight.state = "going"
				sim.freight.approved = false
				sim.freight.erase("request")
				sim.rev += 1
		"going":
			if sim.freight.pos < Tuning.FREIGHT_CROSS and sim.freight.pos + step >= Tuning.FREIGHT_CROSS:
				sim.freight.pos = Tuning.FREIGHT_CROSS
			if sim.freight.pos == Tuning.FREIGHT_CROSS and not sim.portal_lit():
				return
			sim.freight.pos = minf(1.0, sim.freight.pos + step)
			if sim.freight.pos >= 1.0:
				sim.freight.state = "unloading"
				sim.freight.acc = 0.0
				sim.rev += 1
		"unloading":
			var sh := sim.shelter_site()
			if not sh.get("done", false):
				return
			sim.freight.acc += Tuning.LOAD_RATE * Tuning.DT
			while sim.freight.acc >= 1.0 and not sim.freight.load.is_empty() and cache_room(sim) > 0:
				sim.freight.acc -= 1.0
				var k: String = sim.freight.load.keys()[0]
				sh.store[k] = sh.store.get(k, 0) + 1
				sim.freight.load[k] -= 1
				if sim.freight.load[k] <= 0:
					sim.freight.load.erase(k)
				sim.rev += 1
			if sim.freight.load.is_empty():
				sim.freight.state = "returning"
				sim.stats.freight_trips = sim.stats.get("freight_trips", 0) + 1
				sim._toast("The freight cart has unloaded into the cache and is heading back.", 0, sim.portal_station().get("id", 0))
		"returning":
			if sim.freight.pos > Tuning.FREIGHT_CROSS and sim.freight.pos - step <= Tuning.FREIGHT_CROSS:
				sim.freight.pos = Tuning.FREIGHT_CROSS
			if sim.freight.pos == Tuning.FREIGHT_CROSS and not sim.portal_lit():
				return
			sim.freight.pos = maxf(0.0, sim.freight.pos - step)
			if sim.freight.pos <= 0.0:
				sim.freight.state = "home"
				sim.rev += 1


## Where the freight cart is, as {map, at: Vector2 (a cell's corner)}, or {} when there's none or no station to put it at.
static func freight_place(sim: Sim) -> Dictionary:
	var ps := sim.portal_station()
	if sim.freight.is_empty() or sim.freight.state == "ordered" or ps.is_empty() or sim.village_portal().is_empty():
		return {}
	var p: float = sim.freight.pos
	if p <= Tuning.FREIGHT_CROSS:
		var pf := sim.village_portal()
		var a := Vector2(ps.origin) + Vector2(1.0, 0.0)
		var b := Vector2(pf.origin) + Vector2(1.0, 1.0)
		return {"map": "village", "at": a.lerp(b, p / Tuning.FREIGHT_CROSS)}
	var path: Array = NetherLanding.TRACK.duplicate()
	path.append(NetherLanding.STATION_AT + Vector2i(1, 0))
	var f := (p - Tuning.FREIGHT_CROSS) / (1.0 - Tuning.FREIGHT_CROSS) * (path.size() - 1)
	var i := mini(int(f), path.size() - 2)
	return {"map": NetherLanding.ID, "at": Vector2(path[i]).lerp(Vector2(path[i + 1]), f - i)}


static func _stuck_loader(sim: Sim) -> void:
	var ld := sim.freight_loader()
	var ps := sim.portal_station()
	if ld.is_empty() or ps.is_empty() or not sim.loader_powered(ld):
		return
	var at := Vector2(ld.origin) + Vector2(0.5, 0.5)
	if sim.freight.get("state", "") != "home":
		sim._add_stuck("Loader", "no freight cart at the station", at, 1.0, "site", ld.id, false, true)
		return
	var miss := sim.freight_missing(ld)
	if not miss.is_empty() and not sim.residents.any(func(r): return r.map == "village" and not r.away and not r.arriving and r.get("hurt", 0) == 0):
		sim._add_stuck("Loader", "no one with Haul on", at, 1.0, "site", ld.id)
		return
	for k in miss:
		var short: int = miss[k] - sim.free_count(k) - sim._loading_en_route(k)
		if short > 0:
			sim._add_stuck("Loader", "needs %d more %s" % [short, Defs.ITEMS[k].one if short == 1 else Defs.ITEMS[k].many], at, 1.0, "site", ld.id)
			return


static func _stuck_freight(sim: Sim) -> void:
	if sim.map_id == "village":
		_stuck_loader(sim)
	var ps := sim.portal_station()
	if sim.freight.is_empty() or ps.is_empty() or sim.map_id != "village":
		return
	var why := freight_block(sim)
	if why != "":
		var asking := why.begins_with("waiting for approval")  # the sim.cart is loaded and it's the player's call (issue #296)
		sim._add_stuck("Freight cart", why, Vector2(ps.origin) + Vector2(1.5, 0.5), 1.2, "site", ps.id, false, false, "freight" if asking else "")
