class_name Defs
extends RefCounted
## Items, recipes and building templates for Slice 1 (slice-1-spec.md §4, §6, §8).

const BASE_ITEMS := {
	"log": {"one": "log", "many": "logs", "label": "Logs", "group": "building"},
	"plank": {"one": "plank", "many": "planks", "label": "Planks", "group": "building"},
	"stick": {"one": "stick", "many": "sticks", "label": "Sticks", "group": "building"},
	"cobble": {"one": "cobblestone", "many": "cobblestone", "label": "Cobblestone", "group": "building"},
	# Dropped by a felled tree, and planted by a lumberjack (issue #177).
	"sapling": {"one": "sapling", "many": "saplings", "label": "Saplings", "group": "building"},
	# Crafted at the bench and carried into a storehouse (issue #189).
	"torch": {"one": "torch", "many": "torches", "label": "Torches", "group": "building"},
	"chest": {"one": "chest", "many": "chests", "label": "Chests", "group": "building"},
	# Cut at the mason's bench (issue #178), for the upgrades to come.
	"stone_brick": {"one": "stone brick", "many": "stone bricks", "label": "Stone bricks", "group": "building"},
	"wool": {"one": "wool", "many": "wool", "label": "Wool", "group": "animal"},
	"mutton": {"one": "raw mutton", "many": "raw mutton", "label": "Mutton", "group": "food"},
	"wheat": {"one": "wheat", "many": "wheat", "label": "Wheat", "group": "food"},
	"berries": {"one": "berry", "many": "berries", "label": "Berries", "group": "food"},
	"bread": {"one": "bread", "many": "bread", "label": "Bread", "group": "food"},
	"cooked_mutton": {"one": "cooked mutton", "many": "cooked mutton", "label": "Cooked mutton", "group": "food"},
	# Cows and pigs (issue #138).
	"leather": {"one": "leather", "many": "leather", "label": "Leather", "group": "animal"},
	"beef": {"one": "raw beef", "many": "raw beef", "label": "Beef", "group": "food"},
	"cooked_beef": {"one": "cooked beef", "many": "cooked beef", "label": "Cooked beef", "group": "food"},
	"porkchop": {"one": "raw porkchop", "many": "raw porkchops", "label": "Porkchops", "group": "food"},
	"cooked_porkchop": {"one": "cooked porkchop", "many": "cooked porkchops", "label": "Cooked porkchops", "group": "food"},
	# From the old mine (issue #103). Coal is smelting fuel; iron ore is smelted into ingots (#104).
	"coal": {"one": "coal", "many": "coal", "label": "Coal", "group": "ores"},
	"iron_ore": {"one": "iron ore", "many": "iron ore", "label": "Iron ore", "group": "ores"},
	"iron_ingot": {"one": "iron ingot", "many": "iron ingots", "label": "Iron", "group": "ores"},
	# From the deep levels of the old mine (issue #186): found only with an iron pickaxe, from level 4 down.
	"diamond": {"one": "diamond", "many": "diamonds", "label": "Diamond", "group": "ores"},
	# From the deeper levels (issue #146): gold for the piglins, obsidian and flint for the portal.
	"gold_ore": {"one": "gold ore", "many": "gold ore", "label": "Gold ore", "group": "ores"},
	"gold_ingot": {"one": "gold ingot", "many": "gold ingots", "label": "Gold", "group": "ores"},
	"obsidian": {"one": "obsidian", "many": "obsidian", "label": "Obsidian", "group": "ores"},
	"flint": {"one": "flint", "many": "flint", "label": "Flint", "group": "ores"},
	"flint_and_steel": {"one": "flint and steel", "many": "flint and steels", "uses": Tuning.FLINT_STEEL_USES, "group": "tools"},
	# From the deep mine (issues #163, #170): lapis is the common cost of every enchantment, redstone powers the devices.
	"lapis": {"one": "lapis lazuli", "many": "lapis lazuli", "label": "Lapis", "group": "ores"},
	"redstone": {"one": "redstone dust", "many": "redstone dust", "label": "Redstone", "group": "ores"},
	# From the quartz site (issue #155): stockpiled for Slice 6; nothing the village needs to survive.
	"quartz": {"one": "nether quartz", "many": "nether quartz", "label": "Quartz", "group": "ores"},
	"glowstone": {"one": "glowstone", "many": "glowstone", "label": "Glowstone", "group": "ores"},
	# Enchanted books (issues #164, #28): each names one enchantment, and taught to the workshop it's learned for good.
	"book_efficiency": {"one": "enchanted book of Efficiency", "many": "enchanted books of Efficiency", "label": "Efficiency book", "book": "efficiency", "group": "tools"},
	"book_unbreaking": {"one": "enchanted book of Unbreaking", "many": "enchanted books of Unbreaking", "label": "Unbreaking book", "book": "unbreaking", "group": "tools"},
	"book_protection": {"one": "enchanted book of Protection", "many": "enchanted books of Protection", "label": "Protection book", "book": "protection", "group": "tools"},
	"book_fire_protection": {"one": "enchanted book of Fire protection", "many": "enchanted books of Fire protection", "label": "Fire protection book", "book": "fire_protection", "group": "tools"},
	# What the piglins trade (issue #156).
	"string": {"one": "string", "many": "string", "label": "String", "group": "ores"},
	"fire_resistance": {"one": "fire-resistance supply", "many": "fire-resistance supplies", "label": "Fire resistance", "group": "ores"},
	# What the Nether's creatures leave (issue #151), carried home as cargo.
	"magma_cream": {"one": "magma cream", "many": "magma cream", "label": "Magma cream", "group": "ores"},
	"end_stone": {"one": "block of End stone", "many": "blocks of End stone", "label": "End stone", "group": "ores"},  # what the stronghold's portal frame gives (issue #411)
	"bone": {"one": "bone", "many": "bones", "label": "Bones", "group": "ores"},
	"blaze_rod": {"one": "blaze rod", "many": "blaze rods", "label": "Blaze rods", "group": "ores"},
	# What the village's night mobs leave (issue #358).
	"rotten_flesh": {"one": "rotten flesh", "many": "rotten flesh", "label": "Rotten flesh", "group": "ores"},
	"arrow": {"one": "arrow", "many": "arrows", "label": "Arrows", "group": "ores"},
	# What the caves' creatures leave, by biome (issue #241).
	"slime_ball": {"one": "slime ball", "many": "slime balls", "label": "Slime balls", "group": "ores"},
	"nautilus_shell": {"one": "nautilus shell", "many": "nautilus shells", "label": "Nautilus shells", "group": "ores"},
	"husk_dust": {"one": "husk dust", "many": "husk dust", "label": "Husk dust", "group": "ores"},
	# The line to the mine (Slice 4, issue #120). A minecart is one big item: one to a cell, hauled like a tool.
	"rail": {"one": "rail", "many": "rails", "label": "Rails", "group": "building"},
	"minecart": {"one": "minecart", "many": "minecarts", "label": "Minecarts", "single": true, "group": "building"},
	"wood_axe": {"one": "wooden axe", "many": "wooden axes", "tool": "axe", "tier": 1, "group": "tools"},
	"wood_pick": {"one": "wooden pickaxe", "many": "wooden pickaxes", "tool": "pick", "tier": 1, "group": "tools"},
	"stone_axe": {"one": "stone axe", "many": "stone axes", "tool": "axe", "tier": 2, "group": "tools"},
	"stone_pick": {"one": "stone pickaxe", "many": "stone pickaxes", "tool": "pick", "tier": 2, "group": "tools"},
	"iron_sword": {"one": "iron sword", "many": "iron swords", "tool": "sword", "tier": 3, "uses": Tuning.SWORD_USES, "group": "tools"},
	"iron_chestplate": {"one": "iron chestplate", "many": "iron chestplates", "label": "Iron chestplates", "armor": "chest", "tier": 3, "uses": Tuning.IRON_ARMOR_USES, "guard": Tuning.IRON_GUARD, "group": "tools"},
	"iron_axe": {"one": "iron axe", "many": "iron axes", "tool": "axe", "tier": 3, "group": "tools"},
	"iron_pick": {"one": "iron pickaxe", "many": "iron pickaxes", "tool": "pick", "tier": 3, "group": "tools"},
	"diamond_axe": {"one": "diamond axe", "many": "diamond axes", "tool": "axe", "tier": 4, "group": "tools"},
	"diamond_pick": {"one": "diamond pickaxe", "many": "diamond pickaxes", "tool": "pick", "tier": 4, "group": "tools"},
	# Leather armor (Slice 3.5, issue #140): worn, one piece to a slot, and worn out by hazards.
	"leather_cap": {"one": "leather cap", "many": "leather caps", "label": "Leather caps", "armor": "head", "tier": 1, "group": "tools"},
	"leather_tunic": {"one": "leather tunic", "many": "leather tunics", "label": "Leather tunics", "armor": "chest", "tier": 1, "group": "tools"},
	"leather_trousers": {"one": "pair of leather trousers", "many": "pairs of leather trousers", "label": "Leather trousers", "armor": "legs", "tier": 1, "group": "tools"},
	"leather_boots": {"one": "pair of leather boots", "many": "pairs of leather boots", "label": "Leather boots", "armor": "feet", "tier": 1, "group": "tools"},
}

