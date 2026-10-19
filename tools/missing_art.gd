# Writes assets/MISSING_ART.md: everything the game can show art for that has no file in assets/ yet.
# Run: godot --headless --path . -s tools/missing_art.gd
extends SceneTree


func _initialize() -> void:
	var sections := [
		["Screens", [{"name": "Background"}, {"name": "Click"}]],
		["Resources", GameData.RESOURCES],
		["Jobs", GameData.JOBS],
		["Buildings", GameData.BUILDINGS],
		["Discoveries", GameData.TECHS],
		["Upgrades", GameData.UPGRADES],
		["Items", GameData.ITEMS],
		["Legacy upgrades", GameData.PRESTIGE],
	]
	var lands: Array = []
	for tier in WarData.TIERS:
		lands.append({"name": tier["home_name"]})
		for t in tier["targets"]:
			lands.append(t)
	sections.append(["War map lands", lands])
	var lines: PackedStringArray = ["# Missing art", "",
		"Everything below has no picture yet. Save it in `assets/` named exactly as written, e.g. `Hut.png`.",
		"Regenerate with `godot --headless --path . -s tools/missing_art.gd`.", ""]
	var missing := 0
	var total := 0
	for section in sections:
		var names: PackedStringArray = []
		for entry in section[1]:
			total += 1
			if Assets.texture(entry["name"]) == null:
				names.append("- [ ] `%s.png`" % entry["name"])
		missing += names.size()
		if names.is_empty():
			continue
		lines.append("## %s (%d missing)" % [section[0], names.size()])
		lines.append_array(names)
		lines.append("")
	lines.insert(2, "**%d of %d** things still need art.\n" % [missing, total])
	var f := FileAccess.open("res://assets/MISSING_ART.md", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	print("%d of %d missing" % [missing, total])
	quit()
