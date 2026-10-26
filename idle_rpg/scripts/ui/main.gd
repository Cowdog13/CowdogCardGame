extends Control
## Whole UI, built in code. Tabs: Battle (watch), Team (lineup, plans, equipment), Dreamplanes, Equipment.

const CLASS_COLORS := {
	"Flora": Color("5fae5f"), "Mechanical": Color("8e9aa8"), "Elemental": Color("e0703a"),
	"Animalistic": Color("c4944a"), "Shadow": Color("8660b8"), "Void": Color("5a5f8a"),
}
const SPEEDS := [1, 5, 20]

var game: IdleGame
var speed := 1
var autosave_left := 30.0

var top_label: Label
var notice_label: Label
var tabs: TabContainer
var battle_box: VBoxContainer
var player_col: VBoxContainer
var enemy_col: VBoxContainer
var status_label: Label
var log_view: RichTextLabel
var team_box: VBoxContainer
var plane_box: VBoxContainer
var equip_box: VBoxContainer
var selected_id := ""
var shown_battle: IdleBattle = null
var widgets: Dictionary = {}
var notice_time := 0.0


func _ready() -> void:
	game = IdleGame.load_or_new()
	selected_id = game.owned.keys()[0]
	_build()
	_rebuild_team()
	_rebuild_planes()
	_rebuild_equipment()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("171a24")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	top_label = Label.new()
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(top_label)
	for s in SPEEDS:
		var b := Button.new()
		b.text = "x%d" % s
		b.toggle_mode = true
		b.button_pressed = s == speed
		b.pressed.connect(_set_speed.bind(s))
		bar.add_child(b)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	battle_box = VBoxContainer.new()
	battle_box.name = "Battle"
	tabs.add_child(battle_box)
	status_label = Label.new()
	battle_box.add_child(status_label)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	battle_box.add_child(cols)
	player_col = _make_column(cols, "Your Dreamshapes")
	enemy_col = _make_column(cols, "Enemies")
	log_view = RichTextLabel.new()
	log_view.custom_minimum_size.y = 150
	log_view.scroll_following = true
	battle_box.add_child(log_view)

	team_box = _make_tab("Team")
	plane_box = _make_tab("Dreamplanes")
	equip_box = _make_tab("Equipment")

	tabs.tab_changed.connect(func(_i): _rebuild_team(); _rebuild_equipment())
	notice_label = Label.new()
	notice_label.add_theme_color_override("font_color", Color("ffe08a"))
	root.add_child(notice_label)


func _make_column(parent: Control, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 20)
	col.add_child(l)
	parent.add_child(col)
	return col


func _make_tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


func _set_speed(s: int) -> void:
	speed = s
	for b in top_label.get_parent().get_children():
		if b is Button:
			b.button_pressed = b.text == "x%d" % s


func _process(delta: float) -> void:
	game.advance(delta * speed)
	if game.battle != shown_battle:
		_show_battle(game.battle)
	_update_battle()
	_update_top()
	if not game.notices.is_empty():
		notice_label.text = "  |  ".join(game.notices.slice(-3))
		notice_time = 6.0
		game.notices.clear()
		_rebuild_team()
		_rebuild_planes()
		_rebuild_equipment()
	elif notice_time > 0.0:
		notice_time -= delta
		if notice_time <= 0.0:
			notice_label.text = ""
	autosave_left -= delta
	if autosave_left <= 0.0:
		autosave_left = 30.0
		game.save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and game != null:
		game.save()


func _update_top() -> void:
	var plane := IdleDB.dreamplane(game.plane_id)
	top_label.text = "%s  (wave %d/%d)     Energy %d/%d     Vorx %d" % [
		plane.name, game.wave + 1, plane.waves.size(), game.energy_used(), IdleGame.MAX_ENERGY, game.vorx]


# ---- Battle tab ---------------------------------------------------------

func _show_battle(b: IdleBattle) -> void:
	shown_battle = b
	widgets.clear()
	for col in [player_col, enemy_col]:
		for i in range(col.get_child_count() - 1, 0, -1):
			col.get_child(i).queue_free()
	if b == null:
		return
	for side in [BattleUnit.SIDE_PLAYER, BattleUnit.SIDE_ENEMY]:
		var col: VBoxContainer = player_col if side == BattleUnit.SIDE_PLAYER else enemy_col
		for row in ["front", "back"]:
			var header := Label.new()
			header.text = "Frontline" if row == "front" else "Backline"
			header.add_theme_color_override("font_color", Color("9aa3b8"))
			col.add_child(header)
			for u in b.units:
				if u.side == side and u.row == row:
					col.add_child(_make_unit_panel(u))


