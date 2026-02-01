-- src/PrestigeManager.lua
local constants = require("constants")
local styles = constants.colors
local utils = require("utils")

local PrestigeManager = {}

function PrestigeManager.init()
    PrestigeManager.prestigeLevel = 0
    PrestigeManager.prestigeBonus = 0.0 -- 0.10 = +10%
    
    PrestigeManager.baseThreshold = 10000
    PrestigeManager.currentLiquidLevel = 0.0 -- 0 to 1 (visual)
    
    -- UI State
    PrestigeManager.container = {
        x = 50,
        y = constants.V_HEIGHT / 2 - 150,
        w = 60,
        h = 300
    }
    
    PrestigeManager.wavePhase = 0
end

function PrestigeManager.update(dt, game)
    -- Calculate Fill Level based on Gold
    -- Cap visual at 1.0 (full) but track overflow internally for text
    local ratio = game.gold / PrestigeManager.baseThreshold
    local targetLevel = math.min(ratio, 1.0)
    
    -- Smooth fill
    PrestigeManager.currentLiquidLevel = utils.lerp(PrestigeManager.currentLiquidLevel, targetLevel, 5 * dt)
    
    -- Wave Animation
    PrestigeManager.wavePhase = PrestigeManager.wavePhase + (3 * dt)
    
    -- Check Hover/Tooltip? Handled in draw/click
end

function PrestigeManager.draw(game)
    local c = PrestigeManager.container
    local fill = PrestigeManager.currentLiquidLevel
    
    -- Container Body (Glass/Dark Background)
    -- Style: Similar to Shop, dark panel
    love.graphics.setColor(0.05, 0.05, 0.08, 0.9)
    love.graphics.rectangle("fill", c.x, c.y, c.w, c.h, 5)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(0.3, 0.3, 0.35)
    love.graphics.rectangle("line", c.x, c.y, c.w, c.h, 5)
    
    -- Liquid (Red)
    if fill > 0.01 then
        love.graphics.setColor(0.9, 0.2, 0.2, 0.9)
        
        -- Create Wave Polygon
        local liquidH = c.h * fill
        local liquidTopY = c.y + c.h - liquidH
        
        local verts = {}
        -- Bottom-Right
        table.insert(verts, c.x + c.w)
        table.insert(verts, c.y + c.h)
        -- Bottom-Left
        table.insert(verts, c.x)
        table.insert(verts, c.y + c.h)
        
        -- Top Wave surface
        -- 10 segments
        local segments = 10
        local step = c.w / segments
        
        for i = 0, segments do
            local lx = c.x + i * step
            
            -- Sine wave offset
            -- Amplitude depends on fill? Maybe calmer when full?
            local amp = 3
            if fill >= 1.0 then amp = 1 end -- calmer at top
            
            local waveY = math.sin(PrestigeManager.wavePhase + i * 0.5) * amp
            
            table.insert(verts, lx)
            table.insert(verts, liquidTopY + waveY)
        end
        
        -- Need to order correctly? 
        -- Polygon: BL, BR, TR...TL?
        -- Verts list above: BR, BL, then... Left to Right along top?
        -- That results in BL -> BR -> L(top) -> R(top). 
        -- Polygon expects vertices in order.
        -- So: BR, TR(wave right side)... TL(wave left side), BL.
        -- Let's reconstruct.
        
        verts = {}
        -- Start Bottom-Left
        table.insert(verts, c.x)
        table.insert(verts, c.y + c.h)
        
        -- Start Bottom-Right
        table.insert(verts, c.x + c.w)
        table.insert(verts, c.y + c.h)
        
        -- Scan Top Right to Left
        for i = segments, 0, -1 do
            local lx = c.x + i * step
            local amp = 3
            if fill >= 1.0 then amp = 1 end
            local waveY = math.sin(PrestigeManager.wavePhase + i * 0.5) * amp
            
            table.insert(verts, lx)
            table.insert(verts, liquidTopY + waveY)
        end
        
        love.graphics.polygon("fill", verts)
    end
    
    -- Overlay "Glass" shine?
    love.graphics.setColor(1, 1, 1, 0.1)
    love.graphics.rectangle("fill", c.x + 5, c.y, 10, c.h, 2)
    
    -- Text / Status
    love.graphics.setFont(game.fontSmall)
    
    if game.gold >= PrestigeManager.baseThreshold then
        -- Ready
        local alpha = 0.5 + 0.5 * math.sin(love.timer.getTime() * 5)
        love.graphics.setColor(1, 0.8, 0.2, alpha)
        love.graphics.printf("PRESTIGE\nREADY", c.x, c.y + c.h/2 - 20, c.w, "center")
        
        -- Show Potential Bonus
        local nextBonus = PrestigeManager.calculateBonus(game.gold)
        local pct = math.floor(nextBonus * 100)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("+"..pct.."%", c.x, c.y + c.h/2 + 20, c.w, "center")
        
        -- Overflow
        if game.gold > PrestigeManager.baseThreshold then
             love.graphics.setColor(0.5, 1.0, 0.5)
             love.graphics.printf("OVERFLOW", c.x, c.y + c.h - 20, c.w, "center")
        end
    else
        love.graphics.setColor(1, 1, 1, 0.5)
        local pct = math.floor((game.gold / PrestigeManager.baseThreshold) * 100)
        love.graphics.printf(pct.."%", c.x, c.y + c.h/2 - 10, c.w, "center")
    end
