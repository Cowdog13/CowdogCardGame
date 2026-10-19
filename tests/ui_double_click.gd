extends SceneTree
## A click right after another action can't use a creature's ability by accident.
##   godot --headless -s tests/ui_double_click.gd
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
	me.hand = ["fire_berry"]
	me.board[0] = {"cards": ["firespore"], "berries": ["fire_berry"], "exhausted": [false], "stun_until": -1, "ability_used_turn": -1}
	e.state_changed.emit()
	await process_frame
	await process_frame
	var fails := 0
	screen._on_hand_clicked(0)  # one creature: the berry goes straight on
	screen._on_ability_pressed(0, 0)  # the "second click" of a double-click
	if me.abilities_used != 0:
		fails += 1
		print("an ability fired from a double-click")
	await create_timer(0.8).timeout
	screen._on_ability_pressed(0, 0)  # a deliberate click later works
	if me.abilities_used != 1:
		fails += 1
		print("a deliberate ability click was ignored")
	print("double_click failures=%d" % fails)
	quit(fails)
