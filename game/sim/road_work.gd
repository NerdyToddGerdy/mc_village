class_name RoadWork
extends RefCounted
## the road to the mine (issues #118-#121), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.

static func road(sim: Sim) -> SimMap:
	return sim.maps[Road.ID]


## Whether a party member is walking the road map (issue #118), out or home. One who's already home
## and out there for other work isn't.
static func on_road(sim: Sim, r: Dictionary) -> bool:
	return sim.expedition.get("state", "") == "out" and sim.expedition.party.has(r.id) and (r.map == Road.ID or r.map == MeadowRoad.ID) and r.trip != ""


## The road map a trip to `dest` walks: the meadow's strip, or the road to the mine.
static func road_map_for(dest: String) -> String:
	return Adventures.road_of(dest)


## The two ends of the road map `id`: the village's and the site's.
static func road_ends(id: String) -> Array:
	return [MeadowRoad.VILLAGE_END, MeadowRoad.far_end()] if id == MeadowRoad.ID else [Road.VILLAGE_END, Road.MINE_END]


## Onto the road map at the end they're leaving from, heading for `to` (a site, or "village").
static func _onto_road(sim: Sim, r: Dictionary, to: String) -> void:
	var id := road_map_for(sim.expedition.get("dest", ""))
	var ends := road_ends(id)
	sim.move_to_map(r, id, ends[0] if to != "village" else ends[1])
	r.trip = to
	sim.maps[id].known = true
	if id == MeadowRoad.ID:
		return
	if sim.expedition.get("state", "") == "out":  # when the leg started, for the report (issue #124)
		var leg: String = "road_" + sim.expedition.get("leg", "out")
		if not sim.expedition.has(leg):
			sim.expedition[leg] = [sim.tick, sim.tick]
	road(sim).known = true
	_reveal(sim, Sim.rcell(r))


## A party member's walk along the road, to the far end, where they step off it.
static func _road_walk_job(sim: Sim, r: Dictionary) -> Job:
	var home: bool = r.trip == "village"
	var j := Job.new("road", "On the road home" if home else "On the road to the %s" % sim.maps[sim.expedition.dest].name.to_lower(), "the end of the road")
	var from := "mine" if home else "village"
	var to := "village" if home else "mine"
	var ends := road_ends(r.map)
	if r.map == Road.ID and sim.expedition.get("cart", false) and not sim.cart.is_empty() and (sim.cart.riders.has(r.id) or (sim.cart.state == "parked" and sim.cart.at == from)):
		j.label = ("Riding home" if home else "Riding to the %s" % sim.maps[sim.expedition.dest].name.to_lower()) + " by cart"
		if not sim.cart.riders.has(r.id):  # walk to the sim.cart and get in
			j.step(sim._goto([Vector2i(roundi(sim.cart.x), Road.LINE_ROW)], true))
			j.step({"op": "board", "riding": j.label})
			j.label = "Getting into the cart"
		j.step({"op": "ride", "to": to})
	j.step(sim._goto([ends[0] if home else ends[1]], false))
	j.step({"op": "road_end"})
	return j


## About how many seconds a party member has left on the road.
static func road_eta(sim: Sim, r: Dictionary) -> float:
	var ends := road_ends(r.map)
	var end: Vector2i = ends[0] if r.trip == "village" else ends[1]
	return absf(r.pos.x - end.x) / (Tuning.WALK * Sim.hurt_speed(r))


## Walking speed on a cell, as a share of WALK: wading the stream is slow until it's bridged, and a
## worn path is quicker (issue #196).
static func ground_speed(sim: Sim, c: Vector2i) -> float:
	var ride := Tuning.CART_SPEED / Tuning.WALK if sim.m.id == NetherRoute.ROUTES.quartz.id and sim.nline_complete() else 1.0  # the Nether line (issue #159)
	if sim.m.id == NetherLanding.ID and sim.pline_complete() and NetherLanding.TRACK.has(c):  # the portal line (issue #168)
		ride = Tuning.CART_SPEED / Tuning.WALK
	return (Tuning.FORD_SPEED if sim.m.water.has(c) and not bridged(sim, c) else 1.0) * path_speed(sim, c) * ride


