class_name SelectionPanel
extends RefCounted
## Split out of hud.gd (#305). It draws with the HUD's own helpers and state, reached through `hud`; Hud keeps one-line forwarders for what the rest of it calls.

var hud: Hud
var game


func _init(h: Hud, g) -> void:
	hud = h
	game = g


func _refresh_selection(sim: Sim) -> void:
	var sel: Dictionary = game.selection
	var sig := "%s" % [sel]
	var target = game.selected_entity()
	if sel.get("kind", "") == "res":
		for id in sel.ids:
			var r := sim.resident(id)
			if not r.is_empty():
				sig += "%s%s%s%s%s%s%s%d" % [r.job.label if r.job != null else "Idle", r.axe, r.pick, r.carry, r.broken, r.progress >= 0, r.orders, int(r.hunger / 5)] + "%s%s%s%s%s%s%d%d" % [r.jobs, r.role, hud._job_for == r.id, r.kept, hud.equip_kind, r.away, int(sim.back_in(r)), r.get("hurt", 0)] + "%s" % [r.get("armor", {})]
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
		if target.get("tpl", "") == "mason_bench":  # whether it can be dug out depends on the map's boulders and the bricks
			sig += sim.shaft_check(target)
	if not sel.is_empty():  # with nothing selected the panel shows no stuck reason, so a changing one needn't rebuild it (#343)
		for s in sim.stuck:
			sig += s.why
	sig += game.tool + str(game.area_site)  # the Paint area button reads Done painting while it's on (issue #203)
	sig += hud._keys_sig
	hud._update_progress_bar(sim)
	hud._rebuild(hud._sel, sig, func(c: Container) -> void:
		_fill_selection(c, sim, sel, target)
		hud._pin_wrap(c, 330 - 24)
		hud._register_panel_keys(c))


func _fill_selection(c: Container, sim: Sim, sel: Dictionary, target) -> void:
	if sel.is_empty():
		c.add_child(hud._label("Nothing selected", true, Palette.CHALK, Palette.HEADING))
		c.add_child(hud._label("Click Ada to select her. With Ada selected, right-click a tree to mine it, or use the orders toolbar to mark work for anyone. Press F to select a resident.", false, Palette.CHALK_DIM, Palette.BODY, true))
		return
	if sel.kind == "res":
		var rs: Array = sel.ids.map(func(id): return sim.resident(id)).filter(func(r): return not r.is_empty())
		if rs.size() > 1:
			c.add_child(hud._label("%d residents" % rs.size(), true, Palette.CHALK, Palette.TITLE))
			for r in rs:
				var line := HBoxContainer.new()
				line.add_theme_constant_override("separation", 8)
				line.add_child(hud._swatch(r.shirt))
				line.add_child(hud._label("%s: %s" % [r.name, _status(sim, r)], false, Palette.CHALK_DIM))
				c.add_child(line)
			return
		if rs.is_empty():
			return
		var r: Dictionary = rs[0]
		c.add_child(hud._head(r.name, _status(sim, r), true, 24, r.shirt))
		if r.progress >= 0:
			var pbar := hud._bar(r.progress)
			pbar.set_meta("progress_of", r.id)  # filled in place each frame, so the panel isn't rebuilt (#336)
			c.add_child(pbar)
		if r.away:  # on the walk to or from the meadow (issue #137)
			c.add_child(hud._label("Off the map with the party. Residents on the way don’t work or get hungry.", false, Palette.CHALK_DIM, Palette.BODY, true))
			c.add_child(hud._bar(1.0 - sim.back_in(r) / sim.trip_time(r.trip), Palette.GREEN))
			return
		_add_tool_row(c, sim, r, "axe")
		_add_tool_row(c, sim, r, "pick")
		_add_armor_row(c, r)
		c.add_child(hud._row("Carrying", Defs.words(r.carry.type, r.carry.n) if r.carry != null else "Nothing"))
		c.add_child(hud._row("Food", hud._mood(r)))
		if r.get("hurt", 0) > 0:  # issue #110
			c.add_child(hud._row("Health", "Injured" if r.hurt == 1 else "Seriously hurt"))
		c.add_child(hud._bar(r.hunger / 100.0, Palette.YELLOW if r.hunger < Tuning.HUNGRY_BELOW else Palette.CHALK))
		for s in sim.stuck:
			if s.focus_kind == "res" and s.focus_id == r.id:
				c.add_child(hud._reason(s.why))
		if not r.orders.is_empty():
			c.add_child(hud._label("Queued orders", true))
			for i in r.orders.size():
				c.add_child(hud._label("%d  %s" % [i + 1, Sim.order_text(r.orders[i])], false, Palette.CHALK, Palette.BODY))
			c.add_child(hud._destructive("Clear orders", "Click again to clear orders", "orders:%d" % r.id, func(): game.clear_orders(r)))
		if hud.equip_kind != "":
			return  # the tool list takes the Jobs grid's room while it's open
		var rex := sim.expedition_of(r)
		if rex.get("state", "") == "out" and r.map == rex.dest:
			hud._add_call_home(c, sim)
		if r.axe == null and not r.broken.axe:
			c.add_child(hud._label("Chopping by hand is slow. Stone needs a pickaxe.", false, Palette.CHALK_DIM, Palette.BODY, true))
		_add_jobs_summary(c, sim, r)
		return
	if target == null:
		c.add_child(hud._label("That’s gone.", false, Palette.CHALK_DIM))
		return
	match target.kind:
		"tree":
			if not Sim.grown(target):  # planted by a lumberjack (issue #177)
				c.add_child(hud._head("Sapling" if Sim.tree_stage(target) == 0 else "Young tree", "Growing, %d%%" % int(target.grow / Tuning.SAPLING_GROW * 100.0)))
				c.add_child(hud._bar(target.grow / Tuning.SAPLING_GROW, Palette.GREEN))
				c.add_child(hud._label("It grows into a tree in %d minutes, and can't be chopped till then." % int(Tuning.SAPLING_GROW / 60.0), false, Palette.CHALK_DIM, Palette.BODY, true))
				return
			c.add_child(hud._head("Tree", "Drops %d logs and a sapling" % target.logs))
			c.add_child(hud._button("Cancel mining" if target.des else "Mine", func(): game.toggle_mine(target), "Secondary" if target.des else "Primary"))
			_add_keep(c, sim, target)
		"bush":
			c.add_child(hud._head("Berry bush", "%d of %d berries" % [target.berries, Tuning.BUSH_MAX]))
			c.add_child(hud._label("A berry grows back every %d seconds. Hungry residents eat here." % int(Tuning.BUSH_REGROW), false, Palette.CHALK_DIM, Palette.BODY, true))
			var dig := hud._button("Cancel digging" if target.des else "Dig up", func(): game.toggle_dig_bush(target), "Secondary" if target.des else "Primary")
			dig.tooltip_text = "A resident digs the bush up and carries its berries off. Berries are early food, so it's gone for good."
			c.add_child(dig)
		"meadow":  # the signpost to the meadow (issues #136, #137)
			_fill_signpost(c, sim, Meadow.ID)
		"route":
			hud._fill_route(c, sim)
		"crop":
			var stage := Sim.crop_stage(target)
			var status := "Empty, waiting to be planted"
			if stage == 4:
				status = "Ripe wheat, waiting to be harvested"
			elif stage > 0:
				status = "Wheat growing, %d%%" % int(target.grow / Tuning.WHEAT_GROW * 100.0)
			c.add_child(hud._head("Farm plot", status))
			if stage > 0 and stage < 4:
				c.add_child(hud._bar(target.grow / Tuning.WHEAT_GROW, Palette.YELLOW))
			if target.claim != 0:
				var who: String = sim.resident(target.claim).get("name", "Someone")
				c.add_child(hud._label("%s is %s it." % [who, "harvesting" if stage == 4 else "planting"], false, Palette.CHALK_DIM))
			c.add_child(hud._label("Wheat takes %d minutes to grow and gives %d when harvested." % [int(Tuning.WHEAT_GROW / 60.0), Tuning.WHEAT_YIELD], false, Palette.CHALK_DIM, Palette.BODY, true))
			c.add_child(hud._destructive("Remove this plot", "Click again to remove the plot", "plot:%d" % target.id, func(): game.remove_farm_plot(target)))
		"animal":
			_fill_animal(c, sim, target)
		"pen":
			_fill_pen(c, sim, target)
		"boulder":
			var drops := Defs.words("cobble", Tuning.BOULDER_COBBLE)
			if target.has("ore"):
				drops = Defs.words(target.get("book", Defs.ORES[target.ore].item), Tuning.ORE_YIELD[target.ore])
			c.add_child(hud._head(Sim.block_name(target), "Drops " + drops))
			if target.des and sim.stuck.any(func(s): return s.focus_kind == "boulder"):
				c.add_child(hud._reason("Needs a pickaxe"))
			c.add_child(hud._button("Cancel mining" if target.des else "Mine", func(): game.toggle_mine(target), "Secondary" if target.des else "Primary"))
			_add_keep(c, sim, target)
		"site":
			_fill_site(c, sim, target)
			if target.done and not target.tpl in Sim.UNMOVABLE and game.view_map == "village":  # pick a finished building up and put it down elsewhere (issue #234)
				var why := sim.move_check(target, target.origin, target.rot)
				var mv := hud._button("Move", func(): game.start_moving(target), "Secondary")
				mv.set_meta("label", "Move building")
				mv.disabled = why != ""
				mv.tooltip_text = why if why != "" else "Pick it up and put it down somewhere else. Its queue and stored items go with it."
				c.add_child(mv)
			var page := Goals.page_for(target.tpl)
			if not page.is_empty() and Goals.page_known(sim, page):  # the book's page for this building (issue #198)
				var about := hud._button("?  About the %s" % Defs.TEMPLATES[target.tpl].name.to_lower(), func(): game.open_book(page.id))
				about.flat = true
				about.alignment = HORIZONTAL_ALIGNMENT_LEFT
				c.add_child(about)


