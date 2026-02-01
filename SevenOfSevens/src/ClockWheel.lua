-- src/ClockWheel.lua
local constants = require("constants")
local utils = require("utils")
local SignalSystem = require("src.SignalSystem") -- NEW

local ClockWheel = {}
ClockWheel.__index = ClockWheel

local V_WIDTH = constants.V_WIDTH
local V_HEIGHT = constants.V_HEIGHT
local colors = constants.colors
local lerp = utils.lerp

function ClockWheel.new(x, y, tier)
    local self = setmetatable({}, ClockWheel)
    self.type = "clock" -- Explicit type for SignalSystem detection
    self.id = tostring(self) -- Unique ID for SignalSystem
    self.targetX = x
    self.y = y
    
    self.x = x
    self.y = y
    
    self.numbers = {1, 2, 3, 4, 5, 6, 7, 8, 9}
    self.phase = "COUNTDOWN"
    self.timer = 10.0
    self.maxTimer = 10.0
    self.angle = 0
    self.startAngle = 0
    self.targetAngle = 0
    self.spinTimer = 0
    self.spinDuration = 0 
    self.activeNumber = 1
    self.flashTimer = 0
    self.connected = false -- connection system
    self.nodeConnection = nil -- Node powering this clock
    self.triggeredByResult = nil -- Store signal payload
    self.signalQueue = {} -- NEW: Queue for sequential spins
    self.speedMult = 1.0 -- Global speed sync modifier
    
    -- Tier Stats
    self.tier = tier or 1
    self.tierMult = 1.0
    if self.tier == 2 then self.tierMult = 5.0
    elseif self.tier == 3 then self.tierMult = 25.0 end
    
    -- No Sockets for Upgrade Nodes (Only Main Roulette has those)
    -- Signal connections use getClockOutlets() in main.lua which defines cardinal outlets.
    
    return self
end
-- getSocketAt removed as it is only for Upgrade Nodes

-- ... keep update ...

function ClockWheel:draw(game)
    local r = 90
    local fw, fh = 60, 60 -- Slightly larger frame
    local frameX = self.x
    local frameY = self.y - r

    -- 1. Center Hub
    local cx, cy = self.x, self.y
    local indR = 30

    -- Hub Shadow
    love.graphics.setColor(0.1, 0.1, 0.1, 0.5)
    love.graphics.circle("fill", cx, cy + 4, indR)

    -- Hub Body (Dark Hexagon)
    love.graphics.setColor(0.15, 0.15, 0.2)
    love.graphics.circle("fill", cx, cy, indR)

    -- Hub Highlight/Ring
    love.graphics.setColor(colors.highlight)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", cx, cy, indR)

    -- Inner Dot
    love.graphics.circle("fill", cx, cy, 6)

    -- 2. Numbers
    local count = #self.numbers
    local angleStep = (math.pi * 2) / count
    
    love.graphics.setFont(fontBtn)
    for i, n in ipairs(self.numbers) do
        local angle = self.angle + (i-1) * angleStep - (math.pi/2) 
        local nx = self.x + math.cos(angle) * r
        local ny = self.y + math.sin(angle) * r

        -- Text Shadow
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.print(n, nx - fontBtn:getWidth(n)/2 + 2, ny - fontBtn:getHeight(n)/2 + 2)

        -- Text Color
        love.graphics.setColor(colors.text)
        if n == 7 then love.graphics.setColor(colors.highlight) end

        -- Highlight Active Number if passing through top?
        -- No, frame determines it.

        local tw = fontBtn:getWidth(n)
        local th = fontBtn:getHeight()
        love.graphics.print(n, nx - tw/2, ny - th/2)
    end

    -- 3. Selection Frame (Top)
    local color
    if self.phase == "RESULT" then
        if (love.timer.getTime() % 0.2) < 0.1 then
             color = colors.ui_gold
        else
             color = colors.highlight
        end
    else
        -- Tier Colors
        if self.tier == 1 then color = {0.6, 0.4, 0.3} -- Copper
        elseif self.tier == 2 then color = {0.8, 0.8, 0.9} -- Silver
        elseif self.tier == 3 then color = {1.0, 0.85, 0.2} -- Gold
        else color = colors.frame_base end
    end

    local verts = utils.getOctagonVertices(frameX, frameY, fw, fh, 15)

    -- Frame Background
    love.graphics.setColor(0.1, 0.1, 0.12, 0.9)
    love.graphics.polygon("fill", verts)

    -- Frame Outline
    love.graphics.setColor(color)
    love.graphics.setLineWidth(3)
    love.graphics.polygon("line", verts)
    -- Dashed overlay?
    love.graphics.setColor(1, 1, 1, 0.3)
    utils.drawDashedLine(verts[1], verts[2], verts[3], verts[4], 5, 5) -- Top Edge accent

    -- Info Text
    local infoText = self.infoText or ""
    if infoText ~= "" and self.phase == "RESULT" then
        love.graphics.setFont(fontUI)
        local ttw = fontUI:getWidth(infoText)
        local tth = fontUI:getHeight()

        -- Draw with background
        love.graphics.setColor(0, 0, 0, 0.7)
        local bx = self.x - ttw/2 - 5
        local by = self.y - tth/2 - 5
        love.graphics.rectangle("fill", bx, by, ttw + 10, tth + 10, 5)

        love.graphics.setColor(colors.ui_gold)
        love.graphics.print(infoText, self.x - ttw/2, self.y - tth/2)
    end
    
    -- Draw Sockets: REMOVED
end

