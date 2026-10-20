extends SceneTree
## Recycle order dialog: identical cards are grouped, each click numbers one more copy. Needs a display:
##   xvfb-run godot --rendering-driver opengl3 -s tests/ui_order_pick.gd -- [screenshot_dir]
func _click(list: ItemList, i: int, button := MOUSE_BUTTON_LEFT) -> void:
	var pos := list.get_global_rect().position + list.get_item_rect(i).get_center()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.global_position = pos
		ev.button_index = button
		ev.pressed = pressed
		list.get_window().push_input(ev)
		await process_frame


func _texts(list: ItemList) -> Array:
	var texts: Array = []
	for i in list.item_count:
		texts.append(list.get_item_text(i).strip_edges())
	return texts


func _init() -> void:
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["scorching_fire", "crashing_wave"], [HumanAgent.new(0), HumanAgent.new(1)], 0.0, false)
	await process_frame
	var ids := ["firespore", "firespore", "removal", "firepup"]
	var got: Array = []
	screen._ordered_pick("Recycle test", ids, 4, [], "Recycle", func(picked): got.assign(picked), Callable())
	await process_frame
	await process_frame
	var d: ConfirmationDialog = screen.get_children().filter(func(c): return c is ConfirmationDialog)[0]
	var list: ItemList = d.find_children("*", "ItemList", true, false)[0]
	var fails := 0
	# rows: 0 Creatures header, 1 Firepup, 2 Firespore x2, 3 Spells header, 4 Removal
	for i in [2, 2, 4, 1]:
		await _click(list, i)
	var texts := _texts(list)
	print(texts, " ok disabled=", d.get_ok_button().disabled)
	if texts != ["- Creatures (3) -", "x1   Firepup      > 4", "x2   Firespore      > 1, 2", "- Spells (1) -", "x1   Removal      > 3"] or d.get_ok_button().disabled:
		fails += 1
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		root.get_texture().get_image().save_png(args[0] + "/order_pick.png")
	await _click(list, 2)  # every copy numbered: a click removes the last number (2)
	print(_texts(list))
	if _texts(list)[2] != "x2   Firespore      > 1" or not d.get_ok_button().disabled:
		fails += 1
	await _click(list, 1, MOUSE_BUTTON_RIGHT)  # right-click removes Firepup's number
	if _texts(list)[1] != "x1   Firepup" or _texts(list)[4] != "x1   Removal      > 2":
		fails += 1
	await _click(list, 2)
	await _click(list, 1)
	d.get_ok_button().pressed.emit()
	await process_frame
	print("result=", got)
	if got != [1, 2, 0, 3]:  # order is firespore (newest copy), removal, firespore, firepup
		fails += 1
	print("order_pick failures=%d" % fails)
	quit(fails)
