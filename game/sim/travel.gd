class_name Travel
extends RefCounted
## Split out of sim.gd (#305). Every function takes the Sim it works on; Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## The signpost on the village's east edge where the road to the old mine starts and ends.
static func route_sign(sim: Sim) -> Vector2i:
	var v: SimMap = sim.maps.village
	return Vector2i(v.w - 1, v.h / 2)


## Seconds on the way to `to`, or home from it: the road to the meadow, or the road to the mine.
static func trip_time(sim: Sim, to: String) -> float:
	var dest: String = sim.expedition.get("dest", "") if to == "village" else to
	match Adventures.road_of(dest):
		MeadowRoad.ID:
			return MeadowRoad.walk_time()
		SeaRoad.ID:
			return SeaRoad.walk_time()
	return sim.route_walk_time()


## Whether a party member is on their way: walking to the signpost to leave the village, or to the
## site's entrance to come home. Either way, they're out of the work where they are.
static func on_the_way(sim: Sim, r: Dictionary) -> bool:
	if sim.expedition.get("state", "") != "out" or not sim.expedition.party.has(r.id) or r.away:
		return false
	if sim.expedition.get("leg", "out") == "out":  # in the village, or on a level above the one they're bound for (issue #132)
		return r.map == "village" or (MineLevels.level_of(r.map) > 0 and MineLevels.level_of(r.map) < MineLevels.level_of(sim.expedition.dest))
	return r.map == sim.expedition.dest or MineLevels.level_of(r.map) > 0


## Whether a party member is carrying the packs through the village, on the way out (drawn as packs).
static func carrying_packs(sim: Sim, r: Dictionary) -> bool:
	return (sim.on_the_way(r) and r.map != sim.expedition.dest) or sim.on_road(r)


## The walk to where the road starts: the village signpost, or the site's entrance on the way home.
static func _road_job(sim: Sim) -> Job:
	if sim.map_id == "village":
		var dest: String = sim.expedition.dest
		var j := Job.new("road", "Heading for the %s" % sim.maps[dest].name.to_lower(), "the signpost")
		j.step(sim._goto([sim.sign_for(dest)], true))
		j.step({"op": "depart", "to": dest})
		return j
	if sim.expedition.get("leg", "out") == "out":  # down through the door to the level below (issue #132)
		var d := Job.new("road", "Heading down to level %d" % (sim.m.level + 1), "the door")
		d.step(sim._goto([sim.m.door], true))
		d.step({"op": "descend"})
		return d
	var h := Job.new("road", "Heading home", "the entrance")
	h.step(sim._goto([sim.m.entrance], false))
	if sim.realm_of(sim.map_id) == "nether":  # back through the portal, relighting it first if it's gone out (issue #148)
		h.label = "Heading for the portal"
		if not sim.portal_lit():
			if sim.expedition.get("lighter", {}).is_empty():
				h.step({"op": "wait_portal"})
			else:
				h.step({"op": "work", "what": "relight", "label": "Relighting the portal"})
		h.step({"op": "depart", "to": "village"})
		return h
	if sim.m.level > 1:  # up to the level above, then on up
		h.label = "Heading up to level %d" % (sim.m.level - 1) if sim.m.level > 2 else "Heading up to the old caves"
		h.step({"op": "ascend"})
		return h
	h.step({"op": "depart", "to": "village"})
	return h


## Why the party can't be called home yet, or "" when it can.
static func call_home_blocker(sim: Sim, slot_id := "") -> String:
	if slot_id != "" and slot_id != sim.slot:
		return sim.on_slot(slot_id, sim.call_home_blocker)
	if sim.expedition.get("state", "") != "out":
		return "No party is out"
	if sim.expedition.get("leg", "out") == "home":
		return "The party is already heading home"
	for id in sim.expedition.party:
		var r := sim.resident(id)
		if r.map != sim.expedition.dest or r.away:
			return "The party isn't at the %s yet" % sim.maps[sim.expedition.dest].name.to_lower()
	return ""


## Calls the party home now, whatever its return policy says: they walk to the entrance with the
## packs and set off. Returns why it can't, or "".
static func call_home(sim: Sim, slot_id := "") -> String:
	if slot_id != "" and slot_id != sim.slot:
		return sim.on_slot(slot_id, sim.call_home)
	var why := sim.call_home_blocker()
	if why != "":
		return why
	sim.expedition.leg = "home"
	sim.expedition.home_why = "called home"
	for id in sim.expedition.party:
		var r := sim.resident(id)
		sim.fail_job(r)
		r.direct = null
		r.orders.clear()
	sim._toast("The party is heading home from the %s." % sim.maps[sim.expedition.dest].name.to_lower(), sim.expedition.party[0])
	return ""


## A party member back at the village signpost. When the last one is back, the packs are unloaded
## there as stacks, which haulers carry to the stockpile, and the board is free again (issue #112).
static func _arrive_home(sim: Sim, r: Dictionary) -> void:
	r.away = false
	r.trip = ""
	var sign := sim.sign_for(sim.expedition.get("dest", ""))
	var spot = sim.on_map("village", sim.nearest_walkable.bind(sign))
	sim.move_to_map(r, "village", spot if spot != null else sign)
	if sim.expedition.party.all(func(id): return sim.resident(id).map == "village" and not sim.resident(id).away):
		sim._start_unloading()


