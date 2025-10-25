-- Combined ESP + Aim Lock + Triggerbot Script for Roblox with Toggle Menu, Adjustable FOV, and FOV Circle
-- Execute this in your executor as a LocalScript equivalent.
-- ESP: Highlights teammates in green (visible) or magenta (behind wall), enemies in red (visible) or blue (behind wall), with periodic reload every 0.3 seconds for faster color updates. Toggleable.
-- Team ESP: When toggled off, ESP only highlights enemies (not teammates). Toggleable.
-- Aim Lock: Holds right mouse button (MouseButton2) to instantly snap camera onto head closest to your cursor on screen, only if visible (no wall). Toggleable.
-- Always Aim: When toggled, continuously snaps camera to closest visible target in FOV without holding RMB. Toggleable.
-- Triggerbot: When toggled with "E" key (and enabled in menu), continuously auto-fires at closest valid target within FOV AND clear line of sight (no wall). Respects team check and FOV.
-- Triggerbot now uses mouse1click() for reliable firing (exploit function, if available), with fallback to Tool:Activate().
-- Silent Aim: Hooks mouse.Hit/Target to redirect shots to closest enemy head within FOV without moving crosshair. Works with triggerbot/manual firing. Toggleable, respects team check. Requires advanced exploit functions (getrawmetatable, newcclosure).
-- Triggerbot Indicator: Small label under crosshair shows "TRIGGERBOT ON/OFF" when toggled.
-- FOV: Adjustable max screen distance (pixels) for aimbot/triggerbot/silent aim targeting. Default 150.
-- FOV Circle: Visual circle around cursor (red, semi-transparent filled with white border) to show FOV radius. Toggleable, updates in real-time.
-- Menu: Press 'Insert' key to toggle a draggable GUI menu for toggling all features.
-- Team Check: When on, targets only enemies (different team); off, targets all players (except self).
-- ESP Colors: Adjustable RGB values for each ESP color mode via menu text boxes.
-- Misc: Viewmodel FOV adjustment via textbox (always active, continuously applied). Bunnyhop toggle for spamming jumps while holding space (only when grounded).
-- GUI parents to CoreGui for persistence in executors.
-- Assumes your game uses Teams (e.g., player.Team ~= nil).
-- Note: This only affects your local client. Use at your own risk; exploiting can lead to bans.
-- Fix: Wrapped exploit-specific functions (mouse1click, getrawmetatable, newcclosure) in existence checks to prevent "attempt to call a nil value" errors on unsupported executors.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService") -- Kept for potential future use
local workspace = game:GetService("Workspace") -- For raycasting in wall check

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local coreGui = game:GetService("CoreGui") -- For exploit GUI persistence
local camera = workspace.CurrentCamera
local mouse = localPlayer:GetMouse()

-- Menu Variables
local menuGui = nil
local espEnabled = true
local teamEspEnabled = true
local aimbotEnabled = true
local alwaysAimEnabled = false -- Always Aim toggle
local triggerbotEnabled = true -- Triggerbot enable/disable in menu
local triggerbotActive = false -- Triggerbot toggle state (via E key)
local silentAimEnabled = false -- NEW: Silent Aim toggle
local teamCheckEnabled = true
local fovValue = 150 -- Default FOV in pixels (screen distance threshold)
local fovCircleVisible = true -- Default FOV circle on
local menuVisible = false
local viewmodelFovValue = camera.FieldOfView
local bunnyhopEnabled = false
local spaceHeld = false

-- ESP Color Variables
local espTeamVisibleColor = Color3.fromRGB(0, 255, 0)
local espTeamWallColor = Color3.fromRGB(255, 0, 255)
local espEnemyVisibleColor = Color3.fromRGB(255, 0, 0)
local espEnemyWallColor = Color3.fromRGB(0, 0, 255)

-- NEW: Silent Aim Variables
local silentAimTargetPart = nil
local silentAimVisibleCheck = false -- Option for visible-only silent aim (add toggle later if needed)

-- Wall Check Function (shared for aimbot, triggerbot, and ESP)
local function hasClearLineOfSight(localHead, targetHead)
    local rayDirection = targetHead.Position - localHead.Position
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {localPlayer.Character} -- Ignore local character
    local raycastResult = workspace:Raycast(localHead.Position, rayDirection, raycastParams)
    
    if raycastResult then
        -- If hit something that's not part of the target's character, block
        if not raycastResult.Instance:IsDescendantOf(targetHead.Parent) then
            return false
        end
    end
    
    return true
end

-- NEW: Shared function to get closest target part (used by aimbot, triggerbot, silent aim)
local function getClosestTargetPart(useTeamCheck, requireVisible)
    local mousePos = Vector2.new(mouse.X, mouse.Y)
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("Head") then return nil end
    local localHead = character.Head
    
    local closest = nil
    local shortestScreenDistance = math.huge
    
    for _, player in pairs(Players:GetPlayers()) do
        if player == localPlayer then continue end
        if useTeamCheck and player.Team == localPlayer.Team then continue end -- Team check
        
        local enemyChar = player.Character
        if not enemyChar or not enemyChar:FindFirstChild("Head") then continue end
        
        local targetHead = enemyChar.Head
        local screenPos, onScreen = camera:WorldToScreenPoint(targetHead.Position)
        if not onScreen then continue end
        
        local screenDistance = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
        if screenDistance > fovValue then continue end -- FOV check
        
        -- Visible check if required
        if requireVisible and not hasClearLineOfSight(localHead, targetHead) then continue end
        
        if screenDistance < shortestScreenDistance then
            shortestScreenDistance = screenDistance
            closest = targetHead
        end
    end
    
    return closest
end

-- ESP Variables and Functions
local highlights = {} -- Track highlights for easy toggle off

local function createHighlight(player)
    if player == localPlayer then return end
    
    local character = player.Character
    if not character then return end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end
    
    local localCharacter = localPlayer.Character
    if not localCharacter or not localCharacter:FindFirstChild("Head") then return end
    local localHead = localCharacter.Head
    
    local targetHead = character:FindFirstChild("Head")
    if not targetHead then return end
    
    -- Determine team
    local localTeam = localPlayer.Team
    local playerTeam = player.Team
    local isTeammate = (localTeam == playerTeam) or (not localTeam or not playerTeam)
    
    -- Skip teammates if team ESP is disabled
    if isTeammate and not teamEspEnabled then return end
    
    -- Remove existing if any
    if highlights[player] then
        highlights[player]:Destroy()
    end
    
    -- Wall check for color
    local clearSight = hasClearLineOfSight(localHead, targetHead)
    local fillColor
    if isTeammate then
        fillColor = clearSight and espTeamVisibleColor or espTeamWallColor
    else
        fillColor = clearSight and espEnemyVisibleColor or espEnemyWallColor
    end
    
    -- Create Highlight
    local highlight = Instance.new("Highlight")
    highlight.Parent = character
    highlight.Adornee = character
    highlight.FillColor = fillColor
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    
    highlights[player] = highlight
