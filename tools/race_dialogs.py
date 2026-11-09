"""The ghost racer's words (race.lua), drawn as Mario 64's dialog box draws its messages (exporter/dialogx.py's pages, its
font, Koopa the Quick's question's box - DIALOG_005: three lines a page, 30 from the left, 200 up): textures/
dlg_<n>_<page>.png and data/dialogs_extra.lua (dialog.lua takes it in with data/dialogs.lua). 2026-10-27: "now we have
to make the start of the race".

python tools/race_dialogs.py <SM64Map mod dir>   (SM64_DECOMP set, as for the exporter)
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "exporter"))
import introx
from PIL import Image

MOD = sys.argv[1]
TEXD, DATA = os.path.join(MOD, "textures"), os.path.join(MOD, "Scripts", "data")
font, K = introx.Font(), introx.K
LINE_MAX = 132
PER, LEFT, TOP = 3, 30, 200

# the messages: their number (past Mario 64's), their pages - a question's last line its two answers, as his are
# written ("//Go!////Don't Go")
MESSAGES = {
    # (the racer's question: Bowser's hired guard of the level's secret star, one of eighteen brothers - "something about
    # bowser hiring him and his 14 other brothers. to keep the secret star safe, then a hint that collecting them all
    # will make bowser angry and show his true self", then "17 other brothers my bad", 2026-10-27)
    # (two sentences a box, none run on into the next: "make each box 2 sentences per window", 2026-10-27)
    # (then not hired at all: a ghost star gave each his body - "instead of the hired and im going home dialog use
    # something like I can feel myself being pulled back in", "The ghost star has given me a physic form", 2026-11-05.
    # The eighteen's own words are 9100 on, below; this one is left for a racer of none of them)
    9001: ["Heh heh... so you found\nme! This ghost star gave\nme a physical form.",
           "My 17 brothers hold one\ntoo. One of us guards\nevery level!",
           "Outrun me and this star\nis yours. Just follow\nthe flags!",
           "But I'll warn you... Take\nall 18 of our stars, and\nBowser will get angry.",
           "Angry enough to show his\ntrue self! Still want to\nrace me?",
           "Ready....\n\n//Go!////Don't Go"],
    # (back again, his star won from him already: only the question - "now when the player comes back and retrys the
    # level, remove the backpack from the ghost and just have it ask a simple "improve your time?"", 2026-10-27)
    9004: ["Improve your time?\n\n//Go!////Don't Go"],
    # (back again, and beaten by the ghost: only that - "if the player fails just say. try again", 2026-10-27)
    9005: ["Try again!"],
    # (back again, and the ghost beaten: the time beaten, then his new one - drawn in when the box comes up, at
    # FILLS - "if the player succeeds label the old then the new time", 2026-10-27)
    9006: ["Old time:\nNew time:"],
    # (lost: the ghost home first - said from the line as he gets there, "if the ghost finishes before the player it.
    # should say something along the lines of "I knew I could do this job unfortunate for you though next time keep
    # up!"", 2026-10-27)
    9002: ["Heh heh... I knew I could\ndo this job! The secret\nstar stays with me.",
           "Too bad for you, though.\nNext time, try to\nkeep up!"],
    # (won: he gets home after him, worn out, and gives up the star - "if the player wins "huff huff huff, you win I cant
    # go anymore ill leave it up to my brothers to outpace you heres your star and farewell for now I'm going home"",
    # 2026-10-27)
    9003: ["Huff... huff... huff...\nYou win! I can't go\nany more.",
           "I'll leave it to my\nbrothers to outpace you.\nHere's your star!",
           # (and that the race is there to be run again: "oh also add something that say's you can always play again
           # to improve your own time though", 2026-10-27 - the ghost raced then the best of his own runs)
           "Come back any time to\nimprove your time! Retry\nthe level to race again.",
           # (and who will be there: the player's own run, raced from now on - "add that theres a newer faster runner
           # to beat by retrying the level", 2026-10-27)
           "A newer, faster runner\nwill be waiting for you.\nYour own best run!",
           "I can feel the star\npulling me back in...\nFarewell for now!"],
    # (a sign of the mod's own, game.lua G.EXTRA_SIGNS: Rainbow Ride's, by the wall brought down - "in front of the player
    # place a sign and make it say Tic Tac Needed", 2026-11-02)
    9007: ["Tic Tac Needed"],
    # (joined someone's game: its stars - drawn in after the label, FILLS - and its game modes, mp.lua: "when joining
    # someone tell the player how much stars and what gamemodes are in the server", 2026-11-03)
    9010: ["Stars in this game:\nNo game modes are on.\nHave fun!"],
    9011: ["Stars in this game:\nHuman Mode is on: one\nhit and you're dead!"],
    9012: ["Stars in this game:\nIronMan Mode is on:\none life, no retries!"],
    9013: ["Stars in this game:\nHuman and IronMan Mode\nare on. Be careful!"],
    # (turned away from an IRONMAN game he died in - mp.lua M.ironman_tick: "if the connected players disconnect and
    # cannot reconnect after death", 2026-11-04)
    9023: ["You died in this IRONMAN game, so you can't join it again."],
    # (the secrets Final Bowser opens, told back on the castle grounds - secrets.lua, ending.lua: "after the player beats
    # final bowser the player unlocks a secret unlock", 2026-11-04)
}
# (each: "you've unlocked "Example" for finishing the game with "gamemodes". then explain where to find the setting or
# skin", 2026-11-04 - one message per secret and per the modes the file was finished with: secrets.lua M.msg_for)
_WITH = {"": "", "iron": " with IRONMAN mode", "human": " with HUMAN mode", "both": " with HUMAN and IRONMAN mode"}
_WEAR = {"SKIN": "Wear it from the pause menu: the CHARACTER tab, its SKIN row.",
         "HAT": "Wear it from the pause menu: the CHARACTER tab, its HAT row."}
for _n, _what, _modes, _where in (
        ((9014, 9018, 9019, 9020), "the GHOST RUNNER skin", ("", "iron", "human", "both"), _WEAR["SKIN"]),
        ((9015, 9021), "the CROWN", ("iron", "both"), _WEAR["HAT"]),
        ((9016, 9022), "GORE", ("human", "both"),
         "Turn it on in the pause menu's MARIO SETTINGS tab: a death in any mode is gruesome, with no one-hit deaths."),
        ((9017,), "the RAINBOW skin", ("both",), _WEAR["SKIN"])):
    for _id, _m in zip(_n, _modes):
        MESSAGES[_id] = ["You've unlocked %s for finishing the game%s!" % (_what, _WITH[_m]), _where]


# ------------------------------------------------------------------ the eighteen ghosts (2026-11-05)
# Each guard his own words, and what he says hangs on the brothers beaten before him ("every ghost runners dialog
# should be different and dependant on ghosts you beat before"); not hired by Bowser any more - a ghost star gave each
# his body, and beaten, it pulls him back in ("I can feel myself being pulled back in", "the power draws me back in",
# "the ghost star has given me a physical form"). race.lua puts a box together from these (dialog.lua takes a list):
#   9100 + 10*(i-1): +0 his greeting, +1 back again (raced him before), +2 his dare (the question), +3 he won (two
#   boxes), +4 beaten, +5 beaten - the star (or key) handed over as it pulls him back in.
#   Shared: 9300 the ghost stars' tale (the first met), 9301-9305 how many brothers are beaten, 9310+i word of brother
#   i beaten, 9331-9333 a floor's last ghost telling of its key, 9341-9343 the keys so far, 9350 come back any time.
GHOSTS = [
    # (course, greeting, back again, dare, won, beaten, handed over)
    ("bob", "Heh heh! You found me! I'm the fastest thing on this whole battlefield.",
     "Back again? This time I won't even break a sweat!",
     "Race me to the top?",
     ["Ha! Too slow! The summit is mine, and so is my star.", "Go practice on some Goombas and come back later!"],
     "Huff... huff... No way! Nobody's ever beaten me up here!",
     ["Whoa... I can feel the star pulling me back in!", "Take it. My brothers won't be so easy!"]),
    ("wf", "Halt! I guard Whomp's Fortress. None pass me, and none outrun me.",
     "You return? Admirable. Foolish, but admirable.",
     "Shall we begin?",
     ["The fortress stands, and so does my record!", "Train harder, recruit. Then try again."],
     "Impossible... The fortress has fallen!",
     ["The star's power is calling me back.", "Take it, with honor. You won't beat us all!"]),
    ("jrb", "Ahoy, landlubber! This bay be mine, and so be my ghost star!",
     "Washed back ashore, have ye? Har har!",
     "Ready to set sail?",
     ["Har har! Ye be slower than a sunken ship!", "Swab the deck and try again, matey!"],
     "Shiver me timbers... ye outran me!",
     ["The star be draggin' me back in! It be yours now.", "My brothers will sink ye yet!"]),
    ("ccm", "Yo! Just chillin' up here on the mountain. Nice day for a race, huh?",
     "Hey, you again! No hard feelings about last time, right?",
     "Race me, dude?",
     ["Whoa, that was easy! Guess you got cold feet.", "Warm up a bit and come back, dude."],
     "Duuude... you're fast! You totally froze me out.",
     "Whoa, the star's pulling me back in... Gnarly! It's all yours. Stay frosty!"),
    ("bbh", "Boo-hoo-hoo! Welcome to my haunt... Few who enter ever leave on time!",
     "Back from the grave, are we? Delightful!",
     "Dare you race me?",
     ["Boo-hoo-hoo! Scared stiff, were you?", "My star stays here... haunted forever!"],
     "Eek! You ran right through me!",
     "Back into the star I go... Ooooh! Take it, before my brothers come for you!"),
    ("hmc", "Shh! Did anyone follow you? Down here, I know every twist and turn.",
     "You found your way back? Hmm... suspicious.",
     "Can you keep up?",
     ["Lost already? This maze swallows the slow ones.", "Find your way out and try again... if you can!"],
     "How?! You knew the shortcuts! Someone told you!",
     ["No, no, the star's pulling me in!", "Fine, take it. Just don't tell anyone where I hid!"]),
    ("lll", "Grr! Another challenger?! I'm burning to show you how it's done!",
     "YOU again?! You've got some nerve!",
     "Let's heat it up!",
     ["HA! Burned you! Bet you felt the heat!", "Cool off and come back when you're ready!"],
     "ARGH! I'm boiling mad! You beat me?!",
     ["The star's dragging me back in!", "Take it, before I blow my top! My brothers will get you!"]),
    ("ssl", "Out here the sand shifts... but my lead never does.",
     "Back for more sand in your shoes?",
     "Ready to race?",
     ["Still out there? Must be the sand in your eyes.", "Shake it off and try again, wanderer."],
     "Well... the sands have shifted. You win.",
     ["I can feel the star taking me back. It's yours.", "Mind the quicksand on your way out."]),
    ("ddd", "Sigh... It's quiet down here in the docks. Too quiet. Let's race.",
     "Oh. You came back. That's... nice, I guess.",
     "Shall we race?",
     ["I won. Sigh... somehow that didn't cheer me up.", "Try again if you like. I'll be here. Always."],
     "You beat me. Figures. Nothing ever goes my way.",
     ["Now the star's pulling me back in. Of course it is.", "Take it... maybe it'll make you happy."]),
    ("sl", "Brr. Make it quick. It's freezing out here.",
     "You again. Let's not waste time.",
     "Ready? Then go.",
     ["Too slow. Your chances just froze over.", "Thaw out and try again."],
     "...Hmph. You're faster than you look.",
     "The star's power draws me back in. Take it. You won't get past all of us."),
    ("wdw", "Oh! Hi! Are we racing? I think we're racing. Yes. Racing!",
     "You're back! I'm happy. Or mad? Both, maybe!",
     "Race now? Or later?",
     ["I won? I won! Wait, should I feel bad? Nah!", "Come back when the water's right for you!"],
     "I lost... I'm sad. No, mad! No... impressed!",
     ["Oh! The star's pulling me back!", "Here, take it. I think that's the right thing to do!"]),
    ("ttm", "You climbed all the way up here? I run up this mountain for breakfast!",
     "Back at base camp, huh? Let's climb!",
     "Race to the top?",
     ["The view up here is great. Shame you missed it!", "Catch your breath and try again!"],
     "Whew... you've got real mountain legs!",
     "The star's tugging me back in. It's yours! Watch your step going down."),
    ("thi", "Big or small, I'm the fastest thing on this island!",
     "Back again? Your nerve is huge. Your speed is tiny!",
     "Ready, little one?",
     ["You came up short! Tiny steps, tiny chance.", "Grow up a bit and try again!"],
     "Whoa... you're a giant of a runner!",
     ["The star's shrinking me back into it!", "Take it. I'm feeling pretty small right now."]),
    ("ttc", "Tick tock! You're late. I've been waiting for ages!",
     "Right on time. Let's see if you've gotten faster.",
     "Start the clock?",
     ["Time's up! You were behind every second.", "The clock never lies. Try again!"],
     "Impossible! My timing was perfect!",
     ["My time is up... the star is pulling me back in.", "Take it. You earned every second."]),
    ("rr", "Look at me, way up in the clouds! The flashiest racer of them all!",
     "Back for an encore? I love an audience!",
     "Ready for the show?",
     ["What a finish! Did you see it? No, you were behind!", "Come back when you can keep up with a star!"],
     "Whoa... that was some show. You stole it!",
     ["The star's pulling me off stage!", "Take it, superstar. My brothers will steal it back!"]),
    # (the floors' big brothers, in the Bowser courses: each guards one of the three keys of the chained door)
    ("bitdw", ["So... you've beaten my little brothers.", "I'm not like them. I guard one of Bowser's keys."],
     "Back already? The key isn't going anywhere.",
     "Ready for the real thing?",
     ["Heh. Just as I thought. The key stays with me.", "Outrun me fair and square, and it's yours."],
     "Grr... Very well. You've earned it.",
     ["The star's power is pulling me back in...", "Take the key. It opens one lock on Bowser's chained door."]),
    ("bitfs", ["The fire down here burns hot, but I burn hotter!", "Bowser's key is safe with me."],
     "Not scorched enough yet? Let's go!",
     "Into the fire?",
     ["Burned again! This key isn't leaving the Fire Sea.", "Come back when you can stand the heat!"],
     "You... outran the fire itself?!",
     ["The star's drawing me back in...", "The key is yours. Bowser won't be pleased!"]),
    ("bits", ["I am the eldest. My brothers below were only practice.", "Up here in the sky, I don't lose."],
     "You return. Good. Again, then.",
     "One last race?",
     ["The sky belongs to me, and so does this key.", "Climb back up when you're ready to try again."],
     "...At last. Someone faster than me.",
     ["The star is pulling me back in.", "Take my key. Bowser waits behind his door."]),
]
# (word of a beaten brother, said by whichever ghost is met next)
RUMOR = {
    "bob": "I heard you outran the rookie on Bob-omb Battlefield!",
    "wf": "You beat the guard of Whomp's Fortress? He's still sulking!",
    "jrb": "My brother in Jolly Roger Bay says you left him in your wake. Poor fella.",
    "ccm": "You iced our brother on Cool, Cool Mountain! He'll never live that down.",
    "bbh": "Even our spooky brother in Big Boo's Haunt couldn't scare you off the pace.",
    "hmc": "You got past our brother in Hazy Maze Cave. Most folks get lost!",
    "lll": "You beat the hothead in Lethal Lava Land? He's still fuming about it!",
    "ssl": "Our brother in Shifting Sand Land says you left him eating sand.",
    "ddd": "You sank our brother in Dire, Dire Docks. He's so down!",
    "sl": "You left our brother in Snowman's Land out in the cold. Brr!",
    "wdw": "Our brother in Wet-Dry World can't decide if he's mad or sad!",
    "ttm": "You beat our brother on Tall, Tall Mountain? He's still catching his breath!",
    "thi": "Our brother on Tiny-Huge Island says you made him feel very small.",
    "ttc": "Our brother in Tick Tock Clock says you beat him by a second. He counted!",
    "rr": "You stole the show from our brother on Rainbow Ride!",
    "bitdw": "You took the key from our big brother in the Dark World? Wow!",
    "bitfs": "Even our big brother in the Fire Sea got burned by you.",
    "bits": "You beat our eldest, high in the sky? Then nothing can stop you.",
}
for _i, (_c, _open, _again, _dare, _won, _beat, _give) in enumerate(GHOSTS):
    _b = 9100 + 10 * _i
    _l = lambda v: list(v) if isinstance(v, (list, tuple)) else [v]
    MESSAGES[_b] = _l(_open)
    MESSAGES[_b + 1] = _l(_again)
    MESSAGES[_b + 2] = [_dare + "\n\n//Go!////Don't Go"]
    MESSAGES[_b + 3] = list(_won)
    MESSAGES[_b + 4] = _l(_beat)
    MESSAGES[_b + 5] = _l(_give)
    MESSAGES[9311 + _i] = [RUMOR[_c]]
# (the first ghost met tells what they are and what the race is for)
MESSAGES[9300] = ["See this star? It's a ghost star. It gave me a physical form!",
                  "My 17 brothers each hold one too. One of us guards every course.",
                  "Outrun me and my star is yours. Just follow the flags!",
                  "Beat every brother on one floor, and you'll learn where a key is hidden.",
                  "Three keys open Bowser's chained door. But that will make him angry...",
                  "Angry enough to show his true self!"]
MESSAGES[9301] = ["Nobody has beaten any of us yet. You won't be the first!"]
MESSAGES[9302] = ["You've beaten a few of us now. Don't let it go to your head!"]
MESSAGES[9303] = ["Word travels fast. You've sent a lot of my brothers back into their stars."]
MESSAGES[9304] = ["Most of my brothers have lost to you. But I'm not most of my brothers!"]
MESSAGES[9305] = ["Every course guard has fallen to you. Only the big brothers are left!"]
# (the last of a floor's ghosts beaten: where its big brother waits with a key - "The last race the player runs on the
# floor and finishes the ghost reveals the whereabouts of the key", 2026-11-05)
MESSAGES[9331] = ["Wait... I was the last of us on this floor?",
                  "Then here's a secret: our big brother waits in Bowser in the Dark World.",
                  "He guards one of Bowser's keys!"]
MESSAGES[9332] = ["That was the last of us down in the basement!",
                  "Our big brother waits in Bowser in the Fire Sea.", "He guards another of Bowser's keys!"]
MESSAGES[9333] = ["Every brother up here has lost to you now!",
                  "Our eldest waits in Bowser in the Sky.", "He guards the last of Bowser's keys!"]
MESSAGES[9341] = ["That's one key. Two more locks still hold Bowser's chained door shut."]
MESSAGES[9342] = ["That's two keys! Just one lock left on Bowser's chained door."]
MESSAGES[9343] = ["That's all three keys!", "The chained door at the top of the endless stairs will open for you now."]
MESSAGES[9350] = ["Come back any time to improve your time! Retry the level to race again.",
                  "A newer, faster runner will be waiting for you. Your own best run!"]


def line_width(text):
    c = Image.new("RGBA", (400 * K, 40 * K), (0, 0, 0, 0))
    font.draw(c, 0, 20, text, (255, 255, 255))
    b = c.getbbox()
    return (b[2] / K) if b else 0.0


def wrap_pages(pages, per):
    out = []
    for text in pages:
        lines = []
        for para in text.split("\n"):
            if para.startswith("//"):
                lines.append(para)
                continue
            cur = ""
            for w in para.split():
                t = (cur + " " + w).strip()
                if cur and line_width(t) > LINE_MAX:
                    lines.append(cur)
                    cur = w
                else:
                    cur = t
            lines.append(cur)
        while len(lines) % per:
            lines.append("")
        out += lines
    return out


extra = {"pages": {}, "boxes": {}, "choices": {}}
for n, pages in MESSAGES.items():
    lines = wrap_pages(pages, PER)
    introx.dialog_text = lambda name, lines=lines: {"per_page": PER, "left": LEFT, "top": TOP, "lines": lines}
    imgs = introx.dialog_pages(font, "DIALOG_%d" % n)
    for i, page in enumerate(imgs):
        box = page.getbbox()
        if box:
            page = page.crop(box)
        page.save(os.path.join(TEXD, "dlg_%d_%d.png" % (n, i + 1)))
        if i == 0:
            extra["boxes"][n] = [b / K for b in box] if box else [0, 0, 320, 240]
    extra["pages"][n] = len(imgs)
    if "//" in lines[-1]:
        # (the arrow by each answer, as dialogx.py places a question's)
        last = len(lines) - (len(imgs) - 1) * PER
        o = TOP + 2 - 16 * last
        extra["choices"][n] = [LEFT + 9, LEFT + 9 + 56, 240 - (o + 8) + 4]
    for ln in lines:
        if line_width(ln) > LINE_MAX + 4:
            print("!! too wide in", n, repr(ln))
    print(n, len(imgs), "pages:", lines)


def lua(v):
    if isinstance(v, dict):
        return "{ " + ", ".join("[%s] = %s" % (k, lua(x)) if isinstance(k, int) else "%s = %s" % (k, lua(x)) for k, x in v.items()) + " }"
    if isinstance(v, list):
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    return repr(round(v, 3)) if isinstance(v, float) else str(v)


# Times drawn into a box when it comes up (dialog.lua's `fill`): each letter they use, one picture apiece in the
# box's own lettering - dlg_glyph_<name>.png, 8x16 of the game's pixels - and how far each moves the next on; the
# seconds' mark (") two of the apostrophes, the font has none of its own. And where a message's times go: x after the
# longest of its labels, the top of each line.
GLYPHS = {"d%d" % i: str(i) for i in range(10)}
GLYPHS.update({"apos": "'", "dot": ".", "colon": ":"})
adv = {}
for name, ch in GLYPHS.items():
    code = font.encode(ch)[0]
    c = Image.new("RGBA", (8 * K, 16 * K), (0, 0, 0, 0))
    font.draw(c, 0, 0, ch, (255, 255, 255))
    c.save(os.path.join(TEXD, "dlg_glyph_%s.png" % name))
    adv[name] = font.widths[code]
c = Image.new("RGBA", (8 * K, 16 * K), (0, 0, 0, 0))
font.draw(c, 0, 0, "'", (255, 255, 255))
font.draw(c, 2, 0, "'", (255, 255, 255))
c.save(os.path.join(TEXD, "dlg_glyph_quote.png"))
adv["quote"] = adv["apos"] + 2
extra["glyphs"] = adv
FILLS = {9006: ["Old time:", "New time:"], 9010: ["Stars in this game:"], 9011: ["Stars in this game:"],
         9012: ["Stars in this game:"], 9013: ["Stars in this game:"]}
extra["fills"] = {}
for n, labels in FILLS.items():
    scratch = Image.new("RGBA", (320 * K, 240 * K), (0, 0, 0, 0))
    x = max(font.draw(scratch, LEFT, 0, lab, (255, 255, 255)) for lab in labels) + font.widths[font.codes[" "]]
    extra["fills"][n] = {"x": float(x), "y": [float(240 - (TOP - 2 - 16 * i)) for i in range(len(labels))]}
    print("fills", n, extra["fills"][n])

with open(os.path.join(DATA, "dialogs_extra.lua"), "w", encoding="utf-8") as f:
    f.write("-- the mod's own messages (tools/race_dialogs.py), with data/dialogs.lua's\nreturn %s\n" % lua(extra))
print("written dialogs_extra.lua")
