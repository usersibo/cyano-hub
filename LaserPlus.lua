--[[
  LaserPlus.lua — отдельный модуль лазера (Cyanogen.lua НЕ трогать)

  Как грузить:
    1) Сначала Cyanogen.lua (ESP, movement и т.д.)
    2) Потом этот файл

  В Cyanogen ОБЯЗАТЕЛЬНО выключи: Triggerbot (Z) и Silent Aim (V),
  иначе два лазера будут драться за LaserStart/Update/Stop.

  Что делает:
    • Умный Auto LaserStop (нет цели, перегрев, grace 0.15s, античит-стоп)
    • Silent aim + server cone clamp (голова HL ≤80° к цели — как в LaserManager)
    • Зеркало серверного raycast — стреляет только если сервер бы попал
    • «Wall try» — без клиентского LOS (через стены НЕ пробьёт: сервер сам raycast'ит)
    • Подгонка камеры к цели (лучше проходит проверку Head.LookVector)
]]

local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Modules.Config)
local Network = require(RS.Modules.Network)
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local lplr = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function loadLuxtLib()
    local paths = { "cyanogen.lua", "agent-tools/ec3c690f-3afa-4a65-994e-7320742f43a4.txt" }
    if readfile and isfile then
        for _, p in ipairs(paths) do
            if isfile(p) then
                return loadstring(readfile(p), p)()
            end
        end
    end
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/usersibo/cyanogen/refs/heads/main/cyanogen.lua"))()
end

local Luxt = loadLuxtLib().CreateWindow("Laser Plus", 82720440678616)
local tab = Luxt:Tab("Laser", 82720440678616)

-- ========== CONFIG (из Modules.Config) ==========
local LASER_MAX_RANGE = Config.LaserMaxRange or 500
local LASER_MAX_ANGLE = Config.LaserMaxAimAngle or 80
local LASER_COS_ANGLE = math.cos(math.rad(LASER_MAX_ANGLE))
local LASER_TICK = Config.LaserServerTickRate or 0.05
local LASER_FOCUS_TIME = Config.LaserFocusTime or 0.08
local LASER_GRACE = Config.LaserTargetGracePeriod or 0.15
local LASER_MAX_HEAT = Config.LaserMaxHeat or 100
local TEMPV_MAX_HEAT = Config.TempVLaserMaxHeat or 80
local TEMPV_RANGE = Config.TempVLaserRange or 200

-- ========== STATE ==========
local masterEnabled = true
local triggerbotEnabled = false
local silentAimEnabled = true
local serverConeFix = true
local serverRaycastOnly = true
local wallTryMode = false
local alignCameraToTarget = true
local autoStopEnabled = true
local preOverheatStop = true
local preOverheatPercent = 88

local silentFov = 280
local aimPart = "Head"
local cameraAlignStrength = 0.12

local tbLasering = false
local lastNetTick = 0
local laserLockTarget = nil
local laserLockUntil = 0
local lastValidHitAt = 0
local lastHadTargetAt = 0
local laserStartAt = 0

-- ========== HELPERS ==========
local function isStormfront()
    return lplr:GetAttribute("Role") == Config.Role_Stormfront
end

local function isTempVLaser()
    return lplr:GetAttribute("TempVPower") == "LaserEyes"
end

local function canLaserNow()
    local role = lplr:GetAttribute("Role") or ""
    return role == Config.Role_Homelander or role == Config.Role_Stormfront or isTempVLaser()
end

local function getMaxHeat()
    if isTempVLaser() then return TEMPV_MAX_HEAT end
    return LASER_MAX_HEAT
end

local function getMaxRange()
    if isStormfront() then return LASER_MAX_RANGE end
    if isTempVLaser() then return TEMPV_RANGE end
    return LASER_MAX_RANGE
end

local function isPlayerAlive(player)
    local char = player and player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function getCharHead()
    local char = lplr.Character
    return char and char:FindFirstChild("Head")
end

local function getAimPart(player, partName)
    local char = player and player.Character
    if not char then return nil end
    return char:FindFirstChild(partName or aimPart)
        or char:FindFirstChild("Head")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("HumanoidRootPart")
end

local function getRaycastFilter(extra)
    local list = {}
    local char = lplr.Character
    if char then table.insert(list, char) end
    if extra then table.insert(list, extra) end
    return list
end

local function clientHasLOS(targetPart)
    if wallTryMode then return true end
    if not targetPart or not targetPart.Parent then return false end
    local head = getCharHead()
    if not head then return false end
    local origin = head.Position
    local dir = targetPart.Position - origin
    if dir.Magnitude < 0.05 then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = getRaycastFilter(targetPart.Parent)
    local hit = workspace:Raycast(origin, dir, params)
    if not hit then return true end
    local model = hit.Instance:FindFirstAncestorOfClass("Model")
    return model == targetPart.Parent
end

