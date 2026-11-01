class_name Enchanting
extends RefCounted
## The enchanting workshop's rules (issues #165-#167), split out of sim.gd (#305). Every function takes
## the Sim it works on; Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## An item's name for tooltips and the planner: "Iron pickaxe · Efficiency (mines 30% faster)" for an enchanted one (issue #167).
static func item_title(type: String) -> String:
	var it: Dictionary = Defs.ITEMS[type]
	var base: String = Defs.BASE_ITEMS[Defs.base_type(type)].one
	base = base.substr(0, 1).to_upper() + base.substr(1)
	if not it.has("ench"):
		return base
	var e: String = it.ench
	var effect: String = {"efficiency": "%s %d%% faster" % ["chops" if it.get("tool", "") == "axe" else "mines", roundi((Tuning.EFFICIENCY_SPEED - 1.0) * 100.0)],
		"unbreaking": "wears %d%% slower" % roundi((1.0 - Tuning.UNBREAKING_WEAR) * 100.0),
		"protection": "%d%% fewer creature injuries" % roundi(Tuning.PROTECTION_CUT * 100.0),
		"fire_protection": "%d%% less fire and lava harm" % roundi(Tuning.FIRE_PROTECTION_CUT * 100.0)}[e]
	return "%s · %s (%s)" % [base, Defs.ENCHANTS[e].name, effect]


## What an enchantment does, in the words shown on the workshop's panel and the item's tooltip (issue #167).
static func enchant_text(ench: String) -> String:
	match ench:
		"efficiency":
			return "Tools only: work %d%% faster." % roundi((Tuning.EFFICIENCY_SPEED - 1.0) * 100.0)
		"unbreaking":
			return "Tools, swords and armor: wear %d%% slower." % roundi((1.0 - Tuning.UNBREAKING_WEAR) * 100.0)
		"protection":
			return "Armor only: %d%% fewer creature injuries." % roundi(Tuning.PROTECTION_CUT * 100.0)
		"fire_protection":
			return "Armor only: %d%% less harm from fire and lava." % roundi(Tuning.FIRE_PROTECTION_CUT * 100.0)
	return ""


## The village's finished enchanting workshop, or {}.
static func enchanting_workshop(sim: Sim) -> Dictionary:
	for s in sim.maps.village.sites:
		if s.tpl == "enchanting_workshop" and s.done:
			return s
	return {}


## Whether the workshop knows an enchantment.
static func enchant_known(sim: Sim, ench: String) -> bool:
	var ws := enchanting_workshop(sim)
	return not ws.is_empty() and ws.known.has(ench)


## Loose books lying about that would teach the workshop something it doesn't know yet, in the village.
static func learnable_books(sim: Sim) -> Array:
	if enchanting_workshop(sim).is_empty() or sim.map_id != "village":
		return []
	return sim.stacks_where(func(s): return Defs.ITEMS[s.type].has("book") and sim.avail(s) > 0 and not enchant_known(sim, Defs.ITEMS[s.type].book))


## What an Enchanter does: carry a new book to the workshop (issue #165), else work an order (#166).
static func _enchant_claim(sim: Sim, r: Dictionary, c: Vector2i):
	var ws := enchanting_workshop(sim)
	if ws.is_empty() or r.get("hurt", 0) > 0:
		return null
	var books := learnable_books(sim)
	if not books.is_empty():
		var st: Dictionary = sim.nearest(books, c)
		var j := sim._deliver_job(ws, st.type, 1, st)
		j.step({"op": "learn_book", "site": ws, "book": st.type})
		return sim._tagged(j, "enchant")
	return _enchant_order_job(sim, r, c, ws)


## The item types in the village that an enchantment can go on, plain and in a free stack, in the order of the items list
## (issue #166): what the workshop's panel offers for an order.
static func enchantable_types(sim: Sim, ench: String) -> Array:
	var out: Array = []
	for type in Defs.BASE_ITEMS:
		if Defs.ITEMS.has(type + "+" + ench) and not sim.stacks_where(func(s): return s.type == type and sim.avail(s) > 0).is_empty():
			out.append(type)
	return out


## Orders an enchantment onto an item type at the workshop (issue #166). Returns why it can't, or "". One enchantment to an item,
## and only a known recipe.
static func order_enchant(sim: Sim, ench: String, item: String) -> String:
	var ws := enchanting_workshop(sim)
	if ws.is_empty():
		return "Build an enchanting workshop first"
	if not Defs.ENCHANTS.has(ench):
		return "Enchant: no such enchantment"
	if not ws.known.has(ench):
		return "Enchant: recipe unknown"
	if Defs.ITEMS.get(item, {}).has("ench"):
		return "Enchant: item already enchanted"
	if not Defs.ITEMS.has(item + "+" + ench):
		return "Enchant: %s can't go on that" % Defs.ENCHANTS[ench].name
	ws.orders.append({"ench": ench, "item": item})
	sim.rev += 1
	return ""


static func cancel_enchant(sim: Sim, i: int) -> void:
	var ws := enchanting_workshop(sim)
	if not ws.is_empty() and i >= 0 and i < ws.orders.size():
		ws.orders.remove_at(i)
		sim.rev += 1


## What's missing at the workshop for its first order, as {item: how many more}, counting what's delivered and on the way.
static func enchant_missing(sim: Sim, ws: Dictionary) -> Dictionary:
	var out := {}
	if ws.orders.is_empty():
		return out
	var o: Dictionary = ws.orders[0]
	var need: Dictionary = Defs.ENCHANTS[o.ench].cost.duplicate()
	need[o.item] = 1
	for k in need:
		var short: int = need[k] - ws.store.get(k, 0) - ws.incoming.get(k, 0) - sim.free_count(k)
		if short > 0:
			out[k] = short
	return out


## Works the workshop's first order (issue #166): fetch what's missing, one delivery at a time, then enchant.
static func _enchant_order_job(sim: Sim, r: Dictionary, _c: Vector2i, ws: Dictionary):
	if ws.orders.is_empty() or ws.crafter != 0 or sim._cooling(ws):
		return null
	var o: Dictionary = ws.orders[0]
	var need: Dictionary = Defs.ENCHANTS[o.ench].cost.duplicate()
	need[o.item] = 1
	for k in need:  # what's still to be carried in
		var have: int = ws.store.get(k, 0) + ws.incoming.get(k, 0)
		if have >= need[k]:
			continue
		var src := sim.stacks_where(func(s): return s.type == k and sim.avail(s) > 0)
		if src.is_empty():
			return null  # something's missing: the stuck list says what
		var st: Dictionary = sim.nearest(src, sim.rcell(r))
		return sim._tagged(sim._deliver_job(ws, k, mini(mini(need[k] - have, sim.avail(st)), sim.carry_cap(r)), st), "enchant")
	for k in need:  # all of it is here: the work
		if ws.store.get(k, 0) < need[k]:
			return null  # (the last delivery is still on its way)
	var j := Job.new("craft", "Going to the enchanting workshop", "the enchanting workshop")
	j.work = "enchant"
	j.target = ws
	ws.crafter = r.id
	ws.crafting = Defs.ENCHANTS[o.ench].name
	j.hold({"t": "crafter", "site": ws})
	j.step(sim._goto(sim.site_cells(ws), true))
	j.step({"op": "work", "what": "enchant", "site": ws, "order": o, "label": "Enchanting: %s" % Defs.ITEMS[o.item + "+" + o.ench].one})
	return j
