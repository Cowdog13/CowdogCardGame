class_name AIAgent
extends PlayerAgent
## Heuristic computer opponent. Works only from its view of the game, and returns one
## action per call; it is called repeatedly until it ends its turn.


func _init(p_seat: int = 1) -> void:
	seat = p_seat


func decide(view: Dictionary) -> Dictionary:
	if not view.pending.is_empty():
		if view.pending.berries.is_empty():
			return {"type": "recycle", "cards": Rules.recycle_pick(view.you.discard, view.pending.recycle)}
		return {"type": "place_berry", "slot": Rules.best_attach_slot(view.you.board, view.pending.berries.back())}
	if view.phase == "mulligan":
		return _mulligan(view)
	return _main_phase(view)


# --- Mulligan -----------------------------------------------------------------
func _mulligan(view: Dictionary) -> Dictionary:
	var hand: Array = view.you.hand
	var berries := 0
	var starters := 0
	for id in hand:
		if CardDB.is_berry(id):
			berries += 1
		elif CardDB.is_creature(id) and int(CardDB.card(id).tier) == 1:
			starters += 1
	var bottom: Array = []
	if berries < 2 or starters < 1:
		# Keep berries and tier 1 creatures; send back everything we can't use early.
		for i in hand.size():
			var id: String = hand[i]
			var keep := CardDB.is_berry(id) or (CardDB.is_creature(id) and int(CardDB.card(id).tier) == 1)
			if not keep:
				bottom.append(i)
	return {"type": "mulligan", "cards": bottom}


# --- Main phase -----------------------------------------------------------------
func _main_phase(view: Dictionary) -> Dictionary:
	var me: Dictionary = view.you
	var a: Dictionary
	if not me.creature_played:
		a = _creature_play(view)
		if not a.is_empty():
			return a
	if not me.berry_attached:
		a = _berry_attach(view)
		if not a.is_empty():
			return a
	a = _spell(view)
	if not a.is_empty():
		return a
	if me.abilities_used < Rules.ABILITIES_PER_TURN and not Rules.abilities_locked(view.turn):
		a = _ability(view)
		if not a.is_empty():
			return a
	a = _swap(view)
	if not a.is_empty():
		return a
	return {"type": "end_turn"}


func _creature_play(view: Dictionary) -> Dictionary:
	var me: Dictionary = view.you
	var best := {}
	var best_score := -INF
	for hi in me.hand.size():
		var id: String = me.hand[hi]
		if not CardDB.is_creature(id):
			continue
		var tier := int(CardDB.card(id).tier)
		for slot in me.board.size():
			if Rules.place_error(me.board, id, slot) != "":
				continue
			var score := 0.0
			if tier > 1:
				score = 10.0 + tier  # evolving keeps berries and is almost always best
			else:
				score = 3.0 + _best_cheap_value(id)
				for other in me.hand:
					if CardDB.is_creature(other) and CardDB.card(other).evolves_from == id:
						score += 1.5
			if score > best_score:
				best_score = score
				best = {"type": "play_creature", "hand": hi, "slot": slot}
	return best


func _best_cheap_value(id: String) -> float:
	var best := 0.0
	for ab in CardDB.card(id).abilities:
		var v := Rules.ability_value(ab, {"berries": []})
		best = maxf(best, v / float(int(ab.cost.amount)))
	return best


func _berry_attach(view: Dictionary) -> Dictionary:
	var me: Dictionary = view.you
	var best := {}
	var best_score := -INF
	var tried := {}
	for hi in me.hand.size():
		var id: String = me.hand[hi]
		if not CardDB.is_berry(id) or tried.has(id):
			continue
		tried[id] = true
		var slot := Rules.best_attach_slot(me.board, id)
		if slot < 0:
			continue
		var sim: Dictionary = me.board[slot].duplicate(true)
		sim.berries.append(id)
		var score := Rules.creature_potential(sim) - Rules.creature_potential(me.board[slot])
		if CardDB.element_of(id) == Rules.SUPER:
			score -= 0.05  # prefer elemental berries when it makes no difference
		if score > best_score:
			best_score = score
			best = {"type": "attach_berry", "hand": hi, "slot": slot}
	if best.is_empty():
		# No berry in hand: reuse one from the discard (it enters exhausted).
		for di in me.discard.size():
			var id: String = me.discard[di]
			if CardDB.is_berry(id):
				var slot := Rules.best_attach_slot(me.board, id)
				if slot >= 0:
					return {"type": "attach_berry", "from": "discard", "discard": di, "slot": slot}
	return best


