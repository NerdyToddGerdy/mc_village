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
var _radial := Control.new()  ## Draws the radial Gather menu (issue #176) when it's open.
var _tallies := HBoxContainer.new()
var _tools_btn: Button
var _jobs_btn: Button               ## Opens the Village jobs board (issue #78).
var _claim_btn: Button              ## "2 land claims": starts the Claim land order (issue #187).
var _maps := HBoxContainer.new()    ## The map switcher (issue #101): Village, and each known site.
var _party := Button.new()          ## "Party at the old mine: mining", when residents work on another map.
var _party_panel: PanelContainer
var _home_btn: Button               ## "Call the party home", beside the party line while the site is in view (issue #108).
var _party_details := VBoxContainer.new()  ## The party's members, packs and objective, while the site is in view (#109).
var _choice_panel: PanelContainer   ## A choice the game stopped for (issues #110, #111).
var _choice_box := VBoxContainer.new()
var _board_panel: PanelContainer
var _board := VBoxContainer.new()
var _tools_drop: PanelContainer
var _job_drop: PanelContainer       ## A resident's job dropdown (issue #134), under the button it opened from.
var _job_list := VBoxContainer.new()
var _job_for := -1                  ## The resident whose job dropdown is open, or -1.
var _job_anchor := Rect2()          ## The button it opened from, in global coordinates.
var _tally_panel: PanelContainer
var _tally_seen := {}           ## Item types that have turned up in this game; the rest stay hidden.
var _tally_sim := 0             ## Which sim _tally_seen belongs to (it resets for a new or loaded game).
var _goals_panel: PanelContainer
var _tools_list := VBoxContainer.new()
var _drop_pinned := ""          ## The tally group whose dropdown a click pinned open, or "" (issue #141).
var _drop_group := ""           ## The tally group whose dropdown is open, or "".
var _group_btns := {}           ## Tally group id -> its button in the tally bar.
var _pointer := Vector2(-1, -1)
var _goals := VBoxContainer.new()
var _speed_btns := {}
var _menu_btn: Button                ## The on-screen button for the Esc menu (issue #216), beside the speed buttons.
var _menu_cap: PanelContainer        ## Its key badge, which follows the "menu" binding.
var _menu_cap_label: Label
var _stuck_panel: PanelContainer
var _stuck := VBoxContainer.new()
var stuck_open := true          ## The stuck list shows its entries; false folds it to a chip (issue #77).
var _stuck_gives_way := false   ## The expedition planner is tall enough to reach the stuck list, which steps aside.
var waiting_open := false       ## The Waiting tier's entries are shown.
var _stuck_keys := {}           ## Blockers shown last refresh, to open the list when a new one appears.
var _toasts := VBoxContainer.new()
var _sel_panel: PanelContainer
var _sel := VBoxContainer.new()
var _build_menu: PanelContainer
var _craft_panel: PanelContainer
var _plan_panel: PanelContainer     ## The expedition planner (issues #105-#107).
var _plan_box := VBoxContainer.new()
var _craft_box := VBoxContainer.new()
var _craft_pick := {}           ## Station template -> the recipe its Craft panel shows (issue #95).
var _craft_n := {}              ## Recipe id -> how many its Queue button queues (issue #76).
const CRAFT_MAX := 20
var _speed_panel: PanelContainer
var _tool_btns := {}
var _tool_keys := {}            ## Each orders button's keycap Label.
var _toolbar_sig := ""
var _armed_key := ""            ## The Destructive button waiting for its second click, if any.
var _armed_until := 0
const ARM_MS := 3000
var _menus := {}                ## Toolbar menu id -> its rows' container (OrderMenus.MENUS).
var _menu_panels := {}          ## Toolbar menu id -> its panel above the toolbar.
var _tool_icons := {}           ## Toolbar button id -> its icon, redrawn when the active order changes.
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
	for g in Defs.TALLY_GROUPS:  # one button per group, each opening its dropdown (issue #141)
		var gb := _button(g[1] + "  ▾", func(): pass)
		gb.pressed.connect(func():
			_drop_pinned = "" if _drop_pinned == g[0] else g[0]
			gb.release_focus())  # a click pins; only keyboard focus should hold it open (#90)
		gb.set_meta("label", "tally:" + g[0])  # what tests find it by; "Building" alone would match the toolbar's "Build"
		gb.set_meta("name", g[1])
		gb.toggle_mode = true
		gb.custom_minimum_size = Vector2(0, 36)
		tally_row.add_child(gb)
		_group_btns[g[0]] = gb
	_tools_btn = _group_btns.tools
	_jobs_btn = _button("Jobs", func(): game.toggle_jobs_board())
	_jobs_btn.toggle_mode = true
	_jobs_btn.custom_minimum_size = Vector2(0, 36)
	tally_row.add_child(_jobs_btn)
	_claim_btn = _button("", func(): game.start_claiming(), "Primary")
	_claim_btn.custom_minimum_size = Vector2(0, 36)
	_claim_btn.visible = false
	tally_row.add_child(_claim_btn)
	_maps.add_theme_constant_override("separation", 2)
	tally_row.add_child(_maps)
	_tally_panel = _panel(tally_row, Vector2(0, 0))
	tl.add_child(_tally_panel)
	_party.flat = true
	_party.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_party.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for state in ["font_color", "font_focus_color"]:
		_party.add_theme_color_override(state, Palette.CHALK_DIM)
	_party.pressed.connect(func(): game.switch_map(_party.get_meta("map", "village")))
	var party_row := HBoxContainer.new()
	party_row.add_theme_constant_override("separation", 8)
	party_row.add_child(_party)
	_home_btn = _button("Call the party home", func(): game.call_home(), "Primary")
	_home_btn.visible = false
	party_row.add_child(_home_btn)
	var party_box := VBoxContainer.new()
	party_box.add_theme_constant_override("separation", 6)
	party_box.add_child(party_row)
	_party_details.add_theme_constant_override("separation", 4)
	_party_details.custom_minimum_size.x = 300
	party_box.add_child(_party_details)
	_party_panel = _panel(party_box, Vector2.ZERO, 8)
	_party_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_party_panel.visible = false
	tl.add_child(_party_panel)
	_tools_list.add_theme_constant_override("separation", 10)
	_tools_drop = _panel(_tools_list, Vector2(290, 0))
	_tools_drop.visible = false
	_tools_drop.top_level = true
	_job_list.add_theme_constant_override("separation", 2)
	_job_drop = _panel(_job_list, Vector2(250, 0), 6)
	_job_drop.add_theme_stylebox_override("panel", _box(Color(Palette.SLATE, 1.0), 8, 6, Palette.SLATE_DEEP))  # opaque: it lies over other panels
	_job_drop.visible = false
	_job_drop.top_level = true
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
	_menu_btn = _button("Menu", func(): game.toggle_menu())  # the Esc menu, for the mouse and the web build (issue #216)
	_menu_btn.custom_minimum_size = Vector2(0, 44)
	_menu_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_menu_cap = PanelContainer.new()
	var menu_cap_box := _box(Color(0, 0, 0, 0), 3, 0, Palette.CHALK_DIM)
	menu_cap_box.content_margin_left = 5
	menu_cap_box.content_margin_right = 5
	menu_cap_box.content_margin_top = 0
	menu_cap_box.content_margin_bottom = 0
	_menu_cap.add_theme_stylebox_override("panel", menu_cap_box)
	_menu_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_cap_label = _label("", false, Palette.CHALK_DIM, Palette.CAPTION)
	_menu_cap.add_child(_menu_cap_label)
	_menu_btn.add_child(_menu_cap)
	var place_cap := func() -> void:
		var cs := _menu_cap.get_combined_minimum_size()
		_menu_cap.size = cs
		_menu_cap.position = Vector2(_menu_btn.size.x - cs.x - 10, (_menu_btn.size.y - cs.y) / 2)
	_menu_btn.resized.connect(place_cap)
	_menu_cap.minimum_size_changed.connect(place_cap)
	speed.add_child(_menu_btn)
	_speed_panel = _panel(speed, Vector2.ZERO, 4)
	tr.add_child(_speed_panel)
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
	for m in OrderMenus.MENUS:  # Gather, Paint and Build: one menu control for all three (#93, #94)
		var box := GridContainer.new()  # one column, or two once a menu is long (the Build menu, #184)
		box.add_theme_constant_override("h_separation", 2)
		box.add_theme_constant_override("v_separation", 2)
		_menus[m] = box
		var mp := _panel(box, Vector2(300, 0), 6)
		mp.visible = false
		_menu_panels[m] = mp
		br.add_child(mp)
	_build_menu = _menu_panels.build
	_craft_box.add_theme_constant_override("separation", 8)
	_craft_panel = _panel(_craft_box, Vector2(400, 0))
	_craft_panel.visible = false
	br.add_child(_craft_panel)
	_plan_box.add_theme_constant_override("separation", 8)
	_plan_panel = _panel(_plan_box, Vector2(0, 0))
	_plan_panel.visible = false
	br.add_child(_plan_panel)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 2)
	for t in ["gather", "paint", "build", "craft"]:
		if t == "craft":  # Craft opens a panel rather than choosing an order, so it stands apart
			var rule := ColorRect.new()
			rule.color = Palette.SLATE_DEEP
			rule.custom_minimum_size = Vector2(2, 0)
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tools.add_child(rule)
		tools.add_child(_order_button(t))
	br.add_child(_panel(tools, Vector2.ZERO, 4))

	_root.add_child(_tools_drop)
	_board_panel = _panel(_board, Vector2.ZERO)
	_board_panel.top_level = true
	_board_panel.visible = false
	_root.add_child(_board_panel)
	_root.add_child(_job_drop)
	_radial.set_anchors_preset(Control.PRESET_FULL_RECT)
	_radial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radial.draw.connect(_draw_radial)
	_root.add_child(_radial)
	_choice_box.add_theme_constant_override("separation", 8)
	_choice_box.custom_minimum_size.x = 380
	_choice_panel = _panel(_choice_box, Vector2.ZERO, 18)
	_choice_panel.visible = false
	_root.add_child(_choice_panel)
	_hint.visible = false
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := _box(Color(Palette.SLATE, 0.96), 4, 8)
	_hint.add_theme_stylebox_override("normal", hs)
	_root.add_child(_hint)


## An orders-toolbar button (issue #74): a chalk name, with the order's world mark as an icon on the
## left (so colour is never the only signal) and its key as a small keycap on the right.
func _order_button(t: String) -> Button:
	var b := _button("", func(): game.set_tool(t))
	b.custom_minimum_size = Vector2(0, 52)
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(18, 18)
	icon.size = Vector2(18, 18)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func(): _draw_mark(icon, _button_mark(t)))
	b.add_child(icon)
	_tool_icons[t] = icon
	var cap := PanelContainer.new()
	var cap_box := _box(Color(0, 0, 0, 0), 3, 0, Palette.CHALK_DIM)
	cap_box.content_margin_left = 5
	cap_box.content_margin_right = 5
	cap_box.content_margin_top = 0
	cap_box.content_margin_bottom = 0
	cap.add_theme_stylebox_override("panel", cap_box)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap_label := _label("", false, Palette.CHALK_DIM, Palette.CAPTION)
	cap.add_child(cap_label)
	b.add_child(cap)
	_tool_btns[t] = b
	_tool_keys[t] = cap_label
	var place := func() -> void:
		var cs := cap.get_combined_minimum_size()
		icon.position = Vector2(12, (b.size.y - 18) / 2)
		cap.size = cs
		cap.position = Vector2(b.size.x - cs.x - 10, (b.size.y - cs.y) / 2)
	b.resized.connect(place)
	cap.minimum_size_changed.connect(place)
	return b


## Sets an orders button's name and keycap, and leaves room for the icon and the keycap.
func _set_order_label(t: String, name: String, key: String) -> void:
	var b: Button = _tool_btns[t]
	b.text = name
	_tool_keys[t].text = key
	_tool_keys[t].get_parent().visible = key != ""
	var right := 12.0
	if key != "":
		right = 10 + _font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.CAPTION).x + 12 + 10
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var sb := (_theme.get_stylebox(state, "Button") as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.content_margin_left = 40
		sb.content_margin_right = right
		b.add_theme_stylebox_override(state, sb)


## Draws an order's world mark at icon size, with the same dark under-stroke the marks have in the world.
func _draw_mark(c: Control, t: String) -> void:
	var dark := Palette.SLATE_DEEP
	match t:
		"mine":  # a red slash, like the one across a marked tree
			c.draw_line(Vector2(4, 14), Vector2(14, 4), dark, 6)
			c.draw_line(Vector2(4, 14), Vector2(14, 4), Palette.RED, 3)
		"chop":  # a red slash across a trunk
			c.draw_rect(Rect2(6, 4, 6, 13), Palette.LOG)
			c.draw_line(Vector2(3, 14), Vector2(15, 5), dark, 6)
			c.draw_line(Vector2(3, 14), Vector2(15, 5), Palette.RED, 3)
		"break":  # the red X on a boulder
			c.draw_rect(Rect2(3, 5, 12, 10), Palette.STONE)
			for a in [[Vector2(4, 4), Vector2(14, 14)], [Vector2(14, 4), Vector2(4, 14)]]:
				c.draw_line(a[0], a[1], dark, 5)
				c.draw_line(a[0], a[1], Palette.RED, 2.5)
		"keep":  # the green ring round a kept tree (issue #177)
			c.draw_arc(Vector2(9, 9), 6, 0, TAU, 24, dark, 4.5)
			c.draw_arc(Vector2(9, 9), 6, 0, TAU, 24, Palette.GREEN, 2.2)
		"hunt":  # the crosshair over a marked sheep
			c.draw_arc(Vector2(9, 9), 6, 0, TAU, 24, dark, 4)
			c.draw_arc(Vector2(9, 9), 6, 0, TAU, 24, Palette.RED, 2)
			for d in [Vector2(1, 0), Vector2(0, 1)]:
				c.draw_line(Vector2(9, 9) - d * 9, Vector2(9, 9) + d * 9, Palette.RED, 2)
		"lead":  # a loop of rope, in build blue
			c.draw_arc(Vector2(9, 8), 5, 0.9, 0.9 + TAU * 0.85, 20, dark, 4)
			c.draw_arc(Vector2(9, 8), 5, 0.9, 0.9 + TAU * 0.85, 20, Palette.BLUE, 2)
			c.draw_line(Vector2(12, 12), Vector2(15, 17), dark, 4)
			c.draw_line(Vector2(12, 12), Vector2(15, 17), Palette.BLUE, 2)
		"pen":  # posts and rails round a square, in build blue
			for x in [2.0, 9.0, 16.0]:
				c.draw_line(Vector2(x, 4), Vector2(x, 16), Palette.LOG, 2.5)
			for y in [7.0, 12.0]:
				c.draw_line(Vector2(1, y), Vector2(17, y), Palette.BLUE, 1.5)
		"stock":  # a green hatched patch
			c.draw_rect(Rect2(2, 2, 14, 14), Palette.GREEN, false, 1.5)
			for a in [[Vector2(2, 9), Vector2(9, 2)], [Vector2(2, 16), Vector2(16, 2)], [Vector2(9, 16), Vector2(16, 9)]]:
				c.draw_line(a[0], a[1], Palette.GREEN, 1.5)
		"farm":  # rows of wheat on a tilled plot
			for y in [8.0, 16.0]:
				c.draw_line(Vector2(1, y), Vector2(17, y), Palette.DIRT, 2)
				for x in [4.0, 9.0, 14.0]:
					c.draw_line(Vector2(x, y - 1), Vector2(x, y - 6), Palette.WHEAT, 1.5)
					c.draw_rect(Rect2(x - 1.5, y - 7, 3, 3), Palette.WHEAT)
		"build":  # the blue dashed outline of a blueprint
			var r := [Vector2(2, 2), Vector2(16, 2), Vector2(16, 16), Vector2(2, 16)]
			for i in 4:
				c.draw_dashed_line(r[i], r[(i + 1) % 4], Palette.BLUE, 2, 3.5)
		"craft":  # a small bench
			c.draw_rect(Rect2(2, 6, 14, 4), Palette.PLANK)
			c.draw_rect(Rect2(3, 10, 2, 6), Palette.PLANK)
			c.draw_rect(Rect2(13, 10, 2, 6), Palette.PLANK)


## The radial Gather menu (issue #176): slate wedges outlined in chalk round the cursor, each with
## its order's mark, number and name; the hovered one filled in chalk, a greyed one dim. The middle
## names the target and what it drops.
func _draw_radial() -> void:
	var r: Dictionary = game.radial
	if r.is_empty():
		return
	var c: Vector2 = r.center
	var rin := Game.RADIAL_IN
	var rout := Game.RADIAL_OUT
	var n: int = r.wedges.size()
	var span := TAU / n
	for i in n:
		var w: Dictionary = r.wedges[i]
		var a0 := -PI / 2 - span / 2 + i * span + 0.035
		var a1 := a0 + span - 0.07
		var pts := PackedVector2Array()
		for k in 17:
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, k / 16.0)) * rout)
		for k in range(16, -1, -1):
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, k / 16.0)) * rin)
		var lit: bool = r.hover == i and w.ok
		_radial.draw_colored_polygon(pts, Palette.CHALK if lit else Color(Palette.SLATE, 0.95 if w.ok else 0.7))
		var edge := pts.duplicate()
		edge.append(pts[0])
		_radial.draw_polyline(edge, Palette.CHALK if w.ok else Palette.CHALK_DIM, 1.5, true)
		var mid := c + Vector2.from_angle((a0 + a1) / 2) * (rin + rout) / 2
		_radial.draw_set_transform(mid + Vector2(-9, -26))
		_draw_mark(_radial, w.mark)
		_radial.draw_set_transform(Vector2.ZERO)
		var col: Color = Palette.SLATE_DEEP if lit else (Palette.CHALK if w.ok else Palette.CHALK_DIM)
		var tw := 104.0
		_radial.draw_multiline_string(_bold, mid + Vector2(-tw / 2, 4), "%d  %s" % [i + 1, w.label], HORIZONTAL_ALIGNMENT_CENTER, tw, Palette.CAPTION, 2, col)
	_radial.draw_circle(c, rin - 3, Palette.SLATE_DEEP)
	_radial.draw_arc(c, rin - 3, 0, TAU, 40, Palette.CHALK, 1.5, true)
	var title: String = game.radial_title(r.target)
	var parts := title.split(" · ")
	var w2 := (rin - 6) * 2
	_radial.draw_string(_bold, c + Vector2(-w2 / 2, -4), parts[0], HORIZONTAL_ALIGNMENT_CENTER, w2, Palette.CAPTION, Palette.CHALK)
	if parts.size() > 1:
		_radial.draw_multiline_string(_font, c + Vector2(-w2 / 2, 10), parts[1], HORIZONTAL_ALIGNMENT_CENTER, w2, Palette.CAPTION - 2, 2, Palette.CHALK_DIM)


