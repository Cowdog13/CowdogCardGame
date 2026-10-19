class_name MultiplayerMenu
extends Control
## Lobby for peer-to-peer games: host a game (share your address with friends) or join one.

signal back_requested

var session: NetSession
var _name: LineEdit
var _deck: OptionButton
var _status: Label
var _host_box: VBoxContainer
var _join_box: VBoxContainer
var _lobby_box: VBoxContainer
var _players_label: Label
var _info_label: Label
var _start_btn: Button
var _address: LineEdit
var _port: SpinBox
var _upnp: CheckBox
var _choice_box: VBoxContainer


func setup(p_session: NetSession) -> MultiplayerMenu:
	session = p_session
	session.lobby_changed.connect(_on_lobby)
	session.host_info_changed.connect(_on_host_info)
	session.join_failed.connect(_on_join_failed)
	session.ended.connect(func(reason): _fail(reason))
	return self


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.12, 0.11)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var title := Label.new()
	title.text = "Multiplayer (beta)"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Peer to peer: one player hosts, no server needed."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 8)
	box.add_child(_choice_box)
	_choice_box.add_child(_caption("Your name"))
	_name = LineEdit.new()
	_name.text = "Player"
	_choice_box.add_child(_name)
	_choice_box.add_child(_caption("Your deck"))
	_deck = OptionButton.new()
	for id in CardDB.deck_ids():
		_deck.add_item(CardDB.deck_name(id))
	_choice_box.add_child(_deck)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	_choice_box.add_child(tabs)
	var host_btn := Button.new()
	host_btn.text = "Host a game"
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(func(): _show_mode(true))
	tabs.add_child(host_btn)
	var join_btn := Button.new()
	join_btn.text = "Join a game"
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(func(): _show_mode(false))
	tabs.add_child(join_btn)

	_host_box = VBoxContainer.new()
	_host_box.visible = false
	_host_box.add_theme_constant_override("separation", 8)
	_choice_box.add_child(_host_box)
	_host_box.add_child(_caption("Port"))
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = NetSession.DEFAULT_PORT
	_host_box.add_child(_port)
	_upnp = CheckBox.new()
	_upnp.text = "Try to open the port on my router automatically (UPnP)"
	_upnp.button_pressed = true
	_host_box.add_child(_upnp)
	var open_btn := Button.new()
	open_btn.text = "Open lobby"
	open_btn.pressed.connect(_on_host_pressed)
	_host_box.add_child(open_btn)

	_join_box = VBoxContainer.new()
	_join_box.visible = false
	_join_box.add_theme_constant_override("separation", 8)
	_choice_box.add_child(_join_box)
	_join_box.add_child(_caption("Host's address (ip or ip:port)"))
	_address = LineEdit.new()
	_address.placeholder_text = "192.168.1.20:%d" % NetSession.DEFAULT_PORT
	_join_box.add_child(_address)
	var connect_btn := Button.new()
	connect_btn.text = "Connect"
	connect_btn.pressed.connect(_on_join_pressed)
	_join_box.add_child(connect_btn)

	_lobby_box = VBoxContainer.new()
	_lobby_box.visible = false
	_lobby_box.add_theme_constant_override("separation", 8)
	box.add_child(_lobby_box)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(500, 0)
	_lobby_box.add_child(_info_label)
	_players_label = Label.new()
	_players_label.add_theme_font_size_override("font_size", 20)
	_lobby_box.add_child(_players_label)
	_start_btn = Button.new()
	_start_btn.text = "Start game"
	_start_btn.pressed.connect(_on_start_pressed)
	_lobby_box.add_child(_start_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(500, 0)
	_status.add_theme_color_override("font_color", Color(1, 0.8, 0.5))
	box.add_child(_status)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func():
		session.close()
		back_requested.emit())
	box.add_child(back)


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _show_mode(host: bool) -> void:
	_host_box.visible = host
	_join_box.visible = not host
	_status.text = ""


func _selected_deck() -> String:
	return CardDB.deck_ids()[_deck.selected]


func _on_host_pressed() -> void:
	var err := session.host_game(int(_port.value), _name.text, _selected_deck(), _upnp.button_pressed)
	if err != OK:
		_status.text = "Could not open the lobby (error %d). Is the port already in use?" % err
		return
	_choice_box.visible = false
	_lobby_box.visible = true
	_start_btn.visible = true
	_status.text = ""


func _on_join_pressed() -> void:
	var target := NetSession.parse_address(_address.text)
	if String(target.address) == "":
		_status.text = "Enter the host's address first."
		return
	var err := session.join_game(target.address, target.port, _name.text, _selected_deck())
	if err != OK:
		_status.text = "Could not start connecting (error %d)." % err
		return
	_status.text = "Connecting to %s:%d..." % [target.address, target.port]


func _on_start_pressed() -> void:
	var problem := session.start_game()
	if problem != "":
		_status.text = problem


func _on_lobby(players: Array) -> void:
	_choice_box.visible = false
	_lobby_box.visible = true
	_start_btn.visible = session.is_host
	_start_btn.disabled = players.size() != NetSession.REQUIRED_PLAYERS
	_start_btn.text = "Start game" if not _start_btn.disabled else "Start game (waiting for another player)"
	var lines: Array = []
	for p in players:
		lines.append("%d. %s  -  %s%s" % [int(p.seat) + 1, p.name, CardDB.deck_name(p.deck), "  (you)" if p.you else ""])
	_players_label.text = "\n".join(lines)
	if not session.is_host:
		_info_label.text = "Connected. Waiting for the host to start the game..."
		_status.text = ""


func _on_host_info(info: Dictionary) -> void:
	var lines: Array = ["Give friends one of these addresses:"]
	if info.external != "":
		lines.append("Over the internet: %s:%d" % [info.external, int(info.port)])
	for ip in info.lan:
		lines.append("Same network: %s:%d" % [ip, int(info.port)])
	lines.append(String(info.upnp))
	_info_label.text = "\n".join(lines)


func _on_join_failed(message: String) -> void:
	_fail(message)


func _fail(message: String) -> void:
	_status.text = message
	_choice_box.visible = true
	_lobby_box.visible = false
	session.close()
