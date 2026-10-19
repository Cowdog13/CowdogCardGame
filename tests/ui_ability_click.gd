extends SceneTree
## Clicking an ability box on one of your board cards uses that ability. Needs a display:
##   xvfb-run godot --rendering-driver opengl3 -s tests/ui_ability_click.gd
func _init() -> void:
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["scorching_fire", "crashing_wave"], [HumanAgent.new(0), HumanAgent.new(1)], 0.0, false)
	await process_frame
	var e: GameEngine = screen.controller.engine
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.turn = 5
	e.state.active = 0
	var me: Dictionary = e.state.players[0]
	me.board[0] = {"cards": ["firespore"], "berries": ["fire_berry"], "exhausted": [false], "stun_until": -1, "ability_used_turn": -1}
	e.state_changed.emit()
	await process_frame
	await process_frame
	screen._ability_lock_until = 0
	var before: int = e.state.players[1].deck.size()
	var widget: BoardCreature = screen._my_board.get_child(0)
	var rect := widget.ability_rect(0)
	var pos := rect.get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.global_position = pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		root.push_input(ev)
		await process_frame
	var after: int = e.state.players[1].deck.size()
	print("opponent deck %d -> %d" % [before, after])
	quit(0 if after == before - 2 else 1)
