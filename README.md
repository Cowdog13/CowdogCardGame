# Cowdog Card Game (Godot 4.7 playtest build)

A digital playtest version of the Cowdog Game Store card game. You play seat 0 against a
computer opponent. Included decks: **Scorching Fire** and **Crashing Wave** (Preconstructed).
Rules source: `docs/rules.txt`.

Open the folder in Godot 4.7 and press Play (main scene `scenes/main.tscn`).

## How to play
- Mulligan: click cards to send to the bottom, **Confirm** to draw that many.
- Click a hand card, then click a highlighted board space (berry -> creature, creature -> space/evolve target).
- Click an ability button on one of your creatures to use it (2 per turn). Stun/Removal/Berry Trade ask for targets.
- Spells ask which berries pay the cost (the cheapest choice is pre-selected; discard-pile berries are exiled).
- **Discard** and **Exile** buttons show both players' piles.
- Visual effects (toggle on the main menu): the opponent's hand shows as blank cards at the top; their played cards fly to the centre, flip and
  stay 2s before landing (berries 0.7s); your cards fly straight to their target; attached berries pop and blink the creature; berries from
  the discard get a firework and a line to the creature; swaps and spells are shown large in the middle for 2s (spells then fly to their targets).
  The computer waits for effects to finish before acting.
- Hover anything for card text. **Swap** is the once-per-game hand/discard creature swap.

## Layout
- `data/cards.json`, `data/decks.json` - all card and deck data. New decks/cards are added here.
- `scripts/core/` - `GameEngine` (authoritative rules), `Rules` (helpers/constants), `CardDB`.
- `scripts/agents/` - `PlayerAgent` interface, `AIAgent` (computer), `HumanAgent`.
- `scripts/game_controller.gd` - connects the engine to one agent per seat.
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
godot --headless -s tests/ui_payment.gd
xvfb-run godot --rendering-driver opengl3 -s tests/ui_click_area.gd   # needs a display for real mouse events
godot --headless -s tests/ui_smoke.gd
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
- **Evolving** keeps attached berries (and removes any stun); a creature may evolve the turn it was played (still 1 play/evolve per turn).
- **Stun X** can target any creatures (up to X); it ends at the end of the stunned creature's controller's next turn. Active abilities keep working.
- **Exhausted (sideways) berries**: you may attach a berry from your discard instead of from hand; it counts as your berry for the turn and
  enters exhausted. Any exhausted berry that would be discarded (spell payment, Removal, Berry Trade) is exiled instead. Exhausted berries still
  count toward ability costs and never untap (not specified).
- **Spell payment**: pay with attached berries (upright or exhausted) or exile berries from your discard. Upright ones go to the discard,
  exhausted ones to exile. Colorless = any berry; element cost = that element or Super.
- **Revealed Super Berries** (from Plunder or Pillage) go onto a creature of the acting player's choice (the game pauses for the choice), or into their hand if they have no creature.
- **Evolving** a stunned creature removes the stun.
- **Reinforce** ignores (and doesn't use up) the once-per-turn creature play, and only works on a creature pillaged this turn.
- **Firewolf's recycle** picks cards automatically (newest first, keeping creatures in the discard when possible).
- **Berry Trade** (Water Ruler) discards berries from the Ruler itself and from one enemy creature.
- **Not yet implemented**: casting spells in response to abilities/plays (spells are playable on your own turn only), Free-Form deck building, deck size/Super Berry validation.

## Known gaps in the AI
It is a heuristic player: it plays Plunder-focused lines and only uses Pillage with Recycle/Scavenger active, so Scorching Fire
is under-represented (the AI wins ~15% with Fire vs Water). Don't read win rates as deck balance yet.
