local SignalSystem = {}
local utils = require("utils")

-- State
SignalSystem.signals = {} -- List of active signals
SignalSystem.turnState = {
    activatedModules = {},
    active = false
}

-- Config
local SIGNAL_SPEED = 600 -- Pixels per second

function SignalSystem.init(game)
    SignalSystem.game = game
    SignalSystem.signals = {}
    SignalSystem.turnState = { activatedModules = {}, active = false }
end

function SignalSystem.startTurn()
    SignalSystem.turnState.active = true
    SignalSystem.turnState.activatedModules = {}
end

function SignalSystem.endTurn()
    SignalSystem.turnState.active = false
    SignalSystem.turnState.activatedModules = {}
    SignalSystem.signals = {}
end

-- Broadcast a signal from a source module
-- payload: data to pass (e.g. the number rolled)
-- Broadcast a signal from a source module
-- payload: data to pass (e.g. the number rolled)
function SignalSystem.broadcast(source, payload)
    if not SignalSystem.game then return end
    
    -- Auto-start turn if not active (Ensures state is fresh)
    if not SignalSystem.turnState.active then
        SignalSystem.startTurn()
    end
    
    local game = SignalSystem.game
    
    -- Mark source as activated to prevent immediate back-flow if relevant
    -- (Though usually we check activation before acting, not broadcasting)
    if source.id then
        SignalSystem.turnState.activatedModules[source.id] = true
    end
    
    -- Find all outgoing connections from this source
    -- We need to check connectionData of OTHER modules that point to US?
    -- OR check our own outputs?
    -- Existing Logic: Target stores connection info.
    -- So we must scan all modules to see if they are connected to 'source'.
    
    -- Check Clock Wheels
    if game.clockWheels then
        for _, cw in ipairs(game.clockWheels) do
            local wireList = cw.connections or (cw.connectionData and {cw.connectionData}) or {}
            
            for _, data in ipairs(wireList) do
                local connected = false
                
                if data.srcType == "main" and (source.type == "main" or source == game.mainRoulette) then
                    connected = true
                elseif data.srcType == "plinko" and source == data.clockSource then -- Strict Instance Match
                    connected = true
                elseif data.srcType == "clock" and (source == data.clockSource or (source.id and data.clockSource and source.id == data.clockSource.id)) then -- Clock to Clock (Generic)
                    connected = true
                end
                
                if connected then
                    SignalSystem.spawnSignal(source, cw, data.srcIndex, data.tgtIndex, payload)
                end
            end
        end
    end
    
    -- Check Plinko (Input)
    -- Plinko connects TO things (Output). Does it have INPUT?
    -- Yes, Main -> Plinko via "plinko" outlet type? 
    -- Currently Plinko doesn't store "input connection". 
    -- The wire is defined by the TARGET.
    -- Does Main connect to Plinko?
    -- Plinko is usually a target?
    -- Wait, currently wiring is defined on the TARGET.
    -- If Plinko is a target, it should have `connectionData`.
    -- Check Plinko (Input)
    -- Plinko connects TO things (Output). Does it have INPUT?
    -- Yes, Main -> Plinko via "plinko" outlet type? 
    -- Currently Plinko doesn't store "input connection". 
    -- The wire is defined by the TARGET.
    -- If Plinko is a target, it should have `connectionData`.
    -- Check Plinko Boards (Input target)
    if game.plinkoBoards then
        for _, p in ipairs(game.plinkoBoards) do
            local wireList = p.connections or (p.connectionData and {p.connectionData}) or {}
            
            for _, data in ipairs(wireList) do
                local connected = false
                
                if data.srcType == "main" and source.label == "MAIN ROULETTE" then
                    connected = true
                elseif data.srcType == "clock" and source == data.clockSource then -- Connected to a Clock
                    connected = true
                elseif data.srcType == "plinko" and source == data.clockSource then -- Connected to another Plinko
                    connected = true
                end
                
                if connected then
                     SignalSystem.spawnSignal(source, p, data.srcIndex, data.tgtIndex, payload)
                end
            end
        end
    end
end

