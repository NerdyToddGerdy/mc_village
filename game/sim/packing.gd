class_name Packing
extends RefCounted
## Split out of sim.gd (#305). Every function takes the Sim it works on; Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## A plan's list of what to bring back, best first: rows {item, on, n} (n: how many are wanted, 0 for as much as
## fits), and `new` on one the village has just learned the place gives. The old single `target` is kept as the
## first row that's on, for what shows only one item.
static func cargo_rows(plan: Dictionary) -> Array:
	if plan.target.item == "pens":  # tending the pens brings back whatever's hunted, with no list
		return []
	var rows: Array = plan.get("list", []).filter(func(r): return r.on)
	if plan.get("clear", false):  # clearing the level wants all of it: every amount is "as much as fits" (issue #188)
		return rows.map(func(r): return {"item": r.item, "on": true, "n": 0})
	return rows


## Keeps `target` in step with the list: its first row that's on, preferring one with an amount. Tending the
## pens isn't a list, so it's left alone.
static func sync_target(plan: Dictionary) -> void:
	if plan.target.item in ["pens", "survey", "scout", "build", "trade", "fortress", "rescue", "line", "pline"]:
		return
	var rows := cargo_rows(plan)
	var pick: Dictionary = {}
	for r in rows:
		if r.n > 0:
			pick = r
			break
	if pick.is_empty() and not rows.is_empty():
		pick = rows[0]
	if not pick.is_empty():
		plan.target = {"item": pick.item, "n": maxi(1, pick.n)}


## The last trip packed for `dest`, as a new plan (issue #301): the same objective, list, meals, policy and party. A
## member who can't go now is left out, and the next resident who can goes in their place; pens' sticks and wheat and
## the Nether's building stock are worked out afresh, since what's needed has changed. Returns {plan, changes}, where
## `changes` says in words what is not the same, or {} when there is no last trip.
static func repeat_plan(sim: Sim, dest: String) -> Dictionary:
	if not sim.last_plans.has(dest):
		return {}
	var last: Dictionary = sim.last_plans[dest]
	var plan := sim.new_plan(dest)
	for k in last:
		if not k in ["party", "sticks", "wheat", "shelter", "cobble", "planks", "stock"]:
			plan[k] = last[k].duplicate(true) if last[k] is Dictionary or last[k] is Array else last[k]
	var changes: Array = []
	var party: Array = []
	var left_out: Array = []
	for id in last.party:
		var r := sim.resident(id)
		if r.is_empty():
			continue
		var why := sim.cant_join(r)
		if why == "":
			party.append(id)
		else:
			left_out.append("%s (%s)" % [r.name, why.to_lower()])
	for name in left_out:
		var sub: Dictionary = {}
		for r in sim.residents:
			if sim.cant_join(r) == "" and not party.has(r.id) and not last.party.has(r.id):
				sub = r
				break
		if sub.is_empty():
			changes.append("%s can't go, and nobody can take their place" % name)
		else:
			party.append(sub.id)
			changes.append("%s can't go; %s goes instead" % [name, sub.name])
	plan.party = party
	if party.is_empty():
		changes.append("nobody can go")
	return {"plan": plan, "changes": changes}


## Sets a plan's (or an expedition's) list to one wanted item first, then everything else its place gives as much
## as fits: the old single objective, for plans made in code.
static func aim_plan(sim: Sim, plan: Dictionary, item: String, n: int) -> void:
	var rows: Array = [{"item": item, "on": true, "n": n}]
	var known: Array = sim.plan_targets(plan.dest).map(func(x): return x.item)
	var others: Array = Adventures.def(plan.dest).others
	for o in others:
		if o != item and known.has(o):
			rows.append({"item": o, "on": true, "n": 0})
	plan.list = rows
	plan.target = {"item": item, "n": n}


