extends SceneTree
## The four deck leaders (the starting creatures).   godot --headless -s tests/leaders_test.gd
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


func _game(deck: String) -> GameEngine:
	var e := GameEngine.new()
	e.setup([deck, "light"], 4)
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.turn = 5
	e.state.active = 0
	var pl: Dictionary = e.state.players[0]
	pl.hand = []
	pl.discard = []
	pl.exile = []
	pl.board = [null, null, null, null, null]
	e.state.players[1].board = [null, null, null, null, null]
	return e


func _use(e: GameEngine, params := {}) -> Dictionary:
	return e.submit(0, {"type": "use_ability", "slot": 0, "ability": 0, "params": params})


func _init() -> void:
	for pair in [["scorching_fire", "fire_lord"], ["crashing_wave", "water_essence"], ["nature_exile", "mother_nature"], ["light", "sun_god"]]:
		check(CardDB.deck_starter(pair[0]) == pair[1], "%s starts with %s" % pair)
		check(not CardDB.build_deck_list(pair[0]).has(pair[1]), "%s is not part of the 50 cards" % pair[1])

	# Fire Lord: Plunder 1 per attached berry (2 Super Berries needed).
	var e := _game("scorching_fire")
	var pl: Dictionary = e.state.players[0]
	var opp: Dictionary = e.state.players[1]
	pl.board[0] = _creature("fire_lord", ["super_berry", "super_berry", "fire_berry", "fire_berry"])
	var before: int = opp.deck.size()
	check(_use(e).ok and opp.deck.size() == before - 4, "Fire Lord plunders 4 with 4 berries")
	e = _game("scorching_fire")
	e.state.players[0].board[0] = _creature("fire_lord", ["super_berry", "fire_berry", "fire_berry"])
	check(not _use(e).ok, "Fire Lord needs 2 Super Berries")

	# Water Essence: remove the stun from an ENEMY creature, then Plunder (berries x creatures).
	e = _game("crashing_wave")
	pl = e.state.players[0]
	opp = e.state.players[1]
	pl.board[0] = _creature("water_essence", ["super_berry", "super_berry", "water_berry"])
	pl.board[1] = _creature("water_spirit", [])
	pl.board[2] = _creature("water_spirit", [])
	opp.board[0] = _creature("lightling", [])
	check(not _use(e, {"target": {"player": 1, "slot": 0}}).ok, "needs a stunned creature")
	opp.board[0].stun_until = 6
	check(not _use(e, {"target": {"player": 0, "slot": 0}}).ok, "it can't be one of your own creatures")
	before = opp.deck.size()
	check(_use(e, {"target": {"player": 1, "slot": 0}}).ok and opp.board[0].stun_until == -1, "the enemy's stun is removed")
	check(opp.deck.size() == before - 9, "and it plunders 3 berries x 3 creatures: %d" % (before - opp.deck.size()))

	# Mother Nature: recycle X cards from exile (X = attached berries) to the bottom of the deck.
	e = _game("nature_exile")
	pl = e.state.players[0]
	pl.board[0] = _creature("mother_nature", ["super_berry", "super_berry", "nature_berry"])
	check(not _use(e).ok, "an empty exile can't be recycled")
	pl.exile = ["trash", "removal", "leafer", "leaflet", "leafren"]
	check(_use(e).ok and int(e.state.pending.recycle) == 3 and e.state.pending.source == "exile", "asks for 3 cards from the exile")
	check(not e.submit(0, {"type": "recycle", "cards": [0, 1]}).ok, "exactly 3")
	var deck_size: int = pl.deck.size()
	check(e.submit(0, {"type": "recycle", "cards": [4, 0, 2]}).ok and pl.deck.slice(-3) == ["leafren", "trash", "leafer"] and pl.exile == ["removal", "leaflet"] and pl.deck.size() == deck_size + 3, "they go to the bottom in the chosen order")

	# Sun God: draw X, then put X cards from the hand on the bottom.
	e = _game("light")
	pl = e.state.players[0]
	pl.board[0] = _creature("sun_god", ["super_berry", "super_berry", "light_berry"])
	pl.hand = ["removal"]
	pl.deck = ["gather", "lightling", "lighturn", "lightium", "lanturn"]
	check(_use(e).ok and pl.hand == ["removal", "gather", "lightling", "lighturn"], "draws 3: %s" % [pl.hand])
	check(int(e.state.pending.recycle) == 3 and e.state.pending.source == "hand", "then 3 cards from the hand go back")
	check(e.submit(0, {"type": "recycle", "cards": [0, 3, 1]}).ok and pl.hand == ["lightling"] and pl.deck.slice(-3) == ["removal", "lighturn", "gather"], "to the bottom in the chosen order: %s / %s" % [pl.hand, pl.deck])
	# Leaders can't be targeted by anything (Stun, Removal, Berry Trade ...), whoever controls them.
	e = _game("crashing_wave")
	pl = e.state.players[0]
	opp = e.state.players[1]
	pl.board[0] = _creature("water_essence", ["super_berry", "super_berry"])
	pl.board[1] = _creature("water_constrictor", ["water_berry"])
	pl.hand = ["removal"]
	check(not e.submit(0, {"type": "use_ability", "slot": 1, "ability": 0, "params": {"targets": [{"player": 1, "slot": 0}]}}).ok, "Stun can't target the enemy leader")
	check(not e.submit(0, {"type": "use_ability", "slot": 1, "ability": 0, "params": {"targets": [{"player": 0, "slot": 0}]}}).ok, "nor your own")
	check(not e.submit(0, {"type": "play_spell", "hand": 0, "payment": [{"src": "attached", "slot": 0, "index": 0}, {"src": "attached", "slot": 0, "index": 1}, {"src": "attached", "slot": 1, "index": 0}], "params": {"target": {"player": 1, "slot": 0}}}).ok, "Removal can't target a leader")

	# Fireking's Twin Flame (3 Super Berries): the next Plunder ability this turn is doubled, once.
	e = _game("scorching_fire")
	pl = e.state.players[0]
	opp = e.state.players[1]
	pl.board[0] = _creature("fireking", ["super_berry", "super_berry", "super_berry"])
	pl.board[1] = _creature("firespore", ["fire_berry"])
	pl.board[2] = _creature("firespore", ["fire_berry"])
	check(e.submit(0, {"type": "use_ability", "slot": 0, "ability": 1, "params": {}}).ok and e.get_view(0).you.plunder_doubled, "Twin Flame sets up the bonus")
	before = opp.deck.size()
	check(e.submit(0, {"type": "use_ability", "slot": 1, "ability": 0, "params": {}}).ok and opp.deck.size() == before - 4, "Plunder 2 plunders 4")
	check(not e.get_view(0).you.plunder_doubled, "the bonus is used up")
	e.state.turn = 7
	e.state.active = 0
	pl.abilities_used = 0
	for c in pl.board:
		if c != null:
			c.ability_used_turn = -1
	pl.board[0].berries = ["super_berry", "super_berry", "super_berry"]
	pl.board[0].exhausted = [false, false, false]
	e.submit(0, {"type": "use_ability", "slot": 0, "ability": 1, "params": {}})
	e.submit(0, {"type": "end_turn"})
	e.submit(1, {"type": "end_turn"})
	check(not e.get_view(0).you.plunder_doubled, "an unused bonus doesn't carry over to the next turn")
	print("leaders_test failures=%d" % fails)
	quit(fails)
