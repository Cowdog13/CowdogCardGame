class_name NetSession
extends Node
## Peer-to-peer multiplayer without a dedicated server: one player's game is the host, the others
## connect straight to it (ENet over UDP; UPnP opens the router port when it can).
##
## The host runs the real GameEngine, so it alone decides what is legal. Every other player sends
## its actions to the host and receives, after each change, the new events plus ITS OWN view of the
## game (opponents' hands and deck order are never sent). RPCs are used only for these few
## messages; everything else is plain data (see GameEngine.get_view / submit).
##
## The lobby is already shaped for up to MAX_SEATS players and every message names a seat; the
## rules engine plays 2 players for now (REQUIRED_PLAYERS).
##
## One script serves host and client on purpose: Godot matches RPCs by node path and method list,
## so both sides must run the same script, and both add it as /root/NetSession.

signal lobby_changed(players: Array)  # [{"seat": int, "name": String, "deck": String, "you": bool}]
signal host_info_changed(info: Dictionary)  # {"port", "lan": [ip], "external": ip, "upnp": String}
signal joined_lobby
signal join_failed(message: String)
signal ended(reason: String)  # the connection is gone (host left, kicked, ...)
signal game_ready(controller: Node, my_seat: int)
signal player_left(seat: int)

const PROTOCOL := 1
const DEFAULT_PORT := 24680
const MAX_SEATS := 4
const REQUIRED_PLAYERS := 2
const ALLOWED_ACTION_KEYS := ["type", "hand", "slot", "discard", "ability", "params", "payment", "cards", "order", "from"]

var build_id := BuildInfo.fingerprint()  # compared when joining: everyone needs the same build (tests override it)
var is_host := false
var my_seat := 0
var controller: Node  # GameController on the host, RemoteController on clients
var started := false
var timer := TurnTimer.new()  # host: the turn clock (60 s per turn, +4 s per action); tests shorten it
var _clock_sent := 0.0

var _players: Array = []  # host: [{"peer": int, "name": String, "deck": String}] in seat order
var _names: Array = []  # client: names by seat once the game starts
var _local_name := "Player"
var _local_deck := ""
var _events: Array = []
var _upnp: UPNP = null
var _upnp_port := 0
var _thread: Thread = null
var _first_state_seen := false


# --- Hosting ----------------------------------------------------------------------------------
func host_game(port: int, player_name: String, deck: String, use_upnp: bool) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_SEATS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	is_host = true
	my_seat = 0
	_local_name = _clean_name(player_name)
	_players = [{"peer": 1, "name": _local_name, "deck": deck}]
	var info := {"port": port, "lan": _lan_addresses(), "external": "", "upnp": "Automatic router setup is off: for friends over the internet, forward UDP port %d to this computer." % port}
	if use_upnp:
		info.upnp = "Trying to open the port on your router..."
		_thread = Thread.new()
		_thread.start(_upnp_worker.bind(port))
	host_info_changed.emit(info)
	_emit_lobby()
	return OK


func _lan_addresses() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


## UPnP discovery blocks for a couple of seconds, so it runs on a thread.
func _upnp_worker(port: int) -> void:
	var upnp := UPNP.new()
	var info := {"port": port, "lan": _lan_addresses(), "external": "", "upnp": ""}
	var found := upnp.discover(2000, 2, "InternetGatewayDevice")
	var gateway := upnp.get_gateway()
	if found != UPNP.UPNP_RESULT_SUCCESS or gateway == null or not gateway.is_valid_gateway():
		info.upnp = "No router found (UPnP). Friends on your network can still join; for the internet, forward UDP port %d to this computer." % port
	else:
		var mapped := upnp.add_port_mapping(port, port, "Cowdog Card Game", "UDP", 0)
		if mapped == UPNP.UPNP_RESULT_SUCCESS:
			info.upnp = "Port %d opened on your router." % port
			info.external = upnp.query_external_address()
			_upnp = upnp
			_upnp_port = port
		else:
			info.upnp = "Your router refused UPnP. Forward UDP port %d to this computer to play over the internet." % port
	_upnp_finished.call_deferred(info)


func _upnp_finished(info: Dictionary) -> void:
	host_info_changed.emit(info)


func _on_peer_connected(_id: int) -> void:
	pass  # the player is added when its hello arrives


func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	var seat := _seat_of(id)
	if seat < 0:
		return
	if started:
		_players[seat]["peer"] = 0  # first: nothing more can be sent to them
		player_left.emit(seat)
		if controller != null and not controller.engine.is_over():
			controller.submit(seat, {"type": "concede"})  # leaving counts as a concession
	else:
		_players.remove_at(seat)
		_emit_lobby()
		_send_lobby()


