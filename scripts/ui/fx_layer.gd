class_name FxLayer
extends Control
## Transient visual effects drawn above the table: flying cards, bursts, fireworks,
## zap lines and blinking borders. Everything here is cosmetic and uses global
## (viewport) coordinates; GameScreen decides what to play and when.

const CARD_SIZE := Vector2(150, 210)
const FLIP_TIME := 0.16


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A card-sized node with a face (CardView) and a card back; pivot is its centre.
func make_card(card_id: String, face_up: bool) -> Control:
	var wrapper := Control.new()
	wrapper.size = CARD_SIZE
	wrapper.custom_minimum_size = CARD_SIZE
	wrapper.pivot_offset = CARD_SIZE / 2.0
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := CardBack.new().setup(CARD_SIZE)
	back.name = "Back"
	wrapper.add_child(back)
	var face := CardView.new().setup(card_id, CardView.Mark.NONE, CARD_SIZE)
	face.name = "Face"
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


func firework(pos: Vector2, colors := [Color(1, 0.4, 0.3), Color(1, 0.9, 0.3), Color(0.4, 0.9, 1), Color(0.9, 0.5, 1), Color(0.5, 1, 0.5)]) -> void:
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


## Stun: a crackling blue bolt from `origin` to every target, with blue fireworks where it lands.
func stun_bolts(origin: Vector2, targets: Array) -> void:
	var blues := [Color(0.35, 0.65, 1.0), Color(0.55, 0.9, 1.0), Color(1, 1, 1), Color(0.3, 0.45, 1.0), Color(0.7, 0.8, 1.0)]
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var rng := RandomNumberGenerator.new()
	var tw := create_tween().set_parallel(true)
	for target in targets:
		var path: Array = [origin]
		var seg := 9
		var dir: Vector2 = target - origin
		var normal := dir.orthogonal().normalized()
		for i in range(1, seg):
			path.append(origin + dir * (float(i) / seg) + normal * rng.randf_range(-22.0, 22.0))
		path.append(target)
		var layers: Array = []
		for style in [[16.0, 0.22, Color(0.25, 0.5, 1.0)], [8.0, 0.6, Color(0.45, 0.8, 1.0)], [3.0, 1.0, Color(1, 1, 1)]]:
			var line := Line2D.new()
			line.width = style[0]
			var c: Color = style[2]
			line.default_color = Color(c.r, c.g, c.b, style[1])
			line.joint_mode = Line2D.LINE_JOINT_ROUND
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			holder.add_child(line)
			layers.append(line)
		var reveal := func(t: float):
			var upto := int(ceil(t * (path.size() - 1))) + 1
			for line in layers:
				line.clear_points()
				for k in mini(upto, path.size()):
					var pt: Vector2 = path[k]
					if k == upto - 1 and k > 0:  # the head moves smoothly between vertices
						var prev: Vector2 = path[k - 1]
						var f := t * (path.size() - 1) - (k - 1)
						pt = prev.lerp(pt, clampf(f, 0.0, 1.0))
					line.add_point(pt - global_position)
		tw.tween_method(reveal, 0.0, 1.0, 0.32)
		# Sparks along the bolt and a blue firework at the target.
		for k in range(1, path.size() - 1, 2):
			var spark_pos: Vector2 = path[k]
			tw.tween_callback(func(): burst(spark_pos, blues[rng.randi() % blues.size()], 7, 70.0, 0.4)).set_delay(0.32 * k / path.size())
		tw.tween_callback(func(): firework(target, blues)).set_delay(0.32)
	await get_tree().create_timer(0.32).timeout
	var fade := create_tween()
	fade.tween_interval(0.25)
	fade.tween_property(holder, "modulate:a", 0.0, 0.35)
	await fade.finished
	holder.queue_free()
	await get_tree().create_timer(0.3).timeout  # let the last sparks finish


