class_name Assets
extends RefCounted

const FOLDER := "res://assets/"
const EXTENSIONS := ["png", "webp", "jpg", "jpeg", "svg"]

static var _cache: Dictionary = {}


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
				tex = load(path)
				break
		if tex:
			break
	_cache[display_name] = tex
	return tex
