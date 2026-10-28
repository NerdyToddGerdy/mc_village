class_name NetherLanding
extends RefCounted
## The portal landing (Slice 5, issue #148): the first Nether map, a small hub a party steps into through the
## village portal. Netherrack, a few lava pools set in the rock, and three landmarks to survey. Route strips
## (#153) leave from its edges later. Its id starts with "nether", which puts its parties in the Nether's
## expedition slot.

const ID := "nether_landing"
const NAME := "Nether: portal landing"

## One row per line. The party arrives at E, the portal's far side, on the west edge.
##   . netherrack   # rock   L lava pool (rock nobody walks into)   M a landmark to survey   o a block to mine
##   F a patch of fire (stepping on it sets someone alight)   v a ledge (a drop someone can fall from)
const LAYOUT := [
	"########################",
	"#......................#",
	"#..LL.........o........#",
	"#..LL......M..v........#",
	"#.........###..F.......#",
	"#.....o...#............#",
	"#.........#.......LL...#",
	"#...........#.....LL...#",
	"#..o.....M..#..........#",
	"#....v......####.......#",
	"#.....FF...............#",
	"#.........LL...........#",
	"E.........LL.......o...#",
	"#...............F......#",
	"#....###...............#",
	"#....#.......M......v..#",
	"#....#.F...............#",
	"#..........o...........#",
	"#.......LL.............#",
	"#.......LL...v..###....#",
	"#...............#......#",
	"#..o............#......#",
	"#......................#",
	"########################",
]

## Where the shelter's blueprint goes: three by three, near the arch (issue #152).
const SHELTER_AT := Vector2i(2, 5)

const TOLD := "A red, burning country on the far side of the portal. Nobody has been through."
const ACCESS := ["Open netherrack: room for the whole party"]
const HAZARDS := ["Lava pools in the rock: someone beside one can be burned", "Patches of fire: stepping on one sets someone alight", "Ledges: someone could fall"]


static func build(s: Sim) -> SimMap:
	var m := SimMap.new(LAYOUT[0].length(), LAYOUT.size())
	m.id = ID
	m.kind = "site"
	m.name = NAME
	m.known = false
	m.found = true  # no hidden vein here
	m.discovered = true
	for y in LAYOUT.size():
		for x in LAYOUT[y].length():
			var c := Vector2i(x, y)
			match LAYOUT[y][x]:
				"#":
					m.rock[c] = true
				"L":
					m.rock[c] = true
					m.lava[c] = true
				"E":
					m.entrance = c
				"M":
					m.landmarks.append(c)
				"F":
					m.fire[c] = true
				"v":
					m.ledges.append(c)
				"o":
					m.boulders.append(OldMine._block(s, c, ""))
	return m
