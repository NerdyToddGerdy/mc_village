class_name OldMine
extends RefCounted
## The old mine (issue #102): Slice 3's one nearby destination, a small hand-laid site map a short
## walk east of the village. Stone and coal near the entrance, and an iron vein, hidden behind rubble
## at the end of a dark tunnel, that nobody knows about until it's found (#111). Loose ceilings and a
## ledge in the dark make it dangerous (#110).

const ID := "old_mine"
const NAME := "Old caves"

## One row per line, west to east. The party arrives at E, on the west edge.
##   # rock wall (can't be mined)   t rock with a torch on it   . open floor   E the entrance
##   o boulder (cobblestone)        c coal ore                   i iron ore, hidden until discovered
##   D the door down to Level 2 (issue #132), set in the rock at the far end
const LAYOUT := [
	"################",
	"#####c...c######",
	"#####t.o...t####",
	"#######...######",
	"########.#######",
	"###c.###.###c.##",
	"###..t##.##t..##",
	"####..##..#...##",
	"E.....o.....o.oD",
	"#t.....##.o..###",
	"####.c###...####",
	"####..#####.####",
	"#####.#####.o###",
	"#####c######..i#",
	"############iii#",
	"################",
]

## Hazards (issue #110): blocks under a loose ceiling, which can cave in on the miner, and a ledge in
## the dark tunnel to the iron, which someone can fall from.
const LOOSE := [Vector2i(3, 5), Vector2i(12, 8), Vector2i(5, 13)]
const LEDGES := [Vector2i(11, 11)]

## What the village has been told about it, before anyone has been (issue #102).
const TOLD := "Some old caves a short walk east. Stone and coal, they say."
## Access notes for the site report.
const ACCESS := ["Narrow tunnels: 1 resident per tunnel"]


## Builds the old mine as it is before anyone has been there. Ids come from the sim, so they're
## unique across every map.
static func build(s: Sim) -> SimMap:
	var m := SimMap.new(LAYOUT[0].length(), LAYOUT.size())
	m.id = ID
	m.kind = "site"
	m.name = NAME
	m.known = false
	m.level = 1
	m.pattern = "workings"
	m.door_state = "closed"
	for y in LAYOUT.size():
		for x in LAYOUT[y].length():
			var c := Vector2i(x, y)
			match LAYOUT[y][x]:
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
				"o":
					m.boulders.append(_block(s, c, ""))
				"c":
					m.boulders.append(_block(s, c, "coal"))
				"i":
					var b := _block(s, c, "iron")
					b.hidden = true
					m.boulders.append(b)
	add_hazards(m)
	return m


## Marks the loose ceilings and the ledge on an old mine map, also for one from an older save.
static func add_hazards(m: SimMap) -> void:
	for b in m.boulders:
		if b.cell in LOOSE:
			b.loose = true
	m.ledges = LEDGES.duplicate()


static func _block(s: Sim, c: Vector2i, ore: String) -> Dictionary:
	var b := {"id": s._id(), "kind": "boulder", "cell": c, "alive": true, "des": false, "claim": 0, "unreach_until": 0}
	if ore != "":
		b.ore = ore
	return b