## The list a new plan for `dest` starts with: the last one used there, kept to the items the village knows the
## place gives, with newly known ones added at the bottom marked New (issue #185).
static func cargo_list_for(sim: Sim, dest: String) -> Array:
	var known: Array = sim.plan_targets(dest).map(func(x): return x.item)
	var out: Array = []
	var kept: Array = sim.cargo_lists.get(dest, [])
	for r in kept:
		if known.has(r.item):
			out.append({"item": r.item, "on": r.on, "n": r.n})
	if kept.is_empty():  # never planned here: the defaults, in their order
		for d in Tuning.CARGO_DEFAULTS[Adventures.def(dest).cargo]:
			if known.has(d[0]):
				out.append({"item": d[0], "on": true, "n": d[1]})
	for item in known:
		if not out.any(func(r): return r.item == item):
			out.append({"item": item, "on": true, "n": 0, "new": not kept.is_empty()})
	return out


## Where an item stands in the party's list, from 0 (the best) among the rows that are on, or -1 when it isn't
## wanted at all: off, or not listed.
static func cargo_rank(plan: Dictionary, item: String) -> int:
	var i := 0
	for r in cargo_rows(plan):
		if r.item == item:
			return i
		i += 1
	return -1


## How many of a row's item the packs hold.
static func cargo_have(sim: Sim, item: String) -> int:
	return sim.expedition.get("cargo", {}).get(item, 0)


## How many of a row's amount is still to pack; a row for as much as fits is never done.
static func row_left(sim: Sim, row: Dictionary) -> int:
	return maxi(0, row.n - sim.cargo_have(row.item)) if row.n > 0 else 1 << 20


## Whether every row with an amount has its amount packed (and there is one): the policy "Target reached".
static func objective_met(sim: Sim) -> bool:
	var rows := sim.cargo_rows(sim.expedition).filter(func(r): return r.n > 0)
	return not rows.is_empty() and rows.all(func(r): return sim.cargo_have(r.item) >= r.n)


## What's still to pack for the rows with an amount, together; as-much-as-fits rows don't count.
static func objective_left(sim: Sim) -> int:
	if sim.tending():
		return 0
	var n := 0
	for r in sim.cargo_rows(sim.expedition):
		if r.n > 0:
			n += maxi(0, r.n - sim.cargo_have(r.item))
	return n


## Room the packs should keep for the rows above an item's, which come first.
static func _reserve_above(sim: Sim, item: String) -> int:
	var n := 0
	for r in sim.cargo_rows(sim.expedition):
		if r.item == item:
			break
		if r.n > 0:
			n += maxi(0, r.n - sim.cargo_have(r.item))
	return n


## Whether a block or an animal gives any item on the list (issue #185).
static func gives_wanted(sim: Sim, b: Dictionary) -> bool:
	return sim.cargo_rows(sim.expedition).any(func(r): return sim.gives(b, r.item) and sim.can_mine_item(r.item))


## Whether someone in the party, or a spare in the packs, has the iron pickaxe diamond ore needs (issue #186).
static func can_mine_diamond(sim: Sim) -> bool:
	return sim.can_mine_ore("diamond")


## Whether the party has a pickaxe good enough for an ore: iron for diamonds (issue #186), a diamond one for obsidian (#146).
static func can_mine_ore(sim: Sim, ore: String) -> bool:
	var need: int = Tuning.ORE_PICK_TIER.get(ore, 0)
	if need == 0:
		return true
	for id in sim.expedition.get("party", []):
		var r := sim.resident(id)
		if not r.is_empty() and r.pick != null and r.pick.tier >= need and r.get("hurt", 0) == 0:
			return true
	return sim.expedition.get("tools", []).any(func(t): return Defs.ITEMS[t.type].tier >= need)


## Whether the party could mine what gives this item: true unless it comes from an ore that needs a better pickaxe.
static func can_mine_item(sim: Sim, item: String) -> bool:
	for ore in Tuning.ORE_PICK_TIER:
		if Defs.ORES[ore].item == item:
			return sim.can_mine_ore(ore)
	return true


## What a block that needs a better pickaxe says when nobody has one.
static func pick_need_text(ore: String) -> String:
	if ore == "obsidian":
		return "Obsidian: needs a diamond pickaxe"
	return "%s needs an %s pickaxe" % [Defs.ORES[ore].name, Defs.TIER_NAMES[Tuning.ORE_PICK_TIER[ore]].to_lower()]


