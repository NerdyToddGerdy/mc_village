class_name BlockTextures
extends RefCounted
## The blocks' pixel textures (issue #206): 16×16 patterns drawn in code, our own and not Minecraft's
## art, packed as layers of one Texture2DArray for view/block.gdshader. Each texel is a shade around
## mid-grey that the shader multiplies by the block's colour, so Palette stays the source of colour
## and a pattern averages out to the plain colour from far away.

const SIZE := 16

# Layers. FLAT is plain mid-grey, so a block drawn without a finish looks as it always has.
const FLAT := 0
const GRASS := 1
const DIRT := 2
const BARK := 3
const RINGS := 4
const PLANK := 5
const LEAVES := 6
const STONE := 7
const COBBLE := 8
const BRICK := 9
const SHINGLE := 10
const WOOL := 11
const SOIL := 12
const CLOTH := 13
const FUR := 14

## How far a texel strays from mid-grey at most, as a fraction of the block's colour. Low, so chalk
## marks and outlines still read on every material (slice-1-spec.md §12, Contrast).
const CONTRAST := 0.34

## A block's finish: Vector3i(side layer, end layer, end axis). The end layer goes on the two faces
## across the end axis: 1 x, 2 y (the top), 3 z, or 0 for the box's longest. Side layers are laid in
## world space, so neighbouring blocks tile; end layers are fitted to the face, so rings sit centred.
const PLAIN := Vector3i(FLAT, FLAT, 0)
const LOG := Vector3i(BARK, RINGS, 0)          ## A trunk, post or log: grain along it, rings at its ends.
const STUMP := Vector3i(BARK, RINGS, 2)        ## A round of log standing on end: rings on top.
const CUT := Vector3i(RINGS, RINGS, 2)         ## The pale cut face on top of a round.
const BOARD := Vector3i(PLANK, PLANK, 0)
const GROUND := Vector3i(GRASS, GRASS, 0)
const EARTH := Vector3i(DIRT, DIRT, 0)
const FOLIAGE := Vector3i(LEAVES, LEAVES, 0)
const ROCK := Vector3i(STONE, STONE, 0)
const COBBLES := Vector3i(COBBLE, COBBLE, 0)
const BRICKS := Vector3i(BRICK, BRICK, 0)
const SHINGLES := Vector3i(SHINGLE, SHINGLE, 0)
const FLEECE := Vector3i(WOOL, WOOL, 0)
const TILLED := Vector3i(SOIL, SOIL, 0)
const CLOTHING := Vector3i(CLOTH, CLOTH, 0)  ## Residents' clothes (phase 4).
const HIDE := Vector3i(FUR, FUR, 0)          ## Leather, and the cows' and pigs' coats.

static var _array: Texture2DArray


## Every layer, built once.
static func array() -> Texture2DArray:
	if _array == null:
		var draws: Array[Callable] = [_flat, _grass, _dirt, _bark, _rings, _plank, _leaves, _stone, _cobble, _brick, _shingle, _wool, _soil, _cloth, _fur]
		var images: Array[Image] = []
		for i in draws.size():
			var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
			img.fill(Color(0.5, 0.5, 0.5))
			var rng := RandomNumberGenerator.new()
			rng.seed = 206 * 100 + i
			draws[i].call(img, rng)
			_center(img)
			img.generate_mipmaps()
			images.append(img)
		_array = Texture2DArray.new()
		_array.create_from_images(images)
	return _array


## Sets a texel to a shade: -1 darkest, 0 the plain colour, 1 lightest. Wraps, so patterns tile.
static func _px(img: Image, x: int, y: int, shade: float) -> void:
	var v := 0.5 * (1.0 + CONTRAST * clampf(shade, -1.0, 1.0))
	img.set_pixel(posmod(x, SIZE), posmod(y, SIZE), Color(v, v, v))


