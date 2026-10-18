# Regenerates assets/ERA_ASSETS.md from EraData. Run: godot --headless --path . -s tools/write_era_assets.gd
extends SceneTree


func _initialize() -> void:
	var lines: PackedStringArray = ["# Art checklist by age", "",
		"Name each file exactly after the item, e.g. `Wooden Club.png`, and drop it in `assets/`.", ""]
	for i in EraData.ERAS.size():
		var era: Dictionary = EraData.ERAS[i]
		lines.append("## %d. %s (%s)" % [i + 1, era["name"], era["subtitle"]])
		lines.append("*%s*" % era["time"])
		lines.append("")
		for a in era["assets"]:
			lines.append("- [ ] `%s.png`" % a)
		lines.append("")
	var f := FileAccess.open("res://assets/ERA_ASSETS.md", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	quit()
