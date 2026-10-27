class_name SimMap
extends RefCounted
## One block map (issue #100): the village, a site an expedition works, like the old mine, or the
## road between them (issue #118).
##
## The sim works on one map at a time (`Sim.use_map`), and its per-map fields (`trees`, `items`,
## `sites`, ...) read and write that map's. Residents aren't kept here: they're the sim's, each with
## the `map` it's on. Paths and jobs never cross maps; only travel moves a resident between them.

var id := "village"
var kind := "village"        ## "village", "site" or "route".
var name := "Village"
var w := Tuning.MAP_W
var h := Tuning.MAP_H
var trees: Array = []        ## {id, kind:"tree", cell, logs, alive, des, claim, unreach_until}
## {id, kind:"boulder", cell, alive, des, claim, unreach_until}, plus on a site map `ore` ("coal" or
## "iron") for an ore block, `hidden` for one nobody has found yet, which stands as plain rock, and
## `loose` for one under a loose ceiling (issue #110).
var boulders: Array = []
## The animals (issues #42, #138): sheep, and cows and pigs at the meadow. The field keeps its first name.
##   {id, kind:"animal", species, pos, cell, dest, wait, alive, des, claim, unreach_until}
var sheep: Array = []
var bushes: Array = []       ## {id, kind:"bush", cell, berries, regrow}: berry bushes (issue #44)
var items := {}              ## Vector2i -> {cell, type, n, res}
var wear := {}               ## Vector2i -> how worn the ground is from being walked on: the village's paths (issue #196).
var wear_touched := {}       ## Cells stepped on since the last decay (not saved).
var zone := {}               ## Vector2i -> true: stockpile cells
var zone_res := {}           ## Vector2i -> resident id hauling into that cell
var farm := {}               ## Vector2i -> {id, kind:"crop", cell, grow, claim, unreach_until}: farm plots (issue #45)
var sites: Array = []        ## Construction sites and finished buildings.
# Site maps (issue #102).
var rock := {}               ## Vector2i -> true: rock walls, which can't be mined.
var torches: Array = []      ## Rock cells with a torch on them; tunnels beyond their light are dark.
var entrance := Vector2i.ZERO  ## Where a party arrives and leaves.
var known := true            ## Shown in the map switcher. A site becomes known before anyone goes.
var visited := false         ## Someone has been there, so its site report has real estimates.
var found := false           ## Its hidden find (the old mine's iron) has been found (issue #111).
var discovered := false      ## And surveyed, so it's a known resource with an estimate.
var diamond_found := false   ## Someone has mined next to a hidden diamond here, so diamonds are a known resource of this level (issue #186).
var ledges: Array = []       ## Cells with a drop someone can fall from in the dark (issue #110).
# The old mine's levels (issue #132).
var level := 0               ## 1 for the old mine, 2 and on for the levels below it; 0 for any other map.
var pattern := ""            ## The level's pattern family (MineLevels.FAMILIES, or "workings" for Level 1).
var door := Vector2i(-1, -1) ## The door down at the far end: a rock cell the party opens from the cell in front.
var door_state := ""         ## "closed" until the party reaches it, "found" once it has, "open" once it's opened.
# Route maps (Slice 4, issues #118, #119).
var water := {}              ## Vector2i -> true: a stream, forded slowly until it's bridged.
var seen := 0                ## Segments of the route anyone knows, from the village end; the rest is fog.
# The meadow (Slice 3.5, issue #137).
var banks: Array = []        ## The pond's muddy bank: someone stepping onto it can slip.
var fences := {}             ## Vector2i -> true: old fences, which nobody walks through.
var regrow := {}             ## Species -> seconds toward its next animal, while it's below its herd.
## Pens (issue #139): {id, rect (fences included), gate, built: {cell: true}}. A pen is done once every
## cell round its edge is built: fences, which nobody walks through, and the gate, which only animals can't.
var pens: Array = []
var gates := {}              ## Vector2i -> true: built pen gates.

var occ := PackedByteArray()
var occ_dirty := true
var _dark := {}              ## Vector2i -> true for unlit open cells; worked out once, from the torches.


func _init(p_w := Tuning.MAP_W, p_h := Tuning.MAP_H) -> void:
	w = p_w
	h = p_h
	occ.resize(w * h)


const SAVED := ["id", "kind", "name", "w", "h", "rock", "torches", "entrance", "known", "visited", "found", "discovered", "diamond_found", "ledges", "water", "seen", "level", "pattern", "door", "door_state", "banks", "fences", "regrow", "pens", "gates", "wear"]