## Briefly shows cards that were found in a deck (Super Berries, or berries with Fire Famine).
func show_reveal(ids: Array, caption: String, hold: float) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	add_child(holder)
	var n := ids.size()
	var s := minf(1.3, 1100.0 / maxf(n, 1) / CARD_SIZE.x - 0.1)
	var step := CARD_SIZE.x * s + 14.0
	var centers: Array = []
	for i in n:
		var card := make_card(ids[i], true)
		holder.add_child(card)
		var c := screen_center() + Vector2((i - (n - 1) / 2.0) * step, 10.0)
		card.position = c - global_position - CARD_SIZE / 2.0
		card.scale = Vector2(s * 0.7, s * 0.7)
		centers.append(c)
		var pop := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(card, "scale", Vector2(s, s), 0.3)
	var label := Label.new()
	label.text = caption
	label.size = Vector2(800, 50)
	label.position = screen_center() - global_position + Vector2(-400, -CARD_SIZE.y * s / 2.0 - 70.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.2))
	label.add_theme_constant_override("outline_size", 8)
	holder.add_child(label)
	var tw := create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.2)
	await tw.finished
	for i in n:
		burst(centers[i], Rules.element_color(CardDB.element_of(ids[i])), 26, 190.0, 0.8)
	await get_tree().create_timer(hold).timeout
	await fade_out(holder, 0.3)
	holder.queue_free()


## A big caption in the middle of the screen for a moment (e.g. "No berries found").
func show_message(text: String, hold: float) -> void:
	var label := Label.new()
	label.text = text
	label.size = Vector2(900, 60)
	label.position = screen_center() - global_position - label.size / 2.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 38)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.16))
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate.a = 0.0
	add_child(label)
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.15)
	await tw.finished
	await get_tree().create_timer(hold).timeout
	await fade_out(label, 0.25)
	label.queue_free()


## Plunder: lay the plundered cards out in a row in the middle of the screen, then send the ones
## that go to the discard flying there. Super Berries stay behind (the player places them next).
func show_plunder(ids: Array, discard_rect: Rect2, hold: float) -> void:
	var n := ids.size()
	if n == 0:
		await show_message("No berries found", 1.0)
		return
	var s := minf(0.95, 1080.0 / (n * CARD_SIZE.x + 10.0 * n))
	var step := minf(CARD_SIZE.x * s + 12.0, 1080.0 / n)
	var cards: Array = []
	var any_super := false
	for i in n:
		var card := make_card(ids[i], true)
		add_child(card)
		var c := screen_center() + Vector2((i - (n - 1) / 2.0) * step, 0.0)
		place(card, c, s * 0.6)
		card.modulate.a = 0.0
		cards.append(card)
		var pop := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(card, "scale", Vector2(s, s), 0.22).set_delay(0.04 * i)
		pop.tween_property(card, "modulate:a", 1.0, 0.15).set_delay(0.04 * i)
		if CardDB.element_of(ids[i]) == Rules.SUPER:
			any_super = true
	await get_tree().create_timer(0.3 + 0.04 * n).timeout
	if any_super:
		for i in n:
			if CardDB.element_of(ids[i]) == Rules.SUPER:
				burst(cards[i].global_position + CARD_SIZE / 2.0 * s, Rules.element_color(Rules.SUPER), 28, 200.0, 0.8)
	await get_tree().create_timer(hold).timeout
	var flights: Array = []
	for i in n:
		if CardDB.element_of(ids[i]) == Rules.SUPER:
			continue
		flights.append(_to_discard(cards[i], discard_rect, 0.05 * i))
	for tw in flights:
		if tw.is_running():
			await tw.finished
	var supers: Array = cards.filter(func(c): return is_instance_valid(c) and c.modulate.a > 0.5)
	if supers.is_empty():
		await show_message("No berries found", 0.9)
	else:
		await get_tree().create_timer(0.35).timeout
		for c in supers:
			c.queue_free()


func _to_discard(card: Control, target: Rect2, delay: float) -> Tween:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	var s := scale_for(target)
	tw.tween_property(card, "position", target.get_center() - global_position - CARD_SIZE / 2.0, 0.45).set_delay(delay)
	tw.tween_property(card, "scale", Vector2(s, s), 0.45).set_delay(delay)
	tw.tween_property(card, "modulate:a", 0.0, 0.12).set_delay(delay + 0.36)
	tw.finished.connect(card.queue_free)
	return tw
