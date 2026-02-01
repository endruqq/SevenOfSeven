-- SevenOfSevens
-- Refactored Main Entry Point

local utf8 = require("utf8")
local constants = require("constants")
local utils = require("utils")
local Shop = require("src.Shop")
local Wheel = require("src.Wheel") -- Keeping raw Wheel requirement for now? Or can we remove?
local ClockWheel = require("src.ClockWheel")
local Particles = require("src.Particles")
local SkillTree = require("src.SkillTree")
local MainRoulette = require("src.modules.MainRoulette")
local PlinkoBoard = require("src.PlinkoBoard")
local SignalSystem = require("src.SignalSystem") -- NEW
local PrestigeManager = require("src.PrestigeManager") -- NEW: Prestige System
local UpgradeNode = require("src.nodes.UpgradeNode")
local ArtifactNode = require("src.nodes.ArtifactNode")
local QuestManager = require("src.QuestManager") -- NEW: Quest System
local LogicGate = require("src.modules.LogicGate") -- NEW: Logic Gates

-- CONSTANTS ALIASES
local V_WIDTH = constants.V_WIDTH
local V_HEIGHT = constants.V_HEIGHT
local colors = constants.colors

-- UTILS ALIASES
local lerp = utils.lerp
local printBold = utils.printBold
local drawDashedLine = utils.drawDashedLine
local drawChevronPath = utils.drawChevronPath
local drawFluidLine = utils.drawFluidLine
local getOctagonVertices = utils.getOctagonVertices
-- Shaders
local wavyShader
local frameCanvas 
local wavyShaderCode = [[
    extern number time;
    extern number intensity;
    vec3 hsv2rgb(float h, float s, float v) {
        vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        vec3 p = abs(fract(vec3(h) + K.xyz) * 6.0 - K.www);
        return v * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), s);
    }
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec2 p = texture_coords;
        float wave1 = sin(p.y * 8.0 + time * 1.5) * 0.012;
        float wave2 = sin(p.y * 13.0 + time * 0.8) * 0.008;
        float wave3 = cos(p.x * 11.0 + time * 1.1) * 0.010;
        float wave4 = cos(p.x * 7.0 + time * 0.9) * 0.006;
        p.x = p.x + (wave1 + wave2) * intensity;
        p.y = p.y + (wave3 + wave4) * intensity;
        p = clamp(p, 0.0, 1.0);
        vec4 texColor = Texel(texture, p);
        return texColor * color;
    }
]]

local vignetteShader
local vignetteShaderCode = [[
    extern vec2 screenSize;
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec2 uv = (screen_coords / screenSize) * 2.0 - 1.0;
        float dist = length(uv);
        float vignette = smoothstep(0.7, 1.4, dist);
        vec3 darkColor = vec3(0.0, 0.0, 0.02);
        return vec4(darkColor, vignette * 0.5); 
    }
]]
game = {
    gold = 0,
    tokensPerSecond = 0,
    rollCost = 0, -- FREE ROLL
    combo = 0,
    essence = 0, 
    data = 0, -- NEW: Data Resource
    energy = { max = 10, used = 0 },
    
    wheel = nil, -- Deprecated? Or mapped to MainRoulette.wheel?
    mainRoulette = nil, -- The Module instance
    modules = {}, -- List of all modules on board
    
    baseCooldown = 7.0, 
    currentCooldown = 7.0,
    cooldownTimer = 0, 
    
    spinSpeedMult = 1.0, 
    durationMult = 1.0, 
    
    upgradeLevel = 0, 
    luckyLevel = 0,
    
    sevenBaseValue = 1,
    sevenValueLevel = 0,
    
    comboMultBonus = 0, 
    comboMultLevel = 0,
    
    jackpotIntensity = 0.0, 
    
    hypeLevel = 0.0, 
    targetHypeLevel = 0.0,
    screenShake = {x = 0, y = 0},
    
    clockUnlocked = false,
    clockStreak = 0, 
    clockUnlocked = false,
    clockStreak = 0, 
    clockWheels = {}, 
    plinkoBoards = {}, -- New list for multiple boards
    clockSpeedUpgrade = 0, 
    
    popups = {}, 
    
    history = {}, 
    particles = {}, 
    
    inputActive = false,
    inputText = "",
    
    draggingModule = nil, -- For drag & drop
    draggingClock = nil, -- For Clock dragging
    
    -- Camera State (for Game view zoom/pan - infinite world like Skill Tree)
    camera = {
        x = 0, -- Pan offset X (world center at 0,0)
        y = 0, -- Pan offset Y
        zoom = 1.0, -- Default zoom (0.5 to 2.0 range)
        dragging = false
    },
    
    -- Cinematic State
    cinematic = {
        active = false,
        timer = 0,
        duration = 10.0, 
        text = "JACKPOT.. but let it roll",
        displayedText = "",
        charTimer = 0,
        charInterval = 0.15,
        overlayAlpha = 0,
        targetAlpha = 0.85,
        hasTriggeredSandbox = false -- Flag to trigger zoom out once
    },

    skillTree = {
        {id="root", x=0, y=0, name="Big Bang", desc="Where it all began.", cost=0, parents={}, unlocked=true, purchased=true, effect=nil},
        
        -- Speed Branch (Up)
        {id="speed_1", x=0, y=-150, name="Momentum", desc="Spin Speed +10%", cost=1, type="speed", parents={"root"}, effect=function() buySpeed() end},
        
        -- Luck Branch (Down)
        {id="luck_1", x=0, y=150, name="Karma", desc="Luck +5%", cost=1, type="luck", parents={"root"}, effect=function() buyLuck() end},
        
        -- Value Branch (Left)
        {id="value_1", x=-150, y=0, name="Alchemy", desc="7 Payout +1", cost=1, type="value", parents={"root"}, effect=function() buySevenValue() end},
        
        -- Combo Branch (Right - moved clocks further)
        {id="combo_1", x=150, y=0, name="Synergy", desc="Combo Mult +0.2x", cost=1, type="combo", parents={"root"}, effect=function() buyComboMult() end},
        
        -- Clock Branch (Far Right)
        {id="clock_unlock", x=300, y=0, name="Time Keeper", desc="Unlock Sidebar Clocks", cost=1, type="clock_unlock", parents={"combo_1"}, 
         effect=function() 
             game.clockUnlocked = true 
         end},


        {id="clock_speed", x=450, y=0, name="Chronos", desc="Clock Speed +10%", cost=1, type="clock_speed", parents={"clock_unlock"}, effect=function() upgradeClockSpeed() end}
    },
    
    skillCam = {
        x = 0, y = 0, 
        zoom = 1.0,
        dragging = false,
        lastMx = 0, lastMy = 0
    },
    
    -- Viewport 
    scale = 1,
    tx = 0,
    ty = 0,
    
    -- Build Mode State
    buildMode = false,
    wiring = nil, -- {active=true, startOutlet={type="main", index=1, x=, y=}}

    -- Plinko State
    plinko = nil,
    waitingForPlinko = false,
    lastWinAmount = 0,
    
    -- Shop Drawer State [NEW]
    shop = {
        open = false,
        heightRatio = 0.0, -- 0.0 to 1.0 (animating)
        targetHeight = 0.3, -- 30% of screen
        activeTab = "NODES",
        hoverToggle = false
    },
    
    -- Active Nodes [NEW]
    nodes = {},
    
    -- Shop Upgrades (Replaces Nodes)
    upgrades = {
        speed = {id="speed", name="Speed", level=0, baseCost=10, costMult=1.5, desc="Increases Spin Speed (+5%)"},
        luck = {id="luck", name="Luck", level=0, baseCost=15, costMult=1.6, desc="Increases Crit Chance"},
        multi = {id="multi", name="Multiplier", level=0, baseCost=50, costMult=2.0, desc="Global Multiplier (+0.25x)"},
        auxSpeed = {id="auxSpeed", name="Aux Speed", level=0, baseCost=20, costMult=1.4, desc="Clock/Plinko Speed (+5%)"},
        autoSpin = {id="autoSpin", name="Hand of a Gambler", level=0, baseCost=100, costMult=2.5, desc="Auto-Spin Main Roulette"},
        energy = {id="energy", name="Power Supply", level=0, baseCost=20, costMult=1.4, desc="Increases Max Energy (+10)"}
    }
}

local btnRoll = { x=0, y=0, w=200, h=60, text="ROLL" }
local btnBuild = { x=V_WIDTH - 80, y=80, w=60, h=60, icon="wrench" } -- Top Right

-- HELPERS

local function applyNodeStats(game)
    -- Reset Base Stats
    game.spinSpeedMult = 1.0
    game.luckyLevel = 1 
    -- Note: Payout Mult is calculated on win usually, but we can store global mult
    game.globalPayoutMult = 1.0
    
    -- Main Roulette Node
    -- Find Main Roulette Module (Index 1 usually, or search by type)
    if game.modules then
        local mainMod = game.modules[1] -- Assumption: First module is Main
        if mainMod and mainMod.nodeConnection then
            local conn = mainMod.nodeConnection
            local node = conn.source or conn -- Support both {source=node} and direct node
            local stats = node.stats
            
            if stats then
                -- Speed: +20% per level
                game.spinSpeedMult = 1.0 + (stats.speed.val * 0.2)
                -- Multiplier: +0.2x per level
                game.globalPayoutMult = 1.0 + (stats.multi.val * 0.2)
                -- Luck: +1 Level per level
                game.luckyLevel = 1 + stats.luck.val
            end
        end
    end
    
    -- Clock Wheels Node (Individual stats? Or they use global?)
    for _, cw in ipairs(game.clockWheels) do
        if cw.nodeConnection then
            local conn = cw.nodeConnection
            local node = conn.source or conn
            local stats = node.stats
            
            if stats then
                cw.speedMult = 1.0 + (stats.speed.val * 0.2)
                cw.payoutMult = 1.0 + (stats.multi.val * 0.2)
                -- Luck ignored for Clocks
            else
                cw.speedMult = 1.0
                cw.payoutMult = 1.0
            end
        else
            cw.speedMult = 1.0
            cw.payoutMult = 1.0
        end
    end
end

function getMainOutlets()
    local cx, cy = V_WIDTH/2, V_HEIGHT/2
    local w, h = 300, 300 -- approx frame size
    local offset = 140 -- from center
    local outlets = {
        {x = cx - offset, y = cy, type="main", index=1, isOutput=true, obj=game.mainRoulette, parent=game.mainRoulette}, -- Left
        {x = cx + offset, y = cy, type="main", index=2, isOutput=true, obj=game.mainRoulette, parent=game.mainRoulette}  -- Right
    }
    
    -- Bottom Outlet (Horizontal) - Always available
    local bx = V_WIDTH / 2
    local by = V_HEIGHT - 60
    table.insert(outlets, {x = bx, y = by, type="main", index=3, horizontal=true, isOutput=true, obj=game.mainRoulette, parent=game.mainRoulette}) 
    
    return outlets
end

function getClockOutlets(cw)
    local outlets = {}
    local r = 140 -- Radius for outlet centers (same for all 4)
    local lineLen = 15 -- Half-length of tangential line
    
    -- Explicit cardinal positions for perfect symmetry
    local positions = {
        {dx = r, dy = 0, name = "Right", lineVertical = true},   -- Right
        {dx = 0, dy = r, name = "Bottom", lineVertical = false}, -- Bottom
        {dx = -r, dy = 0, name = "Left", lineVertical = true},   -- Left
        {dx = 0, dy = -r, name = "Top", lineVertical = false}    -- Top
    }
    
    for i, pos in ipairs(positions) do
        local cx = cw.x + pos.dx
        local cy = cw.y + pos.dy
        
        -- Tangential line (perpendicular to radius)
        local x1, y1, x2, y2
        if pos.lineVertical then
            -- Vertical line for Left/Right outlets
            x1, y1 = cx, cy - lineLen
            x2, y2 = cx, cy + lineLen
        else
            -- Horizontal line for Top/Bottom outlets
            x1, y1 = cx - lineLen, cy
            x2, y2 = cx + lineLen, cy
        end
        
        table.insert(outlets, {
            x = cx,
            y = cy,
            type = "clock",
            index = i,
            parent = cw,
            obj = cw, -- Generic object reference
            isInput = true,
            isOutput = true, -- Clocks are bidirectional
            x1 = x1, y1 = y1, x2 = x2, y2 = y2
        })
    end
    return outlets
end

function getPlinkoOutlets(plinko)
    if not plinko or not plinko.unlocked then return {} end
    
    local outlets = {}
    for _, o in ipairs(plinko.outlets) do
        local ox = plinko.x + o.x
        local oy = plinko.y + o.y
        table.insert(outlets, {
            x = ox,
            y = oy,
            type = "plinko_out",
            index = o.index,
            parent = plinko,
            obj = plinko,
            isOutput = true,
            isInput = true, -- NEW: Allow side/bottom sockets to accept signals (Bidirectional)
            horizontal = o.horizontal,
            angle = o.angle
        })
    end
    return outlets
end

