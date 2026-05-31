local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Modules.Config)
local Network = require(RS.Modules.Network)
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local lplr = Players.LocalPlayer
local camera = workspace.CurrentCamera
-- ========== БЛОКИРОВКА КИКА (ВСЕГДА) ==========
local kickHook
kickHook = hookmetamethod(game, "__namecall", function(self, ...)
    if getnamecallmethod() == "Kick" then return end
    return kickHook(self, ...)
end)

-- ========== ЗАГРУЗКА GUI ==========
local function loadLuxtLib()
    local paths = {
        "cyanogen.lua",
        "agent-tools/ec3c690f-3afa-4a65-994e-7320742f43a4.txt",
    }
    if readfile and isfile then
        for _, p in ipairs(paths) do
            if isfile(p) then
                return loadstring(readfile(p), p)()
            end
        end
    end
    local urls = {
        "https://raw.githubusercontent.com/usersibo/cyano-hub/refs/heads/main/cyanogen.lua",
        "https://raw.githubusercontent.com/usersibo/cyanogen/refs/heads/main/cyanogen.lua",
    }
    for _, url in ipairs(urls) do
        local ok, lib = pcall(function()
            return loadstring(game:HttpGet(url))()
        end)
        if ok and lib then return lib end
    end
    error("[Cyanogen] GUI lib not found")
end

local Luxtl = loadLuxtLib()
local Luxt = Luxtl.CreateWindow("Cyanogen v1.0", 130428526050758)

