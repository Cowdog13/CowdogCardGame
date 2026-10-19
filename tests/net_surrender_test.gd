extends SceneTree
## Menu -> confirm in a multiplayer game surrenders: that player loses, both players see the result.
##   godot --headless -s tests/net_surrender_test.gd
const PORT := 24984

func _make(root_name: String) -> NetSession:
	var holder := Control.new()
	holder.name = root_name
	root.add_child(holder)
	set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath("/root/" + root_name))
	var s := NetSession.new()
	s.name = "NetSession"
	holder.add_child(s)
	return s


func _confirm_open_dialog(screen: GameScreen) -> bool:
	for c in screen.get_children():
		if c is ConfirmationDialog:
			c.confirmed.emit()
			return true
	return false


func _init() -> void:
	var fails := 0
	var host := _make("HostPeer")
	var client := _make("ClientPeer")
	await process_frame
	var ready: Array = []
	client.game_ready.connect(func(c, seat): ready.append([c, seat]))
	host.host_game(PORT, "Alice", "scorching_fire", false)
	client.join_game("127.0.0.1", PORT, "Bob", "crashing_wave")
	for i in 60:
		await create_timer(0.05).timeout
		if host._players.size() == 2:
			break
	host.start_game()
	var screen_h := GameScreen.new()
	host.get_parent().add_child(screen_h)
	screen_h.attach(host.controller, 0, false, false)
	for i in 60:
		await create_timer(0.05).timeout
		if ready.size() > 0:
			break
	var screen_c := GameScreen.new()
	client.get_parent().add_child(screen_c)
	screen_c.attach(ready[0][0], ready[0][1], false, false)
	await create_timer(0.2).timeout
	# Pressing Menu only asks; nothing happens until it is confirmed.
	screen_c._on_menu_pressed()
	await process_frame
	if host.controller.engine.is_over():
		fails += 1
		print("the game ended without confirmation")
	if not _confirm_open_dialog(screen_c):
		fails += 1
		print("no confirmation dialog")
	await create_timer(0.4).timeout
	var engine: GameEngine = host.controller.engine
	if not engine.is_over() or engine.state.winner != 0:
		fails += 1
		print("host should win after the client surrendered")
	if screen_c.view.get("phase", "") != "over" or int(screen_c.view.winner) != 0:
		fails += 1
		print("the surrendering client should see the game as lost")
	client.close()
	host.close()
	print("net_surrender_test failures=%d" % fails)
	quit(fails)
