class_name Goals
extends RefCounted
## The founding checklist shown to the player, with a hint for the current step.

const LIST := [
	{"t": "Chop a tree", "h": "Choose Gather, then Mine (or press X), and click a tree. Ada fells it by hand, slowly."},
	{"t": "Build a crafting bench", "h": "Choose Build, then Crafting bench, and click open ground."},
	{"t": "Make Ada the toolsmith", "h": "Select Ada and switch Toolsmith on in her Jobs. Only a toolsmith makes tools."},
	{"t": "Craft a pickaxe", "h": "Select the bench. Queue planks, sticks, then a wooden pickaxe."},
	{"t": "Paint a stockpile", "h": "Choose Paint, then Stockpile, and drag over open ground."},
	{"t": "Break a boulder", "h": "Choose Gather, then Mine (or press X), and click a boulder. Ada uses her pickaxe."},
	{"t": "Hunt sheep for wool", "h": "Choose Gather, then Hunt (or press G), and mark sheep. Each gives 1 wool; a house's bed needs 3."},
	{"t": "Build Ada’s house", "h": "Choose Build, then House. R turns the door. Its last stage is the bed."},
	{"t": "Build a second house", "h": "Queue planks at the bench for the walls and roof. Tools now get their planks and sticks made automatically."},
	{"t": "Welcome a traveler", "h": "Someone arrives a little while after the second house is done."},
	{"t": "Two residents at work", "h": "Keep both busy with different jobs."},
]


static func done(sim: Sim, i: int) -> bool:
	match i:
		0: return sim.stats.felled > 0
		1: return sim.sites.any(func(s): return s.tpl == "bench" and s.done)
		2: return sim.has_toolsmith() or sim.stats.pick_crafted  # stays done once a pickaxe is made (issue #91)
		3: return sim.stats.pick_crafted
		4: return not sim.zone.is_empty()
		5: return sim.stats.broken_boulders > 0
		6: return sim.stats.get("sheep_hunted", 0) > 0
		7: return sim.stats.houses >= 1
		8: return sim.stats.houses >= 2
		9: return sim.stats.traveler_home
		_: return sim.stats.division


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
