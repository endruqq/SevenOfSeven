local utils = require("utils")
local constants = require("constants")
local colors = constants.colors
local SignalSystem = require("src.SignalSystem") -- NEW

local PlinkoBoard = {}
PlinkoBoard.__index = PlinkoBoard

function PlinkoBoard.new(x, y)
    local self = setmetatable({}, PlinkoBoard)
    self.id = tostring(self) -- Unique ID for SignalSystem
    self.x = x
    self.y = y
    self.type = "plinko" -- Identification for SignalSystem
    -- Store initial position to calculate delta for pegs
    self.initX = x
    self.initY = y
    
    self.w = 580
    self.h = 320
    self.active = false
    self.connected = false
    self.connectionBlocked = false
    self.unlocked = false 
    
    -- Physics Config
    self.gravity = 1100 
    self.restitution = 0.6
    self.friction = 0.99
    self.pegRadius = 7 
    self.ballRadius = 7
    
    -- State
    self.ball = nil -- {x, y, vx, vy, active} - positions are WORLD coords
    self.result = nil
    
    -- Visual Effects
    self.highlightSlot = nil
    self.highlightTimer = 0
    
    -- Generate Grid (stores ABSOLUTE positions based on initX, initY)
    self.pegs = {}
    self:generateGrid()
    
    -- Outlets for Clock Connections (positions relative to top-center (x,y))
    -- Left/Right: Center height | Bottom: Actual bottom
    -- Index 1 is reserved for TOP Input (Virtual in main.lua)
    self.outlets = {
        {id="left",   x=-self.w/2 - 20, y=self.h/2, angle=math.pi, horizontal=false, index=2},
        {id="right",  x=self.w/2 + 20,  y=self.h/2, angle=0,       horizontal=false, index=3},
        {id="bottom", x=0, y=self.h + 20,           angle=math.pi/2, horizontal=true, index=4}
    }
    
    -- Connected clocks (array of ClockWheel references)
    self.connectedClocks = {}
    
    -- No Sockets for Upgrade Nodes (Only Main Roulette has those)
    
    return self
end

-- getSocketAt removed as it is only for Upgrade Nodes

function PlinkoBoard:generateGrid()
    local rows = 7
    local cols = 11 
    
    local margin = 30
    local availableW = self.w - (margin * 2)
    local spacingX = availableW / (cols - 1)
    local spacingY = (self.h - 130) / rows
    
    local startY = self.initY + 80
    
    for r = 1, rows do
        local odd = (r % 2 == 1)
        local count = odd and cols or (cols - 1)
        local rowOffsetX = odd and 0 or (spacingX / 2)
        
        for c = 1, count do
            local localX = (c-1) * spacingX + rowOffsetX 
            local px = (self.initX - self.w/2 + margin) + localX
            local py = startY + (r-1) * spacingY
            
            table.insert(self.pegs, {x = px, y = py, r = self.pegRadius})
        end
    end
end

-- Helper: Get world position of peg accounting for board movement
function PlinkoBoard:getPegWorldPos(peg)
    local dx = self.x - self.initX
    local dy = self.y - self.initY
    return peg.x + dx, peg.y + dy
end

-- Check if any balls are currently active
function PlinkoBoard:hasActiveBalls()
    -- Check balls list
    if not self.balls then return false end
    for _, b in ipairs(self.balls) do
        if b.active then return true end
    end
    return false
end

function PlinkoBoard:onSignal(payload, source)
    -- Allow infinite re-activation for Multi-Ball support
    -- if SignalSystem.turnState.activatedModules[self.id] then return end
    SignalSystem.turnState.activatedModules[self.id] = true
    
    -- Drop Ball using payload as slot
    local slot = payload or 5
    if type(slot) ~= "number" then slot = 5 end
    -- Wrap or Clamp?
    if slot > 9 then slot = ((slot - 1) % 9) + 1 end
    
    self:dropBall(slot)
end

function PlinkoBoard:dropBall(slotIndex)
    -- Allow dropping via Signal even if not "connected" via manual wire check?
    -- Assume yes.
    
    self.active = true
    self.result = nil
    
    local margin = 20
    local availableW = self.w - (margin * 2)
    local slotWidth = availableW / 9
    
    local startX = (self.x - self.w/2 + margin) + (slotIndex - 1) * slotWidth + slotWidth/2
    local randOffset = (math.random() - 0.5) * 15
    
    local newBall = {
        x = startX + randOffset,
        y = self.y + 20,
        vx = (math.random() - 0.5) * 50, -- Small random kickoff
        vy = 0,
        active = true,
        startIndex = slotIndex,
        stuckTimer = 0
    }
    
    -- Ensure list exists
    self.balls = self.balls or {}
    table.insert(self.balls, newBall)
