extends SceneTree
## Finishing a game saves a replayable report, and the Log window can save one on demand.   godot --headless -s tests/ui_report.gd
func _newest() -> String:
	var best := ""
	var best_time := 0
	for f in DirAccess.get_files_at(Settings.REPORTS_DIR):
		var t := FileAccess.get_modified_time("%s/%s" % [Settings.REPORTS_DIR, f])
		if t >= best_time:
			best_time = t
			best = "%s/%s" % [Settings.REPORTS_DIR, f]
	return best


func _init() -> void:
	var fails := 0
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["light", "nature_exile"], [HumanAgent.new(0), AIAgent.new(1)], 0.0, false)
	await process_frame
	var e: GameEngine = screen.controller.engine
	e.submit(0, {"type": "mulligan", "cards": []})
	await create_timer(0.3).timeout
	var mid := screen.save_report()
	if mid == "" or not FileAccess.file_exists(mid):
		fails += 1
		print("no mid-game report")
	screen.controller.submit(0, {"type": "concede"})
	await create_timer(0.5).timeout
	var path := _newest()
	var report = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not report is Dictionary or report.get("build", "") != BuildInfo.fingerprint() or report.kind != "single player":
		fails += 1
		print("bad report: ", path)
	else:
		var replayed := GameReport.replay(report)
		if replayed == null or not replayed.is_over() or replayed.state.winner != 1:
			fails += 1
			print("the saved report does not replay to the same result")
		if report.actions.back().action.type != "concede":
			fails += 1
			print("the game-ending action is missing from the report")
	var dialogs := screen.get_children().filter(func(c): return c is AcceptDialog)
	if dialogs.is_empty() or not "report" in dialogs[0].dialog_text:
		fails += 1
		print("the game over window does not mention the report")
	print("ui_report failures=%d" % fails)
	quit(fails)