## "3 coal and 2 iron ore", or "what's on the list": what a plan or the party is out for, in words.
static func list_text(plan: Dictionary) -> String:
	if plan.get("clear", false):
		return "clear the level"
	var parts: PackedStringArray = []
	for r in cargo_rows(plan):
		if r.n > 0:
			parts.append(Defs.words(r.item, r.n))
	return " and ".join(parts) if not parts.is_empty() else "what's on the list"


static func objective_text(sim: Sim) -> String:
	return "what clears the level" if sim.expedition.get("clear", false) else sim.list_text(sim.expedition)


## A loose stack at the site that outranks something in the packs, with the cargo it would swap out: the
## lowest-priority item held, as {stack, drop}, or {}.
static func swap_candidate(sim: Sim) -> Dictionary:
	var rows := sim.cargo_rows(sim.expedition)
	var held: Array = rows.filter(func(r): return sim.cargo_have(r.item) > 0)
	if held.is_empty():
		return {}
	var worst: Dictionary = held[-1]
	var worst_rank := sim.cargo_rank(sim.expedition, worst.item)
	var best := {}
	var best_rank := worst_rank
	for st in sim.stacks_where(func(s): return sim.avail(s) > 0):
		var rk := sim.cargo_rank(sim.expedition, st.type)
		if rk >= 0 and rk < best_rank:
			best = st
			best_rank = rk
	return {} if best.is_empty() else {"stack": best, "drop": worst.item}


## The party's packs: each member carries PACK_CAPACITY items, shared by supplies and cargo.
static func pack_capacity(plan: Dictionary) -> int:
	return plan.party.size() * Tuning.PACK_CAPACITY + (Tuning.CART_CAPACITY if plan.get("cart_cap", false) else 0)


## Room the supplies take: a meal, a spare pickaxe, a stick or a wheat is one item each.
static func plan_supplies(plan: Dictionary) -> int:
	return plan.meals + plan.picks + plan.get("sticks", 0) + plan.get("wheat", 0) + plan.get("cobble", 0) + plan.get("planks", 0) + plan.get("gold", 0) + plan.get("rails", 0) + plan.get("minecarts", 0)


## Room left in the packs for what the party brings back.
static func cargo_room(plan: Dictionary) -> int:
	return pack_capacity(plan) - plan_supplies(plan)


## Meals kept for the walk home (brief §8): one each, unless the plan says they may be spent.
static func return_meals(plan: Dictionary) -> int:
	return plan.party.size() * Tuning.RETURN_MEALS


## About how many minutes the provisions feed the party at the site, leaving the return food alone
## unless the plan lets them spend it.
static func site_minutes(plan: Dictionary) -> float:
	var n: int = plan.party.size()
	if n == 0:
		return 0.0
	var meals: int = plan.meals - (0 if plan.spend_return else return_meals(plan))
	return maxf(0.0, meals * Tuning.MEAL_FOOD / (n * 100.0 / Tuning.HUNGER_EMPTY_TIME)) / 60.0


## What a party can be sent to bring back: the resources the village knows the site has.
static func plan_targets(sim: Sim, dest: String) -> Array:
	return sim.site_report(dest).resources.filter(func(x): return x.known)


