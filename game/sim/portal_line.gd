class_name PortalLine
extends RefCounted
## the portal line (issue #168), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## The village's portal station, planned or built, or {}.
static func portal_station(sim: Sim) -> Dictionary:
	for s in sim.maps.village.sites:
		if s.tpl == "portal_station":
			return s
	return {}


## Whether the Nether side is done: all its rails, and the landing station (which the Nether line shares).
static func pline_nether_done(sim: Sim) -> bool:
	return sim.portal_line.laid >= Tuning.PORTAL_LINE_RAILS and sim.nline().stations.landing


## Whether carts can run the whole line: the village station, the rails and the landing station.
static func pline_complete(sim: Sim) -> bool:
	return portal_station(sim).get("done", false) and pline_nether_done(sim)


## Whether the party is out to lay the portal line's Nether side.
static func building_pline(sim: Sim) -> bool:
	return sim.expedition.get("target", {}).get("item", "") == "pline"


## What's left to carry for the Nether side: {rails, planks, cobble}.
static func pline_remaining(sim: Sim) -> Dictionary:
	var out := {"rails": maxi(0, Tuning.PORTAL_LINE_RAILS - sim.portal_line.laid), "planks": 0, "cobble": 0}
	if not sim.nline().stations.landing:
		var st: Dictionary = Defs.TEMPLATES.portal_station.stages[0].cost
		out.planks = st.plank
		out.cobble = st.cobble
	return out


## The next piece the party's supplies allow on the landing: a rail, then the station. {} when there's none.
static func pline_task(sim: Sim, who := 0) -> Dictionary:
	var sup: Dictionary = sim.expedition.get("supplies", {})
	var claims: Dictionary = sim.expedition.get("line_claims", {})
	if sim.portal_line.laid < Tuning.PORTAL_LINE_RAILS and sup.get("rail", 0) > 0:
		return {"kind": "rail", "at": sim.portal_line.laid}
	var st: Dictionary = Defs.TEMPLATES.portal_station.stages[0].cost
	if not sim.nline().stations.landing and sup.get("plank", 0) >= st.plank and sup.get("cobble", 0) >= st.cobble:
		var c: int = claims.get("pline_station", 0)
		if c == 0 or c == who or who == -1 or sim.resident(c).is_empty() or sim.resident(c).job == null or sim.resident(c).job.kind != "build":
			return {"kind": "station", "key": "pline_station"}
	return {}


static func _pline_job(sim: Sim, task: Dictionary, who := 0) -> Job:
	if task.has("key") and who != 0:
		if not sim.expedition.has("line_claims"):
			sim.expedition.line_claims = {}
		sim.expedition.line_claims[task.key] = who
	var cell: Vector2i = NetherLanding.TRACK[mini(task.at, NetherLanding.TRACK.size() - 1)] if task.kind == "rail" else NetherLanding.STATION_AT
	var label: String = "Laying track from the portal" if task.kind == "rail" else "Building the landing station"
	var j := Job.new("build", label, "the portal line")
	j.work = "build"
	j.step(sim._goto([cell], true))
	j.step({"op": "work", "what": "pline", "task": task, "label": label})
	return j


static func _finish_pline_task(sim: Sim, task: Dictionary, r: Dictionary) -> void:
	var sup: Dictionary = sim.expedition.supplies
	var st: Dictionary = Defs.TEMPLATES.portal_station.stages[0].cost
	match task.kind:  # two of the party can sim.reach for the same piece: the second finds it done, or the supplies gone
		"rail":
			if sup.get("rail", 0) <= 0 or sim.portal_line.laid >= Tuning.PORTAL_LINE_RAILS:
				return
			sup.rail -= 1
			sim.portal_line.laid += 1
		"station":
			if sim.nline().stations.landing or sup.get("plank", 0) < st.plank or sup.get("cobble", 0) < st.cobble:
				return
			sup.plank -= st.plank
			sup.cobble -= st.cobble
			sim.nline().stations.landing = true
			sim._toast("The landing station is built, beside the shelter. The Nether line shares it.", r.id)
	for k in sup.keys():
		if sup[k] <= 0:
			sup.erase(k)
	if pline_nether_done(sim):
		sim._toast("The portal line's Nether side is laid." + (" The line is complete." if pline_complete(sim) else " It needs the village station."), r.id)
	sim.rev += 1


## Fills a portal line plan's supplies with what's left to lay, up to what a full party can carry past its meals.
static func _pline_supplies(sim: Sim, plan: Dictionary) -> void:
	var need := pline_remaining(sim)
	var room: int = Tuning.PARTY_MAX * Tuning.PACK_CAPACITY - plan.meals
	var take := {}
	for k in ["rails", "planks", "cobble"]:
		take[k] = mini(need[k], maxi(0, room))
		room -= take[k]
	plan.rails = take.rails
	plan.planks = take.planks
	plan.cobble = take.cobble


static func pline_text(sim: Sim) -> String:
	var need := pline_remaining(sim)
	var parts: PackedStringArray = []
	for k in [["rails", "rail"], ["planks", "plank"], ["cobble", "cobble"]]:
		if need[k[0]] > 0:
			parts.append(Defs.words(k[1], need[k[0]]))
	return "Still to lay on the Nether side: %s. The landing station is shared with the Nether line." % (", ".join(parts) if not parts.is_empty() else "nothing")
