class_name Visits
extends RefCounted
## Another village (Slice 7, issue #253): a friendly place of its own folk, where a party can invite someone home. No trade and no
## currency (that is open, #264's trade); this is the other way to find residents. Provisional rule, decided as a default for now:
## a visit invites `Tuning.INVITES_PER_VISIT` villager, who walks home behind the party and takes a free bed like any traveller
## (#24: one per free bed). It adds to the beds' own arrivals; it does not replace them. The folk are finite: each villager invited is gone.

const NAMES := ["Bram", "Wren", "Tilda", "Odo", "Hazel", "Cormac"]


## Whether a map is a village of folk.
static func is_village(id: String) -> bool:
	return Structures.DEFS.get(id, {}).get("folk", false)


## The villagers still there to invite.
static func folk_left(mp: SimMap) -> Array:
	return mp.creatures.filter(func(c): return c.alive and c.species == "villager")


## A party member's next job at a village: walk up to the nearest villager and invite them home, until the visit's one invitation
## is made. Only one resident goes at a time. Null when there's nothing to do.
static func invite_job(sim: Sim, r: Dictionary, c: Vector2i):
	if not is_village(sim.m.id) or sim.expedition.get("invited", []).size() >= Tuning.INVITES_PER_VISIT:
		return null
	if sim.residents.any(func(o): return o.job != null and o.job.kind == "invite"):
		return null
	var folk := folk_left(sim.m)
	if folk.is_empty():
		return null
	var v: Dictionary = Sim.nearest(folk, c)
	var j := Job.new("invite", "Inviting %s home" % v.name, v.name)
	j.step(sim._goto([v.cell], true))
	j.step({"op": "invite", "folk": v.id})
	return j


## The invitation is made: the villager is gone from the map, and will come home behind the party.
static func invite(sim: Sim, r: Dictionary, folk_id: int) -> Variant:
	var v: Dictionary = {}
	for c in sim.m.creatures:
		if c.id == folk_id and c.alive:
			v = c
	if v.is_empty() or sim.expedition.get("invited", []).size() >= Tuning.INVITES_PER_VISIT:
		return "gone"
	v.alive = false
	sim.expedition.invited = sim.expedition.get("invited", []) + [v.name]
	sim.rev += 1
	sim._toast("%s has asked %s to come home with them." % [r.name, v.name], r.id)
	return true


## The party's home: those invited become guests, who come when a bed is free.
static func home(sim: Sim, ex: Dictionary) -> void:
	var guests: Array = sim.stats.get("guests", [])
	sim.stats.guests = guests + ex.get("invited", [])


## The next guest's name, taken off the list, or "".
static func next_guest(sim: Sim) -> String:
	var guests: Array = sim.stats.get("guests", [])
	return guests.pop_front() if not guests.is_empty() else ""
