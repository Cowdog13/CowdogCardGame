# Playtesting

## For testers (send this to your friends)

**What this is:** an early playtest of a card game. The goal is to find rules problems, confusing moments and unbalanced cards.

1. Download the Windows zip from the itch.io page, unzip it, and run `CowdogCardGame.exe`. (Windows may warn about an unknown
   publisher: "More info", then "Run anyway".) The first time, accept the offer to play the **tutorial**; it takes about ten minutes.
2. **Everyone must have the same build.** The version is shown at the bottom of the main menu (for example `v0.6.0 playtest (data 3fa9c1d2)`).
   The game refuses to connect to someone on another build and tells you both versions.
3. Play against the computer (Start Game) or a friend (Multiplayer: one hosts and gives the other their address; if connecting is
   a problem, ask for help, an easy fix is a free virtual network such as Radmin VPN or ZeroTier).
4. Try every deck, and try to break things: odd card combinations, the swap, the leaders, Plunder-ing the last cards of a deck.

**Reporting.** After each game the game saves a small report file (the game over window tells you so). During a game you can also press
**Log** then **Save game report**. The folder is `%APPDATA%\CowdogCardGame\reports` (Settings, then "Open the game reports folder").
Please send the newest file(s) plus a sentence on what looked wrong or too strong. The report lets the game be replayed exactly.

Useful things to tell us: which deck you played, which card or leader felt too strong or too weak, any moment where the rules or the
card text confused you, anything that seemed to break (wrong number, stuck game, nothing happened).

## For the organiser

- **Bump the version** in `scripts/core/build_info.gd` (`VERSION`) for every build that goes to testers. The data fingerprint changes
  by itself when a card or deck changes, so a forgotten bump is still caught when players connect.
- **Replay a report:** `godot --headless -s tools/replay_report.gd -- path/to/report.json` prints the whole game from the log and
  checks that it ends the same way (only on the same build; reports from a joined player have only their log).
- **Balance matrix (AI vs AI):** `godot --headless -s tests/balance_matrix.gd -- 40` gives win rates for every deck pairing. The AI is a
  modest player, so treat it as a smoke test, not the truth.
- **All tests:** see the list in the README.
