class_name SiteCommands
extends RefCounted
## Split out of sim.gd (#305). Every function takes the Sim it works on; Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## Why a blueprint can't go here, or "" when it can. Trees, boulders, stockpile cells and farm plots
## don't block placement: the blueprint clears them (spec §8). Reserved plots do, and a job
## building's own plot needs room too (Slice 2 spec §8).
static func placement_check(sim: Sim, tpl: String, origin: Vector2i, rot := 0, ignore := 0) -> String:
	if sim.m.kind != "village":
		return "Buildings go in the village"
	if tpl == "portal":
		rot = 0
		if Survey.enabled and not Survey.found(sim, "ruined_portal"):
			return "Find the ruined portal first: send a Cartographer to survey"
	var size: Vector2i = Defs.TEMPLATES[tpl].size
	var foot := Rect2i(origin, size)
	if origin.x < 0 or origin.y < 0 or origin.x + size.x > sim.w or origin.y + size.y > sim.h:
		return "Too close to the edge"
	if foot.has_point(sim.meadow_sign()):
		return "The meadow signpost is in the way"
	if foot.has_point(sim.route_sign()):
		return "The signpost to the old caves is in the way"
	if tpl == "dispatcher":  # beside the village station (issue #173)
		var pst := sim.portal_station()
		if not pst.get("done", false):
			return "Build the portal station first"
		if sim.maps.village.sites.any(func(x): return x.tpl == "dispatcher"):
			return "There's a dispatcher already"
		if not Rect2i(pst.origin, pst.size).grow(Tuning.DISPATCHER_REACH).encloses(foot):
			return "The dispatcher stands beside the station"
	if tpl == "freight_loader":  # on the plot the portal station reserved (issue #172)
		var ps := sim.portal_station()
		if not ps.get("done", false):
			return "Build the portal station first"
		if sim.maps.village.sites.any(func(x): return x.tpl == "freight_loader"):
			return "There's a freight loader already"
		if not ps.plot.encloses(foot):
			return "The loader goes on the station's plot"
	for s in sim.m.sites:
		if s.id != ignore and Rect2i(s.origin, s.size).intersects(foot):
			return "Overlaps another building"
	for s in sim.m.sites:
		if s.id != ignore and s.get("plot") != null and s.plot.intersects(foot) and not (tpl == "freight_loader" and s.tpl == "portal_station"):
			return "Overlaps a reserved plot"
	if tpl == "portal_station":  # beside the portal (issue #168)
		var pf := sim.village_portal()
		if pf.is_empty():
			return "Build the portal first"
		if not sim.portal_station().is_empty():
			return "The portal station is already planned"
		var gap := Rect2i(pf.origin, pf.size).grow(Tuning.PORTAL_STATION_REACH)
		if not gap.encloses(foot):
			return "The station stands beside the portal"
	if tpl == "house" and not sim.front_clear(sim.front_cell(origin, rot), ignore):
		return "The entrance is blocked: leave the cell in front of the door clear"
	var plot = sim.plot_rect(tpl, origin, rot)
	for s in sim.m.sites:  # a later building can't close an entrance that's there (issue #285)
		if s.tpl == "house" and s.id != ignore and not sim.is_old_house(s):
			var fc := sim.front_cell(s.origin, s.rot)
			if foot.has_point(fc) or (plot != null and plot.has_point(fc)):
				return "It would block a house's entrance"
	if plot != null:
		var no_room := "Not enough room to grow into a %s" % Defs.TEMPLATES[tpl].plot
		if not Rect2i(0, 0, sim.w, sim.h).encloses(plot):
			return no_room
		for s in sim.m.sites:
			if s.id != ignore and (Rect2i(s.origin, s.size).intersects(plot) or (s.get("plot") != null and s.plot.intersects(plot))):
				return no_room
	return ""




