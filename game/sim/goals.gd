class_name Goals
extends RefCounted
## The founding checklist shown to the player, with a hint for the current step.

const LIST := [
	{"t": "Chop a tree", "h": "Choose Mine, then click a tree. Ada fells it by hand, slowly."},
	{"t": "Build a crafting bench", "h": "Choose Build, then Crafting bench, and click open ground."},
	{"t": "Craft a pickaxe", "h": "Select the bench. Queue planks, sticks, then a wooden pickaxe."},
	{"t": "Paint a stockpile", "h": "Choose Stockpile and drag over open ground."},
	{"t": "Break a boulder", "h": "Choose Mine, then click a boulder. Ada uses her pickaxe."},
	{"t": "Hunt sheep for wool", "h": "Choose Hunt (G) and mark sheep. Each gives 1 wool; a house's bed needs 3."},
	{"t": "Build Ada’s house", "h": "Choose Build, then House. R turns the door. Its last stage is the bed."},
	{"t": "Build a second house", "h": "Queue planks at the bench for the walls and roof. Tools now get their planks and sticks made automatically."},
	{"t": "Welcome a traveler", "h": "Someone arrives a little while after the second house is done."},
	{"t": "Two residents at work", "h": "Keep both busy with different jobs."},
]


static func done(sim: Sim, i: int) -> bool:
	match i:
		0: return sim.stats.felled > 0
		1: return sim.sites.any(func(s): return s.tpl == "bench" and s.done)
		2: return sim.stats.pick_crafted
		3: return not sim.zone.is_empty()
		4: return sim.stats.broken_boulders > 0
		5: return sim.stats.get("sheep_hunted", 0) > 0
		6: return sim.stats.houses >= 1
		7: return sim.stats.houses >= 2
		8: return sim.stats.traveler_home
		_: return sim.stats.division


## Index of the first unfinished goal, or -1 when the founding is complete.
static func current(sim: Sim) -> int:
	for i in LIST.size():
		if not done(sim, i):
			return i
	return -1


static func progress_text(sim: Sim) -> String:
	var i := current(sim)
	return "Founding complete" if i < 0 else "Next: " + LIST[i].t
