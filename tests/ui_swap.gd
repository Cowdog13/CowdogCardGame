extends SceneTree
## The Swap button: choose the creature to take, then the N cards to give.   godot --headless -s tests/ui_swap.gd
var fails := 0
var screen: GameScreen


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)


func _dialog() -> ConfirmationDialog:
	await process_frame
	await process_frame
	return screen.get_children().filter(func(c): return c is ConfirmationDialog and not c.is_queued_for_deletion())[0]


func _init() -> void:
	screen = GameScreen.new()
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
	pl.hand = ["removal", "fire_berry", "fire_berry", "firepup"]
	pl.discard = ["fireking", "firespore", "fire_berry"]
	pl.swaps_made = 1  # the second swap costs 2 cards
	e.state_changed.emit()
	await process_frame
	check(screen._swap_btn.text == "Swap (2)", "the button shows the cost: " + screen._swap_btn.text)
	screen._on_swap()
	var d := await _dialog()
	var list: ItemList = d.find_children("*", "ItemList", true, false)[0]
	check(list.item_count == 3 and list.get_item_text(1).begins_with("x1   Firespore"), "only creatures of the discard are offered, by evolution line")
	list.select(2)  # Fireking (Firespore's line: Firespore, Fireking)
	list.item_selected.emit(2)
	d.get_ok_button().pressed.emit()
	d = await _dialog()
	check(d.title.contains("choose 2"), "then asks for 2 cards: " + d.title)
	list = d.find_children("*", "ItemList", true, false)[0]
	# rows: Creatures hdr, Firepup, Spells hdr, Removal, Berries hdr, Fire Berry x2
	for row in [1, 3]:
		list.item_clicked.emit(row, Vector2.ZERO, MOUSE_BUTTON_LEFT)
		await process_frame
	check(not d.get_ok_button().disabled, "2 of 2 chosen")
	d.get_ok_button().pressed.emit()
	await process_frame
	await process_frame
	check(pl.hand.has("fireking") and pl.hand.size() == 3 and pl.discard.has("firepup") and pl.discard.has("removal") and pl.swaps_made == 2, "swapped: hand %s discard %s" % [pl.hand, pl.discard])
	check(screen._swap_btn.disabled, "no second swap this turn")
	print("ui_swap failures=%d" % fails)
	quit(fails)
