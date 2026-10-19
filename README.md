# Balatro in VR

Play [Balatro](https://www.playbalatro.com/) in virtual reality. Balatro keeps running on your PC as usual; a small mod (**BalatroVRBridge**) sends the whole game to a VR client built with Godot, which shows it around you in a virtual casino – with your cards in your hand, 3D jokers on the table, booster packs to tear open and much more.

> **Beta:** this is a pre-release for beta testers. Download it from the [Releases](https://github.com/alextreumer/BalatroVRMod/releases) page (marked *Pre-release*) and follow `INSTALL.md` inside the zip.

- `client/` – the Godot 4.7 VR client (see `client/README.md` for all controls and features)
- `BalatroMod/` – the Balatro mod (Lovely + Steamodded)
- `Docs/` – the protocol between mod and client, architecture notes

Godot project and Steamodded Lua file – **no game files from Balatro itself.** Fan project, not affiliated with LocalThunk or Playstack. You need your own copy of Balatro: the client takes all card art, sounds and the font from your installed game at runtime – nothing of the game is included here.

## Build it yourself

1. Install [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) and its export templates (Editor → Manage Export Templates).
2. Open `client/project.godot` in Godot.
3. Run it from the editor, or export it: Project → Export → *Windows Desktop*. The preset writes `Release/Balatro in VR/Balatro in VR.exe` and its `.pck` (both must stay together).
4. Install the mod: Lovely and Steamodded as described in `INSTALL.md`, then copy `BalatroMod/BalatroVRBridge` into `%AppData%\Balatro\Mods\`.

For development, set `TEST_TOOLS := true` in `client/scripts/main.gd` (joker gallery and boss preview in the VR menu) and `TEST_MONEY = true` in `BalatroVRBridge.lua` (money and test buttons in Balatro).

## Reporting bugs

Open an [issue](https://github.com/alextreumer/BalatroVRMod/issues) and attach, if you can:

- the newest log from `%AppData%\Balatro\Mods\lovely\log\` (the mod's lines start with `[BalatroVR]`)
- the newest log from `%AppData%\Godot\app_userdata\Balatro in VR\logs\`
- your Steamodded version and VR setup (Quest via Virtual Desktop, Quest Link, SteamVR …)

## License

GPL-3.0 – see [LICENSE](LICENSE). Balatro and its art belong to LocalThunk and Playstack and are not covered by this license.

By [Under the VRadar](https://www.youtube.com/@UnderTheVRadar).
