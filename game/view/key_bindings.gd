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
	["pen", "Orders", "Paint a pen, at the meadow", []],
	["build", "Orders", "Open the build menu", [KEY_B]],
	["craft", "Orders", "Open the craft menu", [KEY_C]],
	["bench", "Orders", "Place a crafting bench", [KEY_T]],
	["house", "Orders", "Place a house", [KEY_H]],
	["fireplace", "Orders", "Place a fireplace", [KEY_K]],
	["board", "Orders", "Place an expedition board", []],
	["chopping_block", "Orders", "Place a chopping block", []],
	["storehouse", "Orders", "Place a storehouse", []],
	["portal", "Orders", "Place a Nether portal", []],
	["enchanting_workshop", "Orders", "Place an enchanting workshop", []],
	["portal_station", "Orders", "Place a portal station", []],
	["dock", "Orders", "Place a dock", []],
	["boatyard", "Orders", "Place a boatyard", []],
	["cache_sensor", "Orders", "Place a cache sensor", []],
	["condition", "Orders", "Place a condition", []],
	["freight_loader", "Orders", "Place a freight loader", []],
	["dispatcher", "Orders", "Place a dispatcher", []],
	["redstone_overlay", "Time and camera", "Show or hide the redstone overlay", [KEY_O]],
	["minimap", "Time and camera", "Show or hide the minimap", [KEY_I]],
	["worldmap", "Time and camera", "Open the world map", [KEY_P]],
	["claim", "Orders", "Claim land", []],
	["mason_bench", "Orders", "Place a mason's bench", []],
	["toolsmith_bench", "Orders", "Place a toolsmith's bench", []],
	["composter", "Orders", "Place a composter", []],
	["lodge", "Orders", "Place a hunter's lodge", []],
	["builder_table", "Orders", "Place a builder's table", []],
	["cartographer_table", "Orders", "Place a cartographer's table", []],
	["village_pen", "Orders", "Place a village pen", []],
	["rotate", "Orders", "Turn a building while placing", [KEY_R]],
	["next_res", "Residents", "Select the next resident", [KEY_F]],
	["jobs", "Residents", "Open the village jobs board", [KEY_J]],
	["next_stuck", "Residents", "Go to the next stuck item", [KEY_N]],
	["see_through", "Time and camera", "Hold to see through every tree", [KEY_Y]],
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
	["panel1", "Selection", "Panel action 1", [KEY_Q]],
	["panel2", "Selection", "Panel action 2", [KEY_E]],
	["panel3", "Selection", "Panel action 3", [KEY_R]],
	["panel4", "Selection", "Panel action 4", [KEY_Z]],
	["panel5", "Selection", "Panel action 5", [KEY_X]],
	["panel6", "Selection", "Panel action 6", [KEY_C]],
	["panel7", "Selection", "Panel action 7", [KEY_V]],
	["list1", "Selection", "List entry 1", [KEY_1]],
	["list2", "Selection", "List entry 2", [KEY_2]],
	["list3", "Selection", "List entry 3", [KEY_3]],
	["list4", "Selection", "List entry 4", [KEY_4]],
	["list5", "Selection", "List entry 5", [KEY_5]],
	["list6", "Selection", "List entry 6", [KEY_6]],
	["list7", "Selection", "List entry 7", [KEY_7]],
	["list8", "Selection", "List entry 8", [KEY_8]],
	["list9", "Selection", "List entry 9", [KEY_9]],
	["menu", "Game", "Open the menu", [KEY_M]],
	["controls", "Game", "Show the controls", [KEY_SLASH | KEY_MASK_SHIFT, KEY_QUESTION]],
]

const FIXED := [KEY_ESCAPE]  ## Keys that can't be bound to anything.

## The controller (issue #421, the Steam Deck): an action can also have joypad buttons. A is the left click, X the right click and B Esc, and those
## can't be rebound; the left stick pans, the right stick moves the cursor and the triggers zoom. Everything else here is rebindable.
const PAD_FIXED := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X]
const PAD_DEFAULTS := {
	"gather": [JOY_BUTTON_Y], "build": [JOY_BUTTON_LEFT_SHOULDER], "craft": [JOY_BUTTON_RIGHT_SHOULDER],
	"menu": [JOY_BUTTON_START], "worldmap": [JOY_BUTTON_BACK], "toggle_pause": [JOY_BUTTON_LEFT_STICK],
	"next_res": [JOY_BUTTON_RIGHT_STICK], "map": [JOY_BUTTON_GUIDE],
	"pan_up": [JOY_BUTTON_DPAD_UP], "pan_down": [JOY_BUTTON_DPAD_DOWN], "pan_left": [JOY_BUTTON_DPAD_LEFT], "pan_right": [JOY_BUTTON_DPAD_RIGHT],
}