task.wait(0.5)
local playerGui = lplr:WaitForChild("PlayerGui")
for _, gui in ipairs(playerGui:GetChildren()) do
    if gui.Name:lower():find("cyanogen") then
        local icon = gui:FindFirstChild("Icon", true) or gui:FindFirstChild("Avatar", true) or gui:FindFirstChild("Image", true)
        if not icon then
            for _, v in ipairs(gui:GetDescendants()) do
                if v:IsA("ImageLabel") and v.Size.X.Offset < 60 then
                    icon = v
                    break
                end
            end
        end
        if icon and icon:IsA("ImageLabel") then
            icon.Image = Players:GetUserThumbnailAsync(lplr.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
        end
    end
end

-- ========== ТАБЫ ==========
local visualsTab = Luxt:Tab("Visuals", 93915156103067)
local movementTab = Luxt:Tab("Movement", 128706247346129)
local combatTab = Luxt:Tab("Combat", 82720440678616)
local utilityTab = Luxt:Tab("Utility", 72070638458255)
local creditsTab = Luxt:Tab("Credits", 71870986260398)

-- ========== STATE ==========
local espEnabled = false
local labelEnabled = false
local teamEspEnabled = false
local homelanderEspEnabled = false
local chamsEnabled = false
local noclip = false
local bhopEnabled = false
local infiniteJumpEnabled = false
local noJumpCooldownEnabled = false
local localFlightEnabled = false
local autoSprintEnabled = false
local flightSpeed = 50
local customSpeed = 22
local justJumped = false
local flightVBody, flightGBody, flightConn = nil, nil, nil
local isSprinting = false

local triggerbotEnabled = false
local aimEnabled = false
local aimSmoothing = 0.15
local aimPart = "Head"
local tbLasering = false

local autoChokeEnabled = false
local lastChokeTick = 0

local sanityFreezeEnabled = false
local invisVisionEnabled = false
local noDoorCollision = false
local streamSpoofEnabled = false
local chokeRangeEnabled = false

local silentAimEnabled = true
local silentAimFov = 280
local laserLockTarget = nil
local laserLockUntil = 0
local lastLaserNetTick = 0
local serverConeFix = true
local serverRaycastOnly = true
local wallTryMode = false
local alignCameraToTarget = true
local autoLaserStop = true
local preOverheatStop = true
local preOverheatPercent = 88
local cameraAlignStrength = 0.12
local lastValidHitAt = 0
local lastHadTargetAt = 0
local laserStartAt = 0

local CHOKE_RANGE = 13
local RING_SIZE = CHOKE_RANGE * 2
local LASER_TICK = Config.LaserServerTickRate or 0.05
local LASER_MAX_RANGE = Config.LaserMaxRange or 500
local LASER_MAX_ANGLE = Config.LaserMaxAimAngle or 80
local LASER_COS_ANGLE = math.cos(math.rad(LASER_MAX_ANGLE))
local LASER_GRACE = Config.LaserTargetGracePeriod or 0.15
local TEMPV_LASER_RANGE = Config.TempVLaserRange or 200
local TEMPV_MAX_HEAT = Config.TempVLaserMaxHeat or 80
local LASER_MAX_HEAT = Config.LaserMaxHeat or 100
local RING_SYNC_INTERVAL = 0.35
local lastRingSync = 0

local espConnections = {}
local chamsHighlights = {}
local chamsPlayerSetup = {}
local doorCollisionCache = {}
local streamSpoofConn = nil
local streamCamHL = nil
local localRingData = nil
local playerRingData = {}

local function destroyRingEntry(data)
    if not data then return end
    if data.highlight then data.highlight:Destroy() end
    if data.part then data.part:Destroy() end
end

local function destroyAllRings()
    destroyRingEntry(localRingData)
    localRingData = nil
    for player, data in pairs(playerRingData) do
        destroyRingEntry(data)
        playerRingData[player] = nil
    end
end

-- ========== JUMP HEIGHT ==========
local function setJumpHeight()
    local char = lplr.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hum.JumpHeight = 4.8 end
end
setJumpHeight()
lplr.CharacterAdded:Connect(function(char)
    char:WaitForChild("Humanoid").JumpHeight = 4.8
end)

-- ========== ROLE DETECTION ==========
local function getPlayerRoleAttr(player)
    if not player then return "Hider" end
    local role = player:GetAttribute("Role")
    if role == "Homelander" then return "homelander" end
    if role == "Stormfront" then return "stormfront" end
    return "survivor"
end

local function getPlayerRole(player)
    if not player or not player.Character then return "survivor" end
    local ok, role = pcall(function()
        for _, obj in pairs(player.Character:GetDescendants()) do
            if obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("Accessory") then
                local n = obj.Name:upper()
                if n:find("HOMELANDER") then return "homelander" end
                if n:find("STORMFRONT") or n:find("STORM FRONT") then return "stormfront" end
                if n:find("OMNI") or n:find("DARK NOIR") or n:find("BLACKNOIR") or n:find("BLACK ADAM") or n:find("SUPERMAN") or n:find("SUPERGIRL") or n:find("THOR") or n:find("ZEUS") or n:find("KILLUA") or n:find("ELECTRO") then return "killer" end
            end
        end
        return "survivor"
    end)
    return ok and role or "survivor"
end

local function getRolePrefix(player)
    local r = getPlayerRole(player)
    if r == "homelander" then return "[H] " end
    if r == "stormfront" then return "[S] " end
    if r == "killer" then return "[K] " end
    return "[B] "
end

local function getBoxColor(player)
    local r = getPlayerRole(player)
    if homelanderEspEnabled and r ~= "survivor" then return Color3.fromRGB(178, 34, 34) end
    if teamEspEnabled and r == "survivor" then return Color3.fromRGB(0, 191, 255) end
    return Color3.new(1, 1, 1)
end

local function updateBoxColors()
    for _, conn in pairs(espConnections) do
        if conn.player and conn.player.Character then
            conn.box.Color = getBoxColor(conn.player)
        end
    end
end

-- ========== JUMP COOLDOWN ==========
local function setJumpCooldown(disabled)
    local char = lplr.Character
    if not char then return end
    local cd = char:FindFirstChild("Jump Cooldown")
    if cd then cd.Disabled = disabled end
end

lplr.CharacterAdded:Connect(function(char)
    if noJumpCooldownEnabled or bhopEnabled or infiniteJumpEnabled then
        local cd = char:WaitForChild("Jump Cooldown", 5)
        if cd then cd.Disabled = true end
    end
end)

UserInputService.JumpRequest:Connect(function()
    if not noJumpCooldownEnabled and not infiniteJumpEnabled and not bhopEnabled then return end
    local char = lplr.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
        if bhopEnabled then justJumped = true end
    elseif infiniteJumpEnabled then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

-- ========== LOCAL FLIGHT ==========
local function startLocalFlight()
    local char = lplr.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    hum.PlatformStand = true
    flightVBody = Instance.new("BodyVelocity")
    flightVBody.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flightVBody.Velocity = Vector3.new(0, 0, 0)
    flightVBody.Parent = hrp
    flightGBody = Instance.new("BodyGyro")
    flightGBody.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    flightGBody.D = 200
    flightGBody.P = 15000
    flightGBody.CFrame = hrp.CFrame
    flightGBody.Parent = hrp
    flightConn = RunService.RenderStepped:Connect(function()
        if not localFlightEnabled then return end
        local cf = camera.CFrame
        local vel = Vector3.new(0, 0, 0)
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then vel = vel + cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then vel = vel - cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then vel = vel - cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then vel = vel + cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vel = vel + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then vel = vel - Vector3.new(0, 1, 0) end
        if vel.Magnitude > 0 then vel = vel.Unit end
        if flightVBody then flightVBody.Velocity = vel * flightSpeed end
        if flightGBody then flightGBody.CFrame = cf end
    end)
end

local function stopLocalFlight()
    local char = lplr.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
    end
    if flightConn then flightConn:Disconnect(); flightConn = nil end
    if flightVBody then flightVBody:Destroy(); flightVBody = nil end
    if flightGBody then flightGBody:Destroy(); flightGBody = nil end
end

-- ========== SPRINT ==========
local function applySprintSpeed()
    local char = lplr.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 and isSprinting then
        hum.WalkSpeed = customSpeed
    end
end

local function startSprint()
    if isSprinting then return end
    isSprinting = true
    lplr:SetAttribute("IsSprinting", true)
    Network:FireServer("SprintStart")
    applySprintSpeed()
end

local function stopSprint()
    if not isSprinting then return end
    isSprinting = false
    lplr:SetAttribute("IsSprinting", false)
    local char = lplr.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 16 end
    end
    Network:FireServer("SprintStop")
end

-- ========== AIM / COMBAT ==========
local function getRaycastFilter(extra)
    local list = {}
    local char = lplr.Character
    if char then table.insert(list, char) end
    if extra then table.insert(list, extra) end
    return list
end

local function hasLineOfSight(targetPart)
    if not targetPart or not targetPart.Parent then return false end
    local origin = camera.CFrame.Position
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

local function isPlayerAlive(player)
    local char = player and player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0 and char.Parent ~= nil
end
local function getAimPart(player, partName)
    local char = player and player.Character
    if not char then return nil end
    return char:FindFirstChild(partName or aimPart)
        or char:FindFirstChild("Head")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("HumanoidRootPart")
end

local function getScreenFovDist(worldPos)
    local sp, onScreen = camera:WorldToViewportPoint(worldPos)
    if not onScreen or sp.Z <= 0 then return nil, false end
    local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    return (Vector2.new(sp.X, sp.Y) - center).Magnitude, true
end

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

local function getLaserMaxHeat()
    if isTempVLaser() then return TEMPV_MAX_HEAT end
    return LASER_MAX_HEAT
end

local function getLaserMaxRange()
    if isStormfront() then return LASER_MAX_RANGE end
    if isTempVLaser() then return TEMPV_LASER_RANGE end
    return LASER_MAX_RANGE
end

local function getCharHead()
    local char = lplr.Character
    return char and char:FindFirstChild("Head")
end

local function laserClientLOS(targetPart)
    if wallTryMode then return true end
    return hasLineOfSight(targetPart)
end

local function clampDirToServerCone(head, worldDir)
    local look = head.CFrame.LookVector
    local dot = look:Dot(worldDir)
    if dot >= LASER_COS_ANGLE then return worldDir end
    local perp = worldDir - look * dot
    if perp.Magnitude < 0.001 then perp = head.CFrame.RightVector else perp = perp.Unit end
    return (look * LASER_COS_ANGLE + perp * math.sin(math.rad(LASER_MAX_ANGLE))).Unit
end

local function clampAimToServerCone(head, desiredPos)
    local offset = desiredPos - head.Position
    if offset.Magnitude < 0.1 then return desiredPos end
    if not serverConeFix or isStormfront() then return desiredPos end
    local dir = offset.Unit
    return head.Position + clampDirToServerCone(head, dir) * math.min(offset.Magnitude, getLaserMaxRange())
end

local function serverMirrorHitsPlayer(aimPos)
    local head = getCharHead()
    local char = lplr.Character
    if not head or not char then return false, nil end
    local offset = aimPos - head.Position
    if offset.Magnitude < 0.1 then return false, nil end
    local dir = offset.Unit
    if not isStormfront() and head.CFrame.LookVector:Dot(dir) < LASER_COS_ANGLE then return false, nil end
    if offset.Magnitude > getLaserMaxRange() * 1.2 then return false, nil end
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = { char }
    params.FilterType = Enum.RaycastFilterType.Exclude
    local hit = workspace:Raycast(head.Position, dir * math.min(offset.Magnitude + 5, getLaserMaxRange()), params)
    if not hit or not hit.Instance then return false, nil end
    local model = hit.Instance:FindFirstAncestorOfClass("Model")
    local hum = model and model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 or model == char then return false, nil end
    return true, Players:GetPlayerFromCharacter(model)
end

local function getLaserTarget()
    if laserLockTarget and tick() < laserLockUntil then
        local part = getAimPart(laserLockTarget, "Head")
        if part and isPlayerAlive(laserLockTarget) and laserClientLOS(part) then
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
                if onScreen and fovDist and fovDist <= silentAimFov and laserClientLOS(part) then
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

local function getCrosshairLaserTarget()
    local unitRay = camera:ScreenPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    local params = RaycastParams.new()
    local char = lplr.Character
    if char then
        params.FilterDescendantsInstances = { char }
        params.FilterType = Enum.RaycastFilterType.Exclude
    end
    local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * getLaserMaxRange(), params)
    if result and result.Instance then
        local model = result.Instance:FindFirstAncestorOfClass("Model")
        local p = model and Players:GetPlayerFromCharacter(model)
        if p and p ~= lplr and isPlayerAlive(p) then
            local part = getAimPart(p, aimPart)
            if part and laserClientLOS(part) then return p, part end
        end
    end
    return nil, nil
end

local function hideVanillaLasers()
    pcall(function()
        local LM = require(RS.Modules.LaserManager)
        if LM.HideLasers then LM:HideLasers(lplr) end
    end)
end

local function shouldForceLaserStop(targetPlayer, aimPos)
    if not autoLaserStop then return false end
    if not canLaserNow() then return true end
    if lplr:GetAttribute("IsSuperVision") or lplr:GetAttribute("LaserOverheated") then return true end
    local hum = lplr.Character and lplr.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return true end
    if preOverheatStop and (lplr:GetAttribute("LaserHeat") or 0) >= getLaserMaxHeat() * (preOverheatPercent / 100) then
        return true
    end
    if not targetPlayer or not aimPos then
        return tbLasering and tick() - lastHadTargetAt > LASER_GRACE
    end
    if not isPlayerAlive(targetPlayer) then return true end
    if serverRaycastOnly then
        local hit, hitPlr = serverMirrorHitsPlayer(aimPos)
        if hit and (not hitPlr or hitPlr == targetPlayer) then
            lastValidHitAt = tick()
        elseif tbLasering and tick() - lastValidHitAt > LASER_GRACE then
            return true
        end
    else
        lastValidHitAt = tick()
    end
    if tbLasering and lplr:GetAttribute("IsLasering") ~= true and tick() - laserStartAt > 0.25 then
        return true
    end
    return false
end

local function getBestCombatTarget(maxFov, requireAlive, partOverride)
    local fov = maxFov or silentAimFov
    local bestPlayer, bestPart, bestScore = nil, nil, math.huge

    if laserLockTarget and tick() < laserLockUntil then
        local part = getAimPart(laserLockTarget, partOverride or aimPart)
        if part and isPlayerAlive(laserLockTarget) and hasLineOfSight(part) then
            return laserLockTarget, part
        end
        laserLockTarget = nil
    end

    for _, p in pairs(Players:GetPlayers()) do
        if p ~= lplr and isPlayerAlive(p) then
            local part = getAimPart(p, partOverride or aimPart)
            if part then
                local fovDist, onScreen = getScreenFovDist(part.Position)
                if onScreen and fovDist and fovDist <= fov and hasLineOfSight(part) then
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
        laserLockUntil = tick() + 0.25
    end
    return bestPlayer, bestPart
end

local function getClosestPlayerToCrosshair()
    local _, part = getBestCombatTarget(silentAimFov, true, aimPart)
    return part
end

local function getClosestPlayerInRange(range, useCrosshair)
    local char = lplr.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    if useCrosshair then
        local p = select(1, getBestCombatTarget(silentAimFov, true, aimPart))
        if p and p.Character then
            local root = p.Character:FindFirstChild("HumanoidRootPart")
            if root and (root.Position - hrp.Position).Magnitude <= range then
                return p
            end
        end
    end

    local closest, closestDist = nil, range
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= lplr and isPlayerAlive(p) then
            local root = p.Character:FindFirstChild("HumanoidRootPart")
            local head = p.Character:FindFirstChild("Head") or root
            if root and head and hasLineOfSight(head) then
                local dist = (root.Position - hrp.Position).Magnitude
                if dist < closestDist then closestDist = dist; closest = p end
            end
        end
    end
    return closest
end

local function stopLaser()
    if not tbLasering then return end
    tbLasering = false
    laserLockTarget = nil
    Network:FireServer("LaserStop")
    if isStormfront() then Network:FireServer("StormElecStop") end
    hideVanillaLasers()
end

local function runLaserCombat()
    if not canLaserNow() or not triggerbotEnabled then
        stopLaser()
        return
    end

    local targetPlayer, part
    if silentAimEnabled then
        targetPlayer, part = getLaserTarget()
    else
        targetPlayer, part = getCrosshairLaserTarget()
    end

    local head = getCharHead()
    local aimPos = (part and head) and clampAimToServerCone(head, part.Position) or nil

    if shouldForceLaserStop(targetPlayer, aimPos) then
        stopLaser()
        return
    end

    if not targetPlayer or not aimPos then
        if tbLasering then stopLaser() end
        return
    end

    lastHadTargetAt = tick()
    if alignCameraToTarget and part then
        camera.CFrame = camera.CFrame:Lerp(
            CFrame.new(camera.CFrame.Position, part.Position),
            cameraAlignStrength
        )
    end

    local now = tick()
    if now - lastLaserNetTick < LASER_TICK then return end
    lastLaserNetTick = now

    if not tbLasering then
        tbLasering = true
        lastValidHitAt = now
        laserStartAt = now
        Network:FireServer("LaserStart")
        if isStormfront() then Network:FireServer("StormElecStart") end
    end
    Network:FireServer("LaserUpdate", aimPos)
end

-- ========== NO DOOR COLLISION ==========
local function isDoorPart(obj)
    local p = obj.Parent
    while p and p ~= workspace do
        if p.Name:match("^DoorLeft") or p.Name:match("^DoorRight") then
            return true
        end
        p = p.Parent
    end
    return false
end

local function applyDoorCollision(bool)
    local activeMap = workspace:FindFirstChild("ActiveMap")
    if not activeMap then return end
    if bool then
        for _, obj in ipairs(activeMap:GetDescendants()) do
            if obj:IsA("BasePart") and isDoorPart(obj) then
                doorCollisionCache[obj] = obj.CanCollide
                obj.CanCollide = false
            end
        end
    else
        for part, original in pairs(doorCollisionCache) do
            if part and part.Parent then
                part.CanCollide = original
            end
        end
        doorCollisionCache = {}
    end
end

-- ========== STREAM SPOOF (без UI / без телефона) ==========
local function hideStreamUI()
    for _, gui in ipairs(playerGui:GetDescendants()) do
        if gui:IsA("GuiObject") then
            local n = gui.Name:lower()
            if n == "liveoverlay" or n == "phone" or n:find("stream") or n:find("recording") or n:find("viewer") then
                gui.Visible = false
            end
        end
    end
end

local function stashPhoneTool()
    local char = lplr.Character
    if not char then return end
    local phone = char:FindFirstChild("Phone")
    if phone and phone:IsA("Tool") then
        phone.Parent = lplr:FindFirstChild("Backpack") or lplr
    end
end

local function restoreStreamUI()
    for _, gui in ipairs(playerGui:GetDescendants()) do
        if gui.Name == "Phone" then
            gui.Visible = true
        end
    end
end

local function getSeekerPlayer()
    for _, p in ipairs(Players:GetPlayers()) do
        local role = p:GetAttribute("Role")
        if role == "Homelander" or role == "Stormfront" then
            return p
        end
    end
    return nil
end

local function isSeekerOnScreen(seeker)
    if not seeker or not isPlayerAlive(seeker) then return false end
    local head = seeker.Character and seeker.Character:FindFirstChild("Head")
    if not head then return false end
    local _, onScreen = camera:WorldToViewportPoint(head.Position)
    return onScreen and hasLineOfSight(head)
end

local function startStreamSpoof()
    hideStreamUI()
    stashPhoneTool()
    lplr.CameraMode = Enum.CameraMode.Classic
    if camera then camera.CameraType = Enum.CameraType.Custom end
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    RunService:UnbindFromRenderStep("PhoneCamStream")

    Network:FireServer("StartStream")

    streamSpoofConn = RunService.Heartbeat:Connect(function()
        if not streamSpoofEnabled then return end
        hideStreamUI()
        stashPhoneTool()

        local char = lplr.Character
        if char then
            char:SetAttribute("IsRecording", true)
        end

        Network:FireServer("UpdateStreamViewers", math.random(80, 400))

        local seeker = getSeekerPlayer()
        local onCam = seeker and isSeekerOnScreen(seeker)
        if onCam then
            if streamCamHL ~= seeker then
                if streamCamHL then
                    Network:FireServer("CameraOnHomelander", streamCamHL, false)
                end
                Network:FireServer("CameraOnHomelander", seeker, true)
                streamCamHL = seeker
            end
        elseif streamCamHL then
            Network:FireServer("CameraOnHomelander", streamCamHL, false)
            streamCamHL = nil
        end
    end)
end

local function stopStreamSpoof()
    if streamSpoofConn then
        streamSpoofConn:Disconnect()
        streamSpoofConn = nil
    end
    if streamCamHL then
        Network:FireServer("CameraOnHomelander", streamCamHL, false)
        streamCamHL = nil
    end
    local char = lplr.Character
    if char then char:SetAttribute("IsRecording", false) end
    Network:FireServer("EndStream")
    restoreStreamUI()
    if camera then camera.CameraType = Enum.CameraType.Custom end
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

-- ========== CHOKE RANGE (Part + Highlight) ==========
local function ringFillColor(inChoke, isLocal)
    if isLocal then return Color3.fromRGB(95, 8, 12) end
    if inChoke then return Color3.fromRGB(28, 85, 35) end
    return Color3.fromRGB(80, 8, 10)
end

local function buildFloorRing(name, hrp, fillColor)
    local part = Instance.new("Part")
    part.Name = name
    part.Shape = Enum.PartType.Cylinder
    part.Size = Vector3.new(0.12, RING_SIZE, RING_SIZE)
    part.Material = Enum.Material.Neon
    part.Color = fillColor
    part.Transparency = 0.55
    part.Anchored = false
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.Massless = true
    part.CastShadow = false
    part.CFrame = hrp.CFrame * CFrame.new(0, -2.85, 0) * CFrame.Angles(0, 0, math.rad(90))
    part.Parent = hrp

    local hl = Instance.new("Highlight")
    hl.Adornee = part
    hl.FillColor = fillColor
    hl.FillTransparency = 0.35
    hl.OutlineTransparency = 1
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = hrp

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = hrp
    weld.Part1 = part
    weld.Parent = part

    return { part = part, highlight = hl, hrp = hrp }
end

local function syncChokeRings()
    if not chokeRangeEnabled then
        destroyAllRings()
        return
    end

    local myChar = lplr.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")

    if myHrp then
        if not localRingData or localRingData.hrp ~= myHrp or not localRingData.part or not localRingData.part.Parent then
            destroyRingEntry(localRingData)
            localRingData = buildFloorRing("_ChokeRingLocal", myHrp, ringFillColor(false, true))
        else
            localRingData.highlight.FillColor = ringFillColor(false, true)
            localRingData.part.Color = ringFillColor(false, true)
        end
    elseif localRingData then
        destroyRingEntry(localRingData)
        localRingData = nil
    end

    local seen = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= lplr then
            seen[player] = true
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local inRange = myHrp and (hrp.Position - myHrp.Position).Magnitude <= CHOKE_RANGE
                local color = ringFillColor(inRange, false)
                local data = playerRingData[player]
                if not data or data.hrp ~= hrp or not data.part or not data.part.Parent then
                    destroyRingEntry(data)
                    playerRingData[player] = buildFloorRing("_ChokeRing_" .. player.Name, hrp, color)
                else
                    data.highlight.FillColor = color
                    data.part.Color = color
                end
            elseif playerRingData[player] then
                destroyRingEntry(playerRingData[player])
                playerRingData[player] = nil
            end
        end
    end

    for player, data in pairs(playerRingData) do
        if not seen[player] then
            destroyRingEntry(data)
            playerRingData[player] = nil
        end
    end
end

local function setChokeRangeEnabled(on)
    chokeRangeEnabled = on
    if on then
        syncChokeRings()
    else
        destroyAllRings()
    end
end

lplr.CharacterAdded:Connect(function()
    tbLasering = false
    laserLockTarget = nil
    lastValidHitAt = 0
    lastHadTargetAt = 0
    laserStartAt = 0
    if chokeRangeEnabled then
        task.defer(syncChokeRings)
    end
    if streamSpoofEnabled then
        task.wait(0.6)
        stopStreamSpoof()
        startStreamSpoof()
    end
end)

-- ========== CHAMS (только живые) ==========
local function getChamsColor(player)
    local r = getPlayerRoleAttr(player)
    if r == "homelander" then return Color3.fromRGB(220, 50, 50) end
    if r == "stormfront" then return Color3.fromRGB(180, 90, 255) end
    return Color3.fromRGB(0, 160, 255)
end

local function addChams(player)
    if player == lplr or not chamsEnabled then return end
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end

    local existing = chamsHighlights[player]
    if existing and existing.Parent == char then return end
    if existing then existing:Destroy() end

    local hl = Instance.new("Highlight")
    hl.Name = "_CyanogenChams"
    hl.FillColor = getChamsColor(player)
    hl.FillTransparency = 0.45
    hl.OutlineTransparency = 1
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = char
    chamsHighlights[player] = hl
end

local function removeChams(player)
    if chamsHighlights[player] then
        chamsHighlights[player]:Destroy()
        chamsHighlights[player] = nil
    end
end

local function clearAllChams()
    for _, hl in pairs(chamsHighlights) do
        if hl and hl.Parent then hl:Destroy() end
    end
    chamsHighlights = {}
end

local function setupChamsPlayer(player)
    if player == lplr or chamsPlayerSetup[player] then return end
    chamsPlayerSetup[player] = true

    player.CharacterAdded:Connect(function(char)
        task.defer(function()
            if not chamsEnabled then return end
            addChams(player)
            local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 8)
            if hum then
                hum.Died:Connect(function()
                    removeChams(player)
                end)
                hum.HealthChanged:Connect(function(hp)
                    if not chamsEnabled then return end
                    if hp <= 0 then
                        removeChams(player)
                    elseif hp > 0 and (not chamsHighlights[player] or chamsHighlights[player].Parent ~= char) then
                        addChams(player)
                    end
                end)
            end
        end)
    end)

    if player.Character and chamsEnabled then
        addChams(player)
    end
