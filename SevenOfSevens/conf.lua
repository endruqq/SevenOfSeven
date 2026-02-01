function love.conf(t)
    t.window.title = "SevenOfSevens"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.msaa = 8 -- Smooth edges (Anti-Aliasing)
    t.version = "11.5" -- Targeting modern Love2D
    t.console = true -- Enable console window for debug output (Windows)
end
