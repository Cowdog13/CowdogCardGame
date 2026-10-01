class_name HumanAgent
extends PlayerAgent
## Actions come from the UI via GameController.submit(), so there is nothing to decide.


func _init(p_seat: int = 0) -> void:
	seat = p_seat
	is_automatic = false
