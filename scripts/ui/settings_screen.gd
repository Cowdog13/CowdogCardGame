class_name SettingsScreen
extends Control
## Window and game options; everything here is remembered between sessions.

signal back_requested


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.12, 0.11)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(480, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var full := CheckBox.new()
	full.text = "Fullscreen (F11 anywhere)"
	full.button_pressed = Settings.fullscreen()
	full.toggled.connect(func(on): Settings.set_fullscreen(on))
	box.add_child(full)
	var fx := CheckBox.new()
	fx.text = "Visual effects (card animations)"
	fx.button_pressed = bool(Settings.get_value("game", "effects", true))
	fx.toggled.connect(func(on): Settings.set_value("game", "effects", on))
	box.add_child(fx)
	var about := Label.new()
	about.text = "Reporting a problem or a balance issue: after a game (or from the Log button during one) the game saves a small\nreport file with everything needed to replay that game. Send it to whoever runs the test."
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(480, 0)
	about.add_theme_font_size_override("font_size", 14)
	box.add_child(about)
	var reports := Button.new()
	reports.text = "Open the game reports folder"
	reports.pressed.connect(Settings.open_reports_folder)
	box.add_child(reports)
	var version := Label.new()
	version.text = "%s\nFont: Gluten (SIL Open Font License)." % BuildInfo.label()
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.modulate = Color(1, 1, 1, 0.6)
	box.add_child(version)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): back_requested.emit())
	box.add_child(back)