end

local function removeAllHighlights()
    for player, highlight in pairs(highlights) do
        if highlight then highlight:Destroy() end
    end
    highlights = {}
end

local function updateAllHighlights()
    if not espEnabled then 
        removeAllHighlights()
        return 
    end
    
    local localCharacter = localPlayer.Character
    if not localCharacter or not localCharacter:FindFirstChild("Head") then return end
    local localHead = localCharacter.Head
    
    for _, player in pairs(Players:GetPlayers()) do
        if player == localPlayer then continue end
        
        local character = player.Character
        if not character then 
            if highlights[player] then
                highlights[player]:Destroy()
                highlights[player] = nil
            end
            continue
        end
        
        local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoidRootPart then 
            if highlights[player] then
                highlights[player]:Destroy()
                highlights[player] = nil
            end
            continue
        end
        
        local targetHead = character:FindFirstChild("Head")
        if not targetHead then 
            if highlights[player] then
                highlights[player]:Destroy()
                highlights[player] = nil
            end
            continue
        end
        
        -- Determine team
        local localTeam = localPlayer.Team
        local playerTeam = player.Team
        local isTeammate = (localTeam == playerTeam) or (not localTeam or not playerTeam)
        
        -- Skip teammates if team ESP disabled (remove highlight if exists)
        if isTeammate and not teamEspEnabled then 
            if highlights[player] then
                highlights[player]:Destroy()
                highlights[player] = nil
            end
            continue
        end
        
        -- Create if not exists
        if not highlights[player] then
            local highlight = Instance.new("Highlight")
            highlight.Parent = character
            highlight.Adornee = character
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.FillTransparency = 0.5
            highlight.OutlineTransparency = 0
            highlights[player] = highlight
        end
        
        local highlight = highlights[player]
        
        -- Wall check and update color only
        local clearSight = hasClearLineOfSight(localHead, targetHead)
        local fillColor
        if isTeammate then
            fillColor = clearSight and espTeamVisibleColor or espTeamWallColor
        else
            fillColor = clearSight and espEnemyVisibleColor or espEnemyWallColor
        end
        
        highlight.FillColor = fillColor
    end
end

-- Initial ESP setup
updateAllHighlights()

-- Player events for ESP
Players.PlayerAdded:Connect(function(player)
    wait(1)
    if espEnabled then createHighlight(player) end
    player.CharacterAdded:Connect(function()
        wait(0.5)
        if espEnabled then createHighlight(player) end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    if highlights[player] then
        highlights[player]:Destroy()
        highlights[player] = nil
    end
end)

-- Periodic ESP update (every 0.3 seconds for stability)
spawn(function()
    while true do
        wait(0.3)
        if espEnabled then
            updateAllHighlights()
        end
    end
end)

-- Aim Lock Variables and Functions
local isAiming = false
local currentTarget = nil

local function updateAimLock()
    local shouldAim = (alwaysAimEnabled or isAiming) and aimbotEnabled
    if not shouldAim then return end
    
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("Head") then return end
    local localHead = character.Head
    
    local targetHead = currentTarget
    if not targetHead or not targetHead.Parent then
        currentTarget = getClosestTargetPart(teamCheckEnabled, true) -- Visible required for aim lock
        targetHead = currentTarget
    end
    
    if not targetHead then return end
    
    -- Wall check: Only aim if clear line of sight
    if not hasClearLineOfSight(localHead, targetHead) then
        currentTarget = nil -- Reset target if blocked
        return
    end
    
    local newCFrame = CFrame.lookAt(localHead.Position, targetHead.Position)
    
    -- Snap camera
    camera.CFrame = newCFrame
end

-- Aim Lock Input (for manual hold)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isAiming = true
    elseif input.KeyCode == Enum.KeyCode.E and triggerbotEnabled then
        triggerbotActive = not triggerbotActive
        print("Triggerbot " .. (triggerbotActive and "activated" or "deactivated") .. " with E key") -- Debug print
    elseif input.KeyCode == Enum.KeyCode.Space then
        spaceHeld = true
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        isAiming = false
        if not alwaysAimEnabled then
            currentTarget = nil
        end
    elseif input.KeyCode == Enum.KeyCode.Space then
        spaceHeld = false
    end
end)

-- Triggerbot Variables and Functions
local lastTriggerTime = 0
local triggerDelay = 0.05 -- Slightly increased delay for stability (20 shots/sec)

local function triggerFire(targetHead)
    local currentTime = tick()
    if currentTime - lastTriggerTime < triggerDelay then return end
    lastTriggerTime = currentTime
    
    -- Method 1: Tool Activate (common in Roblox games for firing weapons)
    pcall(function()
        local character = localPlayer.Character
        if character then
            local tool = character:FindFirstChildOfClass("Tool")
            if tool then
                tool:Activate()
                print("Tool activated") -- Debug
            end
        end
    end)
    
    -- Method 2: Simulate left mouse click using exploit function (reliable across most executors, if available)
    pcall(function()
        if mouse1click then
            mouse1click() -- Synchronous click simulation
            print("Mouse click simulated via mouse1click") -- Debug
        else
            print("mouse1click not available, skipping") -- Debug
        end
    end)
end

local function updateTriggerbot()
    if not triggerbotEnabled or not triggerbotActive then return end -- Now based on toggle, not RMB hold
    
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("Head") then return end
    local localHead = character.Head
    
    local targetHead = getClosestTargetPart(teamCheckEnabled, true) -- Visible required for triggerbot
    if not targetHead then 
        print("No valid target found for triggerbot") -- Debug: Helps identify if targeting is the issue
        return 
    end
    
    print("Target found at distance: " .. (Vector2.new(mouse.X, mouse.Y) - Vector2.new(camera:WorldToScreenPoint(targetHead.Position).X, camera:WorldToScreenPoint(targetHead.Position).Y)).Magnitude) -- Debug
    
    -- Wall check: Raycast from local head to target head
    if not hasClearLineOfSight(localHead, targetHead) then
        print("Wall blocking target") -- Debug
        return -- Skip if blocked
    end
    
    print("Clear shot, firing") -- Debug
    triggerFire(targetHead)
end

-- NEW: Silent Aim Hook Setup (only if exploit functions available)
local function setupSilentAim()
    if not getrawmetatable or not newcclosure then
        print("Silent Aim requires getrawmetatable and newcclosure; disabling hook.") -- Debug
        return
    end
    
    local mt = getrawmetatable(game)
    local oldIndex = mt.__index
    setreadonly(mt, false)

    mt.__index = newcclosure(function(self, key)
        local original = oldIndex(self, key)
        
        if not silentAimEnabled or self ~= mouse or (key ~= "Hit" and key ~= "Target") then
            return original
        end
        
        if silentAimTargetPart then
            if key == "Hit" then
                return CFrame.new(original.Position, silentAimTargetPart.Position)
            elseif key == "Target" then
                return silentAimTargetPart
            end
        end
        
        return original
    end)

    setreadonly(mt, true)
