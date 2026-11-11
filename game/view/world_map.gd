class_name WorldMap
extends Control
## The full-screen world map (issue #347): the village at the centre, the land round it in 8 sectors and 3 rings with fog over what's
## unsurveyed, the places found so far as pins, and a side bar for what's picked. It pauses the game while open. Click a pin to plan a
## trip there at the expedition board, or a ring to send the Cartographer to survey it. Drawing and input only: it reads the sim.

const SIDE_W := 300.0
const MAP_PAD := 40.0
const TOP := 74.0  ## clear of the top bar
const RINGS := 3

var game: Game
var _hover := Vector2i(-1, -1)  ## the hovered (sector, ring), or (-1, -1)
var _pick := {}                 ## the picked place or ring: {kind: "place", id} or {kind: "ring", sector, ring}
var _bar: VBoxContainer
var _bar_sig := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	_bar = VBoxContainer.new()
	_bar.add_theme_constant_override("separation", 8)
	add_child(_bar)


func _process(_d: float) -> void:
	visible = game != null and game.world_map_open
	if not visible:
		return
	_layout()
	queue_redraw()
	_refresh_bar()


## The map square, centred in what the side bar leaves, and where its middle and radius are.
func _square() -> Rect2:
	var room := Vector2(size.x - SIDE_W - MAP_PAD * 3.0, size.y - TOP - MAP_PAD)
	var side := minf(room.x, room.y)
	return Rect2(Vector2(MAP_PAD + (room.x - side) / 2.0, TOP + (room.y - side) / 2.0), Vector2(side, side))


func _layout() -> void:
	_bar.position = Vector2(size.x - SIDE_W - MAP_PAD, TOP)
	_bar.size = Vector2(SIDE_W, size.y - TOP - MAP_PAD)


func _centre() -> Vector2:
	return _square().get_center()


func _radius(ring: int) -> float:
	return _square().size.x / 2.0 * (0.2 + 0.8 * float(ring) / float(RINGS))


## The corner points of a ring's cell in a sector: an arc out and back.
func _cell_poly(sector: int, ring: int) -> PackedVector2Array:
	var c := _centre()
	var a0 := deg_to_rad(sector * 45.0 - 22.5 - 90.0)
	var a1 := deg_to_rad(sector * 45.0 + 22.5 - 90.0)
	var r_in := _radius(ring - 1) if ring > 1 else _square().size.x / 2.0 * 0.2
	var r_out := _radius(ring)
	var pts := PackedVector2Array()
	for k in 7:
		var a := lerpf(a0, a1, k / 6.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r_out)
	for k in 7:
		var a := lerpf(a1, a0, k / 6.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r_in)
	return pts


## Which (sector, ring) a point is over, or (-1, -1).
func _cell_at(p: Vector2) -> Vector2i:
	var d := p - _centre()
	var dist := d.length()
	var inner := _square().size.x / 2.0 * 0.2
	if dist < inner or dist > _radius(RINGS):
		return Vector2i(-1, -1)
	var ring := 1
	for r in range(1, RINGS + 1):
		if dist <= _radius(r):
			ring = r
			break
	var ang := rad_to_deg(atan2(d.y, d.x)) + 90.0 + 22.5
	var sector := int(floor(fposmod(ang, 360.0) / 45.0)) % 8
	return Vector2i(sector, ring)


## The pins on the map: the places the village knows, with where each sits ("sector:ring").
func _pins() -> Array:
	var sim: Sim = game.sim
	var out: Array = []
	if sim.get_map(Meadow.ID).known:
		out.append({"id": Meadow.ID, "name": "Meadow", "at": "west:1", "adventure": true})
	if sim.get_map(OldMine.ID).known:
		out.append({"id": OldMine.ID, "name": "Old caves", "at": sim.stats.get("found_at", {}).get("old_mine", "east:1"), "adventure": true})
	if Survey.found(sim, "ruined_portal"):
		out.append({"id": "ruined_portal", "name": "Ruined portal", "at": sim.stats.get("found_at", {}).get("ruined_portal", "north-east:1"), "adventure": false})
	return out


func _pin_pos(at: String) -> Vector2:
	var parts := at.split(":")
	var sector := Survey.SECTORS.find(parts[0])
	var ring := int(parts[1])
	var poly := _cell_poly(maxi(sector, 0), ring)
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(poly.size())


