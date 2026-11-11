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
var _jobs_btn: Button               ## Opens the village book (the Jobs page was the jobs board, issue #78).
var _claim_btn: Button              ## "2 land claims": starts the Claim land order (issue #187).
var _maps := HBoxContainer.new()    ## The map switcher (issue #101): Village, and each known site.
var _party := Button.new()          ## "Party at the old mine: mining", when residents work on another map.
var _party_panel: PanelContainer
var _home_btn: Button               ## "Call the party home", beside the party line while the site is in view (issue #108).
var _party_details := VBoxContainer.new()  ## The party's members, packs and objective, while the site is in view (#109).
var _choice_panel: PanelContainer   ## A choice the game stopped for (issues #110, #111).
var _choice_box := VBoxContainer.new()
var _book_panel: PanelContainer      ## The village book (issue #198), over the goals panel's place.
var _book := VBoxContainer.new()
var _board := VBoxContainer.new()    ## The Jobs page, which the book shows in its body.
var _roster := VBoxContainer.new()   ## The Residents page.
var _book_scroll: ScrollContainer
var _tools_drop: PanelContainer
var _job_drop: PanelContainer       ## A resident's job dropdown (issue #134), under the button it opened from.
var _job_list := VBoxContainer.new()
var _job_for := -1                  ## The resident whose job dropdown is open, or -1.
var _job_anchor := Rect2()          ## The button it opened from, in global coordinates.
var _maps_drop: PanelContainer      ## The map switcher's dropdown: every place the village knows, under its button.
var _maps_list := VBoxContainer.new()
var _maps_btn: Button
var _maps_open := false
var _loc_drop: PanelContainer       ## The expedition board's location dropdown (issue #181), under its button.
var _loc_list := VBoxContainer.new()
var _loc_open := false
var _minimap: MiniMap                ## The corner map (issue #298), always on from issue #347.
var _world_map: WorldMap             ## The full-screen world map (issue #347).
var minimap_on := true
var _corner_row: HBoxContainer      ## The bottom right: the menus and toolbar, and the corner map beside them.


## The message log (issue #297): the toasts so far, newest last, in a list that opens under its button.
var _log: Array = []              ## {text, tick, res_id, site_id}
var _log_unread := 0
var _log_open := false
var _log_btn: Button
var _log_panel: PanelContainer
var _log_list := VBoxContainer.new()
const LOG_MAX := 60
var _loc_anchor := Rect2()
var _loc_button: Button  ## The button the location dropdown hangs from, so it follows it.
const SEL_H := 400.0  ## The selection panel's height when something is selected; what doesn't fit scrolls.
const GOALS_W := 340.0  ## The tutorial tab's width, and its dropdown's.
const TOP_BAR_H := 60.0  ## The top bar's height: the screen's upper edge, as far as panels are concerned.
var _topbar_row := HBoxContainer.new()
var _tally_panel: PanelContainer
var _tally_seen := {}           ## Item types that have turned up in this game; the rest stay hidden.
var _tally_sim := 0             ## Which sim _tally_seen belongs to (it resets for a new or loaded game).
var _goals_panel: PanelContainer    ## The tutorial's details, dropped down under its tab; a fixed size, so it never changes height as the steps do.
var _goals_tab: Button              ## The tutorial's tab, hanging below the top bar: the chapter and the step in hand. It opens the details.
var _goals_scroll := ScrollContainer.new()
var goals_open := false             ## The tutorial's details are dropped down; it never opens by itself.
var _goals_done := false            ## Both chapters are done: the tab then opens the village book instead.
var _tools_list := VBoxContainer.new()
var _drop_pinned := ""          ## The tally group whose dropdown a click pinned open, or "" (issue #141).
var _drop_group := ""           ## The tally group whose dropdown is open, or "".
var _group_btns := {}           ## Tally group id -> its button in the tally bar.
var _pointer := Vector2(-1, -1)
var _goals := VBoxContainer.new()
var _speed_btns := {}
var _clock_label: Label             ## "Day 3" and, at night, "· night" (issue #357).
var _skip_btn: Button               ## Skip ahead until something needs the player (issue #299).
var _menu_btn: Button                ## The on-screen button for the Esc menu (issue #216), beside the speed buttons.
var _menu_panel: PanelContainer
var _stuck_panel: PanelContainer
var _stuck := VBoxContainer.new()
var _stuck_tab: Button           ## The tab that hangs below the top bar, always there; it opens the stuck list under it.
var stuck_open := false         ## The stuck list is open under its tab (issue #77); it never opens by itself.
var waiting_open := false       ## The Waiting tier's entries are shown.
var _toasts := VBoxContainer.new()
var _sel_panel: PanelContainer
var _sel := VBoxContainer.new()
var _sel_scroll := ScrollContainer.new()
var _build_menu: PanelContainer
var _craft_panel: PanelContainer
var _plan_panel: PanelContainer     ## The expedition planner (issues #105-#107).
var _plan_box := VBoxContainer.new()
var _plan_scroll := ScrollContainer.new()
var _craft_scroll := ScrollContainer.new()  ## The craft panel scrolls inside the planner's fixed height.
var _toolbar_panel: PanelContainer   ## The toolbar along the bottom, which the planner stands above.
var _craft_box := VBoxContainer.new()
var _craft_pick := {}           ## Station template -> the recipe its Craft panel shows (issue #95).
var _craft_n := {}              ## Recipe id -> how many its Queue button queues (issue #76).
const CRAFT_MAX := 20
var _speed_panel: PanelContainer
var _tool_btns := {}
var _tool_keys := {}            ## Each orders button's keycap Label.
var _toolbar_sig := ""
var _armed_key := ""            ## The Destructive button waiting for its second click, if any.
var _panel_btns: Array = []     ## The selection panel's buttons that have a panel key, in panel order (issue #197).
const PANEL_KEYS := 7
var _armed_until := 0
const ARM_MS := 3000
var _menus := {}                ## Toolbar menu id -> its rows' container (OrderMenus.MENUS).
var _menu_panels := {}          ## Toolbar menu id -> its panel above the toolbar.
var _tool_icons := {}           ## Toolbar button id -> its icon, redrawn when the active order changes.
var _keys_sig := ""
var _hint := Label.new()
var _paused_label: PanelContainer
var _sigs := {}
var _site_panels: SitePanels
var _locks := {}  ## container id -> what it showed when `_rebuild` last locked its size
var _held := false            ## A mouse button is down; panels wait to rebuild until it's released.
var _toast_list: Array = []
var equip_kind := ""          ## "axe" or "pick" while the resident panel lists tools to equip, else "".


## The panels for finished buildings (site_panels.gd), made once the HUD has its game.
var _selection_panel: SelectionPanel


func _selection_panel_of() -> SelectionPanel:
	if _selection_panel == null:
		_selection_panel = SelectionPanel.new(self, game)
	return _selection_panel


var _planner_panel: PlannerPanel


func _planner() -> PlannerPanel:
	if _planner_panel == null:
		_planner_panel = PlannerPanel.new(self, game)
	return _planner_panel


func _panels() -> SitePanels:
	if _site_panels == null:
		_site_panels = SitePanels.new(self, game)
	return _site_panels


