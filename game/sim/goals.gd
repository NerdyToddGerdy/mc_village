class_name Goals
extends RefCounted
## The founding book (issue #198): the founding checklist, then the village chapter, each goal with a
## hint (`h`, how) and a why (`w`), and a page for every building. `current()` is the founding only;
## `village_current()` is the chapter that follows it.

## The founding, in three chapters (issue #318): Shelter, Food and Expanding. Each goal has its chapter in `c`.
const LIST := [
	{"c": 0, "t": "Chop a tree", "h": "Choose Gather, then Mine (or press X), and click a tree. Ada fells it by hand, slowly.", "w": "Trees give logs, and logs are where everything starts. Ada fells one by hand, slowly, until she has an axe."},
	{"c": 0, "t": "Build a crafting bench", "h": "Choose Build, then Crafting bench, and click open ground.", "w": "Every tool, plank and stick is made here. It grows into a workshop later, so leave room around it."},
	{"c": 0, "t": "Craft an axe and a pickaxe", "h": "Select the bench and queue a wooden axe and a wooden pickaxe. It makes their planks and sticks first. An axe chops 2.5× faster.", "w": "Bare hands chop slowly and can't break stone at all."},
	{"c": 0, "t": "Break a boulder", "h": "Choose Gather, then Mine (or press X), and click a boulder. Ada uses her pickaxe.", "w": "Cobblestone builds the house and the fireplace, and a pickaxe is how you get it. Boulders are the clearing's only stone."},
	{"c": 0, "t": "Hunt sheep for wool", "h": "Choose Gather, then Hunt (or press G), and mark sheep. The clearing's 3 sheep give the 3 wool a bed needs.", "w": "A bed needs 3 wool, and the clearing's sheep are the only wool nearby. Hunting also gives mutton for the first meals."},
	{"c": 0, "t": "Build Ada’s house", "h": "Choose Build, then House. R turns the door. Its last stage is the bed.", "w": "A bed is somewhere to rest. Every new resident needs a house before they'll stay."},
	{"c": 1, "t": "Build a composter and paint its plots", "h": "Choose Build, then Composter (4 planks). It starts with plots round it. Select it and use Paint plots to drag more within 3 cells. A farmer plants and harvests them.", "w": "Sheep run out and berry bushes regrow slowly. A farm is a place with a building at its heart: the composter's plots are replanted after every harvest, and a farmer keeps them going: the village's steady food."},
	{"c": 1, "t": "Build a fireplace and cook a meal", "h": "A trip needs a meal for the walk home. Build a fireplace (6 cobblestone), select it and queue bread or cooked mutton. A cook needs wheat, or raw meat, and logs.", "w": "A resident who walks off the map needs a meal for the road. Cooked food also lasts far longer than raw, and a hungry resident works slower."},
	{"c": 2, "t": "Build a storehouse", "h": "Choose Build, then Storehouse (6 cobblestone, then 12 planks and 4 logs). Craft a chest at the bench (8 planks) and a hauler carries it in. Select it and Paint more room to widen it.", "w": "Things have to be kept somewhere. The storehouse holds chests of anything, and it grows as you paint beside it, so nothing lies where it fell."},
	{"c": 2, "t": "Build an expedition board", "h": "The second bed needs more wool than the clearing has. The board plans trips off the map.", "w": "Not everything the village needs grows in the clearing. The board plans trips to places off the map."},
	{"c": 2, "t": "Fetch wool from the meadow", "h": "At the board, plan a trip to the meadow with Ada and a wool target, then Depart. The village waits while she's away.", "w": "The clearing has 3 sheep and the second bed needs more wool. The meadow has flocks to bring it from."},
	{"c": 2, "t": "Build a second house", "h": "Its bed is what brings a traveler.", "w": "Each bed is one more resident the village can keep. The second is what draws a traveler in."},
	{"c": 2, "t": "Welcome a traveler", "h": "Tomas, a lumberjack, arrives a little while after the second bed is ready.", "w": "More hands mean more work done at once. Travelers arrive skilled, and a skilled worker is worth a workstation."},
	{"c": 2, "t": "Build Tomas a chopping block", "h": "Choose Build, then Chopping block, near trees. Tomas fells the trees around it on his own, while Ada does everything else.", "w": "Without a workstation a lumberjack only hauls. With one, they fell the trees around it on their own, so you stop marking every tree."},
]


