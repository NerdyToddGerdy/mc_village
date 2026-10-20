class_name SaveFormat
extends RefCounted
## Reading, writing and upgrading save files.
##
## A save file is one `var_to_str` Dictionary:
##   {v, summary, tick, saved_at, state: Sim.save_state(), camera, speed}
## `v` is the save format version for the whole file.
##
## When the shape of saved data changes:
## 1. Bump VERSION.
## 2. Add an entry to upgrades() that turns a save of the previous version into the new shape.
## 3. Add tests/fixtures/save_v<N>.save (made with tests/fixtures/make_save_fixture.gd) and a test
##    that loads it, alongside the older fixtures, which must keep loading.

const VERSION := 11

## Version N -> the step that upgrades a version-N save to version N + 1. Each step takes the
## whole save Dictionary and returns it upgraded. Steps never need to set `v`; upgrade() does.
static func upgrades() -> Dictionary:
	return {1: _v1_to_v2, 2: _v2_to_v3, 3: _v3_to_v4, 4: _v4_to_v5, 5: _v5_to_v6, 6: _v6_to_v7, 7: _v7_to_v8, 8: _v8_to_v9, 9: _v9_to_v10, 10: _v10_to_v11}


## v11: experience in each job (issue #48). Everyone in an older save starts at level 1.
static func _v10_to_v11(d: Dictionary) -> Dictionary:
	for r in d.state.residents:
		for jb in r.jobs:
			if not r.jobs[jb].has("xp"):
				r.jobs[jb].xp = 0
	return d


## v10: residents' jobs, each on or off with a priority (issue #47). Everyone starts with every
## job on at priority 2, which is how they worked before.
static func _v9_to_v10(d: Dictionary) -> Dictionary:
	for r in d.state.residents:
		if not r.has("jobs"):
			r.jobs = Sim.default_jobs()
	return d


## v9: reserved plots for job buildings, and the fireplace's standing order (issue #46). Benches
## from older saves reserve nothing.
static func _v8_to_v9(d: Dictionary) -> Dictionary:
	for s in d.state.sites:
		if not s.has("plot"):
			s.plot = null
	return d


## v8: farm plots and growing wheat (issue #45). Older saves have no farms.
static func _v7_to_v8(d: Dictionary) -> Dictionary:
	if not d.state.has("farm"):
		d.state.farm = {}
	return d


## v7: hunger and berry bushes (issue #44). Residents start full. Older saves get the same berry
## bushes as a new game, placed relative to the opening (shifted on 32×32 maps); any that land on a
## tree, boulder or building are dropped when the save loads.
static func _v6_to_v7(d: Dictionary) -> Dictionary:
	for r in d.state.residents:
		if not r.has("hunger"):
			r.hunger = 100.0
	if not d.state.has("bushes"):
		var o: Vector2i = Tuning.OPENING_OFFSET if int(d.state.w) > 18 else Vector2i.ZERO
		var next_id: int = d.state.next_id
		var list: Array = []
		for p in Sim.START_BUSHES:
			list.append({"id": next_id, "kind": "bush", "cell": Vector2i(p[0], p[1]) + o, "berries": Tuning.BUSH_MAX, "regrow": 0.0})
			next_id += 1
		d.state.bushes = list
		d.state.next_id = next_id
	return d


## v6: houses have a fourth stage, the bed (issue #43). A finished house in an older save gets a
## finished bed, so its resident stays housed.
static func _v5_to_v6(d: Dictionary) -> Dictionary:
	for s in d.state.sites:
		if s.tpl == "house" and s.done and s.stage < 4:
			s.stage = 4
	return d


## v5: sheep and the sim's random-number state (issue #42). Older saves are past the opening, so
## they get no sheep; their random numbers start from the game's seed.
static func _v4_to_v5(d: Dictionary) -> Dictionary:
	if not d.state.has("sheep"):
		d.state.sheep = []
	if not d.state.has("rng_state"):
		var g := RandomNumberGenerator.new()
		g.seed = Tuning.SEED
		d.state.rng_state = g.state
	return d


## v4: the map size is saved (issue #52). Everything before v4 was played on the 18×18 map.
static func _v3_to_v4(d: Dictionary) -> Dictionary:
	if not d.state.has("w"):
		d.state.w = 18
		d.state.h = 18
	return d


## v3: residents have a list of queued orders (Shift + right-click, issue #2).
static func _v2_to_v3(d: Dictionary) -> Dictionary:
	for r in d.state.residents:
		if not r.has("orders"):
			r.orders = []
	return d


## v2: tool items remember their remaining uses (issue #5). In v1 a dropped tool always came back
## new, so give every loose or carried tool full uses.
static func _v1_to_v2(d: Dictionary) -> Dictionary:
	for k in d.state.items:
		var it: Dictionary = d.state.items[k]
		if Defs.is_tool_item(it.type) and not it.has("dur"):
			it.dur = Sim.full_uses(it.type)
	for r in d.state.residents:
		if r.get("carry") != null and Defs.is_tool_item(r.carry.type) and not r.carry.has("dur"):
			r.carry.dur = Sim.full_uses(r.carry.type)
	return d


## Reads a save file. Returns {"data": Dictionary} upgraded to the current version, or
## {"error": text for the player} when the file can't be used.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "This slot is empty."}
	return parse(FileAccess.get_file_as_string(path))


static func parse(text: String) -> Dictionary:
	var data = str_to_var(text)
	if not (data is Dictionary) or not data.has("v") or not data.has("state"):
		return {"error": "This save is damaged and can’t be loaded."}
	return upgrade(data)


## Runs `data` through each upgrade step from its version up to `target`, in order. `steps` and
## `target` default to the real ones; tests pass their own to check the chain.
static func upgrade(data: Dictionary, steps = null, target := VERSION) -> Dictionary:
	if steps == null:
		steps = upgrades()
	var v: int = int(data.v)
	if v > target:
		return {"error": "This save is from a newer version of the game."}
	while v < target:
		if not steps.has(v):
			return {"error": "This save is from an old version that can’t be upgraded."}
		data = (steps[v] as Callable).call(data)
		v += 1
		data.v = v
	return {"data": data}


static func write(path: String, data: Dictionary) -> bool:
	data.v = VERSION
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(var_to_str(data))
	f.close()
	return true
