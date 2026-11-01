extends SceneTree
## Room-code lobby screens against a local relay (needs a display):
##   xvfb-run godot --rendering-driver opengl3 -s tests/ui_relay.gd -- /tmp/out
func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var relay := RelayServer.new()
	relay.verbose = false
	root.add_child(relay)
	relay.start(24992)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	main._show_multiplayer()
	await create_timer(0.3).timeout
	var lobby: MultiplayerMenu = main._menu
	lobby._show_mode(true)
	lobby._relay_addr.text = "127.0.0.1:24992"
	await create_timer(0.2).timeout
	root.get_texture().get_image().save_png(out + "/mp_relay_host_form.png")
	lobby._on_host_pressed()
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(out + "/mp_relay_lobby.png")
	var ok: bool = lobby._info_label.text.contains("room code") and lobby._best_address.length() == 5
	print("host lobby shows a room code: ", ok, " ", lobby._best_address)
	main._leave_net()
	relay.stop()
	quit(0 if ok else 1)
