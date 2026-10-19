# Cowdog Card Game (Godot 4.7 playtest build)

A digital playtest version of the Cowdog Game Store card game. You play seat 0 against a
computer opponent. Included decks: **Scorching Fire** and **Crashing Wave** (Preconstructed).
Rules source: `docs/rules.txt`.

Open the folder in Godot 4.7 and press Play (main scene `scenes/main.tscn`).

## How to play
- Mulligan: click cards to send to the bottom, **Confirm** to draw that many.
- Click a hand card to play it. Basic creatures join the end of your row; berries go onto your creature (you pick when you have several); evolutions go on the creature
  they evolve (you pick if more than one fits). Cards in hand lift when hovered.
- Click an ability box on one of your creatures' cards to use it (2 per turn). Stun/Removal/Berry Trade ask for targets.
- Spells ask which berries pay the cost (the cheapest choice is pre-selected; discard-pile berries are exiled).
- Each player has Deck / Discard / Exile piles (in the right sidebar) showing their card counts. Click a Discard or Exile pile to see its cards (decks are hidden). Hovering a card in any list (piles, swap, spell payment, recycle, Reinforce) shows it big beside the list.
  In your own Discard viewer, select a berry and press **Play berry from discard** to attach it (the card flies out of the pile to the creature).
- Visual effects (toggle on the main menu): the opponent's hand shows as blank cards at the top; their played cards fly to the centre, flip and
  stay 2s before landing (berries 0.7s); your cards fly straight to their target; attached berries pop and blink the creature; berries from
  the discard fly out of the pile with a firework; stuns shoot a blue lightning bolt with fireworks to every target; swaps and spells are shown large in the middle for 2s (spells then fly to their targets).
  The computer waits for effects to finish before acting.
- Super Berries found in a deck by Plunder or Pillage (and, with Fire Famine, every berry it finds) pop up in the middle of the screen briefly before you choose where they go.
- Plunder lays the plundered cards out in a row in the middle of the screen, then sends them to the discard (Super Berries stay for you to place). If a Plunder or Pillage finds no berries, "No berries found" flashes up.
- Berries on a creature have a green ring when they were played from hand (upright) and a red ring when exhausted (sideways). The berry you are about to place shows beside the prompt and in the big preview.
- A destroyed creature stays on the table until the Removal card has finished its animation and landed on it.
- **Menu** always asks before leaving. In multiplayer it is also how you surrender: confirming concedes the game (you lose, your opponent wins).
- Clicks on an ability within about half a second of another action are ignored, so a double-click can't use an ability by accident.
- The status strip in the middle of the board only appears while it has something to say.
- Used abilities flash for 1.5s so it's clear what was activated. Creature spaces are numbered 1-5 (shown on the board and in the payment list).
- Hover any card (hand, board, piles) to see it large in the right-hand column. **Log** shows the full game log. **Swap** is the once-per-game hand/discard creature swap.

## Multiplayer
Peer-to-peer games (one player hosts, no server) are in **Multiplayer (beta)** on the main menu; single player is unchanged. How to host/join, how it works and the plan for 4 players are in
`docs/MULTIPLAYER.md`. The last single-player-only commit is `84bb8dc`.

## Art and look
- Cards are drawn in code at a fixed 300x420 size (frame, name, `Basic` / `Evolves from X`, element badge, art window, ability boxes with cost badges, spell text) and
  scaled to wherever they are shown. The frame is a **placeholder** built from element colours; the art, symbols, font (Gluten, OFL licence in `assets/fonts`) and board
  background come from your files. Missing art or symbols fall back to a plain placeholder, so partial art is fine.
- `assets/` holds the processed art: `cards/` (creature, spell and berry art with transparent backgrounds), `symbols/` (white glyphs, tinted in-game), `berries/`
  (small berry icons), `board/board_bg.webp`, `ui/card_back_logo.png` (used as the card back for now).
