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
	# From the old mine (issue #103). Coal is smelting fuel; iron ore is smelted into ingots (#104).
	"coal": {"one": "coal", "many": "coal", "label": "Coal"},
	"iron_ore": {"one": "iron ore", "many": "iron ore", "label": "Iron ore"},
	"iron_ingot": {"one": "iron ingot", "many": "iron ingots", "label": "Iron"},
	"wood_axe": {"one": "wooden axe", "many": "wooden axes", "tool": "axe", "tier": 1},
	"wood_pick": {"one": "wooden pickaxe", "many": "wooden pickaxes", "tool": "pick", "tier": 1},
	"stone_axe": {"one": "stone axe", "many": "stone axes", "tool": "axe", "tier": 2},
	"stone_pick": {"one": "stone pickaxe", "many": "stone pickaxes", "tool": "pick", "tier": 2},
	"iron_axe": {"one": "iron axe", "many": "iron axes", "tool": "axe", "tier": 3},
	"iron_pick": {"one": "iron pickaxe", "many": "iron pickaxes", "tool": "pick", "tier": 3},
}

## A tool tier's name: 1 wooden, 2 stone, 3 iron (issue #104).
const TIER_NAMES := ["Bare", "Wooden", "Stone", "Iron"]

## The tally bar's Materials group, in order (issue #73). Raw mutton is counted under Food instead.
const MATERIALS := ["log", "plank", "stick", "cobble", "coal", "iron_ore", "iron_ingot", "wheat", "wool"]

## Ore blocks on a site map (issue #103): the item each drops when mined, and its name.
const ORES := {"coal": {"item": "coal", "name": "Coal ore"}, "iron": {"item": "iron_ore", "name": "Iron ore"}}

## `pattern` (bench) and `fuel` (fireplace) are display only, for the Craft panel's crafting grid and
## furnace (issue #95); they never change what a recipe costs. A pattern is three rows of three, each
## letter one item from PATTERN_KEYS, and uses exactly the recipe's inputs.
const RECIPES := [
	{"id": "planks", "name": "Planks", "inp": {"log": 1}, "out": {"plank": 4}, "pattern": ["   ", " L ", "   "]},
	{"id": "sticks", "name": "Sticks", "inp": {"plank": 2}, "out": {"stick": 4}, "pattern": [" P ", " P ", "   "]},
	{"id": "wood_axe", "name": "Wooden axe", "inp": {"plank": 3, "stick": 2}, "out": {"wood_axe": 1}, "pattern": ["PP ", "PS ", " S "]},
	{"id": "wood_pick", "name": "Wooden pickaxe", "inp": {"plank": 3, "stick": 2}, "out": {"wood_pick": 1}, "pattern": ["PPP", " S ", " S "]},
	{"id": "stone_axe", "name": "Stone axe", "inp": {"cobble": 3, "stick": 2}, "out": {"stone_axe": 1}, "pattern": ["CC ", "CS ", " S "]},
	{"id": "stone_pick", "name": "Stone pickaxe", "inp": {"cobble": 3, "stick": 2}, "out": {"stone_pick": 1}, "pattern": ["CCC", " S ", " S "]},
	# Iron tools (issue #104), from ingots smelted at the fireplace.
	{"id": "iron_axe", "name": "Iron axe", "inp": {"iron_ingot": 3, "stick": 2}, "out": {"iron_axe": 1}, "pattern": ["II ", "IS ", " S "]},
	{"id": "iron_pick", "name": "Iron pickaxe", "inp": {"iron_ingot": 3, "stick": 2}, "out": {"iron_pick": 1}, "pattern": ["III", " S ", " S "]},
	# Fireplace recipes (issue #46). "at" says which job building makes a recipe; the default is the bench.
	{"id": "bread", "name": "Bread", "inp": {"wheat": 3}, "out": {"bread": 1}, "at": "fireplace", "doing": "Baking bread"},
	{"id": "cooked_mutton", "name": "Cooked mutton", "inp": {"mutton": 1, "log": 1}, "out": {"cooked_mutton": 1}, "at": "fireplace", "doing": "Cooking mutton", "fuel": "log"},
	# Smelting (issue #104): coal is the fuel. It's Cook work, like everything at the fireplace.
	{"id": "smelt_iron", "name": "Smelt iron", "inp": {"iron_ore": 1, "coal": 1}, "out": {"iron_ingot": 1}, "at": "fireplace", "doing": "Smelting iron", "fuel": "coal"},
]

const PATTERN_KEYS := {"L": "log", "P": "plank", "S": "stick", "C": "cobble", "I": "iron_ingot"}

## Resident jobs (slice-2-spec.md §5), in the order the Jobs grid shows them.
const JOBS := ["mine", "haul", "build", "craft", "toolsmith", "farm", "cook", "hunt"]
const JOB_NAMES := {"mine": "Mine", "haul": "Haul", "build": "Build", "craft": "Craft", "toolsmith": "Toolsmith",
	"farm": "Farm", "cook": "Cook", "hunt": "Hunt"}
## "Tomas is a skilled farmer."
const JOB_SKILLED := {"mine": "miner", "haul": "hauler", "build": "builder", "craft": "crafter", "toolsmith": "toolsmith",
	"farm": "farmer", "cook": "cook", "hunt": "hunter"}

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
	# Where expeditions are planned and packed (issue #105). It grows into the map room.
	"board": {"name": "Expedition board", "size": Vector2i(1, 1), "plot": "map room", "stages": [
		{"name": "Expedition board", "verb": "needs", "cost": {"plank": 6, "stick": 4}},
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
