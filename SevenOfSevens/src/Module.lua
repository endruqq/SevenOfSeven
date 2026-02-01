-- src/Module.lua
local Module = {}
Module.__index = Module

function Module.new(x, y, w, h)
    local self = setmetatable({}, Module)
    self.x = x or 0
    self.y = y or 0
    self.w = w or 100
    self.h = h or 100
    self.label = "Module"
    self.isDragging = false
    self.dragOffset = {x=0, y=0}
    return self
end

function Module:isHovered(mx, my)
    return mx >= self.x - self.w/2 and mx <= self.x + self.w/2 and
           my >= self.y - self.h/2 and my <= self.y + self.h/2
end

-- Abstract methods
function Module:update(dt) end
function Module:draw(game) end

return Module
