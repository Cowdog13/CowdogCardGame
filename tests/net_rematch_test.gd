extends SceneTree
## Online: a client on a different build is refused, and the host can start another game with the same player.
##   godot --headless -s tests/net_rematch_test.gd
const PORT := 24988
var fails := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: " + msg)


func _make(root_name: String) -> NetSession:
	var holder := Node.new()
	holder.name = root_name
	root.add_child(holder)
	set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath("/root/" + root_name))
	var s := NetSession.new()
	s.name = "NetSession"
	holder.add_child(s)
	return s


func _init() -> void:
	var host := _make("HostPeer")
	var client := _make("ClientPeer")
	var old := _make("OldPeer")
	await process_frame
	var refusals: Array = []
	client.join_failed.connect(func(m): refusals.append(m))
	var ready := []
	client.game_ready.connect(func(c, seat): ready.append(seat))
	var lobby := []
	client.lobby_changed.connect(func(p): lobby.assign(p))
	check(host.host_game(PORT, "Hosty", "scorching_fire", false) == OK, "host opens")
	# 1. A different build is refused with a clear message.
	var old_refusals: Array = []
	old.join_failed.connect(func(m): old_refusals.append(m))
	old.build_id = "0.0.1-old"
	check(old.join_game("127.0.0.1", PORT, "Old", "light") == OK, "an old client connects to the port")
	await create_timer(0.8).timeout
	check(old_refusals.size() == 1 and "different build" in old_refusals[0], "and is refused: %s" % [old_refusals])
	old.close()
	check(client.join_game("127.0.0.1", PORT, "Joiner", "light") == OK, "client connects")
	await create_timer(0.8).timeout
	check(lobby.size() == 2, "same build: joins the lobby")
	check(host.rematch() != "", "no rematch before a game has been played")
	check(host.start_game() == "", "host starts")
	for i in 60:
		await create_timer(0.05).timeout
		if ready.size() > 0:
			break
	check(ready.size() == 1, "client's first game")
	# 2. End the game, then rematch: the client gets a second, fresh game.
	var first: GameController = host.controller
	first.submit(1, {"type": "concede"})
	await create_timer(0.3).timeout
	check(first.engine.is_over(), "game one is over")
	check(host.rematch() == "", "host starts a rematch")
	for i in 60:
		await create_timer(0.05).timeout
		if ready.size() > 1:
			break
	check(ready.size() == 2 and ready[1] == 1, "the client is given the rematch")
	check(host.controller != first and not host.controller.engine.is_over() and host.controller.engine.state.phase == "mulligan", "a new game began")
	check(client.controller is RemoteController and client.controller.has_view(), "the client follows the new game")
	client.close()
	host.close()
	print("net_rematch_test failures=%d" % fails)
	quit(fails)
