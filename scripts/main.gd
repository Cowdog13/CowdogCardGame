extends Control
## Switches between the main menu and a running game.

var _menu: Control
var _game: GameScreen


func _ready() -> void:
	theme = Theme.new()
	theme.default_font_size = 16
	_show_menu()


func _show_menu() -> void:
	_clear()
	_menu = MainMenu.new()
	_menu.start_requested.connect(_start_game)
	add_child(_menu)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _start_game(deck0: String, deck1: String, ai_delay: float, effects: bool) -> void:
	_clear()
	_game = GameScreen.new()
	_game.exit_requested.connect(_show_menu)
	_game.rematch_requested.connect(_start_game.bind(deck0, deck1, ai_delay, effects))
	add_child(_game)
	_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The human always sits in seat 0; seat 1 is the computer for now.
	_game.start([deck0, deck1], [HumanAgent.new(0), AIAgent.new(1)], ai_delay, effects)


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_menu = null
	_game = null
