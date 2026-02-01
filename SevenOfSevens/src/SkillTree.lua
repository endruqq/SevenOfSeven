-- src/SkillTree.lua
local constants = require("constants")
local utils = require("utils")

local M = {}

local V_WIDTH = constants.V_WIDTH
local V_HEIGHT = constants.V_HEIGHT
local colors = constants.colors
local lerp = utils.lerp
local printBold = utils.printBold

function M.drawSkillTree(game, drawResourcePill, getMouseGameCoords, fontUI, fontSmall)
    local w, h = V_WIDTH, V_HEIGHT
    local cx, cy = w/2, h/2
    local cam = game.skillCam
    
    -- Draw Background Grid (moving)
    love.graphics.setColor(1, 1, 1, 0.05)
    local gridSize = 50
    local offsetX = (cam.x % gridSize) 
    local offsetY = (cam.y % gridSize)
    
    -- Could draw grid lines here...
    
    love.graphics.push()
    love.graphics.translate(cx + cam.x, cy + cam.y)
    
    -- Draw Connector Lines First
    love.graphics.setLineWidth(4)
    for _, node in ipairs(game.skillTree) do
        for _, parentId in ipairs(node.parents) do
            local parent = nil
            -- Optimize: Store parent ref instead of lookup? 
            -- For 200 nodes, lookup is acceptable for Love2D but could be better.
            for _, n in ipairs(game.skillTree) do if n.id == parentId then parent = n break end end
            
            if parent then
                if node.purchased and parent.purchased then
                    love.graphics.setColor(colors.ui_gold) -- Gold connection for maxed path
                elseif parent.purchased or parent.id == "root" then
                     -- Check if unlockable
                    local isUnlockable = true
                     -- Logic repeated from below, should cache "isUnlockable" in update or simple check
                    if node.unlocked then 
                        love.graphics.setColor(colors.highlight)
                    else
                        love.graphics.setColor(0.2, 0.2, 0.2)
                    end
                else
                    love.graphics.setColor(0.1, 0.1, 0.1)
                end
                
                -- Draw straight lines for grid look
                love.graphics.line(parent.x, parent.y, node.x, node.y)
            end
        end
    end
    
    -- Draw Nodes (Squares)
    for _, node in ipairs(game.skillTree) do
        local size = 40
        local hs = size/2
        
        -- Logic: Unlocked?
        local isUnlockable = false
        if not node.purchased then
            local parentsPurchased = true
            for _, pid in ipairs(node.parents) do
                 local parent = nil
                 for _, n in ipairs(game.skillTree) do if n.id == pid then parent = n break end end
                 if parent and not parent.purchased then parentsPurchased = false end
            end
            if #node.parents == 0 then parentsPurchased = true end -- Root
            node.unlocked = parentsPurchased
            isUnlockable = parentsPurchased
        end
        node.isUnlockable = isUnlockable or node.unlocked -- Persist unlock status if purchased
        
        -- Hover Check
        local mx, my = getMouseGameCoords()
        local wx = mx - (cx + cam.x)
        local wy = my - (cy + cam.y)
        local hover = (wx >= node.x - hs and wx <= node.x + hs and
                       wy >= node.y - hs and wy <= node.y + hs)
        node.hover = hover
        
        -- Visual State
        if node.purchased then
            love.graphics.setColor(colors.ui_gold)
            love.graphics.rectangle("fill", node.x - hs, node.y - hs, size, size)
            love.graphics.setColor(0, 0, 0)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", node.x - hs, node.y - hs, size, size)
        elseif isUnlockable then
            -- Available to buy
            love.graphics.setColor(0, 0, 0, 0.8)
            love.graphics.rectangle("fill", node.x - hs, node.y - hs, size, size)
            
            if hover then
                 love.graphics.setColor(colors.highlight)
                 love.graphics.setLineWidth(3)
                 -- Glow effect?
                 local glow = 4 + math.sin(love.timer.getTime()*5)*2
                 love.graphics.rectangle("line", node.x - hs - 2, node.y - hs - 2, size + 4, size + 4)
            else
                 love.graphics.setColor(colors.text) 
                 love.graphics.setLineWidth(2)
            end
            love.graphics.rectangle("line", node.x - hs, node.y - hs, size, size)
        else
            -- Locked
            love.graphics.setColor(0.1, 0.1, 0.1)
            love.graphics.rectangle("fill", node.x - hs, node.y - hs, size, size)
            love.graphics.setColor(0.3, 0.3, 0.3)
            love.graphics.setLineWidth(1)
            love.graphics.rectangle("line", node.x - hs, node.y - hs, size, size)
        end
        
        -- Inner Symbol (+)
        if not node.purchased then
            love.graphics.setColor(1, 1, 1, (isUnlockable and 1 or 0.2))
            love.graphics.setLineWidth(2)
            love.graphics.line(node.x - 5, node.y, node.x + 5, node.y)
            love.graphics.line(node.x, node.y - 5, node.x, node.y + 5)
        end
    end
    
    love.graphics.pop()
    
    -- Draw UI Overlay (HUD) - Tooltips
    for _, node in ipairs(game.skillTree) do
        if node.hover then
            local mx, my = getMouseGameCoords()
            local tipX = mx + 20
            local tipY = my - 20
            
            -- Tooltip Box Style (Neon Border)
            love.graphics.setFont(fontUI)
            local txtW = math.max(fontUI:getWidth(node.name), fontUI:getWidth(node.desc)) + 20
            local tw = math.max(txtW, 200)
            local th = 100
            
            love.graphics.setColor(0, 0, 0, 0.95)
            love.graphics.rectangle("fill", tipX, tipY, tw, th)
            
            love.graphics.setLineWidth(2)
            love.graphics.setColor(colors.highlight) -- Neon Cyan/Red
            love.graphics.rectangle("line", tipX, tipY, tw, th)
            
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(node.name, tipX + 10, tipY + 10)
            love.graphics.setFont(fontSmall)
            love.graphics.setColor(0.8, 0.8, 0.8)
            love.graphics.printf(node.desc, tipX + 10, tipY + 40, tw - 20, "left")
            
            if node.purchased then
                love.graphics.setColor(colors.ui_gold)
                love.graphics.print("OWNED", tipX + 10, tipY + 70)
            elseif node.isUnlockable then
                local canAfford = game.gold >= node.cost
                if canAfford then love.graphics.setColor(0, 1, 0) else love.graphics.setColor(1, 0, 0) end
                love.graphics.print("Cost: " .. node.cost .. " G", tipX + 10, tipY + 70)
            else
                love.graphics.setColor(0.5, 0.5, 0.5)
                love.graphics.print("LOCKED", tipX + 10, tipY + 70)
            end
        end
    end
    
    -- HUD Buttons
    -- "BACK" Button
    local bx, by = 20, V_HEIGHT - 60
    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle("fill", bx, by, 100, 40, 5)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fontUI)
    love.graphics.print("BACK", bx + 20, by + 5)
    
    -- Resources
    drawResourcePill(20, 20, "GOLD", game.gold, colors.ui_gold, "diamond", 1.0)
    drawResourcePill(20, 70, "ESSENCE", game.essence, {0.8, 0.3, 0.9}, "sparkle", 0.8)
