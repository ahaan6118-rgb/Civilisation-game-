# Run: godot --headless --path . -s tests/test_economy.gd
extends SceneTree

var _failures := 0
var _game: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		_failures += 1
		print("  FAIL ", what)


func _consumable_count() -> int:
	var n := 0
	for id in _game.consumables:
		n += _game.consumables[id]
	return n


func _sim(seconds: float, offline := false) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		_game.simulate(0.1, offline)
		t += 0.1


func _run() -> void:
	_game = root.get_node("Game")
	_game.set_process(false)
	root.get_node("SaveManager").set_process(false)
	_game._rng.seed = 12345

	print("starting state")
	_game.reset()
	_check(_game.is_unlocked("wood") and _game.is_unlocked("food"), "wood and food unlocked")
	_check(not _game.is_unlocked("stone"), "stone locked")
	_check(_game.idle() == 3, "3 idle people")

	print("clicking")
	_game.click_gather("wood")
	_check(is_equal_approx(_game.amounts["wood"], 1.0), "click gives 1 wood")
	_check(_game.click_gather("stone") == 0.0, "cannot gather locked stone")

	print("jobs")
	_game.assign_job("woodcutter", 2)
	_game.assign_job("gatherer", 5)
	_check(_game.jobs["woodcutter"] == 2 and _game.jobs["gatherer"] == 1, "assignment capped by idle people")
	_game.amounts["wood"] = 0.0
	_sim(10.0)
	_check(absf(_game.amounts["wood"] - 20.0) < 0.01, "2 woodcutters make 20 wood in 10s")

	print("spoilage")
	_game.reset()
	_game.population = 0
	_game.amounts["food"] = 1000.0
	_sim(10.0, true)
	_check(is_equal_approx(_game.amounts["food"], 1000.0), "no spoilage offline")
	_sim(10.0)
	var food: float = _game.amounts["food"]
	_check(food < 910.0 and food > 900.0, "about 10%% rots in 10s online (%.1f left)" % food)
	_game.amounts["food"] = 10.0
	_sim(1.0)
	var small_loss: float = 10.0 - _game.amounts["food"]
	_check(small_loss < 0.11, "small stockpiles rot slowly (lost %.4f)" % small_loss)

	print("starvation and growth")
	_game.reset()
	_game.amounts["food"] = 0.0
	_sim(4.5)
	_check(_game.population == 2, "a person starves without food")
	_game.reset()
	_game.amounts["food"] = 100.0
	_sim(25.0)
	_check(_game.population == 4, "population grows with food")

	print("unlocking stone")
	_game.reset()
	_game.amounts["wood"] = 999.0
	_check(not _game.research("stone_working"), "cannot research with 999 wood")
	_game.amounts["wood"] = 1000.0
	_check(_game.research("stone_working"), "research with 1000 wood")
	_check(_game.is_unlocked("stone") and _game.amounts["wood"] == 0.0, "stone unlocked and wood spent")
	_check(_game.tech_available(GameData.find("tech", "pottery")), "pottery is next")

	print("buildings and upgrades")
	_game.amounts["wood"] = 100.0
	_check(_game.buy_building("hut"), "buy hut")
	_check(_game.pop_cap() == 8, "hut adds 3 pop cap")
	_check(_game.building_cost("hut")["wood"] == 18.0, "hut cost scales")
	_game.amounts["stone"] = 100.0
	_check(_game.buy_upgrade("stone_axes"), "buy stone axes")
	_check(_game.job_multiplier("woodcutter") == 2.0, "woodcutters doubled")

	print("save round trip and offline")
	_game.assign_job("woodcutter", 3)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_game.to_dict()))
	_game.reset()
	_game.from_dict(saved)
	_check(_game.jobs["woodcutter"] == 3 and _game.upgrades.has("stone_axes") and _game.is_unlocked("stone"), "state restored")
	_game.amounts["wood"] = 0.0
	var gains: Dictionary = _game.apply_offline(3600.0)
	_check(absf(gains.get("wood", 0.0) - 3.0 * 2.0 * 3600.0) < 1.0, "offline hour gives wood")

	print("silly upgrades")
	_game.reset()
	var beavers := GameData.find("upgrade", "angry_beavers")
	_check(not _game.upgrade_available(beavers), "Angry Beavers hidden with no woodcutters")
	_game.assign_job("woodcutter", 1)
	_check(_game.upgrade_available(beavers), "Angry Beavers revealed at 1 woodcutter")
	_game.assign_job("woodcutter", -1)
	_check(_game.upgrade_available(beavers), "stays revealed after unassigning")
	for i in 50:
		_game.click_gather("wood")
	_check(_game.upgrade_available(GameData.find("upgrade", "calloused_hands")), "Calloused Hands at 50 clicks")
	_game.upgrades["wheelbarrows"] = true
	_game.unlocked["stone"] = true
	_game.population = 20
	_game.assign_job("woodcutter", 10)
	_check(is_equal_approx(_game.job_multiplier("quarrier"), 1.1), "Wheelbarrows: quarriers +1% per woodcutter")
	_game.upgrades["opposable_thumbs"] = true
	_game.rebuild_modifiers()
	var before_click: float = _game.amounts["wood"]
	_game.click_gather("wood")
	var expected_click: float = 1.0 + 0.01 * _game.production_per_second("wood")
	_check(is_equal_approx(_game.amounts["wood"] - before_click, expected_click), "click gives 1% of wood/s")

	print("artisans and items")
	_game.reset()
	_game.unlocked["stone"] = true
	_game.unlocked["clay"] = true
	_check(_game.building_cost("artisan") == {"wood": 100.0, "stone": 2000.0, "clay": 300.0}, "artisan costs 100 wood, 2000 stone, 300 clay")
	_check(not _game.start_commission("artisan"), "no commission without an artisan")
	_game.amounts["wood"] = 1e5
	_game.amounts["stone"] = 1e5
	_game.amounts["clay"] = 1e5
	_check(_game.buy_building("artisan"), "buy artisan")
	_check(_game.start_commission("artisan"), "start a commission")
	_check(not _game.start_commission("artisan"), "one commission per artisan")
	_game.amounts["food"] = 1e5
	_sim(61.0)
	_check(_game.total_items() + _consumable_count() == 1 and _game.crafts.is_empty(), "commission finished into one item")
	_game.items = {"woven_basket": 2, "flint_knife": 1}
	_game.rebuild_modifiers()
	_check(_game.active_synergies().size() == 1, "Hunter-Gatherer synergy active")
	_check(is_equal_approx(_game.job_multiplier("gatherer"), 1.6 * 3.0), "duplicates add linearly, synergy scales per basket")
	_game.items = {"painted_pot": 3}
	_game.rebuild_modifiers()
	_check(is_equal_approx(_game.mult("spoil:food"), 1.0 / (1.0 + (1.0 / 0.85 - 1.0) * 3.0)), "stacked reductions have diminishing returns")
	_game.items = {"tusk_necklace": 1, "painted_pot": 1, "woven_basket": 1}
	_game.rebuild_modifiers()
	_check(_game.mult("spoil:food") == 0.0, "The Feast stops food spoiling")
	_game.items = {"woven_basket": 2, "flint_knife": 1}
	_game.rebuild_modifiers()
	var counts := {}
	for i in 2000:
		var id: String = _game.roll_item("artisan")
		var rarity: String = GameData.find("item", id)["rarity"]
		counts[rarity] = counts.get(rarity, 0) + 1
	_check(counts.get("common", 0) > counts.get("rare", 0) and counts.has("legendary"), "rarity weights roll sensibly %s" % counts)
	_game.upgrades["unpaid_interns"] = true
	_game.rebuild_modifiers()
	_sim(0.1)
	_check(_game.crafts.size() == 1, "Unpaid Interns auto-start commissions")
	var item_save: Dictionary = JSON.parse_string(JSON.stringify(_game.to_dict()))
	_game.reset()
	_game.from_dict(item_save)
	_check(_game.items.get("woven_basket", 0) == 2 and _game.crafts.size() == 1, "items and commissions saved")
	_game.apply_offline(120.0)
	_check(_game.total_items() + _consumable_count() >= 4, "commissions finish offline")

	print("consumables")
	_game.reset()
	_game._grant_item("rallying_horn")
	_game._grant_item("rallying_horn")
	_check(_game.consumables.get("rallying_horn", 0) == 2 and _game.total_items() == 0, "consumables stored apart from relics")
	_check(_game.use_consumable("rallying_horn").size() == 1 and _game.consumables["rallying_horn"] == 1, "using one removes one")
	_check(_game.use_consumable("fire_pots").is_empty(), "cannot use what you don't own")
	var smith_only := true
	for i in 300:
		if GameData.find("item", _game.roll_item("blacksmith"))["maker"] != "blacksmith":
			smith_only = false
	_check(smith_only, "blacksmith only rolls blacksmith items")
	var cons_save: Dictionary = JSON.parse_string(JSON.stringify(_game.to_dict()))
	_game.reset()
	_game.from_dict(cons_save)
	_check(_game.consumables.get("rallying_horn", 0) == 1, "consumables saved")

	print("invasion map")
	var m := InvasionMap.new()
	m.generate(96, 54, 7, {"name": "You", "color": Color.BLUE, "troops": 300.0},
		[{"name": "Ug", "color": Color.RED, "troop_mult": 0.6, "aggression": 0.2}])
	_check(m.nations[0]["tiles"] > 20 and m.nations[1]["tiles"] > 20, "both nations spawn with land")
	_check(m.status() == "playing", "game starts in progress")
	_check(m.neighbours_of(0).has(InvasionMap.NEUTRAL), "player borders neutral land")
	_check(not m.send_attack(0, 1, 0.5), "cannot attack a nation you don't border")
	var start_tiles: int = m.nations[0]["tiles"]
	_check(m.send_attack(0, InvasionMap.NEUTRAL, 0.5), "attack neutral land")
	_check(is_equal_approx(m.nations[0]["troops"], 150.0), "half the troops leave")
	for i in 50:
		m.tick(0.1)
	_check(m.nations[0]["tiles"] > start_tiles + 10, "territory expands (%d -> %d)" % [start_tiles, m.nations[0]["tiles"]])
	for i in m.owners.size():
		if m.owners[i] == 1:
			m.owners[i] = 0
	m._recount()
	_check(m.status() == "won", "wiping out the enemy wins")

	print("invasions in the economy")
	_game.reset()
	_game.unlocked["stone"] = true
	_game.unlocked["clay"] = true
	_game.techs["stone_working"] = true
	_game.techs["pottery"] = true
	_check(not _game.job_available(GameData.find("job", "warrior")), "no warriors before Warfare")
	_game.amounts["stone"] = 5000.0
	_game.amounts["clay"] = 2000.0
	_check(_game.research("warfare") and _game.invasion_unlocked(), "research Warfare")
	_check(_game.is_unlocked("clay") and not _game.unlocked.has(""), "Warfare unlocks no resource")
	_game.population = 5
	_game.assign_job("warrior", 4)
	_check(is_equal_approx(_game.army_size(), 500.0), "4 warriors add 200 troops")
	_check(_game.next_country()["id"] == "ugs_tribe", "Ug's Tribe is first")
	_check(not _game.start_invasion("ugs_tribe"), "need supplies to invade")
	_game.amounts["food"] = 1e5
	_game.amounts["wood"] = 1e5
	_check(not _game.start_invasion("the_mudlands"), "cannot skip ahead")
	_check(_game.start_invasion("ugs_tribe") and _game.pending_invasion == "ugs_tribe", "launch invasion")
	var invasion_screen: Node = load("res://scenes/invasion.tscn").instantiate()
	root.add_child(invasion_screen)
	for i in 10:
		await process_frame
	_check(invasion_screen.map.nations.size() == 2, "invasion screen builds the map")
	_game.consumables = {"rallying_horn": 1, "sling_stones": 1, "fire_pots": 1}
	var you: Dictionary = invasion_screen.map.nations[0]
	var troops_before: float = you["troops"]
	invasion_screen.use_item("rallying_horn")
	_check(absf(you["troops"] - troops_before - invasion_screen.map.max_troops(0) * 0.3) < 1.0, "Rallying Horn adds 30% of max troops")
	var enemy_before: float = invasion_screen.map.nations[1]["troops"]
	invasion_screen.use_item("fire_pots")
	_check(is_equal_approx(invasion_screen.map.nations[1]["troops"], enemy_before * 0.7), "Fire Pots burn 30% of enemy troops")
	invasion_screen.use_item("sling_stones")
	_check(is_equal_approx(you["attack_mult"], 1.5), "Sling Stones buff attack")
	invasion_screen._update_buffs(21.0)
	_check(is_equal_approx(you["attack_mult"], 1.0), "buff wears off")
	_check(_game.consumables.is_empty(), "all three used up")
	invasion_screen.queue_free()
	var wood_before: float = _game.amounts["wood"]
	_game.finish_invasion(true)
	_check(_game.conquered.has("ugs_tribe") and _game.amounts["wood"] == wood_before + 2e4, "conquest gives loot")
	_check(is_equal_approx(_game.job_multiplier("woodcutter"), 1.25), "conquest bonus applies")
	_check(_game.next_country()["id"] == "the_mudlands", "Mudlands is next")
	var conquest_save: Dictionary = JSON.parse_string(JSON.stringify(_game.to_dict()))
	_game.reset()
	_game.from_dict(conquest_save)
	_check(_game.conquered.has("ugs_tribe"), "conquests saved")

	print("accidents and IQ")
	_game.reset()
	_game.population = 30
	_game.amounts["food"] = 1e6
	_game.assign_job("woodcutter", 30)
	var hourly: float = _game.deaths_per_hour("woodcutter")
	_check(is_equal_approx(hourly, 450.0), "30 woodcutters at IQ 50: 450 deaths/hour (%.1f)" % hourly)
	_game.iq = 100.0
	_check(is_equal_approx(_game.deaths_per_hour("woodcutter"), 112.5), "IQ 100 is 4x safer")
	_game.iq = 50.0
	var before_deaths: int = _game.run_deaths
	_sim(120.0)
	_check(_game.run_deaths > before_deaths and _game.population < 30, "woodcutters die over two minutes (%d deaths)" % (_game.run_deaths - before_deaths))
	_check(_game.jobs["woodcutter"] + _game.idle() == _game.population, "dead workers leave their job")
	_game.reset()
	_game.population = 2
	_game.assign_job("woodcutter", 2)
	for i in 50:
		_game._kill("woodcutter", "test")
	_check(_game.population == 1, "the last survivor is spared")
	_game.reset()
	_game.population = 5
	_game.assign_job("elder", 2)
	_game.amounts["food"] = 1e4
	_game.simulate(100.0, true)
	_check(is_equal_approx(_game.iq, 54.0), "2 elders teach +4 IQ in 100s (%.1f)" % _game.iq)
	_game.simulate(1000.0, true)
	_check(is_equal_approx(_game.iq, _game.iq_cap()), "IQ stops at the cap (%.0f)" % _game.iq_cap())
	_game.upgrades["fire_is_hot"] = true
	_game.rebuild_modifiers()
	_check(_game.iq_cap() == 70.0, "lessons raise the IQ cap")

	print("rebirth")
	_game.reset()
	_check(_game.legacy_gain() == 0, "no legacy for a fresh run")
	_game.unlocked["stone"] = true
	_game.unlocked["clay"] = true
	_game.conquered["ugs_tribe"] = true
	_game.run_deaths = 100
	_check(_game.legacy_gain() == 1 + 2 + 3 + 5, "legacy from eras, conquest and deaths (%d)" % _game.legacy_gain())
	_game.items = {"lucky_pebble": 1}
	_check(_game.rebirth() == 11 and _game.legacy == 11 and _game.runs == 1, "rebirth pays out")
	_check(not _game.is_unlocked("stone") and _game.items.is_empty() and _game.conquered.is_empty(), "rebirth resets the run")
	_check(_game.buy_prestige("ancestral_wisdom") and _game.legacy == 10, "buy Ancestral Wisdom for 1")
	_check(_game.prestige_cost("ancestral_wisdom") == 2, "next level costs 2")
	_check(_game.buy_prestige("heirloom") and _game.legacy == 5, "buy Heirloom for 5")
	_game.new_run()
	_check(_game.iq == 60.0 and _game.iq_cap() == 70.0, "Ancestral Wisdom raises starting IQ and cap")
	_check(_game.total_items() == 1, "Heirloom starts the run with a relic")
	var legacy_save: Dictionary = JSON.parse_string(JSON.stringify(_game.to_dict()))
	_game.reset()
	_check(_game.legacy == 0 and _game.prestige.is_empty(), "wipe clears legacy")
	_game.from_dict(legacy_save)
	_check(_game.legacy == 5 and _game.prestige.get("heirloom", 0) == 1 and _game.runs == 1, "legacy and prestige saved")

	print("number formatting")
	_check(NumFormat.fmt(999) == "999", "999")
	_check(NumFormat.fmt(1000) == "1.00K", "1.00K")
	_check(NumFormat.fmt(1.5e9) == "1.50B", "1.50B")
	_check(NumFormat.fmt(2e40) == "2.00e40", "scientific past Dc")

	print("UI smoke test")
	_game.reset()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	_game.amounts["wood"] = 1e3
	_game.research("stone_working")
	await process_frame
	_check(main.get_child_count() > 0, "main scene built")

	print("\n%s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(_failures)
