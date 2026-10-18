class_name InvasionMapView
extends Control

signal tile_clicked(tile: Vector2i)
signal tile_hovered(tile: Vector2i)

const OWNER_TINT := 0.7

var map: InvasionMap
var terrain_colors: Array = []
var _image: Image
var _texture: ImageTexture
var _labels: Array = []


func setup(m: InvasionMap, colors: Array) -> void:
	map = m
	terrain_colors = colors
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	_image = Image.create(m.width, m.height, false, Image.FORMAT_RGB8)
	_texture = ImageTexture.create_from_image(_image)
	redraw_map()


func redraw_map() -> void:
	var sums: Array = []
	for n in map.nations:
		sums.append([Vector2.ZERO, 0])
	for i in map.owners.size():
		var c: Color = terrain_colors[map.terrain[i]]
		var o := map.owners[i]
		if o >= 0:
			c = c.lerp(map.nations[o]["color"], OWNER_TINT)
			if map.is_border(i):
				c = c.darkened(0.45)
			sums[o][0] += Vector2(i % map.width, i / map.width)
			sums[o][1] += 1
		_image.set_pixel(i % map.width, i / map.width, c)
	_texture.update(_image)
	_labels.clear()
	for idx in map.nations.size():
		if sums[idx][1] > 0:
			_labels.append([idx, sums[idx][0] / sums[idx][1] + Vector2(0.5, 0.5)])
	queue_redraw()


func _map_rect() -> Rect2:
	var scale := minf(size.x / map.width, size.y / map.height)
	var drawn := Vector2(map.width, map.height) * scale
	return Rect2((size - drawn) / 2.0, drawn)


func _draw() -> void:
	if map == null:
		return
	var rect := _map_rect()
	draw_texture_rect(_texture, rect, false)
	var font := ThemeDB.fallback_font
	var scale := rect.size.x / map.width
	for entry in _labels:
		var n: Dictionary = map.nations[entry[0]]
		var pos: Vector2 = rect.position + entry[1] * scale
		var text := "%s\n%s" % [n["name"], NumFormat.fmt(n["troops"])]
		draw_multiline_string_outline(font, pos - Vector2(60, 8), text, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, -1, 4, Color.BLACK)
		draw_multiline_string(font, pos - Vector2(60, 8), text, HORIZONTAL_ALIGNMENT_CENTER, 120, 14)


func _gui_input(event: InputEvent) -> void:
	if map == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var tile := tile_at(event.position)
		if map.in_bounds(tile):
			tile_clicked.emit(tile)
	elif event is InputEventMouseMotion:
		tile_hovered.emit(tile_at(event.position))


func tile_at(pos: Vector2) -> Vector2i:
	var rect := _map_rect()
	var local := (pos - rect.position) / rect.size * Vector2(map.width, map.height)
	return Vector2i(floori(local.x), floori(local.y))
