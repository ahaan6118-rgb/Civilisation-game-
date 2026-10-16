extends Control

const REFRESH_INTERVAL := 0.2
const MAX_LOG_LINES := 5
const ICON_SIZE := Vector2(24, 24)
const BAD_COLOR := Color(1.0, 0.45, 0.4)
const GOOD_COLOR := Color(0.6, 1.0, 0.6)

var _columns: HBoxContainer
var _resource_list: VBoxContainer
var _job_list: VBoxContainer
var _pop_label: Label
var _tech_list: VBoxContainer
var _building_list: VBoxContainer
var _upgrade_list: VBoxContainer
var _craft_list: VBoxContainer
var _invasion_list: VBoxContainer
var _invade_button: Button
var _log_label: Label
var _confirm_wipe: ConfirmationDialog

var _resource_rows: Dictionary = {}
var _job_rows: Dictionary = {}
var _shop_buttons: Array = []
var _shop_signature := ""
var _commission_buttons: Array = []
var _craft_bars: Array = []
var _log: PackedStringArray = []
var _refresh_timer := 0.0


func _ready() -> void:
	_build_layout()
	Game.structure_changed.connect(_rebuild_lists)
	Game.message_posted.connect(_on_message)
	_log = Game.recent_messages.duplicate()
	_log_label.text = "\n".join(_log)
	_rebuild_lists()


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh()


# --- layout ----------------------------------------------------------------

func _build_layout() -> void:
	var bg_tex := Assets.texture("Background")
	if bg_tex:
		var bg := TextureRect.new()
		bg.texture = bg_tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
	else:
		var fill := ColorRect.new()
		fill.color = Color(0.16, 0.13, 0.1)
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(fill)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var root := VBoxContainer.new()
	margin.add_child(root)

	_columns = HBoxContainer.new()
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", 12)
	root.add_child(_columns)

	_resource_list = _make_panel("Resources", 1.0)

	var pop_column := _make_panel("Population", 1.2)
	_pop_label = Label.new()
	pop_column.add_child(_pop_label)
	pop_column.add_child(HSeparator.new())
	_job_list = VBoxContainer.new()
	pop_column.add_child(_job_list)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_stretch_ratio = 1.4
	tabs.custom_minimum_size.x = 450
	tabs.add_theme_font_size_override("font_size", 15)
	_columns.add_child(tabs)
	_tech_list = _make_tab(tabs, "Discoveries")
	_building_list = _make_tab(tabs, "Buildings")
	_upgrade_list = _make_tab(tabs, "Upgrades")
	_craft_list = _make_tab(tabs, "Crafting")
	_invasion_list = _make_tab(tabs, "Invasions")

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	_log_label = Label.new()
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.custom_minimum_size.y = 90
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	bottom.add_child(_log_label)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.size_flags_vertical = Control.SIZE_SHRINK_END
	save_button.pressed.connect(func(): SaveManager.save_game(); _on_message("Game saved."))
	bottom.add_child(save_button)
	var wipe_button := Button.new()
	wipe_button.text = "Wipe Save"
	wipe_button.size_flags_vertical = Control.SIZE_SHRINK_END
	wipe_button.pressed.connect(func(): _confirm_wipe.popup_centered())
	bottom.add_child(wipe_button)

	_confirm_wipe = ConfirmationDialog.new()
	_confirm_wipe.dialog_text = "Delete your save and start over?"
	_confirm_wipe.confirmed.connect(SaveManager.wipe)
	add_child(_confirm_wipe)


func _make_panel(title: String, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	_columns.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 20)
	box.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


func _make_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


func _icon(display_name: String) -> TextureRect:
	var tex := Assets.texture(display_name)
	if tex == null:
		return null
	var icon := TextureRect.new()
	icon.texture = tex
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# --- list building ---------------------------------------------------------

func _rebuild_lists() -> void:
	_rebuild_resources()
	_rebuild_jobs()
	_rebuild_shop()
	_rebuild_crafting()
	_rebuild_invasions()
	_refresh()