## How worn a stretch of ground is, as a stage: 0 grass, 1 worn grass, 2 dirt path, 3 packed path.
static func wear_stage(wear: int) -> int:
	if wear >= Tuning.WEAR_PACKED:
		return 3
	if wear >= Tuning.WEAR_DIRT:
		return 2
	return 1 if wear >= Tuning.WEAR_WORN else 0


## The stage of the ground at `c` on the current map.
static func path_stage(sim: Sim, c: Vector2i) -> int:
	return wear_stage(sim.m.wear.get(c, 0))


## The speed a worn path gives on `c`, as a share of WALK; 1 on grass.
static func path_speed(sim: Sim, c: Vector2i) -> float:
	if sim.m.wear.is_empty():
		return 1.0
	match path_stage(sim, c):
		3: return Tuning.PATH_SPEED_PACKED
		2: return Tuning.PATH_SPEED_DIRT
	return 1.0


## Whether walking wears the ground at `c`: grass in the village, not under a building, stockpile or farm.
static func _wears(sim: Sim, c: Vector2i) -> bool:
	return sim.m.kind == "village" and not sim.m.zone.has(c) and not sim.m.farm.has(c) and sim.site_at(c) == null


## A resident has stepped onto `c`: the ground there packs down a little (issue #196). The ground is
## only redrawn when a cell changes stage.
static func _wear_step(sim: Sim, c: Vector2i) -> void:
	if sim.m.kind != "village" or not _wears(sim, c):
		return
	var before: int = sim.m.wear.get(c, 0)
	var now := mini(before + Tuning.WEAR_STEP, Tuning.WEAR_CAP)
	sim.m.wear[c] = now
	sim.m.wear_touched[c] = true
	if wear_stage(now) != wear_stage(before):
		sim.rev += 1


## Wear grows back over cells nobody walked on since the last pass: 1 each (issue #196).
static func _decay_wear(sim: Sim) -> void:
	var gone: Array = []
	for c in sim.m.wear:
		if sim.m.wear_touched.has(c):
			continue
		var before: int = sim.m.wear[c]
		sim.m.wear[c] = before - 1
		if before - 1 <= 0:
			gone.append(c)
		if wear_stage(before - 1) != wear_stage(before):
			sim.rev += 1
	for c in gone:
		sim.m.wear.erase(c)
	sim.m.wear_touched = {}


## Putting a building or a stockpile on the ground clears the wear under it.
static func _clear_wear(sim: Sim, c: Vector2i) -> void:
	if sim.m.wear.has(c):
		if path_stage(sim, c) != 0:
			sim.rev += 1
		sim.m.wear.erase(c)


static func bridged(sim: Sim, c: Vector2i) -> bool:
	return sim.m.sites.any(func(s): return s.tpl == "bridge" and s.done and Rect2i(s.origin, s.size).has_point(c))


## Someone on the road reaches a new segment: the fog lifts off it (issue #119).
static func _reveal(sim: Sim, c: Vector2i) -> void:
	var rd := road(sim)
	var seg := Road.segment_at(c.x)
	if seg < rd.seen:
		return
	rd.seen = seg + 1
	sim.rev += 1
	if rd.seen >= Road.segment_count():
		var prev := sim.use_map(Road.ID)
		sim._toast("The road to the mine is surveyed: about %d s on foot. Select the signpost for the route." % roundi(route_walk_time(sim)))
		sim.use_map(prev)


static func route_surveyed(sim: Sim) -> bool:
	return road(sim).seen >= Road.segment_count()


## The walk from end to end along the line, fording the stream until it's bridged.
static func route_walk_time(sim: Sim) -> float:
	var t := 0.0
	var rd := road(sim)
	var prev := sim.use_map(Road.ID)
	for x in range(Road.VILLAGE_END.x, Road.MINE_END.x):
		t += 1.0 / (Tuning.WALK * ground_speed(sim, Vector2i(x, Road.LINE_ROW)))
	sim.use_map(prev)
	return t


