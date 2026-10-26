class_name IdleGame
extends RefCounted
## Player progress plus the idle loop: waves of a Dreamplane are fought back to back, forever.
## Edits to the team, plans and equipment take effect when the next wave starts.

const MAX_ACTIVE := 5
const MAX_ENERGY := 10
const MAX_PLAN_SLOTS := 20
const BETWEEN_BATTLES := 1.5
const DROP_CHANCE := 0.03
const SAVE_PATH := "user://idle_save.json"
const OFFLINE_CAP := 2.0 * 3600.0
const STEP := 0.1

## Owned Dreamshapes: id -> {level, xp, equipment, row, active, plan}.
var owned: Dictionary = {}
var equipment_owned: Array = []
var vorx := 0
var cleared: Array = []
var plane_id := ""
var wave := 0
var battle: IdleBattle = null
var pause_left := 0.0
var last_result := ""
var rng := RandomNumberGenerator.new()
## Messages for the UI ("Shurm reached level 2"). UI clears this.
var notices: Array[String] = []


func _init() -> void:
	rng.randomize()


static func new_game() -> IdleGame:
	var g := IdleGame.new()
	for id in ["shurm", "defender", "cannonier"]:
		g.owned[id] = {"level": 1, "xp": 0, "equipment": "", "row": "front", "active": false, "plan": []}
	g.owned.cannonier.row = "back"
	g.owned.defender.active = true
	g.owned.cannonier.active = true
	g.plane_id = "whispering_meadow"
	return g


# ---- Team ---------------------------------------------------------------

func energy_of(id: String) -> int:
	return IdleDB.dreamshape(id).energy


func active_ids() -> Array:
	var out := []
	for id in owned:
		if owned[id].active:
			out.append(id)
	return out


func energy_used() -> int:
	var total := 0
	for id in active_ids():
		total += energy_of(id)
	return total


func can_activate(id: String) -> bool:
	if owned[id].active:
		return true
	return active_ids().size() < MAX_ACTIVE and energy_used() + energy_of(id) <= MAX_ENERGY


func set_active(id: String, on: bool) -> bool:
	if on and not can_activate(id):
		return false
	owned[id].active = on
	return true


func set_row(id: String, row: String) -> void:
	owned[id].row = row


## The ability order actually used: the player's plan, or every ability in order if none is set.
func effective_plan(id: String) -> Array:
	var plan: Array = owned[id].plan
	if plan.is_empty():
		var out := []
		for i in IdleDB.dreamshape(id).abilities.size():
			out.append(i)
		return out
	return plan


func add_to_plan(id: String, ability_index: int) -> bool:
	if owned[id].plan.size() >= MAX_PLAN_SLOTS:
		return false
	owned[id].plan.append(ability_index)
	return true


func remove_from_plan(id: String, slot: int) -> void:
	if slot >= 0 and slot < owned[id].plan.size():
		owned[id].plan.remove_at(slot)


func clear_plan(id: String) -> void:
	owned[id].plan = []


# ---- Equipment ----------------------------------------------------------

## Attaches an unlocked item ("" removes it). An item can only be on one Dreamshape.
func equip(id: String, equipment_id: String) -> void:
	if equipment_id != "":
		if not equipment_owned.has(equipment_id):
			return
		for other in owned:
			if owned[other].equipment == equipment_id:
				owned[other].equipment = ""
	owned[id].equipment = equipment_id


func unlock_equipment(equipment_id: String) -> bool:
	if equipment_owned.has(equipment_id):
		return false
	equipment_owned.append(equipment_id)
	notices.append("Unlocked %s" % IdleDB.equipment(equipment_id).name)
	return true


# ---- Dreamplanes --------------------------------------------------------

func plane_unlocked(id: String) -> bool:
	var req: String = IdleDB.dreamplane(id).requires
	return req == "" or cleared.has(req)


func enter_plane(id: String) -> bool:
	if not plane_unlocked(id):
		return false
	plane_id = id
	wave = 0
	battle = null
	pause_left = 0.0
	return true


# ---- Idle loop ----------------------------------------------------------

func can_fight() -> bool:
	return not active_ids().is_empty() and plane_id != ""


