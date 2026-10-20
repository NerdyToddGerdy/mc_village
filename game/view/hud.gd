class_name Hud
extends CanvasLayer
## The slate-board HUD (slice-1-spec.md §12): tallies and goals top left, speed and the stuck list
## top right, toasts in the gap between them, the selection panel bottom left, orders bottom right.
## Panels rebuild only when their content changes, so clicks aren't lost to a rebuild.

var game  ## The Game node; the HUD calls its command methods.

var _theme := Theme.new()
var _font: FontFile
var _bold: FontVariation
var _root := Control.new()
var _tallies := HBoxContainer.new()
var _tools_btn: Button
var _tools_drop: PanelContainer
var _tally_panel: PanelContainer
var _goals_panel: PanelContainer
var _tools_list := VBoxContainer.new()
var _tools_pinned := false
var _pointer := Vector2(-1, -1)
var _goals := VBoxContainer.new()
var _speed_btns := {}
var _stuck_panel: PanelContainer
var _stuck := VBoxContainer.new()
var _toasts := VBoxContainer.new()
var _sel_panel: PanelContainer
var _sel := VBoxContainer.new()
var _build_menu: PanelContainer
var _craft_panel: PanelContainer
var _craft_box := VBoxContainer.new()
var _tool_btns := {}
var _build_items := {}
var _keys_sig := ""
var _hint := Label.new()
var _paused_label: PanelContainer
var _sigs := {}
var _held := false            ## A mouse button is down; panels wait to rebuild until it's released.
var _toast_list: Array = []
var equip_kind := ""          ## "axe" or "pick" while the resident panel lists tools to equip, else "".


func _ready() -> void:
	_make_theme()
	_root.theme = _theme
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var tl := _corner(Control.PRESET_TOP_LEFT)
	var tally_row := HBoxContainer.new()
	tally_row.add_theme_constant_override("separation", 18)
	_tallies.add_theme_constant_override("separation", 18)
	tally_row.add_child(_tallies)
	_tools_btn = _button("Tools  0  ▾", func(): _tools_pinned = not _tools_pinned)
	_tools_btn.toggle_mode = true
	_tools_btn.custom_minimum_size = Vector2(0, 36)
	tally_row.add_child(_tools_btn)
	_tally_panel = _panel(tally_row, Vector2(0, 0))
	tl.add_child(_tally_panel)
	_tools_list.add_theme_constant_override("separation", 10)
	_tools_drop = _panel(_tools_list, Vector2(290, 0))
	_tools_drop.visible = false
	_tools_drop.top_level = true
	_goals_panel = _panel(_goals, Vector2(290, 0))
	tl.add_child(_goals_panel)

	var tr := _corner(Control.PRESET_TOP_RIGHT)
	var speed := HBoxContainer.new()
	speed.add_theme_constant_override("separation", 2)
	for v in [0, 1, 2, 3]:
		var b := _button("‖" if v == 0 else "%d×" % v, func(): game.set_speed(v))
		b.custom_minimum_size = Vector2(44, 44)
		b.toggle_mode = true
		_speed_btns[v] = b
		speed.add_child(b)
	tr.add_child(_panel(speed, Vector2.ZERO, 4))
	_stuck_panel = _panel(_stuck, Vector2(250, 0))
	tr.add_child(_stuck_panel)

	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)
	_paused_label = _panel(_label("Paused. You can still give orders.", true), Vector2.ZERO)
	_paused_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toasts.add_child(_paused_label)

	var bl := _corner(Control.PRESET_BOTTOM_LEFT)
	_sel_panel = _panel(_sel, Vector2(330, 0))
	_sel.add_theme_constant_override("separation", 8)
	bl.add_child(_sel_panel)

	var br := _corner(Control.PRESET_BOTTOM_RIGHT)
	var bm := VBoxContainer.new()
	_build_items.bench = _menu_item("Crafting bench", "4 logs", "", func(): game.start_placing("bench"))
	_build_items.house = _menu_item("House", "8 cobblestone, then 16 planks and 4 logs, then 12 planks", "", func(): game.start_placing("house"))
	_build_items.fireplace = _menu_item("Fireplace", "6 cobblestone", "", func(): game.start_placing("fireplace"))
	bm.add_child(_build_items.bench)
	bm.add_child(_build_items.house)
	bm.add_child(_build_items.fireplace)
	_build_menu = _panel(bm, Vector2(260, 0), 6)
	br.add_child(_build_menu)
	_craft_box.add_theme_constant_override("separation", 4)
	_craft_panel = _panel(_craft_box, Vector2(340, 0))
	_craft_panel.visible = false
	br.add_child(_craft_panel)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 2)
	for t in [["mine", "Mine", "X", Palette.RED], ["hunt", "Hunt", "G", Palette.RED], ["stock", "Stockpile", "Z", Palette.GREEN], ["farm", "Farm", "P", Palette.YELLOW], ["build", "Build", "B", Palette.BLUE], ["craft", "Craft", "C", Palette.PLANK]]:
		var b := _button(t[1], func(): game.set_tool(t[0]))
		b.custom_minimum_size = Vector2(96, 52)
		b.toggle_mode = true
		b.add_theme_color_override("font_color", t[3])
		b.add_theme_color_override("font_hover_color", t[3])
		b.add_theme_color_override("font_pressed_color", t[3])
		_tool_btns[t[0]] = b
		tools.add_child(b)
	br.add_child(_panel(tools, Vector2.ZERO, 4))

	_root.add_child(_tools_drop)
	_hint.visible = false
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := _box(Color(Palette.SLATE, 0.96), 4, 8)
	_hint.add_theme_stylebox_override("normal", hs)
	_root.add_child(_hint)


