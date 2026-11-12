class_name PlannerPanel
extends RefCounted
## Split out of hud.gd (#305). It draws with the HUD's own helpers and state, reached through `hud`; Hud keeps one-line forwarders for what the rest of it calls.

var hud: Hud
var game


func _init(h: Hud, g) -> void:
	hud = h
	game = g


## The planner opens above the toolbar when the board is selected. With no expedition it draws up a
## plan; while one is packing it shows the packing and Depart; while one is out it says so.
func _refresh_planner(sim: Sim) -> void:
	var prev := sim.use_slot(game.plan_slot())  # the planner shows the realm of the chosen adventure (issue #145)
	_refresh_planner_slot(sim)
	sim.use_slot(prev)


func _refresh_planner_slot(sim: Sim) -> void:
	var board := sim.expedition_board()
	hud._plan_panel.visible = game.planner_open and not board.is_empty()
	if not hud._plan_panel.visible:
		return
	hud._plan_panel.custom_minimum_size.x = 0 if sim.expedition.is_empty() else 400
	var dest: String = sim.expedition.get("dest", game.plan.get("dest", OldMine.ID))
	var sig := "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [game.plan, sim.expedition, board.store, board.get("report", []), sim.stuck.map(func(x): return x.why), sim.site_report(dest), game.adventure, sim.adventures(), hud._loc_open]
	for r in sim.residents:
		sig += "%d%s%s%s%d%d%s%s;" % [r.id, sim.cant_join(r), sim.at_board(r), r.pick, int(r.hunger / 10), ceili(sim.back_in(r)), r.map, r.away]
		sig += r.job.label if r.job != null else "Idle"
	hud._rebuild(hud._plan_box, sig, func(c: Container) -> void:
		_fill_planner(c, sim)
		if not sim.expedition.is_empty():  # the packing view is a single 400-wide column (the panel's width less its margins)
			hud._pin_wrap(c, 400 - 24),
		Callable(), "%s|%s|%s" % [sim.expedition.get("state", ""), dest, game.adventure])


func _fill_planner(c: Container, sim: Sim) -> void:
	var rows := sim.adventures()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := hud._label("Expedition board", true, Palette.CHALK, Palette.HEADING)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_location_button(sim, rows))
	head.add_child(hud._button("Close", func(): game.close_planner(), "Secondary"))
	c.add_child(head)
	match sim.expedition.get("state", ""):
		"staging":
			_fill_staging(c, sim)
		"out":
			_fill_out(c, sim)
		_:
			if rows.is_empty():
				c.add_child(hud._label("Nobody knows of anywhere to go yet. Walk the signpost at the village's edge to learn of a place.", false, Palette.CHALK_DIM, Palette.BODY, true))
				return
			if game.adventure == "" or not rows.any(func(a): return a.id == game.adventure):
				game.adventure = rows[0].id
			if game.plan.is_empty() or not game.plan_matches_adventure():  # the planner was left open while an expedition ended
				game.plan = sim.new_plan(game.adventure)
			if sim.last_plans.has(game.plan.dest):  # one click to what was packed last time (issue #301)
				var again := hud._button("Repeat last trip", func(): game.repeat_last_trip(), "Secondary")
				again.tooltip_text = "Fill in the party, objective, list and meals of the last trip here. Anyone who can't go is replaced."
				again.set_meta("label", "Repeat last trip")
				again.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				c.add_child(again)
			_fill_plan(c, sim)


## The board's Location dropdown (issue #181): the chosen place and its travel time, which opens a list of
## every known destination. While a party is packing or out it shows theirs and the list is read-only.
func _location_button(sim: Sim, rows: Array) -> Button:
	var busy: bool = not sim.expedition.is_empty()
	var here: String = sim.expedition.get("dest", game.adventure)
	var cur := rows.filter(func(a): return a.id == here)
	var text := "Nowhere known yet"
	if not cur.is_empty():
		text = "%s%s" % [cur[0].name, " · ~%d s each way" % roundi(cur[0].travel) if cur[0].travel >= 0.0 else ""]
	var b := hud._button(text + "  ↓", func(): pass, "Secondary")
	b.set_meta("label", "Location: " + text)
	b.disabled = rows.is_empty()
	b.tooltip_text = "One expedition at a time" if busy else "Choose where to go"
	b.pressed.connect(func() -> void:
		if hud._loc_open:
			_close_loc_drop()
		else:
			hud._loc_open = true
			hud._loc_button = b
			hud._loc_anchor = b.get_global_rect())
	return b


