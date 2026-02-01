local constants = require("constants")
local colors = constants.colors
local utils = require("utils")
local SignalSystem = require("src.SignalSystem")

local LogicGate = {}
LogicGate.__index = LogicGate

function LogicGate.new(x, y, gateType)
    local self = setmetatable({}, LogicGate)
    self.x = x
    self.y = y
    self.w = 60
    self.h = 60
    self.type = "logic_gate"
    self.gateType = gateType or "AND" -- AND, OR, NOT, DELAY

    -- State
    self.inputs = {} -- Map of source -> value
    self.outputVal = 0
    self.connections = {} -- List of outgoing connections

    -- Visuals
    self.color = {0.2, 0.2, 0.2}
    if self.gateType == "AND" then self.color = {0.2, 0.6, 0.8}
    elseif self.gateType == "OR" then self.color = {0.8, 0.4, 0.2}
    elseif self.gateType == "NOT" then self.color = {0.8, 0.2, 0.2}
    elseif self.gateType == "DELAY" then self.color = {0.6, 0.6, 0.6}
    end

    -- Sockets (Inputs) & Outlets (Outputs)
    self:initSockets()

    return self
end

function LogicGate:initSockets()
    self.sockets = {} -- Inputs
    self.outlets = {} -- Outputs

    local w, h = self.w, self.h

    -- Inputs (Left Side)
    if self.gateType == "NOT" or self.gateType == "DELAY" then
        -- Single Input
        table.insert(self.sockets, {
            x = -w/2, y = 0,
            type = "input",
            index = 1,
            normal = {x=-1, y=0}
        })
    else
        -- Two Inputs
        table.insert(self.sockets, {
            x = -w/2, y = -15,
            type = "input",
            index = 1,
            normal = {x=-1, y=0}
        })
        table.insert(self.sockets, {
            x = -w/2, y = 15,
            type = "input",
            index = 2,
            normal = {x=-1, y=0}
        })
    end

    -- Output (Right Side)
    table.insert(self.outlets, {
        x = w/2, y = 0,
        type = "output",
        index = 1,
        normal = {x=1, y=0},
        isOutput = true,
        obj = self,
        parent = self
    })
end

function LogicGate:update(dt, game)
    -- Process Logic
    local val1 = self.inputs[1] or 0
    local val2 = self.inputs[2] or 0
    local res = 0

    if self.gateType == "AND" then
        if val1 > 0 and val2 > 0 then res = math.max(val1, val2) end
    elseif self.gateType == "OR" then
        res = math.max(val1, val2)
    elseif self.gateType == "NOT" then
        if val1 == 0 then res = 1 else res = 0 end
    elseif self.gateType == "DELAY" then
        -- TODO: Implement delay queue
        res = val1
    end

    self.outputVal = res

    -- Reset inputs for next frame (pulse logic)?
    -- Or hold state?
    -- SignalSystem usually is pulse based (startTurn clears).
    -- But if we want continuous logic, we need to clear inputs only when signal ends?
    -- For now, inputs are set by SignalSystem.broadcast which propagates immediately.
    -- We'll assume inputs are refreshed every turn or remain.
    -- Actually, SignalSystem.startTurn() should clear active signals.
    -- We need to clear our local input cache too?
    -- No, SignalSystem handles propagation.
end

function LogicGate:receiveSignal(val, source, slotIndex)
    local idx = slotIndex or 1
    self.inputs[idx] = val

    -- Generate Data Resource
    if game and game.data then
        game.data = game.data + 1
    end

    -- Propagate immediately? Or next update?
    -- Immediate for combinatorial logic
    self:update(0, nil)
    if self.outputVal > 0 then
        SignalSystem.broadcast(self, self.outputVal)
    end
end

function LogicGate:draw(game)
    love.graphics.setColor(self.color)
    local x, y, w, h = self.x, self.y, self.w, self.h

    -- Body
    love.graphics.rectangle("fill", x - w/2, y - h/2, w, h, 5)

    -- Symbol
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(game.fontBtn)
    local txt = self.gateType
    local tw = game.fontBtn:getWidth(txt)
    local th = game.fontBtn:getHeight()
    love.graphics.print(txt, x - tw/2, y - th/2)

    -- Sockets
    if game.buildMode then
        for _, s in ipairs(self.sockets) do
            utils.drawOutletShape(x + s.x, y + s.y, math.pi, 15) -- Left facing
        end
        for _, o in ipairs(self.outlets) do
            utils.drawOutletShape(x + o.x, y + o.y, 0, 15) -- Right facing
        end
    end
end

function LogicGate:drawGhost(x, y)
    self.x = x
    self.y = y
    self:draw({fontBtn = love.graphics.getFont()}) -- Mock game object
end

function LogicGate:hits(x, y)
    return x >= self.x - self.w/2 and x <= self.x + self.w/2 and
           y >= self.y - self.h/2 and y <= self.y + self.h/2
end

function LogicGate:getSocketAt(x, y)
    for _, s in ipairs(self.sockets) do
        local sx = self.x + s.x
        local sy = self.y + s.y
        local d = math.sqrt((x-sx)^2 + (y-sy)^2)
        if d < 20 then return {socket=s, x=sx, y=sy} end
    end
    return nil
end

return LogicGate