## The ride from end to end once the line is complete.
static func route_cart_time() -> float:
	return float(Road.MINE_END.x - Road.VILLAGE_END.x) / Tuning.CART_SPEED


## What stands in the way on a segment, in the player's words, or "".
static func obstacle_text(sim: Sim, i: int) -> String:
	match Road.SEGMENTS[i].obstacle:
		"stream":
			var b := bridge(sim)
			if not b.is_empty() and b.done:
				return "Bridged"
			if not b.is_empty():
				return "A bridge is planned. Until it's built, people wade across slowly"
			return "A stream: people wade across slowly. Track needs a plank bridge (%s)" % Defs.cost_text(Defs.TEMPLATES.bridge.stages[0].cost)
		"cut":
			var n := cut_boulders(sim).size()
			if n == 0:
				return "Cleared"
			return "A rocky cut: %d %s on the line to mine before track can go down" % [n, "boulder" if n == 1 else "boulders"]
	return ""


## The bridge over the stream, planned or built, or {}.
static func bridge(sim: Sim) -> Dictionary:
	for st in road(sim).sites:
		if st.tpl == "bridge":
			return st
	return {}


## Boulders still standing on the line in the rocky cut.
static func cut_boulders(sim: Sim) -> Array:
	var line := {}
	for i in Road.segment_count():
		if Road.SEGMENTS[i].obstacle == "cut":
			for c in Road.line_cells(i):
				line[c] = true
	return road(sim).boulders.filter(func(b): return b.alive and line.has(b.cell))


## The route report (issue #119), for the signpost and the expedition board: each segment, and the
## journey on foot and by cart.
static func route_report(sim: Sim) -> Dictionary:
	var rd := road(sim)
	var segs: Array = []
	for i in Road.segment_count():
		var sg: Dictionary = Road.SEGMENTS[i]
		if i >= rd.seen:
			segs.append({"name": "Not walked yet", "known": false, "len": Road.seg_len(i)})
			continue
		segs.append({"name": sg.name, "known": true, "len": Road.seg_len(i), "terrain": sg.terrain,
			"obstacle": obstacle_text(sim, i), "track": track_state(sim, i)})
	return {"segments": segs, "surveyed": route_surveyed(sim), "walk": route_walk_time(sim), "cart": route_cart_time(), "cart_now": route_cart_now(sim)}


## Places the plank bridge over the stream (issue #119). Returns why it can't, or "".
static func plan_bridge(sim: Sim) -> String:
	if road(sim).seen <= _seg_of("stream"):
		return "Nobody has seen the stream yet"
	if not bridge(sim).is_empty():
		return "The bridge is already planned"
	var prev := sim.use_map(Road.ID)
	var b := sim.place_site("bridge", Road.BRIDGE_AT)
	sim.use_map(prev)
	b.plot = null
	return ""


## Marks the cut's boulders on the line to be mined (issue #119). Returns why it can't, or "".
static func clear_cut(sim: Sim) -> String:
	if road(sim).seen <= _seg_of("cut"):
		return "Nobody has seen the cut yet"
	var left := cut_boulders(sim)
	if left.is_empty():
		return "The cut is already clear"
	for b in left:
		b.des = true
		b.unreach_until = 0
	sim.rev += 1
	return ""


static func _seg_of(obstacle: String) -> int:
	for i in Road.segment_count():
		if Road.SEGMENTS[i].obstacle == obstacle:
			return i
	return -1


# The line (issue #121): one point-to-point line along the road, a track blueprint per segment.

## A segment's track site, or {}.
static func track_site(sim: Sim, i: int) -> Dictionary:
	for st in road(sim).sites:
		if st.tpl == "track" and st.seg == i:
			return st
	return {}


## "none", "planned" or "built".
static func track_state(sim: Sim, i: int) -> String:
	var t := track_site(sim, i)
	return "none" if t.is_empty() else ("built" if t.done else "planned")


