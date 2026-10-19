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
## 2. Add an entry to UPGRADES that turns a save of the previous version into the new shape.
## 3. Add tests/fixtures/save_v<N>.save (made with tests/fixtures/make_save_fixture.gd) and a test
##    that loads it, alongside the older fixtures, which must keep loading.

const VERSION := 1

## Version N -> the step that upgrades a version-N save to version N + 1. Each step takes the
## whole save Dictionary and returns it upgraded. Steps never need to set `v`; upgrade() does.
const UPGRADES := {}


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
static func upgrade(data: Dictionary, steps := UPGRADES, target := VERSION) -> Dictionary:
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
