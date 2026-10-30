class_name MineLevels
extends RefCounted
## The old mine's deeper levels (issue #132). Level 1 is the hand-laid old workings (OldMine). Every
## level has a door at its far end, opposite the entrance the party arrives through, and the door
## leads down to the next level. On deeper levels, the entrance is the way back up.
##
## Deeper levels are generated from the game's seed and the level number, so a level always comes
## out the same. Each is drawn from a pattern family: the first five deeper levels use each family
## once, in an order the seed picks, and after that families come back with other settings (size,
## mirroring and where the ore lies), never the same family twice in a row. Every pattern keeps a
## minable way from the entrance to the door, and some ore. Deeper is richer and riskier: more coal and
## iron, fewer torches, and more loose ceilings and ledges.

const FAMILIES := ["winding", "pillared", "branching", "stream", "collapsed"]
const FAMILY_NAMES := {"workings": "Old workings", "winding": "Winding cave", "pillared": "Pillared hall",
	"branching": "Branching tunnels", "stream": "Underground stream", "collapsed": "Collapsed chamber"}
## The site report's access notes for each pattern.
const ACCESS := {
	"workings": ["Narrow tunnels: 1 resident per tunnel"],
	"winding": ["One winding passage, with pockets off it"],
	"pillared": ["A wide hall: room for the whole party"],
	"branching": ["A maze of narrow tunnels, with ore in the dead ends"],
	"stream": ["A stream splits the cavern: the way goes around it"],
	"collapsed": ["A field of rubble to dig through"],
}


## A level's map id: "old_mine" for Level 1, "old_mine_2" and so on below it.
static func level_id(n: int) -> String:
	return OldMine.ID if n <= 1 else "%s_%d" % [OldMine.ID, n]


## The level a map id names, or 0 for a map that isn't part of the old mine.
static func level_of(id: String) -> int:
	if id == OldMine.ID:
		return 1
	if id.begins_with(OldMine.ID + "_"):
		return int(id.substr(OldMine.ID.length() + 1))
	return 0


## "Old mine" for Level 1, "Old mine, level 2" below it.
static func level_name(n: int) -> String:
	return OldMine.NAME if n <= 1 else "%s, level %d" % [OldMine.NAME, n]


## The pattern family of a level: "workings" for Level 1, then each family once in a seeded order,
## then any family but the one above it.
static func family(seed: int, n: int) -> String:
	if n <= 1:
		return "workings"
	if n - 2 < FAMILIES.size():
		var order: Array = FAMILIES.duplicate()
		var g := _rng(seed, 0)
		for i in range(order.size() - 1, 0, -1):
			var k := g.randi_range(0, i)
			var t = order[i]
			order[i] = order[k]
			order[k] = t
		return order[n - 2]
	var above := family(seed, n - 1)
	var choices: Array = FAMILIES.filter(func(f): return f != above)
	return choices[_rng(seed, n * 31).randi_range(0, choices.size() - 1)]


static func _rng(seed: int, salt: int) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = hash([seed, salt, "old mine"])
	return g


## Coal and iron blocks on a level: Level 1's, and more for each level down.
## Ores that only appear from a level down (issue #186), as data so a later one is a new row: the first level, how
## many blocks that level has, one more every `every` levels, and at most `max`.
const DEEP_ORES := {"diamond": {"from": 4, "base": 1, "every": 2, "max": 3},
	"gold": {"from": 2, "base": 2, "every": 2, "max": 5},      # smelted into gold ingots, for the piglins (issue #146)
	"gravel": {"from": 3, "base": 2, "every": 2, "max": 4},    # sometimes drops flint
	"obsidian": {"from": 5, "base": 4, "every": 1, "max": 8},  # beside a lava pool; only a diamond pickaxe breaks it
	"lapis": {"from": 3, "base": 2, "every": 2, "max": 5},     # the common cost of every enchantment (issue #163); an iron pickaxe or better
	"redstone": {"from": 3, "base": 2, "every": 2, "max": 5}}  # for the devices (issue #170); an iron pickaxe or better