# ---------------------------------------------------------------- shared builders (also used by the menu)

func label(text: String, bold := false, color := Palette.CHALK, size := 15, wrap := false) -> Label:
	return _label(text, bold, color, size, wrap)


func button(text: String, on_press: Callable) -> Button:
	return _button(text, on_press)


func box(bg: Color, radius: int, margin: int, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	return _box(bg, radius, margin, border)


func add_overlay(c: Control) -> void:
	_root.add_child(c)


# ---------------------------------------------------------------- theme and builders

func _make_theme() -> void:
	_font = load("res://assets/fonts/BricolageGrotesque.ttf")
	var ts := TextServerManager.get_primary_interface()
	_bold = FontVariation.new()
	_bold.base_font = _font
	_bold.variation_opentype = {ts.name_to_tag("wght"): 720, ts.name_to_tag("wdth"): 80}
	_theme.default_font = _font
	_theme.default_font_size = 15
	_theme.set_color("font_color", "Label", Palette.CHALK)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_theme.set_color(state, "Button", Palette.CHALK)
	_theme.set_color("font_disabled_color", "Button", Palette.CHALK_DIM)
	_theme.set_stylebox("panel", "PanelContainer", _box(Palette.SLATE, 8, 12, Palette.SLATE_DEEP))
	_theme.set_stylebox("normal", "Button", _box(Color(0, 0, 0, 0), 4, 8))
	_theme.set_stylebox("hover", "Button", _box(Palette.SLATE_DEEP, 4, 8))
	_theme.set_stylebox("pressed", "Button", _box(Palette.SLATE_DEEP, 4, 8, Palette.CHALK))
	_theme.set_stylebox("hover_pressed", "Button", _box(Palette.SLATE_DEEP, 4, 8, Palette.CHALK))
	_theme.set_stylebox("disabled", "Button", _box(Color(0, 0, 0, 0), 4, 8))
	var focus := _box(Color(0, 0, 0, 0), 4, 8, Palette.CHALK)
	focus.set_border_width_all(2)
	_theme.set_stylebox("focus", "Button", focus)
	var tip := _box(Palette.SLATE, 4, 8, Palette.SLATE_DEEP)
	_theme.set_stylebox("panel", "TooltipPanel", tip)
	_theme.set_color("font_color", "TooltipLabel", Palette.CHALK)


func _box(bg: Color, radius: int, margin: int, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	if border.a > 0:
		s.border_color = border
		s.set_border_width_all(1)
	return s


func _corner(preset: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(v)
	v.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 16)
	if preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT]:
		v.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		v.child_entered_tree.connect(func(ch): if ch is Control: ch.size_flags_horizontal = Control.SIZE_SHRINK_END)
	else:
		v.child_entered_tree.connect(func(ch): if ch is Control: ch.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN)
	if preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]:
		v.grow_vertical = Control.GROW_DIRECTION_BEGIN
		v.alignment = BoxContainer.ALIGNMENT_END
	return v


