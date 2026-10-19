class_name TutorialScript
extends RefCounted
## Everything the tutorial teaches: the two stacked decks, the practice opponent's moves and the
## steps shown to the player. The game is a normal game on the real engine; only the order of the
## cards is fixed (so the right cards show up on the right turn) and the opponent follows a script.
##
## Turn plan (turns are numbered across both players):
##   1  you      mulligan, play a creature, attach a berry
##   2  opponent plays Water Constrictor
##   3  you      second creature, Plunder (steals a Super Berry)
##   4  opponent stuns your Firespore
##   5  you      evolve (removes the stun), Plunder 3, Pillage 2
##   6  opponent quiet turn
##   7  you      Pillage, once-per-game swap, evolve again, berry from the discard, Removal

const PLAYER_START := [
	"firespore", "fire_berry", "firepup", "firespitter", "fireking", "removal", "fire_berry",  # opening hand
	"fire_berry",  # mulligan draw
	"firespore",  # turn 1 draw
	"fire_berry",  # turn 3
	"firewolf",  # turn 5
	"fireking", "fire_berry",  # turn 5 Pillage 2
	"fire_famine",  # turn 7
	"fire_berry", "fire_berry",  # turn 7 Pillage 2
]
const OPPONENT_START := [
	"water_constrictor", "water_berry", "water_berry", "water_spirit", "removal", "water_berry", "disable",
	"water_berry",  # turn 2
	"water_berry", "super_berry",  # turn 3 Plunder 2 (the Super Berry is stolen)
	"water_berry",  # turn 4
	"water_berry", "water_sprite", "water_berry",  # turn 5 Plunder 3
	"water_berry",  # turn 6
]


## [your deck, opponent's deck]: the scripted cards first, then the rest of the real deck shuffled.
static func decks() -> Array:
	return [_stack("scorching_fire", PLAYER_START, 11), _stack("crashing_wave", OPPONENT_START, 12)]


