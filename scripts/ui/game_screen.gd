class_name GameScreen
extends Control
## The playtest table. Reads only get_view(ME) from the controller and sends every
## move through controller.submit(), exactly like a networked client would.
##
## Layout (1600x900 design, scales with the window): the board and hand on the left, a column
## on the right with the piles, the big card preview and the buttons. Written with anchors and
## containers so a phone layout can later swap the right column for popups.

signal exit_requested
signal rematch_requested

var ME := 0  # the seat shown at the bottom of the screen (your seat)
var OPP := 1
const RIGHT_W := 332.0

var controller: Node  # GameController, or a RemoteController when joined to someone else's game
var view: Dictionary = {}

var _pending: Dictionary = {}  # active targeting: prompt, valid, max, targets, done
var _mull_sel := {}
var _status := ""
var _over_shown := false
var _allow_rematch := true
var tutorial_mode := false  # the tutorial runs this game: the Menu button just leaves, no surrender

var _opp_info: Label
var _last_event: Label
var _turn_label: Label
var _opp_board: HBoxContainer
var _my_board: HBoxContainer
var _hand_view: HandView
var _banner: Label
var _banner_panel: PanelContainer
var _banner_icon: TextureRect
var _confirm_btn: Button
var _cancel_btn: Button
var _end_btn: Button
var _swap_btn: Button
var _preview_holder: Control
var _preview_note: Label
var _preview_id := ""
var _log_bbcode := ""
var _piles: Array = [{}, {}]  # per seat: {"deck": PileView, "discard": ..., "exile": ...}
var fx_enabled := true
var _fx: FxLayer
var _opp_hand_row: Control
var _slot_nodes := {}  # "seat:slot" -> BoardCreature
var _hidden_slots := {}  # "seat:slot" -> number of effects still to land there
var _fx_queue: Array = []
var _fx_running := false
var _recycle_open := false
var _ability_lock_until := 0  # ms; ignores ability clicks right after another click (double-click protection)
var _ghosts := {}  # destroyed creatures kept on screen until the spell that destroys them has landed


func start(deck_ids: Array, agents: Array, ai_delay: float, effects := true) -> void:
	fx_enabled = effects
	_build_ui()
	controller = GameController.new()
	controller.ai_delay = ai_delay
	add_child(controller)
	_connect_controller()
	controller.start(deck_ids, agents)
	_refresh()


## Shows a game that is run elsewhere: the host's own controller, or a RemoteController that mirrors
## the host's game. `my_seat` is the seat shown at the bottom. Rematch needs a local game, so it is
## offered only when `allow_rematch` is set.
func attach(p_controller: Node, my_seat: int, effects := true, allow_rematch := false) -> void:
	ME = my_seat
	OPP = 1 - my_seat
	fx_enabled = effects
	_allow_rematch = allow_rematch
	_build_ui()
	controller = p_controller
	if controller.get_parent() == null:
		add_child(controller)
	# Replay what already happened (the opening log lines) without effects, then follow live.
	var past: Array = controller.get("history") if controller.get("history") != null else []
	for ev in past:
		_log_event(ev)
	_connect_controller()
	_refresh()


func _connect_controller() -> void:
	controller.event_logged.connect(_on_event)
	controller.view_updated.connect(_refresh)
	controller.game_over.connect(_on_game_over)
	if controller.has_signal("action_rejected"):
		controller.action_rejected.connect(_toast)


