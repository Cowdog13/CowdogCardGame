extends SceneTree
## Prints how the starting team progresses.   godot --headless -s tests/balance_sim.gd

func _init() -> void:
	var g := IdleGame.new_game()
	g.rng.seed = 7
	var shown := 0
	for minute in 60:
		g.advance(60.0)
		if minute % 5 == 4:
			print("min %2d plane %s wave %d result %s lv D%d C%d vorx %d cleared %s" % [minute + 1, g.plane_id, g.wave, g.last_result, g.owned.defender.level, g.owned.cannonier.level, g.vorx, g.cleared])
		for n in g.notices:
			if shown < 15:
				print("   ", n)
				shown += 1
		g.notices.clear()
	quit()
