class_name GameEngine
extends RefCounted
## Authoritative game rules. The engine owns all state and all randomness; the only
## way to change the game is submit(player, action) with a plain Dictionary action.
## Players (UI, AI, or later a network peer) only ever see get_view(player).
##
## Actions ("type" selects the action):
##   {"type":"mulligan",     "cards":[hand indices]}            (mulligan phase; [] keeps the hand)
##   {"type":"attach_berry", "hand":i, "slot":s}           (or "from":"discard", "discard":j: berry enters exhausted)
##   {"type":"play_creature","hand":i, "slot":s}                (places tier 1 / evolves tier 2+)
##   {"type":"use_ability",  "slot":s, "ability":a, "params":{}}
##   {"type":"play_spell",   "hand":i, "payment":[...], "params":{}}
##   {"type":"swap",         "cards":[hand indices], "discard":j}  (once per turn: give N cards, take creature j; N = swaps made + 1)
##   {"type":"place_berry",  "slot":s}                        (only while state.pending has berries: where a revealed berry goes)
##   {"type":"order_recycle","order":[indices]}               (only while state.pending.ordering is set: Fire Famine's order)
##   {"type":"recycle",      "cards":[discard indices]}       (only while state.pending.recycle > 0: Firewolf's choice, in order)
##   {"type":"concede"}                                         (any time; the other player wins)
##   {"type":"end_turn"}
## Results are {"ok":true} or {"ok":false,"error":"..."}.

signal event_logged(event: Dictionary)
signal state_changed

var state: Dictionary = {}
var log: Array = []
var seed_value := 0
var rng := RandomNumberGenerator.new()


## `fixed_decks` (optional, for the tutorial): one ordered card list per player. They are used exactly as
## given (no shuffling) and player 0 goes first, so a scripted game plays out the same way every time.
func setup(deck_ids: Array, seed_val: int = -1, names: Array = [], fixed_decks: Array = []) -> void:
	if seed_val < 0:
		rng.randomize()
	else:
		rng.seed = seed_val
	seed_value = rng.seed
	log.clear()
	state = {
		"phase": "mulligan",
		"turn": 0,
		"active": -1,
		"first_player": 0 if not fixed_decks.is_empty() else rng.randi_range(0, 1),
		"winner": -1,
		"doomed": {},  # set when a Plunder could not be completed; applied once everything has resolved
		"pending": {},  # {"player": p, "berries": [ids], "ordering": [ids], "recycle": n} while a player must place berries / choose recycles
		"names": [names[0] if names.size() > 0 else "Player 1", names[1] if names.size() > 1 else "Player 2"],
		"players": [_new_player(deck_ids[0], fixed_decks[0] if not fixed_decks.is_empty() else []), _new_player(deck_ids[1], fixed_decks[1] if not fixed_decks.is_empty() else [])],
	}
	_say("%s goes first." % _pname(state.first_player) if not fixed_decks.is_empty() else "%s wins the roll and goes first." % _pname(state.first_player))
	for p in 2:
		for i in Rules.HAND_SIZE:
			_draw_card(p)
	_say("Both players draw %d cards. Choose cards to mulligan." % Rules.HAND_SIZE, -1, "phase")
	state_changed.emit()


func is_over() -> bool:
	return state.phase == "over"


## Seats the engine is currently waiting on.
func awaiting() -> Array:
	if not state.pending.is_empty():
		return [state.pending.player]
	match state.phase:
		"mulligan":
			var out: Array = []
			for p in 2:
				if not state.players[p].mulligan_done:
					out.append(p)
			return out
		"main":
			return [state.active]
	return []


func submit(player: int, action: Dictionary) -> Dictionary:
	if state.phase == "over":
		return _err("The game is over")
	var t: String = action.get("type", "")
	var res: Dictionary
	if t == "concede":  # allowed at any time, including during the opponent's turn
		_say("%s concedes the game." % _pname(player), player)
		_win(1 - player, "%s conceded." % _pname(player))
		state_changed.emit()
		return _ok()
	if not state.pending.is_empty():
		var wanted := "place_berry"
		if state.pending.berries.is_empty():
			wanted = "order_recycle" if not state.pending.ordering.is_empty() else "recycle"
		if player != state.pending.player or t != wanted:
			return _err("Finish the pending choice first (%s)" % wanted)
		match wanted:
			"place_berry": res = _do_place_berry(player, action)
			"order_recycle": res = _do_order_recycle(player, action)
			_: res = _do_recycle(player, action)
	elif state.phase == "mulligan":
		if t != "mulligan":
			return _err("Mulligan first")
		res = _do_mulligan(player, action)
	else:
		if player != state.active:
			return _err("It is not your turn")
		match t:
			"attach_berry": res = _do_attach(player, action)
			"play_creature": res = _do_play_creature(player, action)
			"use_ability": res = _do_ability(player, action)
			"play_spell": res = _do_spell(player, action)
			"swap": res = _do_swap(player, action)
			"end_turn": res = _do_end_turn(player)
			_: res = _err("Unknown action")
	if res.ok:
		_apply_deferred_loss()
		state_changed.emit()
	return res