end

-- Initialize silent aim hook if functions available
setupSilentAim()

-- Update Silent Aim Target (runs every frame when enabled)
RunService.Heartbeat:Connect(function()
    if silentAimEnabled then
        silentAimTargetPart = getClosestTargetPart(teamCheckEnabled, silentAimVisibleCheck)
    else
        silentAimTargetPart = nil
    end
end)

-- Viewmodel FOV Update Function (always active)
local function updateViewmodelFOV()
    camera.FieldOfView = viewmodelFovValue
end

-- Bunnyhop Function (spam jump while holding space, only when grounded)
local function updateBunnyhop()
    if not bunnyhopEnabled or not spaceHeld then return end
    local character = localPlayer.Character
    if not character then return end
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end
    if humanoid:GetState() == Enum.HumanoidStateType.Freefall or humanoid:GetState() == Enum.HumanoidStateType.Jumping then return end
    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
end

RunService.RenderStepped:Connect(function()
    updateAimLock()
    updateTriggerbot()
    updateViewmodelFOV()
    updateBunnyhop()
end)

-- FOV Circle Creation
local fovCircleGui = Instance.new("ScreenGui")
fovCircleGui.Name = "FOVCircleGui"
fovCircleGui.Parent = coreGui
fovCircleGui.ResetOnSpawn = false
fovCircleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local circleFrame = Instance.new("Frame")
circleFrame.Name = "FOVCircle"
circleFrame.Parent = fovCircleGui
circleFrame.BackgroundColor3 = Color3.fromRGB(255, 0, 0) -- Color doesn't matter when fully transparent
circleFrame.BackgroundTransparency = 1 -- Fully transparent (no fill)
circleFrame.BorderSizePixel = 0 -- Disable old border (UIStroke will handle it)
circleFrame.Position = UDim2.new(0, 0, 0, 0)
circleFrame.AnchorPoint = Vector2.new(0.5, 0.5)
circleFrame.Visible = fovCircleVisible

local uicorner = Instance.new("UICorner")
uicorner.CornerRadius = UDim.new(1, 0) -- Full circle
uicorner.Parent = circleFrame

-- Add UIStroke for better outline
local uistroke = Instance.new("UIStroke")
uistroke.Color = Color3.fromRGB(255, 255, 255) -- White outline
uistroke.Thickness = 2 -- Stroke thickness
uistroke.Transparency = 0 -- Fully opaque outline
uistroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- Stroke on the border
uistroke.Parent = circleFrame

-- Update FOV Circle Position and Size (follows mouse, respects toggles and FOV value)
RunService.Heartbeat:Connect(function()
    if fovCircleVisible and (aimbotEnabled or triggerbotEnabled or silentAimEnabled) then -- Show if any targeting enabled
        circleFrame.Position = UDim2.new(0, mouse.X, 0, mouse.Y)
        circleFrame.Size = UDim2.new(0, fovValue * 2, 0, fovValue * 2)
        circleFrame.Visible = true
    else
        circleFrame.Visible = false
    end
end)

-- Triggerbot Indicator Creation
local indicatorGui = Instance.new("ScreenGui")
indicatorGui.Name = "TriggerIndicatorGui"
indicatorGui.Parent = coreGui
indicatorGui.ResetOnSpawn = false
indicatorGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local indicatorLabel = Instance.new("TextLabel")
indicatorLabel.Name = "TriggerIndicator"
indicatorLabel.Parent = indicatorGui
indicatorLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
indicatorLabel.BackgroundTransparency = 0.5
indicatorLabel.BorderSizePixel = 1
indicatorLabel.BorderColor3 = Color3.fromRGB(255, 255, 255)
indicatorLabel.Position = UDim2.new(0.5, 0, 0.5, 10) -- Under crosshair (center screen, offset down)
indicatorLabel.AnchorPoint = Vector2.new(0.5, 0)
indicatorLabel.Size = UDim2.new(0, 100, 0, 20)
indicatorLabel.Font = Enum.Font.FredokaOne
indicatorLabel.Text = "TRIGGERBOT OFF"
indicatorLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
indicatorLabel.TextSize = 12
indicatorLabel.Visible = false -- Hidden by default

-- Update Triggerbot Indicator
RunService.Heartbeat:Connect(function()
    if triggerbotActive and triggerbotEnabled then
        indicatorLabel.Text = "TRIGGERBOT ON"
        indicatorLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        indicatorLabel.Visible = true
    else
        indicatorLabel.Visible = false
    end
end)