## A village tree or boulder's Keep toggle (issue #177): lumberjacks and stonemasons never take a kept
## one on their own.
func _add_keep(c: Container, sim: Sim, target: Dictionary) -> void:
	if sim.map_id != "village":
		return
	var kept: bool = target.get("keep", false)
	var b := hud._button("Keep: on" if kept else "Keep", func(): game.toggle_keep(target), "Secondary")
	b.toggle_mode = true
	b.set_pressed_no_signal(kept)
	b.tooltip_text = "Lumberjacks and stonemasons leave it alone unless it's marked to mine."
	c.add_child(b)
	if not kept and sim.protected(target):
		c.add_child(hud._label("On protected land: gatherers leave it alone.", false, Palette.CHALK_DIM, Palette.CAPTION, true))


## The Craft button appears once a bench is finished; it opens the Craft panel above the toolbar
## (issue #57), with a tab for each station once there's more than one (issue #76).
func _refresh_craft(sim: Sim) -> void:
	var bench = game.craft_bench()
	hud._tool_btns.craft.visible = bench != null
	hud._craft_panel.visible = game.craft_menu_open and bench != null
	if not hud._craft_panel.visible:
		return
	var list: Array = game.benches()
	var sig := "%s|%s|%s|%s|%s|%s|%s|%d" % [list.map(func(b): return b.id), bench, sim.auto_craft, hud._craft_n, sim.stuck.map(func(x): return x.why), _blocked_sites(sim), hud._craft_pick, int(_craft_progress(sim, bench) * 10)]
	for k in Palette.ITEM_COLORS:
		sig += "%d," % sim.free_count(k)
	hud._rebuild(hud._craft_box, sig, func(c: Container) -> void:
		if list.size() > 1:
			c.add_child(_station_tabs(sim, list, bench))
		_fill_bench(c, sim, bench)
		hud._pin_wrap(c, 400 - 24),
		Callable(), "%s|%s|%s" % [bench.id, hud._craft_pick, list.size()])


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
		var t := hud._button(name, func(): game.show_craft_bench(i), "" if on else "Secondary")
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
	line.add_child(hud._label("Job", false, Palette.CHALK_DIM))
	line.add_child(_job_picker(sim, r))
	c.add_child(line)
	var em: int = r.get("emeralds", 0)
	var el := hud._label("Emeralds  %d" % em, false, Palette.CHALK_DIM)
	el.tooltip_text = "%s earns an emerald with each level gained in any job, from level 2. They're spent on upgrading %s home." % [r.name, "their"]
	c.add_child(el)
	if r.role == "all":
		c.add_child(hud._label("%s founded the village and does any work that's waiting." % r.name, false, Palette.CHALK_DIM, Palette.CAPTION, true))
	var key: String = game.keys.first("jobs")
	var b := hud._button("Jobs board" + ("  (%s)" % key if key != "" else ""), func(): game.toggle_jobs_board(true), "Secondary")
	b.tooltip_text = "Everyone's jobs and levels"
	c.add_child(b)


