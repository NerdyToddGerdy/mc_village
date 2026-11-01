class_name Adventures
extends RefCounted
## What each adventure is, as data (Slice 7, issue #242). A new destination is one entry here, a map builder and a
## site report, not a new branch in every place that used to ask "is it the meadow?".
##
##   kind    "mine", "meadow" or "nether": which of the site's work rules it follows; a new kind adds its own
##   sign    "east" (the old mine's signpost), "west" (the meadow's) or "portal" (the Nether's gathering place)
##   road    the road map its party walks to get there, or "" when there is none (the portal)
##   cargo   the key into `Tuning.CARGO_DEFAULTS` for the Bring-back list's starting rows
##   others  the items it gives, in the order a plan's list adds them behind the objective
##   target  the item and amount a new plan asks for first
##   picks   spare pickaxes a new plan packs
##   pens    whether the party builds and tends pens there (sticks and wheat in the plan)
##   got     "mined", "hunted": what the home report says it came back with nothing of
##   left    the stop reason when nothing's left to work

const IDS := [OldMine.ID, Meadow.ID, NetherLanding.ID]

const DEFS := {
	OldMine.ID: {"kind": "mine", "sign": "east", "road": Road.ID, "cargo": "mine", "others": ["iron_ore", "coal", "cobble"],
		"target": ["coal", 8], "picks": 1, "pens": false, "got": "mined", "left": "nothing left to mine"},
	Meadow.ID: {"kind": "meadow", "sign": "west", "road": MeadowRoad.ID, "cargo": "meadow", "others": ["wool", "mutton", "leather", "beef", "porkchop"],
		"target": ["wool", 6], "picks": 0, "pens": true, "got": "hunted", "left": "nothing left to hunt"},
	NetherLanding.ID: {"kind": "nether", "sign": "portal", "road": "", "cargo": "mine", "others": [],
		"target": ["survey", 1], "picks": 0, "pens": false, "got": "mined", "left": "nothing left to mine"},
}


## An adventure's entry. A destination that isn't one (a deeper mine level, a Nether site) answers as the old mine does,
## which is what its party works by.
static func def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS[OldMine.ID])


## The road map a trip to `id` walks.
static func road_of(id: String) -> String:
	return def(id).road if def(id).road != "" else Road.ID
