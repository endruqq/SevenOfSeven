-- Artifact Node
local Node = require("src.Node")
local constants = require("constants")
local colors = constants.colors
local utils = require("utils")

local ArtifactNode = {}
setmetatable(ArtifactNode, {__index = Node})
ArtifactNode.__index = ArtifactNode

-- Blue color scheme
ArtifactNode.accentColor = {0.2, 0.5, 0.9}

function ArtifactNode.new(x, y)
    local self = Node.new(x, y, 180, 100)
    setmetatable(self, ArtifactNode)
    
    self.label = "ARTIFACT"
    self.nodeType = "artifact" -- For detection in recalcStats
    
    -- Stats (Single: Artifact Chance)
    self.stats = {
        artifactChance = {val=1, max=20, name="Drop %"} -- Base 1%, max 20%
    }
    
    -- Sockets (4 outputs)
    local w2, h2 = self.w/2, self.h/2
    local offset = 25
    self.sockets = {
        {id="top", x=0, y=-(h2 + offset), type="output"},
        {id="bottom", x=0, y=(h2 + offset), type="output"},
        {id="left", x=-(w2 + offset), y=0, type="output"},
        {id="right", x=(w2 + offset), y=0, type="output"}
    }
    
    return self
end

function ArtifactNode:handleClick(wx, wy, game)
    local cx, cy = self.x, self.y
    local w, h = self.w, self.h
    local stat = self.stats.artifactChance
    
    -- Single row for artifact chance
    local ry = cy - h/2 + 50
    
    if stat.val < stat.max then
        local btnW, btnH = 60, 24
        local btnX = cx + w/2 - btnW - 15
        local btnY = ry
        
        if wx >= btnX and wx <= btnX + btnW and wy >= btnY and wy <= btnY + btnH then
            local cost = math.ceil(5 * math.pow(1.5, stat.val))
            
            if game.gold >= cost then
                game.gold = game.gold - cost
                stat.val = stat.val + 1
                print("UPGRADED artifactChance to " .. stat.val .. "%")
                if recalcStats then recalcStats() end
                return true
            end
        end
    end
    return false
end

function ArtifactNode:getSocketAt(wx, wy)
    for i, s in ipairs(self.sockets) do
        local sx = self.x + s.x
        local sy = self.y + s.y
        local dist = math.sqrt((wx - sx)^2 + (wy - sy)^2)
        if dist < 20 then
            return {node=self, socket=s, x=sx, y=sy}
        end
    end
    return nil
end

function ArtifactNode:draw(game)
    local cx, cy = self.x, self.y
    local w, h = self.w, self.h
    local accent = ArtifactNode.accentColor
    
    -- Body Background (Blue Tinted)
    love.graphics.setColor(0.08, 0.1, 0.15, 0.95)
    love.graphics.rectangle("fill", cx - w/2, cy - h/2, w, h, 5)
    
    -- Tech Pattern (Blue dots)
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.1)
    local dotSpacing = 20
    local startX = cx - w/2
    local startY = cy - h/2
    local cols = math.floor(w / dotSpacing)
    local rows = math.floor(h / dotSpacing)
    
    for dy = 0, rows do 
        for dx = 0, cols do
            local px = startX + dx * dotSpacing + 10
            local py = startY + dy * dotSpacing + 10
            if px < cx + w/2 and py < cy + h/2 then
                if (dx + dy) % 3 == 0 then love.graphics.circle("fill", px, py, 2)
                else love.graphics.circle("fill", px, py, 1) end
            end
        end
    end
    
    -- Border (Blue)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(accent[1], accent[2], accent[3], 0.5)
    love.graphics.rectangle("line", cx - w/2, cy - h/2, w, h, 5)

    -- Header
    love.graphics.setColor(accent[1], accent[2], accent[3], 1)
    love.graphics.setFont(fontUI) 
    local header = "ARTIFACT"
    local tw = fontUI:getWidth(header)
    love.graphics.print(header, cx - tw/2, cy - h/2 + 10)
    
    -- Stat Row
    local stat = self.stats.artifactChance
    local ry = cy - h/2 + 50
    love.graphics.setFont(fontSmall)
    
    -- Name
    love.graphics.setColor(0.9, 0.9, 0.9)
    love.graphics.print(stat.name, cx - w/2 + 15, ry + 4)
    
    -- Level (as percentage)
    love.graphics.setColor(accent[1], accent[2], accent[3])
    local lvlText = stat.val .. "%"
    love.graphics.print(lvlText, cx - w/2 + 70, ry + 4)
    
    -- Upgrade Button
    if stat.val < stat.max then
        local cost = math.ceil(5 * math.pow(1.5, stat.val))
        local canAfford = game.gold >= cost
        
        local btnW, btnH = 60, 24
        local btnX = cx + w/2 - btnW - 15
        local btnY = ry
        
        local bcx, bcy = btnX + btnW/2, btnY + btnH/2
        local chamfer = 6
        
        -- Shadow
        love.graphics.setColor(0, 0, 0, 0.6)
        local shadowVerts = utils.getOctagonVertices(bcx, bcy + 3, btnW, btnH, chamfer)
        love.graphics.polygon("fill", shadowVerts)

        -- Cap (Blue if affordable)
        if canAfford then
            love.graphics.setColor(accent[1], accent[2], accent[3], 1.0)
        else
            love.graphics.setColor(0.2, 0.2, 0.25, 1.0)
        end
        local capVerts = utils.getOctagonVertices(bcx, bcy, btnW, btnH, chamfer)
        love.graphics.polygon("fill", capVerts)
        
        -- Price Text
        love.graphics.setColor(1, 1, 1)
        local priceText = tostring(cost)
        local ptw = fontSmall:getWidth(priceText)
        local iconSz = 14
        local space = 4
        local totalW = ptw + iconSz + space
        
        local contentX = bcx - totalW/2
        local contentY = bcy - fontSmall:getHeight()/2
        
        if game.imgToken then
            love.graphics.draw(game.imgToken, contentX, contentY + 1, 0, iconSz/game.imgToken:getWidth(), iconSz/game.imgToken:getHeight())
        else
            love.graphics.circle("fill", contentX + iconSz/2, contentY + iconSz/2, iconSz/2)
        end
        
        love.graphics.print(priceText, contentX + iconSz + space, contentY)
        
    else
        love.graphics.setColor(accent[1], accent[2], accent[3])
        love.graphics.print("MAX", cx + w/2 - 50, ry + 4)
    end
    
    -- Draw Sockets (Blue Circles)
    love.graphics.setLineWidth(2)
    for _, s in ipairs(self.sockets) do
        local sx = cx + s.x
        local sy = cy + s.y
        
        love.graphics.setColor(0.05, 0.05, 0.05)
        love.graphics.circle("fill", sx, sy, 8)
        
        love.graphics.setColor(accent[1], accent[2], accent[3])
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", sx, sy, 8)
        love.graphics.circle("fill", sx, sy, 3)
    end
end

return ArtifactNode
