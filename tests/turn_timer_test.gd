extends SceneTree
## Multiplayer turn clock: +2 s per action, auto end of turn on timeout, forfeit when idle.
##   godot --headless -s tests/turn_timer_test.gd
const PORT := 24985

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
	# Pure timer logic.
	var t := TurnTimer.new()
	t.sync({"phase": "mulligan", "turn": 1, "active": 0})
	if t.seat != -1:
		fails += 1
		print("no clock during the mulligan")
	t.sync({"phase": "main", "turn": 1, "active": 0})
	if t.seat != 0 or t.remaining != 40.0:
		fails += 1
		print("a turn should start with 40 s")
	t.tick(10.0)
	t.on_action(0, {"type": "attach_berry"})
	t.on_action(1, {"type": "attach_berry"})
	t.on_action(0, {"type": "end_turn"})
	if absf(t.remaining - 32.0) > 0.01 or t.actions != 1:
		fails += 1
		print("one action adds 2 s (and only the active player's): ", t.remaining, " ", t.actions)
	t.sync({"phase": "main", "turn": 2, "active": 1})
	if t.seat != 1 or t.remaining != 40.0 or t.actions != 0:
		fails += 1
		print("a new turn resets the clock")
	if not t.tick(41.0):
		fails += 1
		print("should expire")

	# In a real session.
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
	host.timer.base = 1.0
	host.timer.bonus = 0.5
	host.start_game()
	for i in 60:
		await create_timer(0.05).timeout
		if ready.size() > 0:
			break
	var engine: GameEngine = host.controller.engine
	for p in 2:
		host.controller.submit(p, {"type": "mulligan", "cards": []})
	await create_timer(0.3).timeout
	if host.controller.clock_seat != engine.state.active:
		fails += 1
		print("the host's clock should run for the active player")
	if ready[0][0].clock_seat != engine.state.active:
		fails += 1
		print("the client should be told whose clock is running")
	# Idle player: forfeits.
	var idle: int = engine.state.active
	await create_timer(1.6).timeout
	if not engine.is_over() or engine.state.winner != 1 - idle:
		fails += 1
		print("a player who does nothing should lose when time runs out; phase=", engine.state.phase)

	# Rematch; this time the active player acts once and then stalls: the turn just ends.
	host.rematch()
	await create_timer(0.3).timeout
	engine = host.controller.engine
	for p in 2:
		host.controller.submit(p, {"type": "mulligan", "cards": []})
	await create_timer(0.2).timeout
	var actor: int = engine.state.active
	var turn_before: int = engine.state.turn
	var view := engine.get_view(actor)
	var did := false
	for hi in view.you.hand.size():
		if CardDB.is_berry(view.you.hand[hi]):
			did = host.controller.submit(actor, {"type": "attach_berry", "hand": hi, "slot": 0}).ok
			break
		if CardDB.card(view.you.hand[hi]).type == "creature" and CardDB.card(view.you.hand[hi]).evolves_from == "":
			did = host.controller.submit(actor, {"type": "play_creature", "hand": hi, "slot": 0}).ok
			break
	if not did:
		print("(test setup: no simple action available with this seed, skipping that part)")
	else:
		await create_timer(2.2).timeout
		if engine.is_over() or engine.state.turn == turn_before:
			fails += 1
			print("after an action the turn should simply end on timeout; over=", engine.is_over(), " turn=", engine.state.turn)
	print("turn_timer_test failures=%d" % fails)
	quit(fails)