end

-- ========== MAIN HEARTBEAT ==========
RunService.Heartbeat:Connect(function()
    setJumpHeight()

    -- NOCLIP
    if noclip then
        local char = lplr.Character
        if char then
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
        end
    end

    -- BHOP
    if bhopEnabled then
        local char = lplr.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hum and hrp then
                if hum.FloorMaterial ~= Enum.Material.Air then
                    justJumped = false
                elseif justJumped then
                    local lv = hrp.CFrame.LookVector
                    hrp.AssemblyLinearVelocity = Vector3.new(lv.X * 36, hrp.AssemblyLinearVelocity.Y, lv.Z * 36)
                end
            end
        end
    end

    -- AUTO SPRINT
    if autoSprintEnabled then
        local char = lplr.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 and hum.MoveDirection.Magnitude > 0.1 then
                if not isSprinting then startSprint() end
                hum.WalkSpeed = customSpeed
            elseif isSprinting then
                stopSprint()
            end
        end
    elseif isSprinting then
        stopSprint()
    end

    -- SANITY FREEZE
    if sanityFreezeEnabled then
        lplr:SetAttribute("Sanity", 100)
        local char = lplr.Character
        if char then char:SetAttribute("Sanity", 100) end
    end

    -- INVISIBLE FOR VISION
    if invisVisionEnabled then
        local char = lplr.Character
        if char and not char:GetAttribute("IsCrouching") then
            char:SetAttribute("IsCrouching", true)
            Network:FireServer("CrouchStart")
        end
    elseif not invisVisionEnabled then
        local char = lplr.Character
        if char and char:GetAttribute("IsCrouching") and not char:GetAttribute("_realCrouch") then
            char:SetAttribute("IsCrouching", nil)
            Network:FireServer("CrouchStop")
        end
    end

    -- BLOCK RECORDING (только без stream spoof)
    if not streamSpoofEnabled then
        local charRec = lplr.Character
        if charRec then charRec:SetAttribute("IsRecording", nil) end
    end

    -- AUTO CHOKE
    if autoChokeEnabled then
        local t = tick()
        if t - lastChokeTick >= 6 then
            local target = getClosestPlayerInRange(CHOKE_RANGE, silentAimEnabled)
            if target then
                lastChokeTick = t
                Network:FireServer("ChokeAttempt")
            end
        end
    end

    if chokeRangeEnabled and tick() - lastRingSync >= RING_SYNC_INTERVAL then
        lastRingSync = tick()
        syncChokeRings()
    end
end)

