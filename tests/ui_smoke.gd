extends SceneTree
## Headless UI smoke test: runs the real GameScreen with the AI in both seats so every
## board/hand/log refresh path executes.   godot --headless -s tests/ui_smoke.gd

func _init() -> void:
	var screen := GameScreen.new()
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.start(["scorching_fire", "crashing_wave"], [AIAgent.new(0), AIAgent.new(1)], 0.0, false)
	await create_timer(6.0).timeout
	print("phase=%s turn=%d" % [screen.view.phase, screen.view.turn])
	quit(0 if screen.view.phase in ["main", "over"] else 1)