func _ready() -> void:
	_make_theme()
	_root.theme = _theme
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var tl := _corner(Control.PRESET_TOP_LEFT)
	tl.offset_top = TOP_BAR_H  # the tab hangs straight off the top bar
	_goals_tab = _button("The founding", func(): _goals_pressed())
	_goals_tab.toggle_mode = true
	_goals_tab.clip_text = true
	_goals_tab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_goals_tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_goals_tab.custom_minimum_size = Vector2(GOALS_W, 34)  # one size whatever the step says
	_goals_tab.set_meta("label", "Tutorial")
	_style_tab(_goals_tab)
	tl.add_child(_goals_tab)
	var tally_row := HBoxContainer.new()
	tally_row.add_theme_constant_override("separation", 18)
	_tallies.add_theme_constant_override("separation", 18)
	tally_row.add_child(_tallies)
	for g in Defs.TALLY_GROUPS:  # one button per group, each opening its dropdown (issue #141)
		var gb := _button(g[1] + "  ↓", func(): pass)
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
	_jobs_btn = _button("Book", func(): game.open_book(game.book_page, not game.book_open))  # the village book: goals, jobs, residents and a page for each building
	_jobs_btn.toggle_mode = true
	_jobs_btn.set_meta("label", "Book")
	_jobs_btn.custom_minimum_size = Vector2(0, 36)
	_jobs_btn.tooltip_text = "The village book: the founding goals, who does what, the residents, and a page for every building"
	tally_row.add_child(_jobs_btn)
	_claim_btn = _button("", func(): game.start_claiming(), "Primary")
	_claim_btn.custom_minimum_size = Vector2(0, 36)
	_claim_btn.visible = false
	tally_row.add_child(_claim_btn)
	_maps.add_theme_constant_override("separation", 2)
	tally_row.add_child(_maps)
	_tally_panel = PanelContainer.new()  # the top bar: tallies on the left, the speeds, Skip, the gear and Log on the right
	_tally_panel.add_theme_stylebox_override("panel", _box(Palette.SLATE, 0, 8, Palette.SLATE_DEEP))
	_tally_panel.custom_minimum_size.y = TOP_BAR_H
	_tally_panel.z_index = 2  # above the big panels, so every button on it stays clickable (#316)
	_tally_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_topbar_row.add_child(tally_row)
	var bar_gap := Control.new()
	bar_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_topbar_row.add_child(bar_gap)
	_tally_panel.add_child(_topbar_row)
	_root.add_child(_tally_panel)
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
	_job_drop.z_index = 3  # over the top bar (z 2), which they can reach
	_loc_list.add_theme_constant_override("separation", 2)
	_loc_drop = _panel(_loc_list, Vector2(330, 0), 6)
	_loc_drop.add_theme_stylebox_override("panel", _box(Color(Palette.SLATE, 1.0), 8, 6, Palette.SLATE_DEEP))  # opaque: it lies over the planner
	_loc_drop.visible = false
	_loc_drop.top_level = true
	_loc_drop.z_index = 3  # over the top bar (z 2), which they can reach
	_maps_list.add_theme_constant_override("separation", 2)
	_maps_drop = _panel(_maps_list, Vector2(200, 0), 6)
	_maps_drop.add_theme_stylebox_override("panel", _box(Color(Palette.SLATE, 1.0), 8, 6, Palette.SLATE_DEEP))
	_maps_drop.visible = false
	_maps_drop.top_level = true
	_maps_drop.z_index = 3  # over the top bar (z 2), which they can reach
	_goals_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_goals_scroll.custom_minimum_size = Vector2(GOALS_W - 24, 190)
	_goals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goals_scroll.add_child(_goals)
	_goals_panel = _panel(_goals_scroll, Vector2(GOALS_W, 0))
	_goals_panel.add_theme_stylebox_override("panel", _box(Color(Palette.SLATE, 1.0), 8, 12, Palette.SLATE_DEEP))  # opaque: it lies over other panels
	_goals_panel.visible = false
	_goals_panel.top_level = true
	_goals_panel.z_index = 3
	_root.add_child(_goals_panel)

	var tr := _corner(Control.PRESET_TOP_RIGHT)
	var speed := HBoxContainer.new()
	speed.add_theme_constant_override("separation", 2)
	_clock_label = _label("Day 1", false, Palette.CHALK_DIM, Palette.CAPTION)  # the day and whether it's night (issue #357)
	_clock_label.custom_minimum_size = Vector2(96, 0)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock_label.add_theme_constant_override("outline_size", 0)
	speed.add_child(_clock_label)
	for v in [0, 1, 2, 3]:
		var b := _button("‖" if v == 0 else "%d×" % v, func(): game.set_speed(v))
		b.custom_minimum_size = Vector2(44, 44)
		b.toggle_mode = true
		_speed_btns[v] = b
		speed.add_child(b)
	_skip_btn = _button("Skip", func(): game.set_skip(not game.skipping))
	_skip_btn.toggle_mode = true
	_skip_btn.custom_minimum_size = Vector2(60, 44)
	_skip_btn.set_meta("label", "Skip ahead")
	_skip_btn.tooltip_text = "Skip ahead: run fast until something needs you"
	speed.add_child(_skip_btn)  # Skip sits between the speeds and the settings gear
	_menu_btn = _button("", func(): game.toggle_menu())  # the Esc menu, for the mouse and the web build (issue #216)
	_menu_btn.icon = _gear_tex()
	_menu_btn.expand_icon = false
	_menu_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_btn.custom_minimum_size = Vector2(44, 44)
	_menu_btn.set_meta("label", "Menu")
	speed.add_child(_menu_btn)
	_speed_panel = PanelContainer.new()  # no panel of its own now: the bar is the panel
	_speed_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_speed_panel.add_child(speed)
	_topbar_row.add_child(_speed_panel)
	_menu_panel = _speed_panel  # the gear lives in the speed row
	_log_btn = _button("Log", func(): _toggle_log())  # what the toasts said, for the ones that were missed (issue #297)
	_log_btn.custom_minimum_size = Vector2(0, 44)
	_log_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_btn.set_meta("label", "Log")
	_topbar_row.add_child(_log_btn)  # Log ends the bar, after the gear
	tr.offset_top = TOP_BAR_H  # the tab hangs straight off the top bar
	_stuck_tab = _button("Stuck", func(): stuck_open = not stuck_open)
	_stuck_tab.toggle_mode = true
	_stuck_tab.custom_minimum_size.y = 34  # the same height with or without its flag, so what hangs under it never shifts
	_stuck_tab.set_meta("label", "Stuck")
	_style_tab(_stuck_tab)
	tr.add_child(_stuck_tab)
	_stuck_panel = _panel(_stuck, Vector2(250, 0))
	_stuck_panel.add_theme_stylebox_override("panel", _box(Color(Palette.SLATE, 1.0), 8, 12, Palette.SLATE_DEEP))  # opaque: it lies over the other panels
	_stuck_panel.visible = false
	_stuck_panel.top_level = true
	_stuck_panel.z_index = 3
	_root.add_child(_stuck_panel)

	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)
	_paused_label = _panel(_label("Paused. You can still give orders.", true), Vector2.ZERO)
	_paused_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toasts.add_child(_paused_label)

	var bl := _corner(Control.PRESET_BOTTOM_LEFT)
	_sel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # a tall panel scrolls instead of covering the top bar (#15)
	_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_scroll.add_child(_sel)
	_sel_panel = _panel(_sel_scroll, Vector2(330, 0))
	_sel.add_theme_constant_override("separation", 8)
	bl.add_child(_sel_panel)

	var br := _corner(Control.PRESET_BOTTOM_RIGHT)
	_corner_row = HBoxContainer.new()  # the menus and toolbar, with the corner map to their right, fixed to the corner
	_corner_row.add_theme_constant_override("separation", 8)
	_corner_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.remove_child(br)
	_root.add_child(_corner_row)
	_corner_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_corner_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_corner_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_corner_row.add_child(br)
	br.size_flags_vertical = Control.SIZE_SHRINK_END
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
	_craft_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_craft_scroll.add_child(_craft_box)
	_craft_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_panel = _panel(_craft_scroll, Vector2(400, 0))
	_craft_panel.visible = false
	br.add_child(_craft_panel)
	_plan_box.add_theme_constant_override("separation", 8)
	_plan_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # a tall planner scrolls instead of running off the top
	_plan_scroll.add_child(_plan_box)
	_plan_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plan_panel = _panel(_plan_scroll, Vector2(0, 0))
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
	_toolbar_panel = _panel(tools, Vector2.ZERO, 4)
	br.add_child(_toolbar_panel)

	_root.add_child(_tools_drop)
	_book_panel = _panel(_book, Vector2(460, 0))
	_book_panel.top_level = true
	_book_panel.add_theme_stylebox_override("panel", _box(Color(Palette.SLATE, 1.0), 8, 12, Palette.SLATE_DEEP))  # opaque: it lies over the selection panel
	_book_panel.visible = false
	_root.add_child(_book_panel)
	_root.add_child(_job_drop)
	_root.add_child(_loc_drop)
	_root.add_child(_maps_drop)
	_minimap = MiniMap.new()
	_minimap.game = game
	_corner_row.add_child(_minimap)
	_minimap.size_flags_vertical = Control.SIZE_SHRINK_END
	_world_map = WorldMap.new()
	_world_map.game = game
	_root.add_child(_world_map)


	_log_list.add_theme_constant_override("separation", 4)
	var log_scroll := ScrollContainer.new()
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.custom_minimum_size = Vector2(430, 0)
	log_scroll.add_child(_log_list)
	_log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_panel = _panel(log_scroll, Vector2(430, 0), 8)
	_log_panel.add_theme_stylebox_override("panel", _box(Color(Palette.SLATE, 1.0), 8, 8, Palette.SLATE_DEEP))
	_log_panel.visible = false
	_log_panel.top_level = true
	_root.add_child(_log_panel)
	get_viewport().size_changed.connect(func() -> void:  # a resized window must not strand an open list
		if _loc_drop.visible and game != null and game.sim != null:
			_refresh_loc_drop(game.sim))
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


