extends SceneTree
## A destroyed creature stays on the table until the Removal card has played its animation.
##   godot --headless -s tests/ui_removal_ghost.gd
func _init() -> void:
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["crashing_wave", "scorching_fire"], [HumanAgent.new(0), HumanAgent.new(1)], 0.0, true)
	await process_frame
	var e: GameEngine = screen.controller.engine
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.turn = 5
	e.state.active = 0
	var me: Dictionary = e.state.players[0]
	me.hand = ["removal"]
	me.board[0] = {"cards": ["water_spirit"], "berries": ["water_berry", "water_berry", "water_berry"], "exhausted": [false, false, false], "stun_until": -1, "ability_used_turn": -1}
	e.state.players[1].board[0] = {"cards": ["firespore"], "berries": [], "exhausted": [], "stun_until": -1, "ability_used_turn": -1}
	e.state.players[1].board[1] = {"cards": ["firepup"], "berries": [], "exhausted": [], "stun_until": -1, "ability_used_turn": -1}
	e.state_changed.emit()
	await process_frame
	await process_frame
	var pay := [{"src": "attached", "slot": 0, "index": 0}, {"src": "attached", "slot": 0, "index": 1}, {"src": "attached", "slot": 0, "index": 2}]
	var fails := 0
	screen._submit({"type": "play_spell", "hand": 0, "payment": pay, "params": {"target": {"player": 1, "slot": 0}}})
	await process_frame
	await process_frame
	var engine_count: int = e.state.players[1].board.filter(func(c): return c != null).size()
	var shown_during: int = screen._opp_board.get_child_count()
	print("engine creatures=%d, shown during the animation=%d" % [engine_count, shown_during])
	if engine_count != 1 or shown_during != 2:
		fails += 1
	await create_timer(3.8).timeout
	var shown_after: int = screen._opp_board.get_child_count()
	print("shown after the animation=%d" % shown_after)
	if shown_after != 1:
		fails += 1
	quit(fails)
