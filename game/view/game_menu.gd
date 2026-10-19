class_name GameMenu
extends Control
## The main menu (slice-1-spec.md §2, Main menu): Play/Resume, Save game and Load game with
## 5 slots, Controls, and Start over. Overwriting, loading and starting over ask for confirmation
## here on the page. The game pauses while the menu is open.

const KEY_LIST := [
	["Orders", [["X", "Mine trees and boulders"], ["Z", "Paint a stockpile"], ["B", "Open the build menu"],
		["T", "Place a crafting bench"], ["H", "Place a house"], ["R", "Turn the house door while placing"],
		["Esc", "Cancel the current order"]]],
	["Residents", [["Click", "Select a resident, tree, boulder or building"], ["Shift-drag", "Select several residents"],
		["F", "Select the next resident"], ["N", "Go to the next stuck item"],
		["Right-click", "Order the selected residents"]]],
	["Time and camera", [["~", "Pause"], ["Space", "Pause or resume"], ["1  2  3", "Speed 1×, 2× or 3×"],
		["Drag", "Pan the map (W A S D, arrow keys and middle-drag too)"], ["+  −", "Zoom (mouse wheel and pinch too)"]]],
	["Game", [["Esc  M", "Open the menu"], ["?", "Show these controls"]]],
]

var game   ## The Game node.
var hud: Hud
var view := "main"
var first := true          ## Before the first Play, the main button says Play.
var _confirm := {}         ## {text, yes, action, slot}
var _msg := ""
var _msg_err := false
var _slots: Array = []
var _box := VBoxContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(Palette.SLATE_DEEP, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", hud.box(Palette.SLATE, 8, 22, Palette.SLATE_DEEP))
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	_box.add_theme_constant_override("separation", 12)
	panel.add_child(_box)
	visible = false


func show_view(v: String) -> void:
	view = v
	_confirm = {}
	_msg = ""
	if v == "save" or v == "load":
		_slots = game.read_slots()
	visible = true
	_render()


func back() -> void:
	if not _confirm.is_empty():
		_confirm = {}
		_render()
	elif view != "main":
		show_view("main")
	else:
		game.close_menu()


func _render() -> void:
	for ch in _box.get_children():
		ch.queue_free()
	match view:
		"main": _render_main()
		"keys": _render_keys()
		_: _render_slots()
	await get_tree().process_frame
	for ch in _box.get_children():
		if ch is Button and not ch.disabled:
			ch.grab_focus()
			break


func _title(text: String, sub: String) -> void:
	var t := hud.label(text, true, Palette.CHALK, 34)
	_box.add_child(t)
	if sub != "":
		_box.add_child(hud.label(sub, false, Palette.CHALK_DIM, 15, true))


func _big_button(text: String, on_press: Callable, primary := false) -> Button:
	var b := hud.button(text, on_press)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 17)
	var border := Palette.CHALK if primary else Palette.CHALK_DIM
	b.add_theme_stylebox_override("normal", hud.box(Palette.SLATE_DEEP if primary else Color(0, 0, 0, 0), 4, 14, border))
	b.add_theme_stylebox_override("hover", hud.box(Palette.SLATE_DEEP, 4, 14, Palette.CHALK))
	return b


func _render_main() -> void:
	_title("Block Village", "The founding. %s." % Goals.progress_text(game.sim))
	_box.add_child(_big_button("Play" if first else "Resume", func(): game.close_menu(), true))
	_box.add_child(_big_button("Save game", func(): show_view("save")))
	_box.add_child(_big_button("Load game", func(): show_view("load")))
	_box.add_child(_big_button("Controls", func(): show_view("keys")))
	_box.add_child(_big_button("Start over", func(): _ask("Start a new game? Anything you haven’t saved will be lost.", "Start over", "restart")))
	_add_confirm()
	_box.add_child(hud.label("Saves are kept on this computer. Esc or M opens this menu.", false, Palette.CHALK_DIM, 13, true))


func _render_keys() -> void:
	_title("Controls", "Press ? in the game to open this list.")
	for group in KEY_LIST:
		_box.add_child(hud.label(group[0], true, Palette.CHALK, 16))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		for row in group[1]:
			var k := hud.label(row[0], true, Palette.CHALK, 14)
			k.custom_minimum_size = Vector2(110, 0)
			grid.add_child(k)
			grid.add_child(hud.label(row[1], false, Palette.CHALK, 14))
		_box.add_child(grid)
	_box.add_child(_back_button())


