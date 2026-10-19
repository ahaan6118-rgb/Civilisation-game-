class_name Assets
extends RefCounted

const FOLDER := "res://assets/"
const EXTENSIONS := ["png", "webp", "jpg", "jpeg", "svg"]

static var _cache: Dictionary = {}


# Crops away fully transparent borders so small sprites on big canvases fill their slot.
static func _trimmed(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	var used := img.get_used_rect()
	if used.size == Vector2i.ZERO or used.size == img.get_size():
		return tex
	return ImageTexture.create_from_image(img.get_region(used))


# Looks up art by its literal name, e.g. "Stone House" finds Stone House.png, stone_house.png or stone house.png.
static func texture(display_name: String) -> Texture2D:
	if _cache.has(display_name):
		return _cache[display_name]
	var tex: Texture2D = null
	var names := [display_name, display_name.to_lower(), display_name.to_snake_case(), display_name.to_lower().replace(" ", "_")]
	for n in names:
		for ext in EXTENSIONS:
			var path := "%s%s.%s" % [FOLDER, n, ext]
			if ResourceLoader.exists(path):
				tex = _trimmed(load(path))
				break
		if tex:
			break
	_cache[display_name] = tex
	return tex
