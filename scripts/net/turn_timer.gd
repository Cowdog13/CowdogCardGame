class_name TurnTimer
extends RefCounted
## Multiplayer turn clock (host side). Each turn starts with `base` seconds; every action the
## active player completes adds `bonus`. When it runs out the turn ends by itself, unless the
## player did nothing at all that turn, which forfeits the game. No clock during the mulligan.

var base := 60.0
var bonus := 4.0
var seat := -1  # whose clock is running (-1: none)
var remaining := 0.0
var actions := 0  # actions the active player has completed this turn
var changed := true  # set when seat/actions/remaining jumped, so the host tells the clients

var _key := -1


## Call every frame with the engine state; starts a fresh clock whenever a new turn begins.
func sync(state: Dictionary) -> void:
	if state.get("phase", "") != "main":
		if seat != -1:
			seat = -1
			changed = true
		_key = -1
		return
	var key := int(state.turn) * 2 + int(state.active)
	if key != _key:
		_key = key
		seat = int(state.active)
		remaining = base
		actions = 0
		changed = true


## Returns true once the active player's time is up.
func tick(delta: float) -> bool:
	if seat == -1:
		return false
	remaining = maxf(0.0, remaining - delta)
	return remaining <= 0.0


func on_action(by_seat: int, action: Dictionary) -> void:
	if by_seat != seat or action.get("type", "") == "end_turn":
		return
	actions += 1
	remaining += bonus
	changed = true
