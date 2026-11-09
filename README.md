# STORROR × Super Mario 64

Super Mario 64's castle, courses and Bowser stages, rebuilt inside **STORROR Parkour Pro** and played with its full parkour movement.

## What's in it

- Peach's castle with every painting, plus all 15 courses and the three Bowser stages, with their stars, enemies and moving platforms.
- A ghost race on every course as a 7th star, and a key race on each Bowser stage. Race the ghost over the checkpoints to the finish.
- Online play with Steam friends, peer to peer (no servers).
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

## Multiplayer

Pause and open the **ONLINE** tab. You can host a public, passworded or friends-only lobby, join a public one, or invite Steam friends.

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

- Super Mario 64 is © Nintendo. This is a free fan project, not affiliated with or endorsed by Nintendo or the makers of STORROR Parkour Pro.
- Render 96 textures and models are by the Render 96 team.
- The remixed music is by the artists listed in [MUSIC_CREDITS.md](MUSIC_CREDITS.md).
- Mod loading is by [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS).
