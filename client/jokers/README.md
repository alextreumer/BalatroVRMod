# Augmented Jokers – replacing models

Every joker with a 3D model is its own Godot scene in this folder, named after the joker's key in the game, e.g. `j_castle.tscn` (Castle) or `j_selzer.tscn` (Seltzer, spelled without the "t" in the game). If a joker has no scene, it simply gets no 3D model.

The models are built from code (no external assets) and can be replaced one by one with your own models – **no code needed** (see below).

## The jokers included

Every value comes live from the game. A debuffed joker (e.g. by a boss blind) gets a red **X** above it. Parts that count (popcorn flakes, banner stripes, loyalty stamps) pop away and back in.

### Values that shrink or grow

| Joker | What you see | What it means |
|---|---|---|
| **Popcorn** | Striped cup heaped with popcorn; flakes pop away and the level sinks | Mult (starts at 20, −4 per round) |
| **Ice Cream** | A sprinkled scoop with a cherry on a waffle cone shrinks | Chips (starts at 100, −5 per hand played) |
| **Seltzer** | Soda siphon: the water level sinks, the fizz at the spout stops for the last hand | Hands left (10 → 0) |
| **Turtle Bean** | A little turtle shrinks | Extra hand size (+5, −1 per round) |
| **Ramen** | Bowl with noodles, egg, fish cake and nori; the broth sinks | xMult (starts at x2, drops per discarded card) |
| **Green Joker** | Jimbo in green next to a glowing meter + "+X Mult" sign | Mult (+1 per hand played, −1 per discard) |
| **Square Joker** | A square-headed jester grows + "+X Chips" sign | Chips (+4 per hand of exactly 4 cards) |
| **Obelisk** | Stone obelisk with glowing glyphs grows + "x1.4" sign | xMult (grows while you avoid your most played hand) |
| **Campfire** | Logs in a ring of stones; the fire grows and glows | xMult (+0.25 per card sold, resets at the boss) |

### Counters

| Joker | What you see | What it means |
|---|---|---|
| **Banner** | Red banner with one gold stripe per discard left, a white flag at 0 | Discards left (+30 chips each) |
| **Loyalty Card** | Stamp card on a stand; stamps fill up, the full card glows | Progress to the next x4 (every 6 hands) |

### Targets the game picks every round

| Joker | What you see | What it means |
|---|---|---|
| **Ancient Joker** | Stone tablet with a glowing suit symbol ♥ ♦ ♣ ♠ in a gold setting | Which suit gives x1.5 |
| **Castle** | Castle with towers; suit symbol ♥ ♦ ♣ ♠ on the flag | Which suit gives chips when discarded |
| **Mail-In Rebate** | Red mailbox with a letter + "Discard: King" sign | Which rank gives $5 when discarded |
| **The Idol** | Golden idol, the suit symbol on its plaque + "King of Spades" sign | Which exact card gives x2 |
| **To Do List** | Clipboard with ticked boxes and a pencil; the poker hand, e.g. "Full House", is written in the open line | Which hand gives $4 |

### Values as floating text

| Joker | What you see | What it means |
|---|---|---|
| **Runner** | Running Jimbo + "+X Chips" | Chips collected (+15 per straight played) |
| **Wee Joker** | Tiny Jimbo with a "2" card + "+X Chips" | Chips collected (+8 per scored 2) |
| **Ride the Bus** | School bus + "+X Mult" | Mult (+1 per hand without a face card, resets on a face card) |
| **Lucky Cat** | Beckoning cat with a gold coin, glows brighter the higher it gets + "x1.75" | xMult (+0.25 per lucky card triggered) |
| **Hologram** | Jimbo as a spinning hologram over a projector, glows brighter + "x1.50" | xMult (+0.25 per card added to the deck) |

### States and effects

| Joker | What you see | What it means |
|---|---|---|
| **Invisible Joker** | A grey Jimbo goes from almost see-through to solid | Rounds until it can be sold to copy a joker (2) |
| **Gros Michel** | A spotty banana trembles | It may spoil at the end of a round (1 in 6) |
| **Cavendish** | A blazing bunch of bananas: halo, turning sun rays and a real light that bathes the neighbouring jokers in yellow | Gros Michel's rare successor (x3 Mult) |

### The second set (tools/build_jokers2.gd)

