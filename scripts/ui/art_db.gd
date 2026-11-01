class_name ArtDB
extends RefCounted
## Looks up artwork by card id / element. Everything falls back to null, and the card renderer
## then draws a placeholder, so missing art never breaks the game.

const PACKS_DIR := "user://art_packs"
const SETTINGS_PATH := "user://settings.cfg"
const IMAGE_EXTENSIONS := ["webp", "png", "jpg", "jpeg"]

static var _cache := {}
static var active_packs: Array = []  # folder names inside user://art_packs that are switched on (several can be used at once); empty = built-in art only
static var _pack_decks := {}  # pack id -> decks the pack is made for (pack.json "decks"); empty = every deck
static var roll := 0  # decides which pack wins when several have the same picture; re-rolled at the start of every game
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


## The file for `rel_no_ext` inside one pack ("" when the pack doesn't have it).
static func _pack_file(pack_id: String, rel_no_ext: String) -> String:
	var key := "file:%s:%s" % [pack_id, rel_no_ext]
	if _cache.has(key):
		return _cache[key]
	var found := ""
	for ext in IMAGE_EXTENSIONS:
		var path := "%s/%s/%s.%s" % [PACKS_DIR, pack_id, rel_no_ext, ext]
		if FileAccess.file_exists(path):
			found = path
			break
	_cache[key] = found
	return found


## A picture from the switched-on art packs (folders of images with the same names and sub-folders as res://assets), or null.
## When several packs have this picture the game's roll picks one of them. For card art, `card_id` and `owner_seat` limit the
## packs to those made for the deck that owns the card.
static func _pack_tex(rel_no_ext: String, card_id := "", owner_seat := -1) -> Texture2D:
	var candidates: Array = []
	for id in active_packs:
		if card_id != "" and not _pack_applies(id, card_id, owner_seat):
			continue
		if _pack_file(id, rel_no_ext) != "":
			candidates.append(id)
	if candidates.is_empty():
		return null
	var chosen: String = candidates[0] if candidates.size() == 1 else candidates[absi(hash("%d:%s" % [roll, rel_no_ext])) % candidates.size()]
	var key := "pack:%s:%s" % [chosen, rel_no_ext]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var img := Image.load_from_file(_pack_file(chosen, rel_no_ext))
	if img != null and not img.is_empty():
		tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Called when a game starts: re-decides which pack's art is used wherever switched-on packs overlap.
static func new_roll() -> void:
	roll = randi()


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


## Switches on exactly these packs (ids that don't exist are ignored).
static func set_active_packs(pack_ids: Array) -> void:
	active_packs = []
	_pack_decks = {}
	_cache.clear()
	for id in pack_ids:
		var meta_path := "%s/%s/pack.json" % [PACKS_DIR, id]
		if String(id) == "" or active_packs.has(id) or not DirAccess.dir_exists_absolute("%s/%s" % [PACKS_DIR, id]):
			continue
		active_packs.append(String(id))
		_pack_decks[id] = []
		if FileAccess.file_exists(meta_path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
			if parsed is Dictionary and parsed.get("decks", []) is Array:
				_pack_decks[id] = parsed.get("decks", [])


## One pack on its own ("" = the built-in art only).
static func set_active_pack(pack_id: String) -> void:
	set_active_packs([pack_id] if pack_id != "" else [])


static func set_pack_enabled(pack_id: String, on: bool) -> void:
	var ids := active_packs.duplicate()
	if on and not ids.has(pack_id):
		ids.append(pack_id)
	elif not on:
		ids.erase(pack_id)
	set_active_packs(ids)


## Tells the art which deck each seat plays, so cards shared by several decks (Removal, Super Berry) use a pack's art
## only for a player whose deck the pack is made for. Berries follow the same rule, so a pack's berry art never changes the opponent's berries.
static func set_game_decks(p_my_seat: int, deck_0: String, deck_1: String) -> void:
	my_seat = p_my_seat
	seat_decks = [deck_0, deck_1]


## Does this pack's art apply to this card? `owner_seat` is whose card it is (-1: the viewer's own).
static func _pack_applies(pack_id: String, card_id: String, owner_seat := -1) -> bool:
	var decks: Array = _pack_decks.get(pack_id, [])
	if decks.is_empty() or not (CardDB.is_shared(card_id) or CardDB.is_berry(card_id)):
		return true
	var seat := owner_seat if owner_seat >= 0 else my_seat
	return decks.has(seat_decks[seat])


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("art", "packs", active_packs)
	cfg.save(SETTINGS_PATH)


## Reads the saved choice; packs that have been deleted are dropped (back to the built-in art when none are left).
static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var wanted: Array = []
	if cfg.has_section_key("art", "packs"):
		wanted = Array(cfg.get_value("art", "packs", []))
	elif String(cfg.get_value("art", "pack", "")) != "":  # saved by an older version
		wanted = [String(cfg.get_value("art", "pack", ""))]
	set_active_packs(wanted)


static func card_art(card_id: String, owner_seat := -1) -> Texture2D:
	var packed := _pack_tex("cards/%s" % card_id, card_id, owner_seat)
	return packed if packed != null else _tex("res://assets/cards/%s.png" % card_id)


## White glyph on transparent; tint with modulate. `element` may be "super" or "colorless".
static func symbol(element: String) -> Texture2D:
	var packed := _pack_tex("symbols/%s" % element)
	return packed if packed != null else _tex("res://assets/symbols/%s.png" % element)


static func berry_icon(card_id: String, owner_seat := -1) -> Texture2D:
	var packed := _pack_tex("berries/%s" % card_id, card_id, owner_seat)
	return packed if packed != null else _tex("res://assets/berries/%s.png" % card_id)


static func card_back_logo() -> Texture2D:
	var packed := _pack_tex("ui/card_back_logo")
	return packed if packed != null else _tex("res://assets/ui/card_back_logo.png")


static func board_background() -> Texture2D:
	var packed := _pack_tex("board/board_bg")
	return packed if packed != null else _tex("res://assets/board/board_bg.webp")
