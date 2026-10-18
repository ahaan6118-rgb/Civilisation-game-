extends Control

const MAIN_SCENE := "res://scenes/main.tscn"
const BATTLE_SCENE := "res://scenes/invasion.tscn"
const NODE_RADIUS := 26.0
const PLAYER_COLOR := Color(0.25, 0.55, 1.0)
const TARGET_COLOR := Color(0.95, 0.6, 0.2)
const LOCKED_COLOR := Color(0.45, 0.45, 0.45)

var _tier := 0
var _selected := ""
var _bg: ColorRect
var _title: Label
var _map: Control
var _info: VBoxContainer
var _declare: Button
var _prev: Button
var _next: Button
var _refresh_timer := 0.0


func _ready() -> void:
	_tier = Game.current_tier()
	_build_ui()
	_show_tier()


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= 0.25:
		_refresh_timer = 0.0
		_refresh_info()


func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var back := Button.new()
	back.text = "Back home"
	back.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_SCENE))
	top.add_child(back)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_prev = Button.new()
	_prev.text = "< Smaller"
	_prev.pressed.connect(func(): _tier -= 1; _selected = ""; _show_tier())
	top.add_child(_prev)
	_next = Button.new()
	_next.text = "Bigger >"
	_next.pressed.connect(func(): _tier += 1; _selected = ""; _show_tier())
	top.add_child(_next)

	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(middle)
	_map = Control.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_map_input)
	middle.add_child(_map)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 330
	middle.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_info = VBoxContainer.new()
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_info)
	_declare = Button.new()
	_declare.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_declare.pressed.connect(_on_declare)
	box.add_child(_declare)

	var hint := Label.new()
	hint.text = "Click a land next to yours (orange) to see it, then declare war. Blue is yours."
	hint.modulate = Color(1, 1, 1, 0.7)
	root.add_child(hint)


func _show_tier() -> void:
	_tier = clampi(_tier, 0, WarData.TIERS.size() - 1)
	var tier: Dictionary = WarData.TIERS[_tier]
	_bg.color = WarData.STYLES[tier["style"]]["background"]
	_prev.disabled = _tier == 0
	_next.disabled = _tier >= WarData.TIERS.size() - 1 or not Game.tier_unlocked(_tier + 1)
	_map.queue_redraw()
	_refresh_info()


func _node_pos(node_id: String) -> Vector2:
	var tier: Dictionary = WarData.TIERS[_tier]
	var p: Array = tier["home"]
	if node_id != "home":
		p = WarData.find_target(node_id)["pos"]
	var inset := Vector2(70, 50)
	return inset + Vector2(p[0], p[1]) * (_map.size - inset * 2.0)


func _node_name(node_id: String) -> String:
	return WarData.TIERS[_tier]["home_name"] if node_id == "home" else WarData.find_target(node_id)["name"]


func _draw_map() -> void:
	var tier: Dictionary = WarData.TIERS[_tier]
	var ids: Array = ["home"]
	for t in tier["targets"]:
		ids.append(t["id"])
	var font := ThemeDB.fallback_font
	for a in ids:
		for b in WarData.neighbours(_tier, a):
			if a < b:
				_map.draw_line(_node_pos(a), _node_pos(b), Color(1, 1, 1, 0.18), 3.0)
	for id in ids:
		var owned: bool = id == "home" or Game.conquered.has(id)
		var color := PLAYER_COLOR if owned else (TARGET_COLOR if Game.can_attack(id) else LOCKED_COLOR)
		var pos := _node_pos(id)
		if id == _selected:
			_map.draw_circle(pos, NODE_RADIUS + 6, Color.WHITE)
		_map.draw_circle(pos, NODE_RADIUS, color)
		var art := Assets.texture(_node_name(id))
		if art:
			_map.draw_texture_rect(art, Rect2(pos - Vector2.ONE * NODE_RADIUS, Vector2.ONE * NODE_RADIUS * 2), false)
		var label := _node_name(id)
		_map.draw_string_outline(font, pos + Vector2(-90, NODE_RADIUS + 18), label, HORIZONTAL_ALIGNMENT_CENTER, 180, 14, 4, Color.BLACK)
		_map.draw_string(font, pos + Vector2(-90, NODE_RADIUS + 18), label, HORIZONTAL_ALIGNMENT_CENTER, 180, 14)
	if not Game.tier_unlocked(_tier):
		var msg := "Locked: needs %s and the previous map conquered." % GameData.resource_name(tier["requires"])
		if not Game.war_unlocked():
			msg = "Research Warfare to wage war."
		_map.draw_string_outline(font, Vector2(0, _map.size.y / 2), msg, HORIZONTAL_ALIGNMENT_CENTER, _map.size.x, 20, 5, Color.BLACK)
		_map.draw_string(font, Vector2(0, _map.size.y / 2), msg, HORIZONTAL_ALIGNMENT_CENTER, _map.size.x, 20, BAD_TEXT)


const BAD_TEXT := Color(1.0, 0.5, 0.45)


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for t in WarData.TIERS[_tier]["targets"]:
			if _node_pos(t["id"]).distance_to(event.position) <= NODE_RADIUS + 4:
				_selected = t["id"]
				_map.queue_redraw()
				_refresh_info()
				return


static func difficulty(target: Dictionary) -> String:
	var tier: Dictionary = WarData.TIERS[target["tier"]]
	var enemy: float = (InvasionMap.BASE_TROOPS + 29.0 * InvasionMap.TROOPS_PER_TILE) * target["power"] * tier["strength"] * InvasionMap.ENEMY_START_FRACTION
	var ratio: float = enemy / maxf(1.0, Game.army_size())
	if ratio < 0.5:
		return "Easy"
	if ratio < 1.0:
		return "Fair"
	if ratio < 2.0:
		return "Hard"
	if ratio < 4.0:
		return "Brutal"
	return "Suicidal"


func _refresh_info() -> void:
	var tier: Dictionary = WarData.TIERS[_tier]
	_title.text = "%s    Kardashev Type %.2f" % [tier["name"], Game.kardashev()]
	for child in _info.get_children():
		_info.remove_child(child)
		child.queue_free()
	var army := Label.new()
	army.text = "Your army: %s troops (%s)" % [NumFormat.fmt(Game.army_size()), tier["unit"]]
	_info.add_child(army)
	_info.add_child(HSeparator.new())
	_declare.visible = false
	if _selected == "":
		_add_text("Pick a land on the map.")
		return
	var t := WarData.find_target(_selected)
	var header := Label.new()
	header.text = t["name"]
	header.add_theme_font_size_override("font_size", 18)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(header)
	_add_text(t["desc"])
	if Game.conquered.has(_selected):
		_add_text("Conquered. It's yours.")
		return
	_add_text("Difficulty: %s" % difficulty(t))
	_add_text("Win: loot, +10% production and a stronger army for this run.")
	_declare.visible = true
	var cost := Game.war_cost()
	_declare.text = "Declare war\nSupplies: %s" % NumFormat.cost(cost)
	_declare.disabled = not Game.can_attack(_selected) or not Game.can_afford(cost)
	if not Game.can_attack(_selected):
		_add_text("You don't border them yet. Conquer a neighbour first." if Game.tier_unlocked(_tier) else "This map is locked.")


func _add_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(label)


func _on_declare() -> void:
	if Game.start_war(_selected):
		get_tree().change_scene_to_file(BATTLE_SCENE)