## The party unpacks at the signpost by hand (issue #123): cargo first, unless it came off the cart at
## the station, then meals, then spare tools, at HAND_RATE an item a second each.
static func _start_unloading(sim: Sim) -> void:
	var ex := sim.expedition
	var left := {}
	if not ex.get("cargo_unloaded", false):
		for k in ex.get("cargo", {}):
			left[k] = left.get(k, 0) + ex.cargo[k]
	for src in [ex.get("provisions", {}), ex.get("supplies", {})]:
		for k in src:
			left[k] = left.get(k, 0) + src[k]
	ex.unpack = left
	ex.unpack_tools = ex.get("tools", []).duplicate(true)
	if ex.has("lighter"):
		ex.unpack_tools.append({"type": "flint_and_steel", "dur": ex.lighter.dur})
	ex.unloading = true
	ex.unload_acc = 0.0
	if left.is_empty() and ex.unpack_tools.is_empty():
		sim.on_map("village", sim._finish_return)


## One tick of unpacking at the signpost.
static func _step_unload(sim: Sim) -> void:
	var ex := sim.expedition
	if not ex.get("unloading", false):
		return
	var hands: int = ex.party.filter(func(id): return sim.resident(id).map == "village").size()
	ex.unload_acc += Tuning.HAND_RATE * maxi(1, hands) * Tuning.DT
	var spot = sim.nearest_walkable(sim.sign_for(ex.dest))
	spot = spot if spot != null else sim.sign_for(ex.dest)
	while ex.unload_acc >= 1.0:
		ex.unload_acc -= 1.0
		if not ex.unpack.is_empty():
			var k: String = ex.unpack.keys()[0]
			sim._drop_cargo(spot, k, 1)
			ex.unpack[k] -= 1
			if ex.unpack[k] <= 0:
				ex.unpack.erase(k)
		elif not ex.unpack_tools.is_empty():
			var t: Dictionary = ex.unpack_tools.pop_front()
			sim._drop_cargo(spot, t.type, 1, t.dur)
		if ex.unpack.is_empty() and ex.unpack_tools.is_empty():
			sim._finish_return()
			return


## Sets items down as stacks that are hauled before anything else (issue #112).
static func _drop_cargo(sim: Sim, spot: Vector2i, type: String, n: int, dur := -1) -> void:
	if type == "obsidian":
		sim.stats.obsidian_home = true  # the portal can be planned (issue #147)
	var before := {}
	for k in sim.m.items:
		before[k] = true
	sim.drop_items(spot, type, n, dur)
	for k in sim.m.items:
		if not before.has(k):
			sim.m.items[k].cargo = true


## Everything's unpacked: the report, and the board is free again.
static func _finish_return(sim: Sim) -> void:
	var ex := sim.expedition
	var report := sim.expedition_report(ex)
	var b := sim.site(ex.board)
	if not b.is_empty():
		b.report = report
	if sim.realm_of(ex.dest) == "nether" and not sim.expedition_board().is_empty():  # the board shows the last report (issue #148)
		sim.expedition_board().report = report
	if ex.dest == Meadow.ID and ex.get("cargo", {}).get("wool", 0) > 0:
		sim.stats.meadow_wool = true  # a founding goal (issue #182)
	Visits.home(sim, ex)
	sim.expedition = {}
	sim.stats.expeditions = sim.stats.get("expeditions", 0) + 1
	sim.rev += 1
	sim._toast(". ".join(report) + ".", 0, b.get("id", 0))


## What an expedition brought back and what it cost, for the toast and the board (issue #112):
## ["Back from the old mine: 18 cobblestone, 9 coal", "3 meals eaten, 1 pickaxe broken", "Tomas injured"].
static func expedition_report(sim: Sim, ex: Dictionary) -> Array:
	var cargo: Dictionary = ex.get("cargo", {})
	var got: PackedStringArray = []
	var meals_back := 0
	for k in cargo:
		got.append(Defs.words(k, cargo[k]))
	for k in ex.get("provisions", {}):
		meals_back += ex.provisions[k]
	var name: String = sim.maps[ex.dest].name.to_lower()
	var lines: Array = ["Back from the %s: %s" % [name, ", ".join(got)] if not got.is_empty() else "Back from the %s with nothing %s" % [name, Adventures.def(ex.dest).got]]
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
	if not ex.get("abandoned", []).is_empty():  # issue #158
		lines.append("Left behind: " + ", ".join(ex.abandoned))
	if not ex.get("invited", []).is_empty():  # issue #253
		lines.append("Invited home: " + ", ".join(ex.invited))
	if not ex.get("traded", []).is_empty():  # issue #156
		lines.append("Traded: " + "; ".join(ex.traded))
	if ex.get("cart", false) and ex.has("road_out") and ex.has("road_home"):  # issue #124
		var took: float = float(ex.road_out[1] - ex.road_out[0] + ex.road_home[1] - ex.road_home[0]) / Tuning.TPS
		lines.append("By cart: %d s on the road there and back, about %d s saved" % [roundi(took), maxi(0, roundi(2.0 * sim.route_walk_time() - took))])
	var hurt: PackedStringArray = []
	for who in ex.get("hurt", {}):
		hurt.append("%s %s" % [who, "injured" if ex.hurt[who] == 1 else "seriously injured"])
	if not hurt.is_empty():
		lines.append(", ".join(hurt))
	return lines