function SignalSystem.getOutputInfo(mod, index)
    local x, y = mod.x, mod.y
    local nx, ny = 1, 0
    
    if mod.label == "MAIN ROULETTE" or (mod.type == "main") then
        local offset = 140
        if index == 1 then x=mod.x-offset; y=mod.y; nx=-1; ny=0 -- Left
        elseif index == 2 then x=mod.x+offset; y=mod.y; nx=1; ny=0 -- Right
        elseif index == 3 then x=mod.x; y=mod.y+200; nx=0; ny=1 end -- Bottom (Approx)
    elseif mod.id and string.find(mod.id, "clock") or mod.type == "clock" then
        local r = 140
        if index == 1 then x=mod.x+r; y=mod.y; nx=1; ny=0 -- Right
        elseif index == 2 then x=mod.x; y=mod.y+r; nx=0; ny=1 -- Bottom
        elseif index == 3 then x=mod.x-r; y=mod.y; nx=-1; ny=0 -- Left
        elseif index == 4 then x=mod.x; y=mod.y-r; nx=0; ny=-1 end -- Top
    elseif mod.type == "plinko" or (mod.id and string.find(mod.id, "plinko")) then
        if index == 1 then x=mod.x-mod.w/2-20; y=mod.y+mod.h/2; nx=-1; ny=0 -- Left
        elseif index == 2 then x=mod.x+mod.w/2+20; y=mod.y+mod.h/2; nx=1; ny=0 -- Right
        elseif index == 3 then x=mod.x; y=mod.y+mod.h+20; nx=0; ny=1 end -- Bottom
    end
    return x, y, {x=nx, y=ny}
end

function SignalSystem.getInputInfo(mod, index)
    -- Inputs are usually Sockets defined in 'sockets' table
    if mod.sockets and mod.sockets[index] then
        local s = mod.sockets[index]
        return mod.x + s.x, mod.y + s.y, s.normal
    elseif CheckArray(mod.sockets, index) then -- Check assuming index is numeric
        local s = mod.sockets[index]
        return mod.x + s.x, mod.y + s.y, s.normal
    end
    return mod.x, mod.y, {x=0, y=-1}
end
function CheckArray(arr, ind) return arr and arr[ind] end

function SignalSystem.spawnSignal(source, target, srcIndex, tgtIndex, payload)
    local x1, y1, norm1 = SignalSystem.getOutputInfo(source, srcIndex)
    local x2, y2, norm2 = SignalSystem.getInputInfo(target, tgtIndex)
    
    local sig = {
        source = source,
        target = target,
        payload = payload,
        t = 0,
        duration = 0,
        curve = nil
    }
    
    -- Calculate Bezier
    local dist = math.sqrt((x2-x1)^2 + (y2-y1)^2)
    local cDist = math.min(dist * 0.5, 150)
    
    local cp1x = x1 + norm1.x * cDist
    local cp1y = y1 + norm1.y * cDist
    local cp2x = x2 + norm2.x * cDist
    local cp2y = y2 + norm2.y * cDist
    
    sig.curve = love.math.newBezierCurve(x1, y1, cp1x, cp1y, cp2x, cp2y, x2, y2)
    
    sig.duration = dist / SIGNAL_SPEED
    if sig.duration < 0.4 then sig.duration = 0.4 end -- Min duration
    
    table.insert(SignalSystem.signals, sig)
end

function SignalSystem.update(dt)
    for i = #SignalSystem.signals, 1, -1 do
        local sig = SignalSystem.signals[i]
        sig.t = sig.t + (dt / sig.duration)
        
        if sig.t >= 1 then
            SignalSystem.resolve(sig)
            table.remove(SignalSystem.signals, i)
        end
    end
end

function SignalSystem.resolve(sig)
    local target = sig.target
    if target.onSignal then
        target:onSignal(sig.payload, sig.source)
    end
    
    if SignalSystem.game and SignalSystem.game.particles then
        -- Spawn hit particles
    end
end

function SignalSystem.draw()
    -- User requested to disable flying pulse.
    -- Wires themselves will light up red in main.lua instead.
end

function SignalSystem.isWireActive(source, target)
    for _, sig in ipairs(SignalSystem.signals) do
        -- Check strict object equality
        if sig.source == source and sig.target == target then
            return true
        end
    end
    return false
end

return SignalSystem
