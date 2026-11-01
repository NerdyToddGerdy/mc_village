class_name NetherLine
extends RefCounted
## the Nether line (issue #159), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## The line along the quartz route, which a Build party lays from what it carries: bridges over the lava channel and the gap,
## track (as Slice 4's: `RAILS_PER_SEGMENT` a segment), a station at the landing and one at the quartz site, and a minecart.
static func nline(sim: Sim) -> Dictionary:
	var rm: SimMap = sim.maps[NetherRoute.ROUTES.quartz.id]
	if rm.line.is_empty():
		rm.line = NetherRoute.default_line()
	return rm.line


## Whether a segment needs a bridge before track can go down: the lava channel and the gap.
static func nline_obstacle(seg: int) -> bool:
	return NetherRoute.ROUTES.quartz.segments[seg].obstacle in ["lava", "gap"]


static func nline_complete(sim: Sim) -> bool:
	var l := nline(sim)
	for i in Road.segment_count():
		if l.laid[i] < Tuning.RAILS_PER_SEGMENT or (nline_obstacle(i) and not l.bridged.has(i)):
			return false
	return l.stations.landing and l.stations.site and l.cart


## What's still to build, as the items it takes: {rails, planks, cobble, minecarts}.
static func nline_remaining(sim: Sim) -> Dictionary:
	var l := nline(sim)
	var out := {"rails": 0, "planks": 0, "cobble": 0, "minecarts": 0}
	for i in Road.segment_count():
		out.rails += maxi(0, Tuning.RAILS_PER_SEGMENT - l.laid[i])
		if nline_obstacle(i) and not l.bridged.has(i):
			out.planks += Tuning.NETHER_BRIDGE_PLANKS
	var st: Dictionary = Defs.TEMPLATES.station.stages[0].cost
	for end in ["landing", "site"]:
		if not l.stations[end]:
			out.planks += st.plank
			out.cobble += st.cobble
	if not l.cart:
		out.minecarts = 1
	return out


## The next task the party's supplies allow where it is: "route" (bridges, then track west to east), "landing" (its station) or
## "site" (its station, then the cart once both stand). {} when there's none.
static func nline_task(sim: Sim, where: String, who := 0) -> Dictionary:
	var l := nline(sim)
	var sup: Dictionary = sim.expedition.get("supplies", {})
	var claims: Dictionary = sim.expedition.get("line_claims", {})
	var taken := func(key: String) -> bool:  # someone else is already on it (issue #159)
		var c: int = claims.get(key, 0)
		if c == 0 or c == who or who == -1:  # -1 asks whether any task is left, sim.claimed or not
			return false
		var o := sim.resident(c)
		return not o.is_empty() and o.job != null and o.job.kind == "build"
	var st: Dictionary = Defs.TEMPLATES.station.stages[0].cost
	match where:
		"route":
			for i in Road.segment_count():
				if nline_obstacle(i) and not l.bridged.has(i) and sup.get("plank", 0) >= Tuning.NETHER_BRIDGE_PLANKS and not taken.call("bridge%d" % i):
					return {"kind": "bridge", "seg": i, "key": "bridge%d" % i}
			for i in Road.segment_count():
				if l.laid[i] < Tuning.RAILS_PER_SEGMENT:
					if nline_obstacle(i) and not l.bridged.has(i):
						return {}  # the way is blocked until it's sim.bridged
					return {"kind": "rail", "seg": i} if sup.get("rail", 0) > 0 else {}
		"landing":
			if not l.stations.landing and sup.get("plank", 0) >= st.plank and sup.get("cobble", 0) >= st.cobble and not taken.call("station_landing"):
				return {"kind": "station", "end": "landing", "key": "station_landing"}
		"site":
			if not l.stations.site and sup.get("plank", 0) >= st.plank and sup.get("cobble", 0) >= st.cobble and not taken.call("station_site"):
				return {"kind": "station", "end": "site", "key": "station_site"}
			if l.stations.site and l.stations.landing and not l.cart and sup.get("minecart", 0) > 0 and not taken.call("cart"):
				return {"kind": "cart", "key": "cart"}
	return {}


## Fills a line plan's supplies with what's left to build, most urgent first, up to what a full party of three can carry past
## its meals.
static func _line_supplies(sim: Sim, plan: Dictionary) -> void:
	var need := nline_remaining(sim)
	var room: int = Tuning.PARTY_MAX * Tuning.PACK_CAPACITY - plan.meals
	var st: Dictionary = Defs.TEMPLATES.station.stages[0].cost
	var unbridged := 0
	for i in Road.segment_count():
		if nline_obstacle(i) and not nline(sim).bridged.has(i):
			unbridged += 1
	var stations := 0
	for end in ["landing", "site"]:
		if not nline(sim).stations[end]:
			stations += 1
	var planks: int = unbridged * Tuning.NETHER_BRIDGE_PLANKS
	var take := {}
	for k in [["planks", planks], ["rails", need.rails], ["planks_st", stations * st.plank], ["cobble", need.cobble], ["minecarts", need.minecarts]]:
		var n: int = mini(k[1], maxi(0, room))
		take[k[0]] = n
		room -= n
	plan.planks = take.planks + take.planks_st
	plan.rails = take.rails
	plan.cobble = take.cobble
	plan.minecarts = take.minecarts


