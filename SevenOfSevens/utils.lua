-- utils.lua
-- Helper Functions

local M = {}

function M.easeOutCubic(t) 
    return 1 - math.pow(1 - t, 3) 
end

function M.lerp(a, b, t) 
    return a + (b - a) * t 
end

function M.getOctagonVertices(cx, cy, w, h, chamfer)
    local w2, h2 = w/2, h/2
    return {
        cx - w2 + chamfer, cy - h2,
        cx + w2 - chamfer, cy - h2,
        cx + w2, cy - h2 + chamfer,
        cx + w2, cy + h2 - chamfer,
        cx + w2 - chamfer, cy + h2,
        cx - w2 + chamfer, cy + h2,
        cx - w2, cy + h2 - chamfer,
        cx - w2, cy - h2 + chamfer
    }
end

function M.drawDashedLine(x1, y1, x2, y2, dashLen, gapLen)
    love.graphics.setLineWidth(2)
    love.graphics.setLineStyle("rough") 
    local dx, dy = x2-x1, y2-y1
    local dist = math.sqrt(dx*dx + dy*dy)
    local angle = math.atan2(dy, dx)
    local cursor = 0
    while cursor < dist do
        local len = math.min(dashLen, dist - cursor)
        local sx = x1 + math.cos(angle) * cursor
        local sy = y1 + math.sin(angle) * cursor
        local ex = sx + math.cos(angle) * len
        local ey = sy + math.sin(angle) * len
        love.graphics.line(sx, sy, ex, ey)
        cursor = cursor + dashLen + gapLen
    end
    love.graphics.setLineStyle("smooth")
end

function M.drawChevronPath(x1, y1, x2, y2, color)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx*dx + dy*dy)
    
    if dist < 20 then return end
    
    local angle = math.atan2(dy, dx)
    local spacing = 35 
    local count = math.floor(dist / spacing)
    
    -- Use passed color or default gray
    if color then
        love.graphics.setColor(color[1], color[2], color[3], color[4] or 0.8)
    else
        love.graphics.setColor(0.6, 0.6, 0.6, 0.4) 
    end
    love.graphics.setLineWidth(4) 
    love.graphics.setLineJoin("miter") 
    
    -- Draw chevrons along the line
    local startOffset = spacing -- Start chevrons after one spacing from origin
    for i = 0, count - 1 do
        local progress = startOffset + i * spacing
        if progress > dist then break end
        -- Center X,Y of the chevron on the line
        local cx = x1 + math.cos(angle) * progress
        local cy = y1 + math.sin(angle) * progress
        
        -- Chevron size parameters
        local wingspan = 12 -- How wide sideways
        local length = 10 -- How long backwards
        
        -- Rotate points manually
        -- Tip at (cx, cy)
        -- Left Wing: (-length, -wingspan) rotated + (cx, cy)
        -- Right Wing: (-length, +wingspan) rotated + (cx, cy)
        
        local cosA = math.cos(angle)
        local sinA = math.sin(angle)
        
        -- Left point relative to tip
        local lx_local = -length
        local ly_local = -wingspan
        local lx = (lx_local * cosA - ly_local * sinA) + cx
        local ly = (lx_local * sinA + ly_local * cosA) + cy
        
        -- Right point relative to tip
        local rx_local = -length
        local ry_local = wingspan
        local rx = (rx_local * cosA - ry_local * sinA) + cx
        local ry = (rx_local * sinA + ry_local * cosA) + cy
        
        -- Draw V shape
        love.graphics.line(lx, ly, cx, cy, rx, ry)
    end
end

