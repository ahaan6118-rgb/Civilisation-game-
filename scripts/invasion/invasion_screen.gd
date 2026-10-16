extends Control

const MAIN_SCENE := "res://scenes/main.tscn"
const TICK := 0.1
const REDRAW_INTERVAL := 0.2
const MAP_WIDTH := 96
const MAP_HEIGHT := 54
const PLAYER_COLOR := Color(0.25, 0.55, 1.0)
const TERRAIN_NAMES := ["Water", "Plains", "Forest", "Mountains"]

var map := InvasionMap.new()
var _country: Dictionary
var _view: InvasionMapView
var _troops_label: Label
var _nations_label: Label
var _hover_label: Label
var _hint_label: Label
var _slider: HSlider
var _slider_label: Label
var _result_panel: PanelContainer
var _result_label: Label
var _confirm_retreat: ConfirmationDialog
var _accum := 0.0
var _redraw_accum := 0.0
var _finished := false


func _ready() -> void:
	_country = GameData.find("country", Game.pending_invasion)
	if _country.is_empty():
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
		return
	var player := {
		"name": "You",
		"color": PLAYER_COLOR,
		"troops": Game.army_size(),
		"troop_mult": Game.mult("army:size"),
		"regen_mult": Game.mult("army:regen"),
		"attack_mult": Game.mult("army:attack"),
	}
	map.generate(MAP_WIDTH, MAP_HEIGHT, randi(), player, _country["enemies"])
	_build_ui()
	_refresh_hud()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.16)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	root.add_child(top)
	var title := Label.new()
	title.text = "Invading %s" % _country["name"]
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	_troops_label = Label.new()
	_troops_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_troops_label)
	_slider_label = Label.new()
	top.add_child(_slider_label)
	_slider = HSlider.new()
	_slider.min_value = 5
	_slider.max_value = 100
	_slider.step = 5
	_slider.value = 30
	_slider.custom_minimum_size.x = 160
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(func(_v): _refresh_hud())
	top.add_child(_slider)
	var retreat := Button.new()
	retreat.text = "Retreat"
	retreat.pressed.connect(func(): _confirm_retreat.popup_centered())
	top.add_child(retreat)

	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(middle)
	_view = InvasionMapView.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.tile_clicked.connect(_on_tile_clicked)
	_view.tile_hovered.connect(_on_tile_hovered)
	middle.add_child(_view)
	_view.setup(map)
	_nations_label = Label.new()
	_nations_label.custom_minimum_size.x = 200
	middle.add_child(_nations_label)

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	_hint_label = Label.new()
	_hint_label.text = "Click land next to your border to send troops into it."
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_hint_label)
	_hover_label = Label.new()
	bottom.add_child(_hover_label)

	_result_panel = PanelContainer.new()
	_result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_result_panel.visible = false
	add_child(_result_panel)
	var result_box := VBoxContainer.new()
	_result_panel.add_child(result_box)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 22)
	result_box.add_child(_result_label)
	var home := Button.new()
	home.text = "Return home"
	home.pressed.connect(_return_home)
	result_box.add_child(home)

	_confirm_retreat = ConfirmationDialog.new()
	_confirm_retreat.dialog_text = "Retreat? The invasion fails and the supplies are lost."
	_confirm_retreat.confirmed.connect(func(): _end(false); _return_home())
	add_child(_confirm_retreat)


func _process(delta: float) -> void:
	if _finished or _country.is_empty():
		return
	_accum += delta
	while _accum >= TICK:
		map.tick(TICK)
		_accum -= TICK
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		_view.redraw_map()
		_refresh_hud()
	var state := map.status()
	if state != "playing":
		_view.redraw_map()
		_end(state == "won")
		_result_label.text = "Victory! %s is yours.\n%s" % [_country["name"], _country["reward_desc"]] if state == "won" \
			else "Defeat. Your army was wiped out."
		_result_panel.visible = true
		_result_panel.reset_size()
		_result_panel.position = (size - _result_panel.size) / 2.0


func _end(won: bool) -> void:
	if _finished:
		return
	_finished = true
	Game.finish_invasion(won)


func _return_home() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)


func _refresh_hud() -> void:
	var you: Dictionary = map.nations[InvasionMap.PLAYER]
	_troops_label.text = "Troops: %s / %s    Attacking: %s    Land: %d%%" % [
		NumFormat.fmt(you["troops"]), NumFormat.fmt(map.max_troops(InvasionMap.PLAYER)),
		NumFormat.fmt(map.troops_attacking(InvasionMap.PLAYER)), roundi(map.land_share(InvasionMap.PLAYER) * 100.0)]
	_slider_label.text = "Send %d%%" % int(_slider.value)
	var lines: PackedStringArray = []
	for idx in map.nations.size():
		var n: Dictionary = map.nations[idx]
		var state := "%s troops, %d%% land" % [NumFormat.fmt(n["troops"]), roundi(map.land_share(idx) * 100.0)] if map.is_alive(idx) else "defeated"
		lines.append("%s\n  %s" % [n["name"], state])
	_nations_label.text = "\n".join(lines)


func _on_tile_clicked(tile: Vector2i) -> void:
	if _finished:
		return
	var target := map.owner_at(tile)
	if target == InvasionMap.PLAYER:
		_hint_label.text = "That's your land. Click land next to your border."
	elif target == InvasionMap.WATER:
		_hint_label.text = "Your troops can't swim."
	elif map.send_attack(InvasionMap.PLAYER, target, _slider.value / 100.0):
		var name: String = "neutral land" if target == InvasionMap.NEUTRAL else map.nations[target]["name"]
		_hint_label.text = "Attacking %s with %d%% of your troops." % [name, int(_slider.value)]
	elif not map.neighbours_of(InvasionMap.PLAYER).has(target):
		_hint_label.text = "You don't border that land yet."
	else:
		_hint_label.text = "Not enough troops."
	_refresh_hud()


func _on_tile_hovered(tile: Vector2i) -> void:
	if not map.in_bounds(tile):
		_hover_label.text = ""
		return
	var o := map.owner_at(tile)
	var terrain_name: String = TERRAIN_NAMES[map.terrain[tile.y * map.width + tile.x]]
	if o >= 0:
		_hover_label.text = "%s (%s)" % [map.nations[o]["name"], terrain_name]
	elif o == InvasionMap.NEUTRAL:
		_hover_label.text = "Unclaimed %s" % terrain_name
	else:
		_hover_label.text = terrain_name
