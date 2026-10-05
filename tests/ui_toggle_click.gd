extends SceneTree
## Payment list: a plain click toggles an item (no Ctrl needed). Needs a display:
##   xvfb-run godot --rendering-driver opengl3 -s tests/ui_toggle_click.gd -- [screenshot_dir]
func _click(list: ItemList, i: int) -> void:
	var window := list.get_window()
	var r := list.get_item_rect(i)
	var pos := list.get_global_rect().position + r.position + r.size / 2.0
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.global_position = pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		window.push_input(ev)  # the dialog is its own (embedded) viewport
		await process_frame

func _init() -> void:
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["crashing_wave", "scorching_fire"], [HumanAgent.new(0), HumanAgent.new(1)], 0.0, false)
	await process_frame
	var e: GameEngine = screen.controller.engine
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	var pl: Dictionary = e.state.players[0]
	pl.board[0] = {"cards": ["water_spirit"], "berries": ["water_berry", "water_berry"], "exhausted": [false, true], "stun_until": -1, "ability_used_turn": -1}
	pl.board[3] = {"cards": ["water_binder"], "berries": ["super_berry", "water_berry"], "exhausted": [false, false], "stun_until": -1, "ability_used_turn": -1}
	pl.discard = ["water_berry"]
	e.state_changed.emit()
	await process_frame
	screen.view = screen.controller.get_view(0)
	screen._choose_payment(CardDB.card("removal"), func(_p): pass)
	await process_frame
	await process_frame
	var d: ConfirmationDialog = screen.get_children().filter(func(c): return c is ConfirmationDialog)[0]
	var list: ItemList = d.find_children("*", "ItemList", true, false)[0]
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		root.get_texture().get_image().save_png(args[0] + "/payment_dialog.png")
	var fails := 0
	var labels: Array = []
	for i in list.item_count:
		labels.append(list.get_item_text(i))
	print(labels)
	if not labels[0].begins_with("Creature 1") or not labels[2].begins_with("Creature 4"):
		fails += 1
		print("creature numbers missing")
	list.deselect_all()
	for i in [0, 1, 2]:
		await _click(list, i)
	var n := list.get_selected_items().size()
	print("after 3 plain clicks selected=", n, " ok=", d.get_ok_button().text)
	if n != 3:
		fails += 1
	await _click(list, 1)
	print("after clicking item 1 again selected=", list.get_selected_items().size())
	if list.get_selected_items().size() != 2 or list.is_selected(1):
		fails += 1
	quit(fails)
