extends "res://tests/playtest_base.gd"
## The Steam Deck bot (issue #424): the opening played at the Deck's 1280x800 with controller events only. The cursor is moved the way the right stick
## moves it (a pointer motion), and everything else is a joypad button: A clicks, B is Esc, Y opens Gather, LB Build, Start the menu, the D-pad pans.
## Uses its own save folder. Run from game/:
##   godot --headless --path . -s res://tests/playtest_deck.gd


func pad(button: int, hold := 0) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button as JoyButton
	e.pressed = true
	root.push_input(e, true)
	await frames(1 + hold)
	var u := InputEventJoypadButton.new()
	u.button_index = button as JoyButton
	u.pressed = false
	root.push_input(u, true)
	await frames(2)


## The cursor to a place, then A.
func pad_click(pos: Vector2) -> void:
	game._hud.minimap_on = false
	await move(pos)
	await frames(1)
	await pad(JOY_BUTTON_A)
	await frames(2)


func pad_click_button(text: String) -> bool:
	await frames(2)
	game._hud.refresh(game.sim)
	await frames(2)
	var b := find_button(text)
	if b == null:
		printerr("     (no visible button containing \"%s\")" % text)
		return false
	await pad_click(b.get_global_rect().get_center())
	return true


func _initialize() -> void:
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main.tscn").instantiate()
	game.keys_path = "user://test_settings/playtest_deck_keys.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.keys_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.keys_path.get_base_dir().path_join("ui.cfg")))
	root.add_child(game)
	await frames(3)
	game.save_dir = "user://playtest_saves"
	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	var sim := game.sim
	var ada: Dictionary = sim.residents[0]
	check(game._menu.visible, "the menu shows at launch")
	check(await pad_click_button("Play"), "the cursor goes to Play and A clicks it")
	check(not game._menu.visible and game.speed == 1, "Play starts the game at 1×")

	# Start opens the menu and B (Esc) puts it away.
	await pad(JOY_BUTTON_START)
	check(game._menu.visible, "Start opens the menu")
	await pad(JOY_BUTTON_B)
	check(not game._menu.visible, "B closes it")

	# Y opens Gather, a click on Chop trees picks it.
	await pad(JOY_BUTTON_Y)
	check(await pad_click_button("Chop trees"), "Chop trees is clicked with A")
	game._hud.refresh(sim)
	check(game.tool == "chop", "the Gather menu's Chop trees is on (%s)" % game.tool)

	# Drag-marking with A held: the cursor goes to one corner, A goes down, the cursor to the other, A comes up.
	var tree: Dictionary = Sim.nearest(sim.trees.filter(func(t): return t.alive), Sim.rcell(ada))
	var a := screen(tree.cell - Vector2i(3, 3))
	var b := screen(tree.cell + Vector2i(3, 3))
	await move(a)
	await frames(1)
	var down := InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_A
	down.pressed = true
	root.push_input(down, true)
	await frames(2)
	await move(b)
	var up := InputEventJoypadButton.new()
	up.button_index = JOY_BUTTON_A
	up.pressed = false
	root.push_input(up, true)
	await frames(3)
	var marked := sim.trees.filter(func(t): return t.des).size()
	check(marked >= 1, "dragging with A marks trees (%d)" % marked)

	# LB opens the Build menu; the D-pad pans the camera while it is held.
	await pad(JOY_BUTTON_B)
	await pad(JOY_BUTTON_LEFT_SHOULDER)
	await frames(2)
	game._hud.refresh(sim)
	await frames(2)
	check(game.menu_open == "build", "LB opens the Build menu (%s)" % game.menu_open)
	await pad(JOY_BUTTON_B)
	var before: Vector3 = game._target
	await pad(JOY_BUTTON_DPAD_RIGHT, 20)
	check(game._target.distance_to(before) > 0.1, "the D-pad pans the camera")

	# The sim runs on, and Ada gets chopping.
	await play(90.0)
	check(sim.stats.felled > 0 or sim.items.size() > 0, "the game plays on while the controller has the pointer")
	print("deck bot done")
	quit(1 if _failures > 0 else 0)
