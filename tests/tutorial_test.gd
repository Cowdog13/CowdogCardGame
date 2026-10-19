extends SceneTree
## SHOTS=dir to also save screenshots of some steps (needs a renderer, not --headless).
## Plays the whole tutorial through the controller exactly as the steps ask, and checks that the scripted
## game really goes the way the steps say (stun, stolen Super Berry, pillaged Fireking, ...).
##   godot --headless -s tests/tutorial_test.gd
var fails := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)


func _init() -> void:
	var screen := GameScreen.new()
	screen.tutorial_mode = true
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ctrl := GameController.new()
	ctrl.ai_delay = 0.0
	ctrl.hold_external = true
	screen.attach(ctrl, 0, OS.get_environment("SHOTS") != "", false)
	ctrl.start(["scorching_fire", "crashing_wave"], [HumanAgent.new(0), ScriptedAgent.new(1, TutorialScript.opponent_intents())], -1, ["You", "Practice Bot"], TutorialScript.decks())
	var director := TutorialDirector.new().setup(ctrl, screen)
	screen.add_child(director)
	var e: GameEngine = ctrl.engine
	var steps := director.steps
	check(e.state.players[0].deck.size() + e.state.players[0].hand.size() == 50, "player deck is 50 cards")
	check(e.state.players[1].deck.size() + e.state.players[1].hand.size() == 50, "opponent deck is 50 cards")
	for i in steps.size():
		var t0 := Time.get_ticks_msec()
		while director.index != i or not director.overlay._panel.visible:
			await process_frame
			if Time.get_ticks_msec() - t0 > 12000:
				check(false, "step %d (%s) never appeared" % [i, steps[i].title])
				quit(1)
				return
		var step: Dictionary = steps[i]
		# Highlight targets must resolve to something on screen.
		for t in step.get("highlight", []):
			check(screen.tutorial_target_rect(String(t)).size != Vector2.ZERO, "step %d: no target for %s" % [i, t])
		if OS.get_environment("SHOTS") != "" and [1, 3, 9, 10, 11, 14, 15, 18, 21, 23, 25, 26, 27, 28].has(i):
			await create_timer(0.6).timeout
			root.get_viewport().get_texture().get_image().save_png("%s/step%02d.png" % [OS.get_environment("SHOTS"), i])
		if step.has("expect"):
			var wrong := ctrl.submit(0, {"type": "end_turn"}) if step.expect.type != "end_turn" else ctrl.submit(0, {"type": "mulligan", "cards": []})
			check(not wrong.ok, "step %d: a wrong action was accepted" % i)
			var action := _action_for(step.expect, ctrl.get_view(0))
			var res := ctrl.submit(0, action)
			check(res.ok, "step %d (%s): %s -> %s" % [i, step.title, action, res.get("error", "")])
		elif step.get("end", false):
			break
		else:
			director._on_next()
			await process_frame
	check(e.state.players[1].board.count(null) >= 4, "Removal took out a creature of the opponent")
	check(e.state.players[0].exile.size() >= 1, "an exhausted berry was exiled")
	check(e.state.players[0].swap_used, "swap was used")
	check(Rules.top_card(e.state.players[0].board[0]).id == "fireking", "slot 0 is Fireking")
	check(e.state.turn == 7 and e.state.active == 0, "still turn 7")
	director._on_finish()
	check(ctrl.agents[1] is AIAgent, "opponent is the AI after finishing")
	print("tutorial_test failures=%d" % fails)
	quit(fails)


func _slot(side: Dictionary, id: String) -> int:
	for s in side.board.size():
		if side.board[s] != null and Rules.top_card(side.board[s]).id == id:
			return s
	return -1


func _action_for(exp: Dictionary, view: Dictionary) -> Dictionary:
	var you: Dictionary = view.you
	match exp.type:
		"mulligan":
			var idx: Array = []
			for id in exp.cards:
				idx.append(you.hand.find(id))
			return {"type": "mulligan", "cards": idx}
		"attach_berry":
			if exp.get("from", "hand") == "discard":
				return {"type": "attach_berry", "from": "discard", "discard": you.discard.find(exp.card), "slot": _slot(you, exp.to)}
			return {"type": "attach_berry", "hand": you.hand.find(exp.card), "slot": _slot(you, exp.to)}
		"play_creature":
			var c := CardDB.card(exp.card)
			var slot := Rules.first_free_slot(you.board) if int(c.tier) <= 1 else _slot(you, c.evolves_from)
			return {"type": "play_creature", "hand": you.hand.find(exp.card), "slot": slot}
		"use_ability":
			return {"type": "use_ability", "slot": _slot(you, exp.creature), "ability": exp.ability, "params": {}}
		"place_berry":
			return {"type": "place_berry", "slot": _slot(you, exp.to)}
		"swap":
			return {"type": "swap", "hand": you.hand.find(exp.hand_card), "discard": you.discard.find(exp.discard_card)}
		"play_spell":
			var payment: Array = []
			for i in you.discard.size():
				if CardDB.is_berry(you.discard[i]) and payment.size() < 3:
					payment.append({"src": "discard", "index": i})
			for s in you.board.size():
				if you.board[s] != null:
					for k in you.board[s].berries.size():
						if payment.size() < 3 and you.board[s].exhausted[k]:
							payment.append({"src": "attached", "slot": s, "index": k})
			return {"type": "play_spell", "hand": you.hand.find(exp.card), "payment": payment,
				"params": {"target": {"player": 1, "slot": _slot(view.opponent, exp.target)}}}
		"end_turn":
			return {"type": "end_turn"}
	return {}