## What the line costs and saves, for the planner: the items still to build, and the seconds each way once it's done.
static func nline_text(sim: Sim) -> String:
	var need := nline_remaining(sim)
	var parts: PackedStringArray = []
	for k in [["rails", "rail"], ["planks", "plank"], ["cobble", "cobble"], ["minecarts", "minecart"]]:
		if need[k[0]] > 0:
			parts.append(Defs.words(k[1], need[k[0]]))
	var t := nline_times()
	return "Still to build: %s. Once it's done a trip saves about %d s each way (%d s walking, %d s riding)." % [", ".join(parts) if not parts.is_empty() else "nothing", roundi(t.saved), roundi(t.walk), roundi(t.ride)]


## Whether the party is out to work on the Nether line.
static func building_line(sim: Sim) -> bool:
	return sim.expedition.get("target", {}).get("item", "") == "line"


## A job for a line task: walk to where it's done, and work (issue #159).
static func _line_job(sim: Sim, task: Dictionary, who := 0) -> Job:
	if task.has("key") and who != 0:
		if not sim.expedition.has("line_claims"):
			sim.expedition.line_claims = {}
		sim.expedition.line_claims[task.key] = who
	var cells: Array
	var label: String
	match task.kind:
		"bridge":
			cells = [Vector2i(Road.SEGMENTS[task.seg].x + Road.seg_len(task.seg) / 2, NetherRoute.LINE_ROW)]
			label = "Bridging the %s" % NetherRoute.ROUTES.quartz.segments[task.seg].terrain
		"rail":
			cells = [Vector2i(Road.SEGMENTS[task.seg].x + mini(Road.seg_len(task.seg) - 1, sim.expedition.get("supplies", {}).get("rail", 0) % 4), NetherRoute.LINE_ROW)]
			label = "Laying track"
		"station":
			cells = [NetherLanding.STATION_AT] if task.end == "landing" else [NetherRoute.QUARTZ_STATION_PLOT.position + Vector2i(1, 0)]
			label = "Building the %s station" % ("landing" if task.end == "landing" else "quartz site")
		_:
			cells = [NetherRoute.QUARTZ_STATION_PLOT.position + Vector2i(2, 0)]
			label = "Parking the minecart"
	var j := Job.new("build", label, "the line")
	j.work = "build"
	j.step(sim._goto(cells, true))
	j.step({"op": "work", "what": "nline", "task": task, "label": label})
	return j


## Applies a finished task: the party's supplies are used up and the line grows.
static func _finish_line_task(sim: Sim, task: Dictionary, r: Dictionary) -> void:
	var l := nline(sim)
	var sup: Dictionary = sim.expedition.supplies
	var st: Dictionary = Defs.TEMPLATES.station.stages[0].cost
	match task.kind:  # two of the party can sim.reach for the same piece: the second finds it done, or the supplies gone
		"bridge":
			if l.bridged.has(task.seg) or sup.get("plank", 0) < Tuning.NETHER_BRIDGE_PLANKS:
				return
			sup.plank -= Tuning.NETHER_BRIDGE_PLANKS
			l.bridged.append(task.seg)
			sim._toast("The bridge over the %s is built." % NetherRoute.ROUTES.quartz.segments[task.seg].terrain, r.id)
		"rail":
			if sup.get("rail", 0) <= 0 or l.laid[task.seg] >= Tuning.RAILS_PER_SEGMENT:
				return
			sup.rail -= 1
			l.laid[task.seg] += 1
			if l.laid[task.seg] >= Tuning.RAILS_PER_SEGMENT:
				sim._toast("Track is laid along %s." % NetherRoute.ROUTES.quartz.segments[task.seg].name.to_lower(), r.id)
		"station":
			if l.stations[task.end] or sup.get("plank", 0) < st.plank or sup.get("cobble", 0) < st.cobble:
				return
			sup.plank -= st.plank
			sup.cobble -= st.cobble
			l.stations[task.end] = true
			sim._toast("The %s station is built." % ("landing" if task.end == "landing" else "quartz site"), r.id)
		"cart":
			if l.cart or sup.get("minecart", 0) <= 0:
				return
			sup.minecart -= 1
			l.cart = true
			sim._toast("The minecart is parked at the quartz site station.", r.id)
	for k in sup.keys():
		if sup[k] <= 0:
			sup.erase(k)
	if nline_complete(sim):
		sim._toast("The Nether line is complete. Parties ride it both ways.", r.id)
	sim.rev += 1


## Whether someone is riding the finished line: moving along the quartz route, which creatures and the lava can't touch.
static func _riding(sim: Sim, r: Dictionary) -> bool:
	return sim.maps[r.map].id == NetherRoute.ROUTES.quartz.id and nline_complete(sim) and r.job != null and r.job.kind in ["road", "scout"]


## Seconds each way along the quartz route, walking and riding the finished line (issue #159).
static func nline_times() -> Dictionary:
	var walk: float = NetherRoute.W / Tuning.WALK
	return {"walk": walk, "ride": NetherRoute.W / Tuning.CART_SPEED, "saved": walk - NetherRoute.W / Tuning.CART_SPEED}
