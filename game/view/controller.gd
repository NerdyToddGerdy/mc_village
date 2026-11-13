class_name Controller
extends RefCounted
## The game on a controller (issue #421, the Steam Deck). Joypad buttons become the keys and clicks the game already handles, so every order
## the keyboard and mouse reach is reachable here too: A is the left click, X the right click, B Esc, and the rest are KeyBindings' pad
## buttons (rebindable). The left stick pans, the right stick moves the cursor, and the triggers zoom.

const DEAD := 0.25            ## Stick travel that counts.
const CURSOR_SPEED := 900.0   ## Cursor pixels a second at full tilt.
const PAN_SPEED := 1.2        ## Screens a second at full tilt.
const TRIGGER := 0.5

var game: Node
var _cursor := Vector2.ZERO   ## Where the pointer is: the mouse's last position, moved by the right stick.
var _zoom_held := 0   ## -1 or 1 while a trigger is down, so a held trigger zooms once


func _init(p_game: Node) -> void:
	game = p_game


## A joypad button event: true when it was one (and now acts as a key or click).
func handle(e: InputEvent) -> bool:
	if e is InputEventMouseMotion:  # the pointer is where the mouse last was, or the stick took it
		_cursor = e.position
		return false
	if not (e is InputEventJoypadButton):
		return false
	var b: int = e.button_index
	if game._menu.visible and game._menu.listening != "" and game._menu.listening_pad:
		if e.pressed:
			game._menu.pad_pressed(b)
		return true
	match b:
		JOY_BUTTON_A:
			click(MOUSE_BUTTON_LEFT, e.pressed)
			return true
		JOY_BUTTON_X:
			click(MOUSE_BUTTON_RIGHT, e.pressed)
			return true
		JOY_BUTTON_B:
			key(KEY_ESCAPE, e.pressed, false)
			return true
	var action: String = game.keys.pad_action_for(b)
	if action == "":
		return false
	var codes: Array = game.keys.keys[action]
	if codes.is_empty():
		return true
	key(codes[0] & ~KEY_MASK_SHIFT, e.pressed, codes[0] & KEY_MASK_SHIFT != 0)
	return true


## A click at the cursor.
func click(button: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = _cursor
	ev.global_position = ev.position
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = (1 << (button - 1)) if pressed else 0
	Input.parse_input_event(ev)


func key(code: int, pressed: bool, shift: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code as Key
	ev.physical_keycode = code as Key
	ev.shift_pressed = shift
	ev.pressed = pressed
	Input.parse_input_event(ev)


## Each frame: the right stick moves the cursor, the left stick pans, a trigger zooms.
func update(delta: float) -> void:
	if game._menu.visible:
		return
	var r := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if r.length() > DEAD:
		var vp: Viewport = game.get_viewport()
		var at: Vector2 = (_cursor + r * CURSOR_SPEED * delta).clamp(Vector2.ZERO, vp.get_visible_rect().size)
		_cursor = at
		vp.warp_mouse(at)
		var ev := InputEventMouseMotion.new()
		ev.position = at
		ev.global_position = at
		ev.relative = r * CURSOR_SPEED * delta
		Input.parse_input_event(ev)
	var l := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if l.length() > DEAD:
		game._pan_screen(l * PAN_SPEED * delta * game.get_viewport().get_visible_rect().size.y)
	var want := 0
	if Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER:
		want = 1
	elif Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > TRIGGER:
		want = -1
	if want != _zoom_held:
		_zoom_held = want
		if want == 1:
			game.zoom(1 / 1.15)
		elif want == -1:
			game.zoom(1.15)
