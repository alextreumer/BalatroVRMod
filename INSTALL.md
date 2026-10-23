# Balatro in VR – Installation Guide

You need: **Balatro** (Steam, Windows) and a **VR headset** (e.g. Meta Quest with Virtual Desktop or Quest Link, or SteamVR).

The guide has three parts: first the mod basics, then the mod, then the VR program. The order matters.

---

## Step 1: Install Lovely (once)

Lovely is the tool that lets Balatro load mods.

1. Download the file **`lovely-x86_64-pc-windows-msvc.zip`**: https://github.com/ethangreen-dev/lovely-injector/releases
2. Unpack it. Inside is a file called **`winmm.dll`**.
3. Copy this `winmm.dll` into the Balatro game folder.

To find the game folder: Steam → right-click Balatro → **Manage** → **Browse local files**.
It is usually: `C:\Program Files (x86)\Steam\steamapps\common\Balatro\`

---

## Step 2: Install Steamodded (once)

Steamodded is the mod library that Balatro in VR is built on.

1. Download the zip: https://github.com/Steamodded/smods/releases/tag/26.1002.0 → **Source code (zip)**. The file is called **`smods-26.1002.0.zip`**.
2. Unpack it into Balatro's mods folder. Type `%AppData%\Balatro` into the Explorer address bar and create a folder called **`Mods`** there if it does not exist yet.
   In the end it looks like this: `%AppData%\Balatro\Mods\smods-26.1002.0\`

**Check:** Start Balatro once. The main menu now shows a **Mods** button. If it is there, everything works. You can close Balatro again.

---

## Step 3: Install the mod "Balatro in VR"

1. Copy the folder **`Mod\BalatroVRBridge`** from this package into `%AppData%\Balatro\Mods\`.
2. In the end the file must be here: `%AppData%\Balatro\Mods\BalatroVRBridge\BalatroVRBridge.lua`

---

## Step 4: Start the VR program

1. Copy the folder **`Balatro in VR`** to a place of your choice, e.g. `C:\Games\Balatro in VR\`.
   `Balatro in VR.exe` and `Balatro in VR.pck` must stay together.
2. Start your VR software (Virtual Desktop, Quest Link or SteamVR) and put on the headset.
3. Start **`Balatro in VR.exe`**.
4. Start **Balatro** through Steam. After a few seconds the game appears around you.

The order does not matter: both programs find each other by themselves. You can restart either one at any time.

---

## Updating to a new version

Close Balatro and the VR program, then replace both parts with the ones from the new package:

1. `Mod\BalatroVRBridge\BalatroVRBridge.lua` → over the old one in `%AppData%\Balatro\Mods\BalatroVRBridge\`
2. the folder **`Balatro in VR`** → over your old one (exe and pck together)

Your layout, settings and achievements are kept: they are saved separately in `%AppData%\Godot\app_userdata\Balatro in VR\`.

---

## Your first steps in VR

- A small hint above the game table points to **How To Play**. Press the **X button** on the left controller (left-handed: **A** on the right one) or the **≡ button** and choose **How To Play**.
- This button also opens the VR menu: adjust the layout, sitting/standing, background, sound, floor height, your **Achievements** and more.
- In VR the casino table is the main menu: slap the red **PLAY** buzzer to start, or try **SOLATRO**, the solo card game.
- Use **Adjust VR Layout** to move everything to where you want it.

---

## If something does not work

| Problem | Solution |
|---|---|
| The VR program says "Waiting for Balatro …" | Is **Balatro in VR** switched on under **Mods** in Balatro? Is the file in the right place (Step 3)? |
| The VR program opens on your monitor instead of the headset | Your VR software was not running yet. Start it first, then the program. |
| Windows Firewall asks for permission | The programs only talk to each other on this PC (port 27801). You can deny network access. |
| Everything is in strange places | In the VR menu (≡) open **Adjust VR Layout**, then press **Y** (left-handed: **B**). Everything returns to the default positions. |
| Mod error messages | In the newest file in `%AppData%\Balatro\Mods\lovely\log\`, look for the lines with `[BalatroVR]`. |

The program saves your settings and positions in `%AppData%\Godot\app_userdata\Balatro in VR\`.
