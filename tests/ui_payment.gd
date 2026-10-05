extends SceneTree
## Spell payment dialog: preselects the cheapest payment, lets the player change it.
##   godot --headless -s tests/ui_payment.gd
func _init() -> void:
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.start(["scorching_fire", "crashing_wave"], [HumanAgent.new(0), HumanAgent.new(1)], 0.0, false)
	await process_frame
	var e: GameEngine = screen.controller.engine
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	var me: int = e.state.active
	var pl: Dictionary = e.state.players[me]
	pl.hand = ["disable"]
	pl.board[0] = {"cards": ["firespore"], "berries": ["fire_berry", "super_berry"], "exhausted": [true, false], "stun_until": -1, "ability_used_turn": -1}
	e.state.players[1 - me].board[0] = {"cards": ["water_spirit"], "berries": [], "exhausted": [], "stun_until": -1, "ability_used_turn": -1}
	e.state_changed.emit()
	screen.view = screen.controller.get_view(me)
	screen.set("view", screen.view)
	var fails := 0
	# Seat 0 may not be the active seat; drive the dialog directly against that seat's view.
	var spell := CardDB.card("disable")
	var got: Array = []
	screen._choose_payment(spell, func(pay): got.assign(pay))
	var d: ConfirmationDialog = screen.get_children().filter(func(c): return c is ConfirmationDialog)[0]
	var list: ItemList = d.find_children("*", "ItemList", true, false)[0]
	print("items=%d selected=%s ok=%s" % [list.item_count, list.get_selected_items(), d.get_ok_button().text])
	if list.item_count != 2:
		fails += 1
	list.deselect_all()
	list.select(1, false)  # choose the Super Berry manually
	list.multi_selected.emit(1, true)
	d.get_ok_button().pressed.emit()
	await process_frame
	print("payment=%s" % [got])
	if got.size() != 1 or int(got[0].index) != 1:
		fails += 1
	quit(fails)