## The character each deep ore is drawn with in a level's rows ("L" is a lava pool, beside the obsidian).
const DEEP_CHARS := {"diamond": "d", "gold": "g", "gravel": "v", "obsidian": "b", "lapis": "l", "redstone": "r"}


## How many blocks of a deep ore a level has: none above its first level.
static func deep_ore_count(n: int, ore: String) -> int:
	var d: Dictionary = DEEP_ORES[ore]
	if n < d.from:
		return 0
	return mini(d.max, d.base + (n - d.from) / d.every)


static func ore_count(n: int, ore: String) -> int:
	return {"coal": 6, "iron": 4}[ore] + Tuning.LEVEL_ORE[ore] * (n - 1)


## Torches on a level: fewer the deeper it is.
static func torch_count(n: int) -> int:
	return maxi(1, 5 - n)


## A deeper level's layout, rows of characters like OldMine.LAYOUT, plus `~` water, `D` the door and
## its loose ceilings and ledges: {rows, family, loose: [cells], ledges: [cells]}.
static func layout(seed: int, n: int) -> Dictionary:
	var fam := family(seed, n)
	var g := _rng(seed, n)
	var again := n - 2 >= FAMILIES.size()  # a family come back: other settings this time
	var w := 16
	var h := 16
	if again:
		w = g.randi_range(15, 18)
		h = g.randi_range(14, 17)
	var cells: Array = []
	for y in h:
		var row: Array = []
		row.resize(w)
		row.fill("#")
		cells.append(row)
	var grid := {"w": w, "h": h, "c": cells, "ey": 0, "dy": 0}
	match fam:
		"winding": _winding(grid, g)
		"pillared": _pillared(grid, g)
		"branching": _branching(grid, g)
		"stream": _stream(grid, g)
		_: _collapsed(grid, g)
	if again or g.randf() < 0.5:  # mirrored top to bottom
		cells.reverse()
		grid.ey = h - 1 - grid.ey
		grid.dy = h - 1 - grid.dy
	_ends(grid)
	_connect(grid)
	_ore(grid, g, n, fam)
	_torches(grid, g, n)
	var loose := _loose(grid, g, n, fam)
	var ledges := _ledges(grid, g, n)
	_deep_ores(grid, seed, n)
	var rows: Array = []
	for row in cells:
		rows.append("".join(row))
	return {"rows": rows, "family": fam, "loose": loose, "ledges": ledges}


## Builds a deeper level's map, as it is before anyone has been down. Ids come from the sim.
static func build(s: Sim, n: int) -> SimMap:
	var lay := layout(s.seed, n)
	var rows: Array = lay.rows
	var m := SimMap.new(rows[0].length(), rows.size())
	m.id = level_id(n)
	m.kind = "site"
	m.name = level_name(n)
	m.known = false
	m.level = n
	m.pattern = lay.family
	m.door_state = "closed"
	m.found = true  # no hidden vein down here: what's seen is what's there
	m.discovered = true
	for y in rows.size():
		for x in rows[y].length():
			var c := Vector2i(x, y)
			match rows[y][x]:
				"#":
					m.rock[c] = true
				"t":
					m.rock[c] = true
					m.torches.append(c)
				"E":
					m.entrance = c
				"D":
					m.rock[c] = true
					m.door = c
				"~":
					m.water[c] = true
				"o":
					m.boulders.append(OldMine._block(s, c, ""))
				"c":
					m.boulders.append(OldMine._block(s, c, "coal"))
				"i":
					m.boulders.append(OldMine._block(s, c, "iron"))
				"d":  # diamond ore is hidden until someone mines next to it (issue #186)
					var d := OldMine._block(s, c, "diamond")
					d.hidden = true
					m.boulders.append(d)
				"g":
					m.boulders.append(OldMine._block(s, c, "gold"))
				"v":
					m.boulders.append(OldMine._block(s, c, "gravel"))
				"b":
					m.boulders.append(OldMine._block(s, c, "obsidian"))
				"l":
					m.boulders.append(OldMine._block(s, c, "lapis"))
				"r":
					m.boulders.append(OldMine._block(s, c, "redstone"))
				"L":  # a lava pool: rock to walk, with a glow (issue #146)
					m.rock[c] = true
					m.lava[c] = true
	for b in m.boulders:
		if b.cell in lay.loose:
			b.loose = true
	m.ledges = lay.ledges
	return m