## What stops a segment's track going down, in the player's words, or "".
static func track_blocker(sim: Sim, i: int) -> String:
	match Road.SEGMENTS[i].obstacle:
		"stream":
			var b := bridge(sim)
			if b.is_empty() or not b.done:
				return "Needs the bridge"
		"cut":
			if not cut_boulders(sim).is_empty():
				return "Needs the cut cleared"
	return ""


## The segment being laid now: the first unbuilt one from the village end, or -1.
static func next_track(sim: Sim) -> int:
	for i in Road.segment_count():
		var t := track_site(sim, i)
		if not t.is_empty() and not t.done:
			return i
	return -1


## Whether a site on the road can be worked now: track only on the next segment, once it's clear.
static func site_open(sim: Sim, st: Dictionary) -> bool:
	if st.tpl != "track":
		return true
	return st.seg == next_track(sim) and track_blocker(sim, st.seg) == ""


static func line_complete(sim: Sim) -> bool:
	return range(Road.segment_count()).all(func(i): return track_state(sim, i) == "built")


## What the line costs, for the preview (issue #121): the rails it needs that aren't laid or delivered,
## the iron ingots to craft those beyond the rails on hand, and the seconds a round trip saves.
static func line_cost(sim: Sim) -> Dictionary:
	var rails := 0
	for i in Road.segment_count():
		var t := track_site(sim, i)
		if t.is_empty():
			rails += Tuning.RAILS_PER_SEGMENT
		elif not t.done:
			rails += Tuning.RAILS_PER_SEGMENT - t.store.get("rail", 0)
	var on_hand: int = sim.on_map("village", sim.free_count.bind("rail"))
	var crafts := ceili(maxi(0, rails - on_hand) / 16.0)
	var ingots: int = crafts * int(Defs.recipe("rails").inp.iron_ingot)
	return {"rails": rails, "on_hand": on_hand, "ingots": ingots, "saved": 2.0 * (route_walk_time(sim) - route_cart_time())}


## Why the line can't be planned, or "".
static func plan_line_blocker(sim: Sim) -> String:
	if not route_surveyed(sim):
		return "Walk the road first: nobody knows the way past the fog"
	if range(Road.segment_count()).all(func(i): return track_state(sim, i) != "none"):
		return "The whole line is planned"
	return ""


## Plans the line (issue #121): a track blueprint on every segment that has none, from the village end
## to the mine. One point-to-point line, with no switches or branches (#29). Returns why it can't, or "".
static func plan_line(sim: Sim) -> String:
	var why := plan_line_blocker(sim)
	if why != "":
		return why
	var prev := sim.use_map(Road.ID)
	for i in Road.segment_count():
		if track_state(sim, i) != "none":
			continue
		var t := {"id": sim._id(), "kind": "site", "tpl": "track", "origin": Vector2i(Road.SEGMENTS[i].x, Road.LINE_ROW),
			"size": Vector2i(Road.seg_len(i), 1), "rot": 0, "stage": 0, "store": {}, "incoming": {}, "builder": 0,
			"crafter": 0, "crafting": "", "done": false, "owner": 0, "queue": [], "autoq": [], "unreach_until": 0,
			"plot": null, "map": Road.ID, "seg": i}
		sim.m.sites.append(t)
	sim._occ_dirty = true
	sim.rev += 1
	sim.use_map(prev)
	return ""


# Work on the road (issues #119, #121): village residents walk out to build, deliver and clear there.

## Into the road from the village, before step `at` of a job made for the road.
static func _via_road(sim: Sim, j: Job, at: int) -> Job:
	j.steps.insert(at, sim._goto([sim.route_sign()], true))
	j.steps.insert(at + 1, {"op": "cross", "to": Road.ID})
	return j


## Back to the village from the road.
static func _back_job(sim: Sim) -> Job:
	var j := Job.new("commute", "Heading back to the village", "the village")
	j.step(sim._goto([Road.VILLAGE_END], false))
	j.step({"op": "cross", "to": "village"})
	return j


