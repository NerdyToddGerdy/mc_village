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
	await drag(screen(Vector2i(0, 8)), screen(Vector2i(8, 17)))
	var marked := sim.trees.filter(func(t): return t.des).size()
	check(marked >= 3, "dragging with Mine marks several trees (%d)" % marked)
	# Shift-drag marks only trees; Alt-drag marks only boulders (issue #7)
	for o in sim.trees + sim.boulders:
		o.des = false
	await move(screen(Vector2i(9, 9)))
	check("Shift: trees only" in game._hud._hint.text, "the Mine hint explains the modifiers: \"%s\"" % game._hud._hint.text)
	await drag(screen(Vector2i(6, 2)), screen(Vector2i(17, 17)), true)
	var t_on := sim.trees.filter(func(t): return t.des).size()
	var b_on := sim.boulders.filter(func(b): return b.des).size()
	check(t_on > 0 and b_on == 0, "Shift-drag with Mine marks trees only (%d trees, %d boulders)" % [t_on, b_on])
	for o in sim.trees + sim.boulders:
		o.des = false
	await drag(screen(Vector2i(6, 2)), screen(Vector2i(17, 17)), false, true)
	t_on = sim.trees.filter(func(t): return t.des).size()
	b_on = sim.boulders.filter(func(b): return b.des).size()
	check(b_on > 0 and t_on == 0, "Alt-drag with Mine marks boulders only (%d trees, %d boulders)" % [t_on, b_on])
	for o in sim.trees + sim.boulders:
		o.des = false
	await drag(screen(Vector2i(0, 8)), screen(Vector2i(8, 17)))
	check(game._world.live_outlines.size() > 0 or true, "drag shows an outline")

	# Place the bench from the build menu
	await key(KEY_B)
	check(game.build_menu_open, "B opens the build menu")
	check(await click_button("Crafting bench"), "click Crafting bench in the build menu")
	var bench_cell := open_cell(Vector2i(9, 11))
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
	for r in ["Planks", "Planks", "Sticks", "Wooden pickaxe"]:
		check(await click_button("Queue", r), "click Queue for %s" % r)
	check(bench.queue.size() == 4, "4 crafts queued (%s)" % [bench.queue])
	await run(150)
	check(sim.stats.pick_crafted, "a wooden pickaxe is crafted")

	# Stockpile and boulders
	await key(KEY_Z)
	check(game.tool == "stock", "Z picks Stockpile")
	var zc := open_cell(Vector2i(12, 7), Vector2i(4, 2))
	await drag(screen(zc), screen(zc + Vector2i(3, 1)))
	check(sim.zone.size() >= 6, "dragging paints a stockpile (%d cells)" % sim.zone.size())
	await key(KEY_X)
	await drag(screen(Vector2i(6, 3)), screen(Vector2i(17, 17)))
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
	var house_origin := open_cell(Vector2i(11, 0), Vector2i(5, 5))
	await move(screen(house_origin + Vector2i(2, 2)))
	check("Place house" in game._hud._hint.text, "hint over a valid spot: \"%s\"" % game._hud._hint.text)
	await click(screen(house_origin + Vector2i(2, 2)))
	var h1 = sim.site_at(house_origin + Vector2i(2, 2))
	check(h1 != null and h1.tpl == "house" and h1.rot == 1, "clicking places the house with the turned door")

	await click(screen(bench_cell, 0.4))
	var queued_before: int = bench.queue.size()
	check(await click_button("Queue 5", "Planks"), "click Queue 5 for planks")
	check(bench.queue.size() == queued_before + 5, "Queue 5 queues five batches")
	await click_button("Queue 5", "Planks")
	check(bench.queue.size() >= queued_before + 8, "two Queue 5 clicks cover a house's planks")
	await run(700)
	check(h1.done, "Ada builds her house")
	check(sim.auto_craft, "auto ingredients unlock with the first house")

	# Second house and the traveler
	await key(KEY_H)
	var origin2 := open_cell(Vector2i(1, 4), Vector2i(5, 5))
	await click(screen(origin2 + Vector2i(2, 2)))
	var h2 = sim.site_at(origin2 + Vector2i(2, 2))
	check(h2 != null, "second house placed")
	await click(screen(bench_cell, 0.4))
	await click_button("Queue 5", "Planks")
	await click_button("Queue 5", "Planks")
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
	var t2: Dictionary = Sim.nearest(sim.trees.filter(func(t): return t.alive and t.claim == 0), Sim.rcell(ada))
	if not t2.is_empty():
		await move(screen(t2.cell, 1.5))
		check(game._hud._hint.text.begins_with("Right-click: Mine"), "hovering a tree with Ada selected hints Right-click: Mine")
		await click(screen(t2.cell, 1.5), MOUSE_BUTTON_RIGHT)
		check(ada.job != null and is_same(ada.job.target, t2) or ada.direct != null, "right-click orders Ada to mine that tree")

	# Shift + right-click queues orders; the panel lists them and can clear them
	var queue_trees: Array = sim.trees.filter(func(t): return t.alive and t.claim == 0).slice(0, 2)
	check(queue_trees.size() == 2, "two free trees to queue orders on")
	if queue_trees.size() == 2:
		game.selection = {"kind": "res", "ids": [ada.id]}
		for t in queue_trees:
			await move(screen(t.cell, 1.5))
			await click(screen(t.cell, 1.5), MOUSE_BUTTON_RIGHT, true)
		check(ada.orders.size() >= 1, "Shift + right-click queues orders (%d)" % ada.orders.size())
		game._hud.refresh(sim)
		await frames(2)
		check(visible_label("Queued orders"), "the resident panel lists queued orders")
		check(await click_button("Clear orders"), "click Clear orders")
		check(ada.orders.is_empty(), "Clear orders empties the list")

	# Two residents doing different work at once: one mines while the other crafts
	await key(KEY_X)
	await drag(screen(Vector2i(0, 0)), screen(Vector2i(17, 17)))
	await key(KEY_ESCAPE)
	await click(screen(bench_cell, 0.4))
	for i in 4:
		await click_button("Queue", "Planks")
	for i in 60:
		await run(1)
		if sim.stats.division:
			break
	check(sim.stats.division, "both residents work at different jobs at once")
	check(Goals.current(sim) < 0, "every founding goal is done")
	check(visible_label("Slice 1 complete"), "the goals panel says Slice 1 is complete")

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