## Where armor is worn (issue #140), head to feet, and what each slot's piece is called.
const ARMOR_SLOTS := ["head", "chest", "legs", "feet"]
const SLOT_NAMES := {"head": "Cap", "chest": "Tunic", "legs": "Trousers", "feet": "Boots"}

## A tool tier's name: 1 wooden, 2 stone, 3 iron (issue #104).
const TIER_NAMES := ["Bare", "Wooden", "Stone", "Iron", "Diamond"]

## Every item: the base ones, and for each tool, sword and armor an **enchanted** variant for each enchantment that can go on it
## (issue #166), named "iron_pick+efficiency". A variant is the same item with `ench` set, so wear, carrying, dropping and saving
## work as they always have, and an item can only ever hold one enchantment.
static var ITEMS: Dictionary = _build_items()


static func _build_items() -> Dictionary:
	var out: Dictionary = BASE_ITEMS.duplicate(true)
	for type in BASE_ITEMS:
		var it: Dictionary = BASE_ITEMS[type]
		var kind: String = it.get("tool", "armor" if it.has("armor") else "")
		if kind == "":
			continue
		for e in ENCHANTS:
			if kind in ENCHANTS[e].applies:
				var v: Dictionary = it.duplicate(true)
				v.ench = e
				v.base = type
				v.one = "%s of %s" % [it.one, ENCHANTS[e].name]
				v.many = "%s of %s" % [it.many, ENCHANTS[e].name]
				if v.has("label"):
					v.label = "%s (%s)" % [it.label, ENCHANTS[e].name]
				out[type + "+" + e] = v
	return out


