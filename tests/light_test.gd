extends SceneTree
## The Light deck's effects, played directly on the engine.   godot --headless -s tests/light_test.gd
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)


func _creature(id: String, berries: Array) -> Dictionary:
	var ex: Array = []
	ex.resize(berries.size())
	ex.fill(false)
	return {"cards": [id], "berries": berries, "exhausted": ex, "stun_until": -1, "ability_used_turn": -1}


func _game() -> GameEngine:
	var e := GameEngine.new()
	e.setup(["light", "light"], 5)
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.turn = 5
	e.state.active = 0
	for p in 2:
		var pl: Dictionary = e.state.players[p]
		pl.hand = []
		pl.discard = []
		pl.exile = []
		pl.board = [null, null, null, null, null]
	return e


func _use(e: GameEngine, slot: int, ability: int, params := {}) -> Dictionary:
	return e.submit(0, {"type": "use_ability", "slot": slot, "ability": ability, "params": params})


func _init() -> void:
	var deck := CardDB.build_deck_list("light")
	check(deck.size() == 50 and deck.count("super_berry") == 7 and deck.count("light_berry") == 16, "50 cards, 7 Super + 16 Light Berries")

	# Draw 1, and the deck contents are visible (sorted) only in your own view.
	var e := _game()
	var pl: Dictionary = e.state.players[0]
	var opp: Dictionary = e.state.players[1]
	pl.board[0] = _creature("lighturn", ["light_berry", "light_berry"])
	var deck_before: int = pl.deck.size()
	check(_use(e, 0, 0).ok and pl.hand.size() == 1 and pl.deck.size() == deck_before - 1, "Draw 1")
	var view := e.get_view(0)
	var sorted: Array = view.you.deck_cards.duplicate()
	sorted.sort()
	check(view.you.deck_cards == sorted and view.you.deck_cards.size() == pl.deck.size() and not e.get_view(1).opponent.has("deck_cards"), "own deck contents, sorted; never the opponent's")

	# Drawing from an empty deck loses.
	e = _game()
	pl = e.state.players[0]
	pl.board[0] = _creature("lighturn", ["light_berry", "light_berry"])
	pl.deck = []
	check(_use(e, 0, 0).ok and e.is_over() and e.state.winner == 1, "drawing with an empty deck loses")

	# Lightium: Flare = Plunder 3 then Draw 1.
	e = _game()
	pl = e.state.players[0]
	opp = e.state.players[1]
	pl.board[0] = _creature("lightium", ["light_berry", "light_berry", "super_berry", "super_berry"])
	var opp_deck: int = opp.deck.size()
	check(_use(e, 0, 1).ok and opp.deck.size() == opp_deck - 3 and pl.hand.size() == 1, "Flare plunders 3 and draws 1")

	# Lanturn puts a discard card on top; Lighttable searches the deck.
	e = _game()
	pl = e.state.players[0]
	pl.board[0] = _creature("lanturn", ["light_berry", "light_berry"])
	pl.board[1] = _creature("lighttable", ["super_berry", "super_berry"])
	pl.discard = ["removal", "gather"]
	check(not _use(e, 0, 0, {"card": "lightor"}).ok, "Relight needs a card from the discard")
	check(_use(e, 0, 0, {"card": "removal"}).ok and pl.deck[0] == "removal" and pl.discard == ["gather"], "Relight puts it on top")
	check(not _use(e, 1, 0, {"card": "lightling_not_here"}).ok, "Search needs a card that is in the deck")
	var target: String = pl.deck.back()
	var count_before: int = pl.deck.size()
	check(_use(e, 1, 0, {"card": target}).ok and pl.deck[0] == target and pl.deck.size() == count_before, "Search puts a deck card on top")

	# Lightning: two different abilities per creature, still at most 2 abilities in total.
	e = _game()
	pl = e.state.players[0]
	pl.board[0] = _creature("lightning", ["super_berry", "light_berry", "light_berry"])
	check(_use(e, 0, 1).ok, "first ability")
	check(not _use(e, 0, 1).ok, "not the same ability twice")
	check(_use(e, 0, 2).ok, "a second, different ability on the same creature")
	check(not _use(e, 0, 1).ok, "and no more than two abilities in a turn")
	e = _game()
	pl = e.state.players[0]
	pl.board[0] = _creature("lightning", ["light_berry", "light_berry"])  # no Super Berry: the Active is off
	check(_use(e, 0, 1).ok and not _use(e, 0, 2).ok, "without the Active a creature uses one ability")

	# Lightor: every draw plunders 1; Overload draws 4 then plunders per card in hand.
	e = _game()
	pl = e.state.players[0]
	opp = e.state.players[1]
	pl.board[0] = _creature("lightor", ["super_berry", "super_berry", "super_berry"])
	pl.hand = ["gather", "light_berry"]
	pl.hand.append("light_berry")
	opp_deck = opp.deck.size()
	var res := _use(e, 0, 1)
	check(res.ok and pl.hand.size() == 7 and opp.deck.size() == opp_deck - 4 - 7, "Overload: 4 draws plunder 4, then Plunder 1 per card in hand (7): %d" % (opp_deck - opp.deck.size()))
	e = _game()
	pl = e.state.players[0]
	opp = e.state.players[1]
	pl.board[0] = _creature("lightor", ["super_berry"])
	pl.hand = ["gather"]
	pl.discard = []
	opp_deck = opp.deck.size()
	res = e.submit(0, {"type": "play_spell", "hand": 0, "payment": [], "params": {"player": 0}})
	check(not res.ok, "Gather must be paid for")
	pl.board[1] = _creature("lightling", ["super_berry", "light_berry"])
	res = e.submit(0, {"type": "play_spell", "hand": 0, "payment": [{"src": "attached", "slot": 1, "index": 0}, {"src": "attached", "slot": 1, "index": 1}], "params": {"player": 0}})
	check(res.ok and pl.hand.size() == 2 and opp.deck.size() == opp_deck - 2, "Gather draws 2 and Lightor plunders 1 per draw")
	# Gather on the opponent: they draw, and your Lightor does not trigger.
	e = _game()
	pl = e.state.players[0]
	opp = e.state.players[1]
	pl.board[0] = _creature("lightor", ["super_berry"])
	pl.board[1] = _creature("lightling", ["super_berry", "light_berry"])
	pl.hand = ["gather"]
	opp_deck = opp.deck.size()
	res = e.submit(0, {"type": "play_spell", "hand": 0, "payment": [{"src": "attached", "slot": 1, "index": 0}, {"src": "attached", "slot": 1, "index": 1}], "params": {"player": 1}})
	check(res.ok and opp.hand.size() == 2 and opp.deck.size() == opp_deck - 2, "Gather on the opponent: they draw 2, no plunder")
	# The turn's draw triggers Lightor too.
	e = _game()
	pl = e.state.players[0]
	opp = e.state.players[1]
	opp.board[0] = _creature("lightor", ["super_berry"])
	opp_deck = pl.deck.size()
	e.submit(0, {"type": "end_turn"})
	check(pl.deck.size() == opp_deck - 1, "the opponent's turn draw plundered me for 1")

	# Lightium protects creatures with a Super Berry from the opponent's targeting only.
	e = _game()
	pl = e.state.players[0]
	opp = e.state.players[1]
	opp.board[0] = _creature("lightium", ["super_berry", "super_berry"])
	opp.board[1] = _creature("lightling", ["super_berry"])
	opp.board[2] = _creature("lightling", ["light_berry"])
	pl.board[0] = _creature("water_constrictor", ["water_berry"])
	pl.hand = ["removal"]
	var pay := [{"src": "attached", "slot": 0, "index": 0}]
	pl.board[0].berries = ["water_berry", "water_berry", "water_berry"]
	pl.board[0].exhausted = [false, false, false]
	pay = [{"src": "attached", "slot": 0, "index": 0}, {"src": "attached", "slot": 0, "index": 1}, {"src": "attached", "slot": 0, "index": 2}]
	check(not e.submit(0, {"type": "play_spell", "hand": 0, "payment": pay, "params": {"target": {"player": 1, "slot": 1}}}).ok, "Removal can't target a protected creature")
	check(not _use(e, 0, 0, {"targets": [{"player": 1, "slot": 0}]}).ok, "nor Stun")
	check(_use(e, 0, 0, {"targets": [{"player": 1, "slot": 2}]}).ok, "an unprotected creature can be stunned")
	opp.board[0].berries = ["light_berry", "light_berry"]  # the Active needs 2 Super Berries
	pl.board[0].ability_used_turn = -1
	pl.abilities_used = 0
	check(e.submit(0, {"type": "play_spell", "hand": 0, "payment": pay, "params": {"target": {"player": 1, "slot": 1}}}).ok, "with the Active off the creature can be removed")
	print("light_test failures=%d" % fails)
	quit(fails)
