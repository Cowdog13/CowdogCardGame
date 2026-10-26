extends SceneTree
## Loads the main scene and runs it for a while.   godot --headless -s tests/ui_smoke.gd

func _init() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.game = IdleGame.new_game()
	main.speed = 20
	for i in 400:
		await process_frame
	var fails := 0
	if main.shown_battle == null and main.game.battle != null:
		fails += 1
		print("FAIL: battle not shown")
	if main.widgets.is_empty() and main.game.battle != null:
		fails += 1
		print("FAIL: no unit widgets")
	main.game.set_active("cannonier", false)
	main.game.set_active("shurm", true)
	main._rebuild_team()
	main._set_speed(5)
	print("ui_smoke: %d failure(s), plane wave %d, vorx %d" % [fails, main.game.wave, main.game.vorx])
	quit(1 if fails > 0 else 0)
