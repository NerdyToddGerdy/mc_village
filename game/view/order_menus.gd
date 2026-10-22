class_name OrderMenus
extends RefCounted
## The orders toolbar's menus (issues #93, #94): Gather, Paint and Build, each a button that opens
## a small menu above the toolbar. Entries are data, so a later order is a new row, not a new button.
##
## Each entry: id (the tool it switches on, or the template it places), name, sub (one line under
## the name), mark (the icon drawn for it), and optionally `unlock`, a condition it waits for:
##   "animals": a live animal exists on the map in view.
##   "founded": the founding is done (Slice 3's expedition board, issue #105).
##   "village": the map in view is the village; "meadow": it's the meadow (issue #139).
##   "pens": a pen is painted on the map in view (issue #139).

const MENUS := {
	"gather": {"name": "Gather", "entries": [
		{"id": "mine", "name": "Mine", "sub": "Trees and boulders. Shift: trees only. Alt: boulders only", "mark": "mine"},
		{"id": "chop", "name": "Chop trees", "sub": "Trees only", "mark": "chop"},
		{"id": "break", "name": "Break boulders", "sub": "Boulders only. Breaking them needs a pickaxe", "mark": "break"},
		{"id": "hunt", "name": "Hunt", "sub": "Sheep, cows and pigs, for wool, leather and meat. Shift: one kind only", "mark": "hunt", "unlock": "animals"},
		{"id": "lead", "name": "Lead to a pen", "sub": "Animals the party walks into a pen with room", "mark": "lead", "unlock": "pens"},
	]},
	"paint": {"name": "Paint", "entries": [
		{"id": "stock", "name": "Stockpile", "sub": "Where residents store what they gather", "mark": "stock", "unlock": "village"},
		{"id": "farm", "name": "Farm plot", "sub": "Open grass where residents grow wheat", "mark": "farm", "unlock": "village"},
		{"id": "pen", "name": "Pen", "sub": "A fenced pen for animals. The party builds it, a stick a fence", "mark": "pen", "unlock": "meadow"},
	]},
	"build": {"name": "Build", "entries": [
		{"id": "bench", "name": "Crafting bench", "sub": "4 logs. Reserves room for a workshop", "mark": "build"},
		{"id": "house", "name": "House", "sub": "8 cobblestone, then 16 planks and 4 logs, then 12 planks, then a bed", "mark": "build"},
		{"id": "fireplace", "name": "Fireplace", "sub": "6 cobblestone. Reserves room for a kitchen", "mark": "build"},
		{"id": "board", "name": "Expedition board", "sub": "6 planks and 4 sticks. Plans trips to the old mine. Reserves room for a map room", "mark": "build", "unlock": "founded"},
	]},
}

## The tools a Gather or Paint entry switches on: they mark or paint by dragging over the map.
const MARK_TOOLS := ["mine", "chop", "break", "hunt", "lead", "stock", "farm", "pen"]


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
	match e.get("unlock", ""):
		"animals":
			return sim.sheep.any(func(sh): return sh.alive)
		"founded":
			return Goals.current(sim) < 0
		"village":
			return sim.map_id == "village"
		"meadow":
			return sim.map_id == Meadow.ID
		"pens":
			return not sim.m.pens.is_empty()
	return true


static func entry(tool: String) -> Dictionary:
	for m in MENUS:
		for e in MENUS[m].entries:
			if e.id == tool:
				return e
	return {}
