#!/usr/bin/env python3
"""Mario 64's mist puff (actors/mist, mist_geo: a 50-unit square of the soft white mist picture), for the clouds Lakitu
rides (cloud.inc.c bhvCloudPart: five puffs, billboards). Writes data/actor_mist.lua and its texture.
Usage: python mistx.py   (SM64_DECOMP and SM64_OUT as for build_all.py)"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_all as B
import introx
import sm64x as X

TEXD, DATA = introx.TEXD, introx.DATA
os.makedirs(TEXD, exist_ok=True)
os.makedirs(DATA, exist_ok=True)
act = B.S.export_actor(B.db, 'mist_geo', [], B.textures)
X.write_lua(os.path.join(DATA, 'actor_mist.lua'), act)
print('textures copied:', X.copy_textures(B.textures, TEXD))