- **Replacing art:** drop the new raw files into the same folder structure as the original delivery (`FireCards/`, `WaterCards/`, `Berries/`, `Symbols/`) and run
  `python3 tools/process_art.py <raw_dir> assets` (needs pillow, numpy, scipy). It removes the white backgrounds and writes the game-ready PNGs. File names map to card ids in that script.
  Missing element symbols (Void, Metal, Air, Electric) show a lettered badge until their art exists.
- Evolved creatures sit on top of the card they evolved from; the lower cards keep their name plates showing above it. Creatures sit in a row (no fixed spaces) and shuffle over
  to make room; the board holds 5. The number on each creature matches the numbers in the spell payment list.
- The layout uses anchors and containers (board and hand on the left, piles, card preview and buttons in a right-hand column) on a 1600x900 canvas that scales with the window.
  A phone/portrait layout can later replace the right-hand column with popups.

## Layout
- `data/cards.json`, `data/decks.json` - all card and deck data. New decks/cards are added here.
- `scripts/core/` - `GameEngine` (authoritative rules), `Rules` (helpers/constants), `CardDB`.
- `scripts/agents/` - `PlayerAgent` interface, `AIAgent` (computer), `HumanAgent`.
- `scripts/game_controller.gd` - connects the engine to one agent per seat.
- `scripts/net/` - peer-to-peer multiplayer (`NetSession`, `RemoteController`).
- `scripts/ui/`, `scripts/main.gd` - menu and table UI; `fx_layer.gd` holds the visual effects. The engine's log events carry an optional `fx` payload that the UI plays.
- `tests/` - `fx_demo.gd` (screenshots of every effect), `run_sim.gd` (AI vs AI, rule invariants), `ui_smoke.gd`, `ui_interact.gd`, `screenshot.gd`.

## Networking later
The engine is already shaped for it:
- All state changes go through `GameEngine.submit(player, action)` with a plain-Dictionary action; results and
  log events are plain data (JSON-friendly).
- The engine owns all randomness (`seed_value` is recorded); clients never need to shuffle.
- The UI and AI read only `get_view(seat)`, which hides the opponent's hand and deck order.
- A remote player is just another `PlayerAgent`: the host runs `GameController`, sends `get_view(seat)` to the
  client and feeds the client's actions into `GameController.submit(seat, action)`.

## Tests
```
godot --headless --import --quit
godot --headless -s tests/run_sim.gd -- 200     # AI vs AI; fails on illegal AI moves, stuck games, lost cards
godot --headless -s tests/rules_test.gd
godot --headless -s tests/targets_test.gd     # every Plunder hits the opponent, every Pillage hits yourself
godot --headless -s tests/ui_payment.gd
xvfb-run godot --rendering-driver opengl3 -s tests/ui_ability_click.gd   # clicking an ability box on a board card
xvfb-run godot --rendering-driver opengl3 -s tests/ui_click_area.gd   # needs a display for real mouse events
godot --headless -s tests/ui_smoke.gd
godot --headless -s tests/net_test.gd        # host + client over a real local connection play a full game
godot --headless -s tests/net_ui_test.gd     # both screens over the network
godot --headless -s tests/net_surrender_test.gd   # Menu -> confirm surrenders in multiplayer
godot --headless -s tests/ui_double_click.gd      # no accidental ability use after a click
godot --headless -s tests/ui_removal_ghost.gd     # a destroyed creature stays until the Removal animation ends
godot --headless -s tests/net_disconnect_test.gd  # a dropped player concedes
xvfb-run godot --rendering-driver opengl3 -s tests/ui_lobby.gd -- /tmp/out   # lobby screenshots
xvfb-run godot --rendering-driver opengl3 -s tests/ui_look.gd -- /tmp/out   # screenshots of the menu and a full table
xvfb-run godot --rendering-driver opengl3 -s tests/ui_pile_hover.gd    # big card preview in pile lists
xvfb-run godot --rendering-driver opengl3 -s tests/ui_picker_preview.gd  # ...and in the other pickers
xvfb-run godot --rendering-driver opengl3 -s tests/ui_picker_preview.gd  # ...and in the swap/payment/recycle pickers
xvfb-run godot --rendering-driver opengl3 -s tests/ui_order_pick.gd      # numbered recycle ordering
xvfb-run godot --rendering-driver opengl3 -s tests/ui_toggle_click.gd   # one-click toggling in the payment list
godot --headless -s tests/ui_interact.gd
```