func _overlay_open() -> bool:
	for c in _root.get_children():
		if c is GameMenu and c.visible:
			return true
	return false


func add_overlay(c: Control) -> void:
	c.z_index = 10  # above the panels, the Menu button and the toasts
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
	if preset in [Control.PRESET_TOP_LEFT, Control.PRESET_TOP_RIGHT]:
		v.offset_top = TOP_BAR_H + 8.0  # the top bar is the upper edge of the screen
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


## Gives the wrapping labels directly in `c` the panel's width. A label that wraps measures its height
## at its own width, which is nothing when it's new, so for a pass it stands thousands of pixels tall
## and the panel flashes across the screen.
func _pin_wrap(c: Container, width: float) -> void:
	for ch in c.get_children():
		if ch is Label and ch.autowrap_mode != TextServer.AUTOWRAP_OFF and ch.custom_minimum_size.x == 0:
			ch.custom_minimum_size.x = width


## A tab that hangs off the top bar: square along the bar, rounded below, in the panels' slate.
func _style_tab(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var tab_box := _box(Color(Palette.SLATE, 1.0) if state != "hover" else Color(Palette.SLATE, 1.0).lightened(0.08), 8, 8, Palette.SLATE_DEEP)
		tab_box.corner_radius_top_left = 0
		tab_box.corner_radius_top_right = 0
		tab_box.content_margin_left = 14
		tab_box.content_margin_right = 14
		b.add_theme_stylebox_override(state, tab_box)


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


## Gives the selection panel's first PANEL_KEYS buttons their keys (issue #197): the panel's own
## buttons in the order they appear, so a key and a click run the same callable. Each shows its key in
## a small keycap at its left. The − and + steppers and the equip list's entries stay click-only
## (the entries have 1–9 while their list is open).
func _register_panel_keys(c: Container) -> void:
	_panel_btns = []
	for b in c.find_children("*", "Button", true, false):
		if b.disabled or _going(b, c):
			continue
		if b.text in ["−", "+"] or b.has_meta("entry"):
			continue
		if _panel_btns.size() < PANEL_KEYS:
			_panel_btns.append(b)
	for i in _panel_btns.size():
		var key: String = game.keys.first("panel%d" % (i + 1))
		if key != "":
			_add_keycap(_panel_btns[i], key)


## Whether a node, or one of its parents up to `root`, is waiting to be freed: a panel rebuild queues
## the old rows, and the new ones are added beside them in the same frame.
static func _going(n: Node, root: Node) -> bool:
	while n != null and n != root:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false


## A small chalk keycap at the left of a button, with room made for it.
func _add_keycap(b: Button, key: String) -> void:
	var cap := PanelContainer.new()
	var cap_box := _box(Color(0, 0, 0, 0), 3, 0, Palette.CHALK_DIM)
	cap_box.content_margin_left = 5
	cap_box.content_margin_right = 5
	cap_box.content_margin_top = 0
	cap_box.content_margin_bottom = 0
	cap.add_theme_stylebox_override("panel", cap_box)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(_label(key, false, Palette.CHALK_DIM, Palette.CAPTION))
	b.add_child(cap)
	var width := _font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.CAPTION).x + 12
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var sb := b.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		sb.content_margin_left = maxf(sb.content_margin_left, 10 + width + 6)
		b.add_theme_stylebox_override(state, sb)
	var place := func() -> void:
		cap.size = cap.get_combined_minimum_size()
		cap.position = Vector2(10, (b.size.y - cap.size.y) / 2)
	b.resized.connect(place)
	cap.minimum_size_changed.connect(place)
	b.set_meta("keycap", cap)


## Presses the selection panel's button for panel key `i` (from 0), for a click-free action. Returns
## whether there was one. A Destructive button takes its key twice, and any other key disarms it.
func press_panel_key(i: int) -> bool:
	if i >= _panel_btns.size() or not is_instance_valid(_panel_btns[i]) or _panel_btns[i].disabled:
		_disarm()
		return false
	var b: Button = _panel_btns[i]
	if _armed_key != "" and b.get_meta("arm_key", "") != _armed_key:
		_disarm()
	b.pressed.emit()
	return true


## Puts away an armed Destructive button, as its timeout does.
func _disarm() -> void:
	if _armed_key == "":
		return
	_armed_key = ""
	for n in _sel.find_children("*", "Button", true, false) + _plan_box.find_children("*", "Button", true, false):
		if n.has_meta("disarmed_text"):
			n.text = n.get_meta("disarmed_text")


## The entries of the list that's open (the job dropdown, or the equip list in the resident panel), for 1–9.
func list_entries() -> Array:
	var out: Array = []
	if _job_drop.visible:
		for b in _job_list.find_children("*", "Button", true, false):
			if not _going(b, _job_list):
				out.append(b)
	elif equip_kind != "":
		for b in _sel.find_children("*", "Button", true, false):
			if not _going(b, _sel) and b.has_meta("entry"):
				out.append(b)
	return out


func list_open() -> bool:
	return not list_entries().is_empty()


## Any key that isn't the armed button's own puts the Destructive button away.
func disarm_panel() -> void:
	_disarm()


func press_list_key(i: int) -> bool:
	var list := list_entries()
	if i >= list.size() or list[i].disabled:
		return false
	list[i].pressed.emit()
	return true


## Toolbar badges, build-menu keys and tooltips, from the current key bindings (issue #8).
func _refresh_key_labels() -> void:
	var k: KeyBindings = game.keys
	var sig := "%s" % [k.keys]
	if sig == _keys_sig:
		return
	_keys_sig = sig
	var tips := {"gather": "Mine, chop, break and hunt", "paint": "Paint pens at the meadow",
		"build": "Place a building", "craft": "Queue crafts at the bench or the fireplace"}
	for t in _tool_btns:
		_tool_btns[t].tooltip_text = tips[t] + (" (%s)" % k.first(t) if k.first(t) != "" else "")
	_toolbar_sig = ""
	var menu_key := k.first("menu")
	_menu_btn.tooltip_text = "Menu: save, load, controls and more" + (" (%s, or Esc)" % menu_key if menu_key != "" else " (Esc)")
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
	_tool_btns.paint.visible = game.view_map == Meadow.ID  # pens at the meadow; the village's storage and farms are painted from their buildings (issues #318, #319)
	_tool_btns.build.visible = village
	var sig := "%s|%s|%s|%s|%s" % [game.tool, game.menu_open, _keys_sig, gather.size(), game.view_map]
	if sig != _toolbar_sig:
		_toolbar_sig = sig
		for t in _tool_btns:
			var name: String = OrderMenus.MENUS[t].name if OrderMenus.MENUS.has(t) else "Craft"
			if t != "build" and on_menu == t:
				name += ": " + OrderMenus.entry(game.tool).name
			elif OrderMenus.MENUS.has(t):
				name += "  →"
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
	return {"gather": "mine", "paint": "pen"}.get(t, t)


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


func _update_progress_bar(sim: Sim) -> void:
	for bar in _sel.find_children("*", "Panel", true, false):
		if bar.has_meta("progress_of") and not bar.is_queued_for_deletion():
			for r in sim.residents:
				if r.id == bar.get_meta("progress_of") and r.progress >= 0:
					(bar.get_child(0) as Control).anchor_right = clampf(r.progress, 0.0, 1.0)


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
	return _label("!  " + text, true, Palette.YELLOW, Palette.BODY, true)


