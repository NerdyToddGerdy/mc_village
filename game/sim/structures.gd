class_name Structures
extends RefCounted
## The structure adventures (Slice 7, issues #247 to #252): small hand-laid site maps that a Cartographer's survey finds and a party digs,
## told apart by what they hold and what can go wrong in them. They follow the mine's work rules (`kind` "mine" in `Adventures.def`).
## A new one is an entry here, its Bring-back defaults in `Tuning.CARGO_DEFAULTS`, and nothing else: the board, the survey, the world map
## and saves read this table. Each one's `layout` has one row per line, west to east; the party arrives at E. Characters as in
## `OldMine.LAYOUT`, with
##   g gold ore   l lapis   r redstone   v gravel (flint)   c coal   k a chest in the stone, holding one enchanted book

const DEFS := {
	"desert_well": {
		"name": "Desert well", "find": "a desert well", "sign": "west", "road": MeadowRoad.ID, "pin": "west:2",
		"told": "A dry well in the sand to the west, with a stone room under it. Gold, they say.",
		"access": ["Narrow rooms: 1 resident per room"],
		"gives": ["gold"], "others": ["gold_ore", "cobble"], "target": ["gold_ore", 4], "picks": 1,
		"loose": [Vector2i(3, 4), Vector2i(9, 4)], "ledges": [],
		"layout": [
			"###t####t###",
			"#####.g.####",
			"#..o.....o.#",
			"E.....#..#.#",
			"#..o..#g.o.#",
			"t....o.....t",
			"#......k...#",
			"#####.g.####",
			"###t####t###",
		],
	},
	"desert_temple": {
		"name": "Desert temple", "find": "a desert temple", "sign": "west", "road": MeadowRoad.ID, "pin": "south-west:3",
		"told": "A sandstone temple half under the dunes to the west. Its two chests are guarded by stone, they say.",
		"access": ["A narrow hall: 1 resident at a time"],
		"gives": ["gold"], "others": ["gold_ore", "cobble"], "target": ["gold_ore", 4], "picks": 1,
		"loose": [Vector2i(2, 1), Vector2i(11, 5)], "ledges": [],
		"layout": [
			"###t######t###",
			"#.o..g##g..o.#",
			"#....#..#....#",
			"E.....kk.....#",
			"#....#..#....#",
			"#.o..g##g..o.#",
			"##############",
		],
	},
	"jungle_temple": {
		"name": "Jungle temple", "find": "a jungle temple", "sign": "east", "road": Road.ID, "pin": "south-east:3",
		"told": "A mossy temple past the old caves, full of trap rooms. Redstone and lapis, they say. It wants an iron pickaxe.",
		"access": ["Trap rooms: 1 resident per room"],
		"gives": ["redstone", "lapis"], "others": ["redstone", "lapis", "cobble"], "target": ["redstone", 4], "picks": 1,
		"loose": [Vector2i(1, 1), Vector2i(1, 5), Vector2i(11, 3)], "ledges": [Vector2i(3, 3), Vector2i(7, 3)],
		"layout": [
			"###t#####t####",
			"#o.r.#...#.r.#",
			"#....#.k.#...#",
			"E..........o.#",
			"#....#...#...#",
			"#o.r.#...#.l.#",
			"######t#####t#",
		],
	},
	"fossil_site": {
		"name": "Fossil site", "find": "a fossil site", "sign": "west", "road": MeadowRoad.ID, "pin": "north-west:2",
		"told": "Old bones in black stone, a slow dig to the west. Coal and flint, they say.",
		"access": ["An open dig: 2 residents"],
		"gives": ["coal", "gravel"], "others": ["coal", "flint", "cobble"], "target": ["coal", 8], "picks": 1,
		"loose": [Vector2i(6, 1), Vector2i(8, 5)], "ledges": [],
		"layout": [
			"##t#####t###",
			"#c.v..c..v.#",
			"#.vc...v.c.#",
			"E..........#",
			"#.c..v.c..v#",
			"#v..c...v.c#",
			"###t######t#",
		],
	},
	"trail_ruins": {
		"name": "Trail ruins", "find": "some trail ruins", "sign": "west", "road": MeadowRoad.ID, "pin": "north:2",
		"told": "Buried ruins along an old trail. Chests under the gravel, they say.",
		"access": ["A trail of rooms: 1 resident per room"],
		"gives": ["gravel"], "others": ["flint", "cobble"], "target": ["flint", 4], "picks": 1,
		"loose": [Vector2i(4, 1), Vector2i(7, 5)], "ledges": [],
		"layout": [
			"###t####t###",
			"#k..o..o..k#",
			"#..v....v..#",
			"E....kk....#",
			"#..v....v..#",
			"#o..o..o..o#",
			"###t####t###",
		],
	},
	"buried_treasure": {
		"name": "Buried treasure", "find": "buried treasure", "sign": "dock", "road": MeadowRoad.ID, "pin": "south:1", "coast": true,
		"told": "A map's X in the sand along the shore: a chest, and gold with it.",
		"access": ["A shallow dig: 1 resident at a time"],
		"gives": ["gold"], "others": ["gold_ore", "cobble"], "target": ["gold_ore", 4], "picks": 1,
		"loose": [Vector2i(4, 1)], "ledges": [],
		"layout": [
			"##t###t##",
			"#...o...#",
			"E....k..#",
			"#..g.g..#",
			"##t###t##",
		],
	},
	"shipwreck": {
		"name": "Shipwreck", "find": "a shipwreck", "sign": "dock", "road": MeadowRoad.ID, "pin": "south-west:1", "coast": true,
		"told": "A wreck on the sand bars off the shore. Chests in the hold, they say, and gold.",
		"access": ["A narrow hold: 1 resident per room"],
		"gives": ["gold", "gravel"], "others": ["gold_ore", "flint", "cobble"], "target": ["gold_ore", 4], "picks": 1,
		"loose": [Vector2i(1, 1), Vector2i(10, 3)], "ledges": [],
		"layout": [
			"###t####t###",
			"#o..g..k..o#",
			"E.....v....#",
			"#o..k..g..o#",
			"###t####t###",
		],
	},
	"ocean_ruins": {
		"name": "Ocean ruins", "find": "some ocean ruins", "sign": "dock", "road": MeadowRoad.ID, "pin": "south:2", "coast": true,
		"told": "Drowned stone halls off the coast, lapis in their walls. It wants an iron pickaxe.",
		"access": ["Drowned halls: 1 resident per hall"],
		"gives": ["lapis", "gold"], "others": ["lapis", "gold_ore", "cobble"], "target": ["lapis", 4], "picks": 1,
		"loose": [Vector2i(4, 1), Vector2i(6, 3)], "ledges": [],
		"layout": [
			"###t###t###",
			"#l..o.o..l#",
			"E....k...g#",
			"#l..o.o..l#",
			"###t###t###",
		],
	},
	"geode": {
		"name": "Geode", "find": "a geode", "sign": "east", "road": Road.ID, "pin": "north-east:3",
		"told": "A hollow in the rock past the old caves, lined with lapis. It wants an iron pickaxe.",
		"access": ["A narrow hollow: 1 resident at a time"],
		"gives": ["lapis", "gold"], "others": ["lapis", "gold_ore", "cobble"], "target": ["lapis", 6], "picks": 1,
		"loose": [Vector2i(5, 1), Vector2i(5, 5)], "ledges": [],
		"layout": [
			"####t###t##",
			"##l..o..l##",
			"#.l.....l.#",
			"E.....g...#",
			"#.l.....l.#",
			"##l..o..l##",
			"####t###t##",
		],
	},
}

