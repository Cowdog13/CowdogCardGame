extends SceneTree
## Hovering a card in a discard/exile list shows it big next to the list. Needs a display:
##   xvfb-run godot --rendering-driver opengl3 -s tests/ui_pile_hover.gd -- [screenshot_dir]
func _init() -> void:
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["crashing_wave", "scorching_fire"], [HumanAgent.new(0), HumanAgent.new(1)], 0.0, false)
	await process_frame
	var e: GameEngine = screen.controller.engine
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.players[1].exile = ["fireking", "super_berry", "removal"]
	e.state.players[0].discard = ["water_berry", "water_ruler", "disable"]
	e.state_changed.emit()
	await process_frame
	var fails := 0
	for case in [[0, "discard", "water_ruler"], [1, "exile", "super_berry"]]:
		screen._view_pile(case[0], case[1])
		await process_frame
		await process_frame
		var d: Window = screen.get_children().filter(func(c): return c is AcceptDialog)[0]
		var list: ItemList = d.find_children("*", "ItemList", true, false)[0]
		var holder: Control = d.find_children("Preview", "Control", true, false)[0]
		var idx := 1  # newest first: ["disable", "water_ruler", "water_berry"] / ["removal", "super_berry", "fireking"]
		var pos := list.get_global_rect().position + list.get_item_rect(idx).get_center()
		var ev := InputEventMouseMotion.new()
		ev.position = pos
		ev.global_position = pos
		ev.relative = Vector2(3, 3)
		Input.warp_mouse(Vector2(d.position) + pos)  # a real pointer move; embedded dialogs get it from the root window
		await process_frame
		await process_frame
		await process_frame
		await process_frame
		var shown := ""
		if holder.get_child_count() > 0:
			shown = (holder.get_child(0) as CardView).card_id
		print(case[1], " hovered -> ", shown)
		if shown != case[2]:
			fails += 1
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			root.get_texture().get_image().save_png("%s/pile_hover_%s.png" % [args[0], case[1]])
		screen.remove_child(d)
		d.free()
		await process_frame
	quit(fails)