## Rule interpretations (the document left these open - all easy to change)
Constants live in `scripts/core/rules.gd`.
- **Decks**: the decks as listed have 7 Super Berries (the rules text says 6); the lists are used as written.
- **Board**: 5 creature spaces per player; Tier 2/3 creatures still use one space.
- **Ability limit**: 2 ability uses per turn for the whole player, and each creature can use only one ability per turn.
- **Ability costs are requirements, not payments**: berries stay attached. An element cost accepts that element or
  Super Berries; a "Super Berry" cost needs actual Super Berries.
- **First player draws** on turn 1, but neither player can use abilities on their own first turn (`FIRST_TURN_NO_ABILITIES`).
- **Plunder X** with fewer than X cards left in the target's deck ends the game immediately: the plundered player loses (the plunder still takes as many cards as it can, including Super Berries, before the loss applies).
- **Evolving** keeps attached berries (and removes any stun); a creature may evolve the turn it was played (still 1 play/evolve per turn).
- **Stun X** can target any creatures (up to X); it ends at the end of the stunned creature's controller's next turn. Active abilities keep working.
- **Exhausted (sideways) berries**: you may attach a berry from your discard instead of from hand; it counts as your berry for the turn and
  enters exhausted. Any exhausted berry that would be discarded (spell payment, Removal, Berry Trade) is exiled instead. Exhausted berries still
  count toward ability costs and never untap (not specified).
- **Spell payment**: pay with attached berries (upright or exhausted) or exile berries from your discard. Upright ones go to the discard,
  exhausted ones to exile. Colorless = any berry; element cost = that element or Super.
- **Revealed Super Berries** (from Plunder or Pillage) go onto a creature of the acting player's choice (the game pauses for the choice), or into their hand if they have no creature.
- **Evolving** a stunned creature removes the stun.
- **Reinforce** costs 3 Fire Berries and lets you play a second creature this turn (it adds one creature play; casting it twice gives two extra).
- **Recycling order**: whenever cards are recycled you choose the order they go on the bottom of the deck. Click cards to number them 1, 2, 3...: 1 is put on the bottom
  first (so it is drawn soonest of the group) and the highest number ends up at the very bottom.
- **Pillage**: Super Berries are always attached to a creature of your choice. Other revealed cards go to the discard, except that with Fire Famine's Active
  effect every berry is attached to a creature of your choice. With Fire Famine's Active effect, all pillaged non-berry cards are also recycled to the bottom of the deck (you choose their order) instead of going to the discard, so
  Firewolf has nothing to recycle from that pillage. With Firewolf's Active effect you then choose as many cards from your discard to recycle as
  went to the discard in that pillage - berries attached to creatures don't count (e.g. Pillage 4 revealing 2 berries recycles 2; Active effects don't stack, so
  several Firewolves still recycle just that many; capped by the discard size; they go to the bottom in the order chosen).
- **Berry Trade** (Water Ruler) discards berries from the Ruler itself and from one enemy creature.
- **Not yet implemented**: casting spells in response to abilities/plays (spells are playable on your own turn only), Free-Form deck building, deck size/Super Berry validation.

## Known gaps in the AI
It is a heuristic player: it plays Plunder-focused lines and only uses Pillage with Recycle/Scavenger active, so Scorching Fire
is under-represented (the AI wins ~15% with Fire vs Water). Don't read win rates as deck balance yet.
