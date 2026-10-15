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


func _sim(seconds: float, offline := false) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		_game.simulate(0.1, offline)
		t += 0.1


func _run() -> void:
	_game = root.get_node("Game")
	_game.set_process(false)

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
	_check(food < 960.0 and food > 945.0, "about 5%% rots in 10s online (%.1f left)" % food)
	_game.amounts["food"] = 10.0
	_sim(1.0)
	var small_loss: float = 10.0 - _game.amounts["food"]
	_check(small_loss < 0.06, "small stockpiles rot slowly (lost %.4f)" % small_loss)

	print("starvation and growth")
	_game.reset()
	_game.amounts["food"] = 0.0
	_sim(4.5)
	_check(_game.population == 2, "a person starves without food")
	_game.reset()
	_game.amounts["food"] = 100.0
	_sim(12.0)
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