# ---------------------------------------------------------------- shared builders (also used by the menu)

func label(text: String, bold := false, color := Palette.CHALK, size := Palette.BODY, wrap := false) -> Label:
	return _label(text, bold, color, size, wrap)


func button(text: String, on_press: Callable, style := "") -> Button:
	return _button(text, on_press, style)


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
	_theme.default_font_size = Palette.BODY
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
	# Three button variations (issue #75). Primary: a panel's main action. Secondary: inline actions.
	# Destructive: actions that throw work away; they take a second click to confirm.
	for v in [["Primary", Palette.CHALK, Palette.CHALK, Palette.CHALK], ["Secondary", Color(Palette.CHALK_DIM, 0.35), Palette.CHALK_DIM, Palette.CHALK], ["Destructive", Palette.RED, Palette.RED, Palette.RED]]:
		_theme.set_type_variation(v[0], "Button")
		_theme.set_stylebox("normal", v[0], _box(Color(0, 0, 0, 0), 4, 8, v[1]))
		for state in ["hover", "pressed", "hover_pressed"]:
			_theme.set_stylebox(state, v[0], _box(Palette.SLATE_DEEP, 4, 8, v[3]))
		_theme.set_stylebox("disabled", v[0], _box(Color(0, 0, 0, 0), 4, 8, Palette.SLATE_DEEP))
		_theme.set_color("font_color", v[0], v[2])
		_theme.set_color("font_focus_color", v[0], v[2])
		_theme.set_color("font_hover_color", v[0], v[3])
		_theme.set_color("font_pressed_color", v[0], v[3])
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