## The structures, in the order the Cartographer finds them: the land ones in the sectors on land, then the coastal ones (`coast`) in the sectors on the sea, which need a dock.
const IDS := ["desert_well", "desert_temple", "jungle_temple", "fossil_site", "trail_ruins", "geode", "buried_treasure", "shipwreck", "ocean_ruins"]

const ORE_OF := {"c": "coal", "g": "gold", "l": "lapis", "r": "redstone", "v": "gravel", "k": "chest"}


static func is_structure(id: String) -> bool:
	return DEFS.has(id)


## Builds a structure's site map as it is before anyone has been there. Ids come from the sim.
static func build(s: Sim, id: String) -> SimMap:
	var d: Dictionary = DEFS[id]
	var lay: Array = d.layout
	var m := SimMap.new(lay[0].length(), lay.size())
	m.id = id
	m.kind = "site"
	m.name = d.name
	m.known = false
	m.level = 1
	m.pattern = "workings"
	m.door_state = "closed"
	for y in lay.size():
		for x in lay[y].length():
			var c := Vector2i(x, y)
			var ch: String = lay[y][x]
			match ch:
				"#":
					m.rock[c] = true
				"t":
					m.rock[c] = true
					m.torches.append(c)
				"E":
					m.entrance = c
				"o":
					m.boulders.append(OldMine._block(s, c, ""))
				_:
					if ORE_OF.has(ch):
						var b := OldMine._block(s, c, ORE_OF[ch])
						if ch == "k":
							b.book = Defs.book_for("mine", hash([s.seed, id, c]))  # fixed by the game and the cell, so the same game finds the same chest
						m.boulders.append(b)
	for b in m.boulders:
		if b.cell in d.loose:
			b.loose = true
	m.ledges = d.ledges.duplicate()
	return m
