extends SceneTree
## Headless AI-vs-AI simulation and rule checks:
##   godot --headless -s tests/run_sim.gd -- [games]
## Exits non-zero if an illegal AI action, a stuck game or an invariant violation is found.

func _init() -> void:
	var games := 200
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		games = int(args[0])
	var decks := CardDB.deck_ids()
	var problems := 0
	var wins := {}
	var turns_total := 0
	for g in games:
		var d0: String = decks[g % decks.size()]
		var d1: String = decks[(g / decks.size()) % decks.size()]
		var engine := GameEngine.new()
		engine.setup([d0, d1], g)
		var agents := [AIAgent.new(0), AIAgent.new(1)]
		var steps := 0
		while not engine.is_over() and steps < 4000:
			steps += 1
			for seat in engine.awaiting():
				var view := engine.get_view(seat)
				var action: Dictionary = agents[seat].decide(view)
				var res := engine.submit(seat, action)
				if not res.ok:
					problems += 1
					print("ILLEGAL game %d seat %d %s -> %s" % [g, seat, action, res.error])
					engine.submit(seat, PlayerAgent.fallback_action(view))
		if not engine.is_over():
			problems += 1
			print("STUCK game %d" % g)
			continue
		var total := 0  # stolen Super Berries move between players, so check the combined total
		for p in 2:
			var pl: Dictionary = engine.state.players[p]
			total += pl.deck.size() + pl.hand.size() + pl.discard.size() + pl.exile.size()
			for c in pl.board:
				if c != null:
					total += c.cards.size() + c.berries.size()
		if total != 100:
			problems += 1
			print("CARD COUNT game %d = %d" % [g, total])
		var key := "%s(P%d) vs %s" % [d0, 0, d1]
		var w: int = engine.state.winner
		wins["%s %s" % [key, "first-seat" if w == 0 else "second-seat"]] = int(wins.get("%s %s" % [key, "first-seat" if w == 0 else "second-seat"], 0)) + 1
		turns_total += engine.state.turn
	print("games=%d avg_turns=%.1f problems=%d" % [games, float(turns_total) / games, problems])
	for k in wins:
		print("  %s: %d" % [k, wins[k]])
	quit(1 if problems > 0 else 0)
