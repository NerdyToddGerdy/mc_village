class_name Goals
extends RefCounted
## The founding book (issue #198): the founding checklist, then the village chapter, each goal with a
## hint (`h`, how) and a why (`w`), and a page for every building. `current()` is the founding only;
## `village_current()` is the chapter that follows it.

const LIST := [
	{"t": "Chop a tree", "h": "Choose Gather, then Mine (or press X), and click a tree. Ada fells it by hand, slowly.", "w": "Trees give logs, and logs are where everything starts. Ada fells one by hand, slowly, until she has an axe."},
	{"t": "Paint a stockpile", "h": "The logs are lying loose. Choose Paint, then Stockpile, and drag over open ground.", "w": "Loose things get hauled to stockpiles. Without one, logs lie where they fell and no one can find them."},
	{"t": "Build a crafting bench", "h": "Choose Build, then Crafting bench, and click open ground.", "w": "Every tool, plank and stick is made here. It grows into a workshop later, so leave room around it."},
	{"t": "Craft an axe and a pickaxe", "h": "Select the bench and queue a wooden axe and a wooden pickaxe. It makes their planks and sticks first. An axe chops 2.5× faster.", "w": "Bare hands chop slowly and can't break stone at all."},
	{"t": "Break a boulder", "h": "Choose Gather, then Mine (or press X), and click a boulder. Ada uses her pickaxe.", "w": "Cobblestone builds the fireplace, and a pickaxe is how you get it. Boulders are the clearing's only stone."},
	{"t": "Hunt sheep for wool", "h": "Choose Gather, then Hunt (or press G), and mark sheep. The clearing's 3 sheep give the 3 wool a bed needs.", "w": "A bed needs 3 wool, and the clearing's sheep are the only wool nearby. Hunting also gives mutton for the first meals."},
	{"t": "Build Ada’s house", "h": "Choose Build, then House. R turns the door. Its last stage is the bed.", "w": "A bed is somewhere to rest. Every new resident needs a house before they'll stay."},
	{"t": "Build a fireplace", "h": "A trip needs a meal for the walk home. Build a fireplace (6 cobblestone): it cooks the mutton from the sheep.", "w": "A resident who walks off the map needs a meal for the road. Cooked food also lasts far longer than raw."},
	{"t": "Build an expedition board", "h": "The second bed needs more wool than the clearing has. The board plans trips off the map.", "w": "Not everything the village needs grows in the clearing. The board plans trips to places off the map."},
	{"t": "Fetch wool from the meadow", "h": "At the board, plan a trip to the meadow with Ada and a wool target, then Depart. The village waits while she's away.", "w": "The clearing has 3 sheep and the second bed needs more wool. The meadow has flocks to bring it from."},
	{"t": "Build a second house", "h": "Its bed is what brings a traveler.", "w": "Each bed is one more resident the village can keep. The second is what draws a traveler in."},
	{"t": "Welcome a traveler", "h": "Tomas, a lumberjack, arrives a little while after the second bed is ready.", "w": "More hands mean more work done at once. Travelers arrive skilled, and a skilled worker is worth a workstation."},
	{"t": "Build Tomas a chopping block", "h": "Choose Build, then Chopping block, near trees. Tomas fells the trees around it on his own, while Ada does everything else.", "w": "Without a workstation a lumberjack only hauls. With one, they fell the trees around it on their own, so you stop marking every tree."},
]


## The village chapter, which follows the founding. The mine trip is its last task.
const VILLAGE := [
	{"t": "Paint a farm plot", "h": "Choose Paint, then Farm plot, and drag over open grass. A farmer plants and harvests it.",
		"w": "Sheep run out and berry bushes regrow slowly. A farm plot is replanted after every harvest, and a farmer keeps it going: the village's steady food."},
	{"t": "Cook a meal", "h": "Select the fireplace and queue bread or cooked mutton. A cook needs wheat, or raw meat, and logs.",
		"w": "Cooked food fills a resident for much longer than raw. A hungry resident works slower."},
	{"t": "Give a second resident a workstation", "h": "Choose Build for a mason's bench, composter or another workstation, and give someone that job from the Jobs board.",
		"w": "A resident with a workstation works their job on their own, in its area. One workstation is Tomas's; the next frees you from marking boulders, fields or game."},
	{"t": "Bring iron ore home from the old mine", "h": "Plan a trip to the old mine at the expedition board. If the road isn't built yet, the board says what to build first.",
		"w": "The clearing has no ore: only expeditions find it. Smelted with coal at the fireplace's furnace, it makes iron tools that last more than twice as long as stone, and lets the toolsmith's bench grow into an anvil."},
]


