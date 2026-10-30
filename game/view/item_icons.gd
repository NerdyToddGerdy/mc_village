class_name ItemIcons
extends RefCounted
## Small code-drawn item icons for the Craft panel's slots (issue #95), in the chalk-mark style: each
## shape has a dark under-stroke so it reads on the slate. Our own drawings, not Minecraft's art.

static var _cache := {}


static func icon(type: String) -> ImageTexture:
	if not _cache.has(type):
		var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		_draw(img, type)
		_cache[type] = ImageTexture.create_from_image(img)
	return _cache[type]


static func _draw(img: Image, type: String) -> void:
	var dark := Palette.SLATE_DEEP
	var c: Color = Palette.ITEM_COLORS.get(type, Palette.CHALK)
	match type:
		"log":  # a log end: bark ring, pale wood and a growth ring
			_disc(img, Vector2(32, 32), 24, dark)
			_disc(img, Vector2(32, 32), 21, c)
			_disc(img, Vector2(32, 32), 15, Palette.PLANK)
			_ring(img, Vector2(32, 32), 8, 2.0, c)
		"plank":  # a board with its grain
			_box(img, Rect2i(8, 18, 48, 28), dark)
			_box(img, Rect2i(11, 21, 42, 22), c)
			_line(img, Vector2(14, 29), Vector2(50, 29), 2, c.darkened(0.25))
			_line(img, Vector2(14, 36), Vector2(42, 36), 2, c.darkened(0.25))
		"stick":
			_line(img, Vector2(16, 50), Vector2(48, 14), 11, dark)
			_line(img, Vector2(16, 50), Vector2(48, 14), 6, c)
		"cobble":  # a few stones packed together
			for p in [Vector2(22, 26), Vector2(41, 24), Vector2(30, 42), Vector2(46, 41)]:
				_disc(img, p, 12, dark)
			for p in [Vector2(22, 26), Vector2(41, 24), Vector2(30, 42), Vector2(46, 41)]:
				_disc(img, p, 9, c.lightened(0.1 if p.x > 35 else 0.0))
		"chest":  # a plank chest with a dark band and a latch (issue #189)
			_box(img, Rect2i(8, 16, 48, 36), dark)
			_box(img, Rect2i(11, 19, 42, 30), c)
			_box(img, Rect2i(11, 29, 42, 4), dark)
			_box(img, Rect2i(28, 27, 8, 10), Palette.CHALK)
		"stone_brick":  # two courses of dressed stone, offset like a wall (issue #178)
			for row in [[Rect2i(6, 14, 26, 16), Rect2i(34, 14, 24, 16)], [Rect2i(6, 34, 14, 16), Rect2i(22, 34, 26, 16), Rect2i(50, 34, 8, 16)]]:
				for rc in row:
					_box(img, rc, dark)
					_box(img, rc.grow(-3), c)
		"sapling":  # a thin stem with two leaves (issue #177)
			_line(img, Vector2(32, 54), Vector2(32, 22), 9, dark)
			_line(img, Vector2(32, 54), Vector2(32, 22), 4, Palette.LOG)
			for p in [Vector2(22, 24), Vector2(42, 18)]:
				_ellipse(img, p, Vector2(13, 9), dark)
			for p in [Vector2(22, 24), Vector2(42, 18)]:
				_ellipse(img, p, Vector2(10, 6), c)
		"coal", "obsidian", "flint":  # dark lumps, edged in chalk so they read on the slate
			for p in [Vector2(24, 36), Vector2(40, 30), Vector2(34, 46)]:
				_disc(img, p, 13, Palette.CHALK_DIM)
			for p in [Vector2(24, 36), Vector2(40, 30), Vector2(34, 46)]:
				_disc(img, p, 10, c)
			_disc(img, Vector2(37, 27), 3, c.lightened(0.35))
		"iron_ore", "gold_ore", "lapis", "redstone":  # a chunk of stone with flecks of the metal or gem
			_disc(img, Vector2(32, 34), 23, dark)
			_disc(img, Vector2(32, 34), 20, Palette.STONE)
			for p in [Vector2(24, 28), Vector2(38, 26), Vector2(30, 42), Vector2(42, 40)]:
				_disc(img, p, 5, c)
		"iron_ingot", "gold_ingot":  # a bar seen from above at a slant, its top face lighter
			_box(img, Rect2i(8, 22, 48, 26), dark)
			_box(img, Rect2i(11, 25, 42, 20), c.darkened(0.2))
			_box(img, Rect2i(15, 25, 34, 10), c)
		"diamond":  # a cut stone: a kite of facets, its top lighter
			_disc(img, Vector2(32, 34), 22, dark)
			_box(img, Rect2i(20, 22, 24, 24), c.darkened(0.15))
			_box(img, Rect2i(26, 16, 12, 34), c.darkened(0.15))
			_box(img, Rect2i(24, 20, 16, 14), c)
			_box(img, Rect2i(28, 22, 8, 6), c.lightened(0.45))
		"rail":  # two rails across three sleepers
			for y in [18, 32, 46]:
				_box(img, Rect2i(10, y - 5, 44, 10), dark)
				_box(img, Rect2i(12, y - 3, 40, 6), Palette.LOG)
			for x in [22, 42]:
				_box(img, Rect2i(x - 4, 8, 8, 48), dark)
				_box(img, Rect2i(x - 2, 10, 4, 44), c)
		"minecart":  # an open tub on two wheels
			_box(img, Rect2i(8, 18, 48, 28), dark)
			_box(img, Rect2i(11, 21, 42, 22), c)
			_box(img, Rect2i(15, 21, 34, 6), c.darkened(0.35))
			for x in [20.0, 44.0]:
				_disc(img, Vector2(x, 48), 8, dark)
				_disc(img, Vector2(x, 48), 5, Palette.CHALK_DIM)
		"wheat":  # three stalks with heads
			for x in [22.0, 32.0, 42.0]:
				_line(img, Vector2(x, 54), Vector2(x, 26), 6, dark)
				_line(img, Vector2(x, 54), Vector2(x, 26), 3, c.darkened(0.2))
				_disc(img, Vector2(x, 20), 7, dark)
				_disc(img, Vector2(x, 20), 5, c)
		"wool":  # a fleece: overlapping curls
			for p in [Vector2(22, 30), Vector2(36, 24), Vector2(44, 36), Vector2(28, 42), Vector2(38, 44)]:
				_disc(img, p, 13, dark)
			for p in [Vector2(22, 30), Vector2(36, 24), Vector2(44, 36), Vector2(28, 42), Vector2(38, 44)]:
				_disc(img, p, 10, c)
		"leather":  # a hide, stretched out, with a stitched edge
			_ellipse(img, Vector2(32, 32), Vector2(24, 19), dark)
			_ellipse(img, Vector2(32, 32), Vector2(21, 16), c)
			for p in [Vector2(14, 22), Vector2(50, 22), Vector2(14, 42), Vector2(50, 42)]:
				_disc(img, p, 6, dark)
				_disc(img, p, 4, c)
			_ring(img, Vector2(32, 32), 11, 1.5, c.lightened(0.3))
		"leather_cap":  # a rounded cap with a brim (issue #140)
			_ellipse(img, Vector2(32, 34), Vector2(22, 18), dark)
			_box(img, Rect2i(8, 34, 48, 14), dark)
			_ellipse(img, Vector2(32, 34), Vector2(19, 15), c)
			_box(img, Rect2i(11, 36, 42, 9), c.darkened(0.15))
		"leather_tunic":  # a tunic: body and short sleeves
			_box(img, Rect2i(8, 10, 48, 20), dark)
			_box(img, Rect2i(17, 10, 30, 46), dark)
			_box(img, Rect2i(11, 13, 42, 14), c)
			_box(img, Rect2i(20, 13, 24, 40), c)
			_line(img, Vector2(32, 14), Vector2(32, 50), 2, c.darkened(0.3))
		"leather_trousers":  # two legs from a waistband
			_box(img, Rect2i(14, 8, 36, 14), dark)
			_box(img, Rect2i(14, 8, 16, 48), dark)
			_box(img, Rect2i(34, 8, 16, 48), dark)
			_box(img, Rect2i(17, 11, 30, 8), c.darkened(0.15))
			_box(img, Rect2i(17, 19, 10, 34), c)
			_box(img, Rect2i(37, 19, 10, 34), c)
		"leather_boots":  # a pair of boots
			for x in [10, 34]:
				_box(img, Rect2i(x, 14, 14, 36), dark)
				_box(img, Rect2i(x, 38, 22, 14), dark)
				_box(img, Rect2i(x + 3, 17, 8, 30), c)
				_box(img, Rect2i(x + 3, 41, 16, 8), c.darkened(0.15))
		"beef", "cooked_beef":  # a thick steak with its fat edge
			_ellipse(img, Vector2(32, 34), Vector2(23, 17), dark)
			_ellipse(img, Vector2(32, 34), Vector2(20, 14), Palette.CHALK)
			_ellipse(img, Vector2(30, 33), Vector2(17, 11), c)
		"porkchop", "cooked_porkchop":  # a chop: a round of meat and a short bone
			_line(img, Vector2(36, 40), Vector2(52, 52), 9, dark)
			_line(img, Vector2(36, 40), Vector2(52, 52), 4, Palette.CHALK)
			_disc(img, Vector2(28, 28), 18, dark)
			_disc(img, Vector2(28, 28), 15, c)
			_disc(img, Vector2(24, 24), 5, c.lightened(0.25))
		"mutton", "cooked_mutton":  # a joint on the bone
			_line(img, Vector2(20, 46), Vector2(48, 18), 10, dark)
			_line(img, Vector2(20, 46), Vector2(48, 18), 5, Palette.CHALK)
			_disc(img, Vector2(26, 38), 16, dark)
			_disc(img, Vector2(26, 38), 13, c)
		"bread":  # a loaf with its scores
			_ellipse(img, Vector2(32, 34), Vector2(25, 16), dark)
			_ellipse(img, Vector2(32, 34), Vector2(22, 13), c)
			for x in [22.0, 32.0, 42.0]:
				_line(img, Vector2(x - 3, 40), Vector2(x + 3, 28), 2.5, c.darkened(0.3))
		"berries":
			for p in [Vector2(24, 36), Vector2(40, 36), Vector2(32, 24)]:
				_disc(img, p, 10, dark)
				_disc(img, p, 7, c)
		"wood_axe", "stone_axe", "iron_axe", "diamond_axe":
			_handle(img)
			_box(img, Rect2i(30, 8, 22, 22), dark)
			_box(img, Rect2i(33, 11, 16, 16), c)
		"wood_pick", "stone_pick", "iron_pick", "diamond_pick":
			_handle(img)
			_line(img, Vector2(14, 22), Vector2(50, 14), 11, dark)
			_line(img, Vector2(14, 22), Vector2(50, 14), 6, c)
		_:
			_disc(img, Vector2(32, 32), 16, dark)
			_disc(img, Vector2(32, 32), 13, c)