## A resident's job (issue #134): a button that opens the job dropdown, or "Everything" for Ada,
## who has none to choose.
func _job_picker(sim: Sim, r: Dictionary) -> Control:
	if r.role == "all":
		var l := hud._label("Everything", false, Palette.CHALK)
		l.tooltip_text = "%s does every job, and covers whatever nobody else's job does." % r.name
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		return l
	var lv := "" if r.role == "none" else ", level %d" % Sim.level(r, r.role)
	var short := " (no %s)" % Defs.TEMPLATES[Defs.JOB_STATIONS[r.role]].name.to_lower() if sim.needs_station(r) else ""
	var b := hud._button("%s%s%s  ↓" % [Sim.role_name(r), lv, short], func(): pass, "Secondary")
	b.set_meta("label", "Job: %s" % r.name)
	b.toggle_mode = true
	b.set_pressed_no_signal(hud._job_for == r.id)
	b.tooltip_text = "Choose %s's job. They do its work, and haul when there's none." % r.name
	b.pressed.connect(func():
		if hud._job_for == r.id:
			_close_job_drop()
		else:
			hud._job_for = r.id
			hud._job_anchor = b.get_global_rect()
			hud._sigs.erase(hud._job_list.get_instance_id())
			_refresh_job_drop(sim))
	return b


func _close_job_drop() -> void:
	hud._job_for = -1
	hud._job_anchor = Rect2()
	hud._job_drop.visible = false


## The job dropdown (issue #134): each job with the resident's level in it, best first, and how many
## already have it, then No job. Choosing one closes it.
func _refresh_job_drop(sim: Sim) -> void:
	var r: Dictionary = sim.resident(hud._job_for) if hud._job_for >= 0 else {}
	if r.is_empty() or r.role == "all" or not (game.jobs_board_open or game.selection.get("ids", []).has(r.id)):
		_close_job_drop()
		return
	hud._job_drop.visible = true
	var h := hud._job_drop.get_combined_minimum_size().y
	var below := hud._job_anchor.end.y + 4 + h <= hud.get_viewport().get_visible_rect().size.y
	hud._place_drop(hud._job_drop, Vector2(hud._job_anchor.position.x, hud._job_anchor.end.y + 4 if below else hud._job_anchor.position.y - 4 - h))  # above, when there's no room below
	var counts := {}
	for o in sim.residents:
		counts[o.role] = counts.get(o.role, 0) + 1
	var sig := "%d%s%s%s%s" % [r.id, r.role, r.jobs, counts, hud._stations_sig(sim)]
	hud._rebuild(hud._job_list, sig, func(c: Container) -> void:
		var order: Array = Defs.JOBS.duplicate()
		order.sort_custom(func(a, b): return Sim.level(r, a) > Sim.level(r, b) or (Sim.level(r, a) == Sim.level(r, b) and Defs.JOBS.find(a) < Defs.JOBS.find(b)))
		for jb in order + ["none"]:
			var text := "No job: haul" if jb == "none" else "%s · level %d" % [Defs.JOB_NAMES[jb], Sim.level(r, jb)]
			var n: int = counts.get(jb, 0)
			if jb != "none" and n > 0:
				text += " · %d %s" % [n, hud._job_people(jb, n)]
			if Defs.JOB_STATIONS.has(jb):  # issue #184: a job needs a free workstation of its own
				var tpl: String = Defs.JOB_STATIONS[jb]
				var free: int = sim.maps.village.sites.filter(func(st): return st.done and st.tpl == tpl and st.get("worker", 0) in [0, r.id]).size()
				var tname: String = Defs.TEMPLATES[tpl].name.to_lower()
				text += " · %d %s free" % [free, tname] if free > 0 else " · no %s" % tname
			var b := hud._button(text, func():
				game.set_role(r, jb)
				_close_job_drop(), "Secondary")
			b.set_meta("label", "Job choice: " + text)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.set_pressed_no_signal(r.role == jb)
			b.tooltip_text = "Only hauls, when there's something to carry" if jb == "none" else "%s does %s work from a %s of their own, and hauls when there's none or no %s is free" % [r.name, Defs.JOB_NAMES[jb], Defs.TEMPLATES[Defs.JOB_STATIONS[jb]].name.to_lower(), Defs.TEMPLATES[Defs.JOB_STATIONS[jb]].name.to_lower()] if Defs.JOB_STATIONS.has(jb) else "%s does %s work, and hauls when there's none" % [r.name, Defs.JOB_NAMES[jb]]
			c.add_child(b))


