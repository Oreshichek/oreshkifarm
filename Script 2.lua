local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local PathfindingService = game:GetService("PathfindingService")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer
local Environment = getgenv()

local PreviousHub = Environment.SkibidiDefenseHub
if PreviousHub and type(PreviousHub.Destroy) == "function" then
    pcall(PreviousHub.Destroy)
end

local Hub = {}
Environment.SkibidiDefenseHub = Hub

local State = {
    Running = true, Recording = false, Playing = false, PlaybackEnabled = false,
    AutoPlaybackStarted = false, PlaybackFirstActionArmed = false, PlaybackFirstActionDone = false,
    AutoReady = false, AutoSkip = false, AutoReplay = false, AutoSpeed = false,
    SpeedScaleDelay = 1, MovingAround = false, AutoJoinMap = false,
    LobbyMode = "Story", LobbyChapter = "Chapter 1", LobbyModifiers = {},
    AutoBackLobby = false, MatchesBeforeLobby = 3, MatchesCompleted = 0,
    LastCountedJobId = "", PendingLobbyReturn = false, JoinRequested = false,
    WebhookEnabled = false, WebhookURL = "", WebhookMatchEnd = true,
    Speed = 1, PlaybackMode = "Hybrid", ProfileName = "", ProfileVersion = 4,
    Actions = {}, RecordStartedAt = 0, NextHandle = 1,
    Connections = {}, RecorderConnections = {},
    TowerMeta = setmetatable({}, { __mode = "k" }),
    RuntimeHandles = {}, UsedRuntimeTowers = setmetatable({}, { __mode = "k" }),
    PendingAbilityClickAt = -math.huge, PendingAbilityIndex = 1,
    PlayerRecording = false, PlayerRecordingStartedAt = 0,
    PlayerActions = {}, PlayerRecordingProfileName = "", PlayerRecordingConnections = {},
    Chapter9Mode = false, Chapter9SpeedSet = false,
}

local MacroFolder = "SkibidiDefense_Macros"
local ConfigFile = MacroFolder .. "/HubConfig.json"
local LegacyMacroFolder = "Kero" .. "TTD_Macros"
local HasFilesystem = type(isfolder) == "function" and type(makefolder) == "function"
    and type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"

if HasFilesystem and not isfolder(MacroFolder) then makefolder(MacroFolder) end

if HasFilesystem and type(listfiles) == "function" and isfolder(LegacyMacroFolder) then
    for _, oldPath in ipairs(listfiles(LegacyMacroFolder)) do
        local fileName = oldPath:match("([^\\/]+%.json)$")
        local newPath = fileName and (MacroFolder .. "/" .. fileName)
        if newPath and not isfile(newPath) then
            pcall(function() writefile(newPath, readfile(oldPath)) end)
        end
    end
end

local Remotes = {}
local LobbyPlaceId = 14279693118
local Scripted, TowerDataFolder, TowersFolder

local function RefreshGameObjects()
    local eventFolder = ReplicatedStorage:FindFirstChild("Event")
    local gameFolder = ReplicatedStorage:FindFirstChild("Game")
    local gameStartFolder = ReplicatedStorage:FindFirstChild("GAME_START")
    local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
    local speedFolder = gameFolder and gameFolder:FindFirstChild("Speed")

    Remotes.Place = eventFolder and eventFolder:FindFirstChild("placeTower")
    Remotes.Upgrade = eventFolder and eventFolder:FindFirstChild("UpgradeTower")
    Remotes.Sell = eventFolder and eventFolder:FindFirstChild("RemoveTower")
    Remotes.Target = eventFolder and eventFolder:FindFirstChild("ChangeTowerTargetMode")
    Remotes.BoostSelect = ReplicatedStorage:FindFirstChild("BoostSelect")
    local towerScript = ReplicatedStorage:FindFirstChild("TowerScript")
    Remotes.Ability = towerScript and towerScript:FindFirstChild("spawnTowerAbility")
    Remotes.Skip = eventFolder and eventFolder:FindFirstChild("waveSkip")
    Remotes.Replay = eventFolder and eventFolder:FindFirstChild("ReplayCore")
    Remotes.Ready = gameStartFolder and gameStartFolder:FindFirstChild("readyButton")
    Remotes.Speed = speedFolder and speedFolder:FindFirstChild("Change")
    Remotes.CreateServer = eventsFolder and eventsFolder:FindFirstChild("createServer")
    Remotes.StartServer = eventsFolder and eventsFolder:FindFirstChild("start")
    Remotes.ModifierState = ReplicatedStorage:FindFirstChild("ModifierState")

    Scripted = Workspace:FindFirstChild("Scripted")
    TowerDataFolder = Scripted and Scripted:FindFirstChild("TowerData")
    TowersFolder = Scripted and Scripted:FindFirstChild("Towers")
end

local function MatchObjectsReady()
    RefreshGameObjects()
    return TowerDataFolder ~= nil and TowersFolder ~= nil and Remotes.Place ~= nil
        and Remotes.Upgrade ~= nil and Remotes.Sell ~= nil and Remotes.Target ~= nil
end

RefreshGameObjects()

local function AddConnection(bucket, connection)
    table.insert(bucket or State.Connections, connection)
    return connection
end

local function DisconnectAll(bucket)
    for _, connection in ipairs(bucket) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(bucket)
end

local function WaitUntil(condition, timeout, interval)
    local deadline = os.clock() + (timeout or 5)
    interval = interval or 0.05
    repeat
        if not State.Running then return false end
        local success, result = pcall(condition)
        if success and result then return true, result end
        task.wait(interval)
    until os.clock() >= deadline
    return false
end

local function GetPlayerGui() return LocalPlayer:FindFirstChildOfClass("PlayerGui") end
local function GetGameEndedGui()
    local gui = GetPlayerGui()
    return gui and gui:FindFirstChild("GameEnded")
end
-- ============ ДЕТЕКТ КИКА ============
local kickDetected = false