## The founding book's chapters (issue #318): a title, why it matters, and what the village can do once it's done. The first
## three cover `LIST` by each goal's `c`; the last is `VILLAGE`.
const CHAPTERS := [
	{"name": "Shelter", "why": "A first day alone: tools, stone, wool and a bed.", "note": "The village has tools, a roof and a bed, and a place for a second pair of hands."},
	{"name": "Food", "why": "A farm and a fire, so a trip can be fed.", "note": "Wheat grows on its own and meals are cooked: a party can be fed on the road."},
	{"name": "Expanding", "why": "A storehouse, a board, the meadow and the first neighbour.", "note": "The village keeps what it makes, sends parties out, and has more than one pair of hands."},
	{"name": "The village", "why": "Jobs, workstations and the first real expedition.", "note": "Everyone has work, and the old caves are open."},
]


## The village chapter, which follows the founding. The mine trip is its last task.
const VILLAGE := [
	{"c": 3, "t": "Give a second resident a workstation", "h": "Choose Build for a mason's bench, composter or another workstation, and give someone that job from the Jobs board.",
		"w": "A resident with a workstation works their job on their own, in its area. One workstation is Tomas's; the next frees you from marking boulders, fields or game."},
	{"c": 3, "t": "Send a Cartographer to find the old caves", "h": "Build a cartographer's table from the Build menu, give someone the Cartographer job and choose Survey on the table.",
		"w": "The land beyond the clearing is unknown. A survey finds the old caves first, then a ruined portal, and each ring out takes longer and is more dangerous."},
	{"c": 3, "t": "Bring iron ore home from the old caves", "h": "Plan a trip to the old caves at the expedition board. If the road isn't built yet, the board says what to build first.",
		"w": "The clearing has no ore: only expeditions find it. Smelted with coal at the fireplace's furnace, it makes iron tools that last more than twice as long as stone, and lets the toolsmith's bench grow into an anvil."},
]


