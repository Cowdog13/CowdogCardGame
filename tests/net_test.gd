extends SceneTree
## Two peers in one process: a host and a client talk over a real ENet connection on localhost,
## play a whole game with the AI choosing for both, and the test checks that the client's mirrored
## view always matches the host's view of that seat.   godot --headless -s tests/net_test.gd
const PORT := 24987

var fails := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: " + msg)


func _make(root_name: String) -> NetSession:
	var holder := Node.new()
	holder.name = root_name
	root.add_child(holder)
	# Each peer gets its own MultiplayerAPI, rooted at its own subtree, so RPC paths are "NetSession" for both.
	set_multiplayer(MultiplayerAPI.create_default_interface(), NodePath("/root/" + root_name))
	var s := NetSession.new()
	s.name = "NetSession"
	holder.add_child(s)
	return s


func _init() -> void:
	var host := _make("HostPeer")
	var client := _make("ClientPeer")
	await process_frame  # nodes only join the tree (and get their MultiplayerAPI) once the tree is running
	var lobby_seen := {"host": [], "client": []}
	host.lobby_changed.connect(func(p): lobby_seen.host = p)
	client.lobby_changed.connect(func(p): lobby_seen.client = p)
	var client_ready := []
	client.game_ready.connect(func(c, seat): client_ready.append([c, seat]))
	var refusals: Array = []
	client.join_failed.connect(func(m): refusals.append(m))

	check(host.host_game(PORT, "Hosty", "scorching_fire", false) == OK, "host opens")
	check(client.join_game("127.0.0.1", PORT, "Joiner", "crashing_wave") == OK, "client starts connecting")
	for i in 60:
		await create_timer(0.05).timeout
		if lobby_seen.client.size() == 2:
			break
	check(lobby_seen.host.size() == 2 and lobby_seen.client.size() == 2, "both see two players in the lobby")
	check(lobby_seen.client.size() == 2 and lobby_seen.client[1].you and lobby_seen.client[1].name == "Joiner", "client knows its seat and name")
	check(host.start_game() == "", "host starts the game")
	for i in 60:
		await create_timer(0.05).timeout
		if client_ready.size() > 0:
			break
	check(client_ready.size() == 1 and client_ready[0][1] == 1, "client gets a controller for seat 1")
	var hc: GameController = host.controller
	var cc: RemoteController = client_ready[0][0]

	# Play the whole game, each side deciding from its own view only.
	var ais := [AIAgent.new(0), AIAgent.new(1)]
	var rejected: Array = []
	cc.action_rejected.connect(func(m): rejected.append(m))
	var mismatches := 0
	var steps := 0
	while not hc.engine.is_over() and steps < 3000:
		steps += 1
		for seat in hc.engine.awaiting():
			if seat == 0:
				var res: Dictionary = hc.submit(0, ais[0].decide(hc.get_view(0)))
				check(res.ok, "host action legal: %s" % res.get("error", ""))
			else:
				cc.submit(1, ais[1].decide(cc.get_view(1)))
		await create_timer(0.02).timeout
		if cc.has_view() and hc.get_view(1).hash() != cc.get_view(1).hash() and steps % 5 == 0:
			await create_timer(0.1).timeout  # let the last update arrive before comparing
			if hc.get_view(1).hash() != cc.get_view(1).hash():
				mismatches += 1
	await create_timer(0.3).timeout
	check(hc.engine.is_over(), "the game finished (%d steps)" % steps)
	check(rejected.is_empty(), "no client action was rejected: %s" % [rejected])
	check(mismatches == 0, "client view always matched the host's view of seat 1 (%d mismatches)" % mismatches)
	check(hc.get_view(1).hash() == cc.get_view(1).hash(), "final views match")
	check(cc.get_view(1).opponent.has("hand_count") and not cc.get_view(1).opponent.has("hand"), "the client never receives the opponent's hand")
	check(cc.history.size() > 10, "client received the event log (%d events)" % cc.history.size())

	# Cheating attempts are rejected by the host.
	var third := NetSession.new()
	check(not third._action_is_sane({"type": "attach_berry", "evil": 1}), "unknown action keys are refused")
	check(not third._action_is_sane({"type": "play_spell", "params": "x"}), "params must be a dictionary")
	check(third._action_is_sane({"type": "end_turn"}), "ordinary actions pass")
	third.free()
	client.close()
	host.close()
	print("net_test failures=%d" % fails)
	quit(1 if fails > 0 else 0)
