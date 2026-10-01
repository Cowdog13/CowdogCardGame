extends SceneTree
## Drives the human-facing click handlers of GameScreen (mulligan, attach, play, abilities,
## targeting, dialogs) against the AI.   godot --headless -s tests/ui_interact.gd

func _init() -> void:
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["crashing_wave", "scorching_fire"], [HumanAgent.new(0), AIAgent.new(1)], 0.0)
	await process_frame
	screen._on_hand_clicked(0)
	screen._on_hand_clicked(1)
	screen._on_confirm()
	var ok_actions := 0
	for step in 600:
		await process_frame
		var v: Dictionary = screen.view
		if v.phase == "over":
			break
		if v.phase != "main" or v.active != 0 or screen.get_children().any(func(c): return c is ConfirmationDialog):
			continue
		var you: Dictionary = v.you
		var acted := false
		for i in you.hand.size():
			var id: String = you.hand[i]
			if CardDB.is_creature(id) and not you.creature_played:
				for s in Rules.BOARD_SLOTS:
					if Rules.place_error(you.board, id, s) == "":
						screen._on_hand_clicked(i)
						screen._on_slot_clicked(0, s)
						acted = true
						break
				if acted:
					break
			if CardDB.is_berry(id) and not you.berry_attached:
				screen._on_hand_clicked(i)
				for s in Rules.BOARD_SLOTS:
					if you.board[s] != null:
						screen._on_slot_clicked(0, s)
						acted = true
						break
				screen._cancel()
				if acted:
					break
		if not acted and you.abilities_used < Rules.ABILITIES_PER_TURN:
			for s in Rules.BOARD_SLOTS:
				var c = you.board[s]
				if c == null:
					continue
				var abs: Array = Rules.top_card(c).abilities
				for ai in abs.size():
					if not abs[ai].get("active", false) and Rules.meets_cost(c.berries, abs[ai].cost) and not Rules.is_stunned(c, v.turn):
						screen._on_ability_pressed(s, ai)
						if not screen._pending.is_empty():
							for ts in Rules.BOARD_SLOTS:
								screen._on_slot_clicked(1, ts)
							screen._cancel()
						acted = screen.view.you.abilities_used > you.abilities_used
						if acted:
							break
				if acted:
					break
		if not acted:
			screen._submit({"type": "end_turn"})
		else:
			ok_actions += 1
	# Dialog builders (one at a time; they are modal).
	for open_dialog in [func(): screen._show_pile("test", screen.view.you.discard), func(): screen._on_swap()]:
		open_dialog.call()
		for d in screen.get_children().filter(func(c): return c is Window):
			screen.remove_child(d)
			d.free()
		await process_frame
	print("phase=%s turn=%d human_actions=%d status='%s'" % [screen.view.phase, screen.view.turn, ok_actions, screen._status])
	quit(0)