## Replaces a container's children only when `sig` differs from last time.
## `lock` names what the container is showing (the selection, the tab): while it stays the same, the
## container keeps the largest size it has had, so a panel whose numbers tick doesn't jitter in size.
## A different `lock` lets it settle to its new content.
func _rebuild(c: Container, sig: String, fill: Callable, before := Callable(), lock := "") -> void:
	if _sigs.get(c.get_instance_id(), "") == sig:
		return
	# Rebuilding between a button's press and release would swallow the click (the press lands on
	# the old button, the release on nothing), so a panel under a held button waits for the release.
	if _held and c.is_visible_in_tree() and c.get_global_rect().has_point(_pointer):
		return
	_sigs[c.get_instance_id()] = sig
	if lock != "":
		var id := c.get_instance_id()
		if _locks.get(id, "") == lock:
			c.custom_minimum_size = c.custom_minimum_size.max(c.size)
		else:
			_locks[id] = lock
			c.custom_minimum_size = Vector2.ZERO
	if before.is_valid():
		before.call()
	for ch in c.get_children():
		c.remove_child(ch)  # out of the tree now, so the old and new children never share a layout pass
		ch.queue_free()
	fill.call(c)


# ---------------------------------------------------------------- per-frame refresh

func refresh(sim: Sim) -> void:
	_refresh_key_labels()
	_refresh_tallies(sim)
	_refresh_maps(sim)
	_refresh_goals(sim)
	_refresh_book(sim)
	for v in _speed_btns:
		_speed_btns[v].set_pressed_no_signal(game.speed == v and not game.skipping)
	_skip_btn.set_pressed_no_signal(game.skipping)
	var night := Night.is_night(sim)
	_clock_label.text = "Day %d%s" % [Night.day_number(sim), "  · night" if night else ""]
	_clock_label.add_theme_color_override("font_color", Palette.BLUE if night else Palette.CHALK_DIM)
	_paused_label.visible = game.speed == 0 and sim.pending.is_empty()  # a choice says so itself
	_refresh_stuck(sim)
	_refresh_selection(sim)
	_refresh_job_drop(sim)
	_refresh_loc_drop(sim)
	_refresh_minimap()


	_refresh_log()
	_refresh_toolbar(sim)
	_refresh_board(sim)
	_refresh_roster(sim)
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
				b.text = "Food  %d %s%s%s  ↓" % [meals, "meal" if meals == 1 else "meals", " · %d raw" % raw if raw > 0 else "", " · low" if low else ""]  # the word as well as the yellow (issue #302)
				for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
					if low:
						b.add_theme_color_override(k, Palette.YELLOW)
					else:
						b.remove_theme_color_override(k)
				b.tooltip_text = "Fewer meals than residents. Cooks need wheat, or raw meat and logs." if low else ""
			"tools":
				b.text = "%s  %d  ↓" % [name, gear]
			_:
				b.text = "%s  %d  ↓" % [name, n]
	_refresh_drop(sim, totals, loose, meals, raw)


## The map switcher (issue #101), shown once a site map is known, and a dim line for residents at
## work on a map that isn't in view, which switches to it on a click.
## The list under the place button: every place the village knows, the one in view marked. Deeper cave levels
## are named "Old caves, level 3" in full, since there is room in a list.
func _refresh_maps_drop(sim: Sim, known: Array) -> void:
	if not _maps_open or not _maps.visible or not is_instance_valid(_maps_btn):
		_maps_open = false
		_maps_drop.visible = false
		return
	_maps_drop.visible = true
	var anchor := _maps_btn.get_global_rect()
	_place_drop(_maps_drop, Vector2(anchor.position.x, anchor.end.y + 4))
	_rebuild(_maps_list, "%s|%s" % [known, game.view_map], func(c: Container) -> void:
		for id in known:
			var nm: String = sim.get_map(id).name
			var b := _button(nm, func():
				game.switch_map(id)
				_maps_open = false
				_maps_drop.visible = false, "Secondary")
			b.set_meta("label", nm)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.set_pressed_no_signal(id == game.view_map)
			c.add_child(b))


func _refresh_maps(sim: Sim) -> void:
	var known: Array = game.known_maps()
	_maps.visible = known.size() > 1
	var key: String = game.keys.first("map")
	_rebuild(_maps, "%s%s%s" % [known, game.view_map, key], func(c: Container) -> void:
		c.add_child(_divider())
		var cur: String = sim.get_map(game.view_map).name
		_maps_btn = _button(cur + "  ↓", func(): _maps_open = not _maps_open, "Secondary")
		_maps_btn.set_meta("label", "Go to another place")  # not the name, so a search for "Village" finds the list's row
		_maps_btn.custom_minimum_size = Vector2(0, 36)
		_maps_btn.tooltip_text = "Go to another place." + (" %s switches maps." % key if key != "" else "")
		c.add_child(_maps_btn))
	_refresh_maps_drop(sim, known)
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
		if id == Road.ID or id == MeadowRoad.ID:  # a party walking the road, or villagers out working on it (issues #118, #119)
			var walking: Array = party.filter(func(r): return sim.on_road(r))
			line = "On the road: %s" % _party_doing(party)
			if not walking.is_empty():
				line = "Party " + _status(sim, walking[0]).replace("On the road", "on the road")
		_party.set_meta("map", id)
		break
	# Looking at the site the party is working: what they're doing here, and the way to call them home.
	var ex: Dictionary = sim.expeditions[Sim.realm_of(game.view_map)]  # the party of the realm in view (issue #145)
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
		_rebuild(_party_details, sig, func(c: Container) -> void:
			_fill_party(c, sim)
			_pin_wrap(c, 300),
			Callable(), "%d" % ex.party.size())
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
## A gear for the Menu button, drawn here so it doesn't depend on a font having the glyph (the web build's might not).
func _gear_tex() -> ImageTexture:
	var n := 24
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var mid := (n - 1) / 2.0
	for x in n:
		for y in n:
			var d := Vector2(x - mid, y - mid)
			var r := d.length()
			var tooth := absf(fmod(d.angle() / TAU * 8.0 + 8.0, 1.0) - 0.5) < 0.27  # eight teeth round the rim
			var body := r <= 7.4 or (r <= 10.8 and tooth)
			if body and r > 3.6:
				img.set_pixel(x, y, Palette.CHALK)
	return ImageTexture.create_from_image(img)


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
	var most: int = Sim.full_uses(type)
	var low := dur <= 3
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	var row := _row(Sim.item_title(type), "%d / %d uses%s" % [dur, most, " · low" if low else ""], false)  # the word as well as the yellow (issue #302)
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
		if event.pressed and _maps_drop.visible and not _maps_drop.get_global_rect().has_point(event.position) and (not is_instance_valid(_maps_btn) or not _maps_btn.get_global_rect().has_point(event.position)):
			_maps_open = false
			_maps_drop.visible = false
		if event.pressed and _loc_drop.visible and not _loc_drop.get_global_rect().has_point(event.position) and not _loc_anchor.has_point(event.position):
			_close_loc_drop()
		if event.pressed and _log_open and not _log_panel.get_global_rect().has_point(event.position) and not _log_btn.get_global_rect().has_point(event.position):
			_toggle_log()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _tools_drop.visible:
		_close_tools()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _job_drop.visible:
		_close_job_drop()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _maps_drop.visible:
		_maps_open = false
		_maps_drop.visible = false
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _loc_drop.visible:
		_close_loc_drop()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _log_open:
		_toggle_log()
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
	_toasts.visible = not _overlay_open()  # no stray toast beside the menu's dialog (#314)
	_place_toasts()
	var room: float = get_viewport().get_visible_rect().size.y - 150.0  # below the top bar, above the bottom edge
	# Whatever is selected, its panel is one height (what doesn't fit scrolls), so it never bounces between selections.
	var want := minf(SEL_H if not game.selection.is_empty() else _sel.get_combined_minimum_size().y, maxf(120.0, room))
	# The planner and every bench's craft panel are one fixed height: the top right under the Stuck tab, the bottom
	# above the toolbar. It never grows or shrinks with what's in them; what doesn't fit scrolls.
	var avail := get_viewport().get_visible_rect().size.y - (TOP_BAR_H + _stuck_tab.custom_minimum_size.y + 8.0) - 16.0 - _toolbar_panel.get_combined_minimum_size().y - 8.0 - 24.0
	for pair in [[_plan_panel, _plan_scroll, _plan_box], [_craft_panel, _craft_scroll, _craft_box]]:
		if pair[0].visible:
			var fixed := Vector2(pair[2].get_combined_minimum_size().x, maxf(120.0, avail))
			if not pair[1].custom_minimum_size.is_equal_approx(fixed):
				pair[1].custom_minimum_size = fixed
	if not is_equal_approx(_sel_scroll.custom_minimum_size.y, want):
		_sel_scroll.custom_minimum_size.y = want
	# The goals panel gives way to the jobs board, which sits over it, and to a selection panel tall
	# enough to reach it (at a large interface size, issue #80): what's selected matters more.
	# The stuck list gives way to the expedition planner the same way; the planner shows the board's
	# own stuck reasons, and the list comes back when it closes.
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
		_place_drop(_tools_drop, Vector2(b.global_position.x - 12, panel.get_global_rect().end.y + 6))
	for g in _group_btns:
		_group_btns[g].set_pressed_no_signal(_drop_pinned == g)


