class_name Rules
extends RefCounted
## Rule constants and pure helper functions that operate on plain data
## (creature / board dictionaries). Shared by the engine, the AI and the UI.
##
## A creature on the board is: {"cards": [ids, base first], "berries": [ids],
## "exhausted": [bool per berry, true = sideways], "stun_until": int,
## "ability_used_turn": int, "ability_used_idx": ["card_id:index", ...] (optional: the abilities used on that turn)}

# --- Tunable rules (the rules document leaves these open) -------------------
const BOARD_SLOTS := 5  # a Tier 2/3 creature still occupies just one space
const HAND_SIZE := 7
const ABILITIES_PER_TURN := 2  # total per player per turn
const FIRST_PLAYER_SKIPS_FIRST_DRAW := false
const FIRST_TURN_NO_ABILITIES := true  # neither player may use abilities on their first turn

## Every player starts with a free Tier 1 creature on the board; it can't use abilities before this turn.
const STARTER_DORMANT_UNTIL := 5

const SUPER := "super"
const COLORLESS := "colorless"
const ELEMENTS: Array[String] = ["fire", "water", "nature", "light", "shadow", "void", "metal", "air", "electric"]


static func element_color(element: String) -> Color:
	match element:
		"fire": return Color(0.91, 0.34, 0.16)
		"water": return Color(0.23, 0.56, 0.88)
		"nature": return Color(0.31, 0.68, 0.29)
		"light": return Color(0.95, 0.85, 0.30)
		"shadow": return Color(0.42, 0.29, 0.55)
		"void": return Color(0.17, 0.17, 0.23)
		"metal": return Color(0.60, 0.64, 0.68)
		"air": return Color(0.62, 0.89, 0.91)
		"electric": return Color(0.95, 0.69, 0.12)
		"super": return Color(0.88, 0.38, 0.75)
	return Color(0.79, 0.76, 0.69)


## Abilities can't be used on either player's first turn (turns 1 and 2 overall).
static func abilities_locked(turn: int) -> bool:
	return FIRST_TURN_NO_ABILITIES and turn <= 2


# --- Text -------------------------------------------------------------------
static func cost_text(cost: Dictionary) -> String:
	var el: String = cost.element
	var label := "Colorless" if el == COLORLESS else "%s Berry" % el.capitalize()
	return "%d %s" % [int(cost.amount), label]


static func ability_text(ability: Dictionary) -> String:
	if ability.has("text"):
		return ability.text
	var parts: Array[String] = []
	for e in ability.effects:
		match e.type:
			"plunder": parts.append("Plunder %d" % int(e.amount))
			"pillage": parts.append("Pillage %d" % int(e.amount))
			"stun": parts.append("Stun %d" % int(e.count))
			"recycle": parts.append("Recycle %d" % int(e.amount))
			"draw": parts.append("Draw %d" % int(e.amount))
			_: parts.append(String(e.type))
	return ", ".join(parts)


# --- Creatures ---------------------------------------------------------------
static func top_card(creature: Dictionary) -> Dictionary:
	return CardDB.card(creature.cards[creature.cards.size() - 1])


static func creature_name(creature: Dictionary) -> String:
	return top_card(creature).name


## The starting creature sleeps for each player's first two turns (berries can still be attached to it).
static func is_dormant(creature: Dictionary, turn: int) -> bool:
	return int(creature.get("dormant_until", -1)) > turn


static func is_stunned(creature: Dictionary, turn: int) -> bool:
	return int(creature.stun_until) >= turn


## Has this creature used any ability this turn?
static func used_ability_this_turn(creature: Dictionary, turn: int) -> bool:
	return int(creature.get("ability_used_turn", -1)) == turn


## "" when `creature` may use its ability number `ai` now, otherwise why not. Normally a creature uses only one
## ability per turn; with `double` (an Active "two different abilities" effect on the player's board) it may use
## two different ones.
static func ability_blocked(creature: Dictionary, ai: int, turn: int, double: bool) -> String:
	if not used_ability_this_turn(creature, turn):
		return ""
	var used: Array = creature.get("ability_used_idx", ["?"])  # a creature without the list used exactly one
	if not double:
		return "Each creature can use only one ability per turn"
	if used.has(ability_key(creature, ai)):
		return "A creature can't use the same ability twice in a turn"
	if used.size() >= 2:
		return "Each creature can use at most two abilities per turn"
	return ""