-- ========== COMBAT LOOP (RenderStepped) ==========
RunService.RenderStepped:Connect(function()
    if aimEnabled and not silentAimEnabled then
        local target = getClosestPlayerToCrosshair()
        if target then
            local fovDist = select(1, getScreenFovDist(target.Position))
            if fovDist and fovDist <= silentAimFov then
                camera.CFrame = camera.CFrame:Lerp(CFrame.new(camera.CFrame.Position, target.Position), aimSmoothing)
            end
        end
    end
    runLaserCombat()
end)

Players.PlayerRemoving:Connect(function(player)
    if playerRingData[player] then
        destroyRingEntry(playerRingData[player])
        playerRingData[player] = nil
    end
    removeChams(player)
end)

-- ========== PLAYER ESP ==========
local function createBoxESP(player)
    local HeadOff = Vector3.new(0, 0.5, 0)
    local LegOff = Vector3.new(0, 4, 0)
    local widthScale = 2.5

    local BoxOutline = Drawing.new("Square")
    BoxOutline.Visible = false; BoxOutline.Color = Color3.new(0,0,0); BoxOutline.Thickness = 3; BoxOutline.Transparency = 1; BoxOutline.Filled = false

    local Box = Drawing.new("Square")
    Box.Visible = false; Box.Color = Color3.new(1,1,1); Box.Thickness = 1; Box.Transparency = 1; Box.Filled = false

    local LabelOutline = Drawing.new("Text")
    LabelOutline.Visible = false; LabelOutline.Color = Color3.new(0,0,0); LabelOutline.Size = 13; LabelOutline.Font = 2; LabelOutline.Outline = true; LabelOutline.Center = true

    local Label = Drawing.new("Text")
    Label.Visible = false; Label.Color = Color3.new(1,1,1); Label.Size = 13; Label.Font = 2; Label.Outline = false; Label.Center = true

    local connection = RunService.RenderStepped:Connect(function()
        if not espEnabled then
            Box.Visible = false; BoxOutline.Visible = false; Label.Visible = false; LabelOutline.Visible = false
            return
        end
        local localRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
        local alive = player.Character
            and player.Character:FindFirstChild("HumanoidRootPart")
            and player.Character:FindFirstChild("Humanoid")
            and player ~= lplr
            and player.Character.Humanoid.Health > 0

        if alive then
            local RootPart = player.Character.HumanoidRootPart
            local Head = player.Character:FindFirstChild("Head")
            if not Head then return end
            local RootPosition, onScreen = camera:WorldToViewportPoint(RootPart.Position)
            local HeadPosition = camera:WorldToViewportPoint(Head.Position + HeadOff)
            local LegPosition = camera:WorldToViewportPoint(RootPart.Position - LegOff)
            Box.Color = getBoxColor(player)
            local dist = localRoot and math.round((RootPart.Position - localRoot.Position).Magnitude) or 0
            local prefix = getRolePrefix(player)
            local labelText = prefix .. player.Name .. " [" .. dist .. "m]"
            if onScreen then
                local boxWidth = (1000 / RootPosition.Z) * widthScale
                local boxHeight = HeadPosition.Y - LegPosition.Y
                local boxX = RootPosition.X - boxWidth / 2
                local boxY = RootPosition.Y - boxHeight / 2
                BoxOutline.Size = Vector2.new(boxWidth, boxHeight); BoxOutline.Position = Vector2.new(boxX, boxY); BoxOutline.Visible = true
                Box.Size = Vector2.new(boxWidth, boxHeight); Box.Position = Vector2.new(boxX, boxY); Box.Visible = true
                if labelEnabled then
                    Label.Text = labelText; Label.Position = Vector2.new(RootPosition.X, boxY - 18); Label.Visible = true
                    LabelOutline.Text = labelText; LabelOutline.Position = Vector2.new(RootPosition.X, boxY - 18); LabelOutline.Visible = true
                else
                    Label.Visible = false; LabelOutline.Visible = false
                end
            else
                Box.Visible = false; BoxOutline.Visible = false; Label.Visible = false; LabelOutline.Visible = false
            end
        else
            Box.Visible = false; BoxOutline.Visible = false; Label.Visible = false; LabelOutline.Visible = false
        end
    end)

    table.insert(espConnections, {connection = connection, box = Box, outline = BoxOutline, label = Label, labelOutline = LabelOutline, player = player})
