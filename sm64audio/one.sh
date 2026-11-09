#!/bin/bash
# one.sh <name> <SOUND_...> [frames]: render one Mario 64 sound from the ROM, trim the silence, install it as <mod>/sfx/<name>.wav
cd /x/mashup-work/sm64audio
M="/e/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map"
printf 'length %s\n10 sound %s\n' "${3:-120}" "$2" > sfx/$1.txt
./sm64audio.exe ../rom_us.z64 sfx/$1.raw.wav sfx/$1.txt >/dev/null 2>&1
ffmpeg -v error -y -i sfx/$1.raw.wav -af "silenceremove=start_periods=1:start_threshold=-60dB,areverse,silenceremove=start_periods=1:start_threshold=-60dB,areverse" -ar 48000 sfx/$1.wav && cp sfx/$1.wav "$M/sfx/$1.wav"
echo "$1 $(ffprobe -v error -show_entries format=duration -of csv=p=0 sfx/$1.wav)s $(ffmpeg -i sfx/$1.wav -af volumedetect -f null - 2>&1 | grep -o 'max_volume: [-0-9.]* dB')"
