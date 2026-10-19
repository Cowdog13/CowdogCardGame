class_name ScriptedAgent
extends PlayerAgent
## Plays a fixed list of moves (used for the tutorial opponent). Each intent names cards, not
## positions, so it stays valid whatever order the hand is in:
##   {"play": card_id}                          play a creature (a Basic goes on the board, a Stage 2/3 evolves)
##   {"attach": card_id, "to": creature_id}     attach a berry from hand to the creature whose top card is `to`
##   {"ability": creature_id, "index": n, "params": {}}   use that creature's ability (params as for the engine, e.g. Stun targets)
## Once the list is used up it just ends its turn. Each turn ends with an {"end": true}.

var intents: Array = []


func _init(p_seat: int = 1, p_intents: Array = []) -> void:
	seat = p_seat
	intents = p_intents.duplicate(true)


func decide(view: Dictionary) -> Dictionary:
	if view.phase == "mulligan":
		return {"type": "mulligan", "cards": []}
	if not view.pending.is_empty():
		return PlayerAgent.fallback_action(view)
	if intents.is_empty():
		return {"type": "end_turn"}
	var intent: Dictionary = intents.pop_front()
	if intent.has("end"):
		return {"type": "end_turn"}
	var action := _resolve(intent, view)
	return action if not action.is_empty() else {"type": "end_turn"}


func _slot_of(board: Array, creature_id: String) -> int:
	for s in board.size():
		if board[s] != null and Rules.top_card(board[s]).id == creature_id:
			return s
	return -1


func _resolve(intent: Dictionary, view: Dictionary) -> Dictionary:
	var me: Dictionary = view.you
	if intent.has("play"):
		var hi: int = me.hand.find(intent.play)
		if hi < 0:
			return {}
		var card := CardDB.card(intent.play)
		var slot := Rules.first_free_slot(me.board) if int(card.tier) <= 1 else _slot_of(me.board, card.evolves_from)
		return {"type": "play_creature", "hand": hi, "slot": slot} if slot >= 0 else {}
	if intent.has("attach"):
		var hi: int = me.hand.find(intent.attach)
		var slot := _slot_of(me.board, intent.to)
		return {"type": "attach_berry", "hand": hi, "slot": slot} if hi >= 0 and slot >= 0 else {}
	if intent.has("ability"):
		var slot := _slot_of(me.board, intent.ability)
		return {"type": "use_ability", "slot": slot, "ability": int(intent.get("index", 0)), "params": intent.get("params", {})} if slot >= 0 else {}
	return {}