function M.intersectSegmentCircle(x1, y1, x2, y2, cx, cy, r)
    -- Check if either endpoint is inside the circle
    local d1 = math.sqrt((x1 - cx)^2 + (y1 - cy)^2)
    local d2 = math.sqrt((x2 - cx)^2 + (y2 - cy)^2)
    if d1 < r or d2 < r then
        return true -- One endpoint is inside
    end
    
    local dx = x2 - x1
    local dy = y2 - y1
    local fx = x1 - cx
    local fy = y1 - cy
    
    local a = dx*dx + dy*dy
    if a < 0.001 then return false end -- Zero-length segment
    
    local b = 2*(fx*dx + fy*dy)
    local c = (fx*fx + fy*fy) - r*r
    
    local discriminant = b*b - 4*a*c
    if discriminant < 0 then return false end
    
    local t1 = (-b - math.sqrt(discriminant)) / (2*a)
    local t2 = (-b + math.sqrt(discriminant)) / (2*a)
    
    -- Check if intersection is within the segment (t between 0 and 1)
    if (t1 >= 0 and t1 <= 1) or (t2 >= 0 and t2 <= 1) then
        return true
    end
    
    -- Also check if the segment passes completely through (both t values are on same side but straddle the segment)
    if t1 < 0 and t2 > 1 then
        return true
    end
    
    return false
end



function M.drawFluidLine(x1, y1, x2, y2, color, startNormal, endNormal)
    if not color then color = {1, 0, 0, 1} end
    love.graphics.setColor(color)
    love.graphics.setLineWidth(3)
    
    -- Calculate Control Points based on Normals (or default to horizontal if nil)
    local dist = math.sqrt((x2-x1)^2 + (y2-y1)^2)
    local cDist = math.min(dist * 0.5, 150) -- Cap control point distance
    
    local cp1x, cp1y = x1, y1
    local cp2x, cp2y = x2, y2
    
    -- Heuristic Normals if not provided
    if not startNormal then
        cp1x = x1 + (x2 > x1 and cDist or -cDist) -- Horizontal
    else
        cp1x = x1 + startNormal.x * cDist
        cp1y = y1 + startNormal.y * cDist
    end
    
    if not endNormal then
        cp2x = x2 + (x1 > x2 and cDist or -cDist) -- Horizontal towards start
    else
        cp2x = x2 + endNormal.x * cDist
        cp2y = y2 + endNormal.y * cDist
    end

    local curve = love.math.newBezierCurve(x1, y1, cp1x, cp1y, cp2x, cp2y, x2, y2)
    love.graphics.line(curve:render())
    
    -- Pulse Effect
    local time = love.timer.getTime()
    local t = (time * 1.5) % 1.0
    local px, py = curve:evaluate(t)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.circle("fill", px, py, 4)
end

function M.drawFluidDashedLine(x1, y1, x2, y2, color, startNormal, endNormal, dashLen, gapLen)
    if not color then color = {0.5, 0.5, 0.5, 1} end
    love.graphics.setColor(color)
    love.graphics.setLineWidth(3)
    
    local prevStyle = love.graphics.getLineStyle()
    love.graphics.setLineStyle("rough")
    
    local dist = math.sqrt((x2-x1)^2 + (y2-y1)^2)
    local cDist = math.min(dist * 0.5, 150)
    
    local cp1x, cp1y, cp2x, cp2y
    if not startNormal then
        cp1x = x1 + (x2 > x1 and cDist or -cDist)
        cp1y = y1
    else
        cp1x = x1 + startNormal.x * cDist
        cp1y = y1 + startNormal.y * cDist
    end
    
    if not endNormal then
        cp2x = x2 + (x1 > x2 and cDist or -cDist)
        cp2y = y2
    else
        cp2x = x2 + endNormal.x * cDist
        cp2y = y2 + endNormal.y * cDist
    end
    
    local curve = love.math.newBezierCurve(x1, y1, cp1x, cp1y, cp2x, cp2y, x2, y2)
    -- Robust Dashing Algorithm using evaluate
    -- Estimate length to determine step
    -- Note: curve:render() gives polyline, but evaluate gives point at t.
    -- Approximate length by sampling 10 points
    local estLen = 0
    local lx, ly = curve:evaluate(0)
    for i=1,10 do
        local tx, ty = curve:evaluate(i/10)
        estLen = estLen + math.sqrt((tx-lx)^2 + (ty-ly)^2)
        lx, ly = tx, ty
    end
    
    if estLen == 0 then return end
    
    local dash = dashLen or 15
    local gap = gapLen or 10
    local cycle = dash + gap
    
    -- Step size for iteration (pixels)
    local stepPx = 2 -- 2 pixel resolution
    local stepT = stepPx / estLen
    
    local cursor = 0
    local drawing = true
    
    local px, py = curve:evaluate(0)
    
    -- Iterate t from 0 to 1
    local t = 0
    while t < 1 do
        t = t + stepT
        if t > 1 then t = 1 end
        
        local nx, ny = curve:evaluate(t)
        local segLen = math.sqrt((nx-px)^2 + (ny-py)^2)
        
        -- Draw if in drawing phase
        if drawing then
             love.graphics.line(px, py, nx, ny)
        end
        
        cursor = cursor + segLen
        
        if drawing and cursor >= dash then
             cursor = 0
             drawing = false
        elseif not drawing and cursor >= gap then
             cursor = 0
             drawing = true
        end
        
        px, py = nx, ny
    end
    
    love.graphics.setLineStyle(prevStyle)