local function DetectKickAndReact()
    if kickDetected then return end
    local gui = GetPlayerGui()
    if not gui then return end
    for _, obj in ipairs(gui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local text = string.lower(tostring(obj.Text or ""))
            if text:find("macro", 1, true)
                or text:find("kicked", 1, true)
                or text:find("suspected", 1, true)
                or text:find("disconnected", 1, true)
                or text:find("moderation", 1, true) then
                kickDetected = true
                warn("[KickDetect] Обнаружен текст о кике: " .. tostring(obj.Text))
                if Remotes.Replay then
                    pcall(function() Remotes.Replay:FireServer() end)
                    warn("[KickDetect] ReplayCore вызван")
                end
                pcall(function()
                    TeleportService:Teleport(LobbyPlaceId, LocalPlayer)
                end)
                warn("[KickDetect] Попытка телепорта в лобби")
                return
            end
        end
    end
end

task.spawn(function()
    while State.Running do
        if not kickDetected then
            pcall(DetectKickAndReact)
        end
        task.wait(0.1)
    end
end)
-- ============ КОНЕЦ ДЕТЕКТА КИКА ============
local function IsGameEnded()
    local gameEnded = GetGameEndedGui()
    return gameEnded and gameEnded.Enabled == true or false
end

local function TriggerBackLobbyButton()
    local gameEnded = GetGameEndedGui()
    if not gameEnded then return false, "GameEnded not found" end

    -- Ищем кнопку по тексту, а не по имени
    local backButton = nil
    for _, descendant in ipairs(gameEnded:GetDescendants()) do
        if descendant:IsA("GuiButton") or descendant:IsA("TextButton") then
            local text = string.upper(tostring(descendant.Text or ""))
            if text:find("RETURN TO LOBBY", 1, true)
                or text:find("RETURN", 1, true)
                or text:find("BACK TO LOBBY", 1, true)
                or text:find("LOBBY", 1, true) then
                backButton = descendant
                break
            end
        end
    end

    if not backButton then
        return false, "Return to Lobby button not found"
    end

    -- Способ 1: getconnections
    if type(getconnections) == "function" then
        local ok, connections = pcall(getconnections, backButton.MouseButton1Click)
        if ok and type(connections) == "table" then
            for _, connection in ipairs(connections) do
                local fired = pcall(function()
                    if type(connection.Fire) == "function" then
                        connection:Fire()
                    elseif type(connection.Function) == "function" then
                        connection.Function()
                    else
                        error("Connection cannot be invoked")
                    end
                end)
                if fired then return true end
            end
        end
    end

    -- Способ 2: firesignal
    if type(firesignal) == "function" then
        local ok, message = pcall(firesignal, backButton.MouseButton1Click)
        if ok then return true end
        return false, tostring(message)
    end

    -- Способ 3: Fire()
    local ok2 = pcall(function() backButton.MouseButton1Click:Fire() end)
    if ok2 then return true end

    -- Способ 4: VirtualInputManager
    local VIM = game:GetService("VirtualInputManager")
    if VIM and Workspace.CurrentCamera then
        local screenPoint, onScreen = Workspace.CurrentCamera:WorldToViewportPoint(
            backButton.AbsolutePosition + backButton.AbsoluteSize / 2)
        if onScreen then
            VIM:SendMouseButtonEvent(screenPoint.X, screenPoint.Y, 0, true, game, 1)
            task.wait(0.1)
            VIM:SendMouseButtonEvent(screenPoint.X, screenPoint.Y, 0, false, game, 1)
            return true
        end
    end

    return false, "Cannot invoke Return to Lobby button"
end

local function GetMoney()
    local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
    local money = leaderstats and leaderstats:FindFirstChild("Money")
    return money and tonumber(money.Value) or 0
end

local function GetWave()
    local gui = GetPlayerGui()
    local data = gui and gui:FindFirstChild("Data")
    local wave = data and data:FindFirstChild("Wave")
    local frame = wave and wave:FindFirstChild("Frame")
    local label = frame and frame:FindFirstChild("TextLabel")
    local text = label and label.Text or ""
    return tonumber(text:match("[Ww][Aa][Vv][Ee]%s*(%d+)")) or 0
end

local function GetUnitCountText()
    local gui = GetPlayerGui()
    local towers = gui and gui:FindFirstChild("Towers")
    local placement = towers and towers:FindFirstChild("Placement")
    local frame = placement and placement:FindFirstChild("Frame")
    local label = frame and frame:FindFirstChild("TextLabel")
    return label and label.Text or "Units: ?/?"
end

local MovingPointCount = 3
local MovingSession = 0

local function GetCharacterRoot()
    local character = LocalPlayer.Character
    if not character then return nil, nil end
    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then return nil, nil end
    return root, humanoid
end

local CachedMapBounds, CachedMapBoundsTime = nil, 0
local function GetMapBounds()
    if CachedMapBounds and (os.clock() - CachedMapBoundsTime) < 30 then
        return CachedMapBounds.center, CachedMapBounds.size, CachedMapBounds.map
    end
    local map = Workspace:FindFirstChild("Map")
    if not map then return nil, nil end
    if not map:IsA("Model") then return nil, nil end
    local ok, boundsCFrame, boundsSize = pcall(function() return map:GetBoundingBox() end)
    if not ok or boundsSize.X <= 0 or boundsSize.Z <= 0 then return nil, nil end
    CachedMapBounds = { center = boundsCFrame.Position, size = boundsSize, map = map }
    CachedMapBoundsTime = os.clock()
    return boundsCFrame.Position, boundsSize, map
end

local function GetGroundPoint(map, center, size, x, z)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = { map }
    raycastParams.IgnoreWater = true
    local originY = center.Y + (size.Y * 0.5) + 100
    local result = Workspace:Raycast(Vector3.new(x, originY, z), Vector3.new(0, -(size.Y + 300), 0), raycastParams)
    if not result or result.Normal.Y < 0.6 then return nil end
    return result.Position
end

local function StopCharacterMovement()
    local root, humanoid = GetCharacterRoot()
    if root and humanoid then
        humanoid.AutoRotate = true
        humanoid:MoveTo(root.Position)
    end
end

local function ForceCharacterJump(humanoid)
    if not humanoid or humanoid.Health <= 0 then return end
    pcall(function()
        humanoid.Jump = true
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end)
end

local function RunMovingJumpLoop(session)
    while State.Running and State.MovingAround and session == MovingSession do
        local _, humanoid = GetCharacterRoot()
        if humanoid then ForceCharacterJump(humanoid) end
        task.wait(0.65)
    end
end

local function WalkToPoint(session, destination)
    local root, humanoid = GetCharacterRoot()
    if not root or not humanoid then return false end
    local path = PathfindingService:CreatePath({
        AgentRadius = 2, AgentHeight = 5, AgentCanJump = true,
        AgentCanClimb = true, WaypointSpacing = 8,
    })
    if (root.Position - destination).Magnitude > 50 then
        local computed = pcall(function() path:ComputeAsync(root.Position, destination) end)
        if not computed or path.Status ~= Enum.PathStatus.Success then return false end
    end
    local waypoints = path:GetWaypoints()
    if #waypoints < 2 then return false end
    for _, waypoint in ipairs(waypoints) do
        if not State.Running or not State.MovingAround or session ~= MovingSession then return false end
        root, humanoid = GetCharacterRoot()
        if not root or not humanoid then return false end
        if waypoint.Action == Enum.PathWaypointAction.Jump or waypoint.Position.Y > root.Position.Y + 1.5 then
            ForceCharacterJump(humanoid)
        end
        local moveFinished = nil
        local moveConnection = humanoid.MoveToFinished:Connect(function(reached) moveFinished = reached == true end)
        humanoid:MoveTo(waypoint.Position)
        local startedAt = os.clock()
        local lastProgressAt = startedAt
        local lastJumpAt = 0
        local bestDistance = (root.Position - waypoint.Position).Magnitude
        while moveFinished == nil and State.Running and State.MovingAround and session == MovingSession do
            task.wait(0.05)
            root, humanoid = GetCharacterRoot()
            if not root or not humanoid then break end
            local currentDistance = (root.Position - waypoint.Position).Magnitude
            if currentDistance <= bestDistance - 0.5 then
                bestDistance = currentDistance
                lastProgressAt = os.clock()
            elseif os.clock() - lastProgressAt >= 0.8 and os.clock() - lastJumpAt >= 0.8 then
                ForceCharacterJump(humanoid)
                lastJumpAt = os.clock()
            end
            if os.clock() - startedAt >= 8 then break end
        end
        moveConnection:Disconnect()
        if not root or (root.Position - waypoint.Position).Magnitude > 4 then return false end
    end
    return true
end

local function RunMovingAround(session)
    while State.Running and State.MovingAround and session == MovingSession do
        local root, humanoid = GetCharacterRoot()
        local center, size, map = GetMapBounds()
        if not root or not humanoid or not center or not size or not map then
            task.wait(1)
        else
            humanoid.AutoRotate = true
            local radiusScales = { 0.42, 0.34, 0.26, 0.18, 0.10 }
            local baseRadiusX = math.max(size.X, 25)
            local baseRadiusZ = math.max(size.Z, 25)
            local relative = root.Position - center
            local startAngle = math.atan2(relative.Z / baseRadiusZ, relative.X / baseRadiusX)
            for pointIndex = 1, MovingPointCount do
                if not State.Running or not State.MovingAround or session ~= MovingSession then break end
                local randomAngleOffset = (math.random() - 0.5) * 0.5
                local angle = startAngle + ((math.pi * 2 * pointIndex) / MovingPointCount) + randomAngleOffset
                task.wait(math.random(1, 2) * 0.2)
                root, humanoid = GetCharacterRoot()
                if not root or not humanoid then break end
                local walked = false
                for _, radiusScale in ipairs(radiusScales) do
                    local target = GetGroundPoint(map, center, size,
                        center.X + math.cos(angle) * baseRadiusX * radiusScale,
                        center.Z + math.sin(angle) * baseRadiusZ * radiusScale)
                    if target and WalkToPoint(session, target) then walked = true break end
                end
                if not walked then task.wait(0.25) end
            end
        end
    end
end

local function SetMovingAround(enabled)
    MovingSession = MovingSession + 1
    StopCharacterMovement()
    State.MovingAround = enabled == true
    if State.MovingAround then
        local session = MovingSession
        task.spawn(function() RunMovingAround(session) end)
        task.spawn(function() RunMovingJumpLoop(session) end)
    end
end

AddConnection(State.Connections, LocalPlayer.CharacterAdded:Connect(function()
    if not State.MovingAround then return end
    MovingSession = MovingSession + 1
    local session = MovingSession
    task.delay(0.6, function()
        if State.MovingAround and session == MovingSession then
            task.spawn(function() RunMovingAround(session) end)
            RunMovingJumpLoop(session)
        end
    end)
end))

local CachedBaseHealthLabel, CachedBaseHealth, CachedBaseHealthTime = nil, nil, 0
local function GetBaseHealthText()
    if CachedBaseHealthLabel and CachedBaseHealthLabel.Parent then return CachedBaseHealthLabel.Text end
    if CachedBaseHealth and (os.clock() - CachedBaseHealthTime) < 30 then return CachedBaseHealth end
    local map = Workspace:FindFirstChild("Map")
    if not map then return "?/?" end
    for _, descendant in ipairs(map:GetDescendants()) do
        if descendant:IsA("TextLabel") and descendant.Name == "hp"
            and descendant.Parent and descendant.Parent.Name == "Frame" then
            CachedBaseHealthLabel = descendant
            CachedBaseHealth = descendant.Text
            CachedBaseHealthTime = os.clock()
            return descendant.Text
        end
    end
    return "?/?"
end

local function SanitizeName(name)
    name = tostring(name or ""):gsub("[^%w%-%_]", "_")
    name = name:gsub("_+", "_")
    return name:sub(1, 48)
end

local function CFrameToArray(value) return { value:GetComponents() } end
local function ArrayToCFrame(value)
    if type(value) ~= "table" or #value < 12 then return nil end
    return CFrame.new(table.unpack(value, 1, 12))
end
local function ProfilePath(name) return MacroFolder .. "/" .. SanitizeName(name) .. ".json" end

local function SaveProfile(name)
    name = SanitizeName(name)
    if name == "" then return false, "Profile name is empty" end
    if not HasFilesystem then return false, "Executor filesystem APIs are unavailable" end
    local payload = { Version = 4, PlaceId = game.PlaceId, Name = name, RecordedAt = os.time(), Actions = State.Actions }
    local success, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
    if not success then return false, encoded end
    writefile(ProfilePath(name), encoded)
    State.ProfileName = name
    State.ProfileVersion = 4
    return true
end

local function LoadProfile(name)
    name = SanitizeName(name)
    if name == "" or not HasFilesystem or not isfile(ProfilePath(name)) then return false, "Profile not found" end
    local success, decoded = pcall(function() return HttpService:JSONDecode(readfile(ProfilePath(name))) end)
    if not success or type(decoded) ~= "table" or type(decoded.Actions) ~= "table" then
        return false, "Invalid profile file"
    end
    State.ProfileName = name
    State.ProfileVersion = tonumber(decoded.Version) or 1
    State.Actions = decoded.Actions
    return true
end

local function ListProfiles()
    if not HasFilesystem or type(listfiles) ~= "function" then return {} end
    local result = {}
    for _, path in ipairs(listfiles(MacroFolder)) do
        local name = path:match("([^\\/]+)%.json$")
        if name and name ~= "HubConfig" and not name:find("_player$") then
            table.insert(result, name)
        end
    end
    table.sort(result)
    return result
end

local function ListPlayerProfiles()
    if not HasFilesystem or type(listfiles) ~= "function" then return {} end
    local result = {}
    for _, path in ipairs(listfiles(MacroFolder)) do
        local name = path:match("([^\\/]+)_player%.json$")
        if name then table.insert(result, name) end
    end
    table.sort(result)
    return result
end

local Gui = {}
local function SetStatus(title, detail)
    if Gui.Status then
        Gui.Status:SetTitle("State: " .. tostring(title))
        Gui.Status:SetDesc(detail or "")
    end
end
-- ============ ВЕБХУК DISCORD ============
local function IsDiscordWebhookURL(value)
    local url = tostring(value or "")
    return url:match("^https://discord%.com/api/webhooks/") ~= nil
        or url:match("^https://discordapp%.com/api/webhooks/") ~= nil
end

local function GetRequestFunction()
    return http_request or request or (syn and syn.request) or (fluxus and fluxus.request) or (krnl and krnl.request)
end

local function SendWebhook(title, description, color)
    if not State.WebhookEnabled then return false, "Webhook disabled" end
    if not IsDiscordWebhookURL(State.WebhookURL) then
        warn("[Webhook] Неверный URL. Должен начинаться с https://discord.com/api/webhooks/")
        return false, "Invalid URL"
    end
    local requestFunction = GetRequestFunction()
    if type(requestFunction) ~= "function" then
        warn("[Webhook] Инжектор не поддерживает HTTP-запросы")
        return false, "No HTTP support"
    end
    local payload = {
        username = "Skibidi Defense Hub",
        embeds = {{
            title = tostring(title or "Skibidi Defense Hub"),
            description = tostring(description or ""),
            color = tonumber(color) or 5793266,
            footer = { text = "Made By Gothbreach | " .. tostring(LocalPlayer.Name) },
            timestamp = DateTime.now():ToIsoDate(),
        }},
    }
    local ok, encoded = pcall(function() return HttpService:JSONEncode(payload) end)
    if not ok then return false, tostring(encoded) end
    local ok2, response = pcall(function()
        return requestFunction({
            Url = State.WebhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = encoded,
        })
    end)
    if not ok2 then
        warn("[Webhook] Ошибка отправки: " .. tostring(response))
        return false, tostring(response)
    end
    return true
end

local function GetMatchResultText()
    local gameEnded = GetGameEndedGui()
    if not gameEnded then return "Match Ended" end
    for _, descendant in ipairs(gameEnded:GetDescendants()) do
        if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
            local lowered = string.lower(tostring(descendant.Text or ""))
            if lowered:find("you have defeated", 1, true)
                or lowered:find("victory", 1, true)
                or lowered:find("you won", 1, true) then
                return "Victory"
            end
        end
    end
    for _, descendant in ipairs(gameEnded:GetDescendants()) do
        if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
            local lowered = string.lower(tostring(descendant.Text or ""))
            if lowered:find("defeat", 1, true)
                or lowered:find("you lost", 1, true)
                or lowered:find("game over", 1, true) then
                return "Defeat"
            end
        end
    end
    return "Match Ended"
end

local function SendMatchEndWebhook()
    if not State.WebhookEnabled or not State.WebhookMatchEnd then return end
    if not IsDiscordWebhookURL(State.WebhookURL) then return end
    local requestFunction = GetRequestFunction()
    if type(requestFunction) ~= "function" then return end

    local resultText = GetMatchResultText()
    local embedColor = (resultText == "Victory" or resultText:find("Victory")) and 65280 or 16711680

    local payload = {
        username = "Skibidi Defense Hub",
        embeds = {{
            title = "Skibidi Defense Match Report",
            description = string.format("**Stage:** %s\n**Result:** %s",
                tostring(State.LobbyChapter) .. " (" .. tostring(State.LobbyMode) .. ")", resultText),
            color = embedColor,
            fields = {
                {
                    name = "Player Info",
                    value = string.format("Name: %s\nMoney: %s\nBase HP: %s",
                        LocalPlayer.Name, tostring(GetMoney()), tostring(GetBaseHealthText())),
                    inline = false,
                },
                {
                    name = "Match Details",
                    value = string.format("Wave: %s\nMacro: %s\nMatch cycle: %d/%d",
                        tostring(GetWave()), (State.ProfileName ~= "" and State.ProfileName or "None"),
                        State.MatchesCompleted, State.MatchesBeforeLobby),
                    inline = false,
                },
            },
            footer = { text = "Made By Gothbreach" },
            timestamp = DateTime.now():ToIsoDate(),
        }},
    }

    pcall(function()
        requestFunction({
            Url = State.WebhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload),
        })
    end)
end

