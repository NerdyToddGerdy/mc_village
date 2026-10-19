class_name MarkTextures
extends RefCounted
## Small procedurally drawn textures for the chalk marks: every mark sits on a dark under-stroke so
## it reads on any block colour (spec §12, Contrast).

static var _cache := {}


static func slash() -> ImageTexture:
	return _cached("slash", func(img: Image) -> void:
		_line(img, Vector2(14, 50), Vector2(50, 14), 18.0, Palette.SLATE_DEEP)
		_line(img, Vector2(14, 50), Vector2(50, 14), 9.0, Palette.RED))


static func cross() -> ImageTexture:
	return _cached("cross", func(img: Image) -> void:
		for seg in [[Vector2(16, 16), Vector2(48, 48)], [Vector2(48, 16), Vector2(16, 48)]]:
			_line(img, seg[0], seg[1], 18.0, Palette.SLATE_DEEP)
		for seg in [[Vector2(16, 16), Vector2(48, 48)], [Vector2(48, 16), Vector2(16, 48)]]:
			_line(img, seg[0], seg[1], 9.0, Palette.RED))


static func flag() -> ImageTexture:
	return _cached("flag", func(img: Image) -> void:
		_line(img, Vector2(12, 62), Vector2(12, 6), 7.0, Palette.SLATE_DEEP)
		_line(img, Vector2(12, 62), Vector2(12, 6), 3.0, Palette.CHALK)
		img.fill_rect(Rect2i(13, 4, 40, 26), Palette.SLATE_DEEP)
		img.fill_rect(Rect2i(15, 6, 36, 22), Palette.YELLOW)
		img.fill_rect(Rect2i(31, 9, 4, 11), Palette.SLATE_DEEP)
		img.fill_rect(Rect2i(31, 22, 4, 4), Palette.SLATE_DEEP))


static func hatch() -> ImageTexture:
	return _cached("hatch", func(img: Image) -> void:
		img.fill(Color(Palette.GREEN, 0.18))
		for k in range(-64, 64, 16):
			_line(img, Vector2(k, 64), Vector2(k + 64, 0), 7.0, Palette.SLATE_DEEP)
			_line(img, Vector2(k, 64), Vector2(k + 64, 0), 3.5, Palette.GREEN))


static func _cached(key: String, draw: Callable) -> ImageTexture:
	if not _cache.has(key):
		var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		draw.call(img)
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


static func _line(img: Image, a: Vector2, b: Vector2, width: float, col: Color) -> void:
	var half := width / 2.0
	for y in img.get_height():
		for x in img.get_width():
			var p := Vector2(x + 0.5, y + 0.5)
			var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
			if d <= half:
				img.set_pixel(x, y, col)