end

function PlinkoBoard:update(dt, game)
    -- Update ALL balls
    self.balls = self.balls or {} -- Safety init
    for i = #self.balls, 1, -1 do
        local ball = self.balls[i]
        
        if ball.active then
             -- Gravity
            ball.vy = ball.vy + self.gravity * dt
            ball.x = ball.x + ball.vx * dt
            ball.y = ball.y + ball.vy * dt
            
            -- Dampen horizontal
            ball.vx = ball.vx * self.friction
            
            -- Bounds Check (Sides)
            local left = self.x - self.w/2
            local right = self.x + self.w/2
            
            if ball.x < left + self.ballRadius then
                ball.x = left + self.ballRadius
                ball.vx = -ball.vx * 0.5
            elseif ball.x > right - self.ballRadius then
                ball.x = right - self.ballRadius
                ball.vx = -ball.vx * 0.5
            end
            
            -- Peg Collision
            for _, peg in ipairs(self.pegs) do
                local px, py = self:getPegWorldPos(peg)
                local distSq = (ball.x - px)^2 + (ball.y - py)^2
                local radiusSum = self.ballRadius + peg.r
                
                if distSq < radiusSum * radiusSum then
                    -- Collision!
                    local dist = math.sqrt(distSq)
                    local overlap = radiusSum - dist
                    local nx = (ball.x - px) / dist
                    local ny = (ball.y - py) / dist
                    
                    -- Resolve Position
                    ball.x = ball.x + nx * overlap
                    ball.y = ball.y + ny * overlap
                    
                    -- Reflect Velocity
                    local dot = ball.vx * nx + ball.vy * ny
                    ball.vx = (ball.vx - 2 * dot * nx) * self.restitution
                    ball.vy = (ball.vy - 2 * dot * ny) * self.restitution
                    
                    -- Add Random Chaos
                    ball.vx = ball.vx + (math.random() - 0.5) * 100
                end
            end
            
            -- Slot Detection (Bottom)
            if ball.y > self.y + self.h - 20 then
                self:checkResult(ball)
                -- Mark for removal
                ball.active = false
                table.remove(self.balls, i)
            end
        end
    end

    -- Visual Effects Update
    if self.highlightTimer > 0 then
        self.highlightTimer = self.highlightTimer - dt
        if self.highlightTimer <= 0 then
            self.highlightSlot = nil
        end
    end

    if not self.ball or not self.ball.active then return end
    
    local b = self.ball
    
    -- Gravity
    b.vy = b.vy + self.gravity * dt
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt
    
    -- Peg Collisions (use dynamic world positions)
    for _, p in ipairs(self.pegs) do
        local px, py = self:getPegWorldPos(p)
        local dx = b.x - px
        local dy = b.y - py
        local distSq = dx*dx + dy*dy
        local minDist = self.ballRadius + p.r
        
        if distSq < minDist * minDist then
            local dist = math.sqrt(distSq)
            if dist == 0 then dist = 1; dx = 0; dy = 1 end
            
            local nx = dx / dist
            local ny = dy / dist
            
            local overlap = minDist - dist + 0.5 
            b.x = b.x + nx * overlap
            b.y = b.y + ny * overlap
            
            local dot = b.vx * nx + b.vy * ny
            b.vx = b.vx - 2 * dot * nx
            b.vy = b.vy - 2 * dot * ny
            
            b.vx = b.vx * self.restitution
            b.vy = b.vy * self.restitution
            
            local jitter = 60 
            b.vx = b.vx + (math.random() - 0.5) * jitter
            
            if math.abs(b.vx) < 5 then b.vx = (math.random() > 0.5 and 10 or -10) end
        end
    end
    
    -- Walls (Clamp Position to fix tunneling)
    local wallL = self.x - self.w/2 + self.ballRadius
    local wallR = self.x + self.w/2 - self.ballRadius
    
    if b.x < wallL then 
        b.x = wallL
        b.vx = -b.vx * 0.5 
    elseif b.x > wallR then
        b.x = wallR
        b.vx = -b.vx * 0.5
    end
    
    -- Slot Dividers Collision
    local divH = 60
    local divTopY = self.y + self.h - divH
    
    -- Optimization: Only check if ball is low enough
    if b.y > divTopY - self.ballRadius then
        local margin = 30
        local availableW = self.w - (margin * 2)
        local slotWidth = availableW / 9
        
        -- Check all 10 dividers (Left of slot 1 ... Right of slot 9)
        for i = 1, 10 do
            local divX = (self.x - self.w/2 + margin) + (i-1)*slotWidth
            
            -- Horizontal distance check
            if math.abs(b.x - divX) < self.ballRadius then
                -- Vertical check (Ball must be within the vertical range of the divider)
                if b.y > divTopY then
                    -- Collision Logic
                    
                    -- 1. Push Out (Clamp)
                    if b.x < divX then
                        b.x = divX - self.ballRadius - 1 -- slight push
                    else
                        b.x = divX + self.ballRadius + 1
                    end
                    
                    -- 2. Reflect Velocity
                    b.vx = -b.vx * 0.5 -- Lose some energy
                end
            end
        end
    end
    
    -- Bottom (Slots)
    if b.y > self.y + self.h then
        b.active = false
        self.active = false
        
        local margin = 30
        local availableW = self.w - (margin * 2)
        local relX = b.x - (self.x - self.w/2 + margin)
        local slotWidth = availableW / 9
        local slot = math.floor(relX / slotWidth) + 1
        
        if slot < 1 then slot = 1 end
        if slot > 9 then slot = 9 end
        
        self.result = slot
        
        -- Trigger Highlight
        self.highlightSlot = slot
        self.highlightTimer = 0.5 -- Flash for 0.5 seconds
        
        -- Broadcast Result
        SignalSystem.broadcast(self, slot)
        
        return slot
    end
