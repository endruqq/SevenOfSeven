local constants = require("constants")
local colors = constants.colors
local utils = require("utils")
local UpgradeNode = require("src.nodes.UpgradeNode")

local Shop = {
    tabs = {
        {id="upgrades", name="UPGRADES", iconPath="assets/IconsShop/nodeicon.png"}, -- Reuse icon or placeholder
        {id="modules", name="ROULETTES", iconPath="assets/IconsShop/rollicon.png"}
    },
    activeTab = 1,
    hoverTab = nil,
    hoverItem = nil,
    hoverToggle = false,
    itemStates = {}, -- Stores hover progress for items
    
    -- Design Config
    widthRatio = 0.0, 
    targetWidth = 360, -- Reduced width (10% less than 400)
    open = false,
    
    -- Scroll State
    scrollY = 0,
    maxScroll = 0
}

-- Module Definitions (Sold in Tab 2)
local modules = {
    buy_clock = {id="buy_clock", name="Clock Roulette", price=50, icon="clock", desc="Standard Clock"},
    buy_plinko = {id="buy_plinko", name="Plinko Board", price=500, icon="plinko", desc="High Stakes Board (5x Rewards)"},
    buy_gate_and = {id="buy_gate_and", name="AND Gate", price=20, icon="gate", desc="Outputs signal if both inputs are active", gateType="AND"},
    buy_gate_or = {id="buy_gate_or", name="OR Gate", price=20, icon="gate", desc="Outputs signal if any input is active", gateType="OR"},
    buy_gate_not = {id="buy_gate_not", name="NOT Gate", price=20, icon="gate", desc="Inverts signal", gateType="NOT"},
    buy_gate_delay = {id="buy_gate_delay", name="DELAY Gate", price=30, icon="gate", desc="Delays signal by 1 turn", gateType="DELAY"}
}

local function getModulePrice(game, id)
    local m = modules[id]
    if not m then return 0 end

    local count = 0
    if id == "buy_clock" then
        count = #game.clockWheels
        return math.floor(m.price * math.pow(1.5, count))
    elseif id == "buy_plinko" then
        count = #game.plinkoBoards
        return math.floor(m.price * math.pow(2.0, count))
    elseif string.find(id, "buy_gate") then
        -- Count Logic Gates
        for _, mod in ipairs(game.modules) do
            if mod.type == "logic_gate" and mod.gateType == m.gateType then
                count = count + 1
            end
        end
        return math.floor(m.price * math.pow(1.2, count))
    end
    return m.price
end

local function buyItem(game, id)
    -- 1. Try Buying Modules (Tab 2)
    local module = modules[id] -- Direct match
    
    if module then
        local cost = getModulePrice(game, id)

        if game.gold >= cost then
            local pType = "clock"
            if module.id == "buy_plinko" then pType = "plinko"
            elseif string.find(module.id, "buy_gate") then pType = "logic_gate" end

            game.placementMode = {
                active = true,
                type = pType,
                gateType = module.gateType,
                cost = cost,
                name = module.name,
                item = module
            }
            game.buildMode = true
            game.shop.open = false
            return true
        end
        return false
    end
    
    -- 2. Try Buying Upgrades (Tab 1)
    if game.upgrades and game.upgrades[id] then
        local u = game.upgrades[id]
        
        -- One-time purchase check
        if u.id == "autoSpin" and u.level >= 1 then
             return false 
        end
        
        -- Calculate Cost
        local cost = math.floor(u.baseCost * math.pow(u.costMult, u.level))
        
        if game.gold >= cost then
            game.gold = game.gold - cost
            u.level = u.level + 1
            
            -- Trigger Recalc
            if game.recalcStats then game.recalcStats() end
            
            -- Feedback (Sound/Popup)
            if spawnPopup then spawnPopup("Upgraded!", constants.V_WIDTH - 300, 100, colors.highlight, true, 0) end
            return true
        end
    end
    
    return false
end