## Work of this kind out on the road, for a village resident with nothing of it to do at home: build
## or supply the bridge and the line, or mine what's marked there. Null when there's none.
static func _road_claim(sim: Sim, r: Dictionary, kind: String, jobs: Array):
	if sim.map_id != "village" or not sim.maps.has(Road.ID) or not road(sim).known:
		return null
	var c := Sim.rcell(r)
	var has_pick: bool = r.pick != null or not sim.tool_items("pick", 0).is_empty()
	var prev := sim.use_map(Road.ID)
	var j = null
	match kind:
		"build":
			if jobs.has("build"):
				var ready := sim.m.sites.filter(func(st): return site_ready(sim, st))
				if not ready.is_empty():
					j = _via_road(sim, sim._tagged(sim._build_job(r, sim._nearest_site(ready, Road.VILLAGE_END)), "build"), 0)
				else:
					for st in sim.m.sites:
						if st.done or not site_open(sim, st) or sim._cooling(st) or not sim.footprint_clear(st):
							continue
						var need := sim.stage_needs(st)
						for t in need:
							var here_src: Array = sim.m.items.values().filter(func(x): return x.type == t and Sim.avail(x) > 0)
							if not here_src.is_empty():  # already out on the road: rails at the railhead
								var at_road: Dictionary = Sim.nearest(here_src, Road.VILLAGE_END)
								j = _via_road(sim, sim._tagged(sim._deliver_job(st, t, mini(mini(need[t], Sim.carry_cap(r)), Sim.avail(at_road)), at_road), "build"), 0)
								break
							if st.tpl == "track":  # rails go out to the railhead first (issue #122)
								continue
							var src: Array = sim.maps.village.items.values().filter(func(x): return x.type == t and Sim.avail(x) > 0)
							if src.is_empty():
								continue
							var from: Dictionary = Sim.nearest(src, c)
							j = _via_road(sim, sim._tagged(sim._deliver_job(st, t, mini(mini(need[t], Sim.carry_cap(r)), Sim.avail(from)), from), "build"), 2)
							break
						if j != null:
							break
					if j == null:
						j = _railhead_job(sim, r, c)
		"haul":
			if jobs.has("haul"):
				j = _dock_job(sim, r, c)
				if j == null:
					j = sim._freight_dock_job(r, c)

				if j == null:
					j = _platform_haul(sim, r, true)
		"gather":
			if r.get("hurt", 0) == 0:
				var targets: Array = sim.m.trees.filter(func(t): return t.alive and t.des and t.claim == 0 and not sim._cooling(t)) if jobs.has("lumber") else []
				if has_pick and jobs.has("mason"):
					targets += sim.m.boulders.filter(func(b): return b.alive and b.des and b.claim == 0 and not sim._cooling(b))
				if not targets.is_empty():
					var t: Dictionary = Sim.nearest(targets, Road.VILLAGE_END)
					sim.use_map("village")
					j = sim._gather_job(r, t)  # a better tool is fetched in the village first
					sim.use_map(Road.ID)
					_via_road(sim, j, j.steps.size() - 2)
	sim.use_map(prev)
	return j


## What someone out on the road does next: more work there, or back to the village to eat, fetch
## materials or find other work.
static func _claim_on_road(sim: Sim, r: Dictionary) -> Job:
	if r.hunger < Tuning.EAT_BELOW:
		return _back_job(sim)
	var c := Sim.rcell(r)
	var jobs := sim.job_list(r)
	for kind in ["build", "gather"]:
		var j = sim._claim_kind(r, c, kind, jobs)
		if j != null:
			return j
	var hj = _platform_haul(sim, r, false)
	if hj != null:
		return hj
	return _back_job(sim)


# Laying the line (issue #122): rails go out to the railhead, then to the segment being laid, rail by rail.

## Whether a site can be built now: a track segment with a rail to lay, or a stage with all it needs.
static func site_ready(sim: Sim, st: Dictionary) -> bool:
	if st.done or st.builder != 0 or not site_open(sim, st) or sim._cooling(st) or not sim.footprint_clear(st):
		return false
	if st.tpl == "track":
		return st.store.get("rail", 0) > 0
	return Sim.has_all(st.store, sim.current_stage(st).cost)


