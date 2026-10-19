class_name HandView
extends Control
## The player's hand along the bottom edge. Cards overlap when there are many, sit partly
## below the screen edge, and lift up when hovered.

signal card_clicked(index: int)
signal card_hovered(card_id: String)

const CARD := Vector2(150, 210)
const VISIBLE_HEIGHT := 150.0  # how much of a resting card shows above the bottom edge
const LIFT := 70.0

var cards: Array[CardView] = []
var full_view := false  # show the whole card (e.g. during the mulligan) instead of peeking over the edge
var _ids: Array = []
var _marks: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_hand(ids: Array, marks: Array, full := false) -> void:
	if ids == _ids and marks == _marks and full == full_view:
		return
	full_view = full
	_ids = ids.duplicate()
	_marks = marks.duplicate()
	for c in cards:
		remove_child(c)
		c.queue_free()
	cards.clear()
	for i in ids.size():
		var cv := CardView.new().setup(ids[i], marks[i], CARD)
		cv.clicked.connect(func(): card_clicked.emit(i))
		cv.hovered.connect(func(id): card_hovered.emit(id))
		cv.mouse_entered.connect(func(): _lift(cv, true))
		cv.mouse_exited.connect(func(): _lift(cv, false))
		add_child(cv)
		cards.append(cv)
	layout()


func layout() -> void:
	var n := cards.size()
	if n == 0:
		return
	var avail := maxf(size.x, CARD.x * 3.0)
	var step := minf(CARD.x + 10.0, (avail - CARD.x) / maxf(n - 1, 1))
	var total := CARD.x + step * (n - 1)
	var x0 := (size.x - total) / 2.0
	for i in n:
		cards[i].position = Vector2(x0 + step * i, _rest_y())
		cards[i].set_meta("rest_x", cards[i].position.x)
		cards[i].z_index = i


func _rest_y() -> float:
	return size.y - (CARD.y + 12.0 if full_view else VISIBLE_HEIGHT)


func _lift(cv: CardView, up: bool) -> void:
	if not is_instance_valid(cv) or not cards.has(cv):
		return
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var target_y := _rest_y() - LIFT if up else _rest_y()
	tw.tween_property(cv, "position:y", target_y, 0.12)
	cv.z_index = 50 if up else cards.find(cv)


func card_rect(index: int) -> Rect2:
	if index >= 0 and index < cards.size():
		return cards[index].get_global_rect()
	return Rect2(global_position + Vector2(size.x / 2.0, size.y), CARD)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		layout()
