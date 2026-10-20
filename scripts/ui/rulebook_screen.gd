class_name RulebookScreen
extends Control
## A text rulebook: a list of sections on the left, the selected section on the right.

signal back_requested

const SECTIONS := [
	["Overview", """[b]Goal[/b]
Two players each have a deck of 50 cards. You win when your opponent can no longer keep up: a player [b]loses[/b] when they have to draw a card and their deck is empty, or when a [b]Plunder[/b] asks for more cards than their deck has left. A player may also concede at any time.

[b]What you do[/b]
You build a team of up to 5 [b]creatures[/b] and feed them [b]berries[/b]. Berries let your creatures use [b]abilities[/b], and most abilities attack the opponent's deck (Plunder) or reshape your own cards (Pillage, Stun, spells and more). Whoever runs the other player out of cards first wins.

[b]Formats[/b]
In [b]Preconstructed[/b] you play a deck exactly as it is sold. In [b]Free-Form[/b] you may mix cards from different decks into your own 50-card deck (6 of the cards must be Super Berries). This digital build offers the two preconstructed decks, [i]Scorching Fire[/i] and [i]Crashing Wave[/i], and they each contain 7 Super Berries."""],
	["Card types", """[b]Creatures[/b] are the cards that do things. Each has an [b]element[/b], a [b]tier[/b] (1, 2 or 3) and at least one [b]ability[/b]. Tier 1 creatures are written [i]Basic[/i]; Tier 2 and 3 say [i]Evolves from <name>[/i].

[b]Berries[/b] come in two kinds:
- [b]Element Berries[/b] (Fire, Water, Nature, Light, Shadow, Void, Metal, Air, Electric). When something needs a berry of an element, you need a berry of that element.
- [b]Super Berries[/b] count as a berry of [b]any[/b] element. A few abilities need Super Berries specifically, and only a Super Berry can pay for those.

[b]Spells[/b] are one-time effects with a berry cost. After a spell resolves it goes to your discard pile."""],
	["The zones", """[b]Deck[/b] (library): your face-down draw pile. Its order is hidden; you never see the cards.
[b]Hand[/b]: cards you hold. The opponent only sees how many.
[b]Board[/b]: your creatures, up to [b]5[/b]. Each creature is a stack of cards (its Tier 1 card with its evolutions on top) plus the berries attached to it.
[b]Discard pile[/b]: face up and open to both players. Click a pile to browse it. Cards that are used up, plundered, pillaged or destroyed go here.
[b]Exile pile[/b]: face up, but cards here are out of the game for good. Nothing returns from exile.

On screen your piles are at the lower right and the opponent's at the upper right; the number is how many cards are in the pile."""],
	["Starting the game", """1. Each player shuffles their deck. The players roll to see who goes first.
2. Each player draws [b]7 cards[/b].
3. [b]Mulligan:[/b] once, each player may choose any number of cards from their hand and put them on the [b]bottom[/b] of their deck; they then draw that many cards. Pressing Confirm with nothing selected keeps the hand.
4. The first player takes turn 1."""],
	["Your turn", """Every turn starts with you [b]drawing a card[/b] (the first player draws too). If you can't draw, you lose.

Then, in any order you like, you may:
- [b]Attach one berry[/b] to one of your creatures, from your hand or from your discard pile (once per turn).
- [b]Play one creature[/b], or [b]evolve[/b] one (once per turn). Putting a new creature on the board and evolving both count as your creature play.
- [b]Use abilities:[/b] up to [b]2 per turn in total[/b], and each creature can use [b]only one[/b] ability per turn.
- Use the [b]swap[/b] (once per [i]game[/i]).
- Play [b]any number of spells[/b] you can pay for.

When you are done, press [b]End Turn[/b]. Then your opponent's turn begins.

[b]The first-turn rule:[/b] nobody can use abilities on their own first turn. In practice abilities are locked on turns 1 and 2 of the game (the first turn of each player), and you can start using them from your second turn."""],
	["Creatures and evolving", """[b]Playing a creature.[/b] A Tier 1 creature goes into an empty place on your board. The board is packed to the left: new creatures join at the right end, and when a creature leaves, the others close up. You can't have more than 5 creatures.

[b]Evolving.[/b] A Tier 2 creature is played [i]on top of[/i] the Tier 1 creature named on the card, and a Tier 3 creature on top of the named Tier 2. The creature keeps all its attached berries, and only the top card counts: you see its name and abilities, while the cards underneath show as name strips. A creature still takes just one place on the board.

Evolving also [b]removes a stun[/b] from the creature.

[b]One ability per creature per turn.[/b] Evolving does not give a creature another ability use: if it already used an ability this turn, the evolved card can't use one until your next turn.

[b]Reinforce[/b] and similar effects can let you play a second creature in a turn."""],
	["Berries and abilities", """[b]Attaching berries.[/b] Once per turn you attach a berry from your hand to a creature, or from your discard pile (see below). Berries stay on the creature until something removes them (a spell cost, Removal, a Berry Trade, ...).

[b]Ability costs are requirements, not payments.[/b] An ability such as [i]2 Fire Berries: Plunder 3[/i] can be used when the creature has at least two matching berries [i]attached[/i]. Using the ability does not discard them, so a creature with enough berries can use its ability every turn. A Super Berry matches any element.

[b]Exhausted berries.[/b] A berry you attach from your discard pile enters [b]exhausted[/b]: it is turned sideways (shown with a red outline instead of green). An exhausted berry still counts for ability costs and for matching, but when it is spent on a spell it is [b]exiled[/b] instead of discarded.

[b]Using an ability.[/b] Click the ability on the creature (it lights up when usable). Abilities that need a choice, such as Stun, ask for targets first. A creature can't use abilities if it is [b]stunned[/b], if it has already used one this turn, if you have used 2 abilities this turn, or if it lacks the berries.

[b]Active abilities[/b] are marked [i]Active[/i]. They are not used; they are always on, as long as the creature has the berries they need."""],
	["Keywords", """[b]Plunder X[/b] - the opponent puts the top X cards of their deck into their discard pile. Every [b]Super Berry[/b] found this way is not discarded: you take it and attach it to one of your creatures (you choose which). If you have no creature, it goes to your hand. If the opponent's deck has fewer than X cards, they discard everything they have, you still take any Super Berries, and then they lose the game.

[b]Pillage X[/b] - the same, but to [i]your own[/i] deck: you put your top X cards into your discard pile. This fills your discard pile with berries (to attach from the discard pile or pay for spells) and creatures (for the swap). Super Berries you pillage are yours to attach to a creature too. [b]Every Pillage ends with a free Recycle 1[/b]: you put one card of your choice from your discard pile on the bottom of your deck (if your discard pile is empty there is nothing to recycle). Careful: pillaging still thins your own deck.

[b]Stun X[/b] - choose up to X creatures. They can't use abilities until the end of their controller's next turn. Active abilities keep working. A stunned creature is shown greyed out and marked STUNNED. [b]Evolving a stunned creature removes the stun.[/b]

[b]Active[/b] - the effect is always on while the creature has the required berries. Active effects of the same kind do not stack: two Firewolves recycle just as much as one.

[b]Recycle X[/b] - put X cards from your discard pile on the [b]bottom of your deck[/b], in any order you choose. You pick the cards and the order. If your discard pile has fewer than X cards, you recycle them all.

[b]Exile[/b] - some effects send cards to your exile pile instead of the discard pile. Exile is face up but permanent.

[b]Berry Trade[/b] - choose a number of berries attached to the creature, discard them, and discard the same number of berries of your choice from an enemy creature."""],
	["Spells", """Spells are cast from your hand on your turn. Each has a berry cost, and [b]you choose which berries pay[/b]:
- [b]Upright[/b] berries attached to your creatures (green outline) are [b]discarded[/b].
- [b]Exhausted[/b] (sideways, red outline) attached berries are [b]exiled[/b].
- Berries in your [b]discard pile[/b] are [b]exiled[/b]. These are usually the cheapest to pay with, since they aren't doing any work.

Berries must match the cost: [i]Colorless[/i] accepts any berry, and an element accepts that element or a Super Berry. The payment window lists the creatures numbered 1 to 5 from the left, and one click selects or deselects a berry.

[b]Removal[/b] (3 Colorless) sends a creature and all berries attached to it to the discard pile.
[b]Reinforce[/b] (3 Fire) lets you play a second creature this turn.
[b]Disable[/b] (1 Colorless) is Stun 1.
[b]Trash[/b] (2 Nature) exiles 3 cards of your choice from your discard pile. The berries that pay for it can't also be the cards it exiles."""],
	["The swap", """Once per [b]game[/b], on your turn, you may swap a creature card in your hand with a creature card in your discard pile. Press [b]Swap[/b], choose the creature from your hand to give, then the creature from your discard pile to take. Both cards are shown to everyone. The button is disabled once you have used the swap."""],
	["Scorching Fire cards", """[b]Firespore[/b] (Tier 1): 1 Fire Berry, Plunder 2.
[b]Firespitter[/b] (Tier 2, on Firespore): 2 Fire Berries, Plunder 3.
[b]Fireking[/b] (Tier 3, on Firespitter): 3 Fire Berries, Plunder 5; or 2 Super Berries, Inferno: Plunder 1 for each berry attached to this creature.
[b]Firepup[/b] (Tier 1): 2 Fire Berries, Pillage 2; or 1 Fire Berry, Plunder 1.
[b]Firewolf[/b] (Tier 2, on Firepup): 2 Super Berries, [i]Active:[/i] when you pillage, [b]recycle[/b] as many cards as went to your discard pile (berries attached to creatures don't count; several Firewolves don't stack), in addition to the free Recycle 1 of every Pillage; or 2 Fire Berries, Pillage 3.
[b]Fire Famine[/b] (Tier 1): 1 Super Berry, [i]Active:[/i] when you pillage, every pillaged berry can be attached to any of your creatures, and all other pillaged cards are recycled to the bottom of your deck (you choose their order); or 2 Fire Berries, Pillage 4.
[b]Removal[/b], [b]Reinforce[/b]: see Spells.

[b]Strategy:[/b] Firespore and Fireking plunder; Firepup, Firewolf and Fire Famine pillage and then recycle, so your deck lasts longer than your opponent's. Every pillage recycles at least one card."""],
	["Crashing Wave cards", """[b]Water Spirit[/b] (Tier 1): 1 Water Berry, Plunder 2.
[b]Water Sprite[/b] (Tier 2, on Water Spirit): 2 Water Berries, Plunder 3; or 2 Water Berries, Stun 1.
[b]Water Ruler[/b] (Tier 3, on Water Sprite): 1 Super Berry, Berry Trade; or 2 Water Berries, Plunder 3.
[b]Water Constrictor[/b] (Tier 1): 1 Water Berry, Stun 1; or 1 Water Berry, Plunder 2.
[b]Water Binder[/b] (Tier 2, on Water Constrictor): 2 Water Berries, Stun 2; or 2 Water Berries, Plunder 3.
[b]Water Crash[/b] (Tier 1): 3 Super Berries, Plunder 5.
[b]Removal[/b], [b]Disable[/b]: see Spells.

[b]Strategy:[/b] stun the creatures that threaten you, trade away the opponent's berries, and plunder."""],
	["Nature Exile cards", """[b]Leafer[/b] (Tier 1): 1 Nature Berry, Plunder 2.
[b]Leaflet[/b] (Tier 2, on Leafer): 2 Nature Berries, Recycle 2; or 2 Nature Berries, Plunder 3.
[b]Leafren[/b] (Tier 3, on Leaflet): 2 Nature Berries, Recycle 3; or 2 Nature Berries, Plunder 3; or [i]Mulch[/i], 1 Super Berry: exile a Super Berry attached to this creature, then Recycle 6.
[b]Spore Spreader[/b] (Tier 1): 1 Nature Berry, Recycle 2; or [i]Spore Cloud[/i], 2 Super Berries: Plunder 1 for each card in your exile pile.
[b]Spore Muncher[/b] (Tier 2, on Spore Spreader): 2 Nature Berries, Recycle 3; or [i]Decompose[/i], 3 Super Berries: exile a spell from your discard pile and play it (you don't pay its berry cost, choose its targets as usual).
[b]Moosh[/b] (Tier 1): [i]Rot[/i], 2 Nature Berries: exile a Nature Berry attached to this creature, then Plunder 3.
[b]Removal[/b], [b]Trash[/b]: see Spells. [b]Trash[/b] (2 Nature Berries): exile 3 cards of your choice from your discard pile.

Exiled cards never come back, but they are counted by Spore Spreader. An ability that needs an empty pile to do anything (Recycle with no discard pile, Spore Cloud with no exile) can't be used. Recycle 6 with fewer than 6 cards in your discard pile recycles all of them.

[b]Strategy:[/b] fill your exile pile with Trash, Mulch, Rot and spent berries, then let Spore Spreader plunder for it, and keep your deck healthy by recycling."""],
	["Using the screen", """[b]Playing cards.[/b] Click a card in your hand. A berry goes on a creature (if you have several, click which one); a creature is played or evolves; a spell asks for its target and payment. Hover a card to see it large in the right-hand panel.

[b]Using abilities.[/b] Click the ability on the creature. Ability boxes only react when the creature can use that ability.

[b]Piles.[/b] Click your discard pile to browse it and to play a berry from it. Click the exile pile or the opponent's piles to browse them.

[b]Log.[/b] The Log button lists everything that has happened this game.

[b]Menu.[/b] Leave the game. In a multiplayer game this means [b]surrender[/b], and the opponent wins.

[b]Effects.[/b] Card flights, plundered cards laid out in the middle, stun bolts and so on can be switched off on the main menu."""],
]