## The type of an item with its enchantment taken off: "iron_pick+efficiency" is "iron_pick".
static func base_type(type: String) -> String:
	return type.get_slice("+", 0)


## The tally bar's groups (issue #141), in order. Each item names its group in ITEMS; a group's
## dropdown lists its items in ITEMS order.
const TALLY_GROUPS := [["building", "Building"], ["food", "Food"], ["tools", "Tools and armor"], ["animal", "Animal goods"], ["ores", "Ores"]]
const MAX_PINNED := 4  ## Items the player can pin to the tally bar.


## A tally group's items, in ITEMS order.
static func group_items(group: String) -> Array:
	return ITEMS.keys().filter(func(k): return ITEMS[k].group == group)

## Raw meat (issue #138): left for the fireplace, eaten only as a last resort.
const RAW_MEATS := ["mutton", "beef", "porkchop"]

## The animals residents hunt (issues #42, #138). What each drops is in Tuning.ANIMAL_DROPS.
const SPECIES := {
	"sheep": {"name": "Sheep", "one": "sheep", "many": "sheep", "young": "lamb", "youngs": "lambs"},
	"cow": {"name": "Cow", "one": "cow", "many": "cows", "young": "calf", "youngs": "calves"},
	"pig": {"name": "Pig", "one": "pig", "many": "pigs", "young": "piglet", "youngs": "piglets"},
}

## The Nether's creatures (issue #151): health, how a blow from them lands (`hit` the chance, `serious` the chance a hit
## knocks someone down), the seconds between blows, how close they strike from (`reach`: 1 is next to them), how far they
## notice someone (`notice`, 0 for a creature that only fights back), and what they leave.
const CREATURES := {
	"magma_cube": {"name": "Magma cube", "hp": 8, "hit": 0.4, "serious": 0.25, "cool": 1.6, "reach": 1, "notice": 5, "drops": {"magma_cream": 1}},
	"zombified_piglin": {"name": "Zombified piglin", "hp": 10, "hit": 0.5, "serious": 0.3, "cool": 1.4, "reach": 1, "notice": 0, "drops": {"gold_ingot": 1}},
	"skeleton": {"name": "Skeleton", "hp": 6, "hit": 0.3, "serious": 0.2, "cool": 2.0, "reach": 4, "notice": 6, "drops": {"bone": 1}},
	"piglin": {"name": "Piglin", "hp": 12, "hit": 0.5, "serious": 0.3, "cool": 1.4, "reach": 1, "notice": 0, "drops": {}},
	"villager": {"name": "Villager", "hp": 8, "hit": 0.0, "serious": 0.0, "cool": 9.0, "reach": 0, "notice": 0, "drops": {}},  # a friendly folk of another village (issue #253)
	"piglin_brute": {"name": "Piglin brute", "hp": 20, "hit": 0.6, "serious": 0.35, "cool": 1.2, "reach": 1, "notice": 6, "drops": {"gold_ingot": 2}},  # the bastion's fighters (issue #264)
	"blaze": {"name": "Blaze", "hp": 10, "hit": 0.3, "serious": 0.3, "cool": 2.2, "reach": 5, "notice": 7, "drops": {"blaze_rod": 1}},
	# The village's night (issues #358, #359): mobs that come for residents, and the golem that keeps them off.
	"zombie": {"name": "Zombie", "hp": 8, "hit": 0.4, "serious": 0.15, "cool": 1.6, "reach": 1, "notice": 0, "drops": {"rotten_flesh": 1}},
	"spider": {"name": "Spider", "hp": 6, "hit": 0.35, "serious": 0.1, "cool": 1.2, "reach": 1, "notice": 0, "drops": {"string": 1}},
	# The caves' (issue #241): one for each biome, with its own drop.
	"slime": {"name": "Slime", "hp": 6, "hit": 0.35, "serious": 0.1, "cool": 1.4, "reach": 1, "notice": 5, "drops": {"slime_ball": 1}},
	"drowned": {"name": "Drowned", "hp": 8, "hit": 0.4, "serious": 0.15, "cool": 1.6, "reach": 1, "notice": 5, "drops": {"nautilus_shell": 1}},
	"husk": {"name": "Husk", "hp": 10, "hit": 0.45, "serious": 0.2, "cool": 1.5, "reach": 1, "notice": 6, "drops": {"husk_dust": 1}},
	"golem": {"name": "Iron golem", "hp": 100, "hit": 0.0, "serious": 0.0, "cool": 1.2, "reach": 1, "notice": 0, "drops": {}},
}