## Puts a dropdown at `pos`, kept wholly inside the visible area on every side (a browser window is rarely
## 16:9, so what fits on the desktop can run off the edge there).
func _place_drop(drop: Control, pos: Vector2) -> void:
	var view := hud.get_viewport().get_visible_rect()
	var sz := drop.get_combined_minimum_size()
	drop.position = Vector2(clampf(pos.x, view.position.x + 8.0, maxf(view.position.x + 8.0, view.end.x - sz.x - 8.0)),
			clampf(pos.y, view.position.y + 8.0, maxf(view.position.y + 8.0, view.end.y - sz.y - 8.0)))


func _close_loc_drop() -> void:
	hud._loc_open = false
	hud._loc_button = null
	hud._loc_anchor = Rect2()
	hud._loc_drop.visible = false


## The list under the Location button: one line a destination, its travel time and status beside it, and a
## yellow flag where hazards are known. While a party is out the lines are shown but can't be chosen.
func _refresh_loc_drop(sim: Sim) -> void:
	if not hud._loc_open or not hud._plan_panel.visible:
		_close_loc_drop()
		return
	hud._loc_drop.visible = true
	var h := hud._loc_drop.get_combined_minimum_size().y
	if is_instance_valid(hud._loc_button) and hud._loc_button.is_visible_in_tree():
		hud._loc_anchor = hud._loc_button.get_global_rect()  # live: the board can move or resize after it opens
	var w := hud._loc_drop.get_combined_minimum_size().x
	var below := hud._loc_anchor.end.y + 4 + h <= hud.get_viewport().get_visible_rect().size.y
	_place_drop(hud._loc_drop, Vector2(hud._loc_anchor.end.x - w, hud._loc_anchor.end.y + 4 if below else hud._loc_anchor.position.y - 4 - h))
	var rows := sim.adventures()
	hud._rebuild(hud._loc_list, "%s|%s" % [rows, game.adventure], func(c: Container) -> void:
		for a in rows:
			var line := "%s · %s · %s" % [a.name, "~%d s" % roundi(a.travel) if a.travel >= 0.0 else "road not walked", a.status]
			if not a.hazards.is_empty():
				line += "  !"
			var b := hud._button(line, func():
				game.open_adventure(a.id)
				_close_loc_drop(), "Secondary")
			b.set_meta("label", "Adventure: " + a.name)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.disabled = a.locked
			b.toggle_mode = true
			b.set_pressed_no_signal(a.id == game.adventure)
			var hz: String = "Hazards: " + "; ".join(a.hazards) if not a.hazards.is_empty() else "No hazards known yet"
			b.tooltip_text = ("One expedition at a time. " if a.locked else "") + hz
			c.add_child(b))