## The open cell in front of a level's door, where the party stands to open it.
static func door_front(m: SimMap) -> Vector2i:
	return m.door + Vector2i(-1, 0)


## Whether a minable way runs from the entrance to the door: through open floor and blocks, never rock
## or water.
static func minable_path(m: SimMap) -> bool:
	var blocked := func(c: Vector2i) -> bool: return not m.in_bounds(c) or m.rock.has(c) or m.water.has(c)
	var to := door_front(m)
	var seen := {m.entrance: true}
	var queue: Array = [m.entrance]
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		if c == to:
			return true
		for d in Sim.DIRS:
			var nc: Vector2i = c + d
			if not seen.has(nc) and not blocked.call(nc):
				seen[nc] = true
				queue.append(nc)
	return false


# ---------------------------------------------------------------- the pattern families

static func _open(grid: Dictionary, x: int, y: int, ch := ".") -> void:
	if x >= 1 and y >= 1 and x <= grid.w - 2 and y <= grid.h - 2:
		grid.c[y][x] = ch


static func _at(grid: Dictionary, x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= grid.w or y >= grid.h:
		return "#"
	return grid.c[y][x]


## One meandering passage from the entrance to the door, a cell or two wide, with pockets off it.
static func _winding(grid: Dictionary, g: RandomNumberGenerator) -> void:
	var h: int = grid.h
	var y := g.randi_range(3, h - 4)
	grid.ey = y
	var target := y
	var path: Array = []
	var carve := func(x: int, at: int) -> void:
		_open(grid, x, at)
		path.append(Vector2i(x, at))
		if g.randf() < 0.45:
			_open(grid, x, at + (1 if at < h / 2 else -1))
	var up := y > h / 2
	for x in range(1, grid.w - 1):
		if x % 4 == 2:  # swing to the other side of the level, top and bottom by turns
			target = g.randi_range(2, h / 3) if up else g.randi_range(h - 1 - h / 3, h - 3)
			up = not up
		carve.call(x, y)
		for k in 2 + g.randi_range(0, 1):
			if y == target:
				break
			y += signi(target - y)
			carve.call(x, y)
	grid.dy = y
	for i in g.randi_range(3, 4):  # pockets off the passage
		var p: Vector2i = path[g.randi_range(2, path.size() - 3)]
		var side := -1 if p.y > h / 2 else 1
		for dx in g.randi_range(2, 3):
			for dy in range(1, 3):
				_open(grid, p.x + dx, p.y + side * dy)
	for i in 4:  # loose stone in the passage
		var p: Vector2i = path[g.randi_range(3, path.size() - 2)]
		grid.c[p.y][p.x] = "o"


## A wide room broken by a grid of stone pillars.
static func _pillared(grid: Dictionary, g: RandomNumberGenerator) -> void:
	var w: int = grid.w
	var h: int = grid.h
	for x in range(2, w - 2):
		for y in range(2, h - 2):
			var pillar := (x - 2) % 3 == 2 and (y - 2) % 3 == 2
			_open(grid, x, y, "#" if pillar else ".")
	grid.ey = g.randi_range(3, h - 4)
	grid.dy = g.randi_range(3, h - 4)
	_open(grid, 1, grid.ey)
	for i in 10:
		var x := g.randi_range(3, w - 4)
		var y := g.randi_range(2, h - 3)
		if _at(grid, x, y) == ".":
			grid.c[y][x] = "o"


## A maze of narrow tunnels, with a few loops so it isn't all dead ends.
static func _branching(grid: Dictionary, g: RandomNumberGenerator) -> void:
	var cols: int = (grid.w - 2) / 2
	var rows: int = (grid.h - 2) / 2
	var seen := {}
	var stack: Array = [Vector2i(0, g.randi_range(0, rows - 1))]
	seen[stack[0]] = true
	grid.ey = 1 + 2 * stack[0].y
	while not stack.is_empty():
		var cur: Vector2i = stack[-1]
		_open(grid, 1 + 2 * cur.x, 1 + 2 * cur.y)
		var next: Array = []
		for d in Sim.DIRS:
			var nc: Vector2i = cur + d
			if nc.x >= 0 and nc.y >= 0 and nc.x < cols and nc.y < rows and not seen.has(nc):
				next.append(nc)
		if next.is_empty():
			stack.pop_back()
			continue
		var nc: Vector2i = next[g.randi_range(0, next.size() - 1)]
		seen[nc] = true
		_open(grid, 1 + cur.x + nc.x, 1 + cur.y + nc.y)  # the wall between them
		stack.append(nc)
	for i in 4:  # loops
		var x := g.randi_range(2, grid.w - 3)
		var y := g.randi_range(2, grid.h - 3)
		if (x + y) % 2 == 1 and _at(grid, x, y) == "#":
			_open(grid, x, y)
	grid.dy = 1 + 2 * g.randi_range(0, rows - 1)
	_open(grid, 2 * cols, grid.dy)  # out of the maze's last column toward the door
	for i in 4:
		var x := 1 + 2 * g.randi_range(1, cols - 1)
		var y := 1 + 2 * g.randi_range(0, rows - 1)
		grid.c[y][x] = "o"


## A cavern split by a stream that runs from one wall most of the way across: the way goes around it.
static func _stream(grid: Dictionary, g: RandomNumberGenerator) -> void:
	var w: int = grid.w
	var h: int = grid.h
	var cx := w / 2.0
	var cy := h / 2.0
	for x in range(1, w - 1):
		for y in range(1, h - 1):
			var dx := (x + 0.5 - cx) / (w / 2.0 - 0.5)
			var dy := (y + 0.5 - cy) / (h / 2.0 - 0.5)
			if dx * dx + dy * dy <= 1.0 + g.randf_range(-0.12, 0.12):
				_open(grid, x, y)
	var sx := w / 2 - 1
	var gap := h - 4  # the stream stops short of the far wall
	for y in range(1, gap):
		for x in [sx, sx + 1]:
			if _at(grid, x, y) == ".":
				grid.c[y][x] = "~"
	grid.ey = g.randi_range(3, h / 2)
	grid.dy = g.randi_range(3, h / 2)
	for x in range(1, 4):
		_open(grid, x, grid.ey)
	for x in range(w - 4, w - 1):
		_open(grid, x, grid.dy)
	for i in 8:
		var x := g.randi_range(2, w - 3)
		var y := g.randi_range(2, h - 3)
		if _at(grid, x, y) == ".":
			grid.c[y][x] = "o"


## A field of rubble under a loose ceiling.
static func _collapsed(grid: Dictionary, g: RandomNumberGenerator) -> void:
	var w: int = grid.w
	var h: int = grid.h
	for x in range(1, w - 1):
		for y in range(2, h - 2):
			var edge := x == 1 or x == w - 2 or y == 2 or y == h - 3
			if edge and g.randf() < 0.4:
				continue
			_open(grid, x, y, "o" if g.randf() < 0.45 else ".")
	grid.ey = g.randi_range(3, h - 4)
	grid.dy = g.randi_range(3, h - 4)


# ---------------------------------------------------------------- what every level has

## The entrance on the west edge, the door on the east, a block of stone in front of the door, so the
## party has to mine its way to it.
static func _ends(grid: Dictionary) -> void:
	var w: int = grid.w
	grid.c[grid.ey][0] = "E"
	if _at(grid, 1, grid.ey) in ["#", "~", "o"]:
		grid.c[grid.ey][1] = "."
	grid.c[grid.dy][w - 1] = "D"
	grid.c[grid.dy][w - 2] = "o"
	if _at(grid, w - 3, grid.dy) in ["#", "~"]:
		grid.c[grid.dy][w - 3] = "o"


## Makes sure a minable way runs from the entrance to the door: if the pattern left the door cut off,
## a rubble-filled tunnel joins it to the nearest part that can be reached.
static func _connect(grid: Dictionary) -> void:
	var start := Vector2i(1, grid.ey)
	var to := Vector2i(grid.w - 2, grid.dy)
	var reach := _reachable(grid, start)
	if reach.has(to):
		return
	var best: Vector2i = start
	for c in reach:
		if Sim.manhattan(c, to) < Sim.manhattan(best, to):
			best = c
	var c := best
	while c != to:
		if c.x != to.x:
			c.x += signi(to.x - c.x)
		else:
			c.y += signi(to.y - c.y)
		if _at(grid, c.x, c.y) in ["#", "~"]:
			grid.c[c.y][c.x] = "o"


## Cells reachable from `start` through floor and blocks.
static func _reachable(grid: Dictionary, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var queue: Array = [start]
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		for d in Sim.DIRS:
			var nc: Vector2i = c + d
			if not seen.has(nc) and not (_at(grid, nc.x, nc.y) in ["#", "~", "E", "D", "t"]):
				seen[nc] = true
				queue.append(nc)
	return seen


## Coal and iron, set into the walls beside open floor away from the entrance, and in the maze's dead
## ends. Iron lies deeper in than coal. In a wide room, some lies out on the floor too.
static func _ore(grid: Dictionary, g: RandomNumberGenerator, n: int, fam: String) -> void:
	var reach := _reachable(grid, Vector2i(1, grid.ey))
	var keep := {Vector2i(1, grid.ey): true, Vector2i(2, grid.ey): true, Vector2i(grid.w - 2, grid.dy): true, Vector2i(grid.w - 3, grid.dy): true}
	var spots := {}
	for c in reach:
		if _at(grid, c.x, c.y) != "." or c.x < 3:
			continue
		var walls: Array = []
		for d in Sim.DIRS:
			var wc: Vector2i = c + d
			if _at(grid, wc.x, wc.y) == "#" and wc.x >= 2 and wc.y >= 1 and wc.x <= grid.w - 2 and wc.y <= grid.h - 2:
				walls.append(wc)
		var dead := walls.size() >= 3
		for wc in walls:  # the rock beside the floor
			spots[wc] = maxf(spots.get(wc, 0.0), wc.x * 0.4 + g.randf() * 3.0 + (6.0 if dead and fam == "branching" else 0.0))
		if fam in ["pillared", "stream", "collapsed"] and not keep.has(c) and g.randf() < 0.25:
			spots[c] = c.x * 0.4 + g.randf() * 2.0
	var list: Array = spots.keys()
	list.sort_custom(func(a, b): return spots[a] > spots[b])
	var chosen: Array = list.slice(0, ore_count(n, "coal") + ore_count(n, "iron"))
	chosen.sort_custom(func(a, b): return a.x > b.x)  # iron furthest in
	for i in chosen.size():
		var c: Vector2i = chosen[i]
		grid.c[c.y][c.x] = "i" if i < ore_count(n, "iron") else "c"


## Hidden deep ores (issue #186), placed last from a stream of their own so the rest of a level, and every level that
## has none, is exactly as it was: the rock beside open floor, far from the entrance, not already ore.
static func _deep_ores(grid: Dictionary, seed: int, n: int) -> void:
	for ore in DEEP_ORES:
		var count := deep_ore_count(n, ore)
		if count <= 0:
			continue
		var g := _rng(seed ^ 0xD1A if ore == "diamond" else seed ^ 0xD1A ^ hash(ore), n)  # diamonds keep the stream they had
		var spots: Array = []
		var wide: bool = ore in ["lapis", "redstone"]  # these two may also sit in the level's edge wall (issue #163)
		for y in range(0 if wide else 1, grid.h if wide else grid.h - 1):
			for x in range(grid.w / 2 if ore == "diamond" else 3, grid.w - 1 if wide else grid.w - 2):  # the new ores may lie anywhere past the entrance
				if _at(grid, x, y) != "#":
					continue
				for d in Sim.DIRS:
					if _at(grid, x + d.x, y + d.y) in [".", "o", "c", "i"]:  # beside open floor, or stone and ore a party mines through
						spots.append(Vector2i(x, y))
						break
		for i in mini(count, spots.size()):
			var at := g.randi_range(0, spots.size() - 1)
			var c: Vector2i = spots[at]
			spots.remove_at(at)
			grid.c[c.y][c.x] = DEEP_CHARS[ore]
			if ore == "obsidian":  # a lava pool in the rock behind it, where there is room
				for d in Sim.DIRS:
					var lc: Vector2i = c + d
					if _at(grid, lc.x, lc.y) == "#" and lc.x >= 1 and lc.y >= 1 and lc.x <= grid.w - 2 and lc.y <= grid.h - 2 and Sim.DIRS.all(func(e): return _at(grid, lc.x + e.x, lc.y + e.y) in ["#", DEEP_CHARS[ore], "L"]):
						grid.c[lc.y][lc.x] = "L"
						break


## Torches on the walls beside open floor, spread out, fewer the deeper the level.
static func _torches(grid: Dictionary, g: RandomNumberGenerator, n: int) -> void:
	var walls: Array = []
	for y in range(1, grid.h - 1):
		for x in range(1, grid.w - 1):
			if _at(grid, x, y) != "#":
				continue
			for d in Sim.DIRS:
				if _at(grid, x + d.x, y + d.y) == ".":
					walls.append(Vector2i(x, y))
					break
	var lit: Array = [Vector2i(0, grid.ey)]
	for i in torch_count(n):
		var best = null
		var bd := -1.0
		for c in walls:
			var d := INF
			for t in lit:
				d = minf(d, Vector2(c).distance_to(Vector2(t)))
			d += g.randf()
			if d > bd:
				bd = d
				best = c
		if best == null:
			return
		grid.c[best.y][best.x] = "t"
		lit.append(best)
		walls.erase(best)


## Blocks under a loose ceiling: a couple more each level down, and the rubble field is full of them.
## Never the block in front of the door.
static func _loose(grid: Dictionary, g: RandomNumberGenerator, n: int, fam: String) -> Array:
	var blocks: Array = []
	for y in grid.h:
		for x in grid.w:
			if _at(grid, x, y) in ["o", "c", "i"] and Vector2i(x, y) != Vector2i(grid.w - 2, grid.dy):
				blocks.append(Vector2i(x, y))
	var want := 2 + n + (6 if fam == "collapsed" else 0)
	var out: Array = []
	while out.size() < want and not blocks.is_empty():
		out.append(blocks.pop_at(g.randi_range(0, blocks.size() - 1)))
	return out


## Ledges in the dark, which someone could fall from: more the deeper the level.
static func _ledges(grid: Dictionary, g: RandomNumberGenerator, n: int) -> Array:
	var torches: Array = []
	for y in grid.h:
		for x in grid.w:
			if _at(grid, x, y) == "t":
				torches.append(Vector2i(x, y))
	var dark: Array = []
	for y in grid.h:
		for x in grid.w:
			var c := Vector2i(x, y)
			if _at(grid, x, y) != "." or c.x < 3:
				continue
			if not torches.any(func(t): return Vector2(t).distance_to(Vector2(c)) <= Tuning.TORCH_LIGHT):
				dark.append(c)
	var out: Array = []
	for i in mini(1 + n / 2, dark.size()):
		out.append(dark.pop_at(g.randi_range(0, dark.size() - 1)))
	return out
