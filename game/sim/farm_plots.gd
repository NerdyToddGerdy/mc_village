class_name FarmPlots
extends RefCounted
## Split out of sim.gd (#305). Every function takes the Sim it works on; Sim keeps one-line forwarders so commands, the view and tests are unchanged.

## Whether a composter reaches cell `c`: within PLOT_REACH cells of it, either way (a square, not a circle).
static func composter_reaches(s: Dictionary, c: Vector2i) -> bool:
	return maxi(absi(c.x - s.origin.x), absi(c.y - s.origin.y)) <= Tuning.PLOT_REACH


## The finished composters of this map.
static func composters(sim: Sim) -> Array:
	return sim.m.sites.filter(func(s): return s.tpl == "composter" and s.done)


## The plots a composter owns.
static func composter_plots(sim: Sim, s: Dictionary) -> Array:
	return sim.m.farm.values().filter(func(c): return c.get("owner", 0) == s.id)


## A plot nobody's composter reaches, or whose composter is gone, is drying out: 0 while it's looked after.
static func plot_dying(crop: Dictionary) -> float:
	return crop.get("dying", 0.0)


## Paints plots round a composter, or takes them away when `erase` (issue #319). Cells must be open grass within its reach and
## clear of its own reserved plot; a plot of another composter's that this one reaches moves over. Returns how many cells
## were out of reach.
static func paint_plots(sim: Sim, s: Dictionary, rect: Rect2i, erase := false) -> int:
	if s.map != sim.map_id:
		return sim.on_map(s.map, sim.paint_plots.bind(s, rect, erase))
	var far := 0
	if sim.m.kind != "village" or s.tpl != "composter" or not s.done:
		return 0
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var c := Vector2i(x, y)
			if erase:
				var own = sim.m.farm.get(c)
				if own != null and own.get("owner", 0) == s.id:
					sim._drop_crop(c)
				continue
			if not sim.composter_reaches(s, c):
				far += 1
				continue
			var have = sim.m.farm.get(c)
			if have != null:
				if have.get("owner", 0) != 0 and have.owner != s.id:  # one owner a cell: it moves over
					have.owner = s.id
					have.erase("dying")
				continue
			if sim.farm_blocked(c) != "":
				continue
			sim.m.farm[c] = {"id": sim._id(), "kind": "crop", "cell": c, "grow": -1.0, "claim": 0, "unreach_until": 0, "owner": s.id}
			sim._clear_wear(c)
	sim.rev += 1
	return far


## A new composter starts with plots on the open ground round it, nearest first, so a farmer has work at once.
static func _start_plots(sim: Sim, s: Dictionary) -> void:
	var cells: Array = []
	for d in range(1, Tuning.PLOT_REACH + 1):
		for dx in range(-d, d + 1):
			for dy in range(-d, d + 1):
				if maxi(absi(dx), absi(dy)) == d:
					cells.append(s.origin + Vector2i(dx, dy))
	var n := 0
	for c in cells:
		if n >= Tuning.PLOT_START_MAX:
			break
		if sim.m.in_bounds(c) and sim.farm_blocked(c) == "" and not sim.m.items.has(c):
			sim.m.farm[c] = {"id": sim._id(), "kind": "crop", "cell": c, "grow": -1.0, "claim": 0, "unreach_until": 0, "owner": s.id}
			sim._clear_wear(c)
			n += 1
	if n > 0:
		sim.rev += 1


## Once a second: an owned plot whose composter is gone or out of reach passes to another that reaches it, or, if there's none,
## dries out, goes bare and turns back to grass over PLOT_DIE_SECONDS. A plot with no `owner` (one painted before this) is never touched.
static func _step_plots(sim: Sim) -> void:
	var ours := sim.composters()
	var changed := false
	for k in sim.m.farm.keys():
		var crop: Dictionary = sim.m.farm[k]
		if not crop.has("owner"):
			continue
		var home := sim.site(crop.owner)
		if not home.is_empty() and home.done and sim.composter_reaches(home, crop.cell):
			if crop.has("dying"):
				crop.erase("dying")
				changed = true
			continue
		var heir = null
		for o in ours:
			if sim.composter_reaches(o, crop.cell):
				heir = o
				break
		if heir != null:
			crop.owner = heir.id
			crop.erase("dying")
			changed = true
			continue
		var before: float = crop.get("dying", 0.0)
		var now: float = before + 1.0
		crop.dying = now
		var third := Tuning.PLOT_DIE_SECONDS / 3.0
		if before < third and now >= third:  # bare: whatever grew there is lost
			crop.grow = -1.0
			if crop.claim != 0:
				var w := sim.resident(crop.claim)
				if not w.is_empty() and w.job != null and is_same(w.job.target, crop):
					sim.fail_job(w)
			changed = true
		if now >= Tuning.PLOT_DIE_SECONDS:
			sim._drop_crop(k)
			changed = true
		elif int(before / 20.0) != int(now / 20.0):
			changed = true
	if changed:
		sim.rev += 1


## Removes farm plots in `rect`; anything growing there is lost.
static func clear_farm(sim: Sim, rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			sim._drop_crop(Vector2i(x, y))
	sim.rev += 1


static func _drop_crop(sim: Sim, c: Vector2i) -> void:
	var crop = sim.m.farm.get(c)
	if crop == null:
		return
	if crop.claim != 0:
		var r := sim.resident(crop.claim)
		if not r.is_empty() and r.job != null and is_same(r.job.target, crop):
			sim.fail_job(r)
