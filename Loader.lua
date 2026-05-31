--[[
  Loader — одна строка в executor вместо двух файлов.

  Репозиторий: https://github.com/usersibo/cyanogen
  Важно: имена файлов на GitHub с БОЛЬШОЙ буквы — Cyanogen.lua, LaserPlus.lua
]]

local BASE = "https://raw.githubusercontent.com/usersibo/cyanogen/main/"

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

print("[Cyanogen Loader] Cyanogen + LaserPlus loaded from GitHub")
