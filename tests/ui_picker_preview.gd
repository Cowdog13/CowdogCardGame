extends SceneTree
## Every list picker (swap, payment, recycle, reinforce) shows a big card on hover. Needs a display:
##   xvfb-run godot --rendering-driver opengl3 -s tests/ui_picker_preview.gd -- [screenshot_dir]
func _init() -> void:
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["crashing_wave", "scorching_fire"], [HumanAgent.new(0), HumanAgent.new(0)], 0.0, false)
	await process_frame
	var e: GameEngine = screen.controller.engine
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	var pl: Dictionary = e.state.players[0]
	pl.hand = ["water_binder", "water_ruler"]
	pl.discard = ["water_spirit", "water_berry", "water_sprite"]
	pl.board[0] = {"cards": ["water_spirit"], "berries": ["water_berry", "super_berry"], "exhausted": [false, false], "stun_until": -1, "ability_used_turn": -1}
	e.state.active = 0
	e.state.turn = 5
	e.state_changed.emit()
	await process_frame
	var fails := 0
	var args := OS.get_cmdline_user_args()
	var cases := [
		["swap", func(): screen._on_swap(), "water_ruler", 1],
		["payment", func(): screen._choose_payment(CardDB.card("removal"), func(_p): pass), "super_berry", 1],
		["recycle", func(): screen._ask_recycle(1), "water_spirit", 2],
	]
	for case in cases:
		case[1].call()
		await process_frame
		await process_frame
		var d: Window = screen.get_children().filter(func(c): return c is Window)[0]
		var list: ItemList = d.find_children("*", "ItemList", true, false)[0]
		var holders := d.find_children("Preview", "Control", true, false)
		if holders.is_empty():
			print(case[0], ": no preview")
			fails += 1
		else:
			var idx: int = case[3]
			var pos := list.get_global_rect().position + list.get_item_rect(idx).get_center()
			var ev := InputEventMouseMotion.new()
			ev.position = pos
			ev.global_position = pos
			Input.warp_mouse(Vector2(d.position) + pos)
			await process_frame
			await process_frame
			var shown := ""
			if holders[0].get_child_count() > 0:
				shown = (holders[0].get_child(0) as CardView).card_id
			print(case[0], " hovered -> ", shown)
			if shown != case[2]:
				fails += 1
			if args.size() > 0:
				root.get_texture().get_image().save_png("%s/picker_%s.png" % [args[0], case[0]])
		screen.remove_child(d)
		d.free()
		screen._recycle_open = false
		await process_frame
	quit(fails)
