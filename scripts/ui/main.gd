extends Control

const REFRESH_INTERVAL := 0.2
const MAX_LOG_LINES := 5
const ICON_SIZE := Vector2(28, 28)
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
var _war_list: VBoxContainer
var _war_warning: Label
var _defend_button: Button
var _legacy_list: VBoxContainer
var _rebirth_button: Button
var _prestige_buttons: Dictionary = {}
var _confirm_rebirth: ConfirmationDialog
var _click_button: Button
var _click_art: TextureButton
var _click_choice: OptionButton
var _click_ids: Array = []
var _era_label: Label
var _event_list: VBoxContainer
var _event_rows: Array = []
var _log_label: Label
var _confirm_wipe: ConfirmationDialog

var _resource_rows: Dictionary = {}
var _job_rows: Dictionary = {}
var _decay_bar: ProgressBar
var _omen_button: Button
var _decay_label: Label
# How many people/buildings/commissions one click moves. MAX_AMOUNT = as many as possible.
const AMOUNTS := [1, 10, 100, 1000, 10000, -1]
const AMOUNT_LABELS := ["x1", "x10", "x100", "x1K", "x10K", "Max"]
const MAX_AMOUNT := -1
var _amount := 1
var _amount_buttons: Array = []
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

	_era_label = Label.new()
	_era_label.add_theme_font_size_override("font_size", 18)
	_era_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_era_label.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(_era_label)

	_columns = HBoxContainer.new()
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", 12)
	root.add_child(_columns)

	_resource_list = _make_panel("Resources", 1.0)
	_build_click_area(_resource_list.get_parent().get_parent())

	var pop_column := _make_panel("Population", 1.2)
	_pop_label = Label.new()
	pop_column.add_child(_pop_label)
	_event_list = VBoxContainer.new()
	pop_column.add_child(_event_list)
	pop_column.add_child(HSeparator.new())
	var job_tools := _make_amount_row()
	var clear := Button.new()
	clear.text = "Clear"
	clear.tooltip_text = "Take everyone off their jobs."
	clear.pressed.connect(func(): Game.unassign_all())
	job_tools.add_child(clear)
	pop_column.add_child(job_tools)
	_job_list = VBoxContainer.new()
	pop_column.add_child(_job_list)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_stretch_ratio = 1.4
	tabs.clip_tabs = false
	tabs.add_theme_font_size_override("font_size", 14)
	_columns.add_child(tabs)
	_tech_list = _make_tab(tabs, "Discoveries")
	_building_list = _make_tab_with_header(tabs, "Buildings", _make_amount_row())
	_upgrade_list = _make_tab(tabs, "Upgrades")
	_craft_list = _make_tab(tabs, "Crafting")
	_war_list = _make_tab(tabs, "War")
	_legacy_list = _make_tab(tabs, "Legacy")

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
	_confirm_wipe.dialog_text = "Delete your save and start over? This also deletes your Legacy."
	_confirm_wipe.confirmed.connect(SaveManager.wipe)
	add_child(_confirm_wipe)

	_confirm_rebirth = ConfirmationDialog.new()
	_confirm_rebirth.confirmed.connect(func(): Game.rebirth())
	add_child(_confirm_rebirth)


# The big Cookie Clicker button. Art: assets/Click.png (placeholder until then).
func _build_click_area(panel_box: VBoxContainer) -> void:
	var area := VBoxContainer.new()
	panel_box.add_child(area)
	panel_box.move_child(area, 1)
	var art := Assets.texture("Click")
	if art:
		_click_art = TextureButton.new()
		_click_art.texture_normal = art
		_click_art.ignore_texture_size = true
		_click_art.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		_click_art.custom_minimum_size = Vector2(0, 120)
		_click_art.pressed.connect(_on_big_click)
		area.add_child(_click_art)
	_click_button = Button.new()
	_click_button.custom_minimum_size = Vector2(0, 70 if art else 110)
	_click_button.add_theme_font_size_override("font_size", 20)
	_click_button.pressed.connect(_on_big_click)
	area.add_child(_click_button)
	_decay_label = Label.new()
	_decay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_decay_label.tooltip_text = "Everything your people make slowly decays, faster the lower it gets.\nClicking the big button halts it for a few seconds. Discoveries, upgrades and blessings purify it.\nLeave it alone and it builds momentum."
	_decay_label.mouse_filter = Control.MOUSE_FILTER_PASS
	area.add_child(_decay_label)
	_decay_bar = ProgressBar.new()
	_decay_bar.max_value = 1.0
	_decay_bar.show_percentage = false
	_decay_bar.custom_minimum_size.y = 10
	area.add_child(_decay_bar)
	_omen_button = Button.new()
	_omen_button.text = "A Golden Omen appears! Click it!"
	_omen_button.tooltip_text = "Purifies decay and finds a minute of production. Gone in a few seconds."
	_omen_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_omen_button.visible = false
	_omen_button.pressed.connect(func(): Game.click_omen(); _omen_button.visible = false)
	area.add_child(_omen_button)
	var row := HBoxContainer.new()
	area.add_child(row)
	var label := Label.new()
	label.text = "Gathering:"
	row.add_child(label)
	_click_choice = OptionButton.new()
	_click_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_click_choice.item_selected.connect(func(_i): _refresh())
	row.add_child(_click_choice)
	area.add_child(HSeparator.new())


