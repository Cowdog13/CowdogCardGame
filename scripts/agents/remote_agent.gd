class_name RemoteAgent
extends PlayerAgent
## A seat controlled by a player on another computer. It never decides anything itself:
## the network layer feeds that player's actions into GameController.submit().


func _init(p_seat: int = 1) -> void:
	seat = p_seat
	is_automatic = false