end

function M.handleMousePressed(x, y, button, game, getMouseGameCoords, buySpeed, buyLuck, toGameParams)
    local mx, my = getMouseGameCoords()
    
    -- Check Back Button
    local bx, by = 20, V_HEIGHT - 60
    if mx >= bx and mx <= bx + 100 and my >= by and my <= by + 40 then
        toGameParams() 
        return
    end
    
    -- Check Nodes
    local w, h = V_WIDTH, V_HEIGHT
    local cx, cy = w/2, h/2
    local cam = game.skillCam
    
    local hitNode = false
    -- Iterate Reverse for Z-order click? Usually not needed if no overlap.
    for _, node in ipairs(game.skillTree) do
        if node.hover then
             hitNode = true
             -- Re-check unlock logic just in case
             -- Wait, we calculated 'isUnlockable' in draw loop.
             -- We need to recalculate or trust the state.
             -- Let's trust logic: purchased false means check parents.
             local isUnlockable = true
             if not node.purchased then
                 if #node.parents > 0 then
                      for _, pid in ipairs(node.parents) do
                           local parent = nil
                           for _, n in ipairs(game.skillTree) do if n.id == pid then parent = n break end end
                           if parent and not parent.purchased then isUnlockable = false end
                      end
                 end
             else
                 isUnlockable = false -- Already bought
             end
             
             if isUnlockable and game.gold >= node.cost then
                 game.gold = game.gold - node.cost
                 node.purchased = true
                 if node.effect then node.effect() end
                 
                 -- We don't need to manually unlock child nodes because next frame update
                 -- will check `parentsPurchased` for children naturally.
             end
        end
    end
    
    if not hitNode then
        game.skillCam.dragging = true
        game.skillCam.lastMx = x -- Screen coords
        game.skillCam.lastMy = y
    end
end

return M