func _make_unit_panel(u: BattleUnit) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("232838")
	style.border_color = CLASS_COLORS.get(u.dclass, Color.WHITE)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var name_label := Label.new()
	v.add_child(name_label)
	var hp := ProgressBar.new()
	hp.show_percentage = false
	hp.custom_minimum_size.y = 18
	hp.add_theme_stylebox_override("fill", _fill_style(Color("4caf6a") if u.side == BattleUnit.SIDE_PLAYER else Color("c0504d")))
	v.add_child(hp)
	var cast := ProgressBar.new()
	cast.show_percentage = false
	cast.custom_minimum_size.y = 10
	cast.add_theme_stylebox_override("fill", _fill_style(Color("d9b44a")))
	v.add_child(cast)
	var cast_label := Label.new()
	cast_label.add_theme_font_size_override("font_size", 12)
	v.add_child(cast_label)
	widgets[u] = {"panel": panel, "name": name_label, "hp": hp, "cast": cast, "cast_label": cast_label}
	return panel


func _fill_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(3)
	return sb


func _update_battle() -> void:
	var b := shown_battle
	if b == null:
		status_label.text = "Choose at least one active Dreamshape in the Team tab." if not game.can_fight() else "Preparing next battle..."
		return
	status_label.text = "Battle time %.0fs" % b.time
	for u in widgets:
		var w: Dictionary = widgets[u]
		var armor_text := "  armor %d" % roundi(u.armor) if u.armor > 0.5 else ""
		var amp_text := "  +heal boost" if u.heal_amp > 0.0 else ""
		w.name.text = "%s  Lv %d   HP %d/%d%s%s" % [u.name, u.level, ceili(u.hp), roundi(u.max_hp), armor_text, amp_text]
		w.hp.max_value = u.max_hp
		w.hp.value = u.hp
		w.cast.max_value = maxf(u.phase_total, 0.01)
		w.cast.value = u.phase_total - u.phase_left
		w.cast_label.text = u.cast_text()
		w.panel.modulate = Color(1, 1, 1, 1.0 if u.alive() else 0.35)
	b.events.clear()
	var lines := b.log_lines.slice(-12)
	log_view.text = "\n".join(lines)


# ---- Team tab -----------------------------------------------------------

func _rebuild_team() -> void:
	_clear(team_box)
	var head := Label.new()
	head.text = "Up to %d Dreamshapes, %d energy total. Changes apply when the next battle starts." % [IdleGame.MAX_ACTIVE, IdleGame.MAX_ENERGY]
	team_box.add_child(head)
	for id in game.owned:
		team_box.add_child(_make_team_row(id))
	team_box.add_child(HSeparator.new())
	team_box.add_child(_make_plan_editor(selected_id))


