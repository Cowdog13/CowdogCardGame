extends SceneTree
## Both players' screens over a real local connection: the client's table shows ITS seat at the
## bottom, and clicks (submitted actions) flow through the host.   godot --headless -s tests/net_ui_test.gd
const PORT := 24986

func _make(root_name: String) -> NetSession:
	var holder := Control.new()
	holder.name = root_name
	root.add_child(holder)
	set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath("/root/" + root_name))
	var s := NetSession.new()
	s.name = "NetSession"
	holder.add_child(s)
	return s


func _init() -> void:
	var fails := 0
	var host := _make("HostPeer")
	var client := _make("ClientPeer")
	await process_frame
	var cs: Array = []
	client.game_ready.connect(func(c, seat): cs.append([c, seat]))
	host.host_game(PORT, "Alice", "scorching_fire", false)
	client.join_game("127.0.0.1", PORT, "Bob", "crashing_wave")
	for i in 60:
		await create_timer(0.05).timeout
		if host._players.size() == 2:
			break
	host.start_game()
	var screen_h := GameScreen.new()
	host.get_parent().add_child(screen_h)
	screen_h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_h.attach(host.controller, 0, false, false)
	for i in 60:
		await create_timer(0.05).timeout
		if cs.size() > 0:
			break
	var screen_c := GameScreen.new()
	client.get_parent().add_child(screen_c)
	screen_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_c.attach(cs[0][0], cs[0][1], false, false)
	await process_frame
	if screen_c.view.me != 1 or screen_c.ME != 1 or screen_c.OPP != 0:
		fails += 1
		print("client screen is not seated at 1")
	var ais := [AIAgent.new(0), AIAgent.new(1)]
	var steps := 0
	while not host.controller.engine.is_over() and steps < 2500:
		steps += 1
		for seat in host.controller.engine.awaiting():
			if seat == 0:
				screen_h._submit(ais[0].decide(screen_h.view))
			else:
				screen_c._submit(ais[1].decide(screen_c.view))
		await create_timer(0.02).timeout
	await create_timer(0.4).timeout
	print("finished after %d steps; client sees phase=%s, status='%s'" % [steps, screen_c.view.phase, screen_c._status])
	if not host.controller.engine.is_over() or screen_c.view.phase != "over":
		fails += 1
	if screen_c._log_bbcode.find("Alice") < 0 or screen_c._log_bbcode.find("Bob") < 0:
		fails += 1
		print("player names missing from the log")
	client.close()
	host.close()
	print("net_ui_test failures=%d" % fails)
	quit(fails)
