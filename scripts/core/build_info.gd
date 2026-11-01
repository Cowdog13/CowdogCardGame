class_name BuildInfo
extends RefCounted
## Which build of the game this is. Players who connect to each other must have the same one: the version is bumped by
## hand for every build that goes to testers, and a fingerprint of the card and deck data catches a forgotten bump.

const VERSION := "0.6.0"
const CHANNEL := "playtest"

static var _fingerprint := ""


## Short fingerprint of data/cards.json + data/decks.json (any change to a card changes it).
static func data_hash() -> String:
	if _fingerprint == "":
		var text := ""
		for path in [CardDB.CARDS_PATH, CardDB.DECKS_PATH]:
			text += FileAccess.get_file_as_string(path)
		_fingerprint = text.sha256_text().substr(0, 8)
	return _fingerprint


## What is compared when two players connect, e.g. "0.6.0-3fa9c1d2".
static func fingerprint() -> String:
	return "%s-%s" % [VERSION, data_hash()]


## What players see, e.g. "v0.6.0 playtest (data 3fa9c1d2)".
static func label() -> String:
	return "v%s %s (data %s)" % [VERSION, CHANNEL, data_hash()]
