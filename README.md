# STORROR × Super Mario 64

Super Mario 64's castle, courses and Bowser stages, rebuilt inside **STORROR Parkour Pro** and played with its full parkour movement.

## What's in it

- Peach's castle with every painting, plus all 15 courses and the three Bowser stages, with their stars, enemies and moving platforms.
- A ghost race on every course as a 7th star, and a key race on each Bowser stage. Race the ghost over the checkpoints to the finish.
- Online play with Steam friends, peer to peer (no servers).
- A first person mode, per save file, with its own FIRST PERSON tab of over 50 settings (see below).
- Render 96 textures and models, and remixed music.

## What you need

- **STORROR Parkour Pro** on Steam.
- **Your own Super Mario 64 (USA) ROM**, dumped from the original cartridge (`.z64`, `.n64` or `.v64`).

No Super Mario 64 data can be read from this download. The mod's Super Mario 64 files are locked, and only your own ROM unlocks them.

## Install

1. Download `STORROR64-<version>.zip` from [Releases](../../releases) and unzip it.
2. In Steam, right-click STORROR Parkour Pro > **Manage** > **Browse local files**.
3. Copy the `STORRORParkourPRO` folder from the download into that folder, merging it with the one already there.
4. Go to `STORRORParkourPRO\Binaries\Win64\ue4ss\Mods\SM64Map` and run **SM64Setup.exe**.
5. Drag your Super Mario 64 ROM onto its window, or click **Browse** and pick it. The ROM is checked, then the mod's files are unlocked.
6. Start STORROR Parkour Pro.

**Windows warning:** SM64Setup.exe isn't code-signed, so Windows may show "Windows protected your PC" when you run it. Click **More info** > **Run anyway**. Some antivirus programs also flag `dwmapi.dll`, the UE4SS mod loader. Allow it if yours does. Every line of the mod's code is in this repository if you want to check it first.

## Updating

Copy the new download over the old one the same way, then run **SM64Setup.exe** again with your ROM.

## Uninstall

The mod only adds files to STORROR; it doesn't change any of the game's own, so removing those files puts the game back as it was.

1. In Steam, right-click STORROR Parkour Pro > **Manage** > **Browse local files**, then open `STORRORParkourPRO\Binaries\Win64`.
2. **Keep your saves?** They're in `ue4ss\Mods\SM64Map\saves.lua`. Copy that file somewhere safe first.
3. Delete `dwmapi.dll` and the `ue4ss` folder. That removes the mod and UE4SS, the mod loader it came with.
   - If you use other UE4SS mods, keep those: delete only the `ue4ss\Mods\SM64Map` folder, and remove the `SM64Map : 1` line from `ue4ss\Mods\mods.txt`.
4. Optional: the secret unlocks are also kept in `%LOCALAPPDATA%\STORRORParkourPRO\Saved\SM64Map_secrets.lua` (so they survive deleted saves). Delete that file too to remove every trace.

To play again later, install it as above. Put your copied `saves.lua` back in the `SM64Map` folder to carry on where you left off.

## Multiplayer

Pause and open the **ONLINE** tab. You can host a public, passworded or friends-only lobby, join a public one, or invite Steam friends.

## First person

