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


const SAVED := ["id", "kind", "name", "w", "h", "rock", "torches", "entrance", "known", "visited", "found", "discovered", "ledges", "water", "seen", "level", "pattern", "door", "door_state", "banks", "fences", "regrow", "pens", "gates"]


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