func _rebuild_resources() -> void:
	_clear(_resource_list)
	_resource_rows.clear()
	for r in GameData.RESOURCES:
		var id: String = r["id"]
		if not Game.is_unlocked(id):
			continue
		var row := HBoxContainer.new()
		var icon := _icon(r["name"])
		if icon:
			row.add_child(icon)
		var name_label := Label.new()
		name_label.text = r["name"]
		name_label.custom_minimum_size.x = 90
		row.add_child(name_label)
		var amount := Label.new()
		amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(amount)
		var rate := Label.new()
		row.add_child(rate)
		if r.get("clickable", false):
			var button := Button.new()
			button.text = "Gather"
			button.pressed.connect(func(): Game.click_gather(id); _refresh())
			row.add_child(button)
		_resource_list.add_child(row)
		_resource_rows[id] = {"amount": amount, "rate": rate}


func _rebuild_jobs() -> void:
	_clear(_job_list)
	_job_rows.clear()
	for job in GameData.JOBS:
		if not Game.job_available(job):
			continue
		var id: String = job["id"]
		var row := HBoxContainer.new()
		var icon := _icon(job["name"])
		if icon:
			row.add_child(icon)
		var name_label := Label.new()
		name_label.text = job["name"]
		name_label.custom_minimum_size.x = 110
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name_label)
		var output := Label.new()
		output.modulate = Color(1, 1, 1, 0.7)
		output.clip_text = true
		output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		output.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(output)
		var minus := Button.new()
		minus.text = "-"
		minus.custom_minimum_size = Vector2(32, 28)
		minus.tooltip_text = "Shift-click for 10"
		minus.pressed.connect(func(): Game.assign_job(id, -_step()))
		row.add_child(minus)
		var count := Label.new()
		count.custom_minimum_size.x = 40
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(count)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(32, 28)
		plus.tooltip_text = "Shift-click for 10"
		plus.pressed.connect(func(): Game.assign_job(id, _step()))
		row.add_child(plus)
		_job_list.add_child(row)
		_job_rows[id] = {"count": count, "output": output, "name": name_label}


func _step() -> int:
	return 10 if Input.is_key_pressed(KEY_SHIFT) else 1


func _available_signature() -> String:
	var ids: PackedStringArray = []
	for t in GameData.TECHS:
		if Game.tech_available(t):
			ids.append(t["id"])
	for u in GameData.UPGRADES:
		if Game.upgrade_available(u):
			ids.append(u["id"])
	return ",".join(ids)


func _rebuild_shop() -> void:
	_shop_signature = _available_signature()
	for list in [_tech_list, _building_list, _upgrade_list]:
		_clear(list)
	_shop_buttons.clear()
	for t in GameData.TECHS:
		if Game.tech_available(t):
			_add_shop_button(_tech_list, "tech", t)
	for b in GameData.BUILDINGS:
		if Game.building_available(b):
			_add_shop_button(_building_list, "building", b)
	for u in GameData.UPGRADES:
		if Game.upgrade_available(u):
			_add_shop_button(_upgrade_list, "upgrade", u)
	for list in [_tech_list, _building_list, _upgrade_list]:
		if list.get_child_count() == 0:
			var empty := Label.new()
			empty.text = "Nothing available yet."
			empty.modulate = Color(1, 1, 1, 0.5)
			list.add_child(empty)


func _add_shop_button(list: VBoxContainer, kind: String, entry: Dictionary) -> void:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.icon = Assets.texture(entry["name"])
	button.expand_icon = false
	button.add_theme_constant_override("icon_max_width", 32)
	button.tooltip_text = entry["desc"]
	if entry.get("flavor", "") != "":
		button.tooltip_text += "\n\"%s\"" % entry["flavor"]
	var id: String = entry["id"]
	match kind:
		"tech":
			button.pressed.connect(func(): Game.research(id))
		"building":
			button.pressed.connect(func(): Game.buy_building(id))
		"upgrade":
			button.pressed.connect(func(): Game.buy_upgrade(id))
	list.add_child(button)
	_shop_buttons.append({"button": button, "kind": kind, "entry": entry})


# --- refresh ---------------------------------------------------------------

