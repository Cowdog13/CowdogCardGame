class_name Settings
extends RefCounted
## The player's remembered choices (user://settings.cfg, shared with ArtDB's art pack choice).

const PATH := "user://settings.cfg"
const REPORTS_DIR := "user://reports"


static func get_value(section: String, key: String, default: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return default
	return cfg.get_value(section, key, default)


static func set_value(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(section, key, value)
	cfg.save(PATH)


static func fullscreen() -> bool:
	return bool(get_value("display", "fullscreen", false))


static func apply_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


static func set_fullscreen(on: bool) -> void:
	set_value("display", "fullscreen", on)
	apply_fullscreen(on)


static func open_reports_folder() -> void:
	DirAccess.make_dir_recursive_absolute(REPORTS_DIR)
	OS.shell_open(ProjectSettings.globalize_path(REPORTS_DIR))
