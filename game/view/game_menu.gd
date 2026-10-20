class_name GameMenu
extends Control
## The main menu (slice-1-spec.md §2, Main menu): Play/Resume, Save game and Load game with
## 5 slots, Controls, and Start over. Overwriting, loading and starting over ask for confirmation
## here on the page. The game pauses while the menu is open.

## Mouse controls and Esc, which can't be rebound; shown alongside the rebindable keys.
const FIXED_ROWS := {
	"Orders": [["Shift-drag", "With Mine: trees only"], ["Alt-drag", "With Mine: boulders only (Option on a Mac)"],
		["Esc", "Cancel the current order"]],
	"Residents": [["Click", "Select a resident, tree, boulder or building"], ["Shift-drag", "Select several residents"],
		["Right-click", "Order the selected residents"], ["Shift + right-click", "Queue an order after their current one"]],
	"Time and camera": [["Drag", "Pan the map (middle-drag too)"], ["Wheel", "Zoom (pinch too)"]],
	"Game": [["Esc", "Open the menu"]],
}

var game   ## The Game node.
var hud: Hud
var view := "main"
var first := true          ## Before the first Play, the main button says Play.
var _confirm := {}         ## {text, yes, action, slot}
var _msg := ""
var _msg_err := false
var _slots: Array = []
var _box := VBoxContainer.new()
var listening := ""       ## Action waiting for its new key on the Controls page.


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
	listening = ""
	_confirm = {}
	_msg = ""
	if v == "save" or v == "load":
		_slots = game.read_slots()
	visible = true
	_render()


func back() -> void:
	if listening != "":
		listening = ""
		_render()
	elif not _confirm.is_empty():
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
	var k: KeyBindings = game.keys
	_title("Controls", "Change any key. Esc and the mouse can't be changed.")
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	var groups: Array = []
	for a in KeyBindings.ACTIONS:
		if not groups.has(a[1]):
			groups.append(a[1])
	for g in groups:
		list.add_child(hud.label(g, true, Palette.CHALK, 16))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		for a in KeyBindings.ACTIONS:
			if a[1] != g:
				continue
			var waiting: bool = listening == a[0]
			var key_label := hud.label("Press a key…" if waiting else k.text(a[0]), true, Palette.YELLOW if waiting or k.keys[a[0]].is_empty() else Palette.CHALK, 14)
			key_label.custom_minimum_size = Vector2(110, 0)
			grid.add_child(key_label)
			var name := hud.label(a[2], false, Palette.CHALK, 14)
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(name)
			var change := hud.button("Cancel" if waiting else "Change", func(): _listen(a[0]), "Secondary")
			change.custom_minimum_size = Vector2(80, 30)
			grid.add_child(change)
		for row in FIXED_ROWS.get(g, []):
			grid.add_child(hud.label(row[0], true, Palette.CHALK_DIM, 14))
			grid.add_child(hud.label(row[1], false, Palette.CHALK_DIM, 14))
			grid.add_child(Control.new())
		list.add_child(grid)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, mini(460, int(get_viewport_rect().size.y) - 260))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(list)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(scroll)
	if listening != "":
		_box.add_child(hud.label("Press the new key for “%s”. Esc cancels." % KeyBindings.label_of(listening), false, Palette.YELLOW, 14, true))
	_add_confirm()
	if _msg != "":
		_box.add_child(hud.label(_msg, false, Palette.CHALK_DIM, 14, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_back_button())
	var reset := hud.button("Reset to defaults", _reset_keys, "Secondary")
	reset.add_theme_stylebox_override("normal", hud.box(Color(0, 0, 0, 0), 4, 10, Palette.CHALK_DIM))
	row.add_child(reset)
	_box.add_child(row)


func _listen(action: String) -> void:
	listening = "" if listening == action else action
	_confirm = {}
	_msg = ""
	_render()


## The next key pressed while waiting on the Controls page (Esc is handled as cancel by the game).
func key_pressed(e: InputEventKey) -> void:
	if e.keycode == KEY_ESCAPE:
		listening = ""
		_render()
		return
	if e.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return
	var k: KeyBindings = game.keys
	var action := listening
	var code := KeyBindings.event_code(e)
	listening = ""
	var other := k.used_by(code, action)
	if other != "":
		_confirm = {"text": "%s is already used for “%s”. Use it for “%s” instead? “%s” will be left without a key." % [KeyBindings.key_text(code), KeyBindings.label_of(other), KeyBindings.label_of(action), KeyBindings.label_of(other)],
			"yes": "Use %s" % KeyBindings.key_text(code), "action": "rebind", "slot": 0, "target": action, "code": code}
		_render()
		return
	_rebind(action, code)


func _rebind(action: String, code: int) -> void:
	game.keys.assign(action, code)
	game.keys.save_file()
	_msg = "“%s” is now %s." % [KeyBindings.label_of(action), KeyBindings.key_text(code)]
	_render()


func _reset_keys() -> void:
	game.keys.reset()
	game.keys.save_file()
	listening = ""
	_confirm = {}
	_msg = "Keys are back to their defaults."
	_render()


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
		var unreadable: bool = meta != null and meta.has("error")
		if meta == null:
			info.add_child(hud.label("Empty", false, Palette.CHALK_DIM, 14))
		elif unreadable:
			info.add_child(hud.label(meta.error, false, Palette.YELLOW, 14, true))
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
			b.disabled = meta == null or unreadable
		b.custom_minimum_size = Vector2(110, 40)
		b.theme_type_variation = "Primary"
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
	var b := hud.button("Back", func(): show_view("main"), "Secondary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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
	var cancel := hud.button("Cancel", func(): _confirm = {}; _render(), "Secondary")
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
		"rebind": _rebind(c.target, c.code)
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