Turn **FIRST PERSON** on at the file select before starting a file: that file plays in first person for good. While you play a first-person file, the pause menu has a **FIRST PERSON** tab (between CONTROLS and SETTINGS) with over 50 settings: field of view, head motion, effects, crosshair, speedometer, flashlight (L), hiding parts of your body, presets and more. The game keeps going behind that tab, so you see each change as you make it. Its last row, **WHAT EACH SETTING DOES**, explains every one. The same settings are in the standalone mod for vanilla STORROR, [StorrorFirstPerson](https://github.com/chaos4726/StorrorFirstPerson).

## Source code

All the mod's code is here to read:

- [`mod/SM64Map/`](mod/SM64Map): the mod itself, the Lua scripts UE4SS loads into STORROR (`Scripts/main.lua` starts it). These are the same scripts that ship in the release zip.
- [`installer/`](installer): the release builder (`make_release.py`) and the source of SM64Setup.exe (`setup/sm64setup.cpp`), which checks your ROM and unlocks the mod's Super Mario 64 files with it.
- [`exporter/`](exporter): the tools that read the levels, models and dialog out of a Super Mario 64 ROM.
- [`sm64net/`](sm64net): the multiplayer DLL's source (Steam peer to peer).
- [`sm64audio/`](sm64audio): the music and sound renderer's source.
- [`tools/`](tools): smaller helper scripts used while making the mod.

No Super Mario 64 data is in this repository.

## Credits

- **STORROR Parkour PRO** is by **Hole in the Sleeve Game Studios** ([Steam](https://store.steampowered.com/app/3125250/STORROR_Parkour_PRO/)). You need to own it to play this mod.
- **Super Mario 64** is © Nintendo.
- **Render 96** textures and models are by the Render 96 team ([github.com/Render96](https://github.com/Render96)).
- **Music:** remixes by the artists below, also listed in [MUSIC_CREDITS.md](MUSIC_CREDITS.md).
- **UE4SS** loads the mod into the game ([RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)).

This is a free fan project, not affiliated with or endorsed by Nintendo, Hole in the Sleeve Game Studios, STORROR or the Render 96 team.

<details>
<summary><b>Music credits</b> (every remix and its artist)</summary>

#### Menus and cutscenes
- Opening: "Super Mario 64 - Opening (Orchestral remake/remix)" by Diego Leal E.
- Pause menu: "Super Mario 64 - File Select (Anthony Greninger Cover Remix)" by Anthonys Melodies
- Star fanfare: "Super Mario 64 - Course Clear (MIDI Remix)" by Flaming Leo Music
- Game over: "Super Mario World - Game Over [SM64 Style]" by @random_remixer
- Credits: "Super Mario 64 - Staff Roll [Remix]" by Qumu

#### Castle
- Inside the castle: "Super Mario 64 - Inside the Castle Walls Remix" by AJ DiSpirito
- Endless Stairs: "Super Mario 64 | Endless Stairs (Piano Cover)" by CrazyGroupTrio
- Outside ambience: "Flowers (Nature Sounds)" by Dennis Korn Music

#### Courses
- Bob-omb Battlefield: "SM64 - Bob-Omb Battlefield (Joshua Milo Remix) | FUNK" by Joshua Milo
- Whomp's Fortress: "Whomp's Fortress (Orchestral Remix)" by ReOST
- Jolly Roger Bay: "Jolly Roger Bay [Remix] (Super Mario 64)" by Watercrate
- Cool, Cool Mountain: "Super Mario 64 - Cool Cool Mountain [HQ Remix]" by Super 0'Brothers
- Cool, Cool Mountain slide: "Cool, Cool Slide (Orchestral Remix)" by ReOST
- Big Boo's Haunt: "Big Boo's Haunt - Dark Ambient Remix (Super Mario 64)" by Scott Arc
- Big Boo's Haunt merry-go-round: "Super Mario 64 Remastered - Merry Go Round" by DeathlyHand
- Hazy Maze Cave (and the Shifting Sand Land pyramid): "Super Mario 64 [Remix] - Hazy Maze Cave (HD Remake)" by BlueJackG Channel
- Lethal Lava Land: "Shifting Sand Land Remix - (Lethal Lava Land)" by Xilore Inaba
- Shifting Sand Land: "Super Mario 64 - Sand Shifting Land [HQ Remix] by Baf" by Super 0'Brothers
- Dire, Dire Docks: "Super Mario 64 HD - Dire, Dire Docks" by Tee Lopes
- Snowman's Land: "Super Mario Galaxy 2 64 - Snowman's Land (Fanmade)" by marionose1
- Snowman's Land igloo: "Inside the Igloo (Orchestral Remix)" by ReOST
- Wet-Dry World: "Super Mario 64 - Wet-Dry World Remake" by MJS Remakes
- Tall, Tall Mountain: "Tall, Tall Mountain (Bluegrass Remix)" by ReOST
- Tall, Tall Mountain slide: "Tall, Tall Slide (Bluegrass Remix)" by ReOST
- Tiny-Huge Island: "Slider (Tiny-Huge Island) - Super Mario 64" by SiIvaGunner
- Wiggler's cave: "Wiggler's Cave (Electronic Remix)" by ReOST
- Tick Tock Clock: "Super Mario 64 - Tick Tock Clock / Slider Race [HQ Remix] by Baf" by Super 0'Brothers
- Rainbow Ride: "Rainbow Ride (Orchestral Remix)" by ReOST

#### Secret stages
- Peach's Secret Slide: "Super Mario 64 music - Peach's Slide (frosty remake)" by Nate
- Tower of the Wing Cap and Vanish Cap Under the Moat: "Super Mario 64 - Powerful Mario (Wing Cap / Vanish Cap) [Remix]" by Qumu
- Wing Mario Over the Rainbow: "Wing Mario (Orchestral Remix)" by ReOST
- Cavern of the Metal Cap: "Cavern of the Metal Cap" by ReOST
- Secret Aquarium: "SM64: Last Impact OST - Secret Aquarium (Mario Sunshine - Sky and Sea N64 remix)" by Kaze Emanuar

#### Bowser
- Bowser in the Dark World: "(Old Upload) The Road To Koopa - Arrangement ~ Super Mario 64" by Nanashima
- Bowser in the Fire Sea: "Bowser in the Fire Sea (Symphonic Metal Remix)" by ReOST
- Bowser in the Sky: "Ultimate Bowser (Bleeding Ink Remix - Bowser In the Sky) - Super Mario 64" by Hyperactive
- 1st Bowser fight: "Super Mario 64 - Koopa's Theme Remix" by AJ DiSpirito
- 2nd Bowser fight: "Bowser's Theme (AKA Koopa's Theme) Remix | Super Mario 64" by Kunning Fox
- Final Bowser fight: "Super Mario 64 - Ultimate Bowser Epic Orchestral Remix" by TLB Orchestration

#### Bosses
- King Bob-omb and other bosses: "Stage Boss - Super Mario 64 Remix" by SaMiX
- Whomp King: "Whomp King (Orchestral Remix)" by ReOST
- Big Bully: "Big Bully (Rock Remix)" by ReOST
- Chill Bully: "Chill Bully (Metal Remix)" by ReOST
- Eyerok: "Eyerock (Metal Remix)" by ReOST
- Wiggler: "Wiggler (Electronic Remix)" by ReOST
- Final Big Boo: "Final Big Boo (Orchestral Remix)" by ReOST

#### Caps and events
- Wing Cap / Vanish Cap: "SM64 - Powerful Mario (Joshua Milo Remake)" by Joshua Milo
- Metal Cap: "Metallic Mario (New Remix) | Super Smash Bros. Ultimate [FANMADE]" by 0retro0
- Piranha Plant: "Super Mario 64 - Piranha Plant's Lullaby (cover)" by MerryberryMusic
- Race against the ghost: "Cosmic Clones | The Super Mario Galaxy REMIX" by Eyem

</details>
