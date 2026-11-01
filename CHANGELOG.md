# Changelog

## 0.7.0
- Art packs: packs without a preview picture or table background now show a grid of their cards on the Art packs screen. The computer opponent always uses the default art.
- Removed the Computer speed slider and the Visual effects checkbox (effects are always on).
- Art pack conflicts can be resolved picture by picture or by picking one whole pack (option on the Art packs screen).
- Several art packs can be switched on at once (e.g. a table background plus a card-art pack). If two packs have the same picture, one is picked at random at the start of each game.
- A pack's berry art now only appears on the berries of the decks the pack is made for (never the opponent's). The game server address is pre-filled.
- Room codes: a small game server (Start Game Server.bat, optional free Cloudflare tunnel) lets friends connect with a 5-letter code, no port forwarding.
  The old direct-address mode stays available. See docs/MULTIPLAYER.md.
- Build script tools/build_windows.sh; the zip now contains HOW_TO_PLAY.txt, Start Game Server.bat and a console exe for the server.

## 0.6.2
- A big "YOUR TURN" banner flashes when the turn passes to you.
- Multiplayer turn clock: 60 seconds per turn, +4 seconds for every action you complete. When it runs out your turn ends automatically
  (open choices are resolved for you); if you took no action at all that turn you forfeit and your opponent wins. Single player has no clock.

## 0.6.1
- Tidal Surge is removed from the game. Berry Trade moved from Water Ruler to Water Essence (1 Super Berry), which now has only that ability. Water Ruler gets Rearrange (2 Super Berries): move all
  berries between your creatures, then Plunder X = the most berries on one of your creatures.

## 0.6.0 (first playtest build)
- Four decks with leaders: Scorching Fire, Crashing Wave, Nature Exile, Light. Starting leaders are dormant until turn 5 and can't be targeted.
- Swap: once per turn, give N cards from hand for a creature in the discard (N grows by one each time).
- Every Pillage ends with a free Recycle 1. Fireking's Twin Flame doubles the next Plunder ability; Fire Lord plunders X - 2.
- Art packs (table background and card art), a tutorial and a rulebook.
- Playtest support: build version and data fingerprint (online players must match), a saved report of every game (replayable),
  a settings screen with fullscreen (F11), remembered menu choices, "Play again" online, a copy-address button.
