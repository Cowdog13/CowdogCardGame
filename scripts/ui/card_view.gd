class_name CardView
extends PanelContainer
## A face-up card (hand, mulligan). Emits clicked / hovered; highlight is set by the owner.

signal clicked
signal hovered(card_id: String)

enum Mark { NONE, SELECTABLE, SELECTED }

var card_id := ""
var _style := StyleBoxFlat.new()


func setup(id: String, mark: Mark = Mark.NONE) -> CardView:
	card_id = id
	var card := CardDB.card(id)
	custom_minimum_size = Vector2(150, 215)
	var base: Color
	match card.kind:
		"spell": base = Color(0.36, 0.30, 0.46)
		_: base = Rules.element_color(String(card.get("element", "")))
	_style.bg_color = base.darkened(0.45)
	_style.set_corner_radius_all(8)
	_style.set_content_margin_all(8)
	_style.border_color = base.lightened(0.2)
	_style.set_border_width_all(2)
	match mark:
		Mark.SELECTABLE:
			_style.border_color = Color(1, 0.9, 0.3)
			_style.set_border_width_all(4)
		Mark.SELECTED:
			_style.border_color = Color(1, 0.35, 0.35)
			_style.set_border_width_all(5)
	add_theme_stylebox_override("panel", _style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var title := Label.new()
	title.text = card.name
	title.add_theme_font_size_override("font_size", 17)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var body := Label.new()
	body.text = CardDB.card_text(id)
	body.add_theme_font_size_override("font_size", 12)
	body.modulate = Color(1, 1, 1, 0.9)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	mouse_entered.connect(func(): hovered.emit(card_id))
	return self


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
