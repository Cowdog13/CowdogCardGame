class_name GameScreen
extends Control
## The playtest table. Reads only get_view(ME) from the controller and sends every
## move through controller.submit(), exactly like a networked client would.

signal exit_requested
signal rematch_requested

const ME := 0
const SLOT_SIZE := Vector2(232, 215)

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
var _piles: Array = [{}, {}]  # per seat: {"deck": PileView, "discard": ..., "exile": ...}
var fx_enabled := true
var _fx: FxLayer
var _opp_hand_row: Control
var _slot_nodes := {}  # "seat:slot" -> slot panel
var _hidden_slots := {}  # "seat:slot" -> number of effects still to land there
var _fx_queue: Array = []
var _fx_running := false
var _recycle_open := false


func start(deck_ids: Array, agents: Array, ai_delay: float, effects := true) -> void:
	fx_enabled = effects
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
	scroll.custom_minimum_size = Vector2(0, 275)
	# Never let a tall card grow the hand area (and push the table around).
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
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
	_detail.custom_minimum_size = Vector2(0, 150)
	_detail.text = "Hover a card for details."
	side.add_child(_make_pile_row(ME + 1, "Opponent"))
	side.add_child(_detail)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_log)
	side.add_child(_make_pile_row(ME, "You"))
	var menu_btn := Button.new()
	menu_btn.text = "Back to Menu"
	menu_btn.pressed.connect(func(): exit_requested.emit())
	side.add_child(menu_btn)

	# Opponent's hand as blank cards peeking in from the top of the screen.
	_opp_hand_row = Control.new()
	_opp_hand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_opp_hand_row)
	_fx = FxLayer.new()
	add_child(_fx)
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


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
	_opp_info.text = "Opponent - Hand %d" % opp.hand_count
	_set_piles(ME + 1, opp.deck_count, opp.discard.size(), opp.exile.size())
	_set_piles(ME, you.deck_count, you.discard.size(), you.exile.size())
	_my_info.text = "You%s" % _turn_flags(you)
	_rebuild_board(_opp_board, ME + 1)
	_rebuild_board(_my_board, ME)
	_rebuild_hand()
	_rebuild_opp_hand()
	var acting := _can_act()
	_end_btn.disabled = not acting or not _pending.is_empty()
	_swap_btn.disabled = not acting or you.swap_used
	match view.phase:
		"mulligan": _turn_label.text = "Mulligan"
		"over": _turn_label.text = "Game over"
		_: _turn_label.text = "Turn %d - %s" % [view.turn, "YOUR TURN" if acting else "Opponent's turn"]
	_update_banner()
	if not view.pending.is_empty() and view.pending.player == ME and _pending.is_empty():
		if not view.pending.berries.is_empty():
			var id: String = view.pending.berries.back()
			_begin_targeting("Choose a creature to receive the revealed %s (%d left)." % [CardDB.card_name(id), view.pending.berries.size()],
				func(p, s): return p == ME and view.you.board[s] != null, 1,
				func(t): _submit({"type": "place_berry", "slot": t[0].slot}), true)
		elif not _recycle_open:
			if not view.pending.ordering.is_empty():
				_ask_order(view.pending.ordering)
			else:
				_ask_recycle(int(view.pending.recycle))


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
	_cancel_btn.visible = not _pending.is_empty() and not _pending.get("locked", false)