static func ability_key(creature: Dictionary, ai: int) -> String:
	return "%s:%d" % [top_card(creature).id, ai]


## Does a creature on `board` with a satisfied Active ability of this effect type exist? (Stun doesn't turn it off.)
static func has_active(board: Array, effect_type: String) -> bool:
	for c in board:
		if c == null:
			continue
		for ab in top_card(c).abilities:
			if ab.get("active", false) and meets_cost(c.berries, ab.cost):
				for e in ab.effects:
					if e.type == effect_type:
						return true
	return false


## Lightium: creatures with a Super Berry attached can't be targeted by the opponent while the Active effect is on.
static func is_protected(board: Array, slot: int) -> bool:
	var c = board[slot]
	if c == null or not has_active(board, "protect_super"):
		return false
	return c.berries.any(func(b): return CardDB.element_of(b) == SUPER)


static func berry_matches(berry_id: String, needed: String) -> bool:
	var e := CardDB.element_of(berry_id)
	if needed == COLORLESS:
		return true
	if needed == SUPER:
		return e == SUPER
	return e == needed or e == SUPER


static func count_matching(berries: Array, cost: Dictionary) -> int:
	var n := 0
	for b in berries:
		if berry_matches(b, cost.element):
			n += 1
	return n


## Ability costs are requirements: the creature needs this many matching berries
## attached, but they are not consumed.
static func meets_cost(berries: Array, cost: Dictionary) -> bool:
	return count_matching(berries, cost) >= int(cost.amount)


## First empty board space, or -1 when the board is full.
static func first_free_slot(board: Array) -> int:
	for i in board.size():
		if board[i] == null:
			return i
	return -1


## Returns "" when `card_id` can be played on `slot` of `board`, otherwise the reason it can't.
static func place_error(board: Array, card_id: String, slot: int) -> String:
	var c := CardDB.card(card_id)
	if c.kind != "creature":
		return "Not a creature"
	if slot < 0 or slot >= board.size():
		return "Invalid slot"
	var target = board[slot]
	if int(c.tier) <= 1:
		return "That space is occupied" if target != null else ""
	if target == null:
		return "%s must be played on %s" % [c.name, CardDB.card_name(c.evolves_from)]
	if top_card(target).id != c.evolves_from:
		return "%s must be played on %s" % [c.name, CardDB.card_name(c.evolves_from)]
	return ""


# --- Is there anything left to do? -------------------------------------------
## True when the player whose `view` this is has at least one legal action left this turn besides ending it
## (used to flash the End Turn button). Judged from the view only, and a little generous: a spell counts if it
## can be paid for, an ability if its berries and what it needs (cards to recycle, ...) are there.
static func has_move(view: Dictionary, count_swap := true) -> bool:
	var me: Dictionary = view.you
	var opp: Dictionary = view.opponent
	var has_creature: bool = me.board.any(func(c): return c != null)
	if not me.berry_attached and has_creature:
		if me.hand.any(func(id): return CardDB.is_berry(id)) or me.discard.any(func(id): return CardDB.is_berry(id)):
			return true
	if not me.creature_played:
		for id in me.hand:
			if CardDB.is_creature(id):
				for slot in me.board.size():
					if place_error(me.board, id, slot) == "":
						return true
	for id in me.hand:
		if CardDB.is_spell(id):
			var spell := CardDB.card(id)
			if not plan_payment(me, spell.cost).is_empty() and _spell_has_target(spell, me, opp):
				return true
	if count_swap and can_swap(view):
		return true
	if me.abilities_used < ABILITIES_PER_TURN and not abilities_locked(int(view.turn)):
		var double := has_active(me.board, "double_ability")
		for c in me.board:
			if c == null or is_stunned(c, int(view.turn)) or is_dormant(c, int(view.turn)):
				continue
			var abilities: Array = top_card(c).abilities
			for ai in abilities.size():
				var ab: Dictionary = abilities[ai]
				if not ab.get("active", false) and ability_blocked(c, ai, int(view.turn), double) == "" \
						and meets_cost(c.berries, ab.cost) and _ability_can_resolve(ab, c, me, opp):
					return true
	return false


