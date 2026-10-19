class_name CardBack
extends Control
## The back of a card (placeholder: the Cowdog logo on a framed card), drawn at 300x420 design
## size and scaled to whatever size it is shown at.

const DESIGN := Vector2(300, 420)


func setup(display := Vector2(150, 210)) -> CardBack:
	custom_minimum_size = display
	size = display
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := Control.new()
	face.size = DESIGN
	face.scale = Vector2(display.x / DESIGN.x, display.y / DESIGN.y)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(face)
	var frame := Panel.new()
	frame.size = DESIGN
	frame.add_theme_stylebox_override("panel", UiStyle.box(Color(0.17, 0.19, 0.28), 22))
	face.add_child(frame)
	var inner := Panel.new()
	inner.position = Vector2(12, 12)
	inner.size = DESIGN - Vector2(24, 24)
	inner.add_theme_stylebox_override("panel", UiStyle.box(Color(0.96, 0.92, 0.80), 14, Color(0.80, 0.64, 0.28), 4))
	face.add_child(inner)
	var ring := Panel.new()
	ring.position = Vector2(28, 28)
	ring.size = DESIGN - Vector2(56, 56)
	ring.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0), 10, Color(0.17, 0.19, 0.28, 0.35), 2))
	face.add_child(ring)
	var logo := ArtDB.card_back_logo()
	if logo != null:
		var tr := TextureRect.new()
		tr.texture = logo
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = Vector2(60, 100)
		tr.size = Vector2(180, 220)
		face.add_child(tr)
	return self
