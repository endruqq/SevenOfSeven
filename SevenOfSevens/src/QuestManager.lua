-- src/QuestManager.lua
local constants = require("constants")
local styles = constants.colors
local utils = require("utils")

local QuestManager = {}

-- Initialize immediately to prevent nil access if update is called before init
QuestManager.list = {
    {
        id = "intro_seven",
        name = "Feeling Lucky?",
        desc = "Roll a single 7.",
        target = 1,
        reward = 100,
        goalType = "roll_seven" -- Special internal type
    },
    {
        id = "streak_3",
        name = "Three of a Kind",
        desc = "Roll 3 Sevens in a row.",
        target = 3,
        reward = 500,
        goalType = "streak"
    },
    {
        id = "streak_7",
        name = "Jackpot Mastery",
        desc = "Roll 7 Sevens in a row.",
        target = 7,
        reward = 2500,
        goalType = "streak"
    },
    {
        id = "wealth_10k",
        name = "Wealth Hoarder",
        desc = "Accumulate 10,000 Tokens.",
        target = 10000,
        reward = 10000,
        goalType = "gold"
    }
}

QuestManager.currentIndex = 1
QuestManager.isOpen = false
QuestManager.completed = false
QuestManager.claimed = false

-- UI State
QuestManager.btn = {x=0, y=0, w=50, h=50, r=25}
QuestManager.window = {x=0, y=0, w=400, h=250}

-- Transient state
QuestManager.hasRolledSeven = false

function QuestManager.init()
    -- Reset state if needed, or re-init specific values
    QuestManager.currentIndex = 1
    QuestManager.isOpen = false
    QuestManager.completed = false
    QuestManager.hasRolledSeven = false
end

function QuestManager.update(dt, game)
    local q = QuestManager.list[QuestManager.currentIndex]
    if not q then return end -- All done
    
    local progress = QuestManager.getProgress(q, game)
    
    if progress >= q.target and not QuestManager.completed then
        QuestManager.completed = true
        -- Notify usage? "Quest Complete!"
        if game.spawnPopup then 
             -- game.spawnPopup("Quest Complete!", QuestManager.btn.x, QuestManager.btn.y + 50, {0.2, 1.0, 0.2}, true, 0)
        end
    end
end

function QuestManager.getProgress(q, game)
    if q.goalType == "roll_seven" then
        return QuestManager.hasRolledSeven and 1 or 0
    elseif q.goalType == "streak" then
        return game.combo or 0
    elseif q.goalType == "gold" then
        return math.floor(game.gold)
    end
    return 0
end

function QuestManager.onRollResult(res)
    if res == 7 then
        local q = QuestManager.list[QuestManager.currentIndex]
        if q and q.goalType == "roll_seven" then
            QuestManager.hasRolledSeven = true
        end
    end
end

