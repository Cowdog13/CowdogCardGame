extends SceneTree
## A player who drops out loses (concedes); the host's game goes on to a clean ending.
##   godot --headless -s tests/net_disconnect_test.gd
const PORT := 24985

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
	await process_frame
	var left: Array = []
	host.player_left.connect(func(seat): left.append(seat))
	host.host_game(PORT, "H", "scorching_fire", false)
	client.join_game("127.0.0.1", PORT, "J", "crashing_wave")
	for i in 60:
		await create_timer(0.05).timeout
		if host._players.size() == 2:
			break
	host.start_game()
	await create_timer(0.3).timeout
	client.close()
	for i in 60:
		await create_timer(0.05).timeout
		if host.controller.engine.is_over():
			break
	var fails := 0
	if not host.controller.engine.is_over() or host.controller.engine.state.winner != 0:
		fails += 1
		print("host should win after the other player left")
	if left != [1]:
		fails += 1
		print("player_left not reported: ", left)
	host.close()
	print("net_disconnect_test failures=%d" % fails)
	quit(fails)
