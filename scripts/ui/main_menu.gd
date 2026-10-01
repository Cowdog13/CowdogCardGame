class_name MainMenu
extends Control

signal start_requested(deck0: String, deck1: String, ai_delay: float)

var _you: OptionButton
var _opp: OptionButton
var _speed: HSlider


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
	var start := Button.new()
	start.text = "Start Game"
	start.custom_minimum_size = Vector2(0, 48)
	start.pressed.connect(func():
		start_requested.emit(CardDB.deck_ids()[_you.selected], CardDB.deck_ids()[_opp.selected], _speed.value))
	box.add_child(start)
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