func _can_act() -> bool:
	return view.phase == "main" and view.active == ME and view.pending.is_empty()


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
	_slot_nodes["%d:%d" % [seat, slot]] = panel
	if _hidden_slots.get("%d:%d" % [seat, slot], 0) > 0:
		panel.modulate.a = 0.0  # a card is still flying in
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
		empty.text = "Empty (%d)" % (slot + 1)
		empty.modulate = Color(1, 1, 1, 0.35)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(empty)
		return panel
	var top := Rules.top_card(creature)
	panel.mouse_entered.connect(func(): _show_creature_detail(creature))
	var title := Label.new()
	title.text = "%d. %s  (Tier %d)" % [slot + 1, top.name, int(top.tier)]
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
	for bi in creature.berries.size():
		var b: String = creature.berries[bi]
		var sideways: bool = creature.exhausted[bi]
		var chip := ColorRect.new()
		chip.custom_minimum_size = Vector2(26, 14) if sideways else Vector2(16, 24)  # sideways = exhausted
		chip.color = Rules.element_color(CardDB.element_of(b))
		chip.tooltip_text = CardDB.card_name(b) + (" (exhausted: exiled when discarded)" if sideways else "")
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chips.add_child(chip)
	if creature.berries.is_empty():
		var none := Label.new()
		none.text = "No berries"
		none.add_theme_font_size_override("font_size", 12)
		none.modulate = Color(1, 1, 1, 0.4)
		chips.add_child(none)
	box.add_child(chips)
	panel.set_meta("chips", chips)
	if Rules.is_stunned(creature, view.turn):
		var stun := Label.new()
		stun.text = "STUNNED"
		stun.modulate = Color(0.5, 0.85, 1)
		box.add_child(stun)
	var ability_nodes: Array = []
	panel.set_meta("abilities", ability_nodes)
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
			btn.disabled = not (_can_act() and _pending.is_empty() and met and not Rules.abilities_locked(view.turn) and not Rules.used_ability_this_turn(creature, view.turn)
				and not Rules.is_stunned(creature, view.turn) and view.you.abilities_used < Rules.ABILITIES_PER_TURN)
			btn.pressed.connect(_on_ability_pressed.bind(slot, ai))
			# A disabled button would swallow clicks meant for the creature (e.g. while targeting).
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE if btn.disabled else Control.MOUSE_FILTER_STOP
			box.add_child(btn)
			ability_nodes.append(btn)
		else:
			var l := Label.new()
			l.text = label
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.add_theme_font_size_override("font_size", 13)
			l.modulate = Color(1, 1, 1, 1.0 if met else 0.45)
			box.add_child(l)
			ability_nodes.append(l)
	return panel


func _rebuild_opp_hand() -> void:
	for c in _opp_hand_row.get_children():
		_opp_hand_row.remove_child(c)
		c.queue_free()
	var n: int = view.opponent.hand_count
	var center_x := (size.x - 330.0 - 40.0) / 2.0
	for i in n:
		var back := Panel.new()
		back.size = Vector2(70, 100)
		back.pivot_offset = back.size / 2.0
		back.add_theme_stylebox_override("panel", FxLayer.back_style(6))
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var off := float(i) - float(n - 1) / 2.0
		back.position = Vector2(center_x + off * minf(40.0, 560.0 / maxf(n, 1)) - 35.0, -62.0)
		back.rotation = off * 0.035
		_opp_hand_row.add_child(back)


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
	if fx_enabled and ev.has("fx"):
		_enqueue_fx(ev)
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
	d.min_size = Vector2(680, 640)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(320, 520)
	var order: Array = range(ids.size() - 1, -1, -1)  # newest on top
	for i in order:
		list.add_item(CardDB.card_name(ids[i]))
	d.add_child(_list_with_preview(list, func(k: int) -> String: return ids[order[k]]))
	d.canceled.connect(d.queue_free)
	d.confirmed.connect(d.queue_free)
	_popup(d)


## Modal list chooser; `labels` are shown, `on_pick` receives the chosen index.
func _pick_from_list(title: String, labels: Array, on_pick: Callable, card_ids: Array = []) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(320, 520 if not card_ids.is_empty() else 260)
	for l in labels:
		list.add_item(l)
	d.add_child(_list_with_preview(list, func(k: int) -> String: return card_ids[k]) if not card_ids.is_empty() else list)
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
func _begin_targeting(prompt: String, valid: Callable, max_targets: int, done: Callable, locked := false) -> void:
	_status = ""
	_pending = {"prompt": prompt, "valid": valid, "max": max_targets, "targets": [], "done": done, "locked": locked}
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
		_:
			_cast(i, {})


func _cast(i: int, params: Dictionary) -> void:
	var spell := CardDB.card(view.you.hand[i])
	_choose_payment(spell, func(payment: Array):
		_submit({"type": "play_spell", "hand": i, "payment": payment, "params": params}))


