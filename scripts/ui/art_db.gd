class_name ArtDB
extends RefCounted
## Looks up artwork by card id / element. Everything falls back to null, and the card renderer
## then draws a placeholder, so missing art never breaks the game.

static var _cache := {}


static func _tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_cache[path] = tex
	return tex


static func card_art(card_id: String) -> Texture2D:
	return _tex("res://assets/cards/%s.png" % card_id)


## White glyph on transparent; tint with modulate. `element` may be "super" or "colorless".
static func symbol(element: String) -> Texture2D:
	return _tex("res://assets/symbols/%s.png" % element)


static func berry_icon(card_id: String) -> Texture2D:
	return _tex("res://assets/berries/%s.png" % card_id)


static func card_back_logo() -> Texture2D:
	return _tex("res://assets/ui/card_back_logo.png")


static func board_background() -> Texture2D:
	return _tex("res://assets/board/board_bg.webp")