## One rail laid: the segment fills in rail by rail, and is usable once complete.
static func _lay_rail(sim: Sim, st: Dictionary) -> void:
	if st.store.get("rail", 0) <= 0:
		return
	st.store.rail -= 1
	st.laid = st.get("laid", 0) + 1
	sim.rev += 1
	if st.laid >= Tuning.RAILS_PER_SEGMENT:
		st.stage = 1
		st.done = true
		st.store = {}
		st.incoming = {}
		sim._on_site_done(st)


static func _railhead_spot(sim: Sim) -> Vector2i:
	return Road.RAILHEAD


## Rails at the railhead (and anywhere else on the road) that nobody has claimed yet.
static func railhead_rails(sim: Sim) -> int:
	var n := 0
	for st in road(sim).items.values():
		if st.type == "rail":
			n += Sim.avail(st)
	return n


## Rails on their way out to the railhead.
static func _rails_inflight(sim: Sim) -> int:
	var n := 0
	for r in sim.residents:
		if r.job != null and r.job.kind == "railhead":
			n += r.job.steps[-1].n
	return n


## Rails the planned line still needs laid, less those delivered or on their way to a segment.
static func _line_rails_owed(sim: Sim) -> int:
	var n := 0
	for i in Road.segment_count():
		var t := track_site(sim, i)
		if not t.is_empty() and not t.done:
			n += Tuning.RAILS_PER_SEGMENT - t.get("laid", 0) - t.store.get("rail", 0) - t.incoming.get("rail", 0)
	return maxi(0, n)


## Rails still to carry out to the railhead.
static func railhead_need(sim: Sim) -> int:
	return maxi(0, _line_rails_owed(sim) - railhead_rails(sim) - _rails_inflight(sim))


## Rails the line still needs that don't exist anywhere yet.
static func line_short(sim: Sim) -> int:
	var have: int = railhead_rails(sim) + _rails_inflight(sim) + sim.on_map("village", sim.free_count.bind("rail"))
	return maxi(0, _line_rails_owed(sim) - have)


## A load of rails from the village out to the railhead pile, or null.
static func _railhead_job(sim: Sim, r: Dictionary, c: Vector2i):
	var need := railhead_need(sim)
	if need <= 0:
		return null
	var src: Array = sim.maps.village.items.values().filter(func(x): return x.type == "rail" and Sim.avail(x) > 0)
	if src.is_empty():
		return null
	var from: Dictionary = Sim.nearest(src, c)
	var n := mini(mini(need, Sim.carry_cap(r)), Sim.avail(from))
	var j := Job.new("railhead", "Carrying rails to the railhead", "the railhead")
	j.work = "build"
	from.res += n
	var sh := j.hold({"t": "stack", "stack": from, "n": n})
	j.step(sim._goto(sim.reach(from.cell), false))
	j.step({"op": "pickup", "stack": from, "n": n, "hold": sh})
	j.step(sim._goto([sim.route_sign()], true))
	j.step({"op": "cross", "to": Road.ID})
	j.step(sim._goto([_railhead_spot(sim)], false))
	j.step({"op": "railhead_drop", "n": n})
	return j


# Stations and the cart (issue #123).

## The station at "village" or "mine" end, planned or built, or {}.
static func station(sim: Sim, end: String) -> Dictionary:
	for st in road(sim).sites:
		if st.tpl == "station" and st.end == end:
			return st
	return {}


## Where the cart stops at a station, along the line.
static func station_x(end: String) -> float:
	return Road.STATIONS[end].x + 1.0


## Places a station at one end of the road (issue #123). Returns why it can't, or "".
static func plan_station(sim: Sim, end: String) -> String:
	if not station(sim, end).is_empty():
		return "That station is already planned"
	if road(sim).seen <= Road.segment_at(Road.STATIONS[end].x):
		return "Nobody has walked that far yet"
	var prev := sim.use_map(Road.ID)
	var st := sim.place_site("station", Road.STATIONS[end])
	sim.use_map(prev)
	st.end = end
	st.plot = Rect2i(Road.STATIONS[end], Vector2i(3, 3))  # room to grow into a loading station
	return ""


