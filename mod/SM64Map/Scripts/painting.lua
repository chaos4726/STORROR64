-- The castle's paintings as Mario 64 has them (2026-10-16: "you need to add the wave effect to the painting and also
-- the camera locking onto it", "also make the painting deeper so you go into instead of sticking out").
--   The ripple (paintings.c): each painting is a grid that waves - a cosine ring spreading from where it was set off,
--   z = mag * cos(rate * 2pi * (timer - distance / dispersion)), its magnitude dying away by `decay` a frame; the
--   edges stay put. Passing in front of a painting sets off its small ripple from the quarter nearest him, at his
--   height (RIPPLE_TRIGGER_PROXIMITY); DDD's and HMC's ripple all the time (RIPPLE_TRIGGER_CONTINUOUS); going in sets
--   off the big one. Every painting's values are the decomp's (data/paint_ripples.lua, X:/mashup-work/paintx.py).
--   The waves are shaded as the painting's light does (ambient 0x50, a light from the front, above, right).
--   The camera (camera.c cutscene_enter_painting): on the way in it glides to a spot in front of the painting's
--   middle (1000 units for a 614 painting), looking at its middle, and slowly zooms in (field of view to 20, 0.3
--   a frame) while the white comes up. Then the star select (game.lua), which takes the view.
--   Going in: he is carried on through the picture, all of him behind it, instead of held half out of it.
local lib = require("lib")
local log = lib.log
local OFFSET = lib.OFFSET
local M = {}

local N = 20                    -- cells each way of a painting's grid
local PAINTING_SIZE = 614.0     -- (Mario 64's painting mesh runs 0..614; a painting's size scales it)
local U = 0.75                  -- cm per Mario 64 unit
local LIGHT = { 0.57735, 0.57735, 0.57735 }     -- (its light: right, up, out of the picture)
local AMBIENT = 0x50 / 255.0
local NEAR = 3000.0             -- cm: a painting further than this from him is left still (continuous ones too)
local IN_FRONT = 0.8            -- (the floor in front that sets a painting off: this many of its widths out)
-- cm: going in, his middle ends this far behind the picture. 60 left his limbs - a vault's legs, an arm - through the
-- picture: the paintings' hollows (game.lua G.recess_paintings) take him in once his middle is 60 behind, and he
-- stood there, half out: "somethings stopping the player from going deeper into the painting because I can see the
-- player sticking out", 2026-10-29. On past the sill, into the hollow behind it: none of him to be seen.
local BEHIND = 150.0
local IN_TIME = 0.3             -- s to carry him through

local RIPPLES = nil
local st = nil                  -- this scene's: { world, list = { painting records }, rippling = record or nil }
local cam = nil                 -- the camera on the way in: { actor, pos, focus, vfov, target, centre, aspect }
local glide = nil               -- him carried in: { from, to, t }

local function vsub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function vdot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function vlen(a) return math.sqrt(vdot(a, a)) end

-- where the painting is now (the DDD painting slides back: its actor is moved)
local function shift(r)
    local sx, sy, sz = 0.0, 0.0, 0.0
    if r.moves then
        pcall(function()
            local l = r.q.actor:K2_GetActorLocation()
            sx, sy, sz = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z
        end)
    end
    return sx, sy, sz
end

-- him in the painting's own terms: across (0..1), up its face (0..1), out in front of it (cm), from scene cm
local function local_of(r, x, y, z)
    local sx, sy, sz = shift(r)
    local d = { x - (r.c0[1] + sx), y - (r.c0[2] + sy), z - (r.c0[3] + sz) }
    return vdot(d, r.u) / r.l1, vdot(d, r.v) / r.l2, vdot(d, r.n)
end