end

-- ========== GUI ==========
local function restoreNoclipCollision()
    local char = lplr.Character
    if not char then return end
    for _, part in pairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = part.Name == "Head" or part.Name == "Torso"
        end
    end
end

-- Visuals
local espSec = visualsTab:Section("ESP")
espSec:ToggleKeyBind("Box ESP", Enum.KeyCode.F1, function(on)
    espEnabled = on
    if not on then
        for _, conn in pairs(espConnections) do
            if conn.connection then conn.connection:Disconnect() end
            if conn.box then conn.box:Remove() end
            if conn.outline then conn.outline:Remove() end
            if conn.label then conn.label:Remove() end
            if conn.labelOutline then conn.labelOutline:Remove() end
        end
        espConnections = {}
        return
    end
    for _, v in pairs(Players:GetPlayers()) do
        if v ~= lplr then createBoxESP(v) end
    end
    Players.PlayerAdded:Connect(function(v) createBoxESP(v) end)
end)
espSec:Toggle("Name + Distance", function(on) labelEnabled = on end)
espSec:Toggle("Homelander Color", function(on)
    homelanderEspEnabled = on
    updateBoxColors()
end)
espSec:Toggle("Team Color", function(on)
    teamEspEnabled = on
    updateBoxColors()
end)

local chamSec = visualsTab:Section("Chams")
chamSec:ToggleKeyBind("Chams", Enum.KeyCode.F2, function(on)
    chamsEnabled = on
    if on then
        for _, p in pairs(Players:GetPlayers()) do setupChamsPlayer(p) end
        Players.PlayerAdded:Connect(function(p) setupChamsPlayer(p) end)
    else
        clearAllChams()
    end
end)

