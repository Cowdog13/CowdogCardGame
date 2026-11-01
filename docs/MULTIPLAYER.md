# Multiplayer (peer to peer)

Open **Multiplayer (beta)** on the main menu. The single-player game is untouched and still starts from the same menu.
(The last commit before any multiplayer code is `84bb8dc`; `git checkout 84bb8dc` gives exactly the single-player-only build.)

## Playing
- **Host:** pick a name and deck, choose *Host a game*, then *Open lobby*. Give your friend one of the addresses shown.
  - Same network (home Wi-Fi / LAN): use the "Same network" address - it just works.
  - Over the internet: leave "open the port with UPnP" ticked. If your router supports it, the lobby shows an "Over the internet" address.
    If not, forward **UDP port 24680** (or the port you chose) to your computer in the router settings, and allow the game through the firewall.
    Some ISPs (carrier-grade NAT) don't allow incoming connections at all; see *Limits* below.
- **Join:** pick a name and deck, choose *Join a game*, type the host's address (`ip` or `ip:port`) and press *Connect*.
- The host presses *Start game* when both players are in. Each player uses their own deck.
- **Surrender:** the Menu button asks for confirmation and then concedes - you lose and your opponent wins; both players see the result and return to the menu.
  Closing the window or losing the connection also counts as a concession. If the host's program closes, the other player is disconnected.
- To try it on one computer, start two copies of the game; host in one and join `127.0.0.1` in the other.

## Room codes through a game server (no port forwarding)
A small **relay server** lets players connect by room code. Everyone only makes *outgoing* connections to it, so nobody opens a port.
It never runs the game: the host's game is still the real game, the relay only passes packets (`scripts/net/relay_server.gd`, `relay_peer.gd`).
- **Organiser (one person):** double-click `Start Game Server.bat` from the game folder (it runs `CowdogCardGame.console.exe --headless -- --relay --port=24681`).
  For friends outside your network also put the free `cloudflared.exe` (or `cloudflared-windows-amd64.exe`) next to the .bat: the .bat then starts a Cloudflare quick tunnel and its
  window shows `https://<random-words>.trycloudflare.com` (changes every start). A fixed address needs a free Cloudflare account and a domain, or a $5 VPS running the same command.
- **Players:** Multiplayer -> *Room code* -> host opens the lobby and reads out the 5-letter code; the joiner enters the same server address and code.
  Addresses may be written `name.trycloudflare.com`, `wss://...`, or `192.168.1.20:24681` (plain `ws://` for IPs and localhost).
  `BuildInfo.DEFAULT_RELAY` can pre-fill the address in a build.
- The rest is unchanged: `RelayPeer` is a `MultiplayerPeerExtension`, so `NetSession`'s RPCs, the lobby, the version check and the turn clock work as before.
  The relay forwards by room: joiner packets go to the host (tagged with the joiner's id), host packets go to one joiner or all. Rooms vanish when the host leaves.
- Not covered by the automated tests: the Cloudflare tunnel itself (only localhost WebSocket connections are tested).
- Trust/limits: the relay sees (but can't read meaning into) game packets; traffic to a quick tunnel is TLS from the player to Cloudflare. Up to 200 rooms.

## How it works
- The **host's game is the real game**. It runs the same `GameEngine` as single player, so the host alone decides what is legal.
- A joined player's screen is a `RemoteController` (same interface as `GameController`). Clicks become actions that are sent to the host
  (`rpc_action`); the host validates them with the engine and answers with the new events and **that player's own view** (`rpc_state`).
  Opponents' hands and deck order are never sent, so a joined player cannot peek.
- Actions from other players are shape-checked before reaching the engine, and refused with a message if the engine says they are illegal.
- The host's own screen is the normal single-player screen attached to the same controller; the joined seat is a `RemoteAgent`.
- Names and chosen decks are exchanged in the lobby (`rpc_hello`, `rpc_lobby`); `rpc_begin` starts the game; `rpc_error` reports an illegal action.
- Everything lives in `scripts/net/` (`net_session.gd`, `remote_controller.gd`) and `scripts/ui/multiplayer_menu.gd`, plus `agents/remote_agent.gd`.
  The game screen only gained `attach()` (use someone else's controller / seat) - nothing else about single player changed.
- `PROTOCOL` (in `net_session.gd`) must match between host and players; bump it when messages change.

## Limits (v1)
- Trust: the host can see everything (inevitable without a server). A modified client cannot, but a modified host could cheat.
- No reconnecting after a dropped connection (the game ends as a concession).
- Direct connections need a reachable host (see above). If that is too hard for your players, the next step is a free relay or
  WebRTC with a tiny signalling service; the rest of the design does not change because only `NetSession` talks to the network.

## Preparing for 4 players
Already prepared:
- The lobby holds up to `MAX_SEATS = 4`; every message and view is addressed by **seat number**, and the host sends each seat only its own view.
- The UI is seated by `ME`/`OPP` and takes a seat from the host, so another opponent view is a layout addition, not a rewrite.

Still to do when the rules for 3-4 players exist (the engine is two-player today, mostly as `1 - player`):
1. `GameEngine`: N players, turn order that skips eliminated players, a notion of "opponents" (list) instead of `1 - p`, win condition for the last player standing,
   mulligan/first-player roll for N, and `get_view` returning every opponent.
2. Rules that say "target opponent" (Plunder) need a target choice (a new `target_player` param in actions; the AI picks the best one).
3. The table: rows/columns for the extra opponents' boards and piles (the right-hand column can show the other opponents compactly), plus per-seat names/colours.
4. `NetSession`: lift `REQUIRED_PLAYERS`, send views to all remote seats (already a loop), and keep playing when one player leaves (they are eliminated rather than the game ending).