## Lets the player pick exactly which berries pay for `spell`. The cheapest payment is
## pre-selected, so confirming straight away behaves like an automatic payment.
func _choose_payment(spell: Dictionary, on_paid: Callable) -> void:
	var you: Dictionary = view.you
	var options: Array = []  # payment entries, parallel to the list items
	var labels: Array = []
	var berry_ids: Array = []
	for s in you.board.size():
		var c = you.board[s]
		if c == null:
			continue
		for bi in c.berries.size():
			if Rules.berry_matches(c.berries[bi], spell.cost.element):
				var sideways: bool = c.exhausted[bi]
				options.append({"src": "attached", "slot": s, "index": bi})
				berry_ids.append(c.berries[bi])
				labels.append("Creature %d (%s): %s, %s" % [s + 1, Rules.creature_name(c), CardDB.card_name(c.berries[bi]),
					"exhausted -> exile" if sideways else "upright -> discard"])
	for di in you.discard.size():
		if CardDB.is_berry(you.discard[di]) and Rules.berry_matches(you.discard[di], spell.cost.element):
			options.append({"src": "discard", "index": di})
			berry_ids.append(you.discard[di])
			labels.append("Your discard: %s (-> exile)" % CardDB.card_name(you.discard[di]))
	var plan := Rules.plan_payment(you, spell.cost)
	var preselect: Array = []
	for k in options.size():
		for entry in plan.get("payment", []):
			if entry.src == options[k].src and int(entry.index) == int(options[k].index) and int(entry.get("slot", -1)) == int(options[k].get("slot", -1)):
				preselect.append(k)
	_multi_pick("Pay for %s: choose %s" % [spell.name, Rules.cost_text(spell.cost)], labels, int(spell.cost.amount), preselect,
		"Pay", func(picked: Array): on_paid.call(picked.map(func(k): return options[k])), Callable(), berry_ids)


## Dialog where each click toggles an item; confirms only with exactly `need` selected.
func _multi_pick(title: String, labels: Array, need: int, preselect: Array, verb: String, on_ok: Callable, on_cancel: Callable, card_ids: Array = []) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	var list := ItemList.new()
	list.select_mode = ItemList.SELECT_TOGGLE  # a plain click selects / deselects
	list.custom_minimum_size = Vector2(460, 520 if not card_ids.is_empty() else 300)
	for l in labels:
		list.add_item(l)
	d.add_child(_list_with_preview(list, func(k: int) -> String: return card_ids[k]) if not card_ids.is_empty() else list)
	var update := func():
		var n := list.get_selected_items().size()
		d.get_ok_button().disabled = n != need
		d.get_ok_button().text = "%s (%d/%d)" % [verb, n, need]
	for k in preselect:
		list.select(k, false)
	list.multi_selected.connect(func(_i, _sel): update.call())
	list.item_selected.connect(func(_i): update.call())
	d.confirmed.connect(func():
		var picked: Array = Array(list.get_selected_items())
		d.queue_free()
		on_ok.call(picked))
	d.canceled.connect(func():
		d.queue_free()
		if on_cancel.is_valid():
			on_cancel.call())
	_popup(d)
	update.call()


## Firewolf: choose which cards from the discard go to the bottom of the deck, and in what order.
func _ask_recycle(n: int) -> void:
	var discard: Array = view.you.discard
	var order: Array = range(discard.size() - 1, -1, -1)  # newest first
	var labels: Array = order.map(func(i): return CardDB.card_name(discard[i]))
	var recycle_ids: Array = order.map(func(i): return discard[i])
	var suggested := Rules.recycle_pick(discard, n).map(func(i): return order.find(i))
	_recycle_open = true
	_ordered_pick("Recycle: choose %d card(s) and the order they go on the bottom of your deck" % n, labels, n, suggested, "Recycle",
		func(picked: Array):
			_recycle_open = false
			_submit({"type": "recycle", "cards": picked.map(func(k): return order[k])}),
		func():
			_recycle_open = false
			_refresh.call_deferred(),  # a recycle choice can't be skipped; ask again
		recycle_ids)


## Fire Famine: the pillaged non-berry cards are recycled; the player picks their order.
func _ask_order(ids: Array) -> void:
	var labels: Array = ids.map(func(id): return CardDB.card_name(id))
	_recycle_open = true
	_ordered_pick("Recycle: put the %d pillaged cards in order" % ids.size(), labels, ids.size(), range(ids.size()), "Recycle",
		func(picked: Array):
			_recycle_open = false
			_submit({"type": "order_recycle", "order": picked}),
		func():
			_recycle_open = false
			_refresh.call_deferred(),
		ids)