local function rest_mesh(r)
    local verts, cols = {}, {}
    for j = 0, N do
        for i = 0, N do
            local a, b = i / N, j / N
            verts[#verts + 1] = { X = r.c0[1] + r.e1[1] * a + r.e2[1] * b + r.n[1] * 2.0,
                                  Y = r.c0[2] + r.e1[2] * a + r.e2[2] * b + r.n[2] * 2.0,
                                  Z = r.c0[3] + r.e1[3] * a + r.e2[3] * b + r.n[3] * 2.0 }
            cols[#cols + 1] = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
        end
    end
    return verts, cols
end

-- (a painting's picture drawn larger on it, its middle only: 2 shows the middle half - HMC's on the basement floor
-- and DDD's on its wall, "the hazy maze cave texture on the entrance to the level needs zoomed a bit same with dire
-- dire docks", then "zoom them again", "zoom again", 2026-11-07)
M.ZOOM = { hmc = 2.0, ddd = 2.0 }

-- its grid instead of the flat picture: q is game.lua's painting (actor, pt, c0, e1, e2, l1, l2)
function M.add(world, q, pmc)
    RIPPLES = RIPPLES or lib.load_data("data.paint_ripples") or {}
    local here = world:GetAddress()
    if not st or st.world ~= here then st = { world = here, list = {} } end
    local pt = q.pt
    local n = { pt.normal[1], pt.normal[2], pt.normal[3] }
    local r = { q = q, pmc = pmc, c0 = q.c0, e1 = q.e1, e2 = q.e2, l1 = q.l1, l2 = q.l2, n = n,
                u = { q.e1[1] / q.l1, q.e1[2] / q.l1, q.e1[3] / q.l1 }, v = { q.e2[1] / q.l2, q.e2[2] / q.l2, q.e2[3] / q.l2 },
                p = RIPPLES[pt.name] or RIPPLES.bob, name = pt.name, state = 0, moves = pt.name == "ddd",
                floor = math.abs(n[3]) > 0.7 }
    r.size = r.p.size                                   -- (Mario units)
    local verts, cols = rest_mesh(r)
    local idx, nrms, uvs = {}, {}, {}
    local zoom = (M.ZOOM and M.ZOOM[pt.name]) or 1.0
    for j = 0, N do
        for i = 0, N do
            nrms[#nrms + 1] = { X = n[1], Y = n[2], Z = n[3] }
            uvs[#uvs + 1] = { X = 0.5 + (i / N - 0.5) / zoom, Y = 0.5 + (0.5 - j / N) / zoom }
        end
    end
    for j = 0, N - 1 do
        for i = 0, N - 1 do
            local a, b = j * (N + 1) + i, j * (N + 1) + i + 1
            local c, d = (j + 1) * (N + 1) + i + 1, (j + 1) * (N + 1) + i
            -- (both ways round, as the flat picture was: the material shows one side)
            for _, t in ipairs({ a, b, c, a, c, d, a, c, b, a, d, c }) do idx[#idx + 1] = t end
        end
    end
    lib.create_section(pmc, 0, verts, idx, nrms, uvs, cols, false)
    local mid = lib.get_mid(world, "opaque", pt.texture)
    if mid then pmc:SetMaterial(0, mid) end
    st.list[#st.list + 1] = r
    q.ripple = r
    return true
end

-- set it rippling: kind "passive" or "entry", from (rx, ry) on its face (Mario units, 0..size)
local function start(r, kind, rx, ry, keep_timer)
    local k = kind == "entry" and 2 or 1
    r.mag, r.decay, r.rate, r.disp = r.p.mag[k], r.p.decay[k], r.p.rate[k], r.p.disp[k]
    r.state = k
    r.rx, r.ry = rx, ry
    if not keep_timer then r.timer = 0.0 end
    r.timer = r.timer or 0.0
    -- (one painting ripples at a time; the always-rippling ones go on)
    if st then
        for _, o in ipairs(st.list) do
            if o ~= r and o.state ~= 0 and o.p.trigger == "proximity" then o.state, o.flat = 0, false end
        end
    end
    r.flat = false
end

-- (its points and colours kept on it and filled in again each time, not made anew: a rippling painting made 157 KB of
-- tables a frame, and the collector's sweeps through that came as hitches of 20 ms every second or two - "why is it so
-- incredibly laggy?", 2026-11-06)
local function draw(r)
    r.vb, r.cb, r.zb = r.vb or {}, r.cb or {}, r.zb or {}
    local verts, cols, zs = r.vb, r.cb, r.zb
    local scale = r.size / PAINTING_SIZE
    for j = 0, N do
        for i = 0, N do
            local z = 0.0
            if r.state ~= 0 and i > 0 and i < N and j > 0 and j < N then
                local px, py = i / N * r.size, j / N * r.size
                local dist = math.sqrt((px - r.rx) ^ 2 + (py - r.ry) ^ 2)
                local rd = dist / r.disp
                if r.timer >= rd then z = r.mag * math.cos(r.rate * 2.0 * math.pi * (r.timer - rd)) end
            end
            zs[j * (N + 1) + i] = z * scale * U          -- cm, out of the picture
        end
    end
    local du, dv = r.l1 / N, r.l2 / N
    local flat = AMBIENT + LIGHT[3]
    local k = 0
    for j = 0, N do
        for i = 0, N do
            local a, b = i / N, j / N
            local z = zs[j * (N + 1) + i]
            k = k + 1
            local v = verts[k]
            if not v then v = {}; verts[k] = v end
            v.X = r.c0[1] + r.e1[1] * a + r.e2[1] * b + r.n[1] * (2.0 + z)
            v.Y = r.c0[2] + r.e1[2] * a + r.e2[2] * b + r.n[2] * (2.0 + z)
            v.Z = r.c0[3] + r.e1[3] * a + r.e2[3] * b + r.n[3] * (2.0 + z)
            -- (its slope here, and the light on it: the painting at rest is as it always was)
            local zx = (zs[j * (N + 1) + math.min(N, i + 1)] - zs[j * (N + 1) + math.max(0, i - 1)]) / (2.0 * du)
            local zy = (zs[math.min(N, j + 1) * (N + 1) + i] - zs[math.max(0, j - 1) * (N + 1) + i]) / (2.0 * dv)
            local nl = math.sqrt(zx * zx + zy * zy + 1.0)
            local lit = AMBIENT + math.max(0.0, (-zx * LIGHT[1] - zy * LIGHT[2] + LIGHT[3]) / nl)
            local c = math.max(0.35, math.min(1.0, lit / flat))
            local cc = cols[k]
            if not cc then cc = { A = 1.0 }; cols[k] = cc end
            cc.R, cc.G, cc.B = c, c, c
        end
    end
    lib.update_section(r.pmc, 0, verts, cols)
end

-- ------------------------------------------------------------ the camera on the way in
local function look(from, to)
    local dx, dy, dz = to[1] - from[1], to[2] - from[2], to[3] - from[3]
    return { Pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0.0 }
end
local function near(a, k) return 1.0 - (1.0 - k) ^ a end      -- (Mario 64's "this much of the way a frame", for dt)

local function cam_start(r, pawn)
    local pc, world = lib.controller(), lib.world()
    if not (pc and world) then return end
    local pcm = pc.PlayerCameraManager
    local l, rot, fov = pcm:GetCameraLocation(), pcm:GetCameraRotation(), pcm:GetFOVAngle()
    local a = lib.camera(world, "painting", l, rot)
    if not a then return end
    local sx, sy, sz = shift(r)
    local c = { r.c0[1] + sx + (r.e1[1] + r.e2[1]) / 2, r.c0[2] + sy + (r.e1[2] + r.e2[2]) / 2, r.c0[3] + sz + (r.e1[3] + r.e2[3]) / 2 }
    local back = r.size * 1000.0 / PAINTING_SIZE * U        -- (focusOffset z: -(size * 1000 / 2) / 307)
    local aspect = 16.0 / 9.0
    pcall(function()
        local vs = lib.viewport_size and lib.viewport_size()
        if vs and vs.X > 0 and vs.Y > 0 then aspect = vs.X / vs.Y end
    end)
    local fx, fy, fz = math.cos(math.rad(rot.Pitch)) * math.cos(math.rad(rot.Yaw)), math.cos(math.rad(rot.Pitch)) * math.sin(math.rad(rot.Yaw)), math.sin(math.rad(rot.Pitch))
    local here = { l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z }
    cam = { actor = a, pos = here, focus = { here[1] + fx * 500.0, here[2] + fy * 500.0, here[3] + fz * 500.0 },
            target = { c[1] + r.n[1] * back, c[2] + r.n[2] * back, c[3] + r.n[3] * back }, centre = c, aspect = aspect,
            vfov = math.deg(2.0 * math.atan(math.tan(math.rad(fov) / 2.0) / aspect)) }
    pcall(function() a.CameraComponent:SetFieldOfView(fov) end)
    pcall(function()
        local cc = a.CameraComponent
        cc.PostProcessBlendWeight = 1.0
        cc.PostProcessSettings.bOverride_MotionBlurAmount = true
        cc.PostProcessSettings.MotionBlurAmount = 0.0
    end)
    pcall(function() pc:SetViewTargetWithBlend(a, 0.0, 0, 0.0, false) end)
end

local function cam_tick(dt)
    local c = cam
    if not c then return end
    local ok = pcall(function() return c.actor:IsValid() end) and c.actor:IsValid()
    if not ok then cam = nil; return end
    local f = dt * 30.0
    local kf, kxy, kz = near(f, 0.1), near(f, 0.2), near(f, 0.1)
    for i = 1, 3 do c.focus[i] = c.focus[i] + (c.centre[i] - c.focus[i]) * kf end
    c.pos[1] = c.pos[1] + (c.target[1] - c.pos[1]) * kxy
    c.pos[2] = c.pos[2] + (c.target[2] - c.pos[2]) * kxy
    c.pos[3] = c.pos[3] + (c.target[3] - c.pos[3]) * kz
    c.vfov = math.max(20.0, c.vfov - 0.3 * f)
    local h = math.deg(2.0 * math.atan(math.tan(math.rad(c.vfov) / 2.0) * c.aspect))
    pcall(function()
        c.actor:K2_TeleportTo({ X = c.pos[1] + OFFSET.X, Y = c.pos[2] + OFFSET.Y, Z = c.pos[3] + OFFSET.Z }, look(c.pos, c.focus))
        c.actor.CameraComponent:SetFieldOfView(h)
    end)
end

-- the view back on him if it is still ours (the star select takes it itself; a scene going hands it back)
local function cam_release()
    local c = cam
    cam = nil
    if not c then return end
    pcall(function()
        local pc, pawn = lib.controller(), lib.pawn()
        if pc and pawn and pc:GetViewTarget():GetAddress() == c.actor:GetAddress() then
            pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false)
        end
    end)
end

-- ------------------------------------------------------------ going in
-- he has reached the strip behind a painting into `scene`: its big ripple from where he went in, the camera, and him
-- on through the picture
function M.enter(pawn, scene)
    if not (st and pawn) then return end
    local l = pawn:K2_GetActorLocation()
    local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z
    local best, bd = nil, math.huge
    for _, r in ipairs(st.list) do
        if r.q.pt.target == scene or r.name == scene then
            local a, b, d = local_of(r, x, y, z)
            local off = math.abs(d) + math.max(0.0, -a, a - 1.0) * r.l1 + math.max(0.0, -b, b - 1.0) * r.l2
            if off < bd then best, bd = r, off end
        end
    end
    local r = best
    if not r or bd > 400.0 then return end
    local a, b, d = local_of(r, x, y, z)
    local half = 86.0
    if r.floor then
        start(r, "entry", math.max(0.0, math.min(1.0, a)) * r.size, math.max(0.0, math.min(1.0, b)) * r.size, r.state == 1)
    else
        -- (the quarter nearest where he went in - left, middle or right - at his height: painting_nearest_4th, MARIO_Y)
        local third = math.max(0, math.min(2, math.floor(a * 3.0)))
        local feet = (b * r.l2 - half) / U                      -- (his feet up its face, Mario units)
        start(r, "entry", (third + 1) / 4.0 * r.size, math.max(0.0, math.min(r.size, feet + 50.0)), r.p.trigger == "continuous")
        cam_start(r, pawn)
        -- (on through the picture: all of him behind it)
        local deep = d + BEHIND
        if deep > 0.0 then
            glide = { pawn = pawn, from = { l.X, l.Y, l.Z }, to = { l.X - r.n[1] * deep, l.Y - r.n[2] * deep, l.Z - r.n[3] * deep }, t = 0.0 }
        end
    end
    log("painting %s: in, %.0f cm in front of it", r.name, d)
end

local function glide_tick(dt)
    local g = glide
    if not g then return end
    g.t = math.min(IN_TIME, g.t + dt)
    local k = g.t / IN_TIME
    k = 1.0 - (1.0 - k) * (1.0 - k)                     -- (easing out: his jump's way on, slowing in the picture)
    pcall(function()
        g.pawn:K2_SetActorLocation({ X = g.from[1] + (g.to[1] - g.from[1]) * k, Y = g.from[2] + (g.to[2] - g.from[2]) * k,
                                    Z = g.from[3] + (g.to[3] - g.from[3]) * k }, false, {}, true)
        g.pawn.CharacterMovement:SetMovementMode(0, 0)
    end)
    if g.t >= IN_TIME then glide = nil end
end

-- ------------------------------------------------------------ every frame
M.DRAW_STEP = 1.0 / 30.0
function M.update(dt, pawn)
    glide_tick(dt)
    cam_tick(dt)
    if not (st and pawn) then return end
    local G = package.loaded["game"]
    local l = pawn:K2_GetActorLocation()
    local x, y, z = l.X - OFFSET.X, l.Y - OFFSET.Y, l.Z - OFFSET.Z
    local f = dt * 30.0
    for _, r in ipairs(st.list) do
        local a, b, d = local_of(r, x, y, z)
        local far = (math.abs(d) > NEAR) or a < -NEAR / r.l1 or a > 1.0 + NEAR / r.l1
        -- what sets it off
        if r.p.trigger == "continuous" then
            if r.state == 0 and not far then start(r, "passive", r.size / 2.0, r.size / 2.0) end
        elseif not r.floor then
            local third = nil
            if d > 0.0 and d < r.l1 * IN_FRONT and a > -0.1 and a < 1.1 and b > -0.8 and b < 1.0 then
                third = math.max(0, math.min(2, math.floor(a * 3.0)))
            end
            if third and third ~= r.third and r.state == 0 then
                local feet = (b * r.l2 - (G and G.half or 86.0)) / U
                start(r, "passive", (third + 1) / 4.0 * r.size, math.max(0.0, math.min(r.size, feet + 50.0)))
            end
            r.third = third
        end
        -- the ripple on
        if r.state ~= 0 then
            r.mag = r.mag * r.decay ^ f
            r.timer = r.timer + f
            if r.p.trigger == "proximity" then
                if r.mag <= 1.0 then r.state = 0 end
            elseif r.state == 2 and r.mag <= r.p.mag[1] then
                start(r, "passive", r.rx, r.ry, true)
            end
            -- (drawn at Mario 64's 30 a second, not every frame - its ripple moves no faster)
            r.dacc = (r.dacc or 0.0) + dt
            if (not far or r.state == 2) and r.dacc >= M.DRAW_STEP then
                r.dacc = r.dacc % M.DRAW_STEP
                pcall(draw, r)
            end
        elseif not r.flat then
            r.flat = true
            pcall(draw, r)
        end
    end
end

-- whether the camera on the way in has the view (first person leaves it be)
function M.holding() return cam ~= nil end

-- the scene going: the view back to him, nothing kept (the actors are game.lua's)
function M.clear()
    cam_release()
    glide = nil
    st = nil
end

function M.forget() cam, glide, st = nil, nil, nil end

return M
