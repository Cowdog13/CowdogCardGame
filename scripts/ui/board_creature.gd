class_name BoardCreature
extends Control
## A creature on the board: its card (evolution cards stacked, each lower card showing just its
## name strip above the one on top), the attached berries underneath, a number badge, and the
## stunned / target highlights. Own creatures have clickable ability boxes.

signal clicked
signal hovered(creature: Dictionary)
signal ability_pressed(index: int)

const CARD_SIZE := Vector2(150, 210)
const STRIP := 27.0  # how much of each lower evolution card is visible (its name plate)
const BERRY_H := 36.0
const BERRY_ICON := 32.0
const MAX_STACK := 3

var creature: Dictionary = {}
var slot := 0
var top_card: CardView
var berry_strip: Control
var _highlight: Panel


static func widget_size() -> Vector2:
	return Vector2(CARD_SIZE.x + 12.0, STRIP * (MAX_STACK - 1) + CARD_SIZE.y + BERRY_H + 6.0)


func setup(p_creature: Dictionary, p_slot: int, mine: bool, turn: int, valid: bool, chosen: bool) -> BoardCreature:
	creature = p_creature
	slot = p_slot
	custom_minimum_size = widget_size()
	size = widget_size()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var cards: Array = creature.cards
	var n := cards.size()
	for k in n:
		var is_top := k == n - 1
		var cv := CardView.new().setup(cards[k], CardView.Mark.NONE, CARD_SIZE, mine and is_top)
		cv.position = Vector2(6, STRIP * (MAX_STACK - n + k))
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE if not is_top else Control.MOUSE_FILTER_PASS
		add_child(cv)
		if is_top:
			top_card = cv
			cv.ability_pressed.connect(func(i): ability_pressed.emit(i))
	var top_y := STRIP * (MAX_STACK - 1)  # the top card always sits at the same height
	# Slot number: matches the numbers in the spell payment list.
	var num := Panel.new()
	num.position = Vector2(-3, top_y + CARD_SIZE.y - 18)  # bottom-left corner, clear of the name plate
	num.size = Vector2(24, 24)
	num.add_theme_stylebox_override("panel", UiStyle.box(Color(0.12, 0.16, 0.22, 0.92), 12, Color(0.9, 0.78, 0.4), 2))
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := Label.new()
	nl.text = str(slot + 1)
	nl.size = num.size
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.add_theme_font_size_override("font_size", 14)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_child(nl)
	add_child(num)

	if Rules.is_stunned(creature, turn):
		var stun := Panel.new()
		stun.position = Vector2(6, top_y)
		stun.size = CARD_SIZE
		stun.add_theme_stylebox_override("panel", UiStyle.box(Color(0.35, 0.65, 1.0, 0.35), 12, Color(0.6, 0.85, 1.0), 3))
		stun.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(stun)
		var sl := Label.new()
		sl.text = "STUNNED"
		sl.position = Vector2(6, top_y + CARD_SIZE.y * 0.38)
		sl.size = Vector2(CARD_SIZE.x, 30)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.add_theme_font_size_override("font_size", 24)
		sl.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
		sl.add_theme_color_override("font_outline_color", Color(0.1, 0.25, 0.6))
		sl.add_theme_constant_override("outline_size", 6)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sl)

	if Rules.is_dormant(creature, turn) and not Rules.is_stunned(creature, turn):
		var dorm := Panel.new()
		dorm.position = Vector2(6, top_y)
		dorm.size = CARD_SIZE
		dorm.add_theme_stylebox_override("panel", UiStyle.box(Color(0.25, 0.22, 0.12, 0.38), 12, Color(0.9, 0.78, 0.4), 3))
		dorm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dorm)
		var dl := Label.new()
		dl.text = "DORMANT\nuntil turn %d" % int(creature.dormant_until)
		dl.position = Vector2(6, top_y + CARD_SIZE.y * 0.34)
		dl.size = Vector2(CARD_SIZE.x, 60)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.add_theme_font_size_override("font_size", 20)
		dl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
		dl.add_theme_color_override("font_outline_color", Color(0.3, 0.2, 0.05))
		dl.add_theme_constant_override("outline_size", 6)
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dl)

	# Attached berries: upright icons, exhausted ones lie sideways. They overlap when there are many.
	berry_strip = Control.new()
	berry_strip.position = Vector2(6, top_y + CARD_SIZE.y + 4)
	berry_strip.size = Vector2(CARD_SIZE.x, BERRY_H)
	berry_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(berry_strip)
	var count: int = creature.berries.size()
	var step := minf(BERRY_ICON - 2.0, (CARD_SIZE.x - BERRY_ICON) / maxf(count - 1, 1))
	var x0 := (CARD_SIZE.x - (BERRY_ICON + step * (count - 1))) / 2.0
	for i in count:
		var id: String = creature.berries[i]
		var holder := Control.new()
		holder.size = Vector2(BERRY_ICON, BERRY_ICON)
		holder.pivot_offset = holder.size / 2.0
		holder.position = Vector2(x0 + step * i, (BERRY_H - BERRY_ICON) / 2.0)
		holder.mouse_filter = Control.MOUSE_FILTER_PASS
		var sideways: bool = creature.exhausted[i]
		holder.tooltip_text = CardDB.card_name(id) + (" (exhausted: exiled when discarded)" if sideways else "")
		var tex := ArtDB.berry_icon(id)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.size = holder.size
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(tr)
		else:
			holder.add_child(CardView.make_badge(CardDB.element_of(id), BERRY_ICON))
		# Outline: green = played from hand (upright), red = exhausted (sideways; exiled when discarded).
		var ring := Panel.new()
		ring.size = holder.size
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0), int(BERRY_ICON / 2.0),
			Color(0.95, 0.25, 0.25) if sideways else Color(0.25, 0.85, 0.32), 3))
		holder.add_child(ring)
		if sideways:
			holder.rotation = PI / 2.0
		berry_strip.add_child(holder)

	_highlight = Panel.new()
	_highlight.position = Vector2(3, top_y - 3)
	_highlight.size = CARD_SIZE + Vector2(6, 6)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_highlight)
	set_target_state(valid, chosen)
	mouse_entered.connect(func(): hovered.emit(creature))
	return self


func set_target_state(valid: bool, chosen: bool) -> void:
	var sb := UiStyle.box(Color(0, 0, 0, 0), 16)
	if chosen:
		sb.border_color = Color(1.0, 0.35, 0.35)
		sb.set_border_width_all(5)
	elif valid:
		sb.border_color = Color(1.0, 0.9, 0.3)
		sb.set_border_width_all(4)
	_highlight.add_theme_stylebox_override("panel", sb)


## Enables / dims the ability boxes of the top card. `usable[i]` / `affordable[i]` per ability.
func set_ability_states(usable: Array, affordable: Array) -> void:
	for i in top_card.ability_boxes.size():
		top_card.set_ability_state(i, usable[i], affordable[i])


func top_card_rect() -> Rect2:
	return top_card.get_global_rect()


func ability_rect(index: int) -> Rect2:
	if index >= 0 and index < top_card.ability_boxes.size():
		return top_card.global_rect_of(top_card.ability_boxes[index])
	return top_card_rect()


## Where the newest berry sits (for the attach burst).
func newest_berry_pos() -> Vector2:
	if berry_strip.get_child_count() > 0:
		return berry_strip.get_child(berry_strip.get_child_count() - 1).get_global_rect().get_center()
	return berry_strip.get_global_rect().get_center()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