## A swap is possible now: none yet this turn, enough cards in hand to pay its cost and a creature in the discard.
static func can_swap(view: Dictionary) -> bool:
	var me: Dictionary = view.you
	return not me.swapped_this_turn and me.hand.size() >= int(me.swap_cost) and me.discard.any(func(id): return CardDB.is_creature(id))


static func _spell_has_target(spell: Dictionary, me: Dictionary, opp: Dictionary) -> bool:
	match spell.effects[0].type:
		"destroy", "stun":
			if me.board.any(func(c): return c != null):
				return true
			for slot in opp.board.size():
				if opp.board[slot] != null and not is_protected(opp.board, slot):
					return true
			return false
	return true


static func _ability_can_resolve(ab: Dictionary, creature: Dictionary, me: Dictionary, opp: Dictionary) -> bool:
	for e in ab.effects:
		match e.type:
			"recycle", "discard_to_top":
				if me.discard.is_empty():
					return false
			"search_to_top":
				if int(me.deck_count) == 0:
					return false
			"plunder":
				if e.has("per_exile") and int(me.exile_count) == 0:
					return false
			"exile_attached":
				if not creature.berries.any(func(b): return berry_matches(b, e.element)):
					return false
			"cast_from_discard":
				if not me.discard.any(func(id): return CardDB.is_spell(id) and not plan_payment(me, CardDB.card(id).cost).is_empty()):
					return false
			"berry_trade":
				if creature.berries.is_empty() or not opp.board.any(func(c): return c != null and not c.berries.is_empty()):
					return false
			"stun":
				if not (me.board.any(func(c): return c != null) or opp.board.any(func(c): return c != null)):
					return false
	return true


# --- Heuristic valuation (used for AI decisions and automatic choices) -------
static func effect_value(effect: Dictionary, creature: Dictionary) -> float:
	match effect.type:
		"plunder":
			if effect.has("per_attached_berry"):
				return float(int(effect.per_attached_berry) * creature.berries.size())
			if effect.has("per_exile") or effect.has("per_hand"):
				return 2.0  # grows with the exile pile / the hand
			return float(int(effect.amount))
		"recycle":
			return 0.3
		"draw":
			return 0.9 * float(int(effect.amount))
		"discard_to_top":
			return 0.4
		"search_to_top":
			return 1.0
		"cast_from_discard":
			return 1.5
		"stun":
			return 2.0 * int(effect.count)
		"berry_trade":
			return minf(creature.berries.size(), 3.0)
	return 0.0


static func ability_value(ability: Dictionary, creature: Dictionary) -> float:
	if ability.get("active", false):
		return 0.5
	var v := 0.0
	for e in ability.effects:
		v += effect_value(e, creature)
	return v


## How useful this creature is right now: best affordable abilities plus partial credit
## for abilities it is close to affording.
static func creature_potential(creature: Dictionary) -> float:
	var ready: Array = []
	var progress := 0.0
	for ab in top_card(creature).abilities:
		var v := ability_value(ab, creature)
		if meets_cost(creature.berries, ab.cost):
			ready.append(v)
		else:
			progress += 0.25 * v * float(count_matching(creature.berries, ab.cost)) / float(int(ab.cost.amount))
	ready.sort()
	ready.reverse()
	var total := progress
	for i in mini(ready.size(), ABILITIES_PER_TURN):
		total += ready[i]
	return total


static func board_potential(board: Array) -> float:
	var total := 0.0
	for c in board:
		if c != null:
			total += creature_potential(c)
	return total


