#!/bin/bash
# sweep.sh [scenes...]: visit each scene at its spawn, wait, and report how the arrival went (errors, falls, deaths)
cd /x/mashup-work
L="/e/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/UE4SS.log"
D="/e/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/dev"
ID=$(( ($(date +%s) % 100000) * 20 + 220000000 ))
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
SCENES="${@:-bbh bitdw bitfs bits bob bowser bowser_2 bowser_3 castle castle2 castle3 ccm ccm_2 cotmc courtyard ddd ddd_2 grounds hmc jrb jrb_2 lll lll_2 pss rr sa sl sl_2 ssl ssl_2 ssl_3 thi thi_2 thi_3 totwc ttc ttm ttm_2 ttm_3 ttm_4 vcutm wdw wdw_2 wf wmotr}"
for SC in $SCENES; do
    N0=$(wc -l < "$L")
    run "_G.HEALTH.lives = 4; _G.HEALTH.health = _G.HEALTH.MAX; local G=package.loaded.game; G.goto_scene('$SC'); return 'going'"
    T0=$(date +%s.%N); OK=""
    for i in $(seq 1 120); do sleep 0.1; tail -n +$((N0 + 1)) "$L" | grep -aq "player -> $SC" && { OK=1; break; }; done
    LT=$(tail -n +$((N0 + 1)) "$L" | grep -a "scene $SC ready" | grep -o "([0-9.]*s total)")
    sleep 4
    run "local lib=require('lib'); local G=package.loaded.game; local O=lib.OFFSET; local p=lib.pawn(); if not p then return 'NO PAWN' end; local l=p:K2_GetActorLocation(); local H=_G.HEALTH; return string.format('at (%.0f,%.0f,%.0f) m%s lives=%s dead=%s dying=%s', l.X-O.X, l.Y-O.Y, l.Z-O.Z, tostring(p.CharacterMovement.MovementMode), tostring(H.lives), tostring(H.dead_t ~= nil), tostring(G.dying ~= nil))"
    BAD=$(tail -n +$((N0 + 1)) "$L" | grep -ai "error\|fell out\|lost a life\|refused\|stuck\|out of power\|could not\|failed" | cut -c40-150 | sort | uniq -c | tr '\n' ';' | cut -c1-300)
    echo "$SC: arrived=${OK:-NO} $LT $RP ${BAD:+| $BAD}"
done
