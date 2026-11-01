extends SceneTree
## Backing out of an ability that is only waiting for its recycle choice.   godot --headless -s tests/cancel_test.gd
func _init() -> void:
	var fails := 0
	var e := GameEngine.new()
	e.setup(["nature_exile", "scorching_fire"], 11)
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.turn = 5
	e.state.active = 0
	var me: Dictionary = e.state.players[0]
	var berries := ["nature_berry", "nature_berry"]
	me.board[0] = {"cards": ["leafer", "leaflet"], "berries": berries.duplicate(), "exhausted": [false, false], "stun_until": -1, "ability_used_turn": -1}
	me.discard = ["removal", "gather", "leafer"]
	var before: String = JSON.stringify(e.state)
	var res := e.submit(0, {"type": "use_ability", "slot": 0, "ability": 0, "params": {}})
	if not res.ok or int(e.state.pending.get("recycle", 0)) != 2 or not e.state.pending.get("cancelable", false):
		fails += 1
		print("Recycle 2 should wait for a cancelable choice: ", res, e.state.pending)
	if e.get_view(0).pending.get("cancelable", false) != true:
		fails += 1
		print("the player's view should say the choice is cancelable")
	if e.submit(1, {"type": "cancel_pending"}).ok:
		fails += 1
		print("the opponent must not be able to cancel")
	var c := e.submit(0, {"type": "cancel_pending"})
	if not c.ok or not e.state.pending.is_empty():
		fails += 1
		print("cancel should work: ", c)
	var after: Dictionary = JSON.parse_string(JSON.stringify(e.state))
	var was: Dictionary = JSON.parse_string(before)
	for k in ["players", "turn", "active", "phase"]:
		if JSON.stringify(after[k]) != JSON.stringify(was[k]):
			fails += 1
			print("state differs after cancel in ", k)
	if e.submit(0, {"type": "cancel_pending"}).ok:
		fails += 1
		print("nothing left to cancel")
	# The ability can be used again and finished; afterwards there is no cancel.
	e.submit(0, {"type": "use_ability", "slot": 0, "ability": 0, "params": {}})
	var done := e.submit(0, {"type": "recycle", "cards": [0, 1]})
	if not done.ok or e.submit(0, {"type": "cancel_pending"}).ok or me.deck.size() < 2:
		fails += 1
		print("after the choice is made the ability can't be taken back")
	# Pillage's recycle is not cancelable.
	var f := GameEngine.new()
	f.setup(["scorching_fire", "crashing_wave"], 7)
	for p in 2:
		f.submit(p, {"type": "mulligan", "cards": []})
	f.state.turn = 5
	f.state.active = 0
	var fm: Dictionary = f.state.players[0]
	fm.board[0] = {"cards": ["firespore"], "berries": ["fire_berry", "fire_berry", "fire_berry", "fire_berry"], "exhausted": [false, false, false, false], "stun_until": -1, "ability_used_turn": -1}
	fm.discard = ["removal"]
	for ai in CardDB.card("firespore").abilities.size():
		var kinds: Array = CardDB.card("firespore").abilities[ai].effects.map(func(x): return x.type)
		if kinds.has("pillage"):
			var r := f.submit(0, {"type": "use_ability", "slot": 0, "ability": ai, "params": {}})
			if r.ok and not f.state.pending.is_empty() and f.state.pending.get("cancelable", false):
				fails += 1
				print("a Pillage recycle must not be cancelable")
	print("cancel_test failures=%d" % fails)
	quit(fails)
