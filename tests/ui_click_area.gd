extends SceneTree
## Every pixel row of a board creature must select it while targeting (disabled ability buttons
## must not swallow clicks). Needs a display: xvfb-run godot --rendering-driver opengl3 -s tests/ui_click_area.gd
func _init() -> void:
	var fails := 0
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["crashing_wave", "scorching_fire"], [HumanAgent.new(0), HumanAgent.new(1)], 0.0, false)
	await process_frame
	var e: GameEngine = screen.controller.engine
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	var me: int = e.state.active
	if me != 0:
		e.submit(me, {"type": "end_turn"})
	var pl: Dictionary = e.state.players[0]
	for s in 5:
		pl.board[s] = {"cards": ["water_ruler"], "berries": ["water_berry", "super_berry", "water_berry", "water_berry", "super_berry", "water_berry", "water_berry", "super_berry", "water_berry", "water_berry"], "exhausted": [false, true, false, false, false, false, false, false, false, false], "stun_until": -1, "ability_used_turn": -1}
		e.state.players[1].board[s] = {"cards": ["firepup"], "berries": ["fire_berry"], "exhausted": [false], "stun_until": -1, "ability_used_turn": -1}
	pl.hand = ["water_ruler", "water_berry", "removal", "water_spirit"]
	pl.discard = ["water_sprite"]
	e.state_changed.emit()
	await process_frame
	await process_frame
	screen._submit({"type": "swap", "hand": 0, "discard": 0})
	await process_frame
	await process_frame
	# Click probing: begin targeting then click at several y offsets inside slot 2.
	screen._begin_targeting("test", func(p, s): return p == 0, 1, func(t): pass)
	await process_frame
	var slot: Control = screen._my_board.get_child(2)
	var r := slot.get_global_rect()
	for f in [0.05, 0.3, 0.45, 0.6, 0.8, 0.95]:
		screen._pending.targets = []
		var pos := r.position + Vector2(r.size.x * 0.5, r.size.y * f)
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.global_position = pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		root.push_input(ev)
		await process_frame
		if not screen._pending.is_empty():
			fails += 1
			print("click at %.2f of the slot height was ignored" % f)
		if screen._pending.is_empty():
			screen._begin_targeting("test", func(p, s): return p == 0, 1, func(t): pass)
			await process_frame
			slot = screen._my_board.get_child(2)
	print("click_area failures=%d" % fails)
	quit(fails)
