class_name InvasionMapView
extends Control

signal tile_clicked(tile: Vector2i)
signal tile_hovered(tile: Vector2i)

const OWNER_TINT := 0.7
const MIN_ZOOM := 1.0
const MAX_ZOOM := 12.0
const PAN_SPEED := 600.0
# A faction gets a label once it covers this many screen pixels.
const LABEL_AREA := 2500.0

var map: InvasionMap
var terrain_colors: Array = []
var zoom := 1.0
# Map tile at the centre of the view.
var center := Vector2.ZERO
var _image: Image
var _texture: ImageTexture
var _dragging := false


func setup(m: InvasionMap, colors: Array) -> void:
	map = m
	terrain_colors = colors
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	center = Vector2(m.width, m.height) / 2.0
	_image = Image.create(m.width, m.height, false, Image.FORMAT_RGB8)
	for i in m.owners.size():
		_paint(i)
	_texture = ImageTexture.create_from_image(_image)
	m.dirty.clear()
	queue_redraw()


# Repaints only the tiles that changed hands since last time.
func redraw_map() -> void:
	if map.dirty.is_empty():
		queue_redraw()
		return
	for i in map.dirty:
		_paint(i)
	map.dirty.clear()
	_texture.update(_image)
	queue_redraw()


func _paint(i: int) -> void:
	var c: Color = terrain_colors[map.terrain[i]]
	var o := map.owners[i]
	if o >= 0:
		c = c.lerp(map.nations[o]["color"], OWNER_TINT)
		if map.is_border(i):
			# Your borders glow so your land is easy to find on a huge map.
			c = Color(0.85, 0.95, 1.0) if o == InvasionMap.PLAYER else c.darkened(0.45)
	_image.set_pixel(i % map.width, i / map.width, c)


# Pixels per tile at zoom 1 (whole map fits).
func _fit_scale() -> float:
	return minf(size.x / map.width, size.y / map.height)


func _map_rect() -> Rect2:
	var scale := _fit_scale() * zoom
	var drawn := Vector2(map.width, map.height) * scale
	return Rect2(size / 2.0 - center * scale, drawn)


func focus_on(tile: Vector2, new_zoom: float) -> void:
	zoom = clampf(new_zoom, MIN_ZOOM, MAX_ZOOM)
	center = tile
	_clamp_center()
	queue_redraw()


func _clamp_center() -> void:
	var half := size / 2.0 / (_fit_scale() * zoom)
	var lo := half.min(Vector2(map.width, map.height) / 2.0)
	center.x = clampf(center.x, lo.x, map.width - lo.x)
	center.y = clampf(center.y, lo.y, map.height - lo.y)


func _process(delta: float) -> void:
	if map == null or not is_visible_in_tree():
		return
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1
	if move != Vector2.ZERO:
		center += move * PAN_SPEED * delta / (_fit_scale() * zoom)
		_clamp_center()
		queue_redraw()


func _draw() -> void:
	if map == null:
		return
	var rect := _map_rect()
	draw_texture_rect(_texture, rect, false)
	var font := ThemeDB.fallback_font
	var scale := rect.size.x / map.width
	var screen := Rect2(Vector2.ZERO, size)
	for idx in map.nations.size():
		var n: Dictionary = map.nations[idx]
		if n["tiles"] <= 0:
			continue
		# Big or important factions always get a label; small ones only when zoomed in enough.
		var important: bool = idx == InvasionMap.PLAYER or not n["minor"]
		if not important and n["tiles"] * scale * scale < LABEL_AREA:
			continue
		var pos: Vector2 = rect.position + map.label_pos(idx) * scale
		if not screen.has_point(pos):
			continue
		var font_size := 14 if important else 11
		var text := "%s\n%s" % [n["name"], NumFormat.fmt(n["troops"])]
		draw_multiline_string_outline(font, pos - Vector2(70, 8), text, HORIZONTAL_ALIGNMENT_CENTER, 140, font_size, -1, 4, Color.BLACK)
		draw_multiline_string(font, pos - Vector2(70, 8), text, HORIZONTAL_ALIGNMENT_CENTER, 140, font_size)


func _gui_input(event: InputEvent) -> void:
	if map == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				# Zoom toward the cursor.
				var before := _to_tile_f(event.position)
				zoom = clampf(zoom * (1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), MIN_ZOOM, MAX_ZOOM)
				center += before - _to_tile_f(event.position)
				_clamp_center()
				queue_redraw()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var tile := tile_at(event.position)
			if map.in_bounds(tile):
				tile_clicked.emit(tile)
	elif event is InputEventMouseMotion:
		if _dragging:
			center -= event.relative / (_fit_scale() * zoom)
			_clamp_center()
			queue_redraw()
		tile_hovered.emit(tile_at(event.position))


func _to_tile_f(pos: Vector2) -> Vector2:
	var rect := _map_rect()
	return (pos - rect.position) / rect.size * Vector2(map.width, map.height)


func tile_at(pos: Vector2) -> Vector2i:
	var t := _to_tile_f(pos)
	return Vector2i(floori(t.x), floori(t.y))