## Why a finished building can't be moved to `origin` turned `rot`, or "" when it can (issue #234). The new spot
## has to pass the same placement checks as a new building; the building itself isn't in its own way.
static func move_check(sim: Sim, s: Dictionary, origin: Vector2i, rot := 0) -> String:
	if s.map != sim.map_id:
		return sim.on_map(s.map, sim.move_check.bind(s, origin, rot))
	if sim.m.kind != "village":
		return "Buildings are moved in the village"
	if s.tpl == "storehouse" and sim.store_width(s) > Tuning.STORE_WIDTH_MIN:
		return "A storehouse that has grown can't be moved"
	if not s.done:
		return "Only a finished building can be moved"
	if s.tpl in Sim.UNMOVABLE:
		return "The %s stands by the portal and can't be moved" % Defs.TEMPLATES[s.tpl].name.to_lower()
	if s.crafter != 0 or s.builder != 0 or not s.incoming.is_empty() or sim.residents.any(func(r): return r.job != null and is_same(r.job.target, s)):
		return "It's in use right now"
	if sim.expedition.get("board", 0) == s.id and sim.expedition.get("state", "") != "":
		return "The expedition is using the board"
	return sim.placement_check(s.tpl, origin, rot, s.id)


## Moves a finished building at once (issue #234): it keeps its queue, its stored items, its worker or its
## occupant, its work area (shifted with it) and its standing orders. Whatever the new footprint covers is
## cleared the way a new building's would be. Returns why it can't be moved, or "".
static func move_site(sim: Sim, s: Dictionary, origin: Vector2i, rot := 0) -> String:
	if s.map != sim.map_id:
		return sim.on_map(s.map, sim.move_site.bind(s, origin, rot))
	var why := sim.move_check(s, origin, rot)
	if why != "":
		return why
	var delta: Vector2i = origin - s.origin
	if s.has("area"):
		var shifted := {}
		for c in s.area:
			var n: Vector2i = c + delta
			if sim.m.in_bounds(n) and sim._area_owner(s.tpl, n, s).is_empty():
				shifted[n] = true
		s.area = shifted
	var old_front := sim.front_cell(s.origin, s.rot)
	s.origin = origin
	s.rot = rot
	s.erase("old")  # put down where it has an entrance (issue #356)
	if s.get("torch", false):  # its torch comes with it, to the new door (issue #367)
		sim.m.remove_torch(old_front)
		sim.m.add_torch(sim.front_cell(origin, rot))
	if s.tpl == "storehouse":
		s.erase("door")  # it moves only while 3 wide: the door is the formula's again (issue #318)
	s.plot = sim.plot_rect(s.tpl, origin, rot)
	for c in sim.site_cells(s):
		sim.m.zone.erase(c)
		sim._drop_crop(c)
		sim._clear_wear(c)
	if s.plot != null:
		for x in range(s.plot.position.x, s.plot.end.x):
			for y in range(s.plot.position.y, s.plot.end.y):
				sim.m.zone.erase(Vector2i(x, y))
				sim._drop_crop(Vector2i(x, y))
	sim._occ_dirty = true
	sim._mark_obstacles(s)
	sim.rev += 1
	return ""


## Whether an old house can be updated where it stands: the cell in front of its old door is clear (issue #356).
static func house_update_in_place(sim: Sim, s: Dictionary) -> bool:
	return sim.front_clear(sim.front_cell(s.origin, s.rot), s.id)


## Updates an old house (issue #356). With its front clear it turns into a house with an entrance where it stands, its door where it
## was, at no cost, and its resident works again: returns "". Otherwise returns "move": the player moves it to a spot that fits.
static func update_house(sim: Sim, s: Dictionary) -> String:
	if not sim.is_old_house(s):
		return "It's not an old house"
	if not sim.house_update_in_place(s):
		return "move"
	s.erase("old")
	sim._occ_dirty = true
	sim._mark_obstacles(s)
	sim.rev += 1
	var who := sim.resident(s.owner)
	sim._toast("The house is updated%s." % ((", and %s is back to work" % who.name) if not who.is_empty() else ""), 0, s.id)
	return ""