function Shop.update(dt, game)
    local s = game.shop
    if not s then return end
    
    -- Check Scroll Init
    if not s.scrollY then s.scrollY = 0 end
    if not s.maxScroll then s.maxScroll = 0 end
    s.targetWidth = Shop.targetWidth -- Enforce updated width
    if not s.widthRatio then s.widthRatio = 0.0 end -- Safety init for animation
    
    -- Sidebar Animation
    local target = s.open and 1.0 or 0.0
    s.widthRatio = utils.lerp(s.widthRatio, target, 10 * dt)
    
    -- Scroll Clamping (Elastic return or Hard clamp?) -> Hard clamp for now
    if s.scrollY < 0 then s.scrollY = utils.lerp(s.scrollY, 0, 15*dt) end
    if s.scrollY > s.maxScroll then s.scrollY = utils.lerp(s.scrollY, s.maxScroll, 15*dt) end
    
    -- Hover Item Animation Logic
    if not s.itemStates then s.itemStates = {} end 
    -- Modules
    for _, val in pairs(modules) do
        if not s.itemStates[val.id] then s.itemStates[val.id] = 0 end
    end
    -- Upgrades
    if game.upgrades then
        for _, val in pairs(game.upgrades) do
            if not s.itemStates[val.id] then s.itemStates[val.id] = 0 end
        end
    end
    
    local w, h = constants.V_WIDTH, constants.V_HEIGHT
    local currentW = s.targetWidth * s.widthRatio
    local panelX = w - currentW
    local mx, my = love.mouse.getPosition()
    
    Shop.hoverTab = nil
    Shop.hoverToggle = false
    Shop.hoverItem = nil
    
    -- 1. TOGGLE BUTTON (Center Right or Attached to Panel Left)
    -- HIDE when open (User request: "nie powinno byc szczalki chowajacej as it covers tabs")
    local togW, togH = 30, 80
    local togX = panelX - togW
    local togY = h/2 - togH/2
    local showToggle = not s.open
    
    if showToggle and mx >= togX and mx <= togX + togW and my >= togY and my <= togY + togH then
        Shop.hoverToggle = true
    end
    
    -- 2. TABS (Top of Panel)
    if s.open or s.widthRatio > 0.1 then
        local tabW = 80 -- Fixed Width
        local tabH = 40 -- Fixed Height
        local gap = 10 
        local startTabY = 60 - tabH - 5 -- panelY - tabH - 5
        
        for i, tName in ipairs(Shop.tabs) do
            local tX = panelX + (i-1)*(tabW + gap)
            local tY = startTabY
            
            if mx >= tX and mx <= tX + tabW and my >= tY and my <= tY + tabH then
                Shop.hoverTab = i
            end
        end
    end
    
    -- 3. ITEMS (Within Panel)
    if s.widthRatio > 0.8 then
         local margin = 20
         local gridY = 20 -- Reduced from 40
         local colCount = 1 -- Single Column
         
         -- Interactive area is clipped by sidebar rect
         -- Only hover if mouse inside panel
         if mx > panelX then
             local list = {}
             local isUpgradeTab = (Shop.activeTab == 1)
             
             if isUpgradeTab then
                 if game.upgrades then
                     -- Add in specific order
                      local function add(key) 
                         if game.upgrades[key] then 
                             table.insert(list, game.upgrades[key]) 
                         else
                             print("MISSING UPGRADE KEY: " .. key)
                         end
                      end
                     add("speed")
                     add("luck")
                     add("multi")
                     add("auxSpeed")

                     -- Hotfix: Inject Energy if missing (from old save)
                     if not game.upgrades["energy"] then
                         game.upgrades["energy"] = {id="energy", name="Power Supply", level=0, baseCost=20, costMult=1.4, desc="Increases Max Energy (+10)"}
                     end
                     add("energy")
                     
                     -- Hotfix: Inject AutoSpin if missing (from old save)
                     if not game.upgrades["autoSpin"] then
                         game.upgrades["autoSpin"] = {id="autoSpin", name="Hand of a Gambler", level=0, baseCost=100, costMult=2.5, desc="Auto-Spin Main Roulette"}
                     end
                     add("autoSpin")
                 end
             elseif Shop.activeTab == 2 then
                 table.insert(list, modules.buy_clock)
                 table.insert(list, modules.buy_plinko)
                 table.insert(list, modules.buy_gate_and)
                 table.insert(list, modules.buy_gate_or)
                 table.insert(list, modules.buy_gate_not)
                 table.insert(list, modules.buy_gate_delay)
             end
             
             local panelKw = s.targetWidth - margin*2
             local itemW = panelKw
             local itemH = 90
             if isUpgradeTab then itemH = 75 end
             local gap = 15
             
             local panelY = 60 -- Must match draw logic
             local panelH = h - 120 -- Top + Bottom Gap
             
             -- Recalculate maxScroll
             local totalH = #list * (itemH + gap) + gridY + 50 
             s.maxScroll = math.max(0, totalH - panelH)
             
             for i, item in ipairs(list) do
                 local row = i-1
                 local ix = panelX + margin
                 local iy = panelY + gridY + row * (itemH + gap) - s.scrollY
                 
                 -- Check if visible on screen
                 if iy + itemH > panelY and iy < panelY + panelH then
                     if mx >= ix and mx <= ix+itemW and my >= iy and my <= iy+itemH then
                         Shop.hoverItem = item.id
                     end
                 end
             end
         end
    end
    
    -- Update Animations
    -- Modules
    for _, val in pairs(modules) do 
         local displayId = val.id
         local target = (Shop.hoverItem == displayId) and 1.0 or 0.0
         s.itemStates[displayId] = utils.lerp(s.itemStates[displayId], target, 15 * dt)
    end
    -- Upgrades
    if game.upgrades then
        for _, val in pairs(game.upgrades) do
             local displayId = val.id
             local target = (Shop.hoverItem == displayId) and 1.0 or 0.0
             s.itemStates[displayId] = utils.lerp(s.itemStates[displayId], target, 15 * dt)
        end
    end
