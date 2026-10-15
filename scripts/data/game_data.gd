class_name GameData
extends RefCounted

# spoil = fraction of the stockpile lost per second (only while the game is open).
const RESOURCES := [
	{"id": "food", "name": "Food", "spoil": 0.005, "clickable": true},
	{"id": "wood", "name": "Wood", "clickable": true},
	{"id": "stone", "name": "Stone", "clickable": true},
	{"id": "clay", "name": "Clay", "clickable": true},
	{"id": "copper", "name": "Copper"},
	{"id": "bronze", "name": "Bronze"},
	{"id": "iron", "name": "Iron"},
	{"id": "coal", "name": "Coal"},
	{"id": "steel", "name": "Steel"},
	{"id": "oil", "name": "Oil"},
	{"id": "electricity", "name": "Electricity", "spoil": 0.02},
	{"id": "silicon", "name": "Silicon"},
	{"id": "uranium", "name": "Uranium", "spoil": 0.001},
	{"id": "antimatter", "name": "Antimatter", "spoil": 0.01},
	{"id": "dark_matter", "name": "Dark Matter"},
]

const STARTING_RESOURCES := ["food", "wood"]

# Each discovery spends its cost and unlocks the next rung of the ladder.
const TECHS := [
	{"id": "stone_working", "name": "Stone Working", "requires": "", "unlocks": "stone", "cost": {"wood": 1e3},
		"desc": "Shape rocks into tools. Unlocks Stone."},
	{"id": "pottery", "name": "Pottery", "requires": "stone_working", "unlocks": "clay", "cost": {"stone": 1e4},
		"desc": "Dig and fire clay. Unlocks Clay."},
	{"id": "copper_smelting", "name": "Copper Smelting", "requires": "pottery", "unlocks": "copper", "cost": {"clay": 1e5},
		"desc": "Kilns hot enough to melt ore. Unlocks Copper."},
	{"id": "bronze_casting", "name": "Bronze Casting", "requires": "copper_smelting", "unlocks": "bronze", "cost": {"copper": 1e6},
		"desc": "Alloy copper into bronze. Unlocks Bronze."},
	{"id": "iron_working", "name": "Iron Working", "requires": "bronze_casting", "unlocks": "iron", "cost": {"bronze": 1e7},
		"desc": "Bloomeries and forges. Unlocks Iron."},
	{"id": "coal_mining", "name": "Coal Mining", "requires": "iron_working", "unlocks": "coal", "cost": {"iron": 1e8},
		"desc": "Dig deep for black rock. Unlocks Coal."},
	{"id": "steel_making", "name": "Steel Making", "requires": "coal_mining", "unlocks": "steel", "cost": {"coal": 1e9},
		"desc": "Blast furnaces. Unlocks Steel."},
	{"id": "drilling", "name": "Drilling", "requires": "steel_making", "unlocks": "oil", "cost": {"steel": 1e10},
		"desc": "Steel rigs reach oil. Unlocks Oil."},
	{"id": "electrification", "name": "Electrification", "requires": "drilling", "unlocks": "electricity", "cost": {"oil": 1e11},
		"desc": "Generators and wires. Unlocks Electricity."},
	{"id": "semiconductors", "name": "Semiconductors", "requires": "electrification", "unlocks": "silicon", "cost": {"electricity": 1e12},
		"desc": "Purify sand into chips. Unlocks Silicon."},
	{"id": "nuclear_fission", "name": "Nuclear Fission", "requires": "semiconductors", "unlocks": "uranium", "cost": {"silicon": 1e13},
		"desc": "Split the atom. Unlocks Uranium."},
	{"id": "particle_physics", "name": "Particle Physics", "requires": "nuclear_fission", "unlocks": "antimatter", "cost": {"uranium": 1e14},
		"desc": "Capture antiparticles. Unlocks Antimatter."},
	{"id": "void_theory", "name": "Void Theory", "requires": "particle_physics", "unlocks": "dark_matter", "cost": {"antimatter": 1e15},
		"desc": "Harvest the unseen. Unlocks Dark Matter."},
]

