class_name IdleBattle
extends RefCounted
## Simulates one fight between a player side and an enemy side. Call advance(dt) with small
## steps (0.1s or less). There is no direct control: units follow their ability plans.
##
## Ability timeline: startup -> resolve -> cooldown, then the next ability in the plan starts.
## Targets are locked when startup ends; the effect lands when resolve ends (a target that died
## in between is replaced by a fresh pick using the same rule).

const TIMEOUT := 180.0
## Guards against a plan whose abilities all have zero durations looping forever.
const MIN_CYCLE := 0.1

var units: Array[BattleUnit] = []
var time := 0.0
## "" while fighting, then "won", "lost" or "timeout" (timeout counts as a loss).
var result := ""
var rng := RandomNumberGenerator.new()
var log_lines: Array[String] = []
## Short-lived records for the UI to animate: {kind, src, dst, amount}. UI clears this.
var events: Array[Dictionary] = []
## Enemies the player side has defeated so far.
var kills: Array[BattleUnit] = []


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func add_unit(u: BattleUnit) -> void:
	units.append(u)
	_begin_next_ability(u)


func living(side: int) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in units:
		if u.side == side and u.alive():
			out.append(u)
	return out


func advance(dt: float) -> void:
	if result != "":
		return
	time += dt
	for u in units:
		if u.alive():
			_update_unit(u, dt)
		if result != "":
			return
	_check_result()


func _check_result() -> void:
	if living(BattleUnit.SIDE_ENEMY).is_empty():
		result = "won"
	elif living(BattleUnit.SIDE_PLAYER).is_empty():
		result = "lost"
	elif time >= TIMEOUT:
		result = "timeout"


func _update_unit(u: BattleUnit, dt: float) -> void:
	var left := dt
	while u.alive():
		if u.phase_left > left:
			u.phase_left -= left
			return
		left -= u.phase_left
		u.phase_left = 0.0
		_finish_phase(u)


func _finish_phase(u: BattleUnit) -> void:
	match u.phase:
		"startup":
			u.locked = _select(u, u.current.target, u.current.get("hits", 1))
			_set_phase(u, "resolve", u.current.resolve)
		"resolve":
			_resolve(u)
			if u.alive():
				_set_phase(u, "cooldown", maxf(u.current.cooldown * u.cooldown_mult, MIN_CYCLE - u.current.resolve - u.current.startup * u.startup_mult))
		_:
			_begin_next_ability(u)


func _set_phase(u: BattleUnit, phase: String, length: float) -> void:
	u.phase = phase
	u.phase_left = maxf(length, 0.0)
	u.phase_total = u.phase_left


func _begin_next_ability(u: BattleUnit) -> void:
	u.current = u.abilities[u.plan[u.plan_index % u.plan.size()]]
	u.plan_index += 1
	_set_phase(u, "startup", u.current.startup * u.startup_mult)


# ---- Targeting -----------------------------------------------------------

## Enemies that may be targeted: frontline first, backline only once the front is gone.
func _targetable(side: int) -> Array[BattleUnit]:
	var all := living(side)
	var front: Array[BattleUnit] = []
	for t in all:
		if t.row == "front":
			front.append(t)
	return front if not front.is_empty() else all


func _pick(pool: Array[BattleUnit]) -> BattleUnit:
	return pool[rng.randi_range(0, pool.size() - 1)]


func _select(u: BattleUnit, rule: String, hits: int = 1) -> Array:
	var foes := 1 - u.side
	var out: Array = []
	match rule:
		"enemy_random":
			var pool := _targetable(foes)
			var remaining := pool.duplicate()
			for i in hits:
				if pool.is_empty():
					break
				if remaining.is_empty():
					remaining = pool.duplicate()
				var t := _pick(remaining)
				remaining.erase(t)
				out.append(t)
		"enemy_highest_hp":
			var best: Array[BattleUnit] = []
			for t in _targetable(foes):
				if best.is_empty() or t.hp > best[0].hp:
					best = [t]
				elif is_equal_approx(t.hp, best[0].hp):
					best.append(t)
			if not best.is_empty():
				out.append(_pick(best))
		"enemy_back_random":
			var back: Array[BattleUnit] = []
			for t in living(foes):
				if t.row == "back":
					back.append(t)
			var pool := back if not back.is_empty() else _targetable(foes)
			if not pool.is_empty():
				out.append(_pick(pool))
		"self":
			out.append(u)
		"ally_lowest":
			var lowest: Array[BattleUnit] = []
			for t in living(u.side):
				if lowest.is_empty() or t.hp_ratio() < lowest[0].hp_ratio() - 0.0001:
					lowest = [t]
				elif absf(t.hp_ratio() - lowest[0].hp_ratio()) <= 0.0001:
					lowest.append(t)
			if not lowest.is_empty():
				out.append(_pick(lowest))
		"allies_all":
			out.assign(living(u.side))
		"allies_same_row":
			for t in living(u.side):
				if t.row == u.row:
					out.append(t)
	return out


# ---- Effects -------------------------------------------------------------

func _resolve(u: BattleUnit) -> void:
	var ability := u.current
	var rule: String = ability.target
	var amount: float = IdleDB.POWER_TIERS[ability.power]
	if ability.power != "amp":
		amount *= u.power
	var targets := u.locked.duplicate()
	if rule.begins_with("enemy") or rule == "ally_lowest":
		for i in targets.size():
			if not targets[i].alive():
				var repl := _select(u, rule, 1)
				targets[i] = repl[0] if not repl.is_empty() else null
	for t in targets:
		if t == null or not t.alive():
			continue
		match ability.effect:
			"damage":
				_damage(u, t, amount, ability.name)
			"heal":
				_heal(u, t, amount, ability.name)
			"armor":
				t.armor = minf(t.max_hp, t.armor + amount)
				_note("armor", u, t, amount, "%s gains %d armor (%s)" % [t.name, roundi(amount), ability.name])
			"heal_amp":
				t.heal_amp = amount
				_note("buff", u, t, amount, "%s's next heal is boosted (%s)" % [t.name, ability.name])
	u.locked = []


func _damage(src: BattleUnit, dst: BattleUnit, amount: float, ability_name: String) -> void:
	## Armor soaks damage first, point for point.
	var soaked := minf(dst.armor, amount)
	dst.armor -= soaked
	var through := amount - soaked
	dst.hp = maxf(0.0, dst.hp - through)
	_note("damage", src, dst, amount, "%s hits %s for %d (%s)" % [src.name, dst.name, roundi(amount), ability_name])
	if not dst.alive():
		_note("death", src, dst, 0.0, "%s is defeated" % dst.name)
		if dst.side == BattleUnit.SIDE_ENEMY:
			kills.append(dst)


func _heal(src: BattleUnit, dst: BattleUnit, amount: float, ability_name: String) -> void:
	if dst.heal_amp > 0.0:
		amount *= 1.0 + dst.heal_amp
		dst.heal_amp = 0.0
	dst.hp = minf(dst.max_hp, dst.hp + amount)
	_note("heal", src, dst, amount, "%s heals %s for %d (%s)" % [src.name, dst.name, roundi(amount), ability_name])


func _note(kind: String, src: BattleUnit, dst: BattleUnit, amount: float, line: String) -> void:
	events.append({"kind": kind, "src": src, "dst": dst, "amount": amount})
	log_lines.append("%5.1fs  %s" % [time, line])
	if log_lines.size() > 200:
		log_lines.pop_front()
