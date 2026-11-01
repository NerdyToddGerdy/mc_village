extends SceneTree
## Shared helpers for the bot playtests (playtest.gd, playtest_village.gd, playtest_slice3.gd): input pushed into the
## game window the way a player's clicks and keys arrive, plus waiting by stepping the sim.

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


## Clicks until `done` holds, up to `tries` times. A pushed click is now and then lost on a busy machine
## (issue #313: no handler sees it, and nothing is under the pointer), so a lost one is said so, not failed
## silently. A game that never does it still fails the check that follows.
func click_until(pos: Vector2, done: Callable, tries := 3) -> void:
	for i in tries:
		await click(pos)
		if done.call():
			return
		printerr("     (click %d of %d at %s had no effect; trying again)" % [i + 1, tries, pos])


## The same for a drag.
func drag_until(a: Vector2, b: Vector2, done: Callable, tries := 3, shift := false, alt := false) -> void:
	for i in tries:
		await drag(a, b, shift, alt)
		if done.call():
			return
		printerr("     (drag %d of %d had no effect; trying again)" % [i + 1, tries])


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


## The middle of the open radial Gather menu's wedge `i` on screen (issue #176).
func radial_wedge(i: int) -> Vector2:
	var r: Dictionary = game.radial
	var span: float = TAU / r.wedges.size()
	return r.center + Vector2.from_angle(-PI / 2 + i * span) * (Game.RADIAL_IN + Game.RADIAL_OUT) / 2


func radial_ids() -> Array:
	return game.radial.get("wedges", []).map(func(w): return w.id)


func screen(cell: Vector2i, h := 0.0) -> Vector2:
	return game._cam.unproject_position(Vector3(cell.x + 0.5, h, cell.y + 0.5))


## The visible button whose text contains `text`. With `near`, the one in the same row as a label
## containing `near` (for the bench's per-recipe Queue buttons).
## Goes to a place by the map switcher's dropdown: opens the list, then picks the place from it (an exact
## match in the list itself, since other panels, like the board's Location button, carry place names too).
func go_to(place: String) -> bool:
	if not await click_button("another place"):
		return false
	game._hud.refresh(game.sim)
	await frames(2)
	for n in game._hud._maps_list.get_children():
		if n is Button and n.is_visible_in_tree() and n.get_meta("label", "") == place and not n.is_queued_for_deletion():
			await click(n.get_global_rect().get_center())
			return true
	printerr("     (no place \"%s\" in the list)" % place)
	return false


func find_button(text: String, near := "", last := false) -> Button:
	var found: Button = null
	for n in _all(root):
		if n is Button and n.is_visible_in_tree() and not n.disabled and text in str(n.get_meta("label", n.text)):
			if near == "" or _row_has(n, near):
				if not last:
					return n
				found = n
	return found


func _row_has(b: Button, text: String) -> bool:
	if b.get_parent().get_meta("recipe", "") == text:  # a Craft panel recipe row (issue #76)
		return true
	for sib in b.get_parent().get_children():
		if sib is Label and sib.text.begins_with(text + "\n"):
			return true
	return false


func _all(n: Node) -> Array:
	var out: Array = [n]
	for ch in n.get_children():
		out.append_array(_all(ch))
	return out


## Sets the plan's cargo list through the board's buttons (issue #185): `label` (an item's label, such as "Coal") on, at
## the top of the list, with `n` wanted (0 leaves the amount alone). With `only`, the other rows that want an amount are
## turned off.
func plan_wants(label: String, n := 0, only := false) -> bool:
	var item := ""
	for k in Defs.ITEMS:
		if Defs.ITEMS[k].get("label", "") == label:
			item = k
	var at := func() -> int:
		for i in game.plan.list.size():
			if game.plan.list[i].item == item:
				return i
		return -1
	if at.call() < 0:
		return false
	if not game.plan.list[at.call()].on and not await click_button("Bring back: " + label):
		return false
	for i in 10:
		if at.call() == 0:
			break
		if not await click_button(label + " up"):
			return false
	if n > 0:
		for i in 40:
			var have: int = game.plan.list[0].n
			if have == n:
				break
			if not await click_button(label + (" more" if have < n else " less")):
				return false
	for i in range(1, game.plan.list.size() if only else 1):  # with `only`, the other rows that want an amount are off: this is the one thing the trip is for
		var other: Dictionary = game.plan.list[i]
		if other.on and other.n > 0 and not await click_button("Bring back: " + Defs.ITEMS[other.item].label):
			return false
	return game.plan.list[0].item == item and game.plan.list[0].on