function QuestManager.draw(game)
    local w, h = love.graphics.getDimensions()
    
    -- 1. Draw Icon (Top Right, left of Build Button)
    -- Build button is at V_WIDTH - 80.
    local bx = constants.V_WIDTH - 150
    local by = 80
    QuestManager.btn.x = bx
    QuestManager.btn.y = by
    
    local mx, my = love.mouse.getPosition()
    -- Scale considerations handled by game.scale? 
    -- Actually love.mouse.getPosition is raw window coords.
    -- We draw in Screen Space (after pop() in main.lua or specialized UI section).
    -- Assuming this is called in the same block as btnBuild.
    
    -- Button Body
    love.graphics.setColor(0.1, 0.1, 0.15)
    love.graphics.circle("fill", bx + 25, by + 25, 30)
    
    -- Border (Pulse if completed)
    if QuestManager.completed then
        local alpha = 0.5 + 0.5 * math.sin(love.timer.getTime() * 5)
        love.graphics.setColor(0.2, 1.0, 0.2, alpha)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", bx + 25, by + 25, 30)
    else
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", bx + 25, by + 25, 30)
    end
    
    -- Icon (!)
    love.graphics.setFont(game.fontBtn or love.graphics.getFont())
    love.graphics.setColor(1, 1, 1)
    local txt = "!"
    local tw = love.graphics.getFont():getWidth(txt)
    local th = love.graphics.getFont():getHeight()
    love.graphics.print(txt, bx + 25 - tw/2, by + 25 - th/2)
    
    -- 2. Draw Window if Open
    if QuestManager.isOpen then
        local qw, qh = QuestManager.window.w, QuestManager.window.h
        local qx = constants.V_WIDTH/2 - qw/2
        local qy = constants.V_HEIGHT/2 - qh/2
        
        QuestManager.window.x = qx
        QuestManager.window.y = qy
        
        -- Backdrop (Dim)
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", 0, 0, constants.V_WIDTH, constants.V_HEIGHT)
        
        -- Window Body
        love.graphics.setColor(0.05, 0.05, 0.08, 0.95)
        love.graphics.rectangle("fill", qx, qy, qw, qh, 10)
        love.graphics.setColor(1, 1, 1, 0.3)
        love.graphics.rectangle("line", qx, qy, qw, qh, 10)
        
        local q = QuestManager.list[QuestManager.currentIndex]
        
        if not q then
            -- All Quests Done
            love.graphics.setFont(game.fontUI)
            love.graphics.setColor(0.5, 1.0, 0.5)
            love.graphics.printf("ALL QUESTS COMPLETED!", qx, qy + 100, qw, "center")
        else
            -- Title
            love.graphics.setFont(game.fontBtn)
            love.graphics.setColor(1, 0.8, 0.2)
            love.graphics.printf(q.name, qx, qy + 20, qw, "center")
            
            -- Desc
            love.graphics.setFont(game.fontUI)
            love.graphics.setColor(0.9, 0.9, 0.9)
            love.graphics.printf(q.desc, qx, qy + 70, qw, "center")
            
            -- Progress Slider
            local cur = QuestManager.getProgress(q, game)
            local max = q.target
            local pct = math.min(cur / max, 1.0)
            
            local sw = 300
            local sh = 20
            local sx = qx + (qw - sw)/2
            local sy = qy + 120
            
            -- Bar BG
            love.graphics.setColor(0.2, 0.2, 0.2)
            love.graphics.rectangle("fill", sx, sy, sw, sh, 5)
            
            -- Fill
            love.graphics.setColor(0.2, 0.8, 0.2)
            love.graphics.rectangle("fill", sx, sy, sw * pct, sh, 5)
            
            -- Text
            love.graphics.setColor(1, 1, 1)
            love.graphics.setFont(game.fontSmall)
            local progTxt = math.floor(cur) .. " / " .. max
            love.graphics.printf(progTxt, sx, sy + 2, sw, "center")
            
            -- CLAIM Button
            if QuestManager.completed then
                local btnW, btnH = 140, 40
                local btnX = qx + qw/2 - btnW/2
                local btnY = qy + 180
                
                love.graphics.setColor(0.2, 0.8, 0.2)
                love.graphics.rectangle("fill", btnX, btnY, btnW, btnH, 5)
                
                love.graphics.setColor(0, 0, 0)
                love.graphics.setFont(game.fontUI)
                love.graphics.printf("CLAIM " .. q.reward, btnX, btnY + 8, btnW, "center")
                
                QuestManager.claimBtn = {x=btnX, y=btnY, w=btnW, h=btnH}
            else
                love.graphics.setColor(0.5, 0.5, 0.5)
                love.graphics.printf("Reward: " .. q.reward .. " Tokens", qx, qy + 190, qw, "center")
                QuestManager.claimBtn = nil
            end
        end
    end
end

function QuestManager.handleClick(x, y, game)
    -- Check Icon Click
    -- Need to map click coords to UI coords if needed, but here we assume raw or virtual match.
    -- Main.lua passes virtual coords usually?
    -- No, main.lua mousepressed passes screen coords usually, need to convert to virtual.
    -- Assuming x,y passed here are Virtual coords (game.inputs).
    
    local bx, by = QuestManager.btn.x, QuestManager.btn.y
    local dist = math.sqrt((x - (bx + 25))^2 + (y - (by + 25))^2)
    
    if dist < 30 then
        QuestManager.isOpen = not QuestManager.isOpen
        return true
    end
    
    if QuestManager.isOpen then
        -- Check Claim Button
        if QuestManager.completed and QuestManager.claimBtn then
            local b = QuestManager.claimBtn
            if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                QuestManager.claimReward(game)
                return true
            end
        end
        
        -- Close if clicked outside window
        -- Actually, maybe keep open? Or close? User didn't specify. Standard behavior: close on X or outside.
        -- Let's just consume click if inside window
        local w = QuestManager.window
        if x >= w.x and x <= w.x + w.w and y >= w.y and y <= w.y + w.h then
            return true -- Consume click
        else
            QuestManager.isOpen = false -- Close
            return true
        end
    end
    
    return false
end

function QuestManager.claimReward(game)
    local q = QuestManager.list[QuestManager.currentIndex]
    if q then
        game.gold = game.gold + q.reward
        -- Spawn FX
        game.spawnPopup("+" .. q.reward, QuestManager.claimBtn.x + 70, QuestManager.claimBtn.y, {1, 0.8, 0}, true, 0)
    end
    
    QuestManager.currentIndex = QuestManager.currentIndex + 1
    QuestManager.completed = false
    QuestManager.hasRolledSeven = false -- Reset transient
    -- Check if next quest is auto-complete? (e.g. wealth)
end

return QuestManager
