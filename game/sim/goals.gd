class_name Goals
extends RefCounted
## The founding checklist shown to the player, with a hint for the current step.

const LIST := [
	{"t": "Chop a tree", "h": "Choose Gather, then Mine (or press X), and click a tree. Ada fells it by hand, slowly."},
	{"t": "Paint a stockpile", "h": "The logs are lying loose. Choose Paint, then Stockpile, and drag over open ground."},
	{"t": "Build a crafting bench", "h": "Choose Build, then Crafting bench, and click open ground."},
	{"t": "Craft an axe and a pickaxe", "h": "Select the bench and queue a wooden axe and a wooden pickaxe. It makes their planks and sticks first. An axe chops 2.5× faster."},
	{"t": "Break a boulder", "h": "Choose Gather, then Mine (or press X), and click a boulder. Ada uses her pickaxe."},
	{"t": "Hunt sheep for wool", "h": "Choose Gather, then Hunt (or press G), and mark sheep. The clearing's 3 sheep give the 3 wool a bed needs."},
	{"t": "Build Ada’s house", "h": "Choose Build, then House. R turns the door. Its last stage is the bed."},
	{"t": "Build a fireplace", "h": "A trip needs a meal for the walk home. Build a fireplace (6 cobblestone): it cooks the mutton from the sheep."},
	{"t": "Build an expedition board", "h": "The second bed needs more wool than the clearing has. The board plans trips off the map."},
	{"t": "Fetch wool from the meadow", "h": "At the board, plan a trip to the meadow with Ada and a wool target, then Depart. The village waits while she's away."},
	{"t": "Build a second house", "h": "Its bed is what brings a traveler."},
	{"t": "Welcome a traveler", "h": "Tomas, a lumberjack, arrives a little while after the second bed is ready."},
	{"t": "Build Tomas a chopping block", "h": "Choose Build, then Chopping block, near trees. Tomas fells the trees around it on his own, while Ada does everything else."},
]


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