static func _stack(deck_id: String, start: Array, seed_val: int) -> Array:
	var rest := CardDB.build_deck_list(deck_id)
	for id in start:
		rest.erase(id)  # removes one copy
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for i in range(rest.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = rest[i]
		rest[i] = rest[j]
		rest[j] = tmp
	return start + rest


static func opponent_intents() -> Array:
	return [
		{"play": "water_constrictor"}, {"attach": "water_berry", "to": "water_constrictor"}, {"end": true},
		{"play": "water_spirit"}, {"attach": "water_berry", "to": "water_constrictor"},
		{"ability": "water_constrictor", "index": 0, "params": {"targets": [{"player": 0, "slot": 0}]}}, {"end": true},
		{"attach": "water_berry", "to": "water_spirit"}, {"end": true},
	]


## Step keys: title, text (BBCode), highlight [target names for GameScreen.tutorial_target_rect],
## then ONE of: expect {the one action that moves on} (+ hint shown when anything else is tried),
## "bot" (a button lets the practice opponent play its turn), "end" (the last step), or nothing
## (a plain "Next" button).
static func steps() -> Array:
	return [
		{"title": "Welcome!", "text": "This tutorial plays a few turns of a real game against a practice opponent. I'll tell you exactly which card to play and why, so follow the highlighted cards.\n\n[b]How you win:[/b] your opponent loses when they have no card to draw, or when you [b]Plunder[/b] more cards than their deck has left.\n\nYour hand is at the bottom, your creatures are in the lower row and the opponent's are in the upper row. The piles on the right are your deck, discard and exile."},
		{"title": "Mulligan", "highlight": ["hand:fireking"],
			"text": "Before the first turn you may [b]mulligan[/b]: pick any cards you don't like, they go to the [b]bottom of your deck[/b], and you draw that many new ones.\n\n[b]Fireking[/b] is a Tier 3 creature. It can only be played on top of a Tier 2 creature, which in turn goes on a Tier 1, so it won't be playable for a few turns. Click it to select it, then press [b]Confirm[/b].",
			"expect": {"type": "mulligan", "cards": ["fireking"]}, "hint": "Select only the Fireking, then press Confirm."},
		{"title": "Play a creature", "highlight": ["hand:firespore"],
			"text": "You go first. Creatures are the heart of the game. [b]Firespore[/b] is a Tier 1 creature - every creature starts as a Tier 1 and can [b]evolve[/b] later.\n\nYou may play [b]one creature per turn[/b] and have up to 5 on the table. Click Firespore to play it.",
			"expect": {"type": "play_creature", "card": "firespore"}, "hint": "Play the Firespore."},
		{"title": "Attach a berry", "highlight": ["hand:fire_berry"],
			"text": "Berries power your creatures' abilities. Once per turn you can attach a berry from your hand to one of your creatures. Click a [b]Fire Berry[/b] to attach it to Firespore.",
			"expect": {"type": "attach_berry", "card": "fire_berry", "to": "firespore"}, "hint": "Attach a Fire Berry to Firespore."},
		{"title": "End your turn", "highlight": ["end_turn", "mine:firespore"],
			"text": "Firespore's ability, [b]Plunder 2[/b], needs 1 Fire Berry - and it has one. But [b]nobody can use abilities on their first turn[/b] (turn 1 and turn 2 of the game), so there is nothing more to do. Press [b]End Turn[/b].",
			"expect": {"type": "end_turn"}, "hint": "Press End Turn."},
		{"title": "The opponent's turn", "text": "Now the practice opponent takes their turn. They play a Water creature and attach a Water Berry.", "bot": true, "button": "Watch the opponent's turn"},
		{"title": "A second creature", "highlight": ["hand:firepup"],
			"text": "Abilities are unlocked now. First, play a second creature: click [b]Firepup[/b]. It has two abilities, [b]Pillage 2[/b] and [b]Plunder 1[/b], and we will use it soon.",
			"expect": {"type": "play_creature", "card": "firepup"}, "hint": "Play the Firepup."},
		{"title": "Another berry", "highlight": ["hand:fire_berry"],
			"text": "Attach a Fire Berry to [b]Firepup[/b] (click the berry, then click Firepup). Remember: one berry per turn.",
			"expect": {"type": "attach_berry", "card": "fire_berry", "to": "firepup"}, "hint": "Attach a Fire Berry to Firepup."},
		{"title": "Plunder", "highlight": ["mine:firespore"],
			"text": "Now use Firespore's [b]Plunder 2[/b]: click the ability on the creature. Its cost (1 Fire Berry) just has to be [i]attached[/i] - berries are never used up by abilities.\n\n[b]Plunder[/b] makes the opponent discard cards from the top of their deck. That empties their deck, and it can also hit their [b]Super Berries[/b]...",
			"expect": {"type": "use_ability", "creature": "firespore", "ability": 0}, "hint": "Use Firespore's Plunder 2."},
		{"title": "Stolen Super Berry!", "highlight": ["mine:firespore"],
			"text": "A [b]Super Berry[/b] was in the plundered cards. Super Berries aren't discarded: [b]you steal them[/b] and attach them to any of your creatures. A Super Berry counts as a berry of any element.\n\nClick [b]Firespore[/b] to attach it.",
			"expect": {"type": "place_berry", "to": "firespore"}, "hint": "Put the Super Berry on Firespore."},
		{"title": "Ability limits", "highlight": ["end_turn"],
			"text": "Each creature can use [b]one ability per turn[/b], and you can use [b]two abilities per turn[/b] in total. Firespore has used its ability for this turn. Press [b]End Turn[/b].",
			"expect": {"type": "end_turn"}, "hint": "Press End Turn."},
		{"title": "The opponent's turn", "text": "Watch what the opponent does with their Water Constrictor.", "bot": true, "button": "Watch the opponent's turn"},
		{"title": "Stun", "highlight": ["mine:firespore", "theirs:water_constrictor"],
			"text": "The opponent's Water Constrictor used [b]Stun 1[/b] on your Firespore. A stunned creature (greyed out, marked STUNNED) [b]can't use abilities[/b] until the end of its controller's next turn.\n\nYou can wait it out, or [b]evolve the creature: evolving removes a stun.[/b]"},
		{"title": "Evolve", "highlight": ["hand:firespitter", "mine:firespore"],
			"text": "Click [b]Firespitter[/b] to evolve Firespore. Evolving puts a Tier 2 card on top of its Tier 1 card: the berries stay, the stun is gone, and it counts as your creature play for the turn.\n\nThe new card's abilities replace the old ones: Firespitter has [b]Plunder 3[/b].",
			"expect": {"type": "play_creature", "card": "firespitter"}, "hint": "Evolve Firespore with Firespitter."},
		{"title": "Berry for Firepup", "highlight": ["hand:fire_berry"],
			"text": "Firepup's [b]Pillage 2[/b] needs 2 Fire Berries. Attach another Fire Berry to [b]Firepup[/b].",
			"expect": {"type": "attach_berry", "card": "fire_berry", "to": "firepup"}, "hint": "Attach a Fire Berry to Firepup."},
		{"title": "Plunder 3", "highlight": ["mine:firespitter"],
			"text": "Firespitter's Plunder 3 costs 2 Fire Berries. It has a Fire Berry and a Super Berry, and a Super Berry counts as any berry. Use [b]Plunder 3[/b].",
			"expect": {"type": "use_ability", "creature": "firespitter", "ability": 0}, "hint": "Use Firespitter's Plunder 3."},
		{"title": "Pillage", "highlight": ["mine:firepup"],
			"text": "[b]Pillage[/b] is like Plunder, but it hits [b]your own deck[/b]: the top cards go to your discard pile. That sounds bad, but your discard pile is a resource: you can attach berries from it, swap creatures with it and pay for spells with its berries. Any Super Berry you pillage is yours to attach.\n\nUse Firepup's [b]Pillage 2[/b]. That is your second ability, the most you can use in a turn.",
			"expect": {"type": "use_ability", "creature": "firepup", "ability": 0}, "hint": "Use Firepup's Pillage 2."},
		{"title": "Your discard pile", "highlight": ["discard"],
			"text": "Look at your discard pile on the right: the pillage put a [b]Fireking[/b] and a [b]Fire Berry[/b] there. You can click the pile at any time to see the cards in it (the exile pile works the same way - cards there are gone for good).\n\nWe'll use both of them on your next turn."},
		{"title": "End your turn", "highlight": ["end_turn"], "text": "Press [b]End Turn[/b].", "expect": {"type": "end_turn"}, "hint": "Press End Turn."},
		{"title": "The opponent's turn", "text": "A quiet turn for the opponent.", "bot": true, "button": "Watch the opponent's turn"},
		{"title": "Pillage again", "highlight": ["mine:firepup"],
			"text": "Another round of [b]Pillage 2[/b] with Firepup to stock your discard pile with berries.",
			"expect": {"type": "use_ability", "creature": "firepup", "ability": 0}, "hint": "Use Firepup's Pillage 2."},
		{"title": "The once-per-game swap", "highlight": ["swap"],
			"text": "Once per game you may [b]swap[/b] a creature in your hand with a creature in your discard pile. Your spare [b]Firespore[/b] isn't much use, but the Fireking that was pillaged is great. Press [b]Swap[/b], give the Firespore and take the Fireking.",
			"expect": {"type": "swap", "hand_card": "firespore", "discard_card": "fireking"}, "hint": "Swap your Firespore for the Fireking in your discard."},
		{"title": "Evolve again", "highlight": ["hand:fireking", "mine:firespitter"],
			"text": "Play [b]Fireking[/b] on top of Firespitter: Tier 1, then Tier 2, now Tier 3. Evolved creatures keep all their berries.",
			"expect": {"type": "play_creature", "card": "fireking"}, "hint": "Evolve Firespitter with Fireking."},
		{"title": "A berry from the discard", "highlight": ["discard"],
			"text": "You haven't attached a berry this turn. You can use one from your [b]discard pile[/b] instead of your hand: click your discard pile, select a Fire Berry, press [b]Play berry from discard[/b] and choose Fireking.\n\nA berry attached this way enters [b]exhausted[/b] (sideways, red outline). Exhausted berries still count for ability costs, but when one is spent on a spell it is [b]exiled[/b] instead of discarded.",
			"expect": {"type": "attach_berry", "from": "discard", "card": "fire_berry", "to": "fireking"}, "hint": "Play a Fire Berry from your discard onto Fireking."},
		{"title": "Spells", "highlight": ["hand:removal", "theirs:water_constrictor"],
			"text": "Last, a [b]spell[/b]. [b]Removal[/b] sends a creature and all its attached berries to the discard pile. Spells cost berries: Removal costs 3 berries of any kind. You choose which ones pay: berries in your discard pile are the cheapest, and any berry attached to a creature works too (exhausted ones are exiled).\n\nCast Removal on the opponent's [b]Water Constrictor[/b], paying with your two discard berries and the exhausted one on Fireking.",
			"expect": {"type": "play_spell", "card": "removal", "target": "water_constrictor"}, "hint": "Cast Removal on the opponent's Water Constrictor."},
		{"title": "More to discover", "text": "That covers the basics: [b]mulligan, creatures, evolving, berries, abilities, Plunder, Pillage, Stun, Super Berries, the swap and spells[/b].\n\nThere is more in the decks: [b]Reinforce[/b] (pay 3 Fire Berries to play a second creature this turn), [b]Fire Famine[/b] and [b]Firewolf[/b] (their [i]Active[/i] abilities are always on and change what Pillage does), the Water deck's [b]Disable[/b] and [b]Berry Trade[/b], and more. Hover any card to read it."},
		{"title": "Tutorial complete", "end": true,
			"text": "Nicely done! You can [b]finish this game[/b] against the computer (your board and hand carry on, the opponent plays for real from now on), or quit back to the menu."},
	]
