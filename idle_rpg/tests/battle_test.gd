extends SceneTree
## Battle and progression checks.   godot --headless -s tests/battle_test.gd

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: " + msg)

func _init() -> void:
	# Armor soaks damage point for point, then health.
	var b := IdleBattle.new(1)
	var d := IdleDB.make_unit("defender", 1, 0, "front")
	var f := IdleDB.make_unit("snapfang", 1, 1, "front")
	b.add_unit(d)
	b.add_unit(f)
	d.armor = 6.0
	b._damage(f, d, 10.0, "test")
	check(d.armor == 0.0 and is_equal_approx(d.hp, d.max_hp - 4.0), "armor then hp")

	# Frontline must be targeted first; backline only once the front is gone.
	b = IdleBattle.new(2)
	var shooter := IdleDB.make_unit("cannonier", 1, 0, "back")
	var front := IdleDB.make_unit("snapfang", 1, 1, "front")
	var back := IdleDB.make_unit("wisp_shade", 1, 1, "back")
	b.add_unit(shooter)
	b.add_unit(front)
	b.add_unit(back)
	for i in 30:
		check(b._select(shooter, "enemy_random", 1)[0] == front, "random target is frontline")
		check(b._select(shooter, "enemy_back_random", 1)[0] == back, "Reaching Strike prefers backline")
	front.hp = 0.0
	check(b._select(shooter, "enemy_random", 1)[0] == back, "backline targetable after front dies")
	back.hp = 0.0
	front.hp = 5.0
	check(b._select(shooter, "enemy_back_random", 1)[0] == front, "Reaching Strike falls back to front")

	# Overkill hits two different targets when two exist.
	b = IdleBattle.new(3)
	var c := IdleDB.make_unit("cannonier", 1, 0, "back")
	var e1 := IdleDB.make_unit("snapfang", 1, 1, "front")
	var e2 := IdleDB.make_unit("snapfang", 1, 1, "front")
	b.add_unit(c)
	b.add_unit(e1)
	b.add_unit(e2)
	for i in 20:
		var t := b._select(c, "enemy_random", 2)
		check(t.size() == 2 and t[0] != t[1], "overkill picks two different targets")

	# Heal goes to lowest health ratio; Spore Spreader boosts the next heal by 50% once.
	b = IdleBattle.new(4)
	var shurm := IdleDB.make_unit("shurm", 1, 0, "back")
	var tank := IdleDB.make_unit("defender", 1, 0, "front")
	b.add_unit(shurm)
	b.add_unit(tank)
	b.add_unit(IdleDB.make_unit("snapfang", 1, 1, "front"))
	tank.hp = 10.0
	check(b._select(shurm, "ally_lowest", 1)[0] == tank, "heal targets lowest health")
	tank.heal_amp = 0.5
	b._heal(shurm, tank, 10.0, "t")
	check(is_equal_approx(tank.hp, 25.0) and tank.heal_amp == 0.0, "amp boosts next heal only")
	b._heal(shurm, tank, 10.0, "t")
	check(is_equal_approx(tank.hp, 35.0), "second heal is normal")

	# Station only covers Defender's row.
	var st := IdleDB.make_unit("defender", 1, 0, "front")
	b = IdleBattle.new(5)
	b.add_unit(st)
	var back_ally := IdleDB.make_unit("shurm", 1, 0, "back")
	b.add_unit(back_ally)
	b.add_unit(IdleDB.make_unit("snapfang", 1, 1, "front"))
	var sel := b._select(st, "allies_same_row", 1)
	check(sel.size() == 1 and sel[0] == st, "Station hits same row only")

	# Timeline: Barrage locks after 1s startup and lands after 2s more.
	b = IdleBattle.new(6)
	var cn := IdleDB.make_unit("cannonier", 1, 0, "back", [0])
	var dummy := IdleDB.make_unit("burrowhound", 1, 1, "front")
	dummy.plan = [0]
	dummy.abilities = [{"id": "x", "name": "Idle", "effect": "armor", "target": "self", "power": "small", "startup": 99.0, "resolve": 0.0, "cooldown": 0.0}]
	b.add_unit(cn)
	b.add_unit(dummy)
	for i in 29:
		b.advance(0.1)
	check(dummy.hp == dummy.max_hp, "Barrage has not landed at 2.9s")
	for i in 3:
		b.advance(0.1)
	check(dummy.hp < dummy.max_hp, "Barrage lands at 3s")

	# Energy and slot limits.
	var g := IdleGame.new_game()
	check(g.energy_used() == 8, "starting team uses 8 energy")
	check(not g.set_active("shurm", true), "cannot exceed 10 energy")
	g.set_active("cannonier", false)
	check(g.set_active("shurm", true) and g.energy_used() == 7, "swap in Shurm")
	for i in 25:
		g.add_to_plan("shurm", 0)
	check(g.owned.shurm.plan.size() == IdleGame.MAX_PLAN_SLOTS, "plan capped at 20")

	# Equipment: one item, one holder.
	g.unlock_equipment("sharpened_stone")
	g.equip("shurm", "sharpened_stone")
	g.equip("defender", "sharpened_stone")
	check(g.owned.shurm.equipment == "" and g.owned.defender.equipment == "sharpened_stone", "equipment moves between holders")
	g.equip("shurm", "ember_core")
	check(g.owned.shurm.equipment == "", "cannot equip a locked item")

	# Idle loop: the starting team can clear plane 1 and get XP and the first-clear item.
	var game := IdleGame.new_game()
	game.rng.seed = 7
	game.advance(600.0)
	check(game.cleared.has("whispering_meadow"), "plane 1 cleared by starting team (result %s, wave %d)" % [game.last_result, game.wave])
	check(game.owned.defender.level > 1, "defender levelled")
	check(game.equipment_owned.has("wooden_buckler"), "first clear unlocks equipment")
	check(game.owned.shurm.level == 1, "benched Dreamshape earns no XP")

	# Save round trip.
	var copy := IdleGame.from_dict(JSON.parse_string(JSON.stringify(game.to_dict())))
	check(copy.owned.defender.level == game.owned.defender.level and copy.cleared == game.cleared, "save round trip")

	print("battle_test: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
