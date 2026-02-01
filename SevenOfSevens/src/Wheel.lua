-- src/Wheel.lua
local constants = require("constants")
local utils = require("utils")

local Wheel = {}
Wheel.__index = Wheel

local V_WIDTH = constants.V_WIDTH
local V_HEIGHT = constants.V_HEIGHT
local colors = constants.colors
local lerp = utils.lerp
local easeOutCubic = utils.easeOutCubic
local getOctagonVertices = utils.getOctagonVertices
local drawDashedLine = utils.drawDashedLine

local frameCanvas = love.graphics.newCanvas(300, 300)

function Wheel.new()
    local self = setmetatable({}, Wheel)
    self.itemHeight = 80
    self.numbers = {1, 2, 3, 4, 5, 6, 7, 8, 9}
    self.offset = 0
    self.phase = "READY"
    self.timer = 0
    self.speed = 0
    self.spinDuration = 0
    self.result = nil
    self.stopDistance = 0
    self.targetOffset = 0
    self.initialStopOffset = 0
    self.stopDuration = 0
    self.pulseScale = 1.0     
    self.targetPulseScale = 1.0
    self.firstSpin = true -- Guaranteed first win flag
    self.artifactSlotEnabled = false -- Set by recalcStats when ArtifactNode connected
    return self
end

function Wheel:update(dt, game, checkWinCallback)
    if self.phase == "READY" then
    elseif self.phase == "SPINNING" then
        self.offset = self.offset + self.speed * dt
        self.timer = self.timer + dt
        if self.timer >= self.spinDuration then
            self:startStopping(game)
        end
    elseif self.phase == "STOPPING" then
        self.timer = self.timer + dt
        local t = self.timer / self.stopDuration
        if t >= 1 then
            t = 1
            if self.needsBounce and math.abs(self.overshootOffset or 0) > 5 then
                self.phase = "SETTLING"
                self.timer = 0
                self.settleStart = self.offset
                self.settleTarget = self.targetOffset
                self.settleDuration = 0.4 
            else
                self.phase = "RESULT"
                self.timer = 0
                self.offset = self.targetOffset 
                checkWinCallback(self.result)
                if self.result == 7 then self.targetPulseScale = 1.25 end
            end
        else
            self.offset = self.initialStopOffset + self.stopDistance * easeOutCubic(t)
        end
    elseif self.phase == "SETTLING" then
        self.timer = self.timer + dt
        local t = self.timer / self.settleDuration
        if t >= 1 then
            t = 1
            self.phase = "RESULT"
            self.timer = 0
            self.offset = self.settleTarget
            checkWinCallback(self.result)
            if self.result == 7 then self.targetPulseScale = 1.25 end
        else
            local ease = t < 0.5 and (2*t*t) or (1 - math.pow(-2*t + 2, 2) / 2)
            self.offset = lerp(self.settleStart, self.settleTarget, ease)
        end
    elseif self.phase == "RESULT" then
        self.timer = self.timer + dt
        if self.timer > 0.15 then self.targetPulseScale = 1.0 end
        if self.timer >= (0.5 * game.durationMult) then 
            self.phase = "READY" 
            self.result = nil
            self.needsBounce = false
        end
    end
    self.pulseScale = lerp(self.pulseScale, self.targetPulseScale, 15 * dt)
end

function Wheel:roll(game)
    if self.phase == "READY" and game.cooldownTimer <= 0 and not game.waitingForPlinko then
        game.cooldownTimer = game.currentCooldown
        self.phase = "SPINNING"
        
        -- Slow Spin for 7th Streak (Combo 6 -> 7)
        if game.combo == 6 then
            -- Disable acceleration (ignore spinSpeedMult) and slow by 50%
            self.speed = 1500 * 0.5 
        else
            self.speed = 1500 * game.spinSpeedMult
        end

        self.timer = 0
        self.spinDuration = (2.0 + math.random() * 1.0) * game.durationMult
        self.result = nil
        self.pulseScale = 1.0
        self.targetPulseScale = 1.0
        for _, cw in ipairs(game.clockWheels) do
            if cw.connected and not cw.connectionBlocked then
                -- NEW: Only trigger if connected to THIS machine
                if cw.connectionData and cw.connectionData.srcType == "main" then
                    cw:startSpin(self.spinDuration + 1.5)
                end
            end
        end
        return true 
    end
    return false
end