func _seat_of(peer_id: int) -> int:
	for i in _players.size():
		if int(_players[i].peer) == peer_id:
			return i
	return -1


## Host only: start the game for everyone in the lobby. Returns "" or the reason it can't start.
## Host only: another game with the same two players, straight after one has ended.
func rematch() -> String:
	if not is_host or not started:
		return "There is no game to repeat."
	for p in _players:
		if int(p.peer) == 0:
			return "Your opponent has left, so there is nobody to play again."
	if controller != null:
		controller.queue_free()
		controller = null
	_events.clear()
	started = false
	return start_game()


func start_game() -> String:
	if not is_host or started:
		return "Already started."
	if _players.size() != REQUIRED_PLAYERS:
		return "Games need exactly %d players for now (%d in the lobby)." % [REQUIRED_PLAYERS, _players.size()]
	started = true
	var decks: Array = []
	var names: Array = []
	var agents: Array = []
	for i in _players.size():
		decks.append(_players[i].deck)
		names.append(_players[i].name)
		agents.append(HumanAgent.new(i) if i == 0 else RemoteAgent.new(i))
	for i in range(1, _players.size()):
		rpc_id(int(_players[i].peer), "rpc_begin", i, _players.size(), names)
	var ctrl := GameController.new()
	controller = ctrl
	add_child(ctrl)
	ctrl.event_logged.connect(func(ev): _events.append(ev))
	ctrl.view_updated.connect(_send_updates)
	timer = _fresh_timer()
	ctrl.action_done.connect(timer.on_action)
	ctrl.start(decks, agents, -1, names)
	game_ready.emit(ctrl, 0)
	return ""


func _fresh_timer() -> TurnTimer:
	var t := TurnTimer.new()
	t.base = timer.base
	t.bonus = timer.bonus
	return t


func _process(delta: float) -> void:
	if not is_host or not started or controller == null or controller.engine.state.is_empty():
		return
	var engine: GameEngine = controller.engine
	if engine.is_over():
		timer.seat = -1
		controller.clock_seat = -1
		return
	timer.sync(engine.state)
	var expired := timer.tick(delta)
	controller.clock_seat = timer.seat
	controller.clock_left = timer.remaining
	_clock_sent += delta
	if timer.changed or _clock_sent >= 1.0:
		timer.changed = false
		_clock_sent = 0.0
		for i in range(1, _players.size()):
			if int(_players[i].peer) != 0:
				rpc_id(int(_players[i].peer), "rpc_clock", timer.seat, timer.remaining)
	if expired:
		_expire()


## The active player's time is up: no action all turn forfeits, otherwise the turn is ended for them.
func _expire() -> void:
	var seat := timer.seat
	if timer.actions == 0:
		controller.submit(seat, {"type": "timeout"})
		return
	var guard := 0
	while not controller.engine.is_over() and guard < 20:
		guard += 1
		var pend: Dictionary = controller.engine.state.pending
		if pend.is_empty():
			break
		var who := int(pend.player)
		controller.submit(who, PlayerAgent.fallback_action(controller.engine.get_view(who)))
	if not controller.engine.is_over() and controller.engine.state.pending.is_empty():
		controller.submit(seat, {"type": "end_turn"})


func _send_updates() -> void:
	var events := _events
	_events = []
	for i in range(1, _players.size()):
		var peer := int(_players[i].peer)
		if peer != 0:
			rpc_id(peer, "rpc_state", events, controller.get_view(i))


func _emit_lobby() -> void:
	var out: Array = []
	for i in _players.size():
		out.append({"seat": i, "name": _players[i].name, "deck": _players[i].deck, "you": i == my_seat})
	lobby_changed.emit(out)


func _send_lobby() -> void:
	var summary: Array = []
	for i in _players.size():
		summary.append({"seat": i, "name": _players[i].name, "deck": _players[i].deck})
	for i in range(1, _players.size()):
		rpc_id(int(_players[i].peer), "rpc_lobby", summary, i)


# --- Joining ----------------------------------------------------------------------------------
func join_game(address: String, port: int, player_name: String, deck: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): join_failed.emit("Could not reach %s:%d." % [address, port]))
	multiplayer.server_disconnected.connect(func(): ended.emit("The host left the game."))
	is_host = false
	_local_name = _clean_name(player_name)
	_local_deck = deck
	return OK


func _on_connected() -> void:
	rpc_id(1, "rpc_hello", PROTOCOL, build_id, _local_name, _local_deck)