## The piglins' fixed trade table (issue #156), in the order a trading party works down it: what they take, and what they give.
## It's shown in the site report and the planner before a party commits, and never changes or rolls.
const TRADES := [
	{"give": {"gold_ingot": 8}, "get": {"book_efficiency": 1}},  # books at a fixed price (issue #164)
	{"give": {"gold_ingot": 6}, "get": {"book_unbreaking": 1}},
	{"give": {"gold_ingot": 2}, "get": {"obsidian": 1}},
	{"give": {"gold_ingot": 2}, "get": {"string": 3}},
	{"give": {"gold_ingot": 1}, "get": {"flint": 2}},
	{"give": {"gold_ingot": 4}, "get": {"fire_resistance": 1}},
]
## The four enchantments (issues #165-#167): what each costs at the workshop (lapis plus one ingredient), what it can go on
## (a tool kind, "sword" or "armor"), and what it does. One to an item, and no rerolls.
const ENCHANTS := {
	"efficiency": {"name": "Efficiency", "book": "book_efficiency", "cost": {"lapis": 2, "quartz": 1}, "applies": ["axe", "pick"]},
	"unbreaking": {"name": "Unbreaking", "book": "book_unbreaking", "cost": {"lapis": 2, "iron_ingot": 1}, "applies": ["axe", "pick", "sword", "armor"]},
	"protection": {"name": "Protection", "book": "book_protection", "cost": {"lapis": 3, "iron_ingot": 2}, "applies": ["armor"]},
	"fire_protection": {"name": "Fire protection", "book": "book_fire_protection", "cost": {"lapis": 3, "magma_cream": 1}, "applies": ["armor"]},
}


## How likely each enchantment is to turn up in each place (issue #164): fortress salvage favours the protections, the deep
## mine's chests the tools' enchantments.
const BOOK_WEIGHTS := {
	"fortress": {"efficiency": 1, "unbreaking": 1, "protection": 3, "fire_protection": 3},
	"mine": {"efficiency": 3, "unbreaking": 3, "protection": 1, "fire_protection": 1},
}


## The book (an item type) a place gives for a number: the same number, the same book.
static func book_for(source: String, h: int) -> String:
	var w: Dictionary = BOOK_WEIGHTS[source]
	var total := 0
	for k in w:
		total += w[k]
	var pick := absi(h) % total
	for k in w:
		pick -= w[k]
		if pick < 0:
			return "book_" + k
	return "book_efficiency"


## What the fortress's salvage chest holds (issue #157), provisional.
const FORTRESS_SALVAGE := {"diamond": 1, "iron_ingot": 4, "gold_ingot": 3, "blaze_rod": 1}
## The rule that turns the piglins hostile, shown up front (brief §8).
const PIGLIN_RULE := "Piglins turn hostile if anyone in the party strikes one"


## "2 gold ingots for 1 obsidian".
static func trade_text(t: Dictionary) -> String:
	var give: PackedStringArray = []
	for k in t.give:
		give.append(words(k, t.give[k]))
	var get: PackedStringArray = []
	for k in t.get:
		get.append(words(k, t.get[k]))
	return "%s for %s" % [", ".join(give), ", ".join(get)]


## Ore blocks on a site map (issue #103): the item each drops when mined, and its name.
const ORES := {"coal": {"item": "coal", "name": "Coal ore"}, "iron": {"item": "iron_ore", "name": "Iron ore"}, "diamond": {"item": "diamond", "name": "Diamond ore"},
	"chest": {"item": "book_efficiency", "name": "Chest"},  # a chest in the rock holds one book, named by the block (issue #164)
	"lapis": {"item": "lapis", "name": "Lapis ore"}, "redstone": {"item": "redstone", "name": "Redstone ore"},
	"quartz": {"item": "quartz", "name": "Nether quartz ore"}, "fossil": {"item": "bone", "name": "Nether fossil"}, "glowstone": {"item": "glowstone", "name": "Glowstone"},
	"gold": {"item": "gold_ore", "name": "Gold ore"}, "end_portal": {"item": "end_stone", "name": "Portal frame"}, "obsidian": {"item": "obsidian", "name": "Obsidian"}, "gravel": {"item": "flint", "name": "Gravel"}}

