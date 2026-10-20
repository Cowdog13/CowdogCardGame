extends SceneTree
## End Turn flashes only when nothing else can be done:  godot --headless -s tests/ui_end_flash.gd
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
	var pl: Dictionary = e.state.players[0]
	var fails := 0
	var cases := [
		["a playable hand", ["firespore", "fire_berry"], false, true],
		["a berry but no creature", ["fire_berry"], false, false],
		["only a Tier 3 card", ["fireking"], false, false],
		["an unaffordable spell", ["removal"], false, false],
	]
	for c in cases:
		pl.hand = c[1]
		pl.board = [null, null, null, null, null]
		pl.discard = []
		e.state_changed.emit()
		await process_frame
		var has_move: bool = Rules.has_move(screen.controller.get_view(0))
		print(c[0], " -> has_move=", has_move)
		if has_move != c[3]:
			fails += 1
	pl.hand = []
	e.state_changed.emit()
	await create_timer(0.9).timeout
	if screen._end_flash == null:
		print("no flashing with nothing to do")
		fails += 1
	pl.hand = ["firespore"]
	e.state_changed.emit()
	await create_timer(0.9).timeout
	if screen._end_flash != null:
		print("still flashing with a move available")
		fails += 1
	# Swap is the only move left: both buttons flash.
	pl.hand = ["fireking"]
	pl.discard = ["firespore"]
	e.state_changed.emit()
	await create_timer(0.9).timeout
	if screen._end_flash == null or not screen._swap_flash:
		print("End Turn and Swap should both flash when swapping is the only move")
		fails += 1
	pl.hand = ["fireking", "firespore"]  # a creature to play as well: nothing flashes
	e.state_changed.emit()
	await create_timer(0.9).timeout
	if screen._end_flash != null:
		print("flashing although a creature can be played")
		fails += 1
	print("end_flash failures=%d" % fails)
	quit(fails)
