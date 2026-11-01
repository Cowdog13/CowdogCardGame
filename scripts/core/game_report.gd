class_name GameReport
extends RefCounted
## A saved record of one game that a tester can send in: build, decks, the random seed and every accepted action.
## Because the engine is deterministic for a seed and a list of actions, replay() rebuilds the exact game.

const VERSION := 1


## `controller` is the GameController that ran the game (null for a joined player, who only has their log).
static func build(controller: Node, my_seat: int, log_lines: Array, kind: String) -> Dictionary:
	var report := {
		"report_version": VERSION,
		"build": BuildInfo.fingerprint(),
		"kind": kind,  # "single player", "host" or "client"
		"saved": Time.get_datetime_string_from_system(),
		"my_seat": my_seat,
		"log": log_lines,
	}
	if controller is GameController:
		var e: GameEngine = controller.engine
		report["decks"] = [e.state.players[0].deck_id, e.state.players[1].deck_id]
		report["names"] = e.state.names
		report["seed"] = str(e.seed_value)  # as text: a 64-bit seed does not survive being stored as a JSON number
		report["actions"] = controller.action_log
		report["result"] = {"winner": e.state.winner, "turns": e.state.turn, "over": e.is_over()}
	return report


## Writes the report into user://reports and returns the file's path ("" if it could not be written).
static func save(report: Dictionary, prefix := "game") -> String:
	DirAccess.make_dir_recursive_absolute(Settings.REPORTS_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/%s-%s.json" % [Settings.REPORTS_DIR, prefix, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(report, "\t"))
	return path


## Plays a saved report's actions on a fresh engine; returns the engine (or null if the report has no actions).
static func replay(report: Dictionary) -> GameEngine:
	if not report.has("actions"):
		return null
	var e := GameEngine.new()
	e.setup(report.decks, str(report.seed).to_int(), report.names)
	for entry in report.actions:
		var res := e.submit(int(entry.seat), entry.action)
		if not res.ok:
			push_warning("Replay: action refused (%s): %s" % [entry, res.error])
	return e
