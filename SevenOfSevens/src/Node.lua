-- Base Node Class
local utils = require("utils")
local constants = require("constants")

local Node = {}
Node.__index = Node

function Node.new(x, y, w, h)
    local self = setmetatable({}, Node)
    self.x = x
    self.y = y
    self.w = w or 100
    self.h = h or 100
    
    self.draggable = true
    self.dragging = false
    self.dragOffset = {x=0, y=0}
    
    self.inputs = {}
    self.outputs = {} -- Wiring sockets
    
    self.label = "NODE"
    return self
end

function Node:update(dt, game)
    -- Stub
end

function Node:draw(game)
    -- Stub debug
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.rectangle("fill", self.x - self.w/2, self.y - self.h/2, self.w, self.h)
end

function Node:hits(mx, my)
    return mx >= self.x - self.w/2 and mx <= self.x + self.w/2 and 
           my >= self.y - self.h/2 and my <= self.y + self.h/2
end

return Node