## What stops a plan being confirmed, in the player's words; empty when it can be.
static func plan_problems(sim: Sim, plan: Dictionary) -> Array:
	var out: Array = []
	var sl := sim.slot_of_dest(plan.dest)  # a rescue sets out even when its slot is taken (issue #145)
	if plan.get("rescue", false):
		sl = "rescue"
	if not sim.expeditions[sl].is_empty():
		out.append("%s %s is already out" % ["An" if sl == "overworld" else "A", sim.party_name(sl)])
	if sim.expedition_board().is_empty():
		out.append("Build an expedition board first")
	if Adventures.def(plan.dest).sign == "dock" and sim.dock().is_empty():
		out.append("Build a dock first")
	if plan.target.item == "trade" and plan.get("gold", 0) <= 0:  # nothing to trade with (issue #156)
		out.append("Take some gold to trade")
	if plan.target.item == "scout":  # which route, and not one already scouted (issue #153)
		var rk: String = plan.target.get("route", "")
		if not NetherRoute.ROUTES.has(rk):
			out.append("Choose a route to scout")
		elif sim.maps[NetherRoute.ROUTES[rk].id].surveyed:
			out.append("That route is already scouted")
	if NetherRoute.site_ids().has(plan.dest) and not sim.maps[plan.dest].known:  # an unscouted site can't be a destination (issue #153)
		out.append("Nobody has scouted the way there yet")
	if sim.SLOT_REALM[sl] == "nether":  # a crossing needs the portal built and lit (issue #148)
		if sim.village_portal().is_empty():
			out.append("Build the portal first")
		elif not sim.portal_lit():
			out.append("The portal isn't lit")
	if plan.party.is_empty():
		out.append("Choose who goes")
	elif plan.party.size() > Tuning.PARTY_MAX:
		out.append("At most %d can go" % Tuning.PARTY_MAX)
	for id in plan.party:
		var r := sim.resident(id)
		var why := "Gone" if r.is_empty() else sim.cant_join(r)
		if why != "":
			out.append("%s can’t go: %s" % [r.get("name", "Someone"), why.to_lower()])
	if not plan.party.is_empty():
		if plan.meals < sim.return_meals(plan):
			out.append("Pack at least %d %s for the walk home" % [sim.return_meals(plan), "meal" if sim.return_meals(plan) == 1 else "meals"])
		var room := sim.cargo_room(plan)
		if room < 1:
			out.append("The supplies fill the packs. Take fewer, or more people")
		elif not plan.target.item in ["pens", "survey", "scout", "build", "trade", "fortress", "rescue", "line", "pline"]:
			var wanted := 0
			for r in sim.cargo_rows(plan):
				wanted += r.n
			if sim.cargo_rows(plan).is_empty():
				out.append("Choose something to bring back")
			elif wanted > room:
				out.append("The packs only have room for %d of what's wanted" % room)
	if plan.get("stock", 0) > 0 and plan.get("stock", 0) > maxi(0, plan.meals - sim.return_meals(plan)):
		out.append("Meals for the cache come out of the meals taken, past the walk home")
	if not plan.policy.values().has(true):
		out.append("Choose when the party comes home")
	return out


## Confirms a plan (issue #106): packing starts at the board. Nobody leaves until Depart.
## Returns why it can't, or "".
static func plan_expedition(sim: Sim, plan: Dictionary) -> String:
	var problems := sim.plan_problems(plan)
	if not problems.is_empty():
		return problems[0]
	if not plan.target.item in ["pens", "survey", "scout", "build", "trade", "fortress", "rescue", "line", "pline"]:  # each place keeps its last list (issue #185)
		sim.cargo_lists[plan.dest] = plan.get("list", []).map(func(r): return {"item": r.item, "on": r.on, "n": r.n})
	if not plan.get("rescue", false):
		sim.last_plans[plan.dest] = plan.duplicate(true)
	sim.use_slot("rescue" if plan.get("rescue", false) else sim.slot_of_dest(plan.dest))
	sim.expedition = plan.duplicate(true)
	sim.expedition.board = sim.village_portal().id if sim.in_nether() else sim.expedition_board().id  # a Nether party packs at the portal (issue #148)
	sim.expedition.state = "staging"
	sim.expedition.packed = {}
	sim.expedition.tools = []
	sim.rev += 1
	sim._toast("Packing for the %s has started. The party gathers at the board." % sim.maps[plan.dest].name.to_lower(), 0, sim.expedition.board)
	sim.use_slot("overworld")
	return ""


## Meals and spare pickaxes at the board so far, plus those on their way there when `incoming`.
static func packed(sim: Sim, incoming := false) -> Dictionary:
	var out := {"meals": 0, "picks": 0, "wheat": 0, "sticks": 0, "cobble": 0, "planks": 0, "gold": 0, "rails": 0, "minecarts": 0}
	var b := sim.site(sim.expedition.get("board", 0))
	if b.is_empty():
		return out
	for src in ([b.store, b.incoming] if incoming else [b.store]):
		for k in src:
			if Defs.MEALS.has(k):
				out.meals += src[k]
			elif Defs.ITEMS[k].get("tool", "") == "pick":
				out.picks += src[k]
			elif k == "wheat":
				out.wheat += src[k]
			elif k == "stick":
				out.sticks += src[k]
			elif k == "cobble":
				out.cobble += src[k]
			elif k == "plank":
				out.planks += src[k]
			elif k == "gold_ingot":
				out.gold += src[k]
			elif k == "rail":
				out.rails += src[k]
			elif k == "minecart":
				out.minecarts += src[k]
	return out


