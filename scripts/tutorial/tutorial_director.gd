class_name TutorialDirector
extends Node
## Runs the tutorial on top of a normal game: shows the steps of TutorialScript, refuses every move
## except the one the current step asks for (through GameController.action_filter), and lets the
## practice opponent play only when the player says so (GameController.hold_external).

signal finished  # the player chose to keep playing the game
signal quit_requested

var ctrl: GameController
var screen: GameScreen
var steps: Array = []
var index := -1
var overlay: TutorialOverlay

var _step: Dictionary = {}
var _ready_for_input := false  # the current step is on screen and its action may be played
var _bot_turn := -1
var _generation := 0  # bumped on every step so a late timer can't advance a step that was left


func setup(p_ctrl: GameController, p_screen: GameScreen) -> TutorialDirector:
	ctrl = p_ctrl
	screen = p_screen
	steps = TutorialScript.steps()
	return self


func _ready() -> void:
	ctrl.hold_external = true
	ctrl.action_filter = _filter
	ctrl.action_done.connect(_on_action_done)
	ctrl.view_updated.connect(_on_view_updated)
	overlay = TutorialOverlay.new()
	overlay.screen = screen
	overlay.next_pressed.connect(_on_next)
	overlay.quit_pressed.connect(func(): quit_requested.emit())
	overlay.finish_pressed.connect(_on_finish)
	_attach_overlay.call_deferred()


func _attach_overlay() -> void:
	screen.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_go(0)


func _view() -> Dictionary:
	return ctrl.get_view(0)


# --- Moving between steps ---------------------------------------------------------------------
func _go(i: int) -> void:
	if i >= steps.size():
		return
	_generation += 1
	var gen := _generation
	index = i
	_step = steps[i]
	_ready_for_input = false
	overlay.hide_panel()
	# Wait until the table has caught up: effects finished and the game is at the point this step is about.
	while not _step_is_reachable(_step) or screen._fx_busy():
		await get_tree().process_frame
		if gen != _generation or not is_inside_tree():
			return
	await get_tree().create_timer(0.35).timeout
	if gen != _generation or not is_inside_tree():
		return
	var kind := "next"
	if _step.has("expect"):
		kind = "action"
	elif _step.get("bot", false):
		kind = "bot"
	elif _step.get("end", false):
		kind = "end"
	overlay.show_step(_step, i, steps.size(), kind)
	_ready_for_input = _step.has("expect")


func _step_is_reachable(step: Dictionary) -> bool:
	var v := _view()
	if v.is_empty():
		return false
	if v.phase == "over":
		return true
	if step.get("bot", false):
		return v.phase == "main"
	if not step.has("expect"):
		return v.phase == "main" and v.active == 0 or v.phase == "mulligan"
	match step.expect.type:
		"mulligan":
			return v.phase == "mulligan" and not v.you.mulligan_done
		"place_berry", "recycle":
			return not v.pending.is_empty() and v.pending.player == 0
		_:
			return v.phase == "main" and v.active == 0 and v.pending.is_empty()


func _on_next() -> void:
	if _step.get("bot", false):
		_bot_turn = int(_view().turn)
		overlay.hide_panel()
		_ready_for_input = false
		ctrl.hold_external = false
	else:
		_go(index + 1)


func _on_view_updated() -> void:
	if _bot_turn < 0:
		return
	var v := _view()
	if v.phase == "main" and v.active == 0 and int(v.turn) > _bot_turn:
		_bot_turn = -1
		ctrl.hold_external = true
		_go(index + 1)


func _on_action_done(seat: int, _action: Dictionary) -> void:
	if seat == 0 and _ready_for_input and _step.has("expect"):
		_ready_for_input = false
		overlay.hide_panel()
		_go(index + 1)


func _on_finish() -> void:
	ctrl.action_filter = Callable()
	ctrl.hold_external = false
	ctrl.agents[1] = AIAgent.new(1)
	overlay.queue_free()
	finished.emit()
	queue_free()


# --- The rule layer -----------------------------------------------------------------------------
## Only the action the current step asks for is allowed; everything else is refused with a hint.
func _filter(seat: int, action: Dictionary, view: Dictionary) -> String:
	if seat != 0:
		return ""
	if not _ready_for_input or not _step.has("expect"):
		return "Follow the tutorial: press the button in the tutorial window first."
	var exp: Dictionary = _step.expect
	var hint: String = _step.get("hint", "That isn't what the tutorial asks for right now.")
	if action.get("type", "") != exp.type:
		return hint
	var you: Dictionary = view.you
	match exp.type:
		"mulligan":
			var ids: Array = []
			for i in action.get("cards", []):
				if int(i) >= 0 and int(i) < you.hand.size():
					ids.append(you.hand[int(i)])
			ids.sort()
			var want: Array = exp.cards.duplicate()
			want.sort()
			return "" if ids == want else hint
		"attach_berry":
			var from_discard: bool = action.get("from", "hand") == "discard"
			if from_discard != (exp.get("from", "hand") == "discard"):
				return hint
			var source: Array = you.discard if from_discard else you.hand
			var si := int(action.get("discard" if from_discard else "hand", -1))
			if si < 0 or si >= source.size() or source[si] != exp.card:
				return hint
			return "" if _creature_at(you, action.get("slot", -1)) == exp.to else "Attach it to %s." % CardDB.card_name(exp.to)
		"play_creature":
			return "" if _hand_card(you, action) == exp.card else hint
		"use_ability":
			if _creature_at(you, action.get("slot", -1)) != exp.creature or int(action.get("ability", -1)) != int(exp.ability):
				return hint
		"place_berry":
			return "" if _creature_at(you, action.get("slot", -1)) == exp.to else hint
		"recycle":
			var ids: Array = []
			for i in action.get("cards", []):
				if int(i) >= 0 and int(i) < you.discard.size():
					ids.append(you.discard[int(i)])
			return "" if ids == exp.cards else hint
		"swap":
			var given: Array = []
			for i in action.get("cards", []):
				if int(i) >= 0 and int(i) < you.hand.size():
					given.append(you.hand[int(i)])
			given.sort()
			var want_given: Array = exp.hand_cards.duplicate()
			want_given.sort()
			var di := int(action.get("discard", -1))
			var ok: bool = di >= 0 and di < you.discard.size() and given == want_given and you.discard[di] == exp.discard_card
			return "" if ok else hint
		"play_spell":
			if _hand_card(you, action) != exp.card:
				return hint
			var target: Dictionary = action.get("params", {}).get("target", {})
			var side: Dictionary = view.opponent if int(target.get("player", -1)) != 0 else you
			return "" if _creature_at(side, target.get("slot", -1)) == exp.target else hint
	return ""


func _hand_card(you: Dictionary, action: Dictionary) -> String:
	var hi := int(action.get("hand", -1))
	return you.hand[hi] if hi >= 0 and hi < you.hand.size() else ""


## Card id on top of the creature in `slot` of a (public) player view, or "".
func _creature_at(side: Dictionary, slot) -> String:
	var s := int(slot)
	if s < 0 or s >= side.board.size() or side.board[s] == null:
		return ""
	return Rules.top_card(side.board[s]).id
