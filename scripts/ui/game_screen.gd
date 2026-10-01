class_name GameScreen
extends Control
## The playtest table. Reads only get_view(ME) from the controller and sends every
## move through controller.submit(), exactly like a networked client would.

signal exit_requested
signal rematch_requested

const ME := 0
const SLOT_SIZE := Vector2(300, 215)

var controller: GameController
var view: Dictionary = {}

var _pending: Dictionary = {}  # active targeting: prompt, valid, max, targets, done
var _mull_sel := {}
var _status := ""
var _over_shown := false

var _opp_info: Label
var _turn_label: Label
var _opp_board: HBoxContainer
var _my_board: HBoxContainer
var _my_info: Label
var _hand_box: HBoxContainer
var _banner: Label
var _confirm_btn: Button
var _cancel_btn: Button
var _end_btn: Button
var _swap_btn: Button
var _log: RichTextLabel
var _detail: RichTextLabel
var _opp_discard_btn: Button
var _my_discard_btn: Button


func start(deck_ids: Array, agents: Array, ai_delay: float) -> void:
	_build_ui()
	controller = GameController.new()
	controller.ai_delay = ai_delay
	add_child(controller)
	controller.event_logged.connect(_on_event)
	controller.view_updated.connect(_refresh)
	controller.game_over.connect(_on_game_over)
	controller.start(deck_ids, agents)
	_refresh()


# --- Layout ----------------------------------------------------------------------------
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.12, 0.11)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)

	var opp_row := HBoxContainer.new()
	left.add_child(opp_row)
	_opp_info = Label.new()
	_opp_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opp_row.add_child(_opp_info)
	_opp_discard_btn = Button.new()
	_opp_discard_btn.pressed.connect(func(): _show_pile("Opponent's discard", view.opponent.discard))
	opp_row.add_child(_opp_discard_btn)
	_opp_board = _board_row(left)

	var mid := HBoxContainer.new()
	mid.custom_minimum_size = Vector2(0, 44)
	left.add_child(mid)
	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 18)
	mid.add_child(_turn_label)
	_banner = Label.new()
	_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(_banner)
	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm"
	_confirm_btn.pressed.connect(_on_confirm)
	mid.add_child(_confirm_btn)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_cancel)
	mid.add_child(_cancel_btn)

	_my_board = _board_row(left)
	var my_row := HBoxContainer.new()
	left.add_child(my_row)
	_my_info = Label.new()
	_my_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_row.add_child(_my_info)
	_my_discard_btn = Button.new()
	_my_discard_btn.pressed.connect(func(): _show_pile("Your discard", view.you.discard))
	my_row.add_child(_my_discard_btn)
	_swap_btn = Button.new()
	_swap_btn.text = "Swap (once per game)"
	_swap_btn.pressed.connect(_on_swap)
	my_row.add_child(_swap_btn)
	_end_btn = Button.new()
	_end_btn.text = "End Turn"
	_end_btn.custom_minimum_size = Vector2(120, 0)
	_end_btn.pressed.connect(func(): _submit({"type": "end_turn"}))
	my_row.add_child(_end_btn)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 245)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_hand_box = HBoxContainer.new()
	_hand_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_hand_box)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(330, 0)
	side.add_theme_constant_override("separation", 6)
	root.add_child(side)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.custom_minimum_size = Vector2(0, 190)
	_detail.text = "Hover a card for details."
	side.add_child(_detail)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_log)
	var menu_btn := Button.new()
	menu_btn.text = "Back to Menu"
	menu_btn.pressed.connect(func(): exit_requested.emit())
	side.add_child(menu_btn)


func _board_row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size = Vector2(0, SLOT_SIZE.y)
	parent.add_child(row)
	return row


# --- Refresh -----------------------------------------------------------------------------
func _refresh() -> void:
	view = controller.get_view(ME)
	var you: Dictionary = view.you
	var opp: Dictionary = view.opponent
	_opp_info.text = "Opponent - Deck %d | Hand %d | Exile %d" % [opp.deck_count, opp.hand_count, opp.exile_count]
	_opp_discard_btn.text = "Discard (%d)" % opp.discard.size()
	_my_info.text = "You - Deck %d | Exile %d%s" % [you.deck_count, you.exile_count, _turn_flags(you)]
	_my_discard_btn.text = "Discard (%d)" % you.discard.size()
	_rebuild_board(_opp_board, ME + 1)
	_rebuild_board(_my_board, ME)
	_rebuild_hand()
	var acting := _can_act()
	_end_btn.disabled = not acting or not _pending.is_empty()
	_swap_btn.disabled = not acting or you.swap_used
	match view.phase:
		"mulligan": _turn_label.text = "Mulligan"
		"over": _turn_label.text = "Game over"
		_: _turn_label.text = "Turn %d - %s" % [view.turn, "YOUR TURN" if acting else "Opponent's turn"]
	_update_banner()


