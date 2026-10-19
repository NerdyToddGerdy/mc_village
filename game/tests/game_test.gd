extends SceneTree
## Runs the real game scene headlessly to check the menu, saving and loading. Uses its own save
## folder, so real saves are never touched. Run from game/:
##   godot --headless --path . -s res://tests/game_test.gd

var _failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL ", what)
	else:
		print("ok   ", what)


func _mouse(game: Game, kind: String, pos: Vector2, shift := false) -> void:
	var e: InputEvent
	if kind == "move":
		e = InputEventMouseMotion.new()
		e.relative = pos - game._mouse
	else:
		e = InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = kind == "down"
		e.shift_pressed = shift
	e.position = pos
	game._unhandled_input(e)


func _test_drag(game: Game) -> void:
	game.close_menu() if game._menu.visible else null
	game.set_tool("")
	var start := Vector2(1100, 650)  # empty ground near the map's front corner
	game.selection = {}
	var before: Vector3 = game._target
	_mouse(game, "move", start)
	_mouse(game, "down", start)
	_mouse(game, "move", start + Vector2(-60, -40))
	_mouse(game, "move", start + Vector2(-160, -90))
	_mouse(game, "up", start + Vector2(-160, -90))
	check(game._target.distance_to(before) > 1.0, "left-drag on the map pans the camera")
	check(game.selection.is_empty(), "panning doesn't select anything")
	var ada: Dictionary = game.sim.residents[0]
	var ada_screen: Vector2 = game._cam.unproject_position(Vector3(ada.pos.x + 0.5, 0.5, ada.pos.y + 0.5))
	var moved: Vector3 = game._target
	_mouse(game, "move", ada_screen)
	_mouse(game, "down", ada_screen)
	_mouse(game, "up", ada_screen)
	check(game.selection.get("ids", []) == [ada.id], "a click without dragging selects")
	check(game._target == moved, "a click doesn't pan")
	game.selection = {}
	var a := ada_screen - Vector2(40, 40)
	_mouse(game, "move", a)
	_mouse(game, "down", a, true)
	_mouse(game, "move", ada_screen + Vector2(40, 40))
	_mouse(game, "up", ada_screen + Vector2(40, 40), true)
	check(game.selection.get("ids", []) == [ada.id], "shift-drag box-selects residents")
	check(game._target == moved, "shift-drag doesn't pan")
	game.set_tool("mine")
	var t: Dictionary = game.sim.trees.filter(func(x): return x.alive)[0]
	t.des = false
	var ts: Vector2 = game._cam.unproject_position(Vector3(t.cell.x + 0.5, 0.0, t.cell.y + 0.5))
	_mouse(game, "move", ts)
	_mouse(game, "down", ts)
	_mouse(game, "move", ts + Vector2(30, 20))
	_mouse(game, "up", ts + Vector2(30, 20))
	check(t.des and game._target == moved, "with Mine active, dragging marks instead of panning")
	game.set_tool("")


func _initialize() -> void:
	var game: Game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.save_dir = "user://test_saves"
	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	var menu: GameMenu = game._menu
	check(menu.visible and menu.first and game.speed == 0, "menu opens at launch, paused, with Play")
	game.close_menu()
	check(not menu.visible and game.speed == 1, "Play closes the menu and runs at 1×")
	game.sim.designate_mine(Rect2i(0, 0, 10, 18))
	game.sim.place_site("bench", Vector2i(8, 10))
	for i in 60 * Tuning.TPS:
		game.sim.step()
	game.set_speed(3)
	game.open_menu("main")
	check(game.speed == 0, "opening the menu pauses")
	check(game.read_slots().all(func(s): return s == null), "all 5 slots start empty")
	check(game.save_slot(2) == "", "saving to slot 2 works")
	var saved_tick := game.sim.tick
	var slots := game.read_slots()
	check(slots[1] != null and slots[1].tick == saved_tick and slots[1].summary.begins_with("Next:"), "slot 2 shows a summary and time")
	game.close_menu()
	check(game.speed == 3, "closing the menu restores the previous speed")
	for i in 30 * Tuning.TPS:
		game.sim.step()
	var felled_later: int = game.sim.stats.felled
	game.open_menu("load")
	check(game.load_slot(2) == "", "loading slot 2 works")
	check(game.sim.tick == saved_tick, "the loaded game is back at the saved moment")
	check(game.sim.stats.felled <= felled_later, "progress after the save is gone")
	check(not menu.visible and game.speed == 3, "loading returns to the game at the saved speed")
	for i in 30 * Tuning.TPS:
		game.sim.step()
	check(game.sim.tick > saved_tick, "the loaded game keeps running")
	check(game.load_slot(4) != "", "an empty slot can't be loaded")
	_test_drag(game)
	game.open_menu("main")
	game.restart()
	check(game.sim.tick == 0 and game.sim.residents.size() == 1 and not menu.visible, "Start over begins a fresh game")
	for n in range(1, 6):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(game._slot_path(n)))
	print("%s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures else 0)
