class_name OrderMenus
extends RefCounted
## The orders toolbar's menus (issues #93, #94): Gather, Paint and Build, each a button that opens
## a small menu above the toolbar. Entries are data, so a later order is a new row, not a new button.
##
## Each entry: id (the tool it switches on, or the template it places), name, sub (one line under
## the name), mark (the icon drawn for it), and optionally `unlock`, a condition it waits for:
##   "animals": a live animal exists on the map in view.
##   "claims": the village has a land claim to use (issue #187).
##   "house": Ada's house is finished, so the founding's next goals can use it (the board, issue #182).
##   "village": the map in view is the village; "meadow": it's the meadow (issue #139).
##   "pens": a pen is painted on the map in view (issue #139).
## An entry can also carry `step`, the founding goal the book must have reached before the entry shows (issue #370):
## 99 is the village chapter. Both a `step` and an `unlock` have to hold.

const MENUS := {
	"gather": {"name": "Gather", "entries": [
		{"id": "mine", "name": "Mine", "sub": "Trees and boulders. Shift: trees only. Alt: boulders only", "mark": "mine"},
		{"id": "chop", "name": "Chop trees", "sub": "Trees only", "mark": "chop"},
		{"id": "break", "name": "Break boulders", "sub": "Boulders only. Breaking them needs a pickaxe", "mark": "break"},
		{"id": "keep", "name": "Keep", "sub": "Trees and boulders lumberjacks and stonemasons leave alone", "mark": "keep", "unlock": "village"},
		{"id": "hunt", "name": "Hunt", "sub": "Sheep, cows and pigs, for wool, leather and meat. Shift: one kind only", "mark": "hunt", "unlock": "animals"},
		{"id": "lead", "name": "Lead to a pen", "sub": "Animals the party walks into a pen with room", "mark": "lead", "unlock": "pens"},
	]},
	"paint": {"name": "Paint", "entries": [
		{"id": "pen", "name": "Pen", "sub": "A fenced pen for animals. The party builds it, a stick a fence", "mark": "pen", "unlock": "meadow"},
	]},
	"build": {"name": "Build", "entries": [
		{"id": "bench", "name": "Crafting bench", "sub": "4 logs. Reserves room for a workshop", "mark": "build"},
		{"id": "house", "name": "House", "sub": "6 planks and 3 wool: a tent that grows into a house and a building", "mark": "build", "step": 5},
		{"id": "fireplace", "name": "Fireplace", "sub": "6 cobblestone. Reserves room for a kitchen", "mark": "build", "step": 7},
		{"id": "chopping_block", "name": "Chopping block", "sub": "4 planks. Lumberjacks fell the trees around it and pile the logs. Reserves room for a sawmill", "mark": "build", "step": 13},
		{"id": "mason_bench", "name": "Mason's bench", "sub": "2 planks and 4 cobblestone. Stonemasons break the boulders around it. Reserves room for a mineshaft", "mark": "build", "step": 99},
		{"id": "toolsmith_bench", "name": "Toolsmith's bench", "sub": "4 planks and 3 cobblestone. A toolsmith works from it. Reserves room for an anvil", "mark": "build", "step": 99},
		{"id": "composter", "name": "Composter", "sub": "4 planks. A farmer works from it. Reserves room for a granary", "mark": "build", "step": 6},
		{"id": "lodge", "name": "Hunter's lodge", "sub": "6 logs and 2 planks. A hunter leads marked animals home from the meadow. Reserves room for a tannery", "mark": "build", "unlock": "board"},
		{"id": "village_pen", "name": "Pen", "sub": "12 sticks. A pen in the village for the animals a hunter leads home", "mark": "build", "unlock": "board"},
		{"id": "builder_table", "name": "Builder's table", "sub": "4 planks and 2 logs. A builder works from it. Reserves room for a builder's yard", "mark": "build", "step": 99},
		{"id": "cartographer_table", "name": "Cartographer's table", "sub": "6 planks. A cartographer surveys the land from it. Reserves room for a map room", "mark": "build", "unlock": "board"},
		{"id": "claim", "name": "Claim land", "sub": "A strip of new land, 8 cells deep, along an edge. A builder plants stakes (4 sticks). One claim for every 2 residents beyond the first two", "mark": "build", "unlock": "claims"},
		{"id": "storehouse", "name": "Storehouse", "sub": "6 cobblestone, 12 planks and 4 logs. Chests carried in store anything; stockpiles take the overflow. Reserves room to grow", "mark": "build", "step": 8},
		{"id": "enchanting_workshop", "name": "Enchanting workshop", "sub": "4 obsidian, 2 diamonds and 6 planks. An enchanter carries books to it to learn their recipes, and enchants gear. Reserves room for a library", "mark": "build", "unlock": "enchanting"},
		{"id": "portal_station", "name": "Portal station", "sub": "6 planks and 4 cobblestone, beside the portal. The village end of the portal line; a Build party lays the rest in the Nether. Reserves room for a freight loader", "mark": "build", "unlock": "portal_line"},
		{"id": "cache_sensor", "name": "Cache sensor", "sub": "2 redstone dust, 1 quartz and 2 cobblestone. Reads the Nether cache from here and is on when an item is below a threshold", "mark": "build", "unlock": "portal_line"},
		{"id": "condition", "name": "Condition", "sub": "2 redstone dust, 1 quartz and 2 cobblestone. Passes a signal along only while a fact holds: the portal is lit, the cart is home, the loader is idle", "mark": "build", "unlock": "portal_line"},
		{"id": "dispatcher", "name": "Dispatcher", "sub": "2 redstone dust, 1 quartz and 2 cobblestone, beside the portal station. When powered and the cart is loaded it asks you to approve the departure", "mark": "build", "unlock": "portal_line"},
		{"id": "freight_loader", "name": "Freight loader", "sub": "3 redstone dust, 1 quartz and 4 cobblestone, on the portal station's plot. When powered, haulers load the freight list onto the cart", "mark": "build", "unlock": "portal_line"},
		{"id": "portal", "name": "Nether portal", "sub": "10 obsidian, then flint and steel to light it. Parties bound for the Nether pack on the staging area in front. Reserves room for a portal hall", "mark": "build", "unlock": "portal"},
		{"id": "board", "name": "Expedition board", "sub": "6 planks and 4 sticks. Plans trips off the map. Reserves room for a map room", "mark": "build", "unlock": "house", "step": 9},
	]},
}