## What's still to be packed, less what's on its way: {meals, picks, wheat, sticks}.
static func pack_needs(sim: Sim) -> Dictionary:
	if sim.expedition.get("state", "") != "staging":
		return {"meals": 0, "picks": 0, "wheat": 0, "sticks": 0, "cobble": 0, "planks": 0, "gold": 0, "rails": 0, "minecarts": 0}
	var p := sim.packed(true)
	return {"meals": maxi(0, sim.expedition.meals - p.meals), "picks": maxi(0, sim.expedition.picks - p.picks),
		"wheat": maxi(0, sim.expedition.get("wheat", 0) - p.wheat), "sticks": maxi(0, sim.expedition.get("sticks", 0) - p.sticks),
		"cobble": maxi(0, sim.expedition.get("cobble", 0) - p.cobble), "planks": maxi(0, sim.expedition.get("planks", 0) - p.planks),
		"gold": maxi(0, sim.expedition.get("gold", 0) - p.gold), "rails": maxi(0, sim.expedition.get("rails", 0) - p.rails),
		"minecarts": maxi(0, sim.expedition.get("minecarts", 0) - p.minecarts)}


## What a plan can ask to have packed besides meals and spare pickaxes: [the plan's key, the item].
const SUPPLY_KINDS := [["wheat", "wheat"], ["sticks", "stick"], ["cobble", "cobble"], ["planks", "plank"], ["gold", "gold_ingot"], ["rails", "rail"], ["minecarts", "minecart"]]


## A delivery of supplies to the board (issue #107): meals first, then spare pickaxes, the best first.
static func _pack_job(sim: Sim, r: Dictionary, c: Vector2i):
	if sim.expedition.get("state", "") != "staging" or sim.map_id != "village":
		return null
	var b := sim.site(sim.expedition.board)
	if b.is_empty() or sim._cooling(b):
		return null
	var need := sim.pack_needs()
	if need.meals > 0:
		var src := sim.stacks_where(func(st): return Defs.MEALS.has(st.type) and sim.avail(st) > 0)
		if not src.is_empty():
			var st: Dictionary = sim.nearest(src, c)
			return sim._deliver_job(b, st.type, mini(mini(need.meals, sim.carry_cap(r)), sim.avail(st)), st)
	if need.picks > 0:
		var picks := sim.tool_items("pick", 0)
		if not picks.is_empty():
			picks.sort_custom(func(a, x): return Defs.ITEMS[a.type].tier > Defs.ITEMS[x.type].tier or (a.type == x.type and a.dur > x.dur))
			return sim._deliver_job(b, picks[0].type, 1, picks[0])
	for k in SUPPLY_KINDS:  # for the pens (issue #139) and the landing's shelter (issue #152)
		if need[k[0]] > 0:
			var src := sim.stacks_where(func(st): return st.type == k[1] and sim.avail(st) > 0)
			if not src.is_empty():
				var st: Dictionary = sim.nearest(src, c)
				return sim._deliver_job(b, st.type, mini(mini(need[k[0]], sim.carry_cap(r)), sim.avail(st)), st)
	return null


## The jobs that make each kind of supply the packs are short of, for a party member to help with.
const PREP_JOBS := {"meals": ["cook"], "picks": ["toolsmith", "craft"], "wheat": ["craft"], "sticks": ["craft"], "cobble": ["mason", "craft"],
	"planks": ["lumber", "craft"], "gold": ["craft"], "rails": ["craft", "toolsmith"], "minecarts": ["craft", "toolsmith"]}


