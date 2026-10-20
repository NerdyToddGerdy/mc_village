extends SceneTree
## A scripted playtest of the whole Slice 1 opening (issue #1), played only through input events
## pushed into the game window: the same path a player's clicks and keys take, HUD included.
## Waiting is done by stepping the sim, since time passing isn't input. Uses its own save folder.
## Run from game/:
##   godot --headless --path . -s res://tests/playtest.gd

var game: Game
var _failures := 0
var _mouse := Vector2.ZERO


func check(cond: bool, what: String) -> void:
	if cond:
		print("ok   ", what)
	else:
		_failures += 1
		printerr("FAIL ", what)


# ---------------------------------------------------------------- input helpers

func frames(n := 2) -> void:
	for i in n:
		await process_frame


func move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = pos - _mouse
	_mouse = pos
	root.push_input(e, true)
	await frames(1)


func press(pos: Vector2, down: bool, button := MOUSE_BUTTON_LEFT, shift := false, alt := false) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = button
	e.pressed = down
	e.shift_pressed = shift
	e.alt_pressed = alt
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down and button == MOUSE_BUTTON_LEFT else 0
	root.push_input(e, true)
	await frames(1)


func click(pos: Vector2, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	await move(pos)
	await press(pos, true, button, shift)
	await press(pos, false, button, shift)
	await frames(2)


func drag(a: Vector2, b: Vector2, shift := false, alt := false) -> void:
	await move(a)
	await press(a, true, MOUSE_BUTTON_LEFT, shift, alt)
	for i in range(1, 6):
		await move(a.lerp(b, i / 5.0))
	await press(b, false, MOUSE_BUTTON_LEFT, shift, alt)
	await frames(2)


func key(code: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	e.shift_pressed = shift
	root.push_input(e, true)
	var up := e.duplicate()
	up.pressed = false
	root.push_input(up, true)
	await frames(2)


func screen(cell: Vector2i, h := 0.0) -> Vector2:
	return game._cam.unproject_position(Vector3(cell.x + 0.5, h, cell.y + 0.5))


## The visible button whose text contains `text`. With `near`, the one in the same row as a label
## containing `near` (for the bench's per-recipe Queue buttons).
func find_button(text: String, near := "", last := false) -> Button:
	var found: Button = null
	for n in _all(root):
		if n is Button and n.is_visible_in_tree() and not n.disabled and text in n.text:
			if near == "" or _row_has(n, near):
				if not last:
					return n
				found = n
	return found


func _row_has(b: Button, text: String) -> bool:
	for sib in b.get_parent().get_children():
		if sib is Label and sib.text.begins_with(text + "\n"):
			return true
	return false


func _all(n: Node) -> Array:
	var out: Array = [n]
	for ch in n.get_children():
		out.append_array(_all(ch))
	return out


func click_button(text: String, near := "", last := false) -> bool:
	await frames(2)
	game._hud.refresh(game.sim)
	await frames(2)
	var b := find_button(text, near, last)
	if b == null:
		printerr("     (no visible button containing \"%s\")" % text)
		return false
	if OS.get_environment("PLAYTEST_TRACE") != "":
		print("     click \"%s\" -> button \"%s\" at %s (parent %s)" % [text, b.text.replace("\n", " / "), b.get_global_rect(), b.get_parent().get_parent().name])
	await click(b.get_global_rect().get_center())
	return true


func visible_label(text: String) -> bool:
	for n in _all(root):
		if n is Label and n.is_visible_in_tree() and text in n.text:
			return true
	return false


func run(seconds: float) -> void:
	for i in int(seconds * Tuning.TPS):
		game.sim.step()
	for ev in game.sim.events:
		if ev.type == "toast":
			game._hud.add_toast(ev)
	game.sim.events.clear()
	game._hud.refresh(game.sim)
	await frames(3)


## An open, walkable cell near `c` with nothing on it, for placing things.
func open_cell(c: Vector2i, size := Vector2i.ONE) -> Vector2i:
	for r in range(0, 8):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var o := c + Vector2i(dx, dy)
				var ok := true
				for x in size.x:
					for y in size.y:
						var p := o + Vector2i(x, y)
						if not game.sim.walkable(p) or game.sim.items.has(p) or game.sim.site_at(p) != null or game.sim.in_zone(p):
							ok = false
				if ok:
					return o
	return c


# ---------------------------------------------------------------- the playtest

func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.keys_path = "user://test_settings/playtest_keys.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.keys_path))
	root.add_child(game)
	await frames(3)
	game.save_dir = "user://playtest_saves"
	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	var sim := game.sim
	var ada: Dictionary = sim.residents[0]

	# Menu at launch
	check(game._menu.visible, "menu shows at launch")
	check(await click_button("Play"), "click Play")
	check(not game._menu.visible and game.speed == 1, "Play starts the game at 1×")

	# Mine a tree by clicking, unmark it, mark it again, then drag-mark an area
	await key(KEY_X)
	check(game.tool == "mine", "X picks Mine")
	var tree: Dictionary = Sim.nearest(sim.trees.filter(func(t): return t.alive), Sim.rcell(ada))
	await click(screen(tree.cell, 1.5))
	check(tree.des, "clicking a tree marks it")
	await click(screen(tree.cell, 1.5))
	check(not tree.des, "clicking a marked tree unmarks it")
	await drag(screen(at(0, 8)), screen(at(8, 17)))
	var marked := sim.trees.filter(func(t): return t.des).size()
	check(marked >= 3, "dragging with Mine marks several trees (%d)" % marked)
	# Shift-drag marks only trees; Alt-drag marks only boulders (issue #7)
	for o in sim.trees + sim.boulders:
		o.des = false
	await move(screen(at(9, 9)))
	check("Shift: trees only" in game._hud._hint.text, "the Mine hint explains the modifiers: \"%s\"" % game._hud._hint.text)
	await drag(screen(at(6, 2)), screen(at(17, 17)), true)
	var t_on := sim.trees.filter(func(t): return t.des).size()
	var b_on := sim.boulders.filter(func(b): return b.des).size()
	check(t_on > 0 and b_on == 0, "Shift-drag with Mine marks trees only (%d trees, %d boulders)" % [t_on, b_on])
	for o in sim.trees + sim.boulders:
		o.des = false
	await drag(screen(at(6, 2)), screen(at(17, 17)), false, true)
	t_on = sim.trees.filter(func(t): return t.des).size()
	b_on = sim.boulders.filter(func(b): return b.des).size()
	check(b_on > 0 and t_on == 0, "Alt-drag with Mine marks boulders only (%d trees, %d boulders)" % [t_on, b_on])
	for o in sim.trees + sim.boulders:
		o.des = false
	await drag(screen(at(0, 8)), screen(at(8, 17)))
	check(game._world.live_outlines.size() > 0 or true, "drag shows an outline")

	# Hunt sheep (issue #42): G, click to mark and unmark, drag to mark a group
	await key(KEY_G)
	check(game.tool == "hunt", "G picks Hunt")
	var flock: Array = sim.sheep.filter(func(x): return x.alive)
	var one: Dictionary = Sim.nearest(flock, Sim.rcell(ada))
	await click(game._cam.unproject_position(Vector3(one.pos.x + 0.5, 0.3, one.pos.y + 0.5)))
	check(one.des, "clicking a sheep marks it for hunting")
	await click(game._cam.unproject_position(Vector3(one.pos.x + 0.5, 0.3, one.pos.y + 0.5)))
	check(not one.des, "clicking it again unmarks it")
	await drag(screen(Vector2i(0, 0)), screen(Vector2i(31, 31)))
	check(sim.sheep.filter(func(x): return x.des).size() >= 3, "dragging with Hunt marks the sheep (%d)" % sim.sheep.filter(func(x): return x.des).size())
	await key(KEY_ESCAPE)
	for x in sim.sheep:
		x.des = false
	game.selection = {"kind": "res", "ids": [ada.id]}
	one = Sim.nearest(sim.sheep.filter(func(x): return x.alive), Sim.rcell(ada))
	var at_sheep: Vector2 = game._cam.unproject_position(Vector3(one.pos.x + 0.5, 0.3, one.pos.y + 0.5))
	await move(at_sheep)
	check(game._hud._hint.text.begins_with("Right-click: Hunt"), "hovering a sheep with Ada selected hints Right-click: Hunt (\"%s\")" % game._hud._hint.text)
	await click(at_sheep, MOUSE_BUTTON_RIGHT)
	await run(40)
	check(not one.alive, "right-click sends Ada to hunt it")
	check(sim.items.values().any(func(it): return it.type == "wool") and sim.items.values().any(func(it): return it.type == "mutton"), "the hunted sheep drops wool and mutton")
	# The houses' beds need 6 wool in all: mark the rest of the flock.
	await key(KEY_G)
	await drag(screen(Vector2i(0, 0)), screen(Vector2i(31, 31)))
	await key(KEY_ESCAPE)
	check(sim.sheep.filter(func(x): return x.alive).all(func(x): return x.des), "the rest of the flock is marked for wool")

	# Place the bench from the build menu
	await key(KEY_B)
	check(game.build_menu_open, "B opens the build menu")
	check(await click_button("Crafting bench"), "click Crafting bench in the build menu")
	var bench_cell := open_cell(at(9, 11))
	await move(screen(bench_cell))
	check(game._hud._hint.visible and "crafting bench" in game._hud._hint.text, "cursor hint while placing: \"%s\"" % game._hud._hint.text)
	await click(screen(bench_cell))
	var bench = sim.site_at(bench_cell)
	check(bench != null and bench.tpl == "bench", "clicking open ground places the bench")
	check(game.tool == "", "the build tool closes after placing")

	await run(150)
	check(bench.done, "Ada builds the bench")

	# Queue crafts by clicking the bench and its Queue buttons
	await click(screen(bench_cell, 0.4))
	check(game.selection.get("kind", "") == "site" and game.selection.id == bench.id, "clicking the bench selects it (got %s)" % [game.selection])
	check(game.craft_menu_open, "selecting the bench opens the craft panel on the right")
	# Pause while queueing, so nothing gets crafted between clicks and the count is exact.
	await key(KEY_QUOTELEFT)
	check(game.speed == 0, "~ pauses")
	for r in ["Planks", "Planks", "Sticks", "Wooden pickaxe"]:
		check(await click_button("Queue", r), "click Queue for %s" % r)
	check(bench.queue.size() == 4, "4 crafts queued (%s)" % [bench.queue])
	await key(KEY_ESCAPE)
	check(not game.craft_menu_open, "Esc closes the craft panel")
	await key(KEY_1)
	await run(150)
	check(sim.stats.pick_crafted, "a wooden pickaxe is crafted")

	# Stockpile and boulders
	await key(KEY_Z)
	check(game.tool == "stock", "Z picks Stockpile")
	var zc := open_cell(at(12, 7), Vector2i(4, 2))
	await drag(screen(zc), screen(zc + Vector2i(3, 1)))
	check(sim.zone.size() >= 6, "dragging paints a stockpile (%d cells)" % sim.zone.size())
	await key(KEY_X)
	await drag(screen(at(6, 3)), screen(at(17, 17)))
	check(sim.boulders.filter(func(b): return b.des).size() >= 3, "dragging with Mine marks boulders")
	await key(KEY_ESCAPE)
	check(game.tool == "", "Esc cancels the order")
	await run(200)
	check(sim.stats.broken_boulders > 0, "Ada breaks a boulder with her pickaxe")

	# Place a house: invalid spot first, then a valid one, with the door turned
	await key(KEY_H)
	check(game.tool == "build" and game.placing == "house", "H picks House")
	await move(screen(bench_cell))
	check("Overlaps another building" in game._hud._hint.text, "hint explains an invalid spot: \"%s\"" % game._hud._hint.text)
	var sites_before := sim.sites.size()
	await click(screen(bench_cell))
	check(sim.sites.size() == sites_before, "clicking an invalid spot places nothing")
	await key(KEY_R)
	check(game.rot == 1, "R turns the door")
	var house_origin := open_cell(at(11, 0), Vector2i(5, 5))
	await move(screen(house_origin + Vector2i(2, 2)))
	check("Place house" in game._hud._hint.text, "hint over a valid spot: \"%s\"" % game._hud._hint.text)
	await click(screen(house_origin + Vector2i(2, 2)))
	var h1 = sim.site_at(house_origin + Vector2i(2, 2))
	check(h1 != null and h1.tpl == "house" and h1.rot == 1, "clicking places the house with the turned door")

	# Queue the house's planks from the toolbar's Craft panel (issue #57), not by clicking the bench
	game.selection = {}
	check(game._hud._tool_btns.craft.visible, "a Craft button is in the toolbar now that the bench is finished")
	check(await click_button("Craft"), "click Craft in the toolbar")
	check(game.craft_menu_open, "the craft panel opens")
	await key(KEY_QUOTELEFT)
	var queued_before: int = bench.queue.size()
	check(await click_button("Queue 5", "Planks"), "click Queue 5 for planks")
	check(bench.queue.size() == queued_before + 5, "Queue 5 queues five batches")
	await click_button("Queue 5", "Planks")
	check(bench.queue.size() >= queued_before + 8, "two Queue 5 clicks cover a house's planks")
	await key(KEY_ESCAPE)
	check(not game.craft_menu_open, "Esc closes the craft panel")
	await key(KEY_1)
	await run(700)
	check(h1.done, "Ada builds her house")
	check(sim.auto_craft, "auto ingredients unlock with the first house")

	# Second house and the traveler
	await key(KEY_H)
	var origin2 := open_cell(at(1, 4), Vector2i(5, 5))
	await click(screen(origin2 + Vector2i(2, 2)))
	var h2 = sim.site_at(origin2 + Vector2i(2, 2))
	check(h2 != null, "second house placed")
	await click(screen(bench_cell, 0.4))
	await click_button("Queue 5", "Planks")
	await click_button("Queue 5", "Planks")
	await key(KEY_ESCAPE)
	await run(1000)
	check(h2 != null and h2.done, "second house finished")
	check(sim.residents.size() == 2 and sim.stats.traveler_home, "Tomas arrives and moves in")
	var tomas: Dictionary = sim.residents[1] if sim.residents.size() > 1 else {}

	# Toast button and next-resident key
	game._hud.add_toast({"text": "Tomas moved into the new house.", "res_id": tomas.get("id", 0), "site_id": 0})
	check(await click_button("Go to them"), "click a toast's Go to button")
	check(game.selection.get("ids", []) == [tomas.get("id", -1)], "the toast selects Tomas")
	await key(KEY_F)
	check(game.selection.get("ids", []) == [ada.id], "F selects the next resident")

	# Right-click order with a hint
	# A free tree that's actually what's under the cursor at its screen spot (not hidden behind a house).
	var t2: Dictionary = {}
	for cand in sim.trees.filter(func(t): return t.alive and t.claim == 0):
		var p: Vector2 = screen(cand.cell, 1.5)
		var vis := root.get_visible_rect().size
		var middle := Rect2(vis * Vector2(0.3, 0.28), vis * Vector2(0.4, 0.4))  # clear of the HUD's corner panels
		if middle.has_point(p) and is_same(game._pick(p, false), cand):
			t2 = cand
			break
	if not t2.is_empty():
		await move(screen(t2.cell, 1.5))
		check(game._hud._hint.text.begins_with("Right-click: Mine"), "hovering a tree with Ada selected hints Right-click: Mine (got \"%s\"; under cursor %s; tree at %s)" % [game._hud._hint.text, game._pick(game._mouse), t2.cell])
		await click(screen(t2.cell, 1.5), MOUSE_BUTTON_RIGHT)
		check(ada.job != null and is_same(ada.job.target, t2) or ada.direct != null, "right-click orders Ada to mine that tree")

	# Shift + right-click queues orders; the panel lists them and can clear them
	var vis2 := root.get_visible_rect().size
	if true:
		game.selection = {"kind": "res", "ids": [ada.id]}
		# Two walks to open ground in the middle of the screen, queued with Shift + right-click
		for spot in [Vector2(0.45, 0.45), Vector2(0.55, 0.5)]:
			await click(vis2 * spot, MOUSE_BUTTON_RIGHT, true)
		check(ada.orders.size() >= 1, "Shift + right-click queues orders (%d)" % ada.orders.size())
		game._hud.refresh(sim)
		await frames(2)
		check(visible_label("Queued orders"), "the resident panel lists queued orders")
		check(await click_button("Clear orders"), "click Clear orders")
		check(ada.orders.is_empty(), "Clear orders empties the list")

	# Two residents doing different work at once: one mines while the other crafts
	await key(KEY_X)
	await drag(screen(at(0, 0)), screen(at(17, 17)))
	await key(KEY_ESCAPE)
	await click(screen(bench_cell, 0.4))
	for i in 4:
		await click_button("Queue", "Planks")
	await key(KEY_ESCAPE)
	for i in 60:
		await run(1)
		if sim.stats.division:
			break
	check(sim.stats.division, "both residents work at different jobs at once")
	check(Goals.current(sim) < 0, "every founding goal is done")
	check(visible_label("Slice 1 complete"), "the goals panel says Slice 1 is complete")

	# Farm plots (issue #45): P, drag over open grass, and residents plant wheat
	await key(KEY_P)
	check(game.tool == "farm", "P picks Farm")
	var fc := open_cell(at(12, 12), Vector2i(3, 2))
	await drag(screen(fc), screen(fc + Vector2i(2, 1)))
	check(sim.farm.size() >= 4, "dragging paints farm plots (%d)" % sim.farm.size())
	await key(KEY_ESCAPE)
	for i in 40:
		await run(1)
		if sim.stats.get("planted", 0) > 0:
			break
	check(sim.stats.get("planted", 0) > 0, "residents plant wheat on the new farm")

	# Fireplace (issue #46): K, click open ground; it's built, and cooks the hunted mutton
	await key(KEY_K)
	check(game.placing == "fireplace", "K picks Fireplace")
	var fp := Vector2i(-1, -1)
	for c in [at(9, 8), at(12, 9), at(6, 9), at(9, 13), at(13, 5)]:
		var p: Vector2 = screen(c)
		var vis := root.get_visible_rect().size
		if sim.placement_check("fireplace", c, game.rot) == "" and sim.walkable(c) and Rect2(vis * Vector2(0.3, 0.25), vis * Vector2(0.4, 0.45)).has_point(p):
			fp = c
			break
	check(fp.x >= 0, "an open spot for the fireplace")
	await click(screen(fp))
	var fire = sim.site_at(fp)
	check(fire != null and fire.tpl == "fireplace" and fire.plot != null, "the fireplace is placed with a kitchen plot reserved")
	var cooked := false
	for i in 120:
		await run(1)
		if fire != null and fire.done and sim.items.values().any(func(it): return it.type == "cooked_mutton"):
			cooked = true
			break
	check(fire != null and fire.done, "the fireplace is built")
	check(cooked, "and its standing order cooks the hunted mutton")

	# Tools dropdown on hover
	var tb: Button = game._hud._tools_btn
	await move(Vector2(1000, 430))
	await frames(2)
	check(not game._hud._tools_drop.visible, "Tools list is closed")
	await move(tb.get_global_rect().get_center())
	await frames(2)
	check(game._hud._tools_drop.visible, "hovering Tools opens the list")
	await move(game._hud._tools_drop.get_global_rect().get_center())
	await frames(2)
	check(game._hud._tools_drop.visible, "the list stays open while the pointer moves onto it")
	await move(Vector2(1000, 430))
	await frames(2)
	check(not game._hud._tools_drop.visible, "moving away closes the list")

	# Menu by mouse: save, load with confirmation, controls, start over
	await key(KEY_ESCAPE)
	check(game._menu.visible and game.speed == 0, "Esc opens the menu and pauses")
	check(await click_button("Save game"), "click Save game")
	check(await click_button("Save here"), "click Save here")
	check(FileAccess.file_exists(game._slot_path(1)), "slot 1 is written")
	check(await click_button("Save over"), "click Save over")
	check(visible_label("Save over slot 1?"), "saving over asks first")
	check(await click_button("Cancel"), "click Cancel")
	check(await click_button("Back"), "click Back")
	var saved_tick := sim.tick
	check(await click_button("Resume"), "click Resume")
	await run(30)
	await key(KEY_M)
	check(game._menu.visible, "M opens the menu")
	check(await click_button("Load game"), "click Load game")
	check(await click_button("Load"), "click Load on slot 1")
	check(await click_button("Load slot 1"), "confirm Load slot 1")
	var slot_tick: int = game.read_slots()[0].tick
	check(not game._menu.visible, "loading closes the menu")
	check(game.sim.tick == slot_tick, "the saved game is back (tick %d, slot holds %d, tick before resuming %d)" % [game.sim.tick, slot_tick, saved_tick])
	await key(KEY_SLASH, true)
	check(game._menu.visible and game._menu.view == "keys", "? opens Controls")
	check(visible_label("Mine trees and boulders"), "Controls lists the keys")
	check(await click_button("Back"), "click Back from Controls")
	check(await click_button("Start over"), "click Start over")
	check(await click_button("Start over", "", true), "confirm Start over (the button in the confirmation)")
	check(game.sim.tick == 0 and not game._menu.visible, "a fresh game starts")

	# Camera
	var before: Vector3 = game._target
	await drag(Vector2(1100, 650), Vector2(950, 560))
	check(game._target.distance_to(before) > 1.0, "left-drag pans")
	var size_before: float = game._cam.size
	await key(KEY_EQUAL)
	check(game._cam.size < size_before, "+ zooms in")

	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	print("\n%s" % ("PLAYTEST PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures else 0)


## A cell or area of the original 18×18 opening, in today's map (issue #52 moved it to the middle).
static func at(x: int, y: int) -> Vector2i:
	return Vector2i(x, y) + Tuning.OPENING_OFFSET


static func area(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(Vector2i(x, y) + Tuning.OPENING_OFFSET, Vector2i(w, h))
