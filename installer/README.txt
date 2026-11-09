STORROR x SUPER MARIO 64
========================

What you need
- STORROR Parkour Pro (Steam)
- Your own Super Mario 64 (USA) ROM, dumped from the original cartridge (.z64, .n64 or .v64)

Install
1. Open STORROR Parkour Pro's folder: in Steam, right-click the game > Manage > Browse local files.
2. Copy the "STORRORParkourPRO" folder from this download into it (merge it with the one that is there).
3. Go to STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map and run SM64Setup.exe.
4. Drag your Super Mario 64 ROM onto its window, or click Browse and pick it.
   It is checked, then the mod's Super Mario 64 files are unlocked with it. Nothing of Super Mario 64 ships with
   this mod: without the ROM there is nothing to play.
5. Start STORROR Parkour Pro.

Updating
Copy the new download over the old one the same way, then run SM64Setup.exe again with your ROM.

Uninstall
The mod only adds files to STORROR; it doesn't change any of the game's own, so removing them puts the game back as
it was.
1. In Steam, right-click STORROR Parkour Pro > Manage > Browse local files, then open STORRORParkourPRO\Binaries\Win64.
2. Keep your saves? They're in ue4ss\Mods\SM64Map\saves.lua. Copy that file somewhere safe first.
3. Delete dwmapi.dll and the ue4ss folder. That removes the mod and UE4SS, the mod loader it came with.
   If you use other UE4SS mods, keep those: delete only the ue4ss\Mods\SM64Map folder, and remove the
   "SM64Map : 1" line from ue4ss\Mods\mods.txt.
4. Optional: the secret unlocks are also kept in %LOCALAPPDATA%\STORRORParkourPRO\Saved\SM64Map_secrets.lua (so they
   survive deleted saves). Delete that file too to remove every trace.
To play again later, install it as above. Put your copied saves.lua back in the SM64Map folder to carry on where you
left off.

Multiplayer
Pause, go to the ONLINE tab: host a public, passworded or friends-only lobby, join a public one, or invite Steam
friends. Peer to peer through Steam: no server of anyone's.

Credits
STORROR Parkour PRO is by Hole in the Sleeve Game Studios. Super Mario 64 is Nintendo's. Render 96's textures and models
are by the Render 96 team (github.com/Render96). The remixed music is by the artists named on the first sign in the
castle grounds and in MUSIC_CREDITS.md. UE4SS loads the mod. A free fan project, not affiliated with or endorsed by
Nintendo, Hole in the Sleeve Game Studios, STORROR or the Render 96 team.
