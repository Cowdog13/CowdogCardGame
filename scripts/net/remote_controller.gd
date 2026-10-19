class_name RemoteController
extends Node
## What a joined (non-host) player's screen talks to. It looks like GameController to the UI, but
## it owns no game: it holds the latest view the host sent for this seat and forwards actions to
## the host, which decides whether they are legal.

signal view_updated
signal event_logged(event: Dictionary)
signal game_over(winner: int)
signal action_rejected(message: String)

var hold_ai := false  # unused here; keeps the interface identical to GameController
var ai_delay := 0.0
var history: Array = []  # every event received so far (a late-attaching screen replays them)

var _view: Dictionary = {}
var _sender: Callable
var _over_emitted := false


func setup(sender: Callable) -> void:
	_sender = sender


func get_view(_seat: int) -> Dictionary:
	return _view


## The host answers with an update (or an error via reject()), so there is no immediate verdict.
func submit(_seat: int, action: Dictionary) -> Dictionary:
	_sender.call(action)
	return {"ok": true}


func has_view() -> bool:
	return not _view.is_empty()


## Events first (so the screen can capture start positions from the old table), then the new view.
func apply_update(events: Array, view: Dictionary) -> void:
	for ev in events:
		history.append(ev)
		event_logged.emit(ev)
	_view = view
	view_updated.emit()
	if view.get("phase", "") == "over" and not _over_emitted:
		_over_emitted = true
		game_over.emit(int(view.winner))


func reject(message: String) -> void:
	action_rejected.emit(message)