end

function PlinkoBoard:drawGhost(x, y)
    -- Frame (Semi-transparent)
    local cx, cy = x, y + self.h/2
    local w2, h2 = self.w/2, self.h/2
    
    local x1 = cx - w2
    local y1 = cy - h2
    local x2 = cx + w2
    local y2 = cy + h2
    
    love.graphics.setColor(1, 1, 1, 0.1)
    love.graphics.setLineWidth(3)
    utils.drawDashedLine(x1, y1, x1, y2, 20, 15) -- Left
    utils.drawDashedLine(x2, y1, x2, y2, 20, 15) -- Right
    
    love.graphics.setColor(1, 0.2, 0.2, 0.3) 
    utils.drawDashedLine(x1, y1, x2, y1, 20, 15) -- Top
    utils.drawDashedLine(x1, y2, x2, y2, 20, 15) -- Bottom
    
    -- Pegs
    love.graphics.setColor(1, 1, 1, 0.3)
    -- Simplified grid
    local rows = 7
    local cols = 11 
    local margin = 30
    local availableW = self.w - (margin * 2)
    local spacingX = availableW / (cols - 1)
    local spacingY = (self.h - 130) / rows
    local startY = (y + self.initY) + 80 - self.initY -- relative Y adjustment
    
    for r = 1, rows, 2 do -- Draw fewer pegs for ghost
        for c = 1, cols, 2 do
            local px = (x - self.w/2 + margin) + (c-1)*spacingX
            local py = y + 80 + (r-1)*spacingY
            love.graphics.circle("fill", px, py, 4)
        end
    end
end