func _label(text: String, bold := false, color := Palette.CHALK, size := Palette.BODY, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if bold:
		l.add_theme_font_override("font", _bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	return l


func _button(text: String, on_press: Callable, style := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.theme_type_variation = style
	b.pressed.connect(on_press)
	return b


## A Destructive button: the first click arms it ("Click again to …") for a few seconds, and only a
## second click acts. `key` names what it destroys, so the armed state survives a panel rebuild.
func _destructive(text: String, confirm: String, key: String, on_press: Callable) -> Button:
	var armed := _armed_key == key and Time.get_ticks_msec() < _armed_until
	var b := _button(confirm if armed else text, func(): pass, "Destructive")
	b.pressed.connect(func() -> void:
		if _armed_key == key and Time.get_ticks_msec() < _armed_until:
			_armed_key = ""
			on_press.call()
		else:
			_armed_key = key
			_armed_until = Time.get_ticks_msec() + ARM_MS
			b.text = confirm)
	b.set_meta("disarmed_text", text)
	b.set_meta("arm_key", key)
	return b


## Toolbar badges, build-menu keys and tooltips, from the current key bindings (issue #8).
func _refresh_key_labels() -> void:
	var k: KeyBindings = game.keys
	var sig := "%s" % [k.keys]
	if sig == _keys_sig:
		return
	_keys_sig = sig
	var tips := {"gather": "Mine, chop, break and hunt", "paint": "Paint stockpiles and farm plots",
		"build": "Place a building", "craft": "Queue crafts at the bench or the fireplace"}
	for t in _tool_btns:
		_tool_btns[t].tooltip_text = tips[t] + (" (%s)" % k.first(t) if k.first(t) != "" else "")
	_toolbar_sig = ""
	var menu_key := k.first("menu")
	_menu_cap_label.text = menu_key
	_menu_cap.visible = menu_key != ""
	_menu_btn.tooltip_text = "Save, load, controls and more" + (" (%s, or Esc)" % menu_key if menu_key != "" else " (Esc)")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var sb := (_theme.get_stylebox(state, "Button") as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.content_margin_right = 10 + (_font.get_string_size(menu_key, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.CAPTION).x + 12 + 10 if menu_key != "" else 2)
		_menu_btn.add_theme_stylebox_override(state, sb)
	var speed_actions := {0: "pause", 1: "speed1", 2: "speed2", 3: "speed3"}
	for v in _speed_btns:
		var keytext := k.text(speed_actions[v]).replace("  ", " or ")
		_speed_btns[v].tooltip_text = ("Pause" if v == 0 else "Speed %d×" % v) + (" (%s)" % keytext if keytext != "No key" else "")


## The orders toolbar's buttons and open menu (issues #93, #94). A Gather or Paint button names the
## order that's on ("Gather: Hunt") and shows its mark; its menu lists the available orders.
func _refresh_toolbar(sim: Sim) -> void:
	var k: KeyBindings = game.keys
	var on_menu := OrderMenus.menu_of(game.tool)
	var gather: Array = sim.on_map(game.view_map, OrderMenus.entries.bind("gather", sim))
	var village: bool = game.view_map == "village"
	_tool_btns.paint.visible = village or game.view_map == Meadow.ID  # stockpiles and farms in the village, pens at the meadow
	_tool_btns.build.visible = village
	var sig := "%s|%s|%s|%s|%s" % [game.tool, game.menu_open, _keys_sig, gather.size(), game.view_map]
	if sig != _toolbar_sig:
		_toolbar_sig = sig
		for t in _tool_btns:
			var name: String = OrderMenus.MENUS[t].name if OrderMenus.MENUS.has(t) else "Craft"
			if t != "build" and on_menu == t:
				name += ": " + OrderMenus.entry(game.tool).name
			elif OrderMenus.MENUS.has(t):
				name += "  ▸"
			_set_order_label(t, name, k.first(t))
			_tool_icons[t].queue_redraw()
	for t in _tool_btns:
		var on: bool
		match t:
			"craft": on = game.craft_menu_open
			"build": on = game.menu_open == "build" or game.tool == "build"
			_: on = game.menu_open == t or on_menu == t
		_tool_btns[t].set_pressed_no_signal(on)
	for m in _menu_panels:
		_menu_panels[m].visible = game.menu_open == m
		if game.menu_open != m:
			continue
		var list: Array = sim.on_map(game.view_map, OrderMenus.entries.bind(m, sim))
		_menus[m].columns = 2 if list.size() > MENU_ROWS else 1
		_rebuild(_menus[m], "%s%s%s" % [list.map(func(e): return e.id), _keys_sig, game.tool], func(c: Container) -> void:
			for i in list.size():
				c.add_child(_menu_row(m, i, list[i])))


## The mark a toolbar button shows: the active order's, or its menu's first.
func _button_mark(t: String) -> String:
	if OrderMenus.menu_of(game.tool) == t and t != "build":
		return OrderMenus.entry(game.tool).mark
	return {"gather": "mine", "paint": "pen" if game.view_map == Meadow.ID else "stock"}.get(t, t)


## A toolbar menu row: the order's mark, its name and a line about it, and on the right its number
## in the menu (press it while the menu is open) and its direct key, if it has one.
func _menu_row(menu: String, i: int, e: Dictionary) -> Button:
	var b := _button("", func(): game.pick_order(menu, e.id))
	b.set_meta("label", e.name)  # the row's name, for finding it (its text is drawn by labels)
	b.toggle_mode = true
	b.set_pressed_no_signal(game.tool == e.id or (menu == "build" and game.placing == e.id))
	var caps := HBoxContainer.new()
	caps.add_theme_constant_override("separation", 4)
	caps.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var direct: String = game.keys.first(e.id)
	var caps_w := 0.0
	for key in ["%d" % (i + 1), direct]:
		if key != "":
			caps.add_child(_keycap(key))
			caps_w += _font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.CAPTION).x + 12 + 4
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(_label(e.name, true, Palette.CHALK, Palette.BODY))
	var sub := _label(e.sub, false, Palette.CHALK_DIM, Palette.CAPTION, true)
	var sub_w := MENU_W - 40 - 10 - 10 - caps_w
	sub.custom_minimum_size.x = sub_w
	words.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(words)
	row.add_child(caps)
	var m := MarginContainer.new()
	for side in [["left", 40], ["right", 10], ["top", 6], ["bottom", 6]]:
		m.add_theme_constant_override("margin_" + side[0], side[1])
	m.add_child(row)
	b.add_child(m)
	for n in [m, row, words, caps]:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(18, 18)
	icon.size = Vector2(18, 18)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func(): _draw_mark(icon, e.mark))
	b.add_child(icon)
	# A wrapped label reports its height only after layout, so measure the text for the row's height.
	var sub_h := _font.get_multiline_string_size(e.sub, HORIZONTAL_ALIGNMENT_LEFT, sub_w, Palette.CAPTION).y
	b.custom_minimum_size = Vector2(MENU_W, maxf(12 + _bold.get_height(Palette.BODY) + sub_h + 2, 52))
	b.resized.connect(func():
		m.size = b.size
		icon.position = Vector2(12, (b.size.y - 18) / 2))
	b.tooltip_text = "%s (%d%s)" % [e.name, i + 1, ", or %s" % direct if direct != "" else ""]
	return b


const MENU_W := 288.0
const MENU_ROWS := 6  ## Rows a toolbar menu shows in one column; a longer one is laid out in two.


func _keycap(key: String) -> PanelContainer:
	var cap := PanelContainer.new()
	var cap_box := _box(Color(0, 0, 0, 0), 3, 0, Palette.CHALK_DIM)
	cap_box.content_margin_left = 5
	cap_box.content_margin_right = 5
	cap.add_theme_stylebox_override("panel", cap_box)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(_label(key, false, Palette.CHALK_DIM, Palette.CAPTION))
	return cap


## The selection panel's content width at its narrowest (330 wide less its margins).
const HEAD_FIT := 306.0


## A panel's title with its status on the right. When the two won't fit side by side, the status
## moves to its own dimmed line below the title, so they never run together (issue #72).
func _head(title: String, status: String, bold := false, size := 15, swatch := "") -> Control:
	var t: Control = _label(title, bold, Palette.CHALK, size)
	var title_w := (_bold if bold else _font).get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if swatch != "":  # a resident's tunic colour before their name (issue #79)
		var named := HBoxContainer.new()
		named.add_theme_constant_override("separation", 8)
		named.add_child(_swatch(swatch))
		named.add_child(t)
		t = named
		title_w += 22
	var status_w := _font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.BODY).x
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
	v.add_child(_label(status, false, Palette.CHALK_DIM, Palette.BODY, true))
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
	return _label("⚑  " + text, true, Palette.YELLOW, Palette.BODY, true)


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
	_refresh_maps(sim)
	_refresh_goals(sim)
	for v in _speed_btns:
		_speed_btns[v].set_pressed_no_signal(game.speed == v)
	_paused_label.visible = game.speed == 0 and sim.pending.is_empty()  # a choice says so itself
	_refresh_stuck(sim)
	_refresh_selection(sim)
	_refresh_job_drop(sim)
	_refresh_toolbar(sim)
	_refresh_board(sim)
	_refresh_craft(sim)
	_refresh_planner(sim)
	_refresh_choice(sim)
	_refresh_toasts()


func _refresh_tallies(sim: Sim) -> void:
	var claims := sim.claims_available()  # issue #187
	_claim_btn.visible = claims > 0 or sim.claims_pending() > 0
	_claim_btn.disabled = claims == 0
	_claim_btn.text = "%d land %s" % [claims, "claim" if claims == 1 else "claims"] if claims > 0 else "Staking land"
	_claim_btn.tooltip_text = "Claim a strip of new land along an edge. One claim for every %d residents beyond the first two." % Tuning.CLAIM_EVERY if claims > 0 else "A builder is planting the boundary stakes."
	var totals := {}
	var loose := {}
	for k in sim.items:
		var s: Dictionary = sim.items[k]
		totals[s.type] = totals.get(s.type, 0) + s.n
		if not sim.stored(s):
			loose[s.type] = loose.get(s.type, 0) + s.n
	var gear := 0  # tools and armor, worn and spare
	for t in Defs.group_items("tools"):
		gear += totals.get(t, 0)
	for r in sim.residents:
		gear += int(r.axe != null) + int(r.pick != null) + Sim.armor_worn(r).size()
	if _tally_sim != sim.get_instance_id():
		_tally_sim = sim.get_instance_id()
		_tally_seen.clear()
	for t in totals:
		_tally_seen[t] = true
	for site in sim.sites:  # and whatever a building or a queued recipe is waiting for, even at 0
		if not site.done:
			for t in sim.current_stage(site).cost:
				_tally_seen[t] = true
		for id in site.get("queue", []):
			for t in Defs.recipe(id).inp:
				_tally_seen[t] = true
	var meals := 0
	for t in Defs.MEALS:
		meals += totals.get(t, 0)
	var raw := 0
	for t in Defs.RAW_MEATS:
		raw += totals.get(t, 0)
	var low := meals < sim.residents.size()
	var pins: Array = game.keys.pinned
	_rebuild(_tallies, "%s%s%s" % [totals, loose, pins], func(c: Container) -> void:
		for t in pins:  # pinned items, each on its own (issue #141)
			c.add_child(_tally(Defs.ITEMS[t].get("label", Defs.ITEMS[t].many.capitalize()), totals.get(t, 0), loose.get(t, 0)))
		if not pins.is_empty():
			c.add_child(_divider()))
	for g in _group_btns:
		var b: Button = _group_btns[g]
		var items: Array = Defs.group_items(g)
		b.visible = g == "tools" or items.any(func(t): return _tally_seen.has(t))  # a group shows once one of its items turns up
		var n := 0
		for t in items:
			n += totals.get(t, 0)
		var name: String = b.get_meta("name")
		match g:
			"food":
				b.text = "Food  %d %s%s  ▾" % [meals, "meal" if meals == 1 else "meals", " · %d raw" % raw if raw > 0 else ""]
				for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
					if low:
						b.add_theme_color_override(k, Palette.YELLOW)
					else:
						b.remove_theme_color_override(k)
				b.tooltip_text = "Fewer meals than residents. Cooks need wheat, or raw meat and logs." if low else ""
			"tools":
				b.text = "%s  %d  ▾" % [name, gear]
			_:
				b.text = "%s  %d  ▾" % [name, n]
	_refresh_drop(sim, totals, loose, meals, raw)


## The map switcher (issue #101), shown once a site map is known, and a dim line for residents at
## work on a map that isn't in view, which switches to it on a click.
func _refresh_maps(sim: Sim) -> void:
	var known: Array = game.known_maps()
	_maps.visible = known.size() > 1
	var key: String = game.keys.first("map")
	_rebuild(_maps, "%s%s%s" % [known, game.view_map, key], func(c: Container) -> void:
		c.add_child(_divider())
		for id in known:
			var lv: int = sim.get_map(id).level
			var b := _button(sim.get_map(id).name if lv <= 1 else "Lv %d" % lv, func(): game.switch_map(id))  # deeper levels short (issue #132)
			b.set_meta("label", sim.get_map(id).name)
			b.toggle_mode = true
			b.set_pressed_no_signal(id == game.view_map)
			b.custom_minimum_size = Vector2(0, 36)
			b.tooltip_text = "Show the %s." % sim.get_map(id).name.to_lower() + (" %s switches maps." % key if key != "" else "")
			c.add_child(b))
	var line := ""
	for r in sim.residents:  # a party on the road (issues #107, #108)
		if r.away:
			line = "Party " + _road_text(sim, r).substr(0, 1).to_lower() + _road_text(sim, r).substr(1)
			_party.set_meta("map", r.trip)
			break
	for id in sim.maps:
		if line != "" or id == game.view_map or id == "village":
			continue
		var party: Array = sim.residents.filter(func(r): return r.map == id)
		if party.is_empty():
			continue
		line = "Party at the %s: %s" % [sim.get_map(id).name.to_lower(), _party_doing(party)]
		if id == Road.ID:  # a party walking the road, or villagers out working on it (issues #118, #119)
			var walking: Array = party.filter(func(r): return sim.on_road(r))
			line = "On the road: %s" % _party_doing(party)
			if not walking.is_empty():
				line = "Party " + _status(sim, walking[0]).replace("On the road", "on the road")
		_party.set_meta("map", id)
		break
	# Looking at the site the party is working: what they're doing here, and the way to call them home.
	var ex: Dictionary = sim.expedition
	var here_site: bool = ex.get("state", "") == "out" and game.view_map == ex.dest
	_home_btn.visible = here_site and ex.get("leg", "out") == "out"
	if here_site:
		var party: Array = ex.party.map(func(id): return sim.resident(id)).filter(func(r): return r.map == ex.dest and not r.away)
		if ex.get("leg", "out") == "home":
			line = "The party is heading home"
		elif not party.is_empty():
			line = "The party is here: %s" % _party_doing(party)
		elif line == "":
			line = "The party is on its way"
		_party.set_meta("map", game.view_map)
		var why := sim.call_home_blocker()
		_home_btn.disabled = why != ""
		_home_btn.tooltip_text = why if why != "" else "They walk to the entrance with what they’ve mined, and take the road home."
	_party_panel.visible = line != ""
	_party.text = line
	var details: bool = here_site and ex.get("leg", "out") == "out" and ex.party.any(func(id): return sim.at_site(sim.resident(id)))
	_party_details.visible = details
	if details:
		var sig := "%s|%d|%d" % [ex, sim.pack_load(), sim.objective_packed()]
		for id in ex.party:
			var r := sim.resident(id)
			sig += "%s%s%s%d" % [_status(sim, r), r.pick, r.get("hurt", 0), int(r.hunger / 10)]
		_rebuild(_party_details, sig, func(c: Container) -> void: _fill_party(c, sim))
	_party.tooltip_text = "Show the %s" % sim.get_map(_party.get_meta("map", "village")).name.to_lower() if line != "" and not here_site else ""


## What a party is mostly doing, in a word: "mining", "hauling", "idle".
static func _party_doing(party: Array) -> String:
	var doing := {}
	for r in party:
		var w: String = "idle"
		if r.job != null:
			w = {"lumber": "chopping", "mason": "mining", "haul": "hauling", "build": "building", "hunt": "hunting", "farm": "farming"}.get(r.job.work, "")
			if w == "":
				w = "eating" if r.job.kind == "eat" else "walking"
		doing[w] = doing.get(w, 0) + 1
	var best := "idle"
	for w in doing:
		if doing[w] > doing.get(best, 0):
			best = w
	return best


## One tally: a dim name, a bold count, and how many lie outside stockpiles.
func _tally(name: String, n: int, n_loose: int, color := Palette.CHALK) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var h := HBoxContainer.new()
	h.add_child(_label(name, false, Palette.CHALK_DIM, Palette.BODY))
	h.add_child(_label(str(n), true, color, Palette.HEADING))
	v.add_child(h)
	if n_loose > 0:
		v.add_child(_label("%d loose" % n_loose, false, Palette.CHALK_DIM, Palette.CAPTION))
	return v


## A thin upright rule between tally groups.
func _divider() -> Control:
	var d := ColorRect.new()
	d.color = Palette.SLATE_DEEP
	d.custom_minimum_size = Vector2(2, 0)
	return d


## A thin level rule between a panel's sections.
func _rule() -> Control:
	var d := ColorRect.new()
	d.color = Palette.SLATE_DEEP
	d.custom_minimum_size = Vector2(0, 2)
	return d


var _swatches := {}


## A colour as a small chalk-edged square, for icons: a resident's tunic (pass its hex, issue #79)
## or an item's colour (issue #76).
func _swatch_tex(color) -> ImageTexture:
	var c: Color = Color("#" + color) if color is String else color
	var key := c.to_html()
	if not _swatches.has(key):
		var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
		img.fill(Palette.CHALK)
		img.fill_rect(Rect2i(2, 2, 10, 10), c)
		_swatches[key] = ImageTexture.create_from_image(img)
	return _swatches[key]


## The swatch as a control, set beside a resident's name or an item count.
func _swatch(color) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _swatch_tex(color)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.custom_minimum_size = Vector2(14, 14)
	return t


## The open tally group's dropdown (issue #141): each item with its stockpiled and loose counts and
## a Pin button; Food splits meals from raw meat; Tools and armor lists what everyone carries and wears.
func _refresh_drop(sim: Sim, totals: Dictionary, loose: Dictionary, meals: int, raw: int) -> void:
	var g := _drop_group
	if g == "":
		return
	var sig := "%s%s%s%s" % [g, totals, loose, game.keys.pinned]
	if g == "tools":
		for r in sim.residents:
			sig += "%s%s%s%s%s;" % [r.name, r.axe, r.pick, r.broken, r.get("armor", {})]
		for st in sim.stacks_where(func(st): return Defs.wears(st.type)):
			sig += "%s%s%s" % [st.type, st.get("dur", -1), sim.in_zone(st.cell)]
	_rebuild(_tools_list, sig, func(c: Container) -> void:
		if g == "tools":
			_fill_tools(c, sim)
			return
		var title := _label([["building", "Building"], ["food", "Food"], ["animal", "Animal goods"], ["ores", "Ores"]].filter(func(x): return x[0] == g)[0][1], true, Palette.CHALK, Palette.HEADING)
		c.add_child(title)
		if g == "food":
			c.add_child(_row("Meals on hand", "%d" % meals))
			c.add_child(_row("Raw meat to cook", "%d" % raw))
			var berries := 0
			for b in sim.bushes:
				berries += b.berries
			c.add_child(_label("Berries on bushes: %d. Meals are bread and cooked meat; raw meat waits for the fireplace." % berries, false, Palette.CHALK_DIM, Palette.CAPTION, true))
		for t in Defs.group_items(g):
			if _tally_seen.has(t):
				c.add_child(_drop_row(t, totals.get(t, 0), loose.get(t, 0)))
		c.add_child(_label("Pin an item to keep it in the bar (up to %d)." % Defs.MAX_PINNED, false, Palette.CHALK_DIM, Palette.CAPTION, true)))


## One item in a tally dropdown: its name, how many, how many lie loose, and Pin.
func _drop_row(t: String, n: int, n_loose: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(_swatch(Palette.ITEM_COLORS.get(t, Palette.CHALK)))
	var name := _label(Defs.ITEMS[t].get("label", Defs.ITEMS[t].many.capitalize()), false, Palette.CHALK, Palette.BODY)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name)
	h.add_child(_label("%d" % n, true, Palette.CHALK, Palette.BODY))
	var l := _label("%d loose" % n_loose if n_loose > 0 else "", false, Palette.CHALK_DIM, Palette.CAPTION)
	l.custom_minimum_size.x = 56
	h.add_child(l)
	var pinned: bool = game.keys.pinned.has(t)
	var pin := _button("Unpin" if pinned else "Pin", func(): game.pin_item(t), "Secondary")
	pin.add_theme_font_size_override("font_size", Palette.CAPTION)
	pin.set_meta("label", "Pin " + t)
	pin.disabled = not pinned and game.keys.pinned.size() >= Defs.MAX_PINNED
	pin.tooltip_text = "Show it in the tally bar" if not pinned else "Take it out of the tally bar"
	h.add_child(pin)
	return h


## The Tools and armor dropdown (spec §12, issues #140, #141): each resident's tools with uses left,
## broken tools, the armor they wear, and spares.
func _fill_tools(c: Container, sim: Sim) -> void:
	var spare: Array = sim.stacks_where(func(st): return Defs.is_tool_item(st.type))
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
			g.add_child(_label("Bare hands", false, Palette.CHALK_DIM, Palette.BODY))
		var worn := Sim.armor_worn(r)
		if not worn.is_empty():
			var parts: PackedStringArray = []
			for slot in Defs.ARMOR_SLOTS:
				if worn.has(slot):
					parts.append("%s %d" % [Defs.SLOT_NAMES[slot].to_lower(), worn[slot].dur])
			g.add_child(_label("Armor, uses left: %s. %d%% guard." % [", ".join(parts), roundi(Sim.protection(r) * 100.0)], false, Palette.CHALK_DIM, Palette.CAPTION, true))
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
		g.add_child(_label(", ".join(where), false, Palette.CHALK_DIM, Palette.CAPTION))
		for st in spare:
			g.add_child(_tool_row(st.type, st.get("dur", Sim.full_uses(st.type))))
		c.add_child(g)
	var armor: Array = sim.stacks_where(func(st): return Defs.is_armor(st.type))
	if not armor.is_empty():
		var names: PackedStringArray = []
		for st in armor:
			names.append(Defs.ITEMS[st.type].one)
		c.add_child(_label("Spare armor: %s. Whoever lacks that piece puts it on." % ", ".join(names), false, Palette.CHALK_DIM, Palette.CAPTION, true))
	c.add_child(_label("Craft tools and armor at the bench. Residents pick up a better tool when a job needs one.", false, Palette.CHALK_DIM, Palette.CAPTION, true))


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


## Opens a tally group's dropdown (issue #141; the Tools one before it) while the pointer is over its
## button or the list, while the button has keyboard focus, or while it's pinned open by a click or
## tap. A click anywhere else, or Esc, closes it (issue #90: it used to stay open, held by the focus a
## click had left on the button).
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer = event.position
	if event is InputEventMouseButton:
		_held = event.pressed
		if event.pressed and _tools_drop.visible and not _over_tools(event.position):
			_close_tools()
		if event.pressed and _job_drop.visible and not _job_drop.get_global_rect().has_point(event.position) and not _job_anchor.has_point(event.position):
			_close_job_drop()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _tools_drop.visible:
		_close_tools()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _job_drop.visible:
		_close_job_drop()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_pointer = Vector2(-1, -1)  # the last position inside the window no longer counts as hovering


func _close_tools() -> void:
	_drop_pinned = ""
	for g in _group_btns:
		_group_btns[g].release_focus()
	_drop_group = ""
	_tools_drop.visible = false


## Over the open group's button, its list, or the strip between them (not their whole bounding box).
func _over_tools(at: Vector2, group := "") -> bool:
	var g := group if group != "" else _drop_group
	if g == "":
		return false
	var btn: Rect2 = _group_btns[g].get_global_rect().grow(4)
	if btn.has_point(at):
		return true
	if not _tools_drop.visible or g != _drop_group:
		return false
	var drop := _tools_drop.get_global_rect().grow(8)
	var gap := Rect2(Vector2(btn.position.x, btn.end.y), Vector2(btn.size.x, maxf(drop.position.y - btn.end.y, 0)))
	return drop.has_point(at) or gap.has_point(at)


func _process(_delta: float) -> void:
	if _tools_btn == null:
		return
	_radial.visible = not game.radial.is_empty()
	if _radial.visible:
		_radial.queue_redraw()
	if _armed_key != "" and Time.get_ticks_msec() >= _armed_until:
		_armed_key = ""
		for n in _sel.find_children("*", "Button", true, false) + _plan_box.find_children("*", "Button", true, false):
			if n.has_meta("disarmed_text"):
				n.text = n.get_meta("disarmed_text")
	_place_toasts()
	if _board_panel.visible:
		_board_panel.position = Vector2(_tally_panel.global_position.x, _tally_panel.get_global_rect().end.y + 8)
	# The goals panel gives way to the jobs board, which sits over it, and to a selection panel tall
	# enough to reach it (at a large interface size, issue #80): what's selected matters more.
	# The stuck list gives way to the expedition planner the same way; the planner shows the board's
	# own stuck reasons, and the list comes back when it closes.
	_stuck_gives_way = _plan_panel.visible and _plan_panel.get_global_rect().position.y < _stuck_panel.get_global_rect().position.y + _stuck_panel.get_combined_minimum_size().y + 8
	if _stuck_gives_way:
		_stuck_panel.visible = false
	_goals_panel.visible = not game.jobs_board_open and (not _sel_panel.visible or _sel_panel.get_global_rect().position.y > _goals_panel.get_global_rect().position.y + _goals_panel.get_combined_minimum_size().y + 8)
	var open := _drop_pinned
	for g in _group_btns:
		if open == "" and _group_btns[g].has_focus():
			open = g
	if open == "" and _drop_group != "" and _over_tools(_pointer):
		open = _drop_group
	for g in _group_btns:
		if open == "" and _group_btns[g].is_visible_in_tree() and _group_btns[g].get_global_rect().grow(4).has_point(_pointer):
			open = g
	if open != _drop_group:
		_drop_group = open
		_sigs.erase(_tools_list.get_instance_id())
	_tools_drop.visible = open != ""
	if open != "":
		var b: Button = _group_btns[open]
		var panel := b.get_parent().get_parent() as Control
		_tools_drop.position = Vector2(b.global_position.x - 12, panel.get_global_rect().end.y + 6)
	for g in _group_btns:
		_group_btns[g].set_pressed_no_signal(_drop_pinned == g)


func _refresh_goals(sim: Sim) -> void:
	var cur := Goals.current(sim)
	var done_sig := ""
	for i in Goals.LIST.size():
		done_sig += "1" if Goals.done(sim, i) else "0"
	# Once the founding is done, the panel folds to a small chip: it has nothing left to guide (#81).
	_goals_panel.custom_minimum_size.x = 0 if cur < 0 else 290
	_rebuild(_goals, "%d%s" % [cur, done_sig], func(c: Container) -> void:
		var n_done := done_sig.count("1")
		if cur < 0:
			var chip := _label("Founding  ✓", true, Palette.GREEN, Palette.BODY)
			chip.tooltip_text = "Every founding step is done: the village has its bench, its houses and its first traveler."
			chip.mouse_filter = Control.MOUSE_FILTER_STOP
			c.add_child(chip)
			return
		c.add_child(_row("The founding", "%d of %d" % [n_done, Goals.LIST.size()], false))
		# Wrapped at the panel's own width, so they measure right even when built while the panel is
		# hidden; otherwise they'd wrap at nothing, stand thousands of pixels tall and keep it hidden.
		for l in [_label("%d  %s" % [cur + 1, Goals.LIST[cur].t], true, Palette.CHALK, Palette.BODY, true), _label(Goals.LIST[cur].h, false, Palette.CHALK_DIM, Palette.CAPTION, true)]:
			l.custom_minimum_size.x = 290 - 24
			c.add_child(l))


## The stuck list (issue #77) has two tiers. Blockers, work that can't go on, get a yellow flag,
## oldest first. Standing orders short of materials only wait: one dim line that opens on click.
## The player can fold the blockers into a "Stuck n" chip; a new blocker opens it again.
func _refresh_stuck(sim: Sim) -> void:
	var vis := sim.stuck.filter(func(s): return not s.hidden)
	var block := vis.filter(func(s): return not s.waiting)
	var wait := vis.filter(func(s): return s.waiting)
	block.sort_custom(func(a, b): return a.since < b.since or (a.since == b.since and vis.find(a) < vis.find(b)))
	var keys := {}
	for s in block:
		keys[s.key] = true
		if not _stuck_keys.has(s.key):
			stuck_open = true
	_stuck_keys = keys
	_stuck_panel.visible = not vis.is_empty() and not _stuck_gives_way
	var folded := not block.is_empty() and not stuck_open
	_stuck_panel.custom_minimum_size.x = 0 if folded else 250
	var sig := "%s%s" % [stuck_open, waiting_open]
	for s in block + wait:
		sig += s.who + s.why + ";"
	_rebuild(_stuck, sig, func(c: Container) -> void:
		if not block.is_empty():
			var head := _button("Stuck (%d)   %s" % [block.size(), "▴" if stuck_open else "▾"], func(): stuck_open = not stuck_open)
			head.icon = MarkTextures.flag() if folded else null
			head.add_theme_constant_override("icon_max_width", 16)
			head.alignment = HORIZONTAL_ALIGNMENT_LEFT
			head.add_theme_font_override("font", _bold)
			head.add_theme_font_size_override("font_size", Palette.HEADING)
			for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				head.add_theme_color_override(state, Palette.YELLOW)
			head.tooltip_text = "Hide the stuck list. It opens again when something new gets stuck." if stuck_open else "Show what’s stuck"
			c.add_child(head)
			if folded:
				return
			for s in block:
				c.add_child(_stuck_entry(sim, s, false))
		if wait.is_empty():
			return
		if not block.is_empty():
			c.add_child(_rule())
		var n := wait.size()
		var line := _button("%d waiting   %s" % [n, "▴" if waiting_open else "▾"], func(): waiting_open = not waiting_open)
		line.alignment = HORIZONTAL_ALIGNMENT_LEFT
		for state in ["font_color", "font_focus_color"]:
			line.add_theme_color_override(state, Palette.CHALK_DIM)
		line.tooltip_text = "Standing orders short of materials for now, and an expedition being packed. Nothing is blocked."
		c.add_child(line)
		if waiting_open:
			for s in wait:
				c.add_child(_stuck_entry(sim, s, true)))


## One stuck-list entry; clicking it moves the camera there. A resident's entry carries their
## tunic swatch (issue #79), a blocker a yellow flag, a waiting order nothing and dim text.
func _stuck_entry(sim: Sim, s: Dictionary, waiting: bool) -> Button:
	var b := _button("%s\n%s" % [s.who, s.why], func(): game.focus_on(s.focus_kind, s.focus_id, s.map))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_constant_override("icon_max_width", 14)
	b.add_theme_constant_override("h_separation", 10)
	var r := sim.resident(s.focus_id) if s.focus_kind == "res" else {}
	if waiting:
		for state in ["font_color", "font_focus_color"]:
			b.add_theme_color_override(state, Palette.CHALK_DIM)
	elif not r.is_empty():
		b.icon = _swatch_tex(r.shirt)
	else:
		b.icon = MarkTextures.flag()
	return b


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
	for p in [_goals_panel, _party_panel]:  # clear of the goals and the party's panel
		if p.visible:
			left = maxf(left, p.get_global_rect().end.x + 12)
	var right := view.x - 16
	if _stuck_panel.visible:
		right = _stuck_panel.get_global_rect().position.x - 12
	var width := maxf(right - left, 240.0)
	_toasts.position = Vector2(left, _tally_panel.get_global_rect().end.y + 8)
	_toasts.size = Vector2(width, 0)
	for p in _toasts.get_children():
		var lab: Label = null
		var rest := 28.0  # the panel's margins, then the swatch and button beside the text
		if p.get_child(0) is Label:
			lab = p.get_child(0)
		else:
			for ch in p.get_child(0).get_children():
				if ch is Label:
					lab = ch
				else:
					rest += 14 + ch.get_combined_minimum_size().x
		var natural := lab.get_theme_font("font").get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lab.get_theme_font_size("font_size")).x
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size.x = minf(ceilf(natural) + 1, width - rest)


func add_toast(ev: Dictionary) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var who: Dictionary = game.sim.resident(ev.res_id) if ev.res_id else {}
	if not who.is_empty():
		h.add_child(_swatch(who.shirt))
	h.add_child(_label(ev.text))
	if ev.res_id:
		h.add_child(_button("Go to them", func(): game.focus_on("res", ev.res_id), "Secondary"))
	elif ev.site_id:
		h.add_child(_button("Show", func(): game.focus_on("site", ev.site_id), "Secondary"))
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
				sig += "%s%s%s%s%s%d%s%d" % [r.job.label if r.job != null else "Idle", r.axe, r.pick, r.carry, r.broken, int(r.progress * 10), r.orders, int(r.hunger / 5)] + "%s%s%s%s%s%s%d%d" % [r.jobs, r.role, _job_for == r.id, r.kept, equip_kind, r.away, int(sim.back_in(r)), r.get("hurt", 0)] + "%s" % [r.get("armor", {})]
		for kind in ["axe", "pick"]:  # Equip appears when there's a tool to choose
			for st in sim.tool_items(kind, 0):
				sig += "%s%s%s" % [st.type, st.dur, st.cell]
	elif target != null and target.kind == "route":
		sig += "%s%s%s%s" % [sim.residents.map(func(r): return [r.away, r.get("trip", ""), r.map, sim.carrying_packs(r), r.job.label if r.job != null else ""]), sim.route_report(), game.line_preview, game.view_map]
		sig += "%s%s%s" % [sim.cut_boulders().map(func(b): return b.des), sim.cart, [sim.station("village"), sim.station("mine")]]
	elif target != null and target.kind == "meadow":
		sig += "%s%s%s" % [sim.herds(), sim.adventures(), sim.expedition_board().is_empty()]
	elif target != null and target.kind == "crop":
		sig += "%d %d %d" % [Sim.crop_stage(target), int(target.grow / Tuning.WHEAT_GROW * 20.0), target.claim]
	elif target != null and target.kind in ["pen", "animal"]:  # issue #139: counts and timers
		sig += "%s%d%s" % [target, sim.tick / Tuning.TPS, sim.on_map(game.view_map, func(): return sim.m.sheep.map(func(a): return [a.alive, a.get("pen", 0), a.get("young", false), a.get("fed_at", -1)]))]
	elif target != null:
		sig += "%s" % [target]
	for s in sim.stuck:
		sig += s.why
	_rebuild(_sel, sig, func(c: Container) -> void: _fill_selection(c, sim, sel, target))


