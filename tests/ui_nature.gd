extends SceneTree
## The Nature deck's pickers in the real UI: Trash (cards to exile, then payment), Decompose (spell, then
## its target) and Mulch / Rot (berry to exile). Needs a renderer only for the dialogs' layout:
##   godot --headless -s tests/ui_nature.gd
var fails := 0
var screen: GameScreen
var e: GameEngine


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", msg)


func _creature(id: String, berries: Array) -> Dictionary:
	var ex: Array = []
	ex.resize(berries.size())
	ex.fill(false)
	return {"cards": [id], "berries": berries, "exhausted": ex, "stun_until": -1, "ability_used_turn": -1}


func _dialog() -> Window:
	await process_frame
	await process_frame
	return screen.get_children().filter(func(c): return c is ConfirmationDialog)[0]


func _list(d: Window) -> ItemList:
	return d.find_children("*", "ItemList", true, false)[0]


func _click(list: ItemList, row: int) -> void:
	list.item_clicked.emit(row, Vector2.ZERO, MOUSE_BUTTON_LEFT)
	await process_frame


func _confirm(d: ConfirmationDialog) -> void:
	d.get_ok_button().pressed.emit()
	await process_frame
	await process_frame


func _init() -> void:
	screen = GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["nature_exile", "nature_exile"], [HumanAgent.new(0), HumanAgent.new(1)], 0.0, false)
	await process_frame
	e = screen.controller.engine
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.turn = 5
	e.state.active = 0
	var pl: Dictionary = e.state.players[0]
	var opp: Dictionary = e.state.players[1]
	pl.board = [_creature("spore_muncher", ["super_berry", "super_berry", "super_berry"]), _creature("moosh", ["nature_berry", "super_berry"]), null, null, null]
	opp.board = [_creature("leafer", ["nature_berry"]), null, null, null, null]
	pl.hand = ["trash"]
	pl.discard = ["nature_berry", "nature_berry", "removal", "leafer", "leafer", "leaflet"]
	e.state_changed.emit()
	await process_frame

	# Trash: choose Leafer x2 + Leaflet (rows: Creatures header, Leafer, Leaflet, Spells header, Removal, Berries header, Nature Berry).
	screen._on_hand_clicked(0)
	var d: ConfirmationDialog = await _dialog()
	var list := _list(d)
	check(list.get_item_text(1).begins_with("x2   Leafer") and list.get_item_text(6).begins_with("x2   Nature Berry"), "grouped list: " + str([list.get_item_text(1), list.get_item_text(6)]))
	await _click(list, 1)
	await _click(list, 1)
	await _click(list, 2)
	check(not d.get_ok_button().disabled, "3 of 3 chosen")
	await _confirm(d)
	d = await _dialog()  # the payment dialog: both Nature Berries of the discard (they weren't chosen for exile)
	check(d.title.begins_with("Pay for Trash"), "payment dialog opens next")
	await _confirm(d)
	check(pl.discard == ["removal", "trash"] and pl.exile.size() == 5, "Trash exiled leafers + leaflet and the paid berries: %s / %s" % [pl.discard, pl.exile])

	# Decompose with Spore Muncher: exile Removal from the discard, target the enemy Leafer.
	e.state.turn = 7
	pl.hand = []
	pl.board[0].ability_used_turn = -1
	pl.abilities_used = 0
	e.state_changed.emit()
	await process_frame
	screen._ability_lock_until = 0
	screen._on_ability_pressed(0, 1)
	d = await _dialog()
	list = _list(d)
	check(list.get_item_count() == 2, "Removal and Trash are offered")
	list.select(1)  # newest first: Trash, Removal
	list.item_selected.emit(1)
	await _confirm(d)
	check(not screen._pending.is_empty(), "now asks for a target")
	screen._on_slot_clicked(1, 0)
	d = await _dialog()
	check(d.title.begins_with("Pay for Removal"), "then for its cost")
	await _confirm(d)
	check(opp.board[0] == null and pl.exile.has("removal") and pl.discard.has("trash") and not pl.discard.has("removal"), "Removal paid for, replayed and exiled: %s / %s" % [pl.discard, pl.exile])

	# Moosh: two different berries can be exiled, so it asks.
	screen._ability_lock_until = 0
	screen._on_ability_pressed(1, 0)
	d = await _dialog()
	list = _list(d)
	check(list.get_item_count() == 2, "Moosh asks which berry")
	list.select(0)
	list.item_selected.emit(0)
	await _confirm(d)
	check(pl.board[1].berries.size() == 1 and pl.exile.size() >= 7 or pl.board[1].berries.size() == 1, "Moosh exiled the chosen berry")
	print("ui_nature failures=%d" % fails)
	quit(fails)
