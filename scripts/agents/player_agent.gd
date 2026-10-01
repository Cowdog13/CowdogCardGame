class_name PlayerAgent
extends RefCounted
## Something that makes decisions for one seat. The controller asks automatic agents
## for an action whenever their seat is awaited; non-automatic agents (a human at the
## UI, or a future network peer) push actions in through GameController.submit().
##
## decide() may be a coroutine (use `await`), so a network agent can wait for a reply.

var seat := 0
var is_automatic := true


func decide(_view: Dictionary) -> Dictionary:
	return {}


## Always-valid action used if an agent keeps producing illegal ones.
static func fallback_action(view: Dictionary) -> Dictionary:
	if not view.pending.is_empty():
		for s in view.you.board.size():
			if view.you.board[s] != null:
				return {"type": "place_super", "slot": s}
	if view.phase == "mulligan":
		return {"type": "mulligan", "cards": []}
	return {"type": "end_turn"}