function PlinkoBoard:draw(game)
    -- Frame (Dashed Rectangular Design)
    local cx, cy = self.x, self.y + self.h/2
    local w2, h2 = self.w/2, self.h/2
    
    local x1 = cx - w2
    local y1 = cy - h2
    local x2 = cx + w2
    local y2 = cy + h2
    
    -- Side Borders (White, 0.1 Alpha - Matches Main Roulette)
    love.graphics.setColor(1, 1, 1, 0.1)
    love.graphics.setLineWidth(3) -- Slightly thicker for visibility
    utils.drawDashedLine(x1, y1, x1, y2, 20, 15) -- Left
    utils.drawDashedLine(x2, y1, x2, y2, 20, 15) -- Right
    
    -- Top & Bottom Borders (RED - Matches logic outlet)
    -- Using logic red highlight color or standard red
    love.graphics.setColor(1, 0.2, 0.2, 0.8) -- Bright Red
    utils.drawDashedLine(x1, y1, x2, y1, 20, 15) -- Top
    utils.drawDashedLine(x1, y2, x2, y2, 20, 15) -- Bottom
    
    
    -- Pegs (draw at dynamic world positions)
    love.graphics.setColor(1, 1, 1, 0.9)
    for _, p in ipairs(self.pegs) do
        local px, py = self:getPegWorldPos(p)
        love.graphics.circle("fill", px, py, p.r, 100)
    end
    
    -- Slots Markers (use CURRENT self.x, self.y)
    local margin = 30
    local availableW = self.w - (margin * 2)
    local slotWidth = availableW / 9
    
    love.graphics.setFont(fontPlinkoSmall or fontSmall) 
    
    for i = 1, 9 do
        local bx = (self.x - self.w/2 + margin) + (i-1)*slotWidth
        
        -- Highlight Background if Active
        if self.highlightSlot == i then
            -- Use unified highlight color (Red/Crimson)
            local r, g, b = colors.highlight[1], colors.highlight[2], colors.highlight[3]
            love.graphics.setColor(r, g, b, 0.4) 
            -- Draw rect for the slot bottom area
            love.graphics.rectangle("fill", bx, self.y + self.h - 60, slotWidth, 60)
        end
        
        -- BOTTOM NUMBERS
        love.graphics.setColor(1, 1, 1)
        local text = tostring(i)
        local tw = (fontPlinkoSmall or fontSmall):getWidth(text)
        love.graphics.print(text, bx + slotWidth/2 - tw/2, self.y + self.h - 50)
        
        -- BOTTOM DIVIDERS
        love.graphics.setColor(0.9, 0.25, 0.25, 0.5)
        love.graphics.setLineWidth(3)
        local divH = 60
        love.graphics.line(bx, self.y + self.h - divH, bx, self.y + self.h)
        if i == 9 then
             love.graphics.line(bx + slotWidth, self.y + self.h - divH, bx + slotWidth, self.y + self.h)
        end
        
        -- TOP NUMBERS
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.print(text, bx + slotWidth/2 - tw/2, self.y + 10)
        
        -- TOP DIVIDERS
        love.graphics.setColor(0.9, 0.25, 0.25, 0.5)
        love.graphics.line(bx, self.y, bx, self.y + 15)
        if i == 9 then
            love.graphics.line(bx + slotWidth, self.y, bx + slotWidth, self.y + 15)
        end
        
         -- Draw Sockets: REMOVED (Only Main Roulette has Upgrade Sockets)

    end
    
    -- Ball
    self.balls = self.balls or {} -- Safety init for existing instances
    for _, ball in ipairs(self.balls) do
        if ball.active then
            love.graphics.setColor(1.0, 0.2, 0.2)
            love.graphics.circle("fill", ball.x, ball.y, self.ballRadius, 100)
            love.graphics.setColor(1, 1, 1)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line", ball.x, ball.y, self.ballRadius, 100)
        end
    end
    
    -- Connection Blocked Overlay
    if self.connectionBlocked then
        love.graphics.setColor(1, 0, 0, 0.3)
        -- Use simple rectangle overlay
        love.graphics.rectangle("fill", self.x - self.w/2, self.y, self.w, self.h)
    end
end
function PlinkoBoard:checkResult(ball)
    -- Slot Detection Logic
    local margin = 30
    local availableW = self.w - (margin * 2)
    local slotWidth = availableW / 9
    local relativeX = ball.x - (self.x - self.w/2 + margin)
    local slotIndex = math.ceil(relativeX / slotWidth)
    
    -- Clamp slot index
    if slotIndex < 1 then slotIndex = 1 end
    if slotIndex > 9 then slotIndex = 9 end
    
    -- Multipliers (Center is lower risk/reward? Or Standard Plinko: High-Low-High)
    -- 9 Slots. Center is 5.
    -- Pattern: 10x, 5x, 2x, 1x, 0.5x, 1x, 2x, 5x, 10x ?
    -- Let's use: 10, 3, 1.5, 1, 0.5, 1, 1.5, 3, 10
    local mults = {10, 3, 1.5, 1, 0.5, 1, 1.5, 3, 10}
    local mult = mults[slotIndex] or 1
    
    -- Apply Global Multipliers?
    mult = mult * (self.payoutMult or 1)
    
    -- Calculate Win
    local baseValue = game.lastWinAmount or 10 -- Triggered by what?
    -- If Plinko was triggered manually (cost 100), base is?
    -- If triggered by Clock/Main, base is passed in payload?
    -- 'ball' object doesn't store payload from onSignal?
    -- onSignal stored nothing on the ball?
    -- Step 783: `newBall` definition. No payload.
    -- We should assume a base value or store it on ball.
    
    local win = math.floor(baseValue * mult)
    game.gold = game.gold + win
    
    -- Feedback
    self.highlightSlot = slotIndex
    self.highlightTimer = 0.5
    
    if spawnPopup then 
        local col = colors.ui_gold
        spawnPopup("+"..win, ball.x, self.y + self.h, col, true, 0)
    end
    
    -- Broadcast result to connected output
    -- Payload: The multiplier or the slot index?
    -- Daisy chaining: Clock needs a number result?
    -- Plinko doesn't produce "numbers" 1-9 like a clock.
    -- But maybe we map Slot 5 -> 7?
    -- Or just pass 7 to trigger "Jackpot" behavior in clocks?
    -- Or pass slotIndex?
    SignalSystem.broadcast(self, slotIndex)
end

return PlinkoBoard