## Help for a party that's still short of supplies, with nothing yet to carry: a member lends a hand at a
## workstation with work queued for what's missing (a cook at the fireplace for meals, the toolsmith's bench
## for spare pickaxes), so the party isn't idle at the board while others make it. Null when nothing's needed
## or nothing's queued.
static func _prep_job(sim: Sim, r: Dictionary, c: Vector2i):
	if sim.expedition.get("state", "") != "staging" or sim.map_id != "village" or r.get("hurt", 0) > 0:
		return null
	var need := sim.pack_needs()
	var jobs: Array = []
	for k in need:
		if need[k] > 0:
			for jb in PREP_JOBS.get(k, []):
				if not jobs.has(jb):
					jobs.append(jb)
	if jobs.is_empty():
		return null
	sim.keep_meals_stocked()
	sim.keep_made_stocked()
	sim.keep_tools_stocked()
	return sim._claim_kind(r, c, "station", jobs)


## Whether something that's still needed in the packs is lying ready to carry to the board.
static func _can_pack_more(sim: Sim) -> bool:
	if sim.expedition.get("state", "") != "staging" or sim.map_id != "village":
		return false
	var b := sim.site(sim.expedition.board)
	if b.is_empty() or sim._cooling(b):
		return false
	var need := sim.pack_needs()
	if need.meals > 0 and not sim.stacks_where(func(st): return Defs.MEALS.has(st.type) and sim.avail(st) > 0).is_empty():
		return true
	if need.picks > 0 and not sim.tool_items("pick", 0).is_empty():
		return true
	for k in SUPPLY_KINDS:
		if need[k[0]] > 0 and not sim.stacks_where(func(st): return st.type == k[1] and sim.avail(st) > 0).is_empty():
			return true
	return false


## A party member walks to the board and waits there to leave.
static func _stage_job(sim: Sim) -> Job:
	var b := sim.site(sim.expedition.board)
	var j := Job.new("stage", "Going to the expedition board", "the expedition board")
	j.step(sim._goto(sim.staging_cells(b), false))
	j.step({"op": "wait_board"})
	return j


## Whether a party member is waiting at the board.
static func at_board(sim: Sim, r: Dictionary) -> bool:
	return not r.is_empty() and r.job != null and r.job.kind == "stage" and r.job.i >= 1


## Why the party can't leave yet, or "" when Depart can go ahead (issue #107).
static func depart_blocker(sim: Sim, slot_id := "") -> String:
	if slot_id != "" and slot_id != sim.slot:
		return sim.on_slot(slot_id, sim.depart_blocker)
	if sim.expedition.get("state", "") != "staging":
		return "Nothing is being packed"
	if sim.in_nether() and not sim.portal_lit():
		return "The portal isn't lit"
	if NetherRoute.site_ids().has(sim.expedition.get("dest", "")) and sim.maps[sim.expedition.dest].pattern == "":  # scouted, but not built yet
		return "The way to the %s isn't built yet" % sim.maps[sim.expedition.dest].name.to_lower()
	var p := sim.packed()
	var meals: int = sim.expedition.meals - p.meals
	if meals > 0:
		return "Waiting for %d %s to pack" % [meals, "meal" if meals == 1 else "meals"]
	var picks: int = sim.expedition.picks - p.picks
	if picks > 0:
		return "Waiting for %d spare %s to pack" % [picks, "pickaxe" if picks == 1 else "pickaxes"]
	for k in SUPPLY_KINDS:
		var n: int = sim.expedition.get(k[0], 0) - p[k[0]]
		if n > 0:
			return "Waiting for %s to pack" % Defs.words(k[1], n)
	for id in sim.expedition.party:
		var r := sim.resident(id)
		if not sim.at_board(r):
			return "Waiting for %s" % r.get("name", "someone")
	return ""


