extends SceneTree
## AI vs AI win rates for every pairing of decks, with each deck playing first and second.
##   godot --headless -s tests/balance_matrix.gd -- [games per pairing and seat, default 40]
## It is only a rough guide (the AI is not a strong player) but it flags decks that are far ahead or behind.
func _play(d0: String, d1: String, seed_val: int) -> Dictionary:
	var e := GameEngine.new()
	e.setup([d0, d1], seed_val)
	var agents := [AIAgent.new(0), AIAgent.new(1)]
	var steps := 0
	while not e.is_over() and steps < 3000:
		steps += 1
		var seat: int = e.awaiting()[0]
		var view := e.get_view(seat)
		var action: Dictionary = agents[seat].decide(view)
		if not e.submit(seat, action).ok:
			e.submit(seat, PlayerAgent.fallback_action(view))
	return {"winner": e.state.winner, "turns": e.state.turn, "first": e.state.first_player}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 40
	if args.size() > 1 and args[1].begins_with("cap"):  # experiment: cap Tidal Surge's plunder, e.g. "cap6"
		CardDB.card("water_essence").abilities[0].effects[1]["max"] = int(args[1].substr(3))
	if args.size() > 1 and args[1] == "no-essence":  # experiment: what if Water Essence could not use Tidal Surge?
		CardDB.card("water_essence").abilities[0].cost = {"element": "super", "amount": 99}
	var decks := CardDB.deck_ids()
	var wins := {}  # "a|b" -> wins of a against b
	var games := {}
	var turns := 0
	var total := 0
	var first_wins := 0
	for a in decks:
		for b in decks:
			if a >= b:
				continue
			for k in n:
				for swap in [false, true]:
					var d0: String = b if swap else a
					var d1: String = a if swap else b
					var r := _play(d0, d1, 1000 + k * 7 + (1 if swap else 0))
					var winner_deck: String = d0 if r.winner == 0 else d1
					wins["%s|%s" % [a, b]] = int(wins.get("%s|%s" % [a, b], 0)) + (1 if winner_deck == a else 0)
					games["%s|%s" % [a, b]] = int(games.get("%s|%s" % [a, b], 0)) + 1
					turns += r.turns
					total += 1
					if r.winner == r.first:
						first_wins += 1
	print("games per pairing: %d, average length %.1f turns, the player who goes first wins %.0f%%" % [n * 2, float(turns) / total, 100.0 * first_wins / total])
	var overall := {}
	for key in games:
		var ab: PackedStringArray = key.split("|")
		var w: int = wins[key]
		var g: int = games[key]
		print("  %-14s beats %-14s %3d%%   (%d-%d)" % [CardDB.deck_name(ab[0]), CardDB.deck_name(ab[1]), 100 * w / g, w, g - w])
		overall[ab[0]] = overall.get(ab[0], [0, 0])
		overall[ab[1]] = overall.get(ab[1], [0, 0])
		overall[ab[0]][0] += w
		overall[ab[0]][1] += g
		overall[ab[1]][0] += g - w
		overall[ab[1]][1] += g
	print("overall win rate by deck:")
	for d in decks:
		print("  %-14s %3d%%" % [CardDB.deck_name(d), 100 * overall[d][0] / overall[d][1]])
	quit()
