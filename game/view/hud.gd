class_name Hud
extends CanvasLayer
## The slate-board HUD (slice-1-spec.md §12): tallies and goals top left, speed and the stuck list
## top right, toasts top centre, the selection panel bottom left, orders bottom right.
## Panels rebuild only when their content changes, so clicks aren't lost to a rebuild.

var game  ## The Game node; the HUD calls its command methods.

var _theme := Theme.new()
var _font: FontFile
var _bold: FontVariation
var _root := Control.new()
var _tallies := HBoxContainer.new()
var _tools_btn: Button
var _tools_drop: PanelContainer
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
var _tool_btns := {}
var _hint := Label.new()
var _paused_label: PanelContainer
var _sigs := {}
var _toast_list: Array = []


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
	tl.add_child(_panel(tally_row, Vector2(0, 0)))
	_tools_list.add_theme_constant_override("separation", 10)
	_tools_drop = _panel(_tools_list, Vector2(290, 0))
	_tools_drop.visible = false
	_tools_drop.top_level = true
	tl.add_child(_panel(_goals, Vector2(290, 0)))

	var tr := _corner(Control.PRESET_TOP_RIGHT)
	var speed := HBoxContainer.new()
	speed.add_theme_constant_override("separation", 2)
	for v in [0, 1, 2, 3]:
		var b := _button("‖" if v == 0 else "%d×" % v, func(): game.set_speed(v))
		b.custom_minimum_size = Vector2(44, 44)
		b.tooltip_text = "Pause (~ or Space)" if v == 0 else "Speed %d× (%d)" % [v, v]
		b.toggle_mode = true
		_speed_btns[v] = b
		speed.add_child(b)
	tr.add_child(_panel(speed, Vector2.ZERO, 4))
	_stuck_panel = _panel(_stuck, Vector2(250, 0))
	tr.add_child(_stuck_panel)

	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_KEEP_SIZE, 16)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)
	_paused_label = _panel(_label("Paused. You can still give orders.", true), Vector2.ZERO)
	_toasts.add_child(_paused_label)

	var bl := _corner(Control.PRESET_BOTTOM_LEFT)
	_sel_panel = _panel(_sel, Vector2(330, 0))
	_sel.add_theme_constant_override("separation", 8)
	bl.add_child(_sel_panel)

	var br := _corner(Control.PRESET_BOTTOM_RIGHT)
	var bm := VBoxContainer.new()
	bm.add_child(_menu_item("Crafting bench", "4 logs", "T", func(): game.start_placing("bench")))
	bm.add_child(_menu_item("House", "8 cobblestone, then 16 planks and 4 logs, then 12 planks", "H", func(): game.start_placing("house")))
	_build_menu = _panel(bm, Vector2(260, 0), 6)
	br.add_child(_build_menu)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 2)
	for t in [["mine", "Mine", "X", Palette.RED], ["stock", "Stockpile", "Z", Palette.GREEN], ["build", "Build", "B", Palette.BLUE]]:
		var b := _button("%s  %s" % [t[1], t[2]], func(): game.set_tool(t[0]))
		b.custom_minimum_size = Vector2(96, 52)
		b.toggle_mode = true
		b.add_theme_color_override("font_color", t[3])
		b.add_theme_color_override("font_hover_color", t[3])
		b.add_theme_color_override("font_pressed_color", t[3])
		b.tooltip_text = {"mine": "Mine trees and boulders (X). Drag to mark many. Boulders need a pickaxe.",
			"stock": "Paint a stockpile (Z). Drag over open ground.", "build": "Build (B)"}[t[0]]
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


func _menu_item(title: String, sub: String, key: String, on_press: Callable) -> Button:
	var b := _button("%s   %s\n%s" % [title, key, sub], on_press)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(240, 52)
	return b


func _row(left: String, right: String, left_dim := true) -> HBoxContainer:
	var h := HBoxContainer.new()
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
	_sigs[c.get_instance_id()] = sig
	for ch in c.get_children():
		ch.queue_free()
	fill.call(c)


# ---------------------------------------------------------------- per-frame refresh

func refresh(sim: Sim) -> void:
	_refresh_tallies(sim)
	_refresh_goals(sim)
	for v in _speed_btns:
		_speed_btns[v].set_pressed_no_signal(game.speed == v)
	_paused_label.visible = game.speed == 0
	_refresh_stuck(sim)
	_refresh_selection(sim)
	for t in _tool_btns:
		var on: bool = game.build_menu_open or game.tool == "build" if t == "build" else game.tool == t
		_tool_btns[t].set_pressed_no_signal(on)
	_build_menu.visible = game.build_menu_open
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
		sig += "%s%s" % [st.type, sim.in_zone(st.cell)]
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
				g.add_child(_tool_row(st.type, Tuning.DURABILITY[Defs.ITEMS[st.type].tier]))
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


func _process(_delta: float) -> void:
	if _tools_btn == null:
		return
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