static func place_site(sim: Sim, tpl: String, origin: Vector2i, rot := 0) -> Dictionary:
	if tpl == "portal":
		rot = 0
	var s := {"id": sim._id(), "kind": "site", "tpl": tpl, "origin": origin, "size": Defs.TEMPLATES[tpl].size,
		"rot": rot, "stage": 0, "store": {}, "incoming": {}, "builder": 0, "crafter": 0, "crafting": "",
		"done": false, "owner": 0, "queue": [], "autoq": [], "unreach_until": 0,
		"plot": sim.plot_rect(tpl, origin, rot), "map": sim.map_id, "worker": 0}
	if tpl == "house":
		s.tier = 1  # a tent to begin with (issue #285)
	if tpl == "fireplace":
		s.keep_meals = true
	if tpl == "storehouse":
		s.door = sim.store_door(s)  # fixed from here on: it widens round the door (issue #318)
	if tpl == "portal":
		s.lit = false
	if Defs.TEMPLATES[tpl].has("device"):  # a redstone device (issue #170)
		s.cfg = sim.device_default_cfg(Defs.TEMPLATES[tpl].device)
		s.out = false  # whether it's on, and why
		s.why = "Off: not built yet"
	if tpl == "enchanting_workshop":
		s.known = []   # the recipes its books have taught it (issue #165)
		s.orders = []  # enchantments ordered, in turn (issue #166)
	if not sim.work_of(s).is_empty():
		s.keep = Tuning.KEEP_STOCK
	if Defs.TEMPLATES[tpl].has("makes"):
		s.make_keep = Tuning.MAKE_KEEP[tpl]
	if not sim.work_of(s).is_empty():
		s.area = sim.work_area_start(tpl, origin)  # painted from here on (issue #203)
	sim.m.sites.append(s)
	sim._occ_dirty = true
	for c in sim.site_cells(s):
		sim.m.zone.erase(c)
		sim._drop_crop(c)
		sim._clear_wear(c)
	if s.plot != null:  # the reserved plot is kept clear of stockpiles and farms
		for x in range(s.plot.position.x, s.plot.end.x):
			for y in range(s.plot.position.y, s.plot.end.y):
				sim.m.zone.erase(Vector2i(x, y))
				sim._drop_crop(Vector2i(x, y))
	sim._mark_obstacles(s)
	sim.rev += 1
	return s


## Gives a resident their one job (issue #134): one of Defs.JOBS, or "none" to only haul. A new job
## stops work of the old one. Ada does everything, so hers doesn't change.
static func set_role(sim: Sim, r: Dictionary, role: String) -> void:
	if r.role == "all" or r.role == role:
		return
	if r.map != sim.map_id:
		sim.on_map(r.map, sim.set_role.bind(r, role))
		return
	var old: String = r.role
	r.role = role
	if r.job != null and r.job.work == old and old != "haul" and not r.job.ordered:
		sim.fail_job(r)
	sim.assign_workstations()  # the old job's workstation is freed, and the new one's claimed (issue #184)
	sim.rev += 1


## Turns the fireplace's "Keep meals in stock" standing order on or off.
static func set_keep_meals(sim: Sim, f: Dictionary, on: bool) -> void:
	if f.map != sim.map_id:
		sim.on_map(f.map, sim.set_keep_meals.bind(f, on))
		return
	f.keep_meals = on
	if not on:
		for i in range(f.queue.size() - 1, -1, -1):
			if f.autoq[i]:
				sim.queue_remove(f, i)
	sim.rev += 1


static func cancel_site(sim: Sim, s: Dictionary) -> void:
	if s.map != sim.map_id:
		sim.on_map(s.map, sim.cancel_site.bind(s))
		return
	if sim.expedition.get("board", 0) == s.id and sim.expedition.state == "staging":
		sim.cancel_expedition()
	for r in sim.residents:
		if r.job != null and is_same(r.job.target, s):
			sim.fail_job(r)
	for k in s.store:
		if s.store[k] > 0:
			sim.drop_items(s.origin + Vector2i(0, s.size.y), k, s.store[k])
	sim.m.sites.erase(s)
	if s.tpl == "storehouse":  # the room going up beside it goes with it (issue #318)
		for r in sim.m.sites.filter(func(x): return x.tpl == "store_room" and x.get("parent", 0) == s.id):
			sim.cancel_site(r)
	sim.wires = sim.wires.filter(func(w): return w.from != s.id and w.to != s.id)  # dust to a device that's gone (issue #170)
	sim._occ_dirty = true
	sim.assign_workstations()  # its resident claims another free one, or hauls (issue #184)
	sim.rev += 1