## Depart (issue #107): the party leaves with what was packed, and is out of village labor from now on.
## Departure is always the player's call. Returns why it can't go, or "".
static func depart(sim: Sim, slot_id := "") -> String:
	if slot_id != "" and slot_id != sim.slot:
		return sim.on_slot(slot_id, sim.depart)
	var why := sim.depart_blocker()
	if why != "":
		return why
	var b := sim.site(sim.expedition.board)
	for k in b.store:
		if b.store[k] > 0 and not Defs.is_tool_item(k):
			sim.expedition.packed[k] = b.store[k]
	sim.expedition.tools = b.get("tools", []).duplicate(true)
	b.store = {}
	b.tools = []
	if sim.in_nether():  # the party carries a flint and steel, if the village has one, to relight the portal (issue #148)
		var ls := sim.stacks_where(func(s): return s.type == "flint_and_steel" and sim.avail(s) > 0)
		if not ls.is_empty():
			var stk: Dictionary = ls[0]
			sim.expedition.lighter = {"type": "flint_and_steel", "dur": stk.get("dur", sim.full_uses("flint_and_steel"))}
			stk.n -= 1
			if stk.n <= 0:
				sim.m.items.erase(stk.cell)
	sim.expedition.state = "out"
	sim.expedition.leg = "out"
	sim.expedition.cart = sim.cart_ready()  # the party rides the line if there's a cart at the village station (issue #124)
	sim.expedition.cart_cap = sim.cart_adds_room()
	sim.expedition.broken = 0
	sim.expedition.provisions = {}  # the meals in the packs (issue #109)
	sim.expedition.supplies = {}  # sticks and wheat for the pens (issue #139)
	for k in sim.expedition.packed:
		sim.expedition["provisions" if Defs.MEALS.has(k) else "supplies"][k] = sim.expedition.packed[k]
	sim.expedition.cargo = {}
	sim.expedition.hurt = {}
	var names: Array = []
	for id in sim.expedition.party:  # each walks to the signpost with the packs, then takes the road (issue #108)
		var r := sim.resident(id)
		sim.fail_job(r)
		r.direct = null
		r.orders.clear()
		r.note = null
		names.append(r.name)
	sim.rev += 1
	sim._toast("%s set off for the %s." % [sim.names_text(names), sim.maps[sim.expedition.dest].name.to_lower()], 0, b.id)
	return ""


## "Ada", "Ada and Tomas", "Ada, Tomas and Mira".
static func names_text(names: Array) -> String:
	if names.size() < 2:
		return "".join(names)
	return ", ".join(names.slice(0, -1)) + " and " + names[-1]


## A party member at the end of the road: they appear at the site's entrance, with the packs.
## A party member steps through the portal, either way (issue #148): the one way between the village and the
## Nether, where they arrive on the far side or at the staging area.
static func _cross_portal(sim: Sim, r: Dictionary, to: String) -> void:
	if to == "village":
		sim._arrive_home(r)
	else:
		sim._enter_level(r, NetherLanding.ID)  # every Nether place is reached by way of the landing (issue #155)


static func _arrive_at_site(sim: Sim, r: Dictionary) -> void:
	var id: String = r.trip
	if MineLevels.level_of(id) > 1:  # bound for a deeper level: in at the top, then down (issue #132)
		id = OldMine.ID
	r.away = false
	r.trip = ""
	sim._enter_level(r, id)


## A party member comes into a site map at its entrance: the end of the road, or through a door from
## the level above. The first of the party into the one they're bound for says so.
static func _enter_level(sim: Sim, r: Dictionary, id: String) -> void:
	var mp: SimMap = sim.maps[id]
	if id == NetherLanding.ID and sim.shelter_site().is_empty():  # the blueprint the first party builds (issue #152)
		sim.on_map(id, func(): sim.place_site("shelter", NetherLanding.SHELTER_AT))
	sim.move_to_map(r, id, mp.entrance)
	mp.known = true
	mp.visited = true
	if id != sim.expedition.get("dest", "") or sim.expedition.get("reached", "") == id:
		return
	sim.expedition.reached = id
	var prev := sim.use_map(id)
	sim._toast("The party reached the %s." % mp.name.to_lower(), r.id)
	sim.use_map(prev)


