class_name EventData
extends RefCounted

const MIN_GAP := 90.0
const MAX_GAP := 180.0
const MAX_ACTIVE := 4
# Each age: the gap between events shrinks (gap / (1 + this * age)) and disasters hit harder.
const GAP_SHRINK_PER_ERA := 0.06
const SEVERITY_PER_ERA := 0.12
# A "destroy": n disaster also wrecks n * this share of all your buildings, if that's more.
const DESTROY_SHARE := 0.005

# Random events, rolled every MIN_GAP..MAX_GAP seconds while the game is open.
#   requires:  resource that must be unlocked (the age it can happen in)
#   weight:    how often it's picked among eligible events
#   when:      min_pop, max_morale, min_morale, max_health, min_health, starving (bool), mine (needs a staffed mine)
#   duration:  seconds it lasts (0 = instant only; -1 = until fixed)
#   effects:   modifiers while active ("$target" = the job picked for mine events)
#   start:     instant results: kill (fraction of people), lose {res: fraction}, destroy (buildings),
#              iq, pop (fraction), gift (fraction of each stockpile), relic, raid (Warriors reduce kill/lose)
#   fix:       optional way to end it early: pay a fraction of current stock ("top" = your biggest stockpile)
const EVENTS := [
	# --- crises ---
	{"id": "wildfire", "name": "Wildfire", "good": false, "requires": "wood", "weight": 2.0, "duration": 0,
		"when": {"min_pop": 4},
		"desc": "The forest burns. Half your wood is gone and people die in the flames.",
		"start": {"lose": {"wood": 0.5}, "kill": 0.08}},
	{"id": "wolves", "name": "Wolf Pack", "good": false, "requires": "wood", "weight": 2.0, "duration": 0,
		"when": {"min_pop": 4},
		"desc": "Wolves raid the camp at night.",
		"start": {"kill": 0.1, "lose": {"food": 0.3}, "raid": true}},
	{"id": "drought", "name": "Drought", "good": false, "requires": "clay", "weight": 3.0, "duration": 150,
		"when": {"min_pop": 6},
		"desc": "The rivers dry up. Gatherers produce 70% less, no babies are born and health falls.",
		"effects": [{"key": "job:gatherer", "mult": 0.3}, {"key": "growth", "mult": 0.0}, {"key": "health", "add": -15}],
		"fix": {"label": "Dig Wells", "pay": {"stone": 0.3, "clay": 0.3}}},
	{"id": "famine", "name": "Famine", "good": false, "requires": "food", "weight": 6.0, "duration": 120,
		"when": {"starving": true, "min_pop": 8},
		"desc": "There isn't enough food to go around. No babies, health and morale collapse.",
		"effects": [{"key": "growth", "mult": 0.0}, {"key": "health", "add": -20}, {"key": "morale", "add": -20}]},
	{"id": "locusts", "name": "Locust Swarm", "good": false, "requires": "clay", "weight": 2.0, "duration": 60,
		"when": {"min_pop": 6},
		"desc": "A cloud of locusts eats 70% of your food and keeps eating the fields.",
		"start": {"lose": {"food": 0.7}},
		"effects": [{"key": "job:gatherer", "mult": 0.5}]},
	{"id": "flood", "name": "Flood", "good": false, "requires": "clay", "weight": 2.0, "duration": 0,
		"when": {"min_pop": 6},
		"desc": "The river bursts its banks, washing away buildings, clay and wood.",
		"start": {"destroy": 2, "lose": {"clay": 0.3, "wood": 0.2}, "kill": 0.03}},
	{"id": "earthquake", "name": "Earthquake", "good": false, "requires": "stone", "weight": 1.5, "duration": 0,
		"when": {"min_pop": 8},
		"desc": "The ground splits open. Buildings collapse on the people inside.",
		"start": {"destroy": 3, "kill": 0.05}},
	{"id": "volcano", "name": "Volcanic Eruption", "good": false, "requires": "bronze", "weight": 0.6, "duration": 180,
		"when": {"min_pop": 20},
		"desc": "Ash blots out the sun. Buildings are buried and everyone works at half speed.",
		"start": {"destroy": 5, "kill": 0.1},
		"effects": [{"key": "job:all", "mult": 0.5}, {"key": "health", "add": -15}]},
	{"id": "plague", "name": "Plague", "good": false, "requires": "food", "weight": 4.0, "duration": 180,
		"when": {"min_pop": 15, "max_health": 45},
		"desc": "Sickness spreads through the crowded town. Health crashes and work slows.",
		"effects": [{"key": "health", "add": -40}, {"key": "job:all", "mult": 0.6}, {"key": "morale", "add": -10}],
		"fix": {"label": "Quarantine", "pay": {"food": 0.4}}},
	{"id": "raiders", "name": "Raiders", "good": false, "requires": "clay", "weight": 2.0, "duration": 0,
		"when": {"min_pop": 10},
		"desc": "Raiders pillage the countryside. Warriors cut the losses.",
		"start": {"kill": 0.08, "lose": {"food": 0.3, "wood": 0.3, "stone": 0.2}, "raid": true}},
	{"id": "tax_revolt", "name": "Tax Revolt", "good": false, "requires": "copper", "weight": 3.0, "duration": 90,
		"when": {"max_morale": 35, "min_pop": 15},
		"desc": "Nobody wants to pay. Work halves until things calm down.",
		"effects": [{"key": "job:all", "mult": 0.5}, {"key": "morale", "add": -10}],
		"fix": {"label": "Lower Taxes", "pay": {"top": 0.25}}},
	{"id": "schism", "name": "Religious Schism", "good": false, "requires": "bronze", "weight": 2.0, "duration": 180,
		"when": {"max_morale": 45, "min_pop": 20},
		"desc": "The faithful split into feuding sects. Morale drops and Elders stop teaching.",
		"effects": [{"key": "morale", "add": -20}, {"key": "teaching", "mult": 0.0}]},
	{"id": "corruption", "name": "Corruption", "good": false, "requires": "iron", "weight": 2.0, "duration": 150,
		"when": {"max_morale": 50, "min_pop": 25},
		"desc": "Officials skim from everything. Crime is three times worse.",
		"effects": [{"key": "crime", "mult": 3.0}, {"key": "morale", "add": -5}],
		"fix": {"label": "Purge the Officials", "pay": {"top": 0.15}}},
	{"id": "civil_war", "name": "Civil War", "good": false, "requires": "copper", "weight": 5.0, "duration": 240,
		"when": {"max_morale": 15, "min_pop": 40},
		"desc": "Rebels rise up. People die, buildings burn and work grinds almost to a halt.",
		"start": {"kill": 0.15, "destroy": 4},
		"effects": [{"key": "job:all", "mult": 0.3}, {"key": "morale", "add": -10}]},
	{"id": "market_crash", "name": "Market Crash", "good": false, "requires": "steel", "weight": 1.5, "duration": 180,
		"when": {"min_pop": 30},
		"desc": "Panic on the markets. Everyone works at half speed.",
		"effects": [{"key": "job:all", "mult": 0.5}, {"key": "morale", "add": -10}]},
	{"id": "hyperinflation", "name": "Hyperinflation", "good": false, "requires": "oil", "weight": 1.5, "duration": 240,
		"when": {"min_pop": 30},
		"desc": "Money is worthless. Buildings cost twice as much.",
		"effects": [{"key": "build_cost", "mult": 2.0}, {"key": "morale", "add": -5}]},
	{"id": "mine_collapse", "name": "Mine Collapse", "good": false, "requires": "coal", "weight": 2.5, "duration": 300,
		"when": {"mine": true},
		"desc": "A shaft caves in on the miners. That mine produces 90% less until it's dug out.",
		"start": {"kill": 0.06},
		"effects": [{"key": "job:$target", "mult": 0.1}, {"key": "morale", "add": -10}],
		"fix": {"label": "Dig Them Out", "pay": {"$target": 0.4}}},
	{"id": "smog", "name": "Killer Smog", "good": false, "requires": "coal", "weight": 2.5, "duration": 300,
		"when": {"min_pop": 30},
		"desc": "Black smoke chokes the city. Health falls and people grow old fast.",
		"effects": [{"key": "health", "add": -30}, {"key": "lifespan", "mult": 0.6}, {"key": "growth", "mult": 0.5}],
		"fix": {"label": "Shut the Furnaces", "pay": {"coal": 0.5}}},
	{"id": "factory_fire", "name": "Factory Fire", "good": false, "requires": "steel", "weight": 2.0, "duration": 0,
		"when": {"min_pop": 30},
		"desc": "A spark in the wrong place. The district burns.",
		"start": {"destroy": 4, "kill": 0.06, "lose": {"steel": 0.3, "oil": 0.3}}},
	{"id": "pandemic", "name": "Pandemic", "good": false, "requires": "electricity", "weight": 3.0, "duration": 300,
		"when": {"min_pop": 50},
		"desc": "A new disease rides the trains everywhere at once.",
		"start": {"kill": 0.08},
		"effects": [{"key": "health", "add": -45}, {"key": "job:all", "mult": 0.5}, {"key": "growth", "mult": 0.3}],
		"fix": {"label": "Lockdown", "pay": {"top": 0.3, "food": 0.3}}},
	{"id": "blackout", "name": "Grid Collapse", "good": false, "requires": "electricity", "weight": 2.0, "duration": 0,
		"when": {"min_pop": 50},
		"desc": "The whole grid fails. Hospitals go dark.",
		"start": {"lose": {"electricity": 0.9}, "kill": 0.04}},
	{"id": "meltdown", "name": "Reactor Meltdown", "good": false, "requires": "uranium", "weight": 2.0, "duration": 600,
		"when": {"min_pop": 80},
		"desc": "The core melts. A whole region becomes poison for years.",
		"start": {"kill": 0.15, "destroy": 6, "lose": {"uranium": 0.5}},
		"effects": [{"key": "health", "add": -40}, {"key": "lifespan", "mult": 0.5}, {"key": "growth", "mult": 0.3}],
		"fix": {"label": "Entomb the Reactor", "pay": {"uranium": 0.5, "steel": 0.5}}},
	{"id": "containment_breach", "name": "Containment Breach", "good": false, "requires": "antimatter", "weight": 2.0, "duration": 0,
		"when": {"min_pop": 100},
		"desc": "The antimatter touches the matter.",
		"start": {"kill": 0.2, "destroy": 10, "lose": {"antimatter": 0.6}}},
	{"id": "void_rift", "name": "Void Rift", "good": false, "requires": "dark_matter", "weight": 2.0, "duration": 300,
		"when": {"min_pop": 100},
		"desc": "Reality tears. People walk into it and don't come back.",
		"start": {"kill": 0.12},
		"effects": [{"key": "morale", "add": -30}, {"key": "job:all", "mult": 0.4}, {"key": "lifespan", "mult": 0.5}],
		"fix": {"label": "Seal the Rift", "pay": {"dark_matter": 0.5}}},
	{"id": "exhaustion", "name": "Mine Exhausted", "good": false, "requires": "copper", "weight": 2.0, "duration": 600,
		"when": {"mine": true},
		"desc": "The seam is running dry. That mine produces 75% less for 10 minutes unless you dig a new shaft.",
		"effects": [{"key": "job:$target", "mult": 0.25}],
		"fix": {"label": "Sink a New Shaft", "pay": {"$target": 0.3}}},

	# --- blessings ---
	{"id": "bumper_crop", "name": "Bumper Crop", "good": true, "requires": "food", "weight": 2.0, "duration": 90,
		"desc": "The berries are everywhere this year. Gatherers produce double.",
		"effects": [{"key": "job:gatherer", "mult": 2.0}]},
	{"id": "fertile_floodplains", "name": "Fertile Floodplains", "good": true, "requires": "clay", "weight": 1.5, "duration": 120,
		"desc": "Gentle floods leave rich soil behind. Population grows twice as fast.",
		"effects": [{"key": "growth", "mult": 2.0}, {"key": "morale", "add": 5}]},
	{"id": "golden_age", "name": "Golden Age", "good": true, "requires": "stone", "weight": 3.0, "duration": 180,
		"when": {"min_morale": 75},
		"desc": "Everything is going right. Work 1.5x, Elders teach twice as fast.",
		"effects": [{"key": "job:all", "mult": 1.5}, {"key": "teaching", "mult": 2.0}, {"key": "morale", "add": 10}]},
	{"id": "trade_caravan", "name": "Trade Caravan", "good": true, "requires": "copper", "weight": 2.0, "duration": 0,
		"desc": "Merchants arrive with goods. +10% of every stockpile.",
		"start": {"gift": 0.1}},
	{"id": "wandering_scholar", "name": "Wandering Scholar", "good": true, "requires": "stone", "weight": 1.5, "duration": 0,
		"desc": "A wise traveller teaches the tribe a thing or two. +5 IQ.",
		"start": {"iq": 5}},
	{"id": "baby_boom", "name": "Baby Boom", "good": true, "requires": "food", "weight": 1.5, "duration": 0,
		"when": {"min_health": 70, "min_pop": 5},
		"desc": "Healthy, happy people make more people. +10% population.",
		"start": {"pop": 0.1}},
	{"id": "lucky_find", "name": "Lucky Find", "good": true, "requires": "wood", "weight": 0.5, "duration": 0,
		"desc": "Someone digs up something shiny. A free relic!",
		"start": {"relic": true}},
]

# Jobs that can have their mine exhausted.
const MINE_JOBS: Array = ["quarrier", "clay_digger", "copper_miner", "iron_miner", "coal_miner", "oil_driller", "uranium_miner"]


static func find(id: String) -> Dictionary:
	for e in EVENTS:
		if e["id"] == id:
			return e
	return {}
