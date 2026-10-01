extends SceneTree
## Plays each visual effect and saves screenshots mid-animation.
##   xvfb-run godot --path . --rendering-driver opengl3 -s tests/fx_demo.gd -- /tmp/out
func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["crashing_wave", "scorching_fire"], [HumanAgent.new(0), HumanAgent.new(1)], 0.0, true)
	await process_frame
	var e: GameEngine = screen.controller.engine
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.turn = 5
	e.state.active = 1
	var opp: Dictionary = e.state.players[1]
	var me: Dictionary = e.state.players[0]
	opp.hand = ["firepup", "fire_berry", "firespore"]
	me.hand = ["water_spirit", "water_berry", "removal", "disable", "water_sprite"]
	me.board[1] = {"cards": ["water_constrictor"], "berries": ["water_berry", "super_berry", "water_berry"], "exhausted": [false, false, false], "stun_until": -1, "ability_used_turn": -1}
	me.discard = ["water_berry", "water_binder", "super_berry"]
	e.state_changed.emit()
	await process_frame
	print("opp play: ", e.submit(1, {"type": "play_creature", "hand": 0, "slot": 2}))
	await create_timer(1.6).timeout
	root.get_texture().get_image().save_png(out + "/fx1_opp_center.png")
	await create_timer(1.9).timeout
	root.get_texture().get_image().save_png(out + "/fx2_opp_landing.png")
	await create_timer(0.8).timeout
	e.state.active = 0
	e.state_changed.emit()
	print("attach hand: ", e.submit(0, {"type": "attach_berry", "hand": 1, "slot": 1}))
	await create_timer(0.55).timeout
	root.get_texture().get_image().save_png(out + "/fx3_berry.png")
	await create_timer(1.5).timeout
	e.state.players[0].berry_attached = false
	print("attach discard: ", e.submit(0, {"type": "attach_berry", "from": "discard", "discard": 0, "slot": 1}))
	await create_timer(0.55).timeout
	root.get_texture().get_image().save_png(out + "/fx4_discard_berry.png")
	await create_timer(1.5).timeout
	print("spell: ", e.submit(0, {"type": "play_spell", "hand": e.state.players[0].hand.find("disable"), "payment": [{"src": "discard", "index": 1}], "params": {"targets": [{"player": 1, "slot": 2}]}}))
	await create_timer(1.2).timeout
	root.get_texture().get_image().save_png(out + "/fx5_spell.png")
	await create_timer(2.5).timeout
	print("swap: ", e.submit(0, {"type": "swap", "hand": 0, "discard": 0}))
	await create_timer(1.0).timeout
	root.get_texture().get_image().save_png(out + "/fx6_swap.png")
	await create_timer(2.5).timeout
	e.state.players[0].board[1].ability_used_turn = -1
	e.state.players[0].abilities_used = 0
	print("ability: ", e.submit(0, {"type": "use_ability", "slot": 1, "ability": 1, "params": {}}))
	await create_timer(0.8).timeout
	root.get_texture().get_image().save_png(out + "/fx7_ability.png")
	await create_timer(1.5).timeout
	print("queue empty: ", screen._fx_queue.is_empty(), " hold_ai=", screen.controller.hold_ai)
	quit()
