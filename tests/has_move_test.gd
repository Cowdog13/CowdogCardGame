extends SceneTree
## Whenever the AI finds a real move, Rules.has_move (the End Turn flash) must agree:  godot --headless -s tests/has_move_test.gd
func _init() -> void:
	var fails := 0
	var checked := 0
	var decks := CardDB.deck_ids()
	for g in 30:
		var e := GameEngine.new()
		e.setup([decks[g % decks.size()], decks[(g / 3) % decks.size()]], g)
		var agents := [AIAgent.new(0), AIAgent.new(1)]
		var steps := 0
		while not e.is_over() and steps < 1500:
			steps += 1
			var seat: int = e.awaiting()[0]
			var view := e.get_view(seat)
			var action: Dictionary = agents[seat].decide(view)
			if e.state.phase == "main" and e.state.pending.is_empty() and action.type != "end_turn":
				checked += 1
				if not Rules.has_move(view):
					fails += 1
					print("has_move false but the AI plays ", action, " (game ", g, ")")
			if not e.submit(seat, action).ok:
				e.submit(seat, PlayerAgent.fallback_action(view))
	print("has_move_test checked=%d failures=%d" % [checked, fails])
	quit(fails)