# --- Layout ----------------------------------------------------------------------------
func _build_ui() -> void:
	var tex := ArtDB.board_background()
	if tex != null:
		var bg := TextureRect.new()
		bg.texture = tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var flat := ColorRect.new()
		flat.color = Color(0.09, 0.15, 0.2)
		add_child(flat)
		flat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Left: info row, opponent board, status strip, my board.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	add_child(left)
	left.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left.offset_left = 14
	left.offset_top = 6
	left.offset_right = -(RIGHT_W + 20)
	left.offset_bottom = -6

	var opp_row := HBoxContainer.new()
	opp_row.custom_minimum_size = Vector2(0, 26)
	left.add_child(opp_row)
	_opp_info = Label.new()
	_opp_info.add_theme_font_size_override("font_size", 15)
	_opp_info.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_opp_info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_opp_info.add_theme_constant_override("outline_size", 5)
	opp_row.add_child(_opp_info)
	_last_event = Label.new()
	_last_event.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_last_event.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_last_event.add_theme_font_size_override("font_size", 14)
	_last_event.add_theme_color_override("font_color", Color(1, 0.95, 0.75, 1.0))
	_last_event.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_last_event.add_theme_constant_override("outline_size", 5)
	_last_event.clip_text = true
	opp_row.add_child(_last_event)
	_opp_board = _board_row(left)

	var mid := HBoxContainer.new()
	mid.custom_minimum_size = Vector2(0, 46)
	mid.add_theme_constant_override("separation", 10)
	left.add_child(mid)
	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 18)
	_turn_label.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	_turn_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_turn_label.add_theme_constant_override("outline_size", 5)
	mid.add_child(_turn_label)
	_banner_panel = PanelContainer.new()
	var banner_panel := _banner_panel
	banner_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.06, 0.1, 0.14, 0.7), 12, Color(0.85, 0.72, 0.38, 0.6), 2, 6))
	mid.add_child(banner_panel)
	var banner_row := HBoxContainer.new()
	banner_row.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_row.add_theme_constant_override("separation", 8)
	banner_panel.add_child(banner_row)
	_banner_icon = TextureRect.new()  # the berry being placed (Plunder / Pillage)
	_banner_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_banner_icon.custom_minimum_size = Vector2(46, 46)
	_banner_icon.visible = false
	banner_row.add_child(_banner_icon)
	_banner = Label.new()
	_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_theme_font_size_override("font_size", 16)
	banner_row.add_child(_banner)
	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm"
	_confirm_btn.pressed.connect(_on_confirm)
	mid.add_child(_confirm_btn)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_cancel)
	mid.add_child(_cancel_btn)
	_my_board = _board_row(left)

	# Hand: along the bottom edge of the left area.
	_hand_view = HandView.new()
	add_child(_hand_view)
	_hand_view.anchor_left = 0.0
	_hand_view.anchor_right = 1.0
	_hand_view.anchor_top = 1.0
	_hand_view.anchor_bottom = 1.0
	_hand_view.offset_left = 14
	_hand_view.offset_right = -(RIGHT_W + 20)
	_hand_view.offset_top = -180
	_hand_view.offset_bottom = 0
	_hand_view.card_clicked.connect(_on_hand_clicked)
	_hand_view.card_hovered.connect(_show_card_detail)

	# Right column: opponent piles, big card preview, my piles, buttons.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	add_child(right)
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.anchor_top = 0.0
	right.anchor_bottom = 1.0
	right.offset_left = -(RIGHT_W + 8)
	right.offset_right = -8
	right.offset_top = 6
	right.offset_bottom = -6
	right.add_child(_make_pile_row(OPP))
	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.05, 0.09, 0.13, 0.62), 14, Color(0.85, 0.72, 0.38, 0.5), 2, 8))
	right.add_child(preview_panel)
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 4)
	preview_panel.add_child(pbox)
	_preview_holder = Control.new()
	_preview_holder.custom_minimum_size = Vector2(0, 340)
	_preview_holder.resized.connect(_center_preview)
	_preview_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pbox.add_child(_preview_holder)
	_preview_note = Label.new()
	_preview_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_note.add_theme_font_size_override("font_size", 14)
	_preview_note.custom_minimum_size = Vector2(0, 34)
	_preview_note.text = "Hover a card to see it larger."
	_preview_note.modulate = Color(1, 1, 1, 0.85)
	pbox.add_child(_preview_note)
	right.add_child(_make_pile_row(ME))
	_end_btn = Button.new()
	_end_btn.text = "End Turn"
	_end_btn.custom_minimum_size = Vector2(0, 44)
	_end_btn.pressed.connect(func(): _submit({"type": "end_turn"}))
	right.add_child(_end_btn)
	var small := HBoxContainer.new()
	small.add_theme_constant_override("separation", 6)
	right.add_child(small)
	_swap_btn = Button.new()
	_swap_btn.text = "Swap"
	_swap_btn.tooltip_text = "Once per game: swap a creature in your hand with one in your discard"
	_swap_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_swap_btn.pressed.connect(_on_swap)
	small.add_child(_swap_btn)
	var log_btn := Button.new()
	log_btn.text = "Log"
	log_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_btn.pressed.connect(_show_log)
	small.add_child(log_btn)
	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_btn.pressed.connect(_on_menu_pressed)
	small.add_child(menu_btn)

	# Opponent's hand as card backs peeking in from the top of the screen.
	_opp_hand_row = Control.new()
	_opp_hand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_opp_hand_row)
	_fx = FxLayer.new()
	add_child(_fx)
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _board_row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size = Vector2(0, BoardCreature.widget_size().y)
	parent.add_child(row)
	return row


# --- Refresh -----------------------------------------------------------------------------
func _refresh() -> void:
	view = controller.get_view(ME)
	if view.is_empty():
		return  # a networked game before the host's first update
	var you: Dictionary = view.you
	var opp: Dictionary = view.opponent
	_opp_info.text = "%s  -  %d card(s) in hand" % [_opp_name(), opp.hand_count]
	_set_piles(OPP, opp)
	_set_piles(ME, you)
	_rebuild_board(_opp_board, OPP)
	_rebuild_board(_my_board, ME)
	_rebuild_hand()
	_rebuild_opp_hand()
	var acting := _can_act()
	_end_btn.disabled = not acting or not _pending.is_empty()
	_swap_btn.disabled = not acting or you.swap_used
	match view.phase:
		"mulligan": _turn_label.text = "Mulligan"
		"over": _turn_label.text = "Game over"
		_: _turn_label.text = "Turn %d - %s%s" % [view.turn, "YOUR TURN" if acting else "%s's turn" % _opp_name(), _turn_flags(you)]
	_update_banner()
	if not view.pending.is_empty() and view.pending.player == ME and _pending.is_empty() and not _fx_busy():
		if not view.pending.berries.is_empty():
			var id: String = view.pending.berries.back()
			_begin_targeting("Choose a creature to receive the %s (%d left)." % [CardDB.card_name(id), view.pending.berries.size()],
				func(p, s): return p == ME and view.you.board[s] != null, 1,
				func(t): _submit({"type": "place_berry", "slot": t[0].slot}), true)
			_pending["icon"] = id
			_show_card_detail(id)  # the big preview shows exactly which berry this is
			_update_banner()
		elif not _recycle_open:
			if not view.pending.ordering.is_empty():
				_ask_order(view.pending.ordering)
			else:
				_ask_recycle(int(view.pending.recycle))


