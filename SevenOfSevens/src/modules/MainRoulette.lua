-- src/modules/MainRoulette.lua
local Module = require("src.Module")
local Wheel = require("src.Wheel")
local constants = require("constants")
local utils = require("utils")

local MainRoulette = {}
setmetatable(MainRoulette, {__index = Module})
MainRoulette.__index = MainRoulette

local colors = constants.colors
local printBold = utils.printBold

function MainRoulette.new(x, y)
    local w, h = 300, 500 -- Size of the module hull
    local self = Module.new(x, y, w, h)
    setmetatable(self, MainRoulette)
    
    self.label = "MAIN ROULETTE"
    self.wheel = Wheel.new()
    self.btnRoll = { y = 180, w = 200, h = 60, text = "ROLL" }
    
    -- Sockets REMOVED (Shop Upgrade System)
    
    return self
end

function MainRoulette:getSocketAt(wx, wy)
    -- No physical sockets for nodes anymore
    return nil
end

-- ... update ...
function MainRoulette:update(dt, game, checkWinCallback)
    self.wheel:update(dt, game, checkWinCallback)
end

function MainRoulette:draw(game)
    local cx, cy = self.x, self.y
    
    -- Draw Wheel (Pass absolute world coords)
    self.wheel:draw(game, cx, cy) -- Wheel centered (Original Position)
end




return MainRoulette
