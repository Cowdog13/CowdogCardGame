# Cowdog Card Game (Godot 4.7 playtest build)

A digital playtest version of the Cowdog Game Store card game. You play seat 0 against a
computer opponent. Included decks: **Scorching Fire** and **Crashing Wave** (Preconstructed).
Rules source: `docs/rules.txt`.

Open the folder in Godot 4.7 and press Play (main scene `scenes/main.tscn`).

## How to play
- Mulligan: click cards to send to the bottom, **Confirm** to draw that many.
- Click a hand card, then click a highlighted board space (berry -> creature, creature -> space/evolve target).
- Click an ability button on one of your creatures to use it (2 per turn). Stun/Removal/Berry Trade ask for targets.
- Spells show how they will be paid before they resolve (discard-pile berries are exiled first).
- Hover anything for card text. **Swap** is the once-per-game hand/discard creature swap.

## Layout
- `data/cards.json`, `data/decks.json` - all card and deck data. New decks/cards are added here.
- `scripts/core/` - `GameEngine` (authoritative rules), `Rules` (helpers/constants), `CardDB`.
- `scripts/agents/` - `PlayerAgent` interface, `AIAgent` (computer), `HumanAgent`.
- `scripts/game_controller.gd` - connects the engine to one agent per seat.
- `scripts/ui/`, `scripts/main.gd` - menu and table UI.
- `tests/` - `run_sim.gd` (AI vs AI, rule invariants), `ui_smoke.gd`, `ui_interact.gd`, `screenshot.gd`.

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
godot --headless -s tests/ui_smoke.gd
godot --headless -s tests/ui_interact.gd
```

## Rule interpretations (the document left these open - all easy to change)
Constants live in `scripts/core/rules.gd`.
- **Decks**: the decks as listed have 7 Super Berries (the rules text says 6); the lists are used as written.
- **Board**: 3 creature spaces per player.
- **Ability limit**: 2 ability uses per turn for the whole player (not per creature).
- **Ability costs are requirements, not payments**: berries stay attached. An element cost accepts that element or
  Super Berries; a "Super Berry" cost needs actual Super Berries.
- **First player draws** on turn 1 (`FIRST_PLAYER_SKIPS_FIRST_DRAW` toggles this).
- **Evolving** keeps attached berries and stun; a creature may evolve the turn it was played (still 1 play/evolve per turn).
- **Stun X** can target any creatures (up to X); it ends at the end of the stunned creature's controller's next turn. Active abilities keep working.
- **Spell payment**: discard attached berries or exile berries from your discard (the "upright/sideways" distinction is not modeled).
  Colorless = any berry; element cost = that element or Super.
- **Stolen Super Berries** (discarded from an opponent's deck by Plunder) attach to the thief's best creature, or go to the thief's hand if they have none.
- **Reinforce** needs your creature play for the turn (it is a creature play), and only the turn the creature was pillaged.
- **Firewolf's recycle** picks cards automatically (newest first, keeping creatures in the discard when possible).
- **Berry Trade** (Water Ruler) discards berries from the Ruler itself and from one enemy creature.
- **Not yet implemented**: casting spells in response to abilities/plays (spells are playable on your own turn only), Free-Form deck building, deck size/Super Berry validation.

## Known gaps in the AI
It is a heuristic player: it plays Plunder-focused lines and only uses Pillage with Recycle/Scavenger active, so Scorching Fire
is under-represented (the AI wins ~15% with Fire vs Water). Don't read win rates as deck balance yet.