func _turn_flags(you: Dictionary) -> String:
	if view.phase != "main" or view.active != ME:
		return ""
	return " | Berry: %s | Creature: %s | Abilities: %d/%d" % [
		"used" if you.berry_attached else "ready", "used" if you.creature_played else "ready",
		you.abilities_used, Rules.ABILITIES_PER_TURN]


func _update_banner() -> void:
	var text := ""
	var show_confirm := false
	if not _pending.is_empty():
		text = _pending.prompt
		show_confirm = int(_pending.max) > 1 and not _pending.targets.is_empty()
	elif view.phase == "mulligan":
		if view.you.mulligan_done:
			text = "Waiting for the opponent to mulligan..."
		else:
			text = "Mulligan: click cards to put on the bottom (you draw as many). Selected: %d" % _mull_sel.size()
			show_confirm = true
	elif _can_act():
		text = "Play cards from your hand, use creature abilities, then End Turn."
	if _status != "":
		text = (text + "\n" if text != "" else "") + _status
	_banner.text = text
	_confirm_btn.visible = show_confirm
	_cancel_btn.visible = not _pending.is_empty()


func _can_act() -> bool:
	return view.phase == "main" and view.active == ME


func _rebuild_board(row: HBoxContainer, seat: int) -> void:
	for c in row.get_children():
		c.queue_free()
		row.remove_child(c)
	for slot in Rules.BOARD_SLOTS:
		row.add_child(_make_slot(seat, slot))


func _make_slot(seat: int, slot: int) -> Control:
	var side: Dictionary = view.you if seat == ME else view.opponent
	var creature = side.board[slot]
	var valid: bool = not _pending.is_empty() and _pending.valid.call(seat, slot)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	style.bg_color = Color(0.15, 0.19, 0.17)
	style.border_color = Color(0.3, 0.36, 0.33)
	style.set_border_width_all(2)
	if creature != null:
		var base := Rules.element_color(String(Rules.top_card(creature).element))
		style.bg_color = base.darkened(0.6)
		style.border_color = base.lightened(0.1)
	var chosen := _target_index(seat, slot) >= 0
	if valid or chosen:
		style.border_color = Color(1, 0.35, 0.35) if chosen else Color(1, 0.9, 0.3)
		style.set_border_width_all(5)
	panel.add_theme_stylebox_override("panel", style)
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_slot_clicked(seat, slot))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	if creature == null:
		var empty := Label.new()
		empty.text = "Empty"
		empty.modulate = Color(1, 1, 1, 0.35)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(empty)
		return panel
	var top := Rules.top_card(creature)
	panel.mouse_entered.connect(func(): _show_creature_detail(creature))
	var title := Label.new()
	title.text = "%s  (Tier %d)" % [top.name, int(top.tier)]
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	if creature.cards.size() > 1:
		var names: Array = creature.cards.map(func(id): return CardDB.card_name(id))
		var stack := Label.new()
		stack.text = " > ".join(names)
		stack.add_theme_font_size_override("font_size", 11)
		stack.modulate = Color(1, 1, 1, 0.6)
		box.add_child(stack)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 3)
	chips.add_theme_constant_override("v_separation", 3)
	for b in creature.berries:
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(20, 20)
		chip.color = Rules.element_color(CardDB.element_of(b))
		chip.tooltip_text = CardDB.card_name(b)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chips.add_child(chip)
	if creature.berries.is_empty():
		var none := Label.new()
		none.text = "No berries"
		none.add_theme_font_size_override("font_size", 12)
		none.modulate = Color(1, 1, 1, 0.4)
		chips.add_child(none)
	box.add_child(chips)
	if Rules.is_stunned(creature, view.turn):
		var stun := Label.new()
		stun.text = "STUNNED"
		stun.modulate = Color(0.5, 0.85, 1)
		box.add_child(stun)
	for ai in top.abilities.size():
		var ab: Dictionary = top.abilities[ai]
		var label := "[%s] %s" % [Rules.cost_text(ab.cost), Rules.ability_text(ab)]
		var met := Rules.meets_cost(creature.berries, ab.cost)
		if seat == ME and not ab.get("active", false):
			var btn := Button.new()
			btn.text = label
			btn.clip_text = false
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.add_theme_font_size_override("font_size", 13)
			btn.disabled = not (_can_act() and _pending.is_empty() and met
				and not Rules.is_stunned(creature, view.turn) and view.you.abilities_used < Rules.ABILITIES_PER_TURN)
			btn.pressed.connect(_on_ability_pressed.bind(slot, ai))
			box.add_child(btn)
		else:
			var l := Label.new()
			l.text = label
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.add_theme_font_size_override("font_size", 13)
			l.modulate = Color(1, 1, 1, 1.0 if met else 0.45)
			box.add_child(l)
	return panel