## The map as plain data. Reservations and job bookkeeping aren't saved (spec §2, Saving).
func save() -> Dictionary:
	var items_out := {}
	for k in items:
		var it: Dictionary = items[k].duplicate()
		it.res = 0
		items_out[k] = it
	var sites_out: Array = []
	for s in sites:
		var c: Dictionary = s.duplicate(true)
		c.incoming = {}
		c.builder = 0
		c.crafter = 0
		c.crafting = ""
		sites_out.append(c)
	var d := {"trees": trees.duplicate(true), "boulders": boulders.duplicate(true), "sheep": sheep.duplicate(true),
		"bushes": bushes.duplicate(true), "items": items_out, "zone": zone.duplicate(), "farm": farm.duplicate(true),
		"sites": sites_out}
	for k in SAVED:
		d[k] = get(k)
	return d


static func from_save(d: Dictionary) -> SimMap:
	var m := SimMap.new(d.w, d.h)
	for k in SAVED:
		if d.has(k):
			m.set(k, d[k])
	m.trees = d.trees.duplicate(true)
	m.boulders = d.boulders.duplicate(true)
	m.sheep = d.get("sheep", []).duplicate(true)
	m.bushes = d.get("bushes", []).duplicate(true)
	m.items = d.items.duplicate(true)
	m.zone = d.zone.duplicate()
	m.farm = d.get("farm", {}).duplicate(true)
	m.sites = d.sites.duplicate(true)
	m.pens = d.get("pens", []).duplicate(true)
	for o in m.trees + m.boulders + m.sheep + m.farm.values():
		o.claim = 0
		o.unreach_until = 0
	for a in m.sheep:  # nobody is leading them any more (issue #139)
		a.erase("led_by")
		a.erase("led_to")
	return m


# ---------------------------------------------------------------- growing the map (issue #187)

## Grows the map by `depth` cells along an edge ("north", "south", "east" or "west") and returns the
## offset every existing coordinate moved by: zero for south and east, which only extend it, and
## the strip's depth for north and west, which move the origin.
func grow(edge: String, depth: int) -> Vector2i:
	var off := Vector2i.ZERO
	match edge:
		"north":
			off = Vector2i(0, depth)
			h += depth
		"south":
			h += depth
		"west":
			off = Vector2i(depth, 0)
			w += depth
		"east":
			w += depth
	occ.resize(w * h)
	occ_dirty = true
	_dark = {}
	if off != Vector2i.ZERO:
		shift(off)
	return off


## Moves every coordinate on the map by `off`, in one pass, so a claim on the north or west edge
## leaves the village exactly as it was, only further from the origin. Anything with a cell lives
## here: trees, boulders, animals (cell, position and where they're heading), bushes, stacks, the
## stockpile and its reservations, farm plots, sites and their plots, pens, gates, and the terrain
## sets a site map has. A chest slot (issue #189) is keyed off the map and stays put, but its door
## cell moves. Nothing that holds a cell is left behind: jobs, which aren't saved, are failed first.
func shift(off: Vector2i) -> void:
	var offf := Vector2(off)
	for o in trees + boulders + bushes:
		o.cell += off
	for a in sheep:
		a.cell += off
		a.pos += offf
		if a.get("dest") != null:  # the cell it's wandering to
			a.dest += off
	var moved := {}
	for k in items:
		var it: Dictionary = items[k]
		if k.x < 0:  # a chest slot
			it.at += off
			moved[k] = it
		else:
			it.cell += off
			moved[k + off] = it
	items = moved
	zone = _shifted_keys(zone, off)
	zone_res = _shifted_keys(zone_res, off)
	var plots := {}
	for k in farm:
		farm[k].cell += off
		plots[k + off] = farm[k]
	farm = plots
	for s in sites:
		s.origin += off
		if s.has("area"):  # a workstation's painted work area (issue #203)
			s.area = _shifted_keys(s.area, off)
		if s.get("plot") != null:
			s.plot.position += off
	for p in pens:
		p.rect.position += off
		p.gate += off
		p.built = _shifted_keys(p.get("built", {}), off)
	gates = _shifted_keys(gates, off)
	wear = _shifted_keys(wear, off)
	wear_touched = {}
	rock = _shifted_keys(rock, off)
	water = _shifted_keys(water, off)
	fences = _shifted_keys(fences, off)
	for i in torches.size():
		torches[i] += off
	for i in banks.size():
		banks[i] += off
	for i in ledges.size():
		ledges[i] += off
	entrance += off
	_dark = {}
	occ_dirty = true


func _shifted_keys(d: Dictionary, off: Vector2i) -> Dictionary:
	var out := {}
	for k in d:
		out[k + off] = d[k]
	return out


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


## True for an open cell no torch lights (issue #102). Always false in the village.
func is_dark(c: Vector2i) -> bool:
	if torches.is_empty():
		return false
	if _dark.is_empty():
		for x in w:
			for y in h:
				var p := Vector2i(x, y)
				if not rock.has(p) and not torches.any(func(t): return Vector2(t).distance_to(Vector2(p)) <= Tuning.TORCH_LIGHT):
					_dark[p] = true
		_dark[Vector2i(-1, -1)] = false  # worked out, even if every cell is lit
	return _dark.get(c, false)
