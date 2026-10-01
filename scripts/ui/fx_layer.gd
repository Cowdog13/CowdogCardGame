class_name FxLayer
extends Control
## Transient visual effects drawn above the table: flying cards, bursts, fireworks,
## zap lines and blinking borders. Everything here is cosmetic and uses global
## (viewport) coordinates; GameScreen decides what to play and when.

const CARD_SIZE := Vector2(150, 250)
const FLIP_TIME := 0.16


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Style shared by the blank card back (opponent hand, face-down flights).
static func back_style(corner := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.20, 0.36)
	sb.border_color = Color(0.86, 0.70, 0.30)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(corner)
	return sb


## A card-sized node with a face (CardView) and a blank back; pivot is its centre.
func make_card(card_id: String, face_up: bool) -> Control:
	var wrapper := Control.new()
	wrapper.size = CARD_SIZE
	wrapper.custom_minimum_size = CARD_SIZE
	wrapper.pivot_offset = CARD_SIZE / 2.0
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := Panel.new()
	back.name = "Back"
	back.size = CARD_SIZE
	back.add_theme_stylebox_override("panel", back_style(10))
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := Label.new()
	mark.text = "COWDOG"
	mark.add_theme_font_size_override("font_size", 20)
	mark.modulate = Color(0.86, 0.70, 0.30)
	mark.size = CARD_SIZE
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back.add_child(mark)
	wrapper.add_child(back)
	var face := CardView.new().setup(card_id)
	face.name = "Face"
	face.size = CARD_SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(face)
	back.visible = not face_up
	face.visible = face_up
	return wrapper


func place(card: Control, center: Vector2, scale_factor: float) -> void:
	card.position = center - global_position - CARD_SIZE / 2.0
	card.scale = Vector2(scale_factor, scale_factor)


func scale_for(rect: Rect2) -> float:
	return minf(rect.size.x / CARD_SIZE.x, rect.size.y / CARD_SIZE.y)


func screen_center() -> Vector2:
	return global_position + size / 2.0


## Moves a card so its centre lands on `center` (viewport coordinates).
func fly(card: Control, center: Vector2, scale_factor: float, duration: float) -> void:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(card, "position", center - global_position - CARD_SIZE / 2.0, duration)
	tw.tween_property(card, "scale", Vector2(scale_factor, scale_factor), duration)
	await tw.finished


func flip(card: Control) -> void:
	var tw := create_tween()
	tw.tween_property(card, "scale:x", 0.0, FLIP_TIME)
	await tw.finished
	card.get_node("Back").visible = false
	card.get_node("Face").visible = true
	var target := Vector2(card.scale.y, card.scale.y)
	tw = create_tween()
	tw.tween_property(card, "scale:x", target.x, FLIP_TIME)
	await tw.finished


func fade_out(node: CanvasItem, duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", 0.0, duration)
	await tw.finished


## The standard "play a card" sequence.
##  src         where the card starts (hand card / blank card / discard button)
##  hold        seconds to show it large in the middle (0 = fly straight to the target)
##  targets     rects it flies to afterwards (one copy per rect), shrinking and fading
##  face_down   the card starts as a blank back and is turned over in the middle
func play_card(card_id: String, src: Rect2, hold: float, targets: Array, face_down: bool, big := 1.5) -> void:
	var card := make_card(card_id, not face_down)
	add_child(card)
	place(card, src.get_center(), scale_for(src))
	if hold > 0.0:
		await fly(card, screen_center(), big, 0.5)
		if face_down:
			await flip(card)
		await get_tree().create_timer(hold).timeout
	elif face_down:
		card.get_node("Back").visible = false
		card.get_node("Face").visible = true
	if targets.is_empty():
		await fade_out(card, 0.3)
		card.queue_free()
		return
	# Extra targets get their own copy leaving from the card's current position.
	var copies: Array = [card]
	for i in range(1, targets.size()):
		var copy := make_card(card_id, true)
		add_child(copy)
		copy.position = card.position
		copy.scale = card.scale
		copies.append(copy)
	var flights: Array = []
	for i in targets.size():
		flights.append(_land(copies[i], targets[i]))
	for tw in flights:
		if tw.is_running():
			await tw.finished


func _land(card: Control, target: Rect2) -> Tween:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var s := scale_for(target)
	tw.tween_property(card, "position", target.get_center() - global_position - CARD_SIZE / 2.0, 0.5)
	tw.tween_property(card, "scale", Vector2(s, s), 0.5)
	tw.tween_property(card, "modulate:a", 0.0, 0.18).set_delay(0.34)
	tw.finished.connect(card.queue_free)
	return tw


## Shows two cards large in the middle (creature swap).
func show_pair(left_id: String, right_id: String, left_caption: String, right_caption: String, hold: float) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	add_child(holder)
	var s := 1.8
	for i in 2:
		var card := make_card(left_id if i == 0 else right_id, true)
		holder.add_child(card)
		var x := -1.0 if i == 0 else 1.0
		card.scale = Vector2(s, s)
		card.position = screen_center() - global_position + Vector2(x * 190.0, 0.0) - CARD_SIZE / 2.0
		var cap := Label.new()
		cap.text = left_caption if i == 0 else right_caption
		cap.add_theme_font_size_override("font_size", 22)
		cap.size = Vector2(300, 30)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.position = screen_center() - global_position + Vector2(x * 190.0 - 150.0, -CARD_SIZE.y * s / 2.0 - 36.0)
		holder.add_child(cap)
	var tw := create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.25)
	await tw.finished
	await get_tree().create_timer(hold).timeout
	await fade_out(holder, 0.3)
	holder.queue_free()


