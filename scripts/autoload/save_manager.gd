extends Node

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const AUTOSAVE_INTERVAL := 30.0
const MIN_OFFLINE_SECONDS := 10.0

var _timer := 0.0


func _ready() -> void:
	load_game.call_deferred()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= AUTOSAVE_INTERVAL:
		_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


func save_game() -> void:
	var data := Game.to_dict()
	data["version"] = SAVE_VERSION
	data["saved_at"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Save file is unreadable; starting fresh.")
		return
	Game.from_dict(data)
	var away: float = Time.get_unix_time_from_system() - float(data.get("saved_at", 0.0))
	if away < MIN_OFFLINE_SECONDS:
		return
	var gains := Game.apply_offline(away)
	var parts: PackedStringArray = []
	for id in gains:
		if gains[id] > 0.0:
			parts.append("+%s %s" % [NumFormat.fmt(gains[id]), GameData.resource_name(id)])
	var summary := ", ".join(parts) if not parts.is_empty() else "nothing"
	Game.post("Welcome back! Away %s: %s" % [NumFormat.duration(minf(away, Game.MAX_OFFLINE_SECONDS)), summary])


func wipe() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	Game.reset()