## `pattern` (bench) and `fuel` (fireplace) are display only, for the Craft panel's crafting grid and
## furnace (issue #95); they never change what a recipe costs. A pattern is three rows of three, each
## letter one item from PATTERN_KEYS, and uses exactly the recipe's inputs.
const RECIPES := [
	{"id": "planks", "name": "Planks", "inp": {"log": 1}, "out": {"plank": 4}, "pattern": ["   ", " L ", "   "]},
	{"id": "sticks", "name": "Sticks", "inp": {"plank": 2}, "out": {"stick": 4}, "pattern": [" P ", " P ", "   "]},
	{"id": "wood_axe", "name": "Wooden axe", "inp": {"plank": 3, "stick": 2}, "out": {"wood_axe": 1}, "pattern": ["PP ", "PS ", " S "]},
	{"id": "wood_pick", "name": "Wooden pickaxe", "inp": {"plank": 3, "stick": 2}, "out": {"wood_pick": 1}, "pattern": ["PPP", " S ", " S "]},
	{"id": "torch", "name": "Torches", "inp": {"coal": 1, "stick": 1}, "out": {"torch": 4}, "pattern": ["   ", " K ", " S "], "step": 99},
	{"id": "chest", "name": "Chest", "inp": {"plank": 8}, "out": {"chest": 1}, "pattern": ["PPP", "P P", "PPP"], "step": 8},
	{"id": "stone_axe", "name": "Stone axe", "inp": {"cobble": 3, "stick": 2}, "out": {"stone_axe": 1}, "pattern": ["CC ", "CS ", " S "], "step": 4},
	{"id": "stone_pick", "name": "Stone pickaxe", "inp": {"cobble": 3, "stick": 2}, "out": {"stone_pick": 1}, "pattern": ["CCC", " S ", " S "], "step": 4},
	# Iron tools (issue #104), from ingots smelted at the fireplace.
	{"id": "iron_axe", "name": "Iron axe", "inp": {"iron_ingot": 3, "stick": 2}, "out": {"iron_axe": 1}, "pattern": ["II ", "IS ", " S "], "step": 99},
	{"id": "iron_pick", "name": "Iron pickaxe", "inp": {"iron_ingot": 3, "stick": 2}, "out": {"iron_pick": 1}, "pattern": ["III", " S ", " S "], "step": 99},
	# Diamond tools (issue #186): the best tier, from diamonds found on the deep levels.
	{"id": "flint_and_steel", "name": "Flint and steel", "inp": {"flint": 1, "iron_ingot": 1}, "out": {"flint_and_steel": 1}, "pattern": ["F  ", " I ", "   "], "step": 99},
	# The Guard's gear (issue #150).
	{"id": "iron_sword", "name": "Iron sword", "inp": {"iron_ingot": 2, "stick": 1}, "out": {"iron_sword": 1}, "pattern": [" I ", " I ", " S "], "step": 99},
	{"id": "iron_chestplate", "name": "Iron chestplate", "inp": {"iron_ingot": 8}, "out": {"iron_chestplate": 1}, "pattern": ["I I", "III", "III"], "step": 99},
	{"id": "diamond_axe", "name": "Diamond axe", "inp": {"diamond": 3, "stick": 2}, "out": {"diamond_axe": 1}, "pattern": ["DD ", "DS ", " S "], "step": 99},
	{"id": "diamond_pick", "name": "Diamond pickaxe", "inp": {"diamond": 3, "stick": 2}, "out": {"diamond_pick": 1}, "pattern": ["DDD", " S ", " S "], "step": 99},
	# The line to the mine (issue #120): Craft work, not Toolsmith, since nobody carries them as tools.
	{"id": "rails", "name": "Rails", "inp": {"iron_ingot": 6, "stick": 1}, "out": {"rail": 16}, "pattern": ["I I", "ISI", "I I"], "step": 99},
	{"id": "minecart", "name": "Minecart", "inp": {"iron_ingot": 5}, "out": {"minecart": 1}, "pattern": ["   ", "I I", "III"], "step": 99},
	# Leather armor (issue #140): Craft work, like anything queued by hand. Spares aren't kept.
	{"id": "leather_cap", "name": "Leather cap", "inp": {"leather": 5}, "out": {"leather_cap": 1}, "pattern": ["HHH", "H H", "   "], "step": 11},
	{"id": "leather_tunic", "name": "Leather tunic", "inp": {"leather": 8}, "out": {"leather_tunic": 1}, "pattern": ["H H", "HHH", "HHH"], "step": 11},
	{"id": "leather_trousers", "name": "Leather trousers", "inp": {"leather": 7}, "out": {"leather_trousers": 1}, "pattern": ["HHH", "H H", "H H"], "step": 11},
	{"id": "leather_boots", "name": "Leather boots", "inp": {"leather": 4}, "out": {"leather_boots": 1}, "pattern": ["   ", "H H", "H H"], "step": 11},
	# Fireplace recipes (issue #46). "at" says which job building makes a recipe; the default is the bench.
	{"id": "bread", "name": "Bread", "inp": {"wheat": 3}, "out": {"bread": 1}, "at": "fireplace", "doing": "Baking bread", "step": 7},
	{"id": "cooked_mutton", "name": "Cooked mutton", "inp": {"mutton": 1, "log": 1}, "out": {"cooked_mutton": 1}, "at": "fireplace", "doing": "Cooking mutton", "fuel": "log", "step": 7},
	{"id": "cooked_beef", "name": "Cooked beef", "inp": {"beef": 1, "log": 1}, "out": {"cooked_beef": 1}, "at": "fireplace", "doing": "Cooking beef", "fuel": "log", "step": 7},
	{"id": "cooked_porkchop", "name": "Cooked porkchop", "inp": {"porkchop": 1, "log": 1}, "out": {"cooked_porkchop": 1}, "at": "fireplace", "doing": "Cooking a porkchop", "fuel": "log", "step": 7},
	# Smelting (issue #104): coal is the fuel. It's Cook work, like everything at the fireplace.
	{"id": "smelt_iron", "name": "Smelt iron", "inp": {"iron_ore": 1, "coal": 1}, "out": {"iron_ingot": 1}, "at": "fireplace", "doing": "Smelting iron", "fuel": "coal", "step": 99},
	{"id": "smelt_gold", "name": "Smelt gold", "inp": {"gold_ore": 1, "coal": 1}, "out": {"gold_ingot": 1}, "at": "fireplace", "doing": "Smelting gold", "fuel": "coal", "step": 99},
	# Workstations process their material (issue #178): Lumberjack and Stonemason work.
	{"id": "saw_planks", "name": "Sawn planks", "inp": {"log": 1}, "out": {"plank": 5}, "at": "chopping_block", "doing": "Sawing planks", "pattern": ["   ", " L ", "   "]},
	{"id": "stone_bricks", "name": "Stone bricks", "inp": {"cobble": 2}, "out": {"stone_brick": 2}, "at": "mason_bench", "doing": "Cutting stone bricks", "pattern": ["   ", "CC ", "   "]},
]