## One page of the village book per building or zone, in the Build menu's order. `unlock` says when it
## shows: "" from the start, "house" once Ada's house is up, "board" once the board is built, "portal" once obsidian has come home, "road"
## once a party has been to the old mine. `tpl` is the building's template, for its panel's "?".
const PAGES := [
	{"id": "pen", "clue": "Something the expedition board makes room for.", "title": "Pen", "unlock": "board", "who": "The expedition party builds it and leads animals in",
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
		"without": "Stone comes only from boulders you mark, and they run out. Then the mineshaft or a trip to the old caves is the only stone."},
	{"id": "toolsmith_bench", "title": "Toolsmith's bench", "tpl": "toolsmith_bench", "who": "A toolsmith",
		"what": "A toolsmith keeps spare tools made, and tools they make last longer.",
		"grows": "Reserves a plot, and grows into an anvil.",
		"without": "A broken tool stops its user until someone crafts a new one."},
	{"id": "composter", "title": "Composter", "tpl": "composter", "who": "A farmer",
		"what": "The heart of a farm. It starts with plots round it, you paint more within 3 cells, and a farmer plants and harvests them again and again.",
		"grows": "Reserves a plot, and grows into a granary. A plot with no composter in reach dries out and turns back to grass.",
		"without": "No farm: food comes only from berries and from hunting, and both run out."},
	{"id": "lodge", "title": "Hunter's lodge", "tpl": "lodge", "who": "A hunter",
		"what": "A hunter hunts animals on their own and brings the meat, wool and leather home.",
		"grows": "Reserves a plot, and grows into a tannery.",
		"without": "Hunting is something you mark by hand each time."},
	{"id": "cartographer_table", "clue": "Something the expedition board makes room for.", "title": "Cartographer's table", "tpl": "cartographer_table", "who": "A cartographer", "unlock": "board",
		"what": "A cartographer surveys the land round the village, one ring of one direction at a time, and finds the old caves, then a ruined portal.",
		"grows": "Reserves a plot, and grows into a map room.",
		"without": "Nothing beyond the clearing is known: the caves and the portal stay hidden."},
	{"id": "builder_table", "title": "Builder's table", "tpl": "builder_table", "who": "A builder",
		"what": "A builder raises blueprints, and plants the stakes for new land.",
		"grows": "Reserves a plot, and grows into a builder's yard.",
		"without": "Ada builds everything, and nothing else gets her attention."},
	{"id": "storehouse", "title": "Storehouse", "tpl": "storehouse", "who": "Anyone hauls to it",
		"what": "The village's storage. Chests carried in hold anything, one in every cell but the door's aisle.",
		"grows": "Paint more room beside it: 3 wide up to 7, with 6 to 18 chests. The door never moves.",
		"without": "Everything lies where it fell, and runs out of places to be found."},
	{"id": "enchanting_workshop", "clue": "Something an old book might teach.", "title": "Enchanting workshop", "tpl": "enchanting_workshop", "unlock": "enchanting", "who": "An Enchanter",
		"what": "Obsidian and diamonds make a workshop where an Enchanter reads enchanted books, learning their recipes for good, and enchants tools, swords and armor.",
		"grows": "Reserves a plot, and grows into a library.",
		"without": "Enchanted books are only things to carry, and gear stays plain."},
	{"id": "portal_station", "clue": "Something a lit portal leads to.", "title": "Portal station", "tpl": "portal_station", "unlock": "portal_line", "who": "Builders; a Build party lays the Nether side",
		"what": "The village end of the portal line, beside the portal, with a landing station beside the shelter in the Nether. Carts and parties ride it.",
		"grows": "Reserves a plot, and grows into a freight loader.",
		"without": "Everything crosses the portal on foot."},
	{"id": "devices", "clue": "Something a lit portal leads to.", "title": "Redstone devices", "tpl": "cache_sensor", "unlock": "portal_line", "who": "Builders; a hauler lays the dust",
		"what": "Ready-made devices built from redstone dust, quartz and stone: a cache sensor reads the Nether cache, a condition passes a signal only while a fact holds. Dust lines you order join one's output to another's input. Each device says why it's on.",
		"grows": "A freight loader on the portal station's plot and a dispatcher join them in the chain.",
		"without": "A low cache is something to notice yourself."},
	{"id": "condition", "clue": "Something a lit portal leads to.", "title": "Condition", "tpl": "condition", "unlock": "portal_line", "who": "Builders",
		"what": "Passes a signal along only while a fact holds: the portal is lit, the freight cart is home, or the loader is idle.",
		"grows": "Nothing; it joins the sensor to the loader.",
		"without": "A low cache would start the freight even with the portal out."},
	{"id": "dispatcher", "clue": "Something a lit portal leads to.", "title": "Dispatcher", "tpl": "dispatcher", "unlock": "portal_line", "who": "Builders",
		"what": "Stands beside the portal station. When powered and the freight cart is loaded, it asks you to approve the departure. The game keeps running; approve or decline from the station.",
		"grows": "Nothing.",
		"without": "You watch the cart yourself."},
	{"id": "freight_loader", "clue": "Something a lit portal leads to.", "title": "Freight loader", "tpl": "freight_loader", "unlock": "portal_line", "who": "Builders; haulers load the cart",
		"what": "The loading-station upgrade on the portal station's plot. While powered, haulers carry its freight list from the stockpile onto the freight cart.",
		"grows": "Nothing.",
		"without": "The freight cart leaves empty."},
	{"id": "portal", "clue": "Something that only the deep stone can make.", "title": "Nether portal", "tpl": "portal", "unlock": "portal", "who": "Builders carry the obsidian; anyone lights it",
		"what": "A frame of obsidian from the deep mine, lit with flint and steel. Parties bound for the Nether pack on the staging area in front of it.",
		"grows": "Reserves a portal hall around it.",
		"without": "There's no way to the Nether, and nothing it holds."},
	{"id": "board", "clue": "Something Ada's first house makes possible.", "title": "Expedition board", "tpl": "board", "unlock": "house", "who": "Whoever you send",
		"what": "Plans trips off the map: pack the party, set a target, and Depart. The village waits while they're away.",
		"grows": "Reserves a plot, and grows into a map room.",
		"without": "Wool, ore and anything off the map stay out of reach."},
	{"id": "road", "clue": "Something an expedition to the old caves would find.", "title": "The road", "unlock": "road", "who": "Builders, and the party",
		"what": "A bridge, a track and a station at each end: the way to the old caves, and a minecart to ride it.",
		"grows": "A faster ride each way, but mining takes just as long.",
		"without": "Every trip is a long walk, and the party carries everything it needs."},
]


## The pages that show now, in order.
static func pages(sim: Sim) -> Array:
	return PAGES.filter(func(p): return page_known(sim, p))


## Every page, known or not, sorted by its real name, so a locked one sits where its name would (issue #348).
static func guide_rows(sim: Sim) -> Array:
	var rows: Array = PAGES.duplicate()
	rows.sort_custom(func(a, b): return String(a.title).to_lower() < String(b.title).to_lower())
	return rows