## The tools a Gather or Paint entry switches on: they mark or paint by dragging over the map.
const MARK_TOOLS := ["mine", "chop", "break", "keep", "hunt", "lead", "pen", "area", "room", "plots"]


## The menu an order tool belongs to, or "".
static func menu_of(tool: String) -> String:
	for m in MENUS:
		for e in MENUS[m].entries:
			if e.id == tool:
				return m
	return ""


## A menu's entries that are available now.
static func entries(menu: String, sim: Sim) -> Array:
	return MENUS[menu].entries.filter(func(e): return unlocked(e, sim))


static func unlocked(e: Dictionary, sim: Sim) -> bool:
	if e.has("step") and not Goals.reached(sim, e.step):  # the founding book hasn't got to it yet (issue #370)
		return false
	match e.get("unlock", ""):
		"animals":
			return sim.sheep.any(func(sh): return sh.alive)
		"house":
			return sim.stats.houses >= 1
		"claims":
			return sim.claims_available() > 0
		"village":
			return sim.map_id == "village"
		"meadow":
			return sim.map_id == Meadow.ID
		"board":  # once the expedition board is built (issues #321, #355)
			return sim.stats.get("built", {}).has("board")
		"pens":
			return not sim.m.pens.is_empty()
		"enchanting":  # once an enchanted book has been found, or a workshop stands (issue #165)
			return sim.stats.get("book_found", false) or sim.maps.village.sites.any(func(s): return s.tpl == "enchanting_workshop")
		"portal_line":  # once the portal stands (issue #168)
			return not sim.village_portal().is_empty()
		"portal":  # once obsidian has come home from the deep mine (issue #147)
			return sim.stats.get("obsidian_home", false) or sim.maps.village.sites.any(func(s): return s.tpl == "portal")
	return true


static func entry(tool: String) -> Dictionary:
	for m in MENUS:
		for e in MENUS[m].entries:
			if e.id == tool:
				return e
	return {}
