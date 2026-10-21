class_name Road
extends RefCounted
## The road to the old mine (Slice 4, issues #118, #119): a long, narrow route map between the
## village's east signpost and the mine's entrance. Parties walk it, and the line is laid along it.
##
## It's split into segments, each with its own terrain. Two hold obstacles: a stream, which people
## ford slowly until a plank bridge is built, and a rocky cut, whose boulders must be mined before
## track can be laid. Only the first segment is known until someone walks the road (#119).

const ID := "road"
const NAME := "Road to the mine"

## One row per line, west (the village) to east (the mine).
##   . grass   ~ the stream   # rock (the cut's walls)   o boulder   T tree
const LAYOUT := [
	".....T..............~~..........########....T...",
	"....................~~..........########........",
	"..........T.........~~...............o..........",
	"....................~~...........o..o.o.........",
	"....................~~............o.............",
	"............T.......~~..........########........",
	"....................~~....T.....########......T.",
]

## Where the road meets the village (west) and the mine (east). The line runs along this row.
const VILLAGE_END := Vector2i(0, 3)
const MINE_END := Vector2i(47, 3)
const LINE_ROW := 3

## The segments, west to east: name, first column, and obstacle ("", "stream" or "cut").
const SEGMENTS := [
	{"name": "The village edge", "x": 0, "terrain": "grass", "obstacle": ""},
	{"name": "Open grass", "x": 8, "terrain": "grass", "obstacle": ""},
	{"name": "The stream", "x": 16, "terrain": "a stream", "obstacle": "stream"},
	{"name": "The long field", "x": 24, "terrain": "grass", "obstacle": ""},
	{"name": "The rocky cut", "x": 32, "terrain": "a rocky cut", "obstacle": "cut"},
	{"name": "Below the mine", "x": 40, "terrain": "grass", "obstacle": ""},
]

## The plank bridge over the stream: where it goes, and its size. It spans the stream along the line.
const BRIDGE_AT := Vector2i(19, 2)
const BRIDGE_SIZE := Vector2i(4, 3)


## Builds the road as it is before anyone has walked it. Ids come from the sim.
static func build(s: Sim) -> SimMap:
	var m := SimMap.new(LAYOUT[0].length(), LAYOUT.size())
	m.id = ID
	m.kind = "route"
	m.name = NAME
	m.known = false
	m.entrance = VILLAGE_END
	m.seen = 1
	for y in LAYOUT.size():
		for x in LAYOUT[y].length():
			var c := Vector2i(x, y)
			match LAYOUT[y][x]:
				"~":
					m.water[c] = true
				"#":
					m.rock[c] = true
				"o":
					m.boulders.append({"id": s._id(), "kind": "boulder", "cell": c, "alive": true, "des": false, "claim": 0, "unreach_until": 0})
				"T":
					m.trees.append({"id": s._id(), "kind": "tree", "cell": c, "logs": 4, "alive": true, "des": false, "claim": 0, "unreach_until": 0})
	return m


static func segment_count() -> int:
	return SEGMENTS.size()


## Columns a segment covers.
static func seg_len(i: int) -> int:
	var end: int = SEGMENTS[i + 1].x if i + 1 < SEGMENTS.size() else LAYOUT[0].length()
	return end - SEGMENTS[i].x


## The segment a column is in.
static func segment_at(x: int) -> int:
	for i in range(SEGMENTS.size() - 1, -1, -1):
		if x >= SEGMENTS[i].x:
			return i
	return 0


## The cells of a segment along the line, west to east.
static func line_cells(i: int) -> Array:
	var out: Array = []
	for x in range(SEGMENTS[i].x, SEGMENTS[i].x + seg_len(i)):
		out.append(Vector2i(x, LINE_ROW))
	return out


## The bridge's cells.
static func bridge_rect() -> Rect2i:
	return Rect2i(BRIDGE_AT, BRIDGE_SIZE)
