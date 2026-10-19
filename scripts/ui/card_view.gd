class_name CardView
extends Control
## A card face drawn at a fixed 300x420 design size and scaled to `display`. Used for the hand,
## board, piles, previews and effects. Text is drawn here (not baked into the art), so card data
## can change without new artwork.

signal clicked
signal hovered(card_id: String)
signal ability_pressed(index: int)

enum Mark { NONE, SELECTABLE, SELECTED }

const DESIGN := Vector2(300, 420)
const DEFAULT_SIZE := Vector2(150, 210)

var card_id := ""
var display := DEFAULT_SIZE
var ability_boxes: Array[Control] = []
var _face: Control
var _interactive := false
var _mark_panel: Panel


func setup(id: String, mark: Mark = Mark.NONE, p_display := DEFAULT_SIZE, interactive_abilities := false) -> CardView:
	card_id = id
	display = p_display
	_interactive = interactive_abilities
	custom_minimum_size = display
	size = display
	_face = Control.new()
	_face.size = DESIGN
	_face.scale = Vector2(display.x / DESIGN.x, display.y / DESIGN.y)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face)
	_build()
	_ignore_mouse(_face)
	_mark_panel = Panel.new()
	_mark_panel.size = display
	_mark_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mark_panel)
	set_mark(mark)
	mouse_entered.connect(func(): hovered.emit(card_id))
	return self


func set_mark(mark: Mark) -> void:
	var sb := UiStyle.box(Color(0, 0, 0, 0), int(22 * display.x / DESIGN.x))
	match mark:
		Mark.SELECTABLE:
			sb.border_color = Color(1.0, 0.9, 0.3)
			sb.set_border_width_all(4)
		Mark.SELECTED:
			sb.border_color = Color(1.0, 0.35, 0.35)
			sb.set_border_width_all(5)
			sb.bg_color = Color(1.0, 0.3, 0.3, 0.18)
	_mark_panel.add_theme_stylebox_override("panel", sb)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()


## Global rectangle of a node inside the card (the card is scaled, node sizes are in design units).
func global_rect_of(node: Control) -> Rect2:
	return Rect2(node.get_global_position(), node.size * _face.get_global_transform().get_scale())


## Decorative panels must not swallow clicks meant for the card; only ability boxes react.
func _ignore_mouse(node: Node) -> void:
	for c in node.get_children():
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(c)


## Dims an ability box that can't be used and lets clicks pass through it.
func set_ability_state(index: int, usable: bool, affordable: bool) -> void:
	if index < 0 or index >= ability_boxes.size():
		return
	var box := ability_boxes[index]
	box.modulate = Color(1, 1, 1, 1.0 if affordable else 0.5)
	if usable:
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.add_theme_stylebox_override("panel", _ability_style(box.get_meta("element"), true))
	else:
		box.mouse_filter = Control.MOUSE_FILTER_PASS if _interactive else Control.MOUSE_FILTER_IGNORE
		box.mouse_default_cursor_shape = Control.CURSOR_ARROW
		box.add_theme_stylebox_override("panel", _ability_style(box.get_meta("element"), false))


# --- Building ---------------------------------------------------------------------------------------
func _build() -> void:
	var card := CardDB.card(card_id)
	var element := String(card.get("element", ""))
	var kind: String = card.kind
	var pal := UiStyle.palette("spell" if kind == "spell" else element)
	var frame := Panel.new()
	frame.size = DESIGN
	frame.add_theme_stylebox_override("panel", UiStyle.box(pal.frame, 22))
	_face.add_child(frame)
	var inner := Panel.new()
	inner.position = Vector2(10, 10)
	inner.size = DESIGN - Vector2(20, 20)
	inner.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.CREAM, 15, pal.frame.darkened(0.25), 2))
	_face.add_child(inner)

	# Name plate: the name, and the element badge or the spell cost on the right.
	var right_w := 46.0
	if kind == "spell":
		right_w = float(int(card.cost.amount)) * 33.0 + 6.0
	var name_w := 264.0 - right_w
	_label(card.name, Rect2(20, 16, name_w, 36), 30, 20, UiStyle.INK, HORIZONTAL_ALIGNMENT_LEFT)
	if kind == "spell":
		var cost := _cost_row(card.cost, 30.0)
		cost.position = Vector2(282.0 - cost.size.x, 17)
		_face.add_child(cost)
	else:
		var badge := _badge(element, 40.0)
		badge.position = Vector2(240, 14)
		_face.add_child(badge)

	var tier_text := "Spell"
	if kind == "creature":
		tier_text = "Basic" if int(card.tier) <= 1 else "Evolves from %s" % CardDB.card_name(card.evolves_from)
	elif kind == "berry":
		tier_text = "Berry"
	_label(tier_text, Rect2(22, 54, 256, 22), 17, 12, UiStyle.INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT)

	# Art window.
	var art_h := 240.0 if kind == "berry" else 176.0
	var window := Panel.new()
	window.position = Vector2(18, 80)
	window.size = Vector2(264, art_h)
	window.add_theme_stylebox_override("panel", UiStyle.box(pal.light, 12, pal.frame, 3))
	_face.add_child(window)
	var tex := ArtDB.card_art(card_id)
	if tex != null:
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.position = Vector2(22, 82)
		art.size = Vector2(256, art_h - 4)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face.add_child(art)

	match kind:
		"creature": _build_abilities(card, element, pal)
		"spell": _build_text_box(card.text, Rect2(18, 264, 264, 138), pal, 22)
		"berry":
			var txt := "Counts as any element." if element == Rules.SUPER else "A %s Berry." % element.capitalize()
			_build_text_box(txt, Rect2(18, 330, 264, 72), pal, 22)