function ClockWheel:drawGhost(x, y)
    local r = 90
    local fw, fh = 60, 60
    local frameX = x
    local frameY = y - r
    
    -- Hub
    local cx, cy = x, y
    local indR = 30
    love.graphics.setColor(colors.highlight[1], colors.highlight[2], colors.highlight[3], 0.3)
    love.graphics.circle("line", cx, cy, indR)
    
    -- Numbers
    local count = #self.numbers
    local angleStep = (math.pi * 2) / count
    
    love.graphics.setFont(fontBtn)
    for i, n in ipairs(self.numbers) do
        local angle = self.angle + (i-1) * angleStep - (math.pi/2) 
        local nx = x + math.cos(angle) * r
        local ny = y + math.sin(angle) * r
        love.graphics.setColor(colors.text[1], colors.text[2], colors.text[3], 0.5)
        local tw = fontBtn:getWidth(n)
        local th = fontBtn:getHeight()
        love.graphics.print(n, nx - tw/2, ny - th/2)
    end
    
    -- Frame
    local verts = utils.getOctagonVertices(frameX, frameY, fw, fh, 15)
    love.graphics.setColor(colors.frame_base[1], colors.frame_base[2], colors.frame_base[3], 0.5)
    love.graphics.polygon("line", verts)
end

function ClockWheel:update(dt, game)
    if self.phase == "BUILDING" then
        self.buildTimer = self.buildTimer + dt
        local speed = 8.0 * dt
        self.x = lerp(self.x, self.targetX, speed)
        self.angle = 0
        if math.abs(self.x - self.targetX) < 1 then
            self.x = self.targetX
            self.phase = "COUNTDOWN"
            self.timer = self.maxTimer
            self.angle = 0 
        end
    elseif self.phase == "COUNTDOWN" then
        -- Idle, waiting for signal
    elseif self.phase == "GATHERING" then
        -- Deprecated Phase (Removed for instant response)
        -- Fallthrough to immediate spin if somehow entered
        self:startSpin(1.5, self.triggeredByResult)
        
    elseif self.phase == "SPINNING" then
        self.spinTimer = self.spinTimer + dt
        local t = self.spinTimer / self.spinDuration
        if t >= 1 then
            t = 1
            self.phase = "RESULT"
            self.flashTimer = 0.5
            
            -- Process Result Logic
            local res = self.activeNumber
            local incoming = self.triggeredByResult or 0
            local mult = self.multiplier or 1 -- Multiplier is now constantly 1 in sequential mode (unless we keep it?)
            -- Queue mode means multiplier is usually 1.
            
            -- Match Logic
            if incoming == 7 and res == 7 then
                 local base = 77
                 local total = base * mult
                 self.infoText = "JACKPOT! ("..total..")"
                 game.gold = game.gold + total
                 local txt = "+"..total
                 if mult > 1 then txt = txt .. " (x"..mult..")" end
                 if spawnPopup then spawnPopup(txt, self.x, self.y - 50, colors.highlight, true, 0) end
            elseif incoming == res then
                 local base = 10
                 local total = base * mult
                 self.infoText = "MATCH! ("..total..")"
                 game.gold = game.gold + total
                 local txt = "+"..total
                 if mult > 1 then txt = txt .. " (x"..mult..")" end
                 if spawnPopup then spawnPopup(txt, self.x, self.y - 50, colors.ui_gold, true, 0) end
            end
            
            -- Broadcast
            SignalSystem.broadcast(self, res)
        end
        local ease = 1 - math.pow(1 - t, 3)
        self.angle = lerp(self.startAngle, self.targetAngle, ease)
    elseif self.phase == "RESULT" then
        self.flashTimer = self.flashTimer - dt
        if self.flashTimer <= -0.5 then
            -- CHECK QUEUE
            if #self.signalQueue > 0 then
                local nextSignal = table.remove(self.signalQueue, 1)
                -- Spin immediately for next signal
                self:startSpin(1.5, nextSignal.payload)
                self.phase = "SPINNING" -- Explicit set (startSpin does it too)
                if spawnPopup then spawnPopup("Next!", self.x, self.y - 50, colors.text, true, 0) end
            else
                self.phase = "COUNTDOWN"
                self.timer = self.maxTimer
                self.triggeredByResult = nil -- Reset payload
            end
        end
    end
end

function ClockWheel:onSignal(payload, source)
    -- Sequential Spin Logic (Queueing)
    if self.phase == "SPINNING" or self.phase == "RESULT" or self.phase == "GATHERING" then
        -- Add to Queue
        table.insert(self.signalQueue, {payload=payload, source=source})
        
        -- Visual Feedback
        if spawnPopup then spawnPopup("Queued!", self.x, self.y - 80, colors.highlight, true, 0) end
        return
    end

    -- Optimize: Always Spin Immediately (Sequential/Queue Mode)
    self:startSpin(1.5, payload)
end

function ClockWheel:startSpin(duration, triggeredByResult)
    self.phase = "SPINNING"
    self.spinTimer = 0
    self.startAngle = self.angle
    
    -- Apply Speed Multiplier (Global Sync)
    local sm = self.speedMult or 1.0
    self.spinDuration = duration / sm
    
    self.activeNumber = math.random(1, 9)
    self.infoText = "" -- Clear previous result text
    self.triggeredByResult = triggeredByResult 
    self.multiplier = 1 -- Reset Multiplier
    
    local count = #self.numbers
    local step = (math.pi * 2) / count
    local winningIndex = 1
    for i, n in ipairs(self.numbers) do
        if n == self.activeNumber then winningIndex = i; break end
    end
    local targetBase = -(winningIndex - 1) * step
    local currentRot = self.startAngle / (math.pi * 2)
    local extraSpins = math.ceil(duration * 2) 
    local nextRot = math.ceil(currentRot + extraSpins)
    self.targetAngle = targetBase + (nextRot * math.pi * 2)
end

return ClockWheel
