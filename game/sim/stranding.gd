class_name Stranding
extends RefCounted
## stranding and rescue (issue #158), split out of sim.gd (#305). Every function takes the Sim it works on;
## Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## The meals a Nether party has: in its packs, and in the shelter's cache once it stands.
static func _meals_left(sim: Sim) -> int:
	var n := 0
	for k in sim.expedition.get("provisions", {}):
		n += sim.expedition.provisions[k]
	return n + sim.cache_meals()


## Whether the Nether party out now can't go on, and, if it can't, stranding it: its provisions gone with someone hungry, the
## portal dark with no flint and steel to relight it, or everyone seriously hurt. Also the countdown of a rescue window.
static func _check_stranded(sim: Sim) -> void:
	var ex := sim.expedition
	if ex.get("state", "") != "out":
		return
	if ex.has("stranded"):
		if ex.stranded.why.begins_with("the portal is dark") and sim.portal_lit():  # the village lit it again: they can go home (issue #158)
			ex.erase("stranded")
			sim._toast("The portal is lit again. The party is no longer stranded.", ex.party[0])
			return
		if sim.tick >= ex.stranded.until:
			_abandon(sim, "the rescue window passed")
		return
	var party: Array = ex.party.map(func(id): return sim.resident(id)).filter(func(r): return not r.is_empty())
	if party.is_empty() or not party.all(func(r): return Sim.realm_of(r.map) == "nether" and not r.away):
		ex.erase("dark_since")
		return
	var why := ""
	if _meals_left(sim) <= 0 and party.any(func(r): return r.hunger < Tuning.EAT_BELOW):
		why = "the provisions are gone"
	elif party.all(func(r): return r.get("hurt", 0) >= 2):
		why = "everyone is seriously hurt"
	elif ex.get("leg", "out") == "home" and not sim.portal_lit() and ex.get("lighter", {}).is_empty() and party.all(func(r): return r.map == NetherLanding.ID):
		ex.dark_since = ex.get("dark_since", sim.tick)
		if sim.tick - ex.dark_since >= int(Tuning.STRAND_WAIT * Tuning.TPS):
			why = "the portal is dark and no one has flint and steel"
	else:
		ex.erase("dark_since")
	if why != "":
		_strand(sim, party, why)


## The party can't go on: it shelters, and the game stops for the player with the costs shown (issue #158).
static func _strand(sim: Sim, party: Array, why: String) -> void:
	var ex := sim.expedition
	var at: String = party[0].map
	ex.stranded = {"why": why, "at": at, "since": sim.tick, "until": sim.tick + int(Tuning.RESCUE_WINDOW * Tuning.TPS)}
	for r in party:
		sim.fail_job(r)
		r.direct = null
		r.orders.clear()
	sim._toast("%s is stranded: %s." % [Sim.party_name(sim.slot), why], party[0].id)
	var cargo_text := "nothing" if ex.get("cargo", {}).is_empty() else ", ".join(ex.cargo.keys().map(func(k): return Defs.words(k, ex.cargo[k])))
	sim.on_map(at, func(): sim._ask("stranded", "%s is stranded: %s. It shelters %s. Plan a rescue from the expedition board within %d seconds. If none reaches it, the party walks home on its own, hurt, and leaves its cargo (%s) and spare gear behind." % [
		Sim.party_name(sim.slot), why, "in the shelter" if at == NetherLanding.ID and sim.shelter_site().get("done", false) else "where it stands", int(Tuning.RESCUE_WINDOW), cargo_text], [
		{"id": "wait", "label": "Shelter and wait", "cost": "%d seconds for a rescue, on what supplies are left." % int(Tuning.RESCUE_WINDOW)},
		{"id": "walk", "label": "Set out on their own", "cost": "Now, slowly and hurt, leaving the cargo (%s) and spare gear where they stand." % cargo_text},
	], party[0].id))