## The Selection group's keys act on the selection panel (issue #197), so they may share a key with an
## order (Q E R Z X C V are the order keys too) or the speed keys (1 to 3, while a list is open), and
## nothing else. They are looked up with panel_index() and list_index(), never action_for().
const SELECTION := "Selection"
const SHARED_WITH_SELECTION := ["speed1", "speed2", "speed3"]  ## besides the Orders group

var path := "user://settings/keys.cfg"
var keys := {}   ## action id -> Array of key codes
var pads := {}   ## action id -> Array of joypad buttons (issue #421)
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
	pads = {}
	for a in ACTIONS:
		pads[a[0]] = (PAD_DEFAULTS.get(a[0], []) as Array).duplicate()


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var fresh: Array = []  # actions newer than the file, which keep their default keys
	for a in ACTIONS:
		# has_section_key first: get_value with a null default logs an error for every missing key.
		var v = cfg.get_value("keys", a[0]) if cfg.has_section_key("keys", a[0]) else null
		if v is Array:
			keys[a[0]] = v.filter(func(k): return k is int)
		else:
			fresh.append(a[0])
	for id in fresh:
		keys[id] = keys[id].filter(func(k): return not keys.keys().any(func(o): return o != id and not fresh.has(o) and keys[o].has(k) and not may_share(id, o)))
	for a in ACTIONS:  # buttons kept in the file win; an action it doesn't mention keeps its default buttons
		var pv = cfg.get_value("pads", a[0]) if cfg.has_section_key("pads", a[0]) else null
		if pv is Array:
			pads[a[0]] = pv.filter(func(b): return b is int and not PAD_FIXED.has(b))
	var pins = cfg.get_value("tally", "pinned", [])
	if pins is Array:
		pinned = pins.filter(func(t): return t is String and Defs.ITEMS.has(t)).slice(0, Defs.MAX_PINNED)


func save_file() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var cfg := ConfigFile.new()
	for a in ACTIONS:
		cfg.set_value("keys", a[0], keys[a[0]])
	for id in pads:
		if not pads[id].is_empty() or PAD_DEFAULTS.has(id):
			cfg.set_value("pads", id, pads[id])
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
			if group_of(id) == SELECTION:
				continue
			for k in keys[id]:
				if (exact and k == code) or (not exact and k == e.keycode):
					return id
	return ""


func is_down(action: String) -> bool:
	for b in pads.get(action, []):
		if Input.is_joy_button_pressed(0, b):
			return true
	for k in keys[action]:
		if k & KEY_MASK_SHIFT == 0 and Input.is_key_pressed(k):
			return true
	return false


## The Selection action (panel1 to panel7) an event stands for, as an index from 0, or -1.
func panel_index(e: InputEventKey) -> int:
	return _selection_index(e, "panel", 7)


## The list entry (list1 to list9) an event stands for, as an index from 0, or -1.
func list_index(e: InputEventKey) -> int:
	return _selection_index(e, "list", 9)


func _selection_index(e: InputEventKey, prefix: String, n: int) -> int:
	var code := event_code(e)
	for exact in [true, false]:
		for i in n:
			for k in keys["%s%d" % [prefix, i + 1]]:
				if (exact and k == code) or (not exact and k == e.keycode):
					return i
	return -1


static func group_of(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return ""


## Whether two actions may be bound to the same key: a Selection action and an order or a speed key.
static func may_share(a: String, b: String) -> bool:
	var ga := group_of(a)
	var gb := group_of(b)
	if ga == SELECTION and gb != SELECTION:
		return gb == "Orders" or SHARED_WITH_SELECTION.has(b)
	if gb == SELECTION and ga != SELECTION:
		return ga == "Orders" or SHARED_WITH_SELECTION.has(a)
	return false


## The action already using `code`, other than `except`, or "". A Selection action and an order
## don't count as using each other's keys (issue #197).
func used_by(code: int, except := "") -> String:
	for id in keys:
		if id != except and keys[id].has(code) and (except == "" or not may_share(id, except)):
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


## The action a controller button triggers, or "" (issue #421).
func pad_action_for(button: int) -> String:
	for id in pads:
		if pads[id].has(button):
			return id
	return ""


## Makes `button` the only button for `action`, taking it away from any other action.
func pad_assign(action: String, button: int) -> void:
	for id in pads:
		pads[id].erase(button)
	pads[action] = [button]


## Every button for an action, for the Controls page ("-" when it has none).
func pad_text(action: String) -> String:
	if pads.get(action, []).is_empty():
		return "-"
	return " ".join(pads[action].map(func(b): return pad_button_text(b)))


static func pad_button_text(button: int) -> String:
	return {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Select", JOY_BUTTON_GUIDE: "Steam", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
		JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right"}.get(button, "Button %d" % button)
