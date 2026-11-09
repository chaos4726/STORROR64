#!/bin/bash
# actsweep.sh course... : load each act (1-6) of each course, idle 6 s (invulnerable), report script errors seen
cd /x/mashup-work
L="/e/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/UE4SS.log"
D="/e/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map/dev"
ID=$(( ($(date +%s) % 100000) * 20 + 160000000 ))
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
for SC in "$@"; do
  for ACT in 1 2 3 4 5 6; do
    run "local G=package.loaded.game; G.goto_scene('castle'); return 'out'"
    sleep 2.5
    N0=$(wc -l < "$L")
    run "_G.HEALTH.lives = 4; _G.HEALTH.health = _G.HEALTH.MAX; local G=package.loaded.game; G.course_act = { course = '$SC', act = $ACT }; G.goto_scene('$SC', 0x0A); return 'going'"
    sleep 1.5
    run "_G.HEALTH.grace = 30; return 'shielded'"
    sleep 5
    BAD=$(tail -n +$((N0 + 1)) "$L" | grep -ai "error\|broken\|failed\|attempt to\|nil value" | grep -v "falling back" | cut -c40-200 | sort | uniq -c | head -4 | tr '\n' ';')
    echo "$SC act $ACT: ${BAD:-clean}"
  done
done
