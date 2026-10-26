class_name IdleDB
extends RefCounted
## Loads Dreamshape, Dreamplane and equipment definitions from res://data.
## All content is plain dictionaries keyed by id, so adding a Dreamshape is a JSON edit.

const DREAMSHAPES_PATH := "res://data/dreamshapes.json"
const DREAMPLANES_PATH := "res://data/dreamplanes.json"
const EQUIPMENT_PATH := "res://data/equipment.json"

## Stat growth per level above 1 (linear).
const HP_PER_LEVEL := 0.18
const POWER_PER_LEVEL := 0.12
const MAX_LEVEL := 50
## Effect strength words used in the data files. "amp" is a multiplier, not scaled by power.
const POWER_TIERS := {"small": 10.0, "medium": 20.0, "large": 40.0, "amp": 0.5}

static var _dreamshapes: Dictionary = {}
static var _dreamplanes: Dictionary = {}
static var _equipment: Dictionary = {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_dreamshapes = _read_json(DREAMSHAPES_PATH)
	for id in _dreamshapes:
		_dreamshapes[id]["id"] = id
	_dreamplanes = _read_json(DREAMPLANES_PATH)
	for id in _dreamplanes:
		_dreamplanes[id]["id"] = id
	_equipment = _read_json(EQUIPMENT_PATH)
	for id in _equipment:
		_equipment[id]["id"] = id
	_loaded = true


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "Cannot open %s" % path)
	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "Bad JSON in %s" % path)
	return parsed


static func dreamshape(id: String) -> Dictionary:
	_ensure_loaded()
	return _dreamshapes[id]


static func dreamplane(id: String) -> Dictionary:
	_ensure_loaded()
	return _dreamplanes[id]


static func equipment(id: String) -> Dictionary:
	_ensure_loaded()
	return _equipment[id]


static func dreamplane_ids() -> Array:
	_ensure_loaded()
	return _dreamplanes.keys()


## Ids of Dreamshapes the player can summon (everything that is not enemy_only).
static func summonable_ids() -> Array:
	_ensure_loaded()
	var out := []
	for id in _dreamshapes:
		if not _dreamshapes[id].get("enemy_only", false):
			out.append(id)
	return out


static func level_hp_mult(level: int) -> float:
	return 1.0 + HP_PER_LEVEL * (level - 1)


static func level_power_mult(level: int) -> float:
	return 1.0 + POWER_PER_LEVEL * (level - 1)


static func xp_to_next(level: int) -> int:
	return int(round(30.0 * pow(level, 1.4)))


## Builds a ready-to-fight unit. plan is a list of ability indexes (empty = every ability in order).
static func make_unit(id: String, level: int, side: int, row: String, plan: Array = [], equipment_id: String = "") -> BattleUnit:
	var def := dreamshape(id)
	var mods: Dictionary = equipment(equipment_id) if equipment_id != "" else {}
	var u := BattleUnit.new()
	u.id = id
	u.name = def.name
	u.dclass = def.get("class", "")
	u.side = side
	u.row = row
	u.level = level
	u.max_hp = def.base_hp * level_hp_mult(level) * (1.0 + mods.get("hp_pct", 0.0))
	u.hp = u.max_hp
	u.power = def.base_power * level_power_mult(level) * (1.0 + mods.get("power_pct", 0.0))
	u.armor = mods.get("start_armor", 0.0)
	u.cooldown_mult = maxf(0.1, 1.0 + mods.get("cooldown_pct", 0.0))
	u.startup_mult = maxf(0.0, 1.0 + mods.get("startup_pct", 0.0))
	u.abilities = def.abilities
	u.xp_value = def.get("xp", 0)
	u.vorx_value = def.get("vorx", 0)
	if plan.is_empty():
		for i in def.abilities.size():
			plan.append(i)
	u.plan = plan
	return u
