extends SceneTree
## Art packs: a pack's board background replaces the built-in one, the choice is saved, and a missing pack falls back.
##   godot --headless -s tests/art_pack_test.gd
func _init() -> void:
	var fails := 0
	var base := ProjectSettings.globalize_path(ArtDB.PACKS_DIR)
	var folder := base + "/test-pack"
	DirAccess.make_dir_recursive_absolute(folder + "/board")
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 0, 0))
	img.save_png(folder + "/board/board_bg.png")
	FileAccess.open(folder + "/pack.json", FileAccess.WRITE).store_string('{"name": "Red Test", "creator": "Me", "publisher": "Cowdog Game Store", "ai_generated": true}')
	var packs := ArtDB.list_packs().filter(func(p): return p.id == "test-pack")
	if packs.size() != 1 or packs[0].name != "Red Test" or packs[0].publisher != "Cowdog Game Store":
		fails += 1
		print("pack not listed: ", packs)
	ArtDB.set_active_pack("")
	var default_tex := ArtDB.board_background()
	ArtDB.set_active_pack("test-pack")
	var pack_tex := ArtDB.board_background()
	if pack_tex == null or pack_tex.get_width() != 64 or pack_tex.get_image().get_pixel(3, 3).r < 0.9:
		fails += 1
		print("pack background not used")
	if ArtDB.card_art("firespore") == null:
		fails += 1
		print("a card the pack doesn't contain should keep the built-in art")
	ArtDB.save_settings()
	ArtDB.set_active_pack("")
	ArtDB.load_settings()
	if ArtDB.active_pack != "test-pack":
		fails += 1
		print("choice not remembered")
	DirAccess.remove_absolute(folder + "/board/board_bg.png")
	DirAccess.remove_absolute(folder + "/pack.json")
	DirAccess.remove_absolute(folder + "/board")
	DirAccess.remove_absolute(folder)
	ArtDB.load_settings()
	if ArtDB.active_pack != "" or ArtDB.board_background() != default_tex:
		fails += 1
		print("a deleted pack should fall back to the default art")
	ArtDB.save_settings()
	print("art_pack_test failures=%d" % fails)
	quit(fails)