# Rates are per worker per second. A job appears once its "requires" resource is unlocked.
const JOBS := [
	{"id": "gatherer", "name": "Gatherer", "requires": "food", "produces": {"food": 0.5}},
	{"id": "woodcutter", "name": "Woodcutter", "requires": "wood", "produces": {"wood": 1.0}},
	{"id": "quarrier", "name": "Quarrier", "requires": "stone", "produces": {"stone": 1.0}},
	{"id": "clay_digger", "name": "Clay Digger", "requires": "clay", "produces": {"clay": 4.0}},
	{"id": "copper_miner", "name": "Copper Miner", "requires": "copper", "produces": {"copper": 15.0}},
	{"id": "bronzesmith", "name": "Bronzesmith", "requires": "bronze", "produces": {"bronze": 40.0}, "consumes": {"copper": 20.0}},
	{"id": "iron_miner", "name": "Iron Miner", "requires": "iron", "produces": {"iron": 150.0}},
	{"id": "coal_miner", "name": "Coal Miner", "requires": "coal", "produces": {"coal": 600.0}},
	{"id": "steelworker", "name": "Steelworker", "requires": "steel", "produces": {"steel": 2000.0}, "consumes": {"iron": 500.0, "coal": 500.0}},
	{"id": "oil_driller", "name": "Oil Driller", "requires": "oil", "produces": {"oil": 8000.0}},
	{"id": "power_plant_operator", "name": "Power Plant Operator", "requires": "electricity", "produces": {"electricity": 3e4}, "consumes": {"coal": 2000.0}},
	{"id": "chip_maker", "name": "Chip Maker", "requires": "silicon", "produces": {"silicon": 1.2e5}, "consumes": {"electricity": 2e4}},
	{"id": "uranium_miner", "name": "Uranium Miner", "requires": "uranium", "produces": {"uranium": 5e5}},
	{"id": "physicist", "name": "Physicist", "requires": "antimatter", "produces": {"antimatter": 2e6}, "consumes": {"electricity": 1e5}},
	{"id": "void_engineer", "name": "Void Engineer", "requires": "dark_matter", "produces": {"dark_matter": 1e7}, "consumes": {"antimatter": 1e6}},
]

# Effects: {"key": ..., "add": n} adds n per building; {"key": ..., "mult": m} multiplies by m per building.
# Keys: pop_cap, growth, click, click:<resource>, job:<job>, job:all, spoil:<resource>, food_use.
const BUILDINGS := [
	{"id": "hut", "name": "Hut", "requires": "wood", "cost": {"wood": 15.0}, "scale": 1.15,
		"desc": "+3 max population.", "effects": [{"key": "pop_cap", "add": 3}]},
	{"id": "granary", "name": "Granary", "requires": "stone", "cost": {"wood": 100.0, "stone": 50.0}, "scale": 1.3,
		"desc": "Food spoils 10% slower.", "effects": [{"key": "spoil:food", "mult": 0.9}]},
	{"id": "stone_house", "name": "Stone House", "requires": "stone", "cost": {"stone": 200.0}, "scale": 1.15,
		"desc": "+8 max population.", "effects": [{"key": "pop_cap", "add": 8}]},
	{"id": "brick_house", "name": "Brick House", "requires": "clay", "cost": {"clay": 1500.0}, "scale": 1.15,
		"desc": "+20 max population.", "effects": [{"key": "pop_cap", "add": 20}]},
	{"id": "townhouse", "name": "Townhouse", "requires": "iron", "cost": {"iron": 5e4, "bronze": 2e4}, "scale": 1.15,
		"desc": "+60 max population.", "effects": [{"key": "pop_cap", "add": 60}]},
	{"id": "apartment", "name": "Apartment", "requires": "steel", "cost": {"steel": 1e6}, "scale": 1.15,
		"desc": "+200 max population.", "effects": [{"key": "pop_cap", "add": 200}]},
	{"id": "battery", "name": "Battery", "requires": "electricity", "cost": {"steel": 5e8, "copper": 1e9}, "scale": 1.3,
		"desc": "Electricity drains 15% slower.", "effects": [{"key": "spoil:electricity", "mult": 0.85}]},
	{"id": "arcology", "name": "Arcology", "requires": "silicon", "cost": {"silicon": 1e9, "steel": 1e10}, "scale": 1.15,
		"desc": "+1500 max population.", "effects": [{"key": "pop_cap", "add": 1500}]},
]

