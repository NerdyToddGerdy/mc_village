class_name NetherRoute
extends RefCounted
## The Nether's routes (Slice 5, issue #153): three long, narrow strip maps leaving the portal landing's edges, each ending at
## a site. They share Slice 4's road geometry (`Road`: six segments, eight columns each, the line along row 3), so the same
## fog hides what nobody has walked. A scouting party walks one out to its end: that reveals it, and the site at the end.
## The terrain is lava, gaps and netherrack; the obstacles that need a bridge or a cut are listed in each segment, to be dealt
## with when the line is built (#159). Scouts pass beside the lava, with the burns that go with it (#149).

const W := 48
const H := 7
const LINE_ROW := 3

## Each route: its map id, its name, the site at its end (a stub map for #155-#157), where it leaves the landing, its
## segments' terrain (west to east) and what lives on it.
const ROUTES := {
	"quartz": {"id": "nether_route_quartz", "name": "Nether: route to the quartz site", "site": "nether_quartz", "site_name": "Nether: quartz site",
		"exit": Vector2i(23, 12), "told": "A way east through the lava fields, to where quartz is said to lie.",
		"segments": [
			{"name": "The landing's edge", "terrain": "netherrack", "obstacle": "", "hazards": []},
			{"name": "Netherrack flats", "terrain": "netherrack", "obstacle": "", "hazards": []},
			{"name": "The lava channel", "terrain": "a lava channel", "obstacle": "lava", "hazards": ["Lava on both sides of a narrow way: someone can be burned"]},
			{"name": "Scorched flats", "terrain": "netherrack, with fire", "obstacle": "", "hazards": ["Patches of fire"]},
			{"name": "The broken ledge", "terrain": "a drop", "obstacle": "gap", "hazards": ["A ledge: someone could fall"]},
			{"name": "Below the quartz", "terrain": "netherrack", "obstacle": "", "hazards": []}],
		"creatures": [["zombified_piglin", Vector2i(27, 3)], ["magma_cube", Vector2i(43, 2)]]},
	"piglin": {"id": "nether_route_piglin", "name": "Nether: route to the piglin camp", "site": "nether_piglin", "site_name": "Nether: piglin camp",
		"exit": Vector2i(12, 0), "told": "A trail north, where piglins are said to keep a camp.",
		"segments": [
			{"name": "The landing's edge", "terrain": "netherrack", "obstacle": "", "hazards": []},
			{"name": "The lava pool", "terrain": "a lava pool", "obstacle": "lava", "hazards": ["Lava beside the way: someone can be burned"]},
			{"name": "Open flats", "terrain": "netherrack", "obstacle": "", "hazards": []},
			{"name": "The ruined bridge", "terrain": "a drop", "obstacle": "gap", "hazards": ["A ledge: someone could fall"]},
			{"name": "Netherrack hills", "terrain": "netherrack", "obstacle": "", "hazards": []},
			{"name": "The camp's approach", "terrain": "netherrack", "obstacle": "", "hazards": []}],
		"creatures": [["magma_cube", Vector2i(30, 3)], ["zombified_piglin", Vector2i(38, 4)]]},
	"fortress": {"id": "nether_route_fortress", "name": "Nether: route to the fortress", "site": "nether_fortress", "site_name": "Nether: fortress entrance",
		"exit": Vector2i(12, 23), "told": "A road south toward a great dark wall.",
		"segments": [
			{"name": "The landing's edge", "terrain": "netherrack", "obstacle": "", "hazards": []},
			{"name": "Open flats", "terrain": "netherrack", "obstacle": "", "hazards": []},
			{"name": "The basalt cliffs", "terrain": "a rocky cut", "obstacle": "cut", "hazards": []},
			{"name": "Ash flats", "terrain": "netherrack", "obstacle": "", "hazards": []},
			{"name": "The lava lake", "terrain": "a lava lake", "obstacle": "lava", "hazards": ["Lava on both sides: someone can be burned", "Patches of fire"]},
			{"name": "The fortress wall", "terrain": "netherrack", "obstacle": "", "hazards": ["A ledge: someone could fall"]}],
		"creatures": [["magma_cube", Vector2i(26, 3)], ["magma_cube", Vector2i(36, 2)]]},
}


