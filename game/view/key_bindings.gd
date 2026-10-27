class_name KeyBindings
extends RefCounted
## Rebindable keyboard shortcuts (issue #8). A binding is a keycode, optionally combined with
## KEY_MASK_SHIFT (as for "?" = Shift + /). Each action can have several keys. Esc and the mouse
## modifiers are fixed so the player can always cancel and reach the menu. Bindings are saved to
## their own settings file, separate from game saves.

const ACTIONS := [
	# [id, group, label, default keys]
	["gather", "Orders", "Open the gather menu", [KEY_E]],
	["mine", "Orders", "Mine trees and boulders", [KEY_X]],
	["chop", "Orders", "Chop trees only", []],
	["break", "Orders", "Break boulders only", []],
	["keep", "Orders", "Keep trees and boulders from gatherers", []],
	["hunt", "Orders", "Hunt animals", [KEY_G]],
	["lead", "Orders", "Lead animals to a pen", []],
	["paint", "Orders", "Open the paint menu", [KEY_Z]],
	["stock", "Orders", "Paint a stockpile", []],
	["farm", "Orders", "Paint a farm plot", [KEY_P]],
	["pen", "Orders", "Paint a pen, at the meadow", []],
	["build", "Orders", "Open the build menu", [KEY_B]],
	["craft", "Orders", "Open the craft menu", [KEY_C]],
	["bench", "Orders", "Place a crafting bench", [KEY_T]],
	["house", "Orders", "Place a house", [KEY_H]],
	["fireplace", "Orders", "Place a fireplace", [KEY_K]],
	["board", "Orders", "Place an expedition board", []],
	["chopping_block", "Orders", "Place a chopping block", []],
	["storehouse", "Orders", "Place a storehouse", []],
	["mason_bench", "Orders", "Place a mason's bench", []],
	["toolsmith_bench", "Orders", "Place a toolsmith's bench", []],
	["composter", "Orders", "Place a composter", []],
	["lodge", "Orders", "Place a hunter's lodge", []],
	["builder_table", "Orders", "Place a builder's table", []],
	["rotate", "Orders", "Turn a building while placing", [KEY_R]],
	["next_res", "Residents", "Select the next resident", [KEY_F]],
	["jobs", "Residents", "Open the village jobs board", [KEY_J]],
	["next_stuck", "Residents", "Go to the next stuck item", [KEY_N]],
	["map", "Time and camera", "Switch between the village and a site", [KEY_TAB]],
	["pause", "Time and camera", "Pause", [KEY_QUOTELEFT, KEY_ASCIITILDE]],
	["toggle_pause", "Time and camera", "Pause or resume", [KEY_SPACE]],
	["speed1", "Time and camera", "Speed 1×", [KEY_1]],
	["speed2", "Time and camera", "Speed 2×", [KEY_2]],
	["speed3", "Time and camera", "Speed 3×", [KEY_3]],
	["pan_up", "Time and camera", "Pan up", [KEY_W, KEY_UP]],
	["pan_left", "Time and camera", "Pan left", [KEY_A, KEY_LEFT]],
	["pan_down", "Time and camera", "Pan down", [KEY_S, KEY_DOWN]],
	["pan_right", "Time and camera", "Pan right", [KEY_D, KEY_RIGHT]],
	["zoom_in", "Time and camera", "Zoom in", [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]],
	["zoom_out", "Time and camera", "Zoom out", [KEY_MINUS, KEY_KP_SUBTRACT]],
	["menu", "Game", "Open the menu", [KEY_M]],
	["controls", "Game", "Show the controls", [KEY_SLASH | KEY_MASK_SHIFT, KEY_QUESTION]],
]

const FIXED := [KEY_ESCAPE]  ## Keys that can't be bound to anything.

var path := "user://settings/keys.cfg"
var keys := {}   ## action id -> Array of key codes
var pinned: Array = []  ## Items pinned to the tally bar (issue #141): a view preference, kept here, not in game saves.


func _init(p_path := "") -> void:
	if p_path != "":
		path = p_path
	reset()
	load_file()


func reset() -> void:
	keys = {}
	for a in ACTIONS:
		keys[a[0]] = (a[3] as Array).duplicate()


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var fresh: Array = []  # actions newer than the file, which keep their default keys
	for a in ACTIONS:
		var v = cfg.get_value("keys", a[0], null)
		if v is Array:
			keys[a[0]] = v.filter(func(k): return k is int)
		else:
			fresh.append(a[0])
	# Issue #93 moved Z from Stockpile to the Paint menu. A file from before then that still has
	# Stockpile on Z hands it over; any other default key the player already uses stays theirs.
	if fresh.has("paint") and keys.stock == [KEY_Z]:
		keys.stock = []
	for id in fresh:
		keys[id] = keys[id].filter(func(k): return not keys.keys().any(func(o): return o != id and not fresh.has(o) and keys[o].has(k)))
	var pins = cfg.get_value("tally", "pinned", [])
	if pins is Array:
		pinned = pins.filter(func(t): return t is String and Defs.ITEMS.has(t)).slice(0, Defs.MAX_PINNED)


func save_file() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var cfg := ConfigFile.new()
	for a in ACTIONS:
		cfg.set_value("keys", a[0], keys[a[0]])
	cfg.set_value("tally", "pinned", pinned)
	return cfg.save(path) == OK


## The key code an event stands for: its keycode, plus Shift when Shift is held.
static func event_code(e: InputEventKey) -> int:
	return e.keycode | (KEY_MASK_SHIFT if e.shift_pressed else 0)


## The action an event triggers, or "". An exact match (Shift + / for "?") wins; otherwise Shift is
## ignored, so a letter works the same with or without Shift held.
func action_for(e: InputEventKey) -> String:
	var code := event_code(e)
	for exact in [true, false]:
		for id in keys:
			for k in keys[id]:
				if (exact and k == code) or (not exact and k == e.keycode):
					return id
	return ""


func is_down(action: String) -> bool:
	for k in keys[action]:
		if k & KEY_MASK_SHIFT == 0 and Input.is_key_pressed(k):
			return true
	return false


## The action already using `code`, other than `except`, or "".
func used_by(code: int, except := "") -> String:
	for id in keys:
		if id != except and keys[id].has(code):
			return id
	return ""


## Makes `code` the only key for `action`, taking it away from any other action.
func assign(action: String, code: int) -> void:
	var other := used_by(code, action)
	if other != "":
		keys[other].erase(code)
	keys[action] = [code]


static func label_of(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[2]
	return action


static func key_text(code: int) -> String:
	match code:
		KEY_QUOTELEFT: return "`"
		KEY_ASCIITILDE: return "~"
		KEY_EQUAL: return "="
		KEY_MINUS: return "−"
		KEY_TAB: return "Tab"
		KEY_SLASH | KEY_MASK_SHIFT: return "?"
	return OS.get_keycode_string(code)


## The first key for an action, for toolbar badges and hints ("" when it has none).
func first(action: String) -> String:
	return key_text(keys[action][0]) if not keys[action].is_empty() else ""


## Every key for an action, for the Controls page ("No key" when it has none).
func text(action: String) -> String:
	if keys[action].is_empty():
		return "No key"
	return "  ".join(keys[action].map(func(k): return key_text(k)))