visualsTab:Section("World"):ToggleKeyBind("Choke Range", Enum.KeyCode.F4, function(on)
    setChokeRangeEnabled(on)
end)

-- Movement
local moveSec = movementTab:Section("Movement")
moveSec:ToggleKeyBind("Noclip", Enum.KeyCode.RightShift, function(on)
    noclip = on
    if not on then restoreNoclipCollision() end
end)
moveSec:ToggleKeyBind("Local Flight", Enum.KeyCode.G, function(on)
    localFlightEnabled = on
    if on then startLocalFlight() else stopLocalFlight() end
end)
moveSec:Slider("Flight Speed", 10, 200, function(val) flightSpeed = val end)

local jumpSec = movementTab:Section("Jump")
jumpSec:ToggleKeyBind("Bunny Hop", Enum.KeyCode.B, function(on)
    bhopEnabled = on
    if on then setJumpCooldown(true)
    elseif not noJumpCooldownEnabled and not infiniteJumpEnabled then setJumpCooldown(false) end
end)
jumpSec:ToggleKeyBind("Infinite Jump", Enum.KeyCode.J, function(on)
    infiniteJumpEnabled = on
    if on then setJumpCooldown(true)
    elseif not noJumpCooldownEnabled and not bhopEnabled then setJumpCooldown(false) end
end)
jumpSec:ToggleKeyBind("No Jump Cooldown", Enum.KeyCode.K, function(on)
    noJumpCooldownEnabled = on
    setJumpCooldown(on)
end)

