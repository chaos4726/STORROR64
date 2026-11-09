#!/usr/bin/env python3
"""Mario 64's Koopa shell (actors/koopa_shell, koopa_shell_geo), the one lying under water in DDD and JRB
(koopa_shell_underwater.inc.c): grabbed while swimming, he swims fast with it. Writes data/actor_koopa_shell.lua and
its textures. Usage: python shellx.py   (SM64_DECOMP and SM64_OUT as for build_all.py)"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_all as B
import introx
import sm64x as X

TEXD, DATA = introx.TEXD, introx.DATA
os.makedirs(TEXD, exist_ok=True)
os.makedirs(DATA, exist_ok=True)
act = B.S.export_actor(B.db, 'koopa_shell_geo', [], B.textures)
X.write_lua(os.path.join(DATA, 'actor_koopa_shell.lua'), act)
print('textures copied:', X.copy_textures(B.textures, TEXD))