Gui.SendWebhook = SendWebhook
Gui.SendMatchEndWebhook = SendMatchEndWebhook
-- ============ КОНЕЦ ВЕБХУКА ============
local function RefreshActionList()
    if not Gui.ActionSummary then return end
    local lines = {}
    local first = math.max(1, #State.Actions - 7)
    for index = first, #State.Actions do
        local action = State.Actions[index]
        local subject = action.Unit or action.Handle or ""
        if action.Type == "BoostLink" then
            subject = string.format("%s > %s", action.SourceHandle or "?", action.TargetHandle or "?")
        end
        table.insert(lines, string.format("%02d | W%s | %s | %s", index, action.Wave or 0, action.Type or "?", subject))
    end
    Gui.ActionSummary:SetTitle(string.format("Recorded actions: %d", #State.Actions))
    Gui.ActionSummary:SetDesc(#lines > 0 and table.concat(lines, "\n") or "No actions loaded")
end

local function AddAction(action)
    action.Wave = action.Wave or GetWave()
    action.RecordedAt = os.clock() - State.RecordStartedAt
    table.insert(State.Actions, action)
    RefreshActionList()
    SetStatus("Recording", string.format("Captured %s at wave %d", action.Type, action.Wave))
end

Hub.RecordAbilityAction = function(towerId, abilityIndex, marker)
    if not State.Recording or not TowerDataFolder then return false end
    local tower = typeof(towerId) == "Instance" and towerId or TowerDataFolder:FindFirstChild(tostring(towerId or ""))
    local meta = tower and State.TowerMeta[tower]
    if not meta then return false end
    local now = os.clock()
    local previousAction = meta.LastAbilityAction
    if previousAction and previousAction.Marker == (marker and tostring(marker) or nil)
        and now - (meta.LastAbilityRecordedAt or -math.huge) <= 0.35 then
        previousAction.AbilityIndex = tonumber(abilityIndex) or previousAction.AbilityIndex or 1
        if marker and tostring(marker) ~= "" then previousAction.Marker = tostring(marker) end
        meta.LastAbilityRecordedAt = now
        RefreshActionList()
        return true
    end
    local action = { Type = "Ability", Handle = meta.Handle, AbilityIndex = tonumber(abilityIndex) or 1,
        Marker = marker and tostring(marker) or nil }
    meta.LastAbilityAction = action
    meta.LastAbilityRecordedAt = now
    AddAction(action)
    return true
end

Hub.RecordBoostLinkAction = function(sourceId, targetId)
    if not State.Recording or not TowerDataFolder then return false end
    local sourceTower = typeof(sourceId) == "Instance" and sourceId or TowerDataFolder:FindFirstChild(tostring(sourceId or ""))
    local targetTower = typeof(targetId) == "Instance" and targetId or TowerDataFolder:FindFirstChild(tostring(targetId or ""))
    local sourceMeta = sourceTower and State.TowerMeta[sourceTower]
    local targetMeta = targetTower and State.TowerMeta[targetTower]
    if not sourceMeta or not targetMeta or sourceTower == targetTower then return false end
    if not sourceMeta.PlaceRecorded or not targetMeta.PlaceRecorded then
        if targetMeta.PendingBoostSourceHandle == sourceMeta.Handle then return true end
        targetMeta.PendingBoostSourceHandle = sourceMeta.Handle
        task.spawn(function()
            local ready = WaitUntil(function()
                return not State.Recording or (sourceMeta.PlaceRecorded and targetMeta.PlaceRecorded)
            end, 3, 0.03)
            if targetMeta.PendingBoostSourceHandle == sourceMeta.Handle then targetMeta.PendingBoostSourceHandle = nil end
            if ready and State.Recording and sourceTower.Parent == TowerDataFolder and targetTower.Parent == TowerDataFolder then
                Hub.RecordBoostLinkAction(sourceTower, targetTower)
            end
        end)
        return true
    end
    local now = os.clock()
    if targetMeta.LastBoostSourceHandle == sourceMeta.Handle
        and now - (targetMeta.LastBoostRecordedAt or -math.huge) <= 0.5 then return true end
    targetMeta.LastBoostSourceHandle = sourceMeta.Handle
    targetMeta.LastBoostRecordedAt = now
    AddAction({ Type = "BoostLink", SourceHandle = sourceMeta.Handle, TargetHandle = targetMeta.Handle })
    return true
end

local function DisableLegacyAbilityRecorderHook()
    local hookState = Environment.KeroSkibidiAbilityHook
    if type(hookState) == "table" then
        hookState.Callback = nil
        hookState.Remote = nil
    end
    Environment.KeroSkibidiAbilityHook = nil
end
DisableLegacyAbilityRecorderHook()

local function InferAbilityIndex(object)
    local current = object
    for _ = 1, 4 do
        if not current then break end
        for _, attribute in ipairs({ "AbilityIndex", "Ability", "Index", "Slot" }) do
            local value = tonumber(current:GetAttribute(attribute))
            if value and value >= 1 then return math.floor(value) end
        end
        local fromName = tonumber(tostring(current.Name):match("(%d+)$"))
        if fromName and fromName >= 1 then return math.floor(fromName) end
        if current:IsA("GuiObject") and current.LayoutOrder > 0 then return current.LayoutOrder end
        current = current.Parent
    end
    return 1
end

local function IsOwnTower(tower)
    return tower and tower.Parent == TowerDataFolder and tower:GetAttribute("Creator") == LocalPlayer.Name
end

local function FindTowerModel(towerId, timeout)
    if not TowersFolder then return nil end
    local model
    WaitUntil(function()
        model = TowersFolder:FindFirstChild(tostring(towerId))
        return model
    end, timeout or 2, 0.05)
    return model
end

local function GetPlacementCFrame(tower)
    local model = FindTowerModel(tower.Name, 2)
    local boostPosition = tower:GetAttribute("BoostPos")
    if typeof(boostPosition) == "Vector3" then
        local rotation = CFrame.identity
        if model and model:IsA("Model") then
            local success, pivot = pcall(model.GetPivot, model)
            if success then rotation = pivot.Rotation end
        end
        return CFrame.new(boostPosition + Vector3.new(0, 4.7, 0)) * rotation
    end
    if model and model:IsA("Model") then
        local success, pivot = pcall(model.GetPivot, model)
        if success then return pivot end
    end
    return nil
end

local function IsUnavailableTargetMode(mode)
    if mode == nil then return true end
    local normalized = tostring(mode):upper():gsub("%s+", "")
    return normalized == "" or normalized == "N/A" or normalized == "NA" or normalized == "NONE"
end

local function AttachTowerRecorder(tower, handle)
    if State.TowerMeta[tower] then return end
    local meta = {
        Handle = handle, Level = tonumber(tower:GetAttribute("Upgrade")) or 0,
        SellPrice = tonumber(tower:GetAttribute("SellPrice")) or 0, PendingUpgradeCost = nil,
        TargetMode = tower:GetAttribute("TargetMode"), LastUpgradeAt = -math.huge,
        AbilityMarkers = {}, LastAbilityAction = nil, LastAbilityRecordedAt = -math.huge,
        ClockBoost = tower:GetAttribute("ClockBoost"), LastBoostSourceHandle = nil,
        LastBoostRecordedAt = -math.huge, PendingBoostSourceHandle = nil, PlaceRecorded = false,
    }
    for attribute, value in pairs(tower:GetAttributes()) do
        if tostring(attribute):match("^ATTACK") then meta.AbilityMarkers[attribute] = value end
    end
    State.TowerMeta[tower] = meta
    AddConnection(State.RecorderConnections, tower:GetAttributeChangedSignal("SellPrice"):Connect(function()
        local newPrice = tonumber(tower:GetAttribute("SellPrice")) or meta.SellPrice
        if newPrice > meta.SellPrice then
            meta.PendingUpgradeCost = math.max(0, (newPrice - meta.SellPrice) * 2)
            meta.LastUpgradeAt = os.clock()
        end
        meta.SellPrice = newPrice
    end))
    AddConnection(State.RecorderConnections, tower:GetAttributeChangedSignal("Upgrade"):Connect(function()
        local newLevel = tonumber(tower:GetAttribute("Upgrade")) or meta.Level
        if State.Recording and newLevel > meta.Level then
            meta.LastUpgradeAt = os.clock()
            AddAction({ Type = "Upgrade", Handle = meta.Handle, FromLevel = meta.Level,
                ToLevel = newLevel, EstimatedCost = meta.PendingUpgradeCost or 0 })
        end
        meta.Level = newLevel
        meta.PendingUpgradeCost = nil
    end))
    AddConnection(State.RecorderConnections, tower:GetAttributeChangedSignal("TargetMode"):Connect(function()
        local newMode = tower:GetAttribute("TargetMode")
        local oldMode = meta.TargetMode
        local automaticUpgradeTransition = IsUnavailableTargetMode(oldMode) and os.clock() - meta.LastUpgradeAt <= 0.5
        if State.Recording and newMode and newMode ~= oldMode and not automaticUpgradeTransition then
            AddAction({ Type = "Target", Handle = meta.Handle, Mode = newMode })
        end
        meta.TargetMode = newMode
    end))
    AddConnection(State.RecorderConnections, tower:GetAttributeChangedSignal("ClockBoost"):Connect(function()
        local previous = meta.ClockBoost
        local sourceId = tower:GetAttribute("ClockBoost")
        meta.ClockBoost = sourceId
        if not State.Recording or sourceId == nil or tostring(sourceId) == ""
            or tostring(sourceId) == "0" or tostring(sourceId) == tostring(previous) then return end
        Hub.RecordBoostLinkAction(sourceId, tower)
    end))
    AddConnection(State.RecorderConnections, tower.AttributeChanged:Connect(function(attribute)
        if not tostring(attribute):match("^ATTACK") then return end
        local previous = meta.AbilityMarkers[attribute]
        local value = tower:GetAttribute(attribute)
        meta.AbilityMarkers[attribute] = value
        if not State.Recording or os.clock() - State.PendingAbilityClickAt > 2 or previous == value then return end
        local markerIndex = tonumber(tostring(attribute):match("(%d+)$"))
        local abilityIndex = markerIndex or State.PendingAbilityIndex or 1
        State.PendingAbilityClickAt = -math.huge
        State.PendingAbilityIndex = 1
        Hub.RecordAbilityAction(tower, abilityIndex, attribute)
    end))
end

local StopRecording

local function StartRecording(profileName)
    if State.Playing then return false, "Stop playback first" end
    if not MatchObjectsReady() then return false, "Recording is only available after entering a match" end
    profileName = SanitizeName(profileName)
    if profileName == "" then return false, "Enter a profile name" end
    DisconnectAll(State.RecorderConnections)
    State.Actions = {}
    State.ProfileName = profileName
    State.ProfileVersion = 4
    State.RecordStartedAt = os.clock()
    State.NextHandle = 1
    State.TowerMeta = setmetatable({}, { __mode = "k" })
    State.PendingAbilityClickAt = -math.huge
    State.PendingAbilityIndex = 1
    State.Recording = true
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local watchedAbilityButtons = setmetatable({}, { __mode = "k" })
    local function isAbilityButton(object)
        if not object:IsA("GuiButton") then return false end
        local current = object
        for _ = 1, 4 do
            if not current then break end
            if tostring(current.Name):lower():find("abilit", 1, true) then return true end
            current = current.Parent
        end
        return false
    end
    local function watchAbilityButton(object)
        if watchedAbilityButtons[object] or not isAbilityButton(object) then return end
        watchedAbilityButtons[object] = true
        AddConnection(State.RecorderConnections, object.InputBegan:Connect(function(input)
            if State.Recording and (input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch) then
                State.PendingAbilityClickAt = os.clock()
                State.PendingAbilityIndex = InferAbilityIndex(object)
            end
        end))
    end
    if playerGui then
        for _, object in ipairs(playerGui:GetDescendants()) do watchAbilityButton(object) end
        AddConnection(State.RecorderConnections, playerGui.DescendantAdded:Connect(watchAbilityButton))
    end
    local existingOwnTowers = 0
    for _, tower in ipairs(TowerDataFolder:GetChildren()) do
        if IsOwnTower(tower) then existingOwnTowers = existingOwnTowers + 1 end
    end
    AddConnection(State.RecorderConnections, TowerDataFolder.ChildAdded:Connect(function(tower)
        task.spawn(function()
            local ready = WaitUntil(function()
                return IsOwnTower(tower) and tower:GetAttribute("ID") ~= nil
            end, 5, 0.05)
            if not ready or not State.Recording then return end
            local handle = "T" .. State.NextHandle
            State.NextHandle = State.NextHandle + 1
            AttachTowerRecorder(tower, handle)
            local placement = GetPlacementCFrame(tower)
            if not placement then
                SetStatus("Record warning", "Could not read placement CFrame for tower " .. tower.Name)
                return
            end
            local sellPrice = tonumber(tower:GetAttribute("SellPrice")) or 0
            AddAction({ Type = "Place", Handle = handle, Unit = tostring(tower:GetAttribute("ID")),
                CFrame = CFrameToArray(placement), EstimatedCost = sellPrice * 2 })
            local meta = State.TowerMeta[tower]
            if meta then meta.PlaceRecorded = true end
        end)
    end))
    AddConnection(State.RecorderConnections, TowerDataFolder.ChildRemoved:Connect(function(tower)
        local meta = State.TowerMeta[tower]
        if not meta then return end
        task.delay(0.15, function()
            if State.Recording and not IsGameEnded() then
                AddAction({ Type = "Sell", Handle = meta.Handle })
            end
        end)
    end))
    local gameEnded = GetGameEndedGui()
    if gameEnded then
        AddConnection(State.RecorderConnections, gameEnded:GetPropertyChangedSignal("Enabled"):Connect(function()
            if State.Recording and gameEnded.Enabled then
                task.defer(function()
                    if State.Recording then StopRecording(true) end
                end)
            end
        end))
    end
    RefreshActionList()
    if existingOwnTowers > 0 then
        SetStatus("Recording", string.format("Started with %d existing tower(s); new actions only", existingOwnTowers))
    else
        SetStatus("Recording", "Passive recorder active; play normally")
    end
    return true
end

StopRecording = function(save)
    if not State.Recording then return false, "Recorder is not running" end
    State.Recording = false
    if Gui.SetRecordToggle then Gui.SetRecordToggle(false) end
    DisconnectAll(State.RecorderConnections)
    if save then
        local success, message = SaveProfile(State.ProfileName)
        if not success then
            SetStatus("Save failed", message)
            return false, message
        end
        SetStatus("Saved", string.format("%s (%d actions)", State.ProfileName, #State.Actions))
        if Gui.RefreshProfiles then Gui.RefreshProfiles(State.ProfileName) end
        if Gui.QueueSave then Gui.QueueSave() end
    else
        SetStatus("Recorder stopped", string.format("%d unsaved actions", #State.Actions))
    end
    return true
end

-- PLAYER RECORDING
local function StartPlayerRecording(profileName)
    if State.Playing then return false, "Stop playback first" end
    profileName = SanitizeName(profileName)
    if profileName == "" then return false, "Enter a profile name" end
    State.PlayerActions = {}
    State.PlayerRecordingProfileName = profileName
    State.PlayerRecordingStartedAt = os.clock()
    State.PlayerRecording = true
    State.PlayerRecordingConnections = {}
    local towerConn = TowerDataFolder.ChildAdded:Connect(function(tower)
        task.spawn(function()
            local ready = WaitUntil(function()
                return IsOwnTower(tower) and tower:GetAttribute("ID") ~= nil
            end, 5, 0.05)
            if not ready or not State.PlayerRecording then return end
            local handle = "P" .. (#State.PlayerActions + 1)
            local placement = GetPlacementCFrame(tower)
            if not placement then return end
            local sellPrice = tonumber(tower:GetAttribute("SellPrice")) or 0
            table.insert(State.PlayerActions, {
                Type = "Place", Handle = handle, Unit = tostring(tower:GetAttribute("ID")),
                CFrame = CFrameToArray(placement), EstimatedCost = sellPrice * 2,
                Wave = GetWave(), RecordedAt = os.clock() - State.PlayerRecordingStartedAt,
            })
        end)
    end)
    table.insert(State.PlayerRecordingConnections, towerConn)
    local speedConn
    if Remotes.Speed then
        speedConn = Remotes.Speed.OnClientEvent:Connect(function(speed)
            if not State.PlayerRecording then return end
            table.insert(State.PlayerActions, {
                Type = "Speed", Speed = tonumber(speed) or 1,
                Wave = GetWave(), RecordedAt = os.clock() - State.PlayerRecordingStartedAt,
            })
        end)
        table.insert(State.PlayerRecordingConnections, speedConn)
    end
    local playerGui = GetPlayerGui()
    if playerGui then
        local function watchAbility(obj)
            if not obj:IsA("GuiButton") then return end
            if not tostring(obj.Name):lower():find("abilit") then return end
            obj.MouseButton1Click:Connect(function()
                if not State.PlayerRecording then return end
                table.insert(State.PlayerActions, {
                    Type = "Ability", AbilityIndex = InferAbilityIndex(obj),
                    Wave = GetWave(), RecordedAt = os.clock() - State.PlayerRecordingStartedAt,
                })
            end)
        end
        for _, obj in ipairs(playerGui:GetDescendants()) do watchAbility(obj) end
        local abilityConn = playerGui.DescendantAdded:Connect(watchAbility)
        table.insert(State.PlayerRecordingConnections, abilityConn)
    end
    SetStatus("Player Recording", "Recording your actions...")
    return true
end

local function StopPlayerRecording(save)
    if not State.PlayerRecording then return false, "Not recording" end
    State.PlayerRecording = false
    for _, conn in ipairs(State.PlayerRecordingConnections or {}) do
        pcall(function() conn:Disconnect() end)
    end
    State.PlayerRecordingConnections = {}
    if save then
        local payload = { Version = 1, Name = State.PlayerRecordingProfileName, Actions = State.PlayerActions }
        writefile(MacroFolder .. "/" .. State.PlayerRecordingProfileName .. "_player.json", HttpService:JSONEncode(payload))
        SetStatus("Player Saved", string.format("%s (%d actions)", State.PlayerRecordingProfileName, #State.PlayerActions))
    end
    return true
end

local function PlayPlayerRecording(profileName)
    profileName = SanitizeName(profileName)
    local path = MacroFolder .. "/" .. profileName .. "_player.json"
    if not isfile(path) then return false, "Player recording not found" end
    local decoded = HttpService:JSONDecode(readfile(path))
    if type(decoded.Actions) ~= "table" then return false, "Invalid file" end
    State.Playing = true
    task.spawn(function()
        local startedAt = os.clock()
        for _, action in ipairs(decoded.Actions) do
            if not State.Playing then break end
            local targetTime = tonumber(action.RecordedAt) or 0
            while (os.clock() - startedAt) < targetTime and State.Playing do task.wait(0.05) end
            if action.Type == "Place" then
                local placement = ArrayToCFrame(action.CFrame)
                if placement and GetMoney() >= (tonumber(action.EstimatedCost) or 0) then
                    Remotes.Place:FireServer(action.Unit, placement, false)
                end
            elseif action.Type == "Speed" then
                if Remotes.Speed then Remotes.Speed:FireServer(action.Speed) end
            elseif action.Type == "Ability" then
                if Remotes.Ability and Remotes.Ability:IsA("RemoteFunction") then
                    pcall(function() Remotes.Ability:InvokeServer(action.AbilityIndex) end)
                end
            end
            task.wait(0.05)
        end
        State.Playing = false
        SetStatus("Player Playback complete", "")
    end)
    return true
end

-- UPGRADE ALL
local CachedUpgradeBtn = nil
local CachedUpgradeBtnTime = 0
local function PlayUpgradeAll()
    local gui = GetPlayerGui()
    if not gui then return false, "PlayerGui not found" end
    local btn
    if CachedUpgradeBtn and CachedUpgradeBtn.Parent
        and (os.clock() - CachedUpgradeBtnTime) < 5 then
        btn = CachedUpgradeBtn
    else
        local rightButtons = gui:FindFirstChild("RightButtons")
        if rightButtons then
            for _, child in ipairs(rightButtons:GetChildren()) do
                if child:IsA("GuiButton") then
                    local name = tostring(child.Name):lower()
                    local text = child:IsA("TextButton") and tostring(child.Text):lower() or ""
                    if name:find("upgrade") or text:find("upgrade") then
                        btn = child
                        break
                    end
                end
            end
        end
        if not btn then
            for _, obj in ipairs(gui:GetDescendants()) do
                if obj:IsA("GuiButton") then
                    local text = obj:IsA("TextButton") and tostring(obj.Text or ""):lower() or ""
                    if text:find("upgrade all", 1, true) or text:find("upgrade", 1, true) then
                        btn = obj
                        break
                    end
                end
            end
        end
        if btn then
            CachedUpgradeBtn = btn
            CachedUpgradeBtnTime = os.clock()
        end
    end
    if not btn then
        if TowerDataFolder and Remotes.Upgrade then
            for _, tower in ipairs(TowerDataFolder:GetChildren()) do
                if tower:GetAttribute("Creator") == LocalPlayer.Name then
                    pcall(function() Remotes.Upgrade:FireServer(tostring(tower.Name)) end)
                end
            end
            return true
        end
        return false, "Upgrade All button not found"
    end
    if type(firesignal) == "function" then
        local ok = pcall(firesignal, btn.MouseButton1Click)
        if ok then return true end
    end
    local ok2 = pcall(function() btn.MouseButton1Click:Fire() end)
    if ok2 then return true end
    if TowerDataFolder and Remotes.Upgrade then
        for _, tower in ipairs(TowerDataFolder:GetChildren()) do
            if tower:GetAttribute("Creator") == LocalPlayer.Name then
                pcall(function() Remotes.Upgrade:FireServer(tostring(tower.Name)) end)
            end
        end
        return true
    end
    return false, "All methods failed"
end

-- ОБЫЧНОЕ ВОСПРОИЗВЕДЕНИЕ
local function FindMatchingRuntimeTower(action)
    if not TowerDataFolder then return nil end
    for _, tower in ipairs(TowerDataFolder:GetChildren()) do
        if IsOwnTower(tower) and not State.UsedRuntimeTowers[tower]
            and tostring(tower:GetAttribute("ID")) == tostring(action.Unit) then
            return tower
        end
    end
    return nil
end

local function WaitForActionGate(action, playbackStartedAt)
    local recordedAt = tonumber(action.RecordedAt) or 0
    local cost = tonumber(action.EstimatedCost) or 0
    local targetWave = tonumber(action.Wave) or 0
    return WaitUntil(function()
        if not State.Playing or IsGameEnded() then return true end
        local elapsed = os.clock() - playbackStartedAt
        local currentWave = GetWave()
        local hasMoney = cost <= 0 or GetMoney() >= cost
        local hasWave = targetWave <= 0 or currentWave >= targetWave
        local hasTime = elapsed >= recordedAt
        if targetWave > 0 and currentWave > targetWave then hasTime = true end
        if targetWave > 0 and currentWave >= targetWave and not hasTime then hasTime = true end
        if State.PlaybackMode == "Time" then return hasTime
        elseif State.PlaybackMode == "Money" then return hasMoney end
        return hasWave and hasTime and hasMoney
    end, 600, 0.05)
end

local function PlayPlace(action)
    local placement = ArrayToCFrame(action.CFrame)
    if not placement then return false, "Invalid placement CFrame" end
    local existing = FindMatchingRuntimeTower(action)
    if existing then
        State.RuntimeHandles[action.Handle] = existing
        State.UsedRuntimeTowers[existing] = true
        return true
    end
    local estimatedCost = tonumber(action.EstimatedCost) or 0
    if GetMoney() < estimatedCost and GetMoney() >= 0 then
        WaitUntil(function() return GetMoney() >= estimatedCost or GetMoney() < 0 end, 30, 0.2)
    end
    Remotes.Place:FireServer(action.Unit, placement, false)
    task.spawn(function()
        local success, tower = WaitUntil(function()
            return FindMatchingRuntimeTower(action)
        end, 3, 0.1)
        if success and tower then
            State.RuntimeHandles[action.Handle] = tower
            State.UsedRuntimeTowers[tower] = true
        end
    end)
    return true
end

local function ResolveHandle(handle)
    local tower = State.RuntimeHandles[handle]
    if tower and tower.Parent == TowerDataFolder then return tower end
    return nil
end

local function PlayUpgrade(action)
    local ok = PlayUpgradeAll()
    if ok then return true end
    local tower = ResolveHandle(action.Handle)
    if not tower then return true end
    local targetLevel = tonumber(action.ToLevel) or ((tonumber(action.FromLevel) or 0) + 1)
    local estimatedCost = tonumber(action.EstimatedCost) or 0
    local fundsUnlocked = estimatedCost <= 0
    local deadline = os.clock() + 180
    while State.Playing and tower.Parent == TowerDataFolder and os.clock() < deadline and not IsGameEnded() do
        local currentLevel = tonumber(tower:GetAttribute("Upgrade")) or 0
        if currentLevel >= targetLevel then return true end
        if not fundsUnlocked and (GetMoney() >= estimatedCost or GetMoney() < 0) then fundsUnlocked = true end
        if fundsUnlocked then
            Remotes.Upgrade:FireServer(tostring(tower.Name))
            task.wait(0.05)
        else
            task.wait(0.1)
        end
    end
    return true
end

local function IsAutomaticRecordedTarget(index, action)
    if State.ProfileVersion >= 2 then return false end
    local previous = State.Actions[index - 1]
    if not previous or previous.Type ~= "Upgrade" or previous.Handle ~= action.Handle then return false end
    local targetTime = tonumber(action.RecordedAt)
    local upgradeTime = tonumber(previous.RecordedAt)
    return targetTime ~= nil and upgradeTime ~= nil and targetTime >= upgradeTime
        and targetTime - upgradeTime <= 0.5
end

local function PlaySell(action)
    local tower = ResolveHandle(action.Handle)
    if not tower then return true end
    for _ = 1, 3 do
        if not State.Playing or tower.Parent ~= TowerDataFolder then return true end
        Remotes.Sell:FireServer(tostring(tower.Name))
        task.wait(0.1)
        if tower.Parent ~= TowerDataFolder then return true end
    end
    return true
end

local function PlayTarget(action)
    local tower = ResolveHandle(action.Handle)
    if not tower then return true end
    for _ = 1, 5 do
        if not State.Playing or tower.Parent ~= TowerDataFolder then return true end
        if tower:GetAttribute("TargetMode") == action.Mode then return true end
        Remotes.Target:FireServer(tostring(tower.Name))
        task.wait(0.1)
    end
    return true
end

local function PlayAbility(action)
    local tower = ResolveHandle(action.Handle)
    if not tower then return true end
    if not Remotes.Ability or not Remotes.Ability:IsA("RemoteFunction") then
        return true
    end
    local abilityIndex = tonumber(action.AbilityIndex) or 1
    pcall(function()
        Remotes.Ability:InvokeServer(tostring(tower.Name), abilityIndex)
    end)
    task.wait(0.05)
    return true
end

local function PlayBoostLink(action)
    local sourceTower = ResolveHandle(action.SourceHandle)
    local targetTower = ResolveHandle(action.TargetHandle)
    if not sourceTower or not targetTower then return true end
    if not Remotes.BoostSelect or not Remotes.BoostSelect:IsA("RemoteEvent") then
        return true
    end
    local sourceId = tonumber(sourceTower.Name)
    if not sourceId then return true end
    pcall(function()
        Remotes.BoostSelect:FireServer(sourceId, tostring(targetTower.Name))
    end)
    task.wait(0.1)
    return true
end

local function StopPlayback(reason)
    State.Playing = false
    if reason then SetStatus("Stopped", reason) end
end

local function StartPlayback()
    if State.Recording then return false, "Stop recording first" end
    if not MatchObjectsReady() then return false, "Playback is armed and will start after entering a match" end
    if State.Playing then return false, "Playback is already running" end
    if #State.Actions == 0 then return false, "Load or record a profile first" end
    State.Playing = true
    State.AutoPlaybackStarted = true
    State.PlaybackFirstActionArmed = false
    State.PlaybackFirstActionDone = false
    State.RuntimeHandles = {}
    State.UsedRuntimeTowers = setmetatable({}, { __mode = "k" })
    task.spawn(function()
        SetStatus("Playback", string.format("Running %s", State.ProfileName))
        local camera = Workspace.CurrentCamera
        if camera then
            camera.CFrame = camera.CFrame * CFrame.Angles(
                math.rad(math.random(-30, 30)),
                math.rad(math.random(-30, 30)),
                0
            )
        end
        local playbackStartedAt = os.clock()
        for index, action in ipairs(State.Actions) do
            if not State.Playing or IsGameEnded() then break end
            if index == 1 then State.PlaybackFirstActionArmed = true end
            SetStatus("Playback", string.format("%d/%d  %s  W%d", index, #State.Actions, action.Type or "?", action.Wave or 0))
            local gateReady = WaitForActionGate(action, playbackStartedAt)
            if not gateReady or not State.Playing or IsGameEnded() then break end
            local success, message
            if action.Type == "Place" then success, message = PlayPlace(action)
            elseif action.Type == "Upgrade" then success, message = PlayUpgrade(action)
            elseif action.Type == "Sell" then success, message = PlaySell(action)
            elseif action.Type == "Target" then
                if IsAutomaticRecordedTarget(index, action) then success = true
                else success, message = PlayTarget(action) end
            elseif action.Type == "Ability" then success, message = PlayAbility(action)
            elseif action.Type == "BoostLink" then success, message = PlayBoostLink(action)
            else success, message = false, "Unknown action type: " .. tostring(action.Type) end
            if not success then
                SetStatus("Warning", string.format("Action %d failed: %s", index, message or "unknown error"))
            end
            if index == 1 then State.PlaybackFirstActionDone = true end
        end
        if State.Playing then
            State.Playing = false
            SetStatus("Playback complete", "Waiting for the match to end")
        end
    end)
    return true
end

local function ApplySpeed(speed)
    speed = tonumber(speed) or 1
    if speed < 1 or speed > 6 then speed = 1 end
    State.Speed = speed
    pcall(function() Remotes.Speed:FireServer(speed) end)
    if Gui.Runtime then
        Gui.Runtime:SetDesc(string.format("Wave %d | Money %d | %s | Base %s | Speed x%d",
            GetWave(), GetMoney(), GetUnitCountText(), GetBaseHealthText(), speed))
    end
end

task.spawn(function()
    local lastReady, lastSkip = 0, 0
    local speedReadySince = nil
    local lastRefresh = 0
    local wasMatchReady = false
    local startupSpeedReset = false
    local replayLatched = false
    local restartAfterReplay = false
    while State.Running do
        local now = os.clock()
        if now - lastRefresh >= 10 then
            lastRefresh = now
            RefreshGameObjects()
        end
        local ended = IsGameEnded()
        local matchReady = TowerDataFolder ~= nil and TowersFolder ~= nil and Remotes.Place ~= nil
        local macroConfigured = State.PlaybackEnabled and State.ProfileName ~= ""
        local macroProfilePrepared = not macroConfigured or #State.Actions > 0
        local macroAutomationReady = macroProfilePrepared
            and (not macroConfigured or State.PlaybackFirstActionArmed)
        if not matchReady or ended then
            State.AutoPlaybackStarted = false
            State.PlaybackFirstActionArmed = false
            State.PlaybackFirstActionDone = false
            wasMatchReady = false
            speedReadySince = nil
            startupSpeedReset = false
            State.Chapter9SpeedSet = false
        elseif not wasMatchReady then
            wasMatchReady = true
            speedReadySince = nil
            startupSpeedReset = false
        elseif State.PlaybackEnabled and not State.AutoPlaybackStarted and not State.Playing
            and not State.Recording and #State.Actions > 0 and Gui.StartEnabledPlayback then
            Gui.StartEnabledPlayback()
        end
        if State.AutoReady and not ended and Remotes.Ready and now - lastReady >= 1 then
            lastReady = now
            pcall(function() Remotes.Ready:FireServer(true) end)
        end
        if matchReady and macroProfilePrepared and not macroAutomationReady
            and (State.AutoSpeed or State.AutoSkip) and Remotes.Speed and not startupSpeedReset then
            startupSpeedReset = true
            pcall(function() Remotes.Speed:FireServer(1) end)
        end
        local gui = GetPlayerGui()
        local skipGui = gui and gui:FindFirstChild("skipWave")
        local skipWindowOpen = skipGui and skipGui.Enabled == true
        if State.AutoSkip and macroAutomationReady and not ended and Remotes.Skip
            and skipWindowOpen and now - lastSkip >= 0.35 then
            lastSkip = now
            pcall(function() Remotes.Skip:FireServer(true) end)
        end
        local speedEligible = State.AutoSpeed and macroAutomationReady and matchReady and Remotes.Speed and not ended
        if State.Chapter9Mode and matchReady and not ended then
            local currentWave = GetWave()
            if currentWave >= 1 and not State.Chapter9SpeedSet then
                if currentWave == 1 then
                    ApplySpeed(1)
                elseif currentWave >= 2 then
                    ApplySpeed(4)
                    State.Chapter9SpeedSet = true
                end
            end
        elseif speedEligible then
            if speedReadySince == nil then
                speedReadySince = now
            elseif now - speedReadySince >= State.SpeedScaleDelay then
                speedReadySince = now
                ApplySpeed(State.Speed)
            end
        else
            speedReadySince = nil
        end
        if ended and not replayLatched then
    replayLatched = true

    local shouldCount = false
    if State.AutoReplay then
        shouldCount = true
    else
        if State.LastCountedJobId ~= game.JobId then
            shouldCount = true
        end
    end

    if State.AutoBackLobby and shouldCount then
        State.LastCountedJobId = game.JobId
        State.MatchesCompleted = State.MatchesCompleted + 1
        if State.MatchesCompleted >= State.MatchesBeforeLobby then
            State.PendingLobbyReturn = true
            SetStatus("Match cycle complete", "Waiting 5s before lobby")
            local lobbyWaitUntil = os.clock() + 5
            task.spawn(function()
                while os.clock() < lobbyWaitUntil and State.Running do
                    task.wait(0.5)
                end
                if State.Running and State.PendingLobbyReturn then
                    local triggered, message = TriggerBackLobbyButton()
                    if not triggered then
                        SetStatus("Lobby button waiting", tostring(message) .. " | retrying")
                    end
                end
            end)
        else
                    SetStatus("Match counted", string.format("%d/%d matches before lobby",
                        State.MatchesCompleted, State.MatchesBeforeLobby))
                end
                if Gui.UpdateMatchCounter then Gui.UpdateMatchCounter() end
                if Gui.SaveConfigNow then Gui.SaveConfigNow()
                elseif Gui.QueueSave then Gui.QueueSave() end
            end
            SendMatchEndWebhook()
             local lobbyReturnTriggered = false
            if State.PendingLobbyReturn then
                local message
                lobbyReturnTriggered, message = TriggerBackLobbyButton()
                if not lobbyReturnTriggered then
                    SetStatus("Lobby button waiting", tostring(message) .. " | retrying")
                    task.spawn(function()
                        local retryMessage = message
                        for _ = 1, 40 do
                            if not State.Running or not State.PendingLobbyReturn then return end
                            task.wait(1)
                            local triggered
                            triggered, retryMessage = TriggerBackLobbyButton()
                            if triggered then
                                SetStatus("Returning to lobby", "Game back button triggered")
                                return
                            end
                        end
                        SetStatus("Lobby button failed", "Teleporting via service")
                        pcall(function()
                            TeleportService:Teleport(LobbyPlaceId, LocalPlayer)
                        end)
                    end)
                end
            end
            local shouldReplay = State.AutoReplay and not State.PendingLobbyReturn
            if shouldReplay and Remotes.Replay then
                restartAfterReplay = not State.PendingLobbyReturn and State.PlaybackEnabled and #State.Actions > 0
                pcall(function() Remotes.Replay:FireServer() end)
            end
          elseif not ended then
            replayLatched = false
            if restartAfterReplay and not State.Playing and not State.PendingLobbyReturn then
                restartAfterReplay = false
                local started, message = StartPlayback()
                if started and Gui.SetPlaybackToggle then Gui.SetPlaybackToggle(true)
                elseif not started then SetStatus("Replay started", message or "Could not restart profile") end
            end
        end
        task.wait(0.1)
    end
end)

-- ============================================================
-- WindUI
-- ============================================================
local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
local Window = WindUI:CreateWindow({
    Title = "Skibidi Defense Hub", Author = "Made By oreshick :3",
    Folder = "SkibidiDefenseHub", Icon = "clapperboard", Theme = "Dark",
    Size = UDim2.fromOffset(620, 480), Transparent = true, HideSearchBar = true,
    NewElements = true, ToggleKey = Enum.KeyCode.RightShift,
    OpenButton = { Title = "Skibidi Defense Hub", Enabled = true, Draggable = true, OnlyMobile = false },
})

pcall(function() Window:SetToggleKey(Enum.KeyCode.RightShift) end)
pcall(function() Window:SetTogleKey(Enum.KeyCode.RightShift) end)

local function Notify(title, content)
    pcall(function() WindUI:Notify({ Title = title, Content = content, Duration = 4, Icon = "bell" }) end)
end

local function WrapParagraph(element)
    local wrapper = {}
    function wrapper:SetTitle(value)
        pcall(function()
            if element.SetTitle then element:SetTitle(value) else element:Set({ Title = value }) end
        end)
    end
    function wrapper:SetDesc(value)
        pcall(function()
            if element.SetDesc then element:SetDesc(value) else element:Set({ Desc = value }) end
        end)
    end
    return wrapper
end

local function ReadConfig()
    if not HasFilesystem or not isfile(ConfigFile) then return {} end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(ConfigFile)) end)
    return ok and type(decoded) == "table" and decoded or {}
end

local Config = ReadConfig()
State.AutoReplay = Config.AutoReplay == true
State.AutoReady = Config.AutoReady == true
State.AutoSkip = Config.AutoSkip == true
State.AutoSpeed = Config.AutoSpeed == true
State.SpeedScaleDelay = math.clamp(tonumber(Config.SpeedScaleDelay or Config.AutoReadyDelay) or 1, 0.5, 10)
State.MovingAround = Config.MovingAround == true
State.AutoJoinMap = Config.AutoJoinMap == true
State.LobbyMode = tostring(Config.LobbyMode or "Story")
State.LobbyChapter = tostring(Config.LobbyChapter or "Chapter 1")
if type(Config.LobbyModifiers) == "table" then
    for key, value in pairs(Config.LobbyModifiers) do
        if type(key) == "string" and value == true then State.LobbyModifiers[key] = true
        elseif type(key) == "number" and type(value) == "string" then State.LobbyModifiers[value] = true end
    end
end
State.AutoBackLobby = Config.AutoBackLobby == true
State.MatchesBeforeLobby = math.max(1, math.floor(tonumber(Config.MatchesBeforeLobby) or 3))
State.MatchesCompleted = math.max(0, math.floor(tonumber(Config.MatchesCompleted) or 0))
State.LastCountedJobId = tostring(Config.LastCountedJobId or "")
State.PendingLobbyReturn = Config.PendingLobbyReturn == true
State.WebhookEnabled = Config.WebhookEnabled == true
State.WebhookURL = tostring(Config.WebhookURL or "")
State.WebhookMatchEnd = Config.WebhookMatchEnd ~= false
State.PlaybackEnabled = Config.PlaybackEnabled == true
State.Speed = math.clamp(tonumber(Config.Speed) or 1, 1, 6)
State.PlaybackMode = table.find({ "Hybrid", "Time", "Money" }, Config.PlaybackMode) and Config.PlaybackMode or "Hybrid"
State.ProfileName = SanitizeName(Config.SelectedProfile or "")

local saveQueued = false
local function SaveConfig()
    if not HasFilesystem then return end
    local payload = {
        AutoReplay = State.AutoReplay, AutoReady = State.AutoReady, AutoSkip = State.AutoSkip,
        AutoSpeed = State.AutoSpeed, SpeedScaleDelay = State.SpeedScaleDelay,
        MovingAround = State.MovingAround, AutoJoinMap = State.AutoJoinMap,
        LobbyMode = State.LobbyMode, LobbyChapter = State.LobbyChapter,
        LobbyModifiers = State.LobbyModifiers, AutoBackLobby = State.AutoBackLobby,
        MatchesBeforeLobby = State.MatchesBeforeLobby, MatchesCompleted = State.MatchesCompleted,
        LastCountedJobId = State.LastCountedJobId, PendingLobbyReturn = State.PendingLobbyReturn,
        WebhookEnabled = State.WebhookEnabled, WebhookURL = State.WebhookURL,
        WebhookMatchEnd = State.WebhookMatchEnd, PlaybackEnabled = State.PlaybackEnabled,
        Speed = State.Speed, PlaybackMode = State.PlaybackMode,
        SelectedProfile = State.ProfileName, NewProfileName = Config.NewProfileName or "",
    }
    pcall(function() writefile(ConfigFile, HttpService:JSONEncode(payload)) end)
end

local function QueueSave()
    if saveQueued then return end
    saveQueued = true
    task.delay(0.25, function()
        saveQueued = false
        SaveConfig()
    end)
end
Gui.QueueSave = QueueSave
Gui.SaveConfigNow = SaveConfig

if State.PendingLobbyReturn then
    if game.PlaceId == LobbyPlaceId then
        -- Мы уже в лобби, сбрасываем флаг
        State.PendingLobbyReturn = false
        State.MatchesCompleted = 0
        State.LastCountedJobId = ""
        SaveConfig()
    else
        -- Мы в матче, но флаг остался с прошлого раза. Проверяем, есть ли кнопка возврата
        task.delay(3, function()
            if State.Running and State.PendingLobbyReturn then
                -- Если матч уже закончился, пробуем нажать Return to Lobby
                if IsGameEnded() then
                    local triggered, buttonMessage = TriggerBackLobbyButton()
                    if not triggered then
                        pcall(function() TeleportService:Teleport(LobbyPlaceId, LocalPlayer) end)
                    end
                else
                    -- Мы не в конце матча, значит флаг устарел. Сбрасываем.
                    State.PendingLobbyReturn = false
                    State.MatchesCompleted = 0
                    State.LastCountedJobId = ""
                    SaveConfig()
                end
            end
        end)
    end
end

local LobbyTab = Window:Tab({ Title = "Lobby", Icon = "house" })
local MacrosTab = Window:Tab({ Title = "Macros", Icon = "clapperboard" })
local PlayerTab = Window:Tab({ Title = "Player Actions", Icon = "user" })
local MiscTab = Window:Tab({ Title = "Misc", Icon = "settings" })
local WebhookTab = Window:Tab({ Title = "Webhook", Icon = "webhook" })
local Chapter9Tab = Window:Tab({ Title = "Chapter 9", Icon = "zap" })

-- LOBBY TAB
LobbyTab:Section({ Title = "Lobby Automation", Desc = "Ready and replay controls" })

local ModeChapters = {
    Story = { "Chapter 1", "Chapter 1.5", "Chapter 2", "Chapter 3", "Chapter 4", "Chapter 5",
        "Chapter 6", "Chapter 7", "Chapter 8", "Chapter 9" },
    Multiverse = { "Multiverse Chapter 1", "Multiverse Chapter 2", "Multiverse Chapter 3" },
    Nightmare = {},
    Event = { "Partner Takeover", "Skibi Trials" },
    Versus = { "Versus 1v1", "Versus 2v2", "Versus 3v3", "Versus 4v4" },
    Endless = { "Normal", "Roguelite" },
    Episodes = { "Episode 79", "A Fight From the Past", "Civil War", "Land Of Creation",
        "The Final Showdown", "The Last Base" },
    Raid = { "WorldRaid" },
}

local function RefreshNightmareMaps()
    local servers = ReplicatedStorage:FindFirstChild("SERVERS")
    if not servers then return end
    local keywords = { "void", "corruption", "detection", "final showdown", "last base",
        "civil war", "episode 79", "humble beginnings", "land of creation", "rise of" }
    local nightmare = {}
    for _, entry in ipairs(servers:GetChildren()) do
        local lower = entry.Name:lower()
        for _, kw in ipairs(keywords) do
            if lower:find(kw, 1, true) then
                table.insert(nightmare, entry.Name)
                break
            end
        end
    end
    if #nightmare > 0 then
        table.sort(nightmare)
        ModeChapters.Nightmare = nightmare
    end
end
RefreshNightmareMaps()

local LobbyModifierIds = {
    "LBRUN", "BPXP", "NormalRegen", "GodlyRegen", "WeakerEnemies", "WayWeakerEnemies",
    "StrongerEnemies", "WayStrongerEnemies", "GodlyEnemies", "LessEnemies", "DoubleEnemies",
    "AcceleratingEnemies", "DeceleratingEnemies", "RandomSpeed", "RandomHP", "AllHidden",
    "NoHidden", "AllAir", "NoAir", "Ambushed", "AggressiveFoes", "AdvancedForces",
    "Deflection", "TowerNerf", "TowerNerf2", "ThreePlacement", "TenPlacement",
    "OnePlacement", "InfinitePlacement", "DoubleWaveMoney", "LessWaveMoney",
    "MoreDamageMoney", "LessDamageMoney", "MarketLock", "BudgetOptimization",
    "MassiveTowers", "PositionShift", "SmallWar", "ToiletSpawner", "RandomLoadout",
    "Freeze", "InfiniteHP", "InfiniteMoney", "SandboxMap",
}
local LobbyModifierSet, LobbyModifierDisplayToId, LobbyModifierIdToDisplay = {}, {}, {}
local LobbyModifierValues = {}
local LobbyModifierSpecialNames = { LBRUN = "Leaderboard Run", BPXP = "Battlepass XP" }

local function HumanizeModifierId(modifierId)
    local specialName = LobbyModifierSpecialNames[modifierId]
    if specialName then return specialName end
    return modifierId:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
end

for _, modifierId in ipairs(LobbyModifierIds) do
    LobbyModifierSet[modifierId] = true
    local displayName = string.format("%s [%s]", HumanizeModifierId(modifierId), modifierId)
    LobbyModifierDisplayToId[displayName] = modifierId
    LobbyModifierIdToDisplay[modifierId] = displayName
    table.insert(LobbyModifierValues, displayName)
end

local function NormalizeModifierSelection(value)
    local selected = {}
    if type(value) ~= "table" then return selected end
    for key, item in pairs(value) do
        local modifierName
        if type(key) == "string" and item == true then modifierName = key
        elseif type(key) == "number" and type(item) == "string" then modifierName = item end
        local modifierId = modifierName and (LobbyModifierDisplayToId[modifierName] or modifierName)
        if modifierId and LobbyModifierSet[modifierId] then selected[modifierId] = true end
    end
    return selected
end
State.LobbyModifiers = NormalizeModifierSelection(State.LobbyModifiers)

local function ModifierSelectionForDropdown(selection)
    local values = {}
    for _, modifierId in ipairs(LobbyModifierIds) do
        if selection[modifierId] == true then table.insert(values, LobbyModifierIdToDisplay[modifierId]) end
    end
    return values
end

local function ApplyLobbyModifiers()
    local selected = {}
    for _, modifierName in ipairs(LobbyModifierIds) do
        if State.LobbyModifiers[modifierName] == true then table.insert(selected, modifierName) end
    end
    if #selected == 0 then return true end
    RefreshGameObjects()
    if not Remotes.ModifierState or not Remotes.ModifierState:IsA("RemoteEvent") then
        return false, "ReplicatedStorage.ModifierState was not found"
    end
    SetStatus("Auto Join", string.format("Applying %d modifier(s)", #selected))
    for _, modifierName in ipairs(selected) do
        local ok, message = pcall(function() Remotes.ModifierState:FireServer(modifierName, true) end)
        if not ok then return false, modifierName .. ": " .. tostring(message) end
        task.wait(0.05)
    end
    return true
end

local function GetModeChapters(mode)
    if mode ~= "All" then return table.clone(ModeChapters[mode] or {}) end
    local result = {}
    for _, chapters in pairs(ModeChapters) do
        for _, chapter in ipairs(chapters) do
            if not table.find(result, chapter) then table.insert(result, chapter) end
        end
    end
    local replicatedServers = ReplicatedStorage:FindFirstChild("SERVERS")
    if replicatedServers then
        for _, entry in ipairs(replicatedServers:GetChildren()) do
            if not table.find(result, entry.Name) then table.insert(result, entry.Name) end
        end
    end
    table.sort(result)
    return result
end

if not ModeChapters[State.LobbyMode] and State.LobbyMode ~= "All" then State.LobbyMode = "Story" end
local initialChapters = GetModeChapters(State.LobbyMode)
if not table.find(initialChapters, State.LobbyChapter) then
    State.LobbyChapter = initialChapters[1] or "Chapter 1"
end

local chapterDropdown
LobbyTab:Dropdown({
    Title = "Mode",
    Values = { "Story", "Multiverse", "Nightmare", "Event", "Versus", "Endless", "Episodes", "Raid", "All" },
    Value = State.LobbyMode, Multi = false,
    Callback = function(value)
        State.LobbyMode = value
        local chapters = GetModeChapters(value)
        if not table.find(chapters, State.LobbyChapter) then State.LobbyChapter = chapters[1] or "" end
        if chapterDropdown then
            pcall(function() chapterDropdown:Refresh(chapters) end)
            pcall(function() chapterDropdown:Select(State.LobbyChapter) end)
        end
        State.JoinRequested = false
        QueueSave()
    end,
})

chapterDropdown = LobbyTab:Dropdown({
    Title = "Chapter", Values = initialChapters, Value = State.LobbyChapter, Multi = false,
    Callback = function(value)
        State.LobbyChapter = value
        State.JoinRequested = false
        QueueSave()
    end,
})

LobbyTab:Toggle({
    Title = "Auto Join Map", Value = State.AutoJoinMap,
    Callback = function(value)
        State.AutoJoinMap = value == true
        State.JoinRequested = false
        QueueSave()
    end,
})

LobbyTab:Dropdown({
    Title = "Modifiers", Values = LobbyModifierValues,
    Value = ModifierSelectionForDropdown(State.LobbyModifiers),
    Multi = true, AllowNone = true, SearchBarEnabled = true,
    Callback = function(value)
        State.LobbyModifiers = NormalizeModifierSelection(value)
        State.JoinRequested = false
        QueueSave()
    end,
})

LobbyTab:Section({ Title = "Match Cycle", Desc = "Persisted across replay teleports" })
local matchCounterParagraph = WrapParagraph(LobbyTab:Paragraph({ Title = "Match Counter", Desc = "Loading..." }))
local function UpdateMatchCounter()
    matchCounterParagraph:SetDesc(string.format("%d/%d completed | %s",
        State.MatchesCompleted, State.MatchesBeforeLobby,
        State.PendingLobbyReturn and "returning to lobby" or "running"))
end
Gui.UpdateMatchCounter = UpdateMatchCounter
UpdateMatchCounter()

LobbyTab:Toggle({
    Title = "Auto Back Lobby After X Matches", Value = State.AutoBackLobby,
    Callback = function(value)
        State.AutoBackLobby = value == true
        QueueSave()
        UpdateMatchCounter()
    end,
})

LobbyTab:Input({
    Title = "Matches Before Lobby", Placeholder = "3", Value = tostring(State.MatchesBeforeLobby),
    Callback = function(value)
        local amount = tonumber(tostring(value):match("%d+"))
        if amount then
            State.MatchesBeforeLobby = math.max(1, math.floor(amount))
            QueueSave()
            UpdateMatchCounter()
        end
    end,
})

LobbyTab:Button({
    Title = "Reset Match Counter", Icon = "rotate-ccw",
    Callback = function()
        State.MatchesCompleted = 0
        State.LastCountedJobId = ""
        State.PendingLobbyReturn = false
        QueueSave()
        UpdateMatchCounter()
    end,
})

LobbyTab:Toggle({
    Title = "Auto Replay", Value = State.AutoReplay,
    Callback = function(value)
        State.AutoReplay = value == true
        QueueSave()
    end,
})

LobbyTab:Toggle({
    Title = "Auto Ready Up", Value = State.AutoReady,
    Callback = function(value)
        State.AutoReady = value == true
        if State.AutoReady then pcall(function() Remotes.Ready:FireServer(true) end) end
        QueueSave()
    end,
})

task.spawn(function()
    while State.Running do
        if game.PlaceId == LobbyPlaceId and State.AutoJoinMap and not State.JoinRequested and State.LobbyChapter ~= "" then
            RefreshGameObjects()
            if Remotes.CreateServer then
                State.JoinRequested = true
                SetStatus("Auto Join", "Creating " .. State.LobbyChapter)
                task.spawn(function()
                    local ok, result = pcall(function() return Remotes.CreateServer:InvokeServer(State.LobbyChapter) end)
                    if not ok then
                        State.JoinRequested = false
                        Notify("Auto Join failed", tostring(result))
                        return
                    end
                    local modifiersApplied, modifierError = ApplyLobbyModifiers()
                    if not modifiersApplied then
                        State.JoinRequested = false
                        Notify("Auto Join modifiers failed", tostring(modifierError))
                        return
                    end
                    SetStatus("Auto Join", "Starting " .. State.LobbyChapter)
                    local startRemote = Remotes.StartServer
                    for _ = 1, 20 do
                        if startRemote then break end
                        task.wait(0.25)
                        RefreshGameObjects()
                        startRemote = Remotes.StartServer
                    end
                    if not startRemote then
                        State.JoinRequested = false
                        Notify("Auto Join failed", "Events.start was not found")
                        return
                    end
                    local started, startError = pcall(function() startRemote:FireServer(false) end)
                    if not started then
                        State.JoinRequested = false
                        Notify("Auto Join failed", tostring(startError))
                    end
                end)
            end
        end
        task.wait(1)
    end
end)

-- CHAPTER 9 TAB
Chapter9Tab:Section({ Title = "Chapter 9 Mode", Desc = "Wave 1 = x1. Wave 2+ = x4 (set once)" })

Chapter9Tab:Toggle({
    Title = "Enable Chapter 9 Mode",
    Value = false,
    Callback = function(value)
        State.Chapter9Mode = value == true
        State.Chapter9SpeedSet = false
        if value then
            Notify("Chapter 9", "Mode ON — x1 on wave 1, x4 from wave 2")
        else
            Notify("Chapter 9", "Mode OFF")
        end
    end,
})

Chapter9Tab:Paragraph({
    Title = "How it works",
    Desc = "Wave 1: speed x1, macro runs normally. Wave 2+: speed x4 (set once). New match resets the cycle.",
})

-- WEBHOOK TAB
WebhookTab:Section({ Title = "Discord Webhook", Desc = "Optional match notifications" })

WebhookTab:Input({
    Title = "Webhook URL", Placeholder = "https://discord.com/api/webhooks/...", Value = State.WebhookURL,
    Callback = function(value)
        State.WebhookURL = tostring(value or "")
        QueueSave()
    end,
})

WebhookTab:Toggle({
    Title = "Enable Webhook", Value = State.WebhookEnabled,
    Callback = function(value)
        State.WebhookEnabled = value == true
        QueueSave()
    end,
})

WebhookTab:Toggle({
    Title = "Notify On Match End", Value = State.WebhookMatchEnd,
    Callback = function(value)
        State.WebhookMatchEnd = value == true
        QueueSave()
    end,
})

WebhookTab:Button({
    Title = "Send Test Webhook", Icon = "send",
    Callback = function()
        local ok, message = SendDiscordWebhook("Webhook Test", "Skibidi Defense Hub webhook is working.", 5763719)
        if ok then Notify("Webhook", "Test message sent")
        else Notify("Webhook failed", tostring(message)) end
    end,
})

-- MACROS TAB
MacrosTab:Section({ Title = "Macro State", Desc = "Passive recorder and verified playback" })
Gui.Status = WrapParagraph(MacrosTab:Paragraph({ Title = "State: Idle", Desc = "Waiting" }))
Gui.Runtime = WrapParagraph(MacrosTab:Paragraph({ Title = "Live match", Desc = "Reading game state..." }))
Gui.ActionSummary = WrapParagraph(MacrosTab:Paragraph({ Title = "Recorded actions: 0", Desc = "No actions loaded" }))

local newProfileName = Config.NewProfileName or ""
local profileInput = MacrosTab:Input({
    Title = "Create Macro", Placeholder = "example: map1_solo", Value = newProfileName,
    Callback = function(value)
        newProfileName = SanitizeName(value)
        Config.NewProfileName = newProfileName
        QueueSave()
    end,
})

local profileValues = ListProfiles()
if #profileValues == 0 then profileValues = { "(none)" } end
local selectedDefault = State.ProfileName ~= "" and State.ProfileName or profileValues[1]
local profileDropdown

local function RefreshProfiles(selectName)
    local values = ListProfiles()
    if #values == 0 then values = { "(none)" } end
    pcall(function() profileDropdown:Refresh(values) end)
    if selectName and selectName ~= "" then pcall(function() profileDropdown:Select(selectName) end) end
end
Gui.RefreshProfiles = RefreshProfiles

local function StartEnabledPlayback()
    if not State.PlaybackEnabled or State.Playing or State.Recording or #State.Actions == 0 then return end
    local ok, message = StartPlayback()
    if ok then State.AutoPlaybackStarted = true
    else SetStatus("Auto playback", tostring(message)) end
end
Gui.StartEnabledPlayback = StartEnabledPlayback

MacrosTab:Button({
    Title = "Create New Macro", Icon = "file-plus",
    Callback = function()
        local name = SanitizeName(newProfileName)
        if name == "" then Notify("Create Macro", "Enter a macro name first") return end
        if HasFilesystem and isfile(ProfilePath(name)) then Notify("Create Macro", "That macro already exists") return end
        local previousActions, previousName = State.Actions, State.ProfileName
        State.Actions, State.ProfileName = {}, name
        local ok, message = SaveProfile(name)
        if not ok then
            State.Actions, State.ProfileName = previousActions, previousName
            Notify("Create failed", tostring(message))
            return
        end
        RefreshProfiles(name)
        RefreshActionList()
        SetStatus("Created", name .. " is ready to record")
        QueueSave()
    end,
})

profileDropdown = MacrosTab:Dropdown({
    Title = "Select Macro", Values = profileValues, Value = selectedDefault, Multi = false,
    Callback = function(value)
        if value == "(none)" then return end
        local ok, message = LoadProfile(value)
        if ok then
            RefreshActionList()
            SetStatus("Loaded", string.format("%s (%d actions)", State.ProfileName, #State.Actions))
            QueueSave()
            task.defer(StartEnabledPlayback)
        else
            SetStatus("Load failed", tostring(message))
        end
    end,
})

MacrosTab:Dropdown({
    Title = "Playback Mode", Values = { "Hybrid", "Time", "Money" },
    Value = State.PlaybackMode, Multi = false,
    Callback = function(value)
        State.PlaybackMode = value
        QueueSave()
    end,
})

local changingToggle = false
local recordToggle, playbackToggle
local function SetWindToggle(element, value)
    if not element then return end
    changingToggle = true
    pcall(function() element:Set(value) end)
    changingToggle = false
end
Gui.SetRecordToggle = function(value) SetWindToggle(recordToggle, value) end
Gui.SetPlaybackToggle = function(value) SetWindToggle(playbackToggle, value) end

recordToggle = MacrosTab:Toggle({
    Title = "Record", Value = false,
    Callback = function(value)
        if changingToggle then return end
        if value then
            if State.PlaybackEnabled then
                SetWindToggle(playbackToggle, false)
                State.PlaybackEnabled = false
                QueueSave()
            end
            if State.Playing then StopPlayback("Stopped to begin recording") end
            local name = State.ProfileName ~= "" and State.ProfileName or newProfileName
            local ok, message = StartRecording(name)
            if not ok then
                SetWindToggle(recordToggle, false)
                Notify("Cannot record", tostring(message))
            end
        elseif State.Recording then
            local ok, message = StopRecording(true)
            if ok then
                RefreshProfiles(State.ProfileName)
                QueueSave()
            else
                Notify("Cannot save", tostring(message))
            end
        end
    end,
})
Gui.RecordToggle = recordToggle

playbackToggle = MacrosTab:Toggle({
    Title = "Playback", Value = State.PlaybackEnabled,
    Callback = function(value)
        if changingToggle then return end
        State.PlaybackEnabled = value == true
        QueueSave()
        if value then
            if State.Recording then
                SetWindToggle(recordToggle, false)
                StopRecording(true)
            end
            local ok, message = StartPlayback()
            if not ok then SetStatus("Playback armed", tostring(message)) end
        elseif State.Playing then
            StopPlayback("Stopped by user")
        end
    end,
})
Gui.PlayToggle = playbackToggle

-- PLAYER ACTIONS TAB
PlayerTab:Section({ Title = "Player Action State", Desc = "Passive recorder for your own actions" })

local playerStatus = WrapParagraph(PlayerTab:Paragraph({ Title = "State: Idle", Desc = "Waiting" }))
local playerRuntime = WrapParagraph(PlayerTab:Paragraph({ Title = "Live match", Desc = "Reading game state..." }))
local playerActionSummary = WrapParagraph(PlayerTab:Paragraph({ Title = "Recorded actions: 0", Desc = "No actions loaded" }))

Gui.PlayerStatus = playerStatus
Gui.PlayerRuntime = playerRuntime
Gui.PlayerActionSummary = playerActionSummary

local function RefreshPlayerActionList()
    if not playerActionSummary then return end
    local lines = {}
    local first = math.max(1, #State.PlayerActions - 7)
    for index = first, #State.PlayerActions do
        local action = State.PlayerActions[index]
        local subject = action.Unit or action.Handle or ""
        if action.Type == "Speed" then subject = "x" .. tostring(action.Speed or 1)
        elseif action.Type == "Ability" then subject = "Ability #" .. tostring(action.AbilityIndex or 1) end
        table.insert(lines, string.format("%02d | W%s | %s | %s", index, action.Wave or 0, action.Type or "?", subject))
    end
    playerActionSummary:SetTitle(string.format("Recorded actions: %d", #State.PlayerActions))
    playerActionSummary:SetDesc(#lines > 0 and table.concat(lines, "\n") or "No actions loaded")
end

local originalStartPlayerRecording = StartPlayerRecording
StartPlayerRecording = function(profileName)
    local ok, msg = originalStartPlayerRecording(profileName)
    if ok then
        RefreshPlayerActionList()
        playerStatus:SetTitle("State: Recording")
        playerStatus:SetDesc("Recording your actions...")
    end
    return ok, msg
end

local originalStopPlayerRecording = StopPlayerRecording
StopPlayerRecording = function(save)
    local ok, msg = originalStopPlayerRecording(save)
    if ok then
        RefreshPlayerActionList()
        playerStatus:SetTitle("State: Idle")
        playerStatus:SetDesc(save and ("Saved " .. State.PlayerRecordingProfileName) or "Stopped without saving")
    end
    return ok, msg
end

local newPlayerProfileName = ""
PlayerTab:Input({
    Title = "Create Player Macro", Placeholder = "example: my_player_run", Value = "",
    Callback = function(value) newPlayerProfileName = SanitizeName(value) end,
})

local playerProfileValues = ListPlayerProfiles()
if #playerProfileValues == 0 then playerProfileValues = { "(none)" } end
local selectedPlayerDefault = playerProfileValues[1]
local playerProfileDropdown

local function RefreshPlayerProfiles(selectName)
    local values = ListPlayerProfiles()
    if #values == 0 then values = { "(none)" } end
    pcall(function() playerProfileDropdown:Refresh(values) end)
    if selectName and selectName ~= "" then pcall(function() playerProfileDropdown:Select(selectName) end) end
end
Gui.RefreshPlayerProfiles = RefreshPlayerProfiles

PlayerTab:Button({
    Title = "Create New Player Macro", Icon = "file-plus",
    Callback = function()
        local name = SanitizeName(newPlayerProfileName)
        if name == "" then Notify("Create Player Macro", "Enter a macro name first") return end
        local payload = { Version = 1, Name = name, Actions = {} }
        writefile(MacroFolder .. "/" .. name .. "_player.json", HttpService:JSONEncode(payload))
        RefreshPlayerProfiles(name)
        Notify("Create Player Macro", name .. " is ready to record")
    end,
})

playerProfileDropdown = PlayerTab:Dropdown({
    Title = "Select Player Macro", Values = playerProfileValues, Value = selectedPlayerDefault, Multi = false,
    Callback = function(value)
        if value == "(none)" then return end
        local path = MacroFolder .. "/" .. value .. "_player.json"
        if isfile(path) then
            local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
            if ok and type(decoded) == "table" and type(decoded.Actions) == "table" then
                State.PlayerActions = decoded.Actions
                State.PlayerRecordingProfileName = value
                RefreshPlayerActionList()
                playerStatus:SetTitle("State: Loaded")
                playerStatus:SetDesc(value .. " (" .. #decoded.Actions .. " actions)")
            end
        end
    end,
})

PlayerTab:Dropdown({
    Title = "Playback Mode", Values = { "Hybrid", "Time", "Money" },
    Value = State.PlaybackMode, Multi = false,
    Callback = function(value)
        State.PlaybackMode = value
        QueueSave()
    end,
})

local changingPlayerToggle = false
local playerRecordToggle
local function SetPlayerToggle(element, value)
    if not element then return end
    changingPlayerToggle = true
    pcall(function() element:Set(value) end)
    changingPlayerToggle = false
end

playerRecordToggle = PlayerTab:Toggle({
    Title = "Record", Value = false,
    Callback = function(value)
        if changingPlayerToggle then return end
        if value then
            if State.Playing then StopPlayback("Stopped to begin recording") end
            local name = State.PlayerRecordingProfileName ~= "" and State.PlayerRecordingProfileName or newPlayerProfileName
            local ok, message = StartPlayerRecording(name)
            if not ok then
                SetPlayerToggle(playerRecordToggle, false)
                Notify("Cannot record", tostring(message))
            end
        elseif State.PlayerRecording then
            local ok, message = StopPlayerRecording(true)
            if ok then
                RefreshPlayerProfiles(State.PlayerRecordingProfileName)
                RefreshPlayerActionList()
            else
                Notify("Cannot save", tostring(message))
            end
        end
    end,
})
Gui.PlayerRecordToggle = playerRecordToggle

local playerPlaybackToggle
playerPlaybackToggle = PlayerTab:Toggle({
    Title = "Playback", Value = false,
    Callback = function(value)
        if changingPlayerToggle then return end
        if value then
            if State.PlayerRecording then
                SetPlayerToggle(playerRecordToggle, false)
                StopPlayerRecording(true)
            end
            local ok, message = PlayPlayerRecording(playerProfileDropdown.Value)
            if not ok then
                SetPlayerToggle(playerPlaybackToggle, false)
                Notify("Cannot play", tostring(message))
            else
                playerStatus:SetTitle("State: Playing")
                playerStatus:SetDesc("Playing " .. playerProfileDropdown.Value)
            end
        elseif State.Playing then
            StopPlayback("Stopped by user")
            playerStatus:SetTitle("State: Idle")
            playerStatus:SetDesc("Stopped by user")
        end
    end,
})
Gui.PlayerPlaybackToggle = playerPlaybackToggle

PlayerTab:Section({ Title = "Quick Actions", Desc = "One-tap helpers" })

PlayerTab:Button({
    Title = "Upgrade All Now", Icon = "arrow-up",
    Callback = function()
        local ok, msg = PlayUpgradeAll()
        if ok then Notify("Upgrade All", "All towers upgraded")
        else Notify("Upgrade All failed", tostring(msg)) end
    end,
})

task.spawn(function()
    while State.Running do
        if playerRuntime then
            playerRuntime:SetDesc(string.format("Wave %d | Money %d | %s | Base %s | Speed x%d",
                GetWave(), GetMoney(), GetUnitCountText(), GetBaseHealthText(), State.Speed))
        end
        task.wait(0.5)
    end
end)

-- MISC TAB
MiscTab:Section({ Title = "Wave & Speed", Desc = "Match automation" })
MiscTab:Toggle({
    Title = "Auto Skip Waves", Value = State.AutoSkip,
    Callback = function(value)
        State.AutoSkip = value == true
        QueueSave()
    end,
})
MiscTab:Toggle({
    Title = "Auto Speed Scale", Value = State.AutoSpeed,
    Callback = function(value)
        State.AutoSpeed = value == true
        QueueSave()
    end,
})
MiscTab:Dropdown({
    Title = "Speed Scale", Values = { "x1", "x2", "x3", "x4", "x5", "x6" },
    Value = "x" .. tostring(State.Speed), Multi = false,
    Callback = function(value)
        local speed = tonumber(tostring(value):match("%d+")) or 1
        State.Speed = math.clamp(speed, 1, 6)
        QueueSave()
    end,
})
MiscTab:Slider({
    Title = "Speed Scale Delay", Desc = "Seconds between repeated speed requests",
    Step = 0.5, Value = { Min = 0.5, Max = 10, Default = State.SpeedScaleDelay },
    Callback = function(value)
        State.SpeedScaleDelay = math.clamp(tonumber(value) or 1, 0.5, 10)
        QueueSave()
    end,
})

MiscTab:Section({ Title = "Movement", Desc = "Character movement" })
MiscTab:Toggle({
    Title = "Moving Around (AntiKick)", Value = State.MovingAround,
    Callback = function(value)
        SetMovingAround(value)
        QueueSave()
    end,
})

if State.MovingAround then
    task.defer(function() SetMovingAround(true) end)
end

if State.ProfileName ~= "" then
    local ok = LoadProfile(State.ProfileName)
    if not ok then State.ProfileName = "" end
end

if State.PlaybackEnabled and #State.Actions > 0 then
    task.spawn(function()
        WaitUntil(function()
            return TowerDataFolder ~= nil and TowersFolder ~= nil and Remotes.Place ~= nil
        end, 60, 0.1)
        if State.PlaybackEnabled and #State.Actions > 0 then
            StartEnabledPlayback()
        end
    end)
end

task.spawn(function()
    while State.Running do
        if Gui.Runtime then
            Gui.Runtime:SetTitle(State.Playing and ("Live match - " .. State.PlaybackMode) or "Live match")
            Gui.Runtime:SetDesc(string.format("Wave %d | Money %d | %s | Base %s | Speed x%d",
                GetWave(), GetMoney(), GetUnitCountText(), GetBaseHealthText(), State.Speed))
        end
        task.wait(0.5)
    end
end)

function Hub.Destroy()
    MovingSession = MovingSession + 1
    StopCharacterMovement()
    State.Running = false
    State.Recording = false
    State.Playing = false
    DisableLegacyAbilityRecorderHook()
    SaveConfig()
    DisconnectAll(State.RecorderConnections)
    DisconnectAll(State.Connections)
    pcall(function() Window:Destroy() end)
    if Environment.SkibidiDefenseHub == Hub then Environment.SkibidiDefenseHub = nil end
end

Hub.State = State
Hub.StartRecording = StartRecording
Hub.StopRecording = StopRecording
Hub.StartPlayback = StartPlayback
Hub.StopPlayback = StopPlayback
Hub.SaveProfile = SaveProfile
Hub.LoadProfile = LoadProfile
Hub.ListProfiles = ListProfiles
Hub.SetSpeed = ApplySpeed
Hub.StartPlayerRecording = StartPlayerRecording
Hub.StopPlayerRecording = StopPlayerRecording
Hub.PlayPlayerRecording = PlayPlayerRecording
Hub.PlayUpgradeAll = PlayUpgradeAll

RefreshActionList()
SetStatus("Idle", State.ProfileName ~= "" and ("Loaded " .. State.ProfileName) or "Create or select a macro")
SaveConfig()
print("Skibidi Defense Hub loaded. Made By oreshechek :3 | RightShift toggles WindUI.")
