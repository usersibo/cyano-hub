--[[
  Loader — грузит один файл Cyanogen.lua
  https://github.com/usersibo/cyano-hub
]]

local URL = "https://raw.githubusercontent.com/usersibo/cyano-hub/refs/heads/main/Cyanogen.lua"

local ok, src = pcall(function()
    return game:HttpGet(URL)
end)
if not ok or not src or src == "" then
    error("[Loader] Не скачался Cyanogen.lua: " .. tostring(URL))
end

local fn, err = loadstring(src, "Cyanogen.lua")
if not fn then
    error("[Loader] Ошибка компиляции: " .. tostring(err))
end

fn()
