class_name Meadow
extends RefCounted
## The meadow (Slice 3.5, issue #137): an expedition site with its own map, a short walk west of the
## village past the meadow signpost. It replaces Slice 2's timed meadow trip (#50). Herds of sheep, cows
## and pigs wander open grass around a pond, with a few trees and old fences. Each species grows back
## on its own. Its hazards are mild: an angry bull, and a slippery pond bank.

const ID := "meadow"
const NAME := "Meadow"

## One row per line, west to east. The party arrives at E, on the east edge, the side the village is on.
##   . grass   ~ the pond   , the pond's muddy bank (slippery)   T tree   f fence   E the entrance
##   s sheep   c cow   p pig (where each starts)
const LAYOUT := [
	"........................",
	"..T.......s.......T.....",
	".....s.......s..........",
	"..........ffffff........",
	"...c..........s.f....T..",
	"........c.......f.......",
	"..T.......c.....f..s....",
	"......,,,,,.............",
	".....,~~~~~,.....p......",
	"..c..,~~~~~~,...........",
	".....,~~~~~~,.....p.....",
	"......,~~~~,......s.....",
	".......,,,,....p........",
	"...........s...........E",
	"..T.....................",
	"...........p.....T......",
	"....ffff................",
	"....f.......c.....s.....",
	"....f..p................",
	"............T...........",
	"..s...........c.........",
	"........T...........T...",
	"...............p........",
	"........................",
]

## What the village has been told about it, before anyone has been there as an expedition.
const TOLD := "A meadow a short walk west, with sheep, cows and pigs."
const ACCESS := ["Open grass: room for the whole party"]


## Builds the meadow as it is before anyone has been there. Ids come from the sim.
static func build(s: Sim) -> SimMap:
	var m := SimMap.new(LAYOUT[0].length(), LAYOUT.size())
	m.id = ID
	m.kind = "site"
	m.name = NAME
	m.known = false
	var prev := s.map_id
	s.maps[ID] = m  # the animals are added on this map
	s.use_map(ID)
	for y in LAYOUT.size():
		for x in LAYOUT[y].length():
			var c := Vector2i(x, y)
			match LAYOUT[y][x]:
				"~":
					m.water[c] = true
				",":
					m.banks.append(c)
				"f":
					m.fences[c] = true
				"E":
					m.entrance = c
				"T":
					m.trees.append({"id": s._id(), "kind": "tree", "cell": c, "logs": 4, "alive": true, "des": false, "claim": 0, "unreach_until": 0})
				"s":
					s.add_animal(c, "sheep")
				"c":
					s.add_animal(c, "cow")
				"p":
					s.add_animal(c, "pig")
	s.use_map(prev)
	return m


static var _herd := {}


## Animals of each species at the start, and the most the meadow holds of each. Worked out from the
## layout once: the meadow's regrowth asks every tick.
static func herd() -> Dictionary:
	if _herd.is_empty():
		for row in LAYOUT:
			for ch in row:
				var sp: String = {"s": "sheep", "c": "cow", "p": "pig"}.get(ch, "")
				if sp != "":
					_herd[sp] = _herd.get(sp, 0) + 1
		_herd.make_read_only()
	return _herd
