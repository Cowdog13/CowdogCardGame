extends SceneTree
## A saved game report replays to exactly the same game; build info is stable.   godot --headless -s tests/replay_test.gd
func _init() -> void:
	var fails := 0
	if BuildInfo.data_hash().length() != 8 or BuildInfo.fingerprint() != "%s-%s" % [BuildInfo.VERSION, BuildInfo.data_hash()]:
		fails += 1
		print("bad build info")
	for deck_pair in [["nature_exile", "crashing_wave"], ["light", "scorching_fire"]]:
		var ctrl := GameController.new()
		ctrl.ai_delay = 0.0
		root.add_child(ctrl)
		ctrl.start(deck_pair, [AIAgent.new(0), AIAgent.new(1)], -1, ["A", "B"])  # a random 64-bit seed, as in a real game
		var waited := 0
		while not ctrl.engine.is_over() and waited < 6000:
			await process_frame
			waited += 1
		if not ctrl.engine.is_over():
			fails += 1
			print("game did not finish")
			continue
		var report := GameReport.build(ctrl, 0, ["line"], "single player")
		var path := GameReport.save(report, "test")
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		DirAccess.remove_absolute(path)
		var copy := GameReport.replay(parsed)
		var a: Dictionary = ctrl.engine.state
		var b: Dictionary = copy.state
		if copy == null or a.winner != b.winner or a.turn != b.turn or a.players[0].discard != b.players[0].discard \
				or a.players[1].deck != b.players[1].deck or a.players[0].exile != b.players[0].exile:
			fails += 1
			print("replay differs from the original game: ", deck_pair)
		else:
			print("replayed %s: %d actions, winner %d in %d turns" % [deck_pair, parsed.actions.size(), b.winner, b.turn])
		ctrl.queue_free()
	print("replay_test failures=%d" % fails)
	quit(fails)
