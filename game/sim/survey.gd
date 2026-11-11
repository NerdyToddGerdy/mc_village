class_name Survey
extends RefCounted
## The Cartographer's surveys (issue #321). The land round the village is 8 sectors (the compass points) in 3 rings. The Cartographer,
## a resident who works from a cartographer's table, is sent to survey one sector's ring: they are away for a time that grows with
## the ring, and can be driven back by mobs (they return hurt, the sector still unsurveyed). Each survey that succeeds reveals the next
## place on the list: the old caves, then the ruined portal. Every function takes the Sim it works on.

## Off in tests that aren't about it, which keep the old board's way: it names the old caves from the start.
static var enabled := true

const SECTORS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
## The two sectors on the coast (issue #271): the sea can't be surveyed on foot.
const COAST := ["south", "south-west"]
## What a successful survey finds, in order. More follow when the structures are built (#242).
const FINDS := ["old_mine", "ruined_portal"]
const FIND_NAMES := {"old_mine": "the old caves", "ruined_portal": "a ruined portal"}


static func ring_name(ring: int) -> String:
	return ["near", "middle", "far"][ring - 1]


## Whether `id` has been found.
static func found(sim: Sim, id: String) -> bool:
	return sim.stats.get("found", {}).get(id, false)


static func surveyed(sim: Sim, sector: String, ring: int) -> bool:
	return sim.stats.get("surveyed", {}).get("%s:%d" % [sector, ring], false)


## The next place a survey would find, or "" when there's nothing more yet.
static func next_find(sim: Sim) -> String:
	for id in FINDS:
		if not found(sim, id):
			return id
	return ""


## The village's finished cartographer's table, or {}.
static func table(sim: Sim) -> Dictionary:
	for s in sim.maps.village.sites:
		if s.tpl == "cartographer_table" and s.done:
			return s
	return {}


## The resident who works the table, or {}.
static func cartographer(sim: Sim) -> Dictionary:
	var t := table(sim)
	return sim.resident(t.get("worker", 0)) if not t.is_empty() else {}


## How long a survey takes, in seconds, there and back: longer with each ring out, quicker with the Cartographer's level.
static func seconds(sim: Sim, ring: int) -> float:
	var who := cartographer(sim)
	var speed := Sim.skill_speed(who, "cartographer") if not who.is_empty() else 1.0
	return Tuning.SURVEY_SECONDS[ring - 1] / speed


## How likely mobs drive the surveyor back: more with each ring, less with armor.
static func danger(sim: Sim, ring: int) -> float:
	var who := cartographer(sim)
	var armor := Sim.protection(who) if not who.is_empty() else 0.0
	return Tuning.SURVEY_DANGER[ring - 1] * (1.0 - armor)


## Why a sector's ring can't be surveyed now, or "".
static func check(sim: Sim, sector: String, ring: int) -> String:
	if not sim.stats.get("survey", {}).is_empty():
		return "A survey is already out"
	if table(sim).is_empty():
		return "Build a cartographer's table first"
	var who := cartographer(sim)
	if who.is_empty():
		return "Give someone the Cartographer job"
	if who.away or who.map != "village" or who.get("hurt", 0) > 0 or sim.expedition_of(who).size() > 0:
		return "%s is away or hurt" % who.name
	if sector in COAST:
		return "The sea: it needs a boat"
	if ring < 1 or ring > 3:
		return "No such ring"
	if surveyed(sim, sector, ring):
		return "Already surveyed"
	if ring > 1 and not surveyed(sim, sector, ring - 1):
		return "Survey the %s ring first" % ring_name(ring - 1)
	if next_find(sim) == "":
		return "Nothing more to find yet"
	return ""


## Sends the Cartographer out. Returns whether they went.
static func start(sim: Sim, sector: String, ring: int) -> bool:
	if check(sim, sector, ring) != "":
		return false
	var who := cartographer(sim)
	if who.job != null:
		sim.fail_job(who)
	who.away = true
	who.trip = "survey"
	who.back_at = sim.tick + int(seconds(sim, ring) * Tuning.TPS)
	who.path = []
	sim.stats.survey = {"who": who.id, "sector": sector, "ring": ring}
	sim.rev += 1
	sim._toast("%s sets out to survey the %s ring to the %s." % [who.name, ring_name(ring), sector], who.id)
	return true


## The Cartographer comes back: driven off, or with a find.
static func arrive(sim: Sim, r: Dictionary) -> void:
	var sv: Dictionary = sim.stats.get("survey", {})
	sim.stats.erase("survey")
	r.away = false
	r.trip = ""
	var t := table(sim)
	var spot = sim.nearest_walkable(t.origin) if not t.is_empty() else null
	sim.move_to_map(r, "village", spot if spot != null else Vector2i(sim.w / 2, sim.h / 2))
	sim.rev += 1
	if sv.is_empty():
		return
	if Hazards._roll(sim, danger(sim, sv.ring)):
		Hazards.injure(sim, r, 1, "an attack on the survey")
		sim._toast("%s was driven back by mobs. The %s ring to the %s is still unsurveyed." % [r.name, ring_name(sv.ring), sv.sector], r.id)
		return
	if not sim.stats.has("surveyed"):
		sim.stats.surveyed = {}
	sim.stats.surveyed["%s:%d" % [sv.sector, sv.ring]] = true
	sim.gain_xp(r, "cartographer")
	var id := next_find(sim)
	if id == "":
		sim._toast("%s surveyed the %s ring to the %s and found nothing new." % [r.name, ring_name(sv.ring), sv.sector], r.id)
		return
	reveal(sim, id)
	if not sim.stats.has("found_at"):
		sim.stats.found_at = {}
	sim.stats.found_at[id] = "%s:%d" % [sv.sector, sv.ring]  # where the world map pins it
	sim._toast("%s found %s, in the %s ring to the %s." % [r.name, FIND_NAMES[id], ring_name(sv.ring), sv.sector], r.id)


## A place becomes known: the old caves with their road, or the ruined portal, which lets the village build its own.
static func reveal(sim: Sim, id: String) -> void:
	if not sim.stats.has("found"):
		sim.stats.found = {}
	sim.stats.found[id] = true
	if id == "old_mine":
		sim.maps[OldMine.ID].known = true
		sim.road().known = true
	sim.rev += 1
