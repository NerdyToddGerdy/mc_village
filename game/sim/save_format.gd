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

const VERSION := 2

## Version N -> the step that upgrades a version-N save to version N + 1. Each step takes the
## whole save Dictionary and returns it upgraded. Steps never need to set `v`; upgrade() does.
static func upgrades() -> Dictionary:
	return {1: _v1_to_v2}


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