## The Menu button never leaves by accident: it always asks first. In a multiplayer game it is also
## the way to surrender - confirming concedes the game (you lose) and the result screen follows.
func _on_menu_pressed() -> void:
	if view.get("phase", "over") == "over":
		exit_requested.emit()
		return
	if tutorial_mode:
		_confirm("Leave the tutorial?", "You can start it again from the main menu.", func(): exit_requested.emit())
	elif _allow_rematch:  # single player
		_confirm("Leave the game?", "The game in progress will be lost.", func(): exit_requested.emit())
	else:
		_confirm("Surrender?", "You will lose this game and your opponent wins.", func():
			controller.submit(ME, {"type": "concede"}))


## Screen rectangle of something the tutorial points at: "hand:<card id>", "mine:<creature id>",
## "theirs:<creature id>" (the creature whose top card that is), "end_turn", "swap", "discard".
func tutorial_target_rect(target: String) -> Rect2:
	if view.is_empty():
		return Rect2()
	var parts := target.split(":")
	match parts[0]:
		"hand":
			var i: int = view.you.hand.find(parts[1])
			return _hand_view.card_rect(i) if i >= 0 else Rect2()
		"mine", "theirs":
			var seat := ME if parts[0] == "mine" else OPP
			var side: Dictionary = view.you if seat == ME else view.opponent
			for s in side.board.size():
				if side.board[s] != null and Rules.top_card(side.board[s]).id == parts[1]:
					return _slot_rect(seat, s)
		"end_turn": return _end_btn.get_global_rect()
		"swap": return _swap_btn.get_global_rect()
		"discard": return _pile_rect(ME, "discard")
	return Rect2()


func _opp_name() -> String:
	var names: Array = view.get("names", [])
	return String(names[OPP]) if _allow_rematch == false and OPP < names.size() else "Opponent"