func _fill_selection(c: Container, sim: Sim, sel: Dictionary, target) -> void:
	if sel.is_empty():
		c.add_child(_label("Nothing selected", true, Palette.CHALK, Palette.HEADING))
		c.add_child(_label("Click Ada to select her. With Ada selected, right-click a tree to mine it, or use the orders toolbar to mark work for anyone. Press F to select a resident.", false, Palette.CHALK_DIM, Palette.BODY, true))
		return
	if sel.kind == "res":
		var rs: Array = sel.ids.map(func(id): return sim.resident(id)).filter(func(r): return not r.is_empty())
		if rs.size() > 1:
			c.add_child(_label("%d residents" % rs.size(), true, Palette.CHALK, Palette.TITLE))
			for r in rs:
				var line := HBoxContainer.new()
				line.add_theme_constant_override("separation", 8)
				line.add_child(_swatch(r.shirt))
				line.add_child(_label("%s: %s" % [r.name, _status(sim, r)], false, Palette.CHALK_DIM))
				c.add_child(line)
			return
		if rs.is_empty():
			return
		var r: Dictionary = rs[0]
		c.add_child(_head(r.name, _status(sim, r), true, 24, r.shirt))
		if r.progress >= 0:
			c.add_child(_bar(r.progress))
		if r.away:  # on the walk to or from the meadow (issue #137)
			c.add_child(_label("Off the map with the party. Residents on the way don’t work or get hungry.", false, Palette.CHALK_DIM, Palette.BODY, true))
			c.add_child(_bar(1.0 - sim.back_in(r) / sim.trip_time(r.trip), Palette.GREEN))
			return
		_add_tool_row(c, sim, r, "axe")
		_add_tool_row(c, sim, r, "pick")
		_add_armor_row(c, r)
		c.add_child(_row("Carrying", Defs.words(r.carry.type, r.carry.n) if r.carry != null else "Nothing"))
		c.add_child(_row("Food", _mood(r)))
		if r.get("hurt", 0) > 0:  # issue #110
			c.add_child(_row("Health", "Injured" if r.hurt == 1 else "Seriously hurt"))
		c.add_child(_bar(r.hunger / 100.0, Palette.YELLOW if r.hunger < Tuning.HUNGRY_BELOW else Palette.CHALK))
		for s in sim.stuck:
			if s.focus_kind == "res" and s.focus_id == r.id:
				c.add_child(_reason(s.why))
		if not r.orders.is_empty():
			c.add_child(_label("Queued orders", true))
			for i in r.orders.size():
				c.add_child(_label("%d  %s" % [i + 1, Sim.order_text(r.orders[i])], false, Palette.CHALK, Palette.BODY))
			c.add_child(_destructive("Clear orders", "Click again to clear orders", "orders:%d" % r.id, func(): game.clear_orders(r)))
		if equip_kind != "":
			return  # the tool list takes the Jobs grid's room while it's open
		if sim.expedition.get("state", "") == "out" and sim.expedition.party.has(r.id) and r.map == sim.expedition.dest:
			_add_call_home(c, sim)
		if r.axe == null and not r.broken.axe:
			c.add_child(_label("Chopping by hand is slow. Stone needs a pickaxe.", false, Palette.CHALK_DIM, Palette.BODY, true))
		_add_jobs_summary(c, sim, r)
		return
	if target == null:
		c.add_child(_label("That’s gone.", false, Palette.CHALK_DIM))
		return
	match target.kind:
		"tree":
			if not Sim.grown(target):  # planted by a lumberjack (issue #177)
				c.add_child(_head("Sapling" if Sim.tree_stage(target) == 0 else "Young tree", "Growing, %d%%" % int(target.grow / Tuning.SAPLING_GROW * 100.0)))
				c.add_child(_bar(target.grow / Tuning.SAPLING_GROW, Palette.GREEN))
				c.add_child(_label("It grows into a tree in %d minutes, and can't be chopped till then." % int(Tuning.SAPLING_GROW / 60.0), false, Palette.CHALK_DIM, Palette.BODY, true))
				return
			c.add_child(_head("Tree", "Drops %d logs and a sapling" % target.logs))
			c.add_child(_button("Cancel mining" if target.des else "Mine", func(): game.toggle_mine(target), "Secondary" if target.des else "Primary"))
			_add_keep(c, sim, target)
		"bush":
			c.add_child(_head("Berry bush", "%d of %d berries" % [target.berries, Tuning.BUSH_MAX]))
			c.add_child(_label("A berry grows back every %d seconds. Hungry residents eat here." % int(Tuning.BUSH_REGROW), false, Palette.CHALK_DIM, Palette.BODY, true))
		"meadow":  # the signpost to the meadow (issues #136, #137)
			_fill_signpost(c, sim, Meadow.ID)
		"route":
			_fill_route(c, sim)
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
			c.add_child(_label("Wheat takes %d minutes to grow and gives %d when harvested." % [int(Tuning.WHEAT_GROW / 60.0), Tuning.WHEAT_YIELD], false, Palette.CHALK_DIM, Palette.BODY, true))
			c.add_child(_destructive("Remove this plot", "Click again to remove the plot", "plot:%d" % target.id, func(): game.remove_farm_plot(target)))
		"animal":
			_fill_animal(c, sim, target)
		"pen":
			_fill_pen(c, sim, target)
		"boulder":
			var drops := Defs.words("cobble", Tuning.BOULDER_COBBLE)
			if target.has("ore"):
				drops = Defs.words(Defs.ORES[target.ore].item, Tuning.ORE_YIELD[target.ore])
			c.add_child(_head(Sim.block_name(target), "Drops " + drops))
			if target.des and sim.stuck.any(func(s): return s.focus_kind == "boulder"):
				c.add_child(_reason("Needs a pickaxe"))
			c.add_child(_button("Cancel mining" if target.des else "Mine", func(): game.toggle_mine(target), "Secondary" if target.des else "Primary"))
			_add_keep(c, sim, target)
		"site":
			_fill_site(c, sim, target)


## A village tree or boulder's Keep toggle (issue #177): lumberjacks and stonemasons never take a kept
## one on their own.
func _add_keep(c: Container, sim: Sim, target: Dictionary) -> void:
	if sim.map_id != "village":
		return
	var kept: bool = target.get("keep", false)
	var b := _button("Keep: on" if kept else "Keep", func(): game.toggle_keep(target), "Secondary")
	b.toggle_mode = true
	b.set_pressed_no_signal(kept)
	b.tooltip_text = "Lumberjacks and stonemasons leave it alone unless it's marked to mine."
	c.add_child(b)
	if not kept and sim.protected(target):
		c.add_child(_label("On protected land: gatherers leave it alone.", false, Palette.CHALK_DIM, Palette.CAPTION, true))


## The Craft button appears once a bench is finished; it opens the Craft panel above the toolbar
## (issue #57), with a tab for each station once there's more than one (issue #76).
func _refresh_craft(sim: Sim) -> void:
	var bench = game.craft_bench()
	_tool_btns.craft.visible = bench != null
	_craft_panel.visible = game.craft_menu_open and bench != null
	if not _craft_panel.visible:
		return
	var list: Array = game.benches()
	var sig := "%s|%s|%s|%s|%s|%s|%s|%d" % [list.map(func(b): return b.id), bench, sim.auto_craft, _craft_n, sim.stuck.map(func(x): return x.why), _blocked_sites(sim), _craft_pick, int(_craft_progress(sim, bench) * 10)]
	for k in Palette.ITEM_COLORS:
		sig += "%d," % sim.free_count(k)
	_rebuild(_craft_box, sig, func(c: Container) -> void:
		if list.size() > 1:
			c.add_child(_station_tabs(sim, list, bench))
		_fill_bench(c, sim, bench))


func _blocked_sites(sim: Sim) -> Array:
	return sim.stuck.filter(func(x): return not x.waiting and x.focus_kind == "site").map(func(x): return x.focus_id)


## One tab per bench and fireplace (issue #76); a station with a blocker carries a yellow flag.
func _station_tabs(sim: Sim, list: Array, current: Dictionary) -> Control:
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 4)
	tabs.add_theme_constant_override("v_separation", 4)
	var blocked := _blocked_sites(sim)
	var seen := {}
	for i in list.size():
		var st: Dictionary = list[i]
		seen[st.tpl] = seen.get(st.tpl, 0) + 1
		var name: String = ("Bench" if st.tpl == "bench" else Defs.TEMPLATES[st.tpl].name) + ("" if seen[st.tpl] == 1 else " %d" % seen[st.tpl])
		var on := is_same(st, current)
		var t := _button(name, func(): game.show_craft_bench(i), "" if on else "Secondary")
		t.toggle_mode = true
		t.set_pressed_no_signal(on)
		t.custom_minimum_size = Vector2(0, 36)
		if blocked.has(st.id):
			t.icon = MarkTextures.flag()
			t.add_theme_constant_override("icon_max_width", 12)
		tabs.add_child(t)
	return tabs


## The resident panel's line about jobs (issues #78, #134): their job and level, with the job dropdown,
## and a button to the Village jobs board.
func _add_jobs_summary(c: Container, sim: Sim, r: Dictionary) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.add_child(_label("Job", false, Palette.CHALK_DIM))
	line.add_child(_job_picker(sim, r))
	c.add_child(line)
	if r.role == "all":
		c.add_child(_label("%s founded the village and does any work that's waiting." % r.name, false, Palette.CHALK_DIM, Palette.CAPTION, true))
	var key: String = game.keys.first("jobs")
	var b := _button("Jobs board" + ("  (%s)" % key if key != "" else ""), func(): game.toggle_jobs_board(true), "Secondary")
	b.tooltip_text = "Everyone's jobs and levels"
	c.add_child(b)


## A resident's job (issue #134): a button that opens the job dropdown, or "Everything" for Ada,
## who has none to choose.
func _job_picker(sim: Sim, r: Dictionary) -> Control:
	if r.role == "all":
		var l := _label("Everything", false, Palette.CHALK)
		l.tooltip_text = "%s does every job, and covers whatever nobody else's job does." % r.name
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		return l
	var lv := "" if r.role == "none" else ", level %d" % Sim.level(r, r.role)
	var short := " (no %s)" % Defs.TEMPLATES[Defs.JOB_STATIONS[r.role]].name.to_lower() if sim.needs_station(r) else ""
	var b := _button("%s%s%s  ▾" % [Sim.role_name(r), lv, short], func(): pass, "Secondary")
	b.set_meta("label", "Job: %s" % r.name)
	b.toggle_mode = true
	b.set_pressed_no_signal(_job_for == r.id)
	b.tooltip_text = "Choose %s's job. They do its work, and haul when there's none." % r.name
	b.pressed.connect(func():
		if _job_for == r.id:
			_close_job_drop()
		else:
			_job_for = r.id
			_job_anchor = b.get_global_rect()
			_sigs.erase(_job_list.get_instance_id())
			_refresh_job_drop(sim))
	return b


func _close_job_drop() -> void:
	_job_for = -1
	_job_anchor = Rect2()
	_job_drop.visible = false


## The job dropdown (issue #134): each job with the resident's level in it, best first, and how many
## already have it, then No job. Choosing one closes it.
func _refresh_job_drop(sim: Sim) -> void:
	var r: Dictionary = sim.resident(_job_for) if _job_for >= 0 else {}
	if r.is_empty() or r.role == "all" or not (game.jobs_board_open or game.selection.get("ids", []).has(r.id)):
		_close_job_drop()
		return
	_job_drop.visible = true
	var h := _job_drop.get_combined_minimum_size().y
	var below := _job_anchor.end.y + 4 + h <= get_viewport().get_visible_rect().size.y
	_job_drop.position = Vector2(_job_anchor.position.x, _job_anchor.end.y + 4 if below else _job_anchor.position.y - 4 - h)  # above, when there's no room below
	var counts := {}
	for o in sim.residents:
		counts[o.role] = counts.get(o.role, 0) + 1
	var sig := "%d%s%s%s%s" % [r.id, r.role, r.jobs, counts, _stations_sig(sim)]
	_rebuild(_job_list, sig, func(c: Container) -> void:
		var order: Array = Defs.JOBS.duplicate()
		order.sort_custom(func(a, b): return Sim.level(r, a) > Sim.level(r, b) or (Sim.level(r, a) == Sim.level(r, b) and Defs.JOBS.find(a) < Defs.JOBS.find(b)))
		for jb in order + ["none"]:
			var text := "No job: haul" if jb == "none" else "%s · level %d" % [Defs.JOB_NAMES[jb], Sim.level(r, jb)]
			var n: int = counts.get(jb, 0)
			if jb != "none" and n > 0:
				text += " · %d %s" % [n, _job_people(jb, n)]
			if Defs.JOB_STATIONS.has(jb):  # issue #184: a job needs a free workstation of its own
				var tpl: String = Defs.JOB_STATIONS[jb]
				var free: int = sim.maps.village.sites.filter(func(st): return st.done and st.tpl == tpl and st.get("worker", 0) in [0, r.id]).size()
				var tname: String = Defs.TEMPLATES[tpl].name.to_lower()
				text += " · %d %s free" % [free, tname] if free > 0 else " · no %s" % tname
			var b := _button(text, func():
				game.set_role(r, jb)
				_close_job_drop(), "Secondary")
			b.set_meta("label", "Job choice: " + text)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.set_pressed_no_signal(r.role == jb)
			b.tooltip_text = "Only hauls, when there's something to carry" if jb == "none" else "%s does %s work from a %s of their own, and hauls when there's none or no %s is free" % [r.name, Defs.JOB_NAMES[jb], Defs.TEMPLATES[Defs.JOB_STATIONS[jb]].name.to_lower(), Defs.TEMPLATES[Defs.JOB_STATIONS[jb]].name.to_lower()] if Defs.JOB_STATIONS.has(jb) else "%s does %s work, and hauls when there's none" % [r.name, Defs.JOB_NAMES[jb]]
			c.add_child(b))


## Which workstations exist and who has each (issue #184), for panels that show them.
static func _stations_sig(sim: Sim) -> String:
	return str(sim.maps.village.sites.filter(func(st): return st.done and Defs.JOB_STATIONS.values().has(st.tpl)).map(func(st): return [st.id, st.get("worker", 0)]))


## "farmer", "2 farmers".
static func _job_people(jb: String, n: int) -> String:
	return Defs.JOB_SKILLED[jb] + ("" if n == 1 else "s")


## The Village jobs board (issues #78, #134): a row per resident with their job's dropdown, and a
## column per job with their level in it and a tick of progress to the next level. Their own job's
## cell is lit. A column header counts who has the job, yellow when nobody does (Ada aside).
func _refresh_board(sim: Sim) -> void:
	_board_panel.visible = game.jobs_board_open
	_jobs_btn.set_pressed_no_signal(game.jobs_board_open)
	if not game.jobs_board_open:
		return
	var sig := "%s|%s|%d|%s" % [game.selection, _keys_sig, _job_for, _stations_sig(sim)]
	for r in sim.residents:
		sig += "%d%s%s%s%s%s;" % [r.id, r.name, r.role, r.jobs, r.away, r.map]
	var herds := _wild_herds(sim)
	sig += "|%s|%s" % [herds, sim.herd_floor]
	_rebuild(_board, sig, func(c: Container) -> void:
		var head := HBoxContainer.new()
		var title := _label("Village jobs", true, Palette.CHALK, Palette.HEADING)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		head.add_child(_label("One job each. Idle residents haul.", false, Palette.CHALK_DIM, Palette.CAPTION))
		c.add_child(head)
		var grid := GridContainer.new()
		grid.columns = Defs.JOBS.size() + 2
		grid.add_theme_constant_override("h_separation", 3)
		grid.add_theme_constant_override("v_separation", 3)
		grid.add_child(Control.new())
		var job_head := _label("Job", true, Palette.CHALK, Palette.BODY)
		job_head.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		grid.add_child(job_head)
		for jb in Defs.JOBS:
			var n: int = sim.residents.filter(func(r): return r.role == jb).size()
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 0)
			var name := _label(Defs.JOB_NAMES[jb], true, Palette.CHALK, Palette.BODY)
			name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(name)
			var nobody: bool = n == 0 and jb != "haul"  # everyone hauls when idle
			var count := _label("nobody" if n == 0 else str(n), false, Palette.YELLOW if nobody else Palette.CHALK_DIM, Palette.CAPTION)
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(count)
			var people: String = Defs.JOB_SKILLED[jb].capitalize() + "s"
			col.tooltip_text = "%s: %s. Ada does this work when she can." % [people, "nobody" if n == 0 else str(n)] if jb != "haul" else "%s: %d. Everyone hauls when there's nothing of their own job to do." % [people, n]
			if Defs.JOB_STATIONS.has(jb):  # how many workstations there are for it (issue #184)
				var tpl: String = Defs.JOB_STATIONS[jb]
				var ns: int = sim.maps.village.sites.filter(func(st): return st.done and st.tpl == tpl).size()
				var word: String = Defs.TEMPLATES[tpl].name.to_lower().split(" ")[-1]  # "2 benches", "no composter"
				var built := _label("%d %s" % [ns, word if ns == 1 else word + ("es" if word.ends_with("ch") else "s")] if ns > 0 else "no " + word, false, Palette.CHALK_DIM, Palette.CAPTION)
				built.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				col.add_child(built)
				col.tooltip_text += " Each needs a %s of their own: %d built." % [Defs.TEMPLATES[tpl].name.to_lower(), ns]
			col.mouse_filter = Control.MOUSE_FILTER_STOP
			grid.add_child(col)
		for r in sim.residents:
			var who := _button(r.name + (" (away)" if r.away else (" (on the road)" if r.map == Road.ID else "")), func(): game.focus_on("res", r.id))
			who.icon = _swatch_tex(r.shirt)
			who.alignment = HORIZONTAL_ALIGNMENT_LEFT
			who.custom_minimum_size = Vector2(120, 0)
			who.toggle_mode = true
			who.set_pressed_no_signal(game.selection.get("ids", []).has(r.id))
			who.tooltip_text = "Select %s" % r.name if r.map != Road.ID else "Select %s. %s" % [r.name, _status(sim, r)]
			grid.add_child(who)
			var pick := _job_picker(sim, r)
			pick.custom_minimum_size = Vector2(170, 0)
			pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(pick)
			for jb in Defs.JOBS:
				grid.add_child(_board_cell(r, jb))
		c.add_child(grid)
		_add_herd_floors(c, sim, herds))