## Picks a destination from the expedition board's Location dropdown (issue #181).
func pick_location(name: String) -> bool:
	if not await click_button("Location"):
		return false
	return await click_button("Adventure: " + name)


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


## Queues `n` of a recipe in the Craft panel: picks it in the recipe book (issue #95), sets the count
## with − and +, then clicks Queue.
func queue_recipe(recipe: String, n := 1) -> bool:
	if not await click_button(recipe):
		return false
	for i in 40:
		await frames(1)
		game._hud.refresh(game.sim)
		await frames(1)
		var q := find_button("Queue ")
		if q == null:
			printerr("     (no Queue button for %s)" % recipe)
			return false
		var cur := int(q.text.get_slice(" ", 1))
		if cur == n:
			return await click_button("Queue ")
		await click_button("+" if cur < n else "−")
	return false


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
	game.handle_view_events(game.sim.events)
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


## A resident's level cell for a job on the Village jobs board (issue #78), opening the board if needed.
func job_cell(r: Dictionary, job: String) -> Control:
	if not game.jobs_board_open:
		await key(KEY_J)
	game._hud.refresh(game.sim)
	await frames(2)
	for n in _all(game._hud._board):
		if n is Control and n.get_meta("cell", "") == "%d:%s" % [r.id, job] and not n.is_queued_for_deletion():
			return n
	return null


## A resident's job button (issue #134): on the Village jobs board, opened if needed, or with
## `on_board` false on their own panel.
func job_button(r: Dictionary, on_board := true) -> Button:
	if on_board and not game.jobs_board_open:
		await key(KEY_J)
	game._hud.refresh(game.sim)
	await frames(2)
	for n in _all(game._hud._board if on_board else game._hud._sel):
		if n is Button and n.is_visible_in_tree() and n.get_meta("label", "") == "Job: %s" % r.name and not n.is_queued_for_deletion():
			return n
	return null


## Opens a resident's job dropdown and chooses a job from it (issue #134): one of Defs.JOBS, or "none".
func choose_job(r: Dictionary, role: String, on_board := true) -> bool:
	var b: Button = await job_button(r, on_board)
	if b == null:
		printerr("     (no job button for %s)" % r.name)
		return false
	await click(b.get_global_rect().get_center())
	game._hud.refresh(game.sim)
	await frames(2)
	if not await click_button("Job choice: " + ("No job" if role == "none" else Defs.JOB_NAMES[role] + " · ")):
		return false
	game._hud.refresh(game.sim)
	await frames(2)
	return r.role == role


## A cell or area of the original 18×18 opening, in today's map (issue #52 moved it to the middle).
static func at(x: int, y: int) -> Vector2i:
	return Vector2i(x, y) + Tuning.OPENING_OFFSET