## One page of the village book per building or zone, in the Build menu's order. `unlock` says when it
## shows: "" from the start, "house" once Ada's house is up, "board" once the board is built, "road"
## once a party has been to the old mine. `tpl` is the building's template, for its panel's "?".
const PAGES := [
	{"id": "stockpile", "title": "Stockpile", "who": "Anyone hauls to it",
		"what": "Painted ground where loose things are hauled and kept. Residents fetch what they need from the nearest one.",
		"grows": "A storehouse takes the main load once you have one, and the stockpile keeps the overflow.",
		"without": "Logs and stone lie where they fell. Crafting and building wait on things no one can find."},
	{"id": "farm", "title": "Farm plot", "who": "A farmer",
		"what": "Open grass where wheat is planted, grown and harvested again and again.",
		"grows": "The composter beside it reserves room to grow into a granary.",
		"without": "Food comes only from berries and from hunting, and both run out."},
	{"id": "pen", "title": "Pen", "unlock": "board", "who": "The expedition party builds it and leads animals in",
		"what": "A fenced pen at the meadow where animals are kept and bred. Fed pairs have young.",
		"grows": "More animals mean wool, leather and meat on every trip.",
		"without": "Wool and leather depend on whatever the party finds wandering."},
	{"id": "house", "title": "House", "tpl": "house", "who": "Whoever lives there",
		"what": "Somewhere to sleep. Its last stage is the bed, and a finished bed is what brings a traveler.",
		"grows": "Each new house is one more resident the village can keep.",
		"without": "No one new will stay, and the village can never grow."},
	{"id": "bench", "title": "Crafting bench", "tpl": "bench", "who": "A crafter, or Ada",
		"what": "Every tool, plank, stick and chest is made here. It queues what the recipes need.",
		"grows": "Reserves a plot, and grows into a workshop that makes two things at once.",
		"without": "No new tools, so nothing breaks stone and broken tools can't be replaced."},
	{"id": "fireplace", "title": "Fireplace", "tpl": "fireplace", "who": "A cook",
		"what": "Cooks bread and meat. It is also the furnace: its Craft screen smelts iron ore and coal into ingots.",
		"grows": "Reserves a plot, and grows into a kitchen.",
		"without": "Everyone eats raw food, and no trip has a meal for the road. No iron."},
	{"id": "chopping_block", "title": "Chopping block", "tpl": "chopping_block", "who": "A lumberjack",
		"what": "A lumberjack fells the trees around it on their own, piles the logs, and saws planks.",
		"grows": "Reserves a plot, and grows into a sawmill.",
		"without": "Every tree has to be marked by hand, and planks run short."},
	{"id": "mason_bench", "title": "Mason's bench", "tpl": "mason_bench", "who": "A stonemason",
		"what": "A stonemason breaks the boulders around it, and cuts stone bricks.",
		"grows": "Reserves a plot. Once every boulder on the map is gone, it can be dug out into a mineshaft that digs cobblestone from where it stands, slowly.",
		"without": "Stone comes only from boulders you mark, and they run out. Then the mineshaft or a trip to the old mine is the only stone."},
	{"id": "toolsmith_bench", "title": "Toolsmith's bench", "tpl": "toolsmith_bench", "who": "A toolsmith",
		"what": "A toolsmith keeps spare tools made, and tools they make last longer.",
		"grows": "Reserves a plot, and grows into an anvil.",
		"without": "A broken tool stops its user until someone crafts a new one."},
	{"id": "composter", "title": "Composter", "tpl": "composter", "who": "A farmer",
		"what": "A farmer works the fields from it, planting and harvesting.",
		"grows": "Reserves a plot, and grows into a granary.",
		"without": "Wheat is only grown when Ada has time. Meals run out."},
	{"id": "lodge", "title": "Hunter's lodge", "tpl": "lodge", "who": "A hunter",
		"what": "A hunter hunts animals on their own and brings the meat, wool and leather home.",
		"grows": "Reserves a plot, and grows into a tannery.",
		"without": "Hunting is something you mark by hand each time."},
	{"id": "builder_table", "title": "Builder's table", "tpl": "builder_table", "who": "A builder",
		"what": "A builder raises blueprints, and plants the stakes for new land.",
		"grows": "Reserves a plot, and grows into a builder's yard.",
		"without": "Ada builds everything, and nothing else gets her attention."},
	{"id": "storehouse", "title": "Storehouse", "tpl": "storehouse", "who": "Anyone hauls to it",
		"what": "The village's main storage. Chests carried in hold anything; stockpiles take the overflow.",
		"grows": "Up to 4 chests, and room to grow into a warehouse.",
		"without": "Everything sits loose in stockpiles, and runs out of room."},
	{"id": "board", "title": "Expedition board", "tpl": "board", "unlock": "house", "who": "Whoever you send",
		"what": "Plans trips off the map: pack the party, set a target, and Depart. The village waits while they're away.",
		"grows": "Reserves a plot, and grows into a map room.",
		"without": "Wool, ore and anything off the map stay out of reach."},
	{"id": "road", "title": "The road", "unlock": "road", "who": "Builders, and the party",
		"what": "A bridge, a track and a station at each end: the way to the old mine, and a minecart to ride it.",
		"grows": "A faster ride each way, but mining takes just as long.",
		"without": "Every trip is a long walk, and the party carries everything it needs."},
]


