class_name PileView
extends Control
## A pile of cards (deck / discard / exile) drawn as a little stack with the card count.
## Discard and exile piles are clickable; the deck is hidden information.

signal clicked

const SIZE_PILE := Vector2(92, 122)
const CARD_AREA := Vector2(84, 96)

var kind := "deck"
var count := 0
var clickable := false
var _hover := false


func setup(p_kind: String, p_clickable: bool) -> PileView:
	kind = p_kind
	clickable = p_clickable
	custom_minimum_size = SIZE_PILE
	mouse_filter = Control.MOUSE_FILTER_STOP
	if clickable:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "%s%s" % [kind.capitalize(), " (click to view)" if clickable else " (hidden)"]
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())
	return self


func set_count(n: int) -> void:
	if n != count:
		count = n
		queue_redraw()


func _face_style(top: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(7)
	sb.set_border_width_all(2)
	match kind:
		"deck":
			sb.bg_color = Color(0.16, 0.20, 0.36)
			sb.border_color = Color(0.86, 0.70, 0.30)
		"discard":
			sb.bg_color = Color(0.26, 0.28, 0.30)
			sb.border_color = Color(0.55, 0.58, 0.62)
		_:
			sb.bg_color = Color(0.30, 0.18, 0.40)
			sb.border_color = Color(0.72, 0.45, 0.95)
	if not top:
		sb.bg_color = sb.bg_color.darkened(0.25)
	if _hover and clickable:
		sb.border_color = sb.border_color.lightened(0.45)
	return sb


func _draw() -> void:
	var layers := 0 if count == 0 else clampi(int(ceil(count / 8.0)), 1, 5)
	if count == 0:
		var empty := StyleBoxFlat.new()
		empty.bg_color = Color(1, 1, 1, 0.04)
		empty.set_corner_radius_all(7)
		empty.set_border_width_all(2)
		empty.border_color = Color(1, 1, 1, 0.2)
		draw_style_box(empty, Rect2(Vector2(4, 8), CARD_AREA))
	for i in layers:
		var off := Vector2(4, 8) - Vector2(2.5, 2.5) * (layers - 1 - i)
		draw_style_box(_face_style(i == layers - 1), Rect2(off, CARD_AREA))
	var font := get_theme_default_font()
	var top_left := Vector2(4, 8)
	var num := str(count)
	var fs := 34
	var tsize := font.get_string_size(num, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, top_left + Vector2((CARD_AREA.x - tsize.x) / 2.0, CARD_AREA.y / 2.0 + fs * 0.35), num,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
	var cap := kind.capitalize()
	var csize := font.get_string_size(cap, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	draw_string(font, Vector2((size.x - csize.x) / 2.0, size.y - 3), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.75))


func _gui_input(event: InputEvent) -> void:
	if clickable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