func _panel(content: Control, min_size: Vector2, margin := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	if margin != 12:
		p.add_theme_stylebox_override("panel", _box(Palette.SLATE, 8, margin, Palette.SLATE_DEEP))
	p.add_child(content)
	return p


func _label(text: String, bold := false, color := Palette.CHALK, size := 15, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if bold:
		l.add_theme_font_override("font", _bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_press)
	return b


## Toolbar badges, build-menu keys and tooltips, from the current key bindings (issue #8).
func _refresh_key_labels() -> void:
	var k: KeyBindings = game.keys
	var sig := "%s" % [k.keys]
	if sig == _keys_sig:
		return
	_keys_sig = sig
	var names := {"mine": "Mine", "hunt": "Hunt", "stock": "Stockpile", "farm": "Farm", "build": "Build", "craft": "Craft"}
	var tips := {"mine": "Mine trees and boulders. Drag to mark many. Boulders need a pickaxe.",
		"hunt": "Hunt sheep for wool and mutton. Click or drag over them.",
		"craft": "Queue crafts at the bench or the fireplace",
		"farm": "Paint a farm plot over open grass. Residents plant and harvest wheat.",
		"stock": "Paint a stockpile. Drag over open ground.", "build": "Build"}
	for t in _tool_btns:
		var key := k.first(t)
		_tool_btns[t].text = "%s  %s" % [names[t], key] if key != "" else names[t]
		_tool_btns[t].tooltip_text = tips[t] + (" (%s)" % key if key != "" else "")
	var subs := {"bench": "4 logs. Reserves room for a workshop", "house": "8 cobblestone, then 16 planks and 4 logs, then 12 planks, then a bed",
		"fireplace": "6 cobblestone. Reserves room for a kitchen"}
	var titles := {"bench": "Crafting bench", "house": "House", "fireplace": "Fireplace"}
	for b in _build_items:
		_build_items[b].text = "%s   %s\n%s" % [titles[b], k.first(b), subs[b]]
	var speed_actions := {0: "pause", 1: "speed1", 2: "speed2", 3: "speed3"}
	for v in _speed_btns:
		var keytext := k.text(speed_actions[v]).replace("  ", " or ")
		_speed_btns[v].tooltip_text = ("Pause" if v == 0 else "Speed %d×" % v) + (" (%s)" % keytext if keytext != "No key" else "")


func _menu_item(title: String, sub: String, key: String, on_press: Callable) -> Button:
	var b := _button("%s   %s\n%s" % [title, key, sub], on_press)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(240, 52)
	return b


## The selection panel's content width at its narrowest (330 wide less its margins).
const HEAD_FIT := 306.0


## A panel's title with its status on the right. When the two won't fit side by side, the status
## moves to its own dimmed line below the title, so they never run together (issue #72).
func _head(title: String, status: String, bold := false, size := 15) -> Control:
	var t := _label(title, bold, Palette.CHALK, size)
	var title_w := (_bold if bold else _font).get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var status_w := _font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	if title_w + 16 + status_w <= HEAD_FIT:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		h.add_child(_label(status))
		return h
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(t)
	v.add_child(_label(status, false, Palette.CHALK_DIM, 15, true))
	return v


func _row(left: String, right: String, left_dim := true) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := _label(left, false, Palette.CHALK_DIM if left_dim else Palette.CHALK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(l)
	var r := _label(right)
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(r)
	return h


func _bar(frac: float, color := Palette.BLUE) -> Control:
	var bg := Panel.new()
	bg.custom_minimum_size = Vector2(0, 6)
	bg.add_theme_stylebox_override("panel", _box(Palette.SLATE_DEEP, 3, 0))
	var fill := Panel.new()
	fill.add_theme_stylebox_override("panel", _box(color, 3, 0))
	fill.anchor_right = clampf(frac, 0.0, 1.0)
	fill.anchor_bottom = 1.0
	bg.add_child(fill)
	return bg


func _reason(text: String) -> Label:
	return _label("⚑  " + text, true, Palette.YELLOW, 15, true)


## Replaces a container's children only when `sig` differs from last time.
func _rebuild(c: Container, sig: String, fill: Callable) -> void:
	if _sigs.get(c.get_instance_id(), "") == sig:
		return
	# Rebuilding between a button's press and release would swallow the click (the press lands on
	# the old button, the release on nothing), so a panel under a held button waits for the release.
	if _held and c.is_visible_in_tree() and c.get_global_rect().has_point(_pointer):
		return
	_sigs[c.get_instance_id()] = sig
	for ch in c.get_children():
		ch.queue_free()
	fill.call(c)


# ---------------------------------------------------------------- per-frame refresh

func refresh(sim: Sim) -> void:
	_refresh_key_labels()
	_refresh_tallies(sim)
	_refresh_goals(sim)
	for v in _speed_btns:
		_speed_btns[v].set_pressed_no_signal(game.speed == v)
	_paused_label.visible = game.speed == 0
	_refresh_stuck(sim)
	_refresh_selection(sim)
	for t in _tool_btns:
		var on: bool
		match t:
			"build": on = game.build_menu_open or game.tool == "build"
			"craft": on = game.craft_menu_open
			_: on = game.tool == t
		_tool_btns[t].set_pressed_no_signal(on)
	_build_menu.visible = game.build_menu_open
	_refresh_craft(sim)
	_refresh_toasts()


func _refresh_tallies(sim: Sim) -> void:
	var totals := {}
	var loose := {}
	var tools := 0
	for k in sim.items:
		var s: Dictionary = sim.items[k]
		if Defs.is_tool_item(s.type):
			tools += s.n
			continue
		totals[s.type] = totals.get(s.type, 0) + s.n
		if not sim.in_zone(s.cell):
			loose[s.type] = loose.get(s.type, 0) + s.n
	for r in sim.residents:
		tools += int(r.axe != null) + int(r.pick != null)
	_rebuild(_tallies, "%s%s%d" % [totals, loose, tools], func(c: Container) -> void:
		for t in Defs.MATERIALS:
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 0)
			var h := HBoxContainer.new()
			h.add_child(_label(Defs.ITEMS[t].label, false, Palette.CHALK_DIM, 14))
			h.add_child(_label(str(totals.get(t, 0)), true, Palette.CHALK, 18))
			v.add_child(h)
			if loose.get(t, 0) > 0:
				v.add_child(_label("%d loose" % loose[t], false, Palette.CHALK_DIM, 12))
			c.add_child(v))
	_tools_btn.text = "Tools  %d  ▾" % tools
	_refresh_tools(sim)


## The Tools dropdown (spec §12): each resident's tools with uses left, broken tools, and spares.
func _refresh_tools(sim: Sim) -> void:
	var sig := ""
	for r in sim.residents:
		sig += "%s%s%s%s;" % [r.name, r.axe, r.pick, r.broken]
	var spare: Array = sim.stacks_where(func(st): return Defs.is_tool_item(st.type))
	for st in spare:
		sig += "%s%s%s" % [st.type, st.get("dur", -1), sim.in_zone(st.cell)]
	_rebuild(_tools_list, sig, func(c: Container) -> void:
		for r in sim.residents:
			var g := VBoxContainer.new()
			g.add_theme_constant_override("separation", 6)
			g.add_child(_label(r.name, true))
			var any := false
			for k in ["axe", "pick"]:
				if r[k] != null:
					any = true
					g.add_child(_tool_row(r[k].type, r[k].dur))
				elif r.broken[k]:
					any = true
					g.add_child(_reason("Axe broke" if k == "axe" else "Pickaxe broke"))
			if not any:
				g.add_child(_label("Bare hands", false, Palette.CHALK_DIM, 14))
			c.add_child(g)
		if not spare.is_empty():
			var g := VBoxContainer.new()
			g.add_theme_constant_override("separation", 6)
			g.add_child(_label("Spare", true))
			var stored := spare.filter(func(st): return sim.in_zone(st.cell)).size()
			var loose := spare.size() - stored
			var where: PackedStringArray = []
			if stored:
				where.append("%d in the stockpile" % stored)
			if loose:
				where.append("%d lying loose" % loose)
			g.add_child(_label(", ".join(where), false, Palette.CHALK_DIM, 13))
			for st in spare:
				g.add_child(_tool_row(st.type, st.get("dur", Sim.full_uses(st.type))))
			c.add_child(g)
		c.add_child(_label("Craft tools at the bench. Residents pick up a better tool when a job needs one.", false, Palette.CHALK_DIM, 13, true)))


func _tool_row(type: String, dur: int) -> VBoxContainer:
	var most: int = Tuning.DURABILITY[Defs.ITEMS[type].tier]
	var low := dur <= 3
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	var name: String = Defs.ITEMS[type].one
	var row := _row(name.left(1).to_upper() + name.substr(1), "%d / %d uses" % [dur, most], false)
	if low:
		(row.get_child(1) as Label).add_theme_color_override("font_color", Palette.YELLOW)
	v.add_child(row)
	v.add_child(_bar(float(dur) / most, Palette.YELLOW if low else Palette.CHALK))
	return v


## Opens the Tools dropdown while the pointer is over the button or the list, while the button
## has keyboard focus, or while it's pinned open by a click or tap.
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer = event.position
	if event is InputEventMouseButton:
		_held = event.pressed


func _process(_delta: float) -> void:
	if _tools_btn == null:
		return
	_place_toasts()
	var mouse := _pointer
	var btn_rect := _tools_btn.get_global_rect().grow(4)
	var open := _tools_pinned or _tools_btn.has_focus() or btn_rect.has_point(mouse)
	if _tools_drop.visible and not open:
		open = btn_rect.merge(_tools_drop.get_global_rect().grow(8)).has_point(mouse)
	_tools_drop.visible = open
	if open:
		var panel := _tools_btn.get_parent().get_parent() as Control
		_tools_drop.position = Vector2(_tools_btn.global_position.x - 12, panel.get_global_rect().end.y + 6)
	_tools_btn.set_pressed_no_signal(_tools_pinned)


func _refresh_goals(sim: Sim) -> void:
	var cur := Goals.current(sim)
	var done_sig := ""
	for i in Goals.LIST.size():
		done_sig += "1" if Goals.done(sim, i) else "0"
	_rebuild(_goals, "%d%s" % [cur, done_sig], func(c: Container) -> void:
		var n_done := done_sig.count("1")
		c.add_child(_row("The founding", "%d of %d" % [n_done, Goals.LIST.size()], false))
		if cur < 0:
			c.add_child(_label("Slice 1 complete. The village has its first two residents.", false, Palette.GREEN, 14, true))
			return
		c.add_child(_label("%d  %s" % [cur + 1, Goals.LIST[cur].t], true, Palette.CHALK, 15, true))
		c.add_child(_label(Goals.LIST[cur].h, false, Palette.CHALK_DIM, 13, true)))


func _refresh_stuck(sim: Sim) -> void:
	var vis := sim.stuck.filter(func(s): return not s.hidden)
	_stuck_panel.visible = not vis.is_empty()
	var sig := ""
	for s in vis:
		sig += s.who + s.why + ";"
	_rebuild(_stuck, sig, func(c: Container) -> void:
		c.add_child(_label("Stuck (%d)" % vis.size(), true, Palette.YELLOW, 17))
		for s in vis:
			var b := _button("⚑  %s\n     %s" % [s.who, s.why], func(): game.focus_on(s.focus_kind, s.focus_id))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(0, 44)
			c.add_child(b))


func _refresh_toasts() -> void:
	var now := Time.get_ticks_msec()
	_toast_list = _toast_list.filter(func(t): return t.until > now)
	for ch in _toasts.get_children():
		if ch != _paused_label and not _toast_list.any(func(t): return t.node == ch):
			ch.queue_free()


## Toasts sit below the tally bar, centred in the gap between the goals panel and the stuck list,
## so they never cover either (issue #71). A toast too wide for the gap wraps.
func _place_toasts() -> void:
	var view := _root.size
	var left := 16.0
	if _goals_panel.visible:
		left = _goals_panel.get_global_rect().end.x + 12
	var right := view.x - 16
	if _stuck_panel.visible:
		right = _stuck_panel.get_global_rect().position.x - 12
	var width := maxf(right - left, 240.0)
	_toasts.position = Vector2(left, _tally_panel.get_global_rect().end.y + 8)
	_toasts.size = Vector2(width, 0)
	for p in _toasts.get_children():
		var lab := p.get_child(0) as Label if p.get_child(0) is Label else p.get_child(0).get_child(0) as Label
		var rest := 28.0  # the panel's margins
		if p.get_child(0) is HBoxContainer and p.get_child(0).get_child_count() > 1:
			rest += 14 + p.get_child(0).get_child(1).get_combined_minimum_size().x
		var natural := lab.get_theme_font("font").get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lab.get_theme_font_size("font_size")).x
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size.x = minf(ceilf(natural) + 1, width - rest)


func add_toast(ev: Dictionary) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.add_child(_label(ev.text))
	if ev.res_id:
		h.add_child(_button("Go to them", func(): game.focus_on("res", ev.res_id)))
	elif ev.site_id:
		h.add_child(_button("Show", func(): game.focus_on("site", ev.site_id)))
	var p := _panel(h, Vector2.ZERO, 10)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toasts.add_child(p)
	_toast_list.append({"node": p, "until": Time.get_ticks_msec() + 7000})
	if _toast_list.size() > 3:
		_toast_list.pop_front().node.queue_free()


# ---------------------------------------------------------------- selection panel

func _refresh_selection(sim: Sim) -> void:
	var sel: Dictionary = game.selection
	var sig := "%s" % [sel]
	var target = game.selected_entity()
	if sel.get("kind", "") == "res":
		for id in sel.ids:
			var r := sim.resident(id)
			if not r.is_empty():
				sig += "%s%s%s%s%s%d%s%d" % [r.job.label if r.job != null else "Idle", r.axe, r.pick, r.carry, r.broken, int(r.progress * 10), r.orders, int(r.hunger / 5)] + "%s%s%s%s%d" % [r.jobs, r.kept, equip_kind, r.away, int(sim.back_in(r))]
		for kind in ["axe", "pick"]:  # Equip appears when there's a tool to choose
			for st in sim.tool_items(kind, 0):
				sig += "%s%s%s" % [st.type, st.dur, st.cell]
	elif target != null and target.kind == "meadow":
		sig += "%d %d" % [sim.meadow_sheep, int(sim.meadow_regrow)]
	elif target != null and target.kind == "crop":
		sig += "%d %d %d" % [Sim.crop_stage(target), int(target.grow / Tuning.WHEAT_GROW * 20.0), target.claim]
	elif target != null:
		sig += "%s" % [target]
	for s in sim.stuck:
		sig += s.why
	_rebuild(_sel, sig, func(c: Container) -> void: _fill_selection(c, sim, sel, target))


func _fill_selection(c: Container, sim: Sim, sel: Dictionary, target) -> void:
	if sel.is_empty():
		c.add_child(_label("Nothing selected", true, Palette.CHALK, 17))
		c.add_child(_label("Click Ada to select her. With Ada selected, right-click a tree to mine it, or use the orders toolbar to mark work for anyone. Press F to select a resident.", false, Palette.CHALK_DIM, 15, true))
		return
	if sel.kind == "res":
		var rs: Array = sel.ids.map(func(id): return sim.resident(id)).filter(func(r): return not r.is_empty())
		if rs.size() > 1:
			c.add_child(_label("%d residents" % rs.size(), true, Palette.CHALK, 24))
			for r in rs:
				c.add_child(_label("%s: %s" % [r.name, _status(sim, r)], false, Palette.CHALK_DIM))
			if rs.size() == 2:
				_add_meadow_button(c, sim, rs)
			return
		if rs.is_empty():
			return
		var r: Dictionary = rs[0]
		c.add_child(_head(r.name, _status(sim, r), true, 24))
		if r.progress >= 0:
			c.add_child(_bar(r.progress))
		if r.away:
			c.add_child(_label("Off the map at the sheep meadow. Away residents don’t work or get hungry.", false, Palette.CHALK_DIM, 14, true))
			c.add_child(_bar(1.0 - sim.back_in(r) / Tuning.MEADOW_TRIP, Palette.GREEN))
			return
		_add_tool_row(c, sim, r, "axe")
		_add_tool_row(c, sim, r, "pick")
		c.add_child(_row("Carrying", Defs.words(r.carry.type, r.carry.n) if r.carry != null else "Nothing"))
		var mood := "Starving" if r.hunger <= 0.0 else ("Hungry" if r.hunger < Tuning.HUNGRY_BELOW else ("Peckish" if r.hunger < Tuning.EAT_BELOW else "Fed"))
		c.add_child(_row("Food", mood))
		c.add_child(_bar(r.hunger / 100.0, Palette.YELLOW if r.hunger < Tuning.HUNGRY_BELOW else Palette.CHALK))
		for s in sim.stuck:
			if s.focus_kind == "res" and s.focus_id == r.id:
				c.add_child(_reason(s.why))
		if not r.orders.is_empty():
			c.add_child(_label("Queued orders", true))
			for i in r.orders.size():
				c.add_child(_label("%d  %s" % [i + 1, Sim.order_text(r.orders[i])], false, Palette.CHALK, 14))
			c.add_child(_button("Clear orders", func(): game.clear_orders(r)))
		if equip_kind != "":
			return  # the tool list takes the Jobs grid's room while it's open
		_add_meadow_button(c, sim, [r])
		if r.axe == null and not r.broken.axe:
			c.add_child(_label("Chopping by hand is slow. Stone needs a pickaxe.", false, Palette.CHALK_DIM, 15, true))
		_add_jobs_grid(c, r)
		return
	if target == null:
		c.add_child(_label("That’s gone.", false, Palette.CHALK_DIM))
		return
	match target.kind:
		"tree":
			c.add_child(_head("Tree", "Drops %d logs" % target.logs))
			c.add_child(_button("Cancel mining" if target.des else "Mine", func(): game.toggle_mine(target)))
		"bush":
			c.add_child(_head("Berry bush", "%d of %d berries" % [target.berries, Tuning.BUSH_MAX]))
			c.add_child(_label("A berry grows back every %d seconds. Hungry residents eat here." % int(Tuning.BUSH_REGROW), false, Palette.CHALK_DIM, 14, true))
		"meadow":
			c.add_child(_head("Sheep meadow", "%d of %d sheep" % [sim.meadow_sheep, Tuning.MEADOW_SHEEP]))
			var more := "" if sim.meadow_sheep >= Tuning.MEADOW_SHEEP else " The next one in %d seconds." % ceili(Tuning.MEADOW_REGROW - sim.meadow_regrow)
			c.add_child(_label("Off the map, past this signpost. The meadow regains a sheep every %d minutes.%s" % [int(Tuning.MEADOW_REGROW / 60.0), more], false, Palette.CHALK_DIM, 14, true))
			c.add_child(_label("Select one or two residents and choose Send to the meadow. Each brings back %d wool and %d raw mutton." % [Tuning.MEADOW_TAKE, Tuning.MEADOW_TAKE], false, Palette.CHALK_DIM, 14, true))
		"crop":
			var stage := Sim.crop_stage(target)
			var status := "Empty, waiting to be planted"
			if stage == 4:
				status = "Ripe wheat, waiting to be harvested"
			elif stage > 0:
				status = "Wheat growing, %d%%" % int(target.grow / Tuning.WHEAT_GROW * 100.0)
			c.add_child(_head("Farm plot", status))
			if stage > 0 and stage < 4:
				c.add_child(_bar(target.grow / Tuning.WHEAT_GROW, Palette.YELLOW))
			if target.claim != 0:
				var who: String = sim.resident(target.claim).get("name", "Someone")
				c.add_child(_label("%s is %s it." % [who, "harvesting" if stage == 4 else "planting"], false, Palette.CHALK_DIM))
			c.add_child(_label("Wheat takes %d minutes to grow and gives %d when harvested." % [int(Tuning.WHEAT_GROW / 60.0), Tuning.WHEAT_YIELD], false, Palette.CHALK_DIM, 14, true))
			c.add_child(_button("Remove this plot", func(): game.remove_farm_plot(target)))
		"sheep":
			c.add_child(_head("Sheep", "Drops 1 wool and 1 raw mutton"))
			if target.claim != 0:
				c.add_child(_label("%s is hunting it." % sim.resident(target.claim).get("name", "Someone"), false, Palette.CHALK_DIM))
			c.add_child(_button("Cancel hunt" if target.des else "Hunt", func(): game.toggle_hunt(target)))
		"boulder":
			c.add_child(_head("Boulder", "Drops %d cobblestone" % Tuning.BOULDER_COBBLE))
			if target.des and sim.stuck.any(func(s): return s.focus_kind == "boulder"):
				c.add_child(_reason("Needs a pickaxe"))
			c.add_child(_button("Cancel mining" if target.des else "Mine", func(): game.toggle_mine(target)))
		"site":
			_fill_site(c, sim, target)


## The Craft button appears once a bench is finished; it opens the bench panel above the toolbar
## (issue #57), with the same contents as selecting the bench.
func _refresh_craft(sim: Sim) -> void:
	var bench = game.craft_bench()
	_tool_btns.craft.visible = bench != null
	_craft_panel.visible = game.craft_menu_open and bench != null
	if not _craft_panel.visible:
		return
	var n: int = game.benches().size()
	var sig := "%d|%d|%s|%s|%s|%s" % [n, game.craft_bench_i, bench, sim.auto_craft, sim.free_count("log"), sim.stuck.map(func(x): return x.why)]
	_rebuild(_craft_box, sig, func(c: Container) -> void:
		if n > 1:
			var h := HBoxContainer.new()
			var l := _label("%d of %d" % [game.craft_bench_i % n + 1, n], false, Palette.CHALK_DIM, 14)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(l)
			h.add_child(_button("Next", func(): game.next_craft_bench()))
			c.add_child(h)
		_fill_bench(c, sim, bench))


## The Jobs grid (issue #47): each job's on/off switch and its priority, 1 first. Click a job's name
## to switch it, and its number to cycle the priority.
func _add_jobs_grid(c: Container, r: Dictionary) -> void:
	var title := _row("Jobs", "Priority 1 goes first", false)
	(title.get_child(0) as Label).add_theme_font_override("font", _bold)
	(title.get_child(1) as Label).add_theme_color_override("font_color", Palette.CHALK_DIM)
	(title.get_child(1) as Label).add_theme_font_size_override("font_size", 13)
	c.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	for jb in Defs.JOBS:
		var st: Dictionary = r.jobs[jb]
		var on := _button(Defs.JOB_NAMES[jb], func(): game.toggle_job(r, jb))
		on.toggle_mode = true
		on.set_pressed_no_signal(st.on)
		on.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		on.alignment = HORIZONTAL_ALIGNMENT_LEFT
		on.add_theme_font_size_override("font_size", 14)
		on.tooltip_text = "%s is %s. Click to switch it %s." % [Defs.JOB_NAMES[jb], "on" if st.on else "off", "off" if st.on else "on"]
		if not st.on:
			for k in ["font_color", "font_hover_color", "font_pressed_color"]:
				on.add_theme_color_override(k, Color(Palette.CHALK_DIM, 0.55))
		grid.add_child(on)
		grid.add_child(_level_cell(r, jb))
		var pri := _button(str(st.pri) if st.on else "–", func(): game.cycle_job_priority(r, jb))
		pri.custom_minimum_size = Vector2(30, 0)
		pri.disabled = not st.on
		pri.add_theme_font_size_override("font_size", 14)
		pri.tooltip_text = "Priority %d. Click to change it." % st.pri
		grid.add_child(pri)
	c.add_child(grid)


## A job's level, with a thin bar of progress to the next one (issue #48).
func _level_cell(r: Dictionary, jb: String) -> Control:
	var lv := Sim.level(r, jb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.custom_minimum_size = Vector2(30, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := _label("Lv %d" % lv, lv >= Tuning.ARRIVAL_LEVEL, Palette.CHALK if lv > 1 else Palette.CHALK_DIM, 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	var bar := _bar(Sim.level_progress(r, jb), Palette.GREEN)
	bar.custom_minimum_size = Vector2(28, 3)
	box.add_child(bar)
	var xp: int = r.jobs[jb].get("xp", 0)
	if lv > Tuning.SKILL_LEVELS.size():
		box.tooltip_text = "Level %d at %s, the top level." % [lv, Defs.JOB_NAMES[jb]]
	else:
		box.tooltip_text = "Level %d at %s: %d of %d points to level %d. Each level works %d%% faster." % [lv, Defs.JOB_NAMES[jb], xp, Tuning.SKILL_LEVELS[lv - 1], lv + 1, roundi(Tuning.SKILL_SPEED * 100)]
	return box


## A resident's axe or pickaxe, with Equip to choose another one (lying about or stockpiled).
func _add_tool_row(c: Container, sim: Sim, r: Dictionary, kind: String) -> void:
	var t = r[kind]
	var none := "Bare hands" if kind == "axe" else "None"
	var text: String = _tool_text(t) if t != null else ("Broke" if r.broken[kind] else none)
	var h := _row("Axe" if kind == "axe" else "Pickaxe", text)
	var spare := sim.tool_items(kind, 0)
	if not spare.is_empty() or equip_kind == kind:
		var b := _button("Close" if equip_kind == kind else "Equip", func(): equip_kind = "" if equip_kind == kind else kind)
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = "Choose which %s %s uses" % ["axe" if kind == "axe" else "pickaxe", r.name]
		h.add_child(b)
	c.add_child(h)
	if t != null and r.kept[kind]:
		var k := HBoxContainer.new()
		var l := _label("Kept until it breaks.", false, Palette.CHALK_DIM, 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_child(l)
		var auto := _button("Use the best", func(): game.release_kept_tool(r, kind))
		auto.add_theme_font_size_override("font_size", 13)
		auto.tooltip_text = "Let %s swap it for a better one when there is one" % r.name
		k.add_child(auto)
		c.add_child(k)
	if equip_kind != kind:
		return
	if spare.is_empty():
		c.add_child(_label("No other %s is lying about or stockpiled." % ("axe" if kind == "axe" else "pickaxe"), false, Palette.CHALK_DIM, 13, true))
		return
	spare.sort_custom(func(a, b): return Defs.ITEMS[a.type].tier > Defs.ITEMS[b.type].tier or (a.type == b.type and a.dur > b.dur))
	for st in spare:
		var where := "in the stockpile" if sim.in_zone(st.cell) else "on the ground"
		var it: Dictionary = Defs.ITEMS[st.type]
		var b := _button("%s, %d %s left, %s" % [it.one.substr(0, 1).to_upper() + it.one.substr(1), st.dur, "use" if st.dur == 1 else "uses", where], func():
			equip_kind = ""
			game.equip_tool(r, st))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		c.add_child(b)


## What a resident is doing, for panel headings.
func _status(sim: Sim, r: Dictionary) -> String:
	if r.away:
		return "At the meadow, back in %d s" % ceili(sim.back_in(r))
	return r.job.label if r.job != null else "Idle"


## Send to the meadow (issue #50), for one or two selected residents who are here.
func _add_meadow_button(c: Container, sim: Sim, rs: Array) -> void:
	if rs.any(func(r): return r.away or r.arriving):
		return
	var text := "Send to the meadow" if rs.size() == 1 else "Send both to the meadow"
	var b := _button(text, func(): game.send_to_meadow(rs.map(func(r): return r.id)))
	b.tooltip_text = "Away %d seconds. Each brings back %d wool and %d raw mutton. The meadow has %d sheep." % [int(Tuning.MEADOW_TRIP), Tuning.MEADOW_TAKE, Tuning.MEADOW_TAKE, sim.meadow_sheep]
	c.add_child(b)
	if sim.meadow_sheep == 0:
		c.add_child(_reason("Meadow has no sheep left"))


func _tool_text(t: Dictionary) -> String:
	return "%s, %d %s left" % ["Stone" if t.tier == 2 else "Wooden", t.dur, "use" if t.dur == 1 else "uses"]


func _fill_site(c: Container, sim: Sim, s: Dictionary) -> void:
	var tpl: Dictionary = Defs.TEMPLATES[s.tpl]
	var reasons := sim.stuck.filter(func(x): return x.focus_kind == "site" and x.focus_id == s.id)
	if not s.done:
		var st := sim.current_stage(s)
		var stage_line: String = "Stage %d of %d: %s" % [s.stage + 1, tpl.stages.size(), st.name.to_lower()] if tpl.stages.size() > 1 else "Blueprint"
		c.add_child(_head(tpl.name, stage_line))
		if not sim.footprint_clear(s):
			c.add_child(_label("Clearing the ground first: %s." % Sim.clearing_text(sim.site_obstacles(s)), false, Palette.CHALK, 15, true))
		for k in st.cost:
			var have: int = s.store.get(k, 0)
			c.add_child(_row(Defs.ITEMS[k].label, "%d / %d" % [have, st.cost[k]], false))
			c.add_child(_bar(float(have) / st.cost[k]))
		for x in reasons:
			c.add_child(_reason(x.why))
		if s.builder:
			c.add_child(_label("%s is building." % sim.resident(s.builder).name, false, Palette.CHALK_DIM))
		if s.stage + 1 < tpl.stages.size():
			var nxt: Dictionary = tpl.stages[s.stage + 1]
			c.add_child(_label("%s next: %s." % [nxt.name, Defs.cost_text(nxt.cost)], false, Palette.CHALK_DIM, 15, true))
		c.add_child(_button("Cancel blueprint", func(): game.cancel_site(s)))
		return
	if s.tpl == "house":
		var owner := sim.resident(s.owner)
		var line := "Home of %s." % owner.name if not owner.is_empty() else ("Empty. A traveler should arrive soon." if sim.arrival_at >= 0 else "Empty.")
		c.add_child(_label("House", true, Palette.CHALK, 24))
		c.add_child(_label(line, false, Palette.CHALK_DIM, 15, true))
		return
	# A finished bench or fireplace: a short summary here. Its recipes and queue live only in the
	# Craft panel on the right, which selecting it opens.
	c.add_child(_label(tpl.name, true, Palette.CHALK, 24))
	c.add_child(_label(_bench_status(sim, s), false, Palette.CHALK_DIM, 15, true))
	for x in reasons:
		c.add_child(_reason(x.why))
	if not game.craft_menu_open:
		c.add_child(_button("Open the craft menu", func(): game.open_craft_menu(s)))


## What a finished bench or fireplace is doing, for its panels.
func _bench_status(sim: Sim, s: Dictionary) -> String:
	var ready := sim.bench_craftable(s)
	var ai := sim.bench_active(s)
	if s.crafting != "":
		var rec := {}
		for r in Defs.RECIPES:
			if r.name == s.crafting:
				rec = r
		return rec.get("doing", "Crafting " + s.crafting.to_lower())
	if not ready.is_empty():
		return "Ready to make " + ready.name.to_lower()
	if s.queue.is_empty():
		return "Nothing queued"
	var head := Defs.recipe(s.queue[maxi(ai, 0)])
	var missing: PackedStringArray = []
	for k in head.inp:
		var have: int = s.store.get(k, 0)
		if have < head.inp[k]:
			missing.append(Defs.words(k, head.inp[k] - have))
	return "%s %s for %s" % ["Gathering" if ai >= 0 else "Waiting for", ", ".join(missing), head.name.to_lower()]


## The full bench panel: recipes with Queue and Queue 5, then status, reasons and the queue. Shown
## only in the Craft panel above the toolbar (issue #57).
func _fill_bench(c: Container, sim: Sim, s: Dictionary) -> void:
	var reasons := sim.stuck.filter(func(x): return x.focus_kind == "site" and x.focus_id == s.id)
	var status := _bench_status(sim, s)
	# The title and recipe rows come first and never change size, so the Queue buttons stay put while
	# the status, reasons and queue below them change (issue #57: buttons used to jump mid-click).
	c.add_child(_label(Defs.TEMPLATES[s.tpl].name, true, Palette.CHALK, 24))
	for rec in Defs.recipes_at(s.tpl):
		var h := HBoxContainer.new()
		var l := _label("%s\n%s → %s" % [rec.name, Defs.cost_text(rec.inp), Defs.cost_text(rec.out)], false, Palette.CHALK, 13)
		l.add_theme_constant_override("line_spacing", -2)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(_button("Queue", func(): game.queue_craft(s, rec.id)))
		h.add_child(_button("Queue 5", func(): game.queue_craft(s, rec.id, 5)))
		c.add_child(h)
	var lower := VBoxContainer.new()
	lower.add_theme_constant_override("separation", 6)
	lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(_label(status, false, Palette.CHALK_DIM, 15, true))
	for x in reasons:
		lower.add_child(_reason(x.why))
	if not s.queue.is_empty():
		lower.add_child(_label("Queue. Items that can’t be made yet are skipped. Click one to remove it.", false, Palette.CHALK_DIM, 13, true))
		var flow := HFlowContainer.new()
		for i in s.queue.size():
			var mark := ""
			if str(s.autoq[i]) == "toolsmith":
				mark = " (toolsmith)"
			elif s.autoq[i]:
				mark = " (auto)"
			flow.add_child(_button("%s%s ×" % [Defs.recipe(s.queue[i]).name, mark], func(): game.unqueue_craft(s, i)))
		lower.add_child(flow)
	if s.tpl == "fireplace":
		var on: bool = s.get("keep_meals", true)
		var keep := _button("Keep %d meals in stock: %s" % [Tuning.MEAL_STOCK, "on" if on else "off"], func(): game.set_keep_meals(s, not on))
		keep.toggle_mode = true
		keep.set_pressed_no_signal(on)
		lower.add_child(keep)
		lower.add_child(_label("While stored bread and cooked mutton are fewer than %d, cooks make whichever the wheat, mutton and logs allow." % Tuning.MEAL_STOCK, false, Palette.CHALK_DIM, 13, true))
	else:
		lower.add_child(_label("Missing planks and sticks are queued automatically." if sim.auto_craft else "Once Ada’s house is finished, the bench queues the planks and sticks a recipe needs.", false, Palette.CHALK_DIM, 13, true))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 96)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(lower)
	c.add_child(scroll)


# ---------------------------------------------------------------- cursor hint

func show_hint(text: String, at: Vector2, color := Palette.CHALK) -> void:
	_hint.visible = text != ""
	if text == "":
		return
	_hint.text = text
	_hint.add_theme_color_override("font_color", color)
	_hint.position = at + Vector2(18, 14)
	_hint.size = Vector2.ZERO
