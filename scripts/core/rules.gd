class_name Rules
extends RefCounted
## Rule constants and pure helper functions that operate on plain data
## (creature / board dictionaries). Shared by the engine, the AI and the UI.
##
## A creature on the board is: {"cards": [ids, base first], "berries": [ids],
## "exhausted": [bool per berry, true = sideways], "stun_until": int,
## "ability_used_turn": int}

# --- Tunable rules (the rules document leaves these open) -------------------
const BOARD_SLOTS := 5  # a Tier 2/3 creature still occupies just one space
const HAND_SIZE := 7
const ABILITIES_PER_TURN := 2  # total per player per turn
const FIRST_PLAYER_SKIPS_FIRST_DRAW := false
const FIRST_TURN_NO_ABILITIES := true  # neither player may use abilities on their first turn

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
			_: parts.append(String(e.type))
	return ", ".join(parts)


# --- Creatures ---------------------------------------------------------------
static func top_card(creature: Dictionary) -> Dictionary:
	return CardDB.card(creature.cards[creature.cards.size() - 1])


static func creature_name(creature: Dictionary) -> String:
	return top_card(creature).name


static func is_stunned(creature: Dictionary, turn: int) -> bool:
	return int(creature.stun_until) >= turn


## Each creature may use only one ability per turn.
static func used_ability_this_turn(creature: Dictionary, turn: int) -> bool:
	return int(creature.get("ability_used_turn", -1)) == turn


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


# --- Heuristic valuation (used for AI decisions and automatic choices) -------
static func effect_value(effect: Dictionary, creature: Dictionary) -> float:
	match effect.type:
		"plunder":
			if effect.has("per_attached_berry"):
				return float(int(effect.per_attached_berry) * creature.berries.size())
			return float(int(effect.amount))
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
static func plan_payment(me: Dictionary, cost: Dictionary) -> Dictionary:
	var need := int(cost.amount)
	var payment: Array = []
	for pass_super in [false, true]:
		for i in me.discard.size():
			if payment.size() >= need:
				break
			var id: String = me.discard[i]
			if not CardDB.is_berry(id) or not berry_matches(id, cost.element):
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