func _rebuild_hand() -> void:
	for c in _hand_box.get_children():
		c.queue_free()
		_hand_box.remove_child(c)
	var hand: Array = view.you.hand
	for i in hand.size():
		var mark := CardView.Mark.NONE
		if view.phase == "mulligan" and not view.you.mulligan_done:
			mark = CardView.Mark.SELECTED if _mull_sel.has(i) else CardView.Mark.SELECTABLE
		var cv := CardView.new().setup(hand[i], mark)
		cv.clicked.connect(_on_hand_clicked.bind(i))
		cv.hovered.connect(_show_card_detail)
		_hand_box.add_child(cv)


# --- Detail / log / dialogs -------------------------------------------------------------------
func _show_card_detail(id: String) -> void:
	_detail.text = "[b]%s[/b]\n%s" % [CardDB.card_name(id), CardDB.card_text(id)]


func _show_creature_detail(creature: Dictionary) -> void:
	var top := Rules.top_card(creature)
	var counts := {}
	for b in creature.berries:
		counts[CardDB.card_name(b)] = int(counts.get(CardDB.card_name(b), 0)) + 1
	var berries := ", ".join(counts.keys().map(func(k): return "%d %s" % [counts[k], k]))
	_detail.text = "[b]%s[/b]\n%s\n\nAttached: %s" % [top.name, CardDB.card_text(top.id), berries if berries != "" else "none"]


func _on_event(ev: Dictionary) -> void:
	var color := "#cfd8d3"
	match int(ev.player):
		ME: color = "#8fc7ff"
		ME + 1: color = "#ffb27a"
	match ev.kind:
		"turn": _log.append_text("\n[b][color=#ffe27a]%s[/color][/b]\n" % ev.text)
		"win": _log.append_text("[b][color=#ff7a7a]%s[/color][/b]\n" % ev.text)
		_: _log.append_text("[color=%s]%s[/color]\n" % [color, ev.text])


func _toast(msg: String) -> void:
	_status = msg
	_update_banner()


func _popup(dialog: Window) -> void:
	add_child(dialog)
	dialog.popup_centered()


func _show_pile(title: String, ids: Array) -> void:
	var d := AcceptDialog.new()
	d.title = "%s (%d)" % [title, ids.size()]
	d.min_size = Vector2(360, 420)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(320, 340)
	for i in range(ids.size() - 1, -1, -1):  # newest on top
		list.add_item(CardDB.card_name(ids[i]))
	d.add_child(list)
	d.canceled.connect(d.queue_free)
	d.confirmed.connect(d.queue_free)
	_popup(d)