const UPGRADES := [
	{"id": "baskets", "name": "Baskets", "requires": "wood", "cost": {"wood": 30.0},
		"desc": "Gatherers produce 50% more.", "effects": [{"key": "job:gatherer", "mult": 1.5}]},
	{"id": "sharp_sticks", "name": "Sharp Sticks", "requires": "wood", "cost": {"wood": 75.0},
		"desc": "Clicking gathers 2x.", "effects": [{"key": "click", "mult": 2.0}]},
	{"id": "campfire_stories", "name": "Campfire Stories", "requires": "wood", "cost": {"wood": 250.0, "food": 100.0},
		"desc": "Population grows 50% faster.", "effects": [{"key": "growth", "mult": 1.5}]},
	{"id": "stone_axes", "name": "Stone Axes", "requires": "stone", "cost": {"stone": 100.0},
		"desc": "Woodcutters produce 2x.", "effects": [{"key": "job:woodcutter", "mult": 2.0}]},
	{"id": "stone_picks", "name": "Stone Picks", "requires": "stone", "cost": {"stone": 400.0, "wood": 1000.0},
		"desc": "Quarriers produce 2x.", "effects": [{"key": "job:quarrier", "mult": 2.0}]},
	{"id": "spears", "name": "Spears", "requires": "stone", "cost": {"stone": 1500.0},
		"desc": "Gatherers hunt too: 2x food.", "effects": [{"key": "job:gatherer", "mult": 2.0}]},
	{"id": "clay_pots", "name": "Clay Pots", "requires": "clay", "cost": {"clay": 2000.0},
		"desc": "Food spoils 30% slower.", "effects": [{"key": "spoil:food", "mult": 0.7}]},
	{"id": "kilns", "name": "Kilns", "requires": "clay", "cost": {"clay": 2e4, "wood": 5e4},
		"desc": "Clay Diggers produce 2x.", "effects": [{"key": "job:clay_digger", "mult": 2.0}]},
	{"id": "copper_tools", "name": "Copper Tools", "requires": "copper", "cost": {"copper": 5000.0},
		"desc": "Quarriers 3x, Clay Diggers 2x.", "effects": [{"key": "job:quarrier", "mult": 3.0}, {"key": "job:clay_digger", "mult": 2.0}]},
	{"id": "irrigation", "name": "Irrigation", "requires": "copper", "cost": {"copper": 2e4, "clay": 1e5},
		"desc": "Gatherers become farmers: 3x food.", "effects": [{"key": "job:gatherer", "mult": 3.0}]},
	{"id": "bronze_tools", "name": "Bronze Tools", "requires": "bronze", "cost": {"bronze": 5e4},
		"desc": "All workers produce 2x.", "effects": [{"key": "job:all", "mult": 2.0}]},
	{"id": "iron_tools", "name": "Iron Tools", "requires": "iron", "cost": {"iron": 5e5},
		"desc": "All workers produce 2x.", "effects": [{"key": "job:all", "mult": 2.0}]},
	{"id": "steam_engine", "name": "Steam Engine", "requires": "coal", "cost": {"coal": 5e6, "iron": 1e7},
		"desc": "All workers produce 3x.", "effects": [{"key": "job:all", "mult": 3.0}]},
	{"id": "refrigeration", "name": "Refrigeration", "requires": "electricity", "cost": {"electricity": 1e10},
		"desc": "Food spoils 75% slower.", "effects": [{"key": "spoil:food", "mult": 0.25}]},
	{"id": "automation", "name": "Automation", "requires": "silicon", "cost": {"silicon": 1e11},
		"desc": "All workers produce 5x.", "effects": [{"key": "job:all", "mult": 5.0}]},
]

static var _index: Dictionary = {}


static func find(list_name: String, id: String) -> Dictionary:
	if _index.is_empty():
		for pair in [["resource", RESOURCES], ["tech", TECHS], ["job", JOBS], ["building", BUILDINGS], ["upgrade", UPGRADES]]:
			for entry in pair[1]:
				_index["%s:%s" % [pair[0], entry["id"]]] = entry
	return _index.get("%s:%s" % [list_name, id], {})


static func resource_name(id: String) -> String:
	return find("resource", id).get("name", id)
