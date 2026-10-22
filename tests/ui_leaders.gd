extends SceneTree
## Leader abilities in the UI: Water Essence' stun target, Sun God's cards back from the hand.  godot --headless -s tests/ui_leaders.gd
var fails := 0
var screen: GameScreen


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)


func _creature(id: String, berries: Array) -> Dictionary:
	var ex: Array = []
	ex.resize(berries.size())
	ex.fill(false)
	return {"cards": [id], "berries": berries, "exhausted": ex, "stun_until": -1, "ability_used_turn": -1}


func _dialog() -> ConfirmationDialog:
	for i in 120:  # the recycle choice opens once the table has finished its effects
		await process_frame
		var found := screen.get_children().filter(func(c): return c is ConfirmationDialog and not c.is_queued_for_deletion())
		if not found.is_empty():
			return found[0]
	return null


func _init() -> void:
	screen = GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["crashing_wave", "light"], [HumanAgent.new(0), HumanAgent.new(1)], 0.0, false)
	await process_frame
	var e: GameEngine = screen.controller.engine
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.turn = 6
	e.state.active = 0
	var pl: Dictionary = e.state.players[0]
	pl.board = [_creature("water_essence", ["super_berry", "super_berry"]), _creature("water_spirit", []), null, null, null]
	pl.board[1].stun_until = 6
	e.state.players[1].deck = []
	for i in 20:
		e.state.players[1].deck.append("lightling")  # no Super Berry to steal, which would ask where to put it
	var deck_before: int = e.state.players[1].deck.size()
	e.state_changed.emit()
	await process_frame
	screen._ability_lock_until = 0
	screen._on_ability_pressed(0, 0)
	check(not screen._pending.is_empty(), "asks which stunned creature to free")
	screen._on_slot_clicked(0, 0)  # the leader itself isn't stunned: not a valid target
	check(pl.board[1].stun_until == 6, "an unstunned creature can't be picked")
	screen._on_slot_clicked(0, 1)
	await process_frame
	check(pl.board[1].stun_until == -1 and e.state.players[1].deck.size() == deck_before - 4, "stun removed, Plunder 2 berries x 2 creatures")

	# Sun God: draw 2, then choose 2 cards of the hand to put on the bottom.
	pl.board[2] = _creature("sun_god", ["super_berry", "super_berry"])
	pl.hand = ["removal"]
	pl.deck = ["gather", "lightling", "lighturn", "lightium"]
	e.state_changed.emit()
	await process_frame
	screen._ability_lock_until = 0
	screen._on_ability_pressed(2, 0)
	var d := await _dialog()
	check(d.title.contains("from your hand") and pl.hand.size() == 3, "asks for cards from the hand after drawing: " + d.title)
	var list: ItemList = d.find_children("*", "ItemList", true, false)[0]
	check(list.item_count >= 3, "the hand is listed")
	d.get_ok_button().pressed.emit()  # the suggested cards
	await process_frame
	await process_frame
	check(pl.hand.size() == 1 and pl.deck.size() == 4 and e.state.pending.is_empty(), "two cards went back: hand %s" % [pl.hand])
	print("ui_leaders failures=%d" % fails)
	quit(fails)