## Modal list chooser; `labels` are shown, `on_pick` receives the chosen index.
func _pick_from_list(title: String, labels: Array, on_pick: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(320, 260)
	for l in labels:
		list.add_item(l)
	d.add_child(list)
	d.get_ok_button().disabled = true
	list.item_selected.connect(func(_i): d.get_ok_button().disabled = false)
	list.item_activated.connect(func(_i): d.get_ok_button().pressed.emit())
	d.confirmed.connect(func():
		var sel := list.get_selected_items()
		d.queue_free()
		if not sel.is_empty():
			on_pick.call(sel[0]))
	d.canceled.connect(d.queue_free)
	_popup(d)


func _confirm(title: String, text: String, on_ok: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	d.dialog_text = text
	d.confirmed.connect(func():
		d.queue_free()
		on_ok.call())
	d.canceled.connect(d.queue_free)
	_popup(d)


# --- Targeting ----------------------------------------------------------------------------------
func _begin_targeting(prompt: String, valid: Callable, max_targets: int, done: Callable) -> void:
	_status = ""
	_pending = {"prompt": prompt, "valid": valid, "max": max_targets, "targets": [], "done": done}
	_refresh()


func _target_index(seat: int, slot: int) -> int:
	if _pending.is_empty():
		return -1
	for i in _pending.targets.size():
		if _pending.targets[i].player == seat and _pending.targets[i].slot == slot:
			return i
	return -1


func _on_slot_clicked(seat: int, slot: int) -> void:
	if _pending.is_empty() or not _pending.valid.call(seat, slot):
		return
	var idx := _target_index(seat, slot)
	if idx >= 0:
		_pending.targets.remove_at(idx)
	else:
		_pending.targets.append({"player": seat, "slot": slot})
	if _pending.targets.size() >= int(_pending.max):
		_finish_targeting()
	else:
		_refresh()


func _finish_targeting() -> void:
	var done: Callable = _pending.done
	var targets: Array = _pending.targets
	_pending = {}
	done.call(targets)
	_refresh()


func _cancel() -> void:
	_pending = {}
	_status = ""
	_refresh()


func _on_confirm() -> void:
	if view.phase == "mulligan" and _pending.is_empty():
		var cards := _mull_sel.keys()
		_mull_sel = {}
		_submit({"type": "mulligan", "cards": cards})
	elif not _pending.is_empty() and not _pending.targets.is_empty():
		_finish_targeting()


func _submit(action: Dictionary) -> bool:
	var res := controller.submit(ME, action)
	_status = "" if res.ok else String(res.error)
	_refresh()
	return res.ok


# --- Hand interaction -------------------------------------------------------------------------------
func _on_hand_clicked(i: int) -> void:
	if view.phase == "mulligan":
		if view.you.mulligan_done:
			return
		if _mull_sel.has(i):
			_mull_sel.erase(i)
		else:
			_mull_sel[i] = true
		_refresh()
		return
	if not _can_act():
		return
	_pending = {}
	var id: String = view.you.hand[i]
	match CardDB.kind(id):
		"berry":
			if view.you.berry_attached:
				return _toast("You already attached a berry this turn.")
			_begin_targeting("Attach %s to which of your creatures?" % CardDB.card_name(id),
				func(p, s): return p == ME and view.you.board[s] != null, 1,
				func(t): _submit({"type": "attach_berry", "hand": i, "slot": t[0].slot}))
		"creature":
			if view.you.creature_played:
				return _toast("You already played a creature this turn.")
			_begin_targeting("Place %s on which space?" % CardDB.card_name(id),
				func(p, s): return p == ME and Rules.place_error(view.you.board, id, s) == "", 1,
				func(t): _submit({"type": "play_creature", "hand": i, "slot": t[0].slot}))
		"spell":
			_begin_spell(i, id)
	_refresh()


func _any_creature(p: int, s: int) -> bool:
	var side: Dictionary = view.you if p == ME else view.opponent
	return side.board[s] != null


func _begin_spell(i: int, id: String) -> void:
	var spell := CardDB.card(id)
	var effect: Dictionary = spell.effects[0]
	if Rules.plan_payment(view.you, spell.cost).is_empty():
		return _toast("You can't pay for %s (%s)." % [spell.name, Rules.cost_text(spell.cost)])
	match effect.type:
		"destroy":
			_begin_targeting("%s: choose a creature." % spell.name, _any_creature, 1,
				func(t): _cast(i, {"target": t[0]}))
		"stun":
			var n := int(effect.count)
			_begin_targeting("%s: choose up to %d creature(s)." % [spell.name, n], _any_creature, n,
				func(t): _cast(i, {"targets": t}))
		"play_pillaged_creature":
			var options: Array = []
			for c in view.you.pillaged:
				if view.you.discard.has(c) and CardDB.is_creature(c) and not options.has(c):
					options.append(c)
			if options.is_empty():
				return _toast("No creature was pillaged this turn.")
			_pick_from_list("Reinforce: choose a pillaged creature", options.map(func(c): return CardDB.card_name(c)),
				func(k):
					var cid: String = options[k]
					_begin_targeting("Play %s on which space?" % CardDB.card_name(cid),
						func(p, s): return p == ME and Rules.place_error(view.you.board, cid, s) == "", 1,
						func(t): _cast(i, {"card_id": cid, "slot": t[0].slot})))
		_:
			_cast(i, {})


func _cast(i: int, params: Dictionary) -> void:
	var spell := CardDB.card(view.you.hand[i])
	var plan := Rules.plan_payment(view.you, spell.cost)
	if plan.is_empty():
		return _toast("You can't pay for %s." % spell.name)
	var lines: Array = []
	for entry in plan.payment:
		if entry.src == "discard":
			lines.append("Exile %s from your discard" % CardDB.card_name(view.you.discard[entry.index]))
		else:
			var c: Dictionary = view.you.board[entry.slot]
			lines.append("Discard %s from %s" % [CardDB.card_name(c.berries[entry.index]), Rules.creature_name(c)])
	_confirm("Play %s" % spell.name, "Pay %s:\n- %s" % [Rules.cost_text(spell.cost), "\n- ".join(lines)],
		func(): _submit({"type": "play_spell", "hand": i, "payment": plan.payment, "params": params}))


# --- Ability interaction -------------------------------------------------------------------------------
func _on_ability_pressed(slot: int, ai: int) -> void:
	var creature: Dictionary = view.you.board[slot]
	var ab: Dictionary = Rules.top_card(creature).abilities[ai]
	var effect: Dictionary = ab.effects[0]
	_pending = {}
	match effect.type:
		"stun":
			var n := int(effect.count)
			_begin_targeting("Stun: choose up to %d creature(s)." % n, _any_creature, n,
				func(t): _submit({"type": "use_ability", "slot": slot, "ability": ai, "params": {"targets": t}}))
		"berry_trade":
			_begin_targeting("Berry trade: choose an enemy creature with berries.",
				func(p, s): return p != ME and _any_creature(p, s) and not view.opponent.board[s].berries.is_empty(), 1,
				func(t): _ask_trade_amount(slot, ai, t[0]))
		_:
			_submit({"type": "use_ability", "slot": slot, "ability": ai, "params": {}})


func _ask_trade_amount(slot: int, ai: int, target: Dictionary) -> void:
	var mine: Dictionary = view.you.board[slot]
	var theirs: Dictionary = view.opponent.board[target.slot]
	var max_n := mini(mine.berries.size(), theirs.berries.size())
	if max_n < 1:
		return _toast("Your creature has no berries to trade.")
	var d := ConfirmationDialog.new()
	d.title = "Berry trade"
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = "Discard how many of your attached berries?\n(You give up your least useful; you take their best.)"
	box.add_child(l)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = max_n
	spin.value = max_n
	box.add_child(spin)
	d.add_child(box)
	d.confirmed.connect(func():
		var n := int(spin.value)
		d.queue_free()
		var plan := Rules.plan_trade(mine, theirs, n)
		_submit({"type": "use_ability", "slot": slot, "ability": ai, "params": {
			"source_slot": slot, "target": target, "own": plan.own, "theirs": plan.theirs}}))
	d.canceled.connect(d.queue_free)
	_popup(d)


func _on_swap() -> void:
	var hand_idx: Array = []
	var labels: Array = []
	for i in view.you.hand.size():
		if CardDB.is_creature(view.you.hand[i]):
			hand_idx.append(i)
			labels.append(CardDB.card_name(view.you.hand[i]))
	var disc_idx: Array = []
	var disc_labels: Array = []
	for i in view.you.discard.size():
		if CardDB.is_creature(view.you.discard[i]):
			disc_idx.append(i)
			disc_labels.append(CardDB.card_name(view.you.discard[i]))
	if hand_idx.is_empty() or disc_idx.is_empty():
		return _toast("Swap needs a creature in your hand and one in your discard.")
	_pick_from_list("Swap: give which creature from your hand?", labels, func(h):
		_pick_from_list("Swap: take which creature from your discard?", disc_labels, func(d):
			_submit({"type": "swap", "hand": hand_idx[h], "discard": disc_idx[d]})))


# --- Game over ------------------------------------------------------------------------------------------------
func _on_game_over(winner: int) -> void:
	if _over_shown:
		return
	_over_shown = true
	var d := AcceptDialog.new()
	d.title = "Game over"
	d.dialog_text = "You win!" if winner == ME else "The computer wins."
	d.ok_button_text = "Rematch"
	d.add_button("Main Menu", false, "menu")
	d.confirmed.connect(func(): rematch_requested.emit())
	d.custom_action.connect(func(_a): exit_requested.emit())
	_popup(d)
