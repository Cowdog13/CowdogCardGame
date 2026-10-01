class_name CardDB
extends RefCounted
## Loads card and deck definitions from res://data. Cards are plain dictionaries
## keyed by id, so new cards/decks are added by editing JSON only.

const CARDS_PATH := "res://data/cards.json"
const DECKS_PATH := "res://data/decks.json"

static var _cards: Dictionary = {}
static var _decks: Dictionary = {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_cards = _read_json(CARDS_PATH)
	for id in _cards:
		_cards[id]["id"] = id
	_decks = _read_json(DECKS_PATH)
	_loaded = true


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "Cannot open %s" % path)
	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "Bad JSON in %s" % path)
	return parsed


static func card(id: String) -> Dictionary:
	_ensure_loaded()
	return _cards[id]


static func card_name(id: String) -> String:
	return card(id).name


static func kind(id: String) -> String:
	return card(id).kind


static func is_berry(id: String) -> bool:
	return kind(id) == "berry"


static func is_creature(id: String) -> bool:
	return kind(id) == "creature"


static func is_spell(id: String) -> bool:
	return kind(id) == "spell"


static func element_of(id: String) -> String:
	return card(id).get("element", "")


static func deck_ids() -> Array:
	_ensure_loaded()
	return _decks.keys()


static func deck_name(deck_id: String) -> String:
	_ensure_loaded()
	return _decks[deck_id].name


## Expands a deck definition into a flat list of card ids (unshuffled).
static func build_deck_list(deck_id: String) -> Array:
	_ensure_loaded()
	var out: Array = []
	for entry in _decks[deck_id].cards:
		for i in int(entry[1]):
			out.append(entry[0])
	return out


## Human readable description used by tooltips and the card detail panel.
static func card_text(id: String) -> String:
	var c := card(id)
	var lines: Array[String] = []
	match c.kind:
		"berry":
			lines.append("%s Berry" % String(c.element).capitalize())
			if c.element == Rules.SUPER:
				lines.append("Counts as any element.")
		"creature":
			var head := "Creature - Tier %d" % int(c.tier)
			if c.evolves_from != "":
				head += " (evolves from %s)" % card_name(c.evolves_from)
			lines.append(head)
			for ab in c.abilities:
				lines.append("[%s] %s" % [Rules.cost_text(ab.cost), Rules.ability_text(ab)])
		"spell":
			lines.append("Spell - cost %s" % Rules.cost_text(c.cost))
			lines.append(c.text)
	return "\n".join(lines)