func _build_text_box(text: String, rect: Rect2, pal: Dictionary, size_start: int) -> void:
	var box := Panel.new()
	box.position = rect.position
	box.size = rect.size
	box.add_theme_stylebox_override("panel", UiStyle.box(Color(1, 1, 1, 0.55), 10, pal.frame.lightened(0.3), 2))
	_face.add_child(box)
	_label(text, Rect2(rect.position + Vector2(10, 6), rect.size - Vector2(20, 12)), size_start, 13, UiStyle.INK, HORIZONTAL_ALIGNMENT_LEFT)


func _build_abilities(card: Dictionary, element: String, pal: Dictionary) -> void:
	var abilities: Array = card.abilities
	var n := abilities.size()
	var gap := 6.0
	var h := (138.0 - gap * (n - 1)) / n
	for i in n:
		var ab: Dictionary = abilities[i]
		var box := Panel.new()
		box.position = Vector2(18, 264.0 + i * (h + gap))
		box.size = Vector2(264, h)
		box.set_meta("element", element)
		box.add_theme_stylebox_override("panel", _ability_style(element, false))
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face.add_child(box)
		ability_boxes.append(box)
		var cost := _cost_row(ab.cost, minf(28.0, h - 12.0))
		cost.position = Vector2(8, (h - cost.size.y) / 2.0)
		box.add_child(cost)
		var text_x := 8.0 + cost.size.x + 8.0
		var text_w := 264.0 - text_x - 8.0
		var body := Rules.ability_text(ab)
		if ab.has("text") and body.length() > 60:
			# Long rules text: one block, with the ability name leading it.
			_label("%s: %s" % [ab.name, body], Rect2(text_x, 3, text_w, h - 6), 17, 9, UiStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, box)
		elif ab.has("text"):
			_label(String(ab.name), Rect2(text_x, 3, text_w, 22), 18, 13, pal.dark, HORIZONTAL_ALIGNMENT_LEFT, box)
			_label(body, Rect2(text_x, 24, text_w, h - 27), 16, 10, UiStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, box)
		else:
			_label(body, Rect2(text_x, 4, text_w, h - 8), 22, 12, UiStyle.INK, HORIZONTAL_ALIGNMENT_LEFT, box)
		if _interactive and not ab.get("active", false):
			var index := i
			box.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					box.accept_event()
					ability_pressed.emit(index))


func _ability_style(element: String, usable: bool) -> StyleBoxFlat:
	var pal := UiStyle.palette(element)
	if usable:
		return UiStyle.box(Color(1.0, 0.97, 0.78, 0.95), 10, Color(0.95, 0.75, 0.12), 3)
	return UiStyle.box(Color(1, 1, 1, 0.6), 10, pal.frame.lightened(0.3), 2)


## Draws text that shrinks until it fits its rectangle. Returns the label.
func _label(text: String, rect: Rect2, size_start: int, size_min: int, color: Color, align: int, parent: Control = null) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # before text/size, or the label grows to one long line
	l.text = text
	l.position = rect.position
	l.custom_minimum_size = Vector2(rect.size.x, 0)
	l.size = rect.size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := size_start
	var f := UiStyle.font()
	while s > size_min and f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, s).y > rect.size.y:
		s -= 1
	l.add_theme_font_size_override("font_size", s)
	l.add_theme_color_override("font_color", color)
	(parent if parent != null else _face).add_child(l)
	return l


## Round badge with the element symbol (white glyph on the element colour).
static func make_badge(element: String, diameter: float) -> Control:
	var pal := UiStyle.palette(element)
	var badge := Panel.new()
	badge.size = Vector2(diameter, diameter)
	badge.add_theme_stylebox_override("panel", UiStyle.box(pal.frame, int(diameter / 2.0), pal.dark, maxi(int(diameter / 14.0), 1)))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := ArtDB.symbol(element)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var inset := diameter * 0.2
		tr.position = Vector2(inset, inset)
		tr.size = Vector2(diameter - 2 * inset, diameter - 2 * inset)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(tr)
	else:
		var l := Label.new()
		l.text = element.substr(0, 1).to_upper()
		l.size = badge.size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", int(diameter * 0.55))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(l)
	return badge


func _badge(element: String, diameter: float) -> Control:
	return make_badge(element, diameter)


## One badge per berry of the cost (colorless = grey star, super = plus).
static func make_cost_row(cost: Dictionary, diameter: float) -> Control:
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var amount := int(cost.amount)
	var step := diameter + 3.0
	for i in amount:
		var b := make_badge(String(cost.element), diameter)
		b.position = Vector2(i * step, 0)
		row.add_child(b)
	row.size = Vector2(amount * step - 3.0, diameter)
	return row


func _cost_row(cost: Dictionary, diameter: float) -> Control:
	return make_cost_row(cost, diameter)
