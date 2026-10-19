class_name TutorialOverlay
extends Control
## The tutorial's window (title, text, button) and the pulsing frames that point at cards and buttons.
## Clicks pass through everywhere except the window itself.

signal next_pressed
signal quit_pressed
signal finish_pressed

var screen: GameScreen
var _panel: PanelContainer
var _title: Label
var _text: RichTextLabel
var _count: Label
var _next: Button
var _finish: Button
var _targets: Array = []
var _dragging := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.12, 0.94)
	sb.border_color = Color(0.95, 0.8, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.custom_minimum_size = Vector2(470, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.98, 0.85, 0.4))
	box.add_child(_title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(440, 0)
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_font_size_override("bold_font_size", 15)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 12)
	_count.modulate = Color(1, 1, 1, 0.6)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_count)
	var quit := Button.new()
	quit.text = "Leave tutorial"
	quit.pressed.connect(func(): quit_pressed.emit())
	row.add_child(quit)
	_finish = Button.new()
	_finish.text = "Finish the game"
	_finish.pressed.connect(func(): finish_pressed.emit())
	row.add_child(_finish)
	_next = Button.new()
	_next.pressed.connect(func(): next_pressed.emit())
	row.add_child(_next)
	_panel.visible = false
	_place_default.call_deferred()


func _place_default() -> void:
	_panel.position = Vector2(14, 50)


func hide_panel() -> void:
	_panel.visible = false
	_targets = []


## kind: "next" (plain Next), "action" (the player plays a move), "bot" (watch button), "end" (finish / quit).
func show_step(step: Dictionary, index: int, total: int, kind: String) -> void:
	_title.text = step.title
	# The font has no bold or italic face, so emphasis is shown with colour.
	_text.text = String(step.text).replace("[b]", "[color=#f2d065]").replace("[/b]", "[/color]").replace("[i]", "[color=#9fd3ff]").replace("[/i]", "[/color]")
	_count.text = "Step %d of %d" % [index + 1, total]
	_next.visible = kind == "next" or kind == "bot"
	_next.text = String(step.get("button", "Next"))
	_finish.visible = kind == "end"
	if kind == "end":
		_next.visible = false
	_targets = step.get("highlight", [])
	_panel.visible = true
	_panel.reset_size()


func _process(_dt: float) -> void:
	if _panel != null and _panel.visible:
		queue_redraw()
	elif not _targets.is_empty():
		queue_redraw()


func _draw() -> void:
	if screen == null or not _panel.visible:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 220.0)
	for t in _targets:
		var r: Rect2 = screen.tutorial_target_rect(String(t))
		if r.size == Vector2.ZERO:
			continue
		r.position -= global_position
		r = r.grow(6.0 + 3.0 * pulse)
		draw_rect(r, Color(1, 0.88, 0.3, 0.12 + 0.12 * pulse), true)
		draw_rect(r, Color(1, 0.88, 0.3, 0.7 + 0.3 * pulse), false, 3.0)


## The window can be dragged out of the way of the cards.
func _on_panel_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_dragging = ev.pressed
	elif ev is InputEventMouseMotion and _dragging:
		_panel.position += ev.relative