## The route key ("quartz"...) a map id belongs to, or "".
static func route_of(id: String) -> String:
	for k in ROUTES:
		if ROUTES[k].id == id:
			return k
	return ""


## The route key whose site a map id is, or "".
static func site_key(id: String) -> String:
	for k in ROUTES:
		if ROUTES[k].site == id:
			return k
	return ""


## Every route and site map id, in the order a game makes them: each route, then its site.
static func map_ids() -> Array:
	var out: Array = []
	for k in ROUTES:
		out.append(ROUTES[k].id)
		out.append(ROUTES[k].site)
	return out


static func route_ids() -> Array:
	return ROUTES.keys().map(func(k): return ROUTES[k].id)


static func site_ids() -> Array:
	return ROUTES.keys().map(func(k): return ROUTES[k].site)


## The route strip as it is before anyone has walked it. Its west end meets the landing, its east end the site.
static func build(s: Sim, key: String) -> SimMap:
	var def: Dictionary = ROUTES[key]
	var m := SimMap.new(W, H)
	m.id = def.id
	m.kind = "route"
	m.name = def.name
	m.known = false
	m.entrance = Vector2i(0, LINE_ROW)
	m.seen = 1
	match key:
		"quartz":
			_lava(m, 18, 21, [0, 1, 2, 4, 5, 6])
			_fire(m, [Vector2i(27, 1), Vector2i(29, 5)])
			_ledge(m, [Vector2i(34, 3), Vector2i(35, 3)])
		"piglin":
			_lava(m, 12, 15, [1, 2, 5])
			_ledge(m, [Vector2i(27, 3), Vector2i(28, 3)])
			_lava(m, 26, 29, [5, 6])
		_:
			_rock(m, 18, 21, [0, 1, 2, 4, 5, 6])
			_lava(m, 34, 38, [1, 2, 4, 5])
			_fire(m, [Vector2i(37, 3)])
			_ledge(m, [Vector2i(44, 3)])
	for cr in def.creatures:
		var c: Dictionary = {"id": s._id(), "kind": "creature", "species": cr[0], "cell": cr[1], "pos": Vector2(cr[1]), "alive": true,
			"hp": Defs.CREATURES[cr[0]].hp, "angry": false, "engaged": false, "cool": 0.0, "flash": 0, "acc": 0.0}
		m.creatures.append(c)
	return m


static func _lava(m: SimMap, x0: int, x1: int, rows: Array) -> void:
	for x in range(x0, x1 + 1):
		for y in rows:
			m.rock[Vector2i(x, y)] = true
			m.lava[Vector2i(x, y)] = true


static func _rock(m: SimMap, x0: int, x1: int, rows: Array) -> void:
	for x in range(x0, x1 + 1):
		for y in rows:
			m.rock[Vector2i(x, y)] = true


static func _fire(m: SimMap, cells: Array) -> void:
	for c in cells:
		m.fire[c] = true


static func _ledge(m: SimMap, cells: Array) -> void:
	for c in cells:
		m.ledges.append(c)


## The site at a route's end, as a small map for #155 to fill (the quartz site), #156 (the piglin camp) and #157 (the fortress).
static func build_site(s: Sim, key: String) -> SimMap:
	var def: Dictionary = ROUTES[key]
	var m := SimMap.new(16, 16)
	m.id = def.site
	m.kind = "site"
	m.name = def.site_name
	m.known = false
	m.found = true
	m.discovered = true
	m.entrance = Vector2i(0, 8)
	for x in 16:
		m.rock[Vector2i(x, 0)] = true
		m.rock[Vector2i(x, 15)] = true
	for y in 16:
		if y != 8:
			m.rock[Vector2i(0, y)] = true
		m.rock[Vector2i(15, y)] = true
	return m
