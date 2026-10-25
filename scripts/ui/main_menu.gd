class_name MainMenu
extends Control

signal start_requested(deck0: String, deck1: String, ai_delay: float, effects: bool)
signal multiplayer_requested
signal tutorial_requested
signal rulebook_requested
signal art_packs_requested

var _you: OptionButton
var _opp: OptionButton
var _speed: HSlider
var _effects: CheckBox


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
	_you = _deck_picker(box, "Your deck", 0)
	_opp = _deck_picker(box, "Computer's deck", 1)
	var speed_label := Label.new()
	speed_label.text = "Computer speed (seconds per action)"
	box.add_child(speed_label)
	_speed = HSlider.new()
	_speed.min_value = 0.0
	_speed.max_value = 2.0
	_speed.step = 0.1
	_speed.value = 0.7
	box.add_child(_speed)
	_effects = CheckBox.new()
	_effects.text = "Visual effects (card animations)"
	_effects.button_pressed = true
	box.add_child(_effects)
	var start := Button.new()
	start.text = "Start Game"
	start.custom_minimum_size = Vector2(0, 48)
	start.pressed.connect(func():
		start_requested.emit(CardDB.deck_ids()[_you.selected], CardDB.deck_ids()[_opp.selected], _speed.value, _effects.button_pressed))
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
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)


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