# --- Spells ---------------------------------------------------------------------------
func _spell(view: Dictionary) -> Dictionary:
	var me: Dictionary = view.you
	var opp: Dictionary = view.opponent
	for hi in me.hand.size():
		var id: String = me.hand[hi]
		if not CardDB.is_spell(id):
			continue
		var spell := CardDB.card(id)
		var effect: Dictionary = spell.effects[0]
		var plan: Dictionary = Rules.plan_payment(me, spell.cost)
		if plan.is_empty():
			continue
		var params := {}
		var worth := 0.0
		match effect.type:
			"destroy":
				var t := _strongest_enemy(opp, view.turn, false)
				if t < 0:
					continue
				worth = _threat(opp.board[t], view.turn)
				params = {"target": {"player": 1 - view.me, "slot": t}}
				if worth < 4.0:
					continue
			"stun":
				var t := _strongest_enemy(opp, view.turn, true)
				if t < 0:
					continue
				worth = _threat(opp.board[t], view.turn)
				params = {"targets": [{"player": 1 - view.me, "slot": t}]}
				if worth < 3.0:
					continue
			"play_pillaged_creature":
				var pick := _reinforce_pick(me)
				if pick.is_empty():
					continue
				worth = 6.0
				params = pick
			_:
				continue
		if plan.loss < worth * 0.6:
			return {"type": "play_spell", "hand": hi, "payment": plan.payment, "params": params}
	return {}


func _threat(creature: Dictionary, turn: int) -> float:
	var t := Rules.creature_potential(creature) + 0.5 * int(Rules.top_card(creature).tier)
	if Rules.is_stunned(creature, turn):
		t *= 0.3
	return t


## Strongest enemy creature; with `skip_stunned`, ignores creatures already stunned.
func _strongest_enemy(opp: Dictionary, turn: int, skip_stunned: bool) -> int:
	var best := -1
	var best_t := 0.0
	for s in opp.board.size():
		var c = opp.board[s]
		if c == null or (skip_stunned and Rules.is_stunned(c, turn)):
			continue
		var t := _threat(c, turn)
		if t > best_t:
			best_t = t
			best = s
	return best


func _reinforce_pick(me: Dictionary) -> Dictionary:
	for id in me.pillaged:
		if not me.discard.has(id) or not CardDB.is_creature(id):
			continue
		for slot in me.board.size():
			if Rules.place_error(me.board, id, slot) == "":
				return {"card_id": id, "slot": slot}
	return {}


# --- Abilities --------------------------------------------------------------------------
func _ability(view: Dictionary) -> Dictionary:
	var me: Dictionary = view.you
	var opp: Dictionary = view.opponent
	var best := {}
	var best_value := 0.0
	for slot in me.board.size():
		var c = me.board[slot]
		if c == null or Rules.is_stunned(c, view.turn) or Rules.used_ability_this_turn(c, view.turn):
			continue
		var abilities: Array = Rules.top_card(c).abilities
		for ai in abilities.size():
			var ab: Dictionary = abilities[ai]
			if ab.get("active", false) or not Rules.meets_cost(c.berries, ab.cost):
				continue
			var evaluated := _evaluate_ability(view, slot, c, ab, me, opp)
			if evaluated.is_empty() or evaluated.value <= best_value:
				continue
			best_value = evaluated.value
			best = {"type": "use_ability", "slot": slot, "ability": ai, "params": evaluated.params}
	return best


