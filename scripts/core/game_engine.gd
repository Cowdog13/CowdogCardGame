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
##   {"type":"swap",         "hand":i, "discard":j}             (once per game)
##   {"type":"place_berry",  "slot":s}                        (only while state.pending has berries: where a revealed berry goes)
##   {"type":"recycle",      "cards":[discard indices]}       (only while state.pending.recycle > 0: Firewolf's choice)
##   {"type":"end_turn"}
## Results are {"ok":true} or {"ok":false,"error":"..."}.

signal event_logged(event: Dictionary)
signal state_changed

var state: Dictionary = {}
var log: Array = []
var seed_value := 0
var rng := RandomNumberGenerator.new()


func setup(deck_ids: Array, seed_val: int = -1) -> void:
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
		"first_player": rng.randi_range(0, 1),
		"winner": -1,
		"pending": {},  # {"player": p, "berries": [ids], "recycle": n} while a player must place berries / choose recycles
		"names": ["Player 1", "Player 2"],
		"players": [_new_player(deck_ids[0]), _new_player(deck_ids[1])],
	}
	_say("Player %d wins the roll and goes first." % (state.first_player + 1))
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
	if not state.pending.is_empty():
		var wanted := "place_berry" if not state.pending.berries.is_empty() else "recycle"
		if player != state.pending.player or t != wanted:
			return _err("Finish the pending choice first (%s)" % wanted)
		res = _do_place_berry(player, action) if wanted == "place_berry" else _do_recycle(player, action)
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
		"pending": state.pending.duplicate(true),
		"awaiting": awaiting(),
		"you": _public_player(me).merged({"hand": me.hand.duplicate(), "pillaged": me.pillaged.duplicate()}),
		"opponent": _public_player(opp).merged({"hand_count": opp.hand.size()}),
	}


func _public_player(pl: Dictionary) -> Dictionary:
	return {
		"deck_id": pl.deck_id,
		"deck_count": pl.deck.size(),
		"discard": pl.discard.duplicate(),
		"exile": pl.exile.duplicate(),  # exile is public, like the discard
		"exile_count": pl.exile.size(),
		"board": pl.board.duplicate(true),
		"mulligan_done": pl.mulligan_done,
		"swap_used": pl.swap_used,
		"berry_attached": pl.berry_attached,
		"creature_played": pl.creature_played,
		"abilities_used": pl.abilities_used,
	}


