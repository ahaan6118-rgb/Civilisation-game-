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
	# A leftover save would otherwise be loaded by SaveManager's deferred load in the middle of the tests.
	root.get_node("SaveManager").wipe()
	_game._rng.seed = 12345
	_game.events_enabled = false
	_game.decay_enabled = false

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
	_check(food < 745.0 and food > 735.0, "about 26%% rots in 10s online (%.1f left)" % food)
	_game.amounts["food"] = 10.0
	_sim(1.0)
	var small_loss: float = 10.0 - _game.amounts["food"]
	_check(small_loss < 0.31, "small stockpiles rot slowly (lost %.4f)" % small_loss)

	print("starvation and growth")
	_game.reset()
	_game.amounts["food"] = 0.0
	_sim(4.5)
	_check(_game.population == 2, "a person starves without food")
	_game.reset()
	_game.amounts["food"] = 1e5
	_check(is_equal_approx(_game.births_per_second(), (1.0 / 240.0 + 3.0 / 120.0) * (1.0 - 3.0 / 5.0)), "3 healthy people in 5 homes: a baby about every 85s")
	_check(is_equal_approx(_game.old_age_per_second(), 3.0 / 420.0), "and one dies of old age about every 140s")
	_game._age_progress = -100.0
	_sim(180.0)
	_check(_game.population >= 4, "population grows with food")
	_game.reset()
	_game.population = 10
	_game.health = 0.0
	_check(_game.old_age_per_second() > _game.births_per_second(), "a sick tribe dies faster than it breeds")
	_game.health = 60.0
	_game.population = 5
	_check(_game.births_per_second() == 0.0, "no babies without room")

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
	_check(_game.building_cost("hut")["wood"] == 20.0, "hut cost scales")
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
	_check(is_equal_approx(_game.job_multiplier("gatherer") / _game.morale_factor(), 1.6), "duplicates add linearly")
	_game.items = {"painted_pot": 3}
	_game.rebuild_modifiers()
	_check(is_equal_approx(_game.mult("spoil:food"), 1.0 / (1.0 + (1.0 / 0.85 - 1.0) * 3.0)), "stacked reductions have diminishing returns")
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

	print("war")
	_game.reset()
	_game.unlocked["stone"] = true
	_game.unlocked["clay"] = true
	_game.techs["stone_working"] = true
	_game.techs["pottery"] = true
	_check(not _game.job_available(GameData.find("job", "warrior")) and not _game.tier_unlocked(0), "no war before Warfare")
	_game.amounts["stone"] = 5000.0
	_game.amounts["clay"] = 2000.0
	_check(_game.research("warfare") and _game.war_unlocked() and _game.tier_unlocked(0), "Warfare opens The Valley")
	_game.population = 5
	_game.assign_job("warrior", 4)
	_check(is_equal_approx(_game.army_size(), 500.0), "4 Clay-age warriors add 200 troops")
	_check(_game.can_attack("ugs_tribe") and _game.can_attack("the_mudlands"), "neighbours of home can be attacked")
	_check(not _game.can_attack("cave_kings"), "far lands can't be attacked yet")
	_check(not _game.tier_unlocked(1), "The Continent is locked")
	_game.amounts["food"] = 1000.0
	_game.amounts["wood"] = 1000.0
	_check(_game.start_war("ugs_tribe") and _game.pending_war["target"] == "ugs_tribe", "declare war")
	_check(_game.amounts["food"] == 800.0, "war costs 20% of food")
	var battle: Node = load("res://scenes/invasion.tscn").instantiate()
	root.add_child(battle)
	for i in 10:
		await process_frame
	var named := 0
	var minor_count := 0
	for n in battle.map.nations:
		if n["minor"]:
			minor_count += 1
		else:
			named += 1
	_check(named == 6 and battle.map.nations[1]["name"] == "Ug's Tribe" and battle.map.nations[1]["objective"], "the whole valley is on the battle map")
	_check(minor_count >= 100, "with %d minor factions" % minor_count)
	var hostile := 0
	for n in battle.map.nations:
		if n["team"] == InvasionMap.Team.HOSTILE:
			hostile += 1
	_check(hostile >= 2, "Ug's neighbours gang up on you (%d at war)" % hostile)
	_check(battle.map.nations[0]["tiles"] < battle.map.nations[1]["tiles"], "you start smaller than them")
	_game.consumables = {"rallying_horn": 1, "sling_stones": 1, "fire_pots": 1}
	var you: Dictionary = battle.map.nations[0]
	var troops_before: float = you["troops"]
	battle.use_item("rallying_horn")
	_check(absf(you["troops"] - troops_before - battle.map.max_troops(0) * 0.3) < 1.0, "Rallying Horn adds 30% of max troops")
	var enemy_before: float = battle.map.nations[1]["troops"]
	battle.use_item("fire_pots")
	_check(is_equal_approx(battle.map.nations[1]["troops"], enemy_before * 0.7), "Fire Pots burn 30% of enemy troops")
	var base_attack: float = you["attack_mult"]
	battle.use_item("sling_stones")
	_check(is_equal_approx(you["attack_mult"], base_attack * 1.5), "Sling Stones buff attack")
	battle._update_buffs(21.0)
	_check(is_equal_approx(you["attack_mult"], base_attack), "buff wears off")
	_game.consumables = {"rallying_horn": 1}
	battle.use_item("rallying_horn")
	_check(_game.consumables.get("rallying_horn", 0) == 1, "only %d items per battle" % WarData.BATTLE_ITEM_LIMIT)
	battle.queue_free()
	var wood_before: float = _game.amounts["wood"]
	_game.finish_war(true)
	_check(_game.conquered.has("ugs_tribe") and _game.pending_war.is_empty(), "victory conquers the target")
	_check(_game.amounts["wood"] >= wood_before, "conquest gives loot")
	_check(is_equal_approx(_game.mult("job:all"), 1.1), "each conquest boosts production")
	_check(_game.can_attack("hill_folk"), "conquering opens new neighbours")
	_check(_game.kardashev() > 0.0 and _game.kardashev() < 0.3, "Kardashev rises (%.2f)" % _game.kardashev())
	for t in WarData.TIERS[0]["targets"]:
		_game.conquered[t["id"]] = true
	_game.rebuild_modifiers()
	_check(_game.tier_complete(0) and is_equal_approx(_game.kardashev(), 0.3), "conquering The Valley reaches Type 0.3")
	_check(not _game.tier_unlocked(1), "The Continent still needs Bronze")
	_game.unlocked["copper"] = true
	_game.unlocked["bronze"] = true
	_check(_game.tier_unlocked(1) and _game.current_tier() == 1, "Bronze opens The Continent")
	_check(_game.troops_per_warrior() == 200.0, "Bronze-age warriors are 4x stronger")
	_game.start_war("copper_clans", true)
	var pop_before_defeat: int = _game.population
	_game.amounts["clay"] = 1000.0
	_game.finish_war(false)
	_check(_game.amounts["clay"] == 600.0 and _game.population < pop_before_defeat, "losing a defence costs stock and people")
	_game.incoming_war = {"target": "tin_league", "countdown": 3.0}
	var war_save: Dictionary = JSON.parse_string(JSON.stringify(_game.to_dict()))
	_game.reset()
	_game.from_dict(war_save)
	_check(_game.conquered.size() == 5 and _game.incoming_war.get("target", "") == "tin_league", "conquests and declarations saved")
	_game.reset()
	_game.unlocked["clay"] = true
	_game.techs["warfare"] = true
	_game._declare_timer = 0.0
	_game.simulate(0.1, false)
	_check(_game.incoming_war.get("target", "") in ["ugs_tribe", "the_mudlands", "hill_folk"], "a neighbour declares war")
	var world: Node = load("res://scenes/world_map.tscn").instantiate()
	root.add_child(world)
	for i in 5:
		await process_frame
	_check(world.get_child_count() > 0, "the world map builds")
	world.queue_free()

	print("accidents and IQ")
	_game.reset()
	_game.population = 30
	_game.amounts["food"] = 1e6
	_game.assign_job("woodcutter", 30)
	var hourly: float = _game.deaths_per_hour("woodcutter")
	_check(is_equal_approx(hourly, 600.0), "30 woodcutters at IQ 50: 600 deaths/hour (%.1f)" % hourly)
	_game.iq = 100.0
	_check(is_equal_approx(_game.deaths_per_hour("woodcutter"), 300.0), "IQ 100 is 2x safer")
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

	print("decay")
	_game.reset()
	_game.decay_enabled = true
	_check(_game.decay == 1.0, "a run starts with no decay")
	var early_rate: float = _game.decay_rate()
	_game.lifetime["wood"] = 1e20
	var late_rate: float = _game.decay_rate()
	_check(early_rate < 0.005 and late_rate > 0.03, "decay starts gentle and grows with progress (%.4f -> %.4f)" % [early_rate, late_rate])
	_sim(60.0)
	var after_minute: float = _game.decay
	_check(after_minute < 0.97 and after_minute > 0.5, "a minute of neglect late in a run costs production (x%.2f)" % after_minute)
	_sim(600.0)
	_check(_game.decay < after_minute * 0.6 and _game.decay_momentum > 1.5, "it gets worse and builds momentum (x%.2f, momentum %.2f)" % [_game.decay, _game.decay_momentum])
	var held: float = _game.decay
	_game.click_gather("wood")
	_sim(2.0)
	_check(is_equal_approx(_game.decay, held), "clicking halts decay")
	_game.amounts["wood"] = 1000.0
	_game.research("stone_working")
	_check(_game.decay == 1.0 and _game.decay_momentum == 1.0, "a discovery purifies everything")
	_game.population = 10
	_game.assign_job("woodcutter", 10)
	var full: float = _game.production_per_second("wood")
	_game.decay = 0.5
	_check(is_equal_approx(_game.production_per_second("wood"), full * 0.5), "decay scales production")
	_game.decay = 0.5
	_game.simulate(600.0, true)
	_check(_game.decay == 0.5, "no decay offline")
	_game.decay_enabled = false

	print("bulk buying")
	_game.reset()
	_game.amounts["wood"] = 1e6
	var one_cost: float = _game.building_cost("hut")["wood"]
	var ten: Dictionary = _game.building_cost_bulk("hut", 10)
	var expected := 0.0
	for k in 10:
		expected += ceilf(15.0 * pow(1.3, k))
	_check(absf(ten["wood"] - expected) <= 10.0 and one_cost == 15.0, "bulk cost adds up the next 10 huts (%.0f vs %.0f)" % [ten["wood"], expected])
	var can: int = _game.affordable_buildings("hut")
	_check(_game.buy_buildings("hut", 1 << 40) == can and can > 10 and not _game.can_afford(_game.building_cost("hut")), "Max buys every hut you can afford (%d)" % can)
	_game.population = 50
	_game.assign_job("woodcutter", 1 << 40)
	_check(_game.jobs["woodcutter"] == 50 and _game.idle() == 0, "Max assigns every idle person")
	_game.unassign_all()
	_check(_game.idle() == 50, "unassign all")

	print("rebirth")
	_game.reset()
	_check(_game.legacy_gain() == 0, "no legacy for a fresh run")
	_game.unlocked["stone"] = true
	_game.unlocked["clay"] = true
	_game.conquered["ugs_tribe"] = true
	_check(_game.legacy_gain() == 1, "early ages give no legacy, a conquest gives 1 (%d)" % _game.legacy_gain())
	_game.unlocked["copper"] = true
	_game.run_deaths = 2500
	_check(_game.legacy_gain() == 1 + 1 + 3, "legacy from eras, conquest and deaths (%d)" % _game.legacy_gain())
	_game.run_deaths = 2000000
	_check(_game.deaths_legacy() == 6, "mass death can't farm legacy (%d)" % _game.deaths_legacy())
	_game.run_deaths = 2500
	_game.items = {"lucky_pebble": 1}
	_game.legacy = 7
	_check(_game.rebirth() == 5 and _game.legacy == 12 and _game.runs == 1, "rebirth pays out")
	_check(not _game.is_unlocked("stone") and _game.items.is_empty() and _game.conquered.is_empty(), "rebirth resets the run")
	_check(_game.buy_prestige("ancestral_wisdom") and _game.legacy == 9, "buy Ancestral Wisdom for 3")
	_check(_game.prestige_cost("ancestral_wisdom") == 9, "next level costs 9")
	_check(not _game.buy_prestige("heirloom"), "Heirloom costs 15")
	_game.legacy += 11
	_check(_game.buy_prestige("heirloom") and _game.legacy == 5, "buy Heirloom for 15")
	_game.new_run()
	_check(_game.iq == 60.0 and _game.iq_cap() == 70.0, "Ancestral Wisdom raises starting IQ and cap")
	_check(_game.total_items() == 1, "Heirloom starts the run with a relic")
	var legacy_save: Dictionary = JSON.parse_string(JSON.stringify(_game.to_dict()))
	_game.reset()
	_check(_game.legacy == 0 and _game.prestige.is_empty(), "wipe clears legacy")
	_game.from_dict(legacy_save)
	_check(_game.legacy == 5 and _game.prestige.get("heirloom", 0) == 1 and _game.runs == 1, "legacy and prestige saved")

	print("morale, health and crime")
	_game.reset()
	_check(is_equal_approx(_game.morale_factor(), 1.0), "morale 50 is normal speed")
	_game.morale = 0.0
	_check(is_equal_approx(_game.morale_factor(), 0.6), "morale 0 works at 0.6x")
	_game.morale = 50.0
	_game.population = 3
	_game.grief = 20.0
	_check(is_equal_approx(_game.morale_target(), 30.0), "grief lowers target morale")
	_game.grief = 0.0
	_game.population = 10
	_check(is_equal_approx(_game.morale_target(), 40.0), "a full town is unhappy")
	_check(_game.health_target() < _game.START_HEALTH, "a crowded town is less healthy")
	_game.unlocked["stone"] = true
	_game.amounts["wood"] = 1000.0
	_game.morale = 0.0
	_game._run_crime(10.0)
	_check(_game.amounts["wood"] < 1000.0 and _game.amounts["food"] == _game.STARTING_FOOD, "crime steals non-food stock when morale is low")
	_game.health = 10.0
	_check(_game.illness_per_hour() > 10.0, "sick towns die of illness (%.1f/h)" % _game.illness_per_hour())

	print("events")
	_game.reset()
	_game.unlocked["stone"] = true
	_game.unlocked["clay"] = true
	_game.population = 10
	_game.amounts["food"] = 1000.0
	_check(not _game.event_eligible(EventData.find("famine")), "no famine while fed")
	_game.start_event("drought")
	_check(_game.has_event("drought") and is_equal_approx(_game.job_multiplier("gatherer") / _game.morale_factor(), 0.3), "drought cripples gatherers")
	_check(_game.mult("growth") == 0.0, "no babies in a drought")
	_game.amounts["stone"] = 1000.0
	_game.amounts["clay"] = 1000.0
	var drought_cost: Dictionary = _game.fix_cost(_game.events[0])
	_check(drought_cost.get("stone", 0.0) == 300.0, "fix costs a share of current stock")
	_check(_game.fix_event(0) and not _game.has_event("drought"), "Dig Wells ends the drought")
	_game.start_event("locusts")
	_game.simulate(61.0, false)
	_check(not _game.has_event("locusts"), "timed events run out")
	_game.buildings = {"hut": 3}
	_game.rebuild_modifiers()
	_game.population = _game.pop_cap()
	var pop_before: int = _game.population
	_game.start_event("flood")
	_check(_game.buildings["hut"] == 1 and _game.population <= _game.pop_cap() and _game.population < pop_before, "flood destroys huts and the homeless leave")
	_game.population = 20
	_game.buildings = {"hut": 10}
	_game.rebuild_modifiers()
	_game.unlocked["copper"] = true
	_game.jobs = {"copper_miner": 5}
	_game.start_event("exhaustion")
	_check(_game.events[-1]["target"] == "copper_miner" and is_equal_approx(_game.job_multiplier("copper_miner") / _game.morale_factor(), 0.25), "a mine runs dry")
	var event_save: Dictionary = JSON.parse_string(JSON.stringify(_game.to_dict()))
	_game.reset()
	_game.from_dict(event_save)
	_check(_game.has_event("exhaustion") and is_equal_approx(_game.job_multiplier("copper_miner") / _game.morale_factor(), 0.25), "events are saved")
	_game.reset()
	_game.events_enabled = true
	_game._event_timer = 0.0
	_game.simulate(0.1, false)
	_check(_game._event_timer > 50.0, "the event clock rolls")
	_game.events_enabled = false
	_check(EraData.current(_game.unlocked)["name"] == "The Wood & Bone Age", "the first age is Wood & Bone")
	_game.unlocked["clay"] = true
	_check(EraData.current(_game.unlocked)["subtitle"] == "The Neolithic", "clay is the Neolithic")

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