static func area(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(Vector2i(x, y) + Tuning.OPENING_OFFSET, Vector2i(w, h))


# ---------------------------------------------------------------- playing by steps (shared by the village and Slice 3 bots)

var _seen: Array = []       ## Every toast text so far, and every job label residents have shown.


## Steps the sim like run(), remembering toasts and what residents were doing.
func play(seconds: float) -> void:
	for i in int(seconds * Tuning.TPS):
		game.sim.step()
		for r in game.sim.residents:
			if r.job != null and not _seen.has(r.job.label):
				_seen.append(r.job.label)
		for ev in game.sim.events:
			if ev.type == "toast":
				_seen.append(ev.text)
				game._hud.add_toast(ev)
		game.handle_view_events(game.sim.events)
		game.sim.events.clear()
		if not game.sim.pending.is_empty():
			break  # the game stops for a choice, as it does in play
	game._hud.refresh(game.sim)
	await frames(3)


## Plays a second at a time until `cond` holds, for at most `seconds`. Returns whether it did.
func play_until(seconds: float, cond: Callable) -> bool:
	for i in int(seconds):
		if cond.call():
			return true
		await play(1)
	return cond.call()


func seen(text: String) -> bool:
	return _seen.any(func(t): return text in t)


## Points the camera at a cell, so it can be clicked.
func look_at(c: Vector2i) -> void:
	game._target = Vector3(c.x + 0.5, 0, c.y + 0.5)
	game._place_camera()
	await frames(2)


## Whether a cell's screen position is clear of the HUD's corner panels.
func in_middle(p: Vector2) -> bool:
	var vis := root.get_visible_rect().size
	return Rect2(vis * Vector2(0.28, 0.25), vis * Vector2(0.44, 0.45)).has_point(p)


## An open spot near `near` where a building of this template can go, or (-1, -1).
func build_spot(tpl: String, near: Vector2i) -> Vector2i:
	var sim := game.sim
	var size: Vector2i = Defs.TEMPLATES[tpl].size
	for d in range(0, 12):
		for dx in range(-d, d + 1):
			for dy in range(-d, d + 1):
				var o := near + Vector2i(dx, dy)
				if sim.placement_check(tpl, o, game.rot) != "":
					continue
				var ok := true
				for x in size.x:
					for y in size.y:
						var c := o + Vector2i(x, y)
						ok = ok and sim.walkable(c) and not sim.items.has(c) and not sim.farm.has(c)
				if ok:
					return o
	return Vector2i(-1, -1)


## Places a building from the Build menu the way a player would: B, its row, then a click on an
## open spot near `near`. Returns the blueprint, or null.
func place_from_menu(row: String, tpl: String, near: Vector2i):
	if game.menu_open != "build":
		await key(KEY_B)
	if game.menu_open != "build" or not await click_button(row):
		printerr("     (Build menu: open %s)" % game.menu_open)
		return null
	var spot := build_spot(tpl, near)
	if spot.x < 0:
		return null
	await look_at(spot)
	for attempt in 3:  # the camera may not have settled under the cursor yet
		await frames(3)
		await move(screen(spot + Vector2i(Defs.TEMPLATES[tpl].size.x / 2, Defs.TEMPLATES[tpl].size.y / 2)))  # a building is centered on the cursor
		await click(screen(spot + Vector2i(Defs.TEMPLATES[tpl].size.x / 2, Defs.TEMPLATES[tpl].size.y / 2)))
		if game.sim.site_at(spot) != null:
			break
		if game.tool == "":
			await key(KEY_B)
			await click_button(row)
	if game.tool != "":
		await key(KEY_ESCAPE)
	return game.sim.site_at(spot)


## Selects a resident the way a player would: F until it's them.
func select_resident(r: Dictionary) -> void:
	for i in game.sim.residents.size() + 1:
		if game.selection.get("ids", []) == [r.id]:
			break
		await key(KEY_F)
	game._hud.refresh(game.sim)
	await frames(2)


## A w×h rect near `near` where `ok` holds for every cell and both corners are on screen, or a
## rect at (-1, -1).
func open_rect_on_screen(near: Vector2i, w: int, h: int, ok: Callable) -> Rect2i:
	for d in range(0, 10):
		for dx in range(-d, d + 1):
			for dy in range(-d, d + 1):
				var r := Rect2i(near + Vector2i(dx, dy), Vector2i(w, h))
				if not (in_middle(screen(r.position)) and in_middle(screen(r.end - Vector2i.ONE))):
					continue
				var good := true
				for x in range(r.position.x, r.end.x):
					for y in range(r.position.y, r.end.y):
						good = good and ok.call(Vector2i(x, y))
				if good:
					return r
	return Rect2i(-1, -1, 0, 0)


## Opens the toolbar's Craft panel on the crafting bench, stepping past the fireplace with Next.
func open_bench_panel() -> bool:
	game.selection = {}
	if not game.craft_menu_open and not await click_button("Craft"):
		return false
	for i in 4:
		game._hud.refresh(game.sim)
		await frames(2)
		var bench = game.craft_bench()
		if bench != null and bench.tpl == "bench":
			return true
		await click_button("Bench")
	return false


func count(type: String) -> int:
	var n := 0
	for k in game.sim.items:
		if game.sim.items[k].type == type:
			n += game.sim.items[k].n
	return n


## Lets the HUD rebuild after a click, so the next check sees the panel it opened.
func settle() -> void:
	await frames(2)
	game._hud.refresh(game.sim)
	await frames(2)