## The Village jobs board (issues #78, #134): a row per resident with their job's dropdown, and a
## column per job with their level in it and a tick of progress to the next level. Their own job's
## cell is lit. A column header counts who has the job, yellow when nobody does (Ada aside).
func _refresh_board(sim: Sim) -> void:
	hud._jobs_btn.set_pressed_no_signal(game.book_open)
	if not game.jobs_board_open:
		return
	var sig := "%s|%s|%d|%s" % [game.selection, hud._keys_sig, hud._job_for, hud._stations_sig(sim)]
	for r in sim.residents:
		sig += "%d%s%s%s%s%s;" % [r.id, r.name, r.role, r.jobs, r.away, r.map]
	var herds := _wild_herds(sim)
	sig += "|%s|%s|%s|%s" % [herds, sim.herd_floor, sim.wheat_keep, sim.m.farm.size()]
	hud._rebuild(hud._board, sig, func(c: Container) -> void:
		var head := HBoxContainer.new()
		var title := hud._label("Village jobs", true, Palette.CHALK, Palette.HEADING)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		head.add_child(hud._label("One job each. Idle residents haul.", false, Palette.CHALK_DIM, Palette.CAPTION))
		c.add_child(head)
		var grid := GridContainer.new()
		grid.columns = Defs.JOBS.size() + 2
		grid.add_theme_constant_override("h_separation", 3)
		grid.add_theme_constant_override("v_separation", 3)
		grid.add_child(Control.new())
		var job_head := hud._label("Job", true, Palette.CHALK, Palette.BODY)
		job_head.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		grid.add_child(job_head)
		for jb in Defs.JOBS:
			var n: int = sim.residents.filter(func(r): return r.role == jb).size()
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 0)
			var name := hud._label(Defs.JOB_NAMES[jb], true, Palette.CHALK, Palette.BODY)
			name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(name)
			var nobody: bool = n == 0 and jb != "haul"  # everyone hauls when idle
			var count := hud._label("nobody" if n == 0 else str(n), false, Palette.YELLOW if nobody else Palette.CHALK_DIM, Palette.CAPTION)
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(count)
			var people: String = Defs.JOB_SKILLED[jb].capitalize() + "s"
			col.tooltip_text = "%s: %s. Ada does this work when she can." % [people, "nobody" if n == 0 else str(n)] if jb != "haul" else "%s: %d. Everyone hauls when there's nothing of their own job to do." % [people, n]
			if Defs.JOB_STATIONS.has(jb):  # how many workstations there are for it (issue #184)
				var tpl: String = Defs.JOB_STATIONS[jb]
				var ns: int = sim.maps.village.sites.filter(func(st): return st.done and st.tpl == tpl).size()
				var word: String = Defs.TEMPLATES[tpl].name.to_lower().split(" ")[-1]  # "2 benches", "no composter"
				var built := hud._label("%d %s" % [ns, word if ns == 1 else word + ("es" if word.ends_with("ch") else "s")] if ns > 0 else "no " + word, false, Palette.CHALK_DIM, Palette.CAPTION)
				built.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				col.add_child(built)
				col.tooltip_text += " Each needs a %s of their own: %d built." % [Defs.TEMPLATES[tpl].name.to_lower(), ns]
			col.mouse_filter = Control.MOUSE_FILTER_STOP
			grid.add_child(col)
		for r in sim.residents:
			var who := hud._button(r.name + (" (away)" if r.away else (" (on the road)" if r.map == Road.ID or r.map == MeadowRoad.ID else "")), func(): game.focus_on("res", r.id))
			who.icon = hud._swatch_tex(r.shirt)
			who.alignment = HORIZONTAL_ALIGNMENT_LEFT
			who.custom_minimum_size = Vector2(120, 0)
			who.toggle_mode = true
			who.set_pressed_no_signal(game.selection.get("ids", []).has(r.id))
			who.tooltip_text = "Select %s" % r.name if r.map != Road.ID and r.map != MeadowRoad.ID else "Select %s. %s" % [r.name, _status(sim, r)]
			grid.add_child(who)
			var pick := _job_picker(sim, r)
			pick.custom_minimum_size = Vector2(170, 0)
			pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(pick)
			for jb in Defs.JOBS:
				grid.add_child(_board_cell(r, jb))
		c.add_child(grid)
		_add_herd_floors(c, sim, herds)
		_add_wheat_keep(c, sim))


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
	row.add_child(hud._label("Hunters leave", true, Palette.CHALK, Palette.BODY))
	for sp in Defs.SPECIES:
		if not herds.has(sp):
			continue
		var sd: Dictionary = Defs.SPECIES[sp]
		var n := sim.floor_of(sp)
		var less := hud._button("−", func(): game.set_herd_floor(sp, n - 1), "Secondary")
		less.disabled = n <= 0
		less.tooltip_text = "Leave one fewer %s" % sd.one
		row.add_child(less)
		var lbl := hud._label("%d %s" % [n, sd.one if n == 1 else sd.many], false, Palette.CHALK, Palette.BODY)
		lbl.tooltip_text = "Hunters hunt %s on their own until %d %s left (%d now). Marked ones are hunted anyway." % [sd.many, n, "is" if n == 1 else "are", herds[sp]]
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(lbl)
		var more := hud._button("+", func(): game.set_herd_floor(sp, n + 1), "Secondary")
		more.tooltip_text = "Leave one more %s" % sd.one
		row.add_child(more)
	c.add_child(row)


## The jobs board's wheat target (issue #269): farmers stop once the village has this much, with a stepper.
func _add_wheat_keep(c: Container, sim: Sim) -> void:
	if sim.m.farm.is_empty():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(hud._label("Farmers keep", true, Palette.CHALK, Palette.BODY))
	var less := hud._button("−", func(): game.set_wheat_keep(sim.wheat_keep - Tuning.KEEP_STEP), "Secondary")
	less.disabled = sim.wheat_keep <= 0
	row.add_child(less)
	var lbl := hud._label("%d wheat" % sim.wheat_keep, false, Palette.CHALK, Palette.BODY)
	lbl.tooltip_text = "Farmers plant and harvest until the village has %d wheat (%d now)." % [sim.wheat_keep, sim.free_count("wheat")]
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(lbl)
	row.add_child(hud._button("+", func(): game.set_wheat_keep(sim.wheat_keep + Tuning.KEEP_STEP), "Secondary"))
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
	var l := hud._label("Lv %d" % lv, mine, Palette.CHALK if mine else Palette.CHALK_DIM, Palette.BODY)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var bar := hud._bar(Sim.level_progress(r, jb), Palette.GREEN)
	bar.custom_minimum_size = Vector2(46, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bar)
	p.add_child(v)
	var xp: int = r.jobs[jb].get("xp", 0)
	var lv_text := "level %d: %d of %d points to level %d" % [lv, xp, Sim.xp_for(lv + 1), lv + 1]
	p.tooltip_text = "%s, %s: %s%s." % [r.name, Defs.JOB_NAMES[jb], lv_text, ". Their job" if r.role == jb else ""]
	return p


## What armor a resident wears (issue #140), and how much of the hazards' harm it turns aside.
func _add_armor_row(c: Container, r: Dictionary) -> void:
	var worn := Sim.armor_worn(r)
	if worn.is_empty():
		c.add_child(hud._row("Armor", "None"))
		return
	c.add_child(hud._row("Armor", "%d%% guard" % roundi(Sim.protection(r) * 100.0) + (", full set" if worn.size() == Defs.ARMOR_SLOTS.size() else "")))
	var parts: PackedStringArray = []
	for slot in Defs.ARMOR_SLOTS:
		if worn.has(slot):
			parts.append("%s, %d %s" % [Defs.SLOT_NAMES[slot], worn[slot].dur, "use" if worn[slot].dur == 1 else "uses"])
	c.add_child(hud._label("%s. Turns aside that share of injuries from hazards, and wears a use each time one strikes." % "; ".join(parts), false, Palette.CHALK_DIM, Palette.CAPTION, true))


