class_name GameController
extends Node
## Glues an engine to one agent per seat. Automatic agents (the AI) are asked for actions
## on a short timer so a human can follow along; humans (or, later, network peers) call
## submit(). The UI only talks to this class.
##
## Networking seam: a remote opponent is just another PlayerAgent. A host would run this
## controller, forward get_view(seat) to the remote client, and feed the client's actions
## into submit(seat, action). Clients would render the views they receive.

signal view_updated
signal event_logged(event: Dictionary)
signal game_over(winner: int)

const MAX_FAILURES := 5

var engine := GameEngine.new()
var agents: Array = []
var ai_delay := 0.7

var _busy := {}
var _failures := {}
var _over_emitted := false


func start(deck_ids: Array, p_agents: Array, seed_val: int = -1) -> void:
	agents = p_agents
	engine.event_logged.connect(func(ev): event_logged.emit(ev))
	engine.state_changed.connect(_on_state_changed)
	engine.setup(deck_ids, seed_val)
	_pump.call_deferred()


func get_view(seat: int) -> Dictionary:
	return engine.get_view(seat)


## Entry point for humans / remote players.
func submit(seat: int, action: Dictionary) -> Dictionary:
	var res := engine.submit(seat, action)
	if res.ok:
		_failures[seat] = 0
	return res


func _on_state_changed() -> void:
	view_updated.emit()
	if engine.is_over() and not _over_emitted:
		_over_emitted = true
		game_over.emit(engine.state.winner)
	_pump.call_deferred()


func _pump() -> void:
	if not is_inside_tree():
		return
	for seat in engine.awaiting():
		var agent: PlayerAgent = agents[seat]
		if agent.is_automatic and not _busy.get(seat, false):
			_run_agent(seat)


func _run_agent(seat: int) -> void:
	_busy[seat] = true
	await get_tree().create_timer(ai_delay).timeout
	if is_inside_tree() and not engine.is_over() and engine.awaiting().has(seat):
		var view := engine.get_view(seat)
		var action: Dictionary = await agents[seat].decide(view)
		var res := engine.submit(seat, action)
		if res.ok:
			_failures[seat] = 0
		else:
			_failures[seat] = int(_failures.get(seat, 0)) + 1
			push_warning("Agent %d illegal action %s: %s" % [seat, action, res.error])
			if _failures[seat] >= MAX_FAILURES:
				engine.submit(seat, PlayerAgent.fallback_action(view))
	_busy[seat] = false
	_pump()