## Returns {"value": float, "params": Dictionary} or {} if the ability isn't worth using.
func _evaluate_ability(view: Dictionary, slot: int, c: Dictionary, ab: Dictionary, me: Dictionary, opp: Dictionary) -> Dictionary:
	var effect: Dictionary = ab.effects[0]
	var enemy := 1 - int(view.me)
	match effect.type:
		"plunder":
			if opp.deck_count <= 0:
				return {}
			return {"value": Rules.effect_value(effect, c), "params": {}}
		"pillage":
			# Only pillage when something makes it free or profitable: Recycle keeps the deck
			# size, Scavenger turns pillaged berries into attachments.
			var safe: bool = _has_active(me, "recycle_on_pillage") or (_has_active(me, "attach_pillaged_berries") and me.deck_count > 25)
			if not safe or me.deck_count <= int(effect.amount) + 5:
				return {}
			return {"value": 0.8, "params": {}}
		"stun":
			var targets: Array = []
			var order: Array = range(opp.board.size())
			order.sort_custom(func(a, b): return _slot_threat(opp, a, view.turn) > _slot_threat(opp, b, view.turn))
			var total := 0.0
			for s in order:
				var t := _slot_threat(opp, s, view.turn)
				if opp.board[s] == null or Rules.is_stunned(opp.board[s], view.turn) or t < 1.5 or targets.size() >= int(effect.count):
					continue
				targets.append({"player": enemy, "slot": s})
				total += t
			if targets.is_empty():
				return {}
			return {"value": total * 0.6, "params": {"targets": targets}}
		"berry_trade":
			return _evaluate_trade(c, slot, opp, enemy)
	return {}


func _slot_threat(opp: Dictionary, s: int, turn: int) -> float:
	return 0.0 if opp.board[s] == null else _threat(opp.board[s], turn)


func _has_active(me: Dictionary, effect_type: String) -> bool:
	for c in me.board:
		if c == null:
			continue
		for ab in Rules.top_card(c).abilities:
			if ab.get("active", false) and Rules.meets_cost(c.berries, ab.cost):
				for e in ab.effects:
					if e.type == effect_type:
						return true
	return false


func _evaluate_trade(c: Dictionary, slot: int, opp: Dictionary, enemy: int) -> Dictionary:
	var best := {}
	var best_value := 0.5
	for s in opp.board.size():
		var target = opp.board[s]
		if target == null or target.berries.is_empty():
			continue
		for n in range(1, mini(c.berries.size(), target.berries.size()) + 1):
			var plan := Rules.plan_trade(c, target, n)
			var own_after: Dictionary = c.duplicate(true)
			var their_after: Dictionary = target.duplicate(true)
			var own_ids: Array = []
			for i in plan.own:
				own_ids.append(c.berries[i])
			var their_ids: Array = []
			for i in plan.theirs:
				their_ids.append(target.berries[i])
			own_after.berries = c.berries.filter(func(b): return not _consume(own_ids, b))
			their_after.berries = target.berries.filter(func(b): return not _consume(their_ids, b))
			var gain := (Rules.creature_potential(target) - Rules.creature_potential(their_after)) \
				- (Rules.creature_potential(c) - Rules.creature_potential(own_after))
			if gain > best_value:
				best_value = gain
				best = {"value": gain, "params": {
					"source_slot": slot, "target": {"player": enemy, "slot": s},
					"own": plan.own, "theirs": plan.theirs}}
	return best


## Removes one occurrence of `b` from `pool`; true if it was there.
func _consume(pool: Array, b: String) -> bool:
	var i := pool.find(b)
	if i < 0:
		return false
	pool.remove_at(i)
	return true


# --- Swap ----------------------------------------------------------------------------------
func _swap(view: Dictionary) -> Dictionary:
	var me: Dictionary = view.you
	if me.swap_used or me.creature_played:
		return {}
	for di in me.discard.size():
		var wanted: String = me.discard[di]
		if not CardDB.is_creature(wanted) or not _playable_now(me, wanted):
			continue
		for hi in me.hand.size():
			var give: String = me.hand[hi]
			if CardDB.is_creature(give) and not _playable_now(me, give) and int(CardDB.card(give).tier) > 1:
				return {"type": "swap", "hand": hi, "discard": di}
	return {}


func _playable_now(me: Dictionary, id: String) -> bool:
	for slot in me.board.size():
		if Rules.place_error(me.board, id, slot) == "":
			return true
	return false