## A resident's axe or pickaxe, with Equip to choose another one (lying about or stockpiled).
func _add_tool_row(c: Container, sim: Sim, r: Dictionary, kind: String) -> void:
	var t = r[kind]
	var none := "Bare hands" if kind == "axe" else "None"
	var text: String = _tool_text(t) if t != null else ("Broke" if r.broken[kind] else none)
	var h := hud._row("Axe" if kind == "axe" else "Pickaxe", text)
	var spare := sim.tool_items(kind, 0)
	if not spare.is_empty() or hud.equip_kind == kind:
		var b := hud._button("Close" if hud.equip_kind == kind else "Equip", func(): hud.equip_kind = "" if hud.equip_kind == kind else kind, "Secondary")
		b.add_theme_font_size_override("font_size", Palette.CAPTION)
		b.tooltip_text = "Choose which %s %s uses" % ["axe" if kind == "axe" else "pickaxe", r.name]
		h.add_child(b)
	c.add_child(h)
	if t != null and r.kept[kind]:
		var k := HBoxContainer.new()
		var l := hud._label("Kept until it breaks.", false, Palette.CHALK_DIM, Palette.CAPTION)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_child(l)
		var auto := hud._button("Use the best", func(): game.release_kept_tool(r, kind), "Secondary")
		auto.add_theme_font_size_override("font_size", Palette.CAPTION)
		auto.tooltip_text = "Let %s swap it for a better one when there is one" % r.name
		k.add_child(auto)
		c.add_child(k)
	if hud.equip_kind != kind:
		return
	if spare.is_empty():
		c.add_child(hud._label("No other %s is lying about or stockpiled." % ("axe" if kind == "axe" else "pickaxe"), false, Palette.CHALK_DIM, Palette.CAPTION, true))
		return
	spare.sort_custom(func(a, b): return Defs.ITEMS[a.type].tier > Defs.ITEMS[b.type].tier or (a.type == b.type and a.dur > b.dur))
	for st in spare:
		var where := "in the stockpile" if sim.in_zone(st.cell) else "on the ground"
		var it: Dictionary = Defs.ITEMS[st.type]
		var b := hud._button("%s, %d %s left, %s" % [it.one.substr(0, 1).to_upper() + it.one.substr(1), st.dur, "use" if st.dur == 1 else "uses", where], func():
			hud.equip_kind = ""
			game.equip_tool(r, st))
		b.theme_type_variation = "Secondary"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", Palette.CAPTION)
		b.set_meta("entry", true)  # 1–9 pick it while the list is open (issue #197)
		c.add_child(b)


## What a resident is doing, for panel headings.
func _status(sim: Sim, r: Dictionary) -> String:
	if r.away:
		return hud._road_text(sim, r)
	if sim.on_road(r) and r.job != null and not sim.cart.get("riders", []).has(r.id):  # walking the road map (issue #118)
		return "%s, about %d s" % [r.job.label, ceili(sim.road_eta(r))]
	if r.map == Road.ID and not sim.on_road(r) and r.job != null:  # out working on the road (issue #122)
		return "On the road: %s" % r.job.label.to_lower()
	var ex := sim.expedition_of(r)
	if Sim.realm_of(r.map) == "nether" and ex.get("target", {}).get("item", "") in ["line", "pline"] and r.job != null and r.job.kind == "build":  # issue #159
		return "In the Nether: %s" % r.job.label.to_lower()
	if r.job == null and sim.waits_for_home(r):  # issue #356
		return "Waits for a new home"
	return r.job.label if r.job != null else "Idle"