end

function PrestigeManager.calculateBonus(gold)
    if gold < PrestigeManager.baseThreshold then return 0 end
    
    -- Base 10%
    local bonus = 0.10
    
    -- Overflow: +1% per 1000
    local overflow = gold - PrestigeManager.baseThreshold
    if overflow > 0 then
        local extra = math.floor(overflow / 1000) * 0.01
        bonus = bonus + extra
    end
    
    return bonus
end

function PrestigeManager.checkClick(x, y, game)
    -- Screen space click
    local c = PrestigeManager.container
    if x >= c.x and x <= c.x + c.w and y >= c.y and y <= c.y + c.h then
        if game.gold >= PrestigeManager.baseThreshold then
            -- Open Confirmation or Just Do It?
            -- "Reset Game? Yes/No" would be better but let's just do it for now or verify logic.
            -- Let's do it immediately as user request implied "can reset".
            PrestigeManager.performReset(game)
            return true
        end
    end
    return false
end

function PrestigeManager.performReset(game)
    local gainedBonus = PrestigeManager.calculateBonus(game.gold)
    
    PrestigeManager.prestigeLevel = PrestigeManager.prestigeLevel + 1
    PrestigeManager.prestigeBonus = PrestigeManager.prestigeBonus + gainedBonus
    
    -- RESET GAME STATE
    game.gold = 0
    game.tokensPerSecond = 0
    
    -- Modules
    -- Remove all except Main Roulette (index 1 usually)
    -- Assuming game.modules[1] is Main Roulette
    -- We need to keep Main Roulette instance clean
    local main = game.mainRoulette
    game.modules = { main }
    game.clockWheels = {}
    game.plinkoBoards = {}
    
    -- Wires?
    -- Main Roulette wiring should be cleared?
    -- Reset Node Connections on Main
    main.nodeConnection = nil
    
    -- Nodes
    game.nodes = {} -- Remove all nodes
    -- Re-add default/initial nodes? 
    -- Game starts with empty nodes usually, user builds them.
    
    -- Skill Tree?
    -- Usually prestige resets skill tree too.
    -- But keeping "stats" implies permanent upgrades might be separate.
    -- User said "zyskując stały bonus", implies stats gained from Prestige are permanent.
    -- Other things reset.
    -- Reset function for modules/nodes handles most logic.
    
    -- Reset Upgrades logic
    game.upgradeLevel = 0
    game.clockSpeedUpgrade = 0
    game.comboMultLevel = 0
    game.luckyLevel = 0
    game.sevenValueLevel = 0
    
    -- Spawn Visual Feedback
    if game.spawnPopup then
        game.spawnPopup("PRESTIGE!", constants.V_WIDTH/2, constants.V_HEIGHT/2, {1, 0.8, 0.2}, true, 0)
        game.spawnPopup("+" .. math.floor(gainedBonus*100) .. "% Bonus", constants.V_WIDTH/2, constants.V_HEIGHT/2 + 50, {0.5, 1, 0.5}, true, 0.5)
    end
    
    -- Recalculate global stats
    if recalcStats then recalcStats() end
end

return PrestigeManager
