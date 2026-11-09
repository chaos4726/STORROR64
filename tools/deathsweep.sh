#!/bin/bash
# deathsweep.sh [courses...]: in each course, run the power out and check the death warp: one life, where it lands
cd /x/mashup-work
L="/e/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/UE4SS.log"
D="/e/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/dev"
ID=$(( ($(date +%s) % 100000) * 20 + 180000000 ))
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
for SC in ${@:-bob wf jrb ccm bbh hmc lll ssl ddd sl wdw ttm thi ttc rr bitdw bitfs bits pss cotmc totwc vcutm wmotr sa}; do
    run "_G.HEALTH.lives = 4; _G.HEALTH.health = _G.HEALTH.MAX; local G=package.loaded.game; G.goto_scene('$SC'); return 'going'"
    sleep 4
    N0=$(wc -l < "$L")
    run "_G.HEALTH.kill('test'); return 'killed'"
    sleep 7
    run "local lib=require('lib'); local G=package.loaded.game; local p=lib.pawn(); local H=_G.HEALTH; return string.format('-> %s lives=%s pawn=%s dying=%s dead=%s', tostring(G.name), tostring(H.lives), tostring(p ~= nil), tostring(G.dying ~= nil), tostring(H.dead_t ~= nil))"
    LOST=$(tail -n +$((N0 + 1)) "$L" | grep -ac "lost a life")
    BAD=$(tail -n +$((N0 + 1)) "$L" | grep -ai "error\|failed\|refused" | cut -c40-150 | head -2 | tr '\n' ';')
    echo "$SC: $RP lives_lost=$LOST ${BAD:+| $BAD}"
done
