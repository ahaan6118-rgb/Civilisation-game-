# Plays the economy automatically and prints when each era unlocks.
# Run: godot --headless --path . -s tools/balance_bot.gd -- [hours=40] [seed=1]
extends SceneTree

const STEP := 1.0
const THINK_EVERY := 10.0

var game: Node
var hours := 40.0
var _snapshots := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		hours = float(args[0])
	_run.call_deferred(int(args[1]) if args.size() > 1 else 1)


func _run(seed_value: int) -> void:
	game = root.get_node("Game")
	game.set_process(false)
	root.get_node("SaveManager").set_process(false)
	game.reset()
	game._rng.seed = seed_value
	var t := 0.0
	var think := 0.0
	var unlocked_at := {}
	while t < hours * 3600.0:
		game.simulate(STEP, false)
		t += STEP
		think -= STEP
		if think <= 0.0:
			think = THINK_EVERY
			_click_a_bit()
			_think()
		for r in GameData.RESOURCES:
			if game.is_unlocked(r["id"]) and not unlocked_at.has(r["id"]):
				unlocked_at[r["id"]] = t
				_snapshots[r["id"]] = [game.population, game.run_deaths]
		if game.is_unlocked("dark_matter") and t - unlocked_at["dark_matter"] > 600.0:
			break
	_report(unlocked_at, t)
	quit()


# A player clicks early on; model a few clicks per second for the first 15 minutes.
func _click_a_bit() -> void:
	if game.population > 40:
		return
	for i in 30:
		game.click_gather(_target_resource())


func _think() -> void:
	for t in GameData.TECHS:
		if game.tech_available(t) and game.research(t["id"]):
			break
	_buy_things()
	_assign_jobs()
	for maker in GameData.MAKERS:
		while game.maker_busy(maker["id"]) < game.maker_slots(maker["id"]) and _cheap(game.commission_cost(maker["id"]), 0.2):
			if not game.start_commission(maker["id"]):
				break


# Spend at most `share` of each resource so research still gets saved up for.
func _cheap(cost: Dictionary, share: float) -> bool:
	var next := _next_tech()
	for res in cost:
		var have: float = game.amounts.get(res, 0.0)
		if have < cost[res]:
			return false
		if not next.is_empty() and next["cost"].has(res) and cost[res] > have * share:
			return false
	return true


func _buy_things() -> void:
	var bought := true
	while bought:
		bought = false
		for u in GameData.UPGRADES:
			if game.upgrade_available(u) and _cheap(u["cost"], 0.5) and game.buy_upgrade(u["id"]):
				bought = true
		for b in GameData.BUILDINGS:
			if not game.building_available(b):
				continue
			var useful: bool = b["id"] in ["artisan", "blacksmith"] and game.buildings.get(b["id"], 0) < 3
			for e in b["effects"]:
				if e["key"] == "pop_cap" and game.population >= game.pop_cap() - 2:
					useful = true
				if e["key"].begins_with("spoil:") and game.buildings.get(b["id"], 0) < 5:
					useful = true
			if useful and _cheap(game.building_cost(b["id"]), 0.3) and game.buy_building(b["id"]):
				bought = true


func _next_tech() -> Dictionary:
	for t in GameData.TECHS:
		if game.tech_available(t) and t["unlocks"] != "":
			return t
	return {}


func _target_resource() -> String:
	var t := _next_tech()
	if t.is_empty():
		return "dark_matter"
	return t["cost"].keys()[0]


func _job_for(res: String) -> Dictionary:
	for job in GameData.JOBS:
		if game.job_available(job) and job["produces"].has(res):
			return job
	return {}


func _assign_jobs() -> void:
	for id in game.jobs.keys():
		game.jobs[id] = 0
	var pop: int = game.population
	var gather := GameData.find("job", "gatherer")
	var per_gatherer: float = gather["produces"]["food"] * game.job_multiplier("gatherer")
	var food_need: float = pop * game.food_per_second_per_person()
	var gatherers := mini(pop, ceili(food_need * 1.15 / per_gatherer) + 1)
	if game.amounts["food"] < 50.0:
		gatherers = mini(pop, gatherers + 2)
	var elders := 0
	if pop >= 4 and game.iq < game.iq_cap() - 0.5:
		elders = maxi(1, pop / 10)
	var free := pop - gatherers - elders
	var plan := {"gatherer": gatherers, "elder": elders}
	# Most workers go to whatever the next discovery costs (plus that job's inputs);
	# the rest are shared out so buildings and upgrades stay affordable.
	var main := _job_for(_target_resource())
	var focus := int(free * 0.6)
	_staff(plan, main, focus)
	var others: Array = []
	for job in GameData.JOBS:
		if game.job_available(job) and not job["id"] in ["gatherer", "warrior", "elder"] and not job.get("consumes", {}).size() > 0:
			others.append(job)
	var rest := free - _total(plan) + gatherers + elders
	var k := 0
	while rest > 0 and not others.is_empty():
		var job: Dictionary = others[k % others.size()]
		plan[job["id"]] = plan.get(job["id"], 0) + 1
		rest -= 1
		k += 1
	for id in plan:
		game.jobs[id] = plan[id]
	game.rebuild_modifiers()


# Puts `n` workers on a job and enough on its input jobs to keep it supplied.
func _staff(plan: Dictionary, job: Dictionary, n: int) -> void:
	if job.is_empty() or n <= 0:
		return
	var consumes: Dictionary = job.get("consumes", {})
	if consumes.is_empty():
		plan[job["id"]] = plan.get(job["id"], 0) + n
		return
	# Split n between the job and its suppliers in proportion to what they need.
	var weights := {job["id"]: 1.0}
	for res in consumes:
		var supplier := _job_for(res)
		if supplier.is_empty():
			continue
		var per: float = supplier["produces"][res] * game.job_multiplier(supplier["id"])
		weights[supplier["id"]] = weights.get(supplier["id"], 0.0) + consumes[res] / per
	var total := 0.0
	for id in weights:
		total += weights[id]
	for id in weights:
		plan[id] = plan.get(id, 0) + int(n * weights[id] / total)


func _total(plan: Dictionary) -> int:
	var n := 0
	for id in plan:
		n += plan[id]
	return n


func _report(unlocked_at: Dictionary, t: float) -> void:
	print("\nEra unlock times (bot play, no invasions):")
	var prev := 0.0
	for r in GameData.RESOURCES:
		if unlocked_at.has(r["id"]):
			var at: float = unlocked_at[r["id"]]
			var snap: Array = _snapshots.get(r["id"], [0, 0])
			print("  %-12s %9s   (+%s)   people %d, deaths so far %d" % [r["name"], NumFormat.duration(at), NumFormat.duration(at - prev), snap[0], snap[1]])
			prev = at
		else:
			print("  %-12s  not reached" % r["name"])
	print("simulated %s, population %d, items %d, upgrades %d, IQ %.0f, deaths %d, legacy if reborn %d" % [
		NumFormat.duration(t), game.population, game.total_items(), game.upgrades.size(), game.iq, game.run_deaths, game.legacy_gain()])
