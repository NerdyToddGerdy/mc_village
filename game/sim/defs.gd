class_name Defs
extends RefCounted
## Items, recipes and building templates for Slice 1 (slice-1-spec.md §4, §6, §8).

const ITEMS := {
	"log": {"one": "log", "many": "logs", "label": "Logs"},
	"plank": {"one": "plank", "many": "planks", "label": "Planks"},
	"stick": {"one": "stick", "many": "sticks", "label": "Sticks"},
	"cobble": {"one": "cobblestone", "many": "cobblestone", "label": "Cobblestone"},
	"wool": {"one": "wool", "many": "wool", "label": "Wool"},
	"mutton": {"one": "raw mutton", "many": "raw mutton", "label": "Mutton"},
	"wheat": {"one": "wheat", "many": "wheat", "label": "Wheat"},
	"berries": {"one": "berry", "many": "berries", "label": "Berries"},
	"bread": {"one": "bread", "many": "bread", "label": "Bread"},
	"cooked_mutton": {"one": "cooked mutton", "many": "cooked mutton", "label": "Cooked mutton"},
	"wood_axe": {"one": "wooden axe", "many": "wooden axes", "tool": "axe", "tier": 1},
	"wood_pick": {"one": "wooden pickaxe", "many": "wooden pickaxes", "tool": "pick", "tier": 1},
	"stone_axe": {"one": "stone axe", "many": "stone axes", "tool": "axe", "tier": 2},
	"stone_pick": {"one": "stone pickaxe", "many": "stone pickaxes", "tool": "pick", "tier": 2},
}

const MATERIALS := ["log", "plank", "stick", "cobble", "wool", "mutton", "wheat"]

const RECIPES := [
	{"id": "planks", "name": "Planks", "inp": {"log": 1}, "out": {"plank": 4}},
	{"id": "sticks", "name": "Sticks", "inp": {"plank": 2}, "out": {"stick": 4}},
	{"id": "wood_axe", "name": "Wooden axe", "inp": {"plank": 3, "stick": 2}, "out": {"wood_axe": 1}},
	{"id": "wood_pick", "name": "Wooden pickaxe", "inp": {"plank": 3, "stick": 2}, "out": {"wood_pick": 1}},
	{"id": "stone_axe", "name": "Stone axe", "inp": {"cobble": 3, "stick": 2}, "out": {"stone_axe": 1}},
	{"id": "stone_pick", "name": "Stone pickaxe", "inp": {"cobble": 3, "stick": 2}, "out": {"stone_pick": 1}},
	# Fireplace recipes (issue #46). "at" says which job building makes a recipe; the default is the bench.
	{"id": "bread", "name": "Bread", "inp": {"wheat": 3}, "out": {"bread": 1}, "at": "fireplace", "doing": "Baking bread"},
	{"id": "cooked_mutton", "name": "Cooked mutton", "inp": {"mutton": 1, "log": 1}, "out": {"cooked_mutton": 1}, "at": "fireplace", "doing": "Cooking mutton"},
]

## Resident jobs (slice-2-spec.md §5), in the order the Jobs grid shows them.
const JOBS := ["mine", "haul", "build", "craft", "toolsmith", "farm", "cook", "hunt"]
const JOB_NAMES := {"mine": "Mine", "haul": "Haul", "build": "Build", "craft": "Craft", "toolsmith": "Toolsmith",
	"farm": "Farm", "cook": "Cook", "hunt": "Hunt"}

## Meals the fireplace's standing order keeps in stock.
const MEALS := ["bread", "cooked_mutton"]

## Job buildings ("station") have a crafting queue. Those with a "plot" reserve the 3×3 they'll need
## to grow into it later (slice-2-spec.md §8).
const TEMPLATES := {
	"bench": {"name": "Crafting bench", "size": Vector2i(1, 1), "station": true, "plot": "workshop", "stages": [
		{"name": "Bench", "verb": "needs", "cost": {"log": 4}},
	]},
	"fireplace": {"name": "Fireplace", "size": Vector2i(1, 1), "station": true, "plot": "kitchen", "stages": [
		{"name": "Fireplace", "verb": "needs", "cost": {"cobble": 6}},
	]},
	"house": {"name": "House", "size": Vector2i(5, 5), "stages": [
		{"name": "Foundation", "verb": "needs", "cost": {"cobble": 8}},
		{"name": "Walls", "verb": "need", "cost": {"plank": 16, "log": 4}},
		{"name": "Roof", "verb": "needs", "cost": {"plank": 12}},
		{"name": "Bed", "verb": "needs", "cost": {"wool": 3, "plank": 3}},
	]},
}


static func recipe(id: String) -> Dictionary:
	for r in RECIPES:
		if r.id == id:
			return r
	return {}


## The recipes a job building makes.
static func recipes_at(tpl: String) -> Array:
	return RECIPES.filter(func(r): return r.get("at", "bench") == tpl)


## The first recipe at this job building that outputs this item, used to fill in missing ingredients.
static func producer(item: String, tpl := "bench") -> Dictionary:
	for r in recipes_at(tpl):
		if r.out.has(item):
			return r
	return {}


static func is_tool_item(item: String) -> bool:
	return ITEMS[item].has("tool")


static func words(item: String, n: int) -> String:
	var it: Dictionary = ITEMS[item]
	return "%d %s" % [n, it.one if n == 1 else it.many]


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in cost:
		parts.append(words(k, cost[k]))
	return ", ".join(parts)