# --- Setup helpers ------------------------------------------------------------
func _new_player(deck_id: String) -> Dictionary:
	var deck := CardDB.build_deck_list(deck_id)
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	var board: Array = []
	board.resize(Rules.BOARD_SLOTS)
	return {
		"deck_id": deck_id, "deck": deck, "hand": [], "discard": [], "exile": [],
		"board": board, "mulligan_done": false, "swap_used": false,
		"berry_attached": false, "creature_played": false, "abilities_used": 0,
		"pillaged": [],
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
	pl.creature_played = false
	pl.abilities_used = 0
	pl.pillaged = []
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
	return true


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
	if pl.creature_played:
		return _err("You already played a creature this turn")
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
		pl.board[slot] = {"cards": [id], "berries": [], "exhausted": [], "stun_until": -1, "ability_used_turn": -1}
		_say("%s plays %s." % [_pname(player), c.name], player, "info", {"fx": "play_creature", "card": id, "slot": slot, "hand": hand_index})
	else:
		var prev := Rules.creature_name(pl.board[slot])
		pl.board[slot].cards.append(id)
		var was_stunned: bool = Rules.is_stunned(pl.board[slot], state.turn)
		pl.board[slot].stun_until = -1  # evolving removes a stun
		_say("%s evolves %s into %s%s." % [_pname(player), prev, c.name, " (the stun is removed)" if was_stunned else ""], player, "info",
			{"fx": "play_creature", "card": id, "slot": slot, "hand": hand_index})
	if counts_as_play:
		pl.creature_played = true


func _do_swap(player: int, action: Dictionary) -> Dictionary:
	var pl := _P(player)
	var hi := int(action.get("hand", -1))
	var di := int(action.get("discard", -1))
	if pl.swap_used:
		return _err("You already used your once-per-game swap")
	if hi < 0 or hi >= pl.hand.size() or not CardDB.is_creature(pl.hand[hi]):
		return _err("Choose a creature from your hand")
	if di < 0 or di >= pl.discard.size() or not CardDB.is_creature(pl.discard[di]):
		return _err("Choose a creature from your discard")
	var from_hand: String = pl.hand[hi]
	var from_discard: String = pl.discard[di]
	pl.hand[hi] = from_discard
	pl.discard[di] = from_hand
	pl.swap_used = true
	_say("%s swaps %s from hand with %s from the discard." % [_pname(player), CardDB.card_name(from_hand), CardDB.card_name(from_discard)], player, "info",
		{"fx": "swap", "hand_card": from_hand, "discard_card": from_discard})
	return _ok()


# --- Abilities --------------------------------------------------------------------
func _do_ability(player: int, action: Dictionary) -> Dictionary:
	var pl := _P(player)
	var slot := int(action.get("slot", -1))
	var ai := int(action.get("ability", -1))
	var params: Dictionary = action.get("params", {})
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
	if Rules.is_stunned(creature, state.turn):
		return _err("This creature is stunned")
	if Rules.used_ability_this_turn(creature, state.turn):
		return _err("Each creature can use only one ability per turn")
	if pl.abilities_used >= Rules.ABILITIES_PER_TURN:
		return _err("You can only use %d abilities per turn" % Rules.ABILITIES_PER_TURN)
	if not Rules.meets_cost(creature.berries, ab.cost):
		return _err("Not enough berries attached (%s)" % Rules.cost_text(ab.cost))
	for e in ab.effects:
		var why := _check_effect(e, player, params)
		if why != "":
			return _err(why)
	pl.abilities_used += 1
	creature.ability_used_turn = state.turn
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


func _check_effect(e: Dictionary, player: int, params: Dictionary) -> String:
	match e.type:
		"stun":
			var targets: Array = params.get("targets", [])
			if targets.is_empty() or targets.size() > int(e.count):
				return "Choose 1 to %d target creature(s)" % int(e.count)
			var seen := {}
			for t in targets:
				var why := _creature_ref_error(t)
				if why != "":
					return why
				var key := "%d:%d" % [int(t.player), int(t.slot)]
				if seen.has(key):
					return "Targets must be different"
				seen[key] = true
		"destroy":
			if not params.has("target"):
				return "Choose a target creature"
			return _creature_ref_error(params.target)
		"berry_trade":
			if not params.has("target") or not params.has("source_slot"):
				return "Choose an enemy creature"
			var why := _creature_ref_error(params.target)
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
		"play_pillaged_creature":
			var pl := _P(player)
			var id: String = params.get("card_id", "")
			if id == "" or not pl.pillaged.has(id) or not pl.discard.has(id):
				return "That creature was not pillaged this turn"
			return Rules.place_error(pl.board, id, int(params.get("slot", -1)))
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
	var opp := 1 - player
	match e.type:
		"plunder":
			var n := int(e.get("amount", 0))
			if e.has("per_attached_berry"):
				n = int(e.per_attached_berry) * _P(player).board[slot].berries.size()
			_plunder(player, opp, n)
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
		"play_pillaged_creature":
			var pl := _P(player)
			var id: String = params.card_id
			pl.discard.remove_at(pl.discard.find(id))
			pl.pillaged.remove_at(pl.pillaged.find(id))
			_place_creature(player, id, int(params.slot), false)  # Reinforce ignores the once-per-turn limit
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


func _destroy_creature(owner: int, slot: int) -> void:
	var pl := _P(owner)
	var c: Dictionary = pl.board[slot]
	pl.discard.append_array(c.cards)
	while not c.berries.is_empty():
		_release_berry(owner, c, c.berries.size() - 1)
	pl.board[slot] = null
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
	for i in n:
		if tp.deck.is_empty():
			break
		var id: String = tp.deck.pop_front()
		count += 1
		if CardDB.element_of(id) == Rules.SUPER:
			stolen += 1
			_reveal_berry(initiator, id)
		else:
			tp.discard.append(id)
	_say("%s is plundered by %s: %d card(s) discarded from the top of their deck%s." % [_pname(target), _pname(initiator), count, " (%d Super Berry stolen)" % stolen if stolen > 0 else ""], target)


## Berries revealed by Plunder or Pillage that the acting player may place go into
## state.pending; the player then answers with place_berry actions (one per berry).
## A Super Berry always goes onto a creature of the player's choice, or into their
## hand if they have no creature. Other berries are only offered when Fire Famine's
## Active effect applies (see _pillage); otherwise they go to the discard.
func _pending_for(p: int) -> Dictionary:
	if state.pending.is_empty():
		state.pending = {"player": p, "berries": [], "recycle": 0}
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


## Firewolf's Active effect: the player chooses which discard cards go to the bottom of
## the deck. Cards go on the bottom in the order chosen.
func _do_recycle(player: int, action: Dictionary) -> Dictionary:
	var pl := _P(player)
	var picks: Array = action.get("cards", [])
	var need := int(state.pending.recycle)
	if picks.size() != need or _indices_invalid(picks, pl.discard.size()):
		return _err("Choose exactly %d card(s) from your discard to recycle" % need)
	var ids: Array = picks.map(func(i): return pl.discard[int(i)])
	var sorted := picks.map(func(i): return int(i))
	sorted.sort()
	sorted.reverse()
	for i in sorted:
		pl.discard.remove_at(i)
	for id in ids:
		pl.deck.push_back(id)
		var pi: int = pl.pillaged.find(id)
		if pi >= 0:
			pl.pillaged.remove_at(pi)
	state.pending.recycle = 0
	_say("%s recycles %d card(s) to the bottom of their deck." % [_pname(player), ids.size()], player)
	_clear_pending_if_done()
	return _ok()


func _clear_pending_if_done() -> void:
	if state.pending.berries.is_empty() and int(state.pending.recycle) == 0:
		state.pending = {}


## Pillage: the top n cards go to the discard, except
##  - Super Berries, which are always attached to a creature of the player's choice, and
##  - with Fire Famine's Active effect, every berry is attached (player's choice).
## With Firewolf's Active effect the player then chooses as many cards to recycle as went to
## the discard (berries attached to creatures don't count).
func _pillage(p: int, n: int) -> void:
	var pl := _P(p)
	var famine := _active_count(p, "attach_pillaged_berries") > 0
	var wolves := _active_count(p, "recycle_on_pillage") > 0  # Active effects don't stack
	var taken := 0
	var discarded := 0  # cards that actually went to the discard (attached berries don't count)
	for i in n:
		if pl.deck.is_empty():
			break
		var id: String = pl.deck.pop_front()
		taken += 1
		if CardDB.element_of(id) == Rules.SUPER or (famine and CardDB.is_berry(id)):
			_reveal_berry(p, id)
			continue
		pl.discard.append(id)
		pl.pillaged.append(id)
		discarded += 1
	_say("%s pillages %d card(s) from their own deck." % [_pname(p), taken], p)
	var recycle := mini(discarded, pl.discard.size()) if wolves else 0
	if recycle > 0:
		_pending_for(p).recycle = recycle


# --- Spells ---------------------------------------------------------------------------
## Board spaces a spell affects, for presentation: [{"player": p, "slot": s}].
func _spell_targets(spell: Dictionary, params: Dictionary) -> Array:
	var out: Array = []
	match spell.effects[0].type:
		"destroy": out.append(params.target)
		"stun": out.append_array(params.targets)
		"play_pillaged_creature": out.append({"player": state.active, "slot": int(params.slot)})
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
	for e in spell.effects:
		why = _check_effect(e, player, params)
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
