extends SceneTree
## Renders a few frames of the real game and saves PNGs (needs a display, e.g. xvfb-run):
##   xvfb-run godot --path . -s tests/screenshot.gd -- /tmp/out
func _init() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(out + "/menu.png")
	main._start_game("crashing_wave", "scorching_fire", 0.2, false)
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(out + "/mulligan.png")
	var screen: GameScreen = main._game
	screen._on_hand_clicked(0)
	screen._on_confirm()
	await create_timer(1.5).timeout
	if screen.view.active == 0:
		for i in screen.view.you.hand.size():
			if CardDB.is_creature(screen.view.you.hand[i]) and int(CardDB.card(screen.view.you.hand[i]).tier) == 1:
				screen._on_hand_clicked(i)
				screen._on_slot_clicked(0, 0)
				break
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(out + "/game.png")
	quit()