## A tool's stick handle, from the bottom left up to where the head sits.
static func _handle(img: Image) -> void:
	_line(img, Vector2(14, 54), Vector2(40, 18), 10, Palette.SLATE_DEEP)
	_line(img, Vector2(14, 54), Vector2(40, 18), 5, Palette.STICK)


static func _box(img: Image, r: Rect2i, col: Color) -> void:
	img.fill_rect(r, col)


static func _disc(img: Image, at: Vector2, radius: float, col: Color) -> void:
	_ellipse(img, at, Vector2(radius, radius), col)


static func _ellipse(img: Image, at: Vector2, radii: Vector2, col: Color) -> void:
	for y in range(maxi(int(at.y - radii.y), 0), mini(int(at.y + radii.y) + 1, 64)):
		for x in range(maxi(int(at.x - radii.x), 0), mini(int(at.x + radii.x) + 1, 64)):
			var d := Vector2((x + 0.5 - at.x) / radii.x, (y + 0.5 - at.y) / radii.y)
			if d.length_squared() <= 1.0:
				img.set_pixel(x, y, col)


static func _ring(img: Image, at: Vector2, radius: float, width: float, col: Color) -> void:
	for y in 64:
		for x in 64:
			if absf(Vector2(x + 0.5, y + 0.5).distance_to(at) - radius) <= width / 2.0:
				img.set_pixel(x, y, col)


static func _line(img: Image, a: Vector2, b: Vector2, width: float, col: Color) -> void:
	MarkTextures._line(img, a, b, width, col)
