class_name ArtDB
extends RefCounted
## Looks up artwork by card id / element. Everything falls back to null, and the card renderer
## then draws a placeholder, so missing art never breaks the game.

const PACKS_DIR := "user://art_packs"
const SETTINGS_PATH := "user://settings.cfg"
const IMAGE_EXTENSIONS := ["webp", "png", "jpg", "jpeg"]

static var _cache := {}
static var active_pack := ""  # folder name inside user://art_packs, "" = the built-in art
static var active_pack_decks: Array = []  # decks the pack is made for (pack.json "decks"); empty = every deck
static var seat_decks := ["", ""]  # the deck each seat plays, set by the table screen
static var my_seat := 0


static func _tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_cache[path] = tex
	return tex


## A picture from the active art pack (a folder of images with the same names and sub-folders as res://assets), or null.
static func _pack_tex(rel_no_ext: String) -> Texture2D:
	if active_pack == "":
		return null
	var key := "pack:%s:%s" % [active_pack, rel_no_ext]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	for ext in IMAGE_EXTENSIONS:
		var path := "%s/%s/%s.%s" % [PACKS_DIR, active_pack, rel_no_ext, ext]
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
				break
	_cache[key] = tex
	return tex


## Art packs found in the packs folder: [{"id": folder name, "name", "creator", "description", "publisher", "decks", "path"}].
static func list_packs() -> Array:
	DirAccess.make_dir_recursive_absolute(PACKS_DIR)
	var out: Array = []
	for dir in DirAccess.get_directories_at(PACKS_DIR):
		var info := {"id": dir, "name": dir, "creator": "", "description": "", "publisher": "", "decks": [], "ai_generated": false, "path": "%s/%s" % [PACKS_DIR, dir]}
		var meta_path: String = info.path + "/pack.json"
		if FileAccess.file_exists(meta_path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
			if parsed is Dictionary:
				for k in ["name", "creator", "description", "publisher"]:
					if parsed.has(k):
						info[k] = String(parsed[k])
				info["ai_generated"] = bool(parsed.get("ai_generated", false))
				if parsed.get("decks", []) is Array:
					info["decks"] = parsed.get("decks", [])
		out.append(info)
	return out


static func set_active_pack(pack_id: String) -> void:
	active_pack = pack_id
	active_pack_decks = []
	_cache.clear()
	var meta_path := "%s/%s/pack.json" % [PACKS_DIR, pack_id]
	if pack_id != "" and FileAccess.file_exists(meta_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if parsed is Dictionary and parsed.get("decks", []) is Array:
			active_pack_decks = parsed.get("decks", [])


## Tells the art which deck each seat plays, so cards shared by several decks (Removal, Super Berry) use the pack's art
## only for a player whose deck the pack is made for.
static func set_game_decks(p_my_seat: int, deck_0: String, deck_1: String) -> void:
	my_seat = p_my_seat
	seat_decks = [deck_0, deck_1]


## Does the active pack's art apply to this card? `owner_seat` is whose card it is (-1: the viewer's own).
static func pack_applies(card_id: String, owner_seat := -1) -> bool:
	if active_pack == "":
		return false
	if active_pack_decks.is_empty() or not CardDB.is_shared(card_id):
		return true
	var seat := owner_seat if owner_seat >= 0 else my_seat
	return active_pack_decks.has(seat_decks[seat])


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("art", "pack", active_pack)
	cfg.save(SETTINGS_PATH)


## Reads the saved choice; a pack that has been deleted falls back to the built-in art.
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var wanted := String(cfg.get_value("art", "pack", ""))
	set_active_pack(wanted if wanted != "" and DirAccess.dir_exists_absolute("%s/%s" % [PACKS_DIR, wanted]) else "")


static func card_art(card_id: String, owner_seat := -1) -> Texture2D:
	var packed := _pack_tex("cards/%s" % card_id) if pack_applies(card_id, owner_seat) else null
	return packed if packed != null else _tex("res://assets/cards/%s.png" % card_id)


## White glyph on transparent; tint with modulate. `element` may be "super" or "colorless".
static func symbol(element: String) -> Texture2D:
	var packed := _pack_tex("symbols/%s" % element)
	return packed if packed != null else _tex("res://assets/symbols/%s.png" % element)


static func berry_icon(card_id: String, owner_seat := -1) -> Texture2D:
	var packed := _pack_tex("berries/%s" % card_id) if pack_applies(card_id, owner_seat) else null
	return packed if packed != null else _tex("res://assets/berries/%s.png" % card_id)


static func card_back_logo() -> Texture2D:
	var packed := _pack_tex("ui/card_back_logo")
	return packed if packed != null else _tex("res://assets/ui/card_back_logo.png")


static func board_background() -> Texture2D:
	var packed := _pack_tex("board/board_bg")
	return packed if packed != null else _tex("res://assets/board/board_bg.webp")
