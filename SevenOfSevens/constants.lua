-- constants.lua
-- Global Constants

local M = {}

M.V_WIDTH = 1280
M.V_HEIGHT = 720

M.colors = {
    bg = {0.05, 0.05, 0.07},      -- Deep Dark
    text = {0.90, 0.90, 0.95},    -- Crisp White
    highlight = {0.9, 0.25, 0.25},  -- Unified Red (Matches ROLL button)
    wheel_bg = {0.1, 0.1, 0.12},  -- Dark Grey
    ui_gold = {1.0, 0.85, 0.1},   -- Neon Gold
    ui_gold_dark = {0.85, 0.60, 0.05}, -- Darker Amber Gold
    btn_normal = {0.12, 0.12, 0.16},
    btn_hover = {0.20, 0.20, 0.28},
    btn_active = {0.30, 0.30, 0.40},
    btn_text = {1, 1, 1},
    frame_base = {0.2, 0.25, 0.35}, -- Neon-ish Blue Grey
    overlay = {0, 0, 0, 0.7} -- Pause Overlay
}

return M
