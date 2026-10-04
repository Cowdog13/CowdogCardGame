extends SceneTree
## Every Plunder ability must hit the opponent's deck (and only that); every Pillage ability
## must hit the user's own deck.   godot --headless -s tests/targets_test.gd

func _init() -> void:
	var fails := 0
	var checked := 0
	for card_id in ["firespore", "firespitter", "fireking", "firepup", "firewolf", "fire_famine",
			"water_spirit", "water_sprite", "water_ruler", "water_constrictor", "water_binder", "water_crash"]:
		var card := CardDB.card(card_id)
		for ai in card.abilities.size():
			var ab: Dictionary = card.abilities[ai]
			if ab.get("active", false):
				continue
			var kinds: Array = ab.effects.map(func(x): return x.type)
			if not (kinds.has("plunder") or kinds.has("pillage")):
				continue
			for user in 2:
				var e := GameEngine.new()
				e.setup(["scorching_fire", "crashing_wave"], 7)
				for p in 2:
					e.submit(p, {"type": "mulligan", "cards": []})
				e.state.turn = 5
				e.state.active = user
				var me: Dictionary = e.state.players[user]
				var them: Dictionary = e.state.players[1 - user]
				var berries: Array = []
				var cost: Dictionary = ab.cost
				for i in 6:
					berries.append("super_berry" if cost.element == "super" else CardDB.card(card.id).element + "_berry")
				var cards: Array = [card_id]
				# Build the evolution chain so the creature is a legal board state.
				var cur: String = card_id
				while CardDB.card(cur).evolves_from != "":
					cur = CardDB.card(cur).evolves_from
					cards.push_front(cur)
				me.board[0] = {"cards": cards, "berries": berries, "exhausted": berries.map(func(_b): return false), "stun_until": -1, "ability_used_turn": -1}
				# Non-berry, non-super filler so no placement prompts interfere.
				me.deck = []
				them.deck = []
				for i in 12:
					me.deck.append("removal")
					them.deck.append("disable")
				var my_before: int = me.deck.size()
				var their_before: int = them.deck.size()
				var res := e.submit(user, {"type": "use_ability", "slot": 0, "ability": ai, "params": {}})
				if not res.ok:
					print("FAIL %s ability %d: %s" % [card_id, ai, res.error])
					fails += 1
					continue
				var my_loss: int = my_before - me.deck.size()
				var their_loss: int = their_before - them.deck.size()
				checked += 1
				if kinds.has("plunder") and (their_loss <= 0 or my_loss != 0):
					print("FAIL %s ability %d (%s) as seat %d: plunder hit own=%d opponent=%d" % [card_id, ai, ab.name, user, my_loss, their_loss])
					fails += 1
				if kinds.has("pillage") and (my_loss <= 0 or their_loss != 0):
					print("FAIL %s ability %d (%s) as seat %d: pillage hit own=%d opponent=%d" % [card_id, ai, ab.name, user, my_loss, their_loss])
					fails += 1
	print("targets_test checked=%d failures=%d" % [checked, fails])
	quit(1 if fails > 0 else 0)