local function getScreenFovDist(worldPos)
    local sp, onScreen = camera:WorldToViewportPoint(worldPos)
    if not onScreen or sp.Z <= 0 then return nil, false end
    local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    return (Vector2.new(sp.X, sp.Y) - center).Magnitude, true
end

-- Как LaserManager на сервере: clamp направления к конусу головы
local function clampDirToServerCone(head, worldDir)
    local look = head.CFrame.LookVector
    local dot = look:Dot(worldDir)
    if dot >= LASER_COS_ANGLE then
        return worldDir
    end
    local perp = worldDir - look * dot
    if perp.Magnitude < 0.001 then
        perp = head.CFrame.RightVector
    else
        perp = perp.Unit
    end
    return (look * LASER_COS_ANGLE + perp * math.sin(math.rad(LASER_MAX_ANGLE))).Unit
end

local function clampAimToServerCone(head, desiredWorldPos)
    local offset = desiredWorldPos - head.Position
    if offset.Magnitude < 0.1 then
        return desiredWorldPos
    end
    local dir = offset.Unit
    if not serverConeFix or isStormfront() then
        return desiredWorldPos
    end
    local clamped = clampDirToServerCone(head, dir)
    local dist = math.min(offset.Magnitude, getMaxRange())
    return head.Position + clamped * dist
end

-- Зеркало серверного raycast (только Character shooter в фильтре)
local function serverMirrorHitsPlayer(aimPos)
    local head = getCharHead()
    local char = lplr.Character
    if not head or not char then return false, nil end

    local offset = aimPos - head.Position
    if offset.Magnitude < 0.1 then return false, nil end

    local dir = offset.Unit
    if isStormfront() then
        -- SF: сервер не режет по Head.LookVector так же жёстко
    elseif head.CFrame.LookVector:Dot(dir) < LASER_COS_ANGLE then
        return false, nil
    end

    local mag = offset.Magnitude
    if mag > getMaxRange() * 1.2 then
        return false, nil
    end

    local params = RaycastParams.new()
    params.FilterDescendantsInstances = { char }
    params.FilterType = Enum.RaycastFilterType.Exclude
    local hit = workspace:Raycast(head.Position, dir * math.min(mag + 5, getMaxRange()), params)
    if not hit or not hit.Instance then return false, nil end

    local model = hit.Instance:FindFirstAncestorOfClass("Model")
    if not model then return false, nil end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false, nil end
    if model == char then return false, nil end

    local plr = Players:GetPlayerFromCharacter(model)
    return true, plr
end

local function getBestTarget()
    if laserLockTarget and tick() < laserLockUntil then
        local part = getAimPart(laserLockTarget, "Head")
        if part and isPlayerAlive(laserLockTarget) and clientHasLOS(part) then
            return laserLockTarget, part
        end
        laserLockTarget = nil
    end

    local bestPlayer, bestPart, bestScore = nil, nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lplr and isPlayerAlive(p) then
            local part = getAimPart(p, "Head")
            if part then
                local fovDist, onScreen = getScreenFovDist(part.Position)
                if onScreen and fovDist and fovDist <= silentFov and clientHasLOS(part) then
                    if fovDist < bestScore then
                        bestScore = fovDist
                        bestPlayer = p
                        bestPart = part
                    end
                end
            end
        end
    end

    if bestPlayer then
        laserLockTarget = bestPlayer
        laserLockUntil = tick() + 0.3
    end
    return bestPlayer, bestPart
end

local function getCrosshairTarget()
    local unitRay = camera:ScreenPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    local params = RaycastParams.new()
    local char = lplr.Character
    if char then
        params.FilterDescendantsInstances = { char }
        params.FilterType = Enum.RaycastFilterType.Exclude
    end
    local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * getMaxRange(), params)
    if result and result.Instance then
        local model = result.Instance:FindFirstAncestorOfClass("Model")
        if model then
            local p = Players:GetPlayerFromCharacter(model)
            if p and p ~= lplr and isPlayerAlive(p) then
                local part = getAimPart(p, aimPart)
                if part and clientHasLOS(part) then
                    return p, part.Position
                end
            end
        end
    end
    return nil, nil
end

local function hideVanillaLasers()
    pcall(function()
        local LM = require(RS.Modules.LaserManager)
        if LM.HideLasers then
            LM:HideLasers(lplr)
        end
    end)
end

local function stopLaser(reason)
    if not tbLasering then return end
    tbLasering = false
    laserLockTarget = nil
    Network:FireServer("LaserStop")
    if isStormfront() then
        Network:FireServer("StormElecStop")
    end
    hideVanillaLasers()
end

