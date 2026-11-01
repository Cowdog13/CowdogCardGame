class_name MainMenu
extends Control

signal start_requested(deck0: String, deck1: String, ai_delay: float, effects: bool)
signal multiplayer_requested
signal tutorial_requested
signal rulebook_requested
signal art_packs_requested
signal settings_requested

var _you: OptionButton
var _opp: OptionButton
const COMPUTER_DELAY := 0.7  # seconds the computer waits between actions


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.12, 0.11)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var logo := ArtDB.card_back_logo()
	if logo != null:
		var tr := TextureRect.new()
		tr.texture = logo
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(0, 120)
		# The logo is black line art: it sits on a parchment plate so it shows on the dark menu.
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", UiStyle.box(Color(0.93, 0.87, 0.7), 18, Color(0.95, 0.78, 0.35), 3))
		plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		plate.custom_minimum_size = Vector2(150, 0)
		plate.add_child(tr)
		box.add_child(plate)
	var title := Label.new()
	title.text = "Cowdog Card Game"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Playtest build - Preconstructed format"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_you = _deck_picker(box, "Your deck", _deck_index(Settings.get_value("game", "deck_you", ""), 0))
	_opp = _deck_picker(box, "Computer's deck", _deck_index(Settings.get_value("game", "deck_computer", ""), 1))
	var start := Button.new()
	start.text = "Start Game"
	start.custom_minimum_size = Vector2(0, 48)
	start.pressed.connect(func():
		Settings.set_value("game", "deck_you", CardDB.deck_ids()[_you.selected])
		Settings.set_value("game", "deck_computer", CardDB.deck_ids()[_opp.selected])
		start_requested.emit(CardDB.deck_ids()[_you.selected], CardDB.deck_ids()[_opp.selected], COMPUTER_DELAY, true))
	box.add_child(start)
	var tut := Button.new()
	tut.text = "Tutorial (learn to play)"
	tut.pressed.connect(func(): tutorial_requested.emit())
	box.add_child(tut)
	var rules := Button.new()
	rules.text = "Rulebook"
	rules.pressed.connect(func(): rulebook_requested.emit())
	box.add_child(rules)
	var art := Button.new()
	art.text = "Art packs"
	art.pressed.connect(func(): art_packs_requested.emit())
	box.add_child(art)
	var mp := Button.new()
	mp.text = "Multiplayer (beta)"
	mp.pressed.connect(func(): multiplayer_requested.emit())
	box.add_child(mp)
	var settings := Button.new()
	settings.text = "Settings"
	settings.pressed.connect(func(): settings_requested.emit())
	box.add_child(settings)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)
	var version := Label.new()
	version.text = BuildInfo.label()
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.modulate = Color(1, 1, 1, 0.55)
	version.add_theme_font_size_override("font_size", 13)
	box.add_child(version)


func _deck_index(deck_id: String, fallback: int) -> int:
	var i: int = CardDB.deck_ids().find(deck_id)
	return i if i >= 0 else fallback


func _deck_picker(parent: Control, label: String, default_index: int) -> OptionButton:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	var ob := OptionButton.new()
	for id in CardDB.deck_ids():
		ob.add_item(CardDB.deck_name(id))
	ob.select(mini(default_index, ob.item_count - 1))
	parent.add_child(ob)
	return ob
