extends SceneTree
## Shared helpers for the bot playtests (playtest.gd, playtest_village.gd): input pushed into the
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


## A resident's cell for a job on the Village jobs board (issue #78), opening the board if needed.
func job_cell(r: Dictionary, job: String) -> Button:
	if not game.jobs_board_open:
		await key(KEY_J)
	game._hud.refresh(game.sim)
	await frames(2)
	for n in _all(game._hud._board):
		if n is Button and n.get_meta("cell", "") == "%d:%s" % [r.id, job] and not n.is_queued_for_deletion():
			return n
	return null


## Clicks a jobs board cell: switches an Off job on, or cycles its priority; with Shift, switches it off.
func click_job(r: Dictionary, job: String, shift := false) -> bool:
	var b: Button = await job_cell(r, job)
	if b == null:
		printerr("     (no %s cell for %s on the jobs board)" % [job, r.name])
		return false
	await click(b.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, shift)
	game._hud.refresh(game.sim)
	await frames(2)
	return true


## A cell or area of the original 18×18 opening, in today's map (issue #52 moved it to the middle).
static func at(x: int, y: int) -> Vector2i:
	return Vector2i(x, y) + Tuning.OPENING_OFFSET


static func area(x: int, y: int, w: int, h: int) -> Rect2i:
	return Rect2i(Vector2i(x, y) + Tuning.OPENING_OFFSET, Vector2i(w, h))