## The cargo priority list (issue #185): what to bring back, best first. Each row has a toggle (an item that's
## off is left), its name, how many are wanted (Max: as much as fits), and ↑ ↓ to reorder. The packs' bar below
## shows the wanted amounts against the room.
func _add_cargo_list(c: Container, plan: Dictionary, tend: bool) -> void:
	if plan.target.item in ["survey", "scout", "build", "trade", "fortress", "rescue"]:  # these bring nothing back: the objective row says what they do (issues #148, #154)
		return
	var head := HBoxContainer.new()
	var l := hud._label("Bring back, best first", true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	if tend:
		head.add_child(hud._label("Tending the pens", false, Palette.CHALK_DIM, Palette.CAPTION))
	c.add_child(head)
	var clear: bool = plan.get("clear", false)
	if plan.dest != Meadow.ID and not tend:  # clear the level (issue #188)
		var cb := hud._button("Clear the level", func(): game.plan_clear_toggle(), "Secondary")
		cb.toggle_mode = true
		cb.set_pressed_no_signal(clear)
		cb.tooltip_text = "Work every block of what's ticked below, nearest the entrance first. Once the level is cleared the party digs to the door itself and goes down, and carries on until the packs are full, the food runs low or someone is badly hurt."
		c.add_child(cb)
		if clear:
			c.add_child(hud._label("Every amount below is as much as fits. They go down a level when this one's cleared.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
	var list: Array = plan.get("list", [])
	for i in list.size():
		var row: Dictionary = list[i]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		var on := hud._button("√" if row.on and not tend else "", func(): game.plan_cargo_toggle(i), "Secondary")
		on.toggle_mode = true
		on.set_pressed_no_signal(row.on and not tend)
		on.custom_minimum_size = Vector2(28, 0)
		on.set_meta("label", "Bring back: " + Defs.ITEMS[row.item].label)
		on.tooltip_text = "Bring it back" if not row.on else "Leave it"
		h.add_child(on)
		var name := hud._label("%s%s" % [Defs.ITEMS[row.item].label, "  New" if row.get("new", false) else ""], false, Palette.CHALK if row.on and not tend else Palette.CHALK_DIM)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(name)
		var up := hud._button("↑", func(): game.plan_cargo_move(i, -1), "Secondary")
		up.disabled = i == 0
		up.tooltip_text = "Bring it back before the one above"
		up.set_meta("label", "%s up" % Defs.ITEMS[row.item].label)
		var down := hud._button("↓", func(): game.plan_cargo_move(i, 1), "Secondary")
		down.disabled = i == list.size() - 1
		down.tooltip_text = "Bring it back after the one below"
		down.set_meta("label", "%s down" % Defs.ITEMS[row.item].label)
		for b in [up, down]:
			b.add_theme_font_size_override("font_size", Palette.CAPTION)
		h.add_child(up)
		h.add_child(down)
		var less := hud._button("−", func(): game.plan_cargo_amount(i, -1), "Secondary")
		less.disabled = row.n <= 0 or clear
		less.set_meta("label", "%s less" % Defs.ITEMS[row.item].label)
		var amount := hud._label("Max" if row.n <= 0 or clear else "%d" % row.n, false, Palette.CHALK if row.on and not tend else Palette.CHALK_DIM)
		amount.custom_minimum_size.x = 34
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount.tooltip_text = "How many to bring back. Max takes as much as fits."
		amount.mouse_filter = Control.MOUSE_FILTER_STOP
		var more := hud._button("+", func(): game.plan_cargo_amount(i, 1), "Secondary")
		more.disabled = clear
		more.set_meta("label", "%s more" % Defs.ITEMS[row.item].label)
		h.add_child(less)
		h.add_child(amount)
		h.add_child(more)
		c.add_child(h)


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
		left.add_child(hud._label("Last expedition", true))
		for line in last:
			left.add_child(hud._label(line + ".", false, Palette.CHALK_DIM, Palette.CAPTION, true))
		left.add_child(hud._rule())
	_add_level_picker(left, sim, plan)
	_add_site_report(left, sim, plan.dest)
	left.add_child(hud._rule())
	_add_party_picker(left, sim, plan)
	_add_plan_details(right, sim, plan)


## The site report (brief §8): what the village knows of the place before anyone sets off.
func _add_site_report(c: Container, sim: Sim, dest: String) -> void:
	var rep := sim.site_report(dest)
	c.add_child(hud._row(rep.name, "about %d s walk each way" % roundi(rep.travel) if rep.travel >= 0.0 else "the road isn’t walked yet", false))
	if rep.visited and rep.get("pattern", "") != "":
		c.add_child(hud._label(rep.pattern if rep.get("biome", "") == "" else "%s · %s" % [rep.biome, rep.pattern], false, Palette.CHALK_DIM, Palette.CAPTION))
	if not rep.visited:
		c.add_child(hud._label("“%s”" % rep.told, false, Palette.CHALK_DIM, Palette.BODY, true))
	for x in rep.resources:
		c.add_child(hud._row(x.name, "?" if x.reserve < 0 else "about %d" % x.reserve))
	for f in rep.get("finds", []):
		c.add_child(hud._label(f, true, Palette.CHALK, Palette.BODY, true))
	if not rep.visited:
		c.add_child(hud._label("Nobody has been there yet: no estimates, and no hazards known.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
		return
	for hz in rep.hazards:
		c.add_child(hud._label("Hazard: " + hz, false, Palette.YELLOW, Palette.BODY, true))
	for a in rep.access:
		c.add_child(hud._label(a, false, Palette.CHALK_DIM, Palette.BODY, true))
	if rep.get("levels", []).size() > 1:  # every level known so far (issue #132)
		c.add_child(hud._label("Levels", true))
		for lv in rep.levels:
			var ore: String = "%d ore blocks left" % lv.ore if lv.ore >= 0 else "not visited"
			c.add_child(hud._row("%d  %s" % [lv.level, lv.pattern], "%s, %s" % [ore, lv.door]))


## The levels a plan can be made for (issue #132): a button per level once there's more than one.
func _add_level_picker(c: Container, sim: Sim, plan: Dictionary) -> void:
	var levels := sim.mine_levels()
	if levels.size() < 2 or sim.level_of(plan.dest) == 0:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(hud._label("Work level", true))
	for id in levels:
		var n := sim.level_of(id)
		var b := hud._button(str(n), func(): game.plan_dest(id), "Secondary")
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
	c.add_child(hud._row("Party", "%d of up to %d" % [plan.party.size(), Tuning.PARTY_MAX], false))
	var can_go := sim.residents.filter(func(r): return sim.cant_join(r) == "" and not plan.party.has(r.id)).size()
	var fill := HBoxContainer.new()
	var fill_b := hud._button("Fill the party", func(): game.plan_fill(), "Secondary")
	fill_b.set_meta("label", "Fill the party")
	fill_b.disabled = can_go == 0 or plan.party.size() >= Tuning.PARTY_MAX
	fill_b.tooltip_text = "Takes the best fit among those who can go, up to %d" % Tuning.PARTY_MAX
	var clear_b := hud._button("Unselect all", func(): game.plan_clear(), "Secondary")
	clear_b.set_meta("label", "Unselect all")
	clear_b.disabled = plan.party.is_empty()
	fill.add_child(fill_b)
	fill.add_child(clear_b)
	c.add_child(fill)
	for r in sim.residents:
		var why := sim.cant_join(r)
		var on: bool = plan.party.has(r.id)
		var pick: String = Defs.ITEMS[r.pick.type].one if r.pick != null else "no pickaxe"
		var line: String = why if why != "" else "Stonemason level %d, %s, %s" % [Sim.level(r, "mason"), pick, hud._mood(r).to_lower()]
		if why == "" and plan.dest == Meadow.ID:  # at the meadow it's hunting that counts, and no pickaxe is needed
			line = "Hunt level %d, %s" % [Sim.level(r, "hunt"), hud._mood(r).to_lower()]
		var b := hud._button("%s\n%s" % [r.name, line], func(): game.plan_toggle(r.id), "Secondary")
		b.set_meta("label", r.name)
		b.toggle_mode = true
		b.set_pressed_no_signal(on)
		b.icon = hud._swatch_tex(r.shirt)
		b.add_theme_constant_override("icon_max_width", 14)
		b.add_theme_constant_override("h_separation", 10)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = why != "" or (not on and plan.party.size() >= Tuning.PARTY_MAX)
		b.tooltip_text = ("%s can’t go: %s" % [r.name, why.to_lower()]) if why != "" else ("Leave %s at home" % r.name if on else "Take %s" % r.name)
		c.add_child(b)


## The Nether's objective picker (issue #154): one button for each, greyed out with its reason when it has nowhere to go; a scout
## picks a route; then the briefing.
func _add_objectives(c: Container, sim: Sim, plan: Dictionary) -> void:
	c.add_child(hud._label("Objective", true))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	var cur: String = plan.get("objective", "survey")
	for obj in Sim.OBJECTIVES:
		var dests := sim.objective_destinations(obj)
		var b := hud._button(Sim.OBJECTIVES[obj].name, func(): game.plan_objective(obj), "Secondary")
		b.toggle_mode = true
		b.set_pressed_no_signal(obj == cur)
		b.disabled = dests.is_empty()
		b.tooltip_text = Sim.OBJECTIVES[obj].sub if not dests.is_empty() else sim.objective_why_none(obj)
		row.add_child(b)
	c.add_child(row)
	c.add_child(hud._label(Sim.OBJECTIVES[cur].sub, false, Palette.CHALK_DIM, Palette.CAPTION, true))
	if cur == "scout":
		var routes := HFlowContainer.new()
		routes.add_theme_constant_override("h_separation", 4)
		for d in sim.objective_destinations("scout"):
			var rb := hud._button(d.label.replace("route to the ", "").capitalize(), func(): game.plan_objective("scout", d), "Secondary")
			rb.toggle_mode = true
			rb.set_pressed_no_signal(plan.target.get("route", "") == d.route)
			routes.add_child(rb)
		c.add_child(routes)
	for l in sim.plan_briefing(plan):
		c.add_child(hud._label(l, false, Palette.YELLOW if l.begins_with("Risk") or l.begins_with("Danger") else Palette.CHALK_DIM, Palette.CAPTION, true))


## The objective, provisions, spare pickaxes, the packs they share, the return policy, and Start packing.
func _add_plan_details(c: Container, sim: Sim, plan: Dictionary) -> void:
	var tend: bool = plan.target.item in ["pens", "survey"]
	if not plan.party.is_empty():  # issue #140: the party's armor against the hazards
		c.add_child(hud._label(_protection_text(sim, plan.party), false, Palette.CHALK_DIM, Palette.CAPTION, true))
	if Sim.realm_of(plan.dest) == "nether":  # the objective, and what the party is told before it commits (issue #154)
		_add_objectives(c, sim, plan)
	for w in sim.plan_warnings(plan):  # a guard with no sword (issue #150)
		c.add_child(hud._label(w, false, Palette.YELLOW, Palette.CAPTION, true))
	_add_cargo_list(c, plan, tend)
	var meadow: bool = plan.dest == Meadow.ID and not sim.get_map(Meadow.ID).pens.is_empty()
	if meadow:  # issue #139: or tend the pens
		var pr := HBoxContainer.new()
		pr.add_theme_constant_override("separation", 6)
		var tb := hud._button("Tend the pens", func(): game.plan_target("pens"), "Secondary")
		tb.toggle_mode = true
		tb.set_pressed_no_signal(tend)
		pr.add_child(tb)
		var pg := Control.new()
		pg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pr.add_child(pg)
		if tend:
			pr.add_child(hud._label("Keep of each", false, Palette.CHALK_DIM, Palette.CAPTION))
			pr.add_child(_stepper("%d" % plan.target.n, "target"))
		c.add_child(pr)
		if tend:
			c.add_child(hud._label("Build the pens, lead marked animals in, feed pairs, and hunt only what's over %d of each kind." % plan.target.n, false, Palette.CHALK_DIM, Palette.CAPTION, true))
	c.add_child(_stepper_row("Meals to take", plan.meals, "meals"))
	if plan.target.item in ["line", "pline"]:  # what the line crew carries, past its meals (issues #159, #168)
		for k in [["Rails", "rails"], ["Planks", "planks"], ["Cobblestone", "cobble"], ["Minecarts", "minecarts"]]:
			c.add_child(_stepper_row(k[0], plan.get(k[1], 0), k[1]))
	if plan.target.item == "trade":  # the gold carried, which takes room in the packs (issue #156)
		c.add_child(_stepper_row("Gold to trade", plan.get("gold", 0), "gold"))
	if Sim.realm_of(plan.dest) == "nether":  # the landing's shelter and cache (issue #152)
		if plan.get("shelter", false):
			c.add_child(hud._label("Carrying the shelter: %s and %s. The party builds it before it comes home." % [Defs.words("cobble", plan.cobble), Defs.words("plank", plan.planks)], false, Palette.CHALK_DIM, Palette.CAPTION, true))
		else:
			c.add_child(_stepper_row("Meals for the cache", plan.get("stock", 0), "stock"))
	var keep := Sim.return_meals(plan)
	var mins := Sim.site_minutes(plan)
	var at := "the meadow" if plan.dest == Meadow.ID else ("the landing" if Sim.realm_of(plan.dest) == "nether" else "the mine")
	var feeds := "About %d min at %s" % [roundi(mins), at] if mins >= 1.0 else "Not enough to eat at %s" % at
	var food := "%s, the return food too." % feeds if plan.spend_return else "%s. %d kept for the walk home." % [feeds, keep]
	var food_row := HBoxContainer.new()
	food_row.add_theme_constant_override("separation", 8)
	var food_l := hud._label(food, false, Palette.CHALK_DIM, Palette.CAPTION, true)
	food_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	food_row.add_child(food_l)
	var spend := hud._button("Spend it", func(): game.plan_spend_return(), "Secondary")
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
			c.add_child(hud._label(t[0].to_upper() + t.substr(1) + ".", false, Palette.CHALK_DIM, Palette.CAPTION, true))
	_add_packs(c, plan)
	var home := hud._label("Come home when", true)
	home.tooltip_text = "Any of the chosen ones brings them home. A serious injury always does, and stops the game for you."
	home.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(home)
	var policy := HBoxContainer.new()
	policy.add_theme_constant_override("separation", 4)
	for k in [["target", "Target reached"], ["full", "Packs full"], ["low", "Food runs low"]]:
		var b := hud._button(k[1], func(): game.plan_policy(k[0]), "Secondary")
		b.toggle_mode = true
		b.set_pressed_no_signal(plan.policy[k[0]])
		b.add_theme_font_size_override("font_size", Palette.CAPTION)
		policy.add_child(b)
	c.add_child(policy)
	c.add_child(hud._label("Or a serious injury: that always brings them home.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
	var problems := sim.plan_problems(plan)
	for p in problems.slice(0, 2):
		c.add_child(hud._reason(p))
	var go := hud._button("Start packing", func(): game.confirm_plan(), "Primary")
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
	c.add_child(hud._row("Packs", "%d supplies, room for %d of %d" % [sup, room, cap]))
	if plan.get("cart_cap", false):
		c.add_child(hud._label("Includes the cart's %d, with the line laid." % Tuning.CART_CAPACITY, false, Palette.CHALK_DIM, Palette.CAPTION, true))
	if cap == 0:
		return
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 1)
	var wanted := 0  # the amounts the list asks for, against the room (issue #185)
	for r in Sim.cargo_rows(plan):
		wanted += r.n
	var cargo: int = 0 if plan.target.item == "pens" else mini(wanted, room)
	for seg in [[mini(sup, cap), Palette.YELLOW], [cargo, Palette.BLUE], [room - cargo, Palette.SLATE_DEEP]]:
		if seg[0] <= 0:
			continue
		var r := ColorRect.new()
		r.color = seg[1]
		r.custom_minimum_size = Vector2(0, 8)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.size_flags_stretch_ratio = seg[0]
		bar.add_child(r)
	bar.tooltip_text = "Supplies take %d, the amounts wanted %d, and %d is spare" % [sup, cargo, room - cargo]
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(bar)


func _stepper_row(name: String, value: int, key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := hud._label(name)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(_stepper("%d" % value, key))
	return h


## − n + for one of the plan's numbers.
func _stepper(value: String, key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var less := hud._button("−", func(): game.plan_step(key, -1), "Secondary")
	var more := hud._button("+", func(): game.plan_step(key, 1), "Secondary")
	less.set_meta("label", key + " less")
	more.set_meta("label", key + " more")
	for b in [less, more]:
		b.custom_minimum_size = Vector2(30, 0)
	var v := hud._label(value, true)
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
	var aim := "to survey the landing" if ex.target.item == "survey" else "to tend the pens" if ex.target.item == "pens" else ("to clear the level" if ex.get("clear", false) else "to bring back %s" % Sim.list_text(ex))
	c.add_child(hud._label("Packing for the %s, %s" % [sim.get_map(ex.dest).name.to_lower(), aim], false, Palette.CHALK, Palette.BODY, true))
	c.add_child(hud._row("Meals", "%d / %d" % [p.meals, ex.meals]))
	c.add_child(hud._bar(float(p.meals) / maxi(ex.meals, 1)))
	if ex.picks > 0:
		c.add_child(hud._row("Spare pickaxes", "%d / %d" % [p.picks, ex.picks]))
		c.add_child(hud._bar(float(p.picks) / ex.picks))
	for k in [["sticks", "Sticks"], ["wheat", "Wheat"]]:  # issue #139
		if ex.get(k[0], 0) > 0:
			c.add_child(hud._row(k[1], "%d / %d" % [p[k[0]], ex[k[0]]]))
			c.add_child(hud._bar(float(p[k[0]]) / ex[k[0]]))
	c.add_child(hud._label("Party", true))
	for id in ex.party:
		var r := sim.resident(id)
		if r.is_empty():
			continue
		var where := "At the board" if sim.at_board(r) else sim.cant_join(r)
		if where == "":
			where = r.job.label if r.job != null else "Idle"
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.add_child(hud._swatch(r.shirt))
		line.add_child(hud._label("%s: %s" % [r.name, where], false, Palette.CHALK if sim.at_board(r) else Palette.CHALK_DIM))
		c.add_child(line)
	for x in sim.stuck:
		if x.who == "Expedition" and not x.waiting:
			c.add_child(hud._reason(x.why))
	var why := sim.depart_blocker()
	var go := hud._button("Depart", func(): game.depart(), "Primary")
	go.disabled = why != ""
	go.tooltip_text = why if why != "" else "Send the party off. They’re out of village work until they’re back."
	c.add_child(go)
	if why != "":
		c.add_child(hud._label(why, false, Palette.CHALK_DIM, Palette.BODY, true))
	c.add_child(hud._destructive("Call off the expedition", "Click again to call it off", "expedition", func(): game.cancel_expedition()))


## An expedition that's out: one at a time (#25), so there's nothing to plan.
func _fill_out(c: Container, sim: Sim) -> void:
	var ex: Dictionary = sim.expedition
	var mp := sim.get_map(ex.dest)
	var party: Array = ex.party.map(func(id): return sim.resident(id)).filter(func(r): return not r.is_empty())
	var road: Array = party.filter(func(r): return sim.on_road(r))
	var names := Sim.names_text(party.map(func(r): return r.name))
	var are := "is" if party.size() == 1 else "are"
	var home: bool = ex.get("leg", "out") == "home"
	if ex.has("stranded"):  # the rescue window, supplies and what's at stake (issue #158)
		c.add_child(hud._label(sim.stranded_text(ex), false, Palette.YELLOW, Palette.BODY, true))
		var rb := hud._button("Plan a rescue", func(): game.plan_objective("rescue"), "Primary")
		rb.disabled = sim.objective_destinations("rescue").is_empty()
		rb.tooltip_text = "Send a party with provisions and flint and steel. It can set out even with both parties out." if not rb.disabled else sim.objective_why_none("rescue")
		c.add_child(rb)
	if not road.is_empty():
		var when := ceili(sim.road_eta(road[0]))
		c.add_child(hud._label("%s %s on the road %s, there in %d s." % [names, are, "home" if home else "to the " + mp.name.to_lower(), when], false, Palette.CHALK, Palette.BODY, true))
	elif home:
		c.add_child(hud._label("%s %s heading home from the %s." % [names, are, mp.name.to_lower()], false, Palette.CHALK, Palette.BODY, true))
	elif party.all(func(r): return r.map == ex.dest):
		c.add_child(hud._label("The party is at the %s: %s." % [mp.name.to_lower(), names], false, Palette.CHALK, Palette.BODY, true))
		hud._fill_party(c, sim)
		c.add_child(hud._button("Show the %s" % mp.name.to_lower(), func(): game.switch_map(ex.dest), "Secondary"))
	else:
		c.add_child(hud._label("%s %s carrying the packs to the signpost." % [names, are], false, Palette.CHALK, Palette.BODY, true))
	_add_call_home(c, sim)


## Call the party home (issue #108), until #109's return policy does it by itself. Disabled, with
## why, until the whole party is at the site.
func _add_call_home(c: Container, sim: Sim) -> void:
	var sl := Sim.realm_of(game.view_map)
	var why := sim.call_home_blocker(sl)
	if sim.expeditions[sl].get("leg", "out") == "home":
		return
	var b := hud._button("Call the party home", func(): game.call_home(), "Primary")
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
	c.add_child(hud._head("Road to the %s" % mp.name.to_lower() if mp.known else "A road east", sub))
	if not mp.known:
		c.add_child(hud._label("Nobody in the village knows where it goes yet. An expedition board would.", false, Palette.CHALK_DIM, Palette.BODY, true))
		return
	for i in rep.segments.size():
		var sg: Dictionary = rep.segments[i]
		if not sg.known:
			c.add_child(hud._row("%d  Not walked yet" % (i + 1), "%d cells" % sg.len))
			continue
		var track: String = {"none": "", "planned": "track planned", "built": "track laid"}[sg.track]
		c.add_child(hud._row("%d  %s" % [i + 1, sg.name], track if track != "" else "%d cells, %s" % [sg.len, sg.terrain]))
		if sg.obstacle != "":
			var done: bool = sg.obstacle in ["Bridged", "Cleared"]
			c.add_child(hud._label(sg.obstacle, false, Palette.CHALK_DIM if done else Palette.YELLOW, Palette.CAPTION, true))
	if rep.surveyed and not sim.cart.is_empty():
		c.add_child(hud._label("On foot about %d s, by cart about %d s as the line stands." % [roundi(rep.walk), roundi(rep.cart_now)], false, Palette.CHALK, Palette.BODY, true))
	elif rep.surveyed:
		c.add_child(hud._label("By cart about %d s, once the line is laid." % roundi(rep.cart), false, Palette.CHALK, Palette.BODY, true))
	else:
		c.add_child(hud._label("The first party to walk it will survey the rest of the road.", false, Palette.CHALK_DIM, Palette.BODY, true))
	var on_road: Array = sim.residents.filter(func(r): return r.map == Road.ID or sim.carrying_packs(r))
	for r in on_road:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.add_child(hud._swatch(r.shirt))
		line.add_child(hud._label("%s: %s" % [r.name, hud._status(sim, r)], false, Palette.CHALK))
		c.add_child(line)
	if game.view_map != Road.ID:
		c.add_child(hud._button("Show the road", func(): game.switch_map(Road.ID), "Secondary"))
	if not sim.expedition_board().is_empty() and sim.expedition.is_empty():  # the old mine's adventure (issue #136)
		c.add_child(hud._button("Plan a trip to the old caves", func(): game.open_adventure(OldMine.ID), "Secondary"))
	# The work the road needs.
	var seen: int = sim.road().seen
	if sim.bridge().is_empty() and seen > Sim._seg_of("stream"):
		var b := hud._button("Build the bridge", func(): game.plan_bridge(), "Secondary")
		b.tooltip_text = "A plank bridge over the stream: %s. Village builders carry the planks out." % Defs.cost_text(Defs.TEMPLATES.bridge.stages[0].cost)
		c.add_child(b)
	var cut := sim.cut_boulders()
	if not cut.is_empty() and seen > Sim._seg_of("cut") and not cut.all(func(x): return x.des):
		var b := hud._button("Clear the cut", func(): game.clear_cut(), "Secondary")
		b.tooltip_text = "Marks the boulders on the line to be mined. Miners walk out from the village."
		c.add_child(b)
	for end in ["village", "mine"]:  # the stations (issue #123)
		if sim.station(end).is_empty() and seen > Road.segment_at(Road.STATIONS[end].x) and not sim.plan_line_blocker().begins_with("Walk"):
			var b := hud._button("Build the %s station" % end, func(): game.plan_station(end), "Secondary")
			b.tooltip_text = "A platform beside the line where the cart stops, loads and unloads: %s." % Defs.cost_text(Defs.TEMPLATES.station.stages[0].cost)
			c.add_child(b)
	_add_line(c, sim)


## A station (issue #123): the line's state, where the cart is, and what's on the platform.
func _fill_station(c: Container, sim: Sim, s: Dictionary) -> void:
	c.add_child(hud._head("Station", "%s end" % ("Village" if s.end == "village" else "Mine")))
	var laid := range(Road.segment_count()).filter(func(i): return sim.track_state(i) == "built").size()
	c.add_child(hud._row("The line", "%d of %d segments laid" % [laid, Road.segment_count()]))
	var where := "No minecart yet. Craft one at the bench, and it's hauled out here."
	var cart: Dictionary = sim.cart
	if not cart.is_empty():
		match cart.state:
			"moving": where = "The cart is on the line, %s" % ("to the mine" if sim.expedition.get("leg", "out") == "out" else "coming home")
			"loading": where = "The cart is being loaded at the mine end"
			"unloading": where = "The cart is being unloaded at the village end"
			_: where = "The cart is parked at the %s end" % cart.at
	c.add_child(hud._label(where + ".", false, Palette.CHALK, Palette.BODY, true))
	var on: Array = sim.road().items.values().filter(func(st): return Rect2i(s.origin, s.size).grow(1).has_point(st.cell))
	if on.is_empty():
		c.add_child(hud._label("Nothing on the platform.", false, Palette.CHALK_DIM, Palette.BODY, true))
	for st in on:
		c.add_child(hud._row(Defs.ITEMS[st.type].label, str(st.n)))
	c.add_child(hud._label("Carts load and unload here at %d items a second. Haulers carry what's set down to the stockpile." % int(Tuning.LOAD_RATE), false, Palette.CHALK_DIM, Palette.CAPTION, true))


## The line (issue #121): how far it's laid, or the plan with its cost and the time it saves.
func _add_line(c: Container, sim: Sim) -> void:
	var states: Array = range(Road.segment_count()).map(func(i): return sim.track_state(i))
	if states.has("planned") or states.has("built"):
		var laid := states.count("built")
		c.add_child(hud._row("The line", "%d of %d segments laid" % [laid, states.size()], false))
		var nxt := sim.next_track()
		if nxt >= 0 and sim.track_blocker(nxt) != "":
			c.add_child(hud._label("%s: %s" % [Road.SEGMENTS[nxt].name, sim.track_blocker(nxt).to_lower()], false, Palette.YELLOW, Palette.CAPTION, true))
		if not states.has("none"):
			return
	var why := sim.plan_line_blocker()
	if not game.line_preview:
		var b := hud._button("Plan the line", func(): game.line_preview = true, "Primary")
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else "Track along the road, from the village to the mine."
		c.add_child(b)
		return
	var cost := sim.line_cost()
	var craft := " Crafting them takes %d iron ingots." % cost.ingots if cost.ingots > 0 else ""
	c.add_child(hud._label("%d rails, with %d on hand.%s" % [cost.rails, cost.on_hand, craft], false, Palette.CHALK, Palette.BODY, true))
	c.add_child(hud._label("Laid from the village end. Saves about %d s a round trip, once there's a cart." % roundi(cost.saved), false, Palette.CHALK, Palette.BODY, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lay := hud._button("Lay track", func(): game.plan_line(), "Primary")
	lay.disabled = why != ""
	lay.tooltip_text = why
	row.add_child(lay)
	row.add_child(hud._button("Not now", func(): game.line_preview = false, "Secondary"))
	c.add_child(row)


## What the board is up to, for its selection panel.
func _board_status(sim: Sim) -> String:
	var ex: Dictionary = sim.expedition
	match ex.get("state", ""):
		"staging":
			return "Packing for the %s." % sim.get_map(ex.dest).name.to_lower()
		"out":
			return "The party is out at the %s." % sim.get_map(ex.dest).name.to_lower()
	return "Plan an adventure here: the old caves or the meadow."
