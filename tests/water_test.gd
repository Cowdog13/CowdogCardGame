extends SceneTree
## Water Ruler's Rearrange and Water Essence's Berry Trade.   godot --headless -s tests/water_test.gd
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)


func _creature(id: String, berries: Array, exhausted := []) -> Dictionary:
	var ex: Array = []
	for i in berries.size():
		ex.append(i in exhausted)
	return {"cards": [id], "berries": berries, "exhausted": ex, "stun_until": -1, "ability_used_turn": -1}


func _game() -> GameEngine:
	var e := GameEngine.new()
	e.setup(["crashing_wave", "light"], 6)
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.turn = 7
	e.state.active = 0
	for p in 2:
		e.state.players[p].board = [null, null, null, null, null]
		e.state.players[p].discard = []
	return e


func _init() -> void:
	var data := CardDB.card("water_ruler")
	check(data.abilities.size() == 2 and data.abilities[0].name == "Rearrange" and not JSON.stringify(data).contains("berry_trade"), "the Ruler no longer has Berry Trade")
	check(JSON.stringify(CardDB.card("water_essence")).contains("berry_trade"), "Water Essence has Berry Trade")

	# Rearrange: every berry gets a new creature; exhausted berries stay exhausted; then Plunder X = the most on one creature.
	var e := _game()
	var pl: Dictionary = e.state.players[0]
	var opp: Dictionary = e.state.players[1]
	pl.board[0] = _creature("water_ruler", ["super_berry", "super_berry"])
	pl.board[1] = _creature("water_spirit", ["water_berry", "water_berry", "water_berry"], [1])
	var deck_before: int = opp.deck.size()
	check(not e.submit(0, {"type": "use_ability", "slot": 0, "ability": 0, "params": {"assign": [0, 0]}}).ok, "every berry (5) must be placed")
	check(not e.submit(0, {"type": "use_ability", "slot": 0, "ability": 0, "params": {"assign": [0, 0, 0, 0, 3]}}).ok, "only onto your own creatures")
	var res := e.submit(0, {"type": "use_ability", "slot": 0, "ability": 0, "params": {"assign": [0, 0, 0, 0, 1]}})
	check(res.ok and pl.board[0].berries == ["super_berry", "super_berry", "water_berry", "water_berry"] and pl.board[1].berries == ["water_berry"], "berries moved: %s / %s" % [pl.board[0].berries, pl.board[1].berries])
	check(pl.board[0].exhausted == [false, false, false, true] and pl.board[1].exhausted == [false], "exhausted berries stay exhausted: %s" % [pl.board[0].exhausted])
	check(opp.deck.size() == deck_before - 4, "Plunder X = 4 (the most berries on one creature)")

	# Berry Trade (Water Essence): needs 1 Super Berry on it, enemy targets only, never an enemy leader.
	e = _game()
	pl = e.state.players[0]
	opp = e.state.players[1]
	pl.board[0] = _creature("water_essence", ["super_berry", "water_berry"])
	opp.board[0] = _creature("sun_god", ["super_berry", "super_berry"])
	opp.board[1] = _creature("lightling", ["light_berry", "super_berry"])
	var trade := func(target_slot: int):
		return e.submit(0, {"type": "use_ability", "slot": 0, "ability": 1, "params": {"target": {"player": 1, "slot": target_slot}, "own": [1], "theirs": [1]}})
	check(not trade.call(0).ok, "an enemy leader can't be targeted")
	check(trade.call(1).ok and pl.board[0].berries == ["super_berry"] and opp.board[1].berries == ["light_berry"], "one berry each way: %s / %s" % [pl.board[0].berries, opp.board[1].berries])
	print("water_test failures=%d" % fails)
	quit(fails)
