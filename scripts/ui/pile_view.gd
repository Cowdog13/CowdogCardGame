class_name PileView
extends Control
## A pile of cards: a few card backs peeking out under the top card, with the count on a plate.
## Deck shows the card back; discard shows the last discarded card; exile shows the last exiled
## card turned sideways. Discard and exile can be clicked to browse them; the deck is hidden.

signal clicked

const CARD := Vector2(78, 109)
const SIZE_PILE := Vector2(108, 160)

var kind := "deck"
var clickable := false
var count := 0
var top_id := ""
var _stack: Control
var _top_card: Control


func setup(p_kind: String, p_clickable: bool) -> PileView:
	kind = p_kind
	clickable = p_clickable
	custom_minimum_size = SIZE_PILE
	size = SIZE_PILE
	mouse_filter = Control.MOUSE_FILTER_STOP
	if clickable:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "%s%s" % [kind.capitalize(), " (click to view)" if clickable else " (hidden)"]
	_stack = Control.new()
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)
	set_pile(0, "")
	return self


## `top` is the card id shown on top (discard / exile); ignored for the deck.
func set_pile(p_count: int, top_card_id: String) -> void:
	if _stack.get_child_count() > 0 and p_count == count and top_card_id == top_id:
		return
	count = p_count
	top_id = top_card_id
	for c in _stack.get_children():
		_stack.remove_child(c)
		c.queue_free()
	var origin := Vector2((SIZE_PILE.x - CARD.x) / 2.0, 14.0)
	if count == 0:
		var empty := Panel.new()
		empty.position = origin
		empty.size = CARD
		empty.add_theme_stylebox_override("panel", UiStyle.box(Color(1, 1, 1, 0.06), 10, Color(1, 1, 1, 0.3), 2))
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stack.add_child(empty)
	else:
		var layers := clampi(int(ceil(count / 12.0)), 1, 3)  # 1-2 extra card edges under the top card
		for i in range(layers - 1, 0, -1):
			var under := CardBack.new().setup(CARD)
			under.position = origin + Vector2(-3.5, 3.5) * i
			under.modulate = Color(0.78, 0.78, 0.82)
			_stack.add_child(under)
		var top: Control
		if kind == "deck" or top_id == "":
			top = CardBack.new().setup(CARD)
			top.position = origin
		else:
			top = CardView.new().setup(top_id, CardView.Mark.NONE, CARD)
			top.mouse_filter = Control.MOUSE_FILTER_IGNORE
			top.position = origin
			if kind == "exile":
				# Sideways, so it can't be mistaken for the discard pile.
				top.pivot_offset = CARD / 2.0
				top.rotation = PI / 2.0
				top.position = origin + Vector2(0, 4)
		_stack.add_child(top)
		_top_card = top
	# Count plate and caption.
	var plate := Panel.new()
	plate.size = Vector2(46, 26)
	plate.position = Vector2((SIZE_PILE.x - 46) / 2.0, 14.0 + CARD.y - 8.0)
	plate.add_theme_stylebox_override("panel", UiStyle.box(Color(0.1, 0.13, 0.18, 0.92), 13, Color(0.9, 0.78, 0.4), 2))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_child(plate)
	var l := Label.new()
	l.text = str(count)
	l.size = plate.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 17)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(l)
	var cap := Label.new()
	cap.text = kind.capitalize()
	cap.position = Vector2(0, 0)
	cap.size = Vector2(SIZE_PILE.x, 14)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 12)
	cap.modulate = Color(1, 1, 1, 0.75)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_child(cap)


func top_rect() -> Rect2:
	return _top_card.get_global_rect() if _top_card != null and is_instance_valid(_top_card) else get_global_rect()


func _gui_input(event: InputEvent) -> void:
	if clickable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
