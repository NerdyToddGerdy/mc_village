class_name Missions
extends RefCounted
## Split out of sim.gd (#305). Every function takes the Sim it works on; Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## The objectives a Nether plan can have (brief §8, Missions), in the planner's order: what it is, and when the party comes home
## by default.
const OBJECTIVES := {
	"survey": {"name": "Survey", "sub": "The first crossing: walk the landing's landmarks and build the shelter.", "returns": "the landing is surveyed and the shelter built"},
	"scout": {"name": "Scout", "sub": "Walk a route out of the landing and reveal it, with the site at its end.", "returns": "the route is scouted"},
	"gather": {"name": "Gather", "sub": "Bring back a material from a scouted site.", "returns": "the cargo target is reached"},
	"trade": {"name": "Trade", "sub": "Carry gold to the piglins, from the table shown first.", "returns": "the trades are made"},
	"build": {"name": "Build", "sub": "Raise a shelter, a crossing or a depot with materials the party carries.", "returns": "the building is done"},
	"fortress": {"name": "Fortress", "sub": "Delve the fortress entrance for blaze rods and rare salvage.", "returns": "the delve is done, or the party is hurt"},
	"rescue": {"name": "Rescue", "sub": "Reach a stranded party and bring them home.", "returns": "the stranded party is reached"},
}


## The destinations an objective can use now, as [{dest, label, route}], and why there are none when there aren't:
## a scouted route's site for a gather, trade or fortress mission, an unscouted route to scout, the landing to survey or build on.
static func objective_destinations(sim: Sim, obj: String) -> Array:
	var out: Array = []
	match obj:
		"survey":
			if not sim.maps[NetherLanding.ID].surveyed and sim.maps[NetherLanding.ID].known:
				out.append({"dest": NetherLanding.ID, "label": "The portal landing", "route": ""})
		"scout":
			if sim.maps[NetherLanding.ID].known:
				for rk in NetherRoute.ROUTES:
					if not sim.maps[NetherRoute.ROUTES[rk].id].surveyed:
						out.append({"dest": NetherLanding.ID, "label": NetherRoute.ROUTES[rk].name.substr(8), "route": rk})
		"gather", "trade", "fortress":
			for rk in {"gather": ["quartz", "fossil"], "trade": ["piglin"], "fortress": ["fortress"]}[obj]:  # a gather mission can go to any scouted site that gives something (issue #254)
				if sim.maps[NetherRoute.ROUTES[rk].site].known:
					out.append({"dest": NetherRoute.ROUTES[rk].site, "label": NetherRoute.ROUTES[rk].site_name.substr(8), "route": ""})
		"build":
			var sh := sim.shelter_site()
			if sim.maps[NetherLanding.ID].known and not sh.get("done", false):
				out.append({"dest": NetherLanding.ID, "label": "A shelter on the landing", "route": ""})
			if sim.maps[NetherRoute.ROUTES.quartz.id].surveyed and sim.maps[NetherRoute.ROUTES.quartz.site].known and not sim.nline_complete():  # issue #159
				out.append({"dest": NetherRoute.ROUTES.quartz.site, "label": "The Nether line to the quartz site", "route": "", "line": true})
			if sim.maps[NetherLanding.ID].known and not sim.portal_station().is_empty() and not sim.pline_nether_done():  # issue #168
				out.append({"dest": NetherLanding.ID, "label": "The portal line from the landing", "route": "", "pline": true})
		"rescue":  # a stranded party, if no rescue is already out (issue #158)
			var lost: Dictionary = sim.expeditions.nether
			if lost.has("stranded") and sim.expeditions.rescue.is_empty():
				out.append({"dest": lost.stranded.at, "label": "Rescue the party at the %s" % sim.maps[lost.stranded.at].name.substr(8).to_lower(), "route": ""})
	return out


## Why an objective has nowhere to go, in the player's words.
static func objective_why_none(sim: Sim, obj: String) -> String:
	if not sim.maps[NetherLanding.ID].known:
		return "Light the portal first"
	match obj:
		"survey":
			return "The landing is already surveyed"
		"scout":
			return "Every route is scouted"
		"gather":
			return "No site to gather from: scout the route to the quartz site or the fossil ridge first"
		"trade":
			return "No one to trade with: scout the route to the piglin camp first"
		"fortress":
			return "No fortress to delve: scout the route to the fortress first"
		"build":
			return "Nothing to build yet: the shelter stands"
		"rescue":
			return "A rescue party is already out" if not sim.expeditions.rescue.is_empty() else "No one is stranded"
	return ""