## An animal (issues #42, #138, #139): what it drops, whether it's penned, fed or young, and the
## Hunt and Lead buttons.
func _fill_animal(c: Container, sim: Sim, a: Dictionary) -> void:
	var sp: Dictionary = Defs.SPECIES[a.species]
	var secs := func(at: int) -> int: return maxi(1, ceili(float(at - sim.tick) / Tuning.TPS))
	if a.get("young", false):
		c.add_child(hud._head(sp.young.capitalize(), "Grows up in %d s" % secs.call(a.grown_at)))
		c.add_child(hud._label("Young ones can't be hunted. Grown, it drops %s." % Defs.drops_text(a.species), false, Palette.CHALK_DIM, Palette.BODY, true))
	else:
		c.add_child(hud._head(sp.name, "Drops " + Defs.drops_text(a.species)))
	var pens: bool = sim.on_map(game.view_map, func(): return not sim.m.pens.is_empty())
	if a.get("pen", 0) != 0:
		var note := "In a pen."
		if a.get("fed_at", -1) >= 0:
			note = "In a pen, fed: a young one in about %d s, once its mate is fed too." % secs.call(a.fed_at + int(Tuning.BREED_TIME * Tuning.TPS))
		elif a.get("cool_until", 0) > sim.tick:
			note = "In a pen. It can be fed again in %d s." % secs.call(a.cool_until)
		elif not a.get("young", false):
			note = "In a pen. Fed wheat with another %s, it has a young one." % sp.one
		c.add_child(hud._label(note, false, Palette.CHALK_DIM, Palette.BODY, true))
	if a.claim != 0:
		var who: Dictionary = sim.resident(a.claim)
		var doing := "hunting it"
		if who.get("job") != null:
			doing = {"lead": "leading it to a pen", "feed": "feeding it"}.get(who.job.kind, doing)
		c.add_child(hud._label("%s is %s." % [who.get("name", "Someone"), doing], false, Palette.CHALK_DIM))
	elif a.get("lead", false):
		c.add_child(hud._label("Marked to lead into a pen. The party does it at the meadow.", false, Palette.CHALK_DIM, Palette.BODY, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if not a.get("young", false):
		row.add_child(hud._button("Cancel hunt" if a.des else "Hunt", func(): game.toggle_hunt(a), "Secondary" if a.des else "Primary"))
	if pens and a.get("pen", 0) == 0:
		row.add_child(hud._button("Don't lead" if a.get("lead", false) else "Lead to a pen", func(): game.toggle_lead(a), "Secondary"))
	if row.get_child_count() > 0:
		c.add_child(row)


## A pen (issue #139): its fences, or what's in it, and how breeding works.
func _fill_pen(c: Container, sim: Sim, p: Dictionary) -> void:
	var edge := Sim.pen_edge(p).size()
	c.add_child(hud._head("Pen", "%d×%d, room for %d" % [p.rect.size.x, p.rect.size.y, Sim.pen_room(p)]))
	if not Sim.pen_done(p):
		var left: int = (edge - p.built.size()) * Tuning.FENCE_STICKS
		c.add_child(hud._row("Fences built", "%d / %d" % [p.built.size(), edge]))
		c.add_child(hud._bar(float(p.built.size()) / edge, Palette.BLUE))
		c.add_child(hud._label("A party builds it with sticks from its packs: %s more. Plan a meadow trip with sticks." % Defs.words("stick", left), false, Palette.CHALK_DIM, Palette.BODY, true))
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
		c.add_child(hud._label(", ".join(parts) + "." if not parts.is_empty() else "Empty. Mark animals with Gather → Lead to a pen, and the party walks them in.", false, Palette.CHALK, Palette.BODY, true))
		var fed := animals.filter(func(a): return a.get("fed_at", -1) >= 0).size()
		if fed > 0:
			c.add_child(hud._label("%d fed, a young one on the way." % fed, false, Palette.WHEAT, Palette.BODY))
		c.add_child(hud._label("A pair of one kind fed %s each has a young one after %d s, and can be fed again after %d min. Young ones grow up in %d min." % [Defs.words("wheat", Tuning.FEED_WHEAT), roundi(Tuning.BREED_TIME), roundi(Tuning.BREED_COOLDOWN / 60.0), roundi(Tuning.GROW_TIME / 60.0)], false, Palette.CHALK_DIM, Palette.CAPTION, true))
	c.add_child(hud._destructive("Take the pen down", "Click again to take it down. Its animals go free", "pen:%d" % p.id, func(): game.remove_pen(p)))


## A signpost to an adventure (issue #136): what's past it, and the way to plan a trip there.
func _fill_signpost(c: Container, sim: Sim, id: String) -> void:
	var row: Dictionary = {}
	for a in sim.adventures():
		if a.id == id:
			row = a
	var mp := sim.get_map(id)
	c.add_child(hud._head("To the %s" % mp.name.to_lower(), row.get("status", "Nobody knows where it goes")))
	if row.is_empty():
		c.add_child(hud._label("An expedition board would have word of what's past this signpost.", false, Palette.CHALK_DIM, Palette.BODY, true))
		return
	c.add_child(hud._label("%s. About %d s walk each way." % [row.what, roundi(row.travel)], false, Palette.CHALK, Palette.BODY, true))
	if id == Meadow.ID and mp.visited:
		var hs := sim.herds()
		var parts: PackedStringArray = []
		for sp in ["cow", "pig", "sheep"]:
			parts.append(Defs.animals(sp, hs.get(sp, 0)))
		c.add_child(hud._label("%s. Each kind grows back on its own." % ", ".join(parts), false, Palette.CHALK_DIM, Palette.BODY, true))
	var b := hud._button("Plan a trip to the %s" % mp.name.to_lower(), func(): game.open_adventure(id), "Primary")
	b.disabled = row.locked
	b.tooltip_text = "One expedition at a time" if row.locked else "Open the expedition board on this adventure"
	c.add_child(b)


func _tool_text(t: Dictionary) -> String:
	return "%s, %d %s left" % [Defs.TIER_NAMES[t.tier], t.dur, "use" if t.dur == 1 else "uses"]


func _fill_site(c: Container, sim: Sim, s: Dictionary) -> void:
	var tpl: Dictionary = Defs.TEMPLATES[s.tpl]
	var reasons := sim.stuck.filter(func(x): return x.focus_kind == "site" and x.focus_id == s.id)
	if s.tpl == "track":  # a segment of the line (issues #121, #122)
		c.add_child(hud._head("Track", Road.SEGMENTS[s.seg].name))
		if s.done:
			c.add_child(hud._label("Laid. Carts run at full speed here.", false, Palette.CHALK_DIM, Palette.BODY, true))
			return
		var laid: int = s.get("laid", 0)
		c.add_child(hud._row("Rails laid", "%d / %d" % [laid, Tuning.RAILS_PER_SEGMENT], false))
		c.add_child(hud._bar(float(laid) / Tuning.RAILS_PER_SEGMENT))
		c.add_child(hud._row("Rails here", str(s.store.get("rail", 0))))
		for x in reasons:
			c.add_child(hud._reason(x.why))
		if sim.next_track() != s.seg:
			c.add_child(hud._label("Waiting its turn: track is laid from the village end.", false, Palette.CHALK_DIM, Palette.BODY, true))
		if s.builder:
			c.add_child(hud._label("%s is laying it." % sim.resident(s.builder).name, false, Palette.CHALK_DIM))
		c.add_child(hud._destructive("Cancel this segment", "Click again to cancel it", "site:%d" % s.id, func(): game.cancel_site(s)))
		return
	if s.tpl == "station" and s.done:  # issue #123
		hud._fill_station(c, sim, s)
		return
	if Defs.TEMPLATES[s.tpl].has("device") and s.done:  # issues #170, #171
		hud._panels().fill_device(c, sim, s)
		return
	if s.tpl == "portal_station" and s.done:  # issues #168, #169
		hud._panels().fill_portal_station(c, sim, s)
		return
	if not s.done:
		var st := sim.current_stage(s)
		var stages := Sim.stages_of(s)
		var stage_line: String = "Stage %d of %d: %s" % [s.stage + 1, stages.size(), st.name.to_lower()] if stages.size() > 1 else "Blueprint"
		if s.get("upgrading", false):
			stage_line = "Digging it out"
		elif s.get("grow", false):
			stage_line = "Growing into a %s" % Defs.HOUSE_TIER_NAMES[s.tier - 1].to_lower()
		c.add_child(hud._head(Sim.station_name(s), stage_line))
		if not sim.footprint_clear(s):
			c.add_child(hud._label("Clearing the ground first: %s." % Sim.clearing_text(sim.site_obstacles(s)), false, Palette.CHALK, Palette.BODY, true))
		for k in st.cost:
			var have: int = s.store.get(k, 0)
			c.add_child(hud._row(Defs.ITEMS[k].label, "%d / %d" % [have, st.cost[k]], false))
			c.add_child(hud._bar(float(have) / st.cost[k]))
		for x in reasons:
			c.add_child(hud._reason(x.why))
		if s.builder:
			c.add_child(hud._label("%s is building." % sim.resident(s.builder).name, false, Palette.CHALK_DIM))
		if s.stage + 1 < Sim.stages_of(s).size():
			var nxt: Dictionary = Sim.stages_of(s)[s.stage + 1]
			c.add_child(hud._label("%s next: %s." % [nxt.name, Defs.cost_text(nxt.cost)], false, Palette.CHALK_DIM, Palette.BODY, true))
		if not s.get("grow", false):  # a house that is growing keeps what it has
			c.add_child(hud._destructive("Cancel blueprint", "Click again to cancel the blueprint", "site:%d" % s.id, func(): game.cancel_site(s)))
		return
	if s.tpl == "storehouse":  # issue #189
		hud._panels().fill_storehouse(c, sim, s)
		return
	if s.tpl == "cartographer_table" and s.done:  # issue #321
		hud._panels().fill_cartographer(c, sim, s)
		return
	if s.tpl == "composter" and s.done:  # issue #269
		hud._panels().fill_farm(c, sim, s)
		return
	if s.tpl == "enchanting_workshop" and s.done:  # issue #165
		hud._panels().fill_enchanting(c, sim, s)
		return
	if s.tpl == "house":
		var owner := sim.resident(s.owner)
		var line := "Home of %s." % owner.name if not owner.is_empty() else ("Empty. A traveler should arrive soon." if sim.arrival_at >= 0 else "Empty.")
		var tier := Sim.house_tier(s)
		c.add_child(hud._label(Defs.HOUSE_TIER_NAMES[tier - 1] if tier >= 1 else "House", true, Palette.CHALK, Palette.TITLE))
		c.add_child(hud._label(line, false, Palette.CHALK_DIM, Palette.BODY, true))
		if Sim.is_old_house(s):  # issue #356
			var in_place := sim.house_update_in_place(s)
			c.add_child(hud._label("An old house, with no entrance. %s eats and sleeps here but takes no work until it's updated." % (owner.name if not owner.is_empty() else "Its resident"), false, Palette.YELLOW, Palette.BODY, true))
			var upd := hud._button("Update" if in_place else "Update: move it", func(): game.update_house(s), "Primary")
			upd.tooltip_text = "Gives it an entrance where it stands, free." if in_place else "There's no room for a door here. Pick it up and put it down where a 5x5 and its entrance fit."
			c.add_child(upd)
		if s.has("tier") and s.tier < 3 and not owner.is_empty():
			var need: int = Tuning.EMERALD_COSTS[s.tier - 1]
			var next: String = Defs.HOUSE_TIER_NAMES[s.tier].to_lower()
			c.add_child(hud._row("Emeralds", "%d / %d" % [owner.get("emeralds", 0), need], false))
			c.add_child(hud._label("Upgrading to a %s costs %d emeralds from %s, then %s." % [next, need, owner.name, Defs.cost_text(Defs.house_cost(s.tier + 1))], false, Palette.CHALK_DIM, Palette.CAPTION, true))
			var up := hud._button("Upgrade to a %s" % next, func(): game.upgrade_house(s), "Primary")
			up.disabled = sim.house_upgrade_check(s) != ""
			up.tooltip_text = sim.house_upgrade_check(s)
			c.add_child(up)
		return
	if s.tpl == "board":  # its planner opens above the toolbar (issue #106)
		c.add_child(hud._label(tpl.name, true, Palette.CHALK, Palette.TITLE))
		c.add_child(hud._label(hud._board_status(sim), false, Palette.CHALK_DIM, Palette.BODY, true))
		for x in reasons:
			c.add_child(hud._reason(x.why) if not x.waiting else hud._label(x.why, false, Palette.CHALK_DIM, Palette.BODY, true))
		if not game.planner_open:
			c.add_child(hud._button("Open the planner", func(): game.open_planner(), "Primary"))
		return
	if not Sim.work_of(s).is_empty():  # a chopping block or mason's bench (issue #177)
		hud._panels().fill_workstation(c, sim, s, reasons)
		return
	if not Sim.is_station(s):  # the toolsmith's bench, composter, lodge or builder's table (issue #184)
		c.add_child(hud._label(sim.station_title(s), true, Palette.CHALK, Palette.TITLE))
		c.add_child(hud._label(_station_line(sim, s), false, Palette.CHALK_DIM, Palette.BODY, true))
		for x in reasons:
			c.add_child(hud._reason(x.why) if not x.waiting else hud._label(x.why, false, Palette.CHALK_DIM, Palette.BODY, true))
		return
	# A finished bench or fireplace: a short summary here. Its recipes and queue live only in the
	# Craft panel on the right, which selecting it opens.
	c.add_child(hud._label(sim.station_title(s), true, Palette.CHALK, Palette.TITLE))
	c.add_child(hud._label(_station_line(sim, s), false, Palette.CHALK_DIM, Palette.CAPTION, true))
	c.add_child(hud._label(_bench_status(sim, s), false, Palette.CHALK_DIM, Palette.BODY, true))
	for x in reasons:
		c.add_child(hud._reason(x.why))
	if not game.craft_menu_open:
		c.add_child(hud._button("Open the craft menu", func(): game.open_craft_menu(s), "Primary"))


## A workstation's standing order (issue #178): "Keep 20 planks", with − and +. 0 is off.
func _make_keep_row(sim: Sim, s: Dictionary) -> Control:
	var rec := Defs.recipe(Defs.TEMPLATES[s.tpl].makes)
	var out: String = rec.out.keys()[0]
	var v := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var n: int = s.get("make_keep", 0)
	var less := hud._button("−", func(): game.set_make_keep(s, n - Tuning.MAKE_STEP), "Secondary")
	less.disabled = n <= 0
	less.tooltip_text = "Keep %d fewer" % Tuning.MAKE_STEP
	row.add_child(less)
	var lbl := hud._label("Keep %s" % Defs.words(out, n) if n > 0 else "Make %s: off" % Defs.ITEMS[out].many, false, Palette.CHALK, Palette.BODY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	var more := hud._button("+", func(): game.set_make_keep(s, n + Tuning.MAKE_STEP), "Secondary")
	more.tooltip_text = "Keep %d more" % Tuning.MAKE_STEP
	row.add_child(more)
	v.add_child(row)
	var inp: String = rec.inp.keys()[0]
	v.add_child(hud._label("The village has %d. While it has fewer, %ss make them here from %s." % [sim.free_count(out), Defs.JOB_NAMES[Sim.recipe_job(rec)].to_lower(), Defs.ITEMS[inp].many] if n > 0 else "Nothing is made here unless you queue it.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
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
		c.add_child(hud._label(Defs.TEMPLATES[s.tpl].name, true, Palette.CHALK, Palette.HEADING))
	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 2)
	status.custom_minimum_size = Vector2(0, 44)
	status.add_child(hud._label(_bench_status(sim, s), false, Palette.CHALK, Palette.BODY, true))
	for x in reasons.slice(0, 1):
		status.add_child(hud._reason(x.why) if not x.waiting else hud._label(x.why, false, Palette.CHALK_DIM, Palette.BODY, true))
	c.add_child(status)
	var recipes: Array = Defs.recipes_shown(sim, s.tpl)
	for q in s.queue:  # whatever's already queued stays in the book, in its place
		var queued := Defs.recipe(q)
		if not queued.is_empty() and not recipes.has(queued):
			recipes.append(queued)
	if recipes.is_empty():  # a station built before the book reached it (a save, a test): show its whole book
		recipes = Defs.recipes_at(s.tpl)
	var rec: Dictionary = Defs.recipe(hud._craft_pick.get(s.tpl, recipes[0].id))
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
	right.add_child(hud._label(rec.name, true, Palette.CHALK, Palette.BODY, true))
	right.add_child(_queue_control(s, rec))
	table.add_child(right)
	c.add_child(table)
	c.add_child(hud._rule())
	var bar := _hotbar(sim, s)
	if s.tpl == "bench":
		bar.tooltip_text = "Missing planks and sticks are queued automatically." if sim.auto_craft else "Once Ada’s house is finished, the bench queues the planks and sticks a recipe needs."
	c.add_child(bar)
	c.add_child(_on_hand(sim, s))
	if Defs.TEMPLATES[s.tpl].has("makes"):
		c.add_child(_make_keep_row(sim, s))
	if s.tpl == "fireplace":
		var on: bool = s.get("keep_meals", true)
		var keep := hud._button("Keep %d meals in stock: %s" % [Tuning.MEAL_STOCK, "on" if on else "off"], func(): game.set_keep_meals(s, not on), "Secondary")
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
	var sb := hud._box(Palette.SLATE_DEEP, 3, 0, outline)
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
		var count := hud._label("%d" % n, true, Palette.CHALK, Palette.CAPTION)
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
	var b := hud._button("", func(): hud._craft_pick[s.tpl] = rec.id, "Secondary")
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
	var n: int = hud._craft_n.get(rec.id, 1)
	var q := hud._button("Queue %d" % n, func(): game.queue_craft(s, rec.id, hud._craft_n.get(rec.id, 1)), "Primary")
	q.custom_minimum_size = Vector2(84, 0)
	var less := hud._button("−", func(): pass, "Secondary")
	var more := hud._button("+", func(): pass, "Secondary")
	var step := func(by: int) -> void:
		var m: int = clampi(hud._craft_n.get(rec.id, 1) + by, 1, hud.CRAFT_MAX)
		hud._craft_n[rec.id] = m
		q.text = "Queue %d" % m
		less.disabled = m <= 1
		more.disabled = m >= hud.CRAFT_MAX
	less.pressed.connect(step.bind(-1))
	more.pressed.connect(step.bind(1))
	less.disabled = n <= 1
	more.disabled = n >= hud.CRAFT_MAX
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
	v.add_child(hud._label("Queue" if not s.queue.is_empty() else "Queue: nothing yet. Pick a recipe above and queue it.", true if not s.queue.is_empty() else false, Palette.CHALK if not s.queue.is_empty() else Palette.CHALK_DIM, Palette.BODY))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	var shown := mini(s.queue.size(), hud.HOTBAR)
	for i in shown:
		var rec := Defs.recipe(s.queue[i])
		var out_type: String = rec.out.keys()[0]
		var b := hud._button("", func(): game.unqueue_craft(s, i), "Secondary")
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
			var m := hud._label(mark, true, Palette.CHALK_DIM, Palette.CAPTION)
			m.position = Vector2(3, 0)
			m.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(m)
		if i == 0 and s.crafter != 0 and s.crafting == rec.name:
			var fill := hud._bar(_craft_progress(sim, s), Palette.GREEN)
			fill.position = Vector2(4, 30)
			fill.size = Vector2(28, 3)
			fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(fill)
		b.tooltip_text = "%s%s. Click to remove." % [rec.name, {"T": " (toolsmith)", "A": " (auto)"}.get(mark, "")]
		bar.add_child(b)
	for i in range(shown, hud.HOTBAR):
		bar.add_child(_slot("", 1, 36, Color(Palette.CHALK_DIM, 0.35)))
	v.add_child(bar)
	if s.queue.size() > hud.HOTBAR:
		v.add_child(hud._label("and %d more" % (s.queue.size() - hud.HOTBAR), false, Palette.CHALK_DIM, Palette.CAPTION))
	return v


## How far along the craft at the head of the queue is, 0 to 1.
func _craft_progress(sim: Sim, s: Dictionary) -> float:
	var r := sim.resident(s.crafter)
	return clampf(r.progress, 0.0, 1.0) if not r.is_empty() and r.progress >= 0 else 0.0


## The village's stock of this station's ingredients, read-only, like an inventory row.
func _on_hand(sim: Sim, s: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var l := hud._label("On hand", true, Palette.CHALK, Palette.BODY)
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
			var count := hud._label("%d" % n, true, Palette.CHALK if n > 0 else Palette.CHALK_DIM, Palette.CAPTION)
			count.add_theme_color_override("font_outline_color", Palette.SLATE_DEEP)
			count.add_theme_constant_override("outline_size", 4)
			count.size_flags_horizontal = Control.SIZE_SHRINK_END
			count.size_flags_vertical = Control.SIZE_SHRINK_END
			slot.add_child(count)
		slot.tooltip_text = "%s on hand" % Defs.words(k, n)
		h.add_child(slot)
	return h
