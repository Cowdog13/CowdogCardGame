class_name BattleUnit
extends RefCounted
## One combatant in a battle. A unit loops through its plan: startup -> resolve -> cooldown.

const SIDE_PLAYER := 0
const SIDE_ENEMY := 1

var id := ""
var name := ""
var dclass := ""
var side := SIDE_PLAYER
var row := "front"
var level := 1
var max_hp := 1.0
var hp := 1.0
var armor := 0.0
var power := 1.0
var cooldown_mult := 1.0
var startup_mult := 1.0
var abilities: Array = []
var plan: Array = []
var plan_index := 0
var xp_value := 0
var vorx_value := 0
## Bonus applied to the next heal received (0 = none).
var heal_amp := 0.0
## "startup", "resolve" or "cooldown".
var phase := "cooldown"
var phase_left := 0.0
var phase_total := 0.0
var current: Dictionary = {}
var locked: Array = []


func alive() -> bool:
	return hp > 0.0


func hp_ratio() -> float:
	return hp / max_hp


## Short status text for the UI, e.g. "Barrage (resolving)".
func cast_text() -> String:
	if not alive():
		return "Defeated"
	if current.is_empty():
		return "Ready"
	match phase:
		"startup":
			return "%s (starting)" % current.name
		"resolve":
			return "%s (resolving)" % current.name
	return "Recovering"
