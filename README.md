# Balatro in VR

Play [Balatro](https://www.playbalatro.com/) in virtual reality. Balatro keeps running on your PC as usual; a small mod (**BalatroVRBridge**) sends the whole game to a VR client built with Godot, which shows it around you in a virtual casino – with your cards in your hand, 3D jokers on the table, booster packs to tear open and much more.

- **Players:** download the latest release and follow `INSTALL.md` inside it.
- `client/` – the Godot 4.7 VR client (see `client/README.md` for all controls and features)
- `BalatroMod/` – the Balatro mod (Lovely + Steamodded)
- `Docs/` – the protocol between mod and client, architecture notes

Godot project and Steamodded Lua file – **no game files from Balatro itself.** Fan project, not affiliated with LocalThunk or Playstack. You need your own copy of Balatro: the client takes all card art, sounds and the font from your installed game at runtime – nothing of the game is included here.

By [Under the VRadar](https://www.youtube.com/@UnderTheVRadar).