const PATTERN_KEYS := {"L": "log", "P": "plank", "S": "stick", "C": "cobble", "I": "iron_ingot", "H": "leather", "D": "diamond", "F": "flint", "K": "coal"}

## Resident jobs (slice-2-spec.md §5), in the order the Jobs grid shows them.
## Lumberjack and Stonemason replaced Mine in issue #177.
const JOBS := ["lumber", "mason", "haul", "build", "craft", "toolsmith", "farm", "cook", "hunt", "guard", "enchant", "cartographer"]
## The jobs a traveler can arrive skilled in: the Guard is trained in the village, not arrived with (issue #150).
const SKILL_POOL := ["lumber", "mason", "haul", "build", "craft", "toolsmith", "farm", "cook", "hunt"]
const JOB_NAMES := {"lumber": "Lumberjack", "mason": "Stonemason", "haul": "Haul", "build": "Build", "craft": "Craft", "toolsmith": "Toolsmith",
	"farm": "Farm", "cook": "Cook", "hunt": "Hunt", "guard": "Guard", "enchant": "Enchanter", "cartographer": "Cartographer"}
## "Tomas is a skilled farmer."
const JOB_SKILLED := {"lumber": "lumberjack", "mason": "stonemason", "haul": "hauler", "build": "builder", "craft": "crafter", "toolsmith": "toolsmith",
	"farm": "farmer", "cook": "cook", "hunt": "hunter", "guard": "guard", "enchant": "enchanter", "cartographer": "cartographer"}

## Each job's workstation (issue #184): a resident works their job only once they've claimed a finished
## one, one resident to each. Haul needs none.
const JOB_STATIONS := {"lumber": "chopping_block", "mason": "mason_bench", "build": "builder_table", "craft": "bench",
	"toolsmith": "toolsmith_bench", "farm": "composter", "cook": "fireplace", "hunt": "lodge", "enchant": "enchanting_workshop", "cartographer": "cartographer_table"}

## Meals the fireplace's standing order keeps in stock.
const MEALS := ["bread", "cooked_mutton", "cooked_beef", "cooked_porkchop"]


## "2 cows", "1 sheep".
static func animals(species: String, n: int) -> String:
	var sp: Dictionary = SPECIES[species]
	return "%d %s" % [n, sp.one if n == 1 else sp.many]


## What a hunted animal drops, as text: "1 leather and 2 raw beef".
static func drops_text(species: String) -> String:
	var parts: PackedStringArray = []
	for k in Tuning.ANIMAL_DROPS[species]:
		parts.append(words(k, Tuning.ANIMAL_DROPS[species][k]))
	return " and ".join(parts)