| Joker | What you see | What changes |
|---|---|---|
| **Ceremonial Dagger** | Fantasy dagger in a velvet cushion: skull pommel, wrapped grip, skull guard with fangs and spiked quillons, notched blade with a long slot | The slot's rim and the fuller glow redder with its Mult |
| **Constellation** | Star map in a gold ring | One more star lights up per Planet used |
| **Madness** | Laughing harlequin mask on a stick | More cracks, the eyes burn brighter |
| **Erosion** | Sandstone pillar on a plinth | Crumbles as the deck shrinks |
| **Fortune Teller** | Crystal ball, velvet cushion, tarot cards | The mist inside glows brighter per Tarot used |
| **Glass Joker** | Jimbo made of glass | Another shining crack per Glass card destroyed |
| **Rocket** | Retro rocket on a launch pad | The exhaust flame grows with the payout |
| **Egg** | Egg in a twig nest | Grows and turns golden with its sell value |
| **8 Ball** | Black billiard ball on a brass ring | Turns slowly |
| **Credit Card** | Embossed card (JIMBO) in a stand | – |
| **Blueprint** | Half unrolled blueprint with the crest of *Blue Prince* printed on it, pencil | – |
| **DNA** | Double helix on a lab stand | Turns |
| **Space Joker** | Ringed planet, Jimbo in a space helmet | A moon circles it |
| **Mr. Bones** | Skeleton sitting on a crate, waving | – |
| **Supernova** | Blazing star with spikes of light | The spikes turn |
| **Cloud 9** | Cloud with a golden 9, coins raining | – |
| **Canio** | Sad clown with wilted flowers | His tears glow brighter with his xMult |
| **Triboulet** | Royal jester with crown and sceptre | – |
| **Yorick** | Skull on old books, a candle | The eyes glow brighter with his xMult |
| **Chicot** | Jester with a shield, a Boss Blind chip bouncing off | – |
| **Perkeo** | Jester with a wine barrel | Negative-shimmering bottles circle him |

| **Vampire** | Open coffin with candles, Jimbo as a vampire inside | His eyes burn redder with his xMult |
| **Swashbuckler** | Treasure chest with a pirate hat and a cutlass | The heap of gold grows with its Mult |
| **Blue Joker** | A house of blue and white cards | Shrinks as your deck gets smaller |
| **Steel Joker** | A pyramid of steel ingots | One ingot per Steel card in your deck |
| **Brainstorm** | A brain under a glass dome | Lightning bolts circle it |
| **Seance** | Crystal ball with a ghostly hand inside, candles | The hand turns slowly |
| **Golden Ticket** | A golden "ADMIT ONE" ticket on a stand | Turns slowly |
| **Smeared Joker** | A painter's palette, red running into orange and blue into green, a brush | – |

Jokers without a scene stand on the table as their card on a little stand.

The models are made by `tools/build_jokers.gd` (all except Popcorn and Runner) and `tools/build_popcorn.gd`. Running them again overwrites the scenes they build – so after editing a scene by hand, don't run them again (or only for other jokers: `... --script res://tools/build_jokers.gd -- castle obelisk`).

## Replacing a model (example: Ice Cream)

1. **Get a model** in **`.glb`** or **`.gltf`** format (e.g. from Sketchfab, Poly Pizza, Kenney, or exported from Blender).
   - If your model is an `.fbx` (e.g. from the Unity Asset Store): open it in Blender (*File → Import → FBX*) and export it as glTF (*File → Export → glTF 2.0*, format "glTF Binary (.glb)").
   - Check the licence: for a project you share with others, the model must be allowed to be redistributed.
2. Copy the file into this folder `client/jokers/`. Godot imports it automatically as soon as the editor window is active again.
3. In the Godot editor, double-click `j_ice_cream.tscn` in the **FileSystem** dock (bottom left). The scene opens.
4. In the **Scene tree** (top left) you see the parts, e.g. `Cone` and `Fill → Scoop`.
5. **Drag your model from the FileSystem onto the matching node**:
   - The whole model as one piece? → drag it onto the top node `j_ice_cream`.
   - Only the scoop that should melt? → drag it onto `Fill` (then it shrinks with it).
