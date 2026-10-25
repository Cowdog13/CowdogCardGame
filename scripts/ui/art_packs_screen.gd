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
	_apply.text = "Use this art"
	_apply.custom_minimum_size = Vector2(0, 44)
	_apply.pressed.connect(_use_selected)
	right.add_child(_apply)
	_reload()


func _reload() -> void:
	_packs = [{"id": "", "name": "Default art", "creator": "", "description": "The art that comes with the game."}]
	_packs.append_array(ArtDB.list_packs())
	_list.clear()
	var current := 0
	for i in _packs.size():
		var label: String = _packs[i].name
		if _packs[i].id == ArtDB.active_pack:
			label += "   (in use)"
			current = i
		_list.add_item(label)
	_list.select(current)
	_show_pack(current)


func _show_pack(i: int) -> void:
	var pack: Dictionary = _packs[i]
	var text: String = pack.name
	if pack.creator != "":
		text += "  -  by %s" % pack.creator
	if pack.description != "":
		text += "\n" + pack.description
	if pack.get("ai_generated", false):
		text += "\nMade with AI (AI-generated art)."
	if _packs.size() == 1:
		text += "\n\nNo art packs installed. Unzip a pack into the art packs folder (button on the left), then press Refresh."
	_info.text = text
	_preview.texture = _preview_of(pack)
	_apply.disabled = pack.id == ArtDB.active_pack


## The pack's board background, or the built-in one for the default entry.
func _preview_of(pack: Dictionary) -> Texture2D:
	if pack.id == "":
		return load("res://assets/board/board_bg.webp")
	for ext in ArtDB.IMAGE_EXTENSIONS:
		var path := "%s/%s/board/board_bg.%s" % [ArtDB.PACKS_DIR, pack.id, ext]
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null and not img.is_empty():
				return ImageTexture.create_from_image(img)
	return null


func _use_selected() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	ArtDB.set_active_pack(_packs[sel[0]].id)
	ArtDB.save_settings()
	_reload()
