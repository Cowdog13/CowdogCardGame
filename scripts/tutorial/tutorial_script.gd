class_name TutorialScript
extends RefCounted
## Everything the tutorial teaches: the two stacked decks, the practice opponent's moves and the
## steps shown to the player. The game is a normal game on the real engine; only the order of the
## cards is fixed (so the right cards show up on the right turn) and the opponent follows a script.
##
## Turn plan (turns are numbered across both players; both players start with a free, dormant creature):
##   1  you      mulligan, play Firepup, attach a berry to the sleeping Firespore
##   2  opponent plays Water Constrictor
##   3  you      berry on Firepup, Plunder 1 (steals a Super Berry)
##   4  opponent stuns your Firepup
##   5  you      evolve Firepup (removes the stun), Plunder 2 from the awake Firespore, Pillage 3 + Recycle 1
##   6  opponent quiet turn
##   7  you      swap, evolve Firespore, berry from the discard, Removal

const PLAYER_START := [
	"firepup", "fire_berry", "firespore", "firewolf", "fireking", "removal", "fire_berry",  # opening hand
	"fire_berry",  # mulligan draw
	"fire_berry",  # turn 1
	"fire_berry",  # turn 3
	"fire_famine",  # turn 5
	"firespitter", "fire_berry", "fire_berry",  # turn 5 Pillage 3 (then Recycle 1: a berry goes back to the deck)
	"fire_berry",  # turn 7
]
const OPPONENT_START := [
	"water_constrictor", "water_berry", "water_berry", "removal", "water_berry", "disable", "water_berry",  # opening hand
	"water_berry",  # turn 2
	"super_berry",  # turn 3 Plunder 1 (the Super Berry is stolen)
	"water_berry",  # turn 4
	"water_berry", "water_sprite",  # turn 5 Plunder 2
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
		{"attach": "water_berry", "to": "water_constrictor"},
		{"ability": "water_constrictor", "index": 0, "params": {"targets": [{"player": 0, "slot": 1}]}}, {"end": true},
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
			"text": "Before the first turn you may [b]mulligan[/b]: pick any cards you don't like, they go to the [b]bottom of your deck[/b], and you draw that many new ones.\n\n[b]Fireking[/b] is a Tier 3 creature. It can only be played on top of a Tier 2 creature, which in turn goes on a Tier 1, so it won't be playable for a long while. Click it to select it, then press [b]Confirm[/b].",
			"expect": {"type": "mulligan", "cards": ["fireking"]}, "hint": "Select only the Fireking, then press Confirm."},
		{"title": "Your starting creature", "highlight": ["mine:firespore"],
			"text": "Every player starts the game with a free Tier 1 creature on the board: yours is [b]Firespore[/b]. It is an extra card, it didn't come out of your deck.\n\nIt is [b]dormant[/b] for the first two turns of each player: it can't use abilities until turn 5. But you can already [b]attach berries[/b] to it."},
		{"title": "Play a creature", "highlight": ["hand:firepup"],
			"text": "You go first. Creatures are the heart of the game. [b]Firepup[/b] is a Tier 1 creature - every creature starts as a Tier 1 and can [b]evolve[/b] later.\n\nYou may play [b]one creature per turn[/b] and have up to 5 on the table. Click Firepup to play it.",
			"expect": {"type": "play_creature", "card": "firepup"}, "hint": "Play the Firepup."},
		{"title": "Attach a berry", "highlight": ["hand:fire_berry", "mine:firespore"],
			"text": "Berries power your creatures' abilities. Once per turn you can attach a berry from your hand to one of your creatures. Attach a [b]Fire Berry[/b] to the sleeping [b]Firespore[/b] so it is ready when it wakes up (click the berry, then click Firespore).",
			"expect": {"type": "attach_berry", "card": "fire_berry", "to": "firespore"}, "hint": "Attach a Fire Berry to Firespore."},
		{"title": "End your turn", "highlight": ["end_turn"],
			"text": "[b]Nobody can use abilities on their first turn[/b] (turn 1 and turn 2 of the game), so there is nothing more to do. Press [b]End Turn[/b].",
			"expect": {"type": "end_turn"}, "hint": "Press End Turn."},
		{"title": "The opponent's turn", "text": "Now the practice opponent takes their turn. They play a Water creature and attach a Water Berry. Their starting Water Spirit is dormant too.", "bot": true, "button": "Watch the opponent's turn"},
		{"title": "Another berry", "highlight": ["hand:fire_berry", "mine:firepup"],
			"text": "Abilities are unlocked for creatures that aren't dormant. Attach a Fire Berry to [b]Firepup[/b]: its [b]Plunder 1[/b] needs 1 Fire Berry.",
			"expect": {"type": "attach_berry", "card": "fire_berry", "to": "firepup"}, "hint": "Attach a Fire Berry to Firepup."},
		{"title": "Plunder", "highlight": ["mine:firepup"],
			"text": "Use Firepup's [b]Plunder 1[/b]: click the ability on the creature. Its cost just has to be [i]attached[/i] - berries are never used up by abilities.\n\n[b]Plunder[/b] makes the opponent discard cards from the top of their deck. That empties their deck, and it can also hit their [b]Super Berries[/b]...",
			"expect": {"type": "use_ability", "creature": "firepup", "ability": 1}, "hint": "Use Firepup's Plunder 1 (the second ability on the card)."},
		{"title": "Stolen Super Berry!", "highlight": ["mine:firespore"],
			"text": "A [b]Super Berry[/b] was in the plundered cards. Super Berries aren't discarded: [b]you steal them[/b] and attach them to any of your creatures. A Super Berry counts as a berry of any element.\n\nClick [b]Firespore[/b] to attach it: it will have a Fire Berry and a Super Berry when it wakes up.",
			"expect": {"type": "place_berry", "to": "firespore"}, "hint": "Put the Super Berry on Firespore."},
		{"title": "End your turn", "highlight": ["end_turn"],
			"text": "Each creature can use [b]one ability per turn[/b], and you can use [b]two abilities per turn[/b] in total. Firespore is still asleep and Firepup has used its ability, so press [b]End Turn[/b].",
			"expect": {"type": "end_turn"}, "hint": "Press End Turn."},
		{"title": "The opponent's turn", "text": "Watch what the opponent does with their Water Constrictor.", "bot": true, "button": "Watch the opponent's turn"},
		{"title": "Stun", "highlight": ["mine:firepup", "theirs:water_constrictor"],
			"text": "The opponent's Water Constrictor used [b]Stun 1[/b] on your Firepup. A stunned creature (greyed out, marked STUNNED) [b]can't use abilities[/b] until the end of its controller's next turn.\n\nYou can wait it out, or [b]evolve the creature: evolving removes a stun.[/b] Meanwhile it is turn 5: Firespore has woken up."},
		{"title": "Evolve", "highlight": ["hand:firewolf", "mine:firepup"],
			"text": "Click [b]Firewolf[/b] to evolve Firepup. Evolving puts a Tier 2 card on top of its Tier 1 card: the berries stay, the stun is gone, and it counts as your creature play for the turn.\n\nThe new card's abilities replace the old ones: Firewolf has [b]Pillage 3[/b].",
			"expect": {"type": "play_creature", "card": "firewolf"}, "hint": "Evolve Firepup with Firewolf."},
		{"title": "Berry for Firewolf", "highlight": ["hand:fire_berry", "mine:firewolf"],
			"text": "Pillage 3 needs 2 Fire Berries. Attach a Fire Berry to [b]Firewolf[/b].",
			"expect": {"type": "attach_berry", "card": "fire_berry", "to": "firewolf"}, "hint": "Attach a Fire Berry to Firewolf."},
		{"title": "Firespore wakes up", "highlight": ["mine:firespore"],
			"text": "Firespore is awake. It has a Fire Berry and a Super Berry, and a Super Berry counts as any berry. Use its [b]Plunder 2[/b].",
			"expect": {"type": "use_ability", "creature": "firespore", "ability": 0}, "hint": "Use Firespore's Plunder 2."},
		{"title": "Pillage", "highlight": ["mine:firewolf"],
			"text": "[b]Pillage[/b] is like Plunder, but it hits [b]your own deck[/b]: the top cards go to your discard pile. That sounds bad, but your discard pile is a resource: you can attach berries from it, swap with its creatures and pay for spells with its berries. Any Super Berry you pillage is yours to attach.\n\nUse Firewolf's [b]Pillage 3[/b]. That is your second ability, the most you can use in a turn.",
			"expect": {"type": "use_ability", "creature": "firewolf", "ability": 1}, "hint": "Use Firewolf's Pillage 3."},
		{"title": "Recycle 1", "highlight": ["discard"],
			"text": "Every Pillage ends with a free [b]Recycle 1[/b]: you put one card from your discard pile on the [b]bottom of your deck[/b], so it isn't lost for good. The pillage put a [b]Firespitter[/b] and two [b]Fire Berries[/b] in your discard. Keep the Firespitter, you'll want it soon: recycle a [b]Fire Berry[/b].\n\nClick the Fire Berry in the list, then press Recycle.",
			"expect": {"type": "recycle", "cards": ["fire_berry"]}, "hint": "Recycle a Fire Berry and keep the Firespitter."},
		{"title": "Your discard pile", "highlight": ["discard"],
			"text": "Click your discard pile on the right to see what's in it: the Firespitter and a Fire Berry. You can browse the exile pile the same way (cards there are gone for good).\n\nWe'll use both of them on your next turn."},
		{"title": "End your turn", "highlight": ["end_turn"], "text": "Press [b]End Turn[/b].", "expect": {"type": "end_turn"}, "hint": "Press End Turn."},
		{"title": "The opponent's turn", "text": "A quiet turn for the opponent.", "bot": true, "button": "Watch the opponent's turn"},
		{"title": "Swap", "highlight": ["swap", "hand:firespore"],
			"text": "[b]Swap[/b] lets you put cards from your hand into the discard pile and take a [b]creature[/b] from it. You may swap [b]once per turn[/b], and each swap costs [b]one more card[/b] than the last: your first swap costs 1 card, the next 2, then 3, and so on.\n\nYour spare [b]Firespore[/b] isn't much use, but the Firespitter in your discard is. Press [b]Swap (1)[/b], take the Firespitter and give the Firespore.",
			"expect": {"type": "swap", "hand_cards": ["firespore"], "discard_card": "firespitter"}, "hint": "Swap your Firespore for the Firespitter in your discard."},
		{"title": "Evolve the starter", "highlight": ["hand:firespitter", "mine:firespore"],
			"text": "Play [b]Firespitter[/b] on top of your starting Firespore: Tier 1, now Tier 2. Evolved creatures keep all their berries (a Tier 3 Fireking would come next).",
			"expect": {"type": "play_creature", "card": "firespitter"}, "hint": "Evolve Firespore with Firespitter."},
		{"title": "A berry from the discard", "highlight": ["discard"],
			"text": "You haven't attached a berry this turn. You can use one from your [b]discard pile[/b] instead of your hand: click your discard pile, select a Fire Berry, press [b]Play berry from discard[/b] and choose Firespitter.\n\nA berry attached this way enters [b]exhausted[/b] (sideways, red outline). Exhausted berries still count for ability costs, but when one is spent on a spell it is [b]exiled[/b] instead of discarded.",
			"expect": {"type": "attach_berry", "from": "discard", "card": "fire_berry", "to": "firespitter"}, "hint": "Play a Fire Berry from your discard onto Firespitter."},
		{"title": "Spells", "highlight": ["hand:removal", "theirs:water_constrictor"],
			"text": "Last, a [b]spell[/b]. [b]Removal[/b] sends a creature and all its attached berries to the discard pile. Spells cost berries: Removal costs 3 berries of any kind. You choose which ones pay: berries in your discard pile, or berries attached to a creature (exhausted ones are exiled).\n\nCast Removal on the opponent's [b]Water Constrictor[/b]. Pay with the exhausted berry on Firespitter and two more attached berries.",
			"expect": {"type": "play_spell", "card": "removal", "target": "water_constrictor"}, "hint": "Cast Removal on the opponent's Water Constrictor."},
		{"title": "More to discover", "text": "That covers the basics: [b]mulligan, your starting creature, creatures, evolving, berries, abilities, Plunder, Pillage, Recycle, Stun, Super Berries, swapping and spells[/b].\n\nThere is more in the decks: [b]Reinforce[/b] (pay 3 Fire Berries to play a second creature this turn), [b]Fire Famine[/b] and [b]Firewolf's[/b] [i]Active[/i] abilities (always on, they change what Pillage does), the Water deck's [b]Disable[/b] and [b]Berry Trade[/b], and two more decks, Nature and Light. Hover any card to read it."},
		{"title": "Tutorial complete", "end": true,
			"text": "Nicely done! You can [b]finish this game[/b] against the computer (your board and hand carry on, the opponent plays for real from now on), or quit back to the menu."},
	]
