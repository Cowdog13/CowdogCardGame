extends SceneTree
## Builds the lobby screens and saves screenshots (needs a display):
##   xvfb-run godot --rendering-driver opengl3 -s tests/ui_lobby.gd -- /tmp/out
func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png(out + "/mp_menu.png")
	main._show_multiplayer()
	await create_timer(0.3).timeout
	var lobby: MultiplayerMenu = main._menu
	lobby._show_mode(true)
	await create_timer(0.2).timeout
	root.get_texture().get_image().save_png(out + "/mp_host_form.png")
	lobby._upnp.button_pressed = false
	lobby._port.value = 24970
	lobby._on_host_pressed()
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png(out + "/mp_host_lobby.png")
	var ok: bool = lobby._players_label.text.contains("Player") and lobby._info_label.text.contains("24970")
	print("lobby shows the player and the address: ", ok)
	main._leave_net()
	quit(0 if ok else 1)