func _goals_pressed() -> void:
	if _goals_done:
		game.open_book()
	else:
		goals_open = not goals_open


## The tutorial hangs off a tab below the top bar, left of the screen: the chapter and the step in hand.
## Clicking it drops down the step's hint and why, in a panel of one fixed size. Once both chapters are
## done the tab reads "The village √" and opens the village book instead (#81, #198).
func _refresh_goals(sim: Sim) -> void:
	var cur := Goals.current(sim)
	var vcur := Goals.village_current(sim) if cur < 0 else 0
	var founding: bool = cur >= 0
	var at := cur if founding else vcur
	var ch: int = Goals.chapter_of(cur) if founding else 3
	var g: Dictionary = {}
	var step := 0   # which step of its chapter, counted from 1
	var steps := 0
	if at >= 0 and founding:
		g = Goals.LIST[at]
		var counts := Goals.chapter_count(sim, ch)
		steps = counts[1]
		for i in range(0, at + 1):
			step += 1 if Goals.LIST[i].c == ch else 0
	elif at >= 0:
		g = Goals.VILLAGE[at]
		steps = Goals.VILLAGE.size()
		step = at + 1
	var done_sig := ""
	for i in Goals.LIST.size():
		done_sig += "1" if Goals.done(sim, i) else "0"
	for i in Goals.VILLAGE.size():
		done_sig += "1" if Goals.village_done(sim, i) else "0"
	_goals_done = at < 0
	var name: String = Goals.CHAPTERS[ch].name
	var tint: Color = Palette.GREEN if _goals_done else Palette.CHALK
	_goals_tab.text = "The village  √" if _goals_done else "%s  ·  %d  %s" % [name, step, g.t]
	_goals_tab.tooltip_text = "Every founding and village step is done. Open the village book." if _goals_done else "Show this step's hint"
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		_goals_tab.add_theme_color_override(state, tint)
	_goals_tab.set_pressed_no_signal(goals_open and not _goals_done)
	_goals_panel.visible = goals_open and not _goals_done and not game.jobs_board_open and not game.book_open
	if not _goals_panel.visible:
		return
	_rebuild(_goals, "%d%d%s" % [cur, at, done_sig], func(c: Container) -> void:
		var head := HBoxContainer.new()
		var title := _row(name, "%d of %d" % [step - 1, steps], false)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var book := _button("Book", func(): game.open_book())
		book.flat = true
		book.tooltip_text = "Why each step matters, and a page for every building"
		head.add_child(book)
		c.add_child(head)
		# Wrapped at the panel's own width, so they measure right even when built while the panel is
		# hidden; otherwise they'd wrap at nothing, stand thousands of pixels tall and keep it hidden.
		for l in [_label("%d  %s" % [step, g.t], true, Palette.CHALK, Palette.BODY, true), _label(g.h, false, Palette.CHALK_DIM, Palette.CAPTION, true), _label(g.w, false, Palette.CHALK_DIM, Palette.CAPTION, true)]:
			l.custom_minimum_size.x = GOALS_W - 24 - 8
			c.add_child(l))
	_place_drop(_goals_panel, Vector2(16, _goals_tab.get_global_rect().end.y + 2))


## The village book (issues #78, #198): Goals (the tutorial, both chapters with their whys), Jobs (who
## does what), Residents (who needs a look), and one page for every building the village knows of. A row
## of page tabs, the page below it. The Jobs and Residents pages are live containers the book borrows.
func _refresh_book(sim: Sim) -> void:
	_book_panel.visible = game.book_open
	if not game.book_open:
		return
	_book_panel.position = Vector2(16, _goals_tab.get_global_rect().end.y + 8)  # under the tutorial's tab
	var pages := Goals.pages(sim)
	var sig := "%s|" % game.book_page
	for i in Goals.LIST.size():
		sig += "1" if Goals.done(sim, i) else "0"
	for i in Goals.VILLAGE.size():
		sig += "1" if Goals.village_done(sim, i) else "0"
	for p in pages:
		sig += p.id
	var rows := Goals.guide_rows(sim)
	var fresh := Goals.new_pages(sim).map(func(p): return p.id)
	var guide_sel: String = game.guide_page if rows.any(func(p): return p.id == game.guide_page) else rows[0].id
	var cur_chapter := Goals.current_chapter(sim)
	var goals_sel: int = game.goals_chapter if game.goals_chapter >= 0 and game.goals_chapter <= cur_chapter else cur_chapter
	sig += "|%s|%s|%d" % [fresh, guide_sel, goals_sel]
	var live: Control = _board if game.book_page == "jobs" else (_roster if game.book_page == "residents" else null)
	_rebuild(_book, sig, func(c: Container) -> void:
		var head := HBoxContainer.new()
		var title := _label("The village book", true, Palette.CHALK, Palette.HEADING)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		head.add_child(_button("Close", func(): game.open_book("goals", false)))
		c.add_child(head)
		var tabs := HFlowContainer.new()
		tabs.add_theme_constant_override("h_separation", 2)
		tabs.add_theme_constant_override("v_separation", 2)
		for entry in [{"id": "goals", "title": "Goals"}, {"id": "jobs", "title": "Jobs"}, {"id": "residents", "title": "Residents"}, {"id": "guide", "title": "Guide"}]:
			var b := _button(entry.title + ("  new" if entry.id == "guide" and not fresh.is_empty() else ""), func(): game.open_book(entry.id))
			b.set_meta("label", "Book: " + entry.title)
			b.toggle_mode = true
			b.set_pressed_no_signal(game.book_page == entry.id)
			tabs.add_child(b)
		c.add_child(tabs)
		_book_scroll = ScrollContainer.new()
		_book_scroll.custom_minimum_size = Vector2(440, 330)
		_book_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		if game.book_page == "guide" or game.book_page == "goals":  # a list on the left, the chosen one on the right (issues #348, #371)
			var split := HBoxContainer.new()
			split.add_theme_constant_override("separation", 8)
			c.add_child(split)
			var list_scroll := ScrollContainer.new()
			list_scroll.custom_minimum_size = Vector2(170, 330)
			list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			split.add_child(list_scroll)
			var list := VBoxContainer.new()
			list.add_theme_constant_override("separation", 2)
			list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			list_scroll.add_child(list)
			if game.book_page == "goals":
				for ch in Goals.CHAPTERS.size():
					var counts := Goals.chapter_progress(sim, ch)
					var reached := ch <= cur_chapter
					var cb := _button(("%d  %s    %d of %d" % [ch + 1, Goals.CHAPTERS[ch].name, counts[0], counts[1]]) if reached else "%d  ???" % [ch + 1], func(): game.select_chapter(ch))
					cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
					cb.toggle_mode = true
					cb.set_pressed_no_signal(ch == goals_sel)
					cb.set_meta("label", "Chapter: " + (Goals.CHAPTERS[ch].name if reached else "???"))
					if not reached or counts[0] == counts[1]:
						for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
							cb.add_theme_color_override(state, Palette.CHALK_DIM if not reached else Palette.GREEN)
					list.add_child(cb)
			else:
				for row in rows:
					var known := Goals.page_known(sim, row)
					var rb := _button("%s%s" % [row.title if known else "???", "  new" if fresh.has(row.id) else ""], func(): game.select_guide(row.id))
					rb.alignment = HORIZONTAL_ALIGNMENT_LEFT
					rb.toggle_mode = true
					rb.set_pressed_no_signal(row.id == guide_sel)
					rb.set_meta("label", "Guide: " + (row.title if known else "???"))
					if not known:
						for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
							rb.add_theme_color_override(state, Palette.CHALK_DIM)
					list.add_child(rb)
			split.add_child(_book_scroll)
		else:
			c.add_child(_book_scroll)
		if live != null:
			live.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_book_scroll.add_child(live)
			return
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 6)
		body.custom_minimum_size.x = 430
		_book_scroll.add_child(body)
		if game.book_page == "guide":
			var chosen: Dictionary = rows.filter(func(p): return p.id == guide_sel)[0]
			if Goals.page_known(sim, chosen):
				_fill_book_page(body, chosen)
			else:
				body.add_child(_label("???", true, Palette.CHALK, Palette.HEADING))
				var clue := _label(chosen.get("clue", "Not found yet."), false, Palette.CHALK_DIM, Palette.BODY, true)
				clue.custom_minimum_size.x = 420
				body.add_child(clue)
		else:
			_fill_book_goals(body, sim, goals_sel, cur_chapter),
		func() -> void:  # the live pages outlive a rebuild: take them out before the old page is freed
			for n in [_board, _roster]:
				if n.get_parent() != null:
					n.get_parent().remove_child(n))
	if is_instance_valid(_book_scroll):  # the Jobs and Residents pages are as big as they are, up to the room there is
		if live != null:
			var room := get_viewport().get_visible_rect().size.y - TOP_BAR_H - 8.0 - 80.0 - 110.0
			var want := Vector2(maxf(440.0, live.get_combined_minimum_size().x + 8.0), minf(live.get_combined_minimum_size().y, maxf(200.0, room)))
			if not _book_scroll.custom_minimum_size.is_equal_approx(want):
				_book_scroll.custom_minimum_size = want
		elif not _book_scroll.custom_minimum_size.is_equal_approx(Vector2(440, 330)):
			_book_scroll.custom_minimum_size = Vector2(440, 330)