## Calls off an expedition that hasn't left (issue #107). What was packed is set down by the board,
## loose, and hauled back to the stockpile.
static func cancel_expedition(sim: Sim, slot_id := "") -> void:
	if slot_id != "" and slot_id != sim.slot:
		sim.on_slot(slot_id, sim.cancel_expedition)
		return
	if sim.expedition.get("state", "") != "staging":
		return
	if sim.map_id != "village":
		sim.on_map("village", sim.cancel_expedition)
		return
	var b := sim.site(sim.expedition.board)
	var party: Array = sim.expedition.party
	sim.expedition = {}
	for r in sim.residents:
		if r.job != null and ((r.job.kind == "stage" and party.has(r.id)) or (r.job.kind == "deliver" and is_same(r.job.target, b))):
			sim.fail_job(r)
	if not b.is_empty():
		var spot: Vector2i = sim.staging_cells(b)[1]
		for k in b.store:
			if b.store[k] > 0 and not Defs.is_tool_item(k):
				sim.drop_items(spot, k, b.store[k])
		for t in b.get("tools", []):
			sim.drop_items(spot, t.type, 1, t.dur)
		b.store = {}
		b.tools = []
	sim.rev += 1
	sim._toast("The expedition is called off. What was packed goes back to the stockpile.", 0, b.get("id", 0))


## The board's stuck reasons while packing (issue #107). Progress waits in the dim tier; nothing to
## pack is a blocker, with the fix.
static func _stuck_expedition(sim: Sim) -> void:
	if sim.building_line() and sim.expedition.get("state", "") == "out" and sim.map_id == NetherRoute.ROUTES.quartz.id:  # the track waits on a bridge (issue #159)
		var l := sim.nline()
		for i in Road.BASE_SEGMENTS:
			if l.laid[i] < Tuning.RAILS_PER_SEGMENT:
				if sim.nline_obstacle(i) and not l.bridged.has(i) and sim.expedition.get("supplies", {}).get("plank", 0) < Tuning.NETHER_BRIDGE_PLANKS:
					sim._add_stuck("Track", "needs %s bridged first" % NetherRoute.ROUTES.quartz.segments[i].name.to_lower(), Vector2(Road.SEGMENTS[i].x + 2, NetherRoute.LINE_ROW) + Vector2(0.5, 0.5), 0.6, "", 0)
				break
	if sim.expedition.has("stranded"):  # waiting for a rescue (issue #158)
		var lost: Dictionary = sim.expedition
		sim._add_stuck(sim.party_name(sim.slot), "stranded: %s" % lost.stranded.why, Vector2(sim.maps[lost.stranded.at].entrance) + Vector2(0.5, 0.5), 1.9, "", 0, false, true)
	if sim.expedition.get("state", "") != "staging":
		return
	var b := sim.site(sim.expedition.board)
	if b.is_empty() or b.map != sim.map_id:
		return
	var who := "Expedition" if sim.slot == "overworld" else sim.party_name(sim.slot)  # the Nether's names its party (issue #145)
	var at := Vector2(b.origin) + Vector2(0.5, 0.5)
	var p := sim.packed()
	var need := sim.pack_needs()
	var meals: int = sim.expedition.meals - p.meals
	if meals > 0:
		if need.meals > 0 and sim.stacks_where(func(st): return Defs.MEALS.has(st.type) and sim.avail(st) > 0).is_empty():
			sim._add_stuck(who, "No meals to pack. Cooks make them at the fireplace, or plan fewer", at, 1.9, "site", b.id)
		else:
			sim._add_stuck(who, "Waiting for %d %s to pack" % [meals, "meal" if meals == 1 else "meals"], at, 1.9, "site", b.id, false, true)
	var picks: int = sim.expedition.picks - p.picks
	if picks > 0:
		if need.picks > 0 and sim.tool_items("pick", 0).is_empty():
			sim._add_stuck(who, "No spare pickaxes to pack. Craft one at the bench, or plan fewer", at, 1.9, "site", b.id)
		else:
			sim._add_stuck(who, "Waiting for %d spare %s to pack" % [picks, "pickaxe" if picks == 1 else "pickaxes"], at, 1.9, "site", b.id, false, true)
	for id in sim.expedition.party:
		var r := sim.resident(id)
		if not r.is_empty() and not sim.at_board(r):
			sim._add_stuck(who, "Waiting for %s" % r.name, at, 1.9, "res", r.id, false, true)
