extends SceneTree
## Light deck pickers in the UI: Search (deck list), Gather (player, payment) and the empty-deck warning.
##   godot --headless -s tests/ui_light.gd
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
	await process_frame
	await process_frame
	return screen.get_children().filter(func(c): return c is ConfirmationDialog and not c.is_queued_for_deletion())[0]


func _pick(d: ConfirmationDialog, row: int) -> void:
	var list: ItemList = d.find_children("*", "ItemList", true, false)[0]
	list.select(row)
	list.item_selected.emit(row)
	d.get_ok_button().pressed.emit()
	await process_frame
	await process_frame


func _init() -> void:
	screen = GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["light", "light"], [HumanAgent.new(0), HumanAgent.new(1)], 0.0, false)
	await process_frame
	var e: GameEngine = screen.controller.engine
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.turn = 5
	e.state.active = 0
	var pl: Dictionary = e.state.players[0]
	pl.board = [_creature("lighttable", ["super_berry", "super_berry"]), _creature("lightling", ["super_berry", "light_berry"]), null, null, null]
	pl.hand = ["gather"]
	pl.deck = ["lightling", "lightling", "removal", "lightor", "light_berry"]
	e.state_changed.emit()
	await process_frame

	# Search: rows are Creatures, Lightling x2, Lightor, Spells, Removal, Berries, Light Berry.
	screen._ability_lock_until = 0
	screen._on_ability_pressed(0, 0)
	var d := await _dialog()
	var list: ItemList = d.find_children("*", "ItemList", true, false)[0]
	check(list.get_item_text(1).begins_with("x2   Lightling"), "deck list is grouped: " + list.get_item_text(1))
	await _pick(d, 4)  # Removal
	check(pl.deck[0] == "removal" and pl.deck.size() == 5, "Search put Removal on top: %s" % [pl.deck])

	# Gather on yourself: choose the player, then pay with the two berries on Lightling.
	screen._on_hand_clicked(0)
	d = await _dialog()
	await _pick(d, 0)
	d = await _dialog()
	check(d.title.begins_with("Pay for Gather"), "then payment")
	d.get_ok_button().pressed.emit()
	await process_frame
	await process_frame
	check(pl.hand.size() == 2 and pl.deck.size() == 3, "Gather drew 2: hand %d deck %d" % [pl.hand.size(), pl.deck.size()])

	# No warning: drawing from an empty deck simply loses.
	pl.deck = []
	pl.board[1] = _creature("lighturn", ["light_berry", "light_berry"])
	e.state_changed.emit()
	await process_frame
	screen._ability_lock_until = 0
	screen._on_ability_pressed(1, 0)
	await process_frame
	check(e.is_over() and e.state.winner == 1, "using a draw ability with an empty deck loses at once")
	print("ui_light failures=%d" % fails)
	quit(fails)