## Everything `player` is allowed to know: own hand/deck size, public boards and discards.
func get_view(player: int) -> Dictionary:
	var me: Dictionary = state.players[player]
	var opp: Dictionary = state.players[1 - player]
	return {
		"me": player,
		"phase": state.phase,
		"turn": state.turn,
		"active": state.active,
		"first_player": state.first_player,
		"winner": state.winner,
		"names": state.names.duplicate(),
		"pending": state.pending.duplicate(true),
		"awaiting": awaiting(),
		"you": _public_player(me).merged({"hand": me.hand.duplicate(), "deck_cards": _sorted_ids(me.deck)}),
		"opponent": _public_player(opp).merged({"hand_count": opp.hand.size()}),
	}


## The cards of a deck without their order (a player may look at their own deck's contents, e.g. to search it).
func _sorted_ids(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort()
	return out


func _public_player(pl: Dictionary) -> Dictionary:
	return {
		"deck_id": pl.deck_id,
		"deck_count": pl.deck.size(),
		"discard": pl.discard.duplicate(),
		"exile": pl.exile.duplicate(),  # exile is public, like the discard
		"exile_count": pl.exile.size(),
		"board": pl.board.duplicate(true),
		"mulligan_done": pl.mulligan_done,
		"plunder_doubled": pl.plunder_doubled,
		"swaps_made": pl.swaps_made,
		"swapped_this_turn": pl.swapped_this_turn,
		"swap_cost": pl.swaps_made + 1,
		"berry_attached": pl.berry_attached,
		"creature_played": pl.creature_plays_left <= 0,
		"creature_plays_left": pl.creature_plays_left,
		"abilities_used": pl.abilities_used,
	}


# --- Setup helpers ------------------------------------------------------------
func _new_player(deck_id: String, fixed: Array = []) -> Dictionary:
	var deck: Array = fixed.duplicate() if not fixed.is_empty() else CardDB.build_deck_list(deck_id)
	if fixed.is_empty():
		for i in range(deck.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = deck[i]
			deck[i] = deck[j]
			deck[j] = tmp
	var board: Array = []
	board.resize(Rules.BOARD_SLOTS)
	var starter := CardDB.deck_starter(deck_id)
	if starter != "":  # the free starting creature: an extra card, not drawn from the deck
		board[0] = {"cards": [starter], "berries": [], "exhausted": [], "stun_until": -1, "ability_used_turn": -1,
			"ability_used_idx": [], "dormant_until": Rules.STARTER_DORMANT_UNTIL}
	return {
		"deck_id": deck_id, "deck": deck, "hand": [], "discard": [], "exile": [],
		"board": board, "mulligan_done": false, "plunder_doubled": false, "swaps_made": 0, "swapped_this_turn": false,
		"berry_attached": false, "creature_plays_left": 1, "abilities_used": 0,
	}


func _P(p: int) -> Dictionary:
	return state.players[p]


## `fx` (optional) is presentation data for clients, e.g. {"fx": "attach", "card": id, ...}.
## Cards in fx events were just played face-up, so they are public information.
func _say(text: String, player: int = -1, kind := "info", fx := {}) -> void:
	var ev := {"text": text, "player": player, "kind": kind, "turn": state.turn}
	ev.merge(fx)
	log.append(ev)
	event_logged.emit(ev)


func _pname(p: int) -> String:
	return state.names[p]


func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


func _ok() -> Dictionary:
	return {"ok": true}


# --- Turn flow ----------------------------------------------------------------
func _do_mulligan(player: int, action: Dictionary) -> Dictionary:
	var pl := _P(player)
	if pl.mulligan_done:
		return _err("Already mulliganed")
	var picks: Array = []
	for i in action.get("cards", []):
		var idx := int(i)
		if idx < 0 or idx >= pl.hand.size() or picks.has(idx):
			return _err("Invalid mulligan selection")
		picks.append(idx)
	picks.sort()
	picks.reverse()
	for idx in picks:
		pl.deck.push_back(pl.hand[idx])
		pl.hand.remove_at(idx)
	for k in picks.size():
		_draw_card(player)
	pl.mulligan_done = true
	_say("%s puts %d card(s) on the bottom and draws %d." % [_pname(player), picks.size(), picks.size()], player)
	if _P(0).mulligan_done and _P(1).mulligan_done:
		state.phase = "main"
		state.active = state.first_player
		state.turn = 1
		_begin_turn()
	return _ok()


func _begin_turn() -> void:
	var p: int = state.active
	var pl := _P(p)
	pl.berry_attached = false
	pl.swapped_this_turn = false
	pl.plunder_doubled = false
	pl.creature_plays_left = 1
	pl.abilities_used = 0
	_say("Turn %d: %s" % [state.turn, _pname(p)], p, "turn")
	if state.turn == 1 and Rules.FIRST_PLAYER_SKIPS_FIRST_DRAW:
		return
	if not _draw_card(p):
		_win(1 - p, "%s has no card to draw." % _pname(p))


func _do_end_turn(player: int) -> Dictionary:
	state.active = 1 - player
	state.turn += 1
	_begin_turn()
	return _ok()


## Draws the top card. Returns false (without changing anything) if the library is empty.
func _draw_card(p: int) -> bool:
	var pl := _P(p)
	if pl.deck.is_empty():
		return false
	pl.hand.append(pl.deck.pop_front())
	if state.phase != "over" and _active_count(p, "plunder_on_draw") > 0:
		_plunder(p, 1 - p, 1)  # Lightor: whenever its owner draws a card
	return true


## Applies a loss from an uncompletable Plunder once nothing is left to resolve.
func _apply_deferred_loss() -> void:
	if state.doomed.is_empty() or not state.pending.is_empty() or state.phase == "over":
		return
	var d: Dictionary = state.doomed
	state.doomed = {}
	_win(int(d.winner), String(d.reason))


func _win(winner: int, reason: String) -> void:
	state.phase = "over"
	state.winner = winner
	_say("%s %s wins the game!" % [reason, _pname(winner)], winner, "win")


# --- Simple actions -------------------------------------------------------------
func _do_attach(player: int, action: Dictionary) -> Dictionary:
	var pl := _P(player)
	var from_discard: bool = action.get("from", "hand") == "discard"
	var hi := int(action.get("discard" if from_discard else "hand", -1))
	var slot := int(action.get("slot", -1))
	var source: Array = pl.discard if from_discard else pl.hand
	if hi < 0 or hi >= source.size() or not CardDB.is_berry(source[hi]):
		return _err("Choose a berry from your %s" % ("discard" if from_discard else "hand"))
	if pl.berry_attached:
		return _err("You already attached a berry this turn")
	if slot < 0 or slot >= pl.board.size() or pl.board[slot] == null:
		return _err("Choose a creature")
	var id: String = source[hi]
	source.remove_at(hi)
	_add_berry(pl.board[slot], id, from_discard)  # berries from the discard enter sideways
	pl.berry_attached = true
	_say("%s attaches %s%s to %s." % [_pname(player), CardDB.card_name(id), " from the discard (exhausted)" if from_discard else "", Rules.creature_name(pl.board[slot])], player, "info",
		{"fx": "attach", "card": id, "slot": slot, "from": "discard" if from_discard else "hand", "hand": hi})
	return _ok()


func _do_play_creature(player: int, action: Dictionary) -> Dictionary:
	var pl := _P(player)
	var hi := int(action.get("hand", -1))
	var slot := int(action.get("slot", -1))
	if hi < 0 or hi >= pl.hand.size():
		return _err("Choose a card from your hand")
	var id: String = pl.hand[hi]
	if pl.creature_plays_left <= 0:
		return _err("You already played a creature this turn")
	if CardDB.is_creature(id) and int(CardDB.card(id).tier) <= 1:
		# New creatures always join at the end of the row (the board has no fixed spaces).
		slot = Rules.first_free_slot(pl.board)
		if slot < 0:
			return _err("You can't have more than %d creatures" % Rules.BOARD_SLOTS)
	var why := Rules.place_error(pl.board, id, slot)
	if why != "":
		return _err(why)
	pl.hand.remove_at(hi)
	_place_creature(player, id, slot, true, hi)
	return _ok()


func _place_creature(player: int, id: String, slot: int, counts_as_play: bool, hand_index := -1) -> void:
	var pl := _P(player)
	var c := CardDB.card(id)
	if pl.board[slot] == null:
		pl.board[slot] = {"cards": [id], "berries": [], "exhausted": [], "stun_until": -1, "ability_used_turn": -1, "ability_used_idx": []}
		_say("%s plays %s." % [_pname(player), c.name], player, "info", {"fx": "play_creature", "card": id, "slot": slot, "hand": hand_index})
	else:
		var prev := Rules.creature_name(pl.board[slot])
		pl.board[slot].cards.append(id)
		var was_stunned: bool = Rules.is_stunned(pl.board[slot], state.turn)
		pl.board[slot].stun_until = -1  # evolving removes a stun
		_say("%s evolves %s into %s%s." % [_pname(player), prev, c.name, " (the stun is removed)" if was_stunned else ""], player, "info",
			{"fx": "play_creature", "card": id, "slot": slot, "hand": hand_index})
	if counts_as_play:
		pl.creature_plays_left -= 1


## Swap: once per turn, put N cards from your hand into the discard pile and take one creature from the
## discard pile. N is 1 for your first swap of the game, 2 for the next, and so on.
func _do_swap(player: int, action: Dictionary) -> Dictionary:
	var pl := _P(player)
	var picks: Array = action.get("cards", [])
	var di := int(action.get("discard", -1))
	var cost: int = pl.swaps_made + 1
	if pl.swapped_this_turn:
		return _err("You can only swap once per turn")
	if picks.size() != cost or _indices_invalid(picks, pl.hand.size()):
		return _err("This swap costs %d card(s) from your hand" % cost)
	if di < 0 or di >= pl.discard.size() or not CardDB.is_creature(pl.discard[di]):
		return _err("Choose a creature from your discard")
	var taken: String = pl.discard[di]
	var given: Array = picks.map(func(i): return pl.hand[int(i)])
	var sorted := picks.map(func(i): return int(i))
	sorted.sort()
	sorted.reverse()
	for i in sorted:
		pl.hand.remove_at(i)
	pl.discard.remove_at(di)
	pl.discard.append_array(given)
	pl.hand.append(taken)
	pl.swaps_made += 1
	pl.swapped_this_turn = true
	_say("%s swaps %d card(s) from their hand for %s from the discard." % [_pname(player), cost, CardDB.card_name(taken)], player, "info",
		{"fx": "swap", "given": given, "taken": taken})
	return _ok()


# --- Abilities --------------------------------------------------------------------
func _do_ability(player: int, action: Dictionary) -> Dictionary:
	var pl := _P(player)
	var slot := int(action.get("slot", -1))
	var ai := int(action.get("ability", -1))
	var params: Dictionary = action.get("params", {}).duplicate()
	params["_slot"] = slot  # set here, never trusted from the client
	if slot < 0 or slot >= pl.board.size() or pl.board[slot] == null:
		return _err("Choose one of your creatures")
	var creature: Dictionary = pl.board[slot]
	var abilities: Array = Rules.top_card(creature).abilities
	if ai < 0 or ai >= abilities.size():
		return _err("Invalid ability")
	var ab: Dictionary = abilities[ai]
	if ab.get("active", false):
		return _err("That ability is always on")
	if Rules.abilities_locked(state.turn):
		return _err("Abilities can't be used on a player's first turn")
	if Rules.is_dormant(creature, state.turn):
		return _err("Your starting creature is dormant until turn %d (you can still attach berries to it)" % Rules.STARTER_DORMANT_UNTIL)
	if Rules.is_stunned(creature, state.turn):
		return _err("This creature is stunned")
	var blocked := Rules.ability_blocked(creature, ai, state.turn, _active_count(player, "double_ability") > 0)
	if blocked != "":
		return _err(blocked)
	if pl.abilities_used >= Rules.ABILITIES_PER_TURN:
		return _err("You can only use %d abilities per turn" % Rules.ABILITIES_PER_TURN)
	if not Rules.meets_cost(creature.berries, ab.cost):
		return _err("Not enough berries attached (%s)" % Rules.cost_text(ab.cost))
	for e in ab.effects:
		var why := _check_effect(e, player, params)
		if why != "":
			return _err(why)
	pl.abilities_used += 1
	if pl.plunder_doubled and ab.effects.any(func(e): return e.type == "plunder"):
		params["_double"] = true  # Fireking's Twin Flame: this Plunder ability is doubled, then the bonus is gone
		pl.plunder_doubled = false
	if int(creature.get("ability_used_turn", -1)) != state.turn:
		creature["ability_used_idx"] = []
	creature.ability_used_turn = state.turn
	creature["ability_used_idx"].append(Rules.ability_key(creature, ai))
	_say("%s uses %s's %s." % [_pname(player), Rules.creature_name(creature), Rules.ability_text(ab)], player, "ability",
		{"fx": "ability", "slot": slot, "ability": ai})
	for e in ab.effects:
		_apply_effect(e, player, slot, params)
	return _ok()


func _creature_ref_error(ref: Dictionary) -> String:
	var tp := int(ref.get("player", -1))
	var ts := int(ref.get("slot", -1))
	if tp < 0 or tp > 1 or ts < 0 or ts >= Rules.BOARD_SLOTS or _P(tp).board[ts] == null:
		return "Invalid target"
	return ""


## A target that `player` may choose: it must exist, and an opponent's creature must not be protected (Lightium).
func _target_error(player: int, ref: Dictionary) -> String:
	var why := _creature_ref_error(ref)
	if why != "":
		return why
	var tp := int(ref.player)
	if Rules.is_leader(_P(tp).board[int(ref.slot)]):
		return "Leaders can't be targeted"
	if tp != player and Rules.is_protected(_P(tp).board, int(ref.slot)):
		return "That creature can't be targeted (a Lightium protects it)"
	return ""


func _check_effect(e: Dictionary, player: int, params: Dictionary, reserved: Array = []) -> String:
	var pl := _P(player)
	match e.type:
		"recycle":
			if pl.discard.is_empty():
				return "Your discard pile is empty"
		"draw":
			if e.get("target", "") == "player" and int(params.get("player", -1)) not in [0, 1]:
				return "Choose which player draws"
		"remove_stun":
			var ref: Dictionary = params.get("target", {})
			var why := _target_error(player, ref)
			if why != "":
				return why
			if int(ref.player) == player:
				return "Choose a stunned creature of your opponent"
			if not Rules.is_stunned(_P(int(ref.player)).board[int(ref.slot)], state.turn):
				return "Choose a creature that is stunned"
		"recycle_exile":
			if pl.exile.is_empty():
				return "Your exile pile is empty"
		"discard_to_top":
			if not params.get("card", "") is String or not pl.discard.has(params.get("card", "")):
				return "Choose a card in your discard pile"
		"search_to_top":
			if not params.get("card", "") is String or not pl.deck.has(params.get("card", "")):
				return "Choose a card that is in your deck"
		"plunder":
			if e.has("per_exile") and pl.exile.is_empty():
				return "Your exile pile is empty"
		"exile_attached":
			var creature: Dictionary = pl.board[int(params._slot)]
			var bi := int(params.get("berry", -1))
			if bi < 0 or bi >= creature.berries.size() or not Rules.berry_matches(creature.berries[bi], e.element):
				return "Choose one of this creature's attached %s Berries" % String(e.element).capitalize()
		"cast_from_discard":
			var si := int(params.get("spell", -1))
			if si < 0 or si >= pl.discard.size() or not CardDB.is_spell(pl.discard[si]):
				return "Choose a spell in your discard pile"
			var spell := CardDB.card(pl.discard[si])
			var payment: Array = params.get("payment", [])
			var why := _payment_error(player, spell.cost, payment)
			if why != "":
				return why
			var held: Array = [pl.discard[si]]  # the spell itself and the berries that pay can't be picked again
			for entry in payment:
				if entry.src == "discard":
					held.append(pl.discard[int(entry.index)])
			var sp: Dictionary = params.get("spell_params", {})
			for se in spell.effects:
				why = _check_effect(se, player, sp, held)
				if why != "":
					return why
		"exile_discard":
			var pool: Array = pl.discard.duplicate()
			for id in reserved:
				pool.erase(id)
			var need := mini(int(e.amount), pool.size())
			var chosen: Array = params.get("cards", [])
			if chosen.size() != need:
				return "Choose %d card(s) from your discard pile to exile" % need
			for id in chosen:
				var at: int = pool.find(id)
				if at < 0:
					return "Those cards aren't all in your discard pile"
				pool.remove_at(at)
		"stun":
			var targets: Array = params.get("targets", [])
			if targets.is_empty() or targets.size() > int(e.count):
				return "Choose 1 to %d target creature(s)" % int(e.count)
			var seen := {}
			for t in targets:
				var why := _target_error(player, t)
				if why != "":
					return why
				var key := "%d:%d" % [int(t.player), int(t.slot)]
				if seen.has(key):
					return "Targets must be different"
				seen[key] = true
		"destroy":
			if not params.has("target"):
				return "Choose a target creature"
			return _target_error(player, params.target)
		"berry_trade":
			if not params.has("target") or not params.has("source_slot"):
				return "Choose an enemy creature"
			var why := _target_error(player, params.target)
			if why != "":
				return why
			if int(params.target.player) == player:
				return "Choose an enemy creature"
			var own: Array = params.get("own", [])
			var theirs: Array = params.get("theirs", [])
			var mine: Dictionary = _P(player).board[int(params.source_slot)]
			var enemy: Dictionary = _P(int(params.target.player)).board[int(params.target.slot)]
			if own.size() != theirs.size() or own.is_empty():
				return "Trade the same (non-zero) number of berries on each side"
			if _indices_invalid(own, mine.berries.size()) or _indices_invalid(theirs, enemy.berries.size()):
				return "Invalid berry selection"
	return ""


func _indices_invalid(indices: Array, size: int) -> bool:
	var seen := {}
	for i in indices:
		var idx := int(i)
		if idx < 0 or idx >= size or seen.has(idx):
			return true
		seen[idx] = true
	return false


func _apply_effect(e: Dictionary, player: int, slot: int, params: Dictionary) -> void:
	if state.phase == "over":
		return
	var opp := 1 - player
	match e.type:
		"plunder":
			var n := int(e.get("amount", 0))
			if e.has("per_attached_berry"):
				n = int(e.per_attached_berry) * _P(player).board[slot].berries.size()
			elif e.has("per_exile"):
				n = _P(player).exile.size()
			elif e.has("per_hand"):
				n = int(e.per_hand) * _P(player).hand.size()
			elif e.has("per_berry_per_creature"):
				var mine: Dictionary = _P(player).board[slot]
				n = int(e.per_berry_per_creature) * mine.berries.size() * (Rules.BOARD_SLOTS - _P(player).board.count(null))
			if params.get("_double", false):
				n *= 2
			_plunder(player, opp, n)
		"double_next_plunder":
			_P(player).plunder_doubled = true
			_say("%s's next Plunder ability this turn will plunder double." % _pname(player), player)
		"pillage":
			_pillage(player, int(e.amount))
		"stun":
			var names: Array = []
			for t in params.targets:
				var owner := int(t.player)
				var c: Dictionary = _P(owner).board[int(t.slot)]
				c.stun_until = state.turn + (2 if owner == state.active else 1)
				names.append(Rules.creature_name(c))
			_say("%s stuns %s until the end of their controller's next turn." % [_pname(player), ", ".join(names)], player, "info",
				{"fx": "stun", "from_slot": slot, "targets": params.targets.duplicate(true)})
		"destroy":
			_destroy_creature(int(params.target.player), int(params.target.slot))
		"berry_trade":
			var mine: Dictionary = _P(player).board[int(params.source_slot)]
			var tp := int(params.target.player)
			var enemy: Dictionary = _P(tp).board[int(params.target.slot)]
			_release_berries(player, mine, params.own)
			_release_berries(tp, enemy, params.theirs)
			_say("%d berr%s discarded from each side." % [params.own.size(), "y" if params.own.size() == 1 else "ies"], player)
		"draw":
			var target := int(params.get("player", player)) if e.get("target", "") == "player" else player
			var drawn := 0
			var draw_n := int(e.get("amount", 0))
			if e.has("per_attached_berry"):
				draw_n = int(e.per_attached_berry) * _P(player).board[slot].berries.size()
			for i in draw_n:
				if not _draw_card(target):
					_say("%s has no card to draw." % _pname(target), target)
					_win(1 - target, "%s has no card to draw." % _pname(target))
					break
				drawn += 1
				if state.phase == "over":
					break
			if drawn > 0:
				_say("%s draws %d card(s)." % [_pname(target), drawn], target)
		"remove_stun":
			var ref: Dictionary = params.target
			var c: Dictionary = _P(int(ref.player)).board[int(ref.slot)]
			c.stun_until = -1
			_say("%s removes the stun from %s." % [_pname(player), Rules.creature_name(c)], player)
		"recycle_exile":
			var pl := _P(player)
			var n := mini(int(e.per_attached_berry) * pl.board[slot].berries.size(), pl.exile.size())
			if n > 0:
				_pending_for(player).recycle = n
				state.pending["source"] = "exile"
		"bottom_from_hand":
			var pl := _P(player)
			var n := mini(int(e.per_attached_berry) * pl.board[slot].berries.size(), pl.hand.size())
			if n > 0 and state.phase != "over":
				_pending_for(player).recycle = n
				state.pending["source"] = "hand"
		"discard_to_top":
			var pl := _P(player)
			pl.discard.remove_at(pl.discard.find(params.card))
			pl.deck.push_front(params.card)
			_say("%s puts %s from the discard on top of their deck." % [_pname(player), CardDB.card_name(params.card)], player)
		"search_to_top":
			var pl := _P(player)
			pl.deck.remove_at(pl.deck.find(params.card))
			for i in range(pl.deck.size() - 1, 0, -1):  # shuffle the rest, as at a table, then the card goes on top
				var j := rng.randi_range(0, i)
				var tmp = pl.deck[i]
				pl.deck[i] = pl.deck[j]
				pl.deck[j] = tmp
			pl.deck.push_front(params.card)
			_say("%s searches their deck, shuffles it and puts a card on top." % _pname(player), player)
		"recycle":
			var pl := _P(player)
			var n := mini(int(e.amount), pl.discard.size())
			if n > 0:
				_pending_for(player).recycle = n
		"exile_attached":
			var pl := _P(player)
			var creature: Dictionary = pl.board[int(params._slot)]
			var bi := int(params.berry)
			var id: String = creature.berries[bi]
			creature.berries.remove_at(bi)
			creature.exhausted.remove_at(bi)
			pl.exile.append(id)
			_say("%s exiles a %s from %s." % [_pname(player), CardDB.card_name(id), Rules.creature_name(creature)], player)
		"cast_from_discard":
			var pl := _P(player)
			var id: String = pl.discard[int(params.spell)]
			var sp: Dictionary = params.get("spell_params", {})
			_pay(player, params.get("payment", []))  # may exile discard berries, so find the spell again afterwards
			pl.discard.remove_at(pl.discard.find(id))
			pl.exile.append(id)
			var spell := CardDB.card(id)
			_say("%s pays for %s and plays it from the discard pile; it is exiled." % [_pname(player), spell.name], player, "spell",
				{"fx": "spell", "card": id, "hand": -1, "targets": _spell_targets(spell, sp)})
			for se in spell.effects:
				_apply_effect(se, player, -1, sp)
		"exile_discard":
			var pl := _P(player)
			var n := 0
			for id in params.get("cards", []):
				var at: int = pl.discard.find(id)
				if at >= 0:
					pl.discard.remove_at(at)
					pl.exile.append(id)
					n += 1
			_say("%s exiles %d card(s) from their discard pile." % [_pname(player), n], player)
		"extra_creature_play":
			_P(player).creature_plays_left += 1
			_say("%s may play a second creature this turn." % _pname(player), player)
		_:
			pass  # "Active" effects are resolved where they trigger (see _pillage).


func _add_berry(creature: Dictionary, id: String, exhausted: bool) -> void:
	creature.berries.append(id)
	creature.exhausted.append(exhausted)


## Detaches the berry at `index`. Upright berries go to the owner's discard; sideways
## (exhausted) berries are exiled instead.
func _release_berry(owner: int, creature: Dictionary, index: int) -> void:
	var id: String = creature.berries[index]
	var pl := _P(owner)
	(pl.exile if creature.exhausted[index] else pl.discard).append(id)
	creature.berries.remove_at(index)
	creature.exhausted.remove_at(index)


func _release_berries(owner: int, creature: Dictionary, indices: Array) -> void:
	var sorted := indices.map(func(i): return int(i))
	sorted.sort()
	sorted.reverse()
	for i in sorted:
		_release_berry(owner, creature, i)


## Creatures sit left to right with no gaps, so slot numbers match what players see.
func _compact_board(owner: int) -> void:
	var pl := _P(owner)
	var packed: Array = pl.board.filter(func(c): return c != null)
	while packed.size() < pl.board.size():
		packed.append(null)
	pl.board = packed


func _destroy_creature(owner: int, slot: int) -> void:
	var pl := _P(owner)
	var c: Dictionary = pl.board[slot]
	pl.discard.append_array(c.cards)
	while not c.berries.is_empty():
		_release_berry(owner, c, c.berries.size() - 1)
	pl.board[slot] = null
	_compact_board(owner)
	_say("%s and its attached berries go to the discard." % Rules.creature_name(c), owner)


# --- Plunder / Pillage / Recycle ------------------------------------------------------
## Count of creatures with a currently satisfied Active ability containing `effect_type`.
## Stun does not turn Active effects off.
func _active_count(p: int, effect_type: String) -> int:
	var n := 0
	for c in _P(p).board:
		if c == null:
			continue
		for ab in Rules.top_card(c).abilities:
			if ab.get("active", false) and Rules.meets_cost(c.berries, ab.cost):
				for e in ab.effects:
					if e.type == effect_type:
						n += 1
	return n


func _plunder(initiator: int, target: int, n: int) -> void:
	var tp := _P(target)
	var count := 0
	var stolen := 0
	var taken: Array = []  # every card plundered, in order (clients show them before they go to the discard)
	for i in n:
		if tp.deck.is_empty():
			break
		var id: String = tp.deck.pop_front()
		count += 1
		taken.append(id)
		if CardDB.element_of(id) == Rules.SUPER:
			stolen += 1
			_reveal_berry(initiator, id)
		else:
			tp.discard.append(id)
	_say("%s is plundered by %s: %d card(s) discarded from the top of their deck%s." % [_pname(target), _pname(initiator), count, " (%d Super Berry stolen)" % stolen if stolen > 0 else ""], target, "info",
		{"fx": "plunder", "cards": taken, "target": target})
	if count < n:
		# The plunder couldn't be completed, so the target loses. The plunder still resolves in
		# full first (revealed Super Berries are placed), and the loss is applied afterwards in
		# _apply_deferred_loss(), which leaves room for a future card that can save the player.
		state.doomed = {"winner": initiator, "loser": target,
			"reason": "%s cannot complete the Plunder %d (only %d card(s) were left)." % [_pname(target), n, count]}


## Berries revealed by Plunder or Pillage that the acting player may place go into
## state.pending; the player then answers with place_berry actions (one per berry).
## A Super Berry always goes onto a creature of the player's choice, or into their
## hand if they have no creature. Other berries are only offered when Fire Famine's
## Active effect applies (see _pillage); otherwise they go to the discard.
func _pending_for(p: int) -> Dictionary:
	if state.pending.is_empty():
		state.pending = {"player": p, "berries": [], "ordering": [], "recycle": 0, "source": "discard"}
	return state.pending


func _reveal_berry(p: int, id: String) -> void:
	var pl := _P(p)
	if pl.board.all(func(c): return c == null):
		if CardDB.element_of(id) == Rules.SUPER:
			pl.hand.append(id)
		else:
			pl.discard.append(id)
		return
	_pending_for(p).berries.append(id)


func _do_place_berry(player: int, action: Dictionary) -> Dictionary:
	var pl := _P(player)
	var slot := int(action.get("slot", -1))
	if slot < 0 or slot >= pl.board.size() or pl.board[slot] == null:
		return _err("Choose a creature")
	var id: String = state.pending.berries.pop_back()
	_add_berry(pl.board[slot], id, false)
	_say("%s attaches the %s to %s." % [_pname(player), CardDB.card_name(id), Rules.creature_name(pl.board[slot])], player)
	_clear_pending_if_done()
	return _ok()


## Fire Famine's Active effect: the pillaged non-berry cards go to the bottom of the deck in
## an order the player chooses. `order` lists indices into pending.ordering; the first one is
## put on the bottom first (so the last one ends up at the very bottom).
func _do_order_recycle(player: int, action: Dictionary) -> Dictionary:
	var pl := _P(player)
	var order: Array = action.get("order", [])
	var cards: Array = state.pending.ordering
	if order.size() != cards.size() or _indices_invalid(order, cards.size()):
		return _err("Put all %d cards in an order" % cards.size())
	for i in order:
		pl.deck.push_back(cards[int(i)])
	state.pending.ordering = []
	_say("%s recycles %d card(s) to the bottom of their deck in a chosen order." % [_pname(player), order.size()], player)
	_clear_pending_if_done()
	return _ok()


## Firewolf's Active effect: the player chooses which discard cards go to the bottom of
## the deck, and in which order (first listed goes on the bottom first).
func _do_recycle(player: int, action: Dictionary) -> Dictionary:
	var pl := _P(player)
	var zone: String = state.pending.get("source", "discard")  # the discard pile, or the exile pile (Mother Nature), or the hand (Sun God)
	var cards: Array = pl[zone]
	var picks: Array = action.get("cards", [])
	var need := int(state.pending.recycle)
	if picks.size() != need or _indices_invalid(picks, cards.size()):
		return _err("Choose exactly %d card(s) from your %s to put on the bottom of your deck" % [need, zone])
	var ids: Array = picks.map(func(i): return cards[int(i)])
	var sorted := picks.map(func(i): return int(i))
	sorted.sort()
	sorted.reverse()
	for i in sorted:
		cards.remove_at(i)
	for id in ids:
		pl.deck.push_back(id)
	state.pending.recycle = 0
	_say("%s puts %d card(s) from their %s on the bottom of their deck." % [_pname(player), ids.size(), zone], player)
	_clear_pending_if_done()
	return _ok()


func _clear_pending_if_done() -> void:
	if state.pending.berries.is_empty() and state.pending.ordering.is_empty() and int(state.pending.recycle) == 0:
		state.pending = {}


## Pillage: the top n cards go to the discard, except
##  - Super Berries, which are always attached to a creature of the player's choice, and
##  - with Fire Famine's Active effect, every berry is attached (player's choice) and all
##    other cards are recycled to the bottom of the deck instead of being discarded.
## Afterwards the player always recycles 1 card from their discard, and with Firewolf's Active effect
## also as many cards as went to the discard (berries attached to creatures don't count).
## Tells clients that berries were found in `deck_owner`'s deck so they can show them on screen.
func _announce_reveal(deck_owner: int, ids: Array) -> void:
	if ids.is_empty():
		_say("No berries found in %s's deck." % _pname(deck_owner), deck_owner, "info", {"fx": "reveal", "cards": []})
		return
	var names: Array = ids.map(func(id): return CardDB.card_name(id))
	_say("%s's deck reveals: %s." % [_pname(deck_owner), ", ".join(names)], deck_owner, "info",
		{"fx": "reveal", "cards": ids.duplicate()})


func _pillage(p: int, n: int) -> void:
	var pl := _P(p)
	var famine := _active_count(p, "attach_pillaged_berries") > 0
	var wolves := _active_count(p, "recycle_on_pillage") > 0  # Active effects don't stack
	var taken := 0
	var discarded := 0  # cards that actually went to the discard (attached berries don't count)
	var recycled: Array = []  # Fire Famine: non-berry cards go straight to the bottom of the deck
	var revealed: Array = []  # berries the player gets to place (Super Berries; every berry with Fire Famine)
	var shown: Array = []  # every card pillaged, in order, and whether it goes to the discard (for the table's effects)
	var to_discard: Array = []
	for i in n:
		if pl.deck.is_empty():
			break
		var id: String = pl.deck.pop_front()
		taken += 1
		shown.append(id)
		to_discard.append(not (CardDB.element_of(id) == Rules.SUPER or famine))
		if CardDB.element_of(id) == Rules.SUPER or (famine and CardDB.is_berry(id)):
			revealed.append(id)
			_reveal_berry(p, id)
			continue
		if famine:
			recycled.append(id)
			continue
		pl.discard.append(id)
		discarded += 1
	# Recycled cards wait outside the deck until placed, so they can't be pillaged again.
	if recycled.size() == 1:
		pl.deck.append_array(recycled)
	elif recycled.size() > 1:
		_pending_for(p).ordering = recycled
	_say("%s pillages %d card(s) from their own deck%s." % [_pname(p), taken, " (%d recycled to the bottom)" % recycled.size() if not recycled.is_empty() else ""], p, "info",
		{"fx": "pillage", "cards": shown, "discard": to_discard, "target": p})
	_announce_reveal(p, revealed)
	# Every Pillage also Recycles 1 (Firewolf's Active adds one for each card that went to the discard).
	var recycle := mini((discarded if wolves else 0) + 1, pl.discard.size())
	if recycle > 0:
		_pending_for(p).recycle = recycle


# --- Spells ---------------------------------------------------------------------------
## Board spaces a spell affects, for presentation: [{"player": p, "slot": s}].
func _spell_targets(spell: Dictionary, params: Dictionary) -> Array:
	var out: Array = []
	match spell.effects[0].type:
		"destroy": out.append(params.target)
		"stun": out.append_array(params.targets)
	return out


func _do_spell(player: int, action: Dictionary) -> Dictionary:
	var pl := _P(player)
	var hi := int(action.get("hand", -1))
	var params: Dictionary = action.get("params", {})
	if hi < 0 or hi >= pl.hand.size() or not CardDB.is_spell(pl.hand[hi]):
		return _err("Choose a spell from your hand")
	var id: String = pl.hand[hi]
	var spell := CardDB.card(id)
	var why := _payment_error(player, spell.cost, action.get("payment", []))
	if why != "":
		return _err(why)
	var reserved: Array = []  # discard cards the payment uses: the spell's own effect can't pick them too
	for entry in action.get("payment", []):
		if entry.src == "discard":
			reserved.append(pl.discard[int(entry.index)])
	for e in spell.effects:
		why = _check_effect(e, player, params, reserved)
		if why != "":
			return _err(why)
	_pay(player, action.payment)
	pl.hand.remove_at(hi)
	pl.discard.append(id)
	_say("%s plays %s." % [_pname(player), spell.name], player, "spell",
		{"fx": "spell", "card": id, "hand": hi, "targets": _spell_targets(spell, params)})
	for e in spell.effects:
		_apply_effect(e, player, -1, params)
	return _ok()


## Payment entries: {"src":"discard","index":i} (exiled) or
## {"src":"attached","slot":s,"index":i} (discarded; exiled if the berry is exhausted).
## Exactly cost.amount berries.
func _payment_error(player: int, cost: Dictionary, payment: Array) -> String:
	var pl := _P(player)
	if payment.size() != int(cost.amount):
		return "Pay exactly %s" % Rules.cost_text(cost)
	var seen := {}
	for entry in payment:
		var berry := ""
		var key := ""
		var index := int(entry.get("index", -1))
		if entry.get("src", "") == "discard":
			if index < 0 or index >= pl.discard.size():
				return "Invalid payment"
			berry = pl.discard[index]
			key = "d%d" % index
		elif entry.get("src", "") == "attached":
			var slot := int(entry.get("slot", -1))
			if slot < 0 or slot >= pl.board.size() or pl.board[slot] == null:
				return "Invalid payment"
			if index < 0 or index >= pl.board[slot].berries.size():
				return "Invalid payment"
			berry = pl.board[slot].berries[index]
			key = "a%d:%d" % [slot, index]
		else:
			return "Invalid payment"
		if seen.has(key) or not CardDB.is_berry(berry) or not Rules.berry_matches(berry, cost.element):
			return "Invalid payment"
		seen[key] = true
	return ""


func _pay(player: int, payment: Array) -> void:
	var pl := _P(player)
	var attached: Array = []
	var from_discard: Array = []
	for entry in payment:
		if entry.src == "discard":
			from_discard.append(int(entry.index))
		else:
			attached.append(entry)
	attached.sort_custom(func(a, b): return int(a.index) > int(b.index))
	for entry in attached:
		_release_berry(player, pl.board[int(entry.slot)], int(entry.index))
	from_discard.sort()
	from_discard.reverse()
	for i in from_discard:
		pl.exile.append(pl.discard[i])
		pl.discard.remove_at(i)
