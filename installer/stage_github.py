# Gathers the mod's code (no Super Mario 64 data, no backups, nothing compiled) into release/github_repo, the
# git working copy of github.com/chaos4726/STORROR64. Then: cd release/github_repo; git add -A; git commit; git push.
# (Its README.md and MUSIC_CREDITS.md come from release/github/.)
import os, re, shutil
WORK = "X:/mashup-work"
MOD = "E:/SteamLibrary/steamapps/common/STORROR Parkour Pro/STORRORParkourPRO/Binaries/Win64/ue4ss/Mods/SM64Map"
OUT = WORK + "/release/github_repo"
JUNK = re.compile(r"\.bak|\.before_|\.broken|\.orig$|\.tmp$|\.off$|_old\b|\.v1\.py$|__pycache__", re.I)
CODE = (".lua", ".py", ".sh", ".ps1", ".cpp", ".c", ".h", ".rc", ".bat", ".cmd", ".md")
n = {}
def put(src, rel):
    d = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(d), exist_ok=True)
    shutil.copy2(src, d)
    top = rel.split("/")[0]
    n[top] = n.get(top, 0) + 1
if os.path.isdir(OUT):
    for e in os.listdir(OUT):
        if e != ".git":
            p = os.path.join(OUT, e)
            shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
os.makedirs(OUT, exist_ok=True)
# the mod's code: its scripts (not the two ROM-made data tables), and its open small files
for f in sorted(os.listdir(MOD + "/Scripts")):
    if f.endswith(".lua") and not JUNK.search(f) and f not in ("level_data.lua", "collision_data.lua"):
        put(MOD + "/Scripts/" + f, "mod/SM64Map/Scripts/" + f)
for f in ("enabled.txt", "swim_base.lua"):
    put(MOD + "/" + f, "mod/SM64Map/" + f)
# its tools: code only, no backups, nothing compiled, no audio or pictures
for d, exts in (("installer", CODE + (".txt",)), ("exporter", CODE), ("tools", CODE), ("sm64net", (".cpp", ".h", ".rc", ".bat", ".sh")),
                ("sm64audio", (".py", ".sh", ".c", ".cpp", ".h"))):
    for root, dirs, files in os.walk(WORK + "/" + d):
        dirs[:] = [x for x in dirs if not JUNK.search(x)]
        for f in files:
            if f.lower().endswith(exts) and not JUNK.search(f):
                rel = os.path.relpath(os.path.join(root, f), WORK).replace("\\", "/")
                put(os.path.join(root, f), rel)
# the repo's own pages
for f in ("README.md", "MUSIC_CREDITS.md"):
    shutil.copy2(WORK + "/release/github/" + f, OUT + "/" + f)
total = sum(n.values())
size = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(OUT) if ".git" not in r for f in fs)
print(n, "| files", total, "| %.1f MB" % (size / 1e6))
