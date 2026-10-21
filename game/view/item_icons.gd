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
		"coal":  # dark lumps, edged in chalk so they read on the slate
			for p in [Vector2(24, 36), Vector2(40, 30), Vector2(34, 46)]:
				_disc(img, p, 13, Palette.CHALK_DIM)
			for p in [Vector2(24, 36), Vector2(40, 30), Vector2(34, 46)]:
				_disc(img, p, 10, c)
			_disc(img, Vector2(37, 27), 3, c.lightened(0.35))
		"iron_ore":  # a chunk of stone with rusty flecks
			_disc(img, Vector2(32, 34), 23, dark)
			_disc(img, Vector2(32, 34), 20, Palette.STONE)
			for p in [Vector2(24, 28), Vector2(38, 26), Vector2(30, 42), Vector2(42, 40)]:
				_disc(img, p, 5, c)
		"iron_ingot":  # a bar seen from above at a slant, its top face lighter
			_box(img, Rect2i(8, 22, 48, 26), dark)
			_box(img, Rect2i(11, 25, 42, 20), c.darkened(0.2))
			_box(img, Rect2i(15, 25, 34, 10), c)
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
		"wood_axe", "stone_axe":
			_handle(img)
			_box(img, Rect2i(30, 8, 22, 22), dark)
			_box(img, Rect2i(33, 11, 16, 16), c)
		"wood_pick", "stone_pick":
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
