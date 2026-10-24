# Balatro in VR

Play [Balatro](https://www.playbalatro.com/) in virtual reality. Balatro keeps running on your PC as usual; a small mod (**BalatroVRBridge**) sends the whole game to a VR client built with Godot, which shows it around you in a virtual casino:

- your cards in your hand – grab them, play them on the stake chip, throw them over your shoulder to discard
- jokers as 3D models on the table, booster packs to tear open, a reroll machine with a lever
- a shop counter where you grab what you buy, a real Wheel of Fortune, boss blinds that change the room
- a score tower and chip mountains that grow with your run
- the casino table as the main menu, Solatro – a solo card game on the table – and VR achievements


Watch the Showcase Trailer here: https://youtu.be/jdWvll1mY_0

You need your own copy of Balatro: the client takes all card art, sounds and the font from your installed game while it runs – **no game files from Balatro are included here.** Fan project, not affiliated with LocalThunk or Playstack.

## Install

You need Balatro (Steam, Windows) and a VR headset (e.g. Meta Quest with Virtual Desktop or Quest Link, or SteamVR).

1. **Lovely:** download `lovely-x86_64-pc-windows-msvc.zip` from [lovely-injector releases](https://github.com/ethangreen-dev/lovely-injector/releases) and copy the `winmm.dll` inside it into Balatro's game folder (Steam → right-click Balatro → Manage → Browse local files).
2. **Steamodded:** download [Steamodded](https://github.com/Steamodded/smods) (Code → Download ZIP) and unpack it into `%AppData%\Balatro\Mods\`.
3. **Balatro in VR:** download the zip from the [Releases](https://github.com/alextreumer/BalatroVRMod/releases) page. Copy its `Mod\BalatroVRBridge` folder into `%AppData%\Balatro\Mods\` and the `Balatro in VR` folder anywhere you like.
4. **Play:** start your VR software, then `Balatro in VR.exe`, then Balatro. Both find each other by themselves.

The zip contains `INSTALL.md` with every step in detail and help if something does not work.

## Or build it yourself

- `client/` – the Godot 4.7 VR client (see `client/README.md` for all controls and features)
- `BalatroMod/` – the Balatro mod (Lovely + Steamodded)
- `Docs/` – the protocol between mod and client, architecture notes

1. Install [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) and its export templates (Editor → Manage Export Templates).
2. Open `client/project.godot` in Godot.
3. Run it from the editor, or export it: Project → Export → *Windows Desktop*. The preset writes `Release/Balatro in VR/Balatro in VR.exe` and its `.pck` (both must stay together).
4. Install Lovely and Steamodded as in [Install](#install), then copy `BalatroMod/BalatroVRBridge` into `%AppData%\Balatro\Mods\`.

For development, set `TEST_TOOLS := true` in `client/scripts/main.gd` (joker gallery and boss preview in the VR menu) and `TEST_MONEY = true` in `BalatroVRBridge.lua` (money and test buttons in Balatro).

### Reporting bugs

Open an [issue](https://github.com/alextreumer/BalatroVRMod/issues) and attach, if you can:

- the newest log from `%AppData%\Balatro\Mods\lovely\log\` (the mod's lines start with `[BalatroVR]`)
- the newest log from `%AppData%\Godot\app_userdata\Balatro in VR\logs\`
- your Steamodded version and VR setup (Quest via Virtual Desktop, Quest Link, SteamVR …)

## License

GPL-3.0 – see [LICENSE](LICENSE). Balatro and its art belong to LocalThunk and Playstack and are not covered by this license.

By [Under the VRadar](https://www.youtube.com/@UnderTheVRadar).