6. Adjust size/position: click the model and change `Position`, `Rotation` and `Scale` under *Transform* in the **Inspector** on the right. Scale: **1 = 1 metre**; the jokers are about 5–15 cm tall.
7. Click the old placeholder parts you no longer need and delete them with **Del**.
   **Important:** **Don't delete or rename** nodes that are referenced in the top node's Inspector (e.g. `Fill`) – otherwise the joker no longer knows what to move. Only delete the shape *below* it (`Scoop`) and attach your model to `Fill`.
8. **Ctrl+S** to save. On the next start (F5) your model stands on the table.

## What the jokers can do (Inspector of the top node)

Click the top node (e.g. `j_banner`). The Inspector on the right shows these groups:

| Group | Effect | Example |
|---|---|---|
| **Fill** | Node is stretched by a value (0…1) | Seltzer water sinks, ice cream melts, the popcorn bed sinks |
| **Count** | Shows the first N children of a node | Banner stripes, Loyalty stamps |
| **Empty state** | A part appears/disappears at 0 | white flag, Seltzer cork |
| **Suit colour** | Colours a part in the suit's colour; *Suit Shapes* = a node with children named `Hearts`, `Diamonds`, `Clubs`, `Spades` – only the current suit is shown (ready-made symbols: `suit_shape.gd`) | Castle flag, Ancient Joker symbol |
| **Text** | Floating text | "Discard: King", "+12 Mult", "x1.75" |
| **Glow** | Glow | Cavendish, Loyalty Card when full |
| **See-through** | Transparency | Invisible Joker becomes visible |
| **Motion** | Shake / spin | Gros Michel shakes, Hologram spins |

The values are small formulas over the live data from the game:

| Formula | Meaning |
|---|---|
| `ab["mult"]`, `ab["x_mult"]` | the joker's current Mult / xMult |
| `ab["invis_rounds"]`, `ab["loyalty_remaining"]`, `ab["to_do"]` | Invisible Joker, Loyalty Card, To Do List |
| `extra["chips"]`, `extra["h_size"]`, `extra["every"]` … | the joker's extra values (`extra["value"]` if the game only stores a single number) |
| `target["suit"]`, `target["rank"]` | wanted suit/card (Castle, Mail-In Rebate, Ancient Joker, The Idol) |
| `run["discards_left"]`, `run["hands_left"]`, `run["dollars"]`, `run["ante"]` | current round |

Arithmetic is allowed, e.g. `ab["x_mult"] - 1.0` or `extra["every"] - ab["loyalty_remaining"]`.

## Adding another joker

1. Duplicate an existing scene (right-click → *Duplicate*) and name it after the joker's key, e.g. `j_supernova.tscn`. The keys can be found in Balatro's code (`j_…`).
2. Replace the model as described above and adjust the formulas in the Inspector.

## Rebuilding the models

Rebuild the models from code (this **overwrites** those scenes; add joker keys after `--` to rebuild only these):

```
Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tools/build_jokers.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path client --script res://tools/build_popcorn.gd
```

The older tool `tools/generate_jokers.gd` only creates simple placeholder scenes for jokers that have none yet (existing scenes are **not** overwritten).

## Where the jokers stand

The jokers stand on round wooden pedestals on the **Joker Board**, a flat plate you place on your real table. It is only visible while calibrating – while playing, jokers and deck stand directly on your table. The board is about 93 × 45 cm: the deck lies at the front right of the middle part (front left in left-handed mode); at the end on your pointing-hand side stands the reroll slot machine, at the other end the coin slot and a wooden card stand with your tarot / planet cards (its plate shows how many joker and consumable slots are used). Every joker can be picked up (grip) and put down anywhere in the middle part of the board; the board read **from left to right** is the order of the jokers in the game (leftmost = slot 1). A new joker is placed to the right of the others, or on the first free one of the 8 anchor points (two rows of 4) when there is no room. Each joker gets a fixed random rotation. The pedestal is added automatically – your models don't need one.

Via **Options → Adjust VR Layout**:
- Grab the **Joker Board**: move, turn (only around the vertical axis – it always stays level) and scale (with the stick) the whole plate with everything on it – e.g. to fit it onto your real table.
- Grab the **Deck**, the **Money** coins, the **Reroll Machine**, the **Coin Slot** and the **Card Stand** (your tarot / planet / spectral cards stand in it): they only slide on the board, only rotate around the vertical axis, and stay within its area.