func _clicked_resource() -> String:
	var i := _click_choice.selected
	return _click_ids[i] if i >= 0 and i < _click_ids.size() else "wood"


func _on_big_click() -> void:
	var gained := Game.click_gather(_clicked_resource())
	if gained <= 0.0:
		return
	var pop := Label.new()
	pop.text = "+%s" % NumFormat.fmt(gained)
	pop.add_theme_font_size_override("font_size", 20)
	pop.modulate = GOOD_COLOR
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_click_button.add_child(pop)
	var local := _click_button.get_local_mouse_position().clamp(Vector2(20, 30), _click_button.size - Vector2(40, 10))
	pop.position = local - Vector2(10, 20)
	var tween := pop.create_tween()
	tween.set_parallel(true)
	tween.tween_property(pop, "position:y", pop.position.y - 50, 0.7)
	tween.tween_property(pop, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(pop.queue_free)
	if _click_art:
		_click_art.pivot_offset = _click_art.size / 2.0
		var squish := _click_art.create_tween()
		squish.tween_property(_click_art, "scale", Vector2(0.9, 0.9), 0.05)
		squish.tween_property(_click_art, "scale", Vector2.ONE, 0.1)
	_refresh()


func _rebuild_click_choices() -> void:
	var keep := _clicked_resource() if not _click_ids.is_empty() else "wood"
	_click_ids.clear()
	_click_choice.clear()
	for r in GameData.RESOURCES:
		if r.get("clickable", false) and Game.is_unlocked(r["id"]):
			_click_ids.append(r["id"])
			_click_choice.add_item(r["name"])
	var index := _click_ids.find(keep)
	_click_choice.select(index if index >= 0 else 0)


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


# Buy/assign amount picker: x1, x10, ... Max. Every copy of it stays in sync.
func _make_amount_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Buy/assign:"
	row.add_child(label)
	for a in AMOUNTS:
		var amount: int = a
		var button := Button.new()
		button.toggle_mode = true
		button.text = AMOUNT_LABELS[AMOUNTS.find(amount)]
		button.tooltip_text = "Each click moves as many as possible." if amount == MAX_AMOUNT else "Each click moves %s." % NumFormat.fmt(amount)
		button.button_pressed = amount == _amount
		button.pressed.connect(func(): _set_amount(amount))
		row.add_child(button)
		_amount_buttons.append({"button": button, "amount": amount})
	return row


func _set_amount(amount: int) -> void:
	_amount = amount
	for entry in _amount_buttons:
		entry["button"].set_pressed_no_signal(entry["amount"] == amount)


# Number for one click: the picked amount (Shift multiplies it by 10), or a huge number for Max.
func _step() -> int:
	if _amount == MAX_AMOUNT:
		return 1 << 40
	return _amount * (10 if Input.is_key_pressed(KEY_SHIFT) else 1)


func _make_tab_with_header(tabs: TabContainer, title: String, header: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = title
	tabs.add_child(box)
	box.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	var era := EraData.current(Game.unlocked)
	_era_label.text = "%s  -  %s  (%s)    Kardashev Type %.2f" % [era["name"], era["subtitle"], era["time"], Game.kardashev()]
	_era_label.tooltip_text = era["concept"]
	_rebuild_events()
	_rebuild_click_choices()
	_rebuild_resources()
	_rebuild_jobs()
	_rebuild_shop()
	_rebuild_crafting()
	_rebuild_war()
	_rebuild_legacy()
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
		if icon == null:
			icon = TextureRect.new()
			icon.custom_minimum_size = ICON_SIZE
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
		minus.tooltip_text = "Uses the Amount picker; Shift-click for 10x"
		minus.pressed.connect(func(): Game.assign_job(id, -_step()))
		row.add_child(minus)
		var count := Label.new()
		count.custom_minimum_size.x = 40
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(count)
		var plus := Button.new()
		plus.text = "+"
		plus.custom_minimum_size = Vector2(32, 28)
		plus.tooltip_text = "Uses the Amount picker; Shift-click for 10x"
		plus.pressed.connect(func(): Game.assign_job(id, _step()))
		row.add_child(plus)
		_job_list.add_child(row)
		_job_rows[id] = {"count": count, "output": output, "name": name_label}


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
			button.pressed.connect(func(): Game.buy_buildings(id, _step()))
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

	var res_name := GameData.resource_name(_clicked_resource())
	var per_click := Game.mult("click") * Game.mult("click:" + _clicked_resource()) \
		+ Game.add("click_cps") * Game.production_per_second(_clicked_resource())
	_click_button.text = "Gather %s\n+%s per click" % [res_name, NumFormat.fmt(per_click)]
	_decay_bar.value = Game.decay
	_omen_button.visible = Game.omen_left > 0.0
	if _omen_button.visible:
		_omen_button.text = "A Golden Omen appears! Click it! (%ds)" % ceili(Game.omen_left)
	var state := "halted" if Game.decay_hold() >= 1.0 else "-%.1f%%/s" % (Game.decay_per_second() * 100.0)
	_decay_label.text = "Decay: production x%.2f (%s)" % [Game.decay, state]
	if Game.decay_momentum > 1.05:
		_decay_label.text += "  momentum x%.2f" % Game.decay_momentum
	_decay_label.modulate = BAD_COLOR if Game.decay < 0.5 else (Color(1, 0.85, 0.5) if Game.decay < 0.9 else Color.WHITE)
	_decay_bar.modulate = _decay_label.modulate

	var food_use := Game.population * Game.food_per_second_per_person()
	var hourly := 0.0
	for job in GameData.JOBS:
		hourly += Game.deaths_per_hour(job["id"])
	hourly += Game.deaths_per_hour("idle")
	var pop_text := "People: %d / %d    Idle: %d\nEating %s food/s\nTribe IQ: %.1f / %.0f    Deaths this run: %d\nAccidents: about %s per hour" % [
		Game.population, Game.pop_cap(), Game.idle(), NumFormat.fmt(food_use),
		Game.iq, Game.iq_cap(), Game.run_deaths, NumFormat.fmt(hourly)]
	pop_text += "\nMorale: %.0f (work %.2fx)    Health: %.0f" % [Game.morale, Game.morale_factor(), Game.health]
	var births: float = Game.births_per_second() * 3600.0 if Game.population < Game.pop_cap() else 0.0
	var old_age: float = Game.old_age_per_second() * 3600.0
	pop_text += "\nBirths: ~%s/h    Old age: ~%s/h    Lifespan: %s" % [NumFormat.fmt(births), NumFormat.fmt(old_age), NumFormat.duration(Game.lifespan())]
	if Game.illness_per_hour() + old_age + hourly > births:
		pop_text += "\nYour people are dying faster than they're born!"
	if Game.crime_rate > 0.0:
		pop_text += "\nCrime is stealing %.1f%% of your stockpiles per second!" % (Game.crime_rate * 100.0)
	if Game.illness_per_hour() >= 1.0:
		pop_text += "\nIllness: about %s deaths per hour" % NumFormat.fmt(Game.illness_per_hour())
	if Game.starving:
		pop_text += "\nSTARVING! Assign Gatherers or gather food."
	var trouble := Game.starving or Game.morale < 30.0 or Game.health < 30.0
	_pop_label.modulate = BAD_COLOR if trouble else Color.WHITE
	_pop_label.text = pop_text

	for row in _event_rows:
		var ev: Dictionary = row["event"]
		var data := EventData.find(ev["id"])
		var left := "until fixed" if ev["remaining"] < 0.0 else NumFormat.duration(ceilf(ev["remaining"])) + " left"
		row["label"].text = "%s (%s)" % [data["name"], left]
		if row["fix"]:
			var cost := Game.fix_cost(ev)
			row["fix"].text = "%s: %s" % [data["fix"]["label"], NumFormat.cost(cost)]
			row["fix"].disabled = not Game.can_afford(cost)

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

	if _rebirth_button:
		var gain := Game.legacy_gain()
		_rebirth_button.text = "Rebirth for +%d Legacy" % gain
		_rebirth_button.disabled = gain <= 0
	for id in _prestige_buttons:
		var p := GameData.find("prestige", id)
		var level: int = Game.prestige.get(id, 0)
		var button: Button = _prestige_buttons[id]
		if level >= p["max"]:
			button.text = "%s (max %d/%d)\n%s" % [p["name"], level, p["max"], p["desc"]]
			button.disabled = true
		else:
			button.text = "%s (%d/%d)\n%s\nCost: %d Legacy" % [p["name"], level, p["max"], p["desc"], Game.prestige_cost(id)]
			button.disabled = not Game.can_buy_prestige(id)

	if _war_warning:
		if Game.incoming_war.is_empty():
			_war_warning.visible = false
			_defend_button.visible = false
		else:
			var enemy := WarData.find_target(Game.incoming_war["target"])
			_war_warning.text = "%s declared war on you! They arrive in %ds." % [enemy["name"], maxi(0, ceili(Game.incoming_war["countdown"]))]
			_war_warning.visible = true
			_defend_button.visible = true

	for item in _commission_buttons:
		var maker_id: String = item["maker"]
		var cost := Game.commission_cost(maker_id)
		var free := Game.maker_slots(maker_id) - Game.maker_busy(maker_id)
		var paused: bool = Game.paused_makers.has(maker_id)
		var title := "Stopped. Press Resume to craft again." if paused else "Commission an item (%d free)" % free
		item["button"].text = "%s\nCost: %s" % [title, NumFormat.cost(cost)]
		item["button"].disabled = paused or free <= 0 or not Game.can_afford(cost)
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
		var affordable := true
		if item["kind"] == "building":
			var want := _step()
			var n := mini(want, Game.MAX_BULK)
			if _amount == MAX_AMOUNT:
				n = maxi(1, Game.affordable_buildings(entry["id"]))
			cost = Game.building_cost_bulk(entry["id"], n)
			title += " (%d)" % Game.buildings.get(entry["id"], 0)
			if n > 1:
				title += "   buy %s" % NumFormat.fmt(n)
			affordable = Game.affordable_buildings(entry["id"], 1) > 0
		else:
			cost = entry["cost"]
		var text := "%s\n%s" % [title, entry["desc"]]
		if entry.get("flavor", "") != "":
			text += "\n\"%s\"" % entry["flavor"]
		button.text = text + "\nCost: " + NumFormat.cost(cost)
		# Buildings stay clickable while at least one is affordable; you get as many as you can pay for.
		button.disabled = not affordable if item["kind"] == "building" else not Game.can_afford(cost)


func _rebuild_crafting() -> void:
	_clear(_craft_list)
	_commission_buttons.clear()
	_craft_bars.clear()
	for maker in GameData.MAKERS:
		var maker_id: String = maker["id"]
		var slots := Game.maker_slots(maker_id)
		var header := Label.new()
		header.add_theme_font_size_override("font_size", 18)
		header.text = "%ss: %d%s" % [maker["name"], slots, "  (stopped)" if Game.paused_makers.has(maker_id) else ""]
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
		button.pressed.connect(func(): Game.start_commissions(maker_id, _step()))
		var row := HBoxContainer.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
		var stop := Button.new()
		stop.text = "Resume" if Game.paused_makers.has(maker_id) else "Stop"
		stop.tooltip_text = "Stop or resume this maker. Stopped makers pause their crafts and take no new ones."
		stop.pressed.connect(func(): Game.set_maker_paused(maker_id, not Game.paused_makers.has(maker_id)))
		row.add_child(stop)
		_craft_list.add_child(row)
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
	collection.text = "Relics (%d)" % Game.total_items()
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

	var supplies := Label.new()
	supplies.add_theme_font_size_override("font_size", 18)
	supplies.text = "Consumables (used in battle)"
	_craft_list.add_child(supplies)
	if Game.consumables.is_empty():
		_add_wrapped(_craft_list, "None yet.", Color(1, 1, 1, 0.5))
	for it in GameData.ITEMS:
		var count: int = Game.consumables.get(it["id"], 0)
		if count == 0:
			continue
		var row := HBoxContainer.new()
		var icon := _icon(it["name"])
		if icon:
			row.add_child(icon)
		var label := Label.new()
		label.text = "%s x%d: %s" % [it["name"], count, it["desc"]]
		label.modulate = GameData.RARITIES[it["rarity"]]["color"]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		_craft_list.add_child(row)

	var active := Game.active_synergies()
	if GameData.SYNERGIES.is_empty():
		return
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


func _rebuild_war() -> void:
	_clear(_war_list)
	_war_warning = null
	_defend_button = null
	if not Game.war_unlocked():
		_add_wrapped(_war_list, "Research Warfare in the Discoveries tab to wage war on your neighbours.", Color(1, 1, 1, 0.6))
		return
	var tier: Dictionary = WarData.TIERS[Game.current_tier()]
	var header := Label.new()
	header.text = "Kardashev Type %.2f    Fighting over: %s" % [Game.kardashev(), tier["name"]]
	header.add_theme_font_size_override("font_size", 18)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_war_list.add_child(header)
	_add_wrapped(_war_list, "Army: %s %s (%s per Warrior this age)" % [NumFormat.fmt(Game.army_size()), tier["unit"], NumFormat.fmt(Game.troops_per_warrior())], Color.WHITE)
	_war_warning = Label.new()
	_war_warning.modulate = BAD_COLOR
	_war_warning.add_theme_font_size_override("font_size", 18)
	_war_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_war_list.add_child(_war_warning)
	_defend_button = Button.new()
	_defend_button.text = "Defend now!"
	_defend_button.pressed.connect(func():
		if Game.start_war(Game.incoming_war["target"], true):
			get_tree().change_scene_to_file("res://scenes/invasion.tscn"))
	_war_list.add_child(_defend_button)
	var wage := Button.new()
	wage.text = "Wage War (World Map)"
	wage.custom_minimum_size.y = 60
	wage.add_theme_font_size_override("font_size", 20)
	wage.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/world_map.tscn"))
	_war_list.add_child(wage)
	_add_wrapped(_war_list, "Neighbours will declare war on you too. When they do you have %d seconds before the battle starts, wherever you are. Losing a defence costs people, stockpiles and buildings." % int(WarData.DECLARE_WARNING), Color(1, 1, 1, 0.6))
	if not Game.conquered.is_empty():
		_war_list.add_child(HSeparator.new())
		var names: PackedStringArray = []
		for id in Game.conquered:
			names.append(WarData.find_target(id)["name"])
		_add_wrapped(_war_list, "Conquered (%d): %s" % [names.size(), ", ".join(names)], GOOD_COLOR)


func _rebuild_events() -> void:
	_clear(_event_list)
	_event_rows.clear()
	for i in Game.events.size():
		var ev: Dictionary = Game.events[i]
		var data := EventData.find(ev["id"])
		var label := Label.new()
		label.modulate = GOOD_COLOR if data["good"] else BAD_COLOR
		label.tooltip_text = data["desc"]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		_event_list.add_child(label)
		var fix: Button = null
		if data.has("fix"):
			fix = Button.new()
			fix.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var index := i
			fix.pressed.connect(func(): Game.fix_event(index))
			_event_list.add_child(fix)
		_event_rows.append({"event": ev, "label": label, "fix": fix})


func _rebuild_legacy() -> void:
	_clear(_legacy_list)
	_prestige_buttons.clear()
	var header := Label.new()
	header.text = "Legacy: %d    (run %d)" % [Game.legacy, Game.runs + 1]
	header.add_theme_font_size_override("font_size", 18)
	_legacy_list.add_child(header)
	_add_wrapped(_legacy_list, "Rebirth ends this civilisation and starts a new one. You keep Legacy and these upgrades; everything else resets.", Color(1, 1, 1, 0.7))
	var parts: PackedStringArray = []
	for id in Game.unlocked:
		if GameData.ERA_LEGACY.has(id):
			parts.append("%s +%d" % [GameData.resource_name(id), GameData.ERA_LEGACY[id]])
	if not Game.conquered.is_empty():
		parts.append("conquests +%d" % (Game.conquered.size() * GameData.LEGACY_PER_CONQUEST))
	if Game.deaths_legacy() > 0:
		parts.append("%d deaths +%d" % [Game.run_deaths, Game.deaths_legacy()])
	_add_wrapped(_legacy_list, "This run is worth: " + (", ".join(parts) if not parts.is_empty() else "nothing yet (unlock Stone first)"), GOOD_COLOR)
	_rebirth_button = Button.new()
	_rebirth_button.pressed.connect(func():
		_confirm_rebirth.dialog_text = "End this civilisation for +%d Legacy?\nResources, people, buildings, upgrades, items and conquests reset." % Game.legacy_gain()
		_confirm_rebirth.popup_centered())
	_legacy_list.add_child(_rebirth_button)
	_legacy_list.add_child(HSeparator.new())
	for p in GameData.PRESTIGE:
		var id: String = p["id"]
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.icon = Assets.texture(p["name"])
		button.add_theme_constant_override("icon_max_width", 32)
		button.pressed.connect(func(): Game.buy_prestige(id))
		_legacy_list.add_child(button)
		_prestige_buttons[id] = button


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