func _refresh() -> void:
	for id in _resource_rows:
		var row: Dictionary = _resource_rows[id]
		row["amount"].text = NumFormat.fmt(Game.amounts[id])
		var rate: float = Game.rates.get(id, 0.0)
		var text := "%s%s/s" % ["+" if rate >= 0.0 else "", NumFormat.fmt(rate)]
		if Game.spoil_rates.get(id, 0.0) > 0.01:
			text += "  (rotting %s/s)" % NumFormat.fmt(Game.spoil_rates[id])
		row["rate"].text = text
		row["rate"].modulate = BAD_COLOR if rate < -0.005 else (GOOD_COLOR if rate > 0.005 else Color.WHITE)

	var food_use := Game.population * Game.food_per_second_per_person()
	var pop_text := "People: %d / %d    Idle: %d\nEating %s food/s" % [
		Game.population, Game.pop_cap(), Game.idle(), NumFormat.fmt(food_use)]
	if Game.starving:
		pop_text += "\nSTARVING! Assign Gatherers or gather food."
		_pop_label.modulate = BAD_COLOR
	else:
		_pop_label.modulate = Color.WHITE
	_pop_label.text = pop_text

	for id in _job_rows:
		var row: Dictionary = _job_rows[id]
		var job := GameData.find("job", id)
		row["count"].text = str(Game.jobs.get(id, 0))
		var m := Game.job_multiplier(id)
		var parts: PackedStringArray = []
		for res in job["produces"]:
			parts.append("+%s %s" % [NumFormat.fmt(job["produces"][res] * m), GameData.resource_name(res)])
		for res in job.get("consumes", {}):
			parts.append("-%s %s" % [NumFormat.fmt(job["consumes"][res]), GameData.resource_name(res)])
		var output := ", ".join(parts) + " each/s" if not parts.is_empty() else ""
		if job.has("note"):
			output = job["note"] + ("  " + output if output != "" else "")
		row["output"].text = output

	if _available_signature() != _shop_signature:
		_rebuild_shop()

	if _invade_button:
		var c := Game.next_country()
		_invade_button.text = "Launch invasion\nArmy: %s troops\nSupplies: %s" % [NumFormat.fmt(Game.army_size()), NumFormat.cost(c["cost"])]
		_invade_button.disabled = not Game.can_invade(c["id"])

	for item in _commission_buttons:
		var maker_id: String = item["maker"]
		var cost := Game.commission_cost(maker_id)
		var free := Game.maker_slots(maker_id) - Game.maker_busy(maker_id)
		item["button"].text = "Commission an item (%d free)\nCost: %s" % [free, NumFormat.cost(cost)]
		item["button"].disabled = free <= 0 or not Game.can_afford(cost)
	for item in _craft_bars:
		var craft: Dictionary = item["craft"]
		var bar: ProgressBar = item["bar"]
		bar.value = 1.0 - craft["remaining"] / craft["total"]
		item["label"].text = "Crafting... %s left" % NumFormat.duration(ceilf(craft["remaining"] / Game.mult("craft_speed")))

	for item in _shop_buttons:
		var button: Button = item["button"]
		var entry: Dictionary = item["entry"]
		var cost: Dictionary
		var title: String = entry["name"]
		if item["kind"] == "building":
			cost = Game.building_cost(entry["id"])
			title += " (%d)" % Game.buildings.get(entry["id"], 0)
		else:
			cost = entry["cost"]
		var text := "%s\n%s" % [title, entry["desc"]]
		if entry.get("flavor", "") != "":
			text += "\n\"%s\"" % entry["flavor"]
		button.text = text + "\nCost: " + NumFormat.cost(cost)
		button.disabled = not Game.can_afford(cost)