## The Residents page: who needs a look first (hurt or hungry), then who is idle, then everyone else, with what each
## is doing. Click a name to select and centre on them (issue #300).
func _refresh_roster(sim: Sim) -> void:
	if not (game.book_open and game.book_page == "residents"):
		return
	var sig := "%s|" % [game.selection]
	for r in sim.residents:
		sig += "%d%s%s%d%d%s%s;" % [r.id, r.name, _status(sim, r), int(r.hunger / 5), r.get("hurt", 0), r.away, r.map]
	_rebuild(_roster, sig, func(c: Container) -> void:
		var rows: Array = sim.residents.duplicate()
		var rank := func(r: Dictionary) -> int:
			if r.get("hurt", 0) > 0 or r.hunger < Tuning.HUNGRY_BELOW:
				return 0
			return 1 if (r.job == null and not r.away) else 2
		rows.sort_custom(func(a, b): return rank.call(a) < rank.call(b))
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		for h in [["Resident", 128], ["Doing", 230], ["Food", 70], ["", 40]]:
			var l := _label(h[0], true, Palette.CHALK_DIM, Palette.CAPTION)
			l.custom_minimum_size.x = h[1]
			head.add_child(l)
		c.add_child(head)
		for r in rows:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			var who := _button(r.name, func(): game.focus_on("res", r.id))
			who.icon = _swatch_tex(r.shirt)
			who.alignment = HORIZONTAL_ALIGNMENT_LEFT
			who.custom_minimum_size = Vector2(128, 0)
			who.toggle_mode = true
			who.set_pressed_no_signal(game.selection.get("ids", []).has(r.id))
			who.set_meta("label", "Resident: " + r.name)
			who.tooltip_text = "Select %s and centre on them" % r.name
			line.add_child(who)
			var idle: bool = r.job == null and not r.away
			var what := _label(_status(sim, r), false, Palette.YELLOW if idle else Palette.CHALK_DIM, Palette.CAPTION, true)
			what.custom_minimum_size.x = 230
			line.add_child(what)
			var food := _label(_mood(r), false, Palette.YELLOW if r.hunger < Tuning.HUNGRY_BELOW else Palette.CHALK_DIM, Palette.CAPTION)
			food.custom_minimum_size.x = 70
			line.add_child(food)
			var hurt := _label("Hurt" if r.get("hurt", 0) > 0 else "", false, Palette.YELLOW, Palette.CAPTION)
			hurt.custom_minimum_size.x = 40
			line.add_child(hurt)
			c.add_child(line))


## One chapter of the book's Goals tab (issue #371): its why, then each step with its hint and why. A chapter the
## book hasn't reached shows nothing but that it's ahead.
func _fill_book_goals(c: Container, sim: Sim, ch: int, current: int) -> void:
	var info: Dictionary = Goals.CHAPTERS[ch]
	var rows: Array = []  # [goal, done]
	if ch < 3:
		for i in Goals.LIST.size():
			if Goals.LIST[i].c == ch:
				rows.append([Goals.LIST[i], Goals.done(sim, i)])
	else:
		for i in Goals.VILLAGE.size():
			rows.append([Goals.VILLAGE[i], Goals.village_done(sim, i)])
	var finished := rows.filter(func(r): return r[1]).size()
	c.add_child(_label("%d  %s    %d of %d" % [ch + 1, info.name, finished, rows.size()], true, Palette.GREEN if finished == rows.size() else Palette.CHALK, Palette.BODY))
	var why := _label(info.why, false, Palette.CHALK_DIM, Palette.CAPTION, true)
	why.custom_minimum_size.x = 420
	c.add_child(why)
	var first_open := true
	for r in rows:
		var g: Dictionary = r[0]
		var mark := "√" if r[1] else (">" if first_open and ch == current else "·")
		first_open = first_open and r[1]
		var t := _label("%s  %s" % [mark, g.t], true, Palette.GREEN if r[1] else Palette.CHALK, Palette.BODY, true)
		t.custom_minimum_size.x = 420
		c.add_child(t)
		var w := _label(g.w, false, Palette.CHALK_DIM, Palette.CAPTION, true)
		w.custom_minimum_size.x = 420
		c.add_child(w)
	if finished == rows.size():
		var note := _label(info.note, false, Palette.GREEN, Palette.CAPTION, true)
		note.custom_minimum_size.x = 420
		c.add_child(note)


func _fill_book_page(c: Container, p: Dictionary) -> void:
	c.add_child(_label(p.title, true, Palette.CHALK, Palette.HEADING))
	for line in [["What it's for", p.what], ["Who works it", p.who], ["What it grows into", p.grows], ["Without it", p.without]]:
		c.add_child(_label(line[0], true, Palette.CHALK_DIM, Palette.CAPTION))
		var l := _label(line[1], false, Palette.CHALK, Palette.BODY, true)
		l.custom_minimum_size.x = 420
		c.add_child(l)


