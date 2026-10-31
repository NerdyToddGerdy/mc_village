class_name MeadowRoad
extends RefCounted
## The road to the meadow (issue #210): a plain walkable strip between the village's west signpost and
## the meadow's entrance. A party walks it where the player can see them, as it walks the road to the old
## mine, but it has no stream, cut, bridge, stations or rails: it can't be upgraded, and nobody builds on
## it. Its length sets the walk (`Tuning.MEADOW_ROAD_LEN`), so there is no separate timer.

const ID := "meadow_road"
const NAME := "Road to the meadow"
const ROWS := 5
## The row the party walks along.
const LINE_ROW := 2
## Where the strip meets the village (west) and the meadow (east), matching the mine's road.
const VILLAGE_END := Vector2i(0, LINE_ROW)


static func far_end() -> Vector2i:
	return Vector2i(Tuning.MEADOW_ROAD_LEN - 1, LINE_ROW)


## Builds the strip: open grass, with a few trees off the line. Ids come from the sim.
static func build(s: Sim) -> SimMap:
	var m := SimMap.new(Tuning.MEADOW_ROAD_LEN, ROWS)
	m.id = ID
	m.kind = "walk"
	m.name = NAME
	m.known = false
	m.entrance = VILLAGE_END
	for x in range(6, Tuning.MEADOW_ROAD_LEN - 4, 7):  # fixed spacing: the same strip every game
		var y := 0 if (x / 7) % 2 == 0 else ROWS - 1
		m.trees.append({"id": s._id(), "kind": "tree", "cell": Vector2i(x, y), "logs": 4, "alive": true, "des": false, "claim": 0, "unreach_until": 0})
	return m


## Seconds from one end to the other on foot: the walk to the meadow, and the walk home.
static func walk_time() -> float:
	return float(Tuning.MEADOW_ROAD_LEN - 1) / Tuning.WALK
