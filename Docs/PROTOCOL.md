# Balatro in VR – Protocol v2

The VR client is the **TCP server** on `127.0.0.1:27801`. The Balatro mod connects as a client and reconnects automatically (every ~1–3 s) when the client restarts. Every message is **one JSON object per line** (`\n`-terminated), in both directions.

## Game → VR

Envelope: `{"type": "...", "seq": n, "v": 2, "data": {...}}`

### `scene` – complete UI mirror (max. 15/s, only on change, otherwise 1/s as a heartbeat)

```json
{
  "room": {"w": 20, "h": 11.5},
  "state_name": "SHOP",
  "overlay": false,
  "overlay_from": 412,
  "groups": [{"id": 7, "role": "HUD", "x": 0, "y": 0, "w": 4.6, "h": 11.5}],
  "areas":  [{"id": 3, "name": "hand", "type": "hand", "n": 8, "lim": 8, "x": 4, "y": 8, "w": 10, "h": 2}],
  "items":  [ ... in draw order ... ]
}
```

Coordinates are Balatro room units (origin top left, y pointing down, room 20 × 11.5). `x/y/w/h` is the rectangle the game draws (`VT`).

| `k` | Meaning | Fields |
|---|---|---|
| `r` | Rectangle/panel | `c` colour RGBA (missing = invisible click area), `rr` rounded, `oc` outline colour, `pb` progress 0–1, `b` clickable |
| `t` | Text | `s` text, `c` colour, `vert` vertical, `off` button disabled, `b` clickable, `dyn` + `fx` animated DynaText (bump, float, rotate, quiver) |
| `c` | Card | `f` front/back, `set`, `key`, `name`, `rank`/`suit` (playing cards), `area`, `hl` highlighted, `db` debuffed, `ed` edition, `seal`, `cost`, `sell`, `ca`/`cp` atlas + position of the face (jokers/tarots/…), `fa`/`fp` atlas + position of the playing-card front, `ba`/`bp` back |
| `s` | Sprite (blind chip, tag, title logo, …) | `a` atlas name, `p` [x, y] in the atlas |
| `fl` | Score flames | `i` intensity, `c`/`c2` colours |

Every item has an `id` (stable as long as the object exists in the game) and `g` (group = top-level UIBox/card area). Group roles: `HUD`, `HUD_blind`, `shop`, `blind_select`, `round_eval`, `booster_pack`, `OVERLAY_MENU`, `MAIN_MENU_UI`, `SHOP_SIGN`, `logo`, `popup` (with `owner` = card id), `area:<name>`.

Order: card areas → UI panels → overlay menu (from `overlay_from`) → tooltips.
Deck and discard pile are only sent as counts (`areas[].n`). Not mirrored, because VR has its own controls for them: the Play/Sort/Discard button row and the deck's "View Deck" button and card counter.

### `state` – game state for gestures and 3D objects (max. 10/s)
Deck (incl. composition), round (ante, hands, discards, score, money), blind, stake, `won` (run won), jokers with their counters and `value` (the "(Currently …)" value of their tooltip, e.g. "+12 Mult") (see `build_state` in the mod).

### `event`
- `{"event": "shop_buy" | "card_used", "set": "...", "key": "...", "name": "...", "from_pack": bool}`
- `{"event": "calibrate"}` – "Adjust VR Layout" in the Options menu
- `{"event": "toggle_handedness"}` – "VR: Switch Hands" in the Options menu
- `{"event": "toggle_calm" | "toggle_hands" | "toggle_ambience" | "cycle_spectator" | "show_tutorial"}` – the switches in "VR Settings" (Options); the client answers with `vr_flags`
- `{"event": "quit_vr"}` – "QUIT VR" in the main menu: the client closes, Balatro keeps running
- `{"event": "pack_ready", "uid", "name", "atlas", "pos"}` – a booster pack waits to be torn open in VR (the mod holds `Card:open()`; after 15 s or without VR it opens by itself)
- `{"event": "score", "uid", "text", "kind", "c"}` – a scoring popup ("+30", "X2", "$3" …) at the moment the game shows it
- `{"event": "shatter", "uid", "ca", "cp", "fa", "fp"}` – a glass card breaks
- `{"event": "sound", "code", "per", "vol"}` – a sound effect; while VR is connected the game itself stays silent for effects. The file comes once per connection as `{"type": "sound_data", "data": {"code", "data" (base64 ogg)}}`

State also carries `hand_levels` (poker hands above level 1), `consumables` (uid, set, can_use, can_sell), `shop_open`, `reroll_cost`, `can_reroll`, `pack_waiting`, `round.run_chips` (all chips scored in this run), `blind_on_deck` (Small / Big / Boss) and `stats` (profile statistics for the casino's Hall of Fame / Shame: best hand, highest ante, wins, losses, rerolls, favourite hand and joker …).

### `atlas` / `font`
Textures (base64 PNG) and the game font, read by the mod from the local Balatro install; sent once per connection.

### `intro`
`{"fronts": [{"atlas", "pos"}...], "base": {"atlas", "pos"}, "backs": [{"atlas", "pos"}...]}` – every playing-card front, the plain card base and the back of every deck. Sent once per connection (before the atlases it needs). The client keeps these cells' atlases in its app data (`user://intro_cache`) for the card swirl shown while Balatro boots, when the mod is not running yet.

### `ack`
`{"cmd": "...", "id": n, "ok": bool}` – reply to every command.

## VR → Game

Flat JSON objects; `id` is returned in the `ack`:

| Command | Fields | Effect |
|---|---|---|
| `click` | `target` (item id) | Button: `UIElement:click()`; card: `Card:click()` (select; in the shop/pack the Buy/Use buttons then appear) |
| `hover` / `unhover` | `target` | Show/hide a card's tooltip (arrives as `popup` in the next `scene`) |
| `play` / `discard` | – | Clicks the real Play/Discard button |
| `sort` | `by`: `"rank"`, `"suit"` or `"toggle"` | Sorts the hand like the Rank/Suit buttons; `toggle` = the other order than the current one |
| `move` | `target`, `to` (card ids) | Moves a card to the position of another card in the same row (hand or jokers) |
| `order` | `ids`: `"uid;uid;..."` | Puts all jokers in this order (the VR joker board read from left to right) |
| `open_pack` | – | Opens the booster pack that waits for VR (torn open) |
| `reroll` | – | Rerolls the shop (VR lever), if affordable |
| `sell` | `target` | Sells a joker or consumable (VR coin slot) |
| `buy` | `target` | Buys an item of the shop (VR sales counter): joker / card like the Buy button, voucher redeemed, pack opened; refused if it can't be paid or there is no room |
| `next_round` | – | Leaves the shop (VR NEXT ROUND button): clicks the shop's own Next Round button |
| `use` | `target` | Uses a tarot / planet / spectral card (VR gesture), if usable now |
| `deck_view` | `on` | Opens/closes "View Deck" (only closes the overlay it opened itself) |
| `highlight` | `index` (1-based), `on` | Select a hand card |
| `button` | `button`, `action` (tap/press/release) | Emulate a gamepad button |
| `vr_flags` | `calm`, `hands`, `spec`, `amb` | The VR client's settings, so the "VR Settings" buttons show their state |
| `ping` | – | Test |

Gated commands (`click`, `play`, `discard`, `sort`, `move`, `deck_view`, `highlight`) wait while the game blocks input (animations, `G.CONTROLLER.locked`), just like the real controller, and expire after 3 s with `ok: false`. At most one such command is executed per frame.
