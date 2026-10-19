extends SceneTree
## Builds a mid-game table and saves a screenshot (needs a display):
##   xvfb-run godot --rendering-driver opengl3 -s tests/ui_look.gd -- /tmp/out
func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png(out + "/look_menu.png")
	main._start_game("crashing_wave", "scorching_fire", 0.0, false)
	await process_frame
	var screen: GameScreen = main._game
	var e: GameEngine = screen.controller.engine
	for p in 2:
		e.submit(p, {"type": "mulligan", "cards": []})
	e.state.turn = 5
	e.state.active = 0
	var me: Dictionary = e.state.players[0]
	var opp: Dictionary = e.state.players[1]
	me.hand = ["water_binder", "water_berry", "super_berry", "removal", "water_spirit", "disable", "water_sprite"]
	me.board[0] = {"cards": ["water_constrictor", "water_binder"], "berries": ["water_berry", "super_berry", "water_berry", "water_berry"], "exhausted": [false, true, false, false], "stun_until": -1, "ability_used_turn": -1}
	me.board[1] = {"cards": ["water_spirit", "water_sprite", "water_ruler"], "berries": ["water_berry", "water_berry", "super_berry", "water_berry", "water_berry", "super_berry"], "exhausted": [false, false, false, false, true, false], "stun_until": -1, "ability_used_turn": -1}
	me.board[2] = {"cards": ["water_crash"], "berries": ["super_berry"], "exhausted": [false], "stun_until": -1, "ability_used_turn": -1}
	opp.board[0] = {"cards": ["firepup", "firewolf"], "berries": ["fire_berry", "super_berry", "super_berry"], "exhausted": [false, false, false], "stun_until": 99, "ability_used_turn": -1}
	opp.board[1] = {"cards": ["firespore"], "berries": ["fire_berry"], "exhausted": [false], "stun_until": -1, "ability_used_turn": -1}
	opp.board[2] = {"cards": ["fire_famine"], "berries": [], "exhausted": [], "stun_until": -1, "ability_used_turn": -1}
	me.discard = ["water_berry", "water_binder", "removal"]
	me.exile = ["super_berry"]
	opp.discard = ["fireking", "fire_berry"]
	e.state_changed.emit()
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png(out + "/look_table.png")
	screen._show_creature_detail(me.board[1])
	await create_timer(0.2).timeout
	root.get_texture().get_image().save_png(out + "/look_preview.png")
	quit()