func _make_team_row(id: String) -> Control:
	var def := IdleDB.dreamshape(id)
	var o: Dictionary = game.owned[id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var active := CheckBox.new()
	active.text = "Active"
	active.button_pressed = o.active
	active.disabled = not game.can_activate(id)
	active.toggled.connect(func(on: bool): game.set_active(id, on); _rebuild_team())
	row.add_child(active)
	var info := Label.new()
	info.custom_minimum_size.x = 420
	info.text = "%s  (%s %s)  Energy %d   Lv %d   XP %d/%d" % [def.name, def.tribe, def["class"], def.energy, o.level, o.xp, IdleDB.xp_to_next(o.level)]
	info.add_theme_color_override("font_color", CLASS_COLORS.get(def["class"], Color.WHITE))
	row.add_child(info)
	var where := OptionButton.new()
	where.add_item("Frontline")
	where.add_item("Backline")
	where.selected = 0 if o.row == "front" else 1
	where.item_selected.connect(func(i: int): game.set_row(id, "front" if i == 0 else "back"))
	row.add_child(where)
	var gear := OptionButton.new()
	gear.add_item("No equipment")
	var pick := 0
	for e in game.equipment_owned:
		gear.add_item(IdleDB.equipment(e).name)
		gear.set_item_metadata(gear.item_count - 1, e)
		if o.equipment == e:
			pick = gear.item_count - 1
	gear.selected = pick
	gear.item_selected.connect(func(i: int):
		game.equip(id, "" if i == 0 else gear.get_item_metadata(i))
		_rebuild_team())
	row.add_child(gear)
	var edit := Button.new()
	edit.text = "Edit plan"
	edit.toggle_mode = true
	edit.button_pressed = id == selected_id
	edit.pressed.connect(func(): selected_id = id; _rebuild_team())
	row.add_child(edit)
	return row


func _make_plan_editor(id: String) -> Control:
	var def := IdleDB.dreamshape(id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var plan: Array = game.owned[id].plan
	var title := Label.new()
	title.text = "%s ability order (%d/%d slots). Repeats forever; empty = every ability in order." % [def.name, plan.size(), IdleGame.MAX_PLAN_SLOTS]
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	var adds := HBoxContainer.new()
	box.add_child(adds)
	var abilities: Array = def.abilities
	for i in abilities.size():
		var a: Dictionary = abilities[i]
		var b := Button.new()
		b.text = "+ %s" % a.name
		b.tooltip_text = "%s\nStartup %.1fs, resolve %.1fs, cooldown %.1fs" % [a.text, a.startup, a.resolve, a.cooldown]
		b.disabled = plan.size() >= IdleGame.MAX_PLAN_SLOTS
		b.pressed.connect(func(): game.add_to_plan(id, i); _rebuild_team())
		adds.add_child(b)
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(func(): game.clear_plan(id); _rebuild_team())
	adds.add_child(clear)
	var slots := HFlowContainer.new()
	box.add_child(slots)
	for s in plan.size():
		var b := Button.new()
		b.text = "%d. %s  x" % [s + 1, abilities[plan[s]].name]
		b.tooltip_text = "Click to remove"
		b.pressed.connect(func(): game.remove_from_plan(id, s); _rebuild_team())
		slots.add_child(b)
	for a in abilities:
		var l := Label.new()
		l.text = "%s: %s (startup %.1fs, resolve %.1fs, cooldown %.1fs)" % [a.name, a.text, a.startup, a.resolve, a.cooldown]
		l.add_theme_font_size_override("font_size", 13)
		box.add_child(l)
	return box


# ---- Dreamplanes / equipment tabs ---------------------------------------

func _rebuild_planes() -> void:
	_clear(plane_box)
	for id in IdleDB.dreamplane_ids():
		var p := IdleDB.dreamplane(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var info := Label.new()
		info.custom_minimum_size.x = 900
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var state := "CLEARED" if game.cleared.has(id) else ("" if game.plane_unlocked(id) else "LOCKED")
		info.text = "%s (%s)  Recommended level %d   %d waves   %s\n%s" % [p.name, p["class"], p.recommended_level, p.waves.size(), state, p.desc]
		info.add_theme_color_override("font_color", CLASS_COLORS.get(p["class"], Color.WHITE))
		row.add_child(info)
		var enter := Button.new()
		enter.text = "Fighting here" if game.plane_id == id else "Enter"
		enter.disabled = not game.plane_unlocked(id) or game.plane_id == id
		enter.pressed.connect(func(): game.enter_plane(id); _rebuild_planes())
		row.add_child(enter)
		plane_box.add_child(row)


func _rebuild_equipment() -> void:
	_clear(equip_box)
	var head := Label.new()
	head.text = "Unlocked equipment (clear Dreamplanes for new items; some drop from monsters). One item per Dreamshape; attach in the Team tab."
	equip_box.add_child(head)
	if game.equipment_owned.is_empty():
		var none := Label.new()
		none.text = "Nothing unlocked yet."
		equip_box.add_child(none)
	for e in game.equipment_owned:
		var item := IdleDB.equipment(e)
		var holder := ""
		for id in game.owned:
			if game.owned[id].equipment == e:
				holder = "   [on %s]" % IdleDB.dreamshape(id).name
		var l := Label.new()
		l.text = "%s: %s%s" % [item.name, item.desc, holder]
		equip_box.add_child(l)


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
