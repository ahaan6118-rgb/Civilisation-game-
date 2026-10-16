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
	{"id": "warfare", "name": "Warfare", "requires": "pottery", "unlocks": "", "cost": {"stone": 5000.0, "clay": 2000.0},
		"desc": "Unlocks Warriors and invading other countries."},
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

# Rates are per worker per second. A job appears once its "requires" resource (and "requires_tech", if any) is unlocked.
const JOBS := [
	{"id": "gatherer", "name": "Gatherer", "requires": "food", "produces": {"food": 0.5}},
	{"id": "woodcutter", "name": "Woodcutter", "requires": "wood", "produces": {"wood": 1.0}},
	{"id": "quarrier", "name": "Quarrier", "requires": "stone", "produces": {"stone": 1.0}},
	{"id": "clay_digger", "name": "Clay Digger", "requires": "clay", "produces": {"clay": 4.0}},
	{"id": "warrior", "name": "Warrior", "requires": "clay", "requires_tech": "warfare", "produces": {}, "consumes": {"food": 0.25},
		"note": "+50 troops"},
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

# Effects: {"key": k, "add": n} adds n per copy; {"key": k, "mult": m} multiplies by m per copy;
# {"key": k, "per": counter, "pct": p} multiplies by (1 + p * counter), see Game.count_of() for counters.
# Keys: pop_cap, growth, click, click:<resource>, click_cps (click also gives this fraction of the
# resource's production/s), job:<job>, job:all, spoil:<resource>, food_use, craft_speed, luck, auto_craft,
# army:size, army:regen, army:attack.
const BUILDINGS := [
	{"id": "hut", "name": "Hut", "requires": "wood", "cost": {"wood": 15.0}, "scale": 1.15,
		"desc": "+3 max population.", "effects": [{"key": "pop_cap", "add": 3}]},
	{"id": "granary", "name": "Granary", "requires": "stone", "cost": {"wood": 100.0, "stone": 50.0}, "scale": 1.3,
		"desc": "Food spoils 10% slower.", "effects": [{"key": "spoil:food", "mult": 0.9}]},
	{"id": "stone_house", "name": "Stone House", "requires": "stone", "cost": {"stone": 200.0}, "scale": 1.15,
		"desc": "+8 max population.", "effects": [{"key": "pop_cap", "add": 8}]},
	{"id": "brick_house", "name": "Brick House", "requires": "clay", "cost": {"clay": 1500.0}, "scale": 1.15,
		"desc": "+20 max population.", "effects": [{"key": "pop_cap", "add": 20}]},
	{"id": "artisan", "name": "Artisan", "requires": "clay", "cost": {"wood": 100.0, "stone": 2000.0, "clay": 300.0}, "scale": 1.5,
		"desc": "Crafts random items. Each Artisan works on one commission at a time.", "effects": []},
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

	# --- the silly ones. "unlock" conditions must be met once before the upgrade shows up. ---
	# clicking
	{"id": "calloused_hands", "name": "Calloused Hands", "requires": "wood", "cost": {"wood": 200.0}, "unlock": [{"clicks": 50}],
		"desc": "Clicking gathers 2x.", "flavor": "",
		"effects": [{"key": "click", "mult": 2.0}]},
	{"id": "opposable_thumbs", "name": "Opposable Thumbs", "requires": "wood", "cost": {"wood": 600.0}, "unlock": [{"lifetime": "wood", "amount": 500.0}],
		"desc": "Clicks also give 1% of that resource's production per second.", "flavor": "",
		"effects": [{"key": "click_cps", "add": 0.01}]},
	{"id": "aggressive_pointing", "name": "Aggressive Pointing", "requires": "wood", "cost": {"wood": 5000.0}, "unlock": [{"clicks": 500}],
		"desc": "Clicks give another 2% of production per second.", "flavor": "",
		"effects": [{"key": "click_cps", "add": 0.02}]},
	{"id": "carpal_tunnel", "name": "Carpal Tunnel Syndrome", "requires": "stone", "cost": {"stone": 2e4}, "unlock": [{"clicks": 2000}],
		"desc": "Clicking gathers 3x.", "flavor": "",
		"effects": [{"key": "click", "mult": 3.0}]},

	# gatherers
	{"id": "berry_obsession", "name": "Berry Obsession", "requires": "wood", "cost": {"wood": 50.0}, "unlock": [{"job": "gatherer", "count": 1}],
		"desc": "Gatherers produce 50% more.", "flavor": "",
		"effects": [{"key": "job:gatherer", "mult": 1.5}]},
	{"id": "pocket_pants", "name": "Pocket Pants", "requires": "wood", "cost": {"wood": 1500.0}, "unlock": [{"job": "gatherer", "count": 10}],
		"desc": "Gatherers produce 2x.", "flavor": "",
		"effects": [{"key": "job:gatherer", "mult": 2.0}]},
	{"id": "hot_rock_cooking", "name": "Hot Rock Cooking", "requires": "stone", "cost": {"stone": 3000.0}, "unlock": [{"job": "gatherer", "count": 25}],
		"desc": "People eat 20% less.", "flavor": "",
		"effects": [{"key": "food_use", "mult": 0.8}]},
	{"id": "sniff_test", "name": "The Sniff Test", "requires": "wood", "cost": {"food": 400.0}, "unlock": [{"lifetime": "food", "amount": 1000.0}],
		"desc": "Food spoils 20% slower.", "flavor": "",
		"effects": [{"key": "spoil:food", "mult": 0.8}]},
	{"id": "five_second_rule", "name": "Five-Second Rule", "requires": "stone", "cost": {"food": 2000.0, "stone": 500.0}, "unlock": [{"lifetime": "food", "amount": 1e4}],
		"desc": "Food spoils 20% slower.", "flavor": "",
		"effects": [{"key": "spoil:food", "mult": 0.8}]},

	# woodcutters
	{"id": "angry_beavers", "name": "Angry Beavers", "requires": "wood", "cost": {"wood": 100.0}, "unlock": [{"job": "woodcutter", "count": 1}],
		"desc": "Woodcutters produce 2x.", "flavor": "",
		"effects": [{"key": "job:woodcutter", "mult": 2.0}]},
	{"id": "lumberjack_plaid", "name": "Lumberjack Plaid", "requires": "wood", "cost": {"wood": 2000.0}, "unlock": [{"job": "woodcutter", "count": 10}],
		"desc": "Woodcutters produce 2x.", "flavor": "",
		"effects": [{"key": "job:woodcutter", "mult": 2.0}]},
	{"id": "shouting_timber", "name": "Shouting TIMBER", "requires": "stone", "cost": {"wood": 2e4, "stone": 5000.0}, "unlock": [{"job": "woodcutter", "count": 25}],
		"desc": "Woodcutters produce 2x.", "flavor": "",
		"effects": [{"key": "job:woodcutter", "mult": 2.0}]},
	{"id": "tree_diplomacy", "name": "Tree Diplomacy", "requires": "clay", "cost": {"clay": 1e5}, "unlock": [{"job": "woodcutter", "count": 50}],
		"desc": "Woodcutters produce 3x.", "flavor": "",
		"effects": [{"key": "job:woodcutter", "mult": 3.0}]},

	# quarriers
	{"id": "rock_appreciation", "name": "Rock Appreciation Society", "requires": "stone", "cost": {"stone": 200.0}, "unlock": [{"job": "quarrier", "count": 1}],
		"desc": "Quarriers produce 2x.", "flavor": "",
		"effects": [{"key": "job:quarrier", "mult": 2.0}]},
	{"id": "bigger_rock", "name": "Hitting Rock With Bigger Rock", "requires": "stone", "cost": {"stone": 2500.0}, "unlock": [{"job": "quarrier", "count": 10}],
		"desc": "Quarriers produce 2x.", "flavor": "",
		"effects": [{"key": "job:quarrier", "mult": 2.0}]},
	{"id": "pet_rocks", "name": "Pet Rocks", "requires": "stone", "cost": {"stone": 2e4, "clay": 1000.0}, "unlock": [{"job": "quarrier", "count": 25}],
		"desc": "Quarriers 2x, population grows 10% faster.", "flavor": "",
		"effects": [{"key": "job:quarrier", "mult": 2.0}, {"key": "growth", "mult": 1.1}]},

	# clay diggers
	{"id": "mud_enthusiasts", "name": "Mud Enthusiasts", "requires": "clay", "cost": {"clay": 500.0}, "unlock": [{"job": "clay_digger", "count": 1}],
		"desc": "Clay Diggers produce 2x.", "flavor": "",
		"effects": [{"key": "job:clay_digger", "mult": 2.0}]},
	{"id": "mud_spa", "name": "Mud Bath Spa", "requires": "clay", "cost": {"clay": 1e4}, "unlock": [{"job": "clay_digger", "count": 10}],
		"desc": "Clay Diggers 2x, population grows 20% faster.", "flavor": "",
		"effects": [{"key": "job:clay_digger", "mult": 2.0}, {"key": "growth", "mult": 1.2}]},

	# synergies between jobs and buildings
	{"id": "wheelbarrows", "name": "Wooden Wheelbarrows", "requires": "stone", "cost": {"wood": 5000.0, "stone": 2000.0},
		"unlock": [{"job": "woodcutter", "count": 10}, {"job": "quarrier", "count": 10}],
		"desc": "Quarriers +1% per Woodcutter. Woodcutters +0.5% per Quarrier.", "flavor": "",
		"effects": [{"key": "job:quarrier", "per": "job:woodcutter", "pct": 0.01}, {"key": "job:woodcutter", "per": "job:quarrier", "pct": 0.005}]},
	{"id": "mud_pies", "name": "Mud Pies", "requires": "clay", "cost": {"clay": 3000.0, "food": 1000.0},
		"unlock": [{"job": "gatherer", "count": 5}, {"job": "clay_digger", "count": 5}],
		"desc": "Gatherers +2% per Clay Digger.", "flavor": "",
		"effects": [{"key": "job:gatherer", "per": "job:clay_digger", "pct": 0.02}]},
	{"id": "hut_parties", "name": "Hut Parties", "requires": "wood", "cost": {"wood": 3000.0, "food": 500.0}, "unlock": [{"building": "hut", "count": 10}],
		"desc": "Population grows 5% faster per Hut.", "flavor": "",
		"effects": [{"key": "growth", "per": "building:hut", "pct": 0.05}]},
	{"id": "inventing_marriage", "name": "Inventing Marriage", "requires": "wood", "cost": {"wood": 1500.0, "food": 300.0}, "unlock": [{"population": 15}],
		"desc": "Population grows 2x faster.", "flavor": "",
		"effects": [{"key": "growth", "mult": 2.0}]},
	{"id": "crowd_surfing", "name": "Crowd Surfing", "requires": "stone", "cost": {"stone": 8000.0}, "unlock": [{"population": 30}],
		"desc": "All workers +0.5% per person.", "flavor": "",
		"effects": [{"key": "job:all", "per": "population", "pct": 0.005}]},

	# artisans and items
	{"id": "arts_and_crafts", "name": "Arts and Crafts Hour", "requires": "clay", "cost": {"clay": 2000.0, "wood": 5000.0}, "unlock": [{"building": "artisan", "count": 1}],
		"desc": "Commissions finish 50% faster.", "flavor": "",
		"effects": [{"key": "craft_speed", "mult": 1.5}]},
	{"id": "bribing_the_gods", "name": "Bribing the Gods", "requires": "clay", "cost": {"food": 5000.0, "clay": 5000.0}, "unlock": [{"items": 3}],
		"desc": "Rare items are 50% more likely.", "flavor": "",
		"effects": [{"key": "luck", "mult": 1.5}]},
	{"id": "unpaid_interns", "name": "Unpaid Interns", "requires": "clay", "cost": {"clay": 1e4, "stone": 2e4}, "unlock": [{"building": "artisan", "count": 3}],
		"desc": "Idle Artisans start a new commission on their own when you can afford it.", "flavor": "",
		"effects": [{"key": "auto_craft", "add": 1}]},
	{"id": "hoarding_instinct", "name": "Hoarding Instinct", "requires": "clay", "cost": {"clay": 2e4}, "unlock": [{"items": 5}],
		"desc": "All workers +2% per item owned.", "flavor": "",
		"effects": [{"key": "job:all", "per": "items", "pct": 0.02}]},

	# army
	{"id": "pointy_sticks", "name": "Pointy Sticks", "requires": "clay", "cost": {"stone": 3000.0, "wood": 5000.0}, "unlock": [{"job": "warrior", "count": 1}],
		"desc": "Troops conquer land 25% cheaper.", "flavor": "",
		"effects": [{"key": "army:attack", "mult": 1.25}]},
	{"id": "war_drums", "name": "War Drums", "requires": "clay", "cost": {"wood": 2e4, "clay": 5000.0}, "unlock": [{"job": "warrior", "count": 10}],
		"desc": "Troops regenerate 50% faster.", "flavor": "",
		"effects": [{"key": "army:regen", "mult": 1.5}]},
	{"id": "standing_army", "name": "Standing Army", "requires": "clay", "cost": {"food": 1e4, "clay": 2e4}, "unlock": [{"population": 50}],
		"desc": "Army size and max troops 1.5x.", "flavor": "",
		"effects": [{"key": "army:size", "mult": 1.5}]},
	{"id": "bronze_spears", "name": "Bronze Spears", "requires": "bronze", "cost": {"bronze": 1e5}, "unlock": [{"job": "warrior", "count": 25}],
		"desc": "Troops conquer land 50% cheaper.", "flavor": "",
		"effects": [{"key": "army:attack", "mult": 1.5}]},
	{"id": "iron_swords", "name": "Iron Swords", "requires": "iron", "cost": {"iron": 1e6}, "unlock": [{"job": "warrior", "count": 50}],
		"desc": "Troops conquer land 2x cheaper.", "flavor": "",
		"effects": [{"key": "army:attack", "mult": 2.0}]},

	# later eras
	{"id": "shiny_rocks", "name": "Ooh, Shiny", "requires": "copper", "cost": {"copper": 2000.0}, "unlock": [{"job": "copper_miner", "count": 1}],
		"desc": "Copper Miners produce 2x.", "flavor": "",
		"effects": [{"key": "job:copper_miner", "mult": 2.0}]},
	{"id": "midlife_crisis", "name": "Bronze Age Midlife Crisis", "requires": "bronze", "cost": {"bronze": 2e5}, "unlock": [{"job": "bronzesmith", "count": 10}],
		"desc": "All workers produce 1.5x.", "flavor": "",
		"effects": [{"key": "job:all", "mult": 1.5}]},
	{"id": "heavy_metal", "name": "Heavy Metal", "requires": "iron", "cost": {"iron": 1e6}, "unlock": [{"job": "iron_miner", "count": 10}],
		"desc": "Iron Miners produce 3x.", "flavor": "",
		"effects": [{"key": "job:iron_miner", "mult": 3.0}]},
	{"id": "coal_for_christmas", "name": "Coal for Christmas", "requires": "coal", "cost": {"coal": 1e7}, "unlock": [{"job": "coal_miner", "count": 10}],
		"desc": "Coal Miners produce 2x.", "flavor": "",
		"effects": [{"key": "job:coal_miner", "mult": 2.0}]},
	{"id": "oil_baron_mustache", "name": "Oil Baron Mustache", "requires": "oil", "cost": {"oil": 1e9}, "unlock": [{"job": "oil_driller", "count": 10}],
		"desc": "Oil Drillers produce 3x.", "flavor": "",
		"effects": [{"key": "job:oil_driller", "mult": 3.0}]},
	{"id": "off_and_on", "name": "Turning It Off and On Again", "requires": "electricity", "cost": {"electricity": 1e10}, "unlock": [{"job": "power_plant_operator", "count": 10}],
		"desc": "Power Plant Operators produce 2x.", "flavor": "",
		"effects": [{"key": "job:power_plant_operator", "mult": 2.0}]},
	{"id": "download_more_ram", "name": "Downloading More RAM", "requires": "silicon", "cost": {"silicon": 1e11}, "unlock": [{"job": "chip_maker", "count": 10}],
		"desc": "Chip Makers produce 3x.", "flavor": "",
		"effects": [{"key": "job:chip_maker", "mult": 3.0}]},
	{"id": "glow_in_the_dark", "name": "Glow-in-the-Dark Workers", "requires": "uranium", "cost": {"uranium": 1e12}, "unlock": [{"job": "uranium_miner", "count": 10}],
		"desc": "Uranium Miners 3x, population grows 10% slower.", "flavor": "",
		"effects": [{"key": "job:uranium_miner", "mult": 3.0}, {"key": "growth", "mult": 0.9}]},
	{"id": "deleted_the_moon", "name": "Accidentally Deleting the Moon", "requires": "antimatter", "cost": {"antimatter": 1e13}, "unlock": [{"job": "physicist", "count": 10}],
		"desc": "Physicists produce 3x.", "flavor": "",
		"effects": [{"key": "job:physicist", "mult": 3.0}]},
	{"id": "staring_into_void", "name": "Staring Into the Void", "requires": "dark_matter", "cost": {"dark_matter": 1e14}, "unlock": [{"job": "void_engineer", "count": 10}],
		"desc": "Void Engineers produce 3x.", "flavor": "",
		"effects": [{"key": "job:void_engineer", "mult": 3.0}]},
]

# --- items ---------------------------------------------------------------------

const RARITIES := {
	"common": {"name": "Common", "weight": 60.0, "color": Color(0.85, 0.85, 0.85)},
	"uncommon": {"name": "Uncommon", "weight": 28.0, "color": Color(0.45, 0.9, 0.45)},
	"rare": {"name": "Rare", "weight": 10.0, "color": Color(0.4, 0.65, 1.0)},
	"legendary": {"name": "Legendary", "weight": 2.0, "color": Color(1.0, 0.7, 0.2)},
}

# A maker is a building that crafts items: each copy runs one commission at a time.
const MAKERS := [
	{"id": "artisan", "name": "Artisan", "building": "artisan", "time": 60.0,
		"cost": {"wood": 500.0, "stone": 1000.0, "clay": 200.0}, "cost_scale": 1.12},
]

# Items stack: every copy applies its effects again.
const ITEMS := [
	{"id": "lucky_pebble", "name": "Lucky Pebble", "maker": "artisan", "rarity": "common",
		"desc": "Clicking gathers 1.5x.", "flavor": "",
		"effects": [{"key": "click", "mult": 1.5}]},
	{"id": "clay_figurine", "name": "Clay Figurine", "maker": "artisan", "rarity": "common",
		"desc": "Population grows 25% faster.", "flavor": "",
		"effects": [{"key": "growth", "mult": 1.25}]},
	{"id": "woven_basket", "name": "Woven Basket", "maker": "artisan", "rarity": "common",
		"desc": "Gatherers produce 30% more.", "flavor": "",
		"effects": [{"key": "job:gatherer", "mult": 1.3}]},
	{"id": "flint_knife", "name": "Flint Knife", "maker": "artisan", "rarity": "common",
		"desc": "Woodcutters produce 30% more.", "flavor": "",
		"effects": [{"key": "job:woodcutter", "mult": 1.3}]},
	{"id": "carved_totem", "name": "Carved Totem", "maker": "artisan", "rarity": "uncommon",
		"desc": "All workers produce 10% more.", "flavor": "",
		"effects": [{"key": "job:all", "mult": 1.1}]},
	{"id": "painted_pot", "name": "Painted Pot", "maker": "artisan", "rarity": "uncommon",
		"desc": "Food spoils 15% slower.", "flavor": "",
		"effects": [{"key": "spoil:food", "mult": 0.85}]},
	{"id": "bone_flute", "name": "Bone Flute", "maker": "artisan", "rarity": "uncommon",
		"desc": "Population grows 40% faster.", "flavor": "",
		"effects": [{"key": "growth", "mult": 1.4}]},
	{"id": "stone_wheel", "name": "Stone Wheel", "maker": "artisan", "rarity": "rare",
		"desc": "Quarriers produce 2x.", "flavor": "",
		"effects": [{"key": "job:quarrier", "mult": 2.0}]},
	{"id": "obsidian_mirror", "name": "Obsidian Mirror", "maker": "artisan", "rarity": "rare",
		"desc": "Clicks also give 3% of production per second.", "flavor": "",
		"effects": [{"key": "click_cps", "add": 0.03}]},
	{"id": "tusk_necklace", "name": "Mammoth Tusk Necklace", "maker": "artisan", "rarity": "rare",
		"desc": "People eat 20% less.", "flavor": "",
		"effects": [{"key": "food_use", "mult": 0.8}]},
	{"id": "idol_of_plenty", "name": "Idol of Plenty", "maker": "artisan", "rarity": "legendary",
		"desc": "All workers produce 1.5x.", "flavor": "",
		"effects": [{"key": "job:all", "mult": 1.5}]},
	{"id": "the_first_brick", "name": "The First Brick", "maker": "artisan", "rarity": "legendary",
		"desc": "+25 max population, Clay Diggers 3x.", "flavor": "",
		"effects": [{"key": "pop_cap", "add": 25}, {"key": "job:clay_digger", "mult": 3.0}]},
]

# Owning every listed item activates the synergy once.
const SYNERGIES := [
	{"id": "hunter_gatherer", "name": "Hunter-Gatherer", "items": ["woven_basket", "flint_knife"],
		"desc": "Gatherers produce 1.5x.", "effects": [{"key": "job:gatherer", "mult": 1.5}]},
	{"id": "superstitious", "name": "Superstitious", "items": ["lucky_pebble", "clay_figurine"],
		"desc": "Clicking gathers 2x.", "effects": [{"key": "click", "mult": 2.0}]},
	{"id": "potters_wheel", "name": "Potter's Wheel", "items": ["stone_wheel", "painted_pot"],
		"desc": "Clay Diggers produce 2x.", "effects": [{"key": "job:clay_digger", "mult": 2.0}]},
	{"id": "shaman", "name": "Shaman", "items": ["carved_totem", "bone_flute", "obsidian_mirror"],
		"desc": "All workers produce 1.25x, rare items 25% more likely.",
		"effects": [{"key": "job:all", "mult": 1.25}, {"key": "luck", "mult": 1.25}]},
	{"id": "feast", "name": "The Feast", "items": ["tusk_necklace", "painted_pot", "woven_basket"],
		"desc": "Food spoils 30% slower, people eat 10% less.",
		"effects": [{"key": "spoil:food", "mult": 0.7}, {"key": "food_use", "mult": 0.9}]},
	{"id": "god_complex", "name": "God Complex", "items": ["idol_of_plenty", "the_first_brick"],
		"desc": "All workers produce 2x.", "effects": [{"key": "job:all", "mult": 2.0}]},
]

# --- invasions ------------------------------------------------------------------

# Countries are invaded in order; each needs the previous one conquered and its "requires" resource unlocked.
# Conquering pays out "loot" once and applies "effects" permanently.
const COUNTRIES := [
	{"id": "ugs_tribe", "name": "Ug's Tribe", "requires": "clay", "desc": "A small tribe next door.",
		"enemies": [{"name": "Ug's Tribe", "color": Color(0.85, 0.3, 0.25), "troop_mult": 0.6, "aggression": 0.2}],
		"cost": {"food": 2000.0, "wood": 5000.0}, "loot": {"food": 1e4, "wood": 2e4, "stone": 2e4},
		"reward_desc": "All workers produce 1.25x.", "effects": [{"key": "job:all", "mult": 1.25}]},
	{"id": "the_mudlands", "name": "The Mudlands", "requires": "clay", "desc": "A swampy people who really like mud.",
		"enemies": [{"name": "Mud People", "color": Color(0.65, 0.45, 0.25), "troop_mult": 1.0, "aggression": 0.35}],
		"cost": {"food": 5000.0, "clay": 5000.0}, "loot": {"clay": 1e5},
		"reward_desc": "Population grows 1.5x faster, +20 max population.", "effects": [{"key": "growth", "mult": 1.5}, {"key": "pop_cap", "add": 20}]},
	{"id": "copper_clans", "name": "Copper Hill Clans", "requires": "copper", "desc": "Two clans fighting over shiny hills.",
		"enemies": [{"name": "Red Hill Clan", "color": Color(0.9, 0.45, 0.2), "troop_mult": 1.3, "aggression": 0.4},
			{"name": "Green Hill Clan", "color": Color(0.35, 0.75, 0.3), "troop_mult": 1.3, "aggression": 0.4}],
		"cost": {"food": 2e4, "copper": 2e4}, "loot": {"copper": 5e5},
		"reward_desc": "All workers produce 1.5x.", "effects": [{"key": "job:all", "mult": 1.5}]},
	{"id": "bronze_kingdom", "name": "The Bronze Kingdom", "requires": "bronze", "desc": "A proper kingdom with a king and everything.",
		"enemies": [{"name": "Bronze Kingdom", "color": Color(0.8, 0.6, 0.2), "troop_mult": 1.8, "aggression": 0.5},
			{"name": "Tin Traders", "color": Color(0.6, 0.6, 0.7), "troop_mult": 1.2, "aggression": 0.3}],
		"cost": {"food": 1e5, "bronze": 1e5}, "loot": {"bronze": 5e6},
		"reward_desc": "All workers produce 2x.", "effects": [{"key": "job:all", "mult": 2.0}]},
	{"id": "iron_empire", "name": "The Iron Empire", "requires": "iron", "desc": "Three iron-clad nations that hate everyone.",
		"enemies": [{"name": "Iron Empire", "color": Color(0.45, 0.45, 0.5), "troop_mult": 2.5, "aggression": 0.6},
			{"name": "Rust Legion", "color": Color(0.7, 0.3, 0.15), "troop_mult": 1.5, "aggression": 0.5},
			{"name": "Ore Barons", "color": Color(0.55, 0.35, 0.55), "troop_mult": 1.5, "aggression": 0.4}],
		"cost": {"food": 5e5, "iron": 1e6}, "loot": {"iron": 5e7},
		"reward_desc": "All workers produce 2.5x.", "effects": [{"key": "job:all", "mult": 2.5}]},
]

static var _index: Dictionary = {}


static func find(list_name: String, id: String) -> Dictionary:
	if _index.is_empty():
		for pair in [["resource", RESOURCES], ["tech", TECHS], ["job", JOBS], ["building", BUILDINGS], ["upgrade", UPGRADES],
				["maker", MAKERS], ["item", ITEMS], ["synergy", SYNERGIES], ["country", COUNTRIES]]:
			for entry in pair[1]:
				_index["%s:%s" % [pair[0], entry["id"]]] = entry
	return _index.get("%s:%s" % [list_name, id], {})


static func resource_name(id: String) -> String:
	return find("resource", id).get("name", id)
