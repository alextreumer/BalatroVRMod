# Balatro in VR – Godot Client

Balatro runs on your PC as usual (with the **BalatroVRBridge** mod). But you don't look at the monitor: the mod sends the entire game – from the main menu through the shop and blind selection to Game Over – to this client, which draws it on a board in front of you in VR.

## Getting started

1. Open **Godot** and open this project (`client/project.godot`).
2. Press **F5** (Play) and put on your headset.
3. Start **Balatro** (Steam). After a few seconds the mod connects by itself, and the board shows the main menu.

The order doesn't matter: if Godot is restarted, Balatro reconnects automatically.

## VR controls

| What | How |
|---|---|
| Click something (buttons, shop cards, jokers, menus) | Aim with the **right beam**, press the **trigger** |
| See a card's tooltip | Briefly point the beam at the card |
| Select a hand card | Your cards are fanned out in your **left hand** – aim with the beam, trigger |
| Play a hand | Take the selected cards out of your left hand with the **right grip** and release them over the **golden chip** – or press **A** |
| Discard | Grab the selected cards and throw them **over your shoulder** – or press **B** |
| Sort hand cards | **Click the left stick** (L3) – toggles between sorting by **rank** and by **suit** (R3 in left-handed mode) |
| Pick up a joker | **Grip** (either hand) next to a joker on the table: lift it with its pedestal, turn it, look at it. Let go and it stands right there on the joker board (never outside it). The board read **from left to right** is the order of your jokers in the game – the leftmost is slot 1 – and the game is reordered to match. (Jokers and consumables are not shown on the game board in VR – the table is their only place.) |
| Reorder hand cards | Hold the trigger on a hand card and release it on another card |
| Open a booster pack | After buying it (or getting it from a tag) it floats in front of you: **grip it with both hands and pull them apart** to tear it open. Shortcut: point at it and pull the trigger. It opens by itself after 15 s |
| Buy in the shop | In VR the shop is a **sales counter** on the table: jokers and cards stand on it, booster packs on the right, a voucher under a glass dome. **Grab** what you want and **pull it towards you**, let go – bought (a voucher is redeemed, a pack opened). Let go near its place and it goes back; if you can't pay, it says so. Point at or touch an item to read it. The price is on the sign in front (red: too expensive). The animated SHOP sign hangs on its front; at its end on your pointing-hand side stand the **reroll slot machine** (pull the lever) and the red **NEXT ROUND** button above it (point and pull the trigger). The counter can be put anywhere in the room (Adjust VR Layout → "Shop Counter"; it stays upright); machine, button and sign move and scale with it |
| Reroll the shop | Grab the red ball of the **slot machine** at the end of the joker board (grip) and **pull the lever** towards you. The price is shown on the machine; it is dark when you can't pay |
| Sell a joker / consumable | Grab it and let go **above the coin slot** ("SELL") at the other end of the joker board |
| Use a tarot / planet / spectral card | **Point the beam at it in the card stand and pull the trigger** – or grab it with the pointing hand and drop it onto your card hand. A tarot works on the hand cards you selected (select them first); if a card can't be used right now, a hint says so |
| Use a planet card | Grab it and **throw it up into the sky** (or let go above your head) |
| Tooltip of a joker / consumable | **Touch** a 3D joker (anywhere from pedestal to top) or a card in the card stand with either hand – its description appears above it. What a joker has collected so far ("+12 Mult", "X1.5 Mult", "+30 Chips" …) is always written on the front of its pedestal (a model's own floating number is then hidden). Lift a joker and turn it over: a price sticker underneath shows what it sells for |
| View remaining cards ("View Deck") | Hold a hand over the **3D deck** on the table – hand away = window closes |
| Bring everything in front of you | **Y** (left controller) |
| Change background | **X** (left controller): passthrough → green (for Virtual Desktop passthrough) → virtual casino (for headsets without passthrough, e.g. Quest 2) |
| VR settings menu | The **menu button** (≡, left controller) opens a small menu above your card hand, clicked with the beam: Adjust VR Layout, Recenter, **Sitting / Standing** (each has its own layout – e.g. a desk when sitting, a high table when standing; the first time standing starts from the sitting layout), Background, Calm Lights, Hands, Casino Sounds, Spectator On / Off, Camera (the spectator view), Switch Hands, Show Tips. The same switches are also in Balatro's **Options → VR Settings** |
| Adjust layout | Balatro **Options → Adjust VR Layout** or the wrist menu (menu button ≡, left controller). Adjustable: Game Board, Run Panel, Shop (desktop view only), Blind Chip, Joker Board, Deck, Money, Shop Counter (with the reroll machine), Coin Slot, Card Stand (your tarot / planet / spectral cards; its brass plate shows JOKERS 3/5 and CONSUMABLES 1/2, red when full), the **Card Fan** (position, tilt and size relative to the card hand) and **Grabbed Cards** (where they sit in the pointing hand – grab this dot with the card hand's grip) |
| Close the VR client | **QUIT VR** in Balatro's main menu (next to QUIT, only shown while VR is connected) – Balatro keeps running |
| Left-handed mode | Balatro **Options → VR Settings → VR: Switch Hands** |
| Casino sounds | The casino's own sounds (slot machines paying out, glasses, chips) – **Options → VR Settings → VR: Casino Sounds** switches them off. The game's sounds stay |
| Tips | A short guide (controls, the deck, how to move everything): VR menu (≡) → **Show Tips**, or **Options → VR Settings → VR: Show Tips**. Until you have opened them once, a line above the game board points to them |
| Jimbo's gloves | Your hands are cartoon gloves that copy what your fingers do on the controller: grip = fist, finger off the trigger = pointing, thumb off the buttons = thumbs up. Balatro **Options → VR Settings → VR: Hands** switches them off (then only the beam) |
| Spectator camera (recording / streaming) | Balatro **Options → VR Settings → VR: Spectator** switches through Off → Eyes → Tripod → Shoulder → Overhead → Room. It opens its own window on the PC ("Balatro in VR – Spectator", e.g. for OBS) with a calm camera: **Eyes** = your view, steadied and level; **Tripod** = like your view, but fixed on a tripod at your place; **Shoulder** = from behind and above you; **Overhead** = straight down onto the table, like a poker broadcast; **Room** = a slow wide shot of the table. In that window: keys **1 – 5** switch the view, **F11** full screen. In Shoulder, Overhead and Room you wear Jimbo's jester hat (only the spectator sees it). In VR the wrist menu has **Spectator On / Off** and **Camera** (next view, the window stays open); while it runs a blinking "● LIVE · Tripod" badge sits on your card hand's wrist and a little film camera with a red light shows where it films from (both only in the headset, not in the recording) |
| Calm Lights (for photosensitive players) | Balatro **Options → VR Settings → VR: Calm Lights** – no flashes, flicker, pulsing neon, light beams or shock waves; the casino stays dim. Kept after a restart |

**Left-handed mode:** The cards are in your **right** hand; the **left** hand does the beam, clicks and gestures (play = **X**, discard = **Y**; bring everything in front of you = **B**, background = **A** on the right controller). Run Panel and deck are mirrored to the left. Each mode saves its own calibration, and your choice is kept after a restart.

**In the room:** Game Board in front of you · Run Panel (score, hands, money …) on the side of the pointing hand, because the other hand holds the cards – outside of a round only in compact form (money, ante, round, Run Info, Options) · shop lying flat on the table · jokers on wooden pedestals and the deck (colour = deck type, height = cards left) on the table · your money as stacks of gold coins (one coin per dollar, up to 100; in debt an IOU note with the amount owed) · floating Blind Chip during a round (front: current blind, back: stake). Tooltips of hand cards appear right above the card.

**Scoring on the table:** played cards fly from your hand onto a slanted wooden stand on the table in front of you (raised, so the jokers don't hide them); each one pops and its "+30", "+4 Mult", "X2" floats up as it scores (jokers on the board jump with theirs), with a tick in the controller. When you beat a blind, the blind chip **shatters**; glass cards that break burst into shards; coins **fly** into your coin pile when you earn money (from the chip, the cash-out or the coin slot) and out of it when you spend. Every poker hand you levelled up **orbits the room as its planet** (Earth with oceans and clouds, Jupiter with bands and red spot, Saturn with its ring …; clearly bigger with each level). The orbit is fixed in the room (centred over your place), not on your head, so the planets glide around you slowly and stay steady when you move. Sound effects come from where they happen (cards at your hand, coins at the pile, scoring at the table) – while VR is connected the game's own effects are muted on the PC, the music keeps playing there. In the virtual casino **Jimbo** stands on the table and reacts (cheers at big hands, jumps at packs, slumps at Game Over), and the **neon follows the game**: a new colour every ante, a red alarm pulse at boss blinds, flaring when the score burns.

**Game feel:** at the start of each round the 3D deck shuffles itself (split, riffle, tap); new hand cards fly one by one from the 3D deck into your hand (a tick in the hand as each lands); discarded and scored cards fly to a discard pile beside the deck. What you buy flies from the shop to its place – a joker to the board, where it pops up as its model; tarot / planet cards into the card stand; playing cards onto the deck. When a joker fires, a short beam links it to the card that set it off (Blueprint and Brainstorm also flash the joker they copy). Vibrations follow the score (bigger numbers, harder ticks), a debuffed card twitches in your card hand, and going past the blind rumbles. **The last hand** of a round you haven't won yet: the neon sinks to a glimmer and a heartbeat throbs in both controllers – until the score breaks through. A **boss blind** presents itself: its chip flies up in front of you, big, in red light, with its rule. A beaten blind's chip trembles, then bursts with a flash and a shock wave – a boss harder, with a "DEFEATED!".

**Sound of the casino:** all game sounds and the room's own sounds get the reverb of a big hall; slot machines along the walls pay out now and then (bell and coins), glasses clink at the bar, chips click at the tables. It all goes quiet in the last hand. (Only in the virtual casino.) **The end of a run:** won – casino chips rain from the ceiling and every slot machine hits the jackpot; lost – the lights go out and a single spotlight falls on Jimbo.

**Boss blinds change the room:** the neon takes the colour of the boss chip (pulsing slowly), and some bosses do more – **The Wall**: a brick wall rises from the floor all around you and the table; **The Water**: wave light on the ceiling; **The Needle**: everything dark but the table; **The Flint**: all lights at half strength; **The Eye**: a huge eye in the big screen follows you; **The Mouth**: a chewing mouth there; **The Fish**: bubbles rise through the room; **The Wheel**: every machine runs wild; **The Manacle**: chains hang from the walls; **The Serpent**: a glowing serpent winds over the ceiling; **The Ox**: your coin pile trembles. Final bosses come up bigger. With Calm Lights the room keeps its normal colours, without wave light, bubbles or racing machines.

**The casino:** behind you the **Bar-latro** (cocktails · jokers · chips · bananas), the restroom door **The Flush** and the open doorway to **The Ante Room** – a waiting room whose "NOW SERVING" display calls your ante; above it a clock that tells the ante instead of the time ("Ante 8 o'clock"; the minute hand shows the blind: small :00, big :20, boss :40). To the right the round arch of the **Spectral Lounge** (its sign flickers like a ghost when you buy or use a Spectral card), to the left the knee-high door of the **Wee Joker Kids Corner**. Ahead, next to the big screen, the **Hall of Fame** and **Hall of Shame** show your Balatro profile's statistics. On the left end of the card table grows the **chip mountain**: every chip you scored in this run, added up – a little stack at a few hundred points, a heap at a hundred thousand, up to the ceiling at about ten million (the chip colour changes with every power of ten: white hundreds, red thousands, blue, green, black millions). Beyond that a second mountain wakes up on the right end of the table and grows on up to a trillion (purple, gold, orange, cyan, pink, silver). And the "OPEN 24/7" sign has a loose contact …

**Effects:** stars all over the room when you buy or use a Planet card (and constantly while Supernova, Satellite or Constellation is in a joker slot) · burning hand cards when the score is on fire · confetti when you win a run (colourful) or lose (black, grey and dark red) · a swirl of real Balatro cards while Balatro is starting (fronts from the game, backs of all decks mixed – remembered on your PC from the previous session; before the very first connection simple cards stand in).

## Desktop controls (testing without a headset)

Left click = click, hold the right mouse button on a card = tooltip, **P** = play, **D** = discard, **S** = toggle sorting (rank ↔ suit), **B** = background, **C** = calibration on/off, **H** = switch hands, **K** / **Shift+K** = test confetti (run won / Game Over).

## Troubleshooting

- **"Waiting for Balatro …" doesn't go away:** Is Balatro running with the mod? *Balatro in VR* must be enabled under *Mods* in the game. Mod errors are in the newest file in `%APPDATA%\Balatro\Mods\lovely\log\` (lines with `[BalatroVR]`).
- **Black screen in the headset:** The renderer must be *Compatibility* (already set in the project).
- **Port in use:** Is the client running twice? Close one Godot window.

## Files

| File | Contents |
|---|---|
| `scripts/main.gd` | Connection (TCP), VR rig, pointer/clicks/tooltips, card fan, gestures, calibration |
| `scripts/board.gd` | Draws the mirrored game UI (panels, texts, cards) |
| `scripts/card_art.gd`, `scripts/game_font.gd` | Card textures and the game font, sent by the mod from your own Balatro install |
| `scripts/casino_room.gd`, `scripts/casino_machines.gd` | The virtual casino (built entirely from code): card table, bar, side rooms, neon signs; the gaming machines along the walls (themed slots, pachinko, claw machine, video poker, wheel of fortune, coin pusher) |
| `scripts/star_field.gd`, `scripts/confetti.gd`, `scripts/intro_cards.gd` | Effects: stars, confetti, startup cards |
| `scripts/pack_tear.gd`, `scripts/reroll_lever.gd`, `scripts/shatter_fx.gd`, `scripts/hand_planets.gd` | Booster pack to tear open, reroll slot machine, shards (chip, glass), hand-level planets |
| `scripts/jimbo_hand.gd`, `scripts/spectator.gd`, `scripts/casino_ambience.gd`, `scripts/vr_tutorial.gd`, `scripts/wrist_menu.gd`, `scripts/boss_room.gd` | Jimbo's gloves on your hands (posed by the controller inputs); the spectator camera window; the casino's sounds; Jimbo's tips; the VR settings menu above the card hand; what each boss blind does to the room |
| `scripts/sound_bank.gd`, `scripts/jimbo_companion.gd`, `scripts/coin_pile.gd`, `scripts/chip_mountain.gd` | Spatial game sounds, Jimbo at the casino table, the coin pile with flying coins, the chip mountain of the run's score |
| `jokers/` | 3D models for the jokers (see `jokers/README.md`) |
| `scenes/main.tscn` | Start scene |
| `../Docs/PROTOCOL.md` | Data format between mod and client |