local speedSec = movementTab:Section("Speed")
speedSec:ToggleKeyBind("Auto Sprint", Enum.KeyCode.CapsLock, function(on)
    autoSprintEnabled = on
    if not on then stopSprint() end
end)
speedSec:Slider("Sprint Speed", 16, 100, function(val)
    customSpeed = val
    applySprintSpeed()
end)

-- Combat
local laserSec = combatTab:Section("Laser")
laserSec:ToggleKeyBind("Triggerbot", Enum.KeyCode.Z, function(on)
    triggerbotEnabled = on
    if not on then stopLaser() end
end)
laserSec:ToggleKeyBind("Silent Aim", Enum.KeyCode.V, function(on) silentAimEnabled = on end)
laserSec:Slider("Silent FOV", 80, 500, function(val) silentAimFov = val end)
laserSec:DropDown("Aim Part", {"Head", "Torso", "HumanoidRootPart"}, function(val) aimPart = val end)
laserSec:Toggle("Server cone fix", function(on) serverConeFix = on end)
laserSec:Toggle("Server raycast check", function(on) serverRaycastOnly = on end)
laserSec:Toggle("Wall try", function(on) wallTryMode = on end)
laserSec:Toggle("Align camera", function(on) alignCameraToTarget = on end)
laserSec:Slider("Camera align %", 1, 40, function(val) cameraAlignStrength = val / 100 end)
laserSec:Toggle("Auto LaserStop", function(on) autoLaserStop = on end)
laserSec:Toggle("Stop before overheat", function(on) preOverheatStop = on end)
laserSec:Slider("Heat stop %", 50, 99, function(val) preOverheatPercent = val end)

