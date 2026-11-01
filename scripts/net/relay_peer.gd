class_name RelayPeer
extends MultiplayerPeerExtension
## A MultiplayerPeer that talks through a RelayServer (WebSocket) instead of a direct connection, so
## nobody needs to open a port. To the rest of the game it looks like an ordinary star network:
## the host is peer 1 and every joiner has an id of 2 or more; joiners only ever talk to the host.
##
## Wire format: text frames are small JSON control messages; binary frames carry game packets.
##   joiner -> relay -> host: [sender id: 4 bytes] + packet     host -> relay -> joiner: [target id: 4 bytes] + packet
## (On a joiner the relay strips the id, so a joiner's incoming frame is the bare packet.)

signal failed(message: String)  # could not connect, was refused, or the connection was lost
signal room_ready(code: String)  # host: the relay created the room

const MAX_PACKET := 1 << 20

var room_code := ""

var _ws := WebSocketPeer.new()
var _url := ""
var _code_to_join := ""
var _is_host := false
var _opened := false
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _my_id := 0
var _target := 0
var _channel := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _incoming: Array = []  # [{"from": int, "data": PackedByteArray}]
var _peers := {}  # host: ids of the joiners that are connected


func start_host(url: String) -> Error:
	_is_host = true
	return _start(url)


func start_join(url: String, code: String) -> Error:
	_is_host = false
	_code_to_join = code.strip_edges().to_upper()
	return _start(url)


func _start(url: String) -> Error:
	_url = url
	_ws.inbound_buffer_size = MAX_PACKET * 4
	_ws.outbound_buffer_size = MAX_PACKET * 4
	_ws.max_queued_packets = 2048
	_ws.heartbeat_interval = 15.0
	var err := _ws.connect_to_url(url)
	if err != OK:
		return err
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	return OK


# --- MultiplayerPeerExtension -------------------------------------------------------------------
func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _opened:
				_opened = true
				var hello := {"t": "host"} if _is_host else {"t": "join", "code": _code_to_join}
				_ws.send_text(JSON.stringify(hello))
			while _ws.get_available_packet_count() > 0:
				var data := _ws.get_packet()
				if _ws.was_string_packet():
					_on_control(JSON.parse_string(data.get_string_from_utf8()))
				else:
					_on_binary(data)
		WebSocketPeer.STATE_CLOSED:
			_lost("Lost the connection to the game server." if _opened else "Could not reach the game server at %s." % _url)


func _on_control(msg: Variant) -> void:
	if not msg is Dictionary:
		return
	match String(msg.get("t", "")):
		"hosted":
			room_code = String(msg.code)
			_my_id = 1
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			room_ready.emit(room_code)
		"joined":
			_my_id = int(msg.id)
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			peer_connected.emit(1)  # the host is always peer 1
		"peer_joined":
			var id := int(msg.id)
			_peers[id] = true
			peer_connected.emit(id)
		"peer_left":
			var id := int(msg.id)
			if _peers.erase(id):
				peer_disconnected.emit(id)
		"closed":  # the host left
			_lost("")
		"error":
			_lost(String(msg.get("msg", "The game server refused the request.")))


func _on_binary(data: PackedByteArray) -> void:
	if _is_host:
		if data.size() < 4:
			return
		var from := data.decode_u32(0)
		if _peers.has(int(from)):
			_incoming.append({"from": int(from), "data": data.slice(4)})
	else:
		_incoming.append({"from": 1, "data": data})


## The connection is over: tell the game who vanished, and why (an empty message means an ordinary leave).
func _lost(message: String) -> void:
	var was := _status
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	if _is_host:
		for id in _peers.keys():
			peer_disconnected.emit(id)
		_peers.clear()
	elif was == MultiplayerPeer.CONNECTION_CONNECTED:
		peer_disconnected.emit(1)
	_ws.close()
	if message != "" or was != MultiplayerPeer.CONNECTION_CONNECTED:
		failed.emit(message if message != "" else "Could not join the room.")


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front().data


func _get_packet_peer() -> int:
	return int(_incoming[0].from) if not _incoming.is_empty() else 0


func _get_available_packet_count() -> int:
	return _incoming.size()


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if buffer.size() > MAX_PACKET:
		return ERR_OUT_OF_MEMORY
	if _is_host:
		var targets: Array = []
		if _target > 0:
			targets = [_target]
		else:  # 0 = everyone; a negative number = everyone except that peer
			for id in _peers.keys():
				if id != -_target:
					targets.append(id)
		for id in targets:
			if _peers.has(id):
				_send_binary(id, buffer)
		return OK
	_send_binary(0, buffer)
	return OK


func _send_binary(id: int, buffer: PackedByteArray) -> void:
	var frame := PackedByteArray()
	if _is_host:
		frame.resize(4)
		frame.encode_u32(0, id)
	frame.append_array(buffer)
	_ws.send(frame, WebSocketPeer.WRITE_MODE_BINARY)


func _get_max_packet_size() -> int:
	return MAX_PACKET


func _get_packet_channel() -> int:
	return 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_target_peer(peer: int) -> void:
	_target = peer


func _is_server() -> bool:
	return _is_host


func _is_server_relay_supported() -> bool:
	return false


func _close() -> void:
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_ws.close()
	_incoming.clear()
	_peers.clear()


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _is_host and _peers.erase(peer):
		peer_disconnected.emit(peer)


func _get_unique_id() -> int:
	return _my_id


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _set_refuse_new_connections(_enable: bool) -> void:
	pass


func _is_refusing_new_connections() -> bool:
	return false
