class_name ArtDB
extends RefCounted
## Looks up artwork by card id / element. Everything falls back to null, and the card renderer
## then draws a placeholder, so missing art never breaks the game.

const PACKS_DIR := "user://art_packs"
const SETTINGS_PATH := "user://settings.cfg"
const IMAGE_EXTENSIONS := ["webp", "png", "jpg", "jpeg"]

static var _cache := {}
static var active_pack := ""  # folder name inside user://art_packs, "" = the built-in art


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


## Art packs found in the packs folder: [{"id": folder name, "name", "creator", "description", "path"}].
static func list_packs() -> Array:
	DirAccess.make_dir_recursive_absolute(PACKS_DIR)
	var out: Array = []
	for dir in DirAccess.get_directories_at(PACKS_DIR):
		var info := {"id": dir, "name": dir, "creator": "", "description": "", "publisher": "", "ai_generated": false, "path": "%s/%s" % [PACKS_DIR, dir]}
		var meta_path: String = info.path + "/pack.json"
		if FileAccess.file_exists(meta_path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
			if parsed is Dictionary:
				for k in ["name", "creator", "description", "publisher"]:
					if parsed.has(k):
						info[k] = String(parsed[k])
				info["ai_generated"] = bool(parsed.get("ai_generated", false))
		out.append(info)
	return out


static func set_active_pack(pack_id: String) -> void:
	active_pack = pack_id
	_cache.clear()


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


static func card_art(card_id: String) -> Texture2D:
	var packed := _pack_tex("cards/%s" % card_id)
	return packed if packed != null else _tex("res://assets/cards/%s.png" % card_id)


## White glyph on transparent; tint with modulate. `element` may be "super" or "colorless".
static func symbol(element: String) -> Texture2D:
	var packed := _pack_tex("symbols/%s" % element)
	return packed if packed != null else _tex("res://assets/symbols/%s.png" % element)


static func berry_icon(card_id: String) -> Texture2D:
	var packed := _pack_tex("berries/%s" % card_id)
	return packed if packed != null else _tex("res://assets/berries/%s.png" % card_id)


static func card_back_logo() -> Texture2D:
	var packed := _pack_tex("ui/card_back_logo")
	return packed if packed != null else _tex("res://assets/ui/card_back_logo.png")


static func board_background() -> Texture2D:
	var packed := _pack_tex("board/board_bg")
	return packed if packed != null else _tex("res://assets/board/board_bg.webp")