function checkWireObstacles(game, x1, y1, x2, y2, ignoreSource, ignoreTarget)
    -- Check ALL Clocks including the source clock
    -- Wire should not pass through ANY clock body (even its own)
    for _, cw in ipairs(game.clockWheels) do
        -- Skip only the target clock (the one we're connecting TO)
        local skip = false
        if ignoreTarget and ignoreTarget == cw then skip = true end
        
        if not skip then
            -- Visual radius ~90, use 90 for detection (match visual)
            if utils.intersectSegmentCircle(x1, y1, x2, y2, cw.x, cw.y, 90) then
                return true -- Blocked by this clock (including source's own body)
            end
        end
    end
    
    -- Check Plinko Boards (AABB Intersection)
    for _, pb in ipairs(game.plinkoBoards) do
         -- Ignore if target?
         local skip = false
         if ignoreTarget and ignoreTarget == pb then skip = true end
         -- Plinko is rarely a source in a way that we'd ignore it for "pass through" unless wiring FROM it?
         -- If wiring FROM plinko output, we shouldn't block on itself.
         if ignoreSource and ignoreSource == pb then skip = true end

         if not skip then
             -- Simple Segment vs AABB intersection
             -- Bounds: [pb.x - w/2, pb.x + w/2], [pb.y, pb.y + h]
             -- Expand slightly for visual margin
             local margin = 0
             local left = pb.x - pb.w/2 - margin
             local right = pb.x + pb.w/2 + margin
             local top = pb.y - margin
             local bottom = pb.y + pb.h + margin
             
             -- Helper: Cohen-Sutherland or simple AABB check?
             -- Simply check if segment intersects any of the 4 lines?
             -- Or just use utils (if I had rect intersection).
             -- Let's just create a quick local helper or inline.
             
             -- Inline Segment-AABB:
             -- Liang-Barsky is best but complex to inline.
             -- Simple approach: Seg vs 4 lines.
             -- Even simpler: Use intersectSegmentCircle with radius covering the board?
             -- Plinko is 580x320. Rectangle.
             -- Circle will be inaccurate.
             
             -- Implementation: Closest Point on Segment to Rect Center? No.
             -- Just check intersection with 4 sides.
             local hit = false
             -- Top
             hit = hit or utils.intersectSegmentCircle(x1, y1, x2, y2, pb.x, top, 0) -- Circle R=0? No.
             
             -- Re-use utils.intersectSegmentCircle? No.
             -- Fallback: Check intersection with diagonals? No.
             
             -- Let's assume utils has NO rect intersection.
             -- Check 4 lines yourself?
             -- Actually, simple AABB overlap check is enough if we consider the wire as a thin AABB? No.
             -- Wire is a line segment.
             
             -- Check against box:
             local minX, maxX = math.min(x1, x2), math.max(x1, x2)
             local minY, maxY = math.min(y1, y2), math.max(y1, y2)
             
             -- AABB overlap first
             if maxX > left and minX < right and maxY > top and minY < bottom then
                 -- Possible intersection.
                 -- Since we just need ANY blocking, let's just return true if AABB overlaps?
                 -- That works if wires are axis aligned but they aren't.
                 -- Diagonal wire might miss the box but AABB hits.
                 
                 -- Accurate check:
                 -- Check intersection with any of 4 segments defining the box.
                 -- Box Segments: (left, top)-(right, top), (right, top)-(right, bottom), etc.
                 -- But we don't have intersectSegmentSegment.
                 -- We have intersectSegmentCircle.
                 
                 -- HACK: Approximate with 3 circles.
                 -- W=580. 3 Circles of R=100 distributed? Not enough.
                 -- W=580 is HUGE.
                 -- Maybe 3 Circles of R=160?
                 -- Left center, mid center, right center?
                 
                 local r = 160
                 local cy = pb.y + pb.h/2
                 if utils.intersectSegmentCircle(x1, y1, x2, y2, pb.x - 150, cy, 140) or
                    utils.intersectSegmentCircle(x1, y1, x2, y2, pb.x,       cy, 140) or
                    utils.intersectSegmentCircle(x1, y1, x2, y2, pb.x + 150, cy, 140) then
                     return true
                 end
             end
         end
    end
    
    -- ALWAYS check Main Wheel collision (wire cannot go through main body)
    local cx, cy = V_WIDTH/2, V_HEIGHT/2
    if utils.intersectSegmentCircle(x1, y1, x2, y2, cx, cy, 120) then
        return true -- Blocked by main wheel
    end
    
    return false
end

function getMouseGameCoords()
    local mx, my = love.mouse.getPosition()
    return (mx - game.tx) / game.scale, (my - game.ty) / game.scale
end

function getMouseWorldCoords()
    local gx, gy = getMouseGameCoords()
    if app.state ~= "GAME" then return gx, gy end
    
    local w, h = V_WIDTH, V_HEIGHT
    local cam = game.camera
    
    -- Inverse of Camera Transform from drawGame():
    -- Forward: translate(w/2,h/2) -> scale(zoom) -> translate(-w/2,-h/2) -> translate(cam.x,cam.y)
    -- Which means: screen = ((world + cam) - center) * zoom + center
    -- Inverse: world = (screen - center) / zoom + center - cam
    
    local wx = (gx - w/2) / cam.zoom + w/2 - cam.x
    local wy = (gy - h/2) / cam.zoom + h/2 - cam.y
    return wx, wy
end

-- CORE LOGIC

function calculateHype()
    local c = game.combo
    local target = 0
    if c >= 7 then target = 1.0
    elseif c >= 6 then target = 0.8
    elseif c >= 5 then target = 0.6
    elseif c >= 3 then target = 0.3
    end
    game.targetHypeLevel = target
end

function updateHype(dt)
    game.hypeLevel = lerp(game.hypeLevel, game.targetHypeLevel, 2 * dt)
    if game.hypeLevel > 0.5 then
        local shakeAmount = (game.hypeLevel - 0.5) * 5
        game.screenShake.x = (math.random() - 0.5) * shakeAmount
        game.screenShake.y = (math.random() - 0.5) * shakeAmount
    else
        game.screenShake.x = 0
        game.screenShake.y = 0
    end
end

function addToHistory(val)
    local cx = V_WIDTH / 2
    local spacing = 40 
    local newItem = {
        val = val,
        x = cx - 50, 
        targetX = cx, 
        scale = 0,
        targetScale = 1
    }
    table.insert(game.history, 1, newItem)
    local startX = cx - (#game.history * spacing / 2) + (spacing / 2)
    for i, item in ipairs(game.history) do
        item.targetX = startX + (i-1) * spacing 
    end
    while #game.history > 15 do table.remove(game.history) end
end

function updateHistory(dt)
    for i, item in ipairs(game.history) do
        item.x = lerp(item.x, item.targetX, 10 * dt)
        item.scale = lerp(item.scale, item.targetScale, 15 * dt)
    end
end

function drawHistory()
    local y = V_HEIGHT/2 - 250 
    love.graphics.setFont(fontUI)
    local fh = fontUI:getHeight()
    for i, item in ipairs(game.history) do
        if item.val == 7 then love.graphics.setColor(colors.highlight)
        else love.graphics.setColor(0.6, 0.6, 0.6) end
        local text = tostring(item.val)
        local tw = fontUI:getWidth(text)
        love.graphics.push()
        love.graphics.translate(item.x, y)
        love.graphics.scale(item.scale)
        printBold(text, -tw/2, -fh/2)
        local lineY = fh/2 + 2
        love.graphics.setLineWidth(2)
        love.graphics.line(-10, -lineY, 10, -lineY)
        love.graphics.line(-10, lineY, 10, lineY) 
        love.graphics.pop()
    end
end

-- POPUP SYSTEM
function spawnPopup(text, x, y, color, isImpulse, delay)
    table.insert(game.popups, {
        text = text,
        x = x,
        y = y,
        dy = 0,
        life = 2.0,
        maxLife = 2.0,
        color = color or {1, 1, 1},
        isImpulse = isImpulse,
        enterProgress = 0,
        exitProgress = 0,
        isExiting = false,
        delay = delay or 0
    })
end

function updatePopups(dt)
    for i = #game.popups, 1, -1 do
        local p = game.popups[i]
        
        if p.delay > 0 then
            p.delay = p.delay - dt
        else
            p.life = p.life - dt
            if not p.isImpulse then p.y = p.y + p.dy * dt end
            
            if p.isImpulse then
                if not p.isExiting then
                    -- Entrance: Grow 0 -> 1 (wipe L->R)
                    p.enterProgress = lerp(p.enterProgress, 1.0, 15 * dt)
                end
                
                -- Exit: Start exiting at life < 0.5
                if p.life < 0.5 then
                     p.isExiting = true
                     -- Exit: Grow 0 -> 1 (wipe L->R from left side)
                     p.exitProgress = lerp(p.exitProgress, 1.0, 15 * dt) 
                end
            end
            
            if p.life <= 0 then
                table.remove(game.popups, i)
            end
        end
    end
end
-- Assign to game object
game.spawnPopup = spawnPopup

function drawPopups()
    for _, p in ipairs(game.popups) do
        if p.delay <= 0 then
            local alpha = (p.life / p.maxLife)
            if p.isImpulse then alpha = 1.0 end -- Fade managed by wipe
            
            if p.isImpulse then
                love.graphics.setFont(fontBtn) -- Smaller font (32 vs 48)
                local text = p.text
                local tw = fontBtn:getWidth(text)
                local th = fontBtn:getHeight()
                local padX, padY = 15, 0 -- Tighter padding (Zero Y padding for narrow look)
                local rw, rh = tw + padX*2, th + padY*2
                
                -- Center of popup
                local cx, cy = p.x, p.y
                local rx = cx - rw/2
                local ry = cy - rh/2
                
                -- Wipe Logic:
                -- Visible range: Start at `rx + rw * exitProgress`, Width `rw * (enterProgress - exitProgress)`?
                -- Enter: L->R means visible from Left.
                -- Exit: L->R means Left side gets clipped first.
                
                -- Scissor Region
                -- Left Edge: rx + (rw * exitProgress)
                -- Right Edge: rx + (rw * enterProgress)
                -- Width = Right - Left
                
                local scissorX = rx + (rw * p.exitProgress)
                local scissorW = (rw * p.enterProgress) - (rw * p.exitProgress)
                
                if scissorW > 0 then
                    -- Clamp scissor to screen...
                    
                    local sx = game.tx + scissorX * game.scale
                    local sy = game.ty + ry * game.scale
                    local sw = scissorW * game.scale
                    local sh = rh * game.scale
                    
                    love.graphics.setScissor(sx, sy, sw, sh)
                    
                    -- Draw Full Rect + Text
                    love.graphics.setColor(colors.ui_gold) -- Revert to bright Gold
                    love.graphics.rectangle("fill", rx, ry, rw, rh)
                    
                    -- Text Outline (Black)
                    love.graphics.setColor(0, 0, 0, 1)
                    local tx, ty = rx + padX, ry + padY
                    love.graphics.print(text, tx - 1, ty)
                    love.graphics.print(text, tx + 1, ty)
                    love.graphics.print(text, tx, ty - 1)
                    love.graphics.print(text, tx, ty + 1)
                    
                    -- Text (White)
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.print(text, tx, ty)
                    
                    -- Restore Scissor
                    local gsx = game.tx
                    local gsy = game.ty
                    local gsw = V_WIDTH * game.scale
                    local gsh = V_HEIGHT * game.scale
                    love.graphics.setScissor(gsx, gsy, gsw, gsh)
                end
            else
                love.graphics.setColor(p.color[1], p.color[2], p.color[3], alpha)
                love.graphics.setFont(fontUI)
                love.graphics.print(p.text, p.x, p.y)
            end
        end
    end
end






-- CINEMATIC SYSTEM
function startCinematic()
    game.cinematic.active = true
    game.cinematic.timer = 0
    game.cinematic.displayedText = ""
    game.cinematic.charTimer = 0
    game.cinematic.overlayAlpha = 0
end

function updateCinematic(dt)
    local c = game.cinematic
    if not c.active then return end
    
    c.timer = c.timer + dt
    
    -- Fade in overlay
    c.overlayAlpha = lerp(c.overlayAlpha, c.targetAlpha, 2 * dt)
    
    -- Typewriter Text
    if c.timer > 2.0 then -- Delay start to 2.0s
        c.charTimer = c.charTimer + dt
        if c.charTimer >= c.charInterval then
            c.charTimer = 0
            local len = utf8.len(c.displayedText)
            local targetLen = utf8.len(c.text)
            if len < targetLen then
                local offset = utf8.offset(c.text, len + 2)
                if offset then
                    c.displayedText = string.sub(c.text, 1, offset - 1)
                else
                     c.displayedText = c.text
                end
            end
        end
    end
    
    -- End sequence
    if c.timer >= c.duration then
        c.active = false
        c.overlayAlpha = 0 -- Snap back or fade out? Snap for now to "let it roll"
    end
end

function drawCinematic()
    local c = game.cinematic
    if not c.active then return end
    
    -- Overlay
    love.graphics.setColor(0, 0, 0, c.overlayAlpha)
    love.graphics.rectangle("fill", 0, 0, V_WIDTH, V_HEIGHT)
    
    -- Text
    if c.displayedText ~= "" then
        love.graphics.setFont(fontCinematic)
        love.graphics.setColor(colors.highlight) -- Red text
        local text = c.displayedText
        local tw = fontCinematic:getWidth(text)
        local th = fontCinematic:getHeight()
        love.graphics.print(text, V_WIDTH/2 - tw/2, V_HEIGHT/2 - th/2)
    end
end

-- APP STATE

app = {
    state = "MENU", -- MENU, GAME, PAUSED, SETTINGS, SKILL_TREE
    menuBtns = {},
    settingsBtns = {},
    pauseBtns = {}
}

function love.load()
    love.graphics.setBackgroundColor(colors.bg)
    
    local function loadFont(size)
        local status, font = pcall(love.graphics.newFont, "fonts/Karrik-Regular.otf", size)
        if status then return font end
        status, font = pcall(love.graphics.newFont, "Inter-Regular.ttf", size)
        if status then return font end
        return love.graphics.newFont(size) 
    end
    
    fontLarge = loadFont(64)
    fontUI = loadFont(24)
    fontBtn = loadFont(32)
    fontCombo = loadFont(48)
    fontSmall = loadFont(16)
    fontConsole = loadFont(14)
    -- fontCinematic = loadFont(160) -- Old huge font
    fontCinematic = love.graphics.newFont("fonts/OstrichSans-Medium.otf", 160)
    fontPlinko = love.graphics.newFont("fonts/OstrichSans-Medium.otf", 64)
    fontPlinkoSmall = love.graphics.newFont("fonts/OstrichSans-Medium.otf", 36) -- Smaller for Plinko
    
    -- Assign fonts to game object for modules
    game.fontLarge = fontLarge
    game.fontUI = fontUI
    game.fontBtn = fontBtn
    game.fontCombo = fontCombo
    game.fontSmall = fontSmall
    game.fontConsole = fontConsole
    
    wavyShader = love.graphics.newShader(wavyShaderCode)
    vignetteShader = love.graphics.newShader(vignetteShaderCode)
    frameCanvas = love.graphics.newCanvas(300, 300) 
    
    -- Load Assets
    game.imgToken = love.graphics.newImage("assets/token.png", {mipmaps=true}) 
    game.imgToken:setFilter("linear", "linear", 16) -- High quality filtering 
    
    -- Initialize Modules
    math.randomseed(os.time())
    -- Main Roulette Module
    game.mainRoulette = MainRoulette.new(V_WIDTH/2, V_HEIGHT/2)
    -- Important: game.wheel is now DEPRECATED but might be used by legacy code.
    game.wheel = game.mainRoulette.wheel 
    table.insert(game.modules, game.mainRoulette)
    
    -- Init Plinko [NEW] - Removed default spawn
    if PlinkoBoard then
        -- start empty
    end
    
    -- Restore Button Position (Used by drawButton)
    btnRoll.x = V_WIDTH/2 - btnRoll.w/2
    btnRoll.y = V_HEIGHT - 150
    
    recalcStats()
    SignalSystem.init(game) -- NEW: Init Signal System
    game.skillTree = generateSkillTree() -- Initialize Procedural Tree
    
    local function toggleFS()
        local fs = love.window.getFullscreen()
        love.window.setFullscreen(not fs)
    end
    
    app.menuBtns = {
        {text="PLAY", y=300, action=function() app.state = "GAME" end},
        {text="SETTINGS", y=420, action=function() app.state = "SETTINGS" end},
        {text="QUIT", y=540, action=function() love.event.quit() end}
    }
    
    app.settingsBtns = {
        {text="FULLSCREEN", y=300, action=toggleFS},
        {text="BACK", y=500, action=function() app.state = "MENU" end}
    }
    
    app.pauseBtns = {
        {text="RESUME", y=300, action=function() app.state = "GAME" end},
        {text="FULLSCREEN", y=420, action=toggleFS},
        {text="MENU", y=540, action=function() app.state = "MENU" end}
    }
    
    QuestManager.init()
    PrestigeManager.init()
end

function drawMenuButton(btn, yOffset)
    local w, h = V_WIDTH, V_HEIGHT
    local bw, bh = 300, 80
    local bx = w/2 - bw/2
    local by = btn.y
    local mx, my = getMouseGameCoords()
    local isHover = mx >= bx and mx <= bx+bw and my >= by and my <= by+bh
    
    local col = isHover and colors.highlight or colors.btn_normal
    love.graphics.setColor(col)
    local chamfer = 15
    local verts = getOctagonVertices(bx + bw/2, by + bh/2, bw, bh, chamfer)
    love.graphics.polygon("fill", verts)
    
    love.graphics.setFont(fontBtn)
    love.graphics.setColor(colors.text)
    local tw = fontBtn:getWidth(btn.text)
    local th = fontBtn:getHeight()
    love.graphics.print(btn.text, bx + bw/2 - tw/2, by + bh/2 - th/2)
    return bx, by, bw, bh 
end

function drawPauseMenu()
    -- Semi-transparent overlay
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, V_WIDTH, V_HEIGHT)
    
    -- Title
    love.graphics.setFont(fontLarge)
    love.graphics.setColor(colors.text)
    local title = "PAUSED"
    local tw = fontLarge:getWidth(title)
    love.graphics.print(title, V_WIDTH/2 - tw/2, 150)
    
    -- Buttons
    for _, btn in ipairs(app.pauseBtns) do
        drawMenuButton(btn, 0)
    end
end

-- GAME ACTIONS

function getUpgradeCost(level)
    return math.ceil(1 * math.pow(1.25, level))
end

function generateSkillTree()
    local tree = {}
    -- Root
    table.insert(tree, {id="root", x=0, y=0, name="Big Bang", desc="Where it all began.", cost=0, parents={}, unlocked=true, purchased=true, effect=nil})
    
    local branches = {
        {type="speed", name="Momentum", desc="Spin Speed +10%", dx=0, dy=-120, effect=buySpeed},
        {type="luck", name="Karma", desc="Luck +5%", dx=0, dy=120, effect=buyLuck},
        {type="value", name="Alchemy", desc="7 Payout +1", dx=-150, dy=0, effect=buySevenValue},
        {type="combo", name="Synergy", desc="Combo Mult +0.25x", dx=150, dy=0, effect=buyComboMult}
    }
    
    for _, b in ipairs(branches) do
        local prevId = "root"
        local x, y = 0, 0
        for i = 1, 50 do
            local id = b.type .. "_" .. i
            x = x + b.dx
            y = y + b.dy
            
            -- Slight variations to make it look "organic" or just straight? 
            -- User image shows straight grid lines. Let's keep it straight for structure.
            
            local cost = getUpgradeCost(i-1)
            local node = {
                id = id,
                x = x,
                y = y,
                name = b.name .. " " .. i, -- Roman numerals would be cool but I'll stick to simple numbers for now
                desc = b.desc,
                cost = cost,
                type = b.type,
                parents = {prevId},
                unlocked = (i==1), -- First one unlocked by root
                purchased = false,
                effect = b.effect
            }
            table.insert(tree, node)
            prevId = id
        end
    end
    
    -- Separate Clock Branch
    -- "Separate from rest" -> Connected to Root but far away? Or floating?
    
    -- TIME KEEPER I (First Clock)
    local tkNode1 = {
        id="clock_unlock_1", x=400, y=-300, 
        name="Time Keeper I", desc="Unlock First Sidebar Clock", 
        cost=getUpgradeCost(2), -- Slightly more expensive start? Or cheaper? Cost 1/2.
        type="clock_unlock", 
        parents={"root"}, 
        effect=function() if #game.clockWheels < 1 then buyClock() end end
    }
    table.insert(tree, tkNode1)
    
    -- TIME KEEPER II (Second Clock) -- Connects to I
    local tkNode2 = {
        id="clock_unlock_2", x=400, y=-450, 
        name="Time Keeper II", desc="Unlock Second Sidebar Clock", 
        cost=getUpgradeCost(5), -- More expensive
        type="clock_unlock", 
        parents={"clock_unlock_1"}, 
        effect=function() if #game.clockWheels < 2 then buyClock() end end
    }
    table.insert(tree, tkNode2)
    
    -- TIME KEEPER III (Third Clock) -- Connects to II
    local tkNode3 = {
        id="clock_unlock_3", x=400, y=-600, 
        name="Time Keeper III", desc="Unlock Third Sidebar Clock", 
        cost=getUpgradeCost(10), 
        type="clock_unlock", 
        parents={"clock_unlock_2"}, 
        effect=function() if #game.clockWheels < 3 then buyClock() end end
    }
    table.insert(tree, tkNode3)
    
    -- TIME KEEPER IV (Fourth Clock) -- Connects to III
    local tkNode4 = {
        id="clock_unlock_4", x=400, y=-750, 
        name="Time Keeper IV", desc="Unlock Fourth Sidebar Clock", 
        cost=getUpgradeCost(20), 
        type="clock_unlock", 
        parents={"clock_unlock_3"}, 
        effect=function() if #game.clockWheels < 4 then buyClock() end end
    }
    table.insert(tree, tkNode4)
    
    local prevClock = "clock_unlock_1" -- Chronos starts from I
    local cx, cy = 550, -300 -- Offset to right of TK1
    for i = 1, 50 do
        cx = cx + 0 
        cy = cy - 120
        local id = "clock_speed_" .. i
        local node = {
            id = id,
            x = cx,
            y = cy,
            name = "Chronos " .. i,
            desc = "Clock Speed +10%",
            cost = getUpgradeCost(i), 
            type = "clock_speed",
            parents = {prevClock},
            effect = upgradeClockSpeed
        }
        table.insert(tree, node)
        prevClock = id
        
        -- Link II to Chronos? Or Chronos independent? 
        -- Let's just have Chronos chain off TK1. 
        -- If user buys TK2, it's a dead end branch (just the clock).
    end
    
    -- PLINKO BRANCH
    -- Move to Bottom Left to avoid Karma (Down) overlap
    local plinkoUnlock = {
        id="plinko_unlock", x=-400, y=400, 
        name="Gravity Well", desc="Unlock Plinko Board", 
        cost=getUpgradeCost(3), 
        type="plinko_unlock", 
        parents={"root"}, 
        effect=buyPlinkoUnlock
    }
    table.insert(tree, plinkoUnlock)
    
    local prevPlinko = "plinko_unlock"
    local px, py = -400, 400
    for i = 1, 10 do
        py = py + 120
        local id = "plinko_speed_" .. i
        local node = {
            id = id,
            x = px,
            y = py,
            name = "Aerodynamics " .. i,
            desc = "Plinko Speed +100", 
            cost = getUpgradeCost(i+2), 
            type="plinko_speed",
            parents={prevPlinko},
            effect=upgradePlinkoSpeed
        }
        table.insert(tree, node)
        prevPlinko = id
    end
    
    return tree
end

function processClockResults(game, res, srcType, srcObj)
    local results = { multiplier = 1, bonusGold = 0 }
    for _, cw in ipairs(game.clockWheels) do
        -- Only process if Connected to THIS source AND Not Blocked
        -- Check if connectionData.clockSource matches srcObj (if passed)
        local matchSource = true
        if srcObj and cw.connectionData and cw.connectionData.clockSource ~= srcObj then
            matchSource = false
        end
        
        if cw.connected and not cw.connectionBlocked and cw.connectionData and cw.connectionData.srcType == srcType and matchSource then
            cw.phase = "RESULT"
            if cw.activeNumber == 7 and res == 7 then
                results.multiplier = results.multiplier * 2
                cw.infoText = "x2!"
                spawnPopup("x2", cw.x, cw.y - 50, colors.highlight, true, 0)
            elseif cw.activeNumber == res then
                local reward = 10 * (game.sevenBaseValue or 1) * (game.globalPayoutMult or 1.0)
                results.bonusGold = results.bonusGold + reward
                cw.infoText = "+" .. math.floor(reward)
                spawnPopup("+" .. math.floor(reward), cw.x, cw.y - 50, colors.ui_gold, true, 0)
            end
        end
    end
    return results
end

function checkWin(res)
    addToHistory(res)
    
    -- Universal Logic: Start Turn
    SignalSystem.startTurn()
    
    -- Main Roulette Logic (Independent now)
    local totalMultiplier = 1 -- Clocks no longer instantly multiply (they trigger after)
    local bonusGold = 0
    
    -- Combo Multiplier Logic: Base 1.0 + Bonus
    if res == 7 then
        local base = game.sevenBaseValue 
        game.combo = game.combo + 1
        game.clockStreak = game.clockStreak + 1
        
        -- Start Cinematic on 7th Streak
        if game.combo == 7 then
             startCinematic()
        end
        
        local currentComboMult = 1.0
        if game.combo > 1 then
             currentComboMult = 1.0 + (game.comboMultBonus * (game.combo - 1))
        end
        
        -- Apply Global Payout Mult here as well
        local gain = (base * totalMultiplier * currentComboMult * (game.globalPayoutMult or 1.0))
        game.gold = game.gold + gain
        mainWin = gain
        
        -- Center Impulse Popup for Main Win
        local delay = 0.35 * game.durationMult
        spawnPopup("+" .. math.floor(gain), V_WIDTH/2, V_HEIGHT/2 - 120, colors.ui_gold, true, delay)
        
        local essenceGain = math.floor(math.pow(game.combo, 1.5))
        game.essence = game.essence + essenceGain
        if essenceGain > 0 then
             spawnPopup("+" .. essenceGain, 100, 70, {0.8, 0.3, 0.9}, false, delay)
        end
        
        local w, h = V_WIDTH, V_HEIGHT
        local cam = game.camera
        local mr = game.mainRoulette
        -- Project World (mr.x) to Screen
        local screenX = (mr.x + cam.x - w/2) * cam.zoom + w/2
        local screenY = (mr.y + cam.y - h/2) * cam.zoom + h/2

        Particles.spawnFlyingTokens(game, screenX, screenY, 20) -- New "Flying Series" Effect 
        local shockW = game.wheel.itemHeight
        local shockH = game.wheel.itemHeight
        Particles.spawnFrameShockwave(game, V_WIDTH/2 - shockW/2, V_HEIGHT/2 - shockH/2, shockW, shockH)
    else
        mainWin = bonusGold
        game.gold = game.gold + bonusGold
        if bonusGold > 0 then
             local delay = 0.35 * game.durationMult
             spawnPopup("+" .. bonusGold, V_WIDTH/2, V_HEIGHT/2 - 120, colors.ui_gold, true, delay)
        end
        game.combo = 0
        game.clockStreak = 0
    end
    
    -- Store Amount for Plinko Multiplier
    game.lastWinAmount = mainWin
    
    -- Broadcast Signal to Connected Devices
    local payload = res
    SignalSystem.broadcast(game.mainRoulette, payload)
    
    QuestManager.onRollResult(res) -- Notify Quests
end


function buySpeed()
    game.upgradeLevel = game.upgradeLevel + 1
    recalcStats()
end
function buyLuck()
    game.luckyLevel = game.luckyLevel + 1
end

function buySevenValue()
    game.sevenValueLevel = game.sevenValueLevel + 1
    game.sevenBaseValue = game.sevenBaseValue + 1 
end

function buyComboMult()
    game.comboMultLevel = game.comboMultLevel + 1
    game.comboMultBonus = game.comboMultBonus + 0.25 
end


function upgradeClockSpeed()
    game.clockSpeedUpgrade = game.clockSpeedUpgrade + 1
end

function buyPlinkoUnlock()
    -- Deprecated: Plinko is inserted via Shop.
    -- Just show feedback.
    if spawnPopup then spawnPopup("Plinko Available in Shop!", V_WIDTH/2, V_HEIGHT/2, colors.highlight, true, 0) end
end

function upgradePlinkoSpeed()
    game.plinkoSpeedLevel = (game.plinkoSpeedLevel or 0) + 1
    recalcStats()
end

function buyClock()
    if #game.clockWheels < 4 then
        local x
        local cx = V_WIDTH / 2
        local innerOffset = 340
        local outerOffset = 540
        
        local count = #game.clockWheels
        if count == 0 then x = cx + innerOffset
        elseif count == 1 then x = cx - innerOffset
        elseif count == 2 then x = cx + outerOffset
        elseif count == 3 then x = cx - outerOffset
        end
        
        local cw = ClockWheel.new(x, V_HEIGHT / 2)
        cw.maxTimer = 10.0 * math.pow(0.9, game.clockSpeedUpgrade)
        cw.timer = cw.maxTimer
        table.insert(game.clockWheels, cw)
    end
end

function recalcStats()
    -- Migration / Init
    if not game.energy then game.energy = { max = 10, used = 0 } end

    game.tokensPerSecond = 0 -- Passive Income DISABLED
    -- 1. Reset Base Stats (Standardize to 1.0, ignore legacy Skill Tree levels for stats)
    -- Skill Tree now only used for unlocking specific items/mechanics (like Clocks)
    game.currentCooldown = game.baseCooldown -- * math.pow(0.92, game.upgradeLevel) (Disabled)
    game.spinSpeedMult = 1.0 -- * math.pow(1.08, game.upgradeLevel) (Disabled)
    game.durationMult = 1.0 -- * math.pow(0.92, game.upgradeLevel) (Disabled)
    
    -- Combo Bonus Base
    game.comboMultBonus = 0.0
    game.globalPayoutMult = 1.0 -- NEW: Global Mult Base
    
    -- Luck Base
    game.luckyLevel = 1
    
    -- 2. Apply upgrades from Shop (Replacing Nodes)
    if game.upgrades then
        -- Hotfix: Ensure Energy Upgrade Exists (Safety for old saves)
        if not game.upgrades.energy then
            game.upgrades.energy = {id="energy", name="Power Supply", level=0, baseCost=20, costMult=1.4, desc="Increases Max Energy (+10)"}
        end

        local u = game.upgrades
        
        -- SPEED: Increases Speed, Reduces Duration, Reduces Cooldown
        local spd = u.speed.level
        game.spinSpeedMult = game.spinSpeedMult * math.pow(1.05, spd)
        game.durationMult = game.durationMult * math.pow(0.95, spd)
        game.currentCooldown = game.currentCooldown * math.pow(0.95, spd)
        
        -- LUCK: Base Level + Upgrades
        game.luckyLevel = game.luckyLevel + u.luck.level
        
        -- MULTIPLIER: Additive Bonus
        -- Changed from ComboBonus to Global Multiplier
        game.globalPayoutMult = game.globalPayoutMult + (u.multi.level * 0.25)

        -- Keep legacy ComboMult logic just in case? Or rely on global mult?
        -- Upgrades description says "Global Multiplier". Let's assume user wants general power.
        -- But let's ALSO give a small boost to combo? No, keeps it simple.
        
        -- AUX SPEED (Clocks/Plinko)
        -- We will apply this via game.auxSpeedMult which modifies synced speed.
        game.auxSpeedMult = math.pow(1.05, u.auxSpeed.level)

        -- ENERGY: Base 10 + 10 per level
        game.energy.max = 10 + (u.energy.level * 10)
    end
    
    -- REMOVED: Node Connection Logic (UpgradeNode, ArtifactNode)
    game.artifactChance = 0
    game.wheel.artifactSlotEnabled = false -- Temporarily disabled until Artifact Upgrade is added

    
    -- 3. Calculate Roll Cost (Scaling) & Energy Usage
    -- Base: 5
    -- Doubles for every CONNECTED Clock Wheel (Main -> Clock)
    -- count clocks connected to main
    local connectedClocks = 0
    game.energy.used = 0

    for _, cw in ipairs(game.clockWheels) do
        -- Count ANY clock that has an input connection (is part of the system)
        -- We trust 'cw.connected' flag which is set when a wire is attached to it
        if cw.connected then
            connectedClocks = connectedClocks + 1
            game.energy.used = game.energy.used + 1 -- Each connected clock uses 1 Energy
        end
    end
    
    game.rollCost = 0 -- FREE ROLL (was: 5 * math.pow(2, connectedClocks))
    
    -- Add Plinko Boards to Cost Scaling
    local connectedPlinkos = 0
    for _, pb in ipairs(game.plinkoBoards) do
        if pb.connected then
            connectedPlinkos = connectedPlinkos + 1
        end
    end
    
    -- Combine counts (Each connected module doubles the cost)
    game.rollCost = 0 -- FREE ROLL (was: 5 * math.pow(2, connectedClocks + connectedPlinkos))
    
    -- 4. Apply Node Upgrades (Connected to Plinko Boards)
    -- REMOVED: Plinko now syncs strictly with Main Roulette upgrades (User Request)

    
    -- 5. Apply Prestige Bonus
    local prestigeMult = 1.0 + (PrestigeManager.prestigeBonus or 0)
        game.spinSpeedMult = game.spinSpeedMult * prestigeMult
        
        -- LUCK: Multiplicative (Standard)
        game.luckyLevel = game.luckyLevel * prestigeMult
        
        -- PAYOUT: Multiplicative (Standard Prestige behavior)
        -- This was missing!
        game.globalPayoutMult = (game.globalPayoutMult or 1.0) * prestigeMult
        
        -- Also reduce Cooldown and Duration
        game.durationMult = game.durationMult / prestigeMult
        game.currentCooldown = game.currentCooldown / prestigeMult
        
        -- Apply to Clocks
        -- Apply to Clocks
        for _, cw in ipairs(game.clockWheels) do
            -- SYNC_SPEED: Main Speed * Aux Speed Upgrade
            cw.speedMult = game.spinSpeedMult * (game.auxSpeedMult or 1.0)
            
            -- Payout: Clocks have their own payout mult (maybe from their own nodes? or global?)
            -- User only specified speed sync. 
            -- But we must ensure specific clock upgrades (if any exist) are ignored if user wants "only main roulette nodes".
            -- Assuming we just apply prestige to payout for now, or sync global payout?
            -- Let's keep payout independent but prestige-boosted for now, unless instructed.
            cw.payoutMult = (cw.payoutMult or 1.0) * prestigeMult 
        end
        -- Apply to Plinko
        for _, pb in ipairs(game.plinkoBoards) do
            -- SYNC_GRAVITY: Gravity scales with game.spinSpeedMult * auxSpeedMult
            pb.gravity = 1100 * game.spinSpeedMult * (game.auxSpeedMult or 1.0)
            
            -- SYNC_PAYOUT: Use Main Roulette's additive multiplier bonus
            pb.payoutMult = (1.0 + (game.comboMultBonus or 0)) * prestigeMult
        end

    print("[Stats] Recalculated. SpeedMult: " .. game.spinSpeedMult .. " (Prestige: " .. (PrestigeManager.prestigeBonus or 0) .. ")")
end

function drawButton()
    local b = btnRoll
    local ready = (game.wheel.phase == "READY" and game.cooldownTimer <= 0 and not game.waitingForPlinko)
    -- Use World Coords because button is now drawn in World Space
    local mx, my = getMouseWorldCoords()
    local isHover = mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h
    local isDown = love.mouse.isDown(1)
    local pressOffset = (ready and isHover and isDown) and 6 or 0
    
    local chamfer = 15
    local verts = getOctagonVertices(b.x + b.w/2, b.y + b.h/2 + pressOffset, b.w, b.h, chamfer)
    
    -- Base
    love.graphics.setColor(0.05, 0.05, 0.08)
    local baseVerts = getOctagonVertices(b.x + b.w/2 + 4, b.y + b.h/2 + 10, b.w, b.h, chamfer)
    love.graphics.polygon("fill", baseVerts)
    
    -- Stem
    if ready and not game.buildMode then love.graphics.setColor(0.6, 0.1, 0.1) else love.graphics.setColor(0.25, 0.25, 0.25) end
    local stemVerts = getOctagonVertices(b.x + b.w/2, b.y + b.h/2 + 8, b.w, b.h, chamfer)
    love.graphics.polygon("fill", stemVerts)

    -- Cap
    if game.buildMode then
        love.graphics.setColor(0.3, 0.3, 0.35) -- Gray disabled
    elseif ready then
        if isHover and isDown then love.graphics.setColor(0.85, 0.2, 0.2)
        elseif isHover then love.graphics.setColor(1.0, 0.3, 0.3)
        else love.graphics.setColor(0.9, 0.25, 0.25) end
    else love.graphics.setColor(0.3, 0.3, 0.35) end
    love.graphics.polygon("fill", verts)
    
    if ready and not game.buildMode and game.gold >= game.rollCost then love.graphics.setColor(1, 1, 1) else love.graphics.setColor(0.6, 0.6, 0.6) end
    love.graphics.setFont(fontBtn)
    local tw = fontBtn:getWidth(b.text)
    local th = fontBtn:getHeight()
    local textY = math.floor(b.y + b.h/2 - th/2 + pressOffset) - 10 -- Shift Up to make room for price
    printBold(b.text, math.floor(b.x + b.w/2 - tw/2), textY)
    
    -- Draw Cost
    local costTxt = tostring(game.rollCost)
    love.graphics.setFont(fontUI)
    local cw = fontUI:getWidth(costTxt)
    local iconSz = 16
    local totalW = cw + iconSz + 4
    local startX = b.x + b.w/2 - totalW/2
    local costY = textY + 35
    
    -- Icon
    love.graphics.setColor(1, 1, 1, (ready and game.gold >= game.rollCost) and 1 or 0.5)
    if game.imgToken then
         love.graphics.draw(game.imgToken, startX, costY, 0, iconSz/game.imgToken:getWidth(), iconSz/game.imgToken:getHeight())
    else
         love.graphics.circle("fill", startX + iconSz/2, costY + iconSz/2, iconSz/2)
    end
    
    -- Text
    if game.gold >= game.rollCost then love.graphics.setColor(1, 1, 1) else love.graphics.setColor(1, 0.4, 0.4) end
    printBold(costTxt, startX + iconSz + 4, costY - 2)
end

function drawResourcePill(x, y, label, value, color, iconType, iconScale)
    local paddingH = 15
    local h = 40
    local r = h/2 
    love.graphics.setFont(fontUI)
    local iconW = 30
    local fullText = tostring(value)
    local textW = fontUI:getWidth(fullText)
    local w = iconW + textW + paddingH * 2 + 10 
    love.graphics.setColor(0, 0, 0, 0.6) 
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(color[1], color[2], color[3], 0.3)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    local cx = x + paddingH + iconW/2
    local cy = y + h/2
    love.graphics.setColor(color)
    if iconType == "diamond" then
        local s = 8 * iconScale
        love.graphics.polygon("fill", cx, cy-s, cx+s, cy, cx, cy+s, cx-s, cy)
    elseif iconType == "sparkle" then
        local s = 8 * iconScale
        local s2 = 2 * iconScale
        love.graphics.polygon("fill", cx, cy-s, cx+s2, cy-s2, cx+s, cy, cx+s2, cy+s2, cx, cy+s, cx-s2, cy+s2, cx-s, cy, cx-s2, cy-s2)
    end
    love.graphics.setColor(1, 1, 1)
    printBold(fullText, x + paddingH + iconW + 10, y + h/2 - fontUI:getHeight()/2)
end

function drawCooldownBar()
    if game.cooldownTimer <= 0 then return end
    local w, h = V_WIDTH, V_HEIGHT
    local ratio = game.cooldownTimer / game.currentCooldown
    if ratio < 0 then ratio = 0 end
    local barW = w * ratio
    local barH = 10 
    local barX = (w - barW) / 2
    love.graphics.setColor(colors.highlight) 
    love.graphics.rectangle("fill", barX, 0, barW, barH)
end

-- GAME LOOP

function updateGame(dt)
    -- Cinematic Slow Motion
    local gameDt = dt
    if game.cinematic.active then
         gameDt = dt * 0.1 -- Slow down game by 90%
    end

    local targetIntensity = 0.0
    if (game.wheel.phase == "RESULT" and game.wheel.result == 7) or (game.combo > 0) then
        targetIntensity = 1.0
    end
    game.jackpotIntensity = lerp(game.jackpotIntensity, targetIntensity, 2 * gameDt)
    
    if game.cooldownTimer > 0 then game.cooldownTimer = game.cooldownTimer - gameDt end
    updateHistory(gameDt) 
    Particles.updateParticles(gameDt, game)
    calculateHype()
    updateHype(gameDt)

    -- for _, cw in ipairs(game.clockWheels) do cw:update(gameDt, game) end -- REDUNDANT: Clocks are in game.modules now
    
    -- Check & Spawn Clocks if Unlocked - REMOVED for Placement System


    if game.combo >= 6 then
        if math.random() < (5 * gameDt) then Particles.spawnFallingSeven(game) end
    end
    
    updatePopups(dt) -- Popups in real time? Or slow? Let's keep them real time.
    updateCinematic(dt) -- Cinematic logic MUST be real time
    SignalSystem.update(dt) -- NEW: Update Signals
    if game.shop then Shop.update(dt, game) end
    
    -- Passive Income
    -- PASSIVE INCOME DISABLED
    -- if game.tokensPerSecond > 0 then
    --     game.gold = game.gold + (game.tokensPerSecond * gameDt)
    -- end
    
    for _, mod in ipairs(game.modules) do
        mod:update(gameDt, game, checkWin)
    end
    
    QuestManager.update(gameDt, game)
    PrestigeManager.update(gameDt, game)
    
    -- POLLING-BASED DRAG UPDATE (Every Frame)
    if game.draggingPlinko and love.mouse.isDown(1) then
        local wx, wy = getMouseWorldCoords()
        if game.draggingPlinko.dragOffset then
            game.draggingPlinko.x = wx - game.draggingPlinko.dragOffset.x
            game.draggingPlinko.y = wy - game.draggingPlinko.dragOffset.y
        end
    elseif game.draggingPlinko and not love.mouse.isDown(1) then
        game.draggingPlinko = nil
    end
    
    if game.draggingNode and love.mouse.isDown(1) then
        local wx, wy = getMouseWorldCoords()
        if game.draggingNode.dragOffset then
             game.draggingNode.x = wx - game.draggingNode.dragOffset.x
             game.draggingNode.y = wy - game.draggingNode.dragOffset.y
        end
    elseif game.draggingNode and not love.mouse.isDown(1) then
        game.draggingNode = nil
    end

    if game.draggingGate and love.mouse.isDown(1) then
        local wx, wy = getMouseWorldCoords()
        if game.draggingGate.dragOffset then
             game.draggingGate.x = wx - game.draggingGate.dragOffset.x
             game.draggingGate.y = wy - game.draggingGate.dragOffset.y
        end
    elseif game.draggingGate and not love.mouse.isDown(1) then
        game.draggingGate = nil
    end

    -- Validate Connections Real-time
    for _, cw in ipairs(game.clockWheels) do
        if cw.connected and cw.connectionData then
            local data = cw.connectionData
            -- Calculate positions
            local srcPos, tgtPos
            
            if data.srcType == "main" then
                local mainOutlets = getMainOutlets()
                if mainOutlets[data.srcIndex] then srcPos = mainOutlets[data.srcIndex] end
            elseif data.srcType == "plinko" then
                -- Use stored source instance
                local pBoard = data.clockSource
                if pBoard then
                    local plinkoOutlets = getPlinkoOutlets(pBoard)
                    -- Fix: Iterate to find matching index (array is packed, indices are properties)
                    for _, o in ipairs(plinkoOutlets) do
                        if o.index == data.srcIndex then
                            srcPos = o
                            break
                        end
                    end
                end
            end
            
            local clockOutlets = getClockOutlets(cw)
            if clockOutlets[data.tgtIndex] then 
                tgtPos = clockOutlets[data.tgtIndex] 
            elseif #clockOutlets > 0 then
                tgtPos = clockOutlets[1]
            end
            
            if srcPos and tgtPos then
                 -- Check Valid
                 -- We do NOT ignore 'cw' (target) anymore, so if wire goes through clock body, it blocks.
                 local isBlocked = checkWireObstacles(game, srcPos.x, srcPos.y, tgtPos.x, tgtPos.y, nil, nil)
                 cw.connectionBlocked = isBlocked
            end
        else
            cw.connectionBlocked = false
        end
    end
    
    -- Update Plinko Boards
    for _, pb in ipairs(game.plinkoBoards) do
        local slot = pb:update(gameDt)
        if slot then
             -- Plinko Finished
             game.waitingForPlinko = false
             
             -- Handle Clocks connected to THIS Plinko
             -- We need to pass the specific plinko source to processClockResults?
             -- Actually processClockResults likely iterates clocks and checks their connection.
             -- If connection.srcType == "plinko" and connection.clockSource == pb...
             
             -- Let's update processClockResults signature if needed, or it iterates all?
             -- Assuming processClockResults(game, slot, type) handles it globally? 
             -- Wait, if we use "plinko" type, it might trigger all clocks connected to ANY plinko?
             -- check processClockResults implementation later. For now, pass pb as arg if possible or rely on connection data.
             
             local clockRes = processClockResults(game, slot, "plinko", pb) 
             
             -- Handle Plinko Result
             if pb.startResult == 7 and slot == 7 then
                 -- JACKPOT MULTIPLIER
                 -- Apply Clock Multiplier to the entire bonus
                 local baseBonus = game.lastWinAmount * 9 
                 local totalBonus = baseBonus * clockRes.multiplier
                 game.gold = game.gold + totalBonus
                  spawnPopup("x10!", pb.x, pb.y, colors.highlight, true, 0)
                 if clockRes.multiplier > 1 then
                     spawnPopup("x" .. (10 * clockRes.multiplier) .. " COMBO!", pb.x, pb.y - 40, colors.highlight, true, 0.1)
                 end
                 spawnPopup("+" .. math.floor(totalBonus), V_WIDTH/2, V_HEIGHT/2 - 150, colors.ui_gold, true, 0.2)
             elseif slot == pb.startResult then
                  local bonus = 10 + clockRes.bonusGold -- Base 10 for match + clock bonuses
                  game.gold = game.gold + bonus
                  spawnPopup("Match! +" .. bonus, pb.x, pb.y, colors.ui_gold, true, 0)
             elseif clockRes.bonusGold > 0 then
                  -- Give only bonus gold if clock matched but plinko didn't match startResult
                  game.gold = game.gold + clockRes.bonusGold
                  spawnPopup("Clock Match! +" .. clockRes.bonusGold, pb.x, pb.y, colors.ui_gold, true, 0)
             end
        end
    end

    
    -- AUTO-SPIN LOGIC (Hand of a Gambler)
    if not game.waitingForPlinko and game.mainRoulette and game.mainRoulette.wheel then
         local wheel = game.mainRoulette.wheel
         if wheel.phase == "READY" and game.cooldownTimer <= 0 then
             if game.upgrades.autoSpin and game.upgrades.autoSpin.level > 0 then
                 -- Auto-Spin is FREE once purchased
                 wheel:roll(game)
             end
         end
    end
end


function love.update(dt)
    if app.state == "GAME" then updateGame(dt) end
end

function love.draw()
    local rw, rh = love.graphics.getDimensions()
    local scale = math.min(rw / V_WIDTH, rh / V_HEIGHT)
    
    -- Center the viewport (Camera zoom is handled inside drawGame)
    local tx = (rw - scale * V_WIDTH) / 2
    local ty = (rh - scale * V_HEIGHT) / 2
    
    game.scale = scale
    game.tx = tx
    game.ty = ty
    
    love.graphics.setBackgroundColor(0, 0, 0)
    love.graphics.push()
    love.graphics.translate(tx, ty)
    love.graphics.scale(scale)
    
    love.graphics.setScissor(tx, ty, V_WIDTH*scale, V_HEIGHT*scale)
    
    local function drawContent()
        if app.state == "GAME" or app.state == "PAUSED" or app.state == "SKILL_TREE" then
            local bgR = colors.bg[1] + game.hypeLevel * 0.05
            local bgG = colors.bg[2] + game.hypeLevel * 0.02
            local bgB = colors.bg[3] + game.hypeLevel * 0.08 + math.sin(love.timer.getTime() * 3) * game.hypeLevel * 0.03
            love.graphics.clear(bgR, bgG, bgB) -- Clear virtual canvas area
            
            if app.state == "SKILL_TREE" then
                SkillTree.drawSkillTree(game, drawResourcePill, getMouseGameCoords, fontUI, fontSmall)
            else
                drawGame()
                drawPopups()
                drawCinematic()
                QuestManager.draw(game) -- Draw Quest UI 
                PrestigeManager.draw(game) -- Draw Prestige UI
                if game.shop then Shop.draw(game) end -- Draw Shop ON TOP of everything
            end
            
            if app.state == "PAUSED" then
                drawPauseMenu()
            end
        else
            love.graphics.clear(colors.bg)
            local w, h = V_WIDTH, V_HEIGHT
            love.graphics.setFont(fontLarge)
            love.graphics.setColor(colors.text)
            local title = "SevenOfSevens"
            local tw = fontLarge:getWidth(title)
            love.graphics.print(title, w/2 - tw/2, 100)
            
            local list = (app.state == "MENU") and app.menuBtns or app.settingsBtns
            for _, btn in ipairs(list) do
                drawMenuButton(btn, 0)
            end
        end
    end
    
    drawContent()
    
    love.graphics.setScissor()
    love.graphics.pop()
end

function drawGame()
    local w, h = V_WIDTH, V_HEIGHT
    local cam = game.camera
    
    -- ====== WORLD SPACE (Affected by Camera Pan/Zoom) ======
    love.graphics.push()
    
    -- Apply Camera Transform (center zoom on screen center)
    love.graphics.translate(w/2, h/2)  -- Move origin to center
    love.graphics.scale(cam.zoom)       -- Apply zoom
    love.graphics.translate(-w/2, -h/2) -- Move origin back
    love.graphics.translate(cam.x, cam.y) -- Apply pan offset
    
    -- Falling Sevens (World Space)
    for _, p in ipairs(game.particles) do
        if p.type == "falling_seven" then
            love.graphics.setColor(0.5, 0.5, 0.5, p.alpha) 
            love.graphics.setFont(fontBtn) 
            love.graphics.print("7", p.x, p.y, p.rot, 1, 1, 10, 20) 
        end
    end
    
    -- Draw Modules (Main Roulette, etc.)
    for _, mod in ipairs(game.modules) do
        if mod.draw then mod:draw(game) end
    end

    -- Plinko (Draw in World Space)
    for _, pb in ipairs(game.plinkoBoards) do
        -- Assuming unlocking is per board? Or if purchased they are unlocked.
        -- PlinkoBoard doesn't have 'unlocked' param unless we add it. 
        -- But placement = purchased.
        pb:draw(game)
    end

    -- PLACEMENT GHOST (World Space)
    if game.placementMode and game.placementMode.active then
        local mx, my = getMouseWorldCoords()
        -- Snap to grid? Optional. User didn't ask.
        -- Use the ghost drawing function
        if game.placementMode.type == "clock" then
             -- Create a temporary dummy to draw? Or static method?
             -- ClockWheel:drawGhost is a method. We can call it on the class if we change it to accept self or dummy.
             -- But it uses 'self.numbers'.
             -- Let's create a dummy object in placementMode to use.
             if not game.placementMode.dummy then
                 game.placementMode.dummy = ClockWheel.new(0,0)
             end
             game.placementMode.dummy:drawGhost(mx, my)
             
             -- Draw Cost
             love.graphics.setFont(fontBtn)
             love.graphics.setColor(colors.ui_gold)
             love.graphics.print("-"..game.placementMode.cost.." G", mx + 30, my - 30)
             
        elseif game.placementMode.type == "plinko" then
             if not game.placementMode.dummy then
                 game.placementMode.dummy = PlinkoBoard.new(0,0)
             end
             game.placementMode.dummy:drawGhost(mx, my)
             
             love.graphics.setColor(colors.ui_gold)
             love.graphics.print("-"..game.placementMode.cost.." G", mx + 30, my - 30)
             
        elseif game.placementMode.type == "node" then
             if not game.placementMode.dummy then
                 game.placementMode.dummy = UpgradeNode.new(0,0)
             end
             -- Update dummy pos
             game.placementMode.dummy.x = mx
             game.placementMode.dummy.y = my
             
             -- Draw Ghost (Using existing draw method but potentially semi-transparent)
             -- Calling draw(game) works if it uses self.x/y
             love.graphics.setColor(1, 1, 1, 0.5)
             game.placementMode.dummy:draw(game)
             
             love.graphics.setFont(fontBtn)
             love.graphics.setColor(colors.ui_gold)
             love.graphics.print("-"..game.placementMode.cost.." G", mx + 30, my - 30)

        elseif game.placementMode.type == "logic_gate" then
             if not game.placementMode.dummy then
                 game.placementMode.dummy = LogicGate.new(0, 0, game.placementMode.gateType)
             end
             game.placementMode.dummy.x = mx
             game.placementMode.dummy.y = my

             love.graphics.setColor(1, 1, 1, 0.5)
             game.placementMode.dummy:draw(game)

             love.graphics.setFont(fontBtn)
             love.graphics.setColor(colors.ui_gold)
             love.graphics.print("-"..game.placementMode.cost.." G", mx + 30, my - 30)
        end
    end
    
    -- OUTLETS (World Space - Draw if Build Mode)
    if game.buildMode then
         
         -- Main Outlets
         local mainOutlets = getMainOutlets()
         local cx, cy = V_WIDTH/2, V_HEIGHT/2
         for _, o in ipairs(mainOutlets) do
             local angle = math.atan2(o.y - cy, o.x - cx)
             utils.drawOutletShape(o.x, o.y, angle, 30)
         end
         
          -- Plinko Outlets
          for _, pb in ipairs(game.plinkoBoards) do
               -- Plinko Top Input
               -- Note: PlinkoBoard.draw might implement socket drawing internally for build mode?
               -- Checked PlinkoBoard.draw: It draws sockets if game.buildMode is true.
               -- So we MIGHT NOT need to draw them here if the class handles it.
               -- Let's check ClockWheel.draw -> It also draws sockets if buildMode.
               -- But here in main.lua we seem to be drawing outlets separately?
               -- Ah, lines 1472-1496 were drawing OUTLETS (connection points), not INPUT SOCKETS (wiring targets).
               -- Plinko has BOTH.
               -- Top Input is a SOCKET for Node wiring.
               -- But it is ALSO an OUTLET for Main Roulette wiring target?
               -- Wait, Main->Plinko uses Plinko as a target.
               -- game.plinko.outlets defined in PlinkoBoard.lua: left, right, bottom.
               -- Top Input is in self.sockets.
               
               -- This section (Draw Outlets) seems to be for visual indicators of WHERE signals come out.
               -- For Plinko, signal comes out of Left/Right/Bottom.
               
               local plinkoOutlets = getPlinkoOutlets(pb)
               for _, o in ipairs(plinkoOutlets) do
                   local angle = o.angle or math.atan2(o.y - pb.y, o.x - pb.x)
                   utils.drawOutletShape(o.x, o.y, angle, 30)
               end
               
               -- Explicitly Draw Top Input Outlet (Target for Main->Plinko)
               -- Angle: -90 deg (-pi/2) to face UP
               utils.drawOutletShape(pb.x, pb.y - 20, -math.pi/2, 30)
          end
         
         -- Clock Outlets
         for _, cw in ipairs(game.clockWheels) do
             local clockOutlets = getClockOutlets(cw)
             for _, o in ipairs(clockOutlets) do
                 local angle = math.atan2(o.y - cw.y, o.x - cw.x)
                 utils.drawOutletShape(o.x, o.y, angle, 30)
             end
         end
    end
    
    -- WIRES (World Space)
    -- Permanent Wires
    for _, cw in ipairs(game.clockWheels) do 
        local wireList = cw.connections or (cw.connectionData and {cw.connectionData}) or {}
        
        for _, data in ipairs(wireList) do
            -- Safety checks
            local srcPos = {x=0, y=0} -- fallback
            local tgtPos = {x=cw.x, y=cw.y} -- fallback
            
            -- Find Source Pos
            if data.srcType == "main" then
                local mainOutlets = getMainOutlets()
                if mainOutlets[data.srcIndex] then srcPos = mainOutlets[data.srcIndex] end
            elseif data.srcType == "plinko" then
                -- Use stored source instance
                local pBoard = data.clockSource
                if pBoard then
                    local plinkoOutlets = getPlinkoOutlets(pBoard)
                    -- Fix: Iterate to find matching index (array is packed, indices are properties)
                    for _, o in ipairs(plinkoOutlets) do
                        if o.index == data.srcIndex then
                            srcPos = o
                            break
                        end
                    end
                end
            elseif data.srcType == "clock" and data.clockSource then -- NEW: Clock Source
                local co = getClockOutlets(data.clockSource)
                if co[data.srcIndex] then srcPos = co[data.srcIndex] end
            end
            
            -- Find Target Pos (Clock Outlet)
            local clockOutlets = getClockOutlets(cw)
            if data.tgtIndex and clockOutlets[data.tgtIndex] then 
                tgtPos = clockOutlets[data.tgtIndex] 
            elseif #clockOutlets > 0 then
                tgtPos = clockOutlets[1]
            end
            
            -- Color Logic
            local color = nil -- Default
            
            -- Detect Active Signal [NEW]
            local srcObj = nil
            if data.srcType == "main" then srcObj = game.mainRoulette
            elseif data.srcType == "plinko" then srcObj = data.clockSource or game.plinko
            elseif data.srcType == "clock" then srcObj = data.clockSource end
            
            if srcObj and SignalSystem.isWireActive(srcObj, cw) then
                color = {colors.highlight[1], colors.highlight[2], colors.highlight[3], 1} -- Unified Red
            elseif cw.connectionBlocked then
                color = {1.0, 0.2, 0.2, 0.4} -- Dim Red if blocked
            end
            
            -- Legacy Arrow (Standard Wiring between Roulettes)
            drawChevronPath(srcPos.x, srcPos.y, tgtPos.x, tgtPos.y, color) 
        end
    end
    
    -- Draw Logic Gate Connections
    for _, mod in ipairs(game.modules) do
        if mod.type == "logic_gate" and mod.connections then
            for _, data in ipairs(mod.connections) do
                 -- Source Logic (Similar to Plinko)
                 local srcPos = {x=0, y=0}
                 local tgtPos = {x=mod.x, y=mod.y} -- Fallback

                 -- If we have specific target socket info (Input socket of Gate)
                 if data.tgtIndex and mod.sockets and mod.sockets[data.tgtIndex] then
                     local s = mod.sockets[data.tgtIndex]
                     tgtPos = {x = mod.x + s.x, y = mod.y + s.y}
                 end

                 if data.srcType == "main" then
                      local mainOutlets = getMainOutlets()
                      if mainOutlets[data.srcIndex] then srcPos = mainOutlets[data.srcIndex] end
                 elseif data.srcType == "clock" and data.clockSource then
                      local co = getClockOutlets(data.clockSource)
                      if co[data.srcIndex] then srcPos = co[data.srcIndex] end
                 elseif data.srcType == "plinko" and data.clockSource then
                      local po = getPlinkoOutlets(data.clockSource)
                      for _, o in ipairs(po) do
                          if o.index == data.srcIndex then srcPos = o break end
                      end
                 elseif data.srcType == "logic_gate" and data.clockSource then
                      -- From another Gate's Outlet
                      local srcMod = data.clockSource
                      if srcMod.outlets and srcMod.outlets[data.srcIndex] then
                          local o = srcMod.outlets[data.srcIndex]
                          srcPos = {x = srcMod.x + o.x, y = srcMod.y + o.y}
                      end
                 end

                 -- Wire Color
                 local color = {0.5, 0.5, 0.5, 0.5}
                 if SignalSystem.isWireActive(data.clockSource or game.mainRoulette, mod) then
                     color = {colors.highlight[1], colors.highlight[2], colors.highlight[3], 1}
                 end

                 drawChevronPath(srcPos.x, srcPos.y, tgtPos.x, tgtPos.y, color)
            end
        end
    end

    -- Draw Plinko Wire
    SignalSystem.draw() -- NEW: Draw Signals passing through wires
    
    -- Draw Plinko Wires (Incoming from Main)
    for _, pb in ipairs(game.plinkoBoards) do
        local wireList = pb.connections or (pb.connectionData and {pb.connectionData}) or {}
        
        for _, data in ipairs(wireList) do
             local srcPos = {x=0, y=0}
             local tgtPos = {x=pb.x, y=pb.y - 20} -- Default: Top Input (Index 1)
             
             -- Resolve specific target socket if side/bottom
             if data.tgtIndex and data.tgtIndex > 1 then
                 local plinkoOutlets = getPlinkoOutlets(pb)
                 -- Find outlet with matching index
                 for _, po in ipairs(plinkoOutlets) do
                     if po.index == data.tgtIndex then
                         tgtPos = {x=po.x, y=po.y}
                         break
                     end
                 end
             end
             
             local color = nil
             
             if data.srcType == "main" then
                  local mainOutlets = getMainOutlets()
                  if mainOutlets[data.srcIndex] then srcPos = mainOutlets[data.srcIndex] end
                  
                  if SignalSystem.isWireActive(game.mainRoulette, pb) then
                       color = {colors.highlight[1], colors.highlight[2], colors.highlight[3], 1}
                  end
             elseif data.srcType == "clock" and data.clockSource then
                  local co = getClockOutlets(data.clockSource)
                  if co[data.srcIndex] then srcPos = co[data.srcIndex] end
                  
                  if SignalSystem.isWireActive(data.clockSource, pb) then
                       color = {colors.highlight[1], colors.highlight[2], colors.highlight[3], 1}
                  end
             elseif data.srcType == "plinko" and data.clockSource then -- Source is another Plinko
                  local srcPb = data.clockSource
                  local po = getPlinkoOutlets(srcPb)
                  -- Fix: Iterate to find matching index
                  for _, o in ipairs(po) do
                      if o.index == data.srcIndex then
                          srcPos = o
                          break
                      end
                  end
                  
                  if SignalSystem.isWireActive(srcPb, pb) then
                       color = {colors.highlight[1], colors.highlight[2], colors.highlight[3], 1}
                  end
             end
             
             drawChevronPath(srcPos.x, srcPos.y, tgtPos.x, tgtPos.y, color)
        end
    end
    
    -- Draw Nodes (World Space)
    for _, node in ipairs(game.nodes) do
        node:draw(game)
    end
    
    -- Clock Wheels (World Space)
    
     -- Dynamic Wire (World Space)
    if game.buildMode and game.wiring then
         if game.wiring.type == "node" then
             local start = game.wiring.startSocket
             -- Calculate absolute start pos
             local sx = game.wiring.startNode.x + start.x
             local sy = game.wiring.startNode.y + start.y
             local wx, wy = getMouseWorldCoords()
             
             -- Draw Red Fluid Line (Placeholder: Chevron)
             drawChevronPath(sx, sy, wx, wy, {1.0, 0.2, 0.2, 0.9})
         else
             -- Outlet Wiring
             local start = game.wiring.startOutlet
             local wx, wy = getMouseWorldCoords()
             -- Validate Path for Color
             -- Start is outlet object.
             -- End is mouse (no object yet).
             local isBlocked = checkWireObstacles(game, start.x, start.y, wx, wy, start.parent, nil)
             
             local wireColor
             if isBlocked then
                 wireColor = {1.0, 0.2, 0.2, 0.8} -- Red
             else
                 wireColor = {0.2, 1.0, 0.2, 0.8} -- Green
             end
             
             drawChevronPath(start.x, start.y, wx, wy, wireColor)
         end
    end
    
     -- Draw Node Connections (Persisted)
    -- Main Roulette
    for _, mod in ipairs(game.modules) do
        if mod.nodeConnection then
            local c = mod.nodeConnection
            if c.source and c.targetSocket then
                 -- Calculate Source Pos (Socket Abs Position)
                 local sx = c.source.x + c.sourceSocket.x
                 local sy = c.source.y + c.sourceSocket.y
                 -- Target Pos
                 local tx = mod.x + c.targetSocket.x
                 local ty = mod.y + c.targetSocket.y
                 
                 utils.drawFluidDashedLine(sx, sy, tx, ty, {0.6, 0.6, 0.6, 1.0}, c.sourceSocket.normal, c.targetSocket.normal)
            elseif c.x then -- Legacy fallback (if just node stored) or migrating
                 local n = c
                 drawChevronPath(n.x, n.y, mod.x, mod.y, {1.0, 0.2, 0.2, 0.5}) -- Deprecated visual
            end
        end
    end
    -- Clock Wheels
    for _, cw in ipairs(game.clockWheels) do 
        if cw.nodeConnection then
            local c = cw.nodeConnection
             if c.source and c.targetSocket then
                 local sx = c.source.x + c.sourceSocket.x
                 local sy = c.source.y + c.sourceSocket.y
                 local tx = cw.x + c.targetSocket.x
                 local ty = cw.y + c.targetSocket.y
                 
                 utils.drawFluidDashedLine(sx, sy, tx, ty, {0.6, 0.6, 0.6, 1.0}, c.sourceSocket.normal, c.targetSocket.normal)
             elseif c.x then -- Legacy
                 local n = c
                 drawChevronPath(n.x, n.y, cw.x, cw.y, {1.0, 0.2, 0.2, 0.5})
             end
        end
    end
    
    -- Plinko Node Connection [NEW]
    for _, pb in ipairs(game.plinkoBoards) do
        if pb.nodeConnection then
            local c = pb.nodeConnection
            if c.source and c.targetSocket then
                 local sx = c.source.x + c.sourceSocket.x
                 local sy = c.source.y + c.sourceSocket.y
                 local tx = pb.x + c.targetSocket.x
                 local ty = pb.y + c.targetSocket.y
                 
                 utils.drawFluidDashedLine(sx, sy, tx, ty, {0.6, 0.6, 0.6, 1.0}, c.sourceSocket.normal, c.targetSocket.normal)
            end
        end
    end
    
    -- Clock Wheels (World Space)
    for _, cw in ipairs(game.clockWheels) do 
        cw:draw(game) 
    end
    
    -- Hover Tooltip for Nodes
    local mx, my = getMouseWorldCoords()
    for _, node in ipairs(game.nodes) do
         local cx, cy = node.x, node.y
         local w, h = node.w, node.h
         
         -- Calculate where buttons are (same logic as UpgradeNode)
         local startY = cy - h/2 + 50
         local rowH = 35
         local i = 0
         
         if node.stats then
             for key, stat in pairs(node.stats) do
                -- Only check if stat has button (val < max)
                if stat.val < stat.max then
                     local ry = startY + (i*rowH)
                     local btnW, btnH = 60, 24
                     local btnX = cx + w/2 - btnW - 15
                     local btnY = ry
                     
                     -- Check Hover
                     if mx >= btnX and mx <= btnX + btnW and my >= btnY and my <= btnY + btnH then
                         drawNodeTooltip(node, mx, my)
                         break -- Found one, no need to check others for this node
                     end
                end
                i = i + 1
             end
         end
    end
    
    -- Context Menu (Drawing in World Space relative to click)
    if game.contextMenu and game.contextMenu.active then
        local mx, my = game.contextMenu.x, game.contextMenu.y
        love.graphics.setFont(fontUI)
        local optH = 30
        local optW = 100
        for i, opt in ipairs(game.contextMenu.options) do
             local y = my + (i-1)*optH
             love.graphics.setColor(0, 0, 0, 0.8)
             love.graphics.rectangle("fill", mx, y, optW, optH)
             love.graphics.setColor(1, 1, 1)
             love.graphics.rectangle("line", mx, y, optW, optH)
             love.graphics.print(opt.text, mx + 5, y + 5)
        end
    end
    
    -- Particles (World Space)
    -- Draw World Particles (Shockwaves, Falling Sevens)
    Particles.drawWorldParticles(game)
    
    -- Roll History (World Space - Draw BEHIND button?)
    -- Use drawHistory helper
    drawHistory()
    
    -- ROLL Button (World Space)
    drawButton() -- RESTORED LEGACY DRAW
    
    -- Combo Text (World Space)
    if game.combo > 1 then
        love.graphics.setFont(fontCombo)
        love.graphics.setColor(colors.highlight)
        local comboText = "COMBO 7 x" .. game.combo
        local cww = fontCombo:getWidth(comboText)
        printBold(comboText, w - cww - 20, h - 80)
    end
    
    love.graphics.pop()
    -- ====== END WORLD SPACE ======
    
    -- ====== SCREEN SPACE (Fixed UI - Not affected by camera) ======
    
    -- Build Mode Button (Screen Space)
    local bb = btnBuild
    love.graphics.setColor(game.buildMode and colors.highlight or colors.btn_normal)
    love.graphics.rectangle("fill", bb.x, bb.y, bb.w, bb.h, 10)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(3)
    -- Simple Wrench Icon
    love.graphics.line(bb.x+15, bb.y+45, bb.x+30, bb.y+30)
    love.graphics.circle("line", bb.x+40, bb.y+20, 8)
    
    -- Vignette (Screen Space Overlay)
    love.graphics.setShader(vignetteShader)
    vignetteShader:send("screenSize", {w, h})
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setShader()
    
    -- Cooldown Bar (Screen Space)
    drawCooldownBar() 
    
    -- Resource Pills (Screen Space)
    -- Gold Chip UI (Asset Based)
    -- Gold Chip UI (Pill Frame)
    local gcx, gcy = 70, 70
    local targetSize = 120
    local pillW, pillH = 220, 60
    local pillX = gcx 
    local pillY = gcy - pillH/2
    
    -- 1. Draw Pill Frame (Extending Right from Token Center)
    love.graphics.setColor(0.1, 0.1, 0.12, 0.95)
    love.graphics.rectangle("fill", pillX, pillY, pillW, pillH) -- Sharp corners (removed radius)
    
    -- Tech Pattern (Dots) inside Pill
    love.graphics.setScissor(pillX, pillY, pillW, pillH)
    love.graphics.setColor(1, 1, 1, 0.05)
    local dotSpacing = 15
    local rows = math.ceil(pillH / dotSpacing) + 1
    local cols = math.ceil(pillW / dotSpacing) + 1
    for dy = 0, rows do 
        for dx = 0, cols do
            local px = pillX + dx * dotSpacing
            local py = pillY + dy * dotSpacing
            if (dx + dy) % 2 == 0 then love.graphics.circle("fill", px, py, 1.5) end
        end
    end
    love.graphics.setScissor() -- Reset Scissor

    -- Dashed Border
    love.graphics.setColor(1, 1, 1, 0.2)
    utils.drawDashedRectangle(pillX, pillY, pillW, pillH, 10, 5)

    -- 2. Draw Token (Left Side, Overlapping)
    if game.imgToken then
        love.graphics.setColor(1, 1, 1)
        local iw, ih = game.imgToken:getDimensions()
        local scale = targetSize / iw
        -- Draw centered at gcx, gcy
        love.graphics.draw(game.imgToken, gcx, gcy, 0, scale, scale, iw/2, ih/2)
    else
        love.graphics.setColor(colors.highlight)
        love.graphics.circle("fill", gcx, gcy, targetSize/2)
    end
    
    -- Dollar Sign inside Token (Smaller)
    love.graphics.setFont(fontBtn) 
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("$", gcx - fontBtn:getWidth("$")/2, gcy - fontBtn:getHeight()/2)
    
    -- 3. Draw Gold Amount (Inside Pill)
    local gTxt = utils.formatNumber(game.gold)
    love.graphics.setFont(fontBtn) 
    love.graphics.setColor(1, 1, 1)
    
    -- Position text in the empty space of the pill (Right of token)
    local textSpaceX = pillX + 50 -- Start text area after token overlap
    local textSpaceW = pillW - 50
    love.graphics.printf(gTxt, textSpaceX, pillY + pillH/2 - fontBtn:getHeight()/2, textSpaceW, "center")

    -- 4. Income Rate (Below Pill)
    if game.tokensPerSecond > 0 then
        love.graphics.setFont(fontSmall)
        love.graphics.setColor(0.7, 1.0, 0.7)
        local rateTxt = string.format("(+%.1f/s)", game.tokensPerSecond)
        love.graphics.print(rateTxt, pillX + 60, pillY + pillH + 5) 
    end

    -- Resource Pills (Screen Space)
    -- Shift Essence down to avoid overlap
    drawResourcePill(20, 150, "ESSENCE", game.essence, {0.8, 0.3, 0.9}, "sparkle", 0.8)
    
    -- Energy Pill
    local eTxt = game.energy.used .. "/" .. game.energy.max
    drawResourcePill(20, 210, "ENERGY", eTxt, {0.2, 0.8, 1.0}, "diamond", 0.8)

    -- Data Pill
    drawResourcePill(20, 270, "DATA", game.data, {0.2, 1.0, 0.4}, "sparkle", 0.8)

    -- SKILLS BUTTON Removed (Moved to Shop Tabs) 
    
    -- Console Input (Screen Space)
    if game.inputActive then
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", 0, h-40, w, 40)
        love.graphics.setColor(1, 1, 1)
        love.graphics.setFont(fontConsole)
        love.graphics.print(">" .. game.inputText .. "|", 10, h-30)
    end
    
    -- Zoom/Pan Hint (Screen Space)
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.setFont(fontSmall)
    local hintText = "Scroll to Zoom | Right-Drag to Pan"
    local htw = fontSmall:getWidth(hintText)
    love.graphics.print(hintText, w/2 - htw/2, h - 25)
    
    -- Shop Drawer Removed from here (Moved to drawContent to fix Z-Order)

    -- Draw Screen Particles (Flying Tokens)
    Particles.drawScreenParticles(game)
    
    -- ====== END SCREEN SPACE ======
end

function love.mousemoved(x, y, dx, dy, istouch)
    if app.state == "SKILL_TREE" and game.skillCam.dragging then
        game.skillCam.x = game.skillCam.x + dx / game.scale
        game.skillCam.y = game.skillCam.y + dy / game.scale
    elseif app.state == "GAME" then
        -- Camera Panning (Right-drag)
        if game.camera.dragging then
            game.camera.x = game.camera.x + dx / (game.scale * game.camera.zoom)
            game.camera.y = game.camera.y + dy / (game.scale * game.camera.zoom)
        end
        
        -- ClockWheel Dragging (Left-drag)
        if game.draggingClock then
            local wx, wy = getMouseWorldCoords()
            game.draggingClock.x = wx - game.draggingClock.dragOffset.x
            game.draggingClock.y = wy - game.draggingClock.dragOffset.y
            game.draggingClock.targetX = game.draggingClock.x
        end
        
        -- Plinko Dragging
        if game.draggingPlinko then
            local wx, wy = getMouseWorldCoords()
            game.draggingPlinko.x = wx - game.draggingPlinko.dragOffset.x
            game.draggingPlinko.y = wy - game.draggingPlinko.dragOffset.y
        end
        
        -- Node Dragging
        if game.draggingNode then
            local wx, wy = getMouseWorldCoords()
            game.draggingNode.x = wx - game.draggingNode.dragOffset.x
            game.draggingNode.y = wy - game.draggingNode.dragOffset.y
        end
    end
end


function isSocketOccupied(game, obj, index)
    if not obj then return false end
    
    -- 1. Check if used as Input (Receiving)
    -- Look at obj's own connections
    local inputList = obj.connections or (obj.connectionData and {obj.connectionData}) or {}
    for _, c in ipairs(inputList) do
        if c.tgtIndex == index then return true end
    end

    -- 2. Check if used as Output (Sending)
    -- Scan ALL other objects to see if they cite this obj as source
    
    -- Scan Clocks
    for _, cw in ipairs(game.clockWheels) do
        local list = cw.connections or (cw.connectionData and {cw.connectionData}) or {}
        for _, c in ipairs(list) do
            local src = c.parent or c.clockSource or c.plinko
            -- Compare generic object reference
            if src == obj and c.srcIndex == index then return true end
        end
    end
    
    -- Scan Plinko Boards
    for _, pb in ipairs(game.plinkoBoards) do
        local list = pb.connections or (pb.connectionData and {pb.connectionData}) or {}
        for _, c in ipairs(list) do
            local src = c.parent or c.clockSource or c.plinko
            if src == obj and c.srcIndex == index then return true end
        end
    end
    
    -- Main Roulette is special (infinite output? or 3 fixed?)
    -- Only check if obj is NOT main roulette? 
    -- User said "4 outlets on each roulette", meaning Clocks. 
    -- Main has 3. If Main is obj, we should restrict it too?
    -- Let's apply restriction everywhere for consistency.
    
    return false
end

function love.mousepressed(x, y, button)
    local mx, my = getMouseGameCoords()
    
    if app.state == "GAME" then
        -- Shop Interaction (Screen Space - Highest Priority)
        if game.shop and Shop.mousepressed(x, y, button, game) then
            return -- Shop consumed the click
        end
        
        -- Quest Interaction (Screen Space)
        if button == 1 and QuestManager.handleClick(x, y, game) then
            return -- Quest UI consumed click
        end
        
        -- Prestige Interaction (Screen Space)
        if button == 1 and PrestigeManager.checkClick(x, y, game) then
            return
        end
        
        -- PLACEMENT MODE INTERACTION
        if game.placementMode and game.placementMode.active then
            if button == 1 then
                -- Place Item
                local wx, wy = getMouseWorldCoords()
                
                -- Check Cost again (redundant but safe)
                if game.gold >= game.placementMode.cost then
                    game.gold = game.gold - game.placementMode.cost
                    
                    -- Instantiate
                    if game.placementMode.type == "clock" then
                        local newClock = ClockWheel.new(wx, wy)
                        table.insert(game.clockWheels, newClock)
                        table.insert(game.modules, newClock)
                        -- Trigger "Buy" sound?
                    elseif game.placementMode.type == "plinko" then
                        local newPlinko = PlinkoBoard.new(wx, wy)
                        newPlinko.unlocked = true -- Must be unlocked to function
                        table.insert(game.plinkoBoards, newPlinko)
                    elseif game.placementMode.type == "node" then
                        local newNode = UpgradeNode.new(wx, wy)
                        table.insert(game.nodes, newNode)
                    elseif game.placementMode.type == "artifact_node" then
                        local newNode = ArtifactNode.new(wx, wy)
                        table.insert(game.nodes, newNode)
                    elseif game.placementMode.type == "logic_gate" then
                        local newGate = LogicGate.new(wx, wy, game.placementMode.gateType)
                        table.insert(game.modules, newGate) -- Add to modules list for update/draw/signals
                    end
                    
                    -- Clear Mode (Trigger "Place" sound)
                    game.placementMode = nil
                else
                    -- Not enough gold (shouldn't happen if checked at shop)
                end
            elseif button == 2 then
                -- Cancel
                game.placementMode = nil
            end
            return -- Consume click
        end
        
        -- Left Click
        if button == 1 then
            -- Build Mode Toggle (Screen Space)
            local b = btnBuild -- Defined at top as local
            if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
                game.buildMode = not game.buildMode
                game.wiring = nil -- Reset wiring if toggled off
                return
            end

            -- Skills Button Interaction Removed
            
            -- World Interactions
            local wx, wy = getMouseWorldCoords()
            
            -- Normal Game Interactions
            if not game.buildMode then
                -- ROLL Button (LEGACY CHECK)
                if wx >= btnRoll.x and wx <= btnRoll.x + btnRoll.w and
                   wy >= btnRoll.y and wy <= btnRoll.y + btnRoll.h then
                   -- Check Cost
                   if game.gold >= game.rollCost then
                       if game.wheel:roll(game) then 
                           game.gold = game.gold - game.rollCost
                           Particles.spawnButtonShockwave(game, btnRoll) 
                       end
                   else
                       -- Feedback for unsufficient funds?
                       -- Maybe shake button or sound?
                   end
                   return
                end
            end
                
            -- BUILD MODE INTERACTION
            if game.buildMode then
                -- Check Outlets
                local outlets = getMainOutlets()
                for _, cw in ipairs(game.clockWheels) do
                    local co = getClockOutlets(cw)
                    for _, o in ipairs(co) do table.insert(outlets, o) end
                end
                
                -- Add Plinko Outlets (from all boards)
                for _, pb in ipairs(game.plinkoBoards) do
                    -- Top Input (Target for Main->Plinko)
                    -- We treat this as an 'outlet' in the interaction loop so we can CLICK it to complete a wire.
                    -- Position is Center X, Top Y - 20 (based on draw logic)
                    table.insert(outlets, {
                        x = pb.x, 
                        y = pb.y - 20, 
                        type = "plinko", 
                        index = 1,
                        parent = pb,
                        obj = pb,
                        isInput = true
                    })
                    
                    -- Plinko OUTPUTS (Bottom/Sides) are sources.
                    local plinkoOutlets = getPlinkoOutlets(pb)
                    for _, po in ipairs(plinkoOutlets) do
                        table.insert(outlets, po)
                    end
                end
                
                -- Add Logic Gate Outlets & Sockets
                for _, mod in ipairs(game.modules) do
                    if mod.type == "logic_gate" then
                        -- Outlets
                        if mod.outlets then
                            for _, o in ipairs(mod.outlets) do
                                table.insert(outlets, {
                                    x = mod.x + o.x, y = mod.y + o.y,
                                    type = "logic_gate", index = o.index,
                                    parent = mod, obj = mod,
                                    isOutput = true
                                })
                            end
                        end
                        -- Sockets (Inputs)
                        if mod.sockets then
                            for _, s in ipairs(mod.sockets) do
                                table.insert(outlets, {
                                    x = mod.x + s.x, y = mod.y + s.y,
                                    type = "logic_gate", index = s.index,
                                    parent = mod, obj = mod,
                                    isInput = true
                                })
                            end
                        end
                    end
                end

                -- Check Node Sockets (Start Wiring)
                for _, node in ipairs(game.nodes) do
                     local socketInfo = node:getSocketAt(wx, wy)
                     if socketInfo then
                         game.wiring = {
                             active = true,
                             startNode = node,
                             startSocket = socketInfo.socket,
                             type = "node" -- Different from outlet wiring
                         }
                         return
                     end
                end
                
                -- Check Dragging Logic (Moved to Build Mode)
                local handled = false
                -- Check Dragging Logic (Moved below Outlets)
                
                -- 1. Check Outlets Connection
                for _, o in ipairs(outlets) do
                    local dist = math.sqrt((wx - o.x)^2 + (wy - o.y)^2)
                    if dist < 45 then  -- Increased Radius for easier clicking 
                        -- EXCEPTION: If this is a Plinko outlet, check if we're dragging
                        -- Plinko outlet is at the TOP of the board. If click is BELOW the outlet by 50px, it's a drag.
                        if o.type == "plinko" then
                            local p = o.parent
                            -- If click is more than 50px below the outlet (i.e., on the body), skip wiring
                            if wy > o.y + 50 then
                                -- This is a body click, not outlet - skip to drag logic
                                goto continue_outlet_loop
                            end
                        end
                        
                        -- Connection Logic
                        if not game.wiring then
                             game.wiring = { active=true, startOutlet=o }
                        else

                             
                             -- Finish Wiring (Outlet -> Outlet)
                             local start = game.wiring.startOutlet
                             if not start then return end -- Guard
                             
                             local validTopology = false
                             local validTopology = false
                             -- Universal Wiring Logic
                             -- 1. Identify Source and Target
                             -- Direction depends on Drag: Start -> End
                             -- But we must ensure correct flow: Output -> Input
                             
                             local validTopology = false
                             local source, target, targetInd
                             
                             -- Case A: Output -> Input (Standard)
                             if start.isOutput and o.isInput then
                                 if start.obj ~= o.obj then
                                     validTopology = true
                                     source = {type=start.type, index=start.index, parent=start.parent, plinko=start.obj}
                                     target = o.obj
                                     targetInd = o.index
                                 end
                                 
                             -- Case B: Input -> Output (Reverse Drag)
                             -- Constraint: Only allow this if 'start' is NOT an Output.
                             -- If 'start' is both Input and Output (like Clock), dragging to an Output should NOT auto-reverse.
                             -- The user likely intended Case A and missed the Input socket. Making it reverse is confusing.
                             elseif start.isInput and o.isOutput and not start.isOutput then
                                 if start.obj ~= o.obj then
                                     validTopology = true
                                     -- SWAP Source and Target
                                     source = {type=o.type, index=o.index, parent=o.parent, plinko=o.obj}
                                     target = start.obj
                                     targetInd = start.index
                                 end
                             end
                             
                             -- Normalization for "plinko" type consistency in connectionData
                             if validTopology then
                                 -- Fix Source Type string for consistency with legacy checks
                                 -- Check 'source' table we just constructed, not 'start' outlet
                                 local srcType = source.type 
                                 if srcType == "plinko_out" then srcType = "plinko" end 
                                 
                                 -- connectionData Construction
                                 -- Use the 'source' table we built in Case A/B
                                 local finalSource = {
                                     type = srcType,
                                     index = source.index,
                                     parent = source.parent, -- Generic obj ref
                                     plinko = (srcType == "plinko") and source.plinko or nil -- specific for plinko
                                 }
                                 -- Override source var with final structure
                                 source = finalSource
                             end
                             
                             -- STRICT SOCKET RESTRICTION
                             -- Check if Source Socket is occupied (as Output or Input elsewhere)
                             -- Check if Target Socket is occupied (as Input or Output elsewhere)
                             if validTopology then
                                 local srcOccupied = isSocketOccupied(game, source.parent, source.index)
                                 local tgtOccupied = isSocketOccupied(game, target, targetInd)
                                 
                                 if srcOccupied or tgtOccupied then
                                     -- Block Connection
                                     -- Spawn red "Block" particles?
                                     Particles.spawnButtonShockwave(game, {x=o.x-10, y=o.y-10, w=20, h=20}) -- visual feedback?
                                     -- Maybe red color? Shockwave is usually white/blue.
                                     -- Just fail silently or with sound.
                                     game.wiring = nil
                                     return 
                                 end
                             end
                             
                             local isBlocked = checkWireObstacles(game, start.x, start.y, o.x, o.y, start.parent, o.parent)
                             
                             if validTopology and target and not isBlocked then
                                 -- Energy Check
                                 if (game.energy.used + 1) > game.energy.max then
                                     if spawnPopup then spawnPopup("Not Enough Energy!", o.x, o.y - 40, {1, 0.2, 0.2}, true, 0) end
                                     game.wiring = nil
                                     return
                                 end

                                 target.connected = true
                                 
                                 -- Initialize connections list if needed
                                 target.connections = target.connections or {}
                                 
                                 -- Check for duplicates
                                 local isDuplicate = false
                                 if source.parent then -- Standard check
                                     for _, c in ipairs(target.connections) do
                                         if c.parent == source.parent and c.srcIndex == source.index then
                                             isDuplicate = true
                                             break
                                         end
                                     end
                                 end
                                 
                                 if not isDuplicate then
                                     table.insert(target.connections, { 
                                         srcType=source.type, 
                                         srcIndex=source.index, 
                                         tgtIndex=targetInd,
                                         clockSource=source.parent or source.plinko, -- Store reference
                                         parent=source.parent -- Explicit parent ref for duplicate check
                                     })
                                     
                                     -- Calculate correct shockwave position based on socket
                                     local tx, ty = target.x, target.y
                                     if targetInd and target.id and string.find(target.id, "plinko") then
                                         -- Look up plinko socket
                                         local outlets = getPlinkoOutlets(target)
                                         for _, o in ipairs(outlets) do
                                             if o.index == targetInd then
                                                 tx, ty = o.x, o.y
                                                 break
                                             end
                                         end
                                     elseif targetInd and target.type == "clock" then
                                          local outlets = getClockOutlets(target)
                                          if outlets[targetInd] then
                                              tx, ty = outlets[targetInd].x, outlets[targetInd].y
                                          end
                                     end
                                     
                                     Particles.spawnButtonShockwave(game, {x=tx-20, y=ty-20, w=40, h=40})
                                     
                                     recalcStats() -- Update Economy (Roll Cost, etc.)
                                 end
                                 
                                 game.wiring = nil
                             end
                        end
                        return 
                    end
                    ::continue_outlet_loop::
                end
                
                -- 2. Check Dragging (If not wiring)
                if not game.wiring then
                     -- Check Clocks
                     for _, cw in ipairs(game.clockWheels) do
                         local dist = math.sqrt((wx - cw.x)^2 + (wy - cw.y)^2)
                         if dist < 90 then -- Body Radius
                             game.draggingClock = cw
                             cw.dragOffset = {x = wx - cw.x, y = wy - cw.y}
                             return
                         end
                     end
                     
                     -- Check Plinko Boards
                     for _, pb in ipairs(game.plinkoBoards) do
                         -- Plinko Bounds (x is Center, y is Top)
                         local w2 = pb.w/2
                         if wx >= pb.x - w2 and wx <= pb.x + w2 and
                            wy >= pb.y and wy <= pb.y + pb.h then
                             game.draggingPlinko = pb
                             pb.dragOffset = {x = wx - pb.x, y = wy - pb.y}
                             return
                         end
                     end

                     -- Check Logic Gates
                     for _, mod in ipairs(game.modules) do
                         if mod.type == "logic_gate" and mod.hits and mod:hits(wx, wy) then
                             game.draggingGate = mod
                             mod.dragOffset = {x = wx - mod.x, y = wy - mod.y}
                             return
                         end
                     end
                end
                
                -- Check Node Wiring Completion
                -- Check Node Wiring Completion
                if game.wiring and game.wiring.type == "node" then
                     -- Check Main Roulette Sockets (Input)
                     for _, mod in ipairs(game.modules) do
                         if mod.getSocketAt then
                             local info = mod:getSocketAt(wx, wy)
                             if info and info.socket.type == "input" then
                                 mod.nodeConnection = {
                                     source = game.wiring.startNode,
                                     sourceSocket = game.wiring.startSocket,
                                     targetSocket = info.socket
                                 }

                                 game.wiring = nil
                                 Particles.spawnButtonShockwave(game, {x=info.x-20, y=info.y-20, w=40, h=40})
                                 recalcStats() -- Update stats immediately on connection
                                 return
                             end
                         end
                     end
                     
                     -- Check Plinko Sockets (Input) [NEW]
                     for _, pb in ipairs(game.plinkoBoards) do
                         local info = pb:getSocketAt(wx, wy)
                         if info and info.socket.type == "input" then
                             pb.nodeConnection = {
                                 source = game.wiring.startNode,
                                 sourceSocket = game.wiring.startSocket,
                                 targetSocket = info.socket
                             }
                             game.wiring = nil
                             Particles.spawnButtonShockwave(game, {x=info.x-20, y=info.y-20, w=40, h=40})
                             recalcStats()
                             return
                         end
                     end
                     
                     -- Clock Wheels Connection Blocked (User Request)
                     -- for _, cw in ipairs(game.clockWheels) do ... end

                end


                
                -- Check Node Interactions (Upgrades etc.) before Dragging
                -- But after sockets to ensure we can wire?
                -- Actually sockets are small, body is large.
                for _, node in ipairs(game.nodes) do
                    -- If we click on Upgrade Button, Handle IT.
                    -- node:handleClick checks specific buttons.
                    if node.handleClick and node:handleClick(wx, wy, game) then
                        recalcStats() -- Recalculate stats immediately after upgrade
                        return -- UI Interaction consumed
                    end
                end

                -- 2. Check Clock Dragging (If not clicking outlet)
                for _, cw in ipairs(game.clockWheels) do
                    local r = 90
                    local dist = math.sqrt((wx - cw.x)^2 + (wy - cw.y)^2)
                    if dist < r then -- Body click
                        game.draggingClock = cw
                        cw.dragOffset = {x = wx - cw.x, y = wy - cw.y}
                        if game.wiring then game.wiring = nil end
                        return
                    end
                end
                
                -- 3. Check Plinko Dragging
                if game.plinko and game.plinko.unlocked then
                    local p = game.plinko
                    -- Hitbox: CenterX +/- Width/2, TopY to TopY + Height
                    local inX = wx >= p.x - p.w/2 and wx <= p.x + p.w/2
                    local inY = wy >= p.y and wy <= p.y + p.h
                    
                    if inX and inY then
                        game.draggingPlinko = p
                        p.dragOffset = {x = wx - p.x, y = wy - p.y}
                        if game.wiring then game.wiring = nil end
                        return
                    end
                end
                
                -- 4. Check Logic Gate Dragging
                for _, mod in ipairs(game.modules) do
                    if mod.type == "logic_gate" and mod.hits and mod:hits(wx, wy) then
                        game.draggingGate = mod
                        mod.dragOffset = {x = wx - mod.x, y = wy - mod.y}
                        if game.wiring then game.wiring = nil end
                        return
                    end
                end

                -- 5. Check Node Dragging
                for _, node in ipairs(game.nodes) do
                     if node:hits(wx, wy) then
                         game.draggingNode = node
                         node.dragOffset = {x = wx - node.x, y = wy - node.y}
                         if game.wiring then game.wiring = nil end
                         return
                     end
                end
                
                -- Cancel if clicking empty space?
                if game.wiring then game.wiring = nil return end
            end
            
            -- Normal Game Interactions
            if not game.buildMode then
                -- ROLL Button
                -- Check Main Roulette Module
                local mainMod = game.modules[1]
                if mainMod and mainMod.isButtonHovered and mainMod:isButtonHovered(wx, wy) then
                    if mainMod:tryRoll(game) then 
                        -- Shockwave on button center
                        local bx = mainMod.x - mainMod.btnRoll.w/2
                        local by = mainMod.y + mainMod.btnRoll.y
                        Particles.spawnButtonShockwave(game, {x=bx, y=by, w=mainMod.btnRoll.w, h=mainMod.btnRoll.h}) 
                    end
                    return
                end
                
                -- Legacy Fallback (remove if confirmed obsolete)
                -- if wx >= btnRoll.x ... end
                -- No clock dragging here anymore
            end
        end
        
        -- Right Click
        if button == 2 then
            local wx, wy = getMouseWorldCoords()
            if game.isWiring then game.isWiring = false return end

            -- Build Mode Right Click (Disconnect)
            if game.buildMode then
                for _, cw in ipairs(game.clockWheels) do
                    local r = 90
                    local dist = math.sqrt((wx - cw.x)^2 + (wy - cw.y)^2)
                    if dist < r + 20 and cw.connected then
                         cw.connected = false
                         cw.connectionData = nil
                         Particles.spawnButtonShockwave(game, {x=cw.x-50, y=cw.y-50, w=100, h=100})
                         return
                    end
                    local outlets = getClockOutlets(cw)
                    for _, o in ipairs(outlets) do
                        if math.sqrt((wx - o.x)^2 + (wy - o.y)^2) < 30 and cw.connected then
                             cw.connected = false
                             cw.connectionData = nil
                             Particles.spawnButtonShockwave(game, {x=o.x-20, y=o.y-20, w=40, h=40})
                             return
                        end
                    end
                end
            end

            game.camera.dragging = true
        end

    elseif app.state == "SKILL_TREE" then
        SkillTree.handleMousePressed(x, y, button, game, getMouseGameCoords, buySpeed, buyLuck, function() app.state = "GAME" end)
    elseif app.state == "MENU" or app.state == "SETTINGS" or app.state == "PAUSED" then
        -- (Menu logic unchanged)
        local list
        if app.state == "MENU" then list = app.menuBtns
        elseif app.state == "SETTINGS" then list = app.settingsBtns
        else list = app.pauseBtns end
        for _, btn in ipairs(list) do
            local bx, by, bw, bh = drawMenuButton(btn, 0)
            if mx >= bx and mx <= bx+bw and my >= by and my <= by+bh then btn.action() end
        end
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if app.state == "SKILL_TREE" and game.skillCam.dragging then
        game.skillCam.x = game.skillCam.x + dx / game.scale
        game.skillCam.y = game.skillCam.y + dy / game.scale
    elseif app.state == "GAME" then
        -- Camera Panning (Right-drag)
        if game.camera.dragging then
            game.camera.x = game.camera.x + dx / (game.scale * game.camera.zoom)
            game.camera.y = game.camera.y + dy / (game.scale * game.camera.zoom)
        end
        
        -- ClockWheel Dragging (Left-drag) in Build Mode
        if game.draggingClock and game.buildMode then
            local wx, wy = getMouseWorldCoords()
            local targetX = wx - game.draggingClock.dragOffset.x
            local targetY = wy - game.draggingClock.dragOffset.y
            
            local rSelf = 130 -- Radius with padding for collision
            
            -- Resolve Main Wheel Collision
            -- Main Radius ~150 + Self ~130 = 280 Min Dist
            local mainX, mainY = V_WIDTH/2, V_HEIGHT/2
            local mainDistSq = (targetX - mainX)^2 + (targetY - mainY)^2
            local minDistMain = 280
            
            if mainDistSq < minDistMain * minDistMain then
                -- Push out
                local dist = math.sqrt(mainDistSq)
                local dx = (targetX - mainX) / dist
                local dy = (targetY - mainY) / dist
                targetX = mainX + dx * minDistMain
                targetY = mainY + dy * minDistMain
            end
            
            -- Resolve Other Clocks Collision
            -- Radius ~100 + Self ~130 = 230 Min Dist
            local minDistClock = 230
            for _, other in ipairs(game.clockWheels) do
                if other ~= game.draggingClock then
                    local distSq = (targetX - other.x)^2 + (targetY - other.y)^2
                    if distSq < minDistClock * minDistClock then
                        -- Push out
                        local dist = math.sqrt(distSq)
                        -- Avoid division by zero
                        if dist == 0 then dist = 1; dx = 1; dy = 0 
                        else 
                            local dx = (targetX - other.x) / dist
                            local dy = (targetY - other.y) / dist
                            targetX = other.x + dx * minDistClock
                            targetY = other.y + dy * minDistClock
                        end
                    end
                end
            end
            
            game.draggingClock.x = targetX
            game.draggingClock.y = targetY
            game.draggingClock.targetX = targetX -- Reset animation target
        end
    end
end

function love.mousereleased(x, y, button)
    -- Shop Interaction (Release for Press Effect)
    if game.shop and Shop.mousereleased(x, y, button, game) then
        return
    end

    if button == 1 then
        game.skillCam.dragging = false
        game.draggingClock = nil
        game.draggingPlinko = nil
        game.draggingNode = nil
        game.draggingGate = nil
    elseif button == 2 then
        game.camera.dragging = false
    end
end

function love.wheelmoved(x, y)
    -- 1. Check Shop Scroll
    if game.shop and game.shop.open then
        local mx, my = love.mouse.getPosition()
        local currentW = game.shop.targetWidth * game.shop.widthRatio
        local panelX = V_WIDTH - currentW
        
        -- If mouse over shop panel, scroll shop
        if mx >= panelX then
             Shop.wheelmoved(x, y)
             return
        end
    end

    if app.state == "GAME" then
        -- Camera Zoom (wider range for infinite world)
        game.camera.zoom = game.camera.zoom + y * 0.1
        if game.camera.zoom < 0.5 then game.camera.zoom = 0.5 end
        if game.camera.zoom > 2.0 then game.camera.zoom = 2.0 end
    elseif app.state == "SKILL_TREE" then
        game.skillCam.zoom = game.skillCam.zoom + y * 0.1
        if game.skillCam.zoom < 0.5 then game.skillCam.zoom = 0.5 end
        if game.skillCam.zoom > 2.0 then game.skillCam.zoom = 2.0 end
    end
end

-- KEYBOARD & INPUT logic (keeping as is at bottom)
function love.keypressed(key)
    if key == "escape" then 
        if game.placementMode then
             game.placementMode = nil
             return
        end
        
        if app.state == "GAME" then app.state = "PAUSED"
        elseif app.state == "PAUSED" then app.state = "GAME"
        elseif app.state == "SETTINGS" then app.state = "MENU"
        else love.event.quit() end
    end
    
    if key == "/" or key == "slash" then
        if not game.inputActive then
            game.inputActive = true
            game.inputText = "/"
            return
        end
    end
    
    if game.inputActive then
        if key == "return" or key == "kpenter" then
            processCommand(game.inputText)
            game.inputActive = false
            game.inputText = ""
        elseif key == "backspace" then
            local byteoffset = utf8.offset(game.inputText, -1)
            if byteoffset then
                game.inputText = string.sub(game.inputText, 1, byteoffset - 1)
            end
        end
    else
        if key == "space" then
             if game.wheel.phase == "READY" and game.cooldownTimer <= 0 then
                game.wheel:roll(game)
             end
        end
    end
end

function love.textinput(t)
    if game.inputActive then game.inputText = game.inputText .. t end
end

function processCommand(cmd)
    if cmd:sub(1,1) == "/" then cmd = cmd:sub(2) end
    local parts = {}
    for part in string.gmatch(cmd, "%S+") do table.insert(parts, part) end
    if parts[1] == "money" then
        local amount = tonumber(parts[2])
        if amount then game.gold = game.gold + amount end
    end
end

function drawNodeTooltip(node, x, y)
    if not node.stats then return end
    
    local padding = 10
    local lineHeight = 18 -- Reduced line height for smaller font
    
    -- Count stats to calculate height
    local count = 0
    if node.stats.speed then count = count + 1 end
    if node.stats.multi then count = count + 1 end
    if node.stats.luck then count = count + 1 end
    if node.stats.income then count = count + 1 end
    
    if count == 0 then return end

    local w = 280 -- Increased width
    local h = 40 + (count * lineHeight) 
    
    -- Draw separate block to the right of the node
    local bx = node.x + node.w/2 + 20
    local by = node.y - node.h/2
    
    -- Background
    love.graphics.setColor(0, 0, 0, 0.95)
    love.graphics.rectangle("fill", bx, by, w, h, 5)
    
    -- Header
    love.graphics.setColor(1, 1, 1, 1)
    if fontSmall then love.graphics.setFont(fontSmall) end -- Use Small Font
    
    love.graphics.print("STATS SUMMARY", bx + padding, by + padding)
    
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.line(bx + padding, by + padding + 18, bx + w - padding, by + padding + 18)
    
    local yOff = by + padding + 25
    
    -- Helper
    local function printStat(name, val, effect)
        love.graphics.setColor(0.8, 0.8, 0.8)
        love.graphics.print(name, bx + padding, yOff)
        
        love.graphics.setColor(0.4, 1.0, 0.4) -- Green for improved stats
        love.graphics.printf(effect, bx + padding, yOff, w - 2*padding, "right")
        yOff = yOff + lineHeight
    end
    
    if node.stats.speed then
        printStat("Speed Lvl " .. node.stats.speed.val, node.stats.speed.val, "Speed +20%")
    end
    if node.stats.multi then
        printStat("Multi Lvl " .. node.stats.multi.val, node.stats.multi.val, "Multi +0.2x")
    end
    -- Luck
    if node.stats.luck then
        local luckVal = node.stats.luck.val
        -- Calculate local chance contribution (without prestige for this line?)
        -- Or maybe show just the level gain.
        -- "Level 5 (+25% Chance)"
        local chance = luckVal * 5
        printStat("Luck (Lvl " .. luckVal .. ")", luckVal, "+" .. luckVal .. " Lvl (+" .. chance .. "%)")
    end
    if node.stats.income then
        printStat("Income Lvl " .. node.stats.income.val, node.stats.income.val, "+1 Gold/s")
    end
    
    -- PRESTIGE BLOCK (If Active)
    local prestigeMult = 1.0 + (PrestigeManager.prestigeBonus or 0)
    if prestigeMult > 1.0 then
        local ph = 40 + (3 * lineHeight) -- 3 lines of stats
        local py = by + h + 10 -- 10px spacing below main block
        
        -- Background
        love.graphics.setColor(0.1, 0, 0, 0.95) -- Slightly reddish background for prestige
        love.graphics.rectangle("fill", bx, py, w, ph, 5)
        
        -- Border
        love.graphics.setColor(1, 0.8, 0.2, 0.8) -- Gold border
        love.graphics.rectangle("line", bx, py, w, ph, 5)
        
        -- Header
        love.graphics.setColor(1, 0.8, 0.2, 1)
        love.graphics.print("PRESTIGE BONUSES", bx + padding, py + padding)
        
        love.graphics.setColor(0.5, 0.4, 0.1)
        love.graphics.line(bx + padding, py + padding + 18, bx + w - padding, py + padding + 18)
        
        local pOff = py + padding + 25
        local bonusPct = math.floor((prestigeMult - 1.0) * 100)
        
        -- Helper for Prestige Stats
        local function printPStat(name)
            love.graphics.setColor(1, 0.9, 0.7)
            love.graphics.print(name, bx + padding, pOff)
            love.graphics.setColor(0.2, 1.0, 0.2)
            love.graphics.printf("+" .. bonusPct .. "%", bx + padding, pOff, w - 2*padding, "right")
            pOff = pOff + lineHeight
        end
        
        printPStat("Spin Speed")
        printPStat("Luck & Clocks")
        printPStat("Plinko Gravity")
    end
end