## Accepts "ip", "ip:port" or "[::1]:port" style join codes.
static func parse_address(text: String) -> Dictionary:
	var t := text.strip_edges()
	var port := DEFAULT_PORT
	var host := t
	var colon := t.rfind(":")
	if colon > 0 and t.count(":") == 1:
		host = t.substr(0, colon)
		port = int(t.substr(colon + 1))
	return {"address": host, "port": port}


# --- Leaving ----------------------------------------------------------------------------------
func close() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	if _upnp != null and _upnp_port != 0:
		_upnp.delete_port_mapping(_upnp_port, "UDP")
		_upnp = null
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


func _exit_tree() -> void:
	close()


static func _clean_name(raw: String) -> String:
	var n := raw.strip_edges().substr(0, 20)
	return n if n != "" else "Player"


# --- Messages -------------------------------------------------------------------------------------
## Client -> host: join the lobby.
@rpc("any_peer", "reliable")
func rpc_hello(protocol: int, build: String, player_name: String, deck: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if protocol != PROTOCOL:
		reason = "Different game versions (host %d, you %d)." % [PROTOCOL, protocol]
	elif build != build_id:
		reason = "You are on a different build than the host. Host: %s. You: %s. Everyone needs the same download." % [build_id, build]
	elif started:
		reason = "The game has already started."
	elif _players.size() >= MAX_SEATS:
		reason = "The lobby is full."
	elif not CardDB.deck_ids().has(deck):
		reason = "Unknown deck."
	elif _seat_of(id) >= 0:
		return
	if reason != "":
		rpc_id(id, "rpc_refused", reason)
		return
	_players.append({"peer": id, "name": _clean_name(player_name), "deck": deck})
	_emit_lobby()
	_send_lobby()


## Host -> client: you can't join.
@rpc("authority", "reliable")
func rpc_refused(reason: String) -> void:
	join_failed.emit(reason)


## Host -> client: the current lobby and your seat.
@rpc("authority", "reliable")
func rpc_lobby(summary: Array, your_seat: int) -> void:
	my_seat = your_seat
	var out: Array = []
	for p in summary:
		out.append({"seat": int(p.seat), "name": String(p.name), "deck": String(p.deck), "you": int(p.seat) == your_seat})
	lobby_changed.emit(out)
	joined_lobby.emit()


## Host -> client: the game is starting.
@rpc("authority", "reliable")
func rpc_begin(seat: int, _count: int, names: Array) -> void:
	started = true
	my_seat = seat
	_names = names
	if controller != null:
		controller.queue_free()  # a rematch: the old game's controller goes
	var rc := RemoteController.new()
	rc.setup(func(action: Dictionary): rpc_id(1, "rpc_action", action))
	controller = rc
	add_child(rc)
	_first_state_seen = false


## Host -> client: what happened, and the new view of the game for this seat.
@rpc("authority", "reliable")
func rpc_state(events: Array, view: Dictionary) -> void:
	if is_host or not controller is RemoteController:
		return
	(controller as RemoteController).apply_update(events, view)
	if not _first_state_seen:
		_first_state_seen = true
		game_ready.emit(controller, my_seat)


## Host -> client: whose turn clock is running and how many seconds it has left.
@rpc("authority", "reliable")
func rpc_clock(seat: int, seconds: float) -> void:
	if not is_host and controller is RemoteController:
		(controller as RemoteController).set_clock(seat, seconds)


## Client -> host: play this action.
@rpc("any_peer", "reliable")
func rpc_action(action: Dictionary) -> void:
	if not is_host or not started or controller == null:
		return
	var id := multiplayer.get_remote_sender_id()
	var seat := _seat_of(id)
	if seat <= 0:
		return
	if not _action_is_sane(action) or action.type == "timeout":
		rpc_id(id, "rpc_error", "Malformed action.")
		return
	var res: Dictionary = controller.submit(seat, action)
	if not res.ok:
		rpc_id(id, "rpc_error", String(res.error))


## Host -> client: the action was not legal.
@rpc("authority", "reliable")
func rpc_error(message: String) -> void:
	if controller is RemoteController:
		(controller as RemoteController).reject(message)


## Cheap shape check so a modified client can't feed the engine values of the wrong type.
func _action_is_sane(action: Dictionary) -> bool:
	for key in action.keys():
		if not ALLOWED_ACTION_KEYS.has(key):
			return false
	if not action.get("type") is String:
		return false
	for k in ["hand", "slot", "discard", "ability"]:
		if action.has(k) and not (action[k] is int or action[k] is float):
			return false
	for k in ["payment", "cards", "order"]:
		if action.has(k) and not action[k] is Array:
			return false
	if action.has("params") and not action.params is Dictionary:
		return false
	if action.has("from") and not action["from"] is String:
		return false
	return true