local aimSec = combatTab:Section("Aim Assist")
aimSec:ToggleKeyBind("Aim Assist", Enum.KeyCode.X, function(on) aimEnabled = on end)
aimSec:Slider("Smoothing", 1, 100, function(val) aimSmoothing = val / 100 end)

combatTab:Section("Homelander"):ToggleKeyBind("Auto Choke", Enum.KeyCode.C, function(on) autoChokeEnabled = on end)

-- Utility
local survSec = utilityTab:Section("Survivor")
survSec:ToggleKeyBind("Sanity Freeze", Enum.KeyCode.N, function(on) sanityFreezeEnabled = on end)
survSec:ToggleKeyBind("Invisible for Vision", Enum.KeyCode.H, function(on)
    invisVisionEnabled = on
    if not on then
        local char = lplr.Character
        if char then
            char:SetAttribute("IsCrouching", nil)
            Network:FireServer("CrouchStop")
        end
    end
end)
survSec:ToggleKeyBind("No Door Collision", Enum.KeyCode.U, function(on)
    noDoorCollision = on
    applyDoorCollision(on)
end)

local streamSec = utilityTab:Section("Stream")
streamSec:ToggleKeyBind("Stream Spoof", Enum.KeyCode.P, function(on)
    streamSpoofEnabled = on
    if on then startStreamSpoof() else stopStreamSpoof() end
end)

creditsTab:Section("Credits"):Credit("untern v2 — cyano-hub")

Luxt:SetTheme("Grey")
print("[Cyanogen] Loaded — one file, all tabs")
