-- src/Particles.lua
local constants = require("constants")
local utils = require("utils")

local M = {}

local V_WIDTH = constants.V_WIDTH
local V_HEIGHT = constants.V_HEIGHT
local colors = constants.colors
local lerp = utils.lerp
local easeOutCubic = utils.easeOutCubic
local getOctagonVertices = utils.getOctagonVertices

function M.spawnFlyingTokens(game, fromX, fromY, count)
    for i = 1, count do
        local p = {
            type = "flying_token",
            x = fromX,
            y = fromY,
            targetX = 200, -- Opposite Side (Left)
            targetY = 50,
            progress = 0,
            speed = 0.5 + math.random() * 0.5, 
            rot = math.random() * math.pi * 2,
            rotSpeed = (math.random() - 0.5) * 10,
            size = 30 + math.random() * 20, -- Visual size
            curve = (math.random() - 0.5) * 400, -- Big Arc
            delay = math.random() * 0.5 -- Staggered start
        }
        table.insert(game.particles, p)
    end
end

function M.spawnButtonShockwave(game, b)
    local p = {
        type = "btn_shockwave",
        x = b.x, y = b.y, w = b.w, h = b.h,
        cx = b.x + b.w/2, cy = b.y + b.h/2,
        life = 0, maxLife = 0.6, scale = 1.0, maxScale = 1.8, color = colors.ui_gold
    }
    table.insert(game.particles, p)
end

function M.spawnFrameShockwave(game, x, y, w, h)
    -- ... (Keep existing)
    local p = {
        type = "frame_shockwave",
        x = x, y = y, w = w, h = h,
        cx = x + w/2, cy = y + h/2,
        life = 0, maxLife = 0.5, scale = 1.0, maxScale = 1.4, color = colors.highlight
    }
    table.insert(game.particles, p)
end

function M.spawnFallingSeven(game)
    -- ... (Keep existing if needed, or remove)
    local p = {
        type = "falling_seven",
        x = math.random(0, V_WIDTH),
        y = -50,
        speed = 100 + math.random() * 200,
        size = 20 + math.random() * 40,
        alpha = 0.1 + math.random() * 0.2, 
        rot = math.random() * math.pi * 2,
        rotSpeed = (math.random() - 0.5) * 2
    }
    table.insert(game.particles, p)
end

function M.updateParticles(dt, game)
    for i = #game.particles, 1, -1 do
        local p = game.particles[i]
        
        if p.delay and p.delay > 0 then
            p.delay = p.delay - dt
        elseif p.type == "btn_shockwave" or p.type == "frame_shockwave" then
            p.life = p.life + dt
            if p.life >= p.maxLife then table.remove(game.particles, i) end
        elseif p.type == "falling_seven" then
            p.y = p.y + p.speed * dt
            p.rot = p.rot + p.rotSpeed * dt
            if p.y > V_HEIGHT + 50 then table.remove(game.particles, i) end
        elseif p.type == "flying_token" then
            p.progress = p.progress + dt * p.speed
            p.rot = p.rot + p.rotSpeed * dt
            
            if p.progress >= 1 then
                table.remove(game.particles, i)
            else
                local t = p.progress
                -- Cubic Bezier or Quadratic? Quadratic for arc.
                local mt = 1-t
                
                -- Dynamic Start Pos (if needed, but static is fine for now)
                local startX, startY = p.x, p.y
                
                -- Control Point
                local cx = (startX + p.targetX)/2 + p.curve
                local cy = (startY + p.targetY)/2 - 200 -- High Arc
                
                -- Quadratic Bezier
                p.drawX = mt*mt*startX + 2*mt*t*cx + t*t*p.targetX
                p.drawY = mt*mt*startY + 2*mt*t*cy + t*t*p.targetY
                
                -- Scale effect (Pop in, shrink out)
                if t < 0.2 then p.scale = t * 5
                elseif t > 0.8 then p.scale = (1-t) * 5
                else p.scale = 1.0 end
            end
        else
            -- Legacy or fallback
            table.remove(game.particles, i)
        end
    end
end

function M.drawWorldParticles(game)
    for _, p in ipairs(game.particles) do
        if p.delay and p.delay > 0 then
             -- Wait
        elseif p.type == "btn_shockwave" then
             local t = p.life / p.maxLife
             local alpha = 1 - t
             local scale = lerp(p.scale, p.maxScale, easeOutCubic(t))
             local w2 = (p.w/2) * scale
             local h2 = (p.h/2) * scale
             local chamfer = 15 * scale
             local verts = getOctagonVertices(p.cx, p.cy, w2*2, h2*2, chamfer)
             love.graphics.setLineWidth(5 * (1-t))
             love.graphics.setColor(0.6, 0.6, 0.65, alpha) 
             love.graphics.polygon("line", verts)
        elseif p.type == "frame_shockwave" then
            local lifePct = p.life / p.maxLife
            local alpha = 1.0 - lifePct
            local scale = lerp(p.scale, p.maxScale, easeOutCubic(lifePct))
            love.graphics.setColor(p.color[1], p.color[2], p.color[3], alpha)
            love.graphics.setLineWidth(5 * (1-lifePct)) 
            local currentW = p.w * scale
            local currentH = p.h * scale
            local verts = getOctagonVertices(p.cx, p.cy, currentW, currentH, 15 * scale)
            love.graphics.polygon("line", verts)
        elseif p.type == "falling_seven" then
             love.graphics.setColor(1, 1, 1, p.alpha)
             love.graphics.print("7", p.x, p.y, p.rot, 2, 2)
        end
    end
end

function M.drawScreenParticles(game)
    for _, p in ipairs(game.particles) do
        if p.delay and p.delay > 0 then
             -- Wait
        elseif p.type == "flying_token" and p.drawX then
            love.graphics.setColor(1, 1, 1)
            -- Draw Token
            if game.imgToken then
                local img = game.imgToken
                local scale = (p.size / img:getWidth()) * (p.scale or 1)
                love.graphics.draw(img, p.drawX, p.drawY, p.rot, scale, scale, img:getWidth()/2, img:getHeight()/2)
            else
                love.graphics.circle("fill", p.drawX, p.drawY, p.size/2)
            end
        end
    end
end

return M