## Dialog where clicking a card numbers it 1, 2, 3... in the order clicked; clicking a numbered
## card removes its number (the later ones renumber). `need` cards must be numbered. The numbers are
## the order the cards are put on the bottom of the deck: 1 first, so the highest number ends up at
## the very bottom. `on_ok` receives the chosen list indices in order.
func _ordered_pick(title: String, labels: Array, need: int, initial: Array, verb: String, on_ok: Callable, on_cancel: Callable, card_ids: Array = []) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	var box := VBoxContainer.new()
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(380, 520 if not card_ids.is_empty() else 300)
	for l in labels:
		list.add_item(l)
	box.add_child(_list_with_preview(list, func(k: int) -> String: return card_ids[k]) if not card_ids.is_empty() else list)
	var hint := Label.new()
	hint.text = "Click cards to number them in the order they go on the bottom of the deck: 1 goes first (closest to the top), the highest number ends up at the very bottom. Click a numbered card to remove it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(620, 0)
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	d.add_child(box)
	var order: Array = Array(initial)
	var refresh := func():
		for i in labels.size():
			var pos := order.find(i)
			list.set_item_text(i, ("%d.  %s" % [pos + 1, labels[i]]) if pos >= 0 else ("      " + labels[i]))
			list.set_item_custom_bg_color(i, Color(0.25, 0.5, 0.25, 0.7) if pos >= 0 else Color(0, 0, 0, 0))
		list.deselect_all()
		d.get_ok_button().disabled = order.size() != need
		d.get_ok_button().text = "%s (%d/%d)" % [verb, order.size(), need]
	list.item_clicked.connect(func(i: int, _pos: Vector2, button: int):
		if button != MOUSE_BUTTON_LEFT:
			return
		var at := order.find(i)
		if at >= 0:
			order.remove_at(at)
		elif order.size() < need:
			order.append(i)
		refresh.call())
	d.add_button("Clear", false, "clear")
	d.custom_action.connect(func(_a):
		order.clear()
		refresh.call())
	d.confirmed.connect(func():
		d.queue_free()
		on_ok.call(order.duplicate()))
	d.canceled.connect(func():
		d.queue_free()
		if on_cancel.is_valid():
			on_cancel.call())
	_popup(d)
	refresh.call()


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


## Puts `list` next to a big preview of the card under the mouse (or the selected one).
## `card_at` maps a list index to a card id.
func _list_with_preview(list: ItemList, card_at: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(list)
	var holder := Control.new()
	holder.name = "Preview"
	holder.custom_minimum_size = Vector2(280, 540)
	row.add_child(holder)
	var show := func(k: int):
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		if k < 0:
			return
		var card := CardView.new().setup(card_at.call(k))
		card.size = Vector2(150, 250)
		card.scale = Vector2(1.8, 1.8)  # 270 x 450
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(card)
	list.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseMotion:
			show.call(list.get_item_at_position(ev.position, true)))
	list.mouse_exited.connect(func():
		var sel := list.get_selected_items()
		show.call(sel[0] if not sel.is_empty() else -1))
	list.item_selected.connect(func(k): show.call(k))
	list.item_clicked.connect(func(k, _pos, _btn): show.call(k))
	return row


## Opens a pile viewer. For your own discard it also offers to play a berry from there.
func _view_pile(seat: int, kind: String) -> void:
	var side: Dictionary = view.you if seat == ME else view.opponent
	var ids: Array = side.discard if kind == "discard" else side.exile
	var title := "%s %s" % ["Your" if seat == ME else "Opponent's", kind]
	if kind != "discard" or seat != ME:
		_show_pile(title, ids)
		return
	var d := AcceptDialog.new()
	d.title = "%s (%d)" % [title, ids.size()]
	d.ok_button_text = "Close"
	d.min_size = Vector2(700, 680)
	var box := VBoxContainer.new()
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(340, 520)
	var order: Array = range(ids.size() - 1, -1, -1)  # newest on top
	for i in order:
		list.add_item(CardDB.card_name(ids[i]))
	box.add_child(_list_with_preview(list, func(k: int) -> String: return ids[order[k]]))
	var hint := Label.new()
	hint.text = "Select a berry to play it from here (it enters exhausted and uses your berry for the turn)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(620, 0)  # without a width, an autowrapping label makes the dialog huge
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	d.add_child(box)
	var play := d.add_button("Play berry from discard", false, "play")
	var can_play: bool = _can_act() and not view.you.berry_attached and _pending.is_empty() \
		and view.you.board.any(func(c): return c != null)
	play.disabled = true
	list.item_selected.connect(func(k): play.disabled = not (can_play and CardDB.is_berry(ids[order[k]])))
	list.item_activated.connect(func(k):
		if can_play and CardDB.is_berry(ids[order[k]]):
			play.pressed.emit())
	d.custom_action.connect(func(_a):
		var sel := list.get_selected_items()
		if sel.is_empty():
			return
		var di: int = order[sel[0]]
		d.queue_free()
		_begin_targeting("Attach %s from your discard to which creature? (enters exhausted)" % CardDB.card_name(ids[di]),
			func(p, s): return p == ME and view.you.board[s] != null, 1,
			func(t): _submit({"type": "attach_berry", "from": "discard", "discard": di, "slot": t[0].slot})))
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	_popup(d)