## The stuck list (issue #77) hangs off a tab below the top bar. The tab is always there, with a count and
## a flag when something needs a look; the list opens under it only when the player clicks it. It has two
## tiers. Blockers, work that can't go on, get a yellow flag, oldest first. Standing orders short of
## materials only wait: one dim line that opens on click.
func _refresh_stuck(sim: Sim) -> void:
	var vis := sim.stuck.filter(func(s): return not s.hidden)
	var need := vis.filter(func(s): return s.get("decision", "") != "")
	var block := vis.filter(func(s): return not s.waiting)
	var wait := vis.filter(func(s): return s.waiting and s.get("decision", "") == "")
	block.sort_custom(func(a, b): return a.since < b.since or (a.since == b.since and vis.find(a) < vis.find(b)))
	var n := need.size() + block.size()
	var tint: Color = Palette.YELLOW if not block.is_empty() else (Palette.BLUE if not need.is_empty() else Palette.CHALK_DIM)
	_stuck_tab.text = "Stuck" if n == 0 else "Stuck  %d" % n
	_stuck_tab.icon = MarkTextures.flag() if not block.is_empty() else null
	_stuck_tab.add_theme_constant_override("icon_max_width", 14)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		_stuck_tab.add_theme_color_override(state, tint)
	_stuck_tab.set_pressed_no_signal(stuck_open)
	_stuck_tab.tooltip_text = "Show what’s stuck" if not stuck_open else "Hide the stuck list"
	_stuck_panel.visible = stuck_open
	if not stuck_open:
		return
	var sig := "%s%s" % [stuck_open, waiting_open]
	for s in need + block + wait:
		sig += s.who + s.why + ";"
	_rebuild(_stuck, sig, func(c: Container) -> void:
		if vis.is_empty():
			c.add_child(_label("Nothing is stuck.", false, Palette.CHALK_DIM, Palette.BODY))
			return
		if not need.is_empty():  # choices waiting for the player, apart from what's wrong (issue #296)
			var ask := _label("Needs you (%d)" % need.size(), true, Palette.BLUE, Palette.HEADING)
			c.add_child(ask)
			for s in need:
				c.add_child(_decision_entry(sim, s))
			if not block.is_empty() or not wait.is_empty():
				c.add_child(_rule())
		if not block.is_empty():
			var head := _label("Stuck (%d)" % block.size(), true, Palette.YELLOW, Palette.HEADING)
			c.add_child(head)
			for s in block:
				c.add_child(_stuck_entry(sim, s, false))
		if wait.is_empty():
			return
		if not block.is_empty():
			c.add_child(_rule())
		var line := _button("%d waiting   %s" % [wait.size(), "↑" if waiting_open else "↓"], func(): waiting_open = not waiting_open)
		line.alignment = HORIZONTAL_ALIGNMENT_LEFT
		for state in ["font_color", "font_focus_color"]:
			line.add_theme_color_override(state, Palette.CHALK_DIM)
		line.tooltip_text = "Standing orders short of materials for now, and an expedition being packed. Nothing is blocked."
		c.add_child(line)
		if waiting_open:
			for s in wait:
				c.add_child(_stuck_entry(sim, s, true)),
		Callable(), "%d|%d|%d|%s" % [need.size(), block.size(), wait.size(), waiting_open])
	_place_drop(_stuck_panel, Vector2(_stuck_tab.get_global_rect().end.x - _stuck_panel.get_combined_minimum_size().x, _stuck_tab.get_global_rect().end.y + 2))


## A choice waiting for the player (issue #296): what it is, and the buttons that answer it, so it needs no hunting for the panel.
func _decision_entry(sim: Sim, s: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var b := _button("%s\n%s" % [s.who, s.why], func(): game.focus_on(s.focus_kind, s.focus_id, s.map))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 44)
	for state in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(state, Palette.BLUE)
	v.add_child(b)
	if s.decision == "freight":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var yes := _button("Approve departure", func(): game.approve_freight(), "Primary")
		yes.set_meta("label", "Needs you: Approve departure")
		yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var no := _button("Decline", func(): game.decline_freight(), "Secondary")
		no.set_meta("label", "Needs you: Decline")
		no.tooltip_text = "Unload the cart back into the stockpile"
		row.add_child(yes)
		row.add_child(no)
		v.add_child(row)
	return v


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
	for p in [_goals_tab, _party_panel]:  # clear of the tutorial's tab and the party's panel
		if p.visible:
			left = maxf(left, p.get_global_rect().end.x + 12)
	var right := _stuck_tab.get_global_rect().position.x - 12  # clear of the stuck tab
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
	_log.append({"text": ev.text, "tick": game.sim.tick if game.sim != null else 0, "res_id": ev.get("res_id", 0), "site_id": ev.get("site_id", 0)})
	if _log.size() > LOG_MAX:
		_log.pop_front()
	if not _log_open:
		_log_unread += 1
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


# ---------------------------------------------------------------- the minimap (issue #298)

func toggle_minimap() -> void:
	minimap_on = not minimap_on
	_refresh_minimap()


## Shown in the bottom right corner, to the right of the orders toolbar, as part of that corner's row, so it stays put while menus and panels open and close.
func _refresh_minimap() -> void:
	_minimap.visible = minimap_on and not game._menu.visible and not game.world_map_open
	if not _minimap.visible:
		return
	var side := MiniMap.side_for(get_viewport().get_visible_rect().size)  # smaller on a short screen, so it never reaches the top bar or the Menu button (issue #347)
	_minimap.custom_minimum_size = Vector2(side, side)
	_minimap.size = Vector2(side, side)


# ---------------------------------------------------------------- the message log (issue #297)

func _toggle_log() -> void:
	_log_open = not _log_open
	if _log_open:
		_log_unread = 0
	_refresh_log()


## "12:05": the game time a message was shown at.
func _log_time(tick: int) -> String:
	var secs := tick / Tuning.TPS
	return "%d:%02d" % [secs / 60, secs % 60]


## The button says how many are new; the list, newest first, is each message with when it was said and a way to the place.
func _refresh_log() -> void:
	_log_btn.text = "Log" if _log_unread == 0 else "Log  (%d new)" % _log_unread
	_log_btn.tooltip_text = "What the messages said, newest first. Click one's button to go there."
	_log_panel.visible = _log_open
	if not _log_open:
		return
	_place_drop(_log_panel, Vector2(_log_btn.get_global_rect().end.x - 430.0 - 16.0, _log_btn.get_global_rect().end.y + 8.0))
	var cap := get_viewport().get_visible_rect().size.y - _log_panel.position.y - 24.0
	_log_panel.get_child(0).custom_minimum_size.y = clampf(cap, 80.0, 440.0)
	_rebuild(_log_list, "%d" % _log.size() + str(_log.back().text if not _log.is_empty() else ""), func(c: Container) -> void:
		if _log.is_empty():
			c.add_child(_label("Nothing yet. The messages that pop up will be kept here.", false, Palette.CHALK_DIM, Palette.BODY, true))
			return
		for i in range(_log.size() - 1, -1, -1):
			var e: Dictionary = _log[i]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var t := _label(_log_time(e.tick), false, Palette.CHALK_DIM, Palette.CAPTION)
			t.custom_minimum_size.x = 44
			row.add_child(t)
			var msg := _label(e.text, false, Palette.CHALK, Palette.BODY, true)
			msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(msg)
			if e.res_id:
				row.add_child(_button("Go", func(): game.focus_on("res", e.res_id), "Secondary"))
			elif e.site_id:
				row.add_child(_button("Show", func(): game.focus_on("site", e.site_id), "Secondary"))
			c.add_child(row))


# ---------------------------------------------------------------- selection panel

# The drawing lives in selection_panel.gd (#305); these forward to it.

func _refresh_selection(sim: Sim) -> void:
	_selection_panel_of()._refresh_selection(sim)


func _fill_selection(c: Container, sim: Sim, sel: Dictionary, target) -> void:
	_selection_panel_of()._fill_selection(c, sim, sel, target)


func _add_keep(c: Container, sim: Sim, target: Dictionary) -> void:
	_selection_panel_of()._add_keep(c, sim, target)


func _refresh_craft(sim: Sim) -> void:
	_selection_panel_of()._refresh_craft(sim)


func _blocked_sites(sim: Sim) -> Array:
	return _selection_panel_of()._blocked_sites(sim)


func _station_tabs(sim: Sim, list: Array, current: Dictionary) -> Control:
	return _selection_panel_of()._station_tabs(sim, list, current)


func _add_jobs_summary(c: Container, sim: Sim, r: Dictionary) -> void:
	_selection_panel_of()._add_jobs_summary(c, sim, r)


func _job_picker(sim: Sim, r: Dictionary) -> Control:
	return _selection_panel_of()._job_picker(sim, r)


func _close_job_drop() -> void:
	_selection_panel_of()._close_job_drop()


func _refresh_job_drop(sim: Sim) -> void:
	_selection_panel_of()._refresh_job_drop(sim)


func _refresh_board(sim: Sim) -> void:
	_selection_panel_of()._refresh_board(sim)


func _wild_herds(sim: Sim) -> Dictionary:
	return _selection_panel_of()._wild_herds(sim)


func _add_herd_floors(c: Container, sim: Sim, herds: Dictionary) -> void:
	_selection_panel_of()._add_herd_floors(c, sim, herds)


func _add_wheat_keep(c: Container, sim: Sim) -> void:
	_selection_panel_of()._add_wheat_keep(c, sim)


func _board_cell(r: Dictionary, jb: String) -> Control:
	return _selection_panel_of()._board_cell(r, jb)


func _add_armor_row(c: Container, r: Dictionary) -> void:
	_selection_panel_of()._add_armor_row(c, r)


func _add_tool_row(c: Container, sim: Sim, r: Dictionary, kind: String) -> void:
	_selection_panel_of()._add_tool_row(c, sim, r, kind)