func _turn_flags(you: Dictionary) -> String:
	if view.phase != "main" or view.active != ME:
		return ""
	return "   |   Berry %s   Creature %s   Abilities %d/%d" % [
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
	var icon_id := String(_pending.get("icon", "")) if not _pending.is_empty() else ""
	_banner_icon.texture = ArtDB.berry_icon(icon_id) if icon_id != "" else null
	_banner_icon.visible = _banner_icon.texture != null
	_banner_panel.visible = text != ""  # no shaded box when there is nothing to say
	_confirm_btn.visible = show_confirm
	_cancel_btn.visible = not _pending.is_empty() and not _pending.get("locked", false)


func _can_act() -> bool:
	return view.phase == "main" and view.active == ME and view.pending.is_empty()


func _rebuild_board(row: HBoxContainer, seat: int) -> void:
	for c in row.get_children():
		c.queue_free()
		row.remove_child(c)
	for key in _slot_nodes.keys():
		if key.begins_with("%d:" % seat):
			_slot_nodes.erase(key)
	var side: Dictionary = view.you if seat == ME else view.opponent
	for slot in Rules.BOARD_SLOTS:
		var creature = side.board[slot]
		if creature == null:
			continue
		var valid: bool = not _pending.is_empty() and _pending.valid.call(seat, slot)
		var chosen := _target_index(seat, slot) >= 0
		var w := BoardCreature.new().setup(creature, slot, seat == ME, view.turn, valid, chosen)
		w.clicked.connect(_on_slot_clicked.bind(seat, slot))
		w.hovered.connect(_show_creature_detail)
		if seat == ME:
			w.ability_pressed.connect(func(i): _on_ability_pressed(slot, i))
			var abilities: Array = Rules.top_card(creature).abilities
			var usable: Array = []
			var affordable: Array = []
			for ai in abilities.size():
				var ab: Dictionary = abilities[ai]
				var met := Rules.meets_cost(creature.berries, ab.cost)
				affordable.append(met or ab.get("active", false))
				usable.append(not ab.get("active", false) and _can_act() and _pending.is_empty() and met
					and not Rules.abilities_locked(view.turn) and not Rules.used_ability_this_turn(creature, view.turn)
					and not Rules.is_stunned(creature, view.turn) and view.you.abilities_used < Rules.ABILITIES_PER_TURN)
			w.set_ability_states(usable, affordable)
		_slot_nodes["%d:%d" % [seat, slot]] = w
		if _hidden_slots.get("%d:%d" % [seat, slot], 0) > 0:
			w.modulate.a = 0.0  # a card is still flying in
		row.add_child(w)
	# A creature destroyed by a spell stays visible (untouchable) until the spell's card has landed on it.
	for g in _ghosts.get(seat, []):
		var gw := BoardCreature.new().setup(g.creature, int(g.slot), false, view.turn, false, false)
		gw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(gw)
		row.move_child(gw, mini(int(g.slot), row.get_child_count() - 1))


func _rebuild_opp_hand() -> void:
	for c in _opp_hand_row.get_children():
		_opp_hand_row.remove_child(c)
		c.queue_free()
	var n: int = view.opponent.hand_count
	var center_x := (size.x - RIGHT_W - 20.0) / 2.0
	for i in n:
		var back := CardBack.new().setup(Vector2(70, 98))
		back.pivot_offset = back.size / 2.0
		var off := float(i) - float(n - 1) / 2.0
		back.position = Vector2(center_x + off * minf(40.0, 560.0 / maxf(n, 1)) - 35.0, -66.0)
		back.rotation = off * 0.035
		_opp_hand_row.add_child(back)


func _rebuild_hand() -> void:
	var hand: Array = view.you.hand
	var marks: Array = []
	for i in hand.size():
		var mark := CardView.Mark.NONE
		if view.phase == "mulligan" and not view.you.mulligan_done:
			mark = CardView.Mark.SELECTED if _mull_sel.has(i) else CardView.Mark.SELECTABLE
		marks.append(mark)
	_hand_view.set_hand(hand, marks, view.phase == "mulligan")


# --- Preview / log / dialogs -------------------------------------------------------------------
func _set_preview(id: String, note: String) -> void:
	if id != _preview_id:
		_preview_id = id
		for c in _preview_holder.get_children():
			_preview_holder.remove_child(c)
			c.queue_free()
		var cv := CardView.new().setup(id, CardView.Mark.NONE, Vector2(288, 403))
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview_holder.add_child(cv)
		_center_preview()
	_preview_note.text = note


func _center_preview() -> void:
	for c in _preview_holder.get_children():
		c.position = Vector2((_preview_holder.size.x - c.size.x) / 2.0, maxf((_preview_holder.size.y - c.size.y) / 2.0, 0.0))


func _show_card_detail(id: String) -> void:
	_set_preview(id, "")


func _show_creature_detail(creature: Dictionary) -> void:
	var counts := {}
	for b in creature.berries:
		counts[CardDB.card_name(b)] = int(counts.get(CardDB.card_name(b), 0)) + 1
	var berries := ", ".join(counts.keys().map(func(k): return "%d %s" % [counts[k], k]))
	_set_preview(Rules.top_card(creature).id, "Attached: %s" % (berries if berries != "" else "no berries"))


func _on_event(ev: Dictionary) -> void:
	if fx_enabled and ev.has("fx"):
		_enqueue_fx(ev)
	_log_event(ev)


func _log_event(ev: Dictionary) -> void:
	var color := "#cfd8d3"
	match int(ev.player):
		ME: color = "#8fc7ff"
		OPP: color = "#ffb27a"
	match ev.kind:
		"turn": _log_bbcode += "\n[b][color=#ffe27a]%s[/color][/b]\n" % ev.text
		"win": _log_bbcode += "[b][color=#ff7a7a]%s[/color][/b]\n" % ev.text
		_: _log_bbcode += "[color=%s]%s[/color]\n" % [color, ev.text]
	if ev.kind != "turn":
		_last_event.text = ev.text


func _show_log() -> void:
	var d := AcceptDialog.new()
	d.title = "Game log"
	d.min_size = Vector2(620, 560)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.custom_minimum_size = Vector2(580, 480)
	rt.text = _log_bbcode
	rt.scroll_following = true
	d.add_child(rt)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	_popup(d)


func _toast(msg: String) -> void:
	_status = msg
	_update_banner()


func _popup(dialog: Window) -> void:
	add_child(dialog)
	dialog.popup_centered()


## Pile contents for the viewers: identical cards are grouped ("Firespore x3") and the groups are sorted
## by type (creatures, spells, berries). Returns rows: {"header": text} or {"id", "count", "index"} where
## `index` is the position in the pile of the newest copy.
func _pile_rows(ids: Array) -> Array:
	var groups := {}
	for i in ids.size():
		var g: Dictionary = groups.get(ids[i], {"id": ids[i], "count": 0, "index": i})
		g.count += 1
		g.index = i
		groups[ids[i]] = g
	var rows: Array = []
	for kind in [["creature", "Creatures"], ["spell", "Spells"], ["berry", "Berries"]]:
		var of_kind: Array = groups.values().filter(func(g): return CardDB.kind(g.id) == kind[0])
		if of_kind.is_empty():
			continue
		of_kind.sort_custom(func(a, b):
			var ta := int(CardDB.card(a.id).get("tier", 0))
			var tb := int(CardDB.card(b.id).get("tier", 0))
			return CardDB.card_name(a.id) < CardDB.card_name(b.id) if ta == tb else ta < tb)
		var total := 0
		for g in of_kind:
			total += g.count
		rows.append({"header": "%s (%d)" % [kind[1], total]})
		rows.append_array(of_kind)
	return rows


## Fills `list` from _pile_rows(); headers can't be selected.
func _fill_pile_list(list: ItemList, rows: Array) -> void:
	for r in rows:
		if r.has("header"):
			var k := list.add_item("- %s -" % r.header, null, false)
			list.set_item_custom_fg_color(k, Color(0.95, 0.82, 0.4))
		else:
			list.add_item("x%d   %s" % [r.count, CardDB.card_name(r.id)])


func _show_pile(title: String, ids: Array) -> void:
	var d := AcceptDialog.new()
	d.title = "%s (%d)" % [title, ids.size()]
	d.min_size = Vector2(680, 640)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(320, 520)
	var rows := _pile_rows(ids)
	_fill_pile_list(list, rows)
	d.add_child(_list_with_preview(list, func(k: int) -> String: return rows[k].get("id", "")))
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
	_lock_abilities()
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


## Submits and returns (used to end a click handler that needs no further input).
func _submit_action_only(action: Dictionary) -> void:
	_submit(action)


func _submit(action: Dictionary) -> bool:
	_lock_abilities()
	var res: Dictionary = controller.submit(ME, action)
	_status = "" if res.ok else String(res.error)
	_refresh()
	return res.ok


# --- Hand interaction -------------------------------------------------------------------------------
func _on_hand_clicked(i: int) -> void:
	_lock_abilities(450)
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
			var mine: Array = []
			for s in view.you.board.size():
				if view.you.board[s] != null:
					mine.append(s)
			if mine.is_empty():
				return _toast("You need a creature to attach a berry to.")
			if mine.size() == 1:
				return _submit_action_only({"type": "attach_berry", "hand": i, "slot": mine[0]})
			_begin_targeting("Attach %s to which of your creatures?" % CardDB.card_name(id),
				func(p, s): return p == ME and view.you.board[s] != null, 1,
				func(t): _submit({"type": "attach_berry", "hand": i, "slot": t[0].slot}))
		"creature":
			if view.you.creature_played:
				return _toast("You already played a creature this turn.")
			if int(CardDB.card(id).tier) <= 1:
				var free := Rules.first_free_slot(view.you.board)
				if free < 0:
					return _toast("You already have %d creatures - the board is full." % Rules.BOARD_SLOTS)
				return _submit_action_only({"type": "play_creature", "hand": i, "slot": free})
			var options: Array = []
			for s in view.you.board.size():
				if Rules.place_error(view.you.board, id, s) == "":
					options.append(s)
			if options.is_empty():
				return _toast("%s must be played on %s." % [CardDB.card_name(id), CardDB.card_name(CardDB.card(id).evolves_from)])
			if options.size() == 1:
				return _submit_action_only({"type": "play_creature", "hand": i, "slot": options[0]})
			_begin_targeting("Evolve which creature into %s?" % CardDB.card_name(id),
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
		"exile_discard":
			_ask_exile_cards(spell, view.you.discard, func(chosen: Array):
				# The payment may not use the very cards that are being exiled.
				var blocked: Array = []
				for cid in chosen:
					for di in range(view.you.discard.size() - 1, -1, -1):
						if view.you.discard[di] == cid and not blocked.has(di):
							blocked.append(di)
							break
				_cast(i, {"cards": chosen}, blocked))
		_:
			_cast(i, {})


func _cast(i: int, params: Dictionary, blocked: Array = []) -> void:
	var spell := CardDB.card(view.you.hand[i])
	_choose_payment(spell, func(payment: Array):
		_submit({"type": "play_spell", "hand": i, "payment": payment, "params": params}), blocked)


## Lets the player pick exactly which berries pay for `spell`. The cheapest payment is
## pre-selected, so confirming straight away behaves like an automatic payment.
func _choose_payment(spell: Dictionary, on_paid: Callable, blocked: Array = []) -> void:
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
		if not blocked.has(di) and CardDB.is_berry(you.discard[di]) and Rules.berry_matches(you.discard[di], spell.cost.element):
			options.append({"src": "discard", "index": di})
			berry_ids.append(you.discard[di])
			labels.append("Your discard: %s (-> exile)" % CardDB.card_name(you.discard[di]))
	var plan := Rules.plan_payment(you, spell.cost, blocked)
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
	_recycle_open = true
	_ordered_pick("Recycle: choose %d card(s) and the order they go on the bottom of your deck" % n, discard, n, Rules.recycle_pick(discard, n), "Recycle",
		func(picked: Array):
			_recycle_open = false
			_submit({"type": "recycle", "cards": picked}),
		func():
			_recycle_open = false
			_refresh.call_deferred())  # a recycle choice can't be skipped; ask again


## Fire Famine: the pillaged non-berry cards are recycled; the player picks their order.
func _ask_order(ids: Array) -> void:
	_recycle_open = true
	_ordered_pick("Recycle: put the %d pillaged cards in order" % ids.size(), ids, ids.size(), range(ids.size()), "Recycle",
		func(picked: Array):
			_recycle_open = false
			_submit({"type": "order_recycle", "order": picked}),
		func():
			_recycle_open = false
			_refresh.call_deferred())


## Dialog for choosing cards in an order. Identical cards are grouped like the pile viewers ("Firespore x3");
## each click on a group numbers one more copy (1, 2, 3... in click order). Clicking a group whose copies are
## all numbered, or right-clicking, removes its last number; Clear removes all. `need` cards must be numbered.
## The numbers are the order the cards go on the bottom of the deck: 1 first, so the highest number ends up
## at the very bottom. `initial` lists cards (indices into `card_ids`) that start out numbered. `on_ok` receives
## the chosen indices into `card_ids`, in order.
func _ordered_pick(title: String, card_ids: Array, need: int, initial: Array, verb: String, on_ok: Callable, on_cancel: Callable, hint_text := "", ordered := true) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	var box := VBoxContainer.new()
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(380, 520)
	var rows := _pile_rows(card_ids)
	_fill_pile_list(list, rows)
	var copies := {}  # row -> indices into card_ids of its cards, newest (highest index) first
	for k in rows.size():
		if rows[k].has("id"):
			var idx: Array = []
			for i in range(card_ids.size() - 1, -1, -1):
				if card_ids[i] == rows[k].id:
					idx.append(i)
			copies[k] = idx
	box.add_child(_list_with_preview(list, func(k: int) -> String: return rows[k].get("id", "")))
	var hint := Label.new()
	hint.text = hint_text if hint_text != "" else "Click a card to number it: 1 goes on the bottom of the deck first (closest to the top), the highest number ends up at the very bottom. Click a stack again to number another copy. Right-click (or click a stack whose copies are all numbered) to remove the last number."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(620, 0)
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	d.add_child(box)
	var order: Array = []  # row indices, one entry per numbered card
	for ci in initial:
		for k in rows.size():
			if rows[k].get("id", "") == card_ids[ci] and order.count(k) < rows[k].count:
				order.append(k)
				break
	var refresh := func():
		for k in rows.size():
			if rows[k].has("header"):
				continue
			var nums: Array = []
			for pos in order.size():
				if order[pos] == k:
					nums.append(str(pos + 1))
			var name_text := "x%d   %s" % [rows[k].count, CardDB.card_name(rows[k].id)]
			var tag := ", ".join(nums) if ordered else "%d chosen" % nums.size()
			list.set_item_text(k, ("%s      > %s" % [name_text, tag]) if not nums.is_empty() else name_text)
			list.set_item_custom_bg_color(k, Color(0.25, 0.5, 0.25, 0.7) if not nums.is_empty() else Color(0, 0, 0, 0))
		list.deselect_all()
		d.get_ok_button().disabled = order.size() != need
		d.get_ok_button().text = "%s (%d/%d)" % [verb, order.size(), need]
	list.item_clicked.connect(func(k: int, _pos: Vector2, button: int):
		if not rows[k].has("id"):
			return
		var picked := order.count(k)
		if button == MOUSE_BUTTON_RIGHT or (button == MOUSE_BUTTON_LEFT and picked >= rows[k].count):
			if picked > 0:
				order.remove_at(order.rfind(k))
		elif button == MOUSE_BUTTON_LEFT and order.size() < need:
			order.append(k)
		refresh.call())
	d.add_button("Clear", false, "clear")
	d.custom_action.connect(func(_a):
		order.clear()
		refresh.call())
	d.confirmed.connect(func():
		d.queue_free()
		var used := {}
		var result: Array = []
		for k in order:
			var n := int(used.get(k, 0))
			result.append(copies[k][n])
			used[k] = n + 1
		on_ok.call(result))
	d.canceled.connect(func():
		d.queue_free()
		if on_cancel.is_valid():
			on_cancel.call())
	_popup(d)
	refresh.call()


# --- Ability interaction -------------------------------------------------------------------------------
func _lock_abilities(ms := 650) -> void:
	_ability_lock_until = Time.get_ticks_msec() + ms


func _on_ability_pressed(slot: int, ai: int) -> void:
	if Time.get_ticks_msec() < _ability_lock_until or not _pending.is_empty():
		return  # a double-click aimed at something else, or a click meant to choose a target
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
		"exile_attached":
			_ask_exile_berry(slot, effect, func(bi): _submit({"type": "use_ability", "slot": slot, "ability": ai, "params": {"berry": bi}}))
		"cast_from_discard":
			_ask_cast_from_discard(slot, ai)
		_:
			_submit({"type": "use_ability", "slot": slot, "ability": ai, "params": {}})


## Leafren / Moosh: which attached berry of this creature gets exiled. Asks only when there is a real choice.
func _ask_exile_berry(slot: int, effect: Dictionary, on_pick: Callable) -> void:
	var c: Dictionary = view.you.board[slot]
	var options: Array = []  # berry indices, one per distinct (berry, upright / exhausted)
	var labels: Array = []
	var ids: Array = []
	var seen := {}
	for bi in c.berries.size():
		if not Rules.berry_matches(c.berries[bi], effect.element):
			continue
		var key := "%s:%s" % [c.berries[bi], c.exhausted[bi]]
		if seen.has(key):
			continue
		seen[key] = true
		options.append(bi)
		ids.append(c.berries[bi])
		labels.append("%s (%s)" % [CardDB.card_name(c.berries[bi]), "exhausted" if c.exhausted[bi] else "upright"])
	if options.is_empty():
		return _toast("No %s Berry is attached to this creature." % String(effect.element).capitalize())
	if options.size() == 1:
		return on_pick.call(options[0])
	_pick_from_list("Exile which attached berry?", labels, func(k): on_pick.call(options[k]), ids)


## Spore Muncher: choose a spell in the discard pile, then whatever that spell needs (target, cards to exile).
func _ask_cast_from_discard(slot: int, ai: int) -> void:
	var discard: Array = view.you.discard
	var options: Array = []  # discard index of the newest copy of each distinct spell
	var labels: Array = []
	var ids: Array = []
	for di in range(discard.size() - 1, -1, -1):
		if CardDB.is_spell(discard[di]) and not ids.has(discard[di]):
			options.append(di)
			ids.append(discard[di])
			labels.append(CardDB.card_name(discard[di]))
	if options.is_empty():
		return _toast("There is no spell in your discard pile.")
	var go := func(di: int, sp: Dictionary):
		_submit({"type": "use_ability", "slot": slot, "ability": ai, "params": {"spell": di, "spell_params": sp}})
	var on_spell := func(k: int):
		var di: int = options[k]
		var spell := CardDB.card(discard[di])
		var effect: Dictionary = spell.effects[0]
		match effect.type:
			"destroy":
				_begin_targeting("%s: choose a creature." % spell.name, _any_creature, 1, func(t): go.call(di, {"target": t[0]}))
			"stun":
				var n := int(effect.count)
				_begin_targeting("%s: choose up to %d creature(s)." % [spell.name, n], _any_creature, n, func(t): go.call(di, {"targets": t}))
			"exile_discard":
				var rest: Array = discard.duplicate()
				rest.remove_at(di)  # the spell itself is being exiled
				_ask_exile_cards(spell, rest, func(chosen: Array): go.call(di, {"cards": chosen}))
			_:
				go.call(di, {})
	_pick_from_list("Exile which spell to play it?", labels, on_spell, ids)


## Trash: choose which cards of `pool` (card ids) to exile. Calls `on_ok` with the chosen card ids.
func _ask_exile_cards(spell: Dictionary, pool: Array, on_ok: Callable) -> void:
	var need := mini(int(spell.effects[0].amount), pool.size())
	if need == 0:
		return on_ok.call([])
	_ordered_pick("%s: choose %d card(s) from your discard pile to exile" % [spell.name, need], pool, need, [], "Exile",
		func(picked: Array): on_ok.call(picked.map(func(i): return pool[i])), Callable(),
		"Click a card to choose it; click a stack again to choose another copy. Right-click (or click a stack whose copies are all chosen) to take one back. These cards are exiled for good.", false)


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
	holder.custom_minimum_size = Vector2(280, 400)
	row.add_child(holder)
	var show := func(k: int):
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		if k < 0:
			return
		var card_id: String = card_at.call(k)
		if card_id == "":
			return
		var card := CardView.new().setup(card_id, CardView.Mark.NONE, Vector2(270, 378))
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
	var rows := _pile_rows(ids)
	_fill_pile_list(list, rows)
	box.add_child(_list_with_preview(list, func(k: int) -> String: return rows[k].get("id", "")))
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
	list.item_selected.connect(func(k): play.disabled = not (can_play and rows[k].has("id") and CardDB.is_berry(rows[k].id)))
	list.item_activated.connect(func(k):
		if can_play and rows[k].has("id") and CardDB.is_berry(rows[k].id):
			play.pressed.emit())
	d.custom_action.connect(func(_a):
		var sel := list.get_selected_items()
		if sel.is_empty():
			return
		if not rows[sel[0]].has("id"):
			return
		var di: int = rows[sel[0]].index
		d.queue_free()
		_begin_targeting("Attach %s from your discard to which creature? (enters exhausted)" % CardDB.card_name(ids[di]),
			func(p, s): return p == ME and view.you.board[s] != null, 1,
			func(t): _submit({"type": "attach_berry", "from": "discard", "discard": di, "slot": t[0].slot})))
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	_popup(d)


func _make_pile_row(seat: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	for kind in ["deck", "discard", "exile"]:
		var pile := PileView.new().setup(kind, kind != "deck")
		if kind != "deck":
			pile.clicked.connect(func(): _view_pile(seat, kind))
		row.add_child(pile)
		_piles[seat][kind] = pile
	return row


func _set_piles(seat: int, side: Dictionary) -> void:
	var discard: Array = side.discard
	var exile: Array = side.exile
	_piles[seat].deck.set_pile(side.deck_count, "")
	_piles[seat].discard.set_pile(discard.size(), "" if discard.is_empty() else discard.back())
	_piles[seat].exile.set_pile(exile.size(), "" if exile.is_empty() else exile.back())


func _pile_rect(seat: int, kind: String) -> Rect2:
	var pile: PileView = _piles[seat].get(kind)
	if pile != null and is_instance_valid(pile):
		return pile.top_rect()
	return Rect2(size / 2.0, Vector2(78, 109))


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
	var item := {"ev": ev, "src": _fx_source_rect(ev), "targets": []}
	# Targets are measured now: after the action the board may already have changed (e.g. a destroyed
	# creature is gone and the others have shifted).
	if ev.fx == "spell" or ev.fx == "stun":
		for t in ev.targets:
			item.targets.append(_slot_rect(int(t.player), int(t.slot)))
		if ev.fx == "stun" and int(ev.from_slot) >= 0:
			item["origin"] = _slot_rect(ev.player, ev.from_slot).get_center()
	if ev.fx == "spell" and CardDB.card(ev.card).effects[0].type == "destroy":
		item["ghosts"] = []
		for t in ev.targets:
			var w: BoardCreature = _slot_nodes.get("%d:%d" % [int(t.player), int(t.slot)])
			if w != null and is_instance_valid(w):
				var ghost := {"creature": w.creature.duplicate(true), "slot": int(t.slot), "seat": int(t.player)}
				if not _ghosts.has(ghost.seat):
					_ghosts[ghost.seat] = []
				_ghosts[ghost.seat].append(ghost)
				item.ghosts.append(ghost)
	_fx_queue.append(item)
	var key := _fx_hide_key(ev)
	if key != "":
		_hidden_slots[key] = int(_hidden_slots.get(key, 0)) + 1
	controller.hold_ai = true
	if not _fx_running:
		_fx_running = true  # claim it now: several events from one action must share a single runner
		_run_fx_queue.call_deferred()


func _fx_busy() -> bool:
	return _fx_running or not _fx_queue.is_empty()


func _fx_hide_key(ev: Dictionary) -> String:
	return "%d:%d" % [ev.player, ev.slot] if ev.fx == "play_creature" else ""


func _fx_source_rect(ev: Dictionary) -> Rect2:
	var mine: bool = int(ev.player) == ME
	if ev.fx == "swap" or ev.fx == "ability" or ev.fx == "stun" or ev.fx == "reveal" or ev.fx == "plunder" or ev.fx == "pillage":
		return Rect2()
	if ev.fx == "attach" and ev.from == "discard" or (ev.fx == "play_creature" or ev.fx == "spell") and int(ev.hand) < 0:
		return _pile_rect(int(ev.player), "discard")
	var idx := int(ev.hand)
	if mine:
		return _hand_view.card_rect(idx)
	var n := _opp_hand_row.get_child_count()
	if n == 0:
		return Rect2(Vector2(size.x / 2.0 - 35.0, -60.0), Vector2(70, 100))
	return _opp_hand_row.get_child(clampi(idx, 0, n - 1)).get_global_rect()


## The top card of the creature in `slot` (effects aim at the card, not the whole stack).
func _slot_rect(seat: int, slot: int) -> Rect2:
	var node: BoardCreature = _slot_nodes.get("%d:%d" % [seat, slot])
	if node != null and is_instance_valid(node):
		return node.top_card_rect()
	return Rect2(size / 2.0, BoardCreature.CARD_SIZE)


func _run_fx_queue() -> void:
	_fx_running = true
	await get_tree().process_frame
	while not _fx_queue.is_empty():
		var item: Dictionary = _fx_queue.pop_front()
		await _play_fx(item.ev, item.src, item)
		for g in item.get("ghosts", []):
			(_ghosts[g.seat] as Array).erase(g)
			var i: int = item.ghosts.find(g)
			if i >= 0 and i < item.targets.size():
				_fx.burst(item.targets[i].get_center(), Color(0.9, 0.9, 1.0), 34, 220.0, 0.7)
			if view != {}:
				_refresh()
		var key := _fx_hide_key(item.ev)
		if key != "":
			_hidden_slots[key] = maxi(int(_hidden_slots.get(key, 1)) - 1, 0)
			if view != {}:
				_refresh()
	controller.hold_ai = false
	_fx_running = false
	if view != {}:
		_refresh()  # choices that were waiting for the effects (e.g. where a revealed berry goes) appear now


func _play_fx(ev: Dictionary, src: Rect2, item: Dictionary) -> void:
	var mine: bool = int(ev.player) == ME
	match ev.fx:
		"play_creature":
			var target := _slot_rect(ev.player, ev.slot)
			if int(ev.hand) < 0:  # Reinforce: comes out of the discard pile
				await _fx.play_card(ev.card, src, 0.6, [target], false)
			else:
				await _fx.play_card(ev.card, src, 0.0 if mine else 2.0, [target], not mine)
		"spell":
			await _fx.play_card(ev.card, src, 2.0, item.targets, not mine)
		"attach":
			await _play_attach(ev, src, mine)
		"ability":
			var creature: BoardCreature = _slot_nodes.get("%d:%d" % [ev.player, ev.slot])
			var rect := _slot_rect(ev.player, ev.slot)
			if creature != null and is_instance_valid(creature):
				rect = creature.ability_rect(int(ev.ability))
			await _fx.flash(rect, 1.5)
		"stun":
			var origin: Vector2 = item.get("origin", Vector2(size.x / 2.0 - 160.0, size.y - 30.0 if mine else 20.0))
			var points: Array = item.targets.map(func(r: Rect2): return r.get_center())
			await _fx.stun_bolts(origin, points)
		"plunder":
			await _fx.show_plunder(ev.cards, _pile_rect(int(ev.target), "discard"), 0.55)
		"pillage":
			await _fx.show_plunder(ev.cards, _pile_rect(int(ev.target), "discard"), 0.55, ev.discard)
		"reveal":
			if ev.cards.is_empty():
				await _fx.show_message("No berries found", 1.0)
				return
			var all_super: bool = ev.cards.all(func(id): return CardDB.element_of(id) == Rules.SUPER)
			var caption := "Super Berry found!" if all_super and ev.cards.size() == 1 else ("Super Berries found!" if all_super else "Berries found!")
			await _fx.show_reveal(ev.cards, caption, 1.2)
		"swap":
			await _fx.show_pair(ev.hand_card, ev.discard_card, "From hand", "From discard", 2.0)


func _play_attach(ev: Dictionary, src: Rect2, mine: bool) -> void:
	var target := _slot_rect(ev.player, ev.slot)
	if ev.from == "discard":
		_fx.firework(src.get_center())  # sparks over the pile as the card leaves it
		await _fx.play_card(ev.card, src, 0.0, [target], false, 1.3)
	else:
		await _fx.play_card(ev.card, src, 0.0 if mine else 0.7, [target], not mine, 1.3)
	var creature: BoardCreature = _slot_nodes.get("%d:%d" % [ev.player, ev.slot])
	var spot := target.get_center()
	if creature != null and is_instance_valid(creature):
		spot = creature.newest_berry_pos()
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
	if winner == ME:
		d.dialog_text = "You win!"
	else:
		d.dialog_text = "The computer wins." if _allow_rematch else "You lose."
	if _allow_rematch:
		d.ok_button_text = "Rematch"
		d.add_button("Main Menu", false, "menu")
		d.confirmed.connect(func(): rematch_requested.emit())
		d.custom_action.connect(func(_a): exit_requested.emit())
	else:
		d.ok_button_text = "Main Menu"
		d.confirmed.connect(func(): exit_requested.emit())
	_popup(d)
