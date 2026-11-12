class_name Structures
extends RefCounted
## The structure adventures (Slice 7, issues #247 to #252): small hand-laid site maps that a Cartographer's survey finds and a party digs,
## told apart by what they hold and what can go wrong in them. They follow the mine's work rules (`kind` "mine" in `Adventures.def`).
## A new one is an entry here, its Bring-back defaults in `Tuning.CARGO_DEFAULTS`, and nothing else: the board, the survey, the world map
## and saves read this table. Each one's `layout` has one row per line, west to east; the party arrives at E. Characters as in
## `OldMine.LAYOUT`, with
##   g gold ore   l lapis   r redstone   v gravel (flint)   c coal   k a chest in the stone, holding one enchanted book
##   Z a zombie   S a skeleton   X a spider: they come for the party, so a place with them has `fight` and wants a guard

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
	"dungeon": {
		"name": "Dungeon", "find": "a dungeon", "sign": "west", "road": MeadowRoad.ID, "pin": "north:3", "fight": true,
		"told": "A walled room in the rock to the west, where something stirs. Two chests, they say, and coal.",
		"access": ["One room: the party fights where it stands"],
		"gives": ["coal"], "others": ["coal", "cobble"], "target": ["coal", 6], "picks": 1,
		"loose": [Vector2i(5, 1)], "ledges": [],
		"layout": [
			"###t####t###",
			"#Z...o....k#",
			"#....S.....#",
			"E.....c....#",
			"#....Z.....#",
			"#k...o....c#",
			"###t####t###",
		],
	},
	"igloo_cellar": {
		"name": "Igloo cellar", "find": "an igloo cellar", "sign": "east", "road": Road.ID, "pin": "north-east:2", "fight": true,
		"told": "A cold cellar under a snow house past the old caves. Flint, a chest, and something awake down there.",
		"access": ["A narrow cellar: 1 resident at a time"],
		"gives": ["gravel", "coal"], "others": ["flint", "coal", "cobble"], "target": ["flint", 4], "picks": 1,
		"loose": [Vector2i(6, 3)], "ledges": [],
		"layout": [
			"##t####t##",
			"#Z...k...#",
			"E....v...#",
			"#..v..o..#",
			"#k......c#",
			"##t####t##",
		],
	},
	"swamp_hut": {
		"name": "Swamp hut", "find": "a swamp hut", "sign": "west", "road": MeadowRoad.ID, "pin": "south-west:2", "fight": true,
		"told": "A stilt hut in the mud to the west, thick with spiders. Coal in the cellar, they say.",
		"access": ["A cramped hut: 1 resident at a time"],
		"gives": ["coal"], "others": ["coal", "cobble"], "target": ["coal", 6], "picks": 1,
		"loose": [Vector2i(5, 1)], "ledges": [],
		"layout": [
			"##t####t##",
			"#X...o...#",
			"E.....X..#",
			"#..c..k..#",
			"#.c......#",
			"##t####t##",
		],
	},
	"pillager_outpost": {
		"name": "Pillager outpost", "find": "a pillager outpost", "sign": "east", "road": Road.ID, "pin": "east:3", "fight": true,
		"told": "A watchtower camp in the hills past the old caves, held by archers. Chests and gold, they say.",
		"access": ["A camp of small rooms"],
		"gives": ["gold"], "others": ["gold_ore", "cobble"], "target": ["gold_ore", 4], "picks": 1,
		"loose": [Vector2i(5, 1), Vector2i(6, 5)], "ledges": [],
		"layout": [
			"###t####t###",
			"#S...o...g.#",
			"#....#.....#",
			"E.....S.k..#",
			"#....#.....#",
			"#k..S.o..k.#",
			"###t####t###",
		],
	},
	"trial_chambers": {
		"name": "Trial chambers", "find": "some trial chambers", "sign": "west", "road": MeadowRoad.ID, "pin": "south-west:3", "fight": true,
		"told": "A copper-green vault under the western sand, a chamber for each kind of trouble. Lapis, redstone, gold and chests. It wants an iron pickaxe.",
		"access": ["Two chambers joined by a door"],
		"gives": ["gold", "lapis", "redstone"], "others": ["gold_ore", "lapis", "redstone", "cobble"], "target": ["gold_ore", 4], "picks": 1,
		"loose": [Vector2i(4, 1), Vector2i(4, 5)], "ledges": [],
		"layout": [
			"###t######t###",
			"#Z..o..#..g..#",
			"#..k...#.r.S.#",
			"E.......X....#",
			"#..l...#.k...#",
			"#Z..o..#..r.S#",
			"###t######t###",
		],
	},
	"woodland_mansion": {
		"name": "Woodland mansion", "find": "a woodland mansion", "sign": "east", "road": Road.ID, "pin": "north-east:3", "fight": true,
		"told": "A great dark house deep in the trees beyond the old caves, full of rooms and what lives in them. It wants an iron pickaxe.",
		"access": ["Many rooms: the party fights room by room"],
		"gives": ["gold", "lapis", "redstone"], "others": ["gold_ore", "lapis", "redstone", "cobble"], "target": ["gold_ore", 4], "picks": 1,
		"loose": [Vector2i(4, 2), Vector2i(10, 3), Vector2i(4, 6)], "ledges": [],
		"layout": [
			"###t########t###",
			"#Z..k..#..g..Z.#",
			"#...o..#..S...r#",
			"E.........o....#",
			"#..l...#.......#",
			"#...S..#..k..X.#",
			"#k..o..#..g..l.#",
			"###t########t###",
		],
	},
	"stronghold": {
		"name": "Stronghold", "find": "a stronghold", "sign": "east", "road": Road.ID, "pin": "south-east:3", "fight": true,
		"told": "A buried stone fortress past the old caves, with libraries and archers in its halls. Gold and chests, they say.",
		"access": ["Halls and a library: 1 resident per hall"],
		"gives": ["gold"], "others": ["gold_ore", "cobble"], "target": ["gold_ore", 4], "picks": 1,
		"loose": [Vector2i(4, 2), Vector2i(4, 4)], "ledges": [],
		"layout": [
			"###t######t###",
			"#S..k..#..k..#",
			"#...o..#..Z.g#",
			"E.......Z....#",
			"#...o..#..g..#",
			"#S..k..#.....#",
			"###t######t###",
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
const IDS := ["desert_well", "desert_temple", "jungle_temple", "fossil_site", "trail_ruins", "geode", "dungeon", "igloo_cellar", "swamp_hut", "pillager_outpost", "trial_chambers", "woodland_mansion", "stronghold", "buried_treasure", "shipwreck", "ocean_ruins"]

const ORE_OF := {"c": "coal", "g": "gold", "l": "lapis", "r": "redstone", "v": "gravel", "k": "chest"}


## Entity ids in a structure's map come from here, not from the sim's counter: `ID_SPAN` each, far above any the sim hands out.
const ID_BASE := 1000000000
const ID_SPAN := 1000


## A boulder or ore block with a given id (the sim's `OldMine._block` takes one from its counter).
static func _block(bid: int, c: Vector2i, ore: String) -> Dictionary:
	var b := {"id": bid, "kind": "boulder", "cell": c, "alive": true, "des": false, "claim": 0, "unreach_until": 0}
	if ore != "":
		b.ore = ore
	return b


static func is_structure(id: String) -> bool:
	return DEFS.has(id)


## Builds a structure's site map as it is before anyone has been there. Ids come from the sim.
static func build(s: Sim, id: String) -> SimMap:
	var d: Dictionary = DEFS[id]
	var next := ID_BASE + IDS.find(id) * ID_SPAN  # their own range: adding or changing a structure never moves the ids of anything else (the residents', the village's)
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
					m.boulders.append(_block(next, c, ""))
					next += 1
				"Z", "S", "X":  # a creature that hunts anyone who comes in (issue #255)
					var sp: String = {"Z": "zombie", "S": "skeleton", "X": "spider"}[ch]
					next += 1
					m.creatures.append({"id": next, "kind": "creature", "species": sp, "cell": c, "pos": Vector2(c), "alive": true,
						"hp": Defs.CREATURES[sp].hp, "angry": false, "engaged": false, "cool": 0.0, "flash": 0, "acc": 0.0, "hunt": true})
				_:
					if ORE_OF.has(ch):
						next += 1
						var b := _block(next, c, ORE_OF[ch])
						if ch == "k":
							b.book = Defs.book_for("mine", hash([s.seed, id, c]))  # fixed by the game and the cell, so the same game finds the same chest
						m.boulders.append(b)
	for b in m.boulders:
		if b.cell in d.loose:
			b.loose = true
	m.ledges = d.ledges.duplicate()
	return m