function Wheel:startStopping(game)
    self.phase = "STOPPING"
    local winningIndex
    
    if self.firstSpin then
        self.firstSpin = false
        -- Guaranteed 7
        for i, n in ipairs(self.numbers) do
            if n == 7 then winningIndex = i; break end
        end
        if not winningIndex then winningIndex = 1 end -- Fallback
    else
        -- Check Artifact Drop First (if enabled)
        local artifactChance = (game.artifactChance or 0) / 100
        if self.artifactSlotEnabled and math.random() < artifactChance then
            -- Artifact Drop! Use index 10 (special "?" slot)
            winningIndex = 10
            self.result = "?"
        else
            local bonusChance = game.luckyLevel * 0.05
            if math.random() < bonusChance then
                for i, n in ipairs(self.numbers) do
                    if n == 7 then winningIndex = i; break end
                end
                if not winningIndex then winningIndex = math.random(1, 9) end
            else
                winningIndex = math.random(1, 9)
            end
            self.result = self.numbers[winningIndex]
        end
    end
    
    -- If artifact, result is already set to "?"
    if winningIndex ~= 10 then
        self.result = self.numbers[winningIndex]
    end
    local minTravel = self.speed * (0.5 * game.durationMult)
    if minTravel < self.itemHeight * 10 then minTravel = self.itemHeight * 10 end
    local H = self.itemHeight
    local relativeSlots = (3 - winningIndex)
    while relativeSlots < 0 do relativeSlots = relativeSlots + 9 end
    while relativeSlots >= 9 do relativeSlots = relativeSlots - 9 end
    local currentPhase = self.offset / H
    local minTargetPhase = currentPhase + (minTravel / H)
    local K = math.ceil( (minTargetPhase - relativeSlots) / 9 )
    local targetPhase = K * 9 + relativeSlots
    local suspenseOffset = (math.random() - 0.5) * 0.9
    self.targetOffset = targetPhase * H
    self.overshootOffset = suspenseOffset * H  
    self.initialStopOffset = self.offset
    self.stopDistance = (self.targetOffset + self.overshootOffset) - self.initialStopOffset
    self.stopDuration = 4 * self.stopDistance / self.speed
    self.timer = 0
    self.needsBounce = true
    if self.result == 6 or self.result == 8 then
        self.settleDuration = 1.2 
        self.isNearMiss = true
    else
        self.settleDuration = 0.6
        self.isNearMiss = false
    end
end

function Wheel:draw(game, x, y)
    -- Default to screen center if not provided (Legacy support until full refactor)
    local cx = x or (V_WIDTH / 2)
    local cy = y or (V_HEIGHT / 2)
    
    local visibleCount = 5
    local containerH = visibleCount * self.itemHeight
    local containerW = 200
    
    local lineOffset = 80
    -- Dashed Lines: Start slightly later (top/bottom padding)
    local lineY1 = cy - containerH/2 + 30
    local lineY2 = cy + containerH/2 - 30
    
    love.graphics.setColor(1, 1, 1, 0.1) 
    drawDashedLine(cx - lineOffset, lineY1, cx - lineOffset, lineY2, 20, 15)
    drawDashedLine(cx + lineOffset, lineY1, cx + lineOffset, lineY2, 20, 15)
    
    -- Scissor logic using transformPoint to handle Camera/World transforms automatically
    local x1 = cx - containerW/2
    local y1 = cy - containerH/2
    local x2 = cx + containerW/2
    local y2 = cy + containerH/2
    
    local sx1, sy1 = love.graphics.transformPoint(x1, y1)
    local sx2, sy2 = love.graphics.transformPoint(x2, y2)
    
    local sw = sx2 - sx1
    local sh = sy2 - sy1
    
    love.graphics.setScissor(sx1, sy1, sw, sh)
    
    -- Need fonts. Assuming Global for now.
    love.graphics.setFont(fontLarge)
    
    -- Build display list (numbers + optional artifact slot)
    local displayItems = {}
    for _, n in ipairs(self.numbers) do
        table.insert(displayItems, n)
    end
    if self.artifactSlotEnabled then
        table.insert(displayItems, "?")
    end
    
    local itemCount = #displayItems
    local totalHeight = itemCount * self.itemHeight
    local renderOffset = self.offset % totalHeight
    
    for loop = -1, 1 do
        local loopY = loop * totalHeight
        for idx, n in ipairs(displayItems) do
            local finalY = (cy - 2.5 * self.itemHeight) + ((idx-1)*self.itemHeight) + renderOffset + loopY
            
            -- Color based on value
            if n == 7 then
                love.graphics.setColor(colors.highlight)
            elseif n == "?" then
                love.graphics.setColor(0.2, 0.5, 0.9) -- Blue for artifact
            else
                love.graphics.setColor(colors.text)
            end
            
            if finalY > cy - containerH and finalY < cy + containerH then
                local textW = fontLarge:getWidth(tostring(n))
                local textH = fontLarge:getHeight()
                love.graphics.print(tostring(n), cx - textW/2, finalY + (self.itemHeight - textH)/2)
            end
        end
    end
    love.graphics.setScissor()
    
    local frameH = self.itemHeight
    local frameW = frameH 
    
    -- Draw Frame Directly (No Canvas)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.scale(self.pulseScale, self.pulseScale)
    
    -- Frame Style
    love.graphics.setLineWidth(5 + 4 * game.jackpotIntensity)
    
    if game.jackpotIntensity > 0.1 then
         local r, g, b = colors.highlight[1], colors.highlight[2], colors.highlight[3]
         love.graphics.setColor(r, g, b, 1)
    else
         love.graphics.setColor(colors.frame_base)
    end
    
    -- Draw relative to local origin (0,0) because we translated to cx,cy
    -- getOctagonVertices returns coords centered at arguments.
    -- We want vertices centered at 0,0.
    local frameVerts = getOctagonVertices(0, 0, frameW, frameH, 15)
    love.graphics.polygon("line", frameVerts)
    
    love.graphics.pop()
    love.graphics.setShader() 
end

return Wheel
