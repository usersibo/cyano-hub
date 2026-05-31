--[[
  Loader — одна строка в executor.

  Репозиторий: https://github.com/usersibo/cyano-hub
]]

local BASE = "https://raw.githubusercontent.com/usersibo/cyano-hub/refs/heads/main/"

local function loadUrl(path)
    local url = BASE .. path
    local ok, src = pcall(function()
        return game:HttpGet(url)
    end)
    if not ok or not src or src == "" then
        error("[Cyanogen Loader] Failed to fetch: " .. url)
    end
    local fn, err = loadstring(src, path)
    if not fn then
        error("[Cyanogen Loader] Compile error in " .. path .. ": " .. tostring(err))
    end
    return fn()
end

loadUrl("Cyanogen.lua")
task.wait(0.3)
loadUrl("LaserPlus.lua")

print("[Cyanogen Loader] Cyanogen + LaserPlus loaded from cyano-hub")