func advance(dt: float) -> void:
	if not can_fight():
		battle = null
		return
	while dt > 0.0:
		var step := minf(dt, STEP)
		dt -= step
		_step(step)


func _step(dt: float) -> void:
	if battle == null:
		pause_left -= dt
		if pause_left <= 0.0:
			_start_wave()
		return
	battle.advance(dt)
	if battle.result != "":
		_finish_battle()


func _start_wave() -> void:
	var b := IdleBattle.new()
	for id in active_ids():
		var o: Dictionary = owned[id]
		b.add_unit(IdleDB.make_unit(id, o.level, BattleUnit.SIDE_PLAYER, o.row, effective_plan(id).duplicate(), o.equipment))
	for e in IdleDB.dreamplane(plane_id).waves[wave]:
		b.add_unit(IdleDB.make_unit(e.id, e.level, BattleUnit.SIDE_ENEMY, e.row))
	battle = b


func _finish_battle() -> void:
	var b := battle
	last_result = b.result
	battle = null
	pause_left = BETWEEN_BATTLES
	if b.result == "won":
		_reward(b)
		wave += 1
		if wave >= IdleDB.dreamplane(plane_id).waves.size():
			_plane_cleared()
			wave = 0
	else:
		wave = 0
		notices.append("The team was overwhelmed. Restarting %s." % IdleDB.dreamplane(plane_id).name)


func _reward(b: IdleBattle) -> void:
	var xp := 0
	for k in b.kills:
		xp += k.xp_value * k.level
		vorx += k.vorx_value * k.level
		_roll_drop()
	for id in active_ids():
		_give_xp(id, xp)


func _roll_drop() -> void:
	if rng.randf() >= DROP_CHANCE:
		return
	var pool := []
	for e in IdleDB.dreamplane(plane_id).drops:
		if not equipment_owned.has(e):
			pool.append(e)
	if not pool.is_empty():
		unlock_equipment(pool[rng.randi_range(0, pool.size() - 1)])


func _give_xp(id: String, amount: int) -> void:
	var o: Dictionary = owned[id]
	if o.level >= IdleDB.MAX_LEVEL:
		return
	o.xp += amount
	while o.level < IdleDB.MAX_LEVEL and o.xp >= IdleDB.xp_to_next(o.level):
		o.xp -= IdleDB.xp_to_next(o.level)
		o.level += 1
		notices.append("%s reached level %d" % [IdleDB.dreamshape(id).name, o.level])


func _plane_cleared() -> void:
	var plane := IdleDB.dreamplane(plane_id)
	if not cleared.has(plane_id):
		cleared.append(plane_id)
		notices.append("%s cleared!" % plane.name)
		unlock_equipment(plane.first_clear_equipment)


# ---- Saving -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"owned": owned, "equipment_owned": equipment_owned, "vorx": vorx,
		"cleared": cleared, "plane_id": plane_id, "saved_at": Time.get_unix_time_from_system(),
	}


static func from_dict(d: Dictionary) -> IdleGame:
	var g := IdleGame.new()
	for id in d.get("owned", {}):
		if not IdleDB.summonable_ids().has(id):
			continue
		var o: Dictionary = d.owned[id]
		var plan := []
		for i in o.get("plan", []):
			plan.append(int(i))
		g.owned[id] = {"level": int(o.get("level", 1)), "xp": int(o.get("xp", 0)), "equipment": o.get("equipment", ""),
			"row": o.get("row", "front"), "active": bool(o.get("active", false)), "plan": plan}
	g.equipment_owned = d.get("equipment_owned", [])
	g.vorx = int(d.get("vorx", 0))
	g.cleared = d.get("cleared", [])
	g.plane_id = d.get("plane_id", "whispering_meadow")
	return g


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict()))


## Loads the save (or starts fresh) and fast-forwards the time the player was away.
static func load_or_new() -> IdleGame:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return new_game()
	var parsed = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return new_game()
	var g := from_dict(parsed)
	var away := minf(Time.get_unix_time_from_system() - float(parsed.get("saved_at", 0)), OFFLINE_CAP)
	if away > 60.0:
		g.advance(away)
		g.notices.append("Welcome back! Your Dreamshapes fought for %d minutes." % int(away / 60.0))
	return g