# --- Particles and lines ------------------------------------------------------------------
func burst(pos: Vector2, color: Color, amount := 26, speed := 150.0, lifetime := 0.7) -> void:
	var p := CPUParticles2D.new()
	p.position = pos - global_position
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 220)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	get_tree().create_timer(lifetime + 0.3).timeout.connect(p.queue_free)


func firework(pos: Vector2) -> void:
	var colors := [Color(1, 0.4, 0.3), Color(1, 0.9, 0.3), Color(0.4, 0.9, 1), Color(0.9, 0.5, 1), Color(0.5, 1, 0.5)]
	for i in colors.size():
		var offset := Vector2.from_angle(TAU * i / colors.size()) * 26.0
		burst(pos + offset, colors[i], 22, 230.0, 0.9)
		await get_tree().create_timer(0.06).timeout


## A short line that shoots from `a` to `b` and fades.
func zap(a: Vector2, b: Vector2, color := Color(1, 0.95, 0.6)) -> void:
	var line := Line2D.new()
	line.width = 5.0
	line.default_color = color
	line.add_point(a - global_position)
	line.add_point(a - global_position)
	add_child(line)
	var tw := create_tween()
	tw.tween_method(func(t: float): line.set_point_position(1, (a + (b - a) * t) - global_position), 0.0, 1.0, 0.25)
	tw.tween_property(line, "modulate:a", 0.0, 0.2)
	await tw.finished
	line.queue_free()


## Pulses a highlighted frame over `rect` for about `duration` seconds.
func flash(rect: Rect2, duration := 1.5, color := Color(1, 0.92, 0.35)) -> void:
	var frame := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.28)
	sb.border_color = color
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = rect.position - global_position - Vector2(3, 3)
	frame.size = rect.size + Vector2(6, 6)
	frame.modulate.a = 0.0
	add_child(frame)
	var cycles := maxi(int(duration / 0.3), 1)
	var tw := create_tween()
	for i in cycles:
		tw.tween_property(frame, "modulate:a", 1.0, 0.15)
		tw.tween_property(frame, "modulate:a", 0.25, 0.15)
	tw.tween_property(frame, "modulate:a", 0.0, maxf(duration - cycles * 0.3, 0.05))
	await tw.finished
	frame.queue_free()


## Blinks a light border around `rect` a few times.
func blink(rect: Rect2, color := Color(1, 0.96, 0.7), times := 3) -> void:
	var frame := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.0)
	sb.border_color = color
	sb.set_border_width_all(7)
	sb.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = rect.position - global_position
	frame.size = rect.size
	frame.modulate.a = 0.0
	add_child(frame)
	var tw := create_tween()
	for i in times:
		tw.tween_property(frame, "modulate:a", 1.0, 0.1)
		tw.tween_property(frame, "modulate:a", 0.0, 0.14)
	await tw.finished
	frame.queue_free()
