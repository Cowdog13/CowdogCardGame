extends SceneTree
## The Nature Exile deck's effects, played directly on the engine.
##   godot --headless -s tests/nature_test.gd
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


## A game in the main phase on turn 5, seat 0 to act, with an empty hand and empty piles.
func _game() -> GameEngine:
	var e := GameEngine.new()
	e.setup(["nature_exile", "nature_exile"], 3)
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.turn = 5
	e.state.active = 0
	var pl: Dictionary = e.state.players[0]
	pl.hand = []
	pl.discard = []
	pl.exile = []
	pl.board = [null, null, null, null, null]
	return e


func _use(e: GameEngine, slot: int, ability: int, params := {}) -> Dictionary:
	return e.submit(0, {"type": "use_ability", "slot": slot, "ability": ability, "params": params})


func _init() -> void:
	var deck := CardDB.build_deck_list("nature_exile")
	check(deck.size() == 50 and deck.count("super_berry") == 7 and deck.count("nature_berry") == 16, "deck is 50 cards with 7 Super and 16 Nature Berries")

	# Leaflet: Recycle 2 needs cards in the discard and puts them on the bottom, in the chosen order.
	var e := _game()
	var pl: Dictionary = e.state.players[0]
	pl.board[0] = _creature("leaflet", ["nature_berry", "nature_berry"])
	check(not _use(e, 0, 0).ok, "Recycle with an empty discard is refused")
	pl.discard = ["leafer", "removal", "nature_berry"]
	check(_use(e, 0, 0).ok and int(e.state.pending.recycle) == 2, "Recycle 2 asks for two cards")
	check(e.submit(0, {"type": "recycle", "cards": [1, 0]}).ok and pl.deck.slice(-2) == ["removal", "leafer"] and pl.discard == ["nature_berry"], "recycled in order to the bottom")

	# Leafren: Mulch exiles an attached Super Berry (only a Super Berry) and recycles 6 (as many as there are).
	e = _game()
	pl = e.state.players[0]
	pl.board[0] = _creature("leafren", ["nature_berry", "super_berry"])
	pl.discard = ["leafer", "removal", "nature_berry", "trash"]
	check(not _use(e, 0, 2, {"berry": 0}).ok, "Mulch can't exile a Nature Berry")
	check(not _use(e, 0, 2).ok, "Mulch needs a berry choice")
	check(_use(e, 0, 2, {"berry": 1}).ok and pl.exile == ["super_berry"] and pl.board[0].berries == ["nature_berry"], "Mulch exiles the Super Berry")
	check(int(e.state.pending.recycle) == 4, "Recycle 6 with 4 cards in the discard recycles 4")

	# Spore Spreader: Plunder 1 per card in your exile.
	e = _game()
	pl = e.state.players[0]
	pl.board[0] = _creature("spore_spreader", ["super_berry", "super_berry"])
	check(not _use(e, 0, 1).ok, "Spore Cloud with an empty exile is refused")
	pl.exile = ["removal", "leafer", "trash"]
	var before: int = e.state.players[1].deck.size()
	check(_use(e, 0, 1).ok and e.state.players[1].deck.size() == before - 3, "Plunder 3 for 3 cards in exile")

	# Moosh: exile one attached Nature Berry, then Plunder 3.
	e = _game()
	pl = e.state.players[0]
	pl.board[0] = _creature("moosh", ["nature_berry", "nature_berry", "super_berry"])
	before = e.state.players[1].deck.size()
	check(_use(e, 0, 0, {"berry": 0}).ok and pl.exile == ["nature_berry"] and pl.board[0].berries.size() == 2, "Moosh exiles one berry")
	check(e.state.players[1].deck.size() <= before - 3, "and plunders 3")

	# Spore Muncher: pay for Removal from the discard (3 berries) and play it on an enemy creature; it is exiled.
	e = _game()
	pl = e.state.players[0]
	var opp: Dictionary = e.state.players[1]
	opp.board[0] = _creature("leafer", [])
	pl.board[0] = _creature("spore_muncher", ["super_berry", "super_berry", "super_berry"])
	pl.discard = ["leafer", "removal", "nature_berry", "nature_berry", "nature_berry"]
	var target := {"spell": 1, "spell_params": {"target": {"player": 1, "slot": 0}}}
	check(not _use(e, 0, 1, {"spell": 0}).ok, "Decompose needs a spell")
	check(not _use(e, 0, 1, target).ok, "Removal must be paid for")
	target["payment"] = [{"src": "discard", "index": 2}, {"src": "discard", "index": 3}]
	check(not _use(e, 0, 1, target).ok, "two berries don't pay for Removal")
	target["payment"] = [{"src": "discard", "index": 2}, {"src": "discard", "index": 3}, {"src": "discard", "index": 4}]
	var res := _use(e, 0, 1, target)
	check(res.ok and pl.exile.count("removal") == 1 and pl.exile.size() == 4 and pl.discard == ["leafer"] and opp.board[0] == null, "Removal paid for, replayed and exiled: %s / %s" % [pl.discard, pl.exile])

	# Trash from the hand: pay with discard berries, exile three other cards; a card can't do both.
	e = _game()
	pl = e.state.players[0]
	pl.board[0] = _creature("leafer", [])
	pl.hand = ["trash"]
	pl.discard = ["nature_berry", "nature_berry", "removal", "leafer", "leaflet"]
	var pay := [{"src": "discard", "index": 0}, {"src": "discard", "index": 1}]
	check(not e.submit(0, {"type": "play_spell", "hand": 0, "payment": pay, "params": {"cards": ["removal", "leafer"]}}).ok, "Trash needs exactly 3 cards")
	check(not e.submit(0, {"type": "play_spell", "hand": 0, "payment": pay, "params": {"cards": ["nature_berry", "leafer", "leaflet"]}}).ok, "a berry that pays can't also be exiled")
	res = e.submit(0, {"type": "play_spell", "hand": 0, "payment": pay, "params": {"cards": ["removal", "leafer", "leaflet"]}})
	check(res.ok and pl.exile.size() == 5 and pl.discard == ["trash"], "Trash exiled three cards and the two berries that paid")
	print("nature_test failures=%d" % fails)
	quit(fails)
