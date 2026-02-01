-- Upgrade Node
local Node = require("src.Node")
local constants = require("constants")
local colors = constants.colors
local utils = require("utils")

local UpgradeNode = {}
setmetatable(UpgradeNode, {__index = Node})
UpgradeNode.__index = UpgradeNode

function UpgradeNode.new(x, y)
    local self = Node.new(x, y, 220, 160)
    setmetatable(self, UpgradeNode)
    
    self.label = "UPGRADE"
    
    -- Stats
    self.stats = {
        speed = {val=0, max=50, name="Speed"},
        multi = {val=0, max=50, name="Mult"},
        luck = {val=0, max=50, name="Luck"}, -- Only for Main Roulette
        income = {val=0, max=50, name="Income"} -- Passive Income
    }
    
    -- Sockets (Relative to center)
    -- outputs: List of available output points
    local w2, h2 = self.w/2, self.h/2
    local offset = 25 -- Sockets slightly outside the frame
    self.sockets = {
        {id="top", x=0, y=-(h2 + offset), type="output"},
        {id="bottom", x=0, y=(h2 + offset), type="output"},
        {id="left", x=-(w2 + offset), y=0, type="output"},
        {id="right", x=(w2 + offset), y=0, type="output"}
    }
    
    return self
end

function UpgradeNode:handleClick(wx, wy, game)
    local cx, cy = self.x, self.y
    local w, h = self.w, self.h
    local startY = cy - h/2 + 50
    local rowH = 35
    local i = 0
    
    for key, stat in pairs(self.stats) do
        local ry = startY + (i*rowH)
        
        -- Check Upgrade Button Click
        if stat.val < stat.max then
            local btnW, btnH = 60, 24
            local btnX = cx + w/2 - btnW - 15
            local btnY = ry
            
            -- Hitbox check
            if wx >= btnX and wx <= btnX + btnW and wy >= btnY and wy <= btnY + btnH then
                -- Try Purchase Upgrade
                local cost = math.ceil(1 * math.pow(1.25, stat.val))
                
                if game.gold >= cost then
                    game.gold = game.gold - cost
                    stat.val = stat.val + 1
                    -- Trigger Update recalculation? 
                    -- Stats are applied in real-time by the machine reading the node.
                    print("UPGRADED " .. key .. " to " .. stat.val)
                    if recalcStats then recalcStats() end
                    return true
                end
            end
        end
        i = i + 1
    end
    return false
end

function UpgradeNode:getSocketAt(wx, wy)
    for i, s in ipairs(self.sockets) do
        local sx = self.x + s.x
        local sy = self.y + s.y
        local dist = math.sqrt((wx - sx)^2 + (wy - sy)^2)
        if dist < 20 then -- Hit radius
            return {node=self, socket=s, x=sx, y=sy}
        end
    end
    return nil
end

function UpgradeNode:draw(game)
    local cx, cy = self.x, self.y
    local w, h = self.w, self.h
    
    -- Body Background (Tech Style)
    love.graphics.setColor(0.1, 0.1, 0.12, 0.95)
    love.graphics.rectangle("fill", cx - w/2, cy - h/2, w, h, 5) -- Small radius
    
    -- Tech Pattern (Local)
    love.graphics.setColor(1, 1, 1, 0.05)
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
    
    -- Border line
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 0.2)
    love.graphics.rectangle("line", cx - w/2, cy - h/2, w, h, 5)

    -- Header
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fontUI) 
    local header = "UPGRADE"
    local tw = fontUI:getWidth(header)
    love.graphics.print(header, cx - tw/2, cy - h/2 + 10)
    
    -- Stats Rows
    local startY = cy - h/2 + 50
    local rowH = 35
    local i = 0
    love.graphics.setFont(fontSmall)
    
    for key, stat in pairs(self.stats) do
        local ry = startY + (i*rowH)
        
        -- Name
        love.graphics.setColor(0.9, 0.9, 0.9)
        love.graphics.print(stat.name, cx - w/2 + 15, ry + 4)
        
        -- Level
        love.graphics.setColor(colors.highlight)
        local lvlText = "Lvl." .. stat.val
        love.graphics.print(lvlText, cx - w/2 + 80, ry + 4)
        
        -- Price Button
        if stat.val < stat.max then
            local cost = math.ceil(1 * math.pow(1.25, stat.val))
            local canAfford = game.gold >= cost
            
            local btnW, btnH = 60, 24
            local btnX = cx + w/2 - btnW - 15
            local btnY = ry
            
            -- Interaction Logic is handled in handleClick, here just visual state?
            -- Ideally we'd track hover/press per button for visuals, but standard is fine.
            local pressOffset = 0
            -- Check if mouse is hovering for visual feedback (optional)
            local mx, my = love.mouse.getPosition() -- Screen coords
            -- Wait, mx/my are screen. We need world for hit test.
            -- Skip hover effect for now unless we pass world mouse.

            -- Button Body (Octagon Shape)
            local bcx, bcy = btnX + btnW/2, btnY + btnH/2
            local chamfer = 6
            
            -- Shadow (Bottom Layer)
            love.graphics.setColor(0, 0, 0, 0.6)
            local shadowVerts = utils.getOctagonVertices(bcx, bcy + 3, btnW, btnH, chamfer)
            love.graphics.polygon("fill", shadowVerts)

            -- Cap
            if canAfford then
                love.graphics.setColor(colors.highlight[1], colors.highlight[2], colors.highlight[3], 1.0) -- RED
            else
                love.graphics.setColor(0.2, 0.2, 0.25, 1.0) -- Dark Gray
            end
            local capVerts = utils.getOctagonVertices(bcx, bcy, btnW, btnH, chamfer)
            love.graphics.polygon("fill", capVerts)
            
            -- Icon/Text Content
            love.graphics.setColor(1, 1, 1)
            local priceText = tostring(cost)
            local ptw = fontSmall:getWidth(priceText)
            local iconSz = 14
            local space = 4
            local totalW = ptw + iconSz + space
            
            local contentX = bcx - totalW/2
            local contentY = bcy - fontSmall:getHeight()/2
            
            -- Icon
            if game.imgToken then
                love.graphics.draw(game.imgToken, contentX, contentY + 1, 0, iconSz/game.imgToken:getWidth(), iconSz/game.imgToken:getHeight())
            else
                love.graphics.circle("fill", contentX + iconSz/2, contentY + iconSz/2, iconSz/2)
            end
            
            -- Text
            love.graphics.print(priceText, contentX + iconSz + space, contentY)
            
        else
            -- Maxed
            love.graphics.setColor(colors.ui_gold)
            love.graphics.print("MAX", cx + w/2 - 50, ry + 4)
        end
        
        i = i + 1
    end
    
    -- Draw Sockets (Red Circles)
    love.graphics.setLineWidth(2)
    for _, s in ipairs(self.sockets) do
        local sx = cx + s.x
        local sy = cy + s.y
        
        -- Red Outline/Fill
        love.graphics.setColor(0.05, 0.05, 0.05) -- bg
        love.graphics.circle("fill", sx, sy, 8)
        
        love.graphics.setColor(0.9, 0.2, 0.2) -- RED
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", sx, sy, 8)
        -- Small dot inside
        love.graphics.circle("fill", sx, sy, 3)
    end
end

return UpgradeNode