func _rebuild_crafting() -> void:
	_clear(_craft_list)
	_commission_buttons.clear()
	_craft_bars.clear()
	for maker in GameData.MAKERS:
		var maker_id: String = maker["id"]
		var slots := Game.maker_slots(maker_id)
		var header := Label.new()
		header.add_theme_font_size_override("font_size", 18)
		header.text = "%ss: %d" % [maker["name"], slots]
		_craft_list.add_child(header)
		if slots == 0:
			var hint := Label.new()
			hint.text = "Build an %s in the Buildings tab to start crafting." % maker["name"]
			hint.modulate = Color(1, 1, 1, 0.6)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_craft_list.add_child(hint)
			continue
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.tooltip_text = "Pay the cost to get a random item."
		button.pressed.connect(func(): Game.start_commission(maker_id))
		_craft_list.add_child(button)
		_commission_buttons.append({"button": button, "maker": maker_id})
		for craft in Game.crafts:
			if craft["maker"] != maker_id:
				continue
			var label := Label.new()
			_craft_list.add_child(label)
			var bar := ProgressBar.new()
			bar.max_value = 1.0
			bar.show_percentage = false
			bar.custom_minimum_size.y = 12
			_craft_list.add_child(bar)
			_craft_bars.append({"bar": bar, "label": label, "craft": craft})

	_craft_list.add_child(HSeparator.new())
	var collection := Label.new()
	collection.add_theme_font_size_override("font_size", 18)
	collection.text = "Collection (%d items)" % Game.total_items()
	_craft_list.add_child(collection)
	for it in GameData.ITEMS:
		var owned: int = Game.items.get(it["id"], 0)
		if owned == 0:
			continue
		var row := HBoxContainer.new()
		if it.get("flavor", "") != "":
			row.tooltip_text = "\"%s\"" % it["flavor"]
		var icon := _icon(it["name"])
		if icon:
			row.add_child(icon)
		var label := Label.new()
		label.text = "%s%s: %s" % [it["name"], "" if owned == 1 else " x%d" % owned, it["desc"]]
		label.modulate = GameData.RARITIES[it["rarity"]]["color"]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(label)
		_craft_list.add_child(row)

	var active := Game.active_synergies()
	var syn_header := Label.new()
	syn_header.add_theme_font_size_override("font_size", 18)
	syn_header.text = "Synergies (%d / %d found)" % [active.size(), GameData.SYNERGIES.size()]
	_craft_list.add_child(syn_header)
	for syn in active:
		var label := Label.new()
		label.text = "%s: %s" % [syn["name"], syn["desc"]]
		label.modulate = GOOD_COLOR
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_craft_list.add_child(label)
	if active.size() < GameData.SYNERGIES.size():
		var secret := Label.new()
		secret.text = "??? Some items work better together..."
		secret.modulate = Color(1, 1, 1, 0.5)
		_craft_list.add_child(secret)


func _rebuild_invasions() -> void:
	_clear(_invasion_list)
	_invade_button = null
	if not Game.invasion_unlocked():
		_add_wrapped(_invasion_list, "Research Warfare in the Discoveries tab to invade other countries.", Color(1, 1, 1, 0.6))
		return
	var c := Game.next_country()
	if c.is_empty():
		_add_wrapped(_invasion_list, "You have conquered every known country. For now.", GOOD_COLOR)
	else:
		var header := Label.new()
		header.text = "Next target: %s" % c["name"]
		header.add_theme_font_size_override("font_size", 18)
		_invasion_list.add_child(header)
		_add_wrapped(_invasion_list, c["desc"], Color.WHITE)
		_add_wrapped(_invasion_list, "Enemy nations: %d" % c["enemies"].size(), Color.WHITE)
		_add_wrapped(_invasion_list, "Reward: %s" % c["reward_desc"], GOOD_COLOR)
		_add_wrapped(_invasion_list, "Loot: %s" % NumFormat.cost(c["loot"]), GOOD_COLOR)
		if not Game.is_unlocked(c["requires"]):
			_add_wrapped(_invasion_list, "Unlock %s first." % GameData.resource_name(c["requires"]), BAD_COLOR)
		_add_wrapped(_invasion_list, "Warriors add troops to your army. Leaving mid-invasion counts as a retreat.", Color(1, 1, 1, 0.6))
		var country_id: String = c["id"]
		_invade_button = Button.new()
		_invade_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_invade_button.pressed.connect(func():
			if Game.start_invasion(country_id):
				get_tree().change_scene_to_file("res://scenes/invasion.tscn"))
		_invasion_list.add_child(_invade_button)
	var done: Array = []
	for country in GameData.COUNTRIES:
		if Game.conquered.has(country["id"]):
			done.append(country)
	if not done.is_empty():
		_invasion_list.add_child(HSeparator.new())
		var conquered_header := Label.new()
		conquered_header.text = "Conquered"
		conquered_header.add_theme_font_size_override("font_size", 18)
		_invasion_list.add_child(conquered_header)
		for country in done:
			_add_wrapped(_invasion_list, "%s: %s" % [country["name"], country["reward_desc"]], GOOD_COLOR)


func _add_wrapped(list: VBoxContainer, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(label)


func _on_message(text: String) -> void:
	_log.append(text)
	while _log.size() > MAX_LOG_LINES:
		_log.remove_at(0)
	_log_label.text = "\n".join(_log)
