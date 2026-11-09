#!/bin/bash
# fuzz.sh scene[:act]... (FUZZ_N=segments, default 14 ~ 20 s): in each scene, at its spawn, drive him about with random key presses for ~20 s (real input through
# tools/keys.ps1 - the game window must be in front), then report the script errors, lives lost and where he ended up.
# Lives and power put back after each. Restart the game between batches of 3 (crash rules: actor churn).
cd /x/mashup-work
L="/e/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/UE4SS.log"
D="/e/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/dev"
ID=$(( ($(date +%s) % 100000) * 20 + 240000000 ))
run() {
    ID=$((ID + 1))
    printf -- '-- id: %s\n%s\n' "$ID" "$1" > "$D/cmd.lua"
    RP="(no reply)"
    for i in $(seq 1 60); do
        sleep 0.1
        local R=$(awk -v id="$ID" '$0=="== run " id{p=1;next} /^== run /{p=0} p' "$D/out.txt" 2>/dev/null | tail -1)
        [ -n "$R" ] && { RP="$R"; return; }
    done
}
keyseq() {  # a random ~20 s of running, turning and jumping
    local s=""
    for i in $(seq 1 ${FUZZ_N:-14}); do
        local d=$((RANDOM % 4)); local k=W
        [ $d = 1 ] && k=A; [ $d = 2 ] && k=D; [ $d = 3 ] && k=S
        s="$s down:W wait:$((300 + RANDOM % 600))"
        [ $k != W ] && s="$s down:$k wait:$((200 + RANDOM % 500)) up:$k"
        [ $((RANDOM % 3)) = 0 ] && s="$s mx:$(( (RANDOM % 4800) - 2400 ))"
        [ $((RANDOM % 2)) = 0 ] && s="$s down:SPACE wait:120 up:SPACE wait:$((200 + RANDOM % 400))"
        s="$s up:W wait:$((50 + RANDOM % 300))"
    done
    echo "$s"
}
for ARG in "$@"; do
    SC=${ARG%%:*}; ACT=${ARG#*:}; [ "$ACT" = "$ARG" ] && ACT=""
    if [ -n "$ACT" ]; then
        run "_G.HEALTH.lives = 4; _G.HEALTH.health = _G.HEALTH.MAX; local G=package.loaded.game; G.course_act = { course = '$SC', act = $ACT }; G.goto_scene('$SC', 0x0A); return 'going'"
    else
        run "_G.HEALTH.lives = 4; _G.HEALTH.health = _G.HEALTH.MAX; local G=package.loaded.game; G.goto_scene('$SC'); return 'going'"
    fi
    sleep 6
    N0=$(wc -l < "$L")
    powershell -NoProfile -ExecutionPolicy Bypass -File "X:/mashup-work/tools/keys.ps1" "$(keyseq)"
    sleep 2
    run "local lib=require('lib'); local G=package.loaded.game; local O=lib.OFFSET; local p=lib.pawn(); local H=_G.HEALTH; local s=string.format('%s lives=%s hp=%d', tostring(G.name), tostring(H.lives), H.health); if p then local l=p:K2_GetActorLocation(); s=s..string.format(' at (%.0f,%.0f,%.0f)', l.X-O.X, l.Y-O.Y, l.Z-O.Z) end; H.lives = 4; H.health = H.MAX; return s"
    BAD=$(tail -n +$((N0 + 1)) "$L" | grep -ai "error\|attempt to\|nil value\|failed\|traceback" | cut -c40-220 | sort | uniq -c | head -6 | tr '\n' ';')
    EV=$(tail -n +$((N0 + 1)) "$L" | grep -a "\[SM64Map\]" | cut -c40-130 | grep -v "feet: \|footsteps" | sort | uniq -c | sort -rn | head -6 | tr '\n' ';')
    echo "$ARG: $RP | errors: ${BAD:-none} | events: $EV"
done