## A Nether plan for an objective, with its defaults, or {} when it has no destination (issue #154). `pick` is one of the
## objective's destinations; the first if left out.
static func nether_plan(sim: Sim, obj: String, pick := {}) -> Dictionary:
	var dests := sim.objective_destinations(obj)
	if dests.is_empty():
		return {}
	if pick.is_empty():
		pick = dests[0]
	var plan := sim.new_plan(pick.dest)
	plan.objective = obj
	plan.shelter = false
	plan.cobble = 0
	plan.planks = 0
	match obj:
		"survey":
			var build_it: bool = not sim.shelter_site().get("done", false)
			plan.shelter = build_it
			plan.cobble = Tuning.SHELTER_COST.cobble if build_it else 0
			plan.planks = Tuning.SHELTER_COST.plank if build_it else 0
		"scout":
			plan.target = {"item": "scout", "n": 1, "route": pick.route}
		"build":
			plan.target = {"item": "build", "n": 1}
			plan.shelter = true
			plan.cobble = Tuning.SHELTER_COST.cobble
			plan.planks = Tuning.SHELTER_COST.plank
			if pick.get("line", false):  # the Nether line: what's left to build, as much as three can carry (issue #159)
				plan.target = {"item": "line", "n": 1}
				plan.shelter = false
				sim._line_supplies(plan)
			if pick.get("pline", false):  # the portal line's Nether side (issue #168)
				plan.target = {"item": "pline", "n": 1}
				plan.shelter = false
				sim._pline_supplies(plan)
		"gather":  # the first thing the site gives, as much as 8, with a spare pickaxe (issue #155)
			plan.picks = 1
			var first: Array = sim.plan_targets(plan.dest)
			if not first.is_empty():
				sim.aim_plan(plan, first[0].item, 8)
		"trade":  # the gold the village has, up to what the packs take (issue #156)
			plan.target = {"item": "trade", "n": 1}
			plan.gold = mini(sim.free_count("gold_ingot"), 6)
		"fortress":
			plan.target = {"item": "fortress", "n": 1}
		"rescue":  # extra meals and a flint and steel (carried automatically) for the stranded; sets out with both slots taken (issue #158)
			plan.target = {"item": "rescue", "n": 1}
			plan.rescue = true
			plan.meals = 6
	return plan


## What a party is told before it commits (brief §8): the dangers known where it's going, the creatures about, the risks of
## the crossing, and what the objective needs. Lines of text.
static func plan_briefing(sim: Sim, plan: Dictionary) -> Array:
	var out: Array = []
	var obj: String = plan.get("objective", "survey")
	var dest: String = plan.dest
	var rk: String = plan.target.get("route", "") if plan.target.item == "scout" else ""
	var rep := sim.site_report(NetherRoute.ROUTES[rk].id if rk != "" else dest)
	if rep.hazards.is_empty():
		out.append("No dangers are known there yet" if not rep.visited else "No dangers known")
	for hz in rep.hazards:
		out.append("Danger: " + hz)
	if plan.party.any(func(id): return sim.needs_sword(sim.resident(id))) or not plan.party.any(func(id): return sim.resident(id).role in ["guard", "all"]):
		out.append("Risk: no one in the party can fight")
	if sim.realm_of(dest) == "nether" and sim.tool_items("sword", 0).is_empty() and not plan.party.any(func(id): return sim.resident(id).get("sword") != null):
		out.append("Risk: no sword in the village")
	if sim.stacks_where(func(s): return s.type == "flint_and_steel" and sim.avail(s) > 0).is_empty():
		out.append("Risk: no flint and steel to carry, so if the portal goes out the party waits for the village to light it")
	if plan.target.item == "line":  # issue #159
		out.append(sim.nline_text())
	if plan.target.item == "pline":  # issue #168
		out.append(sim.pline_text())
	if obj == "trade":  # the fixed table and the rule, before the party commits (issue #156)
		for t in Defs.TRADES:
			out.append("Trade: " + Defs.trade_text(t))
		out.append("Rule: " + Defs.PIGLIN_RULE)
	if obj == "rescue":
		out.append("A rescue may set out even when both parties are out")
	out.append("Comes home when %s" % OBJECTIVES[obj].returns)
	return out


## Whether the party is out to trade with the piglins (issue #156).
static func trading(sim: Sim) -> bool:
	return sim.expedition.get("target", {}).get("item", "") == "trade"


## Whether the party is out to scout a route (issue #153).
static func scouting(sim: Sim) -> bool:
	return sim.expedition.get("target", {}).get("item", "") == "scout"


## A plan to scout one of the routes out of the landing: "quartz", "piglin" or "fortress".
static func scout_plan(sim: Sim, route: String) -> Dictionary:
	var plan := sim.new_plan(NetherLanding.ID)
	plan.target = {"item": "scout", "n": 1, "route": route}
	return plan


## Whether the party is out to survey a place rather than to bring something back (issue #148).
static func surveying(sim: Sim) -> bool:
	return sim.expedition.get("target", {}).get("item", "") == "survey"