## The known pages the player hasn't clicked since they unlocked (issue #348).
static func new_pages(sim: Sim) -> Array:
	var seen: Dictionary = sim.stats.get("guide_seen", {})
	return pages(sim).filter(func(p): return not seen.has(p.id))


## Marks every page known now as seen: a new game's opening pages, and an older save's whole book (issue #348).
static func seed_seen(sim: Sim) -> void:
	var seen: Dictionary = sim.stats.get("guide_seen", {})
	for p in pages(sim):
		seen[p.id] = true
	sim.stats.guide_seen = seen


static func page_known(sim: Sim, page: Dictionary) -> bool:
	match page.get("unlock", ""):
		"house": return sim.stats.houses >= 1
		"board": return sim.stats.get("built", {}).has("board")
		"road": return sim.get_map("old_mine").visited
		"enchanting": return sim.stats.get("book_found", false) or sim.maps.village.sites.any(func(x): return x.tpl == "enchanting_workshop")
		"portal_line": return not sim.village_portal().is_empty()
		"portal": return sim.stats.get("obsidian_home", false) or sim.maps.village.sites.any(func(x): return x.tpl == "portal")
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
		0: return sim.sites.filter(func(s): return s.done and s.get("worker", 0) != 0 and s.tpl in ["chopping_block", "mason_bench", "toolsmith_bench", "composter", "lodge", "builder_table"]).size() >= 2
		1: return Survey.found(sim, "old_mine") or sim.get_map("old_mine").known
		_: return sim.stats.get("ore_home", false)


## Index of the first unfinished village goal, or -1 when the chapter is done. It starts once the
## founding is complete.
static func village_current(sim: Sim) -> int:
	for i in VILLAGE.size():
		if not village_done(sim, i):
			return i
	return -1


## Whether founding goal `i` is done, from the village's stats and buildings (issue #182). A stockpile or farm painted the old way
## counts for the storehouse and the composter, so a village that started before them isn't sent back.
static func done(sim: Sim, i: int) -> bool:
	var built: Dictionary = sim.stats.get("built", {})
	match i:
		0: return sim.stats.felled > 0
		1: return built.has("bench")
		2: return sim.stats.get("axe_crafted", false) and sim.stats.pick_crafted
		3: return sim.stats.broken_boulders > 0
		4: return sim.stats.get("sheep_hunted", 0) > 0 or sim.stats.houses >= 1  # saves from before sheep built houses without
		5: return sim.stats.houses >= 1
		6: return built.has("composter") or not sim.farm.is_empty()
		7: return built.has("fireplace") and sim.stats.get("meals_cooked", 0) > 0
		8: return built.has("storehouse") or not sim.zone.is_empty()
		9: return built.has("board")
		10: return sim.stats.get("meadow_wool", false)
		11: return sim.stats.houses >= 2
		12: return sim.stats.traveler_home
		_: return built.has("chopping_block")


## Whether a village saved before the composter and the storehouse had finished the founding as it stood then: a stockpile, the
## fireplace, the board, the meadow's wool, two houses, a traveler and Tomas's chopping block.
static func legacy_done(sim: Sim) -> bool:
	var built: Dictionary = sim.stats.get("built", {})
	return sim.stats.felled > 0 and not sim.zone.is_empty() and built.has("bench") and sim.stats.get("axe_crafted", false) and sim.stats.pick_crafted \
		and sim.stats.broken_boulders > 0 and sim.stats.houses >= 1 and built.has("fireplace") and built.has("board") and sim.stats.get("meadow_wool", false) \
		and sim.stats.houses >= 2 and sim.stats.traveler_home and built.has("chopping_block")


## Index of the first unfinished goal, or -1 when the founding is complete. Once it has been, it stays complete.
static func current(sim: Sim) -> int:
	if sim.stats.get("founding_done", false):
		return -1
	return first_open(sim)


static func first_open(sim: Sim) -> int:
	for i in LIST.size():
		if not done(sim, i):
			return i
	return -1


## The chapter a founding goal (or, past the founding, the village chapter) belongs to, 0 to 3.
static func chapter_of(i: int) -> int:
	return LIST[i].c if i >= 0 and i < LIST.size() else 3


## "Shelter, 4 of 6": how far through its chapter goal `i` is.
static func chapter_count(sim: Sim, ch: int) -> Array:
	var total := 0
	var finished := 0
	for i in LIST.size():
		if LIST[i].c == ch:
			total += 1
			finished += 1 if done(sim, i) else 0
	return [finished, total]


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