end

function M.drawDashedRectangle(x, y, w, h, dash, gap)
    M.drawDashedLine(x, y, x+w, y, dash, gap)
    M.drawDashedLine(x+w, y, x+w, y+h, dash, gap)
    M.drawDashedLine(x+w, y+h, x, y+h, dash, gap)
    M.drawDashedLine(x, y+h, x, y, dash, gap)
end

function M.printBold(text, x, y, c)
    local ox, oy = 1, 0
    love.graphics.print(text, x + ox, y + oy)
    love.graphics.print(text, x, y)
end

function M.drawOutletShape(x, y, angle, size, colorOverride)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(angle)
    
    local w = (size or 40) * 1.0 -- Length (Back to normal/standard)
    local h = (size or 40) * 0.8 -- Thickness (Wider/Fatter as requested)
    local r = h/2
    
    -- Design:
    -- Flat Back at x = -w/2
    -- Rounded Front at x = w/2 (semicircle)
    -- But image shows a "Capsule cut in half" or standard capsule?
    -- "Flat part behind (longer), Front is other side".
    -- Let's make a D shape.
    -- Rectangle from -w/2 to 0. Semicircle at 0.
    
    local bodyColor = {0.2, 0.2, 0.2} -- Dark Grey
    local rimColor = {0.6, 0.6, 0.6} -- Lighter Grey
    local accentColor = colorOverride or {0.9, 0.2, 0.2} -- Red
    
    -- 1. Base (Back Plane)
    -- Rect part
    -- x: -w/2 to 0. y: -h/2 to h/2.
    local rw = w * 0.6
    local rx = -w/2
    
    -- Draw Body
    -- Composite Shape: Rectangle + Circle at end?
    -- Let's draw a full capsule but clip the back?
    -- Or just Rect + Arc.
    
    -- Grey Body
    love.graphics.setColor(bodyColor)
    love.graphics.rectangle("fill", rx, -h/2, rw, h)
    love.graphics.arc("fill", rx + rw, 0, h/2, -math.pi/2, math.pi/2)
    
    -- Rim/Highlight (The "Shell")
    love.graphics.setLineWidth(2)
    love.graphics.setColor(rimColor)
    -- Outline
    local points = {
        rx, -h/2, -- Top Back
        rx + rw, -h/2, -- Top Front
        -- Arc... handled by arc line?
    }
    love.graphics.line(rx, -h/2, rx + rw, -h/2) -- Top
    love.graphics.line(rx, h/2, rx + rw, h/2)   -- Bottom
    love.graphics.line(rx, -h/2, rx, h/2)       -- Back Vertical
    love.graphics.arc("line", "open", rx + rw, 0, h/2, -math.pi/2, math.pi/2)
    
    -- Accent (Red strip or center)
    -- Small strip near the flat back
    love.graphics.setColor(accentColor)
    love.graphics.rectangle("fill", rx + 2, -h/2 + 2, 4, h - 4)
    
    love.graphics.pop()
end


function M.formatNumber(n)
    if n < 1000 then
        return tostring(math.floor(n))
    elseif n < 1000000 then
        return string.format("%.1fk", n/1000):gsub("%.0k", "k")
    else
        return string.format("%.1fm", n/1000000):gsub("%.0m", "m")
    end
end

return M
