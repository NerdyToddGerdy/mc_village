class_name SeaRoad
extends RefCounted
## The sea road (Slice 7, issue #407): the way a party sails from the village's dock to a place on the sea. Like the meadow's strip it is a
## plain strip (kind "walk") whose length sets the trip: nothing is built on it and it has no stream, cut or rails. Unlike the strip it needs a
## boatyard (`Sim.boatyard()`), and the view draws it as water with the boat's deck along the line. A coastal structure names it with
## `"road": SeaRoad.ID`; the three first coastal places still walk the meadow's strip.

const ID := "sea_road"
const NAME := "Sea road"
const ROWS := 5
const LINE_ROW := 2
const VILLAGE_END := Vector2i(0, LINE_ROW)


static func far_end() -> Vector2i:
	return Vector2i(Tuning.SEA_ROAD_LEN - 1, LINE_ROW)


## Builds the strip: empty (it has no trees, so adding it never moves an entity id).
static func build(_s: Sim) -> SimMap:
	var m := SimMap.new(Tuning.SEA_ROAD_LEN, ROWS)
	m.id = ID
	m.kind = "walk"
	m.name = NAME
	m.known = false
	m.entrance = VILLAGE_END
	return m


## Seconds from one end to the other under sail, and back.
static func walk_time() -> float:
	return float(Tuning.SEA_ROAD_LEN - 1) / Tuning.WALK