## Wild animals in the village by species, penned ones aside (issue #139).
func _wild_herds(sim: Sim) -> Dictionary:
	var out := {}
	for a in sim.maps.village.sheep:
		if a.alive and a.get("pen", 0) == 0:
			out[a.species] = out.get(a.species, 0) + 1
	return out


## The jobs board's herd floors (issue #183): how many of each wild species hunters leave, with a stepper.
func _add_herd_floors(c: Container, sim: Sim, herds: Dictionary) -> void:
	if herds.is_empty():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_label("Hunters leave", true, Palette.CHALK, Palette.BODY))
	for sp in Defs.SPECIES:
		if not herds.has(sp):
			continue
		var sd: Dictionary = Defs.SPECIES[sp]
		var n := sim.floor_of(sp)
		var less := _button("−", func(): game.set_herd_floor(sp, n - 1), "Secondary")
		less.disabled = n <= 0
		less.tooltip_text = "Leave one fewer %s" % sd.one
		row.add_child(less)
		var lbl := _label("%d %s" % [n, sd.one if n == 1 else sd.many], false, Palette.CHALK, Palette.BODY)
		lbl.tooltip_text = "Hunters hunt %s on their own until %d %s left (%d now). Marked ones are hunted anyway." % [sd.many, n, "is" if n == 1 else "are", herds[sp]]
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(lbl)
		var more := _button("+", func(): game.set_herd_floor(sp, n + 1), "Secondary")
		more.tooltip_text = "Leave one more %s" % sd.one
		row.add_child(more)
	c.add_child(row)


## A resident's level in a job on the board, with a tick of progress to the next; lit for their job.
func _board_cell(r: Dictionary, jb: String) -> Control:
	var lv := Sim.level(r, jb)
	var mine: bool = r.role == jb or r.role == "all"
	var p := PanelContainer.new()
	p.set_meta("cell", "%d:%s" % [r.id, jb])
	p.custom_minimum_size = Vector2(66, 40)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.SLATE_DEEP if mine else Color(Palette.SLATE_DEEP, 0.0)
	sb.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := _label("Lv %d" % lv, mine, Palette.CHALK if mine else Palette.CHALK_DIM, Palette.BODY)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var bar := _bar(Sim.level_progress(r, jb), Palette.GREEN)
	bar.custom_minimum_size = Vector2(46, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bar)
	p.add_child(v)
	var xp: int = r.jobs[jb].get("xp", 0)
	var lv_text := "level %d, the top level" % lv if lv > Tuning.SKILL_LEVELS.size() else "level %d: %d of %d points to level %d" % [lv, xp, Tuning.SKILL_LEVELS[lv - 1], lv + 1]
	p.tooltip_text = "%s, %s: %s%s." % [r.name, Defs.JOB_NAMES[jb], lv_text, ". Their job" if r.role == jb else ""]
	return p


## What armor a resident wears (issue #140), and how much of the hazards' harm it turns aside.
func _add_armor_row(c: Container, r: Dictionary) -> void:
	var worn := Sim.armor_worn(r)
	if worn.is_empty():
		c.add_child(_row("Armor", "None"))
		return
	c.add_child(_row("Armor", "%d%% guard" % roundi(Sim.protection(r) * 100.0) + (", full set" if worn.size() == Defs.ARMOR_SLOTS.size() else "")))
	var parts: PackedStringArray = []
	for slot in Defs.ARMOR_SLOTS:
		if worn.has(slot):
			parts.append("%s, %d %s" % [Defs.SLOT_NAMES[slot], worn[slot].dur, "use" if worn[slot].dur == 1 else "uses"])
	c.add_child(_label("%s. Turns aside that share of injuries from hazards, and wears a use each time one strikes." % "; ".join(parts), false, Palette.CHALK_DIM, Palette.CAPTION, true))


## A resident's axe or pickaxe, with Equip to choose another one (lying about or stockpiled).
func _add_tool_row(c: Container, sim: Sim, r: Dictionary, kind: String) -> void:
	var t = r[kind]
	var none := "Bare hands" if kind == "axe" else "None"
	var text: String = _tool_text(t) if t != null else ("Broke" if r.broken[kind] else none)
	var h := _row("Axe" if kind == "axe" else "Pickaxe", text)
	var spare := sim.tool_items(kind, 0)
	if not spare.is_empty() or equip_kind == kind:
		var b := _button("Close" if equip_kind == kind else "Equip", func(): equip_kind = "" if equip_kind == kind else kind, "Secondary")
		b.add_theme_font_size_override("font_size", Palette.CAPTION)
		b.tooltip_text = "Choose which %s %s uses" % ["axe" if kind == "axe" else "pickaxe", r.name]
		h.add_child(b)
	c.add_child(h)
	if t != null and r.kept[kind]:
		var k := HBoxContainer.new()
		var l := _label("Kept until it breaks.", false, Palette.CHALK_DIM, Palette.CAPTION)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_child(l)
		var auto := _button("Use the best", func(): game.release_kept_tool(r, kind), "Secondary")
		auto.add_theme_font_size_override("font_size", Palette.CAPTION)
		auto.tooltip_text = "Let %s swap it for a better one when there is one" % r.name
		k.add_child(auto)
		c.add_child(k)
	if equip_kind != kind:
		return
	if spare.is_empty():
		c.add_child(_label("No other %s is lying about or stockpiled." % ("axe" if kind == "axe" else "pickaxe"), false, Palette.CHALK_DIM, Palette.CAPTION, true))
		return
	spare.sort_custom(func(a, b): return Defs.ITEMS[a.type].tier > Defs.ITEMS[b.type].tier or (a.type == b.type and a.dur > b.dur))
	for st in spare:
		var where := "in the stockpile" if sim.in_zone(st.cell) else "on the ground"
		var it: Dictionary = Defs.ITEMS[st.type]
		var b := _button("%s, %d %s left, %s" % [it.one.substr(0, 1).to_upper() + it.one.substr(1), st.dur, "use" if st.dur == 1 else "uses", where], func():
			equip_kind = ""
			game.equip_tool(r, st))
		b.theme_type_variation = "Secondary"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", Palette.CAPTION)
		c.add_child(b)


## What a resident is doing, for panel headings.
func _status(sim: Sim, r: Dictionary) -> String:
	if r.away:
		return _road_text(sim, r)
	if sim.on_road(r) and r.job != null and not sim.cart.get("riders", []).has(r.id):  # walking the road map (issue #118)
		return "%s, about %d s" % [r.job.label, ceili(sim.road_eta(r))]
	if r.map == Road.ID and not sim.on_road(r) and r.job != null:  # out working on the road (issue #122)
		return "On the road: %s" % r.job.label.to_lower()
	return r.job.label if r.job != null else "Idle"


## "On the way to the meadow, 22 s", "On the way home, 22 s" or "On the road home, 22 s".
static func _road_text(sim: Sim, r: Dictionary) -> String:
	var meadow: bool = sim.expedition.get("dest", "") == Meadow.ID
	if r.trip == "village":
		return "On the %s home, %d s" % ["way" if meadow else "road", ceili(sim.back_in(r))]
	return "On the %s to the %s, %d s" % ["way" if meadow else "road", sim.get_map(r.trip).name.to_lower(), ceili(sim.back_in(r))]