## Job buildings ("station") have a crafting queue. Those with a "plot" reserve the 3×3 they'll need
## to grow into it later (slice-2-spec.md §8).
const TEMPLATES := {
	"bench": {"name": "Crafting bench", "size": Vector2i(1, 1), "station": true, "plot": "workshop", "stages": [
		{"name": "Bench", "verb": "needs", "cost": {"log": 4}},
	]},
	"fireplace": {"name": "Fireplace", "size": Vector2i(1, 1), "station": true, "plot": "kitchen", "stages": [
		{"name": "Fireplace", "verb": "needs", "cost": {"cobble": 6}},
	]},
	# Workstations (issue #177): a gatherer's job building. `work` names the job whose gatherers use it,
	# what they gather in its work area, and the item it stores in a pile beside it. Each is also a
	# station that processes what it gathers (issue #178): `makes` is its standing order's recipe.
	"chopping_block": {"name": "Chopping block", "size": Vector2i(1, 1), "plot": "sawmill", "station": true, "makes": "saw_planks",
		"work": {"job": "lumber", "kind": "tree", "item": "log"}, "stages": [
		{"name": "Chopping block", "verb": "needs", "cost": {"plank": 4}},
	]},
	"mason_bench": {"name": "Mason's bench", "size": Vector2i(1, 1), "plot": "mineshaft", "station": true, "makes": "stone_bricks",
		"work": {"job": "mason", "kind": "boulder", "item": "cobble"}, "stages": [
		{"name": "Mason's bench", "verb": "needs", "cost": {"plank": 2, "cobble": 4}},
	]},
	# Boundary stakes for a land claim (issue #187): a builder plants them, then the strip joins the village.
	"claim_stakes": {"name": "Boundary stakes", "size": Vector2i(1, 1), "walk": true, "stages": [
		{"name": "Stakes", "verb": "needs", "cost": {"stick": 4}},
	]},
	# The village's storage (issue #189): chests carried in hold the stacks; its door faces its front.
	"storehouse": {"name": "Storehouse", "size": Vector2i(3, 3), "plot": "warehouse", "store": true, "stages": [
		{"name": "Floor", "verb": "needs", "cost": {"cobble": 6}},
		{"name": "Walls and roof", "verb": "needs", "cost": {"plank": 12, "log": 4}},
	]},
	# A column (or a few) going up beside a storehouse (issue #318): it joins the storehouse when it's built.
	"store_room": {"name": "Storehouse room", "size": Vector2i(1, 3), "stages": [
		{"name": "More room", "verb": "needs", "cost": {"cobble": 2, "plank": 6}},
	]},
	# The other jobs' workstations (issue #184). Small builds that reserve room for an upgrade; the
	# toolsmith's grows into an anvil once there's iron.
	"toolsmith_bench": {"name": "Toolsmith's bench", "size": Vector2i(1, 1), "plot": "anvil", "stages": [
		{"name": "Toolsmith's bench", "verb": "needs", "cost": {"plank": 4, "cobble": 3}},
	]},
	"composter": {"name": "Composter", "size": Vector2i(1, 1), "plot": "granary", "stages": [
		{"name": "Composter", "verb": "needs", "cost": {"plank": 4}},
	]},
	# A pen in the village (issue #355): builders raise it from sticks, and it becomes a pen with fences and a gate.
	"village_pen": {"name": "Pen", "size": Vector2i(4, 4), "stages": [
		{"name": "Pen", "verb": "needs", "cost": {"stick": 12}},
	]},
	"lodge": {"name": "Hunter's lodge", "size": Vector2i(1, 1), "plot": "tannery", "stages": [
		{"name": "Hunter's lodge", "verb": "needs", "cost": {"log": 6, "plank": 2}},
	]},
	"builder_table": {"name": "Builder's table", "size": Vector2i(1, 1), "plot": "builder's yard", "stages": [
		{"name": "Builder's table", "verb": "needs", "cost": {"plank": 4, "log": 2}},
	]},
	# Where the Cartographer plans surveys of the land round the village (issue #321). It grows into a map room.
	"cartographer_table": {"name": "Cartographer's table", "size": Vector2i(1, 1), "plot": "map room", "stages": [
		{"name": "Cartographer's table", "verb": "needs", "cost": {"plank": 6}},
	]},
	# Where expeditions are planned and packed (issue #105). It grows into the map room.
	"board": {"name": "Expedition board", "size": Vector2i(1, 1), "plot": "map room", "stages": [
		{"name": "Expedition board", "verb": "needs", "cost": {"plank": 6, "stick": 4}},
	]},
	# On the road to the mine (issues #119, #121). Both are walked over, so neither blocks the way.
	"bridge": {"name": "Bridge", "size": Vector2i(4, 3), "walk": true, "stages": [
		{"name": "Bridge", "verb": "needs", "cost": {"plank": 12}},
	]},
	"track": {"name": "Track", "size": Vector2i(8, 1), "walk": true, "stages": [
		{"name": "Track", "verb": "needs", "cost": {"rail": Tuning.RAILS_PER_SEGMENT}},
	]},
	# A platform with a buffer stop at each end of the line (issue #123). It grows into a loading station.
	"station": {"name": "Station", "size": Vector2i(3, 1), "walk": true, "plot": "loading station", "stages": [
		{"name": "Station", "verb": "needs", "cost": {"plank": 6, "cobble": 4}},
	]},
	# The redstone devices (Slice 6, issues #170-#173): ready-made, built from redstone dust, quartz and stone (provisional). `device`
	# names the kind; dust lines join one's output to another's input.
	"cache_sensor": {"name": "Cache sensor", "size": Vector2i(1, 1), "device": "sensor", "stages": [
		{"name": "Sensor", "verb": "needs", "cost": {"redstone": 2, "quartz": 1, "cobble": 2}},
	]},
	"condition": {"name": "Condition", "size": Vector2i(1, 1), "device": "condition", "stages": [
		{"name": "Condition", "verb": "needs", "cost": {"redstone": 2, "quartz": 1, "cobble": 2}},
	]},
	# The dispatcher (issue #173): beside the village station; raises the departure request once the cart is loaded.
	"dispatcher": {"name": "Dispatcher", "size": Vector2i(1, 1), "device": "dispatcher", "stages": [
		{"name": "Dispatcher", "verb": "needs", "cost": {"redstone": 2, "quartz": 1, "cobble": 2}},
	]},
	# The freight loader (issue #172): the loading-station upgrade, built on the plot the portal station reserves.
	"freight_loader": {"name": "Freight loader", "size": Vector2i(1, 1), "device": "loader", "stages": [
		{"name": "Loader", "verb": "needs", "cost": {"redstone": 3, "quartz": 1, "cobble": 4}},
	]},
	# The portal line's village station, beside the portal (Slice 6, issue #168). It reserves the plot the freight loader grows into.
	"portal_station": {"name": "Portal station", "size": Vector2i(3, 1), "walk": true, "plot": "loading station", "stages": [
		{"name": "Station", "verb": "needs", "cost": {"plank": 6, "cobble": 4}},
	]},
	# The way to the Nether (Slice 5, issue #147): an obsidian frame, lit with flint and steel. The party packs and gathers
	# on the staging area in front, which is part of the plot it reserves. It never turns.
	"portal": {"name": "Nether portal", "size": Vector2i(4, 1), "plot": "portal hall", "stages": [
		{"name": "Portal frame", "verb": "needs", "cost": {"obsidian": Tuning.PORTAL_OBSIDIAN}},
	]},
	# The unstaffed shelter and supply cache on the Nether landing (Slice 5, issue #152): built by a party from what it carries.
	"shelter": {"name": "Shelter", "size": Vector2i(3, 3), "stages": [
		{"name": "Shelter", "verb": "needs", "cost": Tuning.SHELTER_COST},
	]},
	# Where recipes are learned from books and gear enchanted (Slice 6, issue #165). It grows into a library.
	"enchanting_workshop": {"name": "Enchanting workshop", "size": Vector2i(1, 1), "plot": "library", "stages": [
		{"name": "Workshop", "verb": "needs", "cost": {"obsidian": 4, "diamond": 2, "plank": 6}},
	]},
	# The boatyard (Slice 7, issue #407): a party needs one built to sail out from the dock.
	"boatyard": {"name": "Boatyard", "size": Vector2i(1, 1), "stages": [
		{"name": "Boatyard", "verb": "needs", "cost": {"plank": 16, "log": 4, "stick": 4}},
	]},
	# The dock (Slice 7, issue #271): runs from the beach out over the sea, walkable once built. A party leaves by it for the coast.
	"dock": {"name": "Dock", "size": Vector2i(1, Tuning.DOCK_LAND + Tuning.COAST_DEPTH), "walk": true, "stages": [
		{"name": "Dock", "verb": "needs", "cost": {"plank": 12, "log": 4}},
	]},
	"house": {"name": "House", "size": Vector2i(5, 5), "stages": [
		{"name": "Foundation", "verb": "needs", "cost": {"cobble": 8}},
		{"name": "Walls", "verb": "need", "cost": {"plank": 16, "log": 4}},
		{"name": "Roof", "verb": "needs", "cost": {"plank": 12}},
		{"name": "Bed", "verb": "needs", "cost": {"wool": 3, "plank": 3}},
	]},
}