## The minecart on its way to the village station, by someone hauling it.
static func _docking(sim: Sim) -> bool:
	return sim.residents.any(func(r): return r.job != null and r.job.steps.any(func(x): return x.op == "dock"))


## A finished minecart from the village, hauled out to the village station and parked there.
static func _dock_job(sim: Sim, r: Dictionary, c: Vector2i):
	var vs := station(sim, "village")
	if vs.is_empty() or not vs.done or not sim.cart.is_empty() or _docking(sim):
		return null
	var carts: Array = sim.maps.village.items.values().filter(func(x): return x.type == "minecart" and Sim.avail(x) > 0)
	if carts.is_empty():
		return null
	var from: Dictionary = Sim.nearest(carts, c)
	var j := Job.new("haul", "Hauling the minecart to the station", "the station")
	j.work = "haul"
	from.res += 1
	var sh := j.hold({"t": "stack", "stack": from, "n": 1})
	j.step(sim._goto(sim.reach(from.cell), false))
	j.step({"op": "pickup", "stack": from, "n": 1, "hold": sh})
	j.step(sim._goto([sim.route_sign()], true))
	j.step({"op": "cross", "to": Road.ID})
	j.step(sim._goto(sim.site_cells(vs), true))
	j.step({"op": "dock"})
	return j


## Cargo set down on a station's platform, hauled back along the road to the village stockpile.
static func _platform_haul(sim: Sim, r: Dictionary, from_village: bool):
	var src: Array = road(sim).items.values().filter(func(x): return x.get("cargo", false) and Sim.avail(x) > 0)
	if src.is_empty():
		return null
	var st: Dictionary = Sim.nearest(src, Road.VILLAGE_END)
	var vm: SimMap = sim.maps.village
	var dest = sim.on_map("village", sim.zone_dest.bind(st.type))
	if dest == null:
		return null
	var there = vm.items.get(dest)
	var n := mini(mini(Sim.avail(st), Sim.carry_cap(r)), Defs.stack_cap(st.type) - (there.n if there != null else 0))
	if n <= 0:
		return null
	vm.zone_res[dest] = r.id
	var j := Job.new("haul", "Hauling %s from the station" % Defs.ITEMS[st.type].many, "the stockpile")
	j.work = "haul"
	st.res += n
	var sh := j.hold({"t": "stack", "stack": st, "n": n})
	var zh := j.hold({"t": "zone", "cell": dest, "map": "village"})
	if from_village:
		j.step(sim._goto([sim.route_sign()], true))
		j.step({"op": "cross", "to": Road.ID})
	j.step(sim._goto(sim.reach(st.cell), false))
	j.step({"op": "pickup", "stack": st, "n": n, "hold": sh})
	j.step(sim._goto([Road.VILLAGE_END], false))
	j.step({"op": "cross", "to": "village"})
	j.step(sim._goto([dest], false))
	j.step({"op": "haul_drop", "cell": dest, "type": st.type, "n": n, "hold": zh})
	return j


## Whether a party leaving now would ride: the cart waits at the village station, both stations are
## built, and nothing stands on the line in the cut.
static func cart_ready(sim: Sim) -> bool:
	if sim.cart.is_empty() or sim.cart.state != "parked" or sim.cart.at != "village":
		return false
	var vs := station(sim, "village")
	var ms := station(sim, "mine")
	return not vs.is_empty() and vs.done and not ms.is_empty() and ms.done and cut_boulders(sim).is_empty()


## The cart adds its room to the packs while the whole line is laid (issue #123).
static func cart_adds_room(sim: Sim) -> bool:
	return sim.maps.has(Road.ID) and line_complete(sim) and cart_ready(sim)


## Where a rider sits in the cart: side by side along it.
static func _seat(sim: Sim, r: Dictionary) -> Vector2:
	var i: int = sim.cart.riders.find(r.id)
	return Vector2(sim.cart.x + (i - (sim.cart.riders.size() - 1) / 2.0) * 0.3, Road.LINE_ROW)