func _make_pile_row(seat: int, heading: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var l := Label.new()
	l.text = heading
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(1, 1, 1, 0.6)
	box.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for kind in ["deck", "discard", "exile"]:
		var pile := PileView.new().setup(kind, kind != "deck")
		if kind != "deck":
			pile.clicked.connect(func(): _view_pile(seat, kind))
		row.add_child(pile)
		_piles[seat][kind] = pile
	return box


func _set_piles(seat: int, deck: int, discard: int, exile: int) -> void:
	_piles[seat].deck.set_count(deck)
	_piles[seat].discard.set_count(discard)
	_piles[seat].exile.set_count(exile)


func _pile_rect(seat: int, kind: String) -> Rect2:
	var pile: Control = _piles[seat].get(kind)
	if pile != null and is_instance_valid(pile):
		return pile.get_global_rect()
	return Rect2(size / 2.0, Vector2(84, 96))


func _on_swap() -> void:
	var hand_idx: Array = []
	var labels: Array = []
	var hand_ids: Array = []
	for i in view.you.hand.size():
		if CardDB.is_creature(view.you.hand[i]):
			hand_idx.append(i)
			labels.append(CardDB.card_name(view.you.hand[i]))
			hand_ids.append(view.you.hand[i])
	var disc_idx: Array = []
	var disc_labels: Array = []
	var disc_ids: Array = []
	for i in view.you.discard.size():
		if CardDB.is_creature(view.you.discard[i]):
			disc_idx.append(i)
			disc_labels.append(CardDB.card_name(view.you.discard[i]))
			disc_ids.append(view.you.discard[i])
	if hand_idx.is_empty() or disc_idx.is_empty():
		return _toast("Swap needs a creature in your hand and one in your discard.")
	_pick_from_list("Swap: give which creature from your hand?", labels, func(h):
		_pick_from_list("Swap: take which creature from your discard?", disc_labels, func(d):
			_submit({"type": "swap", "hand": hand_idx[h], "discard": disc_idx[d]}), disc_ids),
		hand_ids)


# --- Visual effects -------------------------------------------------------------------------------------
## Events are queued and played one after another. Start positions are captured now, while
## the hand still shows the card that was just played; playback starts a frame later, after
## the table has been rebuilt for the new state.
func _enqueue_fx(ev: Dictionary) -> void:
	var item := {"ev": ev, "src": _fx_source_rect(ev)}
	_fx_queue.append(item)
	var key := _fx_hide_key(ev)
	if key != "":
		_hidden_slots[key] = int(_hidden_slots.get(key, 0)) + 1
	controller.hold_ai = true
	if not _fx_running:
		_run_fx_queue.call_deferred()


func _fx_hide_key(ev: Dictionary) -> String:
	return "%d:%d" % [ev.player, ev.slot] if ev.fx == "play_creature" else ""


func _fx_source_rect(ev: Dictionary) -> Rect2:
	var mine: bool = int(ev.player) == ME
	if ev.fx == "swap" or ev.fx == "ability" or ev.fx == "stun":
		return Rect2()
	if ev.fx == "attach" and ev.from == "discard" or ev.fx == "play_creature" and int(ev.hand) < 0:
		return _pile_rect(int(ev.player), "discard")
	var idx := int(ev.hand)
	if mine:
		if idx >= 0 and idx < _hand_box.get_child_count():
			return _hand_box.get_child(idx).get_global_rect()
		return Rect2(Vector2(size.x / 2.0, size.y), Vector2(150, 250))
	var n := _opp_hand_row.get_child_count()
	if n == 0:
		return Rect2(Vector2(size.x / 2.0 - 35.0, -60.0), Vector2(70, 100))
	return _opp_hand_row.get_child(clampi(idx, 0, n - 1)).get_global_rect()


func _slot_rect(seat: int, slot: int) -> Rect2:
	var node: Control = _slot_nodes.get("%d:%d" % [seat, slot])
	if node != null and is_instance_valid(node):
		return node.get_global_rect()
	return Rect2(size / 2.0, SLOT_SIZE)


func _run_fx_queue() -> void:
	_fx_running = true
	await get_tree().process_frame
	while not _fx_queue.is_empty():
		var item: Dictionary = _fx_queue.pop_front()
		await _play_fx(item.ev, item.src)
		var key := _fx_hide_key(item.ev)
		if key != "":
			_hidden_slots[key] = maxi(int(_hidden_slots.get(key, 1)) - 1, 0)
			if view != {}:
				_refresh()
	controller.hold_ai = false
	_fx_running = false


func _play_fx(ev: Dictionary, src: Rect2) -> void:
	var mine: bool = int(ev.player) == ME
	match ev.fx:
		"play_creature":
			var target := _slot_rect(ev.player, ev.slot)
			if int(ev.hand) < 0:  # Reinforce: comes out of the discard pile
				await _fx.play_card(ev.card, src, 0.6, [target], false)
			else:
				await _fx.play_card(ev.card, src, 0.0 if mine else 2.0, [target], not mine)
		"spell":
			var targets: Array = []
			for t in ev.targets:
				targets.append(_slot_rect(int(t.player), int(t.slot)))
			await _fx.play_card(ev.card, src, 2.0, targets, not mine)
		"attach":
			await _play_attach(ev, src, mine)
		"ability":
			var panel: Control = _slot_nodes.get("%d:%d" % [ev.player, ev.slot])
			var rect := _slot_rect(ev.player, ev.slot)
			if panel != null and is_instance_valid(panel) and panel.has_meta("abilities"):
				var nodes: Array = panel.get_meta("abilities")
				if int(ev.ability) < nodes.size() and is_instance_valid(nodes[int(ev.ability)]):
					rect = nodes[int(ev.ability)].get_global_rect()
			await _fx.flash(rect, 1.5)
		"stun":
			var origin: Vector2
			if int(ev.from_slot) >= 0:
				origin = _slot_rect(ev.player, ev.from_slot).get_center()
			else:  # a spell: the bolt starts on the caster's side of the table
				origin = Vector2(size.x / 2.0 - 160.0, size.y - 30.0 if mine else 20.0)
			var points: Array = []
			for t in ev.targets:
				points.append(_slot_rect(int(t.player), int(t.slot)).get_center())
			await _fx.stun_bolts(origin, points)
		"swap":
			await _fx.show_pair(ev.hand_card, ev.discard_card, "From hand", "From discard", 2.0)


func _play_attach(ev: Dictionary, src: Rect2, mine: bool) -> void:
	var target := _slot_rect(ev.player, ev.slot)
	if ev.from == "discard":
		_fx.firework(src.get_center())  # sparks over the pile as the card leaves it
		await _fx.play_card(ev.card, src, 0.0, [target], false, 1.3)
	else:
		await _fx.play_card(ev.card, src, 0.0 if mine else 0.7, [target], not mine, 1.3)
	var panel: Control = _slot_nodes.get("%d:%d" % [ev.player, ev.slot])
	var spot := target.get_center()
	if panel != null and is_instance_valid(panel) and panel.has_meta("chips"):
		var chips: Control = panel.get_meta("chips")
		if is_instance_valid(chips) and chips.get_child_count() > 0:
			spot = chips.get_child(chips.get_child_count() - 1).get_global_rect().get_center()
	_fx.burst(spot + Vector2(0, -8), Rules.element_color(CardDB.element_of(ev.card)), 30, 170.0, 0.7)
	_fx.blink(_slot_rect(ev.player, ev.slot))
	await get_tree().create_timer(0.8).timeout


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