## Shifts a layer so it averages exactly mid-grey: a block keeps its palette colour overall, and far
## away (where the mipmaps blend the pattern away) it looks just as it did untextured.
static func _center(img: Image) -> void:
	var sum := 0.0
	for y in SIZE:
		for x in SIZE:
			sum += img.get_pixel(x, y).r
	var shift := 0.5 - sum / (SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var v := img.get_pixel(x, y).r + shift
			img.set_pixel(x, y, Color(v, v, v))


static func _shade(img: Image, x: int, y: int) -> float:
	return (img.get_pixel(posmod(x, SIZE), posmod(y, SIZE)).r / 0.5 - 1.0) / CONTRAST


static func _noise(img: Image, rng: RandomNumberGenerator, amount: float) -> void:
	for y in SIZE:
		for x in SIZE:
			_px(img, x, y, rng.randf_range(-amount, amount))


static func _flat(_img: Image, _rng: RandomNumberGenerator) -> void:
	pass


## Short darker blades with a lighter tip, scattered over a slightly mottled lawn.
static func _grass(img: Image, rng: RandomNumberGenerator) -> void:
	_noise(img, rng, 0.25)
	for i in 14:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		_px(img, x, y, -0.9)
		_px(img, x, y - 1, 0.7)


## Fine speckle with a few pale pebbles.
static func _dirt(img: Image, rng: RandomNumberGenerator) -> void:
	_noise(img, rng, 0.45)
	for i in 6:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		_px(img, x, y, 0.9)
		_px(img, x + 1, y, 0.6)


## Bark: grooves running along the trunk (the texture's v), each column its own shade.
static func _bark(img: Image, rng: RandomNumberGenerator) -> void:
	var cols: Array[float] = []
	for x in SIZE:
		cols.append(rng.randf_range(-0.3, 0.4))
	for x in SIZE:
		for y in SIZE:
			_px(img, x, y, cols[x] + rng.randf_range(-0.15, 0.15))
	for i in 5:  # dark grooves, each broken partway along
		var x := rng.randi_range(0, SIZE - 1)
		var y0 := rng.randi_range(0, SIZE - 1)
		for k in rng.randi_range(6, 12):
			_px(img, x, y0 + k, -1.0)


## A cut end: bark round the rim and growth rings round the heart, fitted to the face.
static func _rings(img: Image, rng: RandomNumberGenerator) -> void:
	var c := Vector2(SIZE / 2.0, SIZE / 2.0)
	for y in SIZE:
		for x in SIZE:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length()
			var edge := x == 0 or y == 0 or x == SIZE - 1 or y == SIZE - 1
			var shade := -1.0 if edge else (0.9 if int(d) % 3 != 0 else 0.1)
			_px(img, x, y, shade + rng.randf_range(-0.1, 0.1))
	_px(img, SIZE / 2, SIZE / 2, -0.6)


## Boards four texels wide along v, with dark seams between them and a staggered butt joint in each.
static func _plank(img: Image, rng: RandomNumberGenerator) -> void:
	for b in 4:
		var tone := rng.randf_range(-0.25, 0.25)
		var joint := rng.randi_range(0, SIZE - 1)
		for x in range(b * 4, b * 4 + 4):
			for y in SIZE:
				var shade := tone + rng.randf_range(-0.12, 0.12)
				if x == b * 4:
					shade = -0.95
				elif y == joint:
					shade = -0.7
				elif rng.randf() < 0.08:
					shade -= 0.35  # a grain fleck
				_px(img, x, y, shade)


## Clumps of leaves: lit 2×2 clusters over a mid-green mass, with dark gaps between them.
static func _leaves(img: Image, rng: RandomNumberGenerator) -> void:
	_noise(img, rng, 0.15)
	for i in 9:
		var cx := rng.randi_range(0, SIZE - 1)
		var cy := rng.randi_range(0, SIZE - 1)
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			_px(img, cx + d.x, cy + d.y, 0.85 if d == Vector2i.ZERO else 0.5)
	for i in 10:
		var gx := rng.randi_range(0, SIZE - 1)
		var gy := rng.randi_range(0, SIZE - 1)
		_px(img, gx, gy, -1.0)
		_px(img, gx + 1, gy, -0.75)


## Smooth, mottled stone with a crack or two.
static func _stone(img: Image, rng: RandomNumberGenerator) -> void:
	_noise(img, rng, 0.2)
	for i in 8:
		_px(img, rng.randi_range(0, SIZE - 1), rng.randi_range(0, SIZE - 1), rng.randf_range(-0.6, 0.6))
	for i in 2:
		var p := Vector2i(rng.randi_range(0, SIZE - 1), rng.randi_range(0, SIZE - 1))
		for k in rng.randi_range(4, 7):
			_px(img, p.x, p.y, -1.0)
			p += [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(1, -1)][rng.randi_range(0, 3)]


## Rounded stones set in dark joints: each texel belongs to its nearest stone, lit at its top-left.
static func _cobble(img: Image, rng: RandomNumberGenerator) -> void:
	var seeds: Array[Vector2] = []
	var tones: Array[float] = []
	for i in 9:
		seeds.append(Vector2(rng.randf_range(0, SIZE), rng.randf_range(0, SIZE)))
		tones.append(rng.randf_range(-0.35, 0.35))
	for y in SIZE:
		for x in SIZE:
			var p := Vector2(x + 0.5, y + 0.5)
			var best := 1e9
			var second := 1e9
			var which := 0
			for i in seeds.size():
				for o in [Vector2(0, 0), Vector2(SIZE, 0), Vector2(-SIZE, 0), Vector2(0, SIZE), Vector2(0, -SIZE)]:
					var d := p.distance_to(seeds[i] + o)
					if d < best:
						second = best
						best = d
						which = i
					elif d < second:
						second = d
			var shade := -1.0 if second - best < 0.9 else tones[which]
			_px(img, x, y, shade)
	for y in SIZE:  # a highlight on each stone's upper-left edge
		for x in SIZE:
			if _shade(img, x, y) > -0.9 and _shade(img, x - 1, y - 1) <= -0.9:
				_px(img, x, y, 0.8)


## Dressed stone bricks: courses four texels high, each offset by half a brick, in pale mortar.
static func _brick(img: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		var course := y / 4
		for x in SIZE:
			var shade := rng.randf_range(-0.15, 0.15)
			if y % 4 == 3 or (x + course % 2 * 4) % 8 == 7:
				shade = 0.85
			elif y % 4 == 2:
				shade -= 0.3  # the lower edge of each brick, in shadow
			_px(img, x, y, shade)


## Overlapping wooden shingles: rows four texels deep, split into staggered tiles, dark at their lower edge.
static func _shingle(img: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		var row := y / 4
		for x in SIZE:
			var shade := rng.randf_range(-0.2, 0.2) + (y % 4) * 0.1
			if y % 4 == 3:
				shade = -0.9
			elif (x + row % 2 * 3) % 6 == 0:
				shade = -0.6
			_px(img, x, y, shade)


## Soft, lumpy wool: big gentle blotches.
static func _wool(img: Image, rng: RandomNumberGenerator) -> void:
	_noise(img, rng, 0.15)
	for i in 8:
		var cx := rng.randi_range(0, SIZE - 1)
		var cy := rng.randi_range(0, SIZE - 1)
		var s := -0.45 if i % 2 == 0 else 0.4
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				_px(img, cx + dx, cy + dy, s * (0.6 if dx != 0 and dy != 0 else 1.0))


## Woven cloth: a fine weave, alternate threads a shade apart.
static func _cloth(img: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			_px(img, x, y, (0.35 if (x + y) % 2 == 0 else -0.35) + (0.25 if (x / 2 + y / 2) % 2 == 0 else -0.25) + rng.randf_range(-0.12, 0.12))


## A short coat: soft streaks running down, a few lighter hairs.
static func _fur(img: Image, rng: RandomNumberGenerator) -> void:
	for x in SIZE:
		var col := rng.randf_range(-0.3, 0.3)
		for y in SIZE:
			_px(img, x, y, col + rng.randf_range(-0.2, 0.2))
	for i in 10:
		var x := rng.randi_range(0, SIZE - 1)
		var y := rng.randi_range(0, SIZE - 1)
		for k in 3:
			_px(img, x, y + k, 0.8)


## Tilled earth: furrows running across, a dark trough and a lighter ridge.
static func _soil(img: Image, rng: RandomNumberGenerator) -> void:
	for y in SIZE:
		for x in SIZE:
			var shade := [-0.6, -0.1, 0.5, 0.1][y % 4] as float
			_px(img, x, y, shade + rng.randf_range(-0.25, 0.25))