-- Menu GUI Creation
local function createMenu()
    menuGui = Instance.new("ScreenGui")
    menuGui.Name = "ExploitMenu"
    menuGui.Parent = coreGui -- Changed to CoreGui for exploit visibility/persistence
    menuGui.ResetOnSpawn = false
    menuGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- Ensure it layers properly
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Parent = menuGui
    mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    mainFrame.BorderSizePixel = 0
    mainFrame.Position = UDim2.new(0, 10, 0, 10)
    mainFrame.Size = UDim2.new(0, 900, 0, 440)
    mainFrame.Active = true
    mainFrame.Draggable = true
    
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 8)
    mainCorner.Parent = mainFrame
    
    -- Rage Group
    local rageFrame = Instance.new("Frame")
    rageFrame.Name = "RageFrame"
    rageFrame.Parent = mainFrame
    rageFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    rageFrame.BorderSizePixel = 0
    rageFrame.Position = UDim2.new(0, 10, 0, 10)
    rageFrame.Size = UDim2.new(0, 280, 0, 420)
    
    local rageCorner = Instance.new("UICorner")
    rageCorner.CornerRadius = UDim.new(0, 6)
    rageCorner.Parent = rageFrame
    
    local rageTitle = Instance.new("TextLabel")
    rageTitle.Name = "RageTitle"
    rageTitle.Parent = rageFrame
    rageTitle.BackgroundTransparency = 1
    rageTitle.Position = UDim2.new(0, 0, 0, 0)
    rageTitle.Size = UDim2.new(1, 0, 0, 40)
    rageTitle.Font = Enum.Font.FredokaOne
    rageTitle.Text = "Rage"
    rageTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    rageTitle.TextSize = 24
    
    -- Aimbot Toggle in Rage
    local aimLabel = Instance.new("TextLabel")
    aimLabel.Name = "AimLabel"
    aimLabel.Parent = rageFrame
    aimLabel.BackgroundTransparency = 1
    aimLabel.Position = UDim2.new(0, 10, 0, 45)
    aimLabel.Size = UDim2.new(0.7, 0, 0, 25)
    aimLabel.Font = Enum.Font.FredokaOne
    aimLabel.Text = "Aimbot"
    aimLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    aimLabel.TextSize = 16
    aimLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local aimButton = Instance.new("TextButton")
    aimButton.Name = "AimButton"
    aimButton.Parent = rageFrame
    aimButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    aimButton.BorderSizePixel = 0
    aimButton.Position = UDim2.new(0.75, 0, 0, 45)
    aimButton.Size = UDim2.new(0.25, 0, 0, 25)
    aimButton.Font = Enum.Font.FredokaOne
    aimButton.Text = ""
    aimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    aimButton.TextSize = 14
    
    local aimCorner = Instance.new("UICorner")
    aimCorner.CornerRadius = UDim.new(0, 4)
    aimCorner.Parent = aimButton
    
    aimButton.MouseButton1Click:Connect(function()
        aimbotEnabled = not aimbotEnabled
        aimButton.BackgroundColor3 = aimbotEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        if not aimbotEnabled then
            isAiming = false
            currentTarget = nil
        end
    end)
    
    -- Always Aim Toggle in Rage
    local alwaysAimLabel = Instance.new("TextLabel")
    alwaysAimLabel.Name = "AlwaysAimLabel"
    alwaysAimLabel.Parent = rageFrame
    alwaysAimLabel.BackgroundTransparency = 1
    alwaysAimLabel.Position = UDim2.new(0, 10, 0, 75)
    alwaysAimLabel.Size = UDim2.new(0.7, 0, 0, 25)
    alwaysAimLabel.Font = Enum.Font.FredokaOne
    alwaysAimLabel.Text = "Always Aim"
    alwaysAimLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    alwaysAimLabel.TextSize = 16
    alwaysAimLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local alwaysAimButton = Instance.new("TextButton")
    alwaysAimButton.Name = "AlwaysAimButton"
    alwaysAimButton.Parent = rageFrame
    alwaysAimButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    alwaysAimButton.BorderSizePixel = 0
    alwaysAimButton.Position = UDim2.new(0.75, 0, 0, 75)
    alwaysAimButton.Size = UDim2.new(0.25, 0, 0, 25)
    alwaysAimButton.Font = Enum.Font.FredokaOne
    alwaysAimButton.Text = ""
    alwaysAimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    alwaysAimButton.TextSize = 14
    
    local alwaysAimCorner = Instance.new("UICorner")
    alwaysAimCorner.CornerRadius = UDim.new(0, 4)
    alwaysAimCorner.Parent = alwaysAimButton
    
    alwaysAimButton.MouseButton1Click:Connect(function()
        alwaysAimEnabled = not alwaysAimEnabled
        alwaysAimButton.BackgroundColor3 = alwaysAimEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
    end)
    
    -- Triggerbot Toggle in Rage
    local triggerLabel = Instance.new("TextLabel")
    triggerLabel.Name = "TriggerLabel"
    triggerLabel.Parent = rageFrame
    triggerLabel.BackgroundTransparency = 1
    triggerLabel.Position = UDim2.new(0, 10, 0, 105)
    triggerLabel.Size = UDim2.new(0.7, 0, 0, 25)
    triggerLabel.Font = Enum.Font.FredokaOne
    triggerLabel.Text = "Triggerbot (E to toggle)"
    triggerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    triggerLabel.TextSize = 16
    triggerLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local triggerButton = Instance.new("TextButton")
    triggerButton.Name = "TriggerButton"
    triggerButton.Parent = rageFrame
    triggerButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    triggerButton.BorderSizePixel = 0
    triggerButton.Position = UDim2.new(0.75, 0, 0, 105)
    triggerButton.Size = UDim2.new(0.25, 0, 0, 25)
    triggerButton.Font = Enum.Font.FredokaOne
    triggerButton.Text = ""
    triggerButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    triggerButton.TextSize = 14
    
    local triggerCorner = Instance.new("UICorner")
    triggerCorner.CornerRadius = UDim.new(0, 4)
    triggerCorner.Parent = triggerButton
    
    triggerButton.MouseButton1Click:Connect(function()
        triggerbotEnabled = not triggerbotEnabled
        triggerButton.BackgroundColor3 = triggerbotEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        if not triggerbotEnabled then
            triggerbotActive = false
        end
    end)
    
    -- NEW: Silent Aim Toggle in Rage
    local silentAimLabel = Instance.new("TextLabel")
    silentAimLabel.Name = "SilentAimLabel"
    silentAimLabel.Parent = rageFrame
    silentAimLabel.BackgroundTransparency = 1
    silentAimLabel.Position = UDim2.new(0, 10, 0, 135)
    silentAimLabel.Size = UDim2.new(0.7, 0, 0, 25)
    silentAimLabel.Font = Enum.Font.FredokaOne
    silentAimLabel.Text = "Silent Aim"
    silentAimLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    silentAimLabel.TextSize = 16
    silentAimLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local silentAimButton = Instance.new("TextButton")
    silentAimButton.Name = "SilentAimButton"
    silentAimButton.Parent = rageFrame
    silentAimButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    silentAimButton.BorderSizePixel = 0
    silentAimButton.Position = UDim2.new(0.75, 0, 0, 135)
    silentAimButton.Size = UDim2.new(0.25, 0, 0, 25)
    silentAimButton.Font = Enum.Font.FredokaOne
    silentAimButton.Text = ""
    silentAimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    silentAimButton.TextSize = 14
    
    local silentAimCorner = Instance.new("UICorner")
    silentAimCorner.CornerRadius = UDim.new(0, 4)
    silentAimCorner.Parent = silentAimButton
    
    silentAimButton.MouseButton1Click:Connect(function()
        silentAimEnabled = not silentAimEnabled
        silentAimButton.BackgroundColor3 = silentAimEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        print("Silent Aim " .. (silentAimEnabled and "enabled" or "disabled"))
        if silentAimEnabled and getrawmetatable and newcclosure then
            setupSilentAim() -- Re-setup hook if toggled on
        end
    end)
    
    -- Team Check Toggle in Rage
    local teamLabel = Instance.new("TextLabel")
    teamLabel.Name = "TeamLabel"
    teamLabel.Parent = rageFrame
    teamLabel.BackgroundTransparency = 1
    teamLabel.Position = UDim2.new(0, 10, 0, 165)
    teamLabel.Size = UDim2.new(0.7, 0, 0, 25)
    teamLabel.Font = Enum.Font.FredokaOne
    teamLabel.Text = "Team Check"
    teamLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamLabel.TextSize = 16
    teamLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local teamButton = Instance.new("TextButton")
    teamButton.Name = "TeamButton"
    teamButton.Parent = rageFrame
    teamButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    teamButton.BorderSizePixel = 0
    teamButton.Position = UDim2.new(0.75, 0, 0, 165)
    teamButton.Size = UDim2.new(0.25, 0, 0, 25)
    teamButton.Font = Enum.Font.FredokaOne
    teamButton.Text = ""
    teamButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamButton.TextSize = 14
    
    local teamCorner = Instance.new("UICorner")
    teamCorner.CornerRadius = UDim.new(0, 4)
    teamCorner.Parent = teamButton
    
    teamButton.MouseButton1Click:Connect(function()
        teamCheckEnabled = not teamCheckEnabled
        teamButton.BackgroundColor3 = teamCheckEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
    end)
    
    -- FOV Adjustment in Rage
    local fovLabel = Instance.new("TextLabel")
    fovLabel.Name = "FOVLabel"
    fovLabel.Parent = rageFrame
    fovLabel.BackgroundTransparency = 1
    fovLabel.Position = UDim2.new(0, 10, 0, 195)
    fovLabel.Size = UDim2.new(0.7, 0, 0, 25)
    fovLabel.Font = Enum.Font.FredokaOne
    fovLabel.Text = "FOV"
    fovLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    fovLabel.TextSize = 16
    fovLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local fovTextBox = Instance.new("TextBox")
    fovTextBox.Name = "FOVTextBox"
    fovTextBox.Parent = rageFrame
    fovTextBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    fovTextBox.BorderSizePixel = 0
    fovTextBox.Position = UDim2.new(0.75, 0, 0, 195)
    fovTextBox.Size = UDim2.new(0.25, 0, 0, 25)
    fovTextBox.Font = Enum.Font.FredokaOne
    fovTextBox.Text = "150"
    fovTextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    fovTextBox.TextSize = 14
    
    local fovCorner = Instance.new("UICorner")
    fovCorner.CornerRadius = UDim.new(0, 4)
    fovCorner.Parent = fovTextBox
    
    fovTextBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local newFov = tonumber(fovTextBox.Text)
            if newFov and newFov > 0 then
                fovValue = newFov
                print("FOV updated to: " .. fovValue) -- Debug print
            else
                fovTextBox.Text = tostring(fovValue)
            end
        end
    end)
    
    -- FOV Circle Toggle in Rage
    local circleLabel = Instance.new("TextLabel")
    circleLabel.Name = "CircleLabel"
    circleLabel.Parent = rageFrame
    circleLabel.BackgroundTransparency = 1
    circleLabel.Position = UDim2.new(0, 10, 0, 225)
    circleLabel.Size = UDim2.new(0.7, 0, 0, 25)
    circleLabel.Font = Enum.Font.FredokaOne
    circleLabel.Text = "FOV Circle"
    circleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    circleLabel.TextSize = 16
    circleLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local circleButton = Instance.new("TextButton")
    circleButton.Name = "CircleButton"
    circleButton.Parent = rageFrame
    circleButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    circleButton.BorderSizePixel = 0
    circleButton.Position = UDim2.new(0.75, 0, 0, 225)
    circleButton.Size = UDim2.new(0.25, 0, 0, 25)
    circleButton.Font = Enum.Font.FredokaOne
    circleButton.Text = ""
    circleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    circleButton.TextSize = 14
    
    local circleCorner = Instance.new("UICorner")
    circleCorner.CornerRadius = UDim.new(0, 4)
    circleCorner.Parent = circleButton
    
    circleButton.MouseButton1Click:Connect(function()
        fovCircleVisible = not fovCircleVisible
        circleButton.BackgroundColor3 = fovCircleVisible and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
    end)
    
    -- Visuals Group
    local visualsFrame = Instance.new("Frame")
    visualsFrame.Name = "VisualsFrame"
    visualsFrame.Parent = mainFrame
    visualsFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    visualsFrame.BorderSizePixel = 0
    visualsFrame.Position = UDim2.new(0, 300, 0, 10)
    visualsFrame.Size = UDim2.new(0, 280, 0, 420)
    
    local visualsCorner = Instance.new("UICorner")
    visualsCorner.CornerRadius = UDim.new(0, 6)
    visualsCorner.Parent = visualsFrame
    
    local visualsTitle = Instance.new("TextLabel")
    visualsTitle.Name = "VisualsTitle"
    visualsTitle.Parent = visualsFrame
    visualsTitle.BackgroundTransparency = 1
    visualsTitle.Position = UDim2.new(0, 0, 0, 0)
    visualsTitle.Size = UDim2.new(1, 0, 0, 40)
    visualsTitle.Font = Enum.Font.FredokaOne
    visualsTitle.Text = "Visuals"
    visualsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    visualsTitle.TextSize = 24
    
    -- ESP Toggle in Visuals
    local espLabel = Instance.new("TextLabel")
    espLabel.Name = "ESPLabel"
    espLabel.Parent = visualsFrame
    espLabel.BackgroundTransparency = 1
    espLabel.Position = UDim2.new(0, 10, 0, 45)
    espLabel.Size = UDim2.new(0.7, 0, 0, 25)
    espLabel.Font = Enum.Font.FredokaOne
    espLabel.Text = "ESP"
    espLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    espLabel.TextSize = 16
    espLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local espButton = Instance.new("TextButton")
    espButton.Name = "ESPButton"
    espButton.Parent = visualsFrame
    espButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    espButton.BorderSizePixel = 0
    espButton.Position = UDim2.new(0.75, 0, 0, 45)
    espButton.Size = UDim2.new(0.25, 0, 0, 25)
    espButton.Font = Enum.Font.FredokaOne
    espButton.Text = ""
    espButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    espButton.TextSize = 14
    
    local espCorner = Instance.new("UICorner")
    espCorner.CornerRadius = UDim.new(0, 4)
    espCorner.Parent = espButton
    
    espButton.MouseButton1Click:Connect(function()
        espEnabled = not espEnabled
        espButton.BackgroundColor3 = espEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        updateAllHighlights()
    end)
    
    -- Team ESP Toggle in Visuals
    local teamEspLabel = Instance.new("TextLabel")
    teamEspLabel.Name = "TeamEspLabel"
    teamEspLabel.Parent = visualsFrame
    teamEspLabel.BackgroundTransparency = 1
    teamEspLabel.Position = UDim2.new(0, 10, 0, 75)
    teamEspLabel.Size = UDim2.new(0.7, 0, 0, 25)
    teamEspLabel.Font = Enum.Font.FredokaOne
    teamEspLabel.Text = "Team ESP"
    teamEspLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamEspLabel.TextSize = 16
    teamEspLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local teamEspButton = Instance.new("TextButton")
    teamEspButton.Name = "TeamEspButton"
    teamEspButton.Parent = visualsFrame
    teamEspButton.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    teamEspButton.BorderSizePixel = 0
    teamEspButton.Position = UDim2.new(0.75, 0, 0, 75)
    teamEspButton.Size = UDim2.new(0.25, 0, 0, 25)
    teamEspButton.Font = Enum.Font.FredokaOne
    teamEspButton.Text = ""
    teamEspButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamEspButton.TextSize = 14
    
    local teamEspCorner = Instance.new("UICorner")
    teamEspCorner.CornerRadius = UDim.new(0, 4)
    teamEspCorner.Parent = teamEspButton
    
    teamEspButton.MouseButton1Click:Connect(function()
        teamEspEnabled = not teamEspEnabled
        teamEspButton.BackgroundColor3 = teamEspEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        updateAllHighlights()
    end)
    
    -- ESP Team Visible Color in Visuals
    local teamVisLabel = Instance.new("TextLabel")
    teamVisLabel.Name = "TeamVisLabel"
    teamVisLabel.Parent = visualsFrame
    teamVisLabel.BackgroundTransparency = 1
    teamVisLabel.Position = UDim2.new(0, 10, 0, 105)
    teamVisLabel.Size = UDim2.new(0, 100, 0, 25)
    teamVisLabel.Font = Enum.Font.FredokaOne
    teamVisLabel.Text = "Team Vis RGB"
    teamVisLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamVisLabel.TextSize = 14
    teamVisLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local teamVisR = Instance.new("TextBox")
    teamVisR.Name = "TeamVisR"
    teamVisR.Parent = visualsFrame
    teamVisR.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    teamVisR.BorderSizePixel = 0
    teamVisR.Position = UDim2.new(0, 120, 0, 105)
    teamVisR.Size = UDim2.new(0, 30, 0, 25)
    teamVisR.Font = Enum.Font.FredokaOne
    teamVisR.Text = "0"
    teamVisR.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamVisR.TextSize = 14
    
    local teamVisRCorner = Instance.new("UICorner")
    teamVisRCorner.CornerRadius = UDim.new(0, 4)
    teamVisRCorner.Parent = teamVisR
    
    local teamVisG = Instance.new("TextBox")
    teamVisG.Name = "TeamVisG"
    teamVisG.Parent = visualsFrame
    teamVisG.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    teamVisG.BorderSizePixel = 0
    teamVisG.Position = UDim2.new(0, 155, 0, 105)
    teamVisG.Size = UDim2.new(0, 30, 0, 25)
    teamVisG.Font = Enum.Font.FredokaOne
    teamVisG.Text = "255"
    teamVisG.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamVisG.TextSize = 14
    
    local teamVisGCorner = Instance.new("UICorner")
    teamVisGCorner.CornerRadius = UDim.new(0, 4)
    teamVisGCorner.Parent = teamVisG
    
    local teamVisB = Instance.new("TextBox")
    teamVisB.Name = "TeamVisB"
    teamVisB.Parent = visualsFrame
    teamVisB.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    teamVisB.BorderSizePixel = 0
    teamVisB.Position = UDim2.new(0, 190, 0, 105)
    teamVisB.Size = UDim2.new(0, 30, 0, 25)
    teamVisB.Font = Enum.Font.FredokaOne
    teamVisB.Text = "0"
    teamVisB.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamVisB.TextSize = 14
    
    local teamVisBCorner = Instance.new("UICorner")
    teamVisBCorner.CornerRadius = UDim.new(0, 4)
    teamVisBCorner.Parent = teamVisB
    
    local function updateTeamVisColor()
        local r = math.clamp(tonumber(teamVisR.Text) or 0, 0, 255)
        local g = math.clamp(tonumber(teamVisG.Text) or 0, 0, 255)
        local b = math.clamp(tonumber(teamVisB.Text) or 0, 0, 255)
        espTeamVisibleColor = Color3.fromRGB(r, g, b)
        teamVisR.Text = tostring(r)
        teamVisG.Text = tostring(g)
        teamVisB.Text = tostring(b)
        updateAllHighlights()
    end
    
    teamVisR.FocusLost:Connect(updateTeamVisColor)
    teamVisG.FocusLost:Connect(updateTeamVisColor)
    teamVisB.FocusLost:Connect(updateTeamVisColor)
    
    -- ESP Team Wall Color in Visuals
    local teamWallLabel = Instance.new("TextLabel")
    teamWallLabel.Name = "TeamWallLabel"
    teamWallLabel.Parent = visualsFrame
    teamWallLabel.BackgroundTransparency = 1
    teamWallLabel.Position = UDim2.new(0, 10, 0, 135)
    teamWallLabel.Size = UDim2.new(0, 100, 0, 25)
    teamWallLabel.Font = Enum.Font.FredokaOne
    teamWallLabel.Text = "Team Wall RGB"
    teamWallLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamWallLabel.TextSize = 14
    teamWallLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local teamWallR = Instance.new("TextBox")
    teamWallR.Name = "TeamWallR"
    teamWallR.Parent = visualsFrame
    teamWallR.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    teamWallR.BorderSizePixel = 0
    teamWallR.Position = UDim2.new(0, 120, 0, 135)
    teamWallR.Size = UDim2.new(0, 30, 0, 25)
    teamWallR.Font = Enum.Font.FredokaOne
    teamWallR.Text = "255"
    teamWallR.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamWallR.TextSize = 14
    
    local teamWallRCorner = Instance.new("UICorner")
    teamWallRCorner.CornerRadius = UDim.new(0, 4)
    teamWallRCorner.Parent = teamWallR
    
    local teamWallG = Instance.new("TextBox")
    teamWallG.Name = "TeamWallG"
    teamWallG.Parent = visualsFrame
    teamWallG.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    teamWallG.BorderSizePixel = 0
    teamWallG.Position = UDim2.new(0, 155, 0, 135)
    teamWallG.Size = UDim2.new(0, 30, 0, 25)
    teamWallG.Font = Enum.Font.FredokaOne
    teamWallG.Text = "0"
    teamWallG.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamWallG.TextSize = 14
    
    local teamWallGCorner = Instance.new("UICorner")
    teamWallGCorner.CornerRadius = UDim.new(0, 4)
    teamWallGCorner.Parent = teamWallG
    
    local teamWallB = Instance.new("TextBox")
    teamWallB.Name = "TeamWallB"
    teamWallB.Parent = visualsFrame
    teamWallB.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    teamWallB.BorderSizePixel = 0
    teamWallB.Position = UDim2.new(0, 190, 0, 135)
    teamWallB.Size = UDim2.new(0, 30, 0, 25)
    teamWallB.Font = Enum.Font.FredokaOne
    teamWallB.Text = "255"
    teamWallB.TextColor3 = Color3.fromRGB(255, 255, 255)
    teamWallB.TextSize = 14
    
    local teamWallBCorner = Instance.new("UICorner")
    teamWallBCorner.CornerRadius = UDim.new(0, 4)
    teamWallBCorner.Parent = teamWallB
    
    local function updateTeamWallColor()
        local r = math.clamp(tonumber(teamWallR.Text) or 0, 0, 255)
        local g = math.clamp(tonumber(teamWallG.Text) or 0, 0, 255)
        local b = math.clamp(tonumber(teamWallB.Text) or 0, 0, 255)
        espTeamWallColor = Color3.fromRGB(r, g, b)
        teamWallR.Text = tostring(r)
        teamWallG.Text = tostring(g)
        teamWallB.Text = tostring(b)
        updateAllHighlights()
    end
    
    teamWallR.FocusLost:Connect(updateTeamWallColor)
    teamWallG.FocusLost:Connect(updateTeamWallColor)
    teamWallB.FocusLost:Connect(updateTeamWallColor)
    
    -- ESP Enemy Visible Color in Visuals
    local enemyVisLabel = Instance.new("TextLabel")
    enemyVisLabel.Name = "EnemyVisLabel"
    enemyVisLabel.Parent = visualsFrame
    enemyVisLabel.BackgroundTransparency = 1
    enemyVisLabel.Position = UDim2.new(0, 10, 0, 165)
    enemyVisLabel.Size = UDim2.new(0, 100, 0, 25)
    enemyVisLabel.Font = Enum.Font.FredokaOne
    enemyVisLabel.Text = "Enemy Vis RGB"
    enemyVisLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    enemyVisLabel.TextSize = 14
    enemyVisLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local enemyVisR = Instance.new("TextBox")
    enemyVisR.Name = "EnemyVisR"
    enemyVisR.Parent = visualsFrame
    enemyVisR.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    enemyVisR.BorderSizePixel = 0
    enemyVisR.Position = UDim2.new(0, 120, 0, 165)
    enemyVisR.Size = UDim2.new(0, 30, 0, 25)
    enemyVisR.Font = Enum.Font.FredokaOne
    enemyVisR.Text = "255"
    enemyVisR.TextColor3 = Color3.fromRGB(255, 255, 255)
    enemyVisR.TextSize = 14
    
    local enemyVisRCorner = Instance.new("UICorner")
    enemyVisRCorner.CornerRadius = UDim.new(0, 4)
    enemyVisRCorner.Parent = enemyVisR
    
    local enemyVisG = Instance.new("TextBox")
    enemyVisG.Name = "EnemyVisG"
    enemyVisG.Parent = visualsFrame
    enemyVisG.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    enemyVisG.BorderSizePixel = 0
    enemyVisG.Position = UDim2.new(0, 155, 0, 165)
    enemyVisG.Size = UDim2.new(0, 30, 0, 25)
    enemyVisG.Font = Enum.Font.FredokaOne
    enemyVisG.Text = "0"
    enemyVisG.TextColor3 = Color3.fromRGB(255, 255, 255)
    enemyVisG.TextSize = 14
    
    local enemyVisGCorner = Instance.new("UICorner")
    enemyVisGCorner.CornerRadius = UDim.new(0, 4)
    enemyVisGCorner.Parent = enemyVisG
    
    local enemyVisB = Instance.new("TextBox")
    enemyVisB.Name = "EnemyVisB"
    enemyVisB.Parent = visualsFrame
    enemyVisB.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    enemyVisB.BorderSizePixel = 0
    enemyVisB.Position = UDim2.new(0, 190, 0, 165)
    enemyVisB.Size = UDim2.new(0, 30, 0, 25)
    enemyVisB.Font = Enum.Font.FredokaOne
    enemyVisB.Text = "0"
    enemyVisB.TextColor3 = Color3.fromRGB(255, 255, 255)
    enemyVisB.TextSize = 14
    
    local enemyVisBCorner = Instance.new("UICorner")
    enemyVisBCorner.CornerRadius = UDim.new(0, 4)
    enemyVisBCorner.Parent = enemyVisB
    
    local function updateEnemyVisColor()
        local r = math.clamp(tonumber(enemyVisR.Text) or 0, 0, 255)
        local g = math.clamp(tonumber(enemyVisG.Text) or 0, 0, 255)
        local b = math.clamp(tonumber(enemyVisB.Text) or 0, 0, 255)
        espEnemyVisibleColor = Color3.fromRGB(r, g, b)
        enemyVisR.Text = tostring(r)
        enemyVisG.Text = tostring(g)
        enemyVisB.Text = tostring(b)
        updateAllHighlights()
    end
    
    enemyVisR.FocusLost:Connect(updateEnemyVisColor)
    enemyVisG.FocusLost:Connect(updateEnemyVisColor)
    enemyVisB.FocusLost:Connect(updateEnemyVisColor)
    
    -- ESP Enemy Wall Color in Visuals
    local enemyWallLabel = Instance.new("TextLabel")
    enemyWallLabel.Name = "EnemyWallLabel"
    enemyWallLabel.Parent = visualsFrame
    enemyWallLabel.BackgroundTransparency = 1
    enemyWallLabel.Position = UDim2.new(0, 10, 0, 195)
    enemyWallLabel.Size = UDim2.new(0, 100, 0, 25)
    enemyWallLabel.Font = Enum.Font.FredokaOne
    enemyWallLabel.Text = "Enemy Wall RGB"
    enemyWallLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    enemyWallLabel.TextSize = 14
    enemyWallLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local enemyWallR = Instance.new("TextBox")
    enemyWallR.Name = "EnemyWallR"
    enemyWallR.Parent = visualsFrame
    enemyWallR.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    enemyWallR.BorderSizePixel = 0
    enemyWallR.Position = UDim2.new(0, 120, 0, 195)
    enemyWallR.Size = UDim2.new(0, 30, 0, 25)
    enemyWallR.Font = Enum.Font.FredokaOne
    enemyWallR.Text = "0"
    enemyWallR.TextColor3 = Color3.fromRGB(255, 255, 255)
    enemyWallR.TextSize = 14
    
    local enemyWallRCorner = Instance.new("UICorner")
    enemyWallRCorner.CornerRadius = UDim.new(0, 4)
    enemyWallRCorner.Parent = enemyWallR
    
    local enemyWallG = Instance.new("TextBox")
    enemyWallG.Name = "EnemyWallG"
    enemyWallG.Parent = visualsFrame
    enemyWallG.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    enemyWallG.BorderSizePixel = 0
    enemyWallG.Position = UDim2.new(0, 155, 0, 195)
    enemyWallG.Size = UDim2.new(0, 30, 0, 25)
    enemyWallG.Font = Enum.Font.FredokaOne
    enemyWallG.Text = "0"
    enemyWallG.TextColor3 = Color3.fromRGB(255, 255, 255)
    enemyWallG.TextSize = 14
    
    local enemyWallGCorner = Instance.new("UICorner")
    enemyWallGCorner.CornerRadius = UDim.new(0, 4)
    enemyWallGCorner.Parent = enemyWallG
    
    local enemyWallB = Instance.new("TextBox")
    enemyWallB.Name = "EnemyWallB"
    enemyWallB.Parent = visualsFrame
    enemyWallB.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    enemyWallB.BorderSizePixel = 0
    enemyWallB.Position = UDim2.new(0, 190, 0, 195)
    enemyWallB.Size = UDim2.new(0, 30, 0, 25)
    enemyWallB.Font = Enum.Font.FredokaOne
    enemyWallB.Text = "255"
    enemyWallB.TextColor3 = Color3.fromRGB(255, 255, 255)
    enemyWallB.TextSize = 14
    
    local enemyWallBCorner = Instance.new("UICorner")
    enemyWallBCorner.CornerRadius = UDim.new(0, 4)
    enemyWallBCorner.Parent = enemyWallB
    
    local function updateEnemyWallColor()
        local r = math.clamp(tonumber(enemyWallR.Text) or 0, 0, 255)
        local g = math.clamp(tonumber(enemyWallG.Text) or 0, 0, 255)
        local b = math.clamp(tonumber(enemyWallB.Text) or 0, 0, 255)
        espEnemyWallColor = Color3.fromRGB(r, g, b)
        enemyWallR.Text = tostring(r)
        enemyWallG.Text = tostring(g)
        enemyWallB.Text = tostring(b)
        updateAllHighlights()
    end
    
    enemyWallR.FocusLost:Connect(updateEnemyWallColor)
    enemyWallG.FocusLost:Connect(updateEnemyWallColor)
    enemyWallB.FocusLost:Connect(updateEnemyWallColor)
    
    -- Misc Group
    local miscFrame = Instance.new("Frame")
    miscFrame.Name = "MiscFrame"
    miscFrame.Parent = mainFrame
    miscFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    miscFrame.BorderSizePixel = 0
    miscFrame.Position = UDim2.new(0, 590, 0, 10)
    miscFrame.Size = UDim2.new(0, 280, 0, 420)
    
    local miscCorner = Instance.new("UICorner")
    miscCorner.CornerRadius = UDim.new(0, 6)
    miscCorner.Parent = miscFrame
    
    local miscTitle = Instance.new("TextLabel")
    miscTitle.Name = "MiscTitle"
    miscTitle.Parent = miscFrame
    miscTitle.BackgroundTransparency = 1
    miscTitle.Position = UDim2.new(0, 0, 0, 0)
    miscTitle.Size = UDim2.new(1, 0, 0, 40)
    miscTitle.Font = Enum.Font.FredokaOne
    miscTitle.Text = "Misc"
    miscTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    miscTitle.TextSize = 24
    
    -- Viewmodel FOV Label in Misc
    local vmFovLabel = Instance.new("TextLabel")
    vmFovLabel.Name = "VMFOVLabel"
    vmFovLabel.Parent = miscFrame
    vmFovLabel.BackgroundTransparency = 1
    vmFovLabel.Position = UDim2.new(0, 10, 0, 45)
    vmFovLabel.Size = UDim2.new(0.7, 0, 0, 25)
    vmFovLabel.Font = Enum.Font.FredokaOne
    vmFovLabel.Text = "Viewmodel FOV"
    vmFovLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    vmFovLabel.TextSize = 16
    vmFovLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    -- Viewmodel FOV TextBox in Misc (always active)
    local vmFovTextBox = Instance.new("TextBox")
    vmFovTextBox.Name = "VMFOVTextBox"
    vmFovTextBox.Parent = miscFrame
    vmFovTextBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    vmFovTextBox.BorderSizePixel = 0
    vmFovTextBox.Position = UDim2.new(0.75, 0, 0, 45)
    vmFovTextBox.Size = UDim2.new(0.25, 0, 0, 25)
    vmFovTextBox.Font = Enum.Font.FredokaOne
    vmFovTextBox.Text = tostring(viewmodelFovValue)
    vmFovTextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    vmFovTextBox.TextSize = 14
    
    local vmFovCorner = Instance.new("UICorner")
    vmFovCorner.CornerRadius = UDim.new(0, 4)
    vmFovCorner.Parent = vmFovTextBox
    
    vmFovTextBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local newFov = tonumber(vmFovTextBox.Text)
            if newFov and newFov > 0 and newFov <= 120 then -- Clamp to reasonable FOV values
                viewmodelFovValue = newFov
                vmFovTextBox.Text = tostring(viewmodelFovValue)
                print("Viewmodel FOV updated to: " .. viewmodelFovValue) -- Debug print
            else
                vmFovTextBox.Text = tostring(viewmodelFovValue)
            end
        end
    end)
    
    -- Bunnyhop Toggle in Misc
    local bunnyhopLabel = Instance.new("TextLabel")
    bunnyhopLabel.Name = "BunnyhopLabel"
    bunnyhopLabel.Parent = miscFrame
    bunnyhopLabel.BackgroundTransparency = 1
    bunnyhopLabel.Position = UDim2.new(0, 10, 0, 75)
    bunnyhopLabel.Size = UDim2.new(0.7, 0, 0, 25)
    bunnyhopLabel.Font = Enum.Font.FredokaOne
    bunnyhopLabel.Text = "Bunnyhop (Hold Space)"
    bunnyhopLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    bunnyhopLabel.TextSize = 16
    bunnyhopLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local bunnyhopButton = Instance.new("TextButton")
    bunnyhopButton.Name = "BunnyhopButton"
    bunnyhopButton.Parent = miscFrame
    bunnyhopButton.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    bunnyhopButton.BorderSizePixel = 0
    bunnyhopButton.Position = UDim2.new(0.75, 0, 0, 75)
    bunnyhopButton.Size = UDim2.new(0.25, 0, 0, 25)
    bunnyhopButton.Font = Enum.Font.FredokaOne
    bunnyhopButton.Text = ""
    bunnyhopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    bunnyhopButton.TextSize = 14
    
    local bunnyhopCorner = Instance.new("UICorner")
    bunnyhopCorner.CornerRadius = UDim.new(0, 4)
    bunnyhopCorner.Parent = bunnyhopButton
    
    bunnyhopButton.MouseButton1Click:Connect(function()
        bunnyhopEnabled = not bunnyhopEnabled
        bunnyhopButton.BackgroundColor3 = bunnyhopEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        print("Bunnyhop " .. (bunnyhopEnabled and "enabled" or "disabled"))
    end)
    
    -- Initial visibility
    menuGui.Enabled = false
end

-- Create menu immediately (for debugging - ensures it's built even if key doesn't fire)
createMenu()

-- Toggle Menu on Insert Key
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        menuVisible = not menuVisible
        menuGui.Enabled = menuVisible
        print("Menu toggled:", menuVisible) -- Debug print to console
    end
end)