## The pages that show now, in order.
static func pages(sim: Sim) -> Array:
	return PAGES.filter(func(p): return page_known(sim, p))


static func page_known(sim: Sim, page: Dictionary) -> bool:
	match page.get("unlock", ""):
		"house": return sim.stats.houses >= 1
		"board": return sim.stats.get("built", {}).has("board")
		"road": return sim.get_map("old_mine").visited
	return true


## The page for a building's template, or {}.
static func page_for(tpl: String) -> Dictionary:
	for p in PAGES:
		if p.get("tpl", "") == tpl:
			return p
	return {}


## Whether village goal `i` is done.
static func village_done(sim: Sim, i: int) -> bool:
	match i:
		0: return not sim.farm.is_empty()
		1: return sim.stats.get("meals_cooked", 0) > 0
		2: return sim.sites.filter(func(s): return s.done and s.get("worker", 0) != 0 and s.tpl in ["chopping_block", "mason_bench", "toolsmith_bench", "composter", "lodge", "builder_table"]).size() >= 2
		_: return sim.stats.get("ore_home", false)


## Index of the first unfinished village goal, or -1 when the chapter is done. It starts once the
## founding is complete.
static func village_current(sim: Sim) -> int:
	for i in VILLAGE.size():
		if not village_done(sim, i):
			return i
	return -1


## Whether founding goal `i` is done, from the village's stats and stockpile (issue #182).
static func done(sim: Sim, i: int) -> bool:
	var built: Dictionary = sim.stats.get("built", {})
	match i:
		0: return sim.stats.felled > 0
		1: return not sim.zone.is_empty()
		2: return built.has("bench")
		3: return sim.stats.get("axe_crafted", false) and sim.stats.pick_crafted
		4: return sim.stats.broken_boulders > 0
		5: return sim.stats.get("sheep_hunted", 0) > 0 or sim.stats.houses >= 1  # saves from before sheep built houses without
		6: return sim.stats.houses >= 1
		7: return built.has("fireplace")
		8: return built.has("board")
		9: return sim.stats.get("meadow_wool", false)
		10: return sim.stats.houses >= 2
		11: return sim.stats.traveler_home
		_: return built.has("chopping_block")


## Index of the first unfinished goal, or -1 when the founding is complete.
static func current(sim: Sim) -> int:
	for i in LIST.size():
		if not done(sim, i):
			return i
	return -1


## A save's label and the menu's subtitle: the next founding step, then facts about the village
## once the founding is done (issue #81), so village saves can be told apart.
static func progress_text(sim: Sim) -> String:
	var i := current(sim)
	return village_text(sim) if i < 0 else "Next: " + LIST[i].t


## "4 residents, 3 houses, 18 meals".
static func village_text(sim: Sim) -> String:
	var people := sim.residents.size()
	var houses := sim.sites.filter(func(s): return s.tpl == "house" and s.done).size()
	var meals := 0
	for m in Defs.MEALS:
		meals += sim.free_count(m)
	return "%d %s, %d %s, %d %s" % [people, "resident" if people == 1 else "residents", houses, "house" if houses == 1 else "houses", meals, "meal" if meals == 1 else "meals"]
