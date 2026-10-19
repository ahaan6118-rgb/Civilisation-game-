# Plays the economy automatically and prints when each era unlocks.
# Run: godot --headless --path . -s tools/balance_bot.gd -- [hours=40] [seed=1] [noevents|events] [stop_at resource]
extends SceneTree

const STEP := 1.0
const THINK_EVERY := 10.0

var game: Node
var hours := 40.0
var _snapshots := {}
var _events := true
var _stop_at := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		hours = float(args[0])
	_events = not (args.size() > 2 and args[2] == "noevents")
	_stop_at = args[3] if args.size() > 3 else ""
	_run.call_deferred(int(args[1]) if args.size() > 1 else 1)


func _run(seed_value: int) -> void:
	game = root.get_node("Game")
	game.set_process(false)
	root.get_node("SaveManager").set_process(false)
	game.reset()
	game.events_enabled = _events
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
				if r["id"] == "antimatter":
					print("antimatter production when unlocked: %s/s" % NumFormat.fmt(game.production_per_second("antimatter")))
		if game.is_unlocked("dark_matter") and t - unlocked_at["dark_matter"] > 600.0:
			break
		if _stop_at != "" and game.is_unlocked(_stop_at):
			break
	_report(unlocked_at, t)
	quit()


# An active player: about a click a second to hold back decay, plus lots of gathering early on.
func _click_a_bit() -> void:
	for i in (30 if game.population <= 40 else 10):
		game.click_gather(_target_resource())


func _think() -> void:
	for t in GameData.TECHS:
		if game.tech_available(t) and game.research(t["id"]):
			break
	_buy_things()
	for i in range(game.events.size() - 1, -1, -1):
		var data := EventData.find(game.events[i]["id"])
		if data.has("fix") and _cheap(game.fix_cost(game.events[i]), 0.5):
			game.fix_event(i)
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
				if e["key"] == "morale" and game.morale < 60.0 and game.buildings.get(b["id"], 0) < 8:
					useful = true
				if e["key"] == "health" and game.health < 60.0 and game.buildings.get(b["id"], 0) < 8:
					useful = true
				if e["key"] == "iq_cap" and game.iq >= game.iq_cap() - 1.0 and game.buildings.get(b["id"], 0) < 5:
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


# Puts `n` workers on a job and enough on its whole supply chain to keep it running.
func _staff(plan: Dictionary, job: Dictionary, n: int) -> void:
	if job.is_empty() or n <= 0:
		return
	var weights := {}
	_chain_weights(job, 1.0, weights, 0)
	var total := 0.0
	for id in weights:
		total += weights[id]
	for id in weights:
		var share: float = n * weights[id] / total
		# Suppliers can be so productive their share rounds to zero; always keep one on the job.
		plan[id] = plan.get(id, 0) + (int(share) if id == job["id"] else maxi(1, ceili(share)))


# Workers needed per worker of `job`, for it and (recursively) every input it consumes.
func _chain_weights(job: Dictionary, amount: float, weights: Dictionary, depth: int) -> void:
	weights[job["id"]] = weights.get(job["id"], 0.0) + amount
	if depth > 4:
		return
	var consumes: Dictionary = job.get("consumes", {})
	for res in consumes:
		var supplier := _job_for(res)
		if supplier.is_empty() or supplier["id"] == job["id"]:
			continue
		var per: float = supplier["produces"][res] * maxf(game.job_multiplier(supplier["id"]), 1e-6)
		_chain_weights(supplier, amount * consumes[res] * 1.2 / per, weights, depth + 1)


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
	var next := _next_tech()
	if not next.is_empty():
		for res in next["cost"]:
			print("next: %s needs %s %s; have %s, making %s/s" % [next["name"], NumFormat.fmt(next["cost"][res]), res,
				NumFormat.fmt(game.amounts[res]), NumFormat.fmt(game.production_per_second(res))])
		for res in ["coal", "electricity", "antimatter"]:
			if game.is_unlocked(res):
				print("  %s: actual %s/s, stock %s" % [res, NumFormat.fmt(game.rates.get(res, 0.0)), NumFormat.fmt(game.amounts[res])])
		var staffed: PackedStringArray = []
		for id in game.jobs:
			if game.jobs[id] > 0:
				staffed.append("%s %d" % [id, game.jobs[id]])
		print("  jobs: " + ", ".join(staffed))
	print("simulated %s, population %d, items %d, upgrades %d, IQ %.0f, morale %.0f, health %.0f, deaths %d, legacy if reborn %d" % [
		NumFormat.duration(t), game.population, game.total_items(), game.upgrades.size(), game.iq, game.morale, game.health, game.run_deaths, game.legacy_gain()])
