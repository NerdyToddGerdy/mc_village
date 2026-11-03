class_name SitePanels
extends RefCounted
## The info panels for finished buildings with something of their own to show: the storehouse, composter, enchanting workshop,
## devices, portal station and the work buildings (split out of hud.gd, #305). They are drawn with the HUD's own helpers.

var hud: Hud
var game


func _init(h: Hud, g) -> void:
	hud = h
	game = g


func fill_storehouse(c: Container, sim: Sim, s: Dictionary) -> void:
	c.add_child(hud._label("Storehouse", true, Palette.CHALK, Palette.TITLE))
	var slots := Sim.store_slots(s)
	var used := slots.filter(func(k): return sim.items.has(k)).size()
	var chests: int = s.get("chests", 0)
	c.add_child(hud._row("Chests", "%d / %d" % [chests, Sim.store_chest_cap(s)], false))
	if chests > 0:
		c.add_child(hud._row("Stacks", "%d / %d" % [used, slots.size()], false))
		c.add_child(hud._bar(float(used) / slots.size()))
	var held := {}
	for k in slots:
		var it = sim.items.get(k)
		if it != null:
			held[it.type] = held.get(it.type, 0) + it.n
	if not held.is_empty():
		var parts: PackedStringArray = []
		for t in held:
			parts.append(Defs.words(t, held[t]))
		c.add_child(hud._label("Holds " + ", ".join(parts) + ".", false, Palette.CHALK, Palette.BODY, true))
	var more := "Haulers bring loose things here first; the stockpile takes what doesn't fit." if chests > 0 else "Craft a chest at the bench (8 planks): a hauler carries it in, and it holds %d stacks of anything." % Tuning.CHEST_STACKS
	var growing: bool = game.tool == "room" and game.area_site == s.id
	var wide: int = Sim.store_width(s)
	var room := hud._button("Done painting" if growing else "Paint more room", func(): game.start_room(s), "Primary" if growing else "Secondary")
	room.disabled = wide >= Tuning.STORE_WIDTH_MAX and not growing
	room.tooltip_text = "Drag over whole columns of three cells left or right of the door's column. %s a column; up to %d wide (it's %d now)." % [Defs.cost_text(Tuning.STORE_COLUMN_COST), Tuning.STORE_WIDTH_MAX, wide]
	c.add_child(room)
	if chests > 0 and chests < Sim.store_chest_cap(s):
		more += " Each chest crafted at the bench adds %d stacks, up to %d chests." % [Tuning.CHEST_STACKS, Sim.store_chest_cap(s)]
	c.add_child(hud._label(more, false, Palette.CHALK_DIM, Palette.CAPTION, true))
	for x in sim.stuck.filter(func(x): return x.focus_kind == "site" and x.focus_id == s.id):
		c.add_child(hud._reason(x.why))


