extends SceneTree
## Art packs: a pack's board background replaces the built-in one, the choice is saved, and a missing pack falls back.
##   godot --headless -s tests/art_pack_test.gd
func _init() -> void:
	var fails := 0
	var base := ProjectSettings.globalize_path(ArtDB.PACKS_DIR)
	var folder := base + "/test-pack"
	DirAccess.make_dir_recursive_absolute(folder + "/board")
	DirAccess.make_dir_recursive_absolute(folder + "/cards")
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 0, 0))
	img.save_png(folder + "/board/board_bg.png")
	var small := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	small.fill(Color(0, 1, 0))
	small.save_png(folder + "/cards/removal.png")  # a card shared by several decks
	small.save_png(folder + "/cards/leafer.png")  # a Nature card
	small.save_png(folder + "/cards/fire_berry.png")  # a berry of a deck the pack is not made for
	small.save_png(folder + "/cards/nature_berry.png")
	FileAccess.open(folder + "/pack.json", FileAccess.WRITE).store_string('{"name": "Red Test", "creator": "Me", "publisher": "Cowdog Game Store", "ai_generated": true, "decks": ["nature_exile"]}')
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
	# Shared cards (Removal) use the pack only for a player whose deck the pack is made for.
	ArtDB.set_game_decks(0, "nature_exile", "scorching_fire")
	if ArtDB.card_art("removal", 0).get_width() != 8 or ArtDB.card_art("removal").get_width() != 8:
		fails += 1
		print("your own Removal should use the pack")
	if ArtDB.card_art("removal", 1).get_width() == 8:
		fails += 1
		print("the Fire opponent's Removal should keep the default art")
	if ArtDB.card_art("leafer", 1).get_width() != 8:
		fails += 1
		print("a Nature card always uses the pack")
	if ArtDB.card_art("nature_berry", 0).get_width() != 8 or ArtDB.card_art("fire_berry", 1).get_width() == 8 or ArtDB.card_art("nature_berry", 1).get_width() == 8:
		fails += 1
		print("a pack's berries should only dress the berries of the decks it is made for")
	ArtDB.bot_seats = [1]
	if ArtDB.card_art("leafer", 1).get_width() == 8 or ArtDB.card_art("leafer", 0).get_width() != 8:
		fails += 1
		print("a computer opponent must use the default art; the human keeps the pack")
	ArtDB.bot_seats = []
	ArtDB.set_game_decks(0, "scorching_fire", "nature_exile")
	if ArtDB.card_art("removal", 0).get_width() == 8 or ArtDB.card_art("removal", 1).get_width() != 8:
		fails += 1
		print("shared art should follow the deck of whoever owns the card")
	# Several packs at once: non-overlapping art combines, overlapping art is decided by the roll.
	var folder2 := base + "/test-pack-2"
	DirAccess.make_dir_recursive_absolute(folder2 + "/board")
	DirAccess.make_dir_recursive_absolute(folder2 + "/cards")
	var blue := Image.create(32, 18, false, Image.FORMAT_RGB8)
	blue.fill(Color(0, 0, 1))
	blue.save_png(folder2 + "/board/board_bg.png")
	var green := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	green.fill(Color(0, 1, 0))
	green.save_png(folder2 + "/cards/firespore.png")
	FileAccess.open(folder2 + "/pack.json", FileAccess.WRITE).store_string('{"name": "Blue Test"}')
	ArtDB.set_active_packs(["test-pack", "test-pack-2"])
	if ArtDB.card_art("firespore").get_width() != 16 or ArtDB.card_art("leafer", 1).get_width() != 8:
		fails += 1
		print("art from two packs that don't overlap should both be used")
	var seen := {}
	for i in 40:
		ArtDB.new_roll()
		seen[ArtDB.board_background().get_width()] = true
		if ArtDB.board_background().get_width() != ArtDB.board_background().get_width():
			fails += 1
	if not (seen.has(64) and seen.has(32)):
		fails += 1
		print("two packs with the same picture should both get picked sometimes: ", seen.keys())
	# "Whole pack" mode: one pack wins every overlap in a game; non-overlapping art still combines.
	ArtDB.conflict_by_pack = true
	var wins := {}
	for i in 40:
		ArtDB.new_roll()
		wins[ArtDB.board_background().get_width()] = true
		if ArtDB.card_art("firespore").get_width() != 16:
			fails += 1
			print("art only one pack has must still be used in whole-pack mode")
	if not (wins.has(64) and wins.has(32)):
		fails += 1
		print("whole-pack mode should still pick either pack sometimes: ", wins.keys())
	ArtDB.save_settings()
	ArtDB.conflict_by_pack = false
	ArtDB.load_settings()
	if not ArtDB.conflict_by_pack:
		fails += 1
		print("the conflict mode should be remembered")
	ArtDB.conflict_by_pack = false
	var r1 := ArtDB.board_background().get_width()
	if ArtDB.board_background().get_width() != r1:
		fails += 1
		print("the choice must stay the same within a game")
	ArtDB.save_settings()
	ArtDB.set_active_packs([])
	ArtDB.load_settings()
	if ArtDB.active_packs.size() != 2:
		fails += 1
		print("both packs should be remembered: ", ArtDB.active_packs)
	DirAccess.remove_absolute(folder2 + "/cards/firespore.png")
	DirAccess.remove_absolute(folder2 + "/board/board_bg.png")
	DirAccess.remove_absolute(folder2 + "/pack.json")
	DirAccess.remove_absolute(folder2 + "/cards")
	DirAccess.remove_absolute(folder2 + "/board")
	DirAccess.remove_absolute(folder2)
	ArtDB.set_active_pack("test-pack")
	ArtDB.save_settings()
	ArtDB.set_active_pack("")
	ArtDB.load_settings()
	if ArtDB.active_packs != ["test-pack"]:
		fails += 1
		print("choice not remembered")
	DirAccess.remove_absolute(folder + "/cards/removal.png")
	DirAccess.remove_absolute(folder + "/cards/leafer.png")
	DirAccess.remove_absolute(folder + "/cards/fire_berry.png")
	DirAccess.remove_absolute(folder + "/cards/nature_berry.png")
	DirAccess.remove_absolute(folder + "/cards")
	DirAccess.remove_absolute(folder + "/board/board_bg.png")
	DirAccess.remove_absolute(folder + "/pack.json")
	DirAccess.remove_absolute(folder + "/board")
	DirAccess.remove_absolute(folder)
	ArtDB.load_settings()
	if not ArtDB.active_packs.is_empty() or ArtDB.board_background() != default_tex:
		fails += 1
		print("a deleted pack should fall back to the default art")
	ArtDB.save_settings()
	print("art_pack_test failures=%d" % fails)
	quit(fails)