## The window is missed, or the player chose to walk: the party sets off on its own, slowly and hurt, leaving its cargo and
## spare tools where it stood as abandoned cargo a later mission can recover. Nobody dies.
static func _abandon(sim: Sim, why: String) -> void:
	var ex := sim.expedition
	var party: Array = ex.party.map(func(id): return sim.resident(id)).filter(func(r): return not r.is_empty())
	var left: Array = []
	var at: String = party[0].map if not party.is_empty() else NetherLanding.ID
	var cell: Vector2i = Sim.rcell(party[0]) if not party.is_empty() else sim.maps[at].entrance
	sim.on_map(at, func():
		for k in ex.get("cargo", {}):
			sim.drop_items(cell, k, ex.cargo[k])
			sim.m.abandoned.append({"item": k, "n": ex.cargo[k], "cell": cell})
			if not sim.m.drops_known.has(k) and sim.m.kind == "site":
				sim.m.drops_known.append(k)
			left.append(Defs.words(k, ex.cargo[k]))
		for t in ex.get("tools", []):
			sim.drop_items(cell, t.type, 1, t.dur)
			left.append(Defs.words(t.type, 1)))
	ex.cargo = {}
	ex.tools = []
	ex.erase("stranded")
	ex.abandoned = left
	ex.leg = "home"
	ex.home_why = why
	for r in party:
		sim.fail_job(r)
		r.direct = null
		r.orders.clear()
		sim.on_map(r.map, func(): sim.injure(r, 1, "the long walk home"))
	sim._toast("The party walked home on its own, hurt%s." % (", leaving %s behind" % ", ".join(left) if not left.is_empty() else ""), party[0].id if not party.is_empty() else 0)


## The countdown, supplies and cost shown for a stranded party, for the panel.
static func stranded_text(sim: Sim, ex: Dictionary) -> String:
	if not ex.has("stranded"):
		return ""
	var left := maxi(0, int((ex.stranded.until - sim.tick) / Tuning.TPS))
	var meals := 0
	for k in ex.get("provisions", {}):
		meals += ex.provisions[k]
	return "Stranded: %s. Rescue window %d:%02d. Supplies: %s, %s." % [ex.stranded.why, left / 60, left % 60, "%d %s" % [meals, "meal" if meals == 1 else "meals"], "flint and steel" if ex.get("lighter", {}).size() > 0 else "no flint and steel"]


## A stranded party member shelters in the shelter if the party is on the landing and it stands, else stays put.
static func _stranded_job(sim: Sim, r: Dictionary) -> Job:
	var sh := sim.shelter_site()
	var j := Job.new("rest", "Sheltering, waiting for a rescue", "the shelter" if sim.map_id == NetherLanding.ID and sh.get("done", false) else "where they stand")
	if sim.map_id == NetherLanding.ID and sh.get("done", false):
		j.step(sim._goto(sim.site_cells(sh), true))
	if r.get("hurt", 0) > 0:
		j.step({"op": "rest", "bed": false})
	j.step({"op": "wait_stranded"})
	return j


## A rescue party at the place it was sent: walk to the stranded, then reach them.
static func _rescue_job(sim: Sim, r: Dictionary, c: Vector2i):
	var lost: Dictionary = sim.expeditions.nether
	if not lost.has("stranded"):
		return null
	var who: Array = lost.party.map(func(id): return sim.resident(id)).filter(func(o): return not o.is_empty() and o.map == sim.map_id)
	if who.is_empty():
		return null
	var near: Dictionary = Sim.nearest(who.map(func(o): return {"cell": Sim.rcell(o), "id": o.id}), c)
	var j := Job.new("rescue", "Going to the stranded party", "the stranded party")
	if Sim.manhattan(near.cell, c) > 2:
		j.step(sim._goto([near.cell], false))
	j.step({"op": "rescue_reach"})
	return j


## Whether the party is out to delve the fortress (issue #157).
static func delving(sim: Sim) -> bool:
	return sim.expedition.get("target", {}).get("item", "") == "fortress"


## What a party member does in the fortress (issue #157): walk the halls to the salvage chest at the far end, the guards
## dealing with whatever comes. Once it's taken they pack what's lying about.
static func _delve_job(sim: Sim, r: Dictionary, c: Vector2i):
	if sim.m.salvage_taken or not delving(sim) or r.get("hurt", 0) > 0:
		return sim._stow_job(r, c)
	var j := Job.new("scout", "Delving the fortress", "the salvage chest")
	j.step(sim._goto([sim.m.salvage], true))
	j.step({"op": "open_salvage"})
	return j


## The first enchanted book found stops the game, and says what it teaches (issue #164), like the iron discovery.
static func _note_book(sim: Sim, item: String, r: Dictionary) -> void:
	if not Defs.ITEMS[item].has("book") or sim.stats.get("book_found", false):
		return
	sim.stats.book_found = true
	var what: String = Defs.ENCHANTS[Defs.ITEMS[item].book].name
	sim._ask("book", "%s found an enchanted book of %s. Brought home to an enchanting workshop, it would teach that recipe for good." % [r.get("name", "Someone"), what], [
		{"id": "ok", "label": "Carry on", "cost": "It's packed like any find, and comes home as cargo."},
	], r.get("id", 0))