local function shouldForceStop(targetPlayer, aimPos)
    if not autoStopEnabled then return false end

    if not canLaserNow() then return true, "no power" end
    if lplr:GetAttribute("IsSuperVision") then return true, "super vision" end
    if lplr:GetAttribute("LaserOverheated") then return true, "overheated" end

    local hum = lplr.Character and lplr.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return true, "dead" end

    if preOverheatStop then
        local heat = lplr:GetAttribute("LaserHeat") or 0
        if heat >= getMaxHeat() * (preOverheatPercent / 100) then
            return true, "heat"
        end
    end

    if not targetPlayer or not aimPos then
        if tbLasering and tick() - lastHadTargetAt > LASER_GRACE then
            return true, "no target"
        end
        return false
    end

    if not isPlayerAlive(targetPlayer) then
        return true, "target dead"
    end

    if serverRaycastOnly then
        local hit, hitPlr = serverMirrorHitsPlayer(aimPos)
        if hit and (not hitPlr or hitPlr == targetPlayer) then
            lastValidHitAt = tick()
        elseif tbLasering and tick() - lastValidHitAt > LASER_GRACE then
            return true, "server ray miss"
        end
    else
        lastValidHitAt = tick()
    end

    if tbLasering and lplr:GetAttribute("IsLasering") ~= true then
        if tick() - laserStartAt > 0.25 then
            return true, "desync"
        end
    end

    return false
end

local function alignCamera(part)
    if not alignCameraToTarget or not part then return end
    camera.CFrame = camera.CFrame:Lerp(
        CFrame.new(camera.CFrame.Position, part.Position),
        cameraAlignStrength
    )
end

local function resolveAimPos(targetPlayer, part)
    local head = getCharHead()
    if not head or not part then return nil end
    return clampAimToServerCone(head, part.Position)
end

local function runLaser()
    if not masterEnabled or not triggerbotEnabled then
        stopLaser()
        return
    end

    if not canLaserNow() then
        stopLaser()
        return
    end

    local targetPlayer, part
    if silentAimEnabled then
        targetPlayer, part = getBestTarget()
    else
        local pos
        targetPlayer, pos = getCrosshairTarget()
        if targetPlayer then
            part = getAimPart(targetPlayer, aimPart)
        end
    end

    local aimPos = part and resolveAimPos(targetPlayer, part) or nil

    local forceStop, _reason = shouldForceStop(targetPlayer, aimPos)
    if forceStop then
        stopLaser()
        return
    end

    if not targetPlayer or not aimPos then
        if tbLasering then
            stopLaser()
        end
        return
    end

    lastHadTargetAt = tick()
    alignCamera(part)

    local now = tick()
    if now - lastNetTick < LASER_TICK then return end
    lastNetTick = now

    if not tbLasering then
        tbLasering = true
        lastValidHitAt = now
        laserStartAt = now
        Network:FireServer("LaserStart")
        if isStormfront() then
            Network:FireServer("StormElecStart")
        end
    end

    Network:FireServer("LaserUpdate", aimPos)
end

-- ========== GUI ==========
local coreSec = tab:Section("Core")
coreSec:Toggle("Enabled", function(on) masterEnabled = on; if not on then stopLaser() end end)
coreSec:ToggleKeyBind("Triggerbot", Enum.KeyCode.Z, function(on)
    triggerbotEnabled = on
    if not on then stopLaser() end
end)

local aimSec = tab:Section("Aim")
aimSec:ToggleKeyBind("Silent Aim", Enum.KeyCode.V, function(on) silentAimEnabled = on end)
aimSec:Slider("Silent FOV", 80, 500, function(v) silentFov = v end)
aimSec:DropDown("Aim Part", {"Head", "Torso", "HumanoidRootPart"}, function(v) aimPart = v end)

local srvSec = tab:Section("Server sync")
srvSec:Toggle("Server cone fix (HL)", function(on) serverConeFix = on end)
srvSec:Toggle("Server raycast check", function(on) serverRaycastOnly = on end)
srvSec:Toggle("Wall try (no client LOS)", function(on) wallTryMode = on end)
srvSec:Toggle("Align camera to target", function(on) alignCameraToTarget = on end)
srvSec:Slider("Camera align %", 1, 40, function(v) cameraAlignStrength = v / 100 end)

local stopSec = tab:Section("Auto LaserStop")
stopSec:Toggle("Smart auto stop", function(on) autoStopEnabled = on end)
stopSec:Toggle("Stop before overheat", function(on) preOverheatStop = on end)
stopSec:Slider("Heat stop %", 50, 99, function(v) preOverheatPercent = v end)

tab:Section("Info"):Credit("Выключи Z/V в Cyanogen.lua")
tab:Section("Info"):Credit("Wallbang = сервер всё равно raycast")

Luxt:SetTheme("Grey")

RunService.RenderStepped:Connect(runLaser)

lplr.CharacterAdded:Connect(function()
    tbLasering = false
    laserLockTarget = nil
    lastValidHitAt = 0
    lastHadTargetAt = 0
    laserStartAt = 0
end)

_G.LaserPlus = {
    stop = stopLaser,
    enabled = function() return masterEnabled and triggerbotEnabled end,
}

print("[LaserPlus] Loaded — disable Triggerbot/Silent in Cyanogen")
