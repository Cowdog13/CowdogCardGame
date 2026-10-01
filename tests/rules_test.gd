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
	# One ability per creature per turn (turn 3+ so abilities are unlocked).
	e.state.turn = 5
	e.state.active = a
	pl.abilities_used = 0
	pl.board[3] = {"cards": ["firespore"], "berries": ["fire_berry", "fire_berry"], "exhausted": [false, false], "stun_until": -1}
	check(e.submit(a, {"type": "use_ability", "slot": 3, "ability": 0}).ok, "first ability use")
	check(not e.submit(a, {"type": "use_ability", "slot": 3, "ability": 0}).ok, "second use by same creature rejected")
	# Evolving removes a stun.
	pl.board[3].stun_until = 99
	pl.hand = ["firespitter"]
	pl.creature_played = false
	check(e.submit(a, {"type": "play_creature", "hand": 0, "slot": 3}).ok, "evolve")
	check(not Rules.is_stunned(pl.board[3], e.state.turn), "evolving cleared the stun")
	# Revealed Super Berries are placed by the player's choice (plunder and pillage).
	e.state.players[opp].deck = ["super_berry", "fire_berry"]
	e.state.players[opp].board[0] = null
	pl.board[3].berries = ["fire_berry", "fire_berry"]
	pl.board[3].exhausted = [false, false]
	pl.board[4] = {"cards": ["firespore"], "berries": [], "exhausted": [], "stun_until": -1, "ability_used_turn": -1}
	pl.board[4].ability_used_turn = -1
	pl.board[3].ability_used_turn = -1
	pl.abilities_used = 0
	check(e.submit(a, {"type": "use_ability", "slot": 3, "ability": 0}).ok, "plunder")
	check(e.awaiting() == [a] and not e.state.pending.is_empty(), "pending super berry placement")
	check(not e.submit(a, {"type": "end_turn"}).ok, "must place the berry first")
	check(e.submit(a, {"type": "place_berry", "slot": 4}).ok, "place super berry")
	check(pl.board[4].berries == ["super_berry"] and e.state.pending.is_empty(), "berry on chosen creature")
	pl.deck = ["super_berry", "fire_berry", "fire_berry"]
	pl.board[0] = {"cards": ["firepup"], "berries": ["fire_berry", "fire_berry"], "exhausted": [false, false], "stun_until": -1, "ability_used_turn": -1}
	check(e.submit(a, {"type": "use_ability", "slot": 0, "ability": 0}).ok, "pillage")
	check(not e.state.pending.is_empty() and e.state.pending.player == a, "pillaged super berry placed by choice")
	# Fire Famine + Firewolf: berries attach by choice, others are discarded, recycle is chosen.
	e.state.pending = {}
	pl.discard = []
	pl.board = [null, null, null, null, null]
	pl.board[0] = {"cards": ["firepup"], "berries": ["fire_berry", "fire_berry"], "exhausted": [false, false], "stun_until": -1, "ability_used_turn": -1}
	pl.board[1] = {"cards": ["firewolf"], "berries": ["super_berry", "super_berry"], "exhausted": [false, false], "stun_until": -1, "ability_used_turn": -1}
	pl.board[2] = {"cards": ["fire_famine"], "berries": ["super_berry"], "exhausted": [false], "stun_until": -1, "ability_used_turn": -1}
	pl.deck = ["fire_berry", "firespore", "super_berry", "removal", "fire_berry"]
	pl.abilities_used = 0
	pl.board[0].ability_used_turn = -1
	var before: int = pl.board[2].berries.size()
	check(e.submit(a, {"type": "use_ability", "slot": 0, "ability": 0}).ok, "pillage 2 with both actives")
	# Pillage 2 reveals fire_berry, firespore: berry is offered, firespore goes to discard, 2 recycles (wolf).
	check(e.state.pending.berries == ["fire_berry"], "regular berry offered for placement")
	check(pl.discard == ["firespore"], "non-berry goes to discard")
	check(not e.submit(a, {"type": "recycle", "cards": [0]}).ok, "place the berry before recycling")
	check(e.submit(a, {"type": "place_berry", "slot": 2}).ok, "place berry on a creature of choice")
	check(pl.board[2].berries.size() == before + 1, "berry attached to chosen creature")
	check(int(e.state.pending.recycle) == 1, "recycle count capped by discard size")
	check(not e.submit(a, {"type": "recycle", "cards": [0, 0]}).ok, "wrong number of recycle picks rejected")
	check(e.submit(a, {"type": "recycle", "cards": [0]}).ok and e.state.pending.is_empty(), "recycle chosen")
	check(pl.deck.back() == "firespore" and pl.discard.is_empty(), "recycled card went to the bottom")
	# Firewolf alone: regular berries go to the discard, recycle is still chosen.
	pl.board[2] = null
	pl.deck = ["fire_berry", "removal", "fire_berry", "fire_berry"]
	pl.board[0].ability_used_turn = -1
	pl.abilities_used = 0
	check(e.submit(a, {"type": "use_ability", "slot": 0, "ability": 0}).ok, "pillage with wolf only")
	check(pl.discard == ["fire_berry", "removal"] and e.state.pending.berries.is_empty() and int(e.state.pending.recycle) == 2, "wolf only: berry discarded, two recycles pending")
	e.submit(a, {"type": "recycle", "cards": [1, 0]})
	check(e.state.pending.is_empty() and pl.deck.slice(-2) == ["removal", "fire_berry"], "recycle order respected")
	# Firewolf + Famine, every pillaged card is a berry that gets attached: nothing to recycle.
	pl.board[2] = {"cards": ["fire_famine"], "berries": ["super_berry"], "exhausted": [false], "stun_until": -1, "ability_used_turn": -1}
	pl.board[1] = {"cards": ["firewolf"], "berries": ["super_berry", "super_berry"], "exhausted": [false, false], "stun_until": -1, "ability_used_turn": -1}
	pl.discard = ["removal", "firespore"]
	pl.deck = ["fire_berry", "fire_berry", "removal"]
	pl.board[0].ability_used_turn = -1
	pl.abilities_used = 0
	e.submit(a, {"type": "use_ability", "slot": 0, "ability": 0})
	check(e.state.pending.berries.size() == 2 and int(e.state.pending.recycle) == 0, "attached berries do not count toward recycling")
	e.submit(a, {"type": "place_berry", "slot": 0})
	e.submit(a, {"type": "place_berry", "slot": 0})
	check(e.state.pending.is_empty(), "no recycle prompt when no card was discarded")
	# Two Firewolves don't stack.
	pl.board[2] = {"cards": ["firewolf"], "berries": ["super_berry", "super_berry"], "exhausted": [false, false], "stun_until": -1, "ability_used_turn": -1}
	pl.discard = ["removal", "firespore", "fire_berry", "fire_berry"]
	pl.deck = ["removal", "firespore", "fire_berry"]
	pl.board[0].ability_used_turn = -1
	pl.abilities_used = 0
	e.submit(a, {"type": "use_ability", "slot": 0, "ability": 0})
	check(int(e.state.pending.recycle) == 2, "two Firewolves recycle only as many as were discarded")
	e.submit(a, {"type": "recycle", "cards": [0, 1]})
	pl.board[2] = null
	# Fire Famine alone: all berries are attached by choice; no recycle.
	pl.board[1] = null
	pl.board[2] = {"cards": ["fire_famine"], "berries": ["super_berry", "fire_berry"], "exhausted": [false, false], "stun_until": -1, "ability_used_turn": -1}
	pl.deck = ["fire_berry", "removal", "fire_berry"]
	pl.board[0].ability_used_turn = -1
	pl.abilities_used = 0
	check(e.submit(a, {"type": "use_ability", "slot": 0, "ability": 0}).ok, "pillage with famine only")
	check(e.state.pending.berries == ["fire_berry"] and int(e.state.pending.recycle) == 0, "famine only: berry placed by choice, no recycle")
	e.submit(a, {"type": "place_berry", "slot": 0})
	print("rules_test failures=%d" % fails)
	quit(1 if fails > 0 else 0)
