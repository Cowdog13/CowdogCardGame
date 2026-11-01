extends Control
## Switches between the main menu, the single-player game and the multiplayer lobby / game.

var _menu: Control
var _game: GameScreen
var _session: NetSession


func _ready() -> void:
	theme = UiStyle.build_theme()
	ArtDB.load_settings()
	Settings.apply_fullscreen(Settings.fullscreen())
	_show_menu()
	_offer_tutorial.call_deferred()


## F11 switches fullscreen from anywhere.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		Settings.set_fullscreen(DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN)


## The first time the game is started, point new players at the tutorial.
func _offer_tutorial() -> void:
	if bool(Settings.get_value("app", "welcomed", false)):
		return
	Settings.set_value("app", "welcomed", true)
	var d := ConfirmationDialog.new()
	d.title = "Welcome!"
	d.dialog_text = "New to the game? The tutorial teaches the rules in about ten minutes of play. Start it now?"
	d.ok_button_text = "Start the tutorial"
	d.cancel_button_text = "Not now"
	add_child(d)
	d.confirmed.connect(func():
		d.queue_free()
		_start_tutorial())
	d.canceled.connect(d.queue_free)
	d.popup_centered()


func _show_menu() -> void:
	_clear()
	_menu = MainMenu.new()
	_menu.start_requested.connect(_start_game)
	_menu.multiplayer_requested.connect(_show_multiplayer)
	_menu.tutorial_requested.connect(_start_tutorial)
	_menu.rulebook_requested.connect(_show_rulebook)
	_menu.art_packs_requested.connect(_show_art_packs)
	_menu.settings_requested.connect(_show_settings)
	add_child(_menu)
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# --- Single player ------------------------------------------------------------------------------
func _start_game(deck0: String, deck1: String, ai_delay: float, effects: bool) -> void:
	_clear()
	_game = GameScreen.new()
	_game.exit_requested.connect(_show_menu)
	_game.rematch_requested.connect(_start_game.bind(deck0, deck1, ai_delay, effects))
	add_child(_game)
	_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The human always sits in seat 0; seat 1 is the computer.
	_game.start([deck0, deck1], [HumanAgent.new(0), AIAgent.new(1)], ai_delay, effects)


func _show_settings() -> void:
	_clear()
	var screen := SettingsScreen.new()
	screen.back_requested.connect(_show_menu)
	_menu = screen
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _show_art_packs() -> void:
	_clear()
	var screen := ArtPacksScreen.new()
	screen.back_requested.connect(_show_menu)
	_menu = screen
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _show_rulebook() -> void:
	_clear()
	var book := RulebookScreen.new()
	book.back_requested.connect(_show_menu)
	_menu = book
	add_child(book)
	book.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# --- Tutorial -----------------------------------------------------------------------------------
## A scripted game: stacked decks, a practice opponent that follows a script, and the TutorialDirector
## explaining each step. When the player chooses to finish, the opponent turns into the normal AI.
func _start_tutorial() -> void:
	_clear()
	_game = GameScreen.new()
	_game.tutorial_mode = true
	_game.exit_requested.connect(_show_menu)
	add_child(_game)
	_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ctrl := GameController.new()
	ctrl.ai_delay = 0.9
	ctrl.hold_external = true
	_game.attach(ctrl, 0, true, false)
	var decks := TutorialScript.decks()
	ctrl.start(["scorching_fire", "crashing_wave"], [HumanAgent.new(0), ScriptedAgent.new(1, TutorialScript.opponent_intents())], -1, ["You", "Practice Bot"], decks)
	var director := TutorialDirector.new().setup(ctrl, _game)
	director.quit_requested.connect(_show_menu)
	_game.add_child(director)


# --- Multiplayer ----------------------------------------------------------------------------------
func _show_multiplayer() -> void:
	_clear()
	_leave_net()
	# Host and clients must run this node at the same path (/root/Main/NetSession) for RPCs to match.
	_session = NetSession.new()
	_session.name = "NetSession"
	add_child(_session)
	_session.game_ready.connect(_on_net_game_ready)
	_session.ended.connect(_on_net_ended)
	var lobby := MultiplayerMenu.new().setup(_session)
	lobby.back_requested.connect(func():
		_leave_net()
		_show_menu())
	_menu = lobby
	add_child(lobby)
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_net_game_ready(controller: Node, my_seat: int) -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	if _game != null:
		_game.queue_free()
	_game = GameScreen.new()
	_game.exit_requested.connect(func():
		_leave_net()
		_show_menu())
	add_child(_game)
	_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_game.is_net_host = controller is GameController
	_game.rematch_requested.connect(_net_rematch)
	_game.attach(controller, my_seat, true, false)


func _net_rematch() -> void:
	var problem := _session.rematch()
	if problem != "" and _game != null:
		_game._toast(problem)


func _on_net_ended(reason: String) -> void:
	if _game == null:
		return  # still in the lobby: the lobby shows the reason itself
	var d := AcceptDialog.new()
	d.title = "Disconnected"
	d.dialog_text = reason
	add_child(d)
	d.popup_centered()
	d.confirmed.connect(func():
		d.queue_free()
		_leave_net()
		_show_menu())


func _leave_net() -> void:
	if _session != null:
		_session.close()
		_session.queue_free()
		_session = null


func _clear() -> void:
	for c in get_children():
		if c != _session:
			c.queue_free()
	_menu = null
	_game = null
