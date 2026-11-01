extends SceneTree
## Replays a game report a tester sent in and prints the game, turn by turn.
##   godot --headless -s tools/replay_report.gd -- path/to/report.json
## The report's build must match this checkout's data (the card text may have changed since).
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: godot --headless -s tools/replay_report.gd -- report.json")
		quit(2)
		return
	var report = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not report is Dictionary:
		print("not a game report: ", args[0])
		quit(2)
		return
	print("report from build %s (this checkout: %s), %s, saved %s" % [report.get("build", "?"), BuildInfo.fingerprint(), report.get("kind", "?"), report.get("saved", "?")])
	if not report.has("actions"):
		print("This report has no actions (it comes from a joined player). Their log:")
		for line in report.get("log", []):
			print("  ", line)
		quit()
		return
	var e := GameReport.replay(report)
	print("decks %s, seed %s, %d actions" % [report.decks, report.seed, report.actions.size()])
	for ev in e.log:
		print("  ", ev.text if ev is Dictionary else ev)
	var result: Dictionary = report.get("result", {})
	var same: bool = int(result.get("winner", -2)) == e.state.winner and int(result.get("turns", -2)) == e.state.turn
	print("replay result: winner %d after %d turns; the report says winner %s after %s turns -> %s" % [e.state.winner, e.state.turn, result.get("winner"), result.get("turns"), "identical" if same else "DIFFERENT (different build?)"])
	quit(0 if same else 1)