func add_toast(ev: Dictionary) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.add_child(_label(ev.text))
	if ev.res_id:
		h.add_child(_button("Go to them", func(): game.focus_on("res", ev.res_id)))
	elif ev.site_id:
		h.add_child(_button("Show", func(): game.focus_on("site", ev.site_id)))
	var p := _panel(h, Vector2.ZERO, 10)
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
				sig += "%s%s%s%s%s%d" % [r.job.label if r.job != null else "Idle", r.axe, r.pick, r.carry, r.broken, int(r.progress * 10)]
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
				c.add_child(_label("%s: %s" % [r.name, r.job.label if r.job != null else "Idle"], false, Palette.CHALK_DIM))
			return
		if rs.is_empty():
			return
		var r: Dictionary = rs[0]
		var head := _row(r.name, r.job.label if r.job != null else "Idle", false)
		(head.get_child(0) as Label).add_theme_font_override("font", _bold)
		(head.get_child(0) as Label).add_theme_font_size_override("font_size", 24)
		c.add_child(head)
		if r.progress >= 0:
			c.add_child(_bar(r.progress))
		c.add_child(_row("Axe", _tool_text(r.axe) if r.axe != null else ("Broke" if r.broken.axe else "Bare hands")))
		c.add_child(_row("Pickaxe", _tool_text(r.pick) if r.pick != null else ("Broke" if r.broken.pick else "None")))
		c.add_child(_row("Carrying", Defs.words(r.carry.type, r.carry.n) if r.carry != null else "Nothing"))
		for s in sim.stuck:
			if s.focus_kind == "res" and s.focus_id == r.id:
				c.add_child(_reason(s.why))
		if r.axe == null and not r.broken.axe:
			c.add_child(_label("Chopping by hand is slow. Stone needs a pickaxe.", false, Palette.CHALK_DIM, 15, true))
		return
	if target == null:
		c.add_child(_label("That’s gone.", false, Palette.CHALK_DIM))
		return
	match target.kind:
		"tree":
			c.add_child(_row("Tree", "Drops %d logs" % target.logs, false))
			c.add_child(_button("Cancel mining" if target.des else "Mine", func(): game.toggle_mine(target)))
		"boulder":
			c.add_child(_row("Boulder", "Drops %d cobblestone" % Tuning.BOULDER_COBBLE, false))
			if target.des and sim.stuck.any(func(s): return s.focus_kind == "boulder"):
				c.add_child(_reason("Needs a pickaxe"))
			c.add_child(_button("Cancel mining" if target.des else "Mine", func(): game.toggle_mine(target)))
		"site":
			_fill_site(c, sim, target)


func _tool_text(t: Dictionary) -> String:
	return "%s, %d %s left" % ["Stone" if t.tier == 2 else "Wooden", t.dur, "use" if t.dur == 1 else "uses"]


func _fill_site(c: Container, sim: Sim, s: Dictionary) -> void:
	var tpl: Dictionary = Defs.TEMPLATES[s.tpl]
	var reasons := sim.stuck.filter(func(x): return x.focus_kind == "site" and x.focus_id == s.id)
	if not s.done:
		var st := sim.current_stage(s)
		var stage_line: String = "Stage %d of %d: %s" % [s.stage + 1, tpl.stages.size(), st.name.to_lower()] if tpl.stages.size() > 1 else "Blueprint"
		c.add_child(_row(tpl.name, stage_line, false))
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
		var line := "Home of %s." % owner.name if not owner.is_empty() else ("Empty. A traveler should arrive soon." if sim.arrival_at >= 0 and not sim.arrived else "Empty.")
		c.add_child(_label("House", true, Palette.CHALK, 24))
		c.add_child(_label(line, false, Palette.CHALK_DIM, 15, true))
		return
	var ready := sim.bench_craftable(s)
	var ai := sim.bench_active(s)
	var status := "Nothing queued"
	if s.crafting != "":
		status = "Crafting " + s.crafting.to_lower()
	elif not ready.is_empty():
		status = "Ready to craft " + ready.name.to_lower()
	elif not s.queue.is_empty():
		var head := Defs.recipe(s.queue[maxi(ai, 0)])
		var missing: PackedStringArray = []
		for k in head.inp:
			var have: int = s.store.get(k, 0)
			if have < head.inp[k]:
				missing.append(Defs.words(k, head.inp[k] - have))
		status = "%s %s for %s" % ["Gathering" if ai >= 0 else "Waiting for", ", ".join(missing), head.name.to_lower()]
	c.add_child(_label("Crafting bench", true, Palette.CHALK, 24))
	c.add_child(_label(status, false, Palette.CHALK_DIM, 15, true))
	for x in reasons:
		c.add_child(_reason(x.why))
	for rec in Defs.RECIPES:
		var h := HBoxContainer.new()
		var l := _label("%s\n%s → %s" % [rec.name, Defs.cost_text(rec.inp), Defs.cost_text(rec.out)], false, Palette.CHALK, 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(_button("Queue", func(): game.queue_craft(s, rec.id)))
		c.add_child(h)
	if not s.queue.is_empty():
		c.add_child(_label("Queue. Items that can’t be made yet are skipped. Click one to remove it.", false, Palette.CHALK_DIM, 13, true))
		var flow := HFlowContainer.new()
		for i in s.queue.size():
			var auto: bool = s.autoq[i]
			flow.add_child(_button("%s%s ×" % [Defs.recipe(s.queue[i]).name, " (auto)" if auto else ""], func(): game.unqueue_craft(s, i)))
		c.add_child(flow)
	c.add_child(_label("Missing planks and sticks are queued automatically." if sim.auto_craft else "Once Ada’s house is finished, the bench queues the planks and sticks a recipe needs.", false, Palette.CHALK_DIM, 13, true))


# ---------------------------------------------------------------- cursor hint

func show_hint(text: String, at: Vector2, color := Palette.CHALK) -> void:
	_hint.visible = text != ""
	if text == "":
		return
	_hint.text = text
	_hint.add_theme_color_override("font_color", color)
	_hint.position = at + Vector2(18, 14)
	_hint.size = Vector2.ZERO
