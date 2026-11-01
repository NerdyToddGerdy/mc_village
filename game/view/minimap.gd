class_name MiniMap
extends Control
## A corner map of the map in view (issue #298): the ground, trees, buildings, residents, what's stuck, and the
## rectangle the camera sees. Clicking or dragging on it moves the camera there. Drawing only: it reads the sim.

const SIZE := 190.0

var game: Game
var _drag := false
var _since := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _process(delta: float) -> void:
	_since += delta
	if visible and _since >= 0.2:  # residents move, and so does the camera: five redraws a second is plenty
		_since = 0.0
		queue_redraw()


## Screen pixels in the minimap to map cells, and back.
func _scale(mp: SimMap) -> float:
	return SIZE / float(maxi(mp.w, mp.h))


func _to_map(p: Vector2, mp: SimMap) -> Vector2:
	return p / _scale(mp)


func _to_mini(c: Vector2, mp: SimMap) -> Vector2:
	return c * _scale(mp)


## Where the camera's ray through a screen point meets the ground, in cells.
func _ground(screen: Vector2) -> Vector2:
	var r: Array = game._ray(screen)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	if absf(d.y) < 1e-5:
		return Vector2.ZERO
	var t := -o.y / d.y
	return Vector2(o.x + d.x * t, o.z + d.z * t)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		if event.pressed:
			_go(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		_go(event.position)
		accept_event()


func _go(p: Vector2) -> void:
	var mp: SimMap = game.sim.get_map(game.view_map)
	var c := _to_map(p, mp)
	game._target = Vector3(clampf(c.x, 0.0, mp.w), 0.0, clampf(c.y, 0.0, mp.h))
	game._place_camera()
	queue_redraw()


func _draw() -> void:
	var sim: Sim = game.sim
	var mp: SimMap = sim.get_map(game.view_map)
	var k := _scale(mp)
	draw_rect(Rect2(Vector2.ZERO, Vector2(mp.w, mp.h) * k), Color(Palette.GRASS, 1.0).darkened(0.25))
	for c in mp.water:
		draw_rect(Rect2(Vector2(c) * k, Vector2(k, k)), Palette.BLUE.darkened(0.2))
	for c in mp.rock:
		draw_rect(Rect2(Vector2(c) * k, Vector2(k, k)), Palette.STONE.darkened(0.35))
	for c in mp.zone:
		draw_rect(Rect2(Vector2(c) * k, Vector2(k, k)), Color(Palette.GREEN, 0.45))
	for c in mp.farm:
		draw_rect(Rect2(Vector2(c) * k, Vector2(k, k)), Color(Palette.WHEAT, 0.6))
	for t in mp.trees:
		if t.alive:
			draw_rect(Rect2(Vector2(t.cell) * k, Vector2(maxf(k, 1.5), maxf(k, 1.5))), Palette.LEAVES.darkened(0.2))
	for b in mp.boulders:
		if b.alive:
			draw_rect(Rect2(Vector2(b.cell) * k, Vector2(maxf(k, 1.5), maxf(k, 1.5))), Palette.STONE)
	for s in mp.sites:
		var r := Rect2(Vector2(s.origin) * k, Vector2(s.size) * k)
		if s.done:
			draw_rect(r, Palette.PLANK)
		else:
			draw_rect(r, Color(Palette.BLUE, 0.35))
			draw_rect(r, Palette.BLUE, false, 1.0)
	for s in sim.stuck:
		if s.map == game.view_map and not s.hidden and not s.waiting:
			var at: Vector2 = Vector2(s.cell) * k
			draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), Palette.YELLOW)
	for r in sim.residents:
		if r.map == game.view_map and not r.away:
			var at: Vector2 = (r.pos + Vector2(0.5, 0.5)) * k
			draw_circle(at, 2.6, Palette.SLATE_DEEP)
			draw_circle(at, 1.8, r.shirt)
	# What the camera sees: the screen's corners on the ground.
	var vp := get_viewport().get_visible_rect().size
	var poly := PackedVector2Array()
	for corner in [Vector2.ZERO, Vector2(vp.x, 0), vp, Vector2(0, vp.y)]:
		poly.append(_to_mini(_ground(corner), mp).clamp(Vector2.ZERO, Vector2(SIZE, SIZE)))
	poly.append(poly[0])
	draw_polyline(poly, Palette.CHALK, 1.5)
	draw_rect(Rect2(Vector2.ZERO, Vector2(mp.w, mp.h) * k), Palette.CHALK_DIM, false, 1.0)