## An animal (issues #42, #138, #139): what it drops, whether it's penned, fed or young, and the
## Hunt and Lead buttons.
func _fill_animal(c: Container, sim: Sim, a: Dictionary) -> void:
	var sp: Dictionary = Defs.SPECIES[a.species]
	var secs := func(at: int) -> int: return maxi(1, ceili(float(at - sim.tick) / Tuning.TPS))
	if a.get("young", false):
		c.add_child(_head(sp.young.capitalize(), "Grows up in %d s" % secs.call(a.grown_at)))
		c.add_child(_label("Young ones can't be hunted. Grown, it drops %s." % Defs.drops_text(a.species), false, Palette.CHALK_DIM, Palette.BODY, true))
	else:
		c.add_child(_head(sp.name, "Drops " + Defs.drops_text(a.species)))
	var pens: bool = sim.on_map(game.view_map, func(): return not sim.m.pens.is_empty())
	if a.get("pen", 0) != 0:
		var note := "In a pen."
		if a.get("fed_at", -1) >= 0:
			note = "In a pen, fed: a young one in about %d s, once its mate is fed too." % secs.call(a.fed_at + int(Tuning.BREED_TIME * Tuning.TPS))
		elif a.get("cool_until", 0) > sim.tick:
			note = "In a pen. It can be fed again in %d s." % secs.call(a.cool_until)
		elif not a.get("young", false):
			note = "In a pen. Fed wheat with another %s, it has a young one." % sp.one
		c.add_child(_label(note, false, Palette.CHALK_DIM, Palette.BODY, true))
	if a.claim != 0:
		var who: Dictionary = sim.resident(a.claim)
		var doing := "hunting it"
		if who.get("job") != null:
			doing = {"lead": "leading it to a pen", "feed": "feeding it"}.get(who.job.kind, doing)
		c.add_child(_label("%s is %s." % [who.get("name", "Someone"), doing], false, Palette.CHALK_DIM))
	elif a.get("lead", false):
		c.add_child(_label("Marked to lead into a pen. The party does it at the meadow.", false, Palette.CHALK_DIM, Palette.BODY, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if not a.get("young", false):
		row.add_child(_button("Cancel hunt" if a.des else "Hunt", func(): game.toggle_hunt(a), "Secondary" if a.des else "Primary"))
	if pens and a.get("pen", 0) == 0:
		row.add_child(_button("Don't lead" if a.get("lead", false) else "Lead to a pen", func(): game.toggle_lead(a), "Secondary"))
	if row.get_child_count() > 0:
		c.add_child(row)


## A pen (issue #139): its fences, or what's in it, and how breeding works.
func _fill_pen(c: Container, sim: Sim, p: Dictionary) -> void:
	var edge := Sim.pen_edge(p).size()
	c.add_child(_head("Pen", "%d×%d, room for %d" % [p.rect.size.x, p.rect.size.y, Sim.pen_room(p)]))
	if not Sim.pen_done(p):
		var left: int = (edge - p.built.size()) * Tuning.FENCE_STICKS
		c.add_child(_row("Fences built", "%d / %d" % [p.built.size(), edge]))
		c.add_child(_bar(float(p.built.size()) / edge, Palette.BLUE))
		c.add_child(_label("A party builds it with sticks from its packs: %s more. Plan a meadow trip with sticks." % Defs.words("stick", left), false, Palette.CHALK_DIM, Palette.BODY, true))
	else:
		var animals: Array = sim.on_map(game.view_map, sim.penned.bind(p))
		var parts: PackedStringArray = []
		for sp in ["cow", "pig", "sheep"]:
			var grown := animals.filter(func(a): return a.species == sp and not a.get("young", false)).size()
			var young := animals.filter(func(a): return a.species == sp and a.get("young", false)).size()
			if grown > 0:
				parts.append(Defs.animals(sp, grown))
			if young > 0:
				parts.append("%d %s" % [young, Defs.SPECIES[sp].young if young == 1 else Defs.SPECIES[sp].youngs])
		c.add_child(_label(", ".join(parts) + "." if not parts.is_empty() else "Empty. Mark animals with Gather ▸ Lead to a pen, and the party walks them in.", false, Palette.CHALK, Palette.BODY, true))
		var fed := animals.filter(func(a): return a.get("fed_at", -1) >= 0).size()
		if fed > 0:
			c.add_child(_label("%d fed, a young one on the way." % fed, false, Palette.WHEAT, Palette.BODY))
		c.add_child(_label("A pair of one kind fed %s each has a young one after %d s, and can be fed again after %d min. Young ones grow up in %d min." % [Defs.words("wheat", Tuning.FEED_WHEAT), roundi(Tuning.BREED_TIME), roundi(Tuning.BREED_COOLDOWN / 60.0), roundi(Tuning.GROW_TIME / 60.0)], false, Palette.CHALK_DIM, Palette.CAPTION, true))
	c.add_child(_destructive("Take the pen down", "Click again to take it down. Its animals go free", "pen:%d" % p.id, func(): game.remove_pen(p)))


## A signpost to an adventure (issue #136): what's past it, and the way to plan a trip there.
func _fill_signpost(c: Container, sim: Sim, id: String) -> void:
	var row: Dictionary = {}
	for a in sim.adventures():
		if a.id == id:
			row = a
	var mp := sim.get_map(id)
	c.add_child(_head("To the %s" % mp.name.to_lower(), row.get("status", "Nobody knows where it goes")))
	if row.is_empty():
		c.add_child(_label("An expedition board would have word of what's past this signpost.", false, Palette.CHALK_DIM, Palette.BODY, true))
		return
	c.add_child(_label("%s. About %d s walk each way." % [row.what, roundi(row.travel)], false, Palette.CHALK, Palette.BODY, true))
	if id == Meadow.ID and mp.visited:
		var hs := sim.herds()
		var parts: PackedStringArray = []
		for sp in ["cow", "pig", "sheep"]:
			parts.append(Defs.animals(sp, hs.get(sp, 0)))
		c.add_child(_label("%s. Each kind grows back on its own." % ", ".join(parts), false, Palette.CHALK_DIM, Palette.BODY, true))
	var b := _button("Plan a trip to the %s" % mp.name.to_lower(), func(): game.open_adventure(id), "Primary")
	b.disabled = row.locked
	b.tooltip_text = "One expedition at a time" if row.locked else "Open the expedition board on this adventure"
	c.add_child(b)


func _tool_text(t: Dictionary) -> String:
	return "%s, %d %s left" % [Defs.TIER_NAMES[t.tier], t.dur, "use" if t.dur == 1 else "uses"]


func _fill_site(c: Container, sim: Sim, s: Dictionary) -> void:
	var tpl: Dictionary = Defs.TEMPLATES[s.tpl]
	var reasons := sim.stuck.filter(func(x): return x.focus_kind == "site" and x.focus_id == s.id)
	if s.tpl == "track":  # a segment of the line (issues #121, #122)
		c.add_child(_head("Track", Road.SEGMENTS[s.seg].name))
		if s.done:
			c.add_child(_label("Laid. Carts run at full speed here.", false, Palette.CHALK_DIM, Palette.BODY, true))
			return
		var laid: int = s.get("laid", 0)
		c.add_child(_row("Rails laid", "%d / %d" % [laid, Tuning.RAILS_PER_SEGMENT], false))
		c.add_child(_bar(float(laid) / Tuning.RAILS_PER_SEGMENT))
		c.add_child(_row("Rails here", str(s.store.get("rail", 0))))
		for x in reasons:
			c.add_child(_reason(x.why))
		if sim.next_track() != s.seg:
			c.add_child(_label("Waiting its turn: track is laid from the village end.", false, Palette.CHALK_DIM, Palette.BODY, true))
		if s.builder:
			c.add_child(_label("%s is laying it." % sim.resident(s.builder).name, false, Palette.CHALK_DIM))
		c.add_child(_destructive("Cancel this segment", "Click again to cancel it", "site:%d" % s.id, func(): game.cancel_site(s)))
		return
	if s.tpl == "station" and s.done:  # issue #123
		_fill_station(c, sim, s)
		return
	if not s.done:
		var st := sim.current_stage(s)
		var stage_line: String = "Stage %d of %d: %s" % [s.stage + 1, tpl.stages.size(), st.name.to_lower()] if tpl.stages.size() > 1 else "Blueprint"
		c.add_child(_head(tpl.name, stage_line))
		if not sim.footprint_clear(s):
			c.add_child(_label("Clearing the ground first: %s." % Sim.clearing_text(sim.site_obstacles(s)), false, Palette.CHALK, Palette.BODY, true))
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
			c.add_child(_label("%s next: %s." % [nxt.name, Defs.cost_text(nxt.cost)], false, Palette.CHALK_DIM, Palette.BODY, true))
		c.add_child(_destructive("Cancel blueprint", "Click again to cancel the blueprint", "site:%d" % s.id, func(): game.cancel_site(s)))
		return
	if s.tpl == "storehouse":  # issue #189
		_fill_storehouse(c, sim, s)
		return
	if s.tpl == "house":
		var owner := sim.resident(s.owner)
		var line := "Home of %s." % owner.name if not owner.is_empty() else ("Empty. A traveler should arrive soon." if sim.arrival_at >= 0 else "Empty.")
		c.add_child(_label("House", true, Palette.CHALK, Palette.TITLE))
		c.add_child(_label(line, false, Palette.CHALK_DIM, Palette.BODY, true))
		return
	if s.tpl == "board":  # its planner opens above the toolbar (issue #106)
		c.add_child(_label(tpl.name, true, Palette.CHALK, Palette.TITLE))
		c.add_child(_label(_board_status(sim), false, Palette.CHALK_DIM, Palette.BODY, true))
		for x in reasons:
			c.add_child(_reason(x.why) if not x.waiting else _label(x.why, false, Palette.CHALK_DIM, Palette.BODY, true))
		if not game.planner_open:
			c.add_child(_button("Open the planner", func(): game.open_planner(), "Primary"))
		return
	if not Sim.work_of(s).is_empty():  # a chopping block or mason's bench (issue #177)
		_fill_workstation(c, sim, s, reasons)
		return
	if not Sim.is_station(s):  # the toolsmith's bench, composter, lodge or builder's table (issue #184)
		c.add_child(_label(sim.station_title(s), true, Palette.CHALK, Palette.TITLE))
		c.add_child(_label(_station_line(sim, s), false, Palette.CHALK_DIM, Palette.BODY, true))
		for x in reasons:
			c.add_child(_reason(x.why) if not x.waiting else _label(x.why, false, Palette.CHALK_DIM, Palette.BODY, true))
		return
	# A finished bench or fireplace: a short summary here. Its recipes and queue live only in the
	# Craft panel on the right, which selecting it opens.
	c.add_child(_label(sim.station_title(s), true, Palette.CHALK, Palette.TITLE))
	c.add_child(_label(_station_line(sim, s), false, Palette.CHALK_DIM, Palette.CAPTION, true))
	c.add_child(_label(_bench_status(sim, s), false, Palette.CHALK_DIM, Palette.BODY, true))
	for x in reasons:
		c.add_child(_reason(x.why))
	if not game.craft_menu_open:
		c.add_child(_button("Open the craft menu", func(): game.open_craft_menu(s), "Primary"))


## A finished storehouse (issue #189): its chests, how full they are, and what's in them.
func _fill_storehouse(c: Container, sim: Sim, s: Dictionary) -> void:
	c.add_child(_label("Storehouse", true, Palette.CHALK, Palette.TITLE))
	var slots := Sim.store_slots(s)
	var used := slots.filter(func(k): return sim.items.has(k)).size()
	var chests: int = s.get("chests", 0)
	c.add_child(_row("Chests", "%d / %d" % [chests, Tuning.CHESTS], false))
	if chests > 0:
		c.add_child(_row("Stacks", "%d / %d" % [used, slots.size()], false))
		c.add_child(_bar(float(used) / slots.size()))
	var held := {}
	for k in slots:
		var it = sim.items.get(k)
		if it != null:
			held[it.type] = held.get(it.type, 0) + it.n
	if not held.is_empty():
		var parts: PackedStringArray = []
		for t in held:
			parts.append(Defs.words(t, held[t]))
		c.add_child(_label("Holds " + ", ".join(parts) + ".", false, Palette.CHALK, Palette.BODY, true))
	var more := "Haulers bring loose things here first; the stockpile takes what doesn't fit." if chests > 0 else "Craft a chest at the bench (8 planks): a hauler carries it in, and it holds %d stacks of anything." % Tuning.CHEST_STACKS
	if chests > 0 and chests < Tuning.CHESTS:
		more += " Each chest crafted at the bench adds %d stacks, up to %d chests." % [Tuning.CHEST_STACKS, Tuning.CHESTS]
	c.add_child(_label(more, false, Palette.CHALK_DIM, Palette.CAPTION, true))
	for x in sim.stuck.filter(func(x): return x.focus_kind == "site" and x.focus_id == s.id):
		c.add_child(_reason(x.why))


## A finished chopping block or mason's bench (issue #177): its pile, its keep-stock target with a
## stepper, who works it, and what holds it up.
func _fill_workstation(c: Container, sim: Sim, s: Dictionary, reasons: Array) -> void:
	var wk := Sim.work_of(s)
	var item: Dictionary = Defs.ITEMS[wk.item]
	c.add_child(_label(sim.station_title(s), true, Palette.CHALK, Palette.TITLE))
	var n := sim.pile_count(s)
	c.add_child(_row("Pile", "%d / %d %s" % [n, Tuning.WORK_STORE, item.many], false))
	c.add_child(_bar(float(n) / Tuning.WORK_STORE))
	var keep := HBoxContainer.new()
	keep.add_theme_constant_override("separation", 6)
	var less := _button("−", func(): game.set_keep_stock(s, s.keep - Tuning.KEEP_STEP), "Secondary")
	less.disabled = s.keep <= 0
	less.tooltip_text = "Keep %d fewer" % Tuning.KEEP_STEP
	keep.add_child(less)
	var lbl := _label("Keep %d %s" % [s.keep, item.many], false, Palette.CHALK, Palette.BODY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keep.add_child(lbl)
	var more := _button("+", func(): game.set_keep_stock(s, s.keep + Tuning.KEEP_STEP), "Secondary")
	more.tooltip_text = "Keep %d more" % Tuning.KEEP_STEP
	keep.add_child(more)
	c.add_child(keep)
	c.add_child(_label("The village has %d. %ss %s within %d cells on their own until it has %d." % [
		sim.free_count(wk.item), Defs.JOB_NAMES[wk.job], "fell trees" if wk.kind == "tree" else "break boulders",
		int(Tuning.WORK_RADIUS), s.keep], false, Palette.CHALK_DIM, Palette.CAPTION, true))
	c.add_child(_label(_station_line(sim, s), false, Palette.CHALK_DIM, Palette.CAPTION, true))
	for x in reasons:
		c.add_child(_reason(x.why) if not x.waiting else _label(x.why, false, Palette.CHALK_DIM, Palette.BODY, true))
	c.add_child(_rule())
	c.add_child(_label(_bench_status(sim, s), false, Palette.CHALK_DIM, Palette.BODY, true))
	c.add_child(_make_keep_row(sim, s))
	if not game.craft_menu_open:
		c.add_child(_button("Open the craft menu", func(): game.open_craft_menu(s), "Secondary"))


## A workstation's standing order (issue #178): "Keep 20 planks", with − and +. 0 is off.
func _make_keep_row(sim: Sim, s: Dictionary) -> Control:
	var rec := Defs.recipe(Defs.TEMPLATES[s.tpl].makes)
	var out: String = rec.out.keys()[0]
	var v := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var n: int = s.get("make_keep", 0)
	var less := _button("−", func(): game.set_make_keep(s, n - Tuning.MAKE_STEP), "Secondary")
	less.disabled = n <= 0
	less.tooltip_text = "Keep %d fewer" % Tuning.MAKE_STEP
	row.add_child(less)
	var lbl := _label("Keep %s" % Defs.words(out, n) if n > 0 else "Make %s: off" % Defs.ITEMS[out].many, false, Palette.CHALK, Palette.BODY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	var more := _button("+", func(): game.set_make_keep(s, n + Tuning.MAKE_STEP), "Secondary")
	more.tooltip_text = "Keep %d more" % Tuning.MAKE_STEP
	row.add_child(more)
	v.add_child(row)
	var inp: String = rec.inp.keys()[0]
	v.add_child(_label("The village has %d. While it has fewer, %ss make them here from %s." % [sim.free_count(out), Defs.JOB_NAMES[Sim.recipe_job(rec)].to_lower(), Defs.ITEMS[inp].many] if n > 0 else "Nothing is made here unless you queue it.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
	return v


## Who works from a workstation (issue #184): "Bram works here as the farmer.", or that it's free.
func _station_line(sim: Sim, s: Dictionary) -> String:
	var job: String = Defs.JOB_STATIONS.find_key(s.tpl)
	var who := sim.resident(s.get("worker", 0))
	var what: String = {"toolsmith": " Tools are made at the crafting bench; the toolsmith keeps spares in stock.",
		"farm": " The farmer tends any farm plot.", "hunt": " The hunter hunts marked animals.", "build": " The builder puts up blueprints."}.get(job, "")
	if not who.is_empty():
		return "%s works here as the %s.%s" % [who.name, Defs.JOB_SKILLED[job], what]
	return "Free: give someone the %s job and they'll claim it. Ada works anywhere without one.%s" % [Defs.JOB_NAMES[job], what]


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


## The station panel (issue #95), laid out like a crafting table's screen: a recipe book of result
## icons, the chosen recipe's crafting grid (a furnace at the fireplace), an arrow to the result with
## Queue, then the queue as a hotbar and what's on hand. The grid only shows the recipe: residents
## fetch the ingredients, so nothing is dropped into it. What's doing and stuck comes first, and the
## top part never changes size, so the Queue control stays put as the queue changes (#57, #76).
func _fill_bench(c: Container, sim: Sim, s: Dictionary) -> void:
	var reasons := sim.stuck.filter(func(x): return x.focus_kind == "site" and x.focus_id == s.id)
	if game.benches().size() < 2:  # with tabs, the pressed tab names the station
		c.add_child(_label(Defs.TEMPLATES[s.tpl].name, true, Palette.CHALK, Palette.HEADING))
	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 2)
	status.custom_minimum_size = Vector2(0, 44)
	status.add_child(_label(_bench_status(sim, s), false, Palette.CHALK, Palette.BODY, true))
	for x in reasons.slice(0, 1):
		status.add_child(_reason(x.why) if not x.waiting else _label(x.why, false, Palette.CHALK_DIM, Palette.BODY, true))
	c.add_child(status)
	var recipes: Array = Defs.recipes_at(s.tpl)
	var rec: Dictionary = Defs.recipe(_craft_pick.get(s.tpl, recipes[0].id))
	if rec.is_empty() or not recipes.has(rec):
		rec = recipes[0]
	var table := HBoxContainer.new()
	table.add_theme_constant_override("separation", 14)
	var book := GridContainer.new()
	book.columns = 2
	book.add_theme_constant_override("h_separation", 3)
	book.add_theme_constant_override("v_separation", 3)
	book.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for r in recipes:
		book.add_child(_book_slot(sim, s, r, is_same(r, rec)))
	table.add_child(book)
	table.add_child(_furnace(sim, s, rec) if s.tpl == "fireplace" else _crafting_grid(sim, s, rec))
	table.add_child(_arrow())
	var out_type: String = rec.out.keys()[0]
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(_slot(out_type, rec.out[out_type], 46))
	right.add_child(_label(rec.name, true, Palette.CHALK, Palette.BODY, true))
	right.add_child(_queue_control(s, rec))
	table.add_child(right)
	c.add_child(table)
	c.add_child(_rule())
	var bar := _hotbar(sim, s)
	if s.tpl == "bench":
		bar.tooltip_text = "Missing planks and sticks are queued automatically." if sim.auto_craft else "Once Ada’s house is finished, the bench queues the planks and sticks a recipe needs."
	c.add_child(bar)
	c.add_child(_on_hand(sim, s))
	if Defs.TEMPLATES[s.tpl].has("makes"):
		c.add_child(_make_keep_row(sim, s))
	if s.tpl == "fireplace":
		var on: bool = s.get("keep_meals", true)
		var keep := _button("Keep %d meals in stock: %s" % [Tuning.MEAL_STOCK, "on" if on else "off"], func(): game.set_keep_meals(s, not on), "Secondary")
		keep.toggle_mode = true
		keep.set_pressed_no_signal(on)
		keep.tooltip_text = "While stored bread and cooked mutton are fewer than %d, cooks make whichever the wheat, mutton and logs allow." % Tuning.MEAL_STOCK
		c.add_child(keep)



## How many of an item the station could use now: in it, on the way, or lying about.
func _have(sim: Sim, s: Dictionary, k: String) -> int:
	return s.store.get(k, 0) + s.incoming.get(k, 0) + sim.free_count(k)


func _short(sim: Sim, s: Dictionary, rec: Dictionary) -> Array:
	return rec.inp.keys().filter(func(k): return _have(sim, s, k) < rec.inp[k])


## A square slot: an inset with an item's icon and, past 1, its count in the corner. An outline
## colour marks it (yellow: short of it).
func _slot(type: String, n := 1, size := 40, outline := Palette.CHALK_DIM, dim := false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(Palette.SLATE_DEEP, 3, 0, outline)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(size, size)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	if type != "":
		var t := TextureRect.new()
		t.texture = ItemIcons.icon(type)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(size - 8, size - 8)
		t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.modulate = Color(1, 1, 1, 0.45) if dim else Color.WHITE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(t)
		p.tooltip_text = Defs.words(type, n)
	if n > 1:
		var count := _label("%d" % n, true, Palette.CHALK, Palette.CAPTION)
		count.add_theme_color_override("font_outline_color", Palette.SLATE_DEEP)
		count.add_theme_constant_override("outline_size", 4)
		count.size_flags_horizontal = Control.SIZE_SHRINK_END
		count.size_flags_vertical = Control.SIZE_SHRINK_END
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(count)
	return p


## A recipe in the book: its result's icon. Dimmed with a yellow corner when there isn't enough on
## hand for one; pressed while it's the one shown.
func _book_slot(sim: Sim, s: Dictionary, rec: Dictionary, chosen: bool) -> Button:
	var out_type: String = rec.out.keys()[0]
	var short := _short(sim, s, rec)
	var b := _button("", func(): _craft_pick[s.tpl] = rec.id, "Secondary")
	b.set_meta("label", rec.name)
	b.toggle_mode = true
	b.set_pressed_no_signal(chosen)
	b.custom_minimum_size = Vector2(38, 38)
	var t := TextureRect.new()
	t.texture = ItemIcons.icon(out_type)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	t.modulate = Color(1, 1, 1, 0.45) if not short.is_empty() else Color.WHITE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(t)
	if not short.is_empty():
		var corner := ColorRect.new()
		corner.color = Palette.YELLOW
		corner.size = Vector2(8, 8)
		corner.position = Vector2(28, 2)
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(corner)
	b.tooltip_text = rec.name + (" (not enough %s on hand for one)" % ", ".join(short.map(func(k): return Defs.ITEMS[k].many)) if not short.is_empty() else "")
	return b


## The chosen bench recipe laid out on a 3×3 grid. Slots the village is short of are outlined yellow.
func _crafting_grid(sim: Sim, s: Dictionary, rec: Dictionary) -> Control:
	var short := _short(sim, s, rec)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 3)
	g.add_theme_constant_override("v_separation", 3)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for row in rec.pattern:
		for ch in row:
			var item: String = Defs.PATTERN_KEYS.get(ch, "")
			g.add_child(_slot(item, 1, 34, Palette.YELLOW if short.has(item) else Palette.CHALK_DIM))
	return g


## The fireplace's screen, like a furnace: what's cooked above, the fuel below, a flame between.
func _furnace(sim: Sim, s: Dictionary, rec: Dictionary) -> Control:
	var short := _short(sim, s, rec)
	var fuel: String = rec.get("fuel", "")
	var food: String = rec.inp.keys().filter(func(k): return k != fuel)[0]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(_slot(food, rec.inp[food], 38, Palette.YELLOW if short.has(food) else Palette.CHALK_DIM))
	var flame := Control.new()
	flame.custom_minimum_size = Vector2(38, 22)
	flame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flame.draw.connect(func():
		var pts := PackedVector2Array([Vector2(19, 2), Vector2(28, 14), Vector2(24, 21), Vector2(14, 21), Vector2(10, 14)])
		flame.draw_colored_polygon(pts, Palette.SLATE_DEEP)
		flame.draw_colored_polygon(PackedVector2Array([Vector2(19, 6), Vector2(25, 14), Vector2(22, 19), Vector2(16, 19), Vector2(13, 14)]), Palette.YELLOW if fuel != "" else Palette.CHALK_DIM))
	v.add_child(flame)
	var fuel_slot := _slot(fuel, 1, 38, Palette.YELLOW if short.has(fuel) else Palette.CHALK_DIM)
	fuel_slot.tooltip_text = "Fuel: " + Defs.words(fuel, 1) if fuel != "" else "No fuel needed"
	v.add_child(fuel_slot)
	return v


## The chalk arrow from the grid to the result.
func _arrow() -> Control:
	var a := Control.new()
	a.custom_minimum_size = Vector2(28, 28)
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.draw.connect(func():
		a.draw_line(Vector2(2, 14), Vector2(18, 14), Palette.CHALK, 4)
		a.draw_colored_polygon(PackedVector2Array([Vector2(16, 5), Vector2(27, 14), Vector2(16, 23)]), Palette.CHALK))
	return a


## − Queue n + (issue #76): the count lives in _craft_n, and every button reads it when pressed, so
## quick clicks between panel rebuilds all count; they relabel the control at once.
func _queue_control(s: Dictionary, rec: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var n: int = _craft_n.get(rec.id, 1)
	var q := _button("Queue %d" % n, func(): game.queue_craft(s, rec.id, _craft_n.get(rec.id, 1)), "Primary")
	q.custom_minimum_size = Vector2(84, 0)
	var less := _button("−", func(): pass, "Secondary")
	var more := _button("+", func(): pass, "Secondary")
	var step := func(by: int) -> void:
		var m: int = clampi(_craft_n.get(rec.id, 1) + by, 1, CRAFT_MAX)
		_craft_n[rec.id] = m
		q.text = "Queue %d" % m
		less.disabled = m <= 1
		more.disabled = m >= CRAFT_MAX
	less.pressed.connect(step.bind(-1))
	more.pressed.connect(step.bind(1))
	less.disabled = n <= 1
	more.disabled = n >= CRAFT_MAX
	less.tooltip_text = "Queue fewer"
	more.tooltip_text = "Queue more"
	less.custom_minimum_size = Vector2(30, 0)
	more.custom_minimum_size = Vector2(30, 0)
	for b in [less, q, more]:
		h.add_child(b)
	return h


## The queue as a hotbar: a slot per entry (click to remove), the first filling as it's made. The
## toolsmith's and auto-queued entries carry a small letter. Empty slots fill out the bar.
func _hotbar(sim: Sim, s: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(_label("Queue" if not s.queue.is_empty() else "Queue: nothing yet. Pick a recipe above and queue it.", true if not s.queue.is_empty() else false, Palette.CHALK if not s.queue.is_empty() else Palette.CHALK_DIM, Palette.BODY))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	var shown := mini(s.queue.size(), HOTBAR)
	for i in shown:
		var rec := Defs.recipe(s.queue[i])
		var out_type: String = rec.out.keys()[0]
		var b := _button("", func(): game.unqueue_craft(s, i), "Secondary")
		var mark := ""
		if str(s.autoq[i]) == "toolsmith":
			mark = "T"
		elif s.autoq[i]:
			mark = "A"
		b.set_meta("label", "queued %s" % rec.name)
		b.custom_minimum_size = Vector2(36, 36)
		var t := TextureRect.new()
		t.texture = ItemIcons.icon(out_type)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(t)
		if mark != "":
			var m := _label(mark, true, Palette.CHALK_DIM, Palette.CAPTION)
			m.position = Vector2(3, 0)
			m.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(m)
		if i == 0 and s.crafter != 0 and s.crafting == rec.name:
			var fill := _bar(_craft_progress(sim, s), Palette.GREEN)
			fill.position = Vector2(4, 30)
			fill.size = Vector2(28, 3)
			fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(fill)
		b.tooltip_text = "%s%s. Click to remove." % [rec.name, {"T": " (toolsmith)", "A": " (auto)"}.get(mark, "")]
		bar.add_child(b)
	for i in range(shown, HOTBAR):
		bar.add_child(_slot("", 1, 36, Color(Palette.CHALK_DIM, 0.35)))
	v.add_child(bar)
	if s.queue.size() > HOTBAR:
		v.add_child(_label("and %d more" % (s.queue.size() - HOTBAR), false, Palette.CHALK_DIM, Palette.CAPTION))
	return v


const HOTBAR := 8


## How far along the craft at the head of the queue is, 0 to 1.
func _craft_progress(sim: Sim, s: Dictionary) -> float:
	var r := sim.resident(s.crafter)
	return clampf(r.progress, 0.0, 1.0) if not r.is_empty() and r.progress >= 0 else 0.0


## The village's stock of this station's ingredients, read-only, like an inventory row.
func _on_hand(sim: Sim, s: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var l := _label("On hand", true, Palette.CHALK, Palette.BODY)
	l.custom_minimum_size = Vector2(70, 0)
	h.add_child(l)
	var items: Array = []
	for rec in Defs.recipes_at(s.tpl):
		for k in rec.inp:
			if not items.has(k):
				items.append(k)
	for k in items:
		var n := _have(sim, s, k)
		var slot := _slot(k, maxi(n, 1), 36, Palette.CHALK_DIM, n == 0)
		if n <= 1:  # show 1 and 0 too: a slot with no number would read as one
			var count := _label("%d" % n, true, Palette.CHALK if n > 0 else Palette.CHALK_DIM, Palette.CAPTION)
			count.add_theme_color_override("font_outline_color", Palette.SLATE_DEEP)
			count.add_theme_constant_override("outline_size", 4)
			count.size_flags_horizontal = Control.SIZE_SHRINK_END
			count.size_flags_vertical = Control.SIZE_SHRINK_END
			slot.add_child(count)
		slot.tooltip_text = "%s on hand" % Defs.words(k, n)
		h.add_child(slot)
	return h


# ---------------------------------------------------------------- cursor hint

func show_hint(text: String, at: Vector2, color := Palette.CHALK) -> void:
	_hint.visible = text != ""
	if text == "":
		return
	_hint.text = text
	_hint.add_theme_color_override("font_color", color)
	var wide := _hint.get_combined_minimum_size().x
	var room := get_viewport().get_visible_rect().size.x - 8.0
	_hint.position = Vector2(minf(at.x + 18.0, maxf(8.0, room - wide)), at.y + 14.0)  # never off the right edge
	_hint.size = Vector2.ZERO


# ---------------------------------------------------------------- the expedition planner (issues #105-#107)

## The planner opens above the toolbar when the board is selected. With no expedition it draws up a
## plan; while one is packing it shows the packing and Depart; while one is out it says so.
func _refresh_planner(sim: Sim) -> void:
	var board := sim.expedition_board()
	_plan_panel.visible = game.planner_open and not board.is_empty()
	if not _plan_panel.visible:
		return
	_plan_panel.custom_minimum_size.x = 0 if sim.expedition.is_empty() else 400
	var dest: String = sim.expedition.get("dest", game.plan.get("dest", OldMine.ID))
	var sig := "%s|%s|%s|%s|%s|%s|%s|%s" % [game.plan, sim.expedition, board.store, board.get("report", []), sim.stuck.map(func(x): return x.why), sim.site_report(dest), game.adventure, sim.adventures()]
	for r in sim.residents:
		sig += "%d%s%s%s%d%d%s%s;" % [r.id, sim.cant_join(r), sim.at_board(r), r.pick, int(r.hunger / 10), ceili(sim.back_in(r)), r.map, r.away]
		sig += r.job.label if r.job != null else "Idle"
	_rebuild(_plan_box, sig, func(c: Container) -> void: _fill_planner(c, sim))


func _fill_planner(c: Container, sim: Sim) -> void:
	var head := HBoxContainer.new()
	var title := _label("Expedition board", true, Palette.CHALK, Palette.HEADING)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if sim.expedition.is_empty() and game.adventure != "":  # back to the adventures list (issue #136)
		head.add_child(_button("All adventures", func(): game.close_adventure(), "Secondary"))
	head.add_child(_button("Close", func(): game.close_planner(), "Secondary"))
	c.add_child(head)
	match sim.expedition.get("state", ""):
		"staging":
			_fill_adventures(c, sim, true)
			_fill_staging(c, sim)
		"out":
			_fill_adventures(c, sim, true)
			_fill_out(c, sim)
		_:
			if game.adventure == "":
				_fill_adventures(c, sim)
				return
			if game.plan.is_empty():  # the planner was left open while an expedition ended
				game.plan = sim.new_plan(game.adventure)
			_fill_plan(c, sim)


## The adventures list (issue #136): one row per known destination, with its travel time, what's there,
## its known hazards and what's happening there. Choosing a row opens its site report and planner.
## While an expedition is packing or out, `compact` lists each row's name and status only, since
## planning is locked.
func _fill_adventures(c: Container, sim: Sim, compact := false) -> void:
	var rows := sim.adventures()
	if not compact:
		c.add_child(_label("Adventures", true))
	for a in rows:
		if compact:  # the party's own destination is the panel below; the rest say they're locked
			if not a.here:
				c.add_child(_row(a.name, a.status))
			continue
		var b := _button("%s\n%s" % [a.name, a.what], func(): game.open_adventure(a.id), "Secondary")
		b.set_meta("label", "Adventure: " + a.name)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(420, 0)
		b.disabled = a.locked
		var hz: String = "Hazards: " + "; ".join(a.hazards) if not a.hazards.is_empty() else "No hazards known yet"
		b.tooltip_text = "About %d s walk each way. %s." % [roundi(a.travel), hz] if a.travel >= 0.0 else hz
		c.add_child(b)
		var line := "About %d s each way · %s" % [roundi(a.travel), a.status] if a.travel >= 0.0 else "The road isn’t walked yet · %s" % a.status
		c.add_child(_label(line, false, Palette.CHALK_DIM, Palette.CAPTION, true))
		for hz2 in a.hazards:
			c.add_child(_label("Hazard: " + hz2, false, Palette.YELLOW, Palette.CAPTION, true))
	if compact and rows.size() > 1:
		c.add_child(_rule())
	elif rows.is_empty():
		c.add_child(_label("Nobody knows of anywhere to go yet.", false, Palette.CHALK_DIM, Palette.BODY, true))


## Drawing up a plan (issue #106): the site report and the party on the left, the rest on the right.
func _fill_plan(c: Container, sim: Sim) -> void:
	var plan: Dictionary = game.plan
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size.x = 270
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size.x = 320
	cols.add_child(left)
	cols.add_child(right)
	c.add_child(cols)
	var last: Array = sim.expedition_board().get("report", [])
	if not last.is_empty():  # the last expedition's report (issue #112)
		left.add_child(_label("Last expedition", true))
		for line in last:
			left.add_child(_label(line + ".", false, Palette.CHALK_DIM, Palette.CAPTION, true))
		left.add_child(_rule())
	_add_level_picker(left, sim, plan)
	_add_site_report(left, sim, plan.dest)
	left.add_child(_rule())
	_add_party_picker(left, sim, plan)
	_add_plan_details(right, sim, plan)


## The site report (brief §8): what the village knows of the place before anyone sets off.
func _add_site_report(c: Container, sim: Sim, dest: String) -> void:
	var rep := sim.site_report(dest)
	c.add_child(_row(rep.name, "about %d s walk each way" % roundi(rep.travel) if rep.travel >= 0.0 else "the road isn’t walked yet", false))
	if rep.visited and rep.get("pattern", "") != "":
		c.add_child(_label(rep.pattern, false, Palette.CHALK_DIM, Palette.CAPTION))
	if not rep.visited:
		c.add_child(_label("“%s”" % rep.told, false, Palette.CHALK_DIM, Palette.BODY, true))
	for x in rep.resources:
		c.add_child(_row(x.name, "?" if x.reserve < 0 else "about %d" % x.reserve))
	for f in rep.get("finds", []):
		c.add_child(_label(f, true, Palette.CHALK, Palette.BODY, true))
	if not rep.visited:
		c.add_child(_label("Nobody has been there yet: no estimates, and no hazards known.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
		return
	for hz in rep.hazards:
		c.add_child(_label("Hazard: " + hz, false, Palette.YELLOW, Palette.BODY, true))
	for a in rep.access:
		c.add_child(_label(a, false, Palette.CHALK_DIM, Palette.BODY, true))
	if rep.get("levels", []).size() > 1:  # every level known so far (issue #132)
		c.add_child(_label("Levels", true))
		for lv in rep.levels:
			var ore: String = "%d ore blocks left" % lv.ore if lv.ore >= 0 else "not visited"
			c.add_child(_row("%d  %s" % [lv.level, lv.pattern], "%s, %s" % [ore, lv.door]))


## The levels a plan can be made for (issue #132): a button per level once there's more than one.
func _add_level_picker(c: Container, sim: Sim, plan: Dictionary) -> void:
	var levels := sim.mine_levels()
	if levels.size() < 2 or sim.level_of(plan.dest) == 0:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_label("Work level", true))
	for id in levels:
		var n := sim.level_of(id)
		var b := _button(str(n), func(): game.plan_dest(id), "Secondary")
		b.set_meta("label", "Level %d" % n)
		b.toggle_mode = true
		b.set_pressed_no_signal(id == plan.dest)
		b.custom_minimum_size = Vector2(34, 0)
		b.tooltip_text = "%s: %s" % [sim.get_map(id).name, MineLevels.FAMILY_NAMES.get(sim.get_map(id).pattern, "")] if sim.get_map(id).visited else "%s: nobody has been down yet" % sim.get_map(id).name
		row.add_child(b)
	c.add_child(row)


## Who goes: up to PARTY_MAX residents, each with their Stonemason level, pickaxe and hunger. Anyone who
## can't go is listed with why.
func _add_party_picker(c: Container, sim: Sim, plan: Dictionary) -> void:
	c.add_child(_row("Party", "%d of up to %d" % [plan.party.size(), Tuning.PARTY_MAX], false))
	for r in sim.residents:
		var why := sim.cant_join(r)
		var on: bool = plan.party.has(r.id)
		var pick: String = Defs.ITEMS[r.pick.type].one if r.pick != null else "no pickaxe"
		var line: String = why if why != "" else "Stonemason level %d, %s, %s" % [Sim.level(r, "mason"), pick, _mood(r).to_lower()]
		if why == "" and plan.dest == Meadow.ID:  # at the meadow it's hunting that counts, and no pickaxe is needed
			line = "Hunt level %d, %s" % [Sim.level(r, "hunt"), _mood(r).to_lower()]
		var b := _button("%s\n%s" % [r.name, line], func(): game.plan_toggle(r.id), "Secondary")
		b.set_meta("label", r.name)
		b.toggle_mode = true
		b.set_pressed_no_signal(on)
		b.icon = _swatch_tex(r.shirt)
		b.add_theme_constant_override("icon_max_width", 14)
		b.add_theme_constant_override("h_separation", 10)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = why != "" or (not on and plan.party.size() >= Tuning.PARTY_MAX)
		b.tooltip_text = ("%s can’t go: %s" % [r.name, why.to_lower()]) if why != "" else ("Leave %s at home" % r.name if on else "Take %s" % r.name)
		c.add_child(b)


## The objective, provisions, spare pickaxes, the packs they share, the return policy, and Start packing.
func _add_plan_details(c: Container, sim: Sim, plan: Dictionary) -> void:
	var tend: bool = plan.target.item == "pens"
	if not plan.party.is_empty():  # issue #140: the party's armor against the hazards
		c.add_child(_label(_protection_text(sim, plan.party), false, Palette.CHALK_DIM, Palette.CAPTION, true))
	c.add_child(_label("Bring back", true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for t in sim.plan_targets(plan.dest):
		var b := _button(t.name, func(): game.plan_target(t.item), "Secondary")
		b.toggle_mode = true
		b.set_pressed_no_signal(t.item == plan.target.item)
		row.add_child(b)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	if not tend:
		row.add_child(_stepper("%d" % plan.target.n, "target"))
	c.add_child(row)
	var meadow: bool = plan.dest == Meadow.ID and not sim.get_map(Meadow.ID).pens.is_empty()
	if meadow:  # issue #139: or tend the pens
		var pr := HBoxContainer.new()
		pr.add_theme_constant_override("separation", 6)
		var tb := _button("Tend the pens", func(): game.plan_target("pens"), "Secondary")
		tb.toggle_mode = true
		tb.set_pressed_no_signal(tend)
		pr.add_child(tb)
		var pg := Control.new()
		pg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pr.add_child(pg)
		if tend:
			pr.add_child(_label("Keep of each", false, Palette.CHALK_DIM, Palette.CAPTION))
			pr.add_child(_stepper("%d" % plan.target.n, "target"))
		c.add_child(pr)
		if tend:
			c.add_child(_label("Build the pens, lead marked animals in, feed pairs, and hunt only what's over %d of each kind." % plan.target.n, false, Palette.CHALK_DIM, Palette.CAPTION, true))
	c.add_child(_stepper_row("Meals to take", plan.meals, "meals"))
	var keep := Sim.return_meals(plan)
	var mins := Sim.site_minutes(plan)
	var at := "the meadow" if plan.dest == Meadow.ID else "the mine"
	var feeds := "About %d min at %s" % [roundi(mins), at] if mins >= 1.0 else "Not enough to eat at %s" % at
	var food := "%s, the return food too." % feeds if plan.spend_return else "%s. %d kept for the walk home." % [feeds, keep]
	var food_row := HBoxContainer.new()
	food_row.add_theme_constant_override("separation", 8)
	var food_l := _label(food, false, Palette.CHALK_DIM, Palette.CAPTION, true)
	food_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	food_row.add_child(food_l)
	var spend := _button("Spend it", func(): game.plan_spend_return(), "Secondary")
	spend.toggle_mode = true
	spend.set_pressed_no_signal(plan.spend_return)
	spend.add_theme_font_size_override("font_size", Palette.CAPTION)
	spend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spend.tooltip_text = "Let the party eat the meals kept for the walk home, to stay longer"
	food_row.add_child(spend)
	c.add_child(food_row)
	if plan.dest != Meadow.ID or plan.picks > 0:
		c.add_child(_stepper_row("Spare pickaxes", plan.picks, "picks"))
	if plan.dest == Meadow.ID and not sim.get_map(Meadow.ID).pens.is_empty():  # issue #139
		c.add_child(_stepper_row("Sticks for fences", plan.get("sticks", 0), "sticks"))
		c.add_child(_stepper_row("Wheat to feed pairs", plan.get("wheat", 0), "wheat"))
		var need: PackedStringArray = []
		var fl := sim.fence_left()
		var wh := sim.wheat_wanted()
		if fl > 0:
			need.append("the pens need %s" % Defs.words("stick", fl))
		if wh > 0:
			need.append("%d %s can be fed now, for %s" % [wh / (2 * Tuning.FEED_WHEAT), "pair" if wh == 2 * Tuning.FEED_WHEAT else "pairs", Defs.words("wheat", wh)])
		if not need.is_empty():
			var t := ", ".join(need)
			c.add_child(_label(t[0].to_upper() + t.substr(1) + ".", false, Palette.CHALK_DIM, Palette.CAPTION, true))
	_add_packs(c, plan)
	var home := _label("Come home when", true)
	home.tooltip_text = "Any of the chosen ones brings them home. A serious injury always does, and stops the game for you."
	home.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(home)
	var policy := HBoxContainer.new()
	policy.add_theme_constant_override("separation", 4)
	for k in [["target", "Target reached"], ["full", "Packs full"], ["low", "Food runs low"]]:
		var b := _button(k[1], func(): game.plan_policy(k[0]), "Secondary")
		b.toggle_mode = true
		b.set_pressed_no_signal(plan.policy[k[0]])
		b.add_theme_font_size_override("font_size", Palette.CAPTION)
		policy.add_child(b)
	c.add_child(policy)
	c.add_child(_label("Or a serious injury: that always brings them home.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
	var problems := sim.plan_problems(plan)
	for p in problems.slice(0, 2):
		c.add_child(_reason(p))
	var go := _button("Start packing", func(): game.confirm_plan(), "Primary")
	go.disabled = not problems.is_empty()
	go.tooltip_text = "Residents pack the supplies at the board and the party gathers there. Nobody leaves until you choose Depart."
	c.add_child(go)


## "Armor: Ada turns aside 35% of hazard injuries (full set), Tomas none." (issue #140)
func _protection_text(sim: Sim, party: Array) -> String:
	var parts: PackedStringArray = []
	for id in party:
		var r := sim.resident(id)
		if r.is_empty():
			continue
		var g := Sim.protection(r)
		var full := Sim.armor_worn(r).size() == Defs.ARMOR_SLOTS.size()
		parts.append("%s %s" % [r.name, "none" if g <= 0.0 else "%d%%" % roundi(g * 100.0) + (", full set" if full else "")])
	return "Armor against the hazards: %s. It turns aside that share of injuries." % ", ".join(parts)


## The meadow's pens in a line (issue #139): fences to build, animals penned, young ones.
func _pens_text(sim: Sim) -> String:
	var mp := sim.get_map(Meadow.ID)
	var parts: PackedStringArray = []
	var fl := sim.fence_left()
	if fl > 0:
		parts.append("%d %s to build" % [fl / Tuning.FENCE_STICKS, "fence" if fl == Tuning.FENCE_STICKS else "fences"])
	var penned := mp.sheep.filter(func(a): return a.alive and a.get("pen", 0) != 0)
	var young := penned.filter(func(a): return a.get("young", false)).size()
	parts.append("%d penned" % penned.size() + (", %d young" % young if young > 0 else ""))
	var lead := mp.sheep.filter(func(a): return a.alive and a.get("lead", false) and a.get("pen", 0) == 0).size()
	if lead > 0:
		parts.append("%d to lead in" % lead)
	var t := ", ".join(parts)
	return t[0].to_upper() + t.substr(1) + "."


## The packs, shared (brief §5): supplies in yellow, the cargo target in blue, room left dim.
func _add_packs(c: Container, plan: Dictionary) -> void:
	var cap := Sim.pack_capacity(plan)
	var sup := Sim.plan_supplies(plan)
	var room := maxi(0, cap - sup)
	c.add_child(_row("Packs", "%d supplies, room for %d of %d" % [sup, room, cap]))
	if plan.get("cart_cap", false):
		c.add_child(_label("Includes the cart's %d, with the line laid." % Tuning.CART_CAPACITY, false, Palette.CHALK_DIM, Palette.CAPTION, true))
	if cap == 0:
		return
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 1)
	var cargo: int = 0 if plan.target.item == "pens" else mini(plan.target.n, room)
	for seg in [[mini(sup, cap), Palette.YELLOW], [cargo, Palette.BLUE], [room - cargo, Palette.SLATE_DEEP]]:
		if seg[0] <= 0:
			continue
		var r := ColorRect.new()
		r.color = seg[1]
		r.custom_minimum_size = Vector2(0, 8)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.size_flags_stretch_ratio = seg[0]
		bar.add_child(r)
	bar.tooltip_text = "Supplies take %d, the cargo target %d, and %d is spare" % [sup, cargo, room - cargo]
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(bar)


func _stepper_row(name: String, value: int, key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := _label(name)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(_stepper("%d" % value, key))
	return h


## − n + for one of the plan's numbers.
func _stepper(value: String, key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var less := _button("−", func(): game.plan_step(key, -1), "Secondary")
	var more := _button("+", func(): game.plan_step(key, 1), "Secondary")
	less.set_meta("label", key + " less")
	more.set_meta("label", key + " more")
	for b in [less, more]:
		b.custom_minimum_size = Vector2(30, 0)
	var v := _label(value, true)
	v.custom_minimum_size.x = 30
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(less)
	h.add_child(v)
	h.add_child(more)
	return h


## Packing (issue #107): what's packed, where the party is, and Depart once it's all ready.
func _fill_staging(c: Container, sim: Sim) -> void:
	var ex: Dictionary = sim.expedition
	var p := sim.packed()
	var aim := "to tend the pens" if ex.target.item == "pens" else "to bring back %s" % Defs.words(ex.target.item, ex.target.n)
	c.add_child(_label("Packing for the %s, %s" % [sim.get_map(ex.dest).name.to_lower(), aim], false, Palette.CHALK, Palette.BODY, true))
	c.add_child(_row("Meals", "%d / %d" % [p.meals, ex.meals]))
	c.add_child(_bar(float(p.meals) / maxi(ex.meals, 1)))
	if ex.picks > 0:
		c.add_child(_row("Spare pickaxes", "%d / %d" % [p.picks, ex.picks]))
		c.add_child(_bar(float(p.picks) / ex.picks))
	for k in [["sticks", "Sticks"], ["wheat", "Wheat"]]:  # issue #139
		if ex.get(k[0], 0) > 0:
			c.add_child(_row(k[1], "%d / %d" % [p[k[0]], ex[k[0]]]))
			c.add_child(_bar(float(p[k[0]]) / ex[k[0]]))
	c.add_child(_label("Party", true))
	for id in ex.party:
		var r := sim.resident(id)
		if r.is_empty():
			continue
		var where := "At the board" if sim.at_board(r) else sim.cant_join(r)
		if where == "":
			where = r.job.label if r.job != null else "Idle"
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.add_child(_swatch(r.shirt))
		line.add_child(_label("%s: %s" % [r.name, where], false, Palette.CHALK if sim.at_board(r) else Palette.CHALK_DIM))
		c.add_child(line)
	for x in sim.stuck:
		if x.who == "Expedition" and not x.waiting:
			c.add_child(_reason(x.why))
	var why := sim.depart_blocker()
	var go := _button("Depart", func(): game.depart(), "Primary")
	go.disabled = why != ""
	go.tooltip_text = why if why != "" else "Send the party off. They’re out of village work until they’re back."
	c.add_child(go)
	if why != "":
		c.add_child(_label(why, false, Palette.CHALK_DIM, Palette.BODY, true))
	c.add_child(_destructive("Call off the expedition", "Click again to call it off", "expedition", func(): game.cancel_expedition()))


## An expedition that's out: one at a time (#25), so there's nothing to plan.
func _fill_out(c: Container, sim: Sim) -> void:
	var ex: Dictionary = sim.expedition
	var mp := sim.get_map(ex.dest)
	var party: Array = ex.party.map(func(id): return sim.resident(id)).filter(func(r): return not r.is_empty())
	var road: Array = party.filter(func(r): return sim.on_road(r))
	var names := Sim.names_text(party.map(func(r): return r.name))
	var are := "is" if party.size() == 1 else "are"
	var home: bool = ex.get("leg", "out") == "home"
	if not road.is_empty():
		var when := ceili(sim.road_eta(road[0]))
		c.add_child(_label("%s %s on the road %s, there in %d s." % [names, are, "home" if home else "to the " + mp.name.to_lower(), when], false, Palette.CHALK, Palette.BODY, true))
	elif home:
		c.add_child(_label("%s %s heading home from the %s." % [names, are, mp.name.to_lower()], false, Palette.CHALK, Palette.BODY, true))
	elif party.all(func(r): return r.map == ex.dest):
		c.add_child(_label("The party is at the %s: %s." % [mp.name.to_lower(), names], false, Palette.CHALK, Palette.BODY, true))
		_fill_party(c, sim)
		c.add_child(_button("Show the %s" % mp.name.to_lower(), func(): game.switch_map(ex.dest), "Secondary"))
	else:
		c.add_child(_label("%s %s carrying the packs to the signpost." % [names, are], false, Palette.CHALK, Palette.BODY, true))
	_add_call_home(c, sim)


## Call the party home (issue #108), until #109's return policy does it by itself. Disabled, with
## why, until the whole party is at the site.
func _add_call_home(c: Container, sim: Sim) -> void:
	var why := sim.call_home_blocker()
	if sim.expedition.get("leg", "out") == "home":
		return
	var b := _button("Call the party home", func(): game.call_home(), "Primary")
	b.disabled = why != ""
	b.tooltip_text = why if why != "" else "They walk to the entrance with what they’ve mined, and take the road home."
	c.add_child(b)


## The signpost to the old mine (issue #108), and those at both ends of the road: the route report
## (issue #119) with each segment and the journey, who's on the road, and the work it needs: the
## bridge, the cut, and the line (issue #121).
func _fill_route(c: Container, sim: Sim) -> void:
	var mp := sim.get_map(OldMine.ID)
	var rep := sim.route_report()
	var sub := "about %d s on foot each way" % roundi(rep.walk) if rep.surveyed else "not walked yet"
	c.add_child(_head("Road to the %s" % mp.name.to_lower() if mp.known else "A road east", sub))
	if not mp.known:
		c.add_child(_label("Nobody in the village knows where it goes yet. An expedition board would.", false, Palette.CHALK_DIM, Palette.BODY, true))
		return
	for i in rep.segments.size():
		var sg: Dictionary = rep.segments[i]
		if not sg.known:
			c.add_child(_row("%d  Not walked yet" % (i + 1), "%d cells" % sg.len))
			continue
		var track: String = {"none": "", "planned": "track planned", "built": "track laid"}[sg.track]
		c.add_child(_row("%d  %s" % [i + 1, sg.name], track if track != "" else "%d cells, %s" % [sg.len, sg.terrain]))
		if sg.obstacle != "":
			var done: bool = sg.obstacle in ["Bridged", "Cleared"]
			c.add_child(_label(sg.obstacle, false, Palette.CHALK_DIM if done else Palette.YELLOW, Palette.CAPTION, true))
	if rep.surveyed and not sim.cart.is_empty():
		c.add_child(_label("On foot about %d s, by cart about %d s as the line stands." % [roundi(rep.walk), roundi(rep.cart_now)], false, Palette.CHALK, Palette.BODY, true))
	elif rep.surveyed:
		c.add_child(_label("By cart about %d s, once the line is laid." % roundi(rep.cart), false, Palette.CHALK, Palette.BODY, true))
	else:
		c.add_child(_label("The first party to walk it will survey the rest of the road.", false, Palette.CHALK_DIM, Palette.BODY, true))
	var on_road: Array = sim.residents.filter(func(r): return r.map == Road.ID or sim.carrying_packs(r))
	for r in on_road:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.add_child(_swatch(r.shirt))
		line.add_child(_label("%s: %s" % [r.name, _status(sim, r)], false, Palette.CHALK))
		c.add_child(line)
	if game.view_map != Road.ID:
		c.add_child(_button("Show the road", func(): game.switch_map(Road.ID), "Secondary"))
	if not sim.expedition_board().is_empty() and sim.expedition.is_empty():  # the old mine's adventure (issue #136)
		c.add_child(_button("Plan a trip to the old mine", func(): game.open_adventure(OldMine.ID), "Secondary"))
	# The work the road needs.
	var seen: int = sim.road().seen
	if sim.bridge().is_empty() and seen > Sim._seg_of("stream"):
		var b := _button("Build the bridge", func(): game.plan_bridge(), "Secondary")
		b.tooltip_text = "A plank bridge over the stream: %s. Village builders carry the planks out." % Defs.cost_text(Defs.TEMPLATES.bridge.stages[0].cost)
		c.add_child(b)
	var cut := sim.cut_boulders()
	if not cut.is_empty() and seen > Sim._seg_of("cut") and not cut.all(func(x): return x.des):
		var b := _button("Clear the cut", func(): game.clear_cut(), "Secondary")
		b.tooltip_text = "Marks the boulders on the line to be mined. Miners walk out from the village."
		c.add_child(b)
	for end in ["village", "mine"]:  # the stations (issue #123)
		if sim.station(end).is_empty() and seen > Road.segment_at(Road.STATIONS[end].x) and not sim.plan_line_blocker().begins_with("Walk"):
			var b := _button("Build the %s station" % end, func(): game.plan_station(end), "Secondary")
			b.tooltip_text = "A platform beside the line where the cart stops, loads and unloads: %s." % Defs.cost_text(Defs.TEMPLATES.station.stages[0].cost)
			c.add_child(b)
	_add_line(c, sim)


## A station (issue #123): the line's state, where the cart is, and what's on the platform.
func _fill_station(c: Container, sim: Sim, s: Dictionary) -> void:
	c.add_child(_head("Station", "%s end" % ("Village" if s.end == "village" else "Mine")))
	var laid := range(Road.segment_count()).filter(func(i): return sim.track_state(i) == "built").size()
	c.add_child(_row("The line", "%d of %d segments laid" % [laid, Road.segment_count()]))
	var where := "No minecart yet. Craft one at the bench, and it's hauled out here."
	var cart: Dictionary = sim.cart
	if not cart.is_empty():
		match cart.state:
			"moving": where = "The cart is on the line, %s" % ("to the mine" if sim.expedition.get("leg", "out") == "out" else "coming home")
			"loading": where = "The cart is being loaded at the mine end"
			"unloading": where = "The cart is being unloaded at the village end"
			_: where = "The cart is parked at the %s end" % cart.at
	c.add_child(_label(where + ".", false, Palette.CHALK, Palette.BODY, true))
	var on: Array = sim.road().items.values().filter(func(st): return Rect2i(s.origin, s.size).grow(1).has_point(st.cell))
	if on.is_empty():
		c.add_child(_label("Nothing on the platform.", false, Palette.CHALK_DIM, Palette.BODY, true))
	for st in on:
		c.add_child(_row(Defs.ITEMS[st.type].label, str(st.n)))
	c.add_child(_label("Carts load and unload here at %d items a second. Haulers carry what's set down to the stockpile." % int(Tuning.LOAD_RATE), false, Palette.CHALK_DIM, Palette.CAPTION, true))


## The line (issue #121): how far it's laid, or the plan with its cost and the time it saves.
func _add_line(c: Container, sim: Sim) -> void:
	var states: Array = range(Road.segment_count()).map(func(i): return sim.track_state(i))
	if states.has("planned") or states.has("built"):
		var laid := states.count("built")
		c.add_child(_row("The line", "%d of %d segments laid" % [laid, states.size()], false))
		var nxt := sim.next_track()
		if nxt >= 0 and sim.track_blocker(nxt) != "":
			c.add_child(_label("%s: %s" % [Road.SEGMENTS[nxt].name, sim.track_blocker(nxt).to_lower()], false, Palette.YELLOW, Palette.CAPTION, true))
		if not states.has("none"):
			return
	var why := sim.plan_line_blocker()
	if not game.line_preview:
		var b := _button("Plan the line", func(): game.line_preview = true, "Primary")
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else "Track along the road, from the village to the mine."
		c.add_child(b)
		return
	var cost := sim.line_cost()
	var craft := " Crafting them takes %d iron ingots." % cost.ingots if cost.ingots > 0 else ""
	c.add_child(_label("%d rails, with %d on hand.%s" % [cost.rails, cost.on_hand, craft], false, Palette.CHALK, Palette.BODY, true))
	c.add_child(_label("Laid from the village end. Saves about %d s a round trip, once there's a cart." % roundi(cost.saved), false, Palette.CHALK, Palette.BODY, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lay := _button("Lay track", func(): game.plan_line(), "Primary")
	lay.disabled = why != ""
	lay.tooltip_text = why
	row.add_child(lay)
	row.add_child(_button("Not now", func(): game.line_preview = false, "Secondary"))
	c.add_child(row)


## "Starving", "Hungry", "Peckish" or "Fed".
static func _mood(r: Dictionary) -> String:
	return "Starving" if r.hunger <= 0.0 else ("Hungry" if r.hunger < Tuning.HUNGRY_BELOW else ("Peckish" if r.hunger < Tuning.EAT_BELOW else "Fed"))


## What the board is up to, for its selection panel.
func _board_status(sim: Sim) -> String:
	var ex: Dictionary = sim.expedition
	match ex.get("state", ""):
		"staging":
			return "Packing for the %s." % sim.get_map(ex.dest).name.to_lower()
		"out":
			return "The party is out at the %s." % sim.get_map(ex.dest).name.to_lower()
	return "Plan an adventure here: the old mine or the meadow."


# ---------------------------------------------------------------- the party at work, and choices (issues #109-#111)

## The party at the site (issue #109): each member's task, pickaxe and hunger, then the packs, the
## meals, the objective and what will bring them home.
func _fill_party(c: Container, sim: Sim) -> void:
	var ex: Dictionary = sim.expedition
	for id in ex.party:
		var r := sim.resident(id)
		if r.is_empty():
			continue
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.add_child(_swatch(r.shirt))
		line.add_child(_label("%s: %s" % [r.name, _status(sim, r)], false, Palette.CHALK))
		c.add_child(line)
		var pick: String = "%s pickaxe, %d %s left" % [Defs.TIER_NAMES[r.pick.tier], r.pick.dur, "use" if r.pick.dur == 1 else "uses"] if r.pick != null else "No pickaxe"
		var health: String = ["", ", injured", ", seriously hurt"][r.get("hurt", 0)]
		c.add_child(_label("%s. %s%s." % [pick, _mood(r), health], false, Palette.YELLOW if r.get("hurt", 0) > 0 else Palette.CHALK_DIM, Palette.CAPTION, true))
	var cap := Sim.pack_capacity(ex)
	c.add_child(_row("Packs", "%d / %d" % [sim.pack_load(), cap]))
	c.add_child(_bar(float(sim.pack_load()) / maxi(cap, 1), Palette.BLUE))
	var got: PackedStringArray = []
	for k in ex.get("cargo", {}):
		got.append(Defs.words(k, ex.cargo[k]))
	c.add_child(_label("Cargo: " + (", ".join(got) if not got.is_empty() else "nothing yet"), false, Palette.CHALK_DIM, Palette.CAPTION, true))
	var meals := 0
	for k in ex.get("provisions", {}):
		meals += ex.provisions[k]
	var spares: int = ex.get("tools", []).size()
	var keep := "" if ex.get("spend_return", false) else ", %d kept for the walk home" % mini(meals, Sim.return_meals(ex))
	var sup: Dictionary = ex.get("supplies", {})
	var pen_sup := "" if sup.is_empty() else " Sticks: %d. Wheat: %d." % [sup.get("stick", 0), sup.get("wheat", 0)]
	c.add_child(_label("Meals: %d%s. Spare pickaxes: %d.%s" % [meals, keep, spares, pen_sup], false, Palette.CHALK_DIM, Palette.CAPTION, true))
	if ex.target.item == "pens":  # issue #139
		c.add_child(_row("Tend the pens", "keep %d of each" % ex.target.n))
		c.add_child(_label(_pens_text(sim), false, Palette.CHALK_DIM, Palette.CAPTION, true))
	else:
		c.add_child(_row("Bring back %s" % Defs.ITEMS[ex.target.item].many, "%d / %d" % [sim.objective_packed(), ex.target.n]))
		c.add_child(_bar(float(sim.objective_packed()) / maxi(ex.target.n, 1), Palette.GREEN))
	var when: PackedStringArray = []
	for k in [["target", "the target is reached"], ["full", "the packs are full"], ["low", "food runs low"]]:
		if ex.policy.get(k[0], false):
			when.append(k[1])
	var whens := " or ".join(when) if when.size() < 3 else "%s, %s or %s" % [when[0], when[1], when[2]]
	c.add_child(_label("Home when %s, or if someone is seriously hurt." % whens if not when.is_empty() else "Home when you call them, or if someone is seriously hurt.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
	_add_door_buttons(c, sim)


## The door at the end of the level the party is working (issue #132): dig to it, or, once it's been
## reached, take it down.
func _add_door_buttons(c: Container, sim: Sim) -> void:
	var ex: Dictionary = sim.expedition
	if ex.get("leg", "out") != "out" or sim.level_of(ex.dest) == 0:
		return
	var mp := sim.get_map(ex.dest)
	if mp.door_state == "closed":
		var dig := _button("Dig to the door", func(): game.dig_to_door(), "Secondary")
		dig.tooltip_text = "Marks the blocks between the party and the door at the far end of the level"
		c.add_child(dig)
		return
	var down := _button("Go down to level %d" % (mp.level + 1), func(): game.go_down(), "Secondary")
	down.tooltip_text = "The party takes the door and works the level below instead. What they mine comes back up the same way."
	c.add_child(down)


## The choice the game stopped for (brief §5): what happened, and each option with its known cost.
func _refresh_choice(sim: Sim) -> void:
	var p: Dictionary = sim.pending[0] if not sim.pending.is_empty() else {}
	_choice_panel.visible = not p.is_empty()
	if p.is_empty():
		return
	_rebuild(_choice_box, "%s" % [p], func(c: Container) -> void:
		var title: String = {"discovery": "Iron found", "door": "A door down"}.get(p.kind, "Seriously hurt")
		c.add_child(_label(title, true, Palette.YELLOW if p.kind == "injury" else Palette.CHALK, Palette.HEADING))
		c.add_child(_label(p.text, false, Palette.CHALK, Palette.BODY, true))
		c.add_child(_label("The game is paused until you choose.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
		for o in p.options:
			var b := _button(o.label, func(): game.answer(o.id), "Primary" if o == p.options[0] else "Secondary")
			b.set_meta("label", o.label)
			c.add_child(b)
			c.add_child(_label(o.cost, false, Palette.CHALK_DIM, Palette.CAPTION, true)))
	_choice_panel.position = (_root.size - _choice_panel.get_combined_minimum_size()) / 2.0 - Vector2(0, 40)
