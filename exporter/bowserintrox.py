"""Bowser's words when Mario walks into his arena (camera.c bowser_fight_intro_dialog: DIALOG_067 in the Dark World,
092 in the Fire Sea, 093 in the Sky), as the game's dialog box shows them, one picture per page:
textures/bowser_dialog_<stage>_<n>.png; and his words when beaten (bowser_dead_default_stage_ending: DIALOG_119, 120,
121) as textures/bowser_beaten_<stage>_<n>.png. Prints how many pages each has.
Usage: python bowserintrox.py   (SM64_DECOMP and SM64_OUT as for build_all.py)"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import introx

os.makedirs(introx.TEXD, exist_ok=True)
font = introx.Font()
for stage, dialog in (("bitdw", "DIALOG_067"), ("bitfs", "DIALOG_092"), ("bits", "DIALOG_093")):
    pages = introx.dialog_pages(font, dialog)
    for n, page in enumerate(pages):
        page.save(os.path.join(introx.TEXD, "bowser_dialog_%s_%d.png" % (stage, n + 1)))
    print(stage, dialog, len(pages), "pages")
# and his words when he is beaten and Mario walks up to him (sBowserDefeatedDialogText: 119, 120, 121)
for stage, dialog in (("bitdw", "DIALOG_119"), ("bitfs", "DIALOG_120"), ("bits", "DIALOG_121")):
    pages = introx.dialog_pages(font, dialog)
    for n, page in enumerate(pages):
        page.save(os.path.join(introx.TEXD, "bowser_beaten_%s_%d.png" % (stage, n + 1)))
    print(stage, dialog, len(pages), "pages (beaten)")
