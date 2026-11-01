class_name RelayServer
extends Node
## The tiny server behind "room codes". It never looks inside a game: it hands out room codes and
## forwards packets between a room's host and its joiners (see RelayPeer for the wire format).
## Players only make outgoing connections to it, so nobody has to open a port.
##
## Run it headless (this is what tools/start_server.bat does):
##   CowdogCardGame.exe --headless -- --relay --port=24681
## then put a tunnel (e.g. cloudflared) or a router port forward in front of it.

const DEFAULT_PORT := 24681
const MAX_ROOMS := 200
const MAX_JOINERS := 3  # per room (the lobby holds 4 seats)
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"
const CODE_LENGTH := 5
const IDLE_SECONDS := 600.0  # connections that never say hello are dropped

var port := DEFAULT_PORT
var verbose := true

var _tcp := TCPServer.new()
var _conns: Array = []  # [{"ws": WebSocketPeer, "role": "", "room": "", "id": int, "age": float}]
var _rooms := {}  # code -> {"host": conn, "joiners": {id: conn}, "next_id": int}
var _rng := RandomNumberGenerator.new()


func start(p_port: int = DEFAULT_PORT) -> Error:
	port = p_port
	_rng.randomize()
	var err := _tcp.listen(port)
	if err == OK:
		_log("Relay listening on port %d." % port)
	return err


func stop() -> void:
	_tcp.stop()
	for c in _conns:
		c.ws.close()
	_conns.clear()
	_rooms.clear()


func room_count() -> int:
	return _rooms.size()


func _process(delta: float) -> void:
	while _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = RelayPeer.MAX_PACKET * 2
		ws.outbound_buffer_size = RelayPeer.MAX_PACKET * 2
		ws.max_queued_packets = 2048
		ws.heartbeat_interval = 20.0
		if ws.accept_stream(_tcp.take_connection()) == OK:
			_conns.append({"ws": ws, "role": "", "room": "", "id": 0, "age": 0.0})
	for c in _conns.duplicate():
		var ws: WebSocketPeer = c.ws
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				c.age += delta
				while ws.get_available_packet_count() > 0:
					var data := ws.get_packet()
					if ws.was_string_packet():
						_on_control(c, JSON.parse_string(data.get_string_from_utf8()))
					else:
						_on_binary(c, data)
				if c.role == "" and c.age > IDLE_SECONDS:
					ws.close()
			WebSocketPeer.STATE_CLOSED:
				_drop(c)


func _on_control(c: Dictionary, msg: Variant) -> void:
	if not msg is Dictionary or c.role != "":
		return
	match String(msg.get("t", "")):
		"host":
			if _rooms.size() >= MAX_ROOMS:
				_send(c, {"t": "error", "msg": "The server is full. Try again later."})
				return
			var code := _new_code()
			_rooms[code] = {"host": c, "joiners": {}, "next_id": 2}
			c.role = "host"
			c.room = code
			c.id = 1
			_send(c, {"t": "hosted", "code": code})
			_log("Room %s opened (%d open)." % [code, _rooms.size()])
		"join":
			var code := String(msg.get("code", "")).strip_edges().to_upper()
			if not _rooms.has(code):
				_send(c, {"t": "error", "msg": "No game with the code %s. Check the code with the host." % code})
				return
			var room: Dictionary = _rooms[code]
			if room.joiners.size() >= MAX_JOINERS:
				_send(c, {"t": "error", "msg": "That room is full."})
				return
			var id: int = room.next_id
			room.next_id += 1
			room.joiners[id] = c
			c.role = "joiner"
			c.room = code
			c.id = id
			_send(c, {"t": "joined", "id": id})
			_send(room.host, {"t": "peer_joined", "id": id})
			_log("Player %d joined room %s." % [id, code])


func _on_binary(c: Dictionary, data: PackedByteArray) -> void:
	if c.room == "" or not _rooms.has(c.room):
		return
	var room: Dictionary = _rooms[c.room]
	if c.role == "joiner":
		var frame := PackedByteArray()
		frame.resize(4)
		frame.encode_u32(0, c.id)
		frame.append_array(data)
		room.host.ws.send(frame, WebSocketPeer.WRITE_MODE_BINARY)
	elif c.role == "host" and data.size() >= 4:
		var target := data.decode_u32(0)
		var payload := data.slice(4)
		if target == 0:
			for j in room.joiners.values():
				j.ws.send(payload, WebSocketPeer.WRITE_MODE_BINARY)
		elif room.joiners.has(int(target)):
			room.joiners[int(target)].ws.send(payload, WebSocketPeer.WRITE_MODE_BINARY)


func _drop(c: Dictionary) -> void:
	_conns.erase(c)
	if c.room == "" or not _rooms.has(c.room):
		return
	var room: Dictionary = _rooms[c.room]
	if c.role == "host":
		for j in room.joiners.values():
			_send(j, {"t": "closed"})
			j.ws.close()
			j.room = ""
		_rooms.erase(c.room)
		_log("Room %s closed (%d open)." % [c.room, _rooms.size()])
	elif c.role == "joiner":
		room.joiners.erase(c.id)
		_send(room.host, {"t": "peer_left", "id": c.id})


func _send(c: Dictionary, msg: Dictionary) -> void:
	c.ws.send_text(JSON.stringify(msg))


func _new_code() -> String:
	while true:
		var code := ""
		for i in CODE_LENGTH:
			code += CODE_LETTERS[_rng.randi() % CODE_LETTERS.length()]
		if not _rooms.has(code):
			return code
	return ""


func _log(text: String) -> void:
	if verbose:
		print("[relay] ", text)