func _draw() -> void:
	var sim: Sim = game.sim
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08, 0.86))
	var sq := _square().grow(18.0)
	draw_rect(sq, Color("#C9B98F"))                      # the paper
	draw_rect(sq, Color("#6B5A3A"), false, 4.0)          # its frame
	for sector in 8:
		for ring in range(1, RINGS + 1):
			var name: String = Survey.SECTORS[sector]
			var col := Color("#3A4350")                  # fog
			if name in Survey.COAST:
				col = Color("#4A7FB0")                   # the sea
			elif Survey.surveyed(sim, name, ring):
				col = Color("#7FA55B").lerp(Color("#D8D0A8"), 0.15 * (sector % 3))  # surveyed ground, in blocky biome tints
			var poly := _cell_poly(sector, ring)
			draw_colored_polygon(poly, col)
			var outline := poly.duplicate()
			outline.append(poly[0])
			var hot: bool = _hover == Vector2i(sector, ring) or (_pick.get("kind", "") == "ring" and _pick.sector == name and _pick.ring == ring)
			draw_polyline(outline, Color("#F2E9C8") if hot else Color(0.1, 0.1, 0.1, 0.55), 3.0 if hot else 1.5)
	var c := _centre()
	draw_rect(Rect2(c - Vector2(14, 14), Vector2(28, 28)), Palette.PLANK)  # the village
	draw_rect(Rect2(c - Vector2(14, 14), Vector2(28, 28)), Color("#2A2724"), false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, c + Vector2(-26, 32), "Village", HORIZONTAL_ALIGNMENT_CENTER, 52, 12, Color("#2A2724"))
	if not sim.stats.get("survey", {}).is_empty():
		var sv: Dictionary = sim.stats.survey
		var tp := _pin_pos("%s:%d" % [sv.sector, sv.ring])
		draw_circle(tp, 9.0, Palette.YELLOW)
	for pin in _pins():
		var p := _pin_pos(pin.at)
		draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), Palette.RED if pin.adventure else Palette.CHALK)
		draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), Color("#2A2724"), false, 2.0)
		draw_string(font, p + Vector2(-40, 26), pin.name, HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color("#2A2724"))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _cell_at(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for pin in _pins():
			if _pin_pos(pin.at).distance_to(event.position) <= 14.0:
				_pick = {"kind": "place", "id": pin.id}
				accept_event()
				return
		var cell := _cell_at(event.position)
		if cell.x >= 0:
			_pick = {"kind": "ring", "sector": Survey.SECTORS[cell.x], "ring": cell.y}
		else:
			_pick = {}
	accept_event()


func _refresh_bar() -> void:
	var sim: Sim = game.sim
	var sig := "%s|%s|%s|%s" % [_pick, sim.stats.get("survey", {}), sim.stats.get("found", {}), sim.tick / 20]
	if sig == _bar_sig:
		return
	_bar_sig = sig
	for n in _bar.get_children():
		n.queue_free()
	var hud: Hud = game._hud
	_bar.add_child(hud._label("World map", true, Palette.CHALK, Palette.HEADING))
	var sv: Dictionary = sim.stats.get("survey", {})
	var who := Survey.cartographer(sim)
	if not sv.is_empty() and not who.is_empty():
		_bar.add_child(hud._label("%s is surveying the %s ring to the %s: back in %d s." % [who.name, Survey.ring_name(sv.ring), sv.sector, int(ceil(maxf(0.0, float(who.back_at - sim.tick) / Tuning.TPS)))], false, Palette.CHALK, Palette.BODY, true))
	match _pick.get("kind", ""):
		"place":
			var id: String = _pick.id
			if id == "ruined_portal":
				_bar.add_child(hud._label("Ruined portal", true))
				_bar.add_child(hud._label("Found. Taking it down for its obsidian is for a later trip.", false, Palette.CHALK_DIM, Palette.BODY, true))
			else:
				_bar.add_child(hud._label(sim.get_map(id).name, true))
				var rep := sim.adventures().filter(func(a): return a.id == id)
				if not rep.is_empty():
					_bar.add_child(hud._label("About %d s each way. %s" % [int(rep[0].travel), rep[0].what], false, Palette.CHALK_DIM, Palette.BODY, true))
				var no_board := sim.expedition_board().is_empty()
				var b: Button = hud._button("Plan a trip", func(): game.plan_from_map(id), "Primary")
				b.disabled = no_board
				b.tooltip_text = "Build the expedition board first" if no_board else "Close the map and pack for it at the board"
				_bar.add_child(b)
		"ring":
			var sector: String = _pick.sector
			var ring: int = _pick.ring
			_bar.add_child(hud._label("%s, %s ring" % [sector.capitalize(), Survey.ring_name(ring)], true))
			var why := Survey.check(sim, sector, ring)
			if Survey.surveyed(sim, sector, ring):
				_bar.add_child(hud._label("Surveyed.", false, Palette.CHALK_DIM))
			elif sector in Survey.COAST:
				_bar.add_child(hud._label("The sea: it needs a boat.", false, Palette.CHALK_DIM, Palette.BODY, true))
			else:
				_bar.add_child(hud._label("%d s there and back, %d%% chance of being driven back." % [int(Survey.seconds(sim, ring)), int(Survey.danger(sim, ring) * 100)], false, Palette.CHALK_DIM, Palette.BODY, true))
				var b: Button = hud._button("Send the Cartographer", func(): game.start_survey(sector, ring), "Primary")
				b.disabled = why != ""
				b.tooltip_text = why
				_bar.add_child(b)
				if why != "":
					_bar.add_child(hud._label(why, false, Palette.YELLOW, Palette.BODY, true))
		_:
			_bar.add_child(hud._label("Pick a place to plan a trip, or a ring to survey. Fog is unsurveyed land.", false, Palette.CHALK_DIM, Palette.BODY, true))
	var close: Button = hud._button("Close  (Esc)", func(): game.close_world_map(), "Secondary")
	_bar.add_child(close)
