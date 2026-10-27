class_name Claims
extends RefCounted
## Land claimed at the village's edges (issue #187): which strip a claim would add, and what's on it.
## A strip is generated from the game's seed and its claim number alone, never the sim's live random
## numbers, so the same village claims the same land however long it took to get there.

const EDGES := ["north", "south", "east", "west"]

const TREE_CHANCE := 0.15
const BOULDER_CHANCE := 0.05
const BUSH_CHANCE := 0.012
const SHEEP_MAX := 3
const SHEEP_CHANCE := 0.01


## The strip a claim on `edge` would add to a village `w` by `h`, in the village's present
## coordinates: outside the map, `Tuning.CLAIM_DEPTH` cells deep.
static func strip(edge: String, w: int, h: int) -> Rect2i:
	var d := Tuning.CLAIM_DEPTH
	match edge:
		"north": return Rect2i(0, -d, w, d)
		"south": return Rect2i(0, h, w, d)
		"west": return Rect2i(-d, 0, d, h)
		_: return Rect2i(w, 0, d, h)


## Whether a village `w` by `h` can take a strip on `edge` without passing the maximum size.
static func fits(edge: String, w: int, h: int) -> bool:
	if edge in ["north", "south"]:
		return h + Tuning.CLAIM_DEPTH <= Tuning.MAP_MAX
	return w + Tuning.CLAIM_DEPTH <= Tuning.MAP_MAX


## What's on the strip, as {trees: [cells], boulders: [cells], bushes: [cells], sheep: [cells]}. The
## cells are in the strip's own coordinates (`strip()`), and `lane` rows or columns stay clear. Claim
## number `index` and `seed` fix it completely.
static func generate(seed: int, index: int, rect: Rect2i, lane: Rect2i) -> Dictionary:
	var g := RandomNumberGenerator.new()
	g.seed = hash([seed, index, rect.position.x, rect.position.y])
	var out := {"trees": [], "boulders": [], "bushes": [], "sheep": []}
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var c := Vector2i(x, y)
			var roll := g.randf()
			if lane.has_point(c):
				continue
			if roll < TREE_CHANCE:
				out.trees.append(c)
			elif roll < TREE_CHANCE + BOULDER_CHANCE:
				out.boulders.append(c)
			elif roll < TREE_CHANCE + BOULDER_CHANCE + BUSH_CHANCE:
				out.bushes.append(c)
			elif roll < TREE_CHANCE + BOULDER_CHANCE + BUSH_CHANCE + SHEEP_CHANCE and out.sheep.size() < SHEEP_MAX:
				out.sheep.append(c)
	return out