var _list: ItemList
var _text: RichTextLabel


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.12, 0.11)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	var head := HBoxContainer.new()
	root.add_child(head)
	var back := Button.new()
	back.text = "< Back"
	back.pressed.connect(func(): back_requested.emit())
	head.add_child(back)
	var title := Label.new()
	title.text = "Rulebook"
	title.add_theme_font_size_override("font_size", 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = back.get_minimum_size()
	head.add_child(spacer)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(260, 0)
	_list.add_theme_font_size_override("font_size", 17)
	for s in SECTIONS:
		_list.add_item(s[0])
	_list.item_selected.connect(_show_section)
	body.add_child(_list)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 18)
	_text.add_theme_font_size_override("bold_font_size", 18)
	_text.add_theme_font_size_override("italics_font_size", 18)
	body.add_child(_text)
	_list.select(0)
	_show_section(0)


func _show_section(i: int) -> void:
	# The font has no bold or italic face, so emphasis is shown with colour.
	var body: String = SECTIONS[i][1]
	body = body.replace("[b]", "[color=#f2d065]").replace("[/b]", "[/color]").replace("[i]", "[color=#9fd3ff]").replace("[/i]", "[/color]")
	_text.text = "[font_size=28][color=#ffffff]%s[/color][/font_size]\n\n%s" % [SECTIONS[i][0], body]
	_text.scroll_to_line(0)
