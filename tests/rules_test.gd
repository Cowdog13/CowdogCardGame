extends SceneTree
## Targeted rule checks.   godot --headless -s tests/rules_test.gd

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: " + msg)

func _init() -> void:
	var e := GameEngine.new()
	e.setup(["scorching_fire", "crashing_wave"], 1)
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	var a: int = e.state.active
	var pl: Dictionary = e.state.players[a]
	# First turn: no abilities.
	pl.board[0] = {"cards": ["firespore"], "berries": ["fire_berry"], "exhausted": [false], "stun_until": -1}
	check(not e.submit(a, {"type": "use_ability", "slot": 0, "ability": 0}).ok, "abilities locked on turn 1")
	check(Rules.BOARD_SLOTS == 5, "5 slots")
	# Attach from discard enters exhausted, uses the berry attachment.
	pl.discard = ["fire_berry"]
	check(e.submit(a, {"type": "attach_berry", "from": "discard", "discard": 0, "slot": 0}).ok, "attach from discard")
	check(pl.board[0].exhausted == [false, true], "enters exhausted")
	check(not e.submit(a, {"type": "attach_berry", "from": "discard", "discard": 0, "slot": 0}).ok, "only one berry per turn")
	# Spell payment: exhausted goes to exile, upright to discard.
	pl.hand = ["removal"]
	pl.board[0].berries = ["fire_berry", "fire_berry", "super_berry"]
	pl.board[0].exhausted = [false, true, false]
	var pay := [{"src": "attached", "slot": 0, "index": 0}, {"src": "attached", "slot": 0, "index": 1}, {"src": "attached", "slot": 0, "index": 2}]
	var opp: int = 1 - a
	e.state.players[opp].board[1] = {"cards": ["water_spirit"], "berries": ["water_berry"], "exhausted": [true], "stun_until": -1}
	var exile_before: int = pl.exile.size()
	var r := e.submit(a, {"type": "play_spell", "hand": 0, "payment": pay, "params": {"target": {"player": opp, "slot": 1}}})
	check(r.ok, "removal castable: %s" % r.get("error", ""))
	check(pl.exile.size() == exile_before + 1 and pl.exile.back() == "fire_berry", "exhausted payment exiled")
	check(pl.discard.count("fire_berry") == 1 and pl.discard.has("super_berry") and pl.discard.has("removal"), "upright payment discarded")
	check(e.state.players[opp].exile.has("water_berry") and e.state.players[opp].board[1] == null, "exhausted berries exiled when creature destroyed")
	# Reinforce ignores the once-per-turn creature play.
	pl.creature_played = true
	pl.hand = ["reinforce"]
	pl.discard = ["firepup", "fire_berry"]
	pl.pillaged = ["firepup"]
	pl.board[0] = {"cards": ["firespore"], "berries": ["fire_berry", "fire_berry"], "exhausted": [false, false], "stun_until": -1}
	pay = [{"src": "discard", "index": 1}, {"src": "attached", "slot": 0, "index": 0}]
	r = e.submit(a, {"type": "play_spell", "hand": 0, "payment": pay, "params": {"card_id": "firepup", "slot": 2}})
	check(r.ok, "reinforce despite creature already played: %s" % r.get("error", ""))
	check(pl.board[2] != null and pl.board[2].cards == ["firepup"], "reinforced creature in play")
	print("rules_test failures=%d" % fails)
	quit(1 if fails > 0 else 0)