end

function Shop.wheelmoved(x, y)
    -- Negative y = Scroll Down (increase offset)
    -- Positive y = Scroll Up (decrease offset)
    local s = game.shop
    if not s or not s.open then return end
    
    local scrollSpeed = 40
    s.scrollY = s.scrollY - y * scrollSpeed
    
    -- Clamp immediate (optional, update handles smoothing)
    if s.scrollY < 0 then s.scrollY = 0 end
    if s.scrollY > s.maxScroll then s.scrollY = s.maxScroll end
end

function Shop.draw(game)
    local s = game.shop
    if not s then return end
    
    local w, h = constants.V_WIDTH, constants.V_HEIGHT
    local currentW = s.targetWidth * s.widthRatio
    local panelX = w - currentW
    
    -- 2. PANEL BODY
    local topGap = 60
    local bottomGap = 60
    local panelY = topGap
    local panelH = h - (topGap + bottomGap)
    
    if currentW > 1 then
        love.graphics.setColor(0.1, 0.1, 0.12, 0.95)
        -- Cutout Panel (Sharp Corners)
        love.graphics.rectangle("fill", panelX, panelY, currentW, panelH)
        
        -- Tech Pattern (Clipped to Panel)
        love.graphics.setScissor(panelX, panelY, currentW, panelH)
        love.graphics.setColor(1, 1, 1, 0.05)
        local dotSpacing = 30
        local rows = math.ceil(panelH / dotSpacing) + 1
        local cols = math.ceil(currentW / dotSpacing) + 1
        
        for dy = 0, rows do 
            for dx = 0, cols do
                local px = panelX + dx * dotSpacing
                local py = panelY + dy * dotSpacing
                if (dx + dy) % 4 == 0 then love.graphics.circle("fill", px, py, 3)
                else love.graphics.circle("fill", px, py, 1.5) end
            end
        end
        love.graphics.setScissor()
        
        -- Full Dashed Border
        love.graphics.setColor(1, 1, 1, 0.15) 
        utils.drawDashedRectangle(panelX, panelY, currentW, panelH, 15, 10)
    end
    
    -- 1. TABS (Top of Panel)
    if s.widthRatio > 0.1 then
        local tabW = 80 -- Fixed Width
        local tabH = 40 -- Fixed Height (Smaller)
        local gap = 10 
        local startTabY = panelY - tabH - 5
        
        for i, tName in ipairs(Shop.tabs) do
            local isActive = (i == Shop.activeTab)
            local isHover = (i == Shop.hoverTab)
            
            -- Static Positioning (Left Aligned)
            local tX = panelX + (i-1)*(tabW + gap)
            local tY = startTabY
            
            local alpha = 0.9
            if isActive then love.graphics.setColor(0.3, 0.3, 0.35, alpha)
            elseif isHover then love.graphics.setColor(0.25, 0.25, 0.3, alpha)
            else love.graphics.setColor(0.15, 0.15, 0.2, alpha) end
            
            -- Tab Shape (Rounded Top)
            love.graphics.rectangle("fill", tX, tY, tabW, tabH, 8, 8) 
            
            -- Tab Border
            love.graphics.setColor(1, 1, 1, 0.15)
            utils.drawDashedRectangle(tX, tY, tabW, tabH, 8, 4)
            
            -- Icon Drawing
            love.graphics.setColor(1, 1, 1)
            
            -- Lazy Load Icons
            if not tName.img and tName.iconPath then
                local status, img = pcall(love.graphics.newImage, tName.iconPath)
                if status then 
                    tName.img = img 
                    img:setFilter("linear", "linear", 16)
                end
            end
            
            if tName.img then
                local iconSz = 30 -- Smaller for Top Tabs
                local sx = iconSz / tName.img:getWidth()
                local sy = iconSz / tName.img:getHeight()
                local cx = tX + tabW/2
                local cy = tY + tabH/2
                love.graphics.draw(tName.img, cx, cy, 0, sx, sy, tName.img:getWidth()/2, tName.img:getHeight()/2)
            else
                love.graphics.setColor(1, 1, 1)
                love.graphics.setFont(fontUI)
                love.graphics.printf(tName.name or "TAB", tX, tY + 15, tabW, "center")
            end
        end
    end

    -- 3. TOGGLE ARROW (Draw only if !open)
    local togW, togH = 30, 80
    local togX = panelX - togW
    local togY = h/2 - togH/2
    
    if not s.open then
        -- Rectangular Toggle with Arrow
        love.graphics.setColor(Shop.hoverToggle and {0.3, 0.3, 0.35} or {0.2, 0.2, 0.25})
        love.graphics.rectangle("fill", togX, togY, togW, togH)
        
        love.graphics.setColor(1, 1, 1, 0.15)
        utils.drawDashedRectangle(togX, togY, togW, togH, 8, 4)
        
        -- Arrow
        love.graphics.setColor(1, 1, 1)
        love.graphics.setLineWidth(3)
        local cx, cy = togX + togW/2, togY + togH/2
        local sz = 6
        -- Only Draw "<" since we only show when closed
        love.graphics.line(cx + sz, cy - sz, cx - sz, cy, cx + sz, cy + sz)
    end

    -- 4. ITEMS (Clipped)
    if s.widthRatio > 0.8 then
         local margin = 20
         local gridY = 20
         
         -- Clip to Cutout Panel area
         love.graphics.setScissor(panelX, panelY, currentW, panelH)
         
         local list = {}
         local isUpgradeTab = (Shop.activeTab == 1)
         
         if isUpgradeTab then 
             -- UPGRADES (Order: Speed, Luck, Multi, AuxSpeed)
             if game.upgrades then
                 -- Helper to get specific upgrade
                 local function add(key) 
                    if game.upgrades[key] then table.insert(list, game.upgrades[key]) end 
                 end
                 add("speed")
                 add("luck")
                 add("multi")
                 add("auxSpeed")
                 
                 -- Hotfix: Inject Energy if missing (from old save)
                 if not game.upgrades["energy"] then
                     game.upgrades["energy"] = {id="energy", name="Power Supply", level=0, baseCost=20, costMult=1.4, desc="Increases Max Energy (+10)"}
                 end
                 add("energy")

                 -- Hotfix: Inject AutoSpin if missing
                 if not game.upgrades["autoSpin"] then
                     game.upgrades["autoSpin"] = {id="autoSpin", name="Hand of a Gambler", level=0, baseCost=100, costMult=2.5, desc="Auto-Spin Main Roulette"}
                 end
                 add("autoSpin")
             end
         elseif Shop.activeTab == 2 then 
             -- MODULES (Use Correct Keys!)
             table.insert(list, modules.buy_clock)
             table.insert(list, modules.buy_plinko)
             table.insert(list, modules.buy_gate_and)
             table.insert(list, modules.buy_gate_or)
             table.insert(list, modules.buy_gate_not)
             table.insert(list, modules.buy_gate_delay)
         end
         
         local panelKw = s.targetWidth - margin*2
         local itemW = panelKw
         local itemH = 90 -- Default height (smaller)
         if isUpgradeTab then itemH = 75 end -- Compact upgrades

         
         local gap = 15
         
         -- Recalculate maxScroll
         local totalH = #list * (itemH + gap) + gridY + 50 
         s.maxScroll = math.max(0, totalH - panelH) -- Adjust scroll limit to panel height
         
         for i, item in ipairs(list) do
             local row = i-1
             local ix = panelX + margin
             -- ADJUST Y by panelY (Start inside the cutout)
             local iy = panelY + gridY + row * (itemH + gap) - (s.scrollY or 0)
             
             -- Only draw if visible (Check vs Panel Y bounds)
             if iy + itemH > panelY and iy < panelY + panelH then
                 -- DATA SETUP
                 local u = item -- Alias
                 local price, level, desc, valStr = 0, 0, "", ""
                 
                 if isUpgradeTab then
                     price = math.floor(u.baseCost * math.pow(u.costMult, u.level))
                     level = u.level
                     desc = u.name
                     -- Show Value Change? e.g. "1.0x -> 1.05x"
                     -- Simplify: Just "Lvl X" and Description
                 else
                     price = getModulePrice(game, item.id)
                     desc = item.name
                 end
                 
                 local isMaxed = (u.id == "autoSpin" and u.level >= 1)
                 
                 local canBuy = (game.gold >= price) and not isMaxed
                 local isPressed = (Shop.pressedItem == item.id)
                 local pressOffset = isPressed and 3 or 0
                 
                 -- DRAW ITEM
                 if isUpgradeTab then
                     -- NEW LAYOUT: [Price Button (Left)] [Info Panel (Right)]
                     local priceW = 110
                     local infoW = itemW - priceW - 10
                     local btnH = itemH
                     local infoH = itemH
                     
                     -- 1. PRICE BUTTON (Left)
                     local btnX = ix
                     local btnY = iy + pressOffset
                     
                     -- #9340E6 = {0.58, 0.25, 0.9}
                     local btnColor = canBuy and {0.58, 0.25, 0.9} or {0.3, 0.3, 0.35} 
                     local btnShadow = canBuy and {0.4, 0.15, 0.7} or {0.15, 0.15, 0.2}
                     
                     -- Override if Maxed
                     if isMaxed then
                         btnColor = {0.4, 0.3, 0.2} -- Dark Bronze/Gold
                         btnShadow = {0.2, 0.15, 0.1}
                     end
                     
                     -- Shadow
                     love.graphics.setColor(btnShadow)
                     love.graphics.rectangle("fill", btnX, btnY + 6, priceW, btnH, 10)
                     -- Body
                     love.graphics.setColor(btnColor)
                     love.graphics.rectangle("fill", btnX, btnY, priceW, btnH, 10)
                     
                     -- Price Content
                     if isMaxed then 
                         love.graphics.setColor(1, 0.9, 0.5) 
                         love.graphics.setFont(fontUI)
                         love.graphics.printf("OWNED", btnX, btnY + btnH/2 - 10, priceW, "center")
                     else
                         love.graphics.setColor(canBuy and {1, 1, 1} or {0.7, 0.7, 0.7})
                         local iconSz = 24
                         if game.imgToken then
                             love.graphics.draw(game.imgToken, btnX + priceW/2 - iconSz/2, btnY + 20, 0, iconSz/game.imgToken:getWidth(), iconSz/game.imgToken:getHeight())
                         else
                             love.graphics.circle("fill", btnX + priceW/2, btnY + 32, 10)
                         end
                         
                         love.graphics.setFont(fontUI)
                         love.graphics.printf(utils.formatNumber(price), btnX, btnY + 50, priceW, "center")
                     end
                     
                     -- 2. INFO PANEL (Right)
                     local infoX = ix + priceW + 10
                     local infoY = iy -- No press offset for info? Or sync it? Sync looks better
                     infoY = infoY + pressOffset
                     
                     -- Background
                     love.graphics.setColor(0.15, 0.15, 0.18)
                     love.graphics.rectangle("fill", infoX, infoY, infoW, infoH, 10)
                     
                     -- Highlight if hovered
                     local hoverP = s.itemStates[u.id] or 0
                     if hoverP > 0.01 and canBuy then
                         love.graphics.setColor(1, 1, 1, 0.05 * hoverP)
                         love.graphics.rectangle("fill", infoX, infoY, infoW, infoH, 10)
                         love.graphics.rectangle("fill", btnX, btnY, priceW, btnH, 10)
                     end
                     
                     -- Info Text
                     love.graphics.setColor(1, 1, 1)
                     love.graphics.setFont(fontUI)
                     love.graphics.print(u.name, infoX + 15, infoY + 15)
                     
                     -- Level Badge (Top Right)
                     love.graphics.setColor(1, 1, 1, 0.5)
                     love.graphics.printf("Lvl " .. u.level, infoX, infoY + 15, infoW - 15, "right")
                     
                     -- VALUE PREVIEW (Bottom)
                     love.graphics.setFont(fontSmall or fontUI)
                     local valStr = ""
                     
                     -- Calculate Values
                     local cur, nextVal
                     
                     if u.id == "speed" then
                         cur = string.format("%.2fx", math.pow(1.05, u.level))
                         nextVal = string.format("%.2fx", math.pow(1.05, u.level + 1))
                     elseif u.id == "luck" then
                         cur = (1 + u.level) .. "%" -- Base 1%? actually level 1 = ? LuckyLevel
                         nextVal = (1 + u.level + 1) .. "%"
                     elseif u.id == "multi" then
                         cur = string.format("+%.2fx", u.level * 0.25)
                         nextVal = string.format("+%.2fx", (u.level + 1) * 0.25)
                     elseif u.id == "auxSpeed" then
                         cur = string.format("%.2fx", math.pow(1.05, u.level))
                         nextVal = string.format("%.2fx", math.pow(1.05, u.level + 1))
                     elseif u.id == "energy" then
                         cur = tostring(10 + (u.level * 10))
                         nextVal = tostring(10 + ((u.level + 1) * 10))
                     elseif u.id == "autoSpin" then
                         cur = (u.level > 0) and "Active" or "Inactive"
                         nextVal = "Active"
                     end
                     
                     local txtY = infoY + 50
                     -- Current (Gray)
                     love.graphics.setColor(0.7, 0.7, 0.8)
                     love.graphics.print(cur, infoX + 15, txtY)
                     
                     -- Arrow
                     local w1 = (fontSmall or fontUI):getWidth(cur)
                     love.graphics.setColor(1, 1, 1, 0.5)
                     love.graphics.print("->", infoX + 15 + w1 + 10, txtY)
                     
                     -- Next
                     local w2 = (fontSmall or fontUI):getWidth("->")
                     love.graphics.setColor(0.58, 0.25, 0.9) -- Purple for Next value too
                     love.graphics.print(nextVal, infoX + 15 + w1 + 10 + w2 + 10, txtY)
                     
                 else
                     -- MODULES (Legacy Layout)
                     -- #9340E6 = {0.58, 0.25, 0.9}
                     local mainColor = canBuy and {0.58, 0.25, 0.9} or {0.2, 0.2, 0.25} 
                     local shadowColor = canBuy and {0.4, 0.15, 0.7} or {0.1, 0.1, 0.12}
                     
                     -- Shadow
                     love.graphics.setColor(shadowColor)
                     love.graphics.polygon("fill", utils.getOctagonVertices(ix + itemW/2, iy + itemH/2 + 6, itemW, itemH, 10))
                     
                     -- Body
                     local bodyY = iy + pressOffset
                     love.graphics.setColor(mainColor)
                     local bodyVerts = utils.getOctagonVertices(ix + itemW/2, bodyY + itemH/2, itemW, itemH, 10)
                     love.graphics.polygon("fill", bodyVerts)
                     
                     -- Hover Overlay
                     local hoverP = s.itemStates[item.id] or 0
                     if hoverP > 0.01 and canBuy then
                         love.graphics.setColor(1, 1, 1, 0.1 * hoverP)
                         love.graphics.polygon("fill", bodyVerts)
                     end
                     
                     local contentY = bodyY
                      -- Icon
                     love.graphics.setColor(1, 1, 1)
                     local iconY = contentY + 15
                     if item.icon == "clock" then
                         love.graphics.circle("line", ix + 30, iconY + 20, 15)
                     elseif item.icon == "plinko" then
                          love.graphics.rectangle("line", ix + 15, iconY + 5, 30, 30)
                     elseif item.icon == "gate" then
                          love.graphics.polygon("line", ix+20, iconY+5, ix+40, iconY+20, ix+20, iconY+35)
                     end
                     
                     love.graphics.setFont(fontUI)
                     love.graphics.print(item.name, ix + 60, iconY + 10)
                     
                     -- Price
                     love.graphics.setColor(canBuy and colors.ui_gold or {0.6, 0.6, 0.6})
                     if game.imgToken then
                          love.graphics.draw(game.imgToken, ix + 60, iconY + 40, 0, 15/game.imgToken:getWidth(), 15/game.imgToken:getHeight())
                     else
                          love.graphics.circle("fill", ix + 67, iconY + 47, 6)
                     end
                     love.graphics.print(utils.formatNumber(item.price), ix + 80, iconY + 40)
                 end
             end
         end
         
         love.graphics.setScissor()
    end
end

function Shop.mousepressed(x, y, button, game)
    local s = game.shop
    if not s then return false end
    
    -- 1. Check Toggle
    if Shop.hoverToggle and not s.open then
        s.open = true
        return true
    end
    
    -- 2. Check Tabs
    if Shop.hoverTab then
        Shop.activeTab = Shop.hoverTab
        s.open = true 
        return true
    end
    
    -- 3. Check Items (Start Press)
    if s.open and s.widthRatio > 0.8 then
        if Shop.hoverItem then
            Shop.pressedItem = Shop.hoverItem -- Track pressed item ID
            return true -- Consume click
        end
        
        -- Click outside/inside logic
        local currentW = s.targetWidth * s.widthRatio
        local panelX = constants.V_WIDTH - currentW
        if x > panelX then return true end
        
        if x < panelX and not Shop.hoverTab and not Shop.hoverToggle then
             s.open = false
             return true
        end
    end
    
    return false
end

function Shop.mousereleased(x, y, button, game)
    if Shop.pressedItem then
        -- Check if still hovering the SAME item
        if Shop.hoverItem == Shop.pressedItem then
             buyItem(game, Shop.pressedItem)
        end
        Shop.pressedItem = nil
        return true
    end
    return false
end

return Shop
