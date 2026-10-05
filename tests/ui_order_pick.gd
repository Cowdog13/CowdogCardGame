extends SceneTree
## Recycle order dialog: clicking cards numbers them in click order. Needs a display:
##   xvfb-run godot --rendering-driver opengl3 -s tests/ui_order_pick.gd -- [screenshot_dir]
func _click(list: ItemList, i: int) -> void:
	var pos := list.get_global_rect().position + list.get_item_rect(i).get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.global_position = pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		list.get_window().push_input(ev)
		await process_frame

func _init() -> void:
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["scorching_fire", "crashing_wave"], [HumanAgent.new(0), HumanAgent.new(1)], 0.0, false)
	await process_frame
	var ids := ["removal", "firespore", "firepup"]
	var got: Array = []
	screen._ordered_pick("Recycle test", ids.map(func(id): return CardDB.card_name(id)), 3, [], "Recycle",
		func(picked): got.assign(picked), Callable(), ids)
	await process_frame
	await process_frame
	var d: ConfirmationDialog = screen.get_children().filter(func(c): return c is ConfirmationDialog)[0]
	var list: ItemList = d.find_children("*", "ItemList", true, false)[0]
	var fails := 0
	for i in [2, 0, 1]:
		await _click(list, i)
	var texts: Array = []
	for i in list.item_count:
		texts.append(list.get_item_text(i).strip_edges())
	print(texts, " ok=", d.get_ok_button().text, " disabled=", d.get_ok_button().disabled)
	if texts != ["2.  Removal", "3.  Firespore", "1.  Firepup"] and texts != ["2.  Removal", "3.  Firespore", "1.  Firepup"]:
		fails += 1
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		root.get_texture().get_image().save_png(args[0] + "/order_pick.png")
	await _click(list, 0)  # removes number 2: Firespore becomes 2
	print(list.get_item_text(1).strip_edges(), " ok disabled=", d.get_ok_button().disabled)
	if not d.get_ok_button().disabled or list.get_item_text(1).strip_edges() != "2.  Firespore":
		fails += 1
	await _click(list, 0)  # numbered again as 3
	d.get_ok_button().pressed.emit()
	await process_frame
	print("result=", got)
	if got != [2, 1, 0]:
		fails += 1
	quit(fails)