## Where a rider steps off the cart.
static func _off_cart_cell(sim: Sim) -> Vector2i:
	return Vector2i(roundi(sim.cart.x), Road.LINE_ROW)


## One tick of the cart (issues #123, #124): it waits for the whole party, is loaded at the mine end,
## rides the line (pushed at walking pace where there's no track yet), and is unloaded onto the
## village platform.
static func _step_cart(sim: Sim) -> void:
	if sim.cart.is_empty():
		return
	var ex := sim.expedition
	match sim.cart.state:
		"parked":
			if ex.get("state", "") != "out" or not ex.get("cart", false):
				return
			var home: bool = ex.get("leg", "out") == "home"
			if sim.cart.at != ("mine" if home else "village") or not ex.party.all(func(id): return sim.cart.riders.has(id)):
				return
			if home and not ex.get("cart_loaded", false):
				sim.cart.state = "loading"
				sim.cart.acc = 0.0
				ex.to_load = ex.get("cargo", {}).duplicate()
				return
			sim.cart.state = "moving"
		"loading":
			sim.cart.acc += Tuning.LOAD_RATE * Tuning.DT
			while sim.cart.acc >= 1.0 and not ex.get("to_load", {}).is_empty():
				sim.cart.acc -= 1.0
				var k: String = ex.to_load.keys()[0]
				sim.cart.load[k] = sim.cart.load.get(k, 0) + 1
				ex.to_load[k] -= 1
				if ex.to_load[k] <= 0:
					ex.to_load.erase(k)
				sim.rev += 1
			if ex.get("to_load", {}).is_empty():
				ex.cart_loaded = true
				sim.cart.state = "moving"
		"moving":
			var dir := 1.0 if ex.get("leg", "out") == "out" else -1.0
			var dest := "mine" if dir > 0.0 else "village"
			var c := Vector2i(roundi(sim.cart.x), Road.LINE_ROW)
			var speed := Tuning.CART_SPEED if track_state(sim, Road.segment_at(c.x)) == "built" else Tuning.WALK * ground_speed(sim, c)
			sim.cart.x += dir * speed * Tuning.DT
			var tx := station_x(dest)
			if (dir > 0.0 and sim.cart.x >= tx) or (dir < 0.0 and sim.cart.x <= tx):
				sim.cart.x = tx
				sim.cart.at = dest
				sim.cart.state = "unloading" if dest == "village" and not sim.cart.load.is_empty() else "parked"
				sim.cart.acc = 0.0
				sim.rev += 1
			for id in sim.cart.riders:
				sim.resident(id).pos = _seat(sim, sim.resident(id))
		"unloading":
			sim.cart.acc += Tuning.LOAD_RATE * Tuning.DT
			var spot: Vector2i = Road.STATIONS[sim.cart.at] + Vector2i(1, 0)
			while sim.cart.acc >= 1.0 and not sim.cart.load.is_empty():
				sim.cart.acc -= 1.0
				var k: String = sim.cart.load.keys()[0]
				sim._drop_cargo(spot, k, 1)
				sim.cart.load[k] -= 1
				if sim.cart.load[k] <= 0:
					sim.cart.load.erase(k)
			if sim.cart.load.is_empty():
				sim.cart.state = "parked"
				ex.cargo_unloaded = true
				sim.rev += 1


## The journey from end to end by cart as the line stands now: a walk to the cart, the ride (pushed at
## walking pace over segments without track), and a walk from it (issue #124).
static func route_cart_now(sim: Sim) -> float:
	var t := float(Road.STATIONS.village.x + 1 - Road.VILLAGE_END.x) / Tuning.WALK + float(Road.MINE_END.x - Road.STATIONS.mine.x - 1) / Tuning.WALK
	var prev := sim.use_map(Road.ID)
	for x in range(int(station_x("village")), int(station_x("mine"))):
		var c := Vector2i(x, Road.LINE_ROW)
		t += 1.0 / (Tuning.CART_SPEED if track_state(sim, Road.segment_at(x)) == "built" else Tuning.WALK * ground_speed(sim, c))
	sim.use_map(prev)
	return t
