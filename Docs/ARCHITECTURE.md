# Balatro in VR – Architecture

## 1. Overview

```
┌──────────────────────── Balatro.exe (LÖVE 11 / LuaJIT) ────────────────────────┐
│  Lovely + Steamodded                                                            │
│  BalatroVRBridge.lua                                                            │
│   ├─ Game:update hook                                                           │
│   │    ├─ build_scene()  – walks every UIBox, card area, card, popup ──► "scene" │
│   │    ├─ build_state()  – deck, round, blind, stake, jokers, won   ──► "state" │
│   │    └─ atlases + font from the local install (once per connection)          │
│   ├─ hooks buy_from_shop / use_card ──► "event" (Planet stars …)                │
│   ├─ Options menu: "Adjust VR Layout", "VR: Switch Hands" ──► "event"           │
│   ├─ main menu: YouTube button instead of Discord / X                          │
│   └─ executes commands (click, hover, play, discard, sort, move, deck_view …)  │
└───────────────────────────────┬─────────────────────────────────────────────────┘
                                │ TCP 127.0.0.1:27801, one JSON object per line
┌───────────────────────────────▼──────── Godot 4.7 (Compatibility, OpenXR) ──────┐
│  main.gd     TCP server, VR rig, beam pointer, hover/click/drag, card fan,     │
│              grab gestures (play at the chip, discard over the shoulder),      │
│              3D deck, blind chip, joker board, calibration, left-handed mode   │
│  board.gd    draws the mirrored UI on anchored containers (board, Run Panel,   │
│              shop on the table, tooltips at the cards), text animations, flames│
│  card_art.gd / game_font.gd   card textures, debuff shader, the game's font    │
│  star_field.gd / confetti.gd / intro_cards.gd   effects                        │
│  jokers/j_*.tscn + augmented_joker.gd   3D jokers driven by formulas           │
└────────────────────────────────────────────────────────────────────────────────┘
```

## 2. Design decisions

| Topic | Decision | Reason |
|---|---|---|
| Engine | **Godot 4** with the **Compatibility** renderer | Free and easy to share; Forward+/Mobile gave a black headset image over Virtual Desktop (tonemapper shaders). |
| Transport | **TCP on localhost**, Godot is the server | LÖVE ships LuaSocket; the mod connects non-blocking and reconnects by itself, so start order doesn't matter. |
| What is mirrored | **The game's own UI tree**, not a screen capture | Sharp text at any distance, every element clickable, panels can be placed anywhere in the room. Works for every menu without special code. |
| State model | **Full snapshots** only on change (scene ≤ 15/s, state ≤ 10/s) + 1/s heartbeat | Idempotent; the client only processes the newest snapshot. Keys are encoded sorted, so a string compare detects changes. |
| Input into the game | Clicks on the **real UI elements** / `G.FUNCS` | The game checks everything itself (can_play, can_discard, locks); the result comes back as `ack`. |
| Assets | Textures and font are **read from the player's own install** and sent at runtime | No game assets are redistributed with this project. |
| Calibration | `user://vr_layout.cfg`, one section per hand mode | Keeps the personal layout across restarts; keys are the (German) internal item names – don't rename them. |

## 3. Protocol

See [PROTOCOL.md](PROTOCOL.md).

## 4. Gestures

- **Play:** grip near the selected cards in the card fan → they move to the pointing hand → release them at the blind chip (or press A).
- **Discard:** release the grabbed cards behind your shoulder (or press B).
- **Reorder:** hold the trigger on a hand card or joker, release it on another card of the same row (`move`).
- **View Deck:** hold a hand over the 3D deck (`deck_view`).
- **Sort:** click the stick of the card hand (`sort` with `toggle`).

## 5. Setup

1. Install Lovely + Steamodded, copy `BalatroMod/BalatroVRBridge` to `%APPDATA%\Balatro\Mods\`.
2. Open `client/project.godot` in Godot 4.7, press F5, start Balatro. Details in [client/README.md](../client/README.md).