## A finished composter (issue #269): who farms, the wheat the village has against its target, and the target with a stepper.
func fill_farm(c: Container, sim: Sim, s: Dictionary) -> void:
	c.add_child(hud._label(sim.station_title(s), true, Palette.CHALK, Palette.TITLE))
	var have := sim.free_count("wheat")
	c.add_child(hud._row("Wheat", "%d of %d kept" % [have, sim.wheat_keep], false))
	c.add_child(hud._bar(minf(1.0, float(have) / maxf(1.0, sim.wheat_keep))))
	var keep := HBoxContainer.new()
	keep.add_theme_constant_override("separation", 6)
	var less := hud._button("−", func(): game.set_wheat_keep(sim.wheat_keep - Tuning.KEEP_STEP), "Secondary")
	less.disabled = sim.wheat_keep <= 0
	less.tooltip_text = "Keep %d fewer" % Tuning.KEEP_STEP
	keep.add_child(less)
	var lbl := hud._label("Keep %d wheat" % sim.wheat_keep, false, Palette.CHALK, Palette.BODY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keep.add_child(lbl)
	var more := hud._button("+", func(): game.set_wheat_keep(sim.wheat_keep + Tuning.KEEP_STEP), "Secondary")
	more.tooltip_text = "Keep %d more" % Tuning.KEEP_STEP
	keep.add_child(more)
	c.add_child(keep)
	var plots := sim.composter_plots(s).size()
	var painting: bool = game.tool == "plots" and game.area_site == s.id
	var paint := hud._button("Done painting" if painting else "Paint plots", func(): game.start_plots(s), "Primary" if painting else "Secondary")
	paint.tooltip_text = "Drag over open grass within %d cells of the composter. Start on one of its plots to take it away. It has %d now." % [Tuning.PLOT_REACH, plots]
	c.add_child(paint)
	c.add_child(hud._label("Farmers plant and harvest the painted plots until the village has this much wheat. The crop waits on the plot and is picked again once it falls below.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
	for x in sim.stuck.filter(func(x): return x.focus_kind == "site" and x.focus_id == s.id):
		c.add_child(hud._reason(x.why))


## A finished storehouse (issue #189): its chests, how full they are, and what's in them.
## A finished enchanting workshop (issues #165, #166): who works it, and each recipe, known or not, with its cost.
func fill_enchanting(c: Container, sim: Sim, s: Dictionary) -> void:
	c.add_child(hud._label("Enchanting workshop", true, Palette.CHALK, Palette.TITLE))
	var who := sim.resident(s.get("worker", 0))
	c.add_child(hud._row("Enchanter", who.name if not who.is_empty() else "none (Ada works it, or give someone the job)", false))
	c.add_child(hud._label("Recipes", true))
	for k in Defs.ENCHANTS:
		var e: Dictionary = Defs.ENCHANTS[k]
		var cost: PackedStringArray = []
		for it in e.cost:
			cost.append(Defs.words(it, e.cost[it]))
		var known: bool = s.known.has(k)
		c.add_child(hud._row(e.name, "known" if known else "unknown: needs its book", false))
		c.add_child(hud._label("Costs " + ", ".join(cost) + ". " + Sim.enchant_text(k), false, Palette.CHALK_DIM, Palette.CAPTION, true))
	var known: Array = s.known
	if not known.is_empty():  # order an enchantment on gear in the stockpile (issue #166)
		c.add_child(hud._label("Enchant", true))
		for k in known:
			var types: Array = sim.enchantable_types(k)
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 4)
			row.add_child(hud._label(Defs.ENCHANTS[k].name + ":", false, Palette.CHALK_DIM, Palette.CAPTION))
			if types.is_empty():
				row.add_child(hud._label("nothing in the stockpile it can go on", false, Palette.CHALK_DIM, Palette.CAPTION))
			for t in types:
				var b := hud._button(Defs.BASE_ITEMS[t].one.substr(0, 1).to_upper() + Defs.BASE_ITEMS[t].one.substr(1), func(): game.order_enchant(k, t), "Secondary")
				b.set_meta("label", "Enchant %s: %s" % [Defs.ENCHANTS[k].name, Defs.BASE_ITEMS[t].one])
				row.add_child(b)
			c.add_child(row)
	if not s.orders.is_empty():
		c.add_child(hud._label("Orders", true))
		for i in s.orders.size():
			var o: Dictionary = s.orders[i]
			var line := HBoxContainer.new()
			var l := hud._label("%s on a %s" % [Defs.ENCHANTS[o.ench].name, Defs.BASE_ITEMS[o.item].one], false, Palette.CHALK, Palette.BODY)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(l)
			line.add_child(hud._button("Cancel", func(): game.cancel_enchant(i), "Secondary"))
			c.add_child(line)
	c.add_child(hud._label("A book carried here teaches its recipe for good, and is used up.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
	for x in sim.stuck.filter(func(x): return x.focus_kind == "site" and x.focus_id == s.id):
		c.add_child(hud._reason(x.why))


## A redstone device (issues #170, #171): on or off and why, its settings, and the dust lines in and out with a way to draw one.
func fill_device(c: Container, sim: Sim, s: Dictionary) -> void:
	var kind: String = Defs.TEMPLATES[s.tpl].device
	c.add_child(hud._head(Defs.TEMPLATES[s.tpl].name, "On" if s.out else "Off"))
	c.add_child(hud._label(s.why, false, Palette.YELLOW if s.out else Palette.CHALK_DIM, Palette.BODY, true))
	match kind:
		"sensor":
			var items: Array = Tuning.SENSOR_ITEMS
			var nxt: String = items[(items.find(s.cfg.item) + 1) % items.size()]
			c.add_child(hud._row("Watching", "meals" if s.cfg.item == "food" else Defs.ITEMS[s.cfg.item].many))
			c.add_child(hud._button("Watch %s instead" % ("meals" if nxt == "food" else Defs.ITEMS[nxt].many), func(): game.set_device_cfg(s.id, "item", nxt)))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.add_child(hud._label("On when below", false, Palette.CHALK_DIM))
			row.add_child(hud._button("−", func(): game.set_device_cfg(s.id, "below", s.cfg.below - 1)))
			row.add_child(hud._label(str(s.cfg.below), true))
			row.add_child(hud._button("+", func(): game.set_device_cfg(s.id, "below", s.cfg.below + 1)))
			c.add_child(row)
			var have := sim.cache_count(s.cfg.item) if sim.shelter_site().get("done", false) else -1
			c.add_child(hud._row("In the cache now", str(have) if have >= 0 else "no shelter yet"))
		"loader":
			c.add_child(hud._row("Freight list", Sim.freight_list_text(s.cfg.list)))
			for k in ["bread", "iron_ingot", "plank", "cobble"]:
				var have: int = s.cfg.list.get(k, 0)
				var lrow := HBoxContainer.new()
				lrow.add_theme_constant_override("separation", 8)
				lrow.add_child(hud._label(Defs.ITEMS[k].label, false, Palette.CHALK_DIM))
				lrow.add_child(hud._button("−", func(): game.set_freight_item(s.id, k, have - 1)))
				lrow.add_child(hud._label(str(have), true))
				lrow.add_child(hud._button("+", func(): game.set_freight_item(s.id, k, have + 1)))
				c.add_child(lrow)
			c.add_child(hud._label("When powered, haulers carry the list from the stockpile onto the freight cart (%d items at most). It signals \"loaded\" when the cart has it all." % Tuning.FREIGHT_CAPACITY, false, Palette.CHALK_DIM, Palette.CAPTION, true))
		"dispatcher":
			c.add_child(hud._label("When powered and the cart is loaded it asks you to approve the departure. It never sends the cart itself: approve or decline from the portal station's panel.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
		"condition":
			var facts: Array = Sim.CONDITION_FACTS
			var nf: String = facts[(facts.find(s.cfg.fact) + 1) % facts.size()]
			c.add_child(hud._row("Passes while", sim.condition_fact(s.cfg.fact).yes))
			c.add_child(hud._button("Check \"%s\" instead" % sim.condition_fact(nf).yes, func(): game.set_device_cfg(s.id, "fact", nf)))
	var lines := sim.wires.filter(func(w): return w.from == s.id or w.to == s.id)
	for w in lines:
		var other := sim.device_by_id(w.to if w.from == s.id else w.from)
		var verb := "Feeds" if w.from == s.id else "Fed by"
		var state := "" if Sim.wire_complete(w) else " (%d of %d laid)" % [w.laid, w.cells.size()]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(hud._label("%s %s%s" % [verb, Defs.TEMPLATES[other.tpl].name.to_lower(), state], false, Palette.CHALK))
		row.add_child(hud._button("Cut", func(): game.cut_wire(w.id)))
		c.add_child(row)
	if kind != "":
		for o in sim.maps.village.sites.filter(func(x): return Sim.is_device(x) and x.done and x.id != s.id and Defs.TEMPLATES[x.tpl].device != "sensor"):
			if not sim.wires.any(func(w): return w.from == s.id and w.to == o.id):
				var oid: int = o.id
				var b := hud._button("Wire to the %s" % Defs.TEMPLATES[o.tpl].name.to_lower(), func(): game.order_wire(s.id, oid))
				b.tooltip_text = "A resident lays redstone dust from this device's output to that one's input."
				c.add_child(b)
	for x in sim.stuck.filter(func(x): return x.focus_kind == "site" and x.focus_id == s.id):
		c.add_child(hud._reason(x.why))


## The portal station (issues #168, #169): the line's state, and the freight cart with its load and the departure approval.
func fill_portal_station(c: Container, sim: Sim, s: Dictionary) -> void:
	c.add_child(hud._head("Portal station", "Village end"))
	var line := "complete" if sim.pline_complete() else "%d of %d rails laid%s" % [sim.portal_line.laid, Tuning.PORTAL_LINE_RAILS, "" if sim.nline().stations.landing else ", no landing station"]
	c.add_child(hud._row("The portal line", line))
	var fr: Dictionary = sim.freight
	if fr.is_empty():
		var why := sim.order_freight_cart_blocker()
		var b := hud._button("Order a freight cart", func(): game.order_freight_cart(), "Primary")
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else "A hauler brings a minecart from the stockpile and parks it here as the line's freight cart."
		c.add_child(b)
		c.add_child(hud._label("The freight cart carries goods through the portal to the Nether cache, never riders. It only leaves when you approve it.", false, Palette.CHALK_DIM, Palette.CAPTION, true))
	else:
		var states := {"ordered": "Waiting for a minecart", "home": "Parked at the station", "going": "On its way to the landing", "unloading": "Unloading into the cache", "returning": "Coming home empty"}
		c.add_child(hud._row("Freight cart", states[fr.state]))
		if fr.state != "ordered":
			c.add_child(hud._row("Load", ", ".join(fr.load.keys().map(func(k): return Defs.words(k, fr.load[k]))) if not fr.load.is_empty() else "empty"))
		if fr.state == "home":
			if fr.approved:
				c.add_child(hud._button("Cancel approval", func(): game.cancel_freight_approval()))
			else:
				var ab := hud._button("Approve departure", func(): game.approve_freight(), "Primary")
				ab.disabled = fr.load.is_empty()
				ab.tooltip_text = "Send the loaded cart through the portal to the cache." if not fr.load.is_empty() else "Nothing is loaded."
				c.add_child(ab)
				if not fr.load.is_empty():
					var db := hud._button("Decline: unload it", func(): game.decline_freight())
					db.tooltip_text = "Put the load back in the stockpile."
					c.add_child(db)
	for x in sim.stuck.filter(func(x): return x.focus_kind == "site" and x.focus_id == s.id):
		c.add_child(hud._reason(x.why) if not x.waiting else hud._label(x.why, false, Palette.CHALK_DIM, Palette.BODY, true))  # a choice for you is not a fault


## A finished chopping block or mason's bench (issue #177): its pile, its keep-stock target with a
## stepper, who works it, and what holds it up.
func fill_workstation(c: Container, sim: Sim, s: Dictionary, reasons: Array) -> void:
	var wk := Sim.work_of(s)
	var item: Dictionary = Defs.ITEMS[wk.item]
	c.add_child(hud._label(sim.station_title(s), true, Palette.CHALK, Palette.TITLE))
	var n := sim.pile_count(s)
	c.add_child(hud._row("Pile", "%d / %d %s" % [n, Tuning.WORK_STORE, item.many], false))
	c.add_child(hud._bar(float(n) / Tuning.WORK_STORE))
	var keep := HBoxContainer.new()
	keep.add_theme_constant_override("separation", 6)
	var less := hud._button("−", func(): game.set_keep_stock(s, s.keep - Tuning.KEEP_STEP), "Secondary")
	less.disabled = s.keep <= 0
	less.tooltip_text = "Keep %d fewer" % Tuning.KEEP_STEP
	keep.add_child(less)
	var lbl := hud._label("Keep %d %s" % [s.keep, item.many], false, Palette.CHALK, Palette.BODY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keep.add_child(lbl)
	var more := hud._button("+", func(): game.set_keep_stock(s, s.keep + Tuning.KEEP_STEP), "Secondary")
	more.tooltip_text = "Keep %d more" % Tuning.KEEP_STEP
	keep.add_child(more)
	c.add_child(keep)
	if s.get("shaft", false):
		c.add_child(hud._label("The village has %d. %ss dig 1 cobblestone every %d s from where it stands until it has %d." % [
			sim.free_count(wk.item), Defs.JOB_NAMES[wk.job], int(Tuning.SHAFT_DIG), s.keep], false, Palette.CHALK_DIM, Palette.CAPTION, true))
	else:
		c.add_child(hud._label("The village has %d. %ss %s in its area on their own until it has %d." % [
			sim.free_count(wk.item), Defs.JOB_NAMES[wk.job], "fell trees" if wk.kind == "tree" else "break boulders",
			s.keep], false, Palette.CHALK_DIM, Palette.CAPTION, true))
	var painting: bool = game.tool == "area" and game.area_site == s.id  # its work area is painted (issue #203)
	var paint := hud._button("Done painting" if painting else "Paint area", func(): game.start_area(s), "Primary" if painting else "Secondary")
	paint.tooltip_text = "Drag over the ground it works (%d cells of it, within %d of it). Start on a painted cell to erase." % [s.get("area", {}).size(), int(Tuning.WORK_REACH)]
	c.add_child(paint)
	if s.tpl == "mason_bench" and not s.get("shaft", false):  # issue #204: dug out into a mineshaft once every boulder is gone
		var why := sim.shaft_check(s)
		var up := hud._button("Dig out a mineshaft", func(): game.upgrade_shaft(s), "Secondary" if why != "" else "Primary")
		up.disabled = why != ""
		up.tooltip_text = why if why != "" else "Rebuild it as a mineshaft (%s). It digs cobblestone from where it stands, slowly, with no boulders needed." % Defs.cost_text(Tuning.SHAFT_COST)
		c.add_child(up)
		if why != "":
			c.add_child(hud._label(why, false, Palette.CHALK_DIM, Palette.CAPTION, true))
	c.add_child(hud._label(hud._station_line(sim, s), false, Palette.CHALK_DIM, Palette.CAPTION, true))
	for x in reasons:
		c.add_child(hud._reason(x.why) if not x.waiting else hud._label(x.why, false, Palette.CHALK_DIM, Palette.BODY, true))
	c.add_child(hud._rule())
	c.add_child(hud._label(hud._bench_status(sim, s), false, Palette.CHALK_DIM, Palette.BODY, true))
	c.add_child(hud._make_keep_row(sim, s))
	if not game.craft_menu_open:
		c.add_child(hud._button("Open the craft menu", func(): game.open_craft_menu(s), "Secondary"))


## A finished cartographer's table (issue #321): who works it, what's been found, and the survey: a ring of each sector to send them to.
func fill_cartographer(c: Container, sim: Sim, s: Dictionary) -> void:
	c.add_child(hud._label("Cartographer's table", true, Palette.CHALK, Palette.TITLE))
	var who := Survey.cartographer(sim)
	c.add_child(hud._row("Cartographer", who.name if not who.is_empty() else "none (give someone the job)", false))
	var sv: Dictionary = sim.stats.get("survey", {})
	if not sv.is_empty():
		var left := maxf(0.0, float(who.back_at - sim.tick) / Tuning.TPS)
		c.add_child(hud._label("%s is surveying the %s ring to the %s: back in %d s." % [who.name, Survey.ring_name(sv.ring), sv.sector, int(ceil(left))], false, Palette.CHALK, Palette.BODY, true))
	var next := Survey.next_find(sim)
	var found: Array = Survey.FINDS.filter(func(id): return Survey.found(sim, id)).map(func(id): return Survey.FIND_NAMES[id])
	c.add_child(hud._label("Found: %s." % (", ".join(found) if not found.is_empty() else "nothing yet"), false, Palette.CHALK_DIM, Palette.BODY, true))
	if next == "":
		c.add_child(hud._label("There's nothing more to find on foot yet.", false, Palette.CHALK_DIM, Palette.BODY, true))
	c.add_child(hud._label("Survey", true))
	for sector in Survey.SECTORS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name := hud._label(sector.capitalize(), false, Palette.CHALK_DIM)
		name.custom_minimum_size = Vector2(92, 0)
		row.add_child(name)
		for ring in range(1, 4):
			var done := Survey.surveyed(sim, sector, ring)
			var why := Survey.check(sim, sector, ring)
			var label := "%s √" % Survey.ring_name(ring).capitalize() if done else Survey.ring_name(ring).capitalize()
			var b: Button = hud._button(label, func(): game.start_survey(sector, ring), "Secondary")
			b.set_meta("label", "Survey %s %d" % [sector, ring])
			b.disabled = why != ""
			b.tooltip_text = why if why != "" else "%d s there and back, %d%% chance of being driven back" % [int(Survey.seconds(sim, ring)), int(Survey.danger(sim, ring) * 100)]
			row.add_child(b)
		c.add_child(row)
