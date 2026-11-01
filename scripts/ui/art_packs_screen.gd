class_name ArtPacksScreen
extends Control
## Choose an art pack (a folder in the game's art_packs folder). Packs can replace the board background and,
## later, card art; whatever a pack doesn't contain keeps the built-in art.

signal back_requested

var _list: ItemList
var _packs: Array = []
var _preview: TextureRect
var _info: Label
var _apply: Button
var _selected := 0
var _note: Label
var _mode: OptionButton


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.12, 0.11)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	var head := HBoxContainer.new()
	root.add_child(head)
	var back := Button.new()
	back.text = "< Back"
	back.pressed.connect(func(): back_requested.emit())
	head.add_child(back)
	var title := Label.new()
	title.text = "Art packs"
	title.add_theme_font_size_override("font_size", 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = back.get_minimum_size()
	head.add_child(spacer)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(340, 0)
	body.add_child(left)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.add_theme_font_size_override("font_size", 17)
	_list.item_selected.connect(_show_pack)
	left.add_child(_list)
	var open := Button.new()
	open.text = "Open art packs folder"
	open.pressed.connect(func():
		DirAccess.make_dir_recursive_absolute(ArtDB.PACKS_DIR)
		OS.shell_open(ProjectSettings.globalize_path(ArtDB.PACKS_DIR)))
	left.add_child(open)
	var refresh := Button.new()
	refresh.text = "Refresh list"
	refresh.pressed.connect(_reload)
	left.add_child(refresh)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_preview)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(0, 90)
	right.add_child(_info)
	_apply = Button.new()
	_apply.text = "Use this pack"
	_apply.custom_minimum_size = Vector2(0, 44)
	_apply.pressed.connect(_use_selected)
	right.add_child(_apply)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	right.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = "If two packs have the same picture:"
	mode_row.add_child(mode_label)
	_mode = OptionButton.new()
	_mode.add_item("pick randomly, picture by picture")
	_mode.add_item("pick one whole pack at random")
	_mode.select(1 if ArtDB.conflict_by_pack else 0)
	_mode.item_selected.connect(func(i):
		ArtDB.conflict_by_pack = i == 1
		ArtDB.save_settings())
	mode_row.add_child(_mode)
	_note = Label.new()
	_note.text = "You can switch on several packs at once. Each picture comes from a pack that has it. When packs overlap, the choice is made at the start of each game: either separately for every picture, or by picking one pack that wins all the overlaps."
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	right.add_child(_note)
	_reload()


func _reload() -> void:
	_packs = [{"id": "", "name": "Default art", "creator": "", "description": "The art that comes with the game."}]
	_packs.append_array(ArtDB.list_packs())
	_list.clear()
	for i in _packs.size():
		var label: String = _packs[i].name
		var on: bool = ArtDB.active_packs.has(_packs[i].id) if _packs[i].id != "" else ArtDB.active_packs.is_empty()
		if on:
			label = "[x] " + label + "   (in use)"
		else:
			label = "[  ] " + label
		_list.add_item(label)
	_list.select(clampi(_selected, 0, _packs.size() - 1))
	_show_pack(clampi(_selected, 0, _packs.size() - 1))


func _show_pack(i: int) -> void:
	_selected = i
	var pack: Dictionary = _packs[i]
	var text: String = pack.name
	if pack.creator != "":
		text += "  -  by %s" % pack.creator
	if pack.description != "":
		text += "\n" + pack.description
	if pack.get("publisher", "") != "":
		text += "\n" + pack.publisher
	if _packs.size() == 1:
		text += "\n\nNo art packs installed. Unzip a pack into the art packs folder (button on the left), then press Refresh."
	_info.text = text
	_preview.texture = _preview_of(pack)
	if pack.id == "":
		_apply.text = "Use only the default art"
		_apply.disabled = ArtDB.active_packs.is_empty()
	else:
		_apply.text = "Stop using this pack" if ArtDB.active_packs.has(pack.id) else "Use this pack"
		_apply.disabled = false


## The pack's board background, or the built-in one for the default entry.
func _preview_of(pack: Dictionary) -> Texture2D:
	if pack.id == "":
		return load("res://assets/board/board_bg.webp")
	# preview.* is the picture made for the pack (made by tools/make_art_pack.py); otherwise its table background
	for name in ["preview", "board/board_bg"]:
		for ext in ArtDB.IMAGE_EXTENSIONS:
			var path := "%s/%s/%s.%s" % [ArtDB.PACKS_DIR, pack.id, name, ext]
			if FileAccess.file_exists(path):
				var img := Image.load_from_file(path)
				if img != null and not img.is_empty():
					return ImageTexture.create_from_image(img)
	return _collage_of(pack)


## A pack with no preview picture and no table background: a grid of its first cards.
func _collage_of(pack: Dictionary) -> Texture2D:
	var dir := "%s/%s/cards" % [ArtDB.PACKS_DIR, pack.id]
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in ArtDB.IMAGE_EXTENSIONS:
			files.append(f)
	files.sort()
	if files.is_empty():
		return null
	const COLS := 4
	const ROWS := 2
	const CELL := 240
	var out := Image.create(COLS * CELL, ROWS * CELL, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.07, 0.1, 0.09))
	var step := maxf(1.0, float(files.size()) / (COLS * ROWS))
	for n in mini(files.size(), COLS * ROWS):
		var img := Image.load_from_file("%s/%s" % [dir, files[int(n * step)]])
		if img == null or img.is_empty():
			continue
		img.convert(Image.FORMAT_RGBA8)
		var scale := minf(float(CELL - 12) / img.get_width(), float(CELL - 12) / img.get_height())
		img.resize(maxi(1, int(img.get_width() * scale)), maxi(1, int(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
		var x := (n % COLS) * CELL + (CELL - img.get_width()) / 2
		var y := (n / COLS) * CELL + (CELL - img.get_height()) / 2
		out.blend_rect(img, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i(x, y))
	return ImageTexture.create_from_image(out)


func _use_selected() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	var id: String = _packs[sel[0]].id
	if id == "":
		ArtDB.set_active_packs([])
	else:
		ArtDB.set_pack_enabled(id, not ArtDB.active_packs.has(id))
	ArtDB.save_settings()
	_reload()