## A house's tiers (issue #285), by the tier being built. A house is placed as a tent; each upgrade is built like any stage once its resident
## has spent the emeralds (`Tuning.EMERALD_COSTS`). A house with no `tier` (placed before tiers) is the 5x5 building, built from the template's stages.
const HOUSE_STAGES := {
	1: [{"name": "Tent", "verb": "needs", "cost": {"plank": 6, "wool": 3}}],
	2: [{"name": "House", "verb": "needs", "cost": {"cobble": 4, "plank": 10, "log": 2}}],
	3: [{"name": "Walls", "verb": "need", "cost": {"cobble": 4, "plank": 12, "log": 2}}, {"name": "Roof", "verb": "needs", "cost": {"plank": 12}}],
}
const HOUSE_TIER_NAMES := ["Tent", "House", "Building"]


## What building a house's tier takes in all, over its stages.
static func house_cost(tier: int) -> Dictionary:
	var out := {}
	for st in HOUSE_STAGES[tier]:
		for k in st.cost:
			out[k] = out.get(k, 0) + st.cost[k]
	return out


static func recipe(id: String) -> Dictionary:
	for r in RECIPES:
		if r.id == id:
			return r
	return {}


## The recipes a job building makes. A recipe's optional `step` is the founding goal the book must have reached
## before the panel shows it (issue #372); 99 is the village chapter.
static func recipes_at(tpl: String) -> Array:
	return RECIPES.filter(func(r): return r.get("at", "bench") == tpl)


## What a station's panel lists: its recipes the book has reached (issue #372). A recipe already queued stays.
static func recipes_shown(sim: Sim, tpl: String) -> Array:
	return recipes_at(tpl).filter(func(r): return Goals.reached(sim, r.get("step", 0)))


## The first recipe at this job building that outputs this item, used to fill in missing ingredients.
static func producer(item: String, tpl := "bench") -> Dictionary:
	for r in recipes_at(tpl):
		if r.out.has(item):
			return r
	return {}


static func is_tool_item(item: String) -> bool:
	return ITEMS[item].has("tool")


static func is_armor(item: String) -> bool:
	return ITEMS[item].has("armor")


## Items that wear out, each with its own uses left: tools and armor.
static func wears(item: String) -> bool:
	return ITEMS[item].has("tool") or ITEMS[item].has("armor") or ITEMS[item].has("uses")


## Items to a cell: one tool, piece of armor or minecart, or a stack of anything else.
static func stack_cap(item: String) -> int:
	return 1 if wears(item) or ITEMS[item].get("single", false) else Tuning.STACK


static func words(item: String, n: int) -> String:
	var it: Dictionary = ITEMS[item]
	return "%d %s" % [n, it.one if n == 1 else it.many]


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in cost:
		parts.append(words(k, cost[k]))
	return ", ".join(parts)