## Slot on `board` where attaching `berry_id` helps the most, or -1 when there is no creature.
static func best_attach_slot(board: Array, berry_id: String) -> int:
	var best := -1
	var best_score := -INF
	for s in board.size():
		var c = board[s]
		if c == null:
			continue
		var sim: Dictionary = c.duplicate(true)
		sim.berries.append(berry_id)
		var score := creature_potential(sim) - creature_potential(c)
		score += 0.01 * int(top_card(c).tier) - 0.001 * c.berries.size()
		if score > best_score:
			best_score = score
			best = s
	return best


## Cheapest way for `me` (a player view/state) to pay a spell cost. Prefers exiling berries
## from the discard pile, then discarding attached berries where it hurts the board least.
## Returns {"payment": [...], "loss": float} or {} if the cost cannot be paid.
## `blocked` lists discard indices that may not be used (cards reserved for the spell's own effect).
static func plan_payment(me: Dictionary, cost: Dictionary, blocked: Array = []) -> Dictionary:
	var need := int(cost.amount)
	var payment: Array = []
	for pass_super in [false, true]:
		for i in me.discard.size():
			if payment.size() >= need:
				break
			var id: String = me.discard[i]
			if blocked.has(i) or not CardDB.is_berry(id) or not berry_matches(id, cost.element):
				continue
			if (CardDB.element_of(id) == SUPER) != pass_super:
				continue
			payment.append({"src": "discard", "index": i})
	var board: Array = me.board.duplicate(true)
	var before := board_potential(board)
	var index_map: Array = []  # per slot: original indices of berries still attached
	for c in board:
		var m: Array = []
		if c != null:
			for i in c.berries.size():
				m.append(i)
		index_map.append(m)
	while payment.size() < need:
		var best_loss := INF
		var best_s := -1
		var best_i := -1
		for s in board.size():
			var c = board[s]
			if c == null:
				continue
			var cur := creature_potential(c)
			for i in c.berries.size():
				if not berry_matches(c.berries[i], cost.element):
					continue
				var sim: Dictionary = c.duplicate(true)
				sim.berries.remove_at(i)
				var loss := cur - creature_potential(sim)
				if loss < best_loss:
					best_loss = loss
					best_s = s
					best_i = i
		if best_s < 0:
			return {}
		payment.append({"src": "attached", "slot": best_s, "index": index_map[best_s][best_i]})
		index_map[best_s].remove_at(best_i)
		board[best_s].berries.remove_at(best_i)
	return {"payment": payment, "loss": before - board_potential(board)}


## Indices of the `n` discard cards least worth keeping there, best first: berries, then
## spells, then creatures (Reinforce may want those); newest first within a group.
static func recycle_pick(discard: Array, n: int) -> Array:
	var order: Array = range(discard.size() - 1, -1, -1)
	var rank := func(i: int) -> int:
		return 2 if CardDB.is_creature(discard[i]) else (1 if CardDB.is_spell(discard[i]) else 0)
	order.sort_custom(func(a, b): return rank.call(a) < rank.call(b))
	return order.slice(0, mini(n, order.size()))


## Berry trade: which `n` berries to discard from our creature and from the enemy creature.
## We give up the least useful, we take the most useful (Super Berries first).
static func plan_trade(own: Dictionary, theirs: Dictionary, n: int) -> Dictionary:
	var mine: Array = []
	var sim: Dictionary = own.duplicate(true)
	var idx: Array = range(sim.berries.size())
	for k in n:
		var best_i := -1
		var best_loss := INF
		var cur := creature_potential(sim)
		for i in sim.berries.size():
			var t: Dictionary = sim.duplicate(true)
			t.berries.remove_at(i)
			var loss := cur - creature_potential(t)
			if loss < best_loss:
				best_loss = loss
				best_i = i
		mine.append(idx[best_i])
		idx.remove_at(best_i)
		sim.berries.remove_at(best_i)
	var order: Array = range(theirs.berries.size())
	order.sort_custom(func(a, b):
		var sa := 0 if CardDB.element_of(theirs.berries[a]) == SUPER else 1
		var sb := 0 if CardDB.element_of(theirs.berries[b]) == SUPER else 1
		return sa < sb)
	return {"own": mine, "theirs": order.slice(0, n)}