func _render_slots() -> void:
	var saving := view == "save"
	_title("Save game" if saving else "Load game", "Choose a slot. Saving over a slot replaces it." if saving else "Choose a save to continue from.")
	for i in _slots.size():
		var n := i + 1
		var meta = _slots[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		info.add_child(hud.label("Slot %d" % n, true))
		if meta == null:
			info.add_child(hud.label("Empty", false, Palette.CHALK_DIM, 14))
		else:
			info.add_child(hud.label(meta.summary, false, Palette.CHALK, 14))
			info.add_child(hud.label("%s. Saved %s" % [_played(meta.tick), _when(meta.saved_at)], false, Palette.CHALK_DIM, 13))
		row.add_child(info)
		var b: Button
		if saving:
			if meta == null:
				b = hud.button("Save here", func(): _save(n))
			else:
				b = hud.button("Save over", func(): _ask("Save over slot %d? The save that’s there now will be replaced." % n, "Save over slot %d" % n, "save", n))
		else:
			b = hud.button("Load", func(): _ask("Load slot %d? Anything you haven’t saved will be lost." % n, "Load slot %d" % n, "load", n))
			b.disabled = meta == null
		b.custom_minimum_size = Vector2(110, 40)
		b.add_theme_stylebox_override("normal", hud.box(Color(0, 0, 0, 0), 4, 10, Palette.CHALK if not b.disabled else Palette.SLATE_DEEP))
		row.add_child(b)
		var slot_panel := PanelContainer.new()
		slot_panel.add_theme_stylebox_override("panel", hud.box(Color(Palette.SLATE_DEEP, 0.5), 6, 10, Palette.SLATE_DEEP))
		slot_panel.add_child(row)
		_box.add_child(slot_panel)
	_add_confirm()
	if _msg != "":
		_box.add_child(hud.label(_msg, _msg_err, Palette.YELLOW if _msg_err else Palette.CHALK_DIM, 15, true))
	_box.add_child(_back_button())


func _back_button() -> Button:
	var b := hud.button("Back", func(): show_view("main"))
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_stylebox_override("normal", hud.box(Color(0, 0, 0, 0), 4, 10, Palette.CHALK_DIM))
	return b


func _ask(text: String, yes: String, action: String, slot := 0) -> void:
	_confirm = {"text": text, "yes": yes, "action": action, "slot": slot}
	_render()


func _add_confirm() -> void:
	if _confirm.is_empty():
		return
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(hud.label(_confirm.text, false, Palette.CHALK, 15, true))
	var h := HBoxContainer.new()
	var go := hud.button(_confirm.yes, _do_confirmed)
	go.add_theme_color_override("font_color", Palette.YELLOW)
	go.add_theme_stylebox_override("normal", hud.box(Color(0, 0, 0, 0), 4, 10, Palette.YELLOW))
	h.add_child(go)
	var cancel := hud.button("Cancel", func(): _confirm = {}; _render())
	cancel.add_theme_stylebox_override("normal", hud.box(Color(0, 0, 0, 0), 4, 10, Palette.CHALK_DIM))
	h.add_child(cancel)
	v.add_child(h)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", hud.box(Color(0, 0, 0, 0), 6, 12, Palette.YELLOW))
	p.add_child(v)
	_box.add_child(p)


func _do_confirmed() -> void:
	var c := _confirm
	_confirm = {}
	match c.action:
		"restart": game.restart()
		"save": _save(c.slot)
		"load":
			var err: String = game.load_slot(c.slot)
			if err != "":
				_msg = err
				_msg_err = true
				_render()


func _save(n: int) -> void:
	var err: String = game.save_slot(n)
	_msg = err if err != "" else "Saved to slot %d." % n
	_msg_err = err != ""
	_slots = game.read_slots()
	_render()


static func _played(tick: int) -> String:
	var m := tick / Tuning.TPS / 60
	if m < 1:
		return "Under a minute played"
	return "1 minute played" if m == 1 else "%d minutes played" % m


static func _when(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().bias) * 60)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var hour: int = d.hour % 12
	return "%s %d, %d:%02d %s" % [months[d.month - 1], d.day, 12 if hour == 0 else hour, d.minute, "PM" if d.hour >= 12 else "AM"]