## The salvage goes into the packs, what doesn't fit left on the chest's cell; taken once (issue #157).
static func _take_salvage(sim: Sim) -> void:
	if sim.m.salvage_taken:
		return
	sim.m.salvage_taken = true
	var contents: Dictionary = Defs.FORTRESS_SALVAGE.duplicate()
	var book := Defs.book_for("fortress", hash([sim.seed, "salvage"]))  # an enchanted book, favouring the protections (issue #164)
	contents[book] = 1
	for k in contents:
		var n: int = contents[k]
		var fit := mini(n, maxi(0, sim.pack_room()))
		if fit > 0:
			sim.expedition.cargo[k] = sim.expedition.cargo.get(k, 0) + fit
		if n - fit > 0:
			sim.drop_items(sim.m.salvage, k, n - fit)
	sim.rev += 1
	sim._toast("The party took the salvage, with an enchanted book: %s." % Defs.ITEMS[book].label, sim.expedition.party[0])
	_note_book(sim, book, sim.resident(sim.expedition.party[0]))


## What a party member does at the piglin camp (issue #156): with gold in the packs, walk up to a piglin and trade, down the
## table as shown. Once the trades are made, or the camp has turned hostile, there's nothing more to do.
static func _camp_job(sim: Sim, r: Dictionary, c: Vector2i):
	if not sim.trading() or sim.expedition.get("trade_done", false) or sim.m.hostile:
		return null
	var piglins := sim.m.creatures.filter(func(x): return x.alive and x.species == "piglin")
	if piglins.is_empty():
		return null
	var p: Dictionary = Sim.nearest(piglins, c)
	var j := Job.new("trade", "Going to the piglins to trade", "a piglin")
	j.step({"op": "chase", "target": p, "planned_for": null})
	j.step({"op": "trade"})
	return j


## The first row of the table the packs can pay for, or -1.
static func _next_trade(sim: Sim) -> int:
	var gold: int = sim.expedition.get("supplies", {}).get("gold_ingot", 0)
	for i in Defs.TRADES.size():
		var t: Dictionary = Defs.TRADES[i]
		var paid := 0
		for k in t.give:
			paid += t.give[k]
		var got := 0
		for k in t.get:
			got += t.get[k]
		if gold >= t.give.get("gold_ingot", 0) and sim.pack_room() + paid >= got:
			return i
	return -1


## What a party member does on the portal landing (issue #148): walk to the landmarks not yet seen, then wait.
static func _landing_job(sim: Sim, r: Dictionary, c: Vector2i):
	if sim.building_pline():  # the portal line's rails and the landing sim.station (issue #168)
		var pt := sim.pline_task(r.id)
		if not pt.is_empty():
			return sim._pline_job(pt, r.id)
	var sh := sim.shelter_site()
	if not sh.is_empty() and not sh.done and sim.expedition.get("shelter", false) and sh.builder == 0 and sim._supplies_cover(Tuning.SHELTER_COST):
		var bj := Job.new("build", "Going to build the shelter", "the shelter")
		bj.work = "build"
		bj.target = sh
		sh.builder = r.id
		bj.hold({"t": "builder", "site": sh})
		bj.step(sim._goto(sim.site_cells(sh), true))
		bj.step({"op": "work", "what": "shelter", "site": sh, "label": "Building the shelter"})
		return bj
	if not sh.is_empty() and sh.done and sim.expedition.get("stock", 0) > 0:  # meals left in the cache (issue #152)
		var cj := Job.new("stock", "Stocking the cache", "the cache")
		cj.step(sim._goto(sim.site_cells(sh), true))
		cj.step({"op": "cache_stock"})
		return cj
	if sim.scouting():  # out along the route to scout (issue #153)
		var rk: String = sim.expedition.target.get("route", "")
		if NetherRoute.ROUTES.has(rk) and not sim.maps[NetherRoute.ROUTES[rk].id].surveyed:
			var ej := Job.new("scout", "Setting out to scout the route", "the way out")
			ej.step(sim._goto([NetherRoute.ROUTES[rk].exit], true))
			ej.step({"op": "enter_route", "route": rk})
			return ej
		return null
	var left := sim.m.landmarks.filter(func(x): return not sim.m.landmarks_seen.has(x))
	if left.is_empty():
		return null
	var at: Vector2i = left[0]
	for x in left:
		if Sim.manhattan(x, c) < Sim.manhattan(at, c):
			at = x
	var j := Job.new("scout", "Surveying the landing", "a landmark")
	j.step(sim._goto([at], true))
	j.step({"op": "mark_seen", "cell": at})
	return j