func _status(sim: Sim, r: Dictionary) -> String:
	return _selection_panel_of()._status(sim, r)


func _fill_animal(c: Container, sim: Sim, a: Dictionary) -> void:
	_selection_panel_of()._fill_animal(c, sim, a)


func _fill_pen(c: Container, sim: Sim, p: Dictionary) -> void:
	_selection_panel_of()._fill_pen(c, sim, p)


func _fill_signpost(c: Container, sim: Sim, id: String) -> void:
	_selection_panel_of()._fill_signpost(c, sim, id)


func _tool_text(t: Dictionary) -> String:
	return _selection_panel_of()._tool_text(t)


func _fill_site(c: Container, sim: Sim, s: Dictionary) -> void:
	_selection_panel_of()._fill_site(c, sim, s)


func _make_keep_row(sim: Sim, s: Dictionary) -> Control:
	return _selection_panel_of()._make_keep_row(sim, s)


func _station_line(sim: Sim, s: Dictionary) -> String:
	return _selection_panel_of()._station_line(sim, s)


func _bench_status(sim: Sim, s: Dictionary) -> String:
	return _selection_panel_of()._bench_status(sim, s)


func _fill_bench(c: Container, sim: Sim, s: Dictionary) -> void:
	_selection_panel_of()._fill_bench(c, sim, s)


func _have(sim: Sim, s: Dictionary, k: String) -> int:
	return _selection_panel_of()._have(sim, s, k)


func _short(sim: Sim, s: Dictionary, rec: Dictionary) -> Array:
	return _selection_panel_of()._short(sim, s, rec)


func _slot(type: String, n := 1, size := 40, outline := Palette.CHALK_DIM, dim := false) -> PanelContainer:
	return _selection_panel_of()._slot(type, n, size, outline, dim)


func _book_slot(sim: Sim, s: Dictionary, rec: Dictionary, chosen: bool) -> Button:
	return _selection_panel_of()._book_slot(sim, s, rec, chosen)


func _crafting_grid(sim: Sim, s: Dictionary, rec: Dictionary) -> Control:
	return _selection_panel_of()._crafting_grid(sim, s, rec)


func _furnace(sim: Sim, s: Dictionary, rec: Dictionary) -> Control:
	return _selection_panel_of()._furnace(sim, s, rec)


func _arrow() -> Control:
	return _selection_panel_of()._arrow()


func _queue_control(s: Dictionary, rec: Dictionary) -> Control:
	return _selection_panel_of()._queue_control(s, rec)


func _hotbar(sim: Sim, s: Dictionary) -> Control:
	return _selection_panel_of()._hotbar(sim, s)


func _craft_progress(sim: Sim, s: Dictionary) -> float:
	return _selection_panel_of()._craft_progress(sim, s)


func _on_hand(sim: Sim, s: Dictionary) -> Control:
	return _selection_panel_of()._on_hand(sim, s)


## Which workstations exist and who has each (issue #184), for panels that show them.
static func _stations_sig(sim: Sim) -> String:
	return str(sim.maps.village.sites.filter(func(st): return st.done and Defs.JOB_STATIONS.values().has(st.tpl)).map(func(st): return [st.id, st.get("worker", 0)]))


## "farmer", "2 farmers".
static func _job_people(jb: String, n: int) -> String:
	return Defs.JOB_SKILLED[jb] + ("" if n == 1 else "s")


## "On the way to the meadow, 22 s", "On the way home, 22 s" or "On the road home, 22 s".
static func _road_text(sim: Sim, r: Dictionary) -> String:
	var meadow: bool = sim.expedition_of(r).get("dest", "") == Meadow.ID
	if r.trip == "village":
		return "On the %s home, %d s" % ["way" if meadow else "road", ceili(sim.back_in(r))]
	return "On the %s to the %s, %d s" % ["way" if meadow else "road", sim.get_map(r.trip).name.to_lower(), ceili(sim.back_in(r))]


const HOTBAR := 8


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

# The drawing lives in planner_panel.gd (#305); these forward to it.

func _refresh_planner(sim: Sim) -> void:
	_planner()._refresh_planner(sim)


func _refresh_planner_slot(sim: Sim) -> void:
	_planner()._refresh_planner_slot(sim)


func _fill_planner(c: Container, sim: Sim) -> void:
	_planner()._fill_planner(c, sim)


func _location_button(sim: Sim, rows: Array) -> Button:
	return _planner()._location_button(sim, rows)


func _place_drop(drop: Control, pos: Vector2) -> void:
	_planner()._place_drop(drop, pos)


func _close_loc_drop() -> void:
	_planner()._close_loc_drop()


func _refresh_loc_drop(sim: Sim) -> void:
	_planner()._refresh_loc_drop(sim)


func _add_cargo_list(c: Container, plan: Dictionary, tend: bool) -> void:
	_planner()._add_cargo_list(c, plan, tend)


func _fill_plan(c: Container, sim: Sim) -> void:
	_planner()._fill_plan(c, sim)


func _add_site_report(c: Container, sim: Sim, dest: String) -> void:
	_planner()._add_site_report(c, sim, dest)


func _add_level_picker(c: Container, sim: Sim, plan: Dictionary) -> void:
	_planner()._add_level_picker(c, sim, plan)


func _add_party_picker(c: Container, sim: Sim, plan: Dictionary) -> void:
	_planner()._add_party_picker(c, sim, plan)


func _add_objectives(c: Container, sim: Sim, plan: Dictionary) -> void:
	_planner()._add_objectives(c, sim, plan)


func _add_plan_details(c: Container, sim: Sim, plan: Dictionary) -> void:
	_planner()._add_plan_details(c, sim, plan)


func _protection_text(sim: Sim, party: Array) -> String:
	return _planner()._protection_text(sim, party)


func _pens_text(sim: Sim) -> String:
	return _planner()._pens_text(sim)


func _add_packs(c: Container, plan: Dictionary) -> void:
	_planner()._add_packs(c, plan)


func _stepper_row(name: String, value: int, key: String) -> HBoxContainer:
	return _planner()._stepper_row(name, value, key)


func _stepper(value: String, key: String) -> HBoxContainer:
	return _planner()._stepper(value, key)


func _fill_staging(c: Container, sim: Sim) -> void:
	_planner()._fill_staging(c, sim)


func _fill_out(c: Container, sim: Sim) -> void:
	_planner()._fill_out(c, sim)


func _add_call_home(c: Container, sim: Sim) -> void:
	_planner()._add_call_home(c, sim)


func _fill_route(c: Container, sim: Sim) -> void:
	_planner()._fill_route(c, sim)


func _fill_station(c: Container, sim: Sim, s: Dictionary) -> void:
	_planner()._fill_station(c, sim, s)


func _add_line(c: Container, sim: Sim) -> void:
	_planner()._add_line(c, sim)


static func _mood(r: Dictionary) -> String:
	return "Starving" if r.hunger <= 0.0 else ("Hungry" if r.hunger < Tuning.HUNGRY_BELOW else ("Peckish" if r.hunger < Tuning.EAT_BELOW else "Fed"))


func _board_status(sim: Sim) -> String:
	return _planner()._board_status(sim)



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
	if ex.target.item == "survey":  # issue #148
		c.add_child(_row("Survey the landing", "walk to its landmarks"))
		c.add_child(_label("The party steps through the portal, walks to each landmark and comes home. A shelter comes later.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
	elif ex.target.item == "pens":  # issue #139
		c.add_child(_row("Tend the pens", "keep %d of each" % ex.target.n))
		c.add_child(_label(_pens_text(sim), false, Palette.CHALK_DIM, Palette.CAPTION, true))
	else:
		if ex.get("clear", false):  # clear the level (issue #188): what's left on the level being worked
			c.add_child(_row("Clearing the level", "%d blocks left" % sim.level_left()))
		for r in Sim.cargo_rows(ex):  # one line a row of the cargo list (issue #185)
			c.add_child(_row("Bring back %s" % Defs.ITEMS[r.item].many, "%d / %s" % [sim.cargo_have(r.item), str(r.n) if r.n > 0 else "as much as fits"]))
			if r.n > 0:
				c.add_child(_bar(float(sim.cargo_have(r.item)) / r.n, Palette.GREEN))
